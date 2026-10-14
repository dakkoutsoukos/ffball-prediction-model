# S2 v1 week-k calibration study (VL6). Synthetic data only.

s2_toy <- function(seed = 1) {
  set.seed(seed)
  teams <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE")
  counts <- c(QB = 20, RB = 60, WR = 70, TE = 25)
  players <- tibble::tibble(position = rep(names(counts), counts)) |>
    dplyr::mutate(gsis_id = sprintf("%s%03d", .data$position, dplyr::row_number()), team = sample(teams, dplyr::n(), TRUE),
                  level = stats::rgamma(dplyr::n(), 2, 2 / c(QB = 16, RB = 8, WR = 8, TE = 6)[.data$position]))
  bye <- stats::setNames(rep(5:8, 2), teams)
  tg <- tidyr::expand_grid(season = 2021L, week = 1:17, team = teams) |> dplyr::filter(.data$week != bye[.data$team])
  fr <- tidyr::expand_grid(players, week = 1:17) |>
    dplyr::semi_join(tg, by = c("week", "team")) |>
    dplyr::mutate(season = 2021L, espn_proj = pmax(0, .data$level * stats::rlnorm(dplyr::n(), 0, 0.15)),
                  base = .data$espn_proj, actual = pmax(0, .data$espn_proj + stats::rnorm(dplyr::n(), 0, 5)),
                  active = stats::runif(dplyr::n()) < 0.95)
  list(frame = fr, team_games = tg)
}

s2_toy_table <- function() tibble::tibble(position = POD_POSITIONS, band_lo = 1L, band_hi = 7L, label = "all", n = 1000L,
                                          sd = 5, q = rep(list(stats::qnorm(POD_TAU, 0, 5)), 4), floor = -5)

test_that("week-k playoff odds satisfy the invariant and order teams sensibly", {
  x <- s2_toy()
  S <- lab_season_data(x$frame, x$team_games, 2021L)
  setup <- lab_setup(S, 8L, 1L, seed = 5L)
  run <- lab_run_league(S, setup, "A", tibble::tibble(position = LAB_POSITIONS, a = 0, b = 1))
  tw <- run$team_weeks
  rows <- p4_ros_rows(S, 1:12)
  comp <- p4_fit_components(rows)
  out <- s2_league_k(S, tw, 7L, comp, s2_toy_table(), sims = 400L, seed = 1L)
  expect_equal(nrow(out), 8)
  expect_equal(sum(out$p_playoffs), 4, tolerance = 1e-9)
  expect_true(all(out$p_playoffs >= 0 & out$p_playoffs <= 1))
  rec <- s2_record(tw, 7L, 8L)
  expect_equal(sum(rec$wins), 8 * 7 / 2)                          # each week's games award one win in total
  best <- which.max(rec$wins + rec$pf / 1e4)
  expect_gte(out$p_playoffs[best], stats::median(out$p_playoffs))
  expect_identical(out, s2_league_k(S, tw, 7L, comp, s2_toy_table(), sims = 400L, seed = 1L))
  with_shock <- s2_league_k(S, tw, 7L, comp, s2_toy_table(), sims = 400L, seed = 1L,
                            sigma = c(QB = 0.4, RB = 0.4, WR = 0.4, TE = 0.4))
  expect_equal(sum(with_shock$p_playoffs), 4, tolerance = 1e-9)
})
