test_that("trailing_mean includes the current value and handles short windows and NAs", {
  expect_equal(trailing_mean(c(1, 2, 3, 4), 2), c(1, 1.5, 2.5, 3.5))
  expect_equal(trailing_mean(c(1, 2, 3), 8), c(1, 1.5, 2))
  expect_equal(trailing_mean(c(NA, 2, NA, 4), 2), c(NA, 2, 2, 4))
  expect_equal(trailing_mean(c(NA, NA), 3), c(NA_real_, NA_real_))
})

test_that("asof_join uses only strictly earlier states", {
  targets <- tibble::tibble(id = "a", game_index = c(202401L, 202402L, 202403L))
  states <- tibble::tibble(id = "a", state_index = c(202401L, 202402L), x = c(10, 20))
  out <- asof_join(targets, states, by = "id")
  expect_equal(out$x, c(NA, 10, 20))   # week 2 sees week 1 only, never week 2
})

test_that("asof_join refuses duplicated states", {
  targets <- tibble::tibble(id = "a", game_index = 202403L)
  states <- tibble::tibble(id = "a", state_index = c(202401L, 202401L), x = 1:2)
  expect_error(asof_join(targets, states, by = "id"), "duplicated")
})

test_that("rolling features use prior games only", {
  f <- toy_features()
  p1 <- dplyr::filter(f, gsis_id == "p1", season == 2023L)
  # p1 scores 10, 20, 30, 40 in 2023 weeks 1-4
  expect_true(is.na(p1$fantasy_pts_roll3[p1$week == 1]))
  expect_equal(p1$fantasy_pts_roll3[p1$week == 2], 10)
  expect_equal(p1$fantasy_pts_roll3[p1$week == 4], 20)       # mean(10, 20, 30)
  expect_equal(p1$season_pts_mean[p1$week == 4], 20)
  expect_equal(p1$career_games[p1$week == 4], 3L)
})

test_that("season boundaries: season-to-date resets, trailing windows carry over", {
  f <- toy_features()
  wk1 <- dplyr::filter(f, gsis_id == "p1", season == 2024L, week == 1L)
  expect_true(is.na(wk1$season_pts_mean))
  expect_equal(wk1$season_games, 0L)
  expect_equal(wk1$fantasy_pts_roll3, mean(c(20, 30, 40)))
  expect_equal(wk1$prev_season_pts_mean, 25)
})

test_that("missed games are visible pregame and do not leak", {
  f <- toy_features()
  # p1 missed 2024 week 2. The toy 2024 schedule has a bye in week 3, so AAA's
  # game before week 4 is week 2: in week 4, p1 did not play the team's previous game.
  wk2 <- dplyr::filter(f, gsis_id == "p1", season == 2024L, week == 2L)
  expect_true(wk2$played_team_prev_game)          # played week 1
  wk4 <- dplyr::filter(f, gsis_id == "p1", season == 2024L, week == 4L)
  expect_false(wk4$played_team_prev_game)         # missed week 2
  expect_equal(wk4$fantasy_pts_roll3, mean(c(30, 40, 110)))
})

test_that("players with no history get NA features and has_history = FALSE", {
  f <- toy_features()
  p2 <- dplyr::filter(f, gsis_id == "p2", season == 2024L, week == 1L)
  expect_false(p2$has_history)
  expect_true(is.na(p2$fantasy_pts_roll8))
  p3 <- dplyr::filter(f, gsis_id == "p3", season == 2024L, week == 2L)
  expect_true(p3$has_history)                       # snap-only appearance counts
  expect_equal(p3$fantasy_pts_roll3, 0)
})

test_that("team and opponent context are lagged", {
  f <- toy_features()
  wk1 <- dplyr::filter(f, gsis_id == "p1", season == 2023L, week == 1L)
  expect_true(is.na(wk1$team_pass_att_roll8))
  expect_true(is.na(wk1$opp_pts_allowed_roll))
  wk2 <- dplyr::filter(f, gsis_id == "p2", season == 2024L, week == 2L)
  # AAA defense allowed p2's 5 points per game; week-2 state sees 2023 + 2024 wk1
  expect_false(is.na(wk2$opp_pts_allowed_roll))
})

test_that("corrupting same-week and future outcomes never changes a week's features", {
  inp <- toy_inputs()
  leaks <- check_feature_leakage(
    toy_targets(inp), inp$player_games, inp$team_volume, inp$defense_allowed,
    inp$team_games, n_cutoffs = 100
  )
  expect_identical(leaks, character(0))
})

test_that("the leakage check catches deliberately leaky features", {
  inp <- toy_inputs()
  leaky <- function(targets, player_games, ...) {
    same_week <- dplyr::select(player_games, season, week, gsis_id, same_week_pts = fantasy_pts)
    season_total <- player_games |>
      dplyr::summarise(full_season_mean = mean(fantasy_pts), .by = c(gsis_id, season))
    add_point_in_time_features(targets, player_games, ...) |>
      dplyr::left_join(same_week, by = c("season", "week", "gsis_id")) |>
      dplyr::left_join(season_total, by = c("gsis_id", "season"))
  }
  leaks <- check_feature_leakage(
    toy_targets(inp), inp$player_games, inp$team_volume, inp$defense_allowed,
    inp$team_games, n_cutoffs = 100, feature_fn = leaky
  )
  expect_setequal(leaks, c("same_week_pts", "full_season_mean"))
})
