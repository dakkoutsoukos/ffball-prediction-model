# Power and minimum detectable effects for the 2026 prospective tests (master plan F1, E16) ----
# Base R plus the project's existing data tools. Reads HISTORICAL comparison frames only
# (2019-2025); no 2026 outcome is used anywhere in this file.
#
# The pre-registered tests (E3, E6, E9, E14) bootstrap weeks: the statistic is
# sum over weeks of s_w / sum of n_w, where s_w is the week's summed loss difference and n_w its
# number of paired player-weeks (pooled_bootstrap()). Linearised, its standard error is
# sigma_w / sqrt(W) with sigma_w^2 = Var_w[(s_w - delta * n_w) / n_bar], computed here WITHIN
# season (a prospective test covers one season, so between-season shifts in the mean effect do
# not belong in its noise).

#' Week-level paired loss differences between two models, paired exactly as pooled_bootstrap()
#' pairs them: player-weeks both models predicted, d = loss(model) - loss(baseline).
#' `loss`: "abs" (MAE family) or "sq" (MSE family).
week_level_diffs <- function(preds, model, baseline, loss = c("abs", "sq")) {
  loss <- match.arg(loss)
  f <- if (loss == "abs") abs else function(x) x^2
  wide <- preds |>
    dplyr::filter(.data$model %in% c(!!model, !!baseline)) |>
    dplyr::select("season", "week", "gsis_id", "actual", "model", "pred") |>
    tidyr::pivot_wider(names_from = "model", values_from = "pred") |>
    dplyr::filter(!is.na(.data[[model]]), !is.na(.data[[baseline]])) |>
    dplyr::mutate(d = f(.data[[model]] - .data$actual) - f(.data[[baseline]] - .data$actual))
  dplyr::summarise(wide, s = sum(.data$d), n = dplyr::n(), mean_d = mean(.data$d), .by = c("season", "week")) |>
    dplyr::arrange(.data$season, .data$week)
}

#' Effect and week-level noise of a comparison: the pooled effect (sum s / sum n), its per-season
#' values, and sigma_w (linearised, within-season), plus the simple SD of week means for reference.
week_noise <- function(wk) {
  by_season <- wk |>
    dplyr::summarise(delta = sum(.data$s) / sum(.data$n), n_bar = mean(.data$n), weeks = dplyr::n(), .by = "season")
  u <- wk |>
    dplyr::left_join(by_season, by = "season") |>
    dplyr::mutate(u = (.data$s - .data$delta * .data$n) / .data$n_bar,
                  m = .data$mean_d - mean(.data$mean_d), .by = "season")
  dfree <- sum(by_season$weeks - 1)
  list(delta = sum(wk$s) / sum(wk$n), delta_by_season = stats::setNames(by_season$delta, by_season$season),
       sigma_w = sqrt(sum(u$u^2) / dfree), sd_week_means = sqrt(sum(u$m^2) / dfree),
       weeks = nrow(wk), seasons = nrow(by_season), n_per_week = mean(wk$n))
}

#' Minimum detectable effect of a paired week-level test with W weeks: two-sided 95% CI
#' excluding 0 (equivalently a one-sided 2.5% test) with the given power.
#' MDE = (t_{1 - alpha/2, W-1} + t_{power, W-1}) * sigma_w / sqrt(W).
mde <- function(sigma_w, W, alpha = 0.05, power = 0.8) {
  (stats::qt(1 - alpha / 2, W - 1) + stats::qt(power, W - 1)) * sigma_w / sqrt(W)
}

#' Power of the pre-registered success criterion (the 95% CI lies entirely BELOW 0, i.e. the
#' challenger improves) when the true loss difference is `delta` (negative = improvement), using a
#' noncentral t with W - 1 df. A positive delta (the challenger is worse) gives power below alpha / 2.
power_at <- function(delta, sigma_w, W, alpha = 0.05) {
  1 - stats::pt(stats::qt(1 - alpha / 2, W - 1), W - 1, ncp = -delta * sqrt(W) / sigma_w)
}

#' Pass rate of the pre-registered criterion (percentile week-bootstrap 95% CI entirely below 0)
#' for normal week-level differences with mean `delta` (in sigma_w units) over W weeks of one season.
#' delta = 0 gives the test's actual one-sided size (nominal 2.5%). Synthetic; no data.
percentile_bootstrap_sim <- function(W, deltas, reps = 4000, boot_reps = 400, seed = 7) {
  set.seed(seed)
  vapply(deltas, function(d) {
    mean(replicate(reps, {
      x <- stats::rnorm(W, d, 1)
      b <- replicate(boot_reps, mean(x[sample.int(W, W, replace = TRUE)]))
      stats::quantile(b, 0.975) < 0
    }))
  }, numeric(1))
}

