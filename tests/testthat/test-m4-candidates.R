toy_m4_frame <- function(n_per = 120, seasons = 2019:2024) {
  set.seed(4)
  groups <- c("Q_LP", "Q_FP", "Q_DNP", "listed_DNP_LP", "not_listed", "listed_FP")
  tidyr::expand_grid(season = seasons, group = groups, i = seq_len(n_per)) |>
    dplyr::mutate(
      week = (.data$i %% 17) + 1L, gsis_id = paste(.data$group, .data$i, sep = "_"),
      designation = dplyr::case_when(startsWith(.data$group, "Q_") ~ "Questionable",
                                     startsWith(.data$group, "listed") ~ "listed_only", TRUE ~ "none"),
      practice = dplyr::case_when(grepl("DNP", .data$group) ~ "DNP", grepl("LP", .data$group) ~ "LP",
                                  grepl("FP", .data$group) ~ "FP", TRUE ~ "none"),
      base = stats::runif(dplyr::n(), 2, 15), cal_targets = .data$base / 1.6,
      our_targets = .data$cal_targets + stats::rnorm(dplyr::n()),
      actual = pmax(0, .data$base * ifelse(.data$designation == "Questionable", 0.8, 1) + stats::rnorm(dplyr::n(), 0, 3)),
      actual_targets = pmax(0, .data$cal_targets + stats::rnorm(dplyr::n())),
      roster_status = ifelse(stats::runif(dplyr::n()) < 0.05, "INA", "ACT"),
      has_stat_line = .data$roster_status == "ACT",
      team_games_missed = 0L, weeks_listed_streak = as.integer(.data$i %% 3),
      pts_per_target_espn = 1.6, relevant = TRUE, startable = TRUE, espn_rank = .data$i,
      pred_b1 = .data$base * ifelse(.data$designation == "Questionable", 0.91, 1)
    ) |>
    dplyr::select(-"i")
}

test_that("small development groups are pooled with Questionable", {
  expect_equal(m4_param_group(c("Q_DNP", "Q_LP", "D", "not_listed", "listed_FP"), c("Q_DNP", "D")),
               c("Q_pool", "Q_LP", "Q_pool", NA, NA))
})

test_that("candidate parameters depend only on development seasons", {
  fr <- toy_m4_frame()
  p <- m4_derive_params(fr)
  bad <- dplyr::mutate(fr, actual = ifelse(season %in% c(2019, 2024), actual * 3 + 7, actual),
                       actual_targets = ifelse(season %in% c(2019, 2024), 0, actual_targets),
                       roster_status = ifelse(season %in% c(2019, 2024), "INA", roster_status))
  expect_identical(m4_derive_params(bad), p)
  expect_true(p$k1_multiplier_adj$Q_LP < 0)
  expect_true("Q_other" %in% p$pooled_into_Q_pool)       # n = 0 < 100
})

test_that("candidates adjust only their groups; B1 reproduces the frozen rule", {
  fr <- toy_m4_frame()
  p <- m4_derive_params(fr)
  pr <- m4_candidate_preds(fr, p)
  wide <- tidyr::pivot_wider(dplyr::select(pr, season, week, gsis_id, group, model, pred),
                             names_from = "model", values_from = "pred")
  healthy <- wide$group %in% c("not_listed", "listed_FP")
  expect_equal(wide$K1[healthy], wide$B0[healthy])
  expect_equal(wide$K2[healthy], wide$B0[healthy])
  expect_equal(wide$K3[healthy], wide$B0[healthy])
  q_lp <- wide$group == "Q_LP"
  expect_equal(wide$K1[q_lp], wide$B0[q_lp] * (1 + p$k1_multiplier_adj$Q_LP))
  expect_equal(wide$B1[q_lp], wide$B0[q_lp] * 0.91)
  expect_true(all(pr$adjusted == pr$group %in% M4_ADJ_GROUPS))
})

test_that("freeze decision needs development AND 2019; fewest parameters unless beaten on both", {
  ev <- function(diffs_b0, diffs_b1, ci_high = -0.001) {
    mk <- function(base, d) tibble::tibble(subset = "all", baseline = base, model = names(d), mae_diff = unname(d),
                                           ci_high = ci_high, rmse_model = 6, rmse_baseline = 6.01)
    list(comparisons = dplyr::bind_rows(mk("B0", diffs_b0), mk("B1", diffs_b1)))
  }
  vs_b1_dev <- c(K1 = -0.001, K2 = -0.01, K3 = 0.002, K4 = -0.001)
  vs_b1_19 <- c(K1 = -0.001, K2 = -0.002, K3 = -0.001, K4 = 0.003)
  dev <- ev(c(K1 = -0.02, K2 = -0.03, K3 = -0.01, K4 = -0.02), vs_b1_dev)
  # K2 better than K1 in development only -> the simpler K1 wins
  dec <- m4_freeze_decision(dev, ev(c(K1 = -0.02, K2 = -0.015, K3 = -0.01, K4 = -0.02), vs_b1_19))
  expect_equal(dec$table$freeze, c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(dec$winner, "K1")
  # K2 better than K1 in development AND 2019 -> K2 wins
  expect_equal(m4_freeze_decision(dev, ev(c(K1 = -0.02, K2 = -0.03, K3 = -0.01, K4 = -0.02), vs_b1_19))$winner, "K2")
  expect_true(is.na(m4_freeze_decision(dev, ev(c(K1 = -0.02, K2 = -0.03, K3 = -0.01, K4 = -0.02),
                                               c(K1 = 0.01, K2 = 0.01, K3 = 0.01, K4 = 0.01)))$winner))
})

test_that("frozen registry spec = calibrated base x the candidate multiplier", {
  fr <- toy_m4_frame()
  p <- m4_derive_params(fr)
  rules <- m4_rules(p)
  fr <- dplyr::mutate(fr, espn_proj = base, espn_proj_receptions = base / 3, espn_proj_targets = cal_targets,
                      espn_proj_receiving_yards = base * 6, espn_proj_receiving_tds = 0.3, espn_proj_rushing_yards = 0)
  spec <- registry_spec_availability_adjusted(list(calibration = "components_recency", availability_rule = rules$K2), "x")
  base <- spec_cal("components_recency")
  train <- dplyr::filter(fr, season < 2024)
  test <- dplyr::filter(fr, season == 2024)
  expect_equal(spec$predict(spec$fit(train), test),
               base$predict(base$fit(train), test) * m4_rule_multiplier(test, rules$K2))
  healthy <- test$group %in% c("not_listed", "listed_FP")
  expect_true(all(m4_rule_multiplier(test, rules$K1)[healthy] == 1))
})
