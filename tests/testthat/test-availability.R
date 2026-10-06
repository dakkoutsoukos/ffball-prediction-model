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
