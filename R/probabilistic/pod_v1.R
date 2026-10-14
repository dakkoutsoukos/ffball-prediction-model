# P2: calibrated outcome distributions v1 (master plan P2; pre-registration E20) -------------------
# F(y | active, base, x) at the late horizon on F4 rows that are ESPN-projected and active. Every
# candidate yields quantiles on a 99-level grid. Development is out of sample by season (fit on
# 2019..s-1, score s, s = 2020-2023); nothing is computed on 2024-2025 before the E22 batch check.
#   C0  P0's procedure (empirical residual quantiles by position x band) on the 99-level grid
#   C1  isotonic distributional regression (IDR) of y on base, by position (PAVA via stats::isoreg)
#   C2  EMOS-style shash regression in mgcv (location smooth in base; log-scale smooth in base plus
#       the closed covariate list; skewness and kurtosis constant), by position
#   C3  the better of C0/C2 plus adaptive conformal level tracking (Gibbs and Candes 2021)

P2_TAU <- seq(0.01, 0.99, by = 0.01)
P2_DEV <- 2020:2023
P2_WARMUP <- 2019L
P2_POSITIONS <- c("QB", "RB", "WR", "TE")
P2_IDR_LEVELS <- seq(0.005, 0.995, by = 0.005)
P2_IDR_GRID <- 401L
P2_SHRINK_N <- 8
P2_ACI_GAMMA <- 0.01
P2_CANDIDATES <- c("C0", "C1", "C2", "C3")       # simplest first (the tie rule's order)

#' Point-in-time player volatility: the SD of the player's residuals (y - base) over his earlier
#' projected active weeks, shrunk toward the position's SD over all earlier weeks.
p2_volatility <- function(fr, n0 = P2_SHRINK_N, use = rep(TRUE, nrow(fr))) {
  o <- order(fr$season, fr$week, fr$gsis_id)
  fr <- fr[o, ]
  use <- use[o]                                          # rows that contribute (active rows); all rows get a value
  r <- ifelse(use, fr$y - fr$base, 0)
  u <- as.numeric(use)
  gi <- fr$season * 100L + fr$week
  # player: cumulative sums over strictly earlier contributing rows of the same player
  pl <- data.frame(id = fr$gsis_id, gi = gi, r = r, u = u)
  pl$n <- stats::ave(pl$u, pl$id, FUN = function(x) cumsum(x) - x)
  pl$s1 <- stats::ave(pl$r, pl$id, FUN = function(x) cumsum(x) - x)
  pl$s2 <- stats::ave(pl$r, pl$id, FUN = function(x) cumsum(x^2) - x^2)
  var_p <- ifelse(pl$n >= 2, (pl$s2 - pl$s1^2 / pmax(pl$n, 1)) / pmax(pl$n - 1, 1), NA_real_)
  # position: expanding over strictly earlier weeks
  pw <- dplyr::summarise(data.frame(position = fr$position, gi = gi, r = r, u = u), n = sum(.data$u), s1 = sum(.data$r),
                         s2 = sum(.data$r^2), .by = c("position", "gi")) |>
    dplyr::arrange(.data$position, .data$gi) |>
    dplyr::mutate(cn = cumsum(.data$n) - .data$n, c1 = cumsum(.data$s1) - .data$s1, c2 = cumsum(.data$s2) - .data$s2,
                  var_pos = ifelse(.data$cn >= 2, (.data$c2 - .data$c1^2 / .data$cn) / (.data$cn - 1), NA_real_),
                  .by = "position")
  var_pos <- pw$var_pos[match(paste(fr$position, gi), paste(pw$position, pw$gi))]
  n <- pl$n
  vol <- ifelse(is.na(var_p), sqrt(var_pos), sqrt((n * var_p + n0 * var_pos) / (n + n0)))
  fr$vol_shrunk <- vol
  fr
}

