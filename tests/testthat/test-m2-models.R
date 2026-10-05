toy_model_data <- function(n = 400, seed = 11) {
  set.seed(seed)
  d <- tibble::tibble(
    season = rep(2020:2023, each = n / 4), week = rep(1:10, length.out = n),
    gsis_id = as.character(seq_len(n)), espn_proj = runif(n, 1, 20), x1 = rnorm(n), x2 = rnorm(n),
    relevant = TRUE
  )
  for (c in setdiff(ESPN_COMPONENTS, "espn_proj")) d[[c]] <- d$espn_proj / 10 + rnorm(n, 0, 0.1)
  d$actual <- 1 + 0.8 * d$espn_proj + 2 * d$x1 + rnorm(n)
  d$game_index <- game_index(d$season, d$week)
  d
}

test_that("calibration family fits ESPN-only information", {
  d <- toy_model_data()
  for (type in c("linear", "spline", "components", "components_recency")) {
    s <- spec_cal(type)
    expect_false(any(c("x1", "x2") %in% s$features))
    p <- s$predict(s$fit(d), d)
    expect_length(p, nrow(d))
    expect_true(all(is.finite(p)))
  }
})

test_that("recency-weighted calibration down-weights old seasons", {
  d <- toy_model_data()
  d$actual[d$season == 2020] <- d$actual[d$season == 2020] + 20   # old seasons very different
  p_flat <- mean(spec_cal("components")$predict(spec_cal("components")$fit(d), d[d$season == 2023, ]))
  s <- spec_cal("components_recency")
  p_rec <- mean(s$predict(s$fit(d), d[d$season == 2023, ]))
  expect_lt(abs(p_rec - mean(d$actual[d$season == 2023])), abs(p_flat - mean(d$actual[d$season == 2023])))
})

test_that("residual models add a learned correction on top of calibrated ESPN", {
  d <- toy_model_data()
  base <- spec_cal("linear")
  r <- spec_residual("res", base, spec_m2_linear("r", c("x1", "x2")))
  fit <- r$fit(d)
  p <- r$predict(fit, d)
  p_base <- base$predict(base$fit(d), d)
  expect_lt(mean(abs(p - d$actual)), mean(abs(p_base - d$actual)))   # x1 carries real signal
})

test_that("xgboost specs are deterministic", {
  d <- toy_model_data()
  s <- spec_xgb("x", c("espn_proj", "x1", "x2"), max_depth = 3, nrounds = 50)
  expect_identical(s$predict(s$fit(d), d), s$predict(s$fit(d), d))
})

test_that("pairwise accuracy and top-k precision", {
  expect_equal(pairwise_accuracy(c(3, 2, 1), c(30, 20, 10)), 1)
  expect_equal(pairwise_accuracy(c(1, 2, 3), c(30, 20, 10)), 0)
  expect_equal(pairwise_accuracy(c(1, 1), c(2, 3)), 0.5)          # tied predictions score half
  expect_equal(top_k_precision(1:30, 1:30, 24), 1)
  expect_equal(top_k_precision(1:30, 30:1, 24), 18 / 24)
})

test_that("pooled bootstrap keeps every season in each resample and detects a better model", {
  d <- toy_model_data()
  preds <- dplyr::bind_rows(
    dplyr::mutate(d, model = "good", pred = actual + rnorm(nrow(d), 0, 1)),
    dplyr::mutate(d, model = "bad", pred = actual + rnorm(nrow(d), 0, 3))
  )
  b <- pooled_bootstrap(preds, "good", "bad", reps = 300)
  expect_equal(b$n_seasons, 4)
  expect_lt(b$ci_high, 0)
  expect_lt(b$rmse_model, b$rmse_baseline)
})

test_that("selection rules follow the pre-registration", {
  preds <- tibble::tibble(
    model = rep(c("cal_linear", "nf_a", "nf_b", "aug_a", "aug_b"), each = 3), actual = 10,
    pred = c(9, 11, 10,   7, 13, 10,   8, 12, 10,   9.5, 10.5, 10,   10, 10, 3)
  )
  sel <- select_challengers(preds, "cal_linear", c("nf_a", "nf_b"), c("aug_a", "aug_b"))
  expect_equal(sel$nf, "nf_b")
  # aug_b has lower MAE but worse RMSE than calibration -> aug_a chosen
  expect_equal(sel$aug, "aug_a")
  expect_true(sel$aug_rmse_ok)
})

test_that("development frames refuse seasons beyond the development folds", {
  cfg <- list(dev_seasons = 2020:2023)
  expect_error(assert_dev_only(tibble::tibble(season = c(2022L, 2024L)), cfg), "beyond")
  expect_silent(assert_dev_only(tibble::tibble(season = 2020:2023), cfg))
})
