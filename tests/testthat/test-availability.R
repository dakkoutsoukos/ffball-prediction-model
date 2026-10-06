inj_file <- function(rows) {
  p <- withr::local_tempfile(fileext = ".parquet", .local_envir = parent.frame())
  arrow::write_parquet(rows, p)
  p
}
sched4 <- function(season = 2023L) {
  tibble::tibble(season = season, week = 1:4, team = "KC",
                 kickoff_utc = as.POSIXct(sprintf("%d-09-%02d 17:00", season, c(10, 17, 24, 30)), tz = "UTC"))
}

test_that("practice status and body parts are normalised to broad groups", {
  expect_equal(normalize_practice(c("Did Not Participate In Practice", "Limited Participation in Practice",
                                    "Full Participation in Practice", "\n", NA)),
               c("DNP", "LP", "FP", NA, NA))
  expect_equal(body_group(c("Hamstring", "Concussion", "Illness", "Shoulder", "Not Injury Related - Personal", NA, "Eye")),
               c("lower", "head", "non_injury", "upper", "non_injury", NA, "other"))
})

test_that("listed-only players are kept, and dropped rows are counted by reason", {
  rows <- tibble::tibble(
    season = 2023L, game_type = "REG", team = "KC", week = c(1L, 1L, 1L, 2L),
    gsis_id = c("a", "b", "c", "a"), position = "WR",
    report_status = c("Questionable", NA, "Out", NA),
    practice_status = c("Limited Participation in Practice", "Full Participation in Practice", NA, NA),
    report_primary_injury = c("Ankle", "Knee", "Hamstring", "Ankle"), practice_primary_injury = NA,
    date_modified = as.POSIXct(c("2023-09-08 19:00", "2023-09-08 19:00", "2023-09-10 18:00", NA), tz = "UTC")
  )
  d <- pregame_injury_detail(inj_file(rows), sched4())
  expect_setequal(d$gsis_id, c("a", "b"))                         # c after kickoff, a-week2 untimed
  expect_equal(d$designation[d$gsis_id == "b"], "listed_only")
  expect_equal(d$practice[d$gsis_id == "a"], "LP")
  cov <- injury_coverage_report(d)
  expect_equal(cov$after_kickoff, 1)
  expect_equal(cov$untimed, 1)
})

test_that("duplicated player-weeks keep the most severe designation", {
  rows <- tibble::tibble(season = 2023L, game_type = "REG", team = "KC", week = 1L, gsis_id = c("a", "a"),
                         position = "WR", report_status = c("Questionable", "Out"), practice_status = NA,
                         report_primary_injury = "Knee", practice_primary_injury = NA,
                         date_modified = as.POSIXct("2023-09-08 19:00", tz = "UTC"))
  expect_equal(pregame_injury_detail(inj_file(rows), sched4())$designation, "Out")
})

test_that("Pacific correction applies to 2017-2020 on both DST sides", {
  # 16:30 PT on 2019-09-08 (PDT, UTC-7) = 23:30 UTC; 10:30 PT on 2019-12-01 (PST, UTC-8) = 18:30 UTC
  tg <- tibble::tibble(season = 2019L, week = c(1L, 13L), team = "KC",
                       kickoff_utc = as.POSIXct(c("2019-09-08 23:00", "2019-12-01 18:00"), tz = "UTC"))
  rows <- tibble::tibble(season = 2019L, game_type = "REG", team = "KC", week = c(1L, 13L), gsis_id = c("a", "b"),
                         position = "WR", report_status = "Questionable", practice_status = NA,
                         report_primary_injury = "Knee", practice_primary_injury = NA,
                         date_modified = as.POSIXct(c("2019-09-08 16:30", "2019-12-01 10:30"), tz = "UTC"))
  expect_equal(nrow(pregame_injury_detail(inj_file(rows), tg)), 0)   # both land after kickoff once corrected
})