#' P2 rows: projected F4 player-weeks of `seasons` with the closed covariate list; active rows only
#' unless `active_only = FALSE` (E21's gate scores inactive starters too). Volatility is built from
#' active rows only, so active rows carry the same values either way.
p2_frame <- function(player_week_all, seasons, active_only = TRUE) {
  fr <- player_week_all |>
    dplyr::filter(.data$season %in% !!seasons, .data$position %in% P2_POSITIONS, .data$pop_espn) |>
    dplyr::transmute(.data$season, .data$week, .data$gsis_id, .data$position, .data$team, y = .data$actual, .data$base,
                     .data$espn_proj, .data$active,
                     status = factor(dplyr::case_when(.data$designation %in% c("Questionable", "Doubtful", "Out") ~ "QD",
                                                      .data$designation %in% "listed_only" ~ "listed",
                                                      TRUE ~ "none"), c("none", "listed", "QD")),
                     td_share = pmin(pmax((6 * (dplyr::coalesce(.data$espn_proj_receiving_tds, 0) +
                                                  dplyr::coalesce(.data$espn_proj_rushing_tds, 0)) +
                                             4 * dplyr::coalesce(.data$espn_proj_passing_tds, 0)) / .data$espn_proj, 0), 1),
                     implied_total = .data$implied_team_total, spread = .data$team_spread)
  fr <- p2_volatility(fr, use = fr$active)
  if (active_only) fr <- fr[fr$active, ]
  # rows without a closing line (rare) take the position's training-free neutral value
  fr$implied_total[is.na(fr$implied_total)] <- 22
  fr$spread[is.na(fr$spread)] <- 0
  fr$resid <- fr$y - fr$base
  fr
}

# ---- C0: P0's procedure on the 99-level grid -------------------------------------------------------
p2_fit_c0 <- function(train) {
  list(table = pd_residual_table(train, P2_TAU), resid = split(train$resid, train$position),
       bands = lapply(split(train, train$position), function(d) list(band = pd_band(d$base), r = d$resid)))
}

#' C0 quantiles at levels `tau` (any levels: residual quantiles of the row's merged band cell).
p2_quantiles_c0 <- function(fit, rows, tau = P2_TAU) {
  if (identical(tau, P2_TAU)) return(pd_quantiles(rows$position, rows$base, fit$table, P2_TAU))
  tab <- fit$table
  out <- matrix(NA_real_, nrow(rows), length(tau))
  band <- pd_band(rows$base)
  for (i in seq_len(nrow(tab))) {
    hit <- rows$position == tab$position[i] & band >= tab$band_lo[i] & band <= tab$band_hi[i]
    if (!any(hit)) next
    cell <- fit$bands[[tab$position[i]]]
    r <- cell$r[cell$band >= tab$band_lo[i] & cell$band <= tab$band_hi[i]]
    q <- stats::quantile(r, tau, type = 7, names = FALSE)
    out[hit, ] <- pmax(outer(rows$base[hit], q, `+`), tab$floor[i])
  }
  out
}

# ---- C1: isotonic distributional regression --------------------------------------------------------
#' Per position: thresholds z (training quantiles of y), and on a grid of base values the antitonic
#' (in base) CDF P(y <= z | base), fitted by PAVA on the training rows.
p2_fit_c1 <- function(train, levels = P2_IDR_LEVELS, grid_n = P2_IDR_GRID) {
  lapply(stats::setNames(P2_POSITIONS, P2_POSITIONS), function(p) {
    d <- train[train$position == p, ]
    z <- unique(stats::quantile(d$y, levels, type = 7, names = FALSE))
    ord <- order(-d$base, d$gsis_id)                      # increasing in -base = antitonic in base
    xb <- d$base[ord]
    yv <- d$y[ord]
    grid <- unique(stats::quantile(d$base, seq(0, 1, length.out = grid_n), type = 7, names = FALSE))
    Fg <- vapply(z, function(zz) {
      fitted <- stats::isoreg(yv <= zz)$yf                  # increasing along decreasing base
      # average ties in base, then interpolate onto the grid (base increasing)
      tb <- tapply(fitted, xb, mean)
      stats::approx(as.numeric(names(tb)), as.numeric(tb), xout = grid, rule = 2, ties = "ordered")$y
    }, numeric(length(grid)))
    Fg <- t(apply(matrix(Fg, nrow = length(grid)), 1, cummax))   # monotone in z (guards rounding)
    list(z = z, grid = grid, F = Fg, floor = min(d$y))
  })
}

