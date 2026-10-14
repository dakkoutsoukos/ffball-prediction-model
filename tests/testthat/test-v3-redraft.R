# Valuation v3, X10a (VL7): the V1 re-draft with level uncertainty and learning. Synthetic pools only.

v3_toy_league <- function(teams = 4) {
  val_league(list(name = "toy", teams = teams,
                  slots = list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 1),
                               list(name = "WR", eligible = "WR", count = 1),
                               list(name = "FLEX", eligible = c("RB", "WR"), count = 1)),
                  bench = 2, regular_season_weeks = c(1, 3), playoff_weeks = c(4, 4)))
}

v3_toy_weekly <- function(seed = 1, weeks = 1:4) {
  set.seed(seed)
  counts <- c(QB = 9, RB = 14, WR = 14)
  pl <- tibble::tibble(position = rep(names(counts), counts)) |>
    dplyr::mutate(player_id = sprintf("%s%02d", .data$position, dplyr::row_number()),
                  level = stats::rgamma(dplyr::n(), 4, 4 / c(QB = 16, RB = 9, WR = 9)[.data$position]))
  tidyr::expand_grid(pl, week = weeks) |>
    dplyr::mutate(A = stats::runif(dplyr::n(), 0.75, 1), lvl = .data$level * stats::rlnorm(dplyr::n(), 0, 0.1),
                  E = .data$A * .data$lvl) |>
    dplyr::select("player_id", "position", "week", "E", "A", "lvl")
}

v3_zero <- c(QB = 0, RB = 0, WR = 0, TE = 0)

test_that("top-K insertion keeps decision order per column and carries realised values", {
  set.seed(3)
  C <- 7
  v <- matrix(stats::rnorm(5 * C), 5, C)
  r <- v * 10
  Tp <- list(v = matrix(-Inf, 3, C), r = matrix(0, 3, C))
  for (i in 1:5) Tp <- v3_topk_insert(Tp, v[i, ], r[i, ])
  for (c in seq_len(C)) {
    o <- order(-v[, c])[1:3]
    expect_equal(Tp$v[, c], v[o, c])
    expect_equal(Tp$r[, c], r[o, c])
  }
})

test_that("with sigma = 0 the v3 evaluator equals V1's lineup value", {
  wk <- v3_toy_weekly(2)
  lg <- v3_toy_league()
  spec <- val_lineup_spec(lg)
  lu <- v3_lu_setup(wk, v3_zero, current_week = 1, lag = 0, sims = 30, seed = 5)
  sim <- lu$sim
  pool <- val_proportional_pool(sim, lg)
  undrafted <- setdiff(seq_len(nrow(sim$players)), pool$rows)
  st1 <- val_stream_vectors(val_waiver_levels(sim, pool$rows), sim, spec$positions)
  st3 <- v3_stream(lu, undrafted, spec$positions)
  for (p in spec$positions) expect_equal(st3[[p]]$dec, st1[[p]])
  set.seed(9)
  for (k in 1:5) {
    rows <- sample(seq_len(nrow(sim$players)), 6)
    expect_equal(v3_lineup_value(v3_team_tops(rows, lu, spec), st3, spec, sim$sims),
                 val_lineup_value(val_team_tops(rows, sim, spec), st1, spec, sim$sims))
  }
})

test_that("with sigma = 0 the v3 fixed point reproduces V1's simulation pool exactly", {
  wk <- v3_toy_weekly(4)
  lg <- v3_toy_league()
  sim <- val_sim_setup(wk, 30, 5)
  v1 <- val_league_sim(sim, lg, cand_per_pos = 4, max_iterations = 4, pool = "simulation")
  lu <- v3_lu_setup(wk, v3_zero, current_week = 1, lag = 3, sims = 30, seed = 5)
  fp <- v3_fixed_point(lu, lg, cand_per_pos = 4, max_iterations = 4)
  expect_setequal(sim$players$player_id[fp$drafted], v1$rostered_pool)
  expect_equal(fp$history$changed, v1$iterations$changed)
  expect_equal(fp$converged, isTRUE(v1$converged))
})

test_that("learning: decisions use prior levels before the lag and realised levels after it", {
  wk <- v3_toy_weekly(5)
  sig <- c(QB = 0.4, RB = 0.4, WR = 0.4, TE = 0.4)
  none <- v3_lu_setup(wk, sig, current_week = 1, lag = Inf, sims = 20, seed = 5)
  now <- v3_lu_setup(wk, sig, current_week = 1, lag = 0, sims = 20, seed = 5)
  lag2 <- v3_lu_setup(wk, sig, current_week = 1, lag = 2, sims = 20, seed = 5)
  expect_equal(none$D, none$sim$P)                         # no learning: V1's decision values
  expect_equal(now$D, now$R)                               # immediate learning
  expect_equal(none$R, now$R)                              # same shocks whatever the lag
  wk_col <- rep(lag2$sim$weeks, times = 20)
  expect_equal(lag2$D[, wk_col < 3], lag2$sim$P[, wk_col < 3])
  expect_equal(lag2$D[, wk_col >= 3], lag2$R[, wk_col >= 3])
  big <- v3_lu_setup(v3_toy_weekly(6), sig, current_week = 1, lag = 0, sims = 400, seed = 5)
  expect_equal(mean(big$shock), 1, tolerance = 0.03)       # mean-one shocks
})

test_that("the X10a study reports the harness check, three variants and the decision rule", {
  wk <- v3_toy_weekly(7)
  lg <- v3_toy_league()
  sig <- c(QB = 0.37, RB = 0.37, WR = 0.35, TE = 0.39)
  out <- x10a_study(wk, lg, sig, current_week = 1, sims = 20, max_iterations = 3, cand_per_pos = 3)
  expect_named(out$variants, c("lag3", "lag0", "none"))
  expect_true(all(c("iteration", "changed", "QB") %in% names(out$variants$lag3$history)))
  expect_identical(out$supported, out$variants$lag3$converged && abs(out$variants$lag3$qb_final - out$proportional_qb) <= 3)
  expect_type(out$harness$reproduces, "logical")
})
