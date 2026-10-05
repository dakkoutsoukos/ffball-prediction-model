# Milestone 2 development protocol and evaluation -----------------------------------
# Protocol (pre-registered, research/experiment_log.md E3):
#   development folds 2020-2023, weekly expanding-window refits from 2018;
#   hyperparameters from static season-level fits on the development seasons;
#   historical holdout 2024-2025 run once after selection; 2026 prospective.

#' M2 modelling frame: ESPN population, seasons >= first_train_season, with
#' pregame subset flags. Seasons after `max_season` are refused.
m2_frame <- function(player_week_m2, m2_cfg, max_season) {
  d <- player_week_m2 |>
    dplyr::filter(.data$pop_espn, .data$season >= m2_cfg$first_train_season, .data$season <= max_season) |>
    dplyr::mutate(game_index = game_index(.data$season, .data$week),
                  startable = .data$espn_rank <= m2_cfg$startable_top_n)
  # ESPN projected stat components are 0 when ESPN projected none.
  d |> dplyr::mutate(dplyr::across(dplyr::all_of(setdiff(ESPN_COMPONENTS, "espn_proj")), ~ dplyr::coalesce(.x, 0)))
}

#' Guard: development code may only ever see development seasons.
assert_dev_only <- function(d, m2_cfg) {
  if (max(d$season) > max(unlist(m2_cfg$dev_seasons))) {
    cli::cli_abort("Development data contains season {max(d$season)} beyond the development folds.")
  }
  d
}

#' Static season-level folds: predict each season from all earlier seasons.
static_season_folds <- function(data, spec, seasons, min_train_season) {
  purrr::map(seasons, function(s) {
    train <- dplyr::filter(data, .data$season >= min_train_season, .data$season < s)
    test <- dplyr::filter(data, .data$season == s)
    fit <- spec$fit(train)
    as_predictions(test, spec, spec$predict(fit, test), protocol = "static")
  }) |>
    purrr::list_rbind()
}

rolling_folds <- function(data, spec, seasons, min_train_season) {
  purrr::map(seasons, ~ predict_rolling(data, spec, .x, min_train_season)) |> purrr::list_rbind()
}

#' Tune a small grid of specs on static development folds; returns pooled MAE
#' per grid point (lower is better).
tune_grid <- function(data, specs, m2_cfg) {
  purrr::map(specs, function(spec) {
    p <- static_season_folds(data, spec, unlist(m2_cfg$dev_seasons), m2_cfg$first_train_season)
    tibble::tibble(name = spec$name, mae = mean(abs(p$pred - p$actual)),
                   rmse = sqrt(mean((p$pred - p$actual)^2)))
  }) |>
    purrr::list_rbind()
}

# --- Metrics -------------------------------------------------------------------------------

#' Within-week pairwise ordering accuracy among pregame-relevant players:
#' share of pairs with different actual scores whose predicted order matches
#' (prediction ties count half).
pairwise_accuracy <- function(pred, actual) {
  dp <- outer(pred, pred, "-")
  da <- outer(actual, actual, "-")
  use <- upper.tri(da) & da != 0
  if (!any(use)) return(NA_real_)
  score <- ifelse(dp[use] == 0, 0.5, as.numeric(sign(dp[use]) == sign(da[use])))
  mean(score)
}

#' Share of the predicted top-k (by week) that finished in the actual top-k.
top_k_precision <- function(pred, actual, k = 24) {
  if (length(pred) < k) return(NA_real_)
  length(intersect(order(-pred)[1:k], order(-actual)[1:k])) / k
}

extended_metrics <- function(df) {
  wk <- df |>
    dplyr::summarise(
      rho = if (dplyr::n() > 2) stats::cor(.data$pred, .data$actual, method = "spearman") else NA_real_,
      pair_acc = pairwise_accuracy(.data$pred[.data$relevant], .data$actual[.data$relevant]),
      top24 = top_k_precision(.data$pred, .data$actual, 24),
      .by = c("season", "week")
    )
  dplyr::bind_cols(
    prediction_metrics(df$actual, df$pred),
    tibble::tibble(
      rank_cor = mean(wk$rho, na.rm = TRUE),
      pairwise_acc_top60 = mean(wk$pair_acc, na.rm = TRUE),
      top24_precision = mean(wk$top24, na.rm = TRUE),
      large_miss_rate = mean(abs(df$pred - df$actual) > 10)
    )
  )
}

