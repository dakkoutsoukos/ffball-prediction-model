# P3 gate (E21): are lineup totals calibrated under independence? --------------------------------
# Realistic lineups (F6 arm-A development replays, all teams, regular season), out-of-sample player
# distributions (the E20-selected P2 candidate refit on 2019..s-1) with position x band P(active),
# 2,000 independent draws per lineup. P3 is built only if the coverage gate fails.

P3_SIMS <- 2000L

#' Starting lineups of arm A in a replayed season, as gsis ids (regular season, all teams).
p3_lineups <- function(replay, S) {
  tw <- replay$team_weeks
  tw <- tw[tw$arm == "A" & tw$week %in% LAB_REG_WEEKS, ]
  tibble::tibble(season = tw$season, league = tw$league, n_teams = tw$n_teams, team = tw$team, week = tw$week,
                 starters = lapply(tw$lineup, function(x) S$ids[lab_ids(x)]))
}

#' Quantiles (99-level grid) of a P2 candidate fitted on `train`, for `rows`.
p3_candidate_q <- function(candidate, train, rows) {
  switch(candidate,
    C0 = p2_quantiles_c0(p2_fit_c0(train), rows),
    C1 = p2_quantiles_c1(p2_fit_c1(train), rows),
    C2 = p2_quantiles_c2(p2_fit_c2(train), rows),
    cli::cli_abort("E21's gate is implemented for C0-C2; candidate {.val {candidate}} needs its online levels."))
}

#' Gate rows for one season: per lineup, the realised total, its randomised PIT under independence
#' and interval coverage.
p3_gate_season <- function(frame_all, lineups, candidate, active_table, sims = P3_SIMS, seed = 1L) {
  s <- lineups$season[1]
  train <- frame_all[frame_all$season < s & frame_all$active, ]
  rows <- frame_all[frame_all$season == s, ]
  key <- paste(rows$week, rows$gsis_id)
  q <- p3_candidate_q(candidate, train, rows)
  p_act <- lab_p_active(rows$position, rows$base, active_table)
  set.seed(seed + s)
  out <- purrr::map(seq_len(nrow(lineups)), function(i) {
    k <- match(paste(lineups$week[i], lineups$starters[[i]]), key)
    k <- k[!is.na(k)]                                   # a starter without a projected row contributes 0
    realised <- if (length(k)) sum(rows$y[k]) else 0
    qb_team <- rows$team[k][rows$position[k] == "QB"]
    stack <- length(qb_team) > 0 && any(rows$team[k][rows$position[k] %in% c("WR", "TE", "RB")] %in% qb_team)
    if (!length(k)) return(tibble::tibble(realised = realised, pit = NA_real_, cover50 = NA, cover80 = NA, cover90 = NA,
                                          mean_sim = 0, var_sim = 0, starters = 0L, stack = FALSE))
    u <- matrix(stats::runif(length(k) * sims), length(k), sims)
    a <- matrix(stats::runif(length(k) * sims), length(k), sims) < p_act[k]
    draws <- matrix(sim_qdraw(q[rep(k, times = sims), , drop = FALSE], as.vector(u), P2_TAU), length(k), sims) * a
    tot <- colSums(draws)
    lo <- function(l) stats::quantile(tot, (1 - l) / 2, names = FALSE)
    hi <- function(l) stats::quantile(tot, (1 + l) / 2, names = FALSE)
    tibble::tibble(realised = realised,
                   pit = (sum(tot < realised) + stats::runif(1) * sum(tot == realised)) / sims,
                   cover50 = realised >= lo(0.5) & realised <= hi(0.5), cover80 = realised >= lo(0.8) & realised <= hi(0.8),
                   cover90 = realised >= lo(0.9) & realised <= hi(0.9), mean_sim = mean(tot), var_sim = stats::var(tot),
                   starters = length(k), stack = stack)
  }) |>
    purrr::list_rbind()
  dplyr::bind_cols(lineups[c("season", "league", "n_teams", "team", "week")], out)
}

#' The E21 gate over the three interval levels (05 section 6 procedure, Holm across 3 cells).
p3_gate <- function(gate_rows, reps = 2000L, seed = 1L) {
  d <- gate_rows[!is.na(gate_rows$pit), ]
  cells <- purrr::map(c(50, 80, 90), function(level) {
    x <- as.numeric(d[[paste0("cover", level)]])
    b <- pd_cluster_boot(x, d$season, d$week, reps, seed)
    est <- mean(x)
    nom <- level / 100
    p <- if (est < nom - 0.03) min(1, 2 * mean(b >= nom - 0.03)) else if (est > nom + 0.03) min(1, 2 * mean(b <= nom + 0.03)) else 1
    tibble::tibble(level = level, n = length(x), coverage = est, ci_low = unname(stats::quantile(b, 0.025)),
                   ci_high = unname(stats::quantile(b, 0.975)), p = p)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(p_holm = stats::p.adjust(.data$p, "holm"), fails = .data$p_holm < 0.05)
  desc <- function(g) dplyr::summarise(g, n = dplyr::n(), cover50 = mean(.data$cover50), cover80 = mean(.data$cover80),
                                       cover90 = mean(.data$cover90),
                                       variance_ratio = stats::var(.data$realised - .data$mean_sim) / mean(.data$var_sim))
  list(cells = cells, gate_fails = any(cells$fails), build_p3 = any(cells$fails),
       variance_ratio = stats::var(d$realised - d$mean_sim) / mean(d$var_sim),
       pit_hist = tabulate(pmin(floor(d$pit * 10) + 1, 10), 10) / nrow(d),
       by_stack = dplyr::bind_rows(dplyr::mutate(desc(d[d$stack, ]), stack = TRUE), dplyr::mutate(desc(d[!d$stack, ]), stack = FALSE)),
       by_league_size = dplyr::summarise(d, n = dplyr::n(), cover80 = mean(.data$cover80), .by = "n_teams"))
}
