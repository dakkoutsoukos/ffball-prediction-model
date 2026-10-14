# F6 decision laboratory v1: outcome-free triage (X8, X9) and development results (LAB1) ----------
# Triage reads only decision columns (lineups, claims, model values), never realised points, and is
# reported before lab_dev_results() is computed.

lab_ids <- function(x) as.integer(strsplit(x, " ", fixed = TRUE)[[1]])

#' X8 triage (outcome-free): lineup and waiver flip rates between the raw and calibrated policies
#' on arm-A states, and the calibrated model's implied gains. Regular-season weeks.
lab_x8_triage <- function(replays) {
  tw <- purrr::map(replays, "team_weeks") |> purrr::list_rbind()
  tw <- tw[tw$arm == "A" & tw$week %in% LAB_REG_WEEKS, ]
  wt <- purrr::map(replays, "waiver_triage") |> purrr::list_rbind()
  wt <- wt[wt$arm == "A" & wt$week %in% LAB_REG_WEEKS, ]
  list(
    lineup = tw |>
      dplyr::summarise(team_weeks = dplyr::n(), flip_rate = mean(.data$lineup_flip),
                       model_gain_mean = mean(.data$model_gain),
                       model_gain_given_flip = if (any(.data$lineup_flip)) mean(.data$model_gain[.data$lineup_flip]) else 0,
                       .by = c("season", "n_teams")) |>
      dplyr::arrange(.data$season, .data$n_teams),
    lineup_overall = tw |>
      dplyr::summarise(team_weeks = dplyr::n(), flip_rate = mean(.data$lineup_flip), model_gain_mean = mean(.data$model_gain),
                       model_gain_given_flip = mean(.data$model_gain[.data$lineup_flip])),
    waiver = wt |>
      dplyr::summarise(team_weeks = dplyr::n(), flip_rate = mean(.data$flip), raw_claims_per_week = mean(.data$raw_claims),
                       cal_claims_per_week = mean(.data$cal_claims), model_gain_mean = mean(.data$model_gain_cal_vs_raw),
                       .by = "season") |>
      dplyr::arrange(.data$season)
  )
}

#' Single-swap feasibility of a starting set: at most one QB, and the RB/WR/TE beyond the fixed
#' slots fit the FLEX slots.
lab_feasible <- function(pos) {
  n <- table(factor(pos, LAB_POSITIONS))
  n[["QB"]] <= 1 && n[["TE"]] + n[["RB"]] + n[["WR"]] <= 7 &&
    max(0, n[["RB"]] - 2) + max(0, n[["WR"]] - 2) + max(0, n[["TE"]] - 1) <= LAB_SLOTS$FLEX
}

#' Active share of ESPN-projected player-weeks by position x P0 base band, on P0's development rows
#' (2020-2023). LAB1a: the position-only share mixes starters and backups (QB 0.75).
lab_active_table <- function(pd_based, seasons = POD_DEV_SEASONS) {
  d <- pd_based[pd_based$season %in% seasons, ]
  dplyr::summarise(dplyr::mutate(d, band = pd_band(.data$base)), rows = dplyr::n(), active_share = mean(.data$active),
                   .by = c("position", "band")) |>
    dplyr::arrange(.data$position, .data$band)
}

#' P(active) for players from the position x band table (the position's overall share where a band
#' has no rows).
lab_p_active <- function(pos, base, active_table) {
  k <- match(paste(pos, pd_band(base)), paste(active_table$position, active_table$band))
  p <- active_table$active_share[k]
  overall <- tapply(active_table$active_share * active_table$rows, active_table$position, sum) /
    tapply(active_table$rows, active_table$position, sum)
  p[is.na(p)] <- overall[pos[is.na(p)]]
  unname(p)
}

