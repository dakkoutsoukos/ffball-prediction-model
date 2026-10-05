# Frozen model registry --------------------------------------------------------------
# Frozen model definitions live in models/registry/<lineage>.yml. Code builds
# model specs FROM the registry (never from shared feature constants), so later
# development cannot silently change a frozen model. Each registry file records
# the commit, data window, procedure and selection rationale.

read_registry <- function(lineage, dir = "models/registry") {
  path <- file.path(dir, paste0(tolower(lineage), ".yml"))
  if (!file.exists(path)) cli::cli_abort("No registry file {.file {path}}.")
  reg <- yaml::read_yaml(path)
  reg$path <- path
  reg
}

#' Build spec objects (see R/models/models.R) for every model in a registry.
#' Spec `name`s are the registry ids, e.g. "m1_espn_plus".
registry_specs <- function(reg) {
  specs <- purrr::imap(reg$models, function(m, id) {
    spec <- switch(m$type,
      espn_raw = spec_espn(),
      espn_recal_l2 = spec_espn_recal("l2"),
      naive = spec_naive(m$k),
      linear_ols = spec_linear(id, unlist(m$features)),
      registry_spec_extra(m, id) %||%
        cli::cli_abort("Unknown registry model type {.val {m$type}} for {id}.")
    )
    spec$name <- id
    spec$frozen_lineage <- reg$lineage
    spec
  })
  rlang::set_names(specs, names(reg$models))
}

#' Hook for model types added by later lineages (defined in their own modules).
registry_spec_extra <- function(m, id) {
  fn <- get0(paste0("registry_spec_", m$type), mode = "function")
  if (is.null(fn)) NULL else fn(m, id)
}

#' Player-week dataset as a frozen lineage saw it: features computed only from
#' history on or after the lineage's `history_start_season`, so extending the
#' project's data window later cannot change the lineage's inputs.
lineage_player_week <- function(reg, base, player_games, team_volume, defense_allowed,
                                team_games, splits, top_n = 60) {
  hs <- reg$data$history_start_season
  keep <- function(d) dplyr::filter(d, .data$season >= hs)
  add_point_in_time_features(
    keep(base), keep(player_games), keep(team_volume), keep(defense_allowed), keep(team_games),
    windows = unlist(reg$data$feature_windows)
  ) |>
    finalize_player_week(splits, top_n)
}

#' Model-ready rows for a frozen lineage: its population and training seasons.
frozen_frame <- function(reg, lineage_pw, max_season = Inf) {
  lineage_pw |>
    dplyr::filter(.data[[reg$data$population]], .data$season >= reg$data$min_train_season,
                  .data$season <= max_season) |>
    dplyr::mutate(population = sub("^pop_", "", reg$data$population),
                  game_index = game_index(.data$season, .data$week))
}

#' Rolling (weekly expanding-window) predictions of every frozen spec.
frozen_rolling_predictions <- function(frame, specs, seasons, min_train_season) {
  purrr::map(specs, function(spec) {
    purrr::map(seasons, ~ predict_rolling(frame, spec, .x, min_train_season)) |> purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}

#' Hash rolling predictions the same way the committed fingerprint was made.
prediction_fingerprint <- function(preds) {
  preds |>
    dplyr::arrange(.data$model, .data$season, .data$week, .data$gsis_id) |>
    dplyr::summarise(
      n = dplyr::n(),
      mean_pred = round(mean(.data$pred), 6),
      pred_hash_xxh128 = rlang::hash(paste(.data$season, .data$week, .data$gsis_id,
                                           sprintf("%.6f", .data$pred), collapse = "\n")),
      .by = "model"
    ) |>
    dplyr::rename(model_id = "model")
}

#' Hash of the raw files a frozen lineage actually uses (by size), so adding
#' unrelated seasons or live files does not change its data version.
fingerprint_data_hash <- function(raw_manifest, nflverse_from, espn_from, max_season = 2025) {
  s <- suppressWarnings(as.integer(raw_manifest$season))
  is_espn <- raw_manifest$provider %in% "ESPN"
  use <- (is.na(s) & !is_espn) |
    (!is_espn & !is.na(s) & s >= nflverse_from & s <= max_season) |
    (is_espn & !is.na(s) & s >= espn_from & s <= max_season)
  m <- raw_manifest[use, ]
  rlang::hash(paste(sort(paste(basename(m$path), m$bytes)), collapse = "|"))
}

#' Compare regenerated frozen predictions with the committed fingerprint.
#' Exact agreement is required when the raw data are the same version; with a
#' different data version the check reports "unverifiable" rather than passing.
check_frozen_fingerprint <- function(preds, fingerprint_path, raw_manifest, reg) {
  expected <- readr::read_csv(fingerprint_path, show_col_types = FALSE)
  got <- prediction_fingerprint(preds)
  data_hash <- fingerprint_data_hash(raw_manifest, reg$data$history_start_season,
                                     reg$data$min_train_season)
  cmp <- dplyr::left_join(expected, got, by = "model_id", suffix = c("_expected", "_got")) |>
    dplyr::mutate(match = .data$pred_hash_xxh128_expected == .data$pred_hash_xxh128_got)
  same_data <- all(expected$raw_data_hash_xxh128 == data_hash)
  status <- if (all(cmp$match %in% TRUE)) "identical" else if (same_data) "CHANGED" else "unverifiable_data_changed"
  if (status == "CHANGED") {
    cli::cli_abort(c("Frozen model predictions changed on the same data version.",
                     "x" = "Models: {.val {cmp$model_id[!cmp$match %in% TRUE]}}"))
  }
  list(status = status, comparison = cmp, data_hash = data_hash)
}
