# Chronological backtesting -------------------------------------------------------
# `data` is the modelling frame: one row per player-week with `actual`,
# `split`, `game_index`, features, and `espn_proj`. Two protocols:
#
#   static   fit once on rows with split in `train_splits`, predict the rows
#            of `predict_season`.
#   rolling  for each week w of `predict_season`, fit on ALL eligible rows with
#            game_index < (season, w) and predict week w - i.e. exactly what
#            would have been possible in real time with weekly retraining.
#
# Neither protocol ever trains on a row at or after the predicted week.

predict_static <- function(data, spec, train_splits, predict_season) {
  train <- dplyr::filter(data, .data$split %in% train_splits)
  test <- dplyr::filter(data, .data$season == predict_season)
  stopifnot(max(train$game_index) < min(test$game_index))
  fit <- spec$fit(train)
  as_predictions(test, spec, spec$predict(fit, test), protocol = "static")
}

predict_rolling <- function(data, spec, predict_season, min_train_season) {
  test_weeks <- sort(unique(data$week[data$season == predict_season]))
  purrr::map(test_weeks, function(w) {
    cutoff <- game_index(predict_season, w)
    train <- dplyr::filter(data, .data$season >= min_train_season, .data$game_index < cutoff)
    test <- dplyr::filter(data, .data$game_index == cutoff)
    fit <- spec$fit(train)
    as_predictions(test, spec, spec$predict(fit, test), protocol = "rolling")
  }) |>
    purrr::list_rbind()
}

as_predictions <- function(rows, spec, pred, protocol) {
  if (length(pred) != nrow(rows)) cli::cli_abort("{spec$name}: prediction length mismatch.")
  tibble::tibble(
    model = spec$name, protocol = protocol,
    season = rows$season, week = rows$week, gsis_id = rows$gsis_id,
    espn_proj = rows$espn_proj, actual = rows$actual, pred = pred
  )
}

#' Choose a glmnet penalty using ONLY the validation season (static fit on
#' the training seasons). Returns the grid with validation MAE/RMSE.
tune_penalty <- function(data, name, features, splits, grid = 10^seq(-3, 0.5, length.out = 12),
                         mixture = 0) {
  purrr::map(grid, function(p) {
    spec <- spec_linear(name, features, penalty = p, mixture = mixture)
    pr <- predict_static(data, spec, "train", splits$validation_season)
    dplyr::mutate(prediction_metrics(pr$actual, pr$pred), penalty = p)
  }) |>
    purrr::list_rbind()
}
