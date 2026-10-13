# League state v2 (master plan F3-lite). Hand-written synthetic responses only; no ESPN data.

ls_game <- function(id, period, home, away, hp, ap, winner, tier = "NONE") {
  g <- list(id = id, matchupPeriodId = period, home = list(teamId = home, totalPoints = hp), winner = winner,
            playoffTierType = tier)
  if (!is.na(away)) g$away <- list(teamId = away, totalPoints = ap)
  g
}

ls_team <- function(id, w, l, t, pf, pa, seed, extra = list()) {
  c(list(id = id, abbrev = paste0("T", id), name = paste("Synthetic", id), owners = list(paste0("{O", id, "}")),
         playoffSeed = seed, rankCalculatedFinal = 0, waiverRank = 5 - id, divisionId = 0,
         record = list(overall = list(wins = w, losses = l, ties = t, pointsFor = pf, pointsAgainst = pa,
                                      percentage = (w + 0.5 * t) / max(w + l + t, 1), gamesBack = 0, streakLength = 1,
                                      streakType = "WIN")),
         transactionCounter = list(acquisitionBudgetSpent = 0, acquisitions = id, drops = id, trades = 0, moveToIR = 0),
         roster = list(entries = list())), extra)
}

#' Four teams; regular periods 1-3 (period 3 in progress); a two-week final (period 4 = weeks 4-5).
ls_doc <- function(enh = NULL, sim = FALSE) {
  deadline <- as.numeric(as.POSIXct("2026-12-02 17:00", tz = "UTC")) * 1000
  sc <- list(matchupTieRule = "NONE", playoffMatchupTieRule = "NONE", homeTeamBonus = 0, scoringItems = list())
  if (!is.null(enh)) sc$scoringEnhancementType <- enh
  t4 <- if (sim) list(currentSimulationResults = list(playoffPct = 0.83)) else list()
  list(seasonId = 2026, scoringPeriodId = 3,
       settings = list(size = 4,
                       scheduleSettings = list(matchupPeriodCount = 3, playoffTeamCount = 2, playoffSeedingRule = "TOTAL_POINTS_SCORED",
                                               playoffMatchupPeriodLength = 1, playoffMatchupPeriodLengthByRound = list(`1` = 2),
                                               matchupPeriods = list(`1` = list(1), `2` = list(2), `3` = list(3), `4` = list(4, 5)),
                                               divisions = list(list(id = 0, size = 4))),
                       scoringSettings = sc,
                       tradeSettings = list(deadlineDate = deadline, vetoVotesRequired = 2, revisionHours = 24),
                       acquisitionSettings = list(isUsingAcquisitionBudget = FALSE, acquisitionBudget = 100, waiverProcessDays = list("WEDNESDAY"),
                                                  waiverProcessHour = 3, waiverHours = 24),
                       draftSettings = list(keeperCount = 0)),
       status = list(currentMatchupPeriod = 3, latestScoringPeriod = 3, firstScoringPeriod = 1, finalScoringPeriod = 5),
       teams = list(ls_team(1, 1, 1, 0, 198.5, 190, 2), ls_team(2, 0, 1, 1, 201, 211.5, 4),
                    ls_team(3, 1, 1, 0, 185, 208, 3), ls_team(4, 1, 0, 1, 221, 196, 1, t4)),
       schedule = list(ls_game(1, 1, 1, 2, 110.5, 100, "HOME"), ls_game(2, 1, 3, 4, 95, 120, "AWAY"),
                       ls_game(3, 2, 1, 3, 88, 90, "AWAY"), ls_game(4, 2, 2, 4, 101, 101, "TIE"),
                       ls_game(5, 3, 1, 4, 0, 0, "UNDECIDED"), ls_game(6, 3, 2, 3, 0, 0, "UNDECIDED"),
                       ls_game(7, 4, 4, 1, 0, 0, "UNDECIDED", "WINNERS_BRACKET"),
                       ls_game(8, 4, 2, NA, 0, NA, "UNDECIDED", "LOSERS_CONSOLATION_LADDER")))
}

test_that("the single league request asks for exactly the approved views", {
  u <- lg_league_url(2026, "123")
  expect_equal(u, paste0(ESPN_API, "/seasons/2026/segments/0/leagues/123?view=mSettings&view=mTeam&view=mRoster&view=mStatus&view=mMatchup"))
  expect_equal(LG_VIEWS, c("mSettings", "mTeam", "mRoster", "mStatus", "mMatchup"))
})

