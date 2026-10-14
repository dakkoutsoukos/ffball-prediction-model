# I3 monitoring (VL13). Synthetic manifests and sequences only.

i3_fixture <- function(now) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  stamp <- function(h, fmt = "%Y%m%dT%H%M%SZ") format(now - h * 3600, fmt, tz = "UTC")
  readr::write_csv(tibble::tibble(season = "2026", week = "6", captured_at_utc = c(stamp(60), stamp(40))),
                   file.path(d, "capture.csv"))
  readr::write_csv(tibble::tibble(season = "2026", captured_at_utc = stamp(200)), file.path(d, "snapshot.csv"))
  readr::write_csv(tibble::tibble(season = "2026", as_of_utc = stamp(10, "%Y-%m-%dT%H:%M:%SZ")), file.path(d, "valuation.csv"))
  readr::write_csv(tibble::tibble(logged_at_utc = c(stamp(48, "%Y-%m-%dT%H:%M:%SZ"), stamp(5, "%Y-%m-%dT%H:%M:%SZ")),
                                  reason = c("capture", "no run due"),
                                  result = c("error: ESPN request failed with HTTP 401", "-")),
                   file.path(d, "dispatch.csv"))
  d
}

i3_run <- function(d, now, ...) {
  i3_checks(2026, now = now, capture_manifest = file.path(d, "capture.csv"), snapshot_manifest = file.path(d, "snapshot.csv"),
            valuation_manifest = file.path(d, "valuation.csv"), dispatch_log = file.path(d, "dispatch.csv"), ...)
}

test_that("I3 checks apply the VL13 thresholds", {
  now <- as.POSIXct("2026-10-15 12:00:00", tz = "UTC")
  d <- i3_fixture(now)
  odds <- list(a = list(type = "odds", as_of_utc = "2026-10-14T10:00:00Z", metrics = list(sims = 2000)),
               b = list(type = "lineup", as_of_utc = "2026-10-15T10:00:00Z", metrics = list()))
  cov <- tibble::tibble(flag = c(FALSE, TRUE))
  x <- i3_run(d, now, coverage = cov, ledger_records = odds)
  lv <- stats::setNames(x$level, x$check)
  expect_equal(unname(lv[c("capture_age", "league_snapshot_age", "valuation_run_age", "dispatcher_last_entry",
                           "games_without_post_report_run", "espn_http_401_last_7_days", "odds_max_mc_se")]),
               c("WARN", "ALERT", "OK", "ALERT", "ALERT", "ALERT", "ALERT"))
  expect_equal(x$value[x$check == "capture_age"], 40, tolerance = 1e-6)
  expect_equal(x$value[x$check == "odds_max_mc_se"], sqrt(0.25 / 2000))
  odds$a$metrics$sims <- 10000
  y <- i3_run(d, now, ledger_records = odds)
  expect_equal(y$level[y$check == "odds_max_mc_se"], "OK")
  expect_false("games_without_post_report_run" %in% y$check)
})

test_that("freshness checks rest off season, and a 401 older than a week is ignored", {
  now <- as.POSIXct("2026-10-15 12:00:00", tz = "UTC")
  d <- i3_fixture(now)
  tg <- tibble::tibble(kickoff_utc = as.POSIXct("2026-12-30 18:00:00", tz = "UTC"))
  x <- i3_run(d, now, team_games = tg)
  expect_true(all(x$level[x$check %in% c("capture_age", "league_snapshot_age", "valuation_run_age")] == "OK"))
  later <- now + 10 * 86400
  z <- i3_run(d, later)
  expect_equal(z$level[z$check == "espn_http_401_last_7_days"], "OK")
})

test_that("the coverage e-process keeps its level under the null and alarms under drift", {
  set.seed(1)
  null_alarm <- mean(replicate(400, !is.na(i3_alarm_at(i3_eprocess_coverage(stats::rbinom(200, 1, 0.8))))))
  expect_lte(null_alarm, 0.08)
  drift_alarm <- mean(replicate(200, !is.na(i3_alarm_at(i3_eprocess_coverage(stats::rbinom(200, 1, 0.6))))))
  expect_gte(drift_alarm, 0.75)
  over <- mean(replicate(200, !is.na(i3_alarm_at(i3_eprocess_coverage(stats::rbinom(200, 1, 0.95))))))
  expect_gte(over, 0.5)                                    # two-sided: over-coverage is detected too
})

test_that("the difference e-process respects the predictable bound", {
  set.seed(2)
  b <- stats::runif(300, 0.5, 3)
  null_alarm <- mean(replicate(300, {
    x <- stats::runif(300, -1, 1)
    !is.na(i3_alarm_at(i3_eprocess_diff(x * b, b)))
  }))
  expect_lte(null_alarm, 0.06)
  better <- i3_eprocess_diff(stats::runif(300, -0.2, 1) * b, b)
  expect_false(is.na(i3_alarm_at(better)))
  expect_error(i3_eprocess_diff(c(0.5, 3), c(1, 1)), "exceeds its predictable bound")
  expect_equal(i3_eprocess_diff(c(0, 0), c(0, 0)), c(1, 1))
})

test_that("the drift monitor refuses 2026 outcomes before the season is over", {
  reg <- read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))
  expect_error(i3_drift_guard(2026, register = reg), "sealed|may not use")
  expect_error(i3_drift_guard(2026, family = "weekly_wr_points", register = reg), "sealed")
  expect_error(i3_drift_guard(2027, register = reg), "needs approval")
  expect_true(i3_drift_guard(2027, register = reg, approved_in_season = TRUE))
  expect_error(i3_drift_guard(2023, register = reg), "may not use")
})