#' C1 quantiles: the CDF at the row's base (linear between grid points), inverted at `tau` (linear
#' between thresholds; held at the end thresholds).
p2_quantiles_c1 <- function(fit, rows, tau = P2_TAU) {
  out <- matrix(NA_real_, nrow(rows), length(tau))
  for (p in names(fit)) {
    i <- which(rows$position == p)
    if (!length(i)) next
    f <- fit[[p]]
    k <- findInterval(rows$base[i], f$grid, all.inside = TRUE)
    w <- pmin(pmax((rows$base[i] - f$grid[k]) / pmax(f$grid[k + 1] - f$grid[k], 1e-12), 0), 1)
    Fr <- f$F[k, , drop = FALSE] * (1 - w) + f$F[k + 1, , drop = FALSE] * w
    out[i, ] <- t(apply(Fr, 1, function(Fz) {
      Fz <- cummax(Fz)
      vapply(tau, function(t) {
        j <- which(Fz >= t)[1]
        if (is.na(j)) return(max(f$z))
        if (j == 1) return(f$z[1])
        f$z[j - 1] + (t - Fz[j - 1]) / max(Fz[j] - Fz[j - 1], 1e-12) * (f$z[j] - f$z[j - 1])
      }, 0)
    }))
    out[i, ] <- pmax(out[i, , drop = FALSE], f$floor)
  }
  out
}

# ---- C2: EMOS-style shash regression -----------------------------------------------------------------
# E20a: the shash is fit to the residual r = y - base (location smooth in base), the same model space
# as E20's y ~ s(base) but without its degenerate optimum; quantiles of y are base + quantiles of r.
P2_C2_FORMULA <- list(r ~ s(base, k = 10), ~ s(base, k = 10) + status + td_share + implied_total + spread + vol_shrunk,
                      ~ 1, ~ 1)

p2_fit_c2 <- function(train) {
  lapply(stats::setNames(P2_POSITIONS, P2_POSITIONS), function(p) {
    d <- train[train$position == p, ]
    d$r <- d$y - d$base
    d$status <- droplevels(d$status)
    f <- P2_C2_FORMULA
    if (nlevels(d$status) < 2) f[[2]] <- stats::update(f[[2]], ~ . - status)
    list(fit = mgcv::gam(f, family = mgcv::shash(), data = d, method = "REML"), floor = min(d$y),
         status_levels = levels(d$status))
  })
}

#' shash quantiles from the four linear predictors (location, log-scale, skewness, log-kurtosis).
p2_shash_q <- function(lp, tau) {
  mu <- lp[, 1]
  sig <- exp(lp[, 2])
  eps <- lp[, 3]
  del <- exp(lp[, 4])
  zq <- asinh(stats::qnorm(tau))
  mu + (del * sig) * sinh(outer(1 / del, zq) + eps / del)
}

p2_quantiles_c2 <- function(fit, rows, tau = P2_TAU) {
  out <- matrix(NA_real_, nrow(rows), length(tau))
  for (p in names(fit)) {
    i <- which(rows$position == p)
    if (!length(i)) next
    nd <- rows[i, ]
    nd$status <- factor(ifelse(as.character(nd$status) %in% fit[[p]]$status_levels, as.character(nd$status), "none"),
                        fit[[p]]$status_levels)
    lp <- stats::predict(fit[[p]]$fit, newdata = nd, type = "link")
    out[i, ] <- pmax(rows$base[i] + p2_shash_q(lp, tau), fit[[p]]$floor)   # E20a: residual model
  }
  out
}

