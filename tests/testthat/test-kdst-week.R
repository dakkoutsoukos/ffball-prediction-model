# F4 part 2: K and D/ST statistics and league points. Synthetic data only.

kdst_play <- function(...) {
  base <- list(season = 2022L, season_type = "REG", week = 3L, game_id = "2022_03_PHI_DAL", posteam = NA_character_,
               defteam = NA_character_, play_type = NA_character_, td_team = NA_character_, touchdown = 0, interception = 0,
               sack = 0, safety = 0, punt_blocked = 0, field_goal_result = NA_character_, extra_point_result = NA_character_,
               fumbled_1_team = NA_character_, fumble_recovery_1_team = NA_character_, fumbled_2_team = NA_character_,
               fumble_recovery_2_team = NA_character_, defensive_two_point_conv = 0, defensive_extra_point_conv = 0,
               two_point_attempt = 0, extra_point_attempt = 0, yards_gained = 0, kick_distance = NA_real_,
               kicker_player_id = NA_character_, total_home_score = 0, total_away_score = 0, home_team = "DAL",
               away_team = "PHI")
  tibble::as_tibble(utils::modifyList(base, list(...)))
}

kdst_toy_pbp <- function() {
  dplyr::bind_rows(
    kdst_play(play_type = "pass", posteam = "DAL", defteam = "PHI", sack = 1, yards_gained = -7),
    kdst_play(play_type = "pass", posteam = "DAL", defteam = "PHI", interception = 1, touchdown = 1, td_team = "PHI"),
    kdst_play(play_type = "run", posteam = "PHI", defteam = "DAL", yards_gained = 12),
    kdst_play(play_type = "punt", posteam = "DAL", defteam = "PHI", touchdown = 1, td_team = "PHI"),
    kdst_play(play_type = "kickoff", posteam = "PHI", defteam = "DAL", fumbled_1_team = "PHI", fumble_recovery_1_team = "DAL"),
    kdst_play(play_type = "field_goal", posteam = "PHI", defteam = "DAL", field_goal_result = "blocked", kick_distance = 45),
    kdst_play(play_type = "run", posteam = "PHI", defteam = "DAL", safety = 1, yards_gained = -2),
    kdst_play(play_type = "pass", posteam = "DAL", defteam = "PHI", two_point_attempt = 1, yards_gained = 3),
    kdst_play(play_type = "extra_point", posteam = "DAL", defteam = "PHI", defensive_extra_point_conv = 1,
              extra_point_attempt = 1),
    # the defense intercepts, fumbles, and the offense recovers: not a D/ST recovery for anyone
    kdst_play(play_type = "pass", posteam = "PHI", defteam = "DAL", interception = 1, fumbled_1_team = "DAL",
              fumble_recovery_1_team = "PHI", total_home_score = 10, total_away_score = 20)
  )
}

kdst_toy_sched <- function() {
  tibble::tibble(season = 2022L, week = 3L, game_id = "2022_03_PHI_DAL", game_type = "REG", home_team = "DAL",
                 away_team = "PHI", home_score = 10, away_score = 20)
}

kdst_settings <- function(extra = list()) {
  item <- function(id, pts, dst = NULL) {
    c(list(statId = id, points = pts), if (!is.null(dst)) list(pointsOverrides = list(`16` = dst)))
  }
  list(scoringSettings = list(scoringItems = c(list(
    item(3, 0.04), item(80, 3), item(77, 4), item(85, -1), item(86, 1), item(201, 6),
    item(89, 0, 5), item(92, 0, 1), item(99, 0, 1), item(95, 0, 2), item(96, 0, 2), item(98, 0, 2), item(97, 0, 2),
    item(102, 6, 6), item(103, 6, 6), item(206, 2, 2), item(123, 0, -1), item(128, 0, 5), item(130, 0, 2)
  ), extra)))
}

test_that("tiers are one-hot with inclusive upper bounds", {
  pa <- kdst_tiers(c(0, 1, 6, 7, 45, 46, NA), KDST_PA_TIERS)
  expect_equal(pa$pa_0, c(1, 0, 0, 0, 0, 0, 0))
  expect_equal(pa$pa_1_6, c(0, 1, 1, 0, 0, 0, 0))
  expect_equal(pa$pa_7_13, c(0, 0, 0, 1, 0, 0, 0))
  expect_equal(pa$pa_35_45, c(0, 0, 0, 0, 1, 0, 0))
  expect_equal(pa$pa_46p, c(0, 0, 0, 0, 0, 1, 0))
  expect_equal(rowSums(pa), c(1, 1, 1, 1, 1, 1, 0))
  ya <- kdst_tiers(c(-5, 99, 100, 550), KDST_YA_TIERS)
  expect_equal(ya$ya_0_99, c(1, 1, 0, 0))
  expect_equal(ya$ya_100_199, c(0, 0, 1, 0))
  expect_equal(ya$ya_550p, c(0, 0, 0, 1))
})

