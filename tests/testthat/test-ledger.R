# Decision ledger (master plan F5). Synthetic records and outcomes only.

ld_inputs <- function() list(league_alias = "league_test", league_raw_sha256 = "abc", valuation_run_id = "r1")

ld_lineup_record <- function(root, man, now = as.POSIXct("2026-10-14 12:00", tz = "UTC")) {
  roster <- tibble::tibble(player_id = c("00-1", "00-2", "00-3", "00-4"), espn_id = c("1", "2", "3", "4"),
                           player = c("A", "B", "C", "D"), position = c("QB", "RB", "RB", "WR"),
                           slot_recommended = c("QB", "RB", "BE", "WR"), slot_current = c("QB", "BE", "RB", "WR"),
                           recommended_starter = c(TRUE, TRUE, FALSE, TRUE), current_starter = c(TRUE, FALSE, TRUE, TRUE),
                           is_ir = FALSE, proj = c(20, 15, 9, 12), locked = FALSE, status = "NORMAL",
                           kickoff_utc = "2026-10-18T17:00:00Z")
  lg_ledger_record("lineup", ld_inputs(), 2026, 6, list(roster = roster, plans = list()),
                   list(current_espn_lineup_ev = 41), list(ev_recommended = 47, ev_current = 41), now = now,
                   root = root, manifest = man)
}

ld_league <- function() {
  val_league(list(name = "toy", teams = 2, slots = list(list(name = "QB", eligible = "QB", count = 1),
                                                       list(name = "RB", eligible = "RB", count = 1),
                                                       list(name = "WR", eligible = "WR", count = 1)),
                  bench = 2, regular_season_weeks = c(1, 14), playoff_weeks = c(15, 17)))
}

test_that("records are write-once JSON with a hash-only manifest, and tampering is detected", {
  root <- withr::local_tempdir()
  man <- file.path(root, "decision_manifest.csv")
  d <- ld_lineup_record(root, man)
  expect_true(file.exists(d$path))
  mm <- readr::read_csv(man, col_types = readr::cols(.default = "c"))
  expect_equal(names(mm), c("decision_id", "league_alias", "season", "week", "type", "as_of_utc", "record_sha256", "git_commit"))
  expect_false(any(grepl("\"A\"|00-1", readLines(man))))       # no player names or ids in the manifest
  rd <- lg_ledger_read("league_test", 2026, root, man)
  expect_true(rd$verified$verified)
  rec <- rd$records[[d$decision_id]]
  expect_equal(rec$schema, "decision_record_v1")
  expect_equal(rec$type, "lineup")
  expect_equal(rec$metrics$ev_recommended, 47)
  expect_error(write_once(d$path, function(tmp) writeLines("x", tmp)))   # write-once
  write("tampered", d$path, append = TRUE)
  expect_false(lg_ledger_read("league_test", 2026, root, man)$verified$verified)
})

test_that("two decisions in the same second get distinct ids; unknown types are refused", {
  root <- withr::local_tempdir()
  man <- file.path(root, "m.csv")
  now <- as.POSIXct("2026-10-14 12:00", tz = "UTC")
  a <- lg_ledger_record("waivers", ld_inputs(), 2026, 6, list(x = 1), now = now, root = root, manifest = man)
  b <- lg_ledger_record("waivers", ld_inputs(), 2026, 6, list(x = 2), now = now, root = root, manifest = man)
  expect_false(identical(a$decision_id, b$decision_id))
  expect_error(lg_ledger_record("guess", ld_inputs(), 2026, 6, list(), root = root, manifest = man))
})

test_that("owner actions are appended privately", {
  root <- withr::local_tempdir()
  lg_ledger_action("d1", "followed", "", alias = "league_test", root = root)
  lg_ledger_action("d2", "ignored", "late news", alias = "league_test", root = root)
  a <- readr::read_csv(file.path(root, "league_test", "actions.csv"), col_types = readr::cols(.default = "c"))
  expect_equal(a$action, c("followed", "ignored"))
  expect_error(lg_ledger_action("d3", "maybe", alias = "league_test", root = root))
})

