# Valuation: league settings, exact starter allocation, FLEX and exchange baselines.

toy_league <- function(teams = 2, flex = 1, bench = 2, superflex = 0) {
  slots <- list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 2),
                list(name = "WR", eligible = "WR", count = 2), list(name = "TE", eligible = "TE", count = 1))
  if (flex > 0) slots <- c(slots, list(list(name = "FLEX", eligible = c("RB", "WR", "TE"), count = flex)))
  if (superflex > 0) slots <- c(slots, list(list(name = "SUPERFLEX", eligible = c("QB", "RB", "WR", "TE"), count = superflex)))
  val_league(list(name = "toy", teams = teams, slots = slots, bench = bench,
                  regular_season_weeks = c(1, 14), playoff_weeks = c(15, 17)))
}

# Known pool: values chosen so the optimum is obvious by hand.
toy_pool <- function() {
  tibble::tibble(
    player_id = c(paste0("q", 1:4), paste0("r", 1:6), paste0("w", 1:6), paste0("t", 1:3)),
    position = rep(c("QB", "RB", "WR", "TE"), c(4, 6, 6, 3)),
    E = c(20, 18, 15, 10, 15, 14, 13, 12, 9, 5, 16, 13, 11, 10, 8, 4, 10, 7, 3)
  )
}

test_that("league config is validated and sensitivity overrides apply", {
  cfg <- read_valuation_config(file.path(project_root, "config", "valuation.yml"))
  lg <- cfg$league
  expect_equal(lg$teams, 10L)
  expect_equal(val_starters_per_team(lg), 7L)
  expect_equal(val_roster_size(lg), 14L)
  expect_true(val_slots_laminar(lg))
  l12 <- val_league_override(lg, list(teams = 12), "t12")
  expect_equal(l12$teams, 12L)
  expect_equal(names(l12$slots), names(lg$slots))
  nf <- val_league_override(lg, cfg$sensitivity_leagues$no_flex)
  expect_false("FLEX" %in% names(nf$slots))
  expect_error(val_league(list(teams = 10, slots = list(list(name = "K", eligible = "K", count = 1)),
                               regular_season_weeks = c(1, 14), playoff_weeks = c(15, 17))))
  expect_false(identical(val_league_hash(lg), val_league_hash(l12)))
})

test_that("horizon weeks respect the current week and the segments", {
  lg <- toy_league()
  expect_equal(val_horizon_weeks(lg, 5, "regular"), 5:14)
  expect_equal(val_horizon_weeks(lg, 5, "playoffs"), 15:17)
  expect_equal(val_horizon_weeks(lg, 5, "full"), 5:17)
  expect_equal(val_horizon_weeks(lg, 16, "regular"), integer(0))
  expect_equal(val_horizon_weeks(lg, 16, "full"), 16:17)
})

test_that("Hall condition decides seatability", {
  h <- val_hall_table(toy_league())
  expect_true(val_seatable(c(QB = 2, RB = 5, WR = 5, TE = 2), h))   # 1 RB + 1 WR in FLEX
  expect_false(val_seatable(c(QB = 2, RB = 7, WR = 4, TE = 2), h))  # 3 RBs need FLEX, only 2 FLEX
  expect_false(val_seatable(c(QB = 3, RB = 0, WR = 0, TE = 0), h))  # QB is not FLEX-eligible
  expect_true(val_seatable(c(QB = 2, RB = 4, WR = 4, TE = 4), h))   # 2 TEs in FLEX
})

test_that("allocation is the exact optimum with FLEX filled by the best remaining RB/WR/TE", {
  d <- toy_pool()
  lg <- toy_league()
  st <- val_allocate(d$E, d$position, val_hall_table(lg))
  expect_setequal(d$player_id[st], c("q1", "q2", "r1", "r2", "r3", "r4", "r5", "w1", "w2", "w3", "w4", "w5", "t1", "t2"))
  slot <- val_assign_slots(d$E, d$position, st, lg)
  expect_setequal(d$player_id[slot %in% "FLEX"], c("r5", "w5"))
  # brute force over FLEX fillers confirms optimality
  rest <- d[!d$position %in% "QB" & !d$player_id %in% c("r1", "r2", "r3", "r4", "w1", "w2", "w3", "w4", "t1", "t2"), ]
  best <- max(utils::combn(rest$E, 2, sum))
  expect_equal(sum(d$E[slot %in% "FLEX"]), best)
})

