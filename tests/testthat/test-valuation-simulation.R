# Valuation: lineup evaluator, generic draft, roster utility, 2-for-1 accounting.

sim_league <- function(teams = 2, bench = 1, flex = 1, rb = 1, wr = 1) {
  slots <- list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = rb),
                list(name = "WR", eligible = "WR", count = wr), list(name = "TE", eligible = "TE", count = 1))
  if (flex > 0) slots <- c(slots, list(list(name = "FLEX", eligible = c("RB", "WR", "TE"), count = flex)))
  val_league(list(name = "sim", teams = teams, slots = slots, bench = bench,
                  regular_season_weeks = c(1, 2), playoff_weeks = c(3, 3)))
}

#' Deterministic weekly table (A = 1) for given per-week points.
det_weekly <- function(pts, weeks = 1) {
  tidyr::expand_grid(player_id = names(pts), week = weeks) |>
    dplyr::mutate(position = substr(.data$player_id, 1, 2), E = unname(pts[.data$player_id]), A = 1,
                  lvl = .data$E)
}

test_that("top-K insertion keeps column-wise sorted order", {
  Tm <- matrix(-Inf, 3, 2)
  for (v in list(c(5, 1), c(9, 2), c(1, 8), c(7, 7))) Tm <- val_topk_insert(Tm, v)
  expect_equal(Tm[, 1], c(9, 7, 5))
  expect_equal(Tm[, 2], c(8, 7, 2))
})

test_that("lineup value: dedicated slots, FLEX from the best remaining, streamers floor every slot", {
  lg <- val_league(list(name = "x", teams = 1, bench = 3, regular_season_weeks = c(1, 1), playoff_weeks = c(2, 2),
                        slots = list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 2),
                                     list(name = "WR", eligible = "WR", count = 2), list(name = "TE", eligible = "TE", count = 1),
                                     list(name = "FLEX", eligible = c("RB", "WR", "TE"), count = 1))))
  pts <- c(QB1 = 20, RB1 = 15, RB2 = 10, RB3 = 5, WR1 = 12, WR2 = 8, TE1 = 6)
  sim <- val_sim_setup(det_weekly(pts), sims = 1)
  spec <- val_lineup_spec(lg)
  stream <- list(QB = 10, RB = 7, WR = 9, TE = 4)
  # QB 20 + RB 15 + 10 + WR 12 + max(8, stream 9) + TE 6 + FLEX best of (RB3 5 -> 7, WR stream 9, TE 4) = 9
  expect_equal(val_lineup_value(val_team_tops(seq_len(nrow(sim$players)), sim, spec), stream, spec, 1), 81)
  # an empty roster streams everything
  expect_equal(val_lineup_value(val_team_tops(integer(), sim, spec), stream, spec, 1), 10 + 14 + 18 + 4 + 9)
})

test_that("Monte Carlo availability: expected lineup points include bench cover for absences", {
  lg <- sim_league(teams = 1, bench = 1, flex = 0)
  w <- tibble::tibble(player_id = c("QB1", "QB2", "RB1", "WR1", "TE1"), week = 1L, position = c("QB", "QB", "RB", "WR", "TE"),
                      E = c(18, 12, 10, 10, 5), A = c(0.5, 1, 1, 1, 1), lvl = c(36, 12, 10, 10, 5))
  sim <- val_sim_setup(w, sims = 4000, seed = 3)
  spec <- val_lineup_spec(lg)
  st <- list(QB = 0, RB = 0, WR = 0, TE = 0)
  u1 <- val_lineup_value(val_team_tops(which(sim$players$player_id %in% c("QB1", "RB1", "WR1", "TE1")), sim, spec), st, spec, sim$sims)
  u2 <- val_lineup_value(val_team_tops(seq_len(5), sim, spec), st, spec, sim$sims)
  expect_equal(u1, 18 + 25, tolerance = 0.03)          # QB1 plays half the time at 36
  expect_equal(u2 - u1, 0.5 * 12, tolerance = 0.03)     # QB2 starts when QB1 is out
})

test_that("generic draft fills every roster and takes the obvious best players first", {
  lg <- sim_league(teams = 2, bench = 1, flex = 0)
  pts <- c(QB1 = 22, QB2 = 18, QB3 = 9, RB1 = 20, RB2 = 14, RB3 = 6, WR1 = 19, WR2 = 13, WR3 = 7,
           TE1 = 12, TE2 = 8, TE3 = 3)
  sim <- val_sim_setup(det_weekly(pts, 1:2), sims = 1)
  ls <- val_league_sim(sim, lg, cand_per_pos = 3, pool = "simulation", max_iterations = 3)
  expect_equal(nrow(ls$rosters), 2 * val_roster_size(lg))
  expect_true(all(c("QB1", "RB1", "WR1", "TE1", "QB2", "RB2", "WR2", "TE2") %in% ls$rosters$player_id))
  expect_equal(as.vector(table(ls$rosters$team)), c(5, 5))
  # proportional pool: 4 positions x 1 starter each -> 25% each of 10 rostered (rounded)
  pp <- val_proportional_pool(sim, lg)
  expect_equal(unname(pp$counts[c("QB", "RB", "WR", "TE")]), rep(round(0.25 * 10), 4))
})

