test_that("role-change rule applies fixed signed adjustments at fixed thresholds", {
  nd <- tibble::tibble(xfp_trend = c(2, 1.42, 0, -1.65, -3, NA))
  expect_equal(rule_role_change(nd, "xfp_trend", 1.42, -1.65, -0.3, 0.25),
               c(-0.3, -0.3, 0, 0.25, 0.25, 0))
})

test_that("return rule distinguishes one and several missed games", {
  nd <- tibble::tibble(team_games_missed = c(NA, 0L, 1L, 2L, 5L))
  expect_equal(rule_return(nd, -0.2, -0.4), c(0, 0, -0.2, -0.4, -0.4))
})

test_that("adjusted spec = calibrated ESPN + adjustment, nothing learned from the adjustment", {
  d <- tibble::tibble(season = 2022L, week = 1:200 %% 17 + 1L, espn_proj = runif(200, 1, 20),
                      xfp_trend = rep(c(2, 0), 100))
  for (c in setdiff(ESPN_COMPONENTS, "espn_proj")) d[[c]] <- d$espn_proj / 10
  d$actual <- d$espn_proj + rnorm(200)
  base <- spec_cal("linear")
  adj <- spec_adjusted("a", base, list(function(nd) rule_role_change(nd, "xfp_trend", 1.42, -1.65, -0.3, 0.25)))
  p_base <- base$predict(base$fit(d), d)
  p_adj <- adj$predict(adj$fit(d), d)
  expect_equal(p_adj - p_base, ifelse(d$xfp_trend >= 1.42, -0.3, 0))
})

test_that("team games missed counts only schedule games between the last appearance and the target", {
  tg <- tibble::tibble(season = 2024L, week = c(1:4, 6L), team = "AAA")
  pg <- tibble::tibble(gsis_id = "p", season = 2024L, week = 1L, game_index = game_index(2024, 1))
  targets <- tibble::tibble(season = 2024L, week = c(2L, 3L, 6L), gsis_id = "p", team = "AAA")
  out <- add_absence_features(targets, pg, tg)
  expect_equal(out$team_games_missed, c(0L, 1L, 3L))         # bye in week 5 is not a missed game
  prior_season <- dplyr::mutate(pg, season = 2023L, game_index = game_index(2023, 17))
  expect_true(all(is.na(add_absence_features(targets, prior_season, tg)$team_games_missed)))
})

test_that("absence feature never reads the target week or later", {
  tg <- tibble::tibble(season = 2024L, week = 1:6, team = "AAA")
  pg <- tibble::tibble(gsis_id = "p", season = 2024L, week = c(1L, 4L),
                       game_index = game_index(2024, c(1, 4)))
  t4 <- tibble::tibble(season = 2024L, week = 4L, gsis_id = "p", team = "AAA")
  # the week-4 appearance itself must not count; weeks 2-3 were missed
  expect_equal(add_absence_features(t4, pg, tg)$team_games_missed, 2L)
  later <- dplyr::bind_rows(pg, tibble::tibble(gsis_id = "p", season = 2024L, week = 5L,
                                               game_index = game_index(2024, 5)))
  expect_equal(add_absence_features(t4, later, tg)$team_games_missed, 2L)
})
