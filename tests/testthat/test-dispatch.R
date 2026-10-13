# Kickoff-keyed dispatcher (master plan F0). Synthetic schedules only.

et <- function(x) {
  t <- as.POSIXct(x, tz = "America/New_York")
  attr(t, "tzone") <- "UTC"
  t
}

#' team_games with two rows (home/away) per game; `games` = list of c(home, away, "kickoff ET").
dispatch_tg <- function(games, week, season = 2026L) {
  purrr::imap(games, function(g, i) {
    tibble::tibble(season = season, week = as.integer(week), game_id = sprintf("%d_%02d_%s_%s", season, week, g[2], g[1]),
                   team = c(g[1], g[2]), opponent = c(g[2], g[1]), home = c(TRUE, FALSE), kickoff_utc = et(g[3]))
  }) |>
    purrr::list_rbind()
}

#' Week 5 (Thu/Sun/Mon) and week 6 (Thu, Sun with a London game, Sun main, SNF, Mon).
two_weeks <- function() {
  dplyr::bind_rows(
    dispatch_tg(list(c("A", "B", "2026-10-08 20:15"), c("C", "D", "2026-10-11 13:00"), c("E", "F", "2026-10-12 20:15")), 5),
    dispatch_tg(list(c("A", "C", "2026-10-15 20:15"), c("B", "D", "2026-10-18 09:30"), c("E", "G", "2026-10-18 13:00"),
                     c("F", "H", "2026-10-18 16:25"), c("I", "J", "2026-10-18 20:20"), c("K", "L", "2026-10-19 20:15")), 6)
  )
}

no_runs <- function() tibble::tibble(run_id = character(), season = integer(), week = integer(),
                                     predicted_at = as.POSIXct(character(), tz = "UTC"))
runs_at <- function(times, week = 6L) tibble::tibble(run_id = paste0("r", seq_along(times)), season = 2026L,
                                                    week = as.integer(week), predicted_at = et(times))

test_that("NFL season of a date: January and February belong to the previous season", {
  expect_equal(nfl_season(et("2026-09-10 20:00")), 2026L)
  expect_equal(nfl_season(et("2027-01-03 13:00")), 2026L)
  expect_equal(nfl_season(et("2027-02-14 18:00")), 2026L)
  expect_equal(nfl_season(et("2027-03-01 12:00")), 2027L)
})

test_that("slates group games by Eastern date and split an international morning game", {
  s <- dispatch_slates(two_weeks(), 2026, 6)
  expect_equal(s$slate_id, c("2026-10-15", "2026-10-18_am", "2026-10-18", "2026-10-19"))
  expect_equal(s$n_games, c(1L, 1L, 3L, 1L))
  expect_equal(s$first_kickoff_utc, et(c("2026-10-15 20:15", "2026-10-18 09:30", "2026-10-18 13:00", "2026-10-19 20:15")))
  # windows: [kickoff - 3 h, kickoff - 1.5 h), catch-up until kickoff - 30 min
  expect_equal(s$window_start[3], et("2026-10-18 10:00"))
  expect_equal(s$window_end[3], et("2026-10-18 11:30"))
  expect_equal(s$catchup_end[3], et("2026-10-18 12:30"))
  expect_equal(s$window_start[2], et("2026-10-18 06:30"))
})

test_that("Saturday and Thanksgiving slates are single slates keyed to their first kickoff", {
  sat <- dispatch_tg(list(c("A", "B", "2026-12-19 16:30"), c("C", "D", "2026-12-19 20:15"),
                          c("E", "F", "2026-12-20 13:00")), 15)
  s <- dispatch_slates(sat, 2026, 15)
  expect_equal(s$slate_id, c("2026-12-19", "2026-12-20"))
  expect_equal(s$window_start[1], et("2026-12-19 13:30"))
  tg <- dispatch_tg(list(c("A", "B", "2026-11-26 12:30"), c("C", "D", "2026-11-26 16:30"),
                         c("E", "F", "2026-11-26 20:20"), c("G", "H", "2026-11-29 13:00")), 12)
  s <- dispatch_slates(tg, 2026, 12)
  expect_equal(s$slate_id, c("2026-11-26", "2026-11-29"))
  expect_equal(s$n_games, c(3L, 1L))
  expect_equal(s$window_start[1], et("2026-11-26 09:30"))   # a morning-ish holiday kickoff, no split
})