#' X9 triage (outcome-free) for one focal team-week: P(win) of the calibrated EV lineup against the
#' opponent's calibrated EV lineup, versus every feasible single swap with a bench player. Points:
#' P0 quantiles around the base, active with the position x band probability; common random numbers.
lab_x9_team_week <- function(info, roster, opp_roster, table, active_table, sims = 2000L, seed = 1L) {
  pos <- info$pos
  vf <- lab_lineup_values(info, roster, "calibrated")
  vo <- lab_lineup_values(info, opp_roster, "calibrated")
  lf <- roster[lab_lineup(vf, pos[roster])]
  lo <- opp_roster[lab_lineup(vo, pos[opp_roster])]
  bench <- setdiff(roster[is.finite(vf)], lf)
  players <- unique(c(lf, bench, lo))
  b <- dplyr::coalesce(info$base[players, info$t], 0)
  q <- pd_quantiles(pos[players], b, table)
  set.seed(seed)
  k <- length(players)
  u <- matrix(stats::runif(k * sims), k, sims)
  act <- matrix(stats::runif(k * sims), k, sims) < lab_p_active(pos[players], b, active_table)
  pts <- matrix(sim_qdraw(q[rep(seq_len(k), times = sims), , drop = FALSE], as.vector(u)), k, sims) * act
  row <- function(ids) match(ids, players)
  tot_f <- colSums(pts[row(lf), , drop = FALSE])
  tot_o <- colSums(pts[row(lo), , drop = FALSE])
  win0 <- (tot_f > tot_o) + 0.5 * (tot_f == tot_o)
  best <- list(delta = 0, se = 0, ev_loss = 0)
  for (s in lf) for (bb in bench) {
    new <- c(lf[lf != s], bb)
    if (!lab_feasible(pos[new])) next
    tot <- tot_f - pts[row(s), ] + pts[row(bb), ]
    d <- ((tot > tot_o) + 0.5 * (tot == tot_o)) - win0
    if (mean(d) > best$delta) {
      best <- list(delta = mean(d), se = stats::sd(d) / sqrt(sims),
                   ev_loss = vf[match(s, roster)] - vf[match(bb, roster)])
    }
  }
  tibble::tibble(p_win_ev = mean(win0), delta_best = best$delta, se_best = best$se,
                 flip = best$delta > 2 * best$se && best$delta > 0, ev_loss_of_best = best$ev_loss)
}

#' X9 triage over the arm-A focal team-weeks of one replayed season (regular season).
lab_x9_triage <- function(frame, team_games, replay, table, active_table, sims = 2000L) {
  S <- lab_season_data(frame, team_games, replay$season)
  tw <- replay$team_weeks[replay$team_weeks$arm == "A" & replay$team_weeks$week %in% LAB_REG_WEEKS, ]
  foc <- tw[tw$focal, ]
  purrr::map(seq_len(nrow(foc)), function(i) {
    f <- foc[i, ]
    o <- tw[tw$league == f$league & tw$week == f$week & tw$team == f$opponent, ]
    info <- lab_info(S, f$week, "lineup")
    out <- lab_x9_team_week(info, lab_ids(f$roster), lab_ids(o$roster), table, active_table, sims,
                            seed = replay$season * 10000L + f$league * 100L + f$week)
    dplyr::bind_cols(f[c("season", "league", "n_teams", "week")], out)
  }) |> purrr::list_rbind()
}

#' X9 summary: flip rate, mean delta P(win), and the kill rule for D1's full P(win) mode.
lab_x9_summary <- function(x9) {
  s <- dplyr::summarise(x9, team_weeks = dplyr::n(), flip_rate = mean(.data$flip), mean_delta = mean(.data$delta_best),
                        p90_delta = stats::quantile(.data$delta_best, 0.9), mean_p_win_ev = mean(.data$p_win_ev))
  s$kill_full_pwin_mode <- s$flip_rate < 0.05 || s$mean_delta < 0.005
  s
}

