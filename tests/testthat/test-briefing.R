# D5 weekly briefing (VL13): helpers and the name-free console summary. Synthetic inputs only.

test_that("fragility flags a change of the best item under any alternative", {
  expect_false(d5_fragile(3L, c(3L, 3L, 3L)))
  expect_true(d5_fragile(3L, c(3L, 5L, 3L)))
  expect_true(d5_fragile(3L, c(3L, NA)))
  expect_false(d5_fragile(3L, integer()))
  adv <- list(lineup = tibble::tibble(player_id = c("b", "a", "c", "d"), slot = c("QB", "RB", "BE", "IR")))
  expect_equal(d5_starters(adv), c("a", "b"))
  expect_named(D5_ALTERNATIVES, c("sigma_x0.5", "sigma_x1.5", "noise_x0.8", "noise_x1.2", "seed_2"))
})

test_that("the console summary carries counts and flags but no team or player names", {
  b <- list(team = 3L, week = 6L,
            lineup = list(changes = 2L, fragile = TRUE, adv = list(ev_recommended = 101.4, ev_current = 98.2)),
            odds = list(od = list(results = list(base = list(teams = tibble::tibble(team_id = c(3L, 4L), p_playoffs = c(0.61, 0.4),
                                                                                         p_title = c(0.18, 0.1)))))),
            waivers = list(board = tibble::tibble(add = "Secret Player", d_playoffs = c(0.021)), fragile = FALSE),
            trades = list(n = 12L, top = tibble::tibble(a_gives = "Secret Player", d_title_a = 0.012), fragile = TRUE),
            health = tibble::tibble(level = c("OK", "OK", "WARN")), ledger = c("id1", "id2"),
            team_label = "Secret Team")
  out <- paste(d5_console(b, "data/archive/briefings/x.md"), collapse = "\n")
  expect_false(grepl("Secret", out))
  expect_match(out, "Lineup: 2 change\\(s\\); EV \\+3.2 vs current; FRAGILE")
  expect_match(out, "P\\(playoffs\\) 0.610, P\\(title\\) 0.180")
  expect_match(out, "Trades: 12 re-scored; best dP\\(title\\) \\+0.012; FRAGILE")
  expect_match(out, "Health: 2 OK, 1 WARN, 0 ALERT")
})
