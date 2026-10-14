# F4 position-general frame (master plan F4). Synthetic data only.

pwa_comp_fixture <- function(rows) {
  out <- tibble::as_tibble(rows)
  for (nm in names(PWA_COMPONENT_IDS)) {
    col <- paste0("espn_proj_", nm)
    if (!col %in% names(out)) out[[col]] <- 0
  }
  out
}

pwa_tiny <- function() {
  sched <- tibble::tibble(season = 2019L, week = 1:3, game_id = paste0("2019_0", 1:3, "_AAA_BBB"))
  team_games <- dplyr::bind_rows(
    dplyr::mutate(sched, team = "BBB", opponent = "AAA", home = TRUE, team_spread = 3),
    dplyr::mutate(sched, team = "AAA", opponent = "BBB", home = FALSE, team_spread = -3)
  ) |>
    dplyr::mutate(kickoff = paste0("2019-09-0", week, " 13:00"),
                  kickoff_utc = as.POSIXct(paste0("2019-09-0", week, " 17:00"), tz = "UTC"),
                  total_line = 44, implied_team_total = (44 + team_spread) / 2, rest_days = 7, roof = "outdoors",
                  game_index = game_index(season, week))
  wk <- function(w) tibble::tibble(season = 2019L, week = w)
  espn_weekly <- dplyr::bind_rows(
    tibble::tibble(espn_id = "10", espn_name = "w1", espn_position_id = 3L, espn_proj = 12, espn_actual = c(15, 9, 0),
                   espn_proj_receptions = 5, espn_proj_targets = 8, espn_proj_receiving_yards = 60,
                   espn_proj_receiving_tds = 0.4, espn_proj_rushing_attempts = 0, espn_proj_rushing_yards = 0) |>
      dplyr::bind_cols(wk(1:3)),
    # an RB-default player inside the WR file: supplied by the RB history instead
    tibble::tibble(espn_id = "20", espn_name = "w2", espn_position_id = 2L, espn_proj = 7, espn_actual = 6,
                   espn_proj_receptions = 2, espn_proj_targets = 3, espn_proj_receiving_yards = 15,
                   espn_proj_receiving_tds = 0.1, espn_proj_rushing_attempts = 5, espn_proj_rushing_yards = 20) |>
      dplyr::bind_cols(wk(1))
  ) |> dplyr::mutate(espn_pro_team_id = 1L)
  val_espn_hist <- dplyr::bind_rows(
    tibble::tibble(espn_id = "30", espn_name = "q1", position = "QB", espn_proj = 18, espn_actual = c(20.04, 14, 30)) |>
      dplyr::bind_cols(wk(1:3)),
    tibble::tibble(espn_id = "20", espn_name = "w2", position = "RB", espn_proj = 9, espn_actual = 6) |> dplyr::bind_cols(wk(1)),
    tibble::tibble(espn_id = "10", espn_name = "w1", position = "WR", espn_proj = 99, espn_actual = 99) |> dplyr::bind_cols(wk(1))
  ) |> dplyr::mutate(espn_pro_team_id = 1L, espn_actual_n_stats = 3)
  components <- pwa_comp_fixture(list(season = 2019L, week = c(1L, 2L, 3L, 1L, 1L), espn_id = c("30", "30", "30", "20", "10"),
                                      espn_proj_passing_yards = c(250, 240, 260, 0, 0), espn_proj_receptions = c(0, 0, 0, 2, 5),
                                      espn_proj_targets = c(0, 0, 0, 3, 8), espn_proj_receiving_yards = c(0, 0, 0, 15, 60),
                                      espn_proj_receiving_tds = c(0, 0, 0, 0.1, 0.4), espn_proj_rushing_attempts = c(3, 3, 3, 5, 0),
                                      espn_proj_rushing_yards = c(10, 10, 10, 20, 0)))
  cw <- tibble::tibble(espn_id = c("10", "20"), gsis_id = c("w1", "w2"), match_method = "roster_espn_id")
  vcw <- tibble::tibble(espn_id = c("20", "30"), gsis_id = c("w2", "q1"), match_method = "name")
  stat <- function(id, team, opp, w, pts) {
    tibble::tibble(season = 2019L, week = w, gsis_id = id, player_name = id, stats_position = "X", team = team,
                   opponent = opp, fantasy_pts = pts, targets = 1, receptions = 1, receiving_yards = 10, receiving_tds = 0)
  }
  player_stats <- dplyr::bind_rows(
    stat("q1", "AAA", "BBB", 1:3, c(20.04, 14, 30)) |> dplyr::mutate(stats_position = "QB"),
    stat("w1", "BBB", "AAA", 1:2, c(15, 9)) |> dplyr::mutate(stats_position = "WR"),
    stat("w2", "AAA", "BBB", 1, 6) |> dplyr::mutate(stats_position = "RB")
  )
  roster <- function(id, team, pos, w, status = "ACT") {
    tibble::tibble(season = 2019L, week = w, gsis_id = id, roster_name = id, roster_team = team, roster_position = pos,
                   roster_status = status)
  }
  rosters <- dplyr::bind_rows(roster("q1", "AAA", "QB", 1:3), roster("w1", "BBB", "WR", 1:3, c("ACT", "ACT", "INA")),
                              roster("w2", "AAA", "RB", 1), roster("t1", "BBB", "TE", 1:3))
  injuries <- tibble::tibble(season = 2019L, week = 2L, gsis_id = "w1", report_status = "Questionable")
  injury_detail <- tibble::tibble(season = 2019L, week = 2L, team = "BBB", gsis_id = "w1", position = "WR",
                                  designation = "Questionable", practice = "LP", body = "lower",
                                  known_at = as.POSIXct("2019-09-01 20:00", tz = "UTC"))
  snaps <- tibble::tibble(season = 2019L, week = c(1L, 2L, 3L, 1L, 2L), gsis_id = c("q1", "q1", "q1", "w1", "w1"),
                          snap_team = c("AAA", "AAA", "AAA", "BBB", "BBB"), offense_snaps = c(60, 62, 58, 40, 0),
                          snap_share = c(1, 1, 1, 0.6, 0))
  list(team_games = team_games, espn_weekly = espn_weekly, val_espn_hist = val_espn_hist, components = components, cw = cw,
       vcw = vcw, player_stats = player_stats, rosters = rosters, injuries = injuries, injury_detail = injury_detail,
       snaps = snaps)
}

