# Valuation V2: ESPN league ingestion, team utility, trades, search, archive.

# ---- toy league helpers (deterministic: one draw, every player active) ----------------
toy_lg_league <- function(slots = list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 1),
                                       list(name = "WR", eligible = "WR", count = 1),
                                       list(name = "FLEX", eligible = c("RB", "WR"), count = 1)),
                          bench = 1, ir = 1, limits = list()) {
  lg <- val_league(list(name = "toy", teams = 2, slots = slots, bench = bench,
                        regular_season_weeks = c(1, 1), playoff_weeks = c(2, 2)))
  lg$roster_size <- val_starters_per_team(lg) + bench
  lg$ir_slots <- ir
  lg$position_limits <- limits
  lg$nonskill_starters <- list()
  lg
}

#' players: named numeric vector of weekly points; names "<team>_<pos>_<label>" where team is
#' 1, 2 or F (free agent). byes: list(player = week) for zero weeks.
toy_lg <- function(players, weeks = 1, byes = list(), ir = character(), league = toy_lg_league(), policy = "empty_slots") {
  nm <- names(players)
  info <- tibble::tibble(key = nm, team = sub("_.*", "", nm), position = sub("^[^_]+_([A-Z]+)_.*$", "\\1", nm))
  weekly <- tidyr::expand_grid(info, week = weeks) |>
    dplyr::mutate(player_id = .data$key, espn_id = .data$key, player_name = .data$key, team_nfl = "AAA",
                  proj = unname(players[.data$key]), has_game = TRUE)
  for (b in names(byes)) weekly$proj[weekly$key == b & weekly$week == byes[[b]]] <- 0
  weekly <- dplyr::transmute(weekly, .data$player_id, .data$espn_id, .data$player_name, .data$position, team = .data$team_nfl,
                             .data$week, .data$proj, p_active = as.numeric(.data$proj > 0), lvl = .data$proj, has_game = .data$proj > 0)
  roster <- info |>
    dplyr::filter(.data$team != "F") |>
    dplyr::transmute(team_id = as.integer(.data$team), espn_id = .data$key, player_name = .data$key, .data$position,
                     nfl_team = "AAA", is_skill = TRUE, is_ir_slot = .data$key %in% ir,
                     lineup_slot_id = ifelse(.data$key %in% ir, 21L, 20L))
  gen <- tibble::tibble(player_id = nm, vor = unname(players), trade_value = unname(players), overall_rank = 1L, position_rank = 1L)
  teams <- tibble::tibble(team_id = 1:2, team_abbrev = c("ONE", "TWO"), team_name = c("Team One", "Team Two"), owners = c("{S1}", "{S2}"))
  lg_model(weekly, roster, league, min(weeks), policy = policy, sims = 1, seed = 1, generic = gen, teams = teams)
}

base_players <- c(`1_QB_a1` = 20, `1_RB_a2` = 15, `1_WR_a3` = 12, `1_RB_a4` = 10, `1_WR_a5` = 6,
                  `2_QB_b1` = 18, `2_RB_b2` = 8, `2_WR_b3` = 16, `2_WR_b4` = 11, `2_RB_b5` = 5,
                  `F_QB_f1` = 12, `F_RB_f2` = 7, `F_WR_f3` = 8)

test_that("team utility is the optimal lineup from rostered players (bench excluded)", {
  m <- toy_lg(base_players)
  expect_equal(m$base[["1"]]$U, 20 + 15 + 12 + 10)
  expect_equal(m$base[["2"]]$U, 18 + 8 + 16 + 11)
  expect_equal(sort(m$sim$players$player_id[m$fa_rows]), c("F_QB_f1", "F_RB_f2", "F_WR_f3"))
  a <- lg_attribution(m, m$state[["1"]]$rows)
  expect_equal(a$players$started_pts[a$players$player_id == "1_WR_a5"], 0)  # bench
  expect_equal(a$players$starts[a$players$player_id == "1_RB_a4"], 1)       # FLEX starter
  expect_equal(unname(a$slot_points["FLEX"]), 10)
})

