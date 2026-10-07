# Valuation: providers and ROS weeks, VOR/VAS, display scale, scoring, snapshots.

val_toy_league <- function(teams = 2, flex = 1, bench = 2) {
  slots <- list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 2),
                list(name = "WR", eligible = "WR", count = 2), list(name = "TE", eligible = "TE", count = 1))
  if (flex > 0) slots <- c(slots, list(list(name = "FLEX", eligible = c("RB", "WR", "TE"), count = flex)))
  val_league(list(name = "toy", teams = teams, slots = slots, bench = bench,
                  regular_season_weeks = c(1, 6), playoff_weeks = c(7, 8)))
}

#' Synthetic live context: two teams (AAA bye in week 6), ESPN capture for
#' weeks 5-8 encoded as receptions (1 PPR point each), simple ROS tables
#' (E = X, P(active) ~ 1) and week-of history weeks 1-4.
toy_ctx <- function() {
  ids <- c(q = "1", r = "2", w = "3", t = "4", inj = "5", nf = "6")
  pos <- c(q = "QB", r = "RB", w = "WR", t = "TE", inj = "WR", nf = "RB")
  team_id <- c(q = 1L, r = 1L, w = 2L, t = 2L, inj = 2L, nf = 1L)
  proj <- list(q = c(20, 20, 20, 20), r = c(15, 15, 15, 15), w = c(12, 12, 12, 12), t = c(8, 8, 8, 8),
               inj = c(0, 0, 14, 14), nf = c(9, NA, NA, NA))
  cap <- purrr::imap(proj, function(v, k) {
    tibble::tibble(espn_id = ids[[k]], espn_name = k, position = pos[[k]], espn_pro_team_id = team_id[[k]],
                   week = 5:8, receptions = v, injury_status = if (k == "inj") "OUT" else "ACTIVE",
                   pct_owned = 50, pct_started = 40)
  }) |>
    purrr::list_rbind() |>
    dplyr::filter(!is.na(.data$receptions)) |>
    dplyr::mutate(team = c(`1` = "AAA", `2` = "BBB")[as.character(.data$espn_pro_team_id)], season = 2026L)
  tg <- tidyr::expand_grid(season = 2026L, week = 1:8, team = c("AAA", "BBB", "CCC", "DDD")) |>
    dplyr::mutate(opponent = c(AAA = "CCC", BBB = "DDD", CCC = "AAA", DDD = "BBB")[.data$team]) |>
    dplyr::filter(!(.data$team == "AAA" & .data$week == 6)) |>
    dplyr::mutate(game_final = .data$week < 5)
  hist <- tibble::tibble(season = 2026L, week = rep(1:4, 2), espn_id = rep(c("2", "6"), each = 4),
                         espn_name = rep(c("r", "nf"), each = 4), position = "RB",
                         espn_proj = c(10, 12, 14, 16, 8, 8, 8, 8))
  cd <- tidyr::expand_grid(position = VAL_POSITIONS, bucket = c("h1", "h2_3", "h4_7", "h8p")) |>
    dplyr::mutate(c = 0, d = 1, q = 0, g = 0, a = 20, e = 0)
  list(
    season = 2026L, week = 5L, as_of = as.POSIXct("2026-10-07 12:00:00", tz = "UTC"),
    cfg = list(projection_sources = list(
      current_week = list(QB = "espn_calibrated", RB = "espn_calibrated", WR = "espn_calibrated", TE = "espn_calibrated"),
      future_weeks = list(QB = c("espn_posted_future", "extrapolated"), RB = c("espn_posted_future", "extrapolated"),
                          WR = c("espn_posted_future", "extrapolated"), TE = c("espn_posted_future", "extrapolated"))),
      pool = list(recent_weeks = 4)),
    rules = read_scoring_rules("espn_ppr", file.path(project_root, "config", "scoring")),
    capture = cap, capture_path = "toy_capture.parquet", team_games = tg, history = hist,
    player_stats = tibble::tibble(season = integer(), week = integer(), gsis_id = character(), team = character(),
                                  opponent = character(), stats_position = character(), fantasy_pts = double()),
    crosswalk = tibble::tibble(espn_id = unname(ids), gsis_id = paste0("g", unname(ids))),
    ros = list(version = "toy", form = "linear", cd_tab = cd, c0_tab = tibble::tibble(position = VAL_POSITIONS, c0 = 0.5, d0 = 0.9))
  )
}

