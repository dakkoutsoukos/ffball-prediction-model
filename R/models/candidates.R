# Candidate models and backtest orchestration ------------------------------------

#' Rows used for modelling: train/validation/test seasons, restricted to a
#' pregame-defined population. "auto" uses the ESPN population when ESPN
#' projections exist for every modelling season, else the active-roster one.
modelling_frame <- function(player_week, population = "auto") {
  d <- dplyr::filter(player_week, .data$split %in% c("train", "validation", "test"))
  espn_seasons <- unique(d$season[d$pop_espn])
  espn_complete <- length(espn_seasons) > 0 && all(unique(d$season) %in% espn_seasons)
  if (population == "auto") population <- if (espn_complete) "espn" else "active"
  if (population == "espn" && !espn_complete) {
    cli::cli_abort("ESPN population requested but ESPN projections are missing for some seasons.")
  }
  d |>
    dplyr::filter(.data[[paste0("pop_", population)]]) |>
    dplyr::mutate(population = population, game_index = game_index(.data$season, .data$week))
}

#' Development rows only (train + validation): everything tuning and model
#' selection are allowed to see.
dev_frame <- function(model_data) dplyr::filter(model_data, .data$split %in% c("train", "validation"))

feature_set <- function(name) {
  switch(name,
    usage = c(FEATURES_HISTORY, FEATURES_USAGE, FEATURES_MATCHUP),
    usage_vegas = c(feature_set("usage"), FEATURES_VEGAS),
    usage_vegas_injury = c(feature_set("usage_vegas"), FEATURES_INJURY),
    espn_plus = c("espn_proj", feature_set("usage_vegas")),
    cli::cli_abort("Unknown feature set {.val {name}}.")
  )
}

espn_available <- function(model_data) identical(unique(model_data$population), "espn")

#' Tune ridge penalties on the validation season (static fit on train).
tune_penalties <- function(dev_data, splits) {
  sets <- c(ridge_usage = "usage")
  if (espn_available(dev_data)) sets <- c(sets, ridge_espn_plus = "espn_plus")
  purrr::imap(sets, function(fs, name) tune_penalty(dev_data, name, feature_set(fs), splits))
}

best_penalty <- function(tuning) tuning$penalty[which.min(tuning$mae)]

#' The pre-registered candidate set (research/experiment_log.md).
candidate_specs <- function(penalty_tuning, has_espn) {
  specs <- list(
    spec_naive(8),
    spec_linear("ols_usage", feature_set("usage")),
    spec_linear("ridge_usage", feature_set("usage"), penalty = best_penalty(penalty_tuning$ridge_usage)),
    spec_linear("ols_usage_vegas", feature_set("usage_vegas")),
    spec_linear("ols_usage_vegas_injury", feature_set("usage_vegas_injury"))
  )
  if (has_espn) {
    specs <- c(list(spec_espn()), specs, list(
      spec_linear("ols_espn_plus", feature_set("espn_plus")),
      spec_linear("ridge_espn_plus", feature_set("espn_plus"),
                  penalty = best_penalty(penalty_tuning$ridge_espn_plus)),
      spec_espn_recal("l2"),
      spec_espn_recal("l1")
    ))
  }
  rlang::set_names(specs, purrr::map_chr(specs, "name"))
}

DIAGNOSTIC_MODELS <- c("espn_recal_l2", "espn_recal_l1")
EXPLORATORY_MODELS <- c("ols_usage_vegas_injury")

#' Static and rolling-origin predictions for every spec for one season.
run_backtests <- function(data, specs, splits, season) {
  static_train <- if (season == splits$validation_season) "train" else c("train", "validation")
  if (season > splits$validation_season && !any(data$season == season)) {
    cli::cli_abort("No rows for season {season}.")
  }
  purrr::map(specs, function(spec) {
    dplyr::bind_rows(
      predict_static(data, spec, static_train, season),
      predict_rolling(data, spec, season, splits$first_train_season)
    )
  }) |>
    purrr::list_rbind()
}