test_that("1-for-1: positional need emerges from the lineup, no multipliers", {
  m <- toy_lg(base_players)
  tr <- lg_trade(m, "Team One", "1_RB_a4", "Team Two", "1_WR_b3" |> sub(pattern = "1_", replacement = "2_"))
  d <- tr$teams
  expect_equal(d$delta[d$team_id == 1], (20 + 15 + 16 + 12) - 57)   # WR b3 starts, a3 moves to FLEX
  expect_equal(d$delta[d$team_id == 2], (18 + 10 + 11 + 8) - 53)    # RB a4 starts, FLEX falls to RB b2
  expect_equal(tr$metrics$surplus, 6 - 6)
  expect_equal(tr$metrics$classification, "favors A")                # balance 12: above eps (5), below strong (20)
})

test_that("2-for-1: forced drop on the receiving side, empty slots streamed, no worthless add", {
  m <- toy_lg(base_players)
  tr <- lg_trade(m, 1, c("1_WR_a3", "1_WR_a5"), 2, "2_QB_b1")
  d <- tr$teams
  # Team One has no WR left: the empty WR slot streams the best free-agent WR (8); adding f3 gains nothing
  expect_equal(d$U_after[d$team_id == 1], 20 + 15 + 8 + 10)
  expect_equal(d$added[d$team_id == 1], "")
  # Team Two receives two players for one: roster 6 > 5, drops its least useful bench player (RB b5)
  expect_equal(d$dropped[d$team_id == 2], "2_RB_b5")
  expect_equal(d$U_after[d$team_id == 2], 12 + 8 + 16 + 12)          # QB slot now streamed at 12, a3 into FLEX
  expect_true("2_RB_b5" %in% m$sim$players$player_id[tr$transaction$fa_rows])
  expect_true(any(grepl("must drop 2_RB_b5", tr$explanations)))
})

test_that("an open roster spot is filled when a free agent adds utility", {
  # Team One gives two bench-level players; a free agent WR better than its FLEX starter is available
  p <- base_players
  p[["F_WR_f3"]] <- 13
  m <- toy_lg(p)
  tr <- lg_trade(m, 1, c("1_RB_a4", "1_WR_a5"), 2, "2_RB_b5")
  d <- tr$teams
  expect_equal(d$added[d$team_id == 1], "F_WR_f3")
  expect_gt(d$add_gain[d$team_id == 1], 0)
  expect_true(any(grepl("fills the open roster spot with free agent F_WR_f3", tr$explanations)))
})

test_that("impossible trades are rejected and invariants hold", {
  m <- toy_lg(base_players)
  expect_error(lg_trade(m, 1, "2_QB_b1", 2, "1_QB_a1"), "does not own")
  expect_error(lg_trade(m, 1, "1_QB_a1", 1, "1_RB_a2"), "itself")
  expect_error(lg_trade(m, 1, character(), 2, "2_QB_b1"), "at least one")
  expect_error(lg_trade(m, 1, c("1_QB_a1", "1_QB_a1"), 2, "2_QB_b1"), "twice")
  expect_error(lg_trade(m, 1, "nobody", 2, "2_QB_b1"), "not found")
  tr <- lg_trade(m, 1, c("1_WR_a3", "1_WR_a5"), 2, "2_QB_b1")
  expect_true(lg_check_invariants(m, tr$transaction, 1, tr$gives$a, 2, tr$gives$b))
  # deterministic for a fixed snapshot and configuration
  tr2 <- lg_trade(m, 1, c("1_WR_a3", "1_WR_a5"), 2, "2_QB_b1")
  expect_identical(tr$teams$delta, tr2$teams$delta)
})

test_that("3-for-1 and 1-for-3 resolve to legal rosters", {
  m <- toy_lg(base_players)
  tr <- lg_trade(m, 1, c("1_RB_a4", "1_WR_a5", "1_WR_a3"), 2, "2_WR_b3")
  expect_lte(length(tr$transaction$b$rows), lg_capacity(m, 2))
  expect_equal(length(tr$transaction$b$dropped), 2)
  expect_true(lg_check_invariants(m, tr$transaction, 1, tr$gives$a, 2, tr$gives$b))
})

test_that("position limits force the drop at the over-limit position", {
  lg <- toy_lg_league(limits = list(QB = 1))
  m <- toy_lg(base_players, league = lg)
  tr <- lg_trade(m, 1, "1_RB_a4", 2, "2_QB_b1")
  expect_equal(tr$teams$dropped[tr$teams$team_id == 1], "2_QB_b1")  # keeps the better QB a1
})

