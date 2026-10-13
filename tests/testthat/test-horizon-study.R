# R3 forecast-horizon study (master plan R3; E17, E17a). Synthetic data only.

test_that("final projections are parsed from ESPN source 1 only: actual points are never read", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "season=2024"))
  json <- paste(readLines(file.path(project_root, "tests", "testthat", "fixtures", "espn_kona_synthetic.json")), collapse = "")
  write_gz_text(file.path(root, "season=2024", "espn_wr_2024_w05.json.gz"), json)
  f <- hz_finals(2024, 5, qbrbte_root = file.path(root, "none"), wr_root = root)
  expect_equal(f$f[f$espn_id == "9000001"], 14.5)              # the projection, not the actual 21.3
  expect_false("9000003" %in% f$espn_id)                       # a player with only an actual row is absent
  expect_false(any(c("espn_actual", "applied_total") %in% names(f)))
})

test_that("lead bins: hours for the current week, weeks ahead otherwise", {
  expect_equal(hz_lead_bin(c(10, 50, 100, 200, 10, 10, 10, 10, 10), c(0, 0, 0, 0, 1, 2, 4, 6, 12)),
               c("<24h", "24-72h", "72-120h", ">120h", "1wk", "2wk", "3-4wk", "5-8wk", "9+wk"))
})

hz_synth <- function(weeks = 1:5, players = 60, drift = 0.5, sd = 2, seed = 1) {
  set.seed(seed)
  tidyr::expand_grid(week = weeks, espn_id = paste0("p", seq_len(players))) |>
    dplyr::mutate(position = "WR", lead_bin = "72-120h", v = stats::runif(dplyr::n(), 4, 15),
                  f = .data$v + drift + stats::rnorm(dplyr::n(), 0, sd), active = TRUE, r = .data$f - .data$v,
                  band = pd_band(.data$v),
                  captured_at = as.POSIXct("2026-10-13", tz = "UTC"))
}

test_that("revision drift and variance are recovered, and adoption waits for 4 target weeks", {
  fr <- hz_synth()
  sm <- hz_summary(fr, reps = 300)
  p <- sm$pooled
  expect_equal(p$n_weeks, 5L)
  expect_equal(p$drift, 0.5, tolerance = 0.15)
  expect_equal(p$var, 4, tolerance = 0.5)
  expect_true(p$var_lo > 0)
  ad <- hz_adoption(sm)
  expect_true(ad$ready)
  expect_equal(ad$spread_var, p$var)
  expect_equal(ad$drift, p$drift)                              # CI excludes 0 for a 0.5 drift
  ad3 <- hz_adoption(hz_summary(hz_synth(weeks = 1:3), reps = 300))
  expect_false(ad3$ready)
  expect_equal(ad3$spread_var, 0)                              # E17a: fewer than 4 target weeks
  ad0 <- hz_adoption(hz_summary(hz_synth(drift = 0), reps = 300))
  expect_equal(ad0$drift, 0)                                   # no drift adopted when its CI covers 0
})

test_that("the martingale check finds no correlation for independent revisions and catches momentum", {
  set.seed(2)
  mk <- function(rho) {
    tidyr::expand_grid(espn_id = paste0("p", 1:400), week = 1L) |>
      dplyr::mutate(r1 = stats::rnorm(dplyr::n()), r2 = rho * .data$r1 + stats::rnorm(dplyr::n())) |>
      dplyr::mutate(v1 = 10, v2 = 10 + .data$r1, f = .data$v2 + .data$r2) |>
      (\(d) dplyr::bind_rows(
        dplyr::transmute(d, .data$espn_id, .data$week, v = .data$v1, f = .data$f, captured_at = as.POSIXct("2026-10-13", tz = "UTC")),
        dplyr::transmute(d, .data$espn_id, .data$week, v = .data$v2, f = .data$f, captured_at = as.POSIXct("2026-10-15", tz = "UTC"))))() |>
      dplyr::mutate(active = TRUE)
  }
  m0 <- hz_martingale(mk(0), reps = 300)
  expect_equal(m0$pairs, 400L)
  expect_true(m0$cor_lo < 0 && m0$cor_hi > 0)
  m1 <- hz_martingale(mk(0.8), reps = 300)
  expect_gt(m1$cor_lo, 0.3)
})

test_that("transitions report the share of projected players whose final projection is zero", {
  fr <- tibble::tibble(v = c(5, 5, 5, 5), f = c(0, 6, 7, 0), status3 = c("QUESTIONABLE", "QUESTIONABLE", "ACTIVE", "ACTIVE"),
                       lead_bin = "72-120h")
  tr <- hz_transitions(fr)
  expect_equal(tr$share_final_zero[tr$status3 == "QUESTIONABLE"], 0.5)
})
