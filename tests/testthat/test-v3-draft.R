# D4 draft assistant (VL10). Synthetic pools only.

d4_toy_league <- function(teams = 4) {
  val_league(list(name = "toy", teams = teams,
                  slots = list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 1),
                               list(name = "WR", eligible = "WR", count = 1),
                               list(name = "FLEX", eligible = c("RB", "WR"), count = 1)),
                  bench = 2, regular_season_weeks = c(1, 3), playoff_weeks = c(4, 4)))
}

d4_toy_weekly <- function(seed = 1, weeks = 1:4) {
  set.seed(seed)
  counts <- c(QB = 10, RB = 16, WR = 16)
  pl <- tibble::tibble(position = rep(names(counts), counts)) |>
    dplyr::mutate(player_id = sprintf("%s%02d", .data$position, dplyr::row_number()),
                  level = stats::rgamma(dplyr::n(), 4, 4 / c(QB = 16, RB = 9, WR = 9)[.data$position]))
  tidyr::expand_grid(pl, week = weeks) |>
    dplyr::mutate(A = stats::runif(dplyr::n(), 0.8, 1), lvl = .data$level, E = .data$A * .data$lvl, has_game = TRUE,
                  p_active = .data$A, availability_status = "NORMAL") |>
    dplyr::select("player_id", "position", "week", "E", "A", "lvl", "has_game", "p_active", "availability_status")
}

d4_toy_pool <- function(seed = 1, teams = 4) {
  lg <- d4_toy_league(teams)
  wk <- d4_toy_weekly(seed)
  sim <- val_sim_setup(wk, 20, 1)
  spec <- val_lineup_spec(lg)
  init <- val_proportional_pool(sim, lg)
  stream <- val_stream_vectors(val_waiver_levels(sim, init$rows), sim, spec$positions)
  vor <- sim$ros - stats::ave(sim$ros, sim$players$position, FUN = function(x) sort(x, decreasing = TRUE)[min(length(x), 8)])
  list(sim = sim, spec = spec, stream = stream, vor = vor, rank = rank(-vor, ties.method = "first"), pos = sim$players$position,
       rows = seq_len(nrow(sim$players)), league = lg, rounds = val_roster_size(lg), weekly = wk)
}

test_that("snake order, unfilled slots and the opponents' allowed positions", {
  expect_equal(d4_snake(4, 3), c(1:4, 4:1, 1:4))
  spec <- val_lineup_spec(d4_toy_league())
  expect_equal(d4_unfilled(c("RB", "RB"), spec), list("QB", "WR"))
  expect_length(d4_unfilled(c("QB", "RB", "WR", "WR"), spec), 0)
  expect_false("QB" %in% d4_allowed(c("QB", "QB"), 5, spec, late = FALSE))
  expect_true("QB" %in% d4_allowed(c("QB", "QB"), 5, spec, late = TRUE, caps = c(QB = 2L)))
  expect_setequal(d4_allowed(c("RB", "RB"), 2, spec, late = FALSE), c("QB", "WR"))
})

test_that("opponents draw by rank with herding, from the supplied uniform", {
  pool <- d4_toy_pool()
  avail <- pool$rows
  best <- avail[which.min(pool$rank[avail])]
  expect_equal(d4_opponent_pick(avail, pool, pool$spec$positions, character(), u = 0), best)
  far <- d4_opponent_pick(avail, pool, pool$spec$positions, character(), u = 0.999)
  expect_gt(pool$rank[far], pool$rank[best])
  qb_only <- d4_opponent_pick(avail, pool, "QB", character(), u = 0.5)
  expect_equal(pool$pos[qb_only], "QB")
  # herding: after two RB picks, RBs get more probability mass
  set.seed(4)
  u <- stats::runif(2000)
  share <- function(recent) mean(pool$pos[vapply(u, function(x) d4_opponent_pick(avail, pool, pool$spec$positions, recent, x), 0L)] == "RB")
  expect_gt(share(c("RB", "RB")), share(c("WR", "QB")))
})

