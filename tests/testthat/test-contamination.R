# Contamination register, point-in-time registry and an evaluation regression check (master plan F2-lite).

reg_path <- function() file.path(project_root, "research", "contamination_register.yml")

test_that("the register allows each family's own seasons and roles", {
  r <- read_contamination_register(reg_path())
  expect_true(assert_family_seasons("injury_stack", 2020:2023, "development", r))
  # the injury stack's one 2019 check was run (E19c) and is recorded under spent_checks
  expect_error(assert_family_seasons("injury_stack", 2019, "check", r), "already spent")
  expect_true(assert_family_seasons("distribution_stack", 2024, "check", r))
  # VL11 ran once on 2025 and is recorded under spent_checks
  expect_error(assert_family_seasons("decision_family", 2025, "check", r), "already spent")
  expect_true(assert_family_seasons("horizon_study", 2026, "outcome_free", r))
})

test_that("check seasons stay with their batch, and 2026 is never development data", {
  r <- read_contamination_register(reg_path())
  expect_error(assert_family_seasons("injury_stack", 2024, "check", r), "may not use")        # reserved for distributions
  expect_error(assert_family_seasons("distribution_stack", 2024, "development", r), "may not use")
  expect_error(assert_family_seasons("distribution_stack", 2025, "development", r), "may not use")
  expect_error(assert_family_seasons("decision_family", 2024, "check", r), "may not use")
  expect_error(assert_family_seasons("weekly_wr_points", 2024, "development", r), "may not use")
  expect_error(assert_family_seasons("new_family", 2020, "development", r), "not in the contamination register")
  # 2026 cannot be development data even if a family listed it
  r2 <- r
  r2$families$injury_stack$development <- c(r2$families$injury_stack$development, 2026L)
  expect_error(assert_family_seasons("injury_stack", 2026, "development", r2), "sealed")
})

test_that("sealed seasons open for confirmatory use only once the season is over", {
  r <- read_contamination_register(reg_path())
  expect_error(assert_family_seasons("weekly_wr_points", 2026, "confirmatory", r), "sealed until")
  expect_true(assert_family_seasons("weekly_wr_points", 2026, "confirmatory", r, season_over = TRUE))
  expect_true(assert_family_seasons("weekly_wr_points", 2027, "confirmatory", r))
})

test_that("a check season can be spent only once", {
  r <- read_contamination_register(reg_path())
  r$spent_checks <- list(list(date = "2027-03-01", family = "distribution_stack", season = 2024L, entry = "E22"))
  expect_error(assert_family_seasons("distribution_stack", 2024, "check", r), "already spent")
  expect_true(assert_family_seasons("injury_stack", 2019, "check", r))   # another family's batch is unaffected
})

test_that("the point-in-time registry marks historical ESPN values as late-horizon", {
  p <- yaml::read_yaml(file.path(project_root, "config", "pit_registry.yml"))
  expect_equal(p$sources$espn_weekly_history$use, "late_horizon_only")
  expect_equal(p$sources$injuries_final_report$invalid_seasons, 2025L)
  expect_true(all(c("schedule_lines", "nfldata_git", "espn_snapshots") %in% names(p$sources)))
})

test_that("the existing paired bootstrap reproduces the stored M2 holdout comparison exactly", {
  store <- file.path(project_root, "_targets")
  skip_if(!dir.exists(store), "no targets store")
  aligned <- tryCatch(targets::tar_read(m2_holdout_aligned, store = store), error = function(e) NULL)
  stored <- tryCatch(targets::tar_read(m2_holdout_comparisons, store = store), error = function(e) NULL)
  skip_if(is.null(aligned) || is.null(stored), "M2 holdout targets not built")
  cfg <- withr::with_dir(project_root, read_project_config())
  now <- pooled_bootstrap(aligned, "m2_espn_aug", "m2_espn_cal", cfg$evaluation$bootstrap_reps, cfg$evaluation$seed)
  ref <- stored[stored$model == "m2_espn_aug" & stored$baseline == "m2_espn_cal" & stored$subset == "all", ]
  expect_equal(now$mae_diff, ref$mae_diff)
  expect_equal(now$ci_low, ref$ci_low)
  expect_equal(now$ci_high, ref$ci_high)
  expect_equal(now$n_weeks, ref$n_weeks)
})
