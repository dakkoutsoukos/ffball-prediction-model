# P4: season dynamics (master plan P4; pre-registration VL4, VL4a) --------------------------------
# Rest-of-season (ROS) totals at as-of weeks 4/8/12 for fantasy-relevant players, from rolling-origin
# components fitted on earlier seasons: mean if active by horizon bucket, attrition by position x
# level band x bucket, weekly noise from the E20-selected P2 candidate, and a persistent level shock
# L ~ lognormal(-s^2/2, s^2) with s matched by simulation on 2020-2023. Baseline: the same mean with a
# normal spread. X2 (residual persistence) and X26 (ESPN's revision response) are parameter studies.

P4_ASOF <- c(4L, 8L, 12L)
P4_DEV <- 2020:2023
P4_RELEVANT <- c(QB = 24L, RB = 48L, WR = 60L, TE = 24L)
P4_BUCKETS <- c("1", "2-3", "4-7", "8+")
P4_LAST_WEEK <- 16L
P4_SIMS <- 2000L

p4_bucket <- function(h) factor(dplyr::case_when(h == 1 ~ "1", h <= 3 ~ "2-3", h <= 7 ~ "4-7", TRUE ~ "8+"), P4_BUCKETS)

#' Future team-game rows for the relevant players of a season at as-of weeks `w_set`: one row per
#' (player, w, t), t = w+1..16, with L_avg4 at w, the realised points (0 without a row) and activity.
p4_ros_rows <- function(S, w_set = P4_ASOF) {
  purrr::map(w_set, function(w) {
    L <- S$L[, w]
    ok <- which(!is.na(L) & !is.na(S$team_asof[, w]))
    rel <- unlist(lapply(names(P4_RELEVANT), function(p) {
      i <- ok[S$pos[ok] == p]
      utils::head(i[order(-L[i], i)], P4_RELEVANT[[p]])
    }))
    if (!length(rel)) return(NULL)
    team_row <- match(S$team_asof[rel, w], S$teams)
    purrr::map(seq(w + 1L, min(P4_LAST_WEEK, ncol(S$y))), function(tt) {
      plays <- S$plays[cbind(team_row, tt)]
      i <- rel[!is.na(plays) & plays]
      if (!length(i)) return(NULL)
      # vectors first: inside tibble() a recycled column would shadow `tt` (memory gotcha)
      yy <- dplyr::coalesce(S$y[i, tt], 0)
      act <- S$has_row[i, tt] & dplyr::coalesce(S$active[i, tt], FALSE)
      tibble::tibble(season = S$season, w = w, t = tt, h = tt - w, gsis_id = S$ids[i], position = S$pos[i], L = L[i],
                     y = yy, active = act)
    }) |> purrr::list_rbind()
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(bucket = p4_bucket(.data$h), lband = pd_band(.data$L))
}

#' Rolling-origin components from training rows: mean if active (position x bucket OLS on L) and
#' attrition (position x L band x bucket active share, falling back to position x bucket).
p4_fit_components <- function(train) {
  mu <- purrr::map(P2_POSITIONS, function(p) purrr::map(P4_BUCKETS, function(b) {
    d <- train[train$position == p & train$bucket == b & train$active, ]
    co <- if (nrow(d) >= 20) stats::coef(stats::lm(y ~ L, data = d)) else c(0, 1)
    tibble::tibble(position = p, bucket = b, a = unname(co[1]), b = unname(co[2]), n = nrow(d))
  }) |> purrr::list_rbind()) |> purrr::list_rbind()
  att <- dplyr::summarise(train, n = dplyr::n(), A = mean(.data$active), .by = c("position", "lband", "bucket"))
  att_pb <- dplyr::summarise(train, A_pb = mean(.data$active), .by = c("position", "bucket"))
  list(mu = mu, att = att, att_pb = att_pb)
}

#' Mean-if-active and availability for ROS rows from fitted components.
p4_apply_components <- function(rows, comp, min_n = 30L) {
  k <- match(paste(rows$position, rows$bucket), paste(comp$mu$position, comp$mu$bucket))
  rows$mu <- comp$mu$a[k] + comp$mu$b[k] * rows$L
  ka <- match(paste(rows$position, rows$lband, rows$bucket), paste(comp$att$position, comp$att$lband, comp$att$bucket))
  kb <- match(paste(rows$position, rows$bucket), paste(comp$att_pb$position, comp$att_pb$bucket))
  A <- ifelse(!is.na(ka) & comp$att$n[ka] >= min_n, comp$att$A[ka], comp$att_pb$A_pb[kb])
  rows$A <- dplyr::coalesce(A, 1)
  rows
}

#' Per (player, season, w) group: the realised ROS total and the forecast mean.
p4_groups <- function(rows) {
  rows |>
    dplyr::mutate(group = paste(.data$gsis_id, .data$season, .data$w, sep = "_")) |>
    dplyr::summarise(position = dplyr::first(.data$position), L = dplyr::first(.data$L), actual = sum(.data$y),
                     forecast = sum(.data$A * .data$mu), weeks = dplyr::n(), .by = c("group", "gsis_id", "season", "w"))
}

#' Pre-draws without the level shock: B[g, d] = sum over the group's weeks of active x F^-1(u | mu),
#' with weekly noise from quantile rows `q` (99-level grid), plus normals Z for the level shock.
p4_predraw <- function(rows, q, draws = 200L, seed = 1L) {
  gid <- match(paste(rows$gsis_id, rows$season, rows$w, sep = "_"), unique(paste(rows$gsis_id, rows$season, rows$w, sep = "_")))
  G <- max(gid)
  B <- matrix(0, G, draws)
  withr::with_seed(seed, {
    for (d in seq_len(draws)) {
      act <- stats::runif(nrow(rows)) < rows$A
      x <- ifelse(act, sim_qdraw(q, stats::runif(nrow(rows)), P2_TAU), 0)
      B[, d] <- rowsum(x, gid, reorder = TRUE)[, 1]
    }
    Z <- matrix(stats::rnorm(G * draws), G, draws)
  })
  list(B = B, Z = Z, group = unique(paste(rows$gsis_id, rows$season, rows$w, sep = "_")))
}

#' Level-shock scale by simulation matching per position x tertile band of L (VL4/VL4a).
p4_match_sigma <- function(groups, pre, upper = 1.5, tol = 1e-4) {
  g <- groups[match(pre$group, groups$group), ]
  cuts <- dplyr::summarise(g, t1 = stats::quantile(.data$L, 1 / 3), t2 = stats::quantile(.data$L, 2 / 3), .by = "position")
  g$tband <- 1L + (g$L > cuts$t1[match(g$position, cuts$position)]) + (g$L > cuts$t2[match(g$position, cuts$position)])
  sd_sim <- function(s, idx) stats::sd(as.vector(exp(-s^2 / 2 + s * pre$Z[idx, , drop = FALSE]) * pre$B[idx, , drop = FALSE] -
                                                   g$forecast[idx]))
  out <- purrr::map(seq_len(nrow(dplyr::distinct(g, .data$position, .data$tband))), function(k) {
    cell <- dplyr::distinct(g, .data$position, .data$tband)[k, ]
    idx <- which(g$position == cell$position & g$tband == cell$tband)
    obs <- stats::sd(g$actual[idx] - g$forecast[idx])
    f <- function(s) sd_sim(s, idx) - obs
    s <- if (f(0) >= 0) 0 else if (f(upper) < 0) upper else stats::uniroot(f, c(0, upper), tol = tol)$root
    tibble::tibble(position = cell$position, tband = cell$tband, groups = length(idx), sd_observed = obs,
                   sd_sim_at_0 = sd_sim(0, idx), sigma_L = s, capped = s >= upper)
  }) |> purrr::list_rbind()
  list(sigma = dplyr::arrange(out, .data$position, .data$tband), cuts = cuts)
}

#' Tertile band of L for new groups from the matching cutpoints.
p4_tband <- function(position, L, cuts) {
  k <- match(position, cuts$position)
  1L + (L > cuts$t1[k]) + (L > cuts$t2[k])
}

#' ROS distribution draws per group: L x B with the group's sigma_L. Returns quantiles on the 99 grid.
p4_ros_quantiles <- function(groups, pre, sigma, seed = 2L) {
  g <- groups[match(pre$group, groups$group), ]
  s <- sigma$sigma$sigma_L[match(paste(g$position, p4_tband(g$position, g$L, sigma$cuts)),
                                 paste(sigma$sigma$position, sigma$sigma$tband))]
  s[is.na(s)] <- 0
  withr::with_seed(seed, Z <- matrix(stats::rnorm(length(pre$B)), nrow(pre$B)))
  tot <- exp(-s^2 / 2 + s * Z) * pre$B
  list(group = pre$group, q = t(apply(tot, 1, stats::quantile, probs = P2_TAU, type = 7, names = FALSE)))
}

#' VE1-normal baseline quantiles: the forecast mean with a normal spread at the training residual SD
#' of ROS totals by position x w.
p4_normal_quantiles <- function(groups, sd_tab) {
  sd <- sd_tab$sd[match(paste(groups$position, groups$w), paste(sd_tab$position, sd_tab$w))]
  outer(groups$forecast, rep(1, length(P2_TAU))) + outer(sd, stats::qnorm(P2_TAU))
}

# ---- X2 and X26 parameter studies -------------------------------------------------------------------
#' X2: lag-k autocorrelation of residuals (y - base) within player-season on active projected rows.
p4_x2_autocorr <- function(frame, lags = 1:4) {
  d <- frame[frame$pop_espn & frame$active & frame$position %in% P2_POSITIONS & !is.na(frame$base), ]
  d <- d[order(d$gsis_id, d$season, d$week), ]
  d$r <- d$actual - d$base
  d$band <- pd_band(d$base)
  purrr::map(lags, function(k) {
    nxt <- dplyr::lead(d$r, k)
    same <- dplyr::lead(d$gsis_id, k) == d$gsis_id & dplyr::lead(d$season, k) == d$season
    ok <- !is.na(nxt) & same
    tibble::tibble(position = d$position[ok], band = d$band[ok], r = d$r[ok], r_next = nxt[ok], lag = k)
  }) |>
    purrr::list_rbind() |>
    dplyr::summarise(n = dplyr::n(), autocorr = stats::cor(.data$r, .data$r_next), .by = c("lag", "position")) |>
    dplyr::arrange(.data$position, .data$lag)
}

#' X2: intraclass correlation of residuals by position (player-season random intercept, mgcv REML).
p4_x2_icc <- function(frame) {
  d <- frame[frame$pop_espn & frame$active & frame$position %in% P2_POSITIONS & !is.na(frame$base), ]
  d$r <- d$actual - d$base
  d$ps <- factor(paste(d$gsis_id, d$season))
  purrr::map(P2_POSITIONS, function(p) {
    x <- d[d$position == p, ]
    fit <- mgcv::gam(r ~ s(ps, bs = "re"), data = droplevels(x), method = "REML")
    vc <- mgcv::gam.vcomp(fit, rescale = FALSE)
    v_re <- unname(vc[1, 1])^2
    v_res <- fit$sig2
    tibble::tibble(position = p, n = nrow(x), sd_player_season = sqrt(v_re), sd_resid = sqrt(v_res),
                   icc = v_re / (v_re + v_res))
  }) |> purrr::list_rbind()
}

#' X26: ESPN's revision response, proj(t+1) - proj(t) on the residual at t (both weeks projected,
#' week t active), by position.
p4_x26_revision <- function(frame) {
  d <- frame[frame$pop_espn & frame$position %in% P2_POSITIONS & !is.na(frame$base), ]
  d <- d[order(d$gsis_id, d$season, d$week), ]
  nxt_p <- dplyr::lead(d$espn_proj)
  same <- dplyr::lead(d$gsis_id) == d$gsis_id & dplyr::lead(d$season) == d$season & dplyr::lead(d$week) == d$week + 1L
  ok <- !is.na(nxt_p) & same & d$active
  x <- tibble::tibble(position = d$position[ok], r = d$actual[ok] - d$base[ok], dp = nxt_p[ok] - d$espn_proj[ok])
  dplyr::summarise(x, n = dplyr::n(), slope = unname(stats::coef(stats::lm(dp ~ r))[2]),
                   intercept = unname(stats::coef(stats::lm(dp ~ r))[1]), .by = "position") |>
    dplyr::arrange(match(.data$position, P2_POSITIONS))
}

#' Weekly-noise quantiles (99-level grid) for ROS rows, from the E20-selected P2 candidate fitted on
#' `train` (P2 active rows of earlier seasons), with base = mu. C2's covariates take the as-of values
#' of VL4 (status none, implied total 22, spread 0; TD share and volatility as of week w, else the
#' position's training mean).
p4_noise_quantiles <- function(rows, train, candidate, asof = NULL) {
  nd <- tibble::tibble(position = rows$position, base = rows$mu)
  switch(candidate,
    C0 = p2_quantiles_c0(p2_fit_c0(train), nd),
    C1 = p2_quantiles_c1(p2_fit_c1(train), nd),
    C2 = {
      means <- dplyr::summarise(train, td = mean(.data$td_share), vol = mean(.data$vol_shrunk, na.rm = TRUE), .by = "position")
      k <- if (is.null(asof)) rep(NA_integer_, nrow(rows)) else
        match(paste(rows$gsis_id, rows$season, rows$w), paste(asof$gsis_id, asof$season, asof$week))
      m <- match(rows$position, means$position)
      nd$status <- factor("none", c("none", "listed", "QD"))
      nd$td_share <- dplyr::coalesce(if (is.null(asof)) NA_real_ else asof$td_share[k], means$td[m])
      nd$vol_shrunk <- dplyr::coalesce(if (is.null(asof)) NA_real_ else asof$vol_shrunk[k], means$vol[m])
      nd$implied_total <- 22
      nd$spread <- 0
      p2_quantiles_c2(p2_fit_c2(train), nd)
    },
    cli::cli_abort("P4 noise for candidate {.val {candidate}} is not implemented."))
}

#' Development ROS rows with rolling-origin components for seasons 2020-2023 (each fit on earlier
#' seasons), noise quantiles, and the groups.
p4_dev_rows <- function(player_week_all, team_games, p2_frame_all, candidate, seasons = P4_DEV,
                        register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", seasons, "development", register)
  all_rows <- purrr::map(c(P2_WARMUP, seasons), function(s) {
    S <- lab_season_data(player_week_all, team_games, s)
    dplyr::bind_rows(p4_ros_rows(S, P4_ASOF), p4_ros_rows(S, setdiff(1:15, P4_ASOF)) |> dplyr::mutate(fit_only = TRUE))
  }) |> purrr::list_rbind()
  all_rows$fit_only <- dplyr::coalesce(all_rows$fit_only, FALSE)
  purrr::map(seasons, function(s) {
    comp <- p4_fit_components(all_rows[all_rows$season < s, ])
    rows <- p4_apply_components(all_rows[all_rows$season == s & !all_rows$fit_only, ], comp)
    train <- p2_frame_all[p2_frame_all$season < s & p2_frame_all$active, ]
    rows$q_index <- seq_len(nrow(rows))
    list(rows = rows, q = p4_noise_quantiles(rows, train, candidate, asof = p2_frame_all),
         train_groups = p4_groups(p4_apply_components(all_rows[all_rows$season < s & !all_rows$fit_only &
                                                                 all_rows$season > P2_WARMUP - 1, ], comp)))
  })
}

#' Development evaluation (descriptive; sigma_L is matched in sample on 2020-2023): match sigma_L on
#' the pooled development groups, then score P4's ROS distribution and VE1-normal by CRPS and coverage.
p4_dev_evaluate <- function(dev, match_draws = 200L, sims = P4_SIMS, seed = 4L) {
  groups <- purrr::map(dev, function(x) p4_groups(x$rows)) |> purrr::list_rbind()
  pre_m <- purrr::map(seq_along(dev), function(i) p4_predraw(dev[[i]]$rows, dev[[i]]$q, match_draws, seed + i))
  pre_all <- list(B = do.call(rbind, lapply(pre_m, `[[`, "B")), Z = do.call(rbind, lapply(pre_m, `[[`, "Z")),
                  group = unlist(lapply(pre_m, `[[`, "group")))
  sigma <- p4_match_sigma(groups, pre_all)
  scored <- purrr::map(seq_along(dev), function(i) {
    x <- dev[[i]]
    pre <- p4_predraw(x$rows, x$q, sims, seed + 100L + i)
    g <- groups[match(pre$group, groups$group), ]
    qp <- p4_ros_quantiles(g, pre, sigma, seed + 200L + i)$q
    sd_tab <- dplyr::summarise(x$train_groups, sd = stats::sd(.data$actual - .data$forecast), .by = c("position", "w"))
    qn <- p4_normal_quantiles(g, sd_tab)
    cov <- function(q, lo, hi) g$actual >= q[, match(lo, round(P2_TAU, 2))] & g$actual <= q[, match(hi, round(P2_TAU, 2))]
    tibble::tibble(season = g$season, w = g$w, gsis_id = g$gsis_id, position = g$position, actual = g$actual,
                   forecast = g$forecast, crps_p4 = crps_quantiles(qp, g$actual, P2_TAU),
                   crps_normal = crps_quantiles(qn, g$actual, P2_TAU),
                   cover50 = cov(qp, 0.25, 0.75), cover80 = cov(qp, 0.10, 0.90), cover90 = cov(qp, 0.05, 0.95),
                   cover80_normal = cov(qn, 0.10, 0.90))
  }) |> purrr::list_rbind()
  list(sigma = sigma, scored = scored,
       summary = dplyr::summarise(scored, n = dplyr::n(), crps_p4 = mean(.data$crps_p4), crps_normal = mean(.data$crps_normal),
                                  skill = 1 - mean(.data$crps_p4) / mean(.data$crps_normal), cover50 = mean(.data$cover50),
                                  cover80 = mean(.data$cover80), cover90 = mean(.data$cover90),
                                  cover80_normal = mean(.data$cover80_normal), .by = c("position", "w")) |>
         dplyr::arrange(.data$position, .data$w))
}

#' Player-season cluster bootstrap of a statistic over rows with columns gsis_id and season.
p4_ps_boot <- function(d, stat, reps = 1000L, seed = 1L) {
  ids <- split(seq_len(nrow(d)), paste(d$gsis_id, d$season))
  set.seed(seed)
  replicate(reps, stat(d[unlist(ids[sample(length(ids), length(ids), replace = TRUE)], use.names = FALSE), ]))
}

#' X2 and X26 with player-season bootstrap 95% CIs (development seasons only).
p4_studies <- function(player_week_all, seasons = P4_DEV, reps = 1000L, register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", seasons, "development", register)
  fr <- player_week_all[player_week_all$season %in% seasons, ]
  d <- fr[fr$pop_espn & fr$active & fr$position %in% P2_POSITIONS & !is.na(fr$base), ]
  d <- d[order(d$gsis_id, d$season, d$week), ]
  d$r <- d$actual - d$base
  lag1 <- function(x) {
    nxt <- dplyr::lead(x$r)
    ok <- !is.na(nxt) & dplyr::lead(x$gsis_id) == x$gsis_id & dplyr::lead(x$season) == x$season
    stats::cor(x$r[ok], nxt[ok])
  }
  x2 <- purrr::map(P2_POSITIONS, function(p) {
    x <- d[d$position == p, ]
    b <- p4_ps_boot(x, lag1, reps)
    tibble::tibble(position = p, lag1 = lag1(x), lo = unname(stats::quantile(b, 0.025)), hi = unname(stats::quantile(b, 0.975)))
  }) |> purrr::list_rbind()
  rev_rows <- {
    e <- fr[fr$pop_espn & fr$position %in% P2_POSITIONS & !is.na(fr$base), ]
    e <- e[order(e$gsis_id, e$season, e$week), ]
    nxt <- dplyr::lead(e$espn_proj)
    ok <- !is.na(nxt) & dplyr::lead(e$gsis_id) == e$gsis_id & dplyr::lead(e$season) == e$season &
      dplyr::lead(e$week) == e$week + 1L & e$active
    tibble::tibble(gsis_id = e$gsis_id[ok], season = e$season[ok], position = e$position[ok],
                   r = e$actual[ok] - e$base[ok], dp = nxt[ok] - e$espn_proj[ok])
  }
  slope <- function(x) unname(stats::coef(stats::lm(dp ~ r, data = x))[2])
  x26 <- purrr::map(P2_POSITIONS, function(p) {
    x <- rev_rows[rev_rows$position == p, ]
    b <- p4_ps_boot(x, slope, reps)
    tibble::tibble(position = p, n = nrow(x), slope = slope(x), lo = unname(stats::quantile(b, 0.025)),
                   hi = unname(stats::quantile(b, 0.975)))
  }) |> purrr::list_rbind()
  list(x2_autocorr = p4_x2_autocorr(fr), x2_lag1 = x2, x2_icc = p4_x2_icc(fr), x26 = x26)
}
