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

test_that("a P1 provider sets the current week's availability in the universe (VL3b)", {
  weekly <- tibble::tibble(player_id = rep(c("a", "b"), each = 2), week = rep(3:4, 2), has_game = TRUE, p_active = 1,
                           lvl = 10, availability_status = c("QUESTIONABLE", "NORMAL", "NORMAL", "NORMAL"))
  prior <- list(p_active = c(QUESTIONABLE = 0.71), default = 1, source = "prior")
  u0 <- sim_universe(weekly, c("a", "b"), c("WR", "RB"), 3:4, 3, prior)
  expect_equal(u0$A[, 1], c(0.71, 1))
  f <- function(id, status, position) ifelse(status == "QUESTIONABLE", 0.5, 1)
  u1 <- sim_universe(weekly, c("a", "b"), c("WR", "RB"), 3:4, 3, prior, p_active_fun = f)
  expect_equal(u1$A[, 1], c(0.5, 1))
  expect_equal(u1$A[, 2], c(1, 1))                              # later weeks keep the run's availability
})

# ---- S2 v1 resolver (VL6) ----

s2_state6 <- function(playoff_teams = 6, wins = rep(0L, 6), schedule_winners = NULL) {
  sched <- tibble::tibble(matchup_id = 1:3, matchup_period = 1L, home_team = c(1L, 3L, 5L), away_team = c(2L, 4L, 6L),
                          home_points = NA_real_, away_points = NA_real_, winner = "UNDECIDED", playoff_tier = "NONE")
  st <- tibble::tibble(team_id = 1:6, wins = wins, losses = 0L, ties = 0L, points_for = 0, playoff_seed = NA_integer_,
                       espn_playoff_pct = NA_real_)
  rules <- list(teams = 6L, regular_periods = 1L, playoff_teams = playoff_teams,
                matchup_periods = tibble::tibble(matchup_period = 1:4, scoring_periods = list(1L, 2L, 3L, 4L)))
  list(rules = rules, schedule = sched, standings = st, status = list(current_matchup_period = 1L), has_schedule = TRUE)
}

s2_scores <- function(m) array(m, c(6, 4, 1), dimnames = list(as.character(1:6), as.character(1:4), NULL))

test_that("S2 v1 reproduces S0's resolver exactly on the owner's format", {
  sc <- ss_run(sims = 800)$base
  a <- sim_resolve(sc, ss_state(), 3L)
  b <- s2_resolve(sc, ss_state(), 3L)
  expect_identical(b$seed, a$seed)
  expect_identical(b$champion, a$champion)
  expect_identical(b$wins, a$wins)
  expect_identical(b$points_for, a$points_for)
})

test_that("6-team brackets give the top two seeds byes and follow the fixed bracket", {
  base <- c(100, 90, 80, 70, 60, 50)
  m <- cbind(base, base, base, base)
  sc <- s2_scores(m)
  r <- s2_resolve(sc, s2_state6(), 1L)
  # week 1: 1, 3, 5 win; seeds 1-3 = teams 1, 3, 5 (points), seeds 4-6 = teams 2, 4, 6
  expect_equal(as.vector(r$seed), c(1L, 4L, 2L, 5L, 3L, 6L))
  expect_equal(r$champion, 1L)
  m[2, 3] <- 150                                                  # team 2 (seed 4) upsets seed 1 in round 2
  r2 <- s2_resolve(s2_scores(m), s2_state6(), 1L)
  expect_equal(r2$champion, 2L)                                   # then beats team 3 (90 vs 80) in the final
})

test_that("division winners take the top seeds; head-to-head breaks ties on wins", {
  base <- c(100, 90, 80, 70, 60, 50)
  m <- cbind(base, base, base, base)
  st <- s2_state6(playoff_teams = 4, wins = c(3L, 2L, 1L, 0L, 0L, 0L))
  div <- c(`1` = "A", `2` = "A", `3` = "B", `4` = "B", `5` = "C", `6` = "C")
  r0 <- s2_resolve(s2_scores(m), st, 1L)
  expect_equal(as.vector(r0$seed)[1:3], c(1L, 2L, 3L))           # no divisions: team 2 is seed 2
  r1 <- s2_resolve(s2_scores(m), st, 1L, divisions = div)
  expect_equal(as.vector(r1$seed)[c(1, 3, 5, 2)], 1:4)            # winners 1, 3, 5 first; team 2 is the wild card
  # H2H: teams 3 and 4 end tied on wins (2 each); team 4 wins their week-1 game, team 3 has more points
  st2 <- s2_state6(playoff_teams = 4, wins = c(3L, 3L, 2L, 1L, 0L, 0L))
  st2$standings$points_for <- c(0, 0, 500, 400, 0, 0)
  m2 <- m
  m2[4, 1] <- 85                                                  # week 1: team 4 (85) beats team 3 (80)
  r_pts <- s2_resolve(s2_scores(m2), st2, 1L, tiebreak = "TOTAL_POINTS_SCORED")
  r_h2h <- s2_resolve(s2_scores(m2), st2, 1L, tiebreak = "H2H")
  expect_equal(c(r_pts$wins[3, 1], r_pts$wins[4, 1]), c(2, 2))
  expect_lt(r_pts$seed[3, 1], r_pts$seed[4, 1])                   # points: team 3 (580) above team 4 (485)
  expect_lt(r_h2h$seed[4, 1], r_h2h$seed[3, 1])                   # head to head: team 4 above team 3
})

