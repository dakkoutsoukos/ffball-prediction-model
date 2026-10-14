# Injury stack, E19: P1 availability v2 and R2 (m6) candidates. Synthetic data only.

e19_reg <- function() read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))

test_that("kickoff days are classified in Eastern time", {
  k <- as.POSIXct(c("2021-09-10 00:20", "2021-09-12 17:00", "2021-09-14 00:15", "2021-12-25 21:30"), tz = "UTC")
  expect_equal(p1_kickoff_day(k), c("Thu", "Sun", "Mon", "other"))
})

p1_toy <- function() {
  tg <- tidyr::expand_grid(season = 2020L, week = 1:3, team = c("DAL", "PHI")) |>
    dplyr::mutate(kickoff_utc = as.POSIXct("2020-09-13 17:00", tz = "UTC") + (week - 1) * 7 * 86400,
                  game_id = paste0("g", week), opponent = ifelse(team == "DAL", "PHI", "DAL"))
  detail <- tibble::tibble(season = 2020L, week = c(2L, 2L, 3L), team = c("DAL", "DAL", "PHI"), gsis_id = c("a", "b", "c"),
                           position = c("RB", "QB", "WR"), designation = c("Questionable", "Out", "listed_only"),
                           practice = c("LP", "DNP", "FP"), body = "lower", known_at = as.POSIXct("2020-09-18", tz = "UTC"))
  snaps <- tibble::tibble(season = 2020L, week = c(1L, 2L, 1L, 2L, 3L), gsis_id = c("a", "a", "d", "d", "c"),
                          snap_team = c("DAL", "DAL", "DAL", "DAL", "PHI"), offense_snaps = c(30, 20, 40, 41, 25),
                          snap_share = 0.5)
  stats <- tibble::tibble(season = 2020L, week = 3L, gsis_id = "e")
  rosters <- tibble::tibble(season = 2020L, week = c(2L, 2L, 3L, 3L, 3L), gsis_id = c("d", "a", "d", "a", "e"),
                            roster_team = "DAL", roster_position = c("WR", "RB", "WR", "RB", "TE"), roster_status = "ACT")
  list(tg = tg, detail = detail, snaps = snaps, stats = stats, rosters = rosters)
}

test_that("the P1 frame holds the report population and the unlisted base-rate population", {
  x <- p1_toy()
  fr <- p1_frame(x$detail, x$snaps, x$stats, x$rosters, x$tg, 2020L)
  rep <- fr[fr$population == "report", ]
  expect_setequal(rep$gsis_id, c("a", "b", "c"))
  a <- rep[rep$gsis_id == "a", ]
  expect_true(a$active)                                         # 20 snaps in week 2
  expect_false(a$returning)                                     # played in week 1
  expect_false(rep$active[rep$gsis_id == "b"])                  # no snap record, no stat line
  # unlisted: d (snap in the previous game, on the roster, not listed) in weeks 2 and 3; a in week 3
  un <- fr[fr$population == "unlisted", ]
  expect_setequal(paste(un$gsis_id, un$week), c("d 2", "d 3", "a 3"))
  expect_false("e" %in% un$gsis_id)                             # no snap in the previous game
  expect_true(all(un$designation == "none"))
  expect_equal(as.character(a$kickoff_day), "Sun")
})

test_that("the rate table falls back from sparse cells", {
  tr <- tibble::tibble(designation = factor(rep(c("Questionable", "Out"), c(60, 40)), c(P1_DESIGNATIONS, "none")),
                       practice = factor(rep(c("LP", "DNP"), c(60, 40)), P1_PRACTICE),
                       position = factor(rep(c("RB", "WR"), each = 50), P1_POSITIONS),
                       active = c(rep(TRUE, 45), rep(FALSE, 15), rep(FALSE, 38), rep(TRUE, 2)))
  fit <- p1_fit_rate_table(tr, min_cell = 30)
  nd <- tibble::tibble(designation = factor(c("Questionable", "Questionable", "Out", "Doubtful"), levels(tr$designation)),
                       practice = factor(c("LP", "LP", "DNP", "LP"), P1_PRACTICE),
                       position = factor(c("RB", "TE", "WR", "RB"), P1_POSITIONS))
  p <- p1_predict_rate_table(fit, nd)
  expect_equal(p[1], 45 / 50)                                   # full cell (RB, Q, LP): 50 rows
  expect_equal(p[2], 45 / 60)                                   # no TE cell: designation x practice
  expect_equal(p[3], 2 / 40)                                    # WR Out DNP: 40 rows
  expect_equal(p[4], mean(tr$active))                           # unseen designation: overall rate
})