test_that("D/ST statistics credit the right unit and exclude pick-sixes from points allowed", {
  d <- kdst_dst_stats(kdst_toy_pbp(), kdst_toy_sched())
  a <- d[d$team == "DAL", ]
  b <- d[d$team == "PHI", ]
  expect_equal(nrow(d), 2)
  expect_equal(c(a$sacks, a$interceptions, a$safeties, a$blocked_kicks, a$fumble_recoveries), c(0, 1, 1, 1, 1))
  expect_equal(a$yards_allowed, 10)                              # PHI's runs: 12 - 2
  expect_equal(c(a$points_allowed, a$points_allowed_total, a$pa_14_17), c(14, 20, 1))   # 20 - one pick-six
  expect_equal(c(b$sacks, b$interceptions, b$int_return_td, b$punt_return_td, b$two_pt_return), c(1, 1, 1, 1, 1))
  expect_equal(b$fumble_recoveries, 0)                           # recovering its own side's fumble does not count
  expect_equal(b$yards_allowed, -7)                              # the two-point try is excluded
  expect_equal(c(b$points_allowed, b$pa_7_13, b$ya_0_99), c(10, 1, 1))
  expect_equal(c(b$def_td, b$def_st_td), c(1, 2))
})

test_that("kicks and return touchdowns follow nflverse's possession conventions", {
  p <- dplyr::bind_rows(
    kdst_play(play_type = "kickoff", posteam = "DAL", defteam = "PHI", touchdown = 1, td_team = "DAL"),
    kdst_play(play_type = "punt", posteam = "PHI", defteam = "DAL", punt_blocked = 1, touchdown = 1, td_team = "DAL"),
    kdst_play(play_type = "punt", posteam = "DAL", defteam = "PHI", touchdown = 1, td_team = "DAL",
              fumbled_1_team = "PHI", fumble_recovery_1_team = "DAL"),
    kdst_play(play_type = "run", posteam = "PHI", defteam = "DAL", touchdown = 1, td_team = "DAL",
              fumbled_1_team = "PHI", fumble_recovery_1_team = "DAL")
  )
  a <- kdst_dst_stats(p, kdst_toy_sched())
  a <- a[a$team == "DAL", ]
  expect_equal(c(a$kick_return_td, a$blocked_kick_return_td, a$fumble_return_td, a$blocked_kicks), c(1, 1, 2, 1))
  expect_equal(a$fumble_recoveries, 2)                           # a muffed punt and a scrimmage fumble
  expect_equal(a$def_td, 2)
})

test_that("league rules use D/ST overrides, ignore skill items and refuse unmapped K/DST items", {
  r <- kdst_rules_from_settings(kdst_settings())
  expect_false("3" %in% r$stat_id)
  expect_equal(r$points_dst[r$stat == "pa_0"], 5)
  expect_equal(r$points_k[r$stat == "pa_0"], 0)
  expect_equal(r$points_dst[r$stat == "punt_return_td"], 6)
  expect_equal(r$points_k[r$stat == "fg_made_0_39"], 3)
  expect_error(kdst_rules_from_settings(kdst_settings(list(list(statId = 137, points = 0, pointsOverrides = list(`16` = 1))))),
               "Unmapped")
  expect_silent(kdst_rules_from_settings(kdst_settings(list(list(statId = 137, points = 0)))))   # scores nothing
})

test_that("points use only the unit's own statistics", {
  r <- kdst_rules_from_settings(kdst_settings())
  k <- tibble::tibble(fg_made_0_39 = 2, fg_made_40_49 = 1, fg_made_60p = 1, fg_missed = 1, pat_made = 3)
  for (s in setdiff(KDST_K_STATS, names(k))) k[[s]] <- 0
  expect_equal(kdst_points(k, r, "K"), 2 * 3 + 4 + 6 - 1 + 3)
  d <- kdst_dst_stats(kdst_toy_pbp(), kdst_toy_sched())
  pts <- kdst_points(d, r, "DST")                                 # base points of kicking items do not reach the D/ST
  a <- d$team == "DAL"
  # DAL: INT 2 + fumble recovery 2 + safety 2 + blocked kick 2 + PA 14-17 (1) + YA 0-99 (5)
  expect_equal(pts[a], 2 + 2 + 2 + 2 + 1 + 5)
  expect_error(kdst_points(dplyr::select(d, -"sacks"), r, "DST"), "missing")
  w <- kdst_dst_week(d, r)
  expect_equal(w$dst_points[a], pts[a])
  expect_equal(w$dst_points_pa_total[a], pts[a] - 1)             # 20 allowed is the 18-21 tier, worth 0 here
})

test_that("team K points are summed over kickers and are 0 without a kicker line", {
  kw <- tibble::tibble(season = 2022L, week = 3L, team = c("DAL", "DAL"), k_points = c(5, 2))
  tg <- tibble::tibble(season = 2022L, week = 3L, team = c("DAL", "PHI"), opponent = c("PHI", "DAL"), game_id = "g")
  out <- kdst_team_k(kw, tg, seasons = 2022L)
  expect_equal(out$k_points, c(7, 0))
  expect_equal(out$kickers, c(2L, 0L))
})
