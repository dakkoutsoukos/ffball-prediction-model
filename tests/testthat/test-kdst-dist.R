# X22 (E23, E23a): K and D/ST distributions for lineup totals. Synthetic inputs only.

x22_toy <- function() {
  tg <- tibble::tibble(season = rep(c(2020L, 2021L), each = 4), week = 1L, team = rep(c("AAA", "BBB", "CCC", "DDD"), 2),
                       opponent = rep(c("BBB", "AAA", "DDD", "CCC"), 2), implied_team_total = c(20, 24, 18, 27, 21, 23, 19, 26))
  k <- dplyr::mutate(tg[c("season", "week", "team")], k_points = c(6, 9, 4, 11, 7, 8, 5, 10))
  d <- dplyr::mutate(tg[c("season", "week", "team")], dst_points = c(3, 8, -1, 12, 4, 6, 0, 9))
  list(tg = tg, k = k, d = d)
}

test_that("units carry the team's and the opponent's closing implied totals", {
  x <- x22_toy()
  u <- x22_units(x$k, x$d, x$tg, seasons = 2020:2021)
  expect_equal(nrow(u), 8)
  expect_equal(u$opp_implied[u$season == 2020 & u$team == "AAA"], 24)
  expect_equal(u$opp_implied[u$season == 2020 & u$team == "DDD"], 18)
  expect_equal(nrow(x22_units(x$k, x$d, x$tg, seasons = 2021L)), 4)
})

test_that("the fit uses the training seasons only, with tertile bands of the implied totals", {
  x <- x22_toy()
  u <- x22_units(x$k, x$d, x$tg, seasons = 2020:2021)
  f <- x22_fit(u, 2020L, tau = c(0.1, 0.5, 0.9))
  expect_equal(f$v0$K, stats::quantile(c(6, 9, 4, 11), c(0.1, 0.5, 0.9), names = FALSE))
  expect_equal(f$v0$DST, stats::quantile(c(3, 8, -1, 12), c(0.1, 0.5, 0.9), names = FALSE))
  expect_equal(f$edges$K, stats::quantile(c(20, 24, 18, 27), c(1, 2) / 3, names = FALSE))
  expect_length(f$cond$K, 3)
  # the lowest implied-total tertile holds the low-scoring kicker
  expect_equal(f$cond$K[[1]], stats::quantile(4, c(0.1, 0.5, 0.9), names = FALSE))
})

test_that("scores are named by variant and the gate refuses seasons outside development", {
  set.seed(3)
  s <- x22_score(stats::rnorm(2000, 100, 10), 100, "v0")
  expect_named(s, paste0("v0_", c("realised", "pit", "cover50", "cover80", "cover90", "mean_sim", "var_sim")))
  expect_true(s$v0_cover50 && s$v0_cover90)
  rows <- purrr::map(1:3, function(i) {
    n <- 300
    real <- stats::rnorm(n, 100, 10)
    sc <- function(v) purrr::map(real, function(r) x22_score(stats::rnorm(400, 100, 10), r, v)) |> purrr::list_rbind()
    dplyr::bind_cols(tibble::tibble(season = 2020L + i, week = rep(1:10, length.out = n), n_teams = 8L, starters = 8L),
                     sc("none"), sc("v0"), sc("cond"))
  }) |> purrr::list_rbind()
  reg <- read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))
  g <- x22_gate(rows, register = reg)
  expect_named(g, c("none", "v0", "cond"))
  expect_false(g$v0$fails)                              # calibrated by construction
  expect_error(x22_gate(dplyr::mutate(rows, season = 2024L), register = reg), "may not use")
})