test_that("IR-slot players do not use roster capacity", {
  p <- c(base_players, `1_WR_ir1` = 0)
  m <- toy_lg(p, ir = "1_WR_ir1")
  expect_equal(length(m$state[["1"]]$rows), 5)
  expect_equal(m$state[["1"]]$ir_rows, which(m$sim$players$player_id == "1_WR_ir1"))
  tr <- lg_trade(m, 1, "1_RB_a4", 2, "2_WR_b3")
  expect_equal(tr$teams$dropped[tr$teams$team_id == 1], "")
})

test_that("bye weeks: an uncovered bye is streamed only for that week; bench covers otherwise", {
  p <- c(base_players, `1_QB_a6` = 9)
  lg <- toy_lg_league(bench = 2)
  m0 <- toy_lg(p[names(p) != "1_QB_a6"], weeks = 1:2, byes = list(`1_QB_a1` = 2), league = lg)
  pw <- m0$base[["1"]]$per_week
  expect_equal(unname(pw["2"]), 12 + 15 + 12 + 10)   # QB bye: free agent f1 (12) streamed
  m1 <- toy_lg(p, weeks = 1:2, byes = list(`1_QB_a1` = 2), league = lg)
  pw1 <- m1$base[["1"]]$per_week
  expect_equal(unname(pw1["2"]), 9 + 15 + 12 + 10)    # bench QB a6 starts (no free streaming over a rostered player)
})

test_that("streaming policies: none leaves empty slots at 0, unlimited floors every slot", {
  p <- base_players[names(base_players) != "1_WR_a3" & names(base_players) != "1_WR_a5"]
  p <- c(p, `1_RB_a7` = 4)
  p[["F_WR_f3"]] <- 11
  m_e <- toy_lg(p, policy = "empty_slots")
  m_n <- toy_lg(p, policy = "none")
  m_u <- toy_lg(p, policy = "unlimited")
  expect_equal(m_e$base[["1"]]$U, 20 + 15 + 11 + 10)   # no WR rostered: WR slot streamed
  expect_equal(m_n$base[["1"]]$U, 20 + 15 + 0 + 10)
  expect_equal(m_u$base[["1"]]$U, 20 + 15 + 11 + 11)   # FLEX also floored by the free-agent WR (11 > 10)
})

test_that("superflex lets a second QB start; 1QB keeps him on the bench", {
  sf <- toy_lg_league(slots = list(list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 1),
                                   list(name = "WR", eligible = "WR", count = 1),
                                   list(name = "SUPERFLEX", eligible = c("QB", "RB", "WR"), count = 1)))
  p <- c(base_players, `1_QB_a8` = 17)
  p <- p[names(p) != "1_WR_a5"]
  m1 <- toy_lg(p)
  msf <- toy_lg(p, league = sf)
  expect_equal(lg_attribution(m1, m1$state[["1"]]$rows)$players$started_pts[lg_attribution(m1, m1$state[["1"]]$rows)$players$player_id == "1_QB_a8"], 0)
  expect_equal(msf$base[["1"]]$U, 20 + 15 + 12 + 17)
  # the same QB is worth far more to a superflex team
  x <- lg_find_player(msf, "2_QB_b1")
  expect_gt(lg_mtv_matrix(msf, x)$team_1, lg_mtv_matrix(m1, x)$team_1)
})

test_that("marginal team value differs by destination and blocked players are worth less", {
  m <- toy_lg(base_players)
  mt <- lg_mtv_matrix(m, lg_find_player(m, c("2_WR_b3")))
  expect_equal(mt$team_1, 63 - 57)     # starts over a3; a3 moves to FLEX; bench a5 dropped
  mt2 <- lg_mtv_matrix(m, lg_find_player(m, "F_RB_f2"))
  expect_equal(mt2$team_1, 0)          # free-agent RB 7 would never start for Team One
  own <- lg_mtv_matrix(m, lg_find_player(m, "1_QB_a1"))
  expect_equal(own$team_1, 20 - 12)    # losing a1: best add is free agent QB f1
})

