# Proper scoring and calibration tools (master plan F2-lite): closed-form checks.

POD_TAU <- c(0.01, 0.05, seq(0.10, 0.90, by = 0.10), 0.95, 0.99)

test_that("CRPS from a dense quantile grid matches the analytic normal CRPS", {
  tau <- seq(0.0005, 0.9995, by = 0.001)
  for (y in c(-2, 0, 0.7, 3)) {
    q <- stats::qnorm(tau, 0.5, 1.3)
    expect_equal(crps_quantiles(q, y, tau), crps_normal(y, 0.5, 1.3), tolerance = 2e-3)
  }
})

test_that("on the POD tau grid the CRPS approximation error is small and documented", {
  set.seed(2)
  y <- stats::rnorm(400, 10, 6)
  q <- t(vapply(seq_along(y), function(i) stats::qnorm(POD_TAU, 10, 6), numeric(length(POD_TAU))))
  rel <- mean(crps_quantiles(q, y, POD_TAU)) / mean(crps_normal(y, 10, 6)) - 1
  expect_lt(abs(rel), 0.03)   # within 3% of the exact CRPS on average
})

test_that("CRPS of a point forecast equals absolute error", {
  tau <- seq(0.05, 0.95, by = 0.05)
  expect_equal(crps_quantiles(rep(4, length(tau)), 7, tau), 3)
  expect_equal(crps_quantiles(matrix(rep(c(4, 10), each = length(tau)), nrow = 2, byrow = TRUE), c(7, 7), tau), c(3, 3))
})

test_that("the quantile CDF interpolates, extrapolates and jumps at tied quantiles", {
  tau <- c(0.1, 0.5, 0.9)
  q <- c(0, 10, 20)
  expect_equal(cdf_from_quantiles(5, q, tau)$F, 0.3)
  expect_equal(cdf_from_quantiles(10, q, tau)$F, 0.5)
  expect_equal(cdf_from_quantiles(-30, q, tau)$F, 0)
  expect_equal(cdf_from_quantiles(100, q, tau)$F, 1)
  tied <- c(0, 0, 20)                                  # 50% of the mass at or below 0
  a <- cdf_from_quantiles(0, tied, tau)
  expect_equal(a$F, 0.5)
  expect_equal(a$F_minus, 0.1)
})

test_that("randomised PIT is uniform for a calibrated forecast with a point mass at zero", {
  set.seed(5)
  n <- 4000
  p <- 0.8
  active <- stats::runif(n) < p
  y <- ifelse(active, stats::rnorm(n, 8, 4), 0)
  q <- matrix(stats::qnorm(POD_TAU, 8, 4), nrow = n, ncol = length(POD_TAU), byrow = TRUE)
  cdf <- pod_cdf(y, q, POD_TAU, p)
  pit <- pit_randomised(cdf$F, cdf$F_minus)
  counts <- tabulate(cut(pit, seq(0, 1, 0.1), include.lowest = TRUE, labels = FALSE), 10)
  expect_gt(stats::chisq.test(counts)$p.value, 0.001)
  expect_equal(mean(pit), 0.5, tolerance = 0.02)
  # a forecast that ignores the inactive mass is visibly miscalibrated (PIT piles up near 0)
  bad <- cdf_from_quantiles(y, q, POD_TAU)
  expect_gt(mean(pit_randomised(bad$F, bad$F_minus) < 0.1), 0.2)
})

test_that("coverage and interval score behave as defined", {
  y <- c(1, 5, 9)
  expect_equal(interval_coverage(y, 2, 8), 1 / 3)
  expect_equal(interval_score(5, 2, 8, 0.2), 6)
  expect_equal(interval_score(1, 2, 8, 0.2), 6 + (2 / 0.2) * 1)
  expect_equal(interval_score(9, 2, 8, 0.2), 6 + (2 / 0.2) * 1)
})

test_that("Brier score, reliability table and CORP decomposition are consistent", {
  set.seed(11)
  p <- stats::runif(5000)
  o <- as.integer(stats::runif(5000) < p)          # calibrated by construction
  expect_equal(brier_score(c(1, 0), c(1, 1)), 0.5)
  rt <- reliability_table(p, o, bins = 5)
  expect_equal(sum(rt$n), 5000)
  expect_true(all(abs(rt$observed - rt$mean_forecast) < 0.05))
  dec <- brier_decomposition(p, o)
  expect_equal(dec$brier, dec$mcb - dec$dsc + dec$unc, tolerance = 1e-12)
  expect_lt(dec$mcb, 0.005)                        # calibrated: little miscalibration
  dec2 <- brier_decomposition(pmin(p + 0.2, 1), o)  # biased upward
  expect_gt(dec2$mcb, dec$mcb)
})
