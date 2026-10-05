test_that("assert_unique_key detects duplicates", {
  df <- tibble::tibble(season = c(2024, 2024), week = 1, gsis_id = "x")
  expect_error(assert_unique_key(df, c("season", "week", "gsis_id")), "duplicated")
  expect_silent(assert_unique_key(df[1, ], c("season", "week", "gsis_id")))
})

test_that("range and membership assertions fail loudly", {
  df <- tibble::tibble(snap_share = c(0.5, 1.2), targets = c(1, -1), pos = c("WR", "XX"))
  expect_error(assert_in_range(df, "snap_share", 0, 1), "outside")
  expect_error(assert_in_range(df, "targets", 0), "outside")
  expect_error(assert_values_in(df, "pos", c("WR", "TE")), "unexpected")
})

test_that("safe_left_join refuses to duplicate rows and reports unmatched share", {
  x <- tibble::tibble(id = c(1, 2, 3))
  y_dup <- tibble::tibble(id = c(1, 1), v = 1:2)
  expect_error(safe_left_join(x, y_dup, by = "id"))
  y <- tibble::tibble(id = 1, v = 1)
  out <- safe_left_join(x, y, by = "id")
  expect_equal(nrow(out), 3)
  expect_equal(attr(out, "unmatched_frac"), 2 / 3)
  expect_error(safe_left_join(x, y, by = "id", max_unmatched_frac = 0.5), "unmatched")
})

test_that("team game context uses the nflverse spread sign convention", {
  sch <- tibble::tibble(
    season = 2024L, week = 1L, game_type = "REG", game_id = "g", gameday = "2024-09-08",
    gametime = "13:00", home_team = "KC", away_team = "BAL", location = "Home",
    spread_line = 3, total_line = 47, home_rest = 7, away_rest = 7, result = NA_real_,
    roof = "outdoors"
  )
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(sch, path)
  tg <- clean_team_games(path)
  expect_equal(tg$implied_team_total[tg$team == "KC"], 25)
  expect_equal(tg$implied_team_total[tg$team == "BAL"], 22)
  expect_true(tg$home[tg$team == "KC"])
  expect_equal(tg$team_spread[tg$team == "BAL"], -3)
  expect_false(any(tg$game_final))                       # no result yet = not final
  expect_equal(format(tg$kickoff_utc[1], tz = "UTC"), "2024-09-08 17:00:00")
})

test_that("team codes are normalised to current franchises and unknown codes fail", {
  expect_equal(standardize_team(c("OAK", "LV", "SD", "STL", "LA", "JAC")),
               c("LV", "LV", "LAC", "LA", "LA", "JAX"))
  expect_true(is.na(standardize_team("XXX")))
})

test_that("prediction_metrics computes MAE, RMSE, bias", {
  m <- prediction_metrics(actual = c(0, 10, 20), pred = c(2, 10, 14))
  expect_equal(m$mae, 8 / 3)
  expect_equal(m$rmse, sqrt((4 + 0 + 36) / 3))
  expect_equal(m$bias, -4 / 3)
  expect_equal(m$n, 3)
})

test_that("summarise_metrics works when grouping by season", {
  preds <- tidyr::expand_grid(model = c("a", "b"), season = 2024, week = 1:2, gsis_id = c("x", "y", "z")) |>
    dplyr::mutate(actual = rep(c(1, 5, 9), 4), pred = actual + ifelse(model == "a", 1, 2))
  out <- summarise_metrics(preds, by = "season")
  expect_equal(out$mae, c(1, 2))
  expect_equal(out$rank_cor, c(1, 1))
})

test_that("align_predictions compares models on identical player-weeks", {
  preds <- tibble::tibble(
    model = c("a", "a", "b"), season = 2024, week = 1, gsis_id = c("x", "y", "x"),
    pred = c(1, 2, 3), actual = c(1, 1, 1)
  )
  out <- align_predictions(preds, c("a", "b"))
  expect_setequal(out$gsis_id, "x")
  expect_equal(attr(out, "n_dropped"), 1)
})

test_that("paired bootstrap favours the better model", {
  set.seed(3)
  n <- 400
  base <- tibble::tibble(season = 2024, week = rep(1:16, length.out = n), gsis_id = as.character(seq_len(n)),
                         actual = rnorm(n, 10, 5))
  preds <- dplyr::bind_rows(
    dplyr::mutate(base, model = "good", pred = actual + rnorm(n, 0, 1)),
    dplyr::mutate(base, model = "bad", pred = actual + rnorm(n, 0, 4))
  )
  b <- paired_bootstrap_mae(preds, "good", "bad", reps = 300)
  expect_lt(b$mae_diff, 0)
  expect_lt(b$ci_high, 0)
})

test_that("season_split assigns chronological splits", {
  splits <- list(first_train_season = 2020, train_last_season = 2023,
                 validation_season = 2024, test_season = 2025)
  expect_equal(season_split(2019:2025, splits),
               c("history", rep("train", 4), "validation", "test"))
})

test_that("ridge with a negligible penalty reproduces OLS predictions", {
  set.seed(7)
  d <- tibble::tibble(x1 = rnorm(300), x2 = rnorm(300), x3 = runif(300) > 0.5)
  d$actual <- 2 + 3 * d$x1 - d$x2 + 1.5 * d$x3 + rnorm(300)
  ols <- spec_linear("ols", c("x1", "x2", "x3"))
  ridge <- spec_linear("ridge", c("x1", "x2", "x3"), penalty = 1e-5)
  p_ols <- ols$predict(ols$fit(d), d)
  p_ridge <- ridge$predict(ridge$fit(d), d)
  expect_lt(max(abs(p_ols - p_ridge)), 0.01)
})