test_that("trajectory features use only the team's earlier games", {
  det <- tibble::tibble(season = 2023L, week = c(1L, 2L, 4L), team = "KC", gsis_id = "a", position = "WR",
                        designation = c("Questionable", "Out", "Questionable"), practice = c("LP", "DNP", "FP"),
                        body = "lower", known_at = as.POSIXct("2023-09-01", tz = "UTC"))
  tg <- dplyr::mutate(sched4(), home = TRUE)
  t <- tibble::tibble(season = 2023L, week = c(2L, 3L, 4L), gsis_id = "a", team = "KC")
  f <- add_availability_features(t, det, tg)
  expect_equal(f$prev_designation, c("Questionable", "Out", "none"))   # week 3 not listed
  expect_equal(f$weeks_listed_streak, c(1L, 2L, 0L))
  expect_equal(f$designation, c("Out", "none", "Questionable"))      # this-week report (pregame-valid)
  # a report for week 4 must not change week-3 features (no backward leakage)
  later <- dplyr::bind_rows(det, tibble::tibble(season = 2023L, week = 3L, team = "KC", gsis_id = "a", position = "WR",
                                                designation = "Out", practice = "DNP", body = "lower",
                                                known_at = as.POSIXct("2023-09-22", tz = "UTC")))
  f2 <- add_availability_features(t[1, ], later, tg)
  expect_equal(f2$prev_designation, f$prev_designation[1])
  expect_equal(f2$weeks_listed_streak, f$weeks_listed_streak[1])
})

test_that("corrupting reports from a cutoff week on never changes earlier weeks' features", {
  det <- tibble::tibble(season = 2023L, week = rep(1:4, 2), team = "KC", gsis_id = rep(c("a", "b"), each = 4),
                        position = "WR", designation = c("Questionable", "none", "Out", "Questionable",
                                                         "listed_only", "Questionable", "none", "Doubtful"),
                        practice = "LP", body = "lower", known_at = as.POSIXct("2023-09-01", tz = "UTC")) |>
    dplyr::filter(designation != "none")
  tg <- dplyr::mutate(sched4(), home = TRUE)
  t <- tidyr::expand_grid(season = 2023L, week = 1:4, gsis_id = c("a", "b")) |> dplyr::mutate(team = "KC")
  for (cut in 2:4) {
    base <- add_availability_features(dplyr::filter(t, week < cut), det, tg)
    bad <- dplyr::mutate(det, designation = ifelse(week >= cut, "Out", designation), practice = ifelse(week >= cut, "DNP", practice))
    bad <- dplyr::bind_rows(bad, tibble::tibble(season = 2023L, week = cut, team = "KC", gsis_id = c("a", "b"),
                                                position = "WR", designation = "Out", practice = "DNP", body = "head",
                                                known_at = as.POSIXct("2023-09-01", tz = "UTC"))) |>
      dplyr::distinct(season, week, gsis_id, .keep_all = TRUE)
    pert <- add_availability_features(dplyr::filter(t, week < cut), bad, tg)
    expect_identical(base, pert)
  }
})

test_that("live detail: target week needs a final report; earlier weeks feed lags only", {
  tg <- tibble::tibble(season = 2026L, week = rep(1:3, 2), team = rep(c("KC", "BUF"), each = 3),
                       kickoff_utc = as.POSIXct(sprintf("2026-09-%02d 17:00", rep(c(13, 20, 27), 2)), tz = "UTC"))
  rows <- tibble::tibble(
    season = 2026L, game_type = "REG", week = c(1L, 2L, 3L, 3L, 3L),
    team = c("KC", "KC", "KC", "KC", "BUF"), gsis_id = c("a", "a", "a", "b", "c"), position = "WR",
    report_status = c("Questionable", NA, "Questionable", NA, NA),
    practice_status = c("Limited Participation in Practice", "Full Participation in Practice",
                        "Did Not Participate In Practice", "Limited Participation in Practice",
                        "Did Not Participate In Practice"),
    report_primary_injury = "Knee", practice_primary_injury = NA
  )
  captured <- as.POSIXct("2026-09-26 12:00", tz = "UTC")      # Saturday of week 3
  d <- live_injury_detail(inj_file(rows), tg, captured, 2026L, 3L)
  # KC's week-3 report is final (one designation); BUF's is practice-only -> dropped
  expect_setequal(paste(d$week, d$gsis_id), c("1 a", "2 a", "3 a", "3 b"))
  expect_equal(attr(d, "final_teams"), "KC")
  f <- m4_add_features(tibble::tibble(season = 2026L, week = 3L, gsis_id = c("a", "b", "c"), team = c("KC", "KC", "BUF")),
                       d, dplyr::mutate(tg, home = TRUE))
  expect_equal(f$group, c("Q_DNP", "listed_DNP_LP", "not_listed"))
  expect_equal(f$weeks_listed_streak, c(2L, 0L, 0L))
  # a capture AFTER a team's kickoff gives that team nothing for the target week
  late <- live_injury_detail(inj_file(rows), tg, as.POSIXct("2026-09-27 18:00", tz = "UTC"), 2026L, 3L)
  expect_false(any(late$week == 3))
})

