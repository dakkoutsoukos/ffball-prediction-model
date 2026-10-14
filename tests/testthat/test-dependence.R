# P3 gate (E21). Synthetic data only.

p3_toy <- function(seed = 1, shock_sd = 0) {
  set.seed(seed)
  players <- tibble::tibble(gsis_id = sprintf("p%03d", 1:160), position = rep(c("QB", "RB", "WR", "TE"), c(20, 40, 70, 30)),
                            team = rep(sprintf("T%02d", 1:20), length.out = 160))
  fr <- tidyr::expand_grid(season = 2020:2021, week = 1:14, players) |>
    dplyr::mutate(base = stats::runif(dplyr::n(), 5, 20))
  shocks <- dplyr::distinct(fr, .data$season, .data$week, .data$team) |>
    dplyr::mutate(shock = stats::rnorm(dplyr::n(), 0, shock_sd))
  fr |>
    dplyr::left_join(shocks, by = c("season", "week", "team")) |>
    dplyr::mutate(y = .data$base + .data$shock + stats::rnorm(dplyr::n(), 0, 4), active = TRUE, resid = .data$y - .data$base,
                  espn_proj = .data$base, status = factor("none", c("none", "listed", "QD")), td_share = 0.3,
                  implied_total = 22, spread = 0) |>
    dplyr::select(-"shock") |>
    p2_volatility()
}

p3_toy_lineups <- function(fr, stacked = FALSE, n = 150) {
  rows <- fr[fr$season == 2021, ]
  purrr::map(seq_len(n), function(i) {
    w <- (i - 1) %% 14 + 1
    r <- rows[rows$week == w, ]
    if (stacked) r <- r[r$team == sprintf("T%02d", (i - 1) %% 20 + 1), ]
    pick <- c(utils::head(r$gsis_id[r$position == "QB"], 1), utils::head(r$gsis_id[r$position == "RB"], 2),
              utils::head(r$gsis_id[r$position == "WR"], 3), utils::head(r$gsis_id[r$position == "TE"], 1))
    tibble::tibble(season = 2021L, league = 1L, n_teams = 10L, team = i, week = w, starters = list(pick))
  }) |> purrr::list_rbind()
}

p3_at <- function() tidyr::expand_grid(position = c("QB", "RB", "WR", "TE"), band = 1:7) |>
  dplyr::mutate(rows = 100L, active_share = 1)

test_that("independent outcomes give lineup-total coverage near nominal", {
  fr <- p3_toy(seed = 1)
  g <- p3_gate_season(fr, p3_toy_lineups(fr), "C0", p3_at(), sims = 1000L)
  expect_true(all(g$pit >= 0 & g$pit <= 1))
  expect_true(abs(mean(g$cover80) - 0.8) < 0.1)
  expect_true(is.logical(g$stack))
})

test_that("a shared team shock in stacked lineups breaks independence and the gate detects it", {
  fr <- p3_toy(seed = 2, shock_sd = 7)
  g <- p3_gate_season(fr, p3_toy_lineups(fr, stacked = TRUE, n = 280), "C0", p3_at(), sims = 1000L)
  expect_true(all(g$stack))
  expect_lt(mean(g$cover80), 0.7)
  res <- p3_gate(g, reps = 200L)
  expect_true(res$build_p3)
  expect_gt(res$variance_ratio, 1.5)
})

test_that("starters without a projected row add nothing", {
  fr <- p3_toy(seed = 3)
  ln <- p3_toy_lineups(fr, n = 3)
  ln$starters[[1]] <- c(ln$starters[[1]], "nobody")
  ln$starters[[2]] <- "nobody"
  g <- p3_gate_season(fr, ln, "C0", p3_at(), sims = 200L)
  expect_equal(g$starters[1:2], c(7L, 0L))
  expect_true(is.na(g$pit[2]))
})
