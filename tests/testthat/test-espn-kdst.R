# O8 K/DST ESPN files (X-029) and B-001 matching. Hand-written fixtures only.

kd_fixture <- function() {
  jsonlite::toJSON(list(players = list(
    list(player = list(id = 101, defaultPositionId = 5, proTeamId = 33, stats = list(
      list(seasonId = 2021, scoringPeriodId = 3, statSourceId = 0, statSplitTypeId = 1, proTeamId = 33, appliedTotal = 9,
           stats = list(`80` = 1, `77` = 1, `86` = 2)),
      list(seasonId = 2021, scoringPeriodId = 3, statSourceId = 1, statSplitTypeId = 1, proTeamId = 0, appliedTotal = 8,
           stats = list(`80` = 1.2)),
      list(seasonId = 2021, scoringPeriodId = 0, statSourceId = 0, statSplitTypeId = 0, proTeamId = 33, appliedTotal = 50,
           stats = list(`80` = 9))))),
    list(player = list(id = -16001, defaultPositionId = 16, proTeamId = 1, stats = list(
      list(seasonId = 2021, scoringPeriodId = 3, statSourceId = 0, statSplitTypeId = 1, proTeamId = 1, appliedTotal = 4,
           stats = list(`99` = 2, `123` = 1, `120` = 30))))),
    list(player = list(id = 7, defaultPositionId = 1, proTeamId = 1, stats = list())),
    list(player = list(id = 102, defaultPositionId = 5, proTeamId = 2, stats = list(
      list(seasonId = 2021, scoringPeriodId = 3, statSourceId = 0, statSplitTypeId = 1, proTeamId = 2, appliedTotal = 0,
           stats = structure(list(), names = character()))))))), auto_unbox = TRUE)
}

test_that("the K/DST parser keeps single-week rows of K and D/ST, with stats as s<id> columns", {
  p <- kdst_parse_espn(kd_fixture(), 2021L, periods = 3L)
  expect_setequal(p$espn_id, c("101", "-16001", "102"))                    # the QB is skipped; an empty stat line is kept
  expect_equal(nrow(p), 4L)                                                 # 101: actual + projection
  a <- p[p$espn_id == "101" & p$source == 0, ]
  expect_equal(c(a$s80, a$s77, a$s86, a$stat_pro_team_id), c(1, 1, 2, 33))
  expect_equal(p$s99[p$position == "DST"], 2)
  expect_equal(p$s99[p$espn_id == "102"], 0)
})

test_that("league points from ESPN stat lines follow the K and D/ST rule columns", {
  p <- kdst_parse_espn(kd_fixture(), 2021L, periods = 3L, sources = 0L)
  rules <- tibble::tibble(stat_id = c("80", "77", "86", "99", "123"), stat = c("fg_made_0_39", "fg_made_40_49", "pat_made", "sacks", "pa_28_34"),
                          points_k = c(3, 4, 1, 0, 0), points_dst = c(3, 4, 1, 1, -1))
  pts <- kdst_espn_league_points(p, rules)
  expect_equal(pts[p$espn_id == "101"], 3 + 4 + 2)
  expect_equal(pts[p$espn_id == "-16001"], 2 - 1)
  expect_equal(pts[p$espn_id == "102"], 0)
})

test_that("B-001 v2: points allowed drop the opponent's safeties; recoveries count every opponent fumble", {
  st <- tibble::tibble(season = 2021L, week = 3L, game_id = "g", team = c("A", "B"), opponent = c("B", "A"),
                       safeties = c(1, 0), fumble_recoveries = c(0, 0), points_allowed = c(20, 15))
  pbp <- tibble::tibble(game_id = "g", fumbled_1_team = c("B", "A", "A"), fumble_recovery_1_team = c("A", "A", "B"),
                        fumbled_2_team = NA_character_, fumble_recovery_2_team = NA_character_)
  v2 <- kdst_dst_stats_v2(st, pbp)
  expect_equal(v2$points_allowed, c(20, 13))                               # B allowed 15, 2 of them A's safety
  expect_equal(v2$fumble_recoveries, c(1, 1))
  expect_equal(v2$pa_7_13, c(0, 1))
})
