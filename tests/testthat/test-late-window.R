# D1 late-window study (VL8). Synthetic data only.

test_that("kickoffs map to game slots in Eastern time", {
  k <- as.POSIXct(c("2026-10-16 00:15", "2026-10-18 17:00", "2026-10-18 20:25", "2026-10-19 00:20", "2026-10-20 00:15",
                    "2026-12-26 21:30"), tz = "UTC")
  expect_equal(lw_slot(k), c("Thu", "SunE", "SunL", "SNF", "MNF", "Thu"))
})

test_that("a trailing team swaps in a high-variance late player; an EV-leading one does not", {
  # players: 1-8 own starters (EV lineup), 9 own MNF bench (high variance), 10-17 opponent
  pos <- c("QB", "RB", "RB", "WR", "WR", "TE", "WR", "RB", "WR", "QB", "RB", "RB", "WR", "WR", "TE", "WR", "RB")
  slot_i <- c(rep(2L, 6), 5L, 2L, 5L, rep(2L, 8))                 # own WR 7 and bench WR 9 play Monday night
  base <- c(rep(12, 6), 8, 12, 7.9, rep(10, 8))                   # own team favoured by 12 before kickoff
  startable <- rep(TRUE, 17)
  tau <- POD_TAU
  q <- t(sapply(seq_along(base), function(i) base[i] + stats::qnorm(tau) * if (i == 9) 12 else 2))
  p_act <- rep(1, 17)
  y_trail <- c(rep(8, 6), 8, 8, 25, rep(9.5, 8))                  # after Sunday the team trails by 20 (56 v 76)
  r <- lw_team_week(1:9, 10:17, slot_i, y_trail, base, pos, startable, q, p_act, sims = 4000L, seed = 1L)
  expect_equal(r$swaps, 1L)
  expect_equal(r$swap_points, "SNF")                              # Monday players are still unlocked before SNF
  expect_equal(r$pts_lw - r$pts_ev, 25 - 8)
  expect_lt(r$margin_at_first_swap, 0)
  y_lead <- c(rep(15, 6), 8, 15, 25, rep(5, 8))                   # leading comfortably: keep the safe EV player
  r2 <- lw_team_week(1:9, 10:17, slot_i, y_lead, base, pos, startable, q, p_act, sims = 4000L, seed = 1L)
  expect_equal(r2$swaps, 0L)
  expect_equal(r2$win_lw, r2$win_ev)
})