test_that("MRU is 0 for a player below the streaming level and positive for a clear upgrade", {
  lg <- sim_league(teams = 2, bench = 1, flex = 0)
  pts <- c(QB1 = 22, QB2 = 18, QB3 = 9, QB4 = 2, RB1 = 20, RB2 = 14, RB3 = 6, WR1 = 19, WR2 = 13, WR3 = 7,
           TE1 = 12, TE2 = 8, TE3 = 3, RB9 = 30)
  sim <- val_sim_setup(det_weekly(pts, 1:2), sims = 1)
  ls <- val_league_sim(sim, lg, cand_per_pos = 4)
  free <- setdiff(seq_len(nrow(sim$players)), ls$rosters$row)
  i_low <- which(sim$players$player_id == "QB4")
  if (i_low %in% free) expect_equal(val_mru(ls, i_low), 0)
  i_hi <- which(sim$players$player_id == "RB9")
  expect_gt(val_mru(ls, i_hi), 0)
})

test_that("2-for-1 accounting: the single-player side adds a free player, the pair side drops one", {
  # One RB slot, no FLEX, bench 1. X holds two 15-pt RBs; Y holds a 25-pt RB.
  # Streamer RB = 5, so VOR(A) = 20 = VOR(B) + VOR(C): naive sums call it fair.
  lg <- val_league(list(name = "c", teams = 2, bench = 1, regular_season_weeks = c(1, 1), playoff_weeks = c(2, 2),
                        slots = list(list(name = "RB", eligible = "RB", count = 1))))
  pts <- c(RBa = 25, RBb = 15, RBc = 15, RBd = 4, RBf = 5)
  sim <- val_sim_setup(det_weekly(pts, 1), sims = 1)
  spec <- val_lineup_spec(lg)
  rows <- function(ids) match(ids, sim$players$player_id)
  ls <- list(sim = sim, league = lg, spec = spec, stream = list(RB = 5),
             rosters = tibble::tibble(team = c(1L, 1L, 2L, 2L), row = rows(c("RBb", "RBc", "RBa", "RBd")),
                                      player_id = c("RBb", "RBc", "RBa", "RBd"), position = "RB"))
  ls$utility <- c(val_utility(ls, rows(c("RBb", "RBc"))), val_utility(ls, rows(c("RBa", "RBd"))))
  ex <- val_trade_eval(ls, 1, give = rows(c("RBb", "RBc")), get = rows("RBa"))
  ey <- val_trade_eval(ls, 2, give = rows("RBa"), get = rows(c("RBb", "RBc")))
  expect_equal(length(ex$rows), 2)              # roster size preserved
  expect_equal(sim$players$player_id[ex$added], "RBf")  # freed spot -> best free player
  expect_equal(length(ey$dropped), 1)           # one player too many -> forced drop
  expect_equal(ex$delta, 25 - 15)
  expect_equal(ey$delta, 15 - 25)
  # equal VOR sums, unequal roster value: consolidation favours the single better player
  expect_gt(ex$delta - ey$delta, 0)
  expect_error(val_trade_eval(ls, 1, give = rows("RBa"), get = rows("RBb")), "does not own")
})

test_that("league-size change: more teams lower the replacement level and raise VOR", {
  pts <- c(QB1 = 22, QB2 = 18, QB3 = 15, QB4 = 12, QB5 = 9, QB6 = 6, RB1 = 20, RB2 = 14, RB3 = 10, RB4 = 6, RB5 = 4,
           WR1 = 19, WR2 = 13, WR3 = 9, WR4 = 6, WR5 = 3, TE1 = 12, TE2 = 8, TE3 = 5, TE4 = 2)
  w <- det_weekly(pts, 1:2) |> dplyr::mutate(has_game = TRUE, proj_kind = "current_week", source = "toy")
  vor_top <- function(teams) {
    lg <- sim_league(teams = teams, bench = 1, flex = 0)
    sim <- val_sim_setup(dplyr::select(w, "player_id", "position", "week", "E", "A", "lvl"), sims = 1)
    pool <- sim$players$player_id[val_proportional_pool(sim, lg)$rows]
    b <- val_weekly_baselines(w, lg, pool)
    v <- val_player_values(val_weekly_values(w, b), lg, 1)
    v$vor[v$player_id == "QB1"]
  }
  expect_lt(vor_top(1), vor_top(2))
})
