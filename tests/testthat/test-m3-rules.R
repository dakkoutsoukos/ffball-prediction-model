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
  adj <- spec_adjusted("a", base, list(function(nd, b) rule_role_change(nd, "xfp_trend", 1.42, -1.65, -0.3, 0.25)))
  p_base <- base$predict(base$fit(d), d)
  p_adj <- adj$predict(adj$fit(d), d)
  expect_equal(p_adj - p_base, ifelse(d$xfp_trend >= 1.42, -0.3, 0))
})

test_that("registry-built combined challenger applies BOTH frozen rules", {
  m <- list(type = "adjusted", calibration = "linear",
            role_rule = list(metric = "xfp_trend", hi = 1.42, lo = -1.65, adj_hi = -0.30, adj_lo = 0.25),
            return_rule = list(adj_one = -0.2, adj_two_plus = -0.4))
  combo <- registry_spec_adjusted(m, "combo")
  role_only <- registry_spec_adjusted(m[c("type", "calibration", "role_rule")], "role")
  d <- tibble::tibble(season = 2022L, week = rep(1:10, 10), espn_proj = runif(100, 1, 20),
                      xfp_trend = rep(c(2, 0, -2, 0), 25), team_games_missed = rep(c(0L, 1L, 2L, NA, 0L), 20))
  d$actual <- d$espn_proj + rnorm(100)
  base <- spec_cal("linear")
  p0 <- base$predict(base$fit(d), d)
  expect_equal(combo$predict(combo$fit(d), d) - p0,
               rule_role_change(d, "xfp_trend", 1.42, -1.65, -0.3, 0.25) + rule_return(d, -0.2, -0.4))
  expect_equal(role_only$predict(role_only$fit(d), d) - p0, rule_role_change(d, "xfp_trend", 1.42, -1.65, -0.3, 0.25))
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

test_that("questionable rule is proportional or additive and only for Questionable", {
  nd <- tibble::tibble(own_questionable = c(TRUE, FALSE, NA))
  expect_equal(rule_questionable(nd, c(10, 10, 10), "multiplicative", -0.09), c(-0.9, 0, 0))
  expect_equal(rule_questionable(nd, c(10, 10, 10), "additive", -0.68), c(-0.68, 0, 0))
  expect_error(rule_questionable(nd, 1:3, "other", 1), "Unknown")
})

test_that("pregame injury rows require a timestamp strictly before kickoff", {
  tg <- tibble::tibble(season = 2023L, week = 1L, team = c("KC", "DET"),
                       kickoff_utc = as.POSIXct("2023-09-08 00:20", tz = "UTC"))
  inj <- tibble::tibble(season = 2023L, week = 1L, game_type = "REG", team = c("KC", "KC", "DET"),
                        gsis_id = c("a", "b", "c"), report_status = c("Questionable", "Out", "Questionable"),
                        date_modified = as.POSIXct(c("2023-09-06 20:00", "2023-09-08 03:00", NA), tz = "UTC"))
  p <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(inj, p)
  out <- pregame_injuries(p, tg)
  expect_equal(out$gsis_id, "a")                     # b stamped after kickoff, c untimed
  expect_equal(attr(out, "dropped")$not_pregame_or_untimed, 2)
})

test_that("2017-2020 injury timestamps are re-read as US Pacific time", {
  tg <- tibble::tibble(season = 2019L, week = 1L, team = "KC", kickoff_utc = as.POSIXct("2019-09-06 22:00", tz = "UTC"))
  inj <- tibble::tibble(season = 2019L, week = 1L, game_type = "REG", team = "KC", gsis_id = "a",
                        report_status = "Questionable",
                        date_modified = as.POSIXct("2019-09-06 16:00", tz = "UTC"))   # 16:00 PT = 23:00 UTC
  p <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(inj, p)
  expect_equal(nrow(pregame_injuries(p, tg)), 0)       # after the 22:00 UTC kickoff once corrected
})

test_that("prospective injury capture uses the retrieval time and no backfill", {
  tg <- tibble::tibble(season = 2026L, week = 5L, team = "KC", kickoff_utc = as.POSIXct("2026-10-11 17:00", tz = "UTC"))
  inj <- tibble::tibble(season = 2026L, week = 5L, game_type = "REG", team = "KC", gsis_id = "a",
                        report_status = "Questionable")          # 2025+ files carry no date_modified
  p <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(inj, p)
  expect_equal(nrow(pregame_injuries(p, tg)), 0)       # no capture time -> not usable
  expect_equal(nrow(pregame_injuries(p, tg, captured_at = as.POSIXct("2026-10-11 15:00", tz = "UTC"))), 1)
  expect_equal(nrow(pregame_injuries(p, tg, captured_at = as.POSIXct("2026-10-11 18:00", tz = "UTC"))), 0)
})