test_that("D3: roster-change deltas are zero for no change and positive for an upgrade (common random numbers)", {
  uni <- ss_universe()
  uni$player_id <- c(uni$player_id, "fa")
  uni$position <- c(uni$position, "RB")
  uni$A <- rbind(uni$A, 0.95)
  uni$lvl <- rbind(uni$lvl, 30)
  cfg <- ss_config()
  spec <- val_lineup_spec(ss_league())
  stream <- lapply(as.character(uni$weeks), function(w) list(QB = 5, RB = 4, WR = 4)) |> rlang::set_names(as.character(uni$weeks))
  sig <- c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3)
  changes <- list(list(team = 2L, rows = cfg[["2"]]),
                  list(team = 2L, rows = c(cfg[["2"]][-2], length(uni$player_id))))
  d <- sim_roster_deltas(uni, cfg, changes, ss_state(), spec, stream, ss_table(), sig, sims = 1500L, chunk = 500L, seed = 3L)
  expect_equal(c(d$d_wins[1], d$d_playoffs[1], d$d_title[1]), c(0, 0, 0))
  expect_gt(d$d_title[2], 0)
  expect_gt(d$d_wins[2], 0)
  expect_equal(d$sum_p_playoffs, c(4, 4))
  expect_equal(d$sum_p_title, c(1, 1))
})

test_that("D2 v3: the title decomposition is exact, the Nash product needs two gains, rankings agree or not", {
  uni <- ss_universe()
  cfg <- ss_config()
  spec <- val_lineup_spec(ss_league())
  stream <- lapply(as.character(uni$weeks), function(w) list(QB = 5, RB = 4, WR = 4)) |> rlang::set_names(as.character(uni$weeks))
  sig <- c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3)
  trades <- list(list(team_a = 1L, rows_a = c(5L, 2L, 3L, 4L), team_b = 2L, rows_b = c(1L, 6L, 7L, 8L)))
  d <- sim_trade_deltas(uni, cfg, trades, ss_state(), spec, stream, ss_table(), sig, sims = 1500L, chunk = 500L, seed = 3L)
  expect_equal(d$d_title_a, d$p_title_a1 - d$p_title_a0)
  expect_equal(d$d_playoffs_b, d$p_playoffs_b1 - d$p_playoffs_b0)
  dec <- trade_title_decomposition(d, "a")
  expect_equal(dec$qualification + dec$playoff_strength, d$d_title_a)
  decb <- trade_title_decomposition(d, "b")
  expect_equal(decb$qualification + decb$playoff_strength, d$d_title_b)
  x <- tibble::tibble(d_playoffs_a = c(0.02, 0.02, -0.01), d_playoffs_b = c(0.03, -0.01, 0.05))
  expect_equal(trade_nash(x), c(0.0006, 0, 0))
  same <- x11_agreement(c(3, 2, 1, 0), c(0.3, 0.2, 0.1, 0))
  expect_equal(c(same$tau, same$top1_differs, same$top3_differs), c(1, 0, 0))
  rev <- x11_agreement(c(3, 2, 1, 0), c(0, 0.1, 0.2, 0.3))
  expect_equal(rev$tau, -1)
  expect_true(rev$top1_differs)
})

test_that("VL3c: no adopted cell leaves S0 bit-identical; an adopted cell widens only the current week", {
  uni <- ss_universe()
  cfg <- ss_config()
  base <- ss_run(sims = 1000, uni = uni)
  zero <- uni
  zero$extra_sd <- rep(0, length(uni$player_id))
  zero$extra_week <- 1L
  expect_identical(ss_run(sims = 1000, uni = zero), base)                  # an all-zero term changes nothing
  wide <- uni
  wide$extra_sd <- rep(6, length(uni$player_id))
  wide$extra_week <- 1L
  w <- ss_run(sims = 1000, uni = wide)
  v <- function(x, j) stats::var(as.vector(x$base[, j, ]))
  expect_gt(v(w, 1), v(base, 1))
  expect_identical(w$base[, 2:4, ], base$base[, 2:4, ])                    # later weeks are untouched
})