test_that("ROS weekly table: current week calibrated, byes, posted zeros, extrapolation fallback", {
  ctx <- toy_ctx()
  pr <- val_build_weekly(ctx, 5:8)
  expect_silent(validate_projection_table(pr))
  g <- function(id, wk) pr[pr$player_id == id & pr$week == wk, ]
  # current week = c0 + d0 * ESPN
  expect_equal(g("g1", 5)$proj, 0.5 + 0.9 * 20)
  expect_equal(g("g1", 5)$proj_kind, "current_week")
  # AAA bye in week 6: no game, 0 points, for every AAA player
  expect_false(g("g1", 6)$has_game)
  expect_equal(g("g1", 6)$proj, 0)
  expect_equal(g("g2", 6)$proj, 0)
  # posted future week: E = X under the toy model (c = 0, d = 1), A ~ 1
  expect_equal(g("g1", 7)$proj, 20)
  expect_equal(g("g1", 7)$p_active, stats::plogis(20))
  expect_equal(g("g1", 7)$proj_kind, "posted_future")
  # injured WR: ESPN posts 0 in weeks 5-6 (game weeks) -> 0 only there, positive later
  expect_equal(g("g5", 5)$proj, 0)
  expect_equal(g("g5", 6)$proj, 0)
  expect_equal(g("g5", 6)$p_active, 0)
  expect_gt(g("g5", 7)$proj, 13)
  # no posted future weeks -> extrapolated from L_avg4 = mean(last 4 positive incl. current) = (8+8+8+9)/4
  expect_equal(g("g6", 7)$proj_kind, "extrapolated")
  expect_equal(g("g6", 7)$proj_raw, mean(c(8, 8, 8, 9)))
  # the extrapolated level for a player WITH history uses weeks <= current: (12+14+16+15)/4
  ctx2 <- ctx
  ctx2$capture <- dplyr::filter(ctx$capture, !(.data$espn_id == "2" & .data$week > 5))
  pr2 <- val_build_weekly(ctx2, 5:8)
  expect_equal(pr2$proj_raw[pr2$player_id == "g2" & pr2$week == 7], mean(c(12, 14, 16, 15)))
})

test_that("missing projections fall back to 0 and keep the table valid", {
  ctx <- toy_ctx()
  ctx$history <- ctx$history[0, ]
  ctx$capture <- dplyr::filter(ctx$capture, !(.data$espn_id == "6" & .data$week > 5))
  pr <- val_build_weekly(ctx, 5:8)
  expect_silent(validate_projection_table(pr))
  # nf has a current projection, so L = 9 and future weeks are extrapolated (not missing)
  expect_true(all(pr$proj[pr$player_id == "g6" & pr$week > 5 & pr$has_game] > 0))
  # a player present only in the current week with no history and no projection gets 0 later
  ctx$capture <- dplyr::bind_rows(ctx$capture, tibble::tibble(
    espn_id = "7", espn_name = "x", position = "TE", espn_pro_team_id = 2L, week = 5L, receptions = 0,
    injury_status = "ACTIVE", pct_owned = 1, pct_started = 0, team = "BBB", season = 2026L))
  ctx$history <- tibble::tibble(season = 2026L, week = 4L, espn_id = "7", espn_name = "x", position = "TE", espn_proj = 0)
  pr <- val_build_weekly(ctx, 5:8)
  expect_false("espn:7" %in% pr$player_id)  # never projected above 0: not in the pool
})

test_that("projection table validation catches bad rows", {
  pr <- val_build_weekly(toy_ctx(), 5:8)
  bad <- pr
  bad$proj[1] <- -1
  expect_error(validate_projection_table(bad))
  bad <- pr
  bad$proj[which(!bad$has_game)[1]] <- 5
  bad$lvl[which(!bad$has_game)[1]] <- 5
  bad$p_active[which(!bad$has_game)[1]] <- 1
  expect_error(validate_projection_table(bad), "without a game")
  expect_error(validate_projection_table(dplyr::bind_rows(pr, pr[1, ])), "duplicated")
})

