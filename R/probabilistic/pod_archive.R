# Prospective POD archive (master plan P0, E18) -------------------------------------------------
# From the freeze, the current-week PODs implied by each valuation run are archived write-once:
#   data/archive/distributions/season=S/week=WW/run=<valuation run id>/pods.parquet   (git-ignored)
#   archive/distribution_manifest.csv                                                  (hashes; committed)
# Base = the run's current-week projection (the mean V1/V2/S0 use; for WRs the frozen M4 prediction);
# P(active) = the designation prior for the ESPN status at capture (1 if undesignated), until P1.
# No outcome is read. These archives are evaluation-only (2027 confirmatory; sealed for 2026).

POD_ARCHIVE_ROOT <- "data/archive/distributions"
POD_MANIFEST <- "archive/distribution_manifest.csv"

#' Current-week PODs of one valuation run's weekly table.
pd_run_pods <- function(weekly, week, table = read_pod_table(), prior = read_availability_prior()) {
  cur <- weekly |>
    dplyr::filter(.data$week == !!week, .data$has_game, .data$proj > 0, .data$position %in% POD_POSITIONS) |>
    dplyr::transmute(.data$player_id, .data$espn_id, .data$position, .data$team, .data$week, base = .data$proj,
                     status = .data$availability_status, p_active = val_designation_prior(.data$status, prior))
  pods <- pd_pods(cur, table)
  validate_pod_table(pods)
  pods
}

#' Archive the current-week PODs of a valuation run (write-once) and append the manifest.
pd_archive_run <- function(season, week, run = NULL, table_file = POD_TABLE_FILE, root = POD_ARCHIVE_ROOT,
                           manifest = POD_MANIFEST, val_manifest = VAL_MANIFEST, val_root = VAL_ARCHIVE_ROOT,
                           prior = read_availability_prior()) {
  if (is.null(run)) {
    vm <- readr::read_csv(val_manifest, col_types = readr::cols(.default = "c")) |>
      dplyr::filter(as.integer(.data$season) == !!season, as.integer(.data$week) == !!week)
    if (!nrow(vm)) cli::cli_abort("No valuation run for {season} week {week}.")
    run <- sort(vm$run_id, decreasing = TRUE)[1]   # UTC stamps: lexical order is chronological
  }
  dir <- file.path(val_root, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", run))
  weekly <- arrow::read_parquet(file.path(dir, "weekly.parquet"), mmap = FALSE)
  pods <- pd_run_pods(weekly, week, pd_table_from_yaml(yaml::read_yaml(table_file)), prior)
  out <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", run), "pods.parquet")
  out <- write_once(out, function(tmp) arrow::write_parquet(pods, tmp))
  git <- git_state()
  append_manifest(tibble::tibble(valuation_run_id = run, season = season, week = week,
                                 created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                 pod_version = "pod_baseline_v0", pod_table_sha256 = sha256_file(table_file),
                                 n_players = nrow(pods), pods_sha256 = sha256_file(out), git_commit = git$commit), manifest)
  invisible(list(path = out, n = nrow(pods), run = run))
}