pwa_tiny_frame <- function(x = pwa_tiny()) {
  build_player_week_all(x$espn_weekly, x$val_espn_hist, x$components, x$cw, x$vcw, x$player_stats, x$rosters,
                        x$team_games, x$injuries, x$injury_detail, x$snaps, seasons = 2019L, asof_root = tempfile())
}

test_that("components are parsed from the week's projection entry only, and duplicates fail", {
  dir <- tempfile()
  dir.create(dir)
  entry <- function(src, period, stats, split = 1) {
    list(seasonId = 2024, scoringPeriodId = period, statSplitTypeId = split, statSourceId = src, appliedTotal = 1,
         stats = stats)
  }
  doc <- list(players = list(
    list(player = list(id = 1, stats = list(entry(1, 5, list(`53` = 5, `58` = 7, `3` = 250)), entry(0, 5, list(`53` = 9)),
                                            entry(1, 6, list(`53` = 1)), entry(1, 5, list(`53` = 4), split = 0)))),
    list(player = list(id = 2, stats = list(entry(0, 5, list(`53` = 3)))))
  ))
  p <- file.path(dir, "espn_qbrbte_2024_w05.json.gz")
  write_gz_text(p, jsonlite::toJSON(doc, auto_unbox = TRUE))
  out <- pwa_parse_components(p)
  expect_equal(nrow(out), 1)
  expect_equal(out$espn_id, "1")
  expect_equal(c(out$season, out$week), c(2024L, 5L))
  expect_equal(out$espn_proj_receptions, 5)
  expect_equal(out$espn_proj_targets, 7)
  expect_equal(out$espn_proj_passing_yards, 250)
  expect_equal(out$espn_proj_rushing_tds, 0)                    # absent stat in a present projection = 0
  doc$players[[1]]$player$stats <- c(doc$players[[1]]$player$stats, list(entry(1, 5, list(`53` = 6))))
  write_gz_text(p, jsonlite::toJSON(doc, auto_unbox = TRUE))
  expect_error(pwa_parse_components(p), "projection entries")
})