test_that("VL3c: the horizon hook maps leads to adopted cells and is inert without adoption", {
  ad <- tibble::tibble(position = c("WR", "WR", "RB"), lead_bin = c("72-120h", "<24h", "72-120h"),
                       spread_var = c(4, 0, 9), drift = 0)
  tg <- tibble::tibble(season = 2026L, week = 7L, team = c("AAA", "BBB"),
                       kickoff_utc = as.POSIXct(c("2026-10-25 17:00:00", "2026-10-21 12:00:00"), tz = "UTC"))
  now <- as.POSIXct("2026-10-21 00:00:00", tz = "UTC")
  f <- r3_horizon_sd_fun(ad, tg, 2026L, 7L, now)
  expect_equal(f(c("a", "b", "c", "d"), c("WR", "WR", "RB", "TE"), c("AAA", "BBB", "AAA", "AAA")), c(2, 0, 3, 0))
  expect_null(r3_horizon_sd_fun(dplyr::mutate(ad, spread_var = 0), tg, 2026L, 7L, now))
  expect_null(r3_horizon_sd_fun(NULL, tg, 2026L, 7L, now))
  w <- tibble::tibble(player_id = c("a", "b"), week = 7L, has_game = TRUE, p_active = 1, lvl = 10,
                      availability_status = "NORMAL", team = c("AAA", "BBB"))
  prior <- list(p_active = c(QUESTIONABLE = 0.71), default = 1, source = "prior")
  u <- sim_universe(w, c("a", "b"), c("WR", "WR"), 7:8, 7L, prior, horizon_sd_fun = f)
  expect_equal(u$extra_sd, c(2, 0))
  expect_equal(u$extra_week, 1L)
  expect_null(sim_universe(w, c("a", "b"), c("WR", "WR"), 7:8, 7L, prior)$extra_sd)
})

test_that("VL3d: K/D-ST draws leave skill scores bit-identical, add the same draws to every configuration and match v0", {
  uni <- ss_universe()
  cfg <- ss_config()
  up <- cfg
  up[["2"]] <- c(1L, up[["2"]])                                            # a different configuration
  base <- ss_run(sims = 1000, uni = uni, configs = list(a = cfg, b = up))
  kd <- list(tau = P2_TAU, q = list(K = stats::qnorm(P2_TAU, 8, 4), DST = stats::qnorm(P2_TAU, 6, 6)),
             n = c(K = 1L, DST = 1L), source = "test")
  ku <- uni
  ku$kdst <- kd
  with <- ss_run(sims = 1000, uni = ku, configs = list(a = cfg, b = up))
  da <- with$a - base$a
  expect_equal(da, with$b - base$b, tolerance = 1e-12)                     # common to every configuration
  expect_equal(mean(da), 14, tolerance = 0.03)
  expect_equal(stats::sd(as.vector(da)), sqrt(16 + 36), tolerance = 0.05)            # tails clipped at 1%/99%
  expect_identical(ss_run(sims = 1000, uni = ku, configs = list(a = cfg, b = up)), with)   # deterministic
  none <- uni
  none$kdst <- NULL
  expect_identical(ss_run(sims = 1000, uni = none, configs = list(a = cfg, b = up)), base)
})

test_that("VL3d: K/D-ST parameters follow the league's starting slots; draws follow sim_qdraw's rule", {
  v0 <- list(version = "kdst_v0", tau = POD_TAU, K = stats::qnorm(POD_TAU, 8, 4), DST = stats::qnorm(POD_TAU, 6, 6))
  expect_null(kdst_sim_params(list(nonskill_starters = list()), v0))
  p <- kdst_sim_params(list(nonskill_starters = list(`D/ST` = 1L, K = 2L)), v0)
  expect_equal(p$n, c(K = 2L, DST = 1L))
  expect_equal(p$source, "kdst_v0")
  u <- c(0, 0.005, 0.01, 0.237, 0.5, 0.99, 0.999, 1)
  expect_equal(kdst_qdraw(v0$K, u, v0$tau), sim_qdraw(matrix(v0$K, length(u), length(v0$tau), byrow = TRUE), u, v0$tau))
  f <- read_kdst_v0(file.path(project_root, KDST_V0_FILE))
  expect_equal(f$seasons, 2019:2023)
  expect_length(f$K, length(f$tau))
  expect_true(all(diff(f$K) >= 0) && all(diff(f$DST) >= 0))
})