test_that("scoring is configurable: ESPN stat lines are rescored under any rules", {
  d <- tibble::tibble(receptions = 5, receiving_yards = 50, receiving_tds = 1, passing_yards = 0, passing_tds = 0)
  ppr <- read_scoring_rules("espn_ppr", file.path(project_root, "config", "scoring"))
  half <- ppr
  half$weights[["receptions"]] <- 0.5
  expect_equal(val_rescore(d, ppr), 5 + 5 + 6)
  expect_equal(val_rescore(d, half), 2.5 + 5 + 6)
})

test_that("ESPN parser maps stat ids (return TDs share one stat) and sums per-game actuals", {
  json <- jsonlite::toJSON(list(players = list(list(player = list(
    id = 9, fullName = "Toy", defaultPositionId = 3, proTeamId = 2, injuryStatus = "ACTIVE",
    ownership = list(percentOwned = 50, percentStarted = 10),
    stats = list(
      list(seasonId = 2026, statSplitTypeId = 1, statSourceId = 1, scoringPeriodId = 5, appliedTotal = 18,
           stats = list(`53` = 5, `42` = 40, `101` = 0.5, `102` = 0.5)),
      list(seasonId = 2026, statSplitTypeId = 1, statSourceId = 0, scoringPeriodId = 4, appliedTotal = 3,
           stats = list(`53` = 3)),
      list(seasonId = 2026, statSplitTypeId = 1, statSourceId = 0, scoringPeriodId = 4, appliedTotal = 1,
           stats = list(`53` = 1)),
      list(seasonId = 2025, statSplitTypeId = 1, statSourceId = 1, scoringPeriodId = 5, appliedTotal = 99,
           stats = list(`53` = 99)))
  )))), auto_unbox = TRUE)
  x <- val_parse_espn(json, 2026)
  expect_equal(nrow(x), 2)
  p <- x[x$source == 1, ]
  expect_equal(p$special_teams_tds, 1)
  expect_equal(p$position, "WR")
  a <- x[x$source == 0, ]
  expect_equal(a$applied_total, 4)
  expect_equal(a$receptions, 4)
})

test_that("weekly VOR is floored at 0 per week; raw VOR and VAS are not", {
  lg <- val_toy_league()
  weekly <- tidyr::expand_grid(player_id = c("q1", "q2", "q3"), week = 5:6) |>
    dplyr::mutate(position = "QB", E = c(20, 0, 15, 15, 10, 10), has_game = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE),
                  A = 1, lvl = .data$E, proj_kind = "current_week", source = "toy")
  base <- val_weekly_baselines(weekly, lg, rostered = c("q1", "q2"))
  wv <- val_weekly_values(weekly, base)
  v <- val_player_values(wv, lg, 5)
  q1 <- v[v$player_id == "q1", ]
  expect_equal(base$R[base$position == "QB" & base$week == 5], 10)
  expect_equal(q1$vor, 10)            # week 5: 20 - 10; week 6 (bye): max(0, 0 - 10) = 0
  expect_equal(q1$vor_raw, 0)         # 10 + (-10)
  expect_equal(q1$games_remaining, 1)
  expect_equal(q1$bye_weeks, "6")
  expect_equal(q1$replacement_points, 10)  # baseline over the player's game weeks only
  # week 6: q1 on bye, so both other QBs start (2 teams) and S = 0 (no QB left)
  expect_equal(base$S[base$position == "QB" & base$week == 6], 0)
  expect_true(all(v$vor >= 0))
})

test_that("display scale is a monotone 0-100 transform of VOR", {
  set.seed(1)
  vor <- sort(stats::runif(60, 0, 150))
  mru <- 0.004 * vor^2 + stats::rnorm(60, 0, 2)  # convex with noise
  map <- val_fit_display_map(vor, mru)
  tv <- val_trade_value(vor, map)
  expect_equal(max(tv), 100)
  expect_true(all(diff(tv) >= -1e-9))
  expect_true(all(tv >= 0))
  expect_equal(val_trade_value(0, map), 0)
  # convexity emerges: half the top VOR gets well under half the display value
  expect_lt(val_trade_value(c(75, 150), map)[1], 40)
  # too few points: identity (linear) map
  lin <- val_fit_display_map(c(10, 20), c(5, 30))
  expect_equal(lin$type, "identity")
  expect_equal(val_trade_value(c(50, 100), lin), c(50, 100))
})