test_that("windows follow the kickoff across the end of daylight saving time", {
  tg <- dispatch_tg(list(c("A", "B", "2026-11-08 13:00")), 9)
  s <- dispatch_slates(tg, 2026, 9)
  expect_equal(format(s$window_start, "%H:%M", tz = "UTC"), "15:00")   # 10:00 EST = 15:00 UTC
  expect_equal(format(s$window_start, "%H:%M", tz = "America/New_York"), "10:00")
})

test_that("early-week window runs from the morning after last week's final game to the day before kickoff", {
  ew <- dispatch_early_window(two_weeks(), 2026, 6)
  expect_equal(ew$start, et("2026-10-13 08:15"))   # Mon 20:15 + 12 h
  expect_equal(ew$end, et("2026-10-14 20:15"))     # Thu 20:15 - 24 h
  ew1 <- dispatch_early_window(two_weeks(), 2026, 5)
  expect_equal(ew1$start, et("2026-10-05 20:15"))   # no previous week: first kickoff - 72 h
})

test_that("a slate window with no run makes a run due; one run per window", {
  tg <- two_weeks()
  d <- dispatch_decision(et("2026-10-15 17:30"), tg, 2026, no_runs())
  expect_equal(d$action, "run")
  expect_equal(d$kind, "slate")
  expect_equal(d$slate_id, "2026-10-15")
  expect_equal(d$week, 6L)
  d2 <- dispatch_decision(et("2026-10-15 18:30"), tg, 2026, runs_at("2026-10-15 17:31"))
  expect_equal(d2$action, "none")
})

test_that("a missed window is caught up until kickoff - 30 min, then given up", {
  tg <- two_weeks()
  d <- dispatch_decision(et("2026-10-15 19:05"), tg, 2026, runs_at("2026-10-13 03:00"))
  expect_equal(d$action, "run")
  expect_equal(d$kind, "catch-up")
  late <- dispatch_decision(et("2026-10-15 19:50"), tg, 2026, runs_at("2026-10-13 03:00"))
  expect_equal(late$action, "none")
  expect_equal(late$next_due, et("2026-10-18 06:30"))   # the next slate's window
})

test_that("Sunday slates need their own runs even if a Thursday run exists", {
  tg <- two_weeks()
  runs <- runs_at(c("2026-10-13 03:00", "2026-10-15 17:31"))
  am <- dispatch_decision(et("2026-10-18 07:05"), tg, 2026, runs)
  expect_equal(am$slate_id, "2026-10-18_am")
  main <- dispatch_decision(et("2026-10-18 10:05"), tg, 2026, dplyr::bind_rows(runs, runs_at("2026-10-18 07:06")))
  expect_equal(main$action, "run")
  expect_equal(main$slate_id, "2026-10-18")
  # the Monday game gets its own pre-kickoff run as well
  mon <- dispatch_decision(et("2026-10-19 17:30"), tg, 2026, runs)
  expect_equal(mon$slate_id, "2026-10-19")
})

test_that("the early-week run is due only while the week has no run", {
  tg <- two_weeks()
  d <- dispatch_decision(et("2026-10-13 10:05"), tg, 2026, no_runs())
  expect_equal(d$action, "run")
  expect_equal(d$kind, "early-week")
  expect_equal(dispatch_decision(et("2026-10-13 10:05"), tg, 2026, runs_at("2026-10-13 03:00"))$action, "none")
  # before the window (Monday night game not yet played): week 5 still pending, nothing due
  expect_equal(dispatch_decision(et("2026-10-12 12:00"), tg, 2026, runs_at("2026-10-11 10:30", 5))$action, "none")
})

