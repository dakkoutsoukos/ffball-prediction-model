# Evaluation metrics -------------------------------------------------------------
# Predictions are handled in "long" form: one row per (model, player-week) with
# columns model, season, week, gsis_id, pred, actual (plus any grouping cols).

prediction_metrics <- function(actual, pred) {
  err <- pred - actual
  tibble::tibble(
    n = length(err),
    mae = mean(abs(err)),
    rmse = sqrt(mean(err^2)),
    bias = mean(err),                 # > 0: over-projection on average
    median_ae = stats::median(abs(err)),
    cor = if (length(err) > 2) stats::cor(pred, actual) else NA_real_
  )
}

#' Mean within-week Spearman rank correlation (how well a model orders players
#' in the same week, which is what start/sit decisions depend on).
weekly_rank_cor <- function(df) {
  df |>
    dplyr::summarise(
      rho = if (dplyr::n() > 2) stats::cor(.data$pred, .data$actual, method = "spearman") else NA_real_,
      .by = c("season", "week")
    ) |>
    dplyr::summarise(rank_cor = mean(.data$rho, na.rm = TRUE)) |>
    dplyr::pull("rank_cor")
}

#' Restrict long predictions to player-weeks every listed model predicted, so
#' models are compared on identical observations. Reports what was dropped.
align_predictions <- function(preds, models = unique(preds$model),
                              keys = c("season", "week", "gsis_id")) {
  wide <- preds |>
    dplyr::filter(.data$model %in% models) |>
    dplyr::select(dplyr::all_of(keys), "model", "pred") |>
    tidyr::pivot_wider(names_from = "model", values_from = "pred")
  complete <- stats::complete.cases(wide[, models, drop = FALSE])
  kept <- wide[complete, keys]
  out <- dplyr::semi_join(dplyr::filter(preds, .data$model %in% models), kept, by = keys)
  attr(out, "n_dropped") <- sum(!complete)
  attr(out, "n_kept") <- sum(complete)
  out
}

summarise_metrics <- function(preds, by = character()) {
  preds |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c("model", by)))) |>
    dplyr::group_modify(function(d, k) {
      dplyr::mutate(prediction_metrics(d$actual, d$pred), rank_cor = weekly_rank_cor(d))
    }) |>
    dplyr::ungroup()
}

#' Paired, week-clustered bootstrap of MAE(model) - MAE(baseline).
#'
#' Errors are correlated within a week (shared game environments, scoring
#' climate), so whole weeks are resampled rather than player-weeks.
#' Negative differences favour `model`.
paired_bootstrap_mae <- function(preds, model, baseline, reps = 2000, seed = 1) {
  wide <- preds |>
    dplyr::filter(.data$model %in% c(!!model, !!baseline)) |>
    dplyr::select("season", "week", "gsis_id", "actual", "model", "pred") |>
    tidyr::pivot_wider(names_from = "model", values_from = "pred") |>
    dplyr::filter(!is.na(.data[[model]]), !is.na(.data[[baseline]])) |>
    dplyr::mutate(d = abs(.data[[model]] - .data$actual) - abs(.data[[baseline]] - .data$actual))

  by_week <- dplyr::summarise(wide, s = sum(.data$d), n = dplyr::n(), .by = c("season", "week"))
  set.seed(seed)
  boots <- replicate(reps, {
    i <- sample.int(nrow(by_week), replace = TRUE)
    sum(by_week$s[i]) / sum(by_week$n[i])
  })
  tibble::tibble(
    model = model, baseline = baseline, n = nrow(wide), n_weeks = nrow(by_week),
    mae_diff = mean(wide$d),
    ci_low = unname(stats::quantile(boots, 0.025)),
    ci_high = unname(stats::quantile(boots, 0.975)),
    share_boot_better = mean(boots < 0),
    weeks_model_better = mean(by_week$s < 0)
  )
}
