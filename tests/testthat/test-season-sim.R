# S0 shadow league simulator (master plan S0, VL3). Synthetic leagues only.

ss_league <- function() {
  val_league(list(name = "toy", teams = 6, slots = list(list(name = "QB", eligible = "QB", count = 1),
                                                       list(name = "RB", eligible = "RB", count = 1),
                                                       list(name = "WR", eligible = "WR", count = 1)),
                  bench = 1, regular_season_weeks = c(1, 3), playoff_weeks = c(4, 6)))
}

#' A residual table with normal residuals (SD 3) for every position and band.
ss_table <- function(sd = 3) {
  tibble::tibble(position = POD_POSITIONS, band_lo = 1L, band_hi = 7L, label = "all", n = 1000L, sd = sd,
                 q = rep(list(stats::qnorm(POD_TAU, 0, sd)), 4), floor = -5)
}

#' Six teams; periods 1-2 played (records), period 3 left; semis period 4 (week 4), final period 5 (weeks 5-6).
ss_state <- function() {
  sched <- tibble::tibble(matchup_id = 1:9, matchup_period = rep(1:3, each = 3),
                          home_team = c(1L, 3L, 5L, 1L, 2L, 4L, 1L, 2L, 3L),
                          away_team = c(2L, 4L, 6L, 3L, 5L, 6L, 6L, 4L, 5L),
                          home_points = NA_real_, away_points = NA_real_, winner = c(rep("HOME", 6), rep("UNDECIDED", 3)),
                          playoff_tier = "NONE")
  st <- tibble::tibble(team_id = 1:6, wins = c(2L, 0L, 1L, 2L, 1L, 0L), losses = c(0L, 2L, 1L, 0L, 1L, 2L), ties = 0L,
                       points_for = c(250, 180, 210, 240, 210, 190), playoff_seed = NA_integer_, espn_playoff_pct = NA_real_)
  rules <- list(teams = 6L, regular_periods = 3L, playoff_teams = 4L,
                matchup_periods = tibble::tibble(matchup_period = 1:5, scoring_periods = list(1L, 2L, 3L, 4L, c(5L, 6L))))
  list(rules = rules, schedule = sched, standings = st, status = list(current_matchup_period = 3L), has_schedule = TRUE)
}

#' Universe: each team has a QB, an RB, a WR and a bench RB; team 1 is much stronger.
ss_universe <- function(weeks = 3:6) {
  pos <- rep(c("QB", "RB", "WR", "RB"), 6)
  lvl <- rep(c(18, 12, 12, 6), 6) * rep(c(1.6, 1, 1, 1, 1, 1), each = 4)
  n <- length(pos)
  list(player_id = paste0("p", seq_len(n)), position = pos, weeks = weeks,
       A = matrix(0.95, n, length(weeks)), lvl = matrix(lvl, n, length(weeks)))
}

ss_config <- function() lapply(1:6, function(t) (t - 1) * 4 + 1:4) |> rlang::set_names(as.character(1:6))

ss_run <- function(seed = 1, sims = 2000, configs = list(base = ss_config()), uni = ss_universe()) {
  spec <- val_lineup_spec(ss_league())
  stream <- lapply(as.character(uni$weeks), function(w) list(QB = 5, RB = 4, WR = 4)) |> rlang::set_names(as.character(uni$weeks))
  sim_scores(uni, configs, spec, stream, ss_table(), c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3), sims = sims, chunk = 500, seed = seed)
}

test_that("lineups are chosen on decision values and scored on realised values; empty slots stream", {
  spec <- val_lineup_spec(ss_league())
  pos <- c("QB", "RB", "RB", "WR")
  dec <- matrix(c(20, 10, 8, 0), 4, 1)          # WR inactive (decision value 0)
  real <- matrix(c(25, 2, 20, 0), 4, 1)         # the benched RB would have scored 20
  tot <- sim_team_week(1:4, dec, real, pos, spec, list(QB = 5, RB = 4, WR = 7))
  expect_equal(tot, 25 + 2 + 7)                  # QB realised, RB chosen on decision (realised 2), WR streamed
})

test_that("season resolution: ties count half, seeds by wins then points, 1 v 4 and 2 v 3, final summed over two weeks", {
  st <- ss_state()
  sc <- array(0, c(6, 4, 1), dimnames = list(as.character(1:6), as.character(3:6), NULL))
  sc[, "3", 1] <- c(100, 90, 80, 80, 80, 60)     # period 3: 1 beats 6, 2 beats 4, 3 ties 5
  sc[, "4", 1] <- c(50, 99, 98, 60, 0, 0)        # semis (week 4)
  sc[, "5", 1] <- c(0, 40, 0, 50, 0, 0)          # final weeks 5 + 6
  sc[, "6", 1] <- c(0, 45, 0, 30, 0, 0)
  res <- sim_resolve(sc, st, 3L)
  # final wins: t1 3, t2 1, t3 1.5, t4 2, t5 1.5, t6 0
  expect_equal(res$wins[, 1], c(3, 1, 1.5, 2, 1.5, 0))
  # seeds: t1 (3), t4 (2), then t3 vs t5 at 1.5: points for 290 vs 290 -> team id breaks the tie -> t3
  expect_equal(res$seed[c(1, 4, 3, 5), 1], 1:4)
  # semis: seed1 t1 (50) v seed4 t5 (0) -> t1; seed2 t4 (60) v seed3 t3 (98) -> t3; final t1 0 v t3 0 -> tie -> higher seed t1
  expect_equal(res$champion, 1L)
  sc[, "5", 1] <- c(0, 0, 10, 0, 0, 0)
  expect_equal(sim_resolve(sc, st, 3L)$champion, 3L)
})