test_that("the outcome of record is the first stats retrieval after the Thursday noon that follows the week", {
  tg <- tibble::tibble(season = 2026L, week = 6L, team = c("A", "B"),
                       kickoff_utc = as.POSIXct(c("2026-10-16 00:15", "2026-10-20 00:15"), tz = "UTC"))  # Thu, Mon (ET)
  cut <- lg_ledger_outcome_cutoff(2026, 6, tg)
  expect_equal(format(cut, "%Y-%m-%d %H:%M", tz = "America/New_York"), "2026-10-22 12:00")
  root <- withr::local_tempdir()
  dir <- file.path(root, "player_stats", "season=2026")
  dir.create(dir, recursive = TRUE)
  for (s in c("20261020T120000Z", "20261022T170500Z", "20261023T010000Z")) file.create(file.path(dir, paste0("retrieved_at=", s, ".parquet")))
  expect_equal(basename(lg_ledger_outcome_file(2026, 6, tg, root)), "retrieved_at=20261022T170500Z.parquet")
  expect_true(is.na(lg_ledger_outcome_file(2026, 6, dplyr::mutate(tg, kickoff_utc = kickoff_utc + 30 * 86400), root)))
})

test_that("seal 1: the outcome join refuses to run before the season is over", {
  root <- withr::local_tempdir()
  man <- file.path(root, "m.csv")
  d <- ld_lineup_record(root, man)
  rec <- lg_ledger_read("league_test", 2026, root, man)$records[[1]]
  tg <- tibble::tibble(season = 2026L, week = 18L, kickoff_utc = as.POSIXct("2027-01-03 18:00", tz = "UTC"))
  expect_false(ledger_join_allowed(2026, tg, now = as.POSIXct("2026-10-25", tz = "UTC")))
  expect_true(ledger_join_allowed(2026, tg, now = as.POSIXct("2027-01-11", tz = "UTC")))
  pts <- c(`00-1` = 18, `00-2` = 3, `00-3` = 21, `00-4` = 10)
  expect_error(lg_ledger_join_lineup(rec, pts, ld_league(), allowed = FALSE), "sealed")
  j <- lg_ledger_join_lineup(rec, pts, ld_league(), allowed = TRUE)
  expect_equal(j$recommended, 18 + 3 + 10)
  expect_equal(j$alternative, 18 + 21 + 10)
  expect_equal(j$hindsight, 18 + 21 + 10)
  expect_equal(j$regret_recommended, 18)
  expect_equal(j$regret_alternative, 0)
})

test_that("seal 2: reports wait for the VL8-VL11 pre-registrations", {
  log <- withr::local_tempfile(fileext = ".md")
  writeLines(c("# Valuation log", "## 2026-10-07 — VL0: pre-specification", "## 2026-10-07 — VL1: league",
               "## 2026-10-13 — VL2: capture fix"), log)
  expect_false(ledger_reports_unsealed(log))
  j <- tibble::tibble(regret_recommended = 1, regret_alternative = 2, recommended = 10, alternative = 9)
  expect_error(lg_ledger_report(j, unsealed = ledger_reports_unsealed(log)), "sealed")
  write(c("## 2027-05-01 — VL8: lineup", "## 2027-05-01 — VL9: waivers", "## 2027-06-01 — VL10: draft",
          "## 2027-07-01 — VL11: decision batch"), log, append = TRUE)
  expect_true(ledger_reports_unsealed(log))
  expect_equal(lg_ledger_report(j, unsealed = TRUE)$mean_gain_vs_alternative, 1)
  # 2026 development entries with the same ids do not unseal (X-028)
  dev <- withr::local_tempfile(fileext = ".md")
  writeLines(c("## 2026-10-13 — VL8: lineup", "## 2026-10-14 — VL9: waivers", "## 2026-10-14 — VL10: draft",
               "## 2026-10-14 — VL11: decision batch"), dev)
  expect_false(ledger_reports_unsealed(dev))
  # the project's own log is still sealed
  expect_false(ledger_reports_unsealed(file.path(project_root, "research", "valuation_log.md")))
})
