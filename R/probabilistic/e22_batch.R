# E22: the distribution stack's one-time batch check on 2024 (P2, P4; P3 only if its gate built it)
# Everything is fit on 2019-2023 and frozen before 2024 is scored once. Gated in the pipeline on the
# E22 pre-registration; records go to spent_checks afterwards.

E22_SEASON <- 2024L

#' P2 on 2024: quantiles of the selected candidate, C0 and C1 fit on 2019-2023; per-row scores.
e22_p2_scores <- function(frame_all, selected, c3_base = "C0") {
  train <- frame_all[frame_all$season < E22_SEASON & frame_all$active, ]
  rows <- frame_all[frame_all$season == E22_SEASON & frame_all$active, ]
  q_of <- function(k) switch(k,
    C0 = p2_quantiles_c0(p2_fit_c0(train), rows),
    C1 = p2_quantiles_c1(p2_fit_c1(train), rows),
    C2 = p2_quantiles_c2(p2_fit_c2(train), rows),
    C3 = {
      fit <- if (c3_base == "C0") p2_fit_c0(train) else p2_fit_c2(train)
      qf <- if (c3_base == "C0") function(r, lev) p2_quantiles_c0(fit, r, lev) else function(r, lev) p2_quantiles_c2(fit, r, lev)
      p2_quantiles_c3(qf, rows)
    })
  ks <- unique(c(selected, "C0", "C1"))
  stats::setNames(lapply(ks, function(k) dplyr::mutate(p2_score_rows(rows, q_of(k), seed = E22_SEASON), candidate = k)), ks)
}

#' P2's primary: dCRPS(selected - C0) week-clustered bootstrap (one-sided p for < 0), non-inferiority
#' against C1 (upper bound <= 0.5% of C1's CRPS), and the coverage gate.
e22_p2_primary <- function(scores, selected, reps = 2000L, seed = 22L) {
  d <- function(a, b) scores[[a]]$crps - scores[[b]]$crps
  s <- scores[[selected]]
  x0 <- d(selected, "C0")
  b0 <- pd_cluster_boot(x0, s$season, s$week, reps = reps, seed = seed)
  out <- list(selected = selected, n = nrow(s), crps = vapply(scores, function(z) mean(z$crps), 0),
              d_vs_c0 = mean(x0), ci_vs_c0 = unname(stats::quantile(b0, c(0.025, 0.975))),
              p_vs_c0 = (1 + sum(b0 >= 0)) / (1 + reps), gate = p2_coverage_gate(s, reps = reps, seed = seed))
  if (selected != "C1") {
    x1 <- d(selected, "C1")
    b1 <- pd_cluster_boot(x1, s$season, s$week, reps = reps, seed = seed + 1L)
    out$d_vs_c1 <- mean(x1)
    out$ci_vs_c1 <- unname(stats::quantile(b1, c(0.025, 0.975)))
    out$not_worse_than_c1 <- out$ci_vs_c1[2] <= 0.005 * mean(scores[["C1"]]$crps)
  } else {
    out$not_worse_than_c1 <- TRUE
  }
  out$gate_passed <- !any(out$gate$fails_gate)
  out
}

