# P2 calibrated distributions v1 (E20). Synthetic data only.

p2_toy <- function(seed = 1, seasons = 2019:2021, n = 60, weeks = 1:12) {
  set.seed(seed)
  tidyr::expand_grid(season = seasons, week = weeks, position = P2_POSITIONS, k = seq_len(n)) |>
    dplyr::mutate(gsis_id = paste(.data$position, .data$k, sep = "_"),
                  base = stats::runif(dplyr::n(), 2, 25),
                  y = .data$base + (1 + 0.25 * .data$base) * stats::rnorm(dplyr::n()),
                  espn_proj = .data$base, active = TRUE,
                  status = factor(sample(c("none", "listed", "QD"), dplyr::n(), TRUE, c(0.85, 0.1, 0.05)),
                                  c("none", "listed", "QD")),
                  td_share = stats::runif(dplyr::n(), 0, 0.5), implied_total = stats::rnorm(dplyr::n(), 22, 3),
                  spread = stats::rnorm(dplyr::n(), 0, 5)) |>
    dplyr::select(-"k") |>
    p2_volatility() |>
    dplyr::mutate(resid = .data$y - .data$base)
}

p2_reg <- function() read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))

test_that("player volatility uses only earlier weeks and shrinks toward the position", {
  fr <- tibble::tibble(season = 2020L, week = 1:4, gsis_id = "a", position = "WR", base = 10, y = c(10, 14, 6, 30))
  fr <- dplyr::bind_rows(fr, tibble::tibble(season = 2020L, week = 1:4, gsis_id = "b", position = "WR", base = 10,
                                            y = c(10, 10, 11, 9)))
  v <- p2_volatility(fr)
  a <- v[v$gsis_id == "a", ]
  r_all <- c(0, 0, 4, 0)                                        # weeks 1-2 residuals of a and b
  expect_true(is.na(a$vol_shrunk[1]))                           # week 1: nothing earlier at all
  pos_sd3 <- stats::sd(c(0, 0, 4, 0))                           # position SD before week 3
  expect_equal(a$vol_shrunk[a$week == 3], sqrt((2 * stats::var(c(0, 4)) + 8 * pos_sd3^2) / (2 + 8)))
  # changing a later outcome does not change earlier volatility
  fr2 <- fr
  fr2$y[fr2$gsis_id == "a" & fr2$week == 4] <- 999
  v2 <- p2_volatility(fr2)
  expect_equal(v2$vol_shrunk[v2$week <= 4], v$vol_shrunk[v$week <= 4])
})

test_that("C0 on the 99-level grid matches P0's quantile function and handles any levels", {
  fr <- p2_toy()
  fit <- p2_fit_c0(fr[fr$season < 2021, ])
  rows <- fr[fr$season == 2021, ][1:50, ]
  q <- p2_quantiles_c0(fit, rows)
  expect_equal(q, pd_quantiles(rows$position, rows$base, fit$table, P2_TAU))
  q2 <- p2_quantiles_c0(fit, rows, c(0.05, 0.5, 0.95))
  expect_equal(dim(q2), c(50L, 3L))
  expect_true(all(q2[, 1] <= q2[, 2] & q2[, 2] <= q2[, 3]))
})

test_that("C1 (IDR) quantiles increase in tau and in base, and are roughly calibrated", {
  fr <- p2_toy(seed = 2)
  fit <- p2_fit_c1(fr[fr$season < 2021, ])
  rows <- fr[fr$season == 2021, ]
  q <- p2_quantiles_c1(fit, rows)
  expect_true(all(apply(q, 1, function(x) !is.unsorted(x))))
  grid <- tibble::tibble(position = "WR", base = c(5, 10, 15, 20))
  qg <- p2_quantiles_c1(fit, grid, c(0.1, 0.5, 0.9))
  expect_true(all(diff(qg[, 2]) > 0))
  cov80 <- mean(rows$y >= q[, 10] & rows$y <= q[, 90])
  expect_true(abs(cov80 - 0.8) < 0.05)
})