test_that("injury leakage check passes M4 features and catches planted leaks", {
  tg <- dplyr::mutate(sched4(), home = TRUE)
  raw <- tibble::tibble(
    season = 2023L, game_type = "REG", team = "KC", week = rep(1:4, each = 2), gsis_id = rep(c("a", "b"), 4),
    position = "WR", report_status = c("Questionable", NA, NA, "Questionable", "Doubtful", NA, NA, NA),
    practice_status = rep(c("Limited Participation in Practice", "Full Participation in Practice"), 4),
    report_primary_injury = "Knee", practice_primary_injury = NA,
    date_modified = tg$kickoff_utc[rep(1:4, each = 2)] - 3600 * 48
  )
  targets <- tidyr::expand_grid(season = 2023L, week = 1:4, gsis_id = c("a", "b")) |>
    dplyr::mutate(team = "KC", roster_status = "ACT", has_stat_line = TRUE, actual = 10, actual_targets = 6)
  m4_fn <- function(t, rows, team_games) {
    m4_add_features(t, pregame_injury_detail(inj_file(rows), team_games), team_games)
  }
  expect_identical(check_injury_leakage(targets, raw, tg, m4_fn), character(0))
  # planted: next week's designation
  next_week <- function(t, rows, team_games) {
    det <- pregame_injury_detail(inj_file(rows), team_games)
    nxt <- dplyr::transmute(det, season, week = week - 1L, gsis_id, next_des = designation)
    dplyr::left_join(m4_fn(t, rows, team_games), nxt, by = c("season", "week", "gsis_id"))
  }
  expect_true("next_des" %in% check_injury_leakage(targets, raw, tg, next_week))
  # planted: a report used without its timestamp (post-kickoff report)
  untimed <- function(t, rows, team_games) {
    rows$date_modified <- as.POSIXct("2000-01-01", tz = "UTC")
    m4_fn(t, rows, team_games)
  }
  expect_true("designation" %in% check_injury_leakage(targets, raw, tg, untimed))
  # planted: realised game-day active status
  realised <- function(t, rows, team_games) dplyr::mutate(m4_fn(t, rows, team_games), active_now = roster_status == "ACT")
  expect_true("active_now" %in% check_injury_leakage(targets, raw, tg, realised))
})

test_that("snapshot integrity: corrected reports, ID failures, postponed games, team changes, missing states", {
  tg <- sched4()
  rows <- tibble::tibble(
    season = 2023L, game_type = "REG", team = "KC", week = c(1L, 1L, 1L, 2L),
    gsis_id = c("a", "a", NA, "b"), position = "WR",
    # a: Questionable on Friday, "corrected" to Out after kickoff -> the correction must be ignored
    report_status = c("Questionable", "Out", "Questionable", "Questionable"), practice_status = NA,
    report_primary_injury = "Knee", practice_primary_injury = NA,
    date_modified = as.POSIXct(c("2023-09-08 19:00", "2023-09-10 20:00", "2023-09-08 19:00", "2023-09-18 12:00"),
                               tz = "UTC")
  )
  d <- pregame_injury_detail(inj_file(rows), tg)
  expect_equal(d$designation[d$gsis_id == "a"], "Questionable")
  expect_equal(injury_coverage_report(d)$no_player_id, 1)          # join failure counted, not dropped silently
  expect_false("b" %in% d$gsis_id)                                  # stamped after the week-2 kickoff (09-17)
  # the same week-2 game postponed to 09-19: kickoff comes from the schedule, so the report is now valid
  moved <- dplyr::mutate(tg, kickoff_utc = dplyr::if_else(week == 2L, as.POSIXct("2023-09-19 00:15", tz = "UTC"), kickoff_utc))
  expect_true("b" %in% pregame_injury_detail(inj_file(rows), moved)$gsis_id)
  # team change: a report filed with KC in week 2 is the trajectory of the player now on BUF in week 3
  tg2 <- dplyr::bind_rows(tg, dplyr::mutate(tg, team = "BUF")) |> dplyr::mutate(home = TRUE)
  det <- tibble::tibble(season = 2023L, week = 2L, team = "KC", gsis_id = "a", position = "WR",
                        designation = "Questionable", practice = "LP", body = "lower",
                        known_at = as.POSIXct("2023-09-15", tz = "UTC"))
  f <- add_availability_features(tibble::tibble(season = c(2023L, 2023L, 2022L), week = c(3L, 2L, 5L),
                                                gsis_id = c("a", "z", "a"), team = c("BUF", "KC", "KC")), det, tg2)
  expect_equal(f$prev_designation[1], "Questionable")
  expect_equal(f$report_state, c("no_team_report", "not_listed", "source_missing"))
})