test_that("WR rows come from the frozen WR source and QB/RB/TE rows from the valuation history", {
  x <- pwa_tiny()
  e <- pwa_espn_all(x$espn_weekly, x$val_espn_hist, x$components, seasons = 2019L)
  expect_equal(nrow(e), 7)                                      # 3 WR + 3 QB + 1 RB; the WR file's RB-default row dropped
  expect_equal(e$espn_proj[e$espn_id == "10"], c(12, 12, 12))   # not the valuation history's WR value (99)
  expect_equal(e$espn_proj[e$espn_id == "20"], 9)               # the RB history, not the WR file's RB-default row
  expect_equal(e$espn_proj_passing_yards[e$espn_id == "30"], c(250, 240, 260))
  expect_equal(e$espn_proj_passing_yards[e$espn_id == "10" & e$week == 1], 0)
  expect_equal(e$espn_proj_receptions[e$espn_id == "10"], c(5, 5, 5))   # frozen WR components kept
  cw <- pwa_crosswalk(x$cw, x$vcw)
  expect_equal(nrow(cw), 3)
  expect_equal(cw$match_method[cw$espn_id == "20"], "roster_espn_id")   # the WR crosswalk wins on shared ids
  chk <- pwa_check_components(x$espn_weekly, x$components, seasons = 2019L)
  expect_equal(chk$matched, 1)
  expect_equal(chk$differing, 0)
})

test_that("previous-game snaps skip byes, read a missing record as 0, and are NA in the first game", {
  tg <- tibble::tibble(season = 2020L, week = c(1L, 2L, 4L), team = "AAA")
  fr <- tibble::tibble(season = 2020L, week = c(1L, 2L, 4L), team = "AAA", gsis_id = "p")
  sn <- tibble::tibble(season = 2020L, week = 1L, gsis_id = "p", offense_snaps = 30)
  out <- pwa_prev_snaps(fr, sn, tg)
  expect_equal(out$prev_week, c(NA, 1L, 2L))
  expect_equal(out$prev_offense_snaps, c(NA, 30, 0))
})

test_that("role ranks follow the position depth and ignore unprojected rows", {
  fr <- tibble::tibble(season = 2020L, week = 3L, team = "AAA",
                       position = c("WR", "WR", "WR", "WR", "QB", "QB", "TE"),
                       espn_proj = c(10, 8, 6, 4, 18, 2, NA), pop_espn = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
                       prev_offense_snaps = c(50, 60, 0, NA, 70, 0, 30))
  out <- pwa_role_ranks(fr)
  expect_equal(out$role, c("WR1", "WR2", "WR3", "WR_depth", "QB1", "QB_depth", NA))
  expect_equal(out$role_rank_prev, c(2, 1, 3, NA, 1, 2, 1))
  expect_equal(out$role_prev, c("WR2", "WR1", "WR3", NA, "QB1", "QB_depth", "TE1"))
})

test_that("as-of lines take the designated home team from the game id, also at neutral sites", {
  root <- tempfile()
  dir.create(root)
  asof <- function(game_id, spread, total, hq, aq) {
    tibble::tibble(game_id = game_id, kickoff_utc = as.POSIXct("2021-10-10 17:00", tz = "UTC"),
                   cutoff_utc = as.POSIXct("2021-10-10 15:00", tz = "UTC"), spread_line = spread, total_line = total,
                   home_qb_id = hq, away_qb_id = aq, home_qb_name = "h", away_qb_name = "a", commit_sha = "abc",
                   committed_utc = as.POSIXct("2021-10-10 14:50", tz = "UTC"))
  }
  arrow::write_parquet(asof("2021_05_DAL_TB", 7, 50, "qtb", "qdal"), file.path(root, "asof_kickoff_minus_2h_2021.parquet"))
  arrow::write_parquet(asof("2021_05_NYJ_ATL", 3, 46, "qatl", "qnyj"),
                       file.path(root, "asof_kickoff_minus_2h_neutral_2021.parquet"))
  tg <- tibble::tibble(season = 2021L, week = 5L, game_id = rep(c("2021_05_DAL_TB", "2021_05_NYJ_ATL"), each = 2),
                       team = c("TB", "DAL", "ATL", "NYJ"), home = c(TRUE, FALSE, FALSE, FALSE),
                       kickoff_utc = as.POSIXct("2021-10-10 17:00", tz = "UTC"))
  out <- dplyr::arrange(pwa_asof_lines(tg, 2021, root = root), match(team, tg$team))
  expect_equal(out$asof_spread, c(7, -7, 3, -3))
  expect_equal(out$asof_implied_total, c(28.5, 21.5, 24.5, 21.5))
  expect_equal(out$asof_expected_qb_id, c("qtb", "qdal", "qatl", "qnyj"))
  unlink(file.path(root, "asof_kickoff_minus_2h_neutral_2021.parquet"))
  expect_error(pwa_asof_lines(tg, 2021, root = root, dir = file.path(root, "no_clone")), "No local nfldata clone")
  expect_equal(nrow(pwa_asof_lines(tg, 2022, root = root)), 0)           # no E11 cache: no lines
})