test_that("the shash quantile formula matches mgcv's, and C2 is roughly calibrated", {
  fr <- p2_toy(seed = 3)
  fit <- suppressWarnings(p2_fit_c2(fr[fr$season < 2021, ]))   # mgcv may note a step failure at a ~0 gradient
  rows <- fr[fr$season == 2021 & fr$position == "RB", ]
  lp <- stats::predict(fit$RB$fit, newdata = rows[1:5, ], type = "link")
  mine <- p2_shash_q(lp, c(0.1, 0.5, 0.9))
  ref <- sapply(c(0.1, 0.5, 0.9), function(p) fit$RB$fit$family$qf(rep(p, 5), lp))
  expect_equal(unname(mine), unname(ref), tolerance = 1e-10)
  q <- p2_quantiles_c2(fit, rows)
  cov80 <- mean(rows$y >= q[, 10] & rows$y <= q[, 90])
  expect_true(abs(cov80 - 0.8) < 0.06)
})

test_that("C3 pulls a miscalibrated base model's coverage toward nominal", {
  fr <- p2_toy(seed = 4, seasons = 2020L, n = 80, weeks = 1:17)
  narrow <- function(r, lev) outer(r$base, stats::qnorm(lev) * 2, `+`)      # true spread is larger
  q0 <- narrow(fr, P2_TAU)
  q3 <- p2_quantiles_c3(narrow, fr)
  late <- fr$week > 8
  cov <- function(q) mean(fr$y[late] >= q[late, 10] & fr$y[late] <= q[late, 90])
  expect_lt(abs(cov(q3) - 0.8), abs(cov(q0) - 0.8))
  expect_true(all(apply(q3, 1, function(x) !is.unsorted(x))))
})

test_that("scores, the coverage gate and the selection rule behave as pre-registered", {
  fr <- p2_toy(seed = 5)
  rows <- fr[fr$season == 2021, ]
  q <- p2_quantiles_c0(p2_fit_c0(fr[fr$season < 2021, ]), rows)
  sc <- p2_score_rows(rows, q)
  expect_equal(nrow(sc), nrow(rows))
  expect_true(all(sc$crps >= 0))
  expect_true(all(sc$pit >= 0 & sc$pit <= 1))
  g <- p2_coverage_gate(sc, reps = 200L)
  expect_equal(nrow(g), 12)
  s <- tibble::tibble(candidate = P2_CANDIDATES, crps = c(5.00, 4.99, 4.90, 4.80), gate_passed = c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(p2_select(s), "C2")                              # C3 fails the gate; C2 beats C0 by > 0.5%
  s$crps[3] <- 4.98
  expect_equal(p2_select(s), "C0")                              # within 0.5% of the best: the simplest wins
  s$gate_passed <- FALSE
  expect_true(is.na(p2_select(s)))
})

test_that("development runs refuse 2024 rows and check the register", {
  fr <- p2_toy(seasons = 2023:2024)
  expect_error(p2_dev_run(fr, "C0", register = p2_reg()), "may not contain")
})

test_that("E22's decision applies Holm over the primaries present", {
  p2 <- list(selected = "C2", p_vs_c0 = 0.004, ci_vs_c0 = c(-0.05, -0.01), not_worse_than_c1 = TRUE, gate_passed = TRUE)
  p4 <- list(p = 0.03, ci = c(-0.4, -0.02), gate_passed = TRUE)
  d <- e22_decide(p2, p4)
  expect_equal(unname(d$p_holm), c(0.008, 0.03))
  expect_true(d$success_p2 && d$success_p4)
  p4$p <- 0.04
  p2$p_vs_c0 <- 0.03
  d2 <- e22_decide(p2, p4)
  expect_equal(unname(d2$p_holm), c(0.06, 0.06))
  expect_false(d2$success_p2 || d2$success_p4)
  p2$selected <- "C0"                                            # development kept P0: P2 has no primary
  d3 <- e22_decide(p2, p4)
  expect_equal(names(d3$p_holm), "P4")
  expect_false(d3$success_p2)
  expect_true(d3$success_p4)
  b <- e22_player_boot(c(1, 1, 3, 3), c("a", "a", "b", "b"), reps = 200L)
  expect_true(all(b %in% c(1, 2, 3)))                            # players resampled whole
})
