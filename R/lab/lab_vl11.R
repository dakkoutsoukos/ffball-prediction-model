# VL11 (master plan Phase 4): the decision-family batch check on the 2025 replays. Run ONCE, after the
# VL11 pre-registration is committed; the register then records 2025 under spent_checks.
#
# 2024 is excluded for decisions (contamination register), so the 2025 inputs never use 2024 outcomes:
# the waiver calibration is fit on 2019-2023 and P0's rolling base is refit without 2024 rows. The 2025
# draft values use 2024 ESPN *projections* (no outcomes), as LAB1b specifies for every season.

VL11_SEASON <- 2025L
VL11_CALIB_SEASONS <- 2019:2023
VL11_NI_MARGIN <- 0.005                  # X23 non-inferiority margin on Brier (VL5, 05 section 6)

#' The F4 frame with the 2025 base refit by P0's procedure on every projected row except 2024's.
vl11_frame <- function(player_week_all, season = VL11_SEASON) {
  fr <- player_week_all
  src <- fr[fr$season != 2024L & !is.na(fr$espn_proj) & fr$espn_proj > 0, ]
  based <- pd_rolling_base(dplyr::transmute(src, .data$season, .data$week, .data$gsis_id, .data$position,
                                            .data$espn_proj, y = .data$actual, .data$active))
  based <- based[based$season == season, c("season", "week", "gsis_id", "base")]
  k <- match(paste(fr$season, fr$week, fr$gsis_id), paste(based$season, based$week, based$gsis_id))
  in_s <- fr$season == season
  fr$base[in_s] <- unname(based$base[k[in_s]])
  fr
}

#' The 2025 replay (check role): LAB1's design with arms A-E, the waiver calibration on 2019-2023.
vl11_replay <- function(frame, team_games, leagues = 20L, register = read_contamination_register()) {
  season <- VL11_SEASON
  assert_family_seasons("decision_family", season, "check", register)
  assert_family_seasons("decision_family", LAB_WARMUP, "warmup", register)
  S <- lab_season_data(frame, team_games, season)
  calib <- lab_waiver_calibration(frame, team_games, VL11_CALIB_SEASONS)
  sizes <- rep(c(8L, 10L, 12L), length.out = leagues)
  runs <- purrr::map(seq_len(leagues), function(l) {
    setup <- lab_setup(S, sizes[l], l, seed = season * 1000L + l)
    purrr::map(names(LAB_ARMS), function(arm) lab_run_league(S, setup, arm, calib, shadow = arm == "A"))
  }) |> purrr::list_flatten()
  pick <- function(el) purrr::list_rbind(purrr::compact(purrr::map(runs, el)))
  list(season = season, calib = dplyr::mutate(calib, season = season), team_weeks = pick("team_weeks"),
       standings = pick("standings"), claims = pick("claims"), waiver_triage = pick("waiver_triage"))
}

#' One-sided percentile-bootstrap p-value (E19c's form): the share of replicates on the null side.
vl11_p <- function(b, null_side = c("le0", "ge_margin"), margin = 0) {
  null_side <- match.arg(null_side)
  k <- if (null_side == "le0") sum(b <= 0) else sum(b >= margin)
  (1 + k) / (1 + length(b))
}

#' Week-level one-sided t-test (the plan's HLN-type sensitivity with h = 1): reported, never decisive.
vl11_t <- function(x, week, null = 0, alternative = "greater") {
  wm <- tapply(x, week, mean)
  n <- length(wm)
  tt <- (mean(wm) - null) / (stats::sd(wm) / sqrt(n)) * sqrt((n - 1) / n)
  if (alternative == "greater") stats::pt(tt, n - 1, lower.tail = FALSE) else stats::pt(tt, n - 1)
}

#' The five primaries on the 2025 replay (VL11). `x10b_metric`: the metric tested against VOR.
vl11_primaries <- function(replay, frame, team_games, table, active_table, x10b_metric, reps = 2000L, seed = 11L,
                           register = read_contamination_register()) {
  assert_family_seasons("decision_family", replay$season, "check", register)
  S <- lab_season_data(frame, team_games, replay$season)
  tw <- replay$team_weeks
  reg <- tw$week %in% LAB_REG_WEEKS
  est <- function(id, x, week, b, p, sens, extra = list()) {
    c(list(id = id, n = length(x), estimate = mean(x), ci = unname(stats::quantile(b, c(0.025, 0.975))), p = p,
           p_t_sensitivity = sens), extra)
  }
  out <- list()
  # X8: shadow calibrated - raw lineups, arm A, all teams, regular season
  a <- tw[tw$arm == "A" & reg, ]
  d8 <- a$shadow_cal - a$shadow_raw
  b8 <- pd_cluster_boot(d8, a$season, a$week, reps = reps, seed = seed)
  out$X8 <- est("X8", d8, a$week, b8, vl11_p(b8), vl11_t(d8, a$week))
  # X9 (late window, D1): late-window - EV win rate per team-week
  lw <- lw_season(replay, frame, team_games, table, active_table)
  d9 <- lw$win_lw - lw$win_ev
  b9 <- pd_cluster_boot(d9, lw$season, lw$week, reps = reps, seed = seed + 1L)
  out$X9 <- est("X9", d9, lw$week, b9, vl11_p(b9), vl11_t(d9, lw$week), list(share_swaps = mean(lw$swaps > 0)))
  # X10b: the tested metric's stage Spearman minus VOR's
  rows <- x10b_season(replay, frame, team_games, table, active_table)
  sc <- x10b_stage_cor(rows)
  ok <- !is.na(sc[[x10b_metric]]) & !is.na(sc$vor)
  d10 <- sc[[x10b_metric]][ok] - sc$vor[ok]
  b10 <- pd_cluster_boot(d10, sc$season[ok], sc$stage[ok], reps = reps, seed = seed + 2L)
  out$X10b <- est("X10b", d10, sc$stage[ok], b10, vl11_p(b10), vl11_t(d10, sc$stage[ok]),
                  list(metric = x10b_metric, stages = sum(ok)))
  # X16: focal arm E - C lineup points
  f <- tw[tw$focal & reg & tw$arm %in% c("C", "E"), c("season", "league", "week", "arm", "points")]
  wide <- tidyr::pivot_wider(f, names_from = "arm", values_from = "points")
  d16 <- wide$E - wide$C
  b16 <- pd_cluster_boot(d16, wide$season, wide$week, reps = reps, seed = seed + 3L)
  out$X16 <- est("X16", d16, wide$week, b16, vl11_p(b16), vl11_t(d16, wide$week))
  # X23: S1-sim vs normal approximation, non-inferiority of Brier (margin 0.005); slope reported
  pred <- s1_predict(s1_matchups(replay, S), frame, table, active_table)
  d23 <- (pred$p_sim - pred$outcome)^2 - (pred$p_normal - pred$outcome)^2
  b23 <- pd_cluster_boot(d23, pred$season, pred$week, reps = reps, seed = seed + 4L)
  out$X23 <- est("X23", d23, pred$week, b23, vl11_p(b23, "ge_margin", VL11_NI_MARGIN),
                 vl11_t(d23, pred$week, null = VL11_NI_MARGIN, alternative = "less"),
                 list(slope_sim = calibration_slope(pred$p_sim[pred$outcome != 0.5], pred$outcome[pred$outcome != 0.5])))
  ps <- vapply(out, `[[`, 0, "p")
  adj <- stats::p.adjust(ps, "holm")
  for (k in names(out)) {
    out[[k]]$p_holm <- unname(adj[k])
    out[[k]]$supported <- adj[[k]] < 0.05
  }
  out
}