test_that("odds satisfy the invariants and a dominant team is a favourite", {
  sc <- ss_run()
  s <- sim_summarise(sim_resolve(sc$base, ss_state(), 3L), owner = 1L)
  expect_equal(unname(s$invariants["sum_p_playoffs"]), 4)
  expect_equal(unname(s$invariants["sum_p_title"]), 1)
  expect_equal(unname(colSums(s$teams[, paste0("p_seed", 1:4)])), rep(1, 4))
  t1 <- s$teams[s$teams$team_id == 1, ]
  expect_gt(t1$p_playoffs, 0.99)
  expect_gt(t1$p_title, 0.4)
  expect_equal(nrow(s$matchups), 3L)
  expect_true(is.data.frame(s$leverage))
  expect_lte(unname(s$invariants["max_mc_se"]), 0.0113)   # 2,000 sims: SE <= sqrt(0.25 / 2000)
})

test_that("runs are deterministic for a seed, differ across seeds, and leave the caller's RNG untouched", {
  set.seed(99)
  before <- stats::runif(1)
  set.seed(99)
  a <- ss_run(seed = 5, sims = 600)
  after <- stats::runif(1)
  expect_equal(before, after)                               # caller's stream restored
  b <- ss_run(seed = 5, sims = 600)
  expect_identical(a, b)
  c <- ss_run(seed = 6, sims = 600)
  expect_false(identical(a, c))
})

test_that("common random numbers: an identical what-if changes nothing; a real upgrade helps that team", {
  cfg <- ss_config()
  uni <- ss_universe()
  uni$player_id <- c(uni$player_id, "fa")
  uni$position <- c(uni$position, "RB")
  uni$A <- rbind(uni$A, 0.95)
  uni$lvl <- rbind(uni$lvl, 30)
  up <- cfg
  up[["2"]] <- c(cfg[["2"]][-2], length(uni$player_id))     # add a 30-point RB, drop the starter
  sc <- ss_run(sims = 1500, configs = list(base = cfg, same = cfg, upgrade = up), uni = uni)
  expect_identical(sc$base, sc$same)
  pb <- sim_summarise(sim_resolve(sc$base, ss_state(), 3L))$teams
  pu <- sim_summarise(sim_resolve(sc$upgrade, ss_state(), 3L))$teams
  expect_gt(pu$p_title[pu$team_id == 2], pb$p_title[pb$team_id == 2])
})

test_that("D2-thin: an identity trade changes nothing and a QB swap moves both teams' odds in opposite directions", {
  uni <- ss_universe()
  cfg <- ss_config()
  spec <- val_lineup_spec(ss_league())
  stream <- lapply(as.character(uni$weeks), function(w) list(QB = 5, RB = 4, WR = 4)) |> rlang::set_names(as.character(uni$weeks))
  sig <- c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3)
  trades <- list(list(team_a = 1L, rows_a = cfg[["1"]], team_b = 2L, rows_b = cfg[["2"]]),        # identity
                 list(team_a = 1L, rows_a = c(5L, 2L, 3L, 4L), team_b = 2L, rows_b = c(1L, 6L, 7L, 8L)))   # QBs swap
  d <- sim_trade_deltas(uni, cfg, trades, ss_state(), spec, stream, ss_table(), sig, sims = 1500L, chunk = 500L, seed = 3L)
  expect_equal(c(d$d_wins_a[1], d$d_playoffs_a[1], d$d_title_a[1], d$d_title_b[1]), c(0, 0, 0, 0))
  expect_lt(d$d_title_a[2], 0)                                    # team 1 gives the best QB
  expect_gt(d$d_title_b[2], 0)
  expect_equal(d$sum_p_playoffs, c(4, 4))
  expect_equal(d$sum_p_title, c(1, 1))
})

test_that("the partner-lens frontier keeps only non-dominated trades", {
  d <- tibble::tibble(trade = 1:5, d_title_a = c(0.05, 0.03, 0.05, 0.01, -0.01), partner_lens_b = c(2, 5, 1, 4, 9))
  f <- trade_frontier(d)
  expect_equal(f$trade, c(1, 2, 5))
})