test_that("failed attempts are retried at most max_attempts times per slate", {
  tg <- two_weeks()
  log <- tibble::tibble(action = "run", season = "2026", week = "6", slate_id = "2026-10-15",
                        result = "weekly_run FAILED")
  d1 <- dispatch_decision(et("2026-10-15 18:05"), tg, 2026, no_runs(), log)
  expect_equal(d1$action, "run")
  d2 <- dispatch_decision(et("2026-10-15 18:05"), tg, 2026, no_runs(), dplyr::bind_rows(log, log))
  expect_equal(d2$action, "none")
  expect_match(d2$reason, "attempt limit")
})

test_that("nothing is due after the last regular-season kickoff", {
  d <- dispatch_decision(et("2026-10-20 12:00"), two_weeks(), 2026, no_runs())
  expect_equal(d$action, "none")
  expect_match(d$reason, "no upcoming")
})

test_that("post-report coverage uses each run's final reports, with a timing fallback", {
  tg <- two_weeks()
  runs <- runs_at(c("2026-10-15 17:31", "2026-10-17 08:00"))
  finals <- list(r1 = list(final = c("A", "C"), captured_at = et("2026-10-15 17:30")),
                 r2 = list(final = c("A", "C", "E", "G"), captured_at = et("2026-10-17 08:00")))
  ff <- function(run_id, season, week, team_games) finals[[run_id]]
  cov <- post_report_coverage(2026, 6, tg, runs, now = et("2026-10-18 14:00"), final_fn = ff)
  by <- stats::setNames(cov$post_report, cov$teams)
  expect_true(by[["A-C"]])    # Thursday game: both teams' final reports in r1's capture
  expect_true(by[["B-D"]])    # Sun 09:30: no designations, but r2's capture is 25.5 h before kickoff (fallback)
  expect_true(by[["E-G"]])    # Sun 13:00: both teams' final reports in r2's capture (29 h before)
  expect_false(by[["F-H"]])   # Sun 16:25: no final report and r2 captured 32.4 h before kickoff
  expect_false(by[["K-L"]])   # Monday: r2 is a Saturday capture, 60 h before kickoff
  expect_equal(cov$latest_run[cov$teams == "A-C"], "r1")
  expect_equal(cov$latest_run[cov$teams == "E-G"], "r2")
  # F-H kicks off within 3 h without a post-report run -> flagged; SNF (6 h) and started games are not
  expect_true(cov$flag[cov$teams == "F-H"])
  expect_false(cov$flag[cov$teams == "I-J"])
  expect_false(cov$flag[cov$teams == "A-C"])
  expect_equal(cov$slate_id[cov$teams == "B-D"], "2026-10-18_am")
  # a run made after `now` is not visible yet
  cov0 <- post_report_coverage(2026, 6, tg, runs, now = et("2026-10-16 12:00"), final_fn = ff)
  expect_true(all(cov0$latest_run %in% "r1"))
})

test_that("season-to-date coverage counts started games only and reads no outcome", {
  tg <- two_weeks()
  runs <- dplyr::bind_rows(runs_at("2026-10-15 17:31"), runs_at("2026-10-08 18:00", 5))
  ff <- function(run_id, season, week, team_games) list(final = c("A", "B", "C"), captured_at = et("2026-10-08 18:00"))
  rep <- ops_coverage_report(2026, tg, runs, from_week = 6, now = et("2026-10-16 09:00"), final_fn = ff)
  expect_equal(rep$n_games, 1L)       # only the Thursday game has kicked off
  expect_equal(rep$share_any_run, 1)
  expect_equal(rep$share_post_report, 1)
})

test_that("capture cadence counts distinct capture times per week", {
  man <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(tibble::tibble(file = letters[1:4], season = 2026, week = c(5, 5, 6, 6),
                                  captured_at_utc = c("2026-10-07 06:05:35", "2026-10-07 19:39:33",
                                                      "2026-10-13 07:06:39", "2026-10-13 07:06:39")), man)
  cad <- capture_cadence(2026, man)
  expect_equal(cad$week, c(5L, 6L))
  expect_equal(cad$captures, c(2L, 1L))
})