# ---- C3: adaptive conformal level tracking --------------------------------------------------------
#' Online over the scored season's weeks, per position: quantiles at levels tau + delta (clipped),
#' with delta updated after each week from that week's realised coverage of every level.
p2_quantiles_c3 <- function(qfun, rows, tau = P2_TAU, gamma = P2_ACI_GAMMA) {
  out <- matrix(NA_real_, nrow(rows), length(tau))
  for (p in P2_POSITIONS) {
    delta <- rep(0, length(tau))
    for (s in sort(unique(rows$season))) {
      delta[] <- 0
      for (w in sort(unique(rows$week[rows$season == s & rows$position == p]))) {
        i <- which(rows$position == p & rows$season == s & rows$week == w)
        lev <- pmin(pmax(tau + delta, 0.005), 0.995)
        q <- qfun(rows[i, ], lev)
        q <- t(apply(q, 1, cummax))                         # keep quantiles ordered
        out[i, ] <- q
        cov <- colMeans(rows$y[i] <= q)
        delta <- delta + gamma * (tau - cov)
      }
    }
  }
  out
}

# ---- Development evaluation ----------------------------------------------------------------------
#' Quantiles of one candidate for season s, fit on 2019..s-1 (C3 uses `c3_base`, "C0" or "C2").
p2_candidate_quantiles <- function(frame, s, candidate, c3_base = "C0") {
  train <- frame[frame$season < s, ]
  rows <- frame[frame$season == s, ]
  q <- switch(candidate,
    C0 = p2_quantiles_c0(p2_fit_c0(train), rows),
    C1 = p2_quantiles_c1(p2_fit_c1(train), rows),
    C2 = p2_quantiles_c2(p2_fit_c2(train), rows),
    C3 = {
      fit <- if (c3_base == "C0") p2_fit_c0(train) else p2_fit_c2(train)
      qf <- if (c3_base == "C0") function(r, lev) p2_quantiles_c0(fit, r, lev) else function(r, lev) p2_quantiles_c2(fit, r, lev)
      p2_quantiles_c3(qf, rows)
    })
  list(rows = rows, q = q)
}

#' Per-row scores of quantile forecasts on the 99-level grid.
p2_score_rows <- function(rows, q, tau = P2_TAU, seed = 1L) {
  cdf <- cdf_from_quantiles(rows$y, q, tau)
  set.seed(seed)
  lv <- function(lo, hi) rows$y >= q[, match(lo, round(tau, 2))] & rows$y <= q[, match(hi, round(tau, 2))]
  tibble::tibble(season = rows$season, week = rows$week, position = rows$position, y = rows$y, base = rows$base,
                 crps = crps_quantiles(q, rows$y, tau), pit = pit_randomised(cdf$F, cdf$F_minus),
                 cover50 = lv(0.25, 0.75), cover80 = lv(0.10, 0.90), cover90 = lv(0.05, 0.95),
                 twcrps20 = p2_tw_crps(q, rows$y, tau, 20))
}

#' Threshold-weighted CRPS with weight 1{z >= t}: 2 * integral of QS over levels whose quantile is
#' at or above t (the quantile-weighted analogue; reported only).
p2_tw_crps <- function(q, y, tau, t) {
  K <- length(tau)
  qs <- vapply(seq_len(K), function(k) quantile_score(q[, k], y, tau[k]) * (q[, k] >= t), numeric(length(y)))
  2 * rowMeans(matrix(qs, nrow = length(y)))
}