test_that("valuation archive is write-once, hash-manifested and verified", {
  root <- withr::local_tempdir()
  man <- file.path(root, "valuation_manifest.csv")
  res <- list(
    values = tibble::tibble(player_id = c("a", "b"), vor = c(10, 5)),
    weekly = tibble::tibble(player_id = "a", week = 5L, proj = 10),
    baselines = tibble::tibble(week = 5L, position = "QB", S = 1, R = 0),
    scarcity = tibble::tibble(position = "QB"), rosters = tibble::tibble(team = 1L, player_id = "a"),
    display_knots = tibble::tibble(vor = 0, mru = 0), sensitivity = NULL, consolidation = NULL,
    meta = list(run_id = "20261007T120000Z", season = 2026L, week = 5L, as_of_utc = "2026-10-07T12:00:00Z",
                methodology_version = "valuation_v1", league_hash = "h", n_players = 2L,
                provider_versions = list(espn_capture_sha256 = "x", m4_run_id = "r", ros_params_sha256 = "p"),
                git_commit = "c")
  )
  out <- val_archive_run(res, root, man)
  expect_true(file.exists(file.path(out$dir, "values.parquet")))
  v <- verify_valuation_archive(man, root)
  expect_true(v$verified)
  latest <- latest_valuation_run(manifest = man, root = root)
  expect_equal(latest$run_id, "20261007T120000Z")
  expect_equal(latest$values$vor, c(10, 5))
  expect_error(val_archive_run(res, root, man), "immutable")
  # tampering is detected
  arrow::write_parquet(tibble::tibble(player_id = "a", vor = 99), file.path(out$dir, "values.parquet"))
  expect_false(verify_valuation_archive(man, root)$verified)
  expect_null(latest_valuation_run(manifest = man, root = root))
})

test_that("the archived M4 run is used only when it matches its manifest hash", {
  root <- withr::local_tempdir()
  dir <- file.path(root, "season=2026", "week=05", "run=20261006T000000Z")
  dir.create(dir, recursive = TRUE)
  p <- file.path(dir, "predictions.parquet")
  arrow::write_parquet(tibble::tibble(model_id = "m4_two_stage_v1", gsis_id = "g3", pred = 11, espn_proj = 12), p)
  man <- file.path(root, "m.csv")
  readr::write_csv(tibble::tibble(run_id = "20261006T000000Z", season = 2026, week = 5, lineages = "m1+m4",
                                  predicted_at_utc = "2026-10-06T00:00:00Z", predictions_sha256 = sha256_file(p),
                                  snapshot_captured_at_utc = "2026-10-05T23:00:00Z"), man)
  r <- val_latest_m4_run(2026, 5, as.POSIXct("2026-10-07", tz = "UTC"), man, root)
  expect_equal(r$run_id, "20261006T000000Z")
  expect_null(val_latest_m4_run(2026, 5, as.POSIXct("2026-10-05", tz = "UTC"), man, root))  # run is after as_of
  arrow::write_parquet(tibble::tibble(model_id = "m4_two_stage_v1", gsis_id = "g3", pred = 30, espn_proj = 12), p)
  expect_error(val_latest_m4_run(2026, 5, as.POSIXct("2026-10-07", tz = "UTC"), man, root), "does not match")
})

test_that("ROS fit recovers a known linear relation and buckets horizons", {
  expect_equal(val_h_bucket(c(1, 2, 3, 4, 7, 8, 13)), c("h1", "h2_3", "h2_3", "h4_7", "h4_7", "h8p", "h8p"))
  set.seed(2)
  fut <- tidyr::expand_grid(position = VAL_POSITIONS, h = 1:10, i = 1:60) |>
    dplyr::mutate(season = 2020L, L_avg4 = stats::runif(dplyr::n(), 2, 20), bucket = val_h_bucket(.data$h),
                  opp = 1, active = TRUE, pts = 1 + 0.8 * .data$L_avg4)
  fit <- val_fit_ros(fut, "L_avg4", 2020, form = "linear")
  expect_equal(unique(round(fit$cd$c, 6)), 1)
  expect_equal(unique(round(fit$cd$d, 6)), 0.8)
  pr <- val_predict_ros(fut, fit)
  expect_equal(pr$E, fut$pts, tolerance = 1e-8)
  expect_equal(pr$E, pr$A * pr$lvl, tolerance = 1e-8)
})