test_that("adding the schedule leaves the V2 roster and team parsing unchanged", {
  doc <- ls_doc()
  doc$settings$rosterSettings <- list(lineupSlotCounts = list(`0` = 1, `20` = 1))
  doc$teams[[1]]$roster$entries <- list(list(playerId = 9, lineupSlotId = 0, acquisitionType = "DRAFT", acquisitionDate = 1.7e12,
                                             playerPoolEntry = list(player = list(id = 9, fullName = "Q Nine", defaultPositionId = 1,
                                                                                  proTeamId = 2, injuryStatus = "ACTIVE"))))
  with_sched <- lg_parse_league(jsonlite::toJSON(doc, auto_unbox = TRUE), "20261013T000000Z", "league_test")
  doc$schedule <- NULL
  without <- lg_parse_league(jsonlite::toJSON(doc, auto_unbox = TRUE), "20261013T000000Z", "league_test")
  expect_identical(with_sched$roster, without$roster)
  expect_identical(with_sched$teams, without$teams)
  expect_identical(with_sched$settings, without$settings)
})

test_that("rules parse the format, deadline, tie rules, waivers and keepers", {
  r <- lg_league_state(jsonlite::toJSON(ls_doc(), auto_unbox = TRUE))$rules
  expect_equal(r$teams, 4L)
  expect_equal(r$regular_periods, 3L)
  expect_equal(r$playoff_teams, 2L)
  expect_equal(r$playoff_seeding_rule, "TOTAL_POINTS_SCORED")
  expect_equal(r$matchup_periods$scoring_periods[[4]], c(4L, 5L))   # two-week final
  expect_equal(unname(r$playoff_period_length_by_round), 2L)
  expect_equal(r$trade_deadline_utc, as.POSIXct("2026-12-02 17:00", tz = "UTC"))
  expect_false(r$top_half_bonus)
  expect_true(is.na(r$scoring_enhancement_type))
  expect_false(r$faab)
  expect_equal(r$keeper_count, 0L)
  expect_equal(r$matchup_tie_rule, "NONE")
  expect_equal(r$waiver_process_days, "WEDNESDAY")
  expect_true(lg_parse_rules(ls_doc("WIN_BONUS_TOP_HALF")$settings)$top_half_bonus)
  s <- lg_rules_summary(r, now = as.POSIXct("2026-10-13 17:00", tz = "UTC"))
  expect_match(s, "trade deadline 2026-12-02 \\(50 days from now\\)")
  expect_false(grepl("Synthetic", s))   # no team names
})

test_that("the schedule parses matchups, ties, byes and playoff tiers", {
  st <- lg_league_state(ls_doc())
  s <- st$schedule
  expect_equal(nrow(s), 8L)
  expect_true(st$has_schedule)
  expect_true(is.na(s$away_team[s$matchup_id == 8]))   # a bye in the consolation ladder
  expect_equal(s$winner[s$matchup_id == 4], "TIE")
  expect_equal(sum(s$playoff_tier == "WINNERS_BRACKET"), 1L)
  expect_equal(st$status$current_matchup_period, 3L)
})

test_that("standings parse records and ESPN's playoff odds only when ESPN returns them", {
  st <- lg_league_state(ls_doc())
  expect_true(all(is.na(st$standings$espn_playoff_pct)))
  expect_equal(st$standings$playoff_seed, c(2L, 4L, 3L, 1L))
  st2 <- lg_league_state(ls_doc(sim = TRUE))
  expect_equal(st2$standings$espn_playoff_pct[st2$standings$team_id == 4], 0.83)
  expect_false("name" %in% names(st$standings))
})

test_that("records recomputed from the schedule reproduce ESPN's, including a tie", {
  rec <- lg_recompute_records(lg_parse_schedule(ls_doc()), 3)
  expect_equal(rec$wins, c(1L, 0L, 1L, 1L))
  expect_equal(rec$ties, c(0L, 1L, 0L, 1L))
  expect_equal(rec$points_for, c(198.5, 201, 185, 221))
  expect_equal(lg_seed_order(rec, "TOTAL_POINTS_SCORED"), c(2L, 4L, 3L, 1L))   # 0.5 tie broken by points for
  expect_true(all(is.na(lg_seed_order(rec, "H2H_RECORD"))))
})

test_that("state checks pass on a consistent league and catch inconsistent ones", {
  ok <- lg_state_checks(lg_league_state(ls_doc()))
  expect_true(all(ok$passed))
  bad <- ls_doc()
  bad$teams[[1]]$record$overall$wins <- 2
  chk <- lg_state_checks(lg_league_state(bad))
  expect_false(chk$passed[chk$check == "records recomputed from the schedule equal ESPN's"])
  twice <- ls_doc()
  twice$schedule[[2]]$home$teamId <- 1                       # team 1 twice in period 1, team 3 missing
  chk2 <- lg_state_checks(lg_league_state(twice))
  expect_false(chk2$passed[chk2$check == "one game per team per regular period"])
  noschedule <- ls_doc()
  noschedule$schedule <- NULL
  expect_false(lg_state_checks(lg_league_state(noschedule))$passed)
})