#' The coverage gate (05 section 6; E18's procedure): per position x level, the week-clustered CI
#' must overlap [nominal - 3 pp, nominal + 3 pp]; a cell fails only when the Holm-adjusted test rejects.
p2_coverage_gate <- function(pred, reps = 2000L, seed = 1L) {
  cells <- tidyr::expand_grid(position = P2_POSITIONS, level = c(50, 80, 90))
  purrr::pmap(cells, function(position, level) {
    d <- pred[pred$position == position, ]
    x <- as.numeric(d[[paste0("cover", level)]])
    b <- pd_cluster_boot(x, d$season, d$week, reps, seed)
    est <- mean(x)
    nom <- level / 100
    p <- if (est < nom - 0.03) min(1, 2 * mean(b >= nom - 0.03)) else if (est > nom + 0.03) min(1, 2 * mean(b <= nom + 0.03)) else 1
    tibble::tibble(position = position, level = level, n = length(x), coverage = est,
                   ci_low = unname(stats::quantile(b, 0.025)), ci_high = unname(stats::quantile(b, 0.975)), p = p)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(p_holm = stats::p.adjust(.data$p, "holm"), fails_gate = .data$p_holm < 0.05)
}

#' Selection (E20): lowest pooled development CRPS among candidates passing the coverage gate; a
#' difference below 0.5% of the best is a tie and the simpler candidate wins.
p2_select <- function(summary, tie = 0.005) {
  ok <- summary[summary$gate_passed, ]
  if (!nrow(ok)) return(NA_character_)
  best <- min(ok$crps)
  tied <- ok$candidate[ok$crps <= best * (1 + tie)]
  tied[order(match(tied, P2_CANDIDATES))][1]
}

#' One candidate's out-of-sample development predictions and per-row scores (2020-2023).
p2_dev_run <- function(frame, candidate, c3_base = "C0", register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", P2_DEV, "development", register)
  assert_family_seasons("distribution_stack", P2_WARMUP, "warmup", register)
  if (any(frame$season > max(P2_DEV))) cli::cli_abort("The P2 development frame may not contain seasons after {max(P2_DEV)}.")
  purrr::map(P2_DEV, function(s) {
    x <- p2_candidate_quantiles(frame, s, candidate, c3_base)
    p2_score_rows(x$rows, x$q, seed = s)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(candidate = candidate, .before = 1)
}

#' C3's base (E20): the better of C0 and C2 by pooled development CRPS.
p2_c3_base <- function(dev_c0, dev_c2) if (mean(dev_c2$crps) < mean(dev_c0$crps)) "C2" else "C0"

#' Development summary and selection (E20). `runs`: list of p2_dev_run() outputs.
p2_dev_summary <- function(runs, reps = 2000L, seed = 1L) {
  runs <- stats::setNames(runs, vapply(runs, function(r) r$candidate[1], ""))
  gates <- lapply(runs, p2_coverage_gate, reps = reps, seed = seed)
  summ <- purrr::map(names(runs), function(k) {
    r <- runs[[k]]
    tibble::tibble(candidate = k, n = nrow(r), crps = mean(r$crps), twcrps20 = mean(r$twcrps20),
                   cover50 = mean(r$cover50), cover80 = mean(r$cover80), cover90 = mean(r$cover90),
                   gate_passed = !any(gates[[k]]$fails_gate))
  }) |> purrr::list_rbind()
  paired <- function(k, ref) {
    a <- runs[[k]]
    b <- runs[[ref]]
    stopifnot(identical(a$season, b$season), identical(a$week, b$week), identical(a$y, b$y))
    x <- a$crps - b$crps
    bt <- pd_cluster_boot(x, a$season, a$week, reps = reps, seed = seed)
    tibble::tibble(candidate = k, reference = ref, d_crps = mean(x), lo = unname(stats::quantile(bt, 0.025)),
                   hi = unname(stats::quantile(bt, 0.975)), rel = mean(x) / mean(b$crps))
  }
  others <- setdiff(names(runs), "C0")
  deltas <- dplyr::bind_rows(purrr::map(others, paired, ref = "C0"),
                             purrr::map(setdiff(others, "C1"), paired, ref = "C1"))
  by_position <- purrr::map(names(runs), function(k) {
    dplyr::summarise(runs[[k]], n = dplyr::n(), crps = mean(.data$crps), cover50 = mean(.data$cover50),
                     cover80 = mean(.data$cover80), cover90 = mean(.data$cover90),
                     pit_chisq = unname(stats::chisq.test(tabulate(pmin(floor(.data$pit * 10) + 1, 10), 10))$statistic),
                     .by = "position") |>
      dplyr::mutate(candidate = k, .before = 1)
  }) |> purrr::list_rbind()
  list(summary = summ, deltas = deltas, by_position = by_position, gates = gates, selected = p2_select(summ))
}
