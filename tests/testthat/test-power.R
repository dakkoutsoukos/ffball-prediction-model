# Power and MDE for the 2026 prospective tests (master plan F1). Synthetic data only.

test_that("the MDE formula matches its closed form and the plan's reference values", {
  expect_equal(mde(1, 10), (qt(0.975, 9) + qt(0.8, 9)) / sqrt(10))
  expect_equal(round(mde(1, 8), 2), 1.15)    # 02 section 10: W = 8 about 1.15 sigma_w
  expect_equal(round(mde(1, 10), 2), 0.99)   # W = 10 about 0.99 sigma_w
  expect_equal(round(mde(1, 17), 2), 0.72)   # W = 17 about 0.72 sigma_w
  expect_equal(mde(2, 13), 2 * mde(1, 13))   # linear in sigma_w
})

test_that("power at the MDE is close to the nominal 80% and rises with the improvement", {
  for (W in c(8, 10, 13, 14)) {
    p <- power_at(-mde(0.05, W), 0.05, W)   # an improvement of exactly the MDE
    expect_gt(p, 0.77)
    expect_lt(p, 0.83)
  }
  expect_lt(power_at(-0.01, 0.05, 10), power_at(-0.03, 0.05, 10))
  # one-sided: a challenger that is truly WORSE almost never passes "CI below 0"
  expect_lt(power_at(0.02, 0.05, 10), 0.025)
  expect_equal(power_at(0, 0.05, 10), 0.025, tolerance = 1e-8)   # size under the null
})

test_that("week-level differences pair player-weeks exactly like pooled_bootstrap()", {
  p <- tibble::tibble(season = 2024L, week = rep(c(1L, 1L, 2L), 2), gsis_id = rep(c("a", "b", "a"), 2),
                      actual = rep(c(10, 0, 5), 2), model = rep(c("m", "base"), each = 3),
                      pred = c(9, 1, 6, 12, 1, 5))
  p <- dplyr::bind_rows(p, tibble::tibble(season = 2024L, week = 2L, gsis_id = "c", actual = 3, model = "m", pred = 3))
  wk <- week_level_diffs(p, "m", "base", "abs")
  # week 1: |9-10| - |12-10| = -1 ; |1-0| - |1-0| = 0  -> s = -1, n = 2 ; week 2: |6-5| - |5-5| = 1, n = 1
  # (player c is predicted by one model only and is not paired)
  expect_equal(wk$s, c(-1, 1))
  expect_equal(wk$n, c(2L, 1L))
  expect_equal(week_level_diffs(p, "m", "base", "sq")$s, c(1 - 4, 1))
  pb <- pooled_bootstrap(p, "m", "base", reps = 50)
  expect_equal(pb$mae_diff, sum(wk$s) / sum(wk$n))
})

test_that("sigma_w is within season: a shift in the mean effect between seasons adds no noise", {
  set.seed(3)
  mk <- function(season, shift) tibble::tibble(season = season, week = 1:17, s = 100 * (shift + rnorm(17, 0, 0.05)), n = 100L,
                                               mean_d = s / n)
  base <- dplyr::bind_rows(mk(2023L, 0), mk(2024L, 0))
  a <- week_noise(base)
  b <- week_noise(dplyr::mutate(base, s = .data$s + ifelse(.data$season == 2024L, 100 * 0.5, 0),
                                mean_d = .data$s / .data$n))
  expect_equal(a$sigma_w, b$sigma_w)
  expect_equal(a$sigma_w, a$sd_week_means)   # equal n per week: linearised = SD of week means
  expect_lt(abs(a$sigma_w - 0.05), 0.02)
})

test_that("the bootstrap simulation reports pass rates and rises with the improvement", {
  p <- percentile_bootstrap_sim(10, c(0, -1.5), reps = 200, boot_reps = 100, seed = 1)
  expect_length(p, 2)
  expect_true(all(p >= 0 & p <= 1))
  expect_gt(p[2], p[1])
  expect_equal(p, percentile_bootstrap_sim(10, c(0, -1.5), reps = 200, boot_reps = 100, seed = 1))   # seeded
})

test_that("the MDE table pools sigma_w by degrees of freedom and flags detectable effects", {
  noise <- tibble::tibble(hypothesis = "H", loss = "MAE", source = c("x", "y"), weeks = c(18L, 36L),
                          sigma_w = c(0.02, 0.04), delta = c(-0.01, -0.02))
  t <- mde_table(noise, W = c(8, 14), inflation = c(1, 1.5))
  expect_equal(nrow(t), 4L)
  expect_equal(t$sigma_w[1], sqrt((17 * 0.02^2 + 35 * 0.04^2) / 52))
  expect_equal(t$sigma_used, t$sigma_w * t$inflation)
  expect_equal(t$detectable, -t$delta_hist >= t$mde)
  ref <- tibble::tibble(hypothesis = "H", loss = "MAE", delta_hist = -0.5, reference_seasons = "2019")
  t2 <- mde_table(noise, W = 8, inflation = 1, reference = ref)
  expect_true(t2$detectable)
  expect_equal(t2$reference_seasons, "2019")
  worse <- mde_table(noise, W = 8, inflation = 1, reference = dplyr::mutate(ref, delta_hist = 0.5))
  expect_false(worse$detectable)   # a harmful reference effect is never "detectable"
  expect_lt(worse$power_at_hist, 0.025)
})