summarise_m2 <- function(preds, by = character()) {
  preds |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c("model", by)))) |>
    dplyr::group_modify(function(d, k) extended_metrics(d), .keep = TRUE) |>
    dplyr::ungroup()
}

#' Paired bootstrap of MAE(model) - MAE(baseline) resampling WEEKS WITHIN EACH
#' SEASON (so every resample keeps the season mix). Also reports RMSE of both.
pooled_bootstrap <- function(preds, model, baseline, reps = 2000, seed = 1) {
  wide <- preds |>
    dplyr::filter(.data$model %in% c(!!model, !!baseline)) |>
    dplyr::select("season", "week", "gsis_id", "actual", "model", "pred") |>
    tidyr::pivot_wider(names_from = "model", values_from = "pred") |>
    dplyr::filter(!is.na(.data[[model]]), !is.na(.data[[baseline]])) |>
    dplyr::mutate(d = abs(.data[[model]] - .data$actual) - abs(.data[[baseline]] - .data$actual))
  wk <- dplyr::summarise(wide, s = sum(.data$d), n = dplyr::n(), .by = c("season", "week"))
  set.seed(seed)
  groups <- split(seq_len(nrow(wk)), wk$season)
  boots <- replicate(reps, {
    i <- unlist(lapply(groups, function(g) g[sample.int(length(g), replace = TRUE)]))
    sum(wk$s[i]) / sum(wk$n[i])
  })
  tibble::tibble(
    model = model, baseline = baseline, n = nrow(wide), n_weeks = nrow(wk),
    n_seasons = length(groups), mae_diff = mean(wide$d),
    ci_low = unname(stats::quantile(boots, 0.025)), ci_high = unname(stats::quantile(boots, 0.975)),
    weeks_better = mean(wk$s < 0),
    rmse_model = sqrt(mean((wide[[model]] - wide$actual)^2)),
    rmse_baseline = sqrt(mean((wide[[baseline]] - wide$actual)^2))
  )
}

#' Per-season MAE differences (generalisation across seasons).
seasonal_deltas <- function(preds, model, baseline) {
  preds |>
    dplyr::filter(.data$model %in% c(!!model, !!baseline)) |>
    dplyr::summarise(mae = mean(abs(.data$pred - .data$actual)),
                     rmse = sqrt(mean((.data$pred - .data$actual)^2)), .by = c("season", "model")) |>
    tidyr::pivot_wider(names_from = "model", values_from = c("mae", "rmse")) |>
    dplyr::mutate(model = model, baseline = baseline,
                  mae_diff = .data[[paste0("mae_", model)]] - .data[[paste0("mae_", baseline)]],
                  rmse_diff = .data[[paste0("rmse_", model)]] - .data[[paste0("rmse_", baseline)]]) |>
    dplyr::select("season", "model", "baseline", "mae_diff", "rmse_diff")
}

# --- Pre-registered selection rules ------------------------------------------------------

pooled_mae <- function(preds) {
  preds |>
    dplyr::summarise(mae = mean(abs(.data$pred - .data$actual)),
                     rmse = sqrt(mean((.data$pred - .data$actual)^2)), .by = "model") |>
    dplyr::arrange(.data$mae)
}

select_calibration <- function(dev_preds) {
  tab <- pooled_mae(dplyr::filter(dev_preds, startsWith(.data$model, "cal_")))
  list(model = tab$model[[1]], table = tab)
}

select_challengers <- function(dev_preds, cal_name, nf_names, aug_names) {
  tab <- pooled_mae(dev_preds)
  nf <- dplyr::filter(tab, .data$model %in% nf_names)
  cal_rmse <- tab$rmse[tab$model == cal_name]
  aug <- dplyr::filter(tab, .data$model %in% aug_names) |>
    dplyr::mutate(rmse_ok = .data$rmse <= cal_rmse)
  aug_pick <- if (any(aug$rmse_ok)) aug$model[aug$rmse_ok][[1]] else aug$model[[1]]
  list(nf = nf$model[[1]], aug = aug_pick, aug_rmse_ok = any(aug$rmse_ok), table = tab)
}