test_that("win-win search finds mutually beneficial swaps of surplus depth", {
  p <- c(`1_QB_a1` = 20, `1_RB_a2` = 15, `1_RB_a3` = 14, `1_RB_a4` = 13, `1_WR_a5` = 5,
         `2_QB_b1` = 18, `2_WR_b2` = 16, `2_WR_b3` = 15, `2_WR_b4` = 14, `2_RB_b5` = 5,
         `F_QB_f1` = 10, `F_RB_f2` = 4, `F_WR_f3` = 4)
  m <- toy_lg(p)
  s <- lg_trade_search(m, 1, 2, sizes_a = 1, sizes_b = 1, top_n = 5, tv_band = 100)
  top <- s[1, ]
  expect_true(top$win_win)
  # several RB-for-WR swaps tie at the optimum: Team One's WR slot gets 16 or 14+, Team Two's RB slot 15 or 13+
  expect_equal(top$delta_a, 9)
  expect_equal(top$delta_b, 8)
  expect_equal(top$classification, "mild win-win")
  best <- s[s$surplus == max(s$surplus), ]
  expect_true(any(best$a_gives == "1_RB_a4" & best$b_gives == "2_WR_b4"))   # bench-for-bench swap is among them
  expect_true(all(s$win_win == (s$delta_a > 0 & s$delta_b > 0)))
  # target offers for b4: Team Two must not lose more than eps
  off <- lg_target_offers(m, 1, "2_WR_b4", sizes = 1, tv_band = 100)
  expect_true(all(off$delta_them >= -5))
  expect_equal(off$offer[1], "1_RB_a4")
  # selling a4: Team Two values him most
  sd <- lg_sell_destinations(m, 1, "1_RB_a4", n_teams = 1, sizes = 1, tv_band = 100)
  expect_equal(sd$destinations$team_id[1], 2L)
  expect_true(nrow(sd$offers) >= 1)
})

test_that("team needs and power rankings emerge from lineup attribution", {
  p <- c(`1_QB_a1` = 20, `1_RB_a2` = 15, `1_RB_a3` = 14, `1_RB_a4` = 13, `1_WR_a5` = 5,
         `2_QB_b1` = 18, `2_WR_b2` = 16, `2_WR_b3` = 15, `2_WR_b4` = 14, `2_RB_b5` = 5,
         `F_QB_f1` = 10, `F_RB_f2` = 4, `F_WR_f3` = 4)
  m <- toy_lg(p)
  pr <- lg_power_rankings(m)
  expect_equal(pr$team[1], "Team One")
  expect_equal(pr$U, c(20 + 15 + 5 + 14, 18 + 5 + 16 + 15))
  n <- lg_team_needs(m, 1, pr)
  expect_equal(n$weakest_slot, "WR")
  # no rostered backup QB: the backup is the best free-agent QB (10), so QB has the largest drop (20 -> 10)
  expect_equal(n$largest_drop_position, "QB")
  expect_equal(n$depth$best_backup_ppg[n$depth$position == "RB"], 14)
  expect_equal(n$deepest_bench_position, n$depth$position[which.max(n$depth$bench_started_pts)])
})

# ---- ESPN league ingestion -------------------------------------------------------------
toy_settings <- function(counts = list(`0` = 1, `2` = 2, `4` = 2, `6` = 1, `23` = 1, `16` = 1, `17` = 1, `20` = 7, `21` = 1),
                         items = NULL) {
  items <- items %||% list(list(statId = 53, points = 1), list(statId = 42, points = 0.1), list(statId = 43, points = 6),
                           list(statId = 3, points = 0.04), list(statId = 4, points = 4), list(statId = 20, points = -2),
                           list(statId = 24, points = 0.1), list(statId = 25, points = 6), list(statId = 72, points = -2),
                           list(statId = 19, points = 2), list(statId = 26, points = 2), list(statId = 44, points = 2),
                           list(statId = 101, points = 6), list(statId = 102, points = 6), list(statId = 63, points = 6))
  list(name = "Toy League", size = 10, rosterSettings = list(lineupSlotCounts = counts, positionLimits = list(`1` = 0)),
       scoringSettings = list(scoringItems = items),
       scheduleSettings = list(matchupPeriodCount = 14, playoffTeamCount = 6, playoffMatchupPeriodLength = 1))
}