test_that("the scoring criterion counts rows without a stat line as 0 points", {
  fr <- tibble::tibble(position = c("QB", "QB", "QB", "WR"), actual = c(20.04, 0, 7, 3), espn_actual = c(20.04, 0, 7.5, NA),
                       has_stat_line = c(TRUE, FALSE, TRUE, TRUE))
  out <- pwa_scoring_match(fr)
  expect_equal(out$rows, 3)
  expect_equal(out$mismatches, 1)
  expect_equal(out$match_share, 2 / 3)
  expect_equal(out$match_share_stat_line, 1 / 2)
})

test_that("the WR reproduction check allows only ESPN-position reassignments", {
  old <- tibble::tibble(season = 2020L, week = 1L, gsis_id = c("a", "b", "c"), has_game = TRUE, espn_proj = c(10, NA, 5),
                        espn_position = c("WR", NA, "WR"), position = c("WR", "WR", "WR"), actual = c(1, 2, 3),
                        player_name = c("a", "b", "c"))
  new <- dplyr::mutate(old, espn_proj = c(10, 7, 5), espn_position = c("WR", "RB", "WR"), position = c("WR", "RB", "WR"))
  ok <- pwa_check_wr_reproduction(new, old, seasons = 2020L)
  expect_true(ok$pass)
  expect_equal(ok$rows_reassigned, 1)
  bad <- new
  bad$actual[1] <- 9
  expect_false(pwa_check_wr_reproduction(bad, old, seasons = 2020L)$pass)
  expect_equal(pwa_check_wr_reproduction(new[-3, ], old, seasons = 2020L)$missing_in_new, 1)
  extra <- dplyr::bind_rows(new, dplyr::mutate(new[1, ], gsis_id = "d"))
  expect_equal(pwa_check_wr_reproduction(extra, old, seasons = 2020L)$new_wr_rows, 1)
})

test_that("the frame is built end to end with one row per player-week and pregame-only features", {
  x <- pwa_tiny()
  fr <- pwa_tiny_frame(x)
  expect_equal(nrow(fr), 10)                                    # q1, w1, t1 weeks 1-3 + w2 week 1
  expect_setequal(unique(fr$gsis_id), c("q1", "w1", "w2", "t1"))
  w2 <- fr[fr$gsis_id == "w2", ]
  expect_equal(w2$position, "RB")
  expect_equal(w2$espn_proj, 9)
  w1 <- fr[fr$gsis_id == "w1", ]
  expect_equal(w1$espn_proj, c(12, 12, 12))
  expect_equal(w1$actual, c(15, 9, 0))
  expect_equal(w1$active, c(TRUE, FALSE, FALSE))                # week 2: snap record with 0 snaps
  expect_equal(w1$designation, c("none", "Questionable", "none"))
  expect_equal(w1$prev_offense_snaps, c(NA, 40, 0))
  q1 <- fr[fr$gsis_id == "q1", ]
  expect_equal(q1$espn_proj_passing_yards, c(250, 240, 260))
  expect_equal(q1$base, q1$espn_proj)                           # fewer than 200 training rows: identity base
  expect_equal(q1$role, rep("QB1", 3))
  expect_true(all(fr$espn_horizon == "late"))
  expect_false(any(fr$asof_available))
  expect_true(all(!is.na(fr$kickoff_utc)))
  t1 <- fr[fr$gsis_id == "t1", ]
  expect_false(any(t1$pop_espn))
  expect_true(all(is.na(t1$role)))
  sm <- pwa_scoring_match(fr)
  expect_true(all(sm$match_share == 1))
})

test_that("the leakage check passes on a clean frame and flags as-of lines committed after the cutoff", {
  x <- pwa_tiny()
  fr <- pwa_tiny_frame(x)
  fr$asof_cutoff_utc <- fr$kickoff_utc - 7200
  fr$asof_committed_utc <- fr$asof_cutoff_utc - 60
  expect_equal(pwa_check_leakage(fr, x$snaps, x$team_games, weeks = c(201902L, 201903L)), character(0))
  fr$asof_committed_utc[1] <- fr$asof_cutoff_utc[1] + 60
  expect_equal(pwa_check_leakage(fr, x$snaps, x$team_games, weeks = 201902L), "asof_lines")
})
