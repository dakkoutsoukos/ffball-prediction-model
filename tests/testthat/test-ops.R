ops_games <- function() {
  ko <- as.POSIXct(c("2026-10-09 00:15", "2026-10-11 17:00", "2026-10-13 00:15", "2026-10-16 00:15"), tz = "UTC")
  tibble::tibble(season = 2026L, week = c(5L, 5L, 5L, 6L), game_id = paste0("g", 1:4),
                 team = c("A", "B", "C", "D"), home = TRUE, kickoff_utc = ko)
}

test_that("target week = earliest week with a game not yet kicked off", {
  tg <- ops_games()
  expect_equal(infer_target_week(tg, 2026, as.POSIXct("2026-10-06 12:00", tz = "UTC")), 5L)
  expect_equal(infer_target_week(tg, 2026, as.POSIXct("2026-10-12 12:00", tz = "UTC")), 5L)  # Monday game left
  expect_equal(infer_target_week(tg, 2026, as.POSIXct("2026-10-14 12:00", tz = "UTC")), 6L)
  expect_true(is.na(infer_target_week(tg, 2026, as.POSIXct("2027-01-01", tz = "UTC"))))
})

test_that("coverage shows which upcoming games have a run made before their kickoff", {
  tg <- ops_games()
  ko <- week_kickoffs(tg, 2026, 5, as.POSIXct("2026-10-10 12:00", tz = "UTC"))
  expect_equal(ko$started, c(TRUE, FALSE, FALSE))
  man <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(tibble::tibble(run_id = c("r1", "r2"), season = 2026, week = 5, lineages = c("m1", "m1+m2"),
                                  predicted_at_utc = c("2026-10-08T20:00:00Z", "2026-10-11T12:00:00Z")), man)
  cov <- week_coverage(2026, 5, ko, man)
  expect_equal(cov$latest_valid_run, c("r1", "r2", "r2"))   # Thursday game only covered by r1
})

test_that("snapshot verification detects tampering", {
  root <- withr::local_tempdir()
  dir <- file.path(root, "season=2026", "week=05")
  dir.create(dir, recursive = TRUE)
  pq <- file.path(dir, "captured_at=20261005T194046Z_wr.parquet")
  arrow::write_parquet(tibble::tibble(x = 1), pq)
  raw <- sub("[.]parquet$", ".json.gz", pq)
  writeLines("{}", gzfile(raw))
  man <- file.path(root, "m.csv")
  readr::write_csv(tibble::tibble(file = basename(pq), season = 2026, week = 5,
                                  parquet_sha256 = sha256_file(pq), raw_sha256 = sha256_file(raw)), man)
  expect_true(all(unlist(verify_snapshot_archive(man, root)[, c("parquet_ok", "raw_ok")])))
  arrow::write_parquet(tibble::tibble(x = 2), pq)
  expect_false(verify_snapshot_archive(man, root)$parquet_ok)
})

test_that("backups copy, verify, and never delete at the destination", {
  src <- withr::local_tempdir()
  dest <- withr::local_tempdir()
  d <- file.path(src, "archive")
  dir.create(d)
  writeLines("evidence", file.path(d, "a.txt"))
  writeLines("keep me", file.path(dest, "unrelated.txt"))
  withr::local_dir(src)
  marker <- file.path(dest, "marker")
  rows <- backup_archives(dest, dirs = "archive", marker = marker)
  expect_true(all(rows$verified))
  expect_equal(readLines(file.path(dest, "archive", "a.txt")), "evidence")
  expect_true(file.exists(file.path(dest, "unrelated.txt")))
  expect_error(backup_archives(file.path(dest, "missing"), dirs = "archive", marker = marker), "Backup destination")
})

test_that("frozen lineages are discovered from the registry directory", {
  expect_true(all(c("m1", "m2") %in% frozen_lineages(file.path(project_root, "models", "registry"))))
})
