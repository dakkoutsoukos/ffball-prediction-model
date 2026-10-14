# S1 matchup P(win) (VL5). Synthetic data only.

s1_table <- function(q) {
  tibble::tibble(position = POD_POSITIONS, band_lo = 1L, band_hi = 7L, label = "all", n = 1000L, sd = 5,
                 q = rep(list(q), 4), floor = -10)
}

s1_toy_frame <- function(seed = 1) {
  set.seed(seed)
  tibble::tibble(season = 2021L, week = 1L, gsis_id = sprintf("p%02d", 1:16), position = rep(c("QB", "RB", "WR", "TE"), 4),
                 espn_proj = stats::runif(16, 5, 20)) |>
    dplyr::mutate(base = .data$espn_proj)
}

s1_at <- function(p = 1) tidyr::expand_grid(position = POD_POSITIONS, band = 1:7) |> dplyr::mutate(rows = 100L, active_share = p)

test_that("POD moments match Monte Carlo", {
  q <- matrix(stats::qnorm(POD_TAU, 10, 4), 1)
  mo <- s1_pod_moments(q, 0.8)
  set.seed(1)
  x <- (stats::runif(2e5) < 0.8) * sim_qdraw(q[rep(1, 2e5), ], stats::runif(2e5))
  expect_equal(mo$mean, mean(x), tolerance = 0.01)
  expect_equal(mo$var, stats::var(x), tolerance = 0.03)
})

test_that("simulation and the normal approximation agree for symmetric, always-active players", {
  fr <- s1_toy_frame()
  m <- tibble::tibble(season = 2021L, league = 1L, n_teams = 8L, week = 1L, team = 1L, opponent = 2L,
                      lineup_a = list(fr$gsis_id[1:8]), lineup_b = list(fr$gsis_id[9:16]), outcome = 1)
  p <- s1_predict(m, fr, s1_table(stats::qnorm(POD_TAU, 0, 5)), s1_at(1), sims = 20000L)
  expect_equal(p$p_sim, p$p_normal, tolerance = 0.02)
  expect_equal(p$mu_diff, sum(fr$base[1:8]) - sum(fr$base[9:16]), tolerance = 0.2)
})

test_that("skewed distributions separate simulation from the normal approximation", {
  fr <- s1_toy_frame(seed = 2)
  fr$base <- 10
  m <- tibble::tibble(season = 2021L, league = 1L, n_teams = 8L, week = 1L, team = 1L, opponent = 2L,
                      lineup_a = list(fr$gsis_id[1]), lineup_b = list(fr$gsis_id[2]), outcome = 1)
  skew <- stats::qexp(POD_TAU, 1 / 6) - 6                      # strongly right-skewed residuals, mean ~0
  p <- s1_predict(m, fr, s1_table(skew), s1_at(1), sims = 20000L)
  # one player each with the same distribution: P(win) = 0.5 by symmetry under both methods
  expect_equal(p$p_sim, 0.5, tolerance = 0.02)
  fr2 <- fr
  fr2$base[1:2] <- c(10, 12)                                     # A is 2 points behind; e1 - e2 is Laplace-like
  p2 <- s1_predict(m, fr2, s1_table(skew), s1_at(1), sims = 40000L)
  expect_lt(p2$p_sim, p2$p_normal - 0.02)                        # heavy tails: the normal overstates the underdog
})

test_that("the VL5 evaluation reports the bound and the slope rule", {
  set.seed(4)
  n <- 600
  p_true <- stats::runif(n, 0.1, 0.9)
  pred <- tibble::tibble(season = rep(2020:2021, each = n / 2), league = 1L, n_teams = 8L, week = rep(1:14, length.out = n),
                         team = 1L, opponent = 2L, outcome = as.numeric(stats::runif(n) < p_true),
                         p_sim = p_true, p_normal = pmin(pmax(p_true + stats::rnorm(n, 0, 0.1), 0.01), 0.99))
  ev <- s1_evaluate(pred, reps = 300L)
  expect_lt(ev$d_brier, 0)
  expect_true(ev$non_inferior)
  expect_true(ev$slope_ci[1] < 1.2 && ev$slope_ci[2] > 0.8)
})