#' Development results (LAB1; computed only after the triage is reported). Regular-season weeks.
#' Shadow: calibrated minus raw lineup on identical rosters (arm A, all teams). Arms: the focal
#' team's realised lineup points, paired by league and week. Intervals: week-clustered,
#' season-blocked bootstrap (weeks resampled within season).
lab_dev_results <- function(replays, reps = 2000L, seed = 1L,
                            register = read_contamination_register()) {
  tw <- purrr::map(replays, "team_weeks") |> purrr::list_rbind()
  assert_family_seasons("decision_family", unique(tw$season), "development", register)
  tw <- tw[tw$week %in% LAB_REG_WEEKS, ]
  ci <- function(x, season, week) {
    b <- pd_cluster_boot(x, season, week, reps = reps, seed = seed)
    tibble::tibble(n = length(x), mean = mean(x), lo = unname(stats::quantile(b, 0.025)), hi = unname(stats::quantile(b, 0.975)))
  }
  sh <- tw[tw$arm == "A", ]
  shadow <- dplyr::bind_cols(tibble::tibble(comparison = "shadow: calibrated - raw lineup (all teams, arm A)"),
                             ci(sh$shadow_cal - sh$shadow_raw, sh$season, sh$week))
  foc <- tw[tw$focal, c("season", "league", "week", "arm", "points", "hindsight")]
  wide <- tidyr::pivot_wider(foc[c("season", "league", "week", "arm", "points")], names_from = "arm", values_from = "points")
  arms <- purrr::map(c("B", "C", "D"), function(a) {
    dplyr::bind_cols(tibble::tibble(comparison = paste0("focal arm ", a, " - A")),
                     ci(wide[[a]] - wide$A, wide$season, wide$week))
  }) |> purrr::list_rbind()
  st <- purrr::map(replays, "standings") |> purrr::list_rbind()
  list(
    lineup_points = dplyr::bind_rows(shadow, arms),
    regret = dplyr::summarise(foc, regret = mean(.data$hindsight - .data$points), .by = "arm") |> dplyr::arrange(.data$arm),
    season_level = st[st$focal, ] |>
      dplyr::summarise(leagues = dplyr::n(), wins = mean(.data$wins), playoffs = mean(.data$playoffs),
                       titles = mean(.data$title), .by = "arm") |>
      dplyr::arrange(.data$arm)
  )
}

#' X16 (VL9): focal realised lineup points, arm E (QB streaming) minus arm C, per team-week (regular
#' season), with a week-clustered, season-blocked CI. Also: the focal team's claims and QB claims per
#' league-season, and the realised points of its starting QB (E - C, same CI).
lab_stream_result <- function(replays, player_week_all, team_games, reps = 2000L, seed = 16L,
                              register = read_contamination_register()) {
  seasons <- vapply(replays, function(rp) as.integer(rp$season), 0L)
  assert_family_seasons("decision_family", seasons, "development", register)
  parts <- purrr::map(replays, function(rp) {
    S <- lab_season_data(player_week_all, team_games, rp$season)
    tw <- rp$team_weeks
    x <- tw[tw$focal & tw$week %in% LAB_REG_WEEKS & tw$arm %in% c("C", "E"), ]
    ids <- lapply(strsplit(x$lineup, " ", fixed = TRUE), as.integer)
    wk <- match(x$week, S$weeks)
    qb_pts <- vapply(seq_along(ids), function(i) {
      q <- ids[[i]][S$pos[ids[[i]]] == "QB"]
      sum(dplyr::coalesce(S$y[q, wk[i]], 0))
    }, 0)
    rows <- tibble::tibble(season = x$season, league = x$league, week = x$week, arm = x$arm, points = x$points,
                           qb_points = qb_pts)
    st <- rp$standings[rp$standings$focal & rp$standings$arm == "E", ]
    cl <- rp$claims %||% tibble::tibble(league = integer(), arm = character(), team = integer(), add = integer())
    cl <- cl[cl$arm %in% c("C", "E") & cl$team == st$team[match(cl$league, st$league)], ]
    is_qb <- S$pos[cl$add] == "QB"
    claims <- tibble::tibble(season = rp$season, arm = c("C", "E"), leagues = nrow(st),
                             claims = c(sum(cl$arm == "C"), sum(cl$arm == "E")),
                             qb_claims = c(sum(is_qb & cl$arm == "C"), sum(is_qb & cl$arm == "E")))
    list(rows = rows, claims = claims)
  })
  rows <- purrr::map(parts, "rows") |> purrr::list_rbind()
  wide <- tidyr::pivot_wider(rows, id_cols = c("season", "league", "week"), names_from = "arm",
                             values_from = c("points", "qb_points"))
  d <- wide$points_E - wide$points_C
  dq <- wide$qb_points_E - wide$qb_points_C
  b <- pd_cluster_boot(d, wide$season, wide$week, reps = reps, seed = seed)
  bq <- pd_cluster_boot(dq, wide$season, wide$week, reps = reps, seed = seed + 1L)
  claims <- purrr::map(parts, "claims") |> purrr::list_rbind()
  list(n = length(d), mean = mean(d), ci = unname(stats::quantile(b, c(0.025, 0.975))),
       share_differs = mean(d != 0), qb_mean = mean(dq), qb_ci = unname(stats::quantile(bq, c(0.025, 0.975))),
       claims = dplyr::mutate(claims, per_league = .data$claims / .data$leagues,
                              qb_per_league = .data$qb_claims / .data$leagues))
}
