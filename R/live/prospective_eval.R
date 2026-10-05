# Scoring the prospective record (docs/prospective_protocol.md) ------------------------
# Only ARCHIVED predictions count. Files are verified against the committed
# manifest hashes first; regenerated predictions are never mixed in.

#' Recompute SHA-256 of every archived run and compare with the manifest.
verify_prediction_archive <- function(manifest = PREDICTION_MANIFEST, root = "data/archive/predictions") {
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
  purrr::pmap(m, function(run_id, season, week, predictions_sha256, ...) {
    path <- file.path(root, paste0("season=", season), sprintf("week=%02d", as.integer(week)),
                      paste0("run=", run_id), "predictions.parquet")
    ok <- file.exists(path) && identical(sha256_file(path), predictions_sha256)
    tibble::tibble(run_id = run_id, season = as.integer(season), week = as.integer(week), path = path, verified = ok)
  }) |>
    purrr::list_rbind()
}

#' Official prediction per (model, player-week): the latest VERIFIED run made
#' before that game's kickoff, using a snapshot captured before kickoff.
official_predictions <- function(verified, archive) {
  ok <- verified$path[verified$verified]
  if (length(ok) == 0) return(tibble::tibble())
  read_parquet_files(ok) |>
    dplyr::mutate(predicted_at = as.POSIXct(.data$predicted_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                  snapshot_at = as.POSIXct(.data$snapshot_captured_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) |>
    dplyr::filter(.data$predicted_at < .data$kickoff_utc, .data$snapshot_at < .data$kickoff_utc) |>
    dplyr::slice_max(.data$predicted_at, n = 1, with_ties = FALSE, by = c("model_id", "season", "week", "gsis_id"))
}

#' Score completed weeks only. `outcomes` = clean player stats (live), `team_games`
#' carries `game_final`. A predicted player without a stat line in a final game
#' scored 0. Returns per-model metrics and paired comparisons with benchmarks
#' from the same runs.
score_prospective <- function(official, outcomes, team_games, reps = 2000, seed = 1) {
  if (nrow(official) == 0) return(list(weeks_complete = 0L, metrics = tibble::tibble(), comparisons = tibble::tibble()))
  final_weeks <- team_games |>
    dplyr::summarise(done = all(.data$game_final), .by = c("season", "week")) |>
    dplyr::filter(.data$done)
  d <- official |>
    dplyr::semi_join(final_weeks, by = c("season", "week")) |>
    dplyr::left_join(dplyr::select(outcomes, "season", "week", "gsis_id", actual = "fantasy_pts"),
                     by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(actual = dplyr::coalesce(.data$actual, 0), model = .data$model_id) |>
    # Pregame top-60 by the run's ESPN projection, as in the historical evaluation.
    dplyr::mutate(relevant = dplyr::min_rank(dplyr::desc(.data$espn_proj)) <= 60,
                  .by = c("model", "season", "week"))
  weeks <- dplyr::n_distinct(paste(d$season, d$week))
  if (weeks == 0) return(list(weeks_complete = 0L, metrics = tibble::tibble(), comparisons = tibble::tibble()))
  aligned <- align_predictions(d)
  benches <- intersect(c("m2_espn_cal", "m1_espn_raw", "m1_espn_recal"), unique(aligned$model))
  comps <- tidyr::expand_grid(model = unique(aligned$model), baseline = benches) |>
    dplyr::filter(.data$model != .data$baseline) |>
    purrr::pmap(~ pooled_bootstrap(aligned, ..1, ..2, reps, seed)) |>
    purrr::list_rbind()
  list(weeks_complete = weeks, metrics = summarise_m2(aligned), comparisons = comps)
}