test_that("the GLMM fits, predicts with the random effect at 0, and orders designations", {
  set.seed(2)
  n <- 3000
  d <- tibble::tibble(designation = factor(sample(c("Out", "Doubtful", "Questionable", "listed_only"), n, TRUE,
                                                  c(0.2, 0.05, 0.35, 0.4)), c(P1_DESIGNATIONS, "none")),
                      practice = factor(sample(c("DNP", "LP", "FP"), n, TRUE), P1_PRACTICE),
                      position = factor(sample(P1_POSITIONS, n, TRUE), P1_POSITIONS),
                      returning = stats::runif(n) < 0.2, streak = sample(0:4, n, TRUE),
                      prev_designation = factor(sample(c("none", "Questionable"), n, TRUE), c("none", P1_DESIGNATIONS)),
                      kickoff_day = factor(sample(c("Sun", "Thu", "Mon"), n, TRUE), c("Sun", "Thu", "Mon", "other")),
                      team_season = paste0("T", sample(1:20, n, TRUE)))
  lp <- c(Out = -4, Doubtful = -2, Questionable = 1.2, listed_only = 3)[as.character(d$designation)] -
    0.8 * (d$practice == "DNP")
  d$active <- stats::runif(n) < stats::plogis(lp)
  g <- p1_fit_glmm(d)
  nd <- d[1:4, ]
  nd$designation <- factor(c("Out", "Doubtful", "Questionable", "listed_only"), levels(d$designation))
  nd$practice <- factor("LP", P1_PRACTICE)
  nd$team_season <- "unseen"
  p <- p1_predict_glmm(g, nd)
  expect_false(anyNA(p))
  expect_true(all(diff(p) > 0))
  expect_true(abs(calibration_slope(p1_predict_glmm(g, d), d$active) - 1) < 0.2)
})

test_that("the frozen provider reproduces the GLMM's predictions with the random effect at 0", {
  set.seed(7)
  n <- 2500
  d <- tibble::tibble(designation = factor(sample(c("Out", "Doubtful", "Questionable", "listed_only"), n, TRUE,
                                                  c(0.2, 0.05, 0.35, 0.4)), c(P1_DESIGNATIONS, "none")),
                      practice = factor(sample(c("DNP", "LP", "FP"), n, TRUE), P1_PRACTICE),
                      position = factor(sample(P1_POSITIONS, n, TRUE), P1_POSITIONS),
                      returning = stats::runif(n) < 0.2, streak = sample(0:4, n, TRUE),
                      prev_designation = factor(sample(c("none", "Questionable"), n, TRUE), c("none", P1_DESIGNATIONS)),
                      kickoff_day = factor(sample(c("Sun", "Thu", "Mon"), n, TRUE), c("Sun", "Thu", "Mon", "other")),
                      team_season = paste0("T", sample(1:15, n, TRUE)))
  d$active <- stats::runif(n) < stats::plogis(c(Out = -3, Doubtful = -1.5, Questionable = 1, listed_only = 2.5)[as.character(d$designation)])
  g <- suppressWarnings(p1_fit_glmm(d))
  prov <- yaml::yaml.load(yaml::as.yaml(p1_provider_list(g, list(passed = TRUE))))
  expect_equal(p1_provider_predict(prov, d[1:200, ]), as.numeric(p1_predict_glmm(g, d[1:200, ])), tolerance = 1e-6)
})

test_that("the week bootstrap resamples whole weeks within each season", {
  sc <- tibble::tibble(season = rep(c(2020L, 2021L), each = 6), week = rep(rep(1:3, each = 2), 2),
                       x = c(1, 1, 2, 2, 3, 3, 10, 10, 20, 20, 30, 30))
  b <- p1_boot(sc, function(d) c(n2020 = sum(d$season == 2020), w = sum(table(paste(d$season, d$week)) %% 2)), reps = 50L)
  expect_true(all(b["n2020", ] == 6))                           # each season keeps its number of weeks
  expect_true(all(b["w", ] == 0))                               # weeks are drawn whole (2 rows each)
  m <- p1_boot(sc, function(d) mean(d$x[d$season == 2020]), reps = 200L, seed = 3L)
  expect_true(all(m %in% c(1, 2, 3, 4 / 3, 5 / 3, 7 / 3, 8 / 3, 2, 1, 3)) || all(m >= 1 & m <= 3))
})