#' P4 on 2024: components and noise fit on 2019-2023, sigma_L from the development matching, the
#' VE1-normal baseline SD from 2019-2023 ROS residuals. Returns scored groups.
e22_p4_scores <- function(player_week_all, team_games, frame_all, selected, sigma, sims = P4_SIMS, seed = 2024L) {
  all_rows <- purrr::map(c(P2_WARMUP, P4_DEV, E22_SEASON), function(s) {
    S <- lab_season_data(player_week_all, team_games, s)
    dplyr::bind_rows(p4_ros_rows(S, P4_ASOF), dplyr::mutate(p4_ros_rows(S, setdiff(1:15, P4_ASOF)), fit_only = TRUE))
  }) |> purrr::list_rbind()
  all_rows$fit_only <- dplyr::coalesce(all_rows$fit_only, FALSE)
  comp <- p4_fit_components(all_rows[all_rows$season < E22_SEASON, ])
  rows <- p4_apply_components(all_rows[all_rows$season == E22_SEASON & !all_rows$fit_only, ], comp)
  train <- frame_all[frame_all$season < E22_SEASON & frame_all$active, ]
  q <- p4_noise_quantiles(rows, train, selected, asof = frame_all)
  tg <- p4_groups(p4_apply_components(all_rows[all_rows$season < E22_SEASON & !all_rows$fit_only, ], comp))
  sd_tab <- dplyr::summarise(tg, sd = stats::sd(.data$actual - .data$forecast), .by = c("position", "w"))
  pre <- p4_predraw(rows, q, sims, seed)
  groups <- p4_groups(rows)
  g <- groups[match(pre$group, groups$group), ]
  qp <- p4_ros_quantiles(g, pre, sigma, seed + 1L)$q
  qn <- p4_normal_quantiles(g, sd_tab)
  cov <- function(q, lo, hi) g$actual >= q[, match(lo, round(P2_TAU, 2))] & g$actual <= q[, match(hi, round(P2_TAU, 2))]
  tibble::tibble(season = g$season, w = g$w, gsis_id = g$gsis_id, position = g$position, actual = g$actual,
                 crps_p4 = crps_quantiles(qp, g$actual, P2_TAU), crps_normal = crps_quantiles(qn, g$actual, P2_TAU),
                 cover50 = cov(qp, 0.25, 0.75), cover80 = cov(qp, 0.10, 0.90), cover90 = cov(qp, 0.05, 0.95))
}

#' Player-clustered bootstrap of a mean (players resampled, keeping all their as-of weeks).
e22_player_boot <- function(x, player, reps = 2000L, seed = 1L) {
  idx <- split(seq_along(x), player)
  set.seed(seed)
  replicate(reps, {
    i <- unlist(idx[sample(length(idx), length(idx), replace = TRUE)], use.names = FALSE)
    mean(x[i])
  })
}

#' P4's primary: dCRPS(P4 - VE1-normal) with the player-clustered bootstrap, and the ROS coverage
#' gate over position x level (Holm across 12 cells, same cluster).
e22_p4_primary <- function(sc, reps = 2000L, seed = 23L) {
  x <- sc$crps_p4 - sc$crps_normal
  b <- e22_player_boot(x, sc$gsis_id, reps, seed)
  cells <- tidyr::expand_grid(position = P2_POSITIONS, level = c(50, 80, 90))
  gate <- purrr::pmap(cells, function(position, level) {
    d <- sc[sc$position == position, ]
    v <- as.numeric(d[[paste0("cover", level)]])
    bb <- e22_player_boot(v, d$gsis_id, reps, seed + level)
    est <- mean(v)
    nom <- level / 100
    p <- if (est < nom - 0.03) min(1, 2 * mean(bb >= nom - 0.03)) else if (est > nom + 0.03) min(1, 2 * mean(bb <= nom + 0.03)) else 1
    tibble::tibble(position = position, level = level, n = length(v), coverage = est,
                   ci_low = unname(stats::quantile(bb, 0.025)), ci_high = unname(stats::quantile(bb, 0.975)), p = p)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(p_holm = stats::p.adjust(.data$p, "holm"), fails_gate = .data$p_holm < 0.05)
  list(n = length(x), crps_p4 = mean(sc$crps_p4), crps_normal = mean(sc$crps_normal), d = mean(x),
       ci = unname(stats::quantile(b, c(0.025, 0.975))), p = (1 + sum(b >= 0)) / (1 + reps), gate = gate,
       gate_passed = !any(gate$fails_gate))
}

#' Holm across the batch's primaries; success flags per family member.
e22_decide <- function(p2, p4, alpha = 0.05) {
  # if development selected C0 (P0's procedure), P2 has no primary: Holm runs over the rest
  ps <- c(P2 = if (identical(p2$selected, "C0")) NA_real_ else p2$p_vs_c0, P4 = p4$p)
  ps <- ps[!is.na(ps)]
  adj <- stats::p.adjust(ps, "holm")
  list(p_holm = adj,
       success_p2 = "P2" %in% names(adj) && adj[["P2"]] <= alpha && p2$ci_vs_c0[2] < 0 && p2$not_worse_than_c1 &&
         p2$gate_passed,
       success_p4 = adj[["P4"]] <= alpha && p4$ci[2] < 0 && p4$gate_passed)
}