test_that("ESPN roster settings map to the V1 league (and unsupported slots fail clearly)", {
  lg <- lg_map_settings(toy_settings())
  expect_equal(names(lg$slots), c("QB", "RB", "WR", "TE", "FLEX"))
  expect_equal(lg$slots$FLEX$eligible, c("RB", "WR", "TE"))
  expect_equal(lg$bench, 7L)
  expect_equal(lg$ir_slots, 1L)
  expect_equal(lg$roster_size, 16L)      # 7 starters + K + D/ST + 7 bench; IR excluded
  expect_equal(lg$playoff_weeks, c(15L, 17L))
  expect_equal(unlist(lg$nonskill_starters), c(`D/ST` = 1L, K = 1L))
  sf <- lg_map_settings(toy_settings(list(`0` = 1, `2` = 2, `4` = 2, `6` = 1, `23` = 1, `7` = 1, `20` = 6)))
  expect_true("SUPERFLEX" %in% names(sf$slots))
  expect_error(lg_map_settings(toy_settings(list(`0` = 1, `10` = 2, `20` = 6))), "cannot model")
  expect_error(lg_map_settings(toy_settings(list(`0` = 1, `2` = 2, `3` = 1, `5` = 1, `20` = 6))), "laminar")
})

test_that("league scoring maps to rules; PPR is recognised, other formats and bonuses are reported", {
  sdir <- file.path(project_root, "config", "scoring")
  sc <- lg_map_scoring(toy_settings(), sdir)
  expect_true(sc$equals_espn_ppr)
  expect_equal(sc$rules$weights[["receptions"]], 1)
  half <- toy_settings()
  half$scoringSettings$scoringItems[[1]]$points <- 0.5
  half$scoringSettings$scoringItems <- c(half$scoringSettings$scoringItems, list(list(statId = 201, points = 3)))
  sh <- lg_map_scoring(half, sdir)
  expect_false(sh$equals_espn_ppr)
  expect_equal(sh$rules$weights[["receptions"]], 0.5)
  expect_equal(sh$unmapped$stat_id, "201")
})

toy_league_json <- function() {
  ent <- function(id, name, pos, slot, team = 1) {
    list(playerId = id, lineupSlotId = slot, acquisitionType = "DRAFT", acquisitionDate = 1.7e12,
         playerPoolEntry = list(id = id, onTeamId = team, player = list(id = id, fullName = name, defaultPositionId = pos,
                                                                         proTeamId = 2, injuryStatus = "ACTIVE")))
  }
  jsonlite::toJSON(list(seasonId = 2026, scoringPeriodId = 5, settings = toy_settings(), status = list(currentMatchupPeriod = 5),
    teams = list(
      list(id = 1, abbrev = "ONE", name = "Team One", owners = list("{S1}"),
           roster = list(entries = list(ent(101, "Q One", 1, 0), ent(102, "R One", 2, 2), ent(103, "K One", 5, 17),
                                        ent(104, "W Hurt", 3, 21)))),
      list(id = 2, abbrev = "TWO", name = "Team Two", owners = list("{S2}"),
           roster = list(entries = list(ent(201, "Q Two", 1, 0, 2), ent(202, "W Two", 3, 20, 2)))))),
    auto_unbox = TRUE)
}

test_that("league JSON parses into rosters with slots, IR and non-skill players; my team via SWID", {
  lg <- lg_parse_league(toy_league_json(), "20261007T000000Z", "league_test")
  expect_equal(nrow(lg$teams), 2)
  r <- lg$roster
  expect_equal(nrow(r), 6)
  expect_equal(r$is_skill[r$espn_id == "103"], FALSE)   # kicker
  expect_true(r$is_ir_slot[r$espn_id == "104"])
  expect_equal(r$lineup_slot[r$espn_id == "202"], "BE")
  expect_equal(r$position[r$espn_id == "101"], "QB")
  expect_equal(lg_my_team(lg$teams, list(my_team_id = NA, swid = "{S2}")), 2L)
  expect_true(is.na(lg_my_team(lg$teams, list(my_team_id = NA, swid = NA))))
  d <- lg_id_diagnostics(r, tibble::tibble(espn_id = c("101", "102", "201"), player_id = c("g1", "g2", "g3"),
                                           position = c("QB", "WR", "QB"), team = "BUF"))
  expect_setequal(d$no_projection$espn_id, c("104", "202"))   # kept and flagged, not discarded
  expect_equal(d$position_mismatch$espn_id, "102")
  expect_equal(d$nonskill, 1)
})