test_that("the manifest reader keeps run times exactly", {
  man <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(tibble::tibble(run_id = "20261013T070227Z", season = 2026, week = 6, lineages = "m1",
                                  predicted_at_utc = "2026-10-13T07:02:27Z"), man)
  r <- dispatch_runs(man)
  expect_equal(r$predicted_at, as.POSIXct("2026-10-13 07:02:27", tz = "UTC"))
  expect_equal(nrow(dispatch_runs(file.path(tempdir(), "missing.csv"))), 0L)
})

test_that("the lock blocks a second dispatcher until it goes stale", {
  lock <- file.path(withr::local_tempdir(), "dispatch.lock")
  expect_true(dispatch_lock(lock))
  expect_false(dispatch_lock(lock))
  Sys.setFileTime(lock, Sys.time() - 4 * 3600)
  expect_true(dispatch_lock(lock))
  dispatch_unlock(lock)
  expect_false(file.exists(lock))
})

test_that("the wrapper and task definition quote paths with spaces and never push", {
  cmd <- ops_wrapper_cmd("C:/Users/x/My Project", "C:/Program Files/R/R-4.5.1/bin/Rscript.exe")
  expect_true(any(grepl('cd /d "C:\\Users\\x\\My Project"', cmd, fixed = TRUE)))
  expect_true(any(grepl('if not defined HOME set "HOME=%USERPROFILE%"', cmd, fixed = TRUE)))   # git identity
  expect_true(any(grepl('"C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe" scripts\\ops_dispatch.R', cmd, fixed = TRUE)))
  expect_false(any(grepl("push", cmd, ignore.case = TRUE) & !grepl("^rem", cmd)))
  xml <- ops_task_xml("C:/Users/x/My Project/scripts/ops/ffball_dispatch.cmd", "C:/Users/x/My Project",
                      "PC\\x", as.POSIXct("2026-10-13 18:05:00"))
  expect_true(any(grepl("<LogonType>InteractiveToken</LogonType>", xml, fixed = TRUE)))
  expect_true(any(grepl("<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>", xml, fixed = TRUE)))
  expect_true(any(grepl("<Interval>PT1H</Interval>", xml, fixed = TRUE)))
  expect_true(any(grepl('--headless "C:\\Users\\x\\My Project\\scripts\\ops\\ffball_dispatch.cmd"', xml, fixed = TRUE)))
  expect_true(any(grepl("<StartBoundary>2026-10-13T18:05:00</StartBoundary>", xml, fixed = TRUE)))
  f <- withr::local_tempfile(fileext = ".xml")
  write_utf16(xml, f)
  expect_equal(readBin(f, "raw", 2), as.raw(c(0xFF, 0xFE)))
})

test_that("status lines surface alerts, unpushed commits and capture cadence", {
  dec <- list(action = "none", kind = NA_character_, reason = "no run due", season = 2026L, week = 6L,
              slate_id = NA_character_, next_due = et("2026-10-18 10:00"))
  cov <- tibble::tibble(teams = c("A-C", "B-D"), kickoff_utc = et(c("2026-10-15 20:15", "2026-10-18 09:30")),
                        started = c(TRUE, FALSE), latest_run = c("r1", NA), post_report = c(TRUE, FALSE),
                        flag = c(FALSE, TRUE))
  l <- dispatch_status_lines(et("2026-10-18 07:00"), dec, cov, tibble::tibble(week = 6L, captures = 2L),
                             list(commits_not_pushed = 2L, code_dirty = TRUE, manifests_uncommitted = TRUE))
  expect_true(any(grepl("ALERT: 1 game", l)))
  expect_true(any(grepl("COMMIT NEEDED", l)))
  expect_true(any(grepl("PUSH NEEDED: 2", l)))
  expect_true(any(grepl("W6=2", l)))
  expect_true(any(grepl("scheduled runs will be skipped", l)))
})