test_that("mock drafts fill every roster, share the opponents' randomness, and the assistant scores rollouts", {
  pool <- d4_toy_pool(2)
  v <- d4_mock_draft(pool, seat = 2, policy = "vor", seed = 7)
  a <- d4_mock_draft(pool, seat = 2, policy = "assistant", seed = 7, rollouts = 5, per_pos = 2)
  expect_true(all(lengths(v$rosters) == pool$rounds))
  expect_false(anyDuplicated(unlist(a$rosters)) > 0)
  expect_identical(v$rosters[[1]][1], a$rosters[[1]][1])        # pick 1 precedes the owner's first pick
  expect_identical(v, d4_mock_draft(pool, seat = 2, policy = "vor", seed = 7))
  rec <- d4_recommend(replicate(4, integer(), simplify = FALSE), integer(), 1L, d4_snake(4, pool$rounds), 1L, pool,
                      rollouts = 6, per_pos = 2)
  expect_equal(nrow(rec), 6)
  expect_true(all(diff(rec$mean_u) <= 0))
  expect_true(all(rec$survival_next >= 0 & rec$survival_next <= 1))
})

test_that("week-0 odds satisfy the invariants", {
  pool <- d4_toy_pool(3)
  d <- d4_mock_draft(pool, seat = 1, policy = "vor", seed = 3)
  tab <- tibble::tibble(position = POD_POSITIONS, band_lo = 1L, band_hi = 7L, label = "all", n = 1000L, sd = 3,
                        q = rep(list(stats::qnorm(POD_TAU, 0, 3)), 4), floor = -5)
  o <- d4_week0_odds(d$rosters, pool, pool$weekly, tab, c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3), playoff_teams = 2L, sims = 300L)
  expect_equal(sum(o$p_playoffs), 2)
  expect_equal(sum(o$e_wins), 4 * 3 / 2)
})

test_that("week-0 odds follow a supplied schedule", {
  pool <- d4_toy_pool(5)
  d <- d4_mock_draft(pool, seat = 1, policy = "vor", seed = 5)
  tab <- tibble::tibble(position = POD_POSITIONS, band_lo = 1L, band_hi = 7L, label = "all", n = 1000L, sd = 3,
                        q = rep(list(stats::qnorm(POD_TAU, 0, 3)), 4), floor = -5)
  sig <- c(QB = 0.3, RB = 0.3, WR = 0.3, TE = 0.3)
  same <- rep(list(rbind(c(1L, 2L), c(3L, 4L))), 3)          # 1 v 2 and 3 v 4 every week
  o <- d4_week0_odds(d$rosters, pool, pool$weekly, tab, sig, playoff_teams = 2L, sims = 300L, schedule = same)
  expect_equal(o$e_wins[1] + o$e_wins[2], 3)
  expect_equal(o$e_wins[3] + o$e_wins[4], 3)
  expect_error(d4_week0_odds(d$rosters, pool, pool$weekly, tab, sig, sims = 10L, schedule = same[1:2]), "one matrix per")
})

test_that("live state: the snake order, K/D-ST reservations and skill rosters follow the pick log", {
  picks <- tibble::tibble(seat = c(1L, 2L, 3L, 4L, 4L), row = c(10L, 20L, NA, 30L, 31L))
  s <- d4_live_state(picks, teams = 4, skill_rounds = 2, n_nonskill = 2)
  expect_equal(s$rosters[[4]], c(30L, 31L))
  expect_equal(s$rosters[[3]], integer())
  expect_equal(s$taken, c(10L, 20L, 30L, 31L))
  expect_equal(s$on_clock, 3L)
  # team 3 already used one K/D-ST pick, so only its last remaining pick is reserved; others keep their last two
  full <- d4_snake(4, 4)
  expect_equal(s$order, c(full[1:5], 3L, 2L, 1L, 3L))         # each team ends with exactly 2 skill picks
  expect_true(s$next_is_skill)
  expect_error(d4_live_state(tibble::tibble(seat = 2L, row = 1L), 4, 2), "snake order")
  # the last picks of the draft are K/D-ST for everyone
  done <- tibble::tibble(seat = full[1:8], row = 1:8)
  s2 <- d4_live_state(done, 4, 2)
  expect_false(s2$next_is_skill)
})