test_that("league snapshots are write-once, hash-verified and staleness is enforced", {
  root <- withr::local_tempdir()
  man <- file.path(root, "league_manifest.csv")
  cred <- list(league_id = "x", espn_s2 = NA, swid = NA, my_team_id = NA, alias = "league_test")
  s <- lg_snapshot_league(2026, cred, root = root, manifest = man, body = toy_league_json())
  expect_true(file.exists(s$raw))
  mm <- readr::read_csv(man, col_types = readr::cols(.default = "c"))
  expect_equal(mm$league_alias, "league_test")
  expect_false(any(grepl("Team One|Q One", readLines(man))))       # no private names in the manifest
  lg <- lg_latest_snapshot(2026, "league_test", root = root, manifest = man)
  expect_equal(nrow(lg$roster), 6)
  expect_silent(lg_check_fresh(lg, 24))
  lg$age_hours <- 30
  expect_error(lg_check_fresh(lg, 24), "hours old")
  expect_warning(lg_check_fresh(lg, 24, allow_stale = TRUE), "hours old")
  writeLines("tampered", gzfile(s$raw))
  expect_error(lg_latest_snapshot(2026, "league_test", root = root, manifest = man), "does not match")
})

test_that("analysis archive writes outputs and a manifest without private content", {
  root <- withr::local_tempdir()
  man <- file.path(root, "analysis_manifest.csv")
  m <- toy_lg(base_players)
  m$inputs <- list(league_alias = "league_test", league_raw_sha256 = "abc", valuation_run_id = "r1", league_captured_at_utc = "t")
  m$la <- lg_config(read_valuation_config(file.path(project_root, "config", "valuation.yml")))
  m$season <- 2026L
  a <- lg_archive_analysis(m, root = root, manifest = man)
  expect_true(file.exists(file.path(a$dir, "mtv.parquet")))
  expect_equal(nrow(a$rankings), 2)
  expect_false(any(grepl("Team One", readLines(man))))
  cached <- lg_cached_mtv(m, root = root, manifest = man)
  expect_equal(cached$team_1, a$mtv$team_1)
})

test_that("playoff weeks come from the matchup-period map (two-week final round)", {
  st <- toy_settings()
  st$scheduleSettings <- list(matchupPeriodCount = 14, playoffTeamCount = 4, playoffMatchupPeriodLength = 0,
                              matchupPeriods = c(stats::setNames(as.list(1:15), 1:15), list(`16` = list(16, 17))))
  lg <- lg_map_settings(st)
  expect_equal(lg$regular_season_weeks, c(1L, 14L))
  expect_equal(lg$playoff_weeks, c(15L, 17L))
  expect_error(val_league(list(teams = 2, slots = list(list(name = "QB", eligible = "QB", count = 1)),
                               regular_season_weeks = c(1, 14), playoff_weeks = c(15, 14))), "first <= last")
})

test_that("unmapped scoring items count only if they score for skill players in ESPN's history", {
  sdir <- file.path(project_root, "config", "scoring")
  st <- toy_settings()
  st$scoringSettings$scoringItems <- c(st$scoringSettings$scoringItems,
    list(list(statId = 77, points = 4),                                   # kicker FG: never recorded by skill players
         list(statId = 95, points = 0, pointsOverrides = list(`16` = 2)), # D/ST-only override
         list(statId = 93, points = 6)))                                  # return TD: recorded, but negligibly
  usage <- tibble::tibble(stat_id = c("77", "95", "93"), entries = 1e5, abs_total = c(0, 80, 3))
  sc <- lg_map_scoring(st, sdir, usage = usage)
  expect_true(sc$equals_espn_ppr)
  expect_setequal(sc$ignored$stat_id, c("77", "95", "93"))
  # without usage evidence, scoring unmapped items are treated as relevant (conservative)
  expect_false(lg_map_scoring(st, sdir)$equals_espn_ppr)
  # a per-slot override on a skill slot (TE premium on receptions) is never ignored
  te <- toy_settings()
  te$scoringSettings$scoringItems[[1]]$pointsOverrides <- list(`6` = 1.5)
  expect_false(lg_map_scoring(te, sdir, usage = usage)$equals_espn_ppr)
})

test_that("team labels handle free agents and unknown ids", {
  m <- toy_lg(base_players)
  expect_equal(lg_team_label(m, NA), "free agent")
  expect_equal(lg_team_label(m, 1L), "Team One")
  expect_equal(lg_team_label(m, 99L), "Team 99")
})