test_that("P1 development evaluation refuses the check season", {
  expect_error(p1_dev_evaluation(tibble::tibble(population = "report"), dev = 2019:2020, register = e19_reg()), "may not use")
})

m6_toy <- function(seed = 1) {
  set.seed(seed)
  n <- 6000
  tibble::tibble(season = sample(2020:2023, n, TRUE), week = sample(1:17, n, TRUE), gsis_id = paste0("p", seq_len(n)),
                 position = sample(M6_POSITIONS, n, TRUE, c(0.5, 0.3, 0.2)),
                 group = sample(c("not_listed", "Q_LP", "Q_DNP", "Q_FP", "D", "listed_FP"), n, TRUE,
                                c(0.8, 0.08, 0.02, 0.05, 0.01, 0.04)),
                 base = stats::runif(n, 3, 20)) |>
    dplyr::mutate(designation = dplyr::case_when(grepl("^Q", .data$group) ~ "Questionable", .data$group == "D" ~ "Doubtful",
                                                 .data$group == "listed_FP" ~ "listed_only", TRUE ~ "none"),
                  practice = dplyr::case_when(grepl("DNP", .data$group) ~ "DNP", grepl("LP", .data$group) ~ "LP",
                                              grepl("FP", .data$group) ~ "FP", TRUE ~ "none"),
                  weeks_listed_streak = ifelse(.data$designation == "none", 0L, 1L), prev_offense_snaps = 30,
                  active = stats::runif(dplyr::n()) < ifelse(.data$designation == "Questionable", 0.9, 0.99),
                  actual = ifelse(.data$active, .data$base * ifelse(.data$designation == "Questionable", 0.8, 1) +
                                    stats::rnorm(dplyr::n(), 0, 4), 0))
}

test_that("m6 parameters follow the M4 recipe per position, from development rows only", {
  fr <- m6_toy()
  pr <- m6_derive_params(fr, register = e19_reg())
  d <- fr[fr$position == "RB", ]
  qd <- d$designation %in% c("Questionable", "Doubtful")
  expect_equal(pr$RB$b1_multiplier_adj, round((sum(d$actual[qd]) / sum(d$base[qd]) - 1) / 2, 2))
  expect_true("Q_DNP" %in% pr$QB$pooled_into_Q_pool)           # few QB Q_DNP rows: pooled
  expect_true(all(unlist(pr$RB$k2_ratio_if_active) > 0.5))
  expect_error(m6_derive_params(dplyr::mutate(fr, season = 2019L), seasons = 2019L, register = e19_reg()), "may not use")
  # multipliers: 1 outside the adjustable groups
  m <- m6_multiplier(fr, pr, "K1")
  expect_true(all(m[fr$group == "not_listed"] == 1))
  expect_equal(m6_multiplier(fr, pr, "B0"), rep(1, nrow(fr)))
})

test_that("the development selection applies qualification, the tie band and simplicity", {
  fr <- m6_toy(seed = 3)
  pr <- m6_derive_params(fr, register = e19_reg())
  sel <- m6_dev_selection(fr, pr, reps = 200L)
  expect_equal(sel$results$candidate, M6_CANDIDATES)
  expect_true(all(sel$results$d_mse < 0))                       # the planted -20% effect is found
  q <- sel$results[sel$results$hi < 0, ]
  expect_true(sel$selected %in% q$candidate)
  # nothing qualifies when the adjustments are useless
  flat <- dplyr::mutate(fr, actual = ifelse(.data$active, .data$base + stats::rnorm(dplyr::n(), 0, 4), .data$base))
  pf <- m6_derive_params(flat, register = e19_reg())
  expect_true(is.na(m6_dev_selection(flat, pf, reps = 200L)$selected) ||
                all(m6_dev_selection(flat, pf, reps = 200L)$results$d_mse > -0.01))
  mde <- m6_mde(fr, pr, "B1")
  expect_equal(mde$mde, (stats::qnorm(0.975) + stats::qnorm(0.8)) * mde$sd_week / sqrt(13))
})