#' The F1 comparison set: each pre-registered prospective hypothesis with its historical sources.
#' `frames` is a named list of historical comparison frames (columns model, season, week, gsis_id,
#' actual, pred), e.g. list(m2_holdout = tar_read(m2_holdout_aligned), ...).
F1_COMPARISONS <- tibble::tribble(
  ~hypothesis, ~frame, ~model, ~baseline, ~source,
  "H-M2", "m2_holdout", "m2_espn_aug", "m2_espn_cal", "E5 holdout 2024-2025 (frozen models)",
  "H-M2", "m2_dev", "aug_resid_enet", "cal_components_recency", "E4 development 2020-2023 (selected candidates)",
  "H-A", "m3_holdout", "m3_role_adjust_v1", "m2_espn_cal", "E7 check 2024-2025",
  "H-B", "m3_holdout", "m3_return_adjust_v1", "m2_espn_cal", "E7 check 2024-2025",
  "H-D", "m4", "B1", "B0", "E13/E14 frame: M3b rule vs calibrated ESPN, 2019-2024",
  "H-M4 vs cal", "m4", "K2", "B0", "E13/E14 frame: m4_two_stage_v1 (K2) vs calibrated ESPN, 2019-2024",
  "H-M4 vs M3b", "m4", "K2", "B1", "E13/E14 frame: m4_two_stage_v1 (K2) vs M3b, 2019-2024"
)

#' Historical effect and noise of every F1 comparison, for both loss families.
f1_noise_table <- function(frames, comparisons = F1_COMPARISONS) {
  purrr::pmap(comparisons, function(hypothesis, frame, model, baseline, source) {
    purrr::map(c("abs", "sq"), function(loss) {
      wk <- week_level_diffs(frames[[frame]], model, baseline, loss)
      nz <- week_noise(wk)
      tibble::tibble(hypothesis = hypothesis, loss = if (loss == "abs") "MAE" else "MSE", source = source,
                     seasons = paste(range(wk$season), collapse = "-"), weeks = nz$weeks,
                     n_per_week = round(nz$n_per_week, 1), delta = nz$delta,
                     delta_by_season = paste(sprintf("%d: %+.4f", as.integer(names(nz$delta_by_season)), nz$delta_by_season),
                                             collapse = "; "),
                     sigma_w = nz$sigma_w, sd_week_means = nz$sd_week_means)
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}

#' Reference (plausible true) effect per hypothesis: the cleanest historical check, never a
#' development season (2020-2023 is in-sample for the M4 parameters). 2019 was fresh for the
#' M4 checks (E14); 2024-2025 is the frozen holdout for M2/M3 (E5, E7).
F1_REFERENCE <- tibble::tribble(
  ~hypothesis, ~frame, ~model, ~baseline, ~seasons,
  "H-M2", "m2_holdout", "m2_espn_aug", "m2_espn_cal", "2024,2025",
  "H-A", "m3_holdout", "m3_role_adjust_v1", "m2_espn_cal", "2024,2025",
  "H-B", "m3_holdout", "m3_return_adjust_v1", "m2_espn_cal", "2024,2025",
  "H-D", "m4", "B1", "B0", "2019",
  "H-M4 vs cal", "m4", "K2", "B0", "2019",
  "H-M4 vs M3b", "m4", "K2", "B1", "2019"
)

f1_reference_table <- function(frames, reference = F1_REFERENCE) {
  purrr::pmap(reference, function(hypothesis, frame, model, baseline, seasons) {
    yrs <- as.integer(strsplit(seasons, ",")[[1]])
    d <- dplyr::filter(frames[[frame]], .data$season %in% yrs)
    purrr::map(c("abs", "sq"), function(loss) {
      wk <- week_level_diffs(d, model, baseline, loss)
      tibble::tibble(hypothesis = hypothesis, loss = if (loss == "abs") "MAE" else "MSE",
                     delta_hist = sum(wk$s) / sum(wk$n), sigma_ref = week_noise(wk)$sigma_w,
                     reference_seasons = seasons)
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}

#' MDE table: for each hypothesis and loss, sigma_w pooled over its historical sources (weighted
#' by degrees of freedom), MDE at W informative weeks and sigma_w x inflation, and power at the
#' reference effect (f1_reference_table(); without one, the weeks-weighted historical effect).
mde_table <- function(noise, W = c(8, 10, 13, 14), inflation = c(1, 1.5), reference = NULL) {
  pooled <- noise |>
    dplyr::summarise(delta_hist = stats::weighted.mean(.data$delta, .data$weeks),
                     sigma_w = sqrt(sum((.data$weeks - 1) * .data$sigma_w^2) / sum(.data$weeks - 1)),
                     hist_weeks = sum(.data$weeks), .by = c("hypothesis", "loss"))
  if (!is.null(reference)) {
    pooled <- dplyr::left_join(dplyr::select(pooled, -"delta_hist"), reference, by = c("hypothesis", "loss"))
  }
  out <- tidyr::expand_grid(pooled, W = W, inflation = inflation) |>
    dplyr::mutate(sigma_used = .data$sigma_w * .data$inflation,
                  mde = mde(.data$sigma_used, .data$W),
                  power_at_hist = power_at(.data$delta_hist, .data$sigma_used, .data$W),
                  detectable = -.data$delta_hist >= .data$mde)
  if ("sigma_ref" %in% names(out)) {
    # sensitivity: the reference season's own noise (one season; 2019 was the quietest injury season)
    out <- dplyr::mutate(out, power_ref_sigma = power_at(.data$delta_hist, .data$sigma_ref * .data$inflation, .data$W))
  }
  out
}