test_that("exchange baselines: FLEX equalizes RB/WR, TE keeps its own", {
  d <- toy_pool()
  h <- val_hall_table(toy_league())
  st <- val_allocate(d$E, d$position, h)
  b <- val_exchange_baselines(d$E, d$position, st, !st, h)$baseline
  expect_equal(unname(b[c("QB", "RB", "WR", "TE")]), c(15, 5, 5, 3))
  # without FLEX every position keeps its own next player
  h0 <- val_hall_table(toy_league(flex = 0))
  st0 <- val_allocate(d$E, d$position, h0)
  b0 <- val_exchange_baselines(d$E, d$position, st0, !st0, h0)$baseline
  expect_equal(unname(b0[c("QB", "RB", "WR", "TE")]), c(15, 9, 8, 3))
})

test_that("TE baseline joins the FLEX baseline when a TE sits in FLEX", {
  d <- toy_pool()
  d$E[d$player_id == "t3"] <- 9.5  # now t3 beats r5/w5... and takes a FLEX spot
  h <- val_hall_table(toy_league())
  st <- val_allocate(d$E, d$position, h)
  expect_true(st[d$player_id == "t3"])
  b <- val_exchange_baselines(d$E, d$position, st, !st, h)$baseline
  expect_equal(unname(b["TE"]), unname(b["RB"]))
})

test_that("superflex lets QBs fill the extra slot and links the QB baseline", {
  d <- toy_pool()
  h <- val_hall_table(toy_league(superflex = 1))
  st <- val_allocate(d$E, d$position, h)
  # both SUPERFLEX spots go to QBs: q3 (15) and q4 (10, ahead of tied w4/t1 by order)
  expect_true(all(st[d$player_id %in% c("q1", "q2", "q3", "q4")]))
  b <- val_exchange_baselines(d$E, d$position, st, !st, h)$baseline
  # no QB is left, so a departing QB is replaced through SUPERFLEX by the best
  # flex-eligible non-starter (r6 = 5): the QB baseline joins the RB/WR one
  expect_equal(unname(b["QB"]), 5)
  expect_equal(unname(b["QB"]), unname(b["RB"]))
})

test_that("league size changes starters and baselines monotonically", {
  d <- toy_pool()
  b1 <- val_exchange_baselines(d$E, d$position, val_allocate(d$E, d$position, val_hall_table(toy_league(teams = 1))),
                               !val_allocate(d$E, d$position, val_hall_table(toy_league(teams = 1))),
                               val_hall_table(toy_league(teams = 1)))$baseline
  b2 <- val_exchange_baselines(d$E, d$position, val_allocate(d$E, d$position, val_hall_table(toy_league(teams = 2))),
                               !val_allocate(d$E, d$position, val_hall_table(toy_league(teams = 2))),
                               val_hall_table(toy_league(teams = 2)))$baseline
  expect_true(all(b2 <= b1))
})

test_that("weekly baselines: byes change the starters, waiver baseline uses only non-rostered players", {
  d <- toy_pool()
  weekly <- dplyr::bind_rows(dplyr::mutate(d, week = 5L),
                             dplyr::mutate(d, week = 6L, E = ifelse(player_id == "q1", 0, E)))  # q1 bye in week 6
  lg <- toy_league()
  rostered <- c("q1", "q2", "q3", paste0("r", 1:5), paste0("w", 1:5), "t1", "t2")
  b <- val_weekly_baselines(weekly, lg, rostered)
  s5 <- dplyr::filter(b, week == 5)
  s6 <- dplyr::filter(b, week == 6)
  expect_equal(s5$S[s5$position == "QB"], 15)
  expect_equal(s6$S[s6$position == "QB"], 10)            # q3 now starts, q4 is next
  expect_equal(s5$R[s5$position == "QB"], 10)            # best non-rostered QB
  expect_equal(s5$W[s5$position == "RB"], 5)
  expect_equal(s5$R[s5$position == "RB"], 5)             # max(r6 5, w6 4, t3 3)
  expect_equal(s5$R[s5$position == "TE"], 3)
  expect_equal(s5$n_starters[s5$position == "RB"], 5)
  expect_equal(s5$n_in_multi_slots[s5$position == "RB"], 1)
})
