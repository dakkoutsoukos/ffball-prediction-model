test_that("official snapshot = latest captured strictly before kickoff", {
  snaps <- tibble::tibble(
    path = c("a", "b", "c"),
    captured_at = as.POSIXct(c("2026-10-06 12:00", "2026-10-08 20:00", "2026-10-11 15:00"), tz = "UTC")
  )
  kick <- as.POSIXct(c("2026-10-09 00:15", "2026-10-11 17:00", "2026-10-06 12:00", "2026-10-11 15:00"), tz = "UTC")
  expect_equal(official_snapshot(snaps, kick), c("b", "c", NA, "b"))  # equal time does not count
})

test_that("kickoff times convert from US Eastern to UTC across DST", {
  expect_equal(format(kickoff_to_utc("2026-10-08", "20:15"), tz = "UTC"), "2026-10-09 00:15:00")
  expect_equal(format(kickoff_to_utc("2026-12-13", "13:00"), tz = "UTC"), "2026-12-13 18:00:00")
})

test_that("write_once never overwrites", {
  p <- file.path(withr::local_tempdir(), "x.txt")
  write_once(p, function(tmp) writeLines("first", tmp))
  expect_error(write_once(p, function(tmp) writeLines("second", tmp)), "overwrite")
  expect_equal(readLines(p), "first")
})

test_that("manifests are append-only and keep earlier rows", {
  p <- file.path(withr::local_tempdir(), "m.csv")
  append_manifest(tibble::tibble(run_id = "1", n = 5), p)
  append_manifest(tibble::tibble(run_id = "2", n = 7), p)
  m <- readr::read_csv(p, col_types = readr::cols(.default = "c"))
  expect_equal(m$run_id, c("1", "2"))
})

test_that("manifests refuse rows with a different column layout", {
  p <- file.path(withr::local_tempdir(), "m.csv")
  append_manifest(tibble::tibble(run_id = "1", n = 5), p)
  expect_error(append_manifest(tibble::tibble(run_id = "2", n = 7, extra = "x"), p), "refusing")
  append_manifest(tibble::tibble(n = 9, run_id = "3"), p)                    # same columns, any order
  expect_equal(readr::read_csv(p, col_types = readr::cols(.default = "c"))$n, c("5", "9"))
})

test_that("latest live retrieval respects the as-of time", {
  root <- withr::local_tempdir()
  d <- file.path(root, "player_stats", "season=2026")
  dir.create(d, recursive = TRUE)
  for (s in c("20261005T120000Z", "20261006T120000Z")) file.create(file.path(d, paste0("retrieved_at=", s, ".parquet")))
  got <- latest_live_file("player_stats", 2026, as.POSIXct("2026-10-05 18:00", tz = "UTC"), root)
  expect_match(got, "20261005T120000Z")
  expect_error(latest_live_file("player_stats", 2026, as.POSIXct("2026-10-01", tz = "UTC"), root), "No live")
})

test_that("ESPN team ids map one-to-one onto all 32 nflverse teams", {
  expect_length(ESPN_TEAM_IDS, 32)
  expect_false(anyDuplicated(ESPN_TEAM_IDS) > 0)
  expect_identical(standardize_team(unname(ESPN_TEAM_IDS)), unname(ESPN_TEAM_IDS))
  expect_equal(espn_team(c(33, 14, 999)), c("BAL", "LA", NA))
})

test_that("unplayed games are never used as training rows", {
  base <- tibble::tibble(season = 2026L, week = c(4L, 4L), team = c("AAA", "BBB"), actual = 0)
  tg <- tibble::tibble(season = 2026L, week = 4L, team = c("AAA", "BBB"), game_final = c(TRUE, FALSE))
  expect_equal(final_games_only(base, tg)$team, "AAA")
})

test_that("prospective targets come from the snapshot, mapped and with game context", {
  snap <- tibble::tibble(
    season = 2026L, week = 5L, espn_id = c("1", "2", "3", "4"), espn_name = c("A", "B", "C", "D"),
    espn_position_id = c(3L, 3L, 3L, 4L), espn_pro_team_id = c(33L, 33L, 2L, 33L),
    espn_proj = c(12, 0, 8, 9)
  )
  cw <- tibble::tibble(espn_id = c("1", "2", "4"), gsis_id = c("g1", "g2", "g4"))
  tg <- tibble::tibble(season = 2026L, week = 5L, team = "BAL", game_id = "2026_05_X", opponent = "PIT",
                       home = TRUE, kickoff_utc = as.POSIXct("2026-10-11 17:00", tz = "UTC"),
                       team_spread = 3, total_line = 44, implied_team_total = 23.5, rest_days = 7)
  out <- prospective_targets(snap, cw, tg, 2026, 5)
  expect_equal(out$gsis_id, "g1")          # proj 0 dropped, unmatched dropped, TE dropped
  expect_equal(out$opponent, "PIT")
  ex <- attr(out, "excluded")
  expect_equal(ex$projected, 2)            # two WRs with projection > 0
  expect_equal(ex$unmatched_id, 1)
})

test_that("sha256_file returns a plain 64-character hex string", {
  p <- withr::local_tempfile()
  writeLines("abc", p)
  h <- sha256_file(p)
  expect_identical(class(h), "character")
  expect_match(h, "^[0-9a-f]{64}$")
  expect_silent(jsonlite::toJSON(list(h = h), auto_unbox = TRUE))
})
