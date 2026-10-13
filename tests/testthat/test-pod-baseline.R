# P0 baseline distributions (master plan P0, E18). Synthetic data only.

lh_prior_p0 <- function() read_availability_prior(file.path(project_root, "config", "availability_prior.yml"))

pd_reg <- function() read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))

pd_synth <- function(seed = 1, seasons = 2019:2021, weeks = 1:17, n = 40, positions = c("QB", "RB", "WR", "TE")) {
  set.seed(seed)
  tidyr::expand_grid(season = seasons, week = weeks, position = positions, k = seq_len(n)) |>
    dplyr::mutate(gsis_id = paste(.data$position, .data$k, sep = "_"),
                  espn_proj = stats::runif(dplyr::n(), 1, 25),
                  y = 1 + 0.9 * .data$espn_proj + stats::rnorm(dplyr::n(), 0, 4),
                  active = TRUE, offense_snaps = 30, stat_line = TRUE)
}

test_that("the frame flags activity by offensive snaps and refuses seasons outside development", {
  cur <- tibble::tibble(season = 2020L, week = 1L, gsis_id = c("a", "b", "c", "d"), espn_id = "1", espn_name = "x",
                        position = "WR", espn_proj = c(10, 8, 6, 0), team = "T", roster_status = "ACT",
                        pts = c(12, 0, 3, 5), active = c(TRUE, FALSE, TRUE, TRUE), rank = 1, relevant = TRUE)
  sn <- tibble::tibble(season = 2020L, week = 1L, gsis_id = c("a", "b"), snap_team = "T", offense_snaps = c(40, 0), snap_share = 0.5)
  f <- pd_frame(cur, sn, seasons = 2020, register = pd_reg())
  expect_equal(f$gsis_id, c("a", "b", "c"))                    # projection 0 is not in the population
  expect_equal(f$active, c(TRUE, FALSE, TRUE))                  # b: snap record with 0 offensive snaps; c: no record, stat line
  expect_error(pd_frame(cur, sn, seasons = 2024, register = pd_reg()), "may not use")
  expect_error(pd_frame(cur, sn, seasons = 2026, register = pd_reg()), "may not use|sealed")
})

test_that("the rolling base uses only earlier weeks and recovers a linear calibration", {
  d <- pd_synth()
  b <- pd_rolling_base(d)
  last <- b[b$season == 2021 & b$week == 17 & b$position == "WR", ]
  expect_equal(unique(round(last$b, 1)), 0.9)
  expect_equal(unique(round(last$a, 0)), 1)
  # a planted outlier in a week does not move that week's base
  d2 <- d
  hit <- d2$season == 2020 & d2$week == 5 & d2$position == "RB"
  d2$y[hit] <- d2$y[hit] + 500
  b2 <- pd_rolling_base(d2)
  same <- b$season == 2020 & b$week == 5 & b$position == "RB"
  expect_equal(b2$base[same], b$base[same])
  later <- b$season == 2020 & b$week == 6 & b$position == "RB"
  expect_false(isTRUE(all.equal(b2$base[later], b$base[later])))
  # warm-up: identity base before 200 training rows
  first <- b[b$season == 2019 & b$week == 1, ]
  expect_equal(first$base, first$espn_proj)
})

test_that("the residual table merges small bands and reproduces empirical quantiles", {
  d <- pd_rolling_base(pd_synth())
  tab <- pd_residual_table(d)
  expect_true(all(tab$n >= POD_MIN_CELL))
  qb <- tab[tab$position == "QB", ]
  expect_equal(sum(qb$n), sum(d$active & d$position == "QB"))
  i <- 1
  rows <- d[d$position == "QB" & pd_band(d$base) >= qb$band_lo[i] & pd_band(d$base) <= qb$band_hi[i], ]
  expect_equal(qb$q[[i]], unname(stats::quantile(rows$resid, POD_TAU, type = 7)))
  expect_true(all(vapply(tab$q, function(q) !is.unsorted(q), TRUE)))
})

test_that("predictive quantiles are monotone and respect the floor", {
  d <- pd_rolling_base(pd_synth())
  tab <- pd_residual_table(d)
  q <- pd_quantiles(c("WR", "QB"), c(0.5, 22), tab)
  expect_equal(dim(q), c(2L, length(POD_TAU)))
  expect_true(all(apply(q, 1, function(r) !is.unsorted(r))))
  expect_true(all(q[1, ] >= tab$floor[tab$position == "WR"][1]))
})

