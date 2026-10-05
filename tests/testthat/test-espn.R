fixture <- function() {
  paste(readLines(testthat::test_path("fixtures", "espn_kona_synthetic.json")), collapse = "\n")
}

test_that("parser keeps only this season-week's weekly projection and actual", {
  out <- parse_espn_week(fixture(), 2024, 5)
  a <- dplyr::filter(out, espn_id == "9000001")
  expect_equal(a$espn_proj, 14.5)                 # not the 2023 entry (99)
  expect_equal(a$espn_actual, 21.3)
  expect_equal(a$espn_proj_receptions, 5.2)
  expect_equal(a$espn_proj_targets, 7.9)
  expect_equal(a$espn_proj_receiving_yards, 70.1)
  expect_equal(a$espn_proj_receiving_tds, 0.45)
  expect_equal(a$espn_proj_rushing_yards, 0)       # absent stat in a projection = 0
})

test_that("zero projections, missing projections and positions are preserved", {
  out <- parse_espn_week(fixture(), 2024, 5)
  b <- dplyr::filter(out, espn_id == "9000002")
  expect_equal(b$espn_proj, 0)
  expect_true(is.na(b$espn_actual))
  c <- dplyr::filter(out, espn_id == "9000003")
  expect_true(is.na(c$espn_proj))                  # no projection entry != projected 0
  expect_equal(c$espn_actual, 8.7)
  expect_equal(out$espn_position_id[out$espn_id == "9000004"], 4L)
  expect_equal(nrow(out), 4)
})

test_that("per-game actual entries in one week are summed; duplicate projections fail", {
  doc <- jsonlite::fromJSON(
    paste(readLines(testthat::test_path("fixtures", "espn_kona_synthetic_twogames.json")), collapse = "\n"),
    simplifyVector = FALSE
  )
  one <- function(i) { d <- doc; d$players <- d$players[i]; jsonlite::toJSON(d, auto_unbox = TRUE) }
  out <- parse_espn_week(one(1), 2020, 8)
  expect_equal(out$espn_actual, 1.5)
  expect_equal(out$espn_proj, 0)
  expect_error(parse_espn_week(one(2), 2020, 8), "projection entries")
})

test_that("the request filter asks for weekly projected + actual splits for one slot", {
  f <- jsonlite::fromJSON(espn_filter_header(5, ESPN_SLOT_IDS[["WR"]]))
  expect_equal(f$players$filterSlotIds$value, 4)
  expect_equal(sort(f$players$filterStatsForSourceIds$value), c(0, 1))
  expect_equal(f$players$filterStatsForSplitTypeIds$value, 1)
  expect_equal(f$players$filterStatsForScoringPeriodIds$value, 5)
})

test_that("fetching is refused unless explicitly enabled", {
  expect_error(fetch_espn_week(2024, 5, root = withr::local_tempdir(), enabled = FALSE), "disabled")
  expect_error(snapshot_espn_projections(enabled = FALSE), "disabled")
  grid <- tibble::tibble(season = 2024L, week = 5L)
  expect_equal(nrow(fetch_espn_weeks(grid, root = withr::local_tempdir(), enabled = FALSE)), 0)
})

test_that("name normalisation handles suffixes, punctuation and accents", {
  expect_equal(normalize_name("Marvin Harrison Jr."), "marvin harrison")
  expect_equal(normalize_name("D'Andre Swift"), "dandre swift")
  expect_equal(normalize_name("Amon-Ra St. Brown"), "amonra st brown")
  expect_equal(normalize_name("Ja'Marr  Chase II"), "jamarr chase")
})

test_that("crosswalk accepts unanimous ids and never guesses ambiguous ones", {
  espn <- tibble::tibble(
    season = 2024L, week = 5L,
    espn_id = c("1", "2", "3", "4", "5", "6"),
    espn_name = c("Alpha One", "Bravo Two", "Charlie Three", "Delta Four", "Echo Five", "Foxtrot Six")
  )
  players <- tibble::tibble(
    espn_id = c("1", "2", "3", "5", "6"),
    gsis_id = c("G1", "G2", "G3", "G5", "G5"),
    display_name = c("Alpha One", "Bravo Two", "Charlie Three", "Echo Five", "Foxtrot Six")
  )
  rosters <- tibble::tibble(
    roster_espn_id = c("1", "2", "3"), gsis_id = c("G1", "G2x", "G3x"),
    roster_name = c("Alpha One", "Someone Else", "Charlie Three")
  )
  ffids <- tibble::tibble(espn_id = character(), gsis_id = character(), name = character())

  cw <- build_espn_crosswalk(espn, rosters, players, ffids)
  get <- function(id, col) cw[[col]][cw$espn_id == id]
  expect_equal(get("1", "match_method"), "id_unanimous")
  expect_equal(get("1", "gsis_id"), "G1")
  expect_equal(get("2", "match_method"), "id_conflict_name_resolved")   # G2 (name matches) vs G2x
  expect_equal(get("2", "gsis_id"), "G2")
  expect_equal(get("3", "match_method"), "ambiguous")                   # both candidates named Charlie Three
  expect_true(is.na(get("3", "gsis_id")))
  expect_equal(get("4", "match_method"), "unmatched")
  expect_equal(get("5", "match_method"), "ambiguous")                   # two ESPN ids -> one gsis id
  expect_equal(get("6", "match_method"), "ambiguous")
  expect_equal(nrow(cw), 6)
})
