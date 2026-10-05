reg_dir <- file.path(project_root, "models", "registry")

test_that("M1 registry defines the five frozen models", {
  reg <- read_registry("m1", reg_dir)
  expect_setequal(names(reg$models),
                  c("m1_espn_raw", "m1_espn_recal", "m1_espn_plus", "m1_no_espn", "m1_naive"))
  expect_equal(reg$frozen_commit, "9663ca7")
  expect_equal(reg$data$history_start_season, 2019)
  expect_equal(reg$data$min_train_season, 2020)
})

test_that("M1 frozen feature lists still match the code they were frozen from", {
  # If this fails, someone edited FEATURES_* constants that M1 was built with.
  # M1 is rebuilt from the registry, but the constants document what it used.
  reg <- read_registry("m1", reg_dir)
  expect_identical(unlist(reg$models$m1_espn_plus$features), feature_set("espn_plus"))
  expect_identical(unlist(reg$models$m1_no_espn$features), feature_set("usage"))
})

test_that("registry specs are named by registry id and use registry features", {
  specs <- registry_specs(read_registry("m1", reg_dir))
  expect_equal(unname(purrr::map_chr(specs, "name")), names(specs))
  expect_identical(specs$m1_no_espn$features, feature_set("usage"))
  expect_equal(specs$m1_naive$features, c("fantasy_pts_roll8", "prev_season_pts_mean"))
})

test_that("fingerprint check passes identical predictions and fails changed ones", {
  preds <- tibble::tibble(model = "m_x", season = 2024L, week = 1:3, gsis_id = "a", pred = c(1, 2, 3))
  fp <- prediction_fingerprint(preds)
  manifest <- tibble::tibble(provider = "nflverse", season = "2024", path = "x.parquet", bytes = 10)
  reg <- list(data = list(history_start_season = 2019, min_train_season = 2020))
  fp$raw_data_hash_xxh128 <- fingerprint_data_hash(manifest, 2019, 2020)
  path <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(fp, path)

  expect_equal(check_frozen_fingerprint(preds, path, manifest, reg)$status, "identical")
  changed <- dplyr::mutate(preds, pred = pred + c(0, 0, 1e-4))
  expect_error(check_frozen_fingerprint(changed, path, manifest, reg), "changed")
  other_data <- dplyr::mutate(manifest, bytes = 11)
  expect_equal(check_frozen_fingerprint(changed, path, other_data, reg)$status,
               "unverifiable_data_changed")
})

test_that("data-version hash ignores files outside the lineage's window", {
  m <- tibble::tibble(provider = c("nflverse", "nflverse", "ESPN", "nflverse"),
                      season = c("2019", NA, "2020", "2024"),
                      path = c("a", "ids", "e", "b"), bytes = c(1, 2, 3, 4))
  h <- fingerprint_data_hash(m, 2019, 2020)
  extra <- dplyr::bind_rows(m, tibble::tibble(provider = c("nflverse", "ESPN", "nflverse"),
                                               season = c("2017", "2018", "2026"),
                                               path = c("old", "olde", "live"), bytes = 9))
  expect_identical(fingerprint_data_hash(extra, 2019, 2020), h)
})

test_that("M2 registry defines three frozen models built from registry entries", {
  reg <- read_registry("m2", reg_dir)
  expect_setequal(names(reg$models), c("m2_espn_cal", "m2_no_espn", "m2_espn_aug"))
  expect_equal(reg$data$min_train_season, 2018)
  specs <- registry_specs(reg)
  expect_equal(unname(purrr::map_chr(specs, "name")), names(specs))
  # frozen feature lists = the M2 feature set at freeze time (edits to the
  # FEATURES_M2 constant would not change the frozen models, which use the registry)
  expect_identical(unlist(reg$models$m2_no_espn$features), FEATURES_M2)
  expect_identical(unlist(reg$models$m2_espn_cal$features), ESPN_COMPONENTS)
  expect_false(any(c("implied_team_total", "team_spread", "total_line", "inj_questionable") %in%
                     unlist(reg$models$m2_espn_aug$features)))   # no betting lines / injuries
})

test_that("frozen registries refuse to be overwritten", {
  expect_error(write_m2_registry(list(), list(), list(), path = file.path(reg_dir, "m2.yml")), "never overwritten")
})