test_that("PODs carry p_active, their mean scales with it, and validation catches bad tables", {
  d <- pd_rolling_base(pd_synth())
  tab <- pd_residual_table(d)
  pl <- tibble::tibble(player_id = c("p1", "p2"), position = c("RB", "RB"), base = c(12, 12), p_active = c(1, 0.71))
  pods <- pd_pods(pl, tab)
  expect_equal(pods$mean[2], 0.71 * pods$mean[1])
  expect_true(validate_pod_table(pods))
  bad <- pods
  bad$q50 <- bad$q99 + 1
  expect_error(validate_pod_table(bad), "decreasing")
})

test_that("the development evaluation is out of sample by season and reports the coverage gate", {
  d <- pd_rolling_base(pd_synth(seasons = 2019:2021, n = 30))
  ev <- pd_dev_evaluation(d, seasons = 2020:2021, reps = 200)
  expect_equal(sort(unique(ev$gate$position)), sort(POD_POSITIONS))
  expect_equal(nrow(ev$gate), 12L)
  expect_true(all(ev$gate$coverage > 0.3 & ev$gate$coverage < 1))
  # synthetic normal noise is well described by empirical quantiles: no cell should fail
  expect_true(ev$gate_passed)
  expect_true(all(ev$by_position$crps > 0))
})

test_that("the committed frozen table loads and gives sane quantiles for every position", {
  tab <- read_pod_table(file.path(project_root, "models", "probabilistic", "pod_baseline_v0.yml"))
  expect_setequal(unique(tab$position), POD_POSITIONS)
  expect_true(all(tab$n >= POD_MIN_CELL))
  q <- pd_quantiles(c("QB", "RB", "WR", "TE"), c(18, 12, 12, 8), tab)
  expect_false(anyNA(q))
  expect_true(all(apply(q, 1, function(r) !is.unsorted(r))))
  med <- q[, match(0.5, POD_TAU)]
  expect_true(all(abs(med - c(18, 12, 12, 8)) < 3))   # medians near the base (right skew: slightly below)
})

test_that("the prospective archive writes current-week PODs once, with a hash-only manifest", {
  root <- withr::local_tempdir()
  vroot <- file.path(root, "valuation")
  run_dir <- file.path(vroot, "season=2026", "week=06", "run=20261013T070000Z")
  dir.create(run_dir, recursive = TRUE)
  weekly <- tibble::tibble(player_id = c("00-1", "00-2", "00-3", "00-4"), espn_id = c("1", "2", "3", "4"),
                           position = c("WR", "RB", "TE", "WR"), team = "T", week = c(6L, 6L, 6L, 7L),
                           proj = c(12, 9, 0, 10), has_game = c(TRUE, TRUE, TRUE, TRUE),
                           availability_status = c("ACTIVE", "QUESTIONABLE", "ACTIVE", "ACTIVE"))
  arrow::write_parquet(weekly, file.path(run_dir, "weekly.parquet"))
  vman <- file.path(root, "valuation_manifest.csv")
  readr::write_csv(tibble::tibble(run_id = "20261013T070000Z", season = 2026, week = 6), vman)
  man <- file.path(root, "distribution_manifest.csv")
  table_file <- file.path(project_root, "models", "probabilistic", "pod_baseline_v0.yml")
  res <- pd_archive_run(2026, 6, table_file = table_file, root = file.path(root, "dist"), manifest = man,
                        val_manifest = vman, val_root = vroot, prior = lh_prior_p0())
  pods <- arrow::read_parquet(res$path)
  expect_equal(pods$player_id, c("00-1", "00-2"))           # current week, projected > 0
  expect_equal(pods$p_active, c(1, 0.71))                    # designation prior
  m <- readr::read_csv(man, col_types = readr::cols(.default = "c"))
  expect_equal(m$pod_version, "pod_baseline_v0")
  expect_equal(m$pods_sha256, sha256_file(res$path))
  expect_error(pd_archive_run(2026, 6, table_file = table_file, root = file.path(root, "dist"), manifest = man,
                              val_manifest = vman, val_root = vroot))   # write-once
})

test_that("the frozen-table list round-trips through YAML into a usable residual table", {
  d <- pd_rolling_base(pd_synth(seasons = 2019:2023, n = 20))
  fz <- pd_freeze_table(d)
  y <- yaml::yaml.load(yaml::as.yaml(fz))
  tab <- pd_table_from_yaml(y)
  expect_equal(nrow(tab), length(fz$cells))
  q <- pd_quantiles("TE", 9, tab)
  expect_false(anyNA(q))
  expect_equal(y$tau, POD_TAU)
})
