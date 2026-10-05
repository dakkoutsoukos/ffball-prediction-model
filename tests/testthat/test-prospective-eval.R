make_run <- function(root, manifest, run_id, predicted_at, snapshot_at, preds) {
  dir <- file.path(root, "season=2026", "week=05", paste0("run=", run_id))
  dir.create(dir, recursive = TRUE)
  p <- file.path(dir, "predictions.parquet")
  preds$predicted_at_utc <- predicted_at
  preds$snapshot_captured_at_utc <- snapshot_at
  arrow::write_parquet(preds, p)
  append_manifest(tibble::tibble(run_id = run_id, season = 2026, week = 5, predictions_sha256 = sha256_file(p)),
                  manifest)
}

base_preds <- function(pred) {
  tibble::tibble(model_id = "m_a", season = 2026L, week = 5L, gsis_id = c("g1", "g2"),
                 kickoff_utc = as.POSIXct(c("2026-10-09 00:15", "2026-10-11 17:00"), tz = "UTC"),
                 espn_proj = c(10, 5), pred = pred)
}

test_that("archive verification detects tampered files", {
  root <- withr::local_tempdir(); manifest <- file.path(root, "m.csv")
  make_run(root, manifest, "r1", "2026-10-05T20:00:00Z", "2026-10-05T19:00:00Z", base_preds(c(1, 2)))
  expect_true(all(verify_prediction_archive(manifest, root)$verified))
  p <- list.files(root, pattern = "predictions.parquet", recursive = TRUE, full.names = TRUE)
  arrow::write_parquet(base_preds(c(9, 9)), p)          # tamper
  expect_false(any(verify_prediction_archive(manifest, root)$verified))
})

test_that("official prediction = latest verified run before each player's kickoff", {
  root <- withr::local_tempdir(); manifest <- file.path(root, "m.csv")
  make_run(root, manifest, "r1", "2026-10-05T20:00:00Z", "2026-10-05T19:00:00Z", base_preds(c(1, 1)))
  make_run(root, manifest, "r2", "2026-10-08T21:00:00Z", "2026-10-08T20:00:00Z", base_preds(c(2, 2)))
  # r3 is after the Thursday kickoff: valid only for the Sunday player
  make_run(root, manifest, "r3", "2026-10-10T12:00:00Z", "2026-10-10T11:00:00Z", base_preds(c(3, 3)))
  # r4's snapshot is fine but it was made after both kickoffs
  make_run(root, manifest, "r4", "2026-10-12T12:00:00Z", "2026-10-10T11:00:00Z", base_preds(c(4, 4)))
  off <- official_predictions(verify_prediction_archive(manifest, root))
  expect_equal(off$pred[off$gsis_id == "g1"], 2)
  expect_equal(off$pred[off$gsis_id == "g2"], 3)
})

test_that("prospective scoring uses only completed weeks and zero-fills non-players", {
  off <- base_preds(c(8, 4)) |>
    dplyr::bind_rows(dplyr::mutate(base_preds(c(10, 5)), model_id = "m1_espn_raw"))
  outcomes <- tibble::tibble(season = 2026L, week = 5L, gsis_id = "g1", fantasy_pts = 12)
  open <- tibble::tibble(season = 2026L, week = 5L, game_final = c(TRUE, FALSE))
  expect_equal(score_prospective(off, outcomes, open, reps = 50)$weeks_complete, 0L)
  done <- tibble::tibble(season = 2026L, week = 5L, game_final = TRUE)
  s <- score_prospective(off, outcomes, done, reps = 50)
  expect_equal(s$weeks_complete, 1)
  m <- dplyr::filter(s$metrics, model == "m_a")
  expect_equal(m$mae, mean(c(abs(8 - 12), abs(4 - 0))))      # g2 had no stat line -> 0 points
  expect_true("m1_espn_raw" %in% s$comparisons$baseline)
})
