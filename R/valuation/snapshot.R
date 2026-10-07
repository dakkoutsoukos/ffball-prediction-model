# Valuation: point-in-time runs and their archive ------------------------------------------
# A run values every pool player as of `as_of` with a fixed methodology and writes
#   data/archive/valuation/season=S/week=WW/run=<UTC>/{values,weekly,baselines,
#       rosters,sensitivity,consolidation}.parquet + run_meta.json   (write-once)
# and appends their hashes to the committed archive/valuation_manifest.csv.
# The meta records the league settings (and hash), scoring file hash, provider
# configuration and versions (ESPN capture hash, archived M4 run id + hash),
# ROS parameter hash, methodology version, simulation settings, live nflverse
# files and the git commit, so a run can be reproduced and later evaluated.
# Archived values are ESPN-derived: they stay local (git-ignored).

VAL_ARCHIVE_ROOT <- "data/archive/valuation"
VAL_MANIFEST <- "archive/valuation_manifest.csv"

#' Value one season-week as of `as_of`; optionally archive the result.
run_valuation <- function(season, week, as_of = Sys.time(), cfg = read_valuation_config(), archive = TRUE,
                          sensitivity = TRUE, consolidation = TRUE, require_clean_git = archive,
                          root = VAL_ARCHIVE_ROOT, manifest = VAL_MANIFEST) {
  git <- git_state()
  if (require_clean_git && !isFALSE(git$dirty)) {
    cli::cli_abort("Archived valuation runs need a clean git tree (commit first) so values map to a commit.")
  }
  t0 <- Sys.time()
  ctx <- val_live_context(season, week, as_of, cfg)
  weeks <- val_horizon_weeks(cfg$league, week, "full")
  proj <- val_build_weekly(ctx, weeks)
  players <- attr(proj, "players")
  wk <- val_weekly_frame(proj)
  sim <- val_sim_setup(wk, cfg$simulation$sims, cfg$simulation$seed)
  main <- val_value_league(wk, cfg$league, week, cfg$simulation, players, with_mru = TRUE, sim = sim)

  sens <- NULL
  if (sensitivity) {
    leagues <- c(list(default = cfg$league),
                 purrr::imap(cfg$sensitivity_leagues, function(o, nm) val_league_override(cfg$league, o, nm)))
    sens <- purrr::imap(leagues, function(lg, nm) {
      pools <- if (nm == "default") c("proportional", "simulation") else "proportional"
      purrr::map(pools, function(pl) {
        r <- val_value_league(wk, lg, week, cfg$simulation, players, with_mru = FALSE, pool = pl, sim = sim)
        list(values = dplyr::mutate(dplyr::select(r$values, "player_id", "position", "overall_rank", "position_rank",
                                                  "ros_points", "vor", "vas", "replacement_points", "rostered"),
                                    league = nm, pool = pl),
             scarcity = dplyr::mutate(r$scarcity, league = nm, pool = pl))
      })
    }) |>
      purrr::list_flatten()
    sens <- list(values = purrr::map(sens, "values") |> purrr::list_rbind(),
                 scarcity = purrr::map(sens, "scarcity") |> purrr::list_rbind())
  }
  cons <- if (consolidation) val_consolidation_study(main$league_sim, main$values) else NULL

  run_id <- utc_stamp(as_of)
  m4 <- val_latest_m4_run(season, week, as_of)
  league_yaml <- yaml::as.yaml(cfg$league)
  weekly_out <- proj |>
    dplyr::left_join(dplyr::select(main$weekly_values, "player_id", "week", "S", "R", "vor_week", "vor_plus", "vas_week",
                                   "league_starter"), by = c("player_id", "week"))
  values_out <- main$values |>
    dplyr::mutate(season = as.integer(season), week = as.integer(week), run_id = run_id,
                  methodology_version = cfg$methodology_version, .before = 1)
  meta <- list(
    run_id = run_id, season = season, week = week,
    as_of_utc = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    methodology_version = cfg$methodology_version, git_commit = git$commit, git_dirty = git$dirty,
    league = cfg$league, league_hash = val_league_hash(cfg$league),
    scoring_file = if (is.null(cfg$scoring_rules)) file.path("config", "scoring", paste0(cfg$league$scoring, ".yml")) else "league settings",
    scoring_sha256 = if (is.null(cfg$scoring_rules)) sha256_file(file.path("config", "scoring", paste0(cfg$league$scoring, ".yml")))
                     else digest_text(yaml::as.yaml(as.list(cfg$scoring_rules$weights))),
    valuation_config_sha256 = sha256_file(cfg$path),
    projection_sources = cfg$projection_sources,
    provider_versions = list(
      espn_capture = basename(ctx$capture_path), espn_capture_sha256 = ctx$capture_sha256,
      espn_capture_captured_at_utc = unique(ctx$capture$captured_at_utc),
      m4_model_id = cfg$m4_model_id,
      m4_run_id = m4$run_id %||% NA, m4_predictions_sha256 = m4$sha256 %||% NA,
      m4_snapshot_captured_at_utc = m4$snapshot_captured_at_utc %||% NA,
      ros_params_file = cfg$ros_params_file, ros_params_sha256 = ctx$ros_params_sha256, ros_params_version = ctx$ros$version
    ),
    sources_used = as.list(table(paste(proj$proj_kind, proj$source, sep = ":"))),
    live_files = ctx$live_files, live_sha256 = lapply(ctx$live_files, sha256_file),
    simulation = cfg$simulation, pool = main$league_sim$pool,
    generic_team_composition = as.list(table(main$league_sim$rosters$position)),
    rostered_pool_composition = as.list(table(main$values$position[main$values$rostered])),
    display_map = main$display_map$type,
    n_players = nrow(main$values), horizon_weeks = weeks,
    elapsed_seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  )
  res <- list(values = values_out, weekly = weekly_out, baselines = main$baselines, scarcity = main$scarcity,
              rosters = dplyr::left_join(main$league_sim$rosters, dplyr::select(players, "player_id", "espn_name", "team"),
                                         by = "player_id"),
              display_knots = main$display_map$knots %||% tibble::tibble(), sensitivity = sens,
              consolidation = cons, meta = meta, league_sim = main$league_sim)
  if (!archive) return(res)
  val_archive_run(res, root, manifest)
}

#' Write a valuation result write-once and append its hashes to the manifest.
val_archive_run <- function(res, root = VAL_ARCHIVE_ROOT, manifest = VAL_MANIFEST) {
  meta <- res$meta
  dir <- file.path(root, sprintf("season=%d", as.integer(meta$season)), sprintf("week=%02d", as.integer(meta$week)),
                   paste0("run=", meta$run_id))
  wp <- function(name, d) write_once(file.path(dir, paste0(name, ".parquet")), function(tmp) arrow::write_parquet(d, tmp))
  tabs <- list(values = res$values, weekly = res$weekly, baselines = res$baselines, scarcity = res$scarcity,
               rosters = res$rosters, display_knots = res$display_knots,
               sensitivity_values = res$sensitivity$values, sensitivity_scarcity = res$sensitivity$scarcity,
               consolidation = res$consolidation)
  tabs <- Filter(function(d) !is.null(d) && is.data.frame(d), tabs)
  paths <- purrr::imap(tabs, function(d, nm) wp(nm, d))
  meta$files <- lapply(paths, basename)
  meta$files_sha256 <- lapply(paths, sha256_file)
  meta_path <- write_once(file.path(dir, "run_meta.json"), function(tmp) {
    jsonlite::write_json(meta, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  })
  append_manifest(tibble::tibble(
    run_id = meta$run_id, season = meta$season, week = meta$week, as_of_utc = meta$as_of_utc,
    methodology_version = meta$methodology_version, league_hash = meta$league_hash, n_players = meta$n_players,
    values_sha256 = sha256_file(paths$values), weekly_sha256 = sha256_file(paths$weekly),
    run_meta_sha256 = sha256_file(meta_path),
    espn_capture_sha256 = meta$provider_versions$espn_capture_sha256 %||% "",
    m4_run_id = meta$provider_versions$m4_run_id %||% "",
    ros_params_sha256 = meta$provider_versions$ros_params_sha256 %||% "", git_commit = meta$git_commit %||% ""
  ), manifest)
  res$dir <- dir
  res$meta <- meta
  res
}

#' Verify archived valuation runs against the committed manifest.
verify_valuation_archive <- function(manifest = VAL_MANIFEST, root = VAL_ARCHIVE_ROOT) {
  if (!file.exists(manifest)) return(tibble::tibble())
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
  purrr::pmap(m, function(run_id, season, week, values_sha256, weekly_sha256, run_meta_sha256, ...) {
    dir <- file.path(root, paste0("season=", season), sprintf("week=%02d", as.integer(week)), paste0("run=", run_id))
    ok <- function(f, h) file.exists(file.path(dir, f)) && identical(sha256_file(file.path(dir, f)), h)
    tibble::tibble(run_id = run_id, season = as.integer(season), week = as.integer(week),
                   verified = ok("values.parquet", values_sha256) && ok("weekly.parquet", weekly_sha256) &&
                     ok("run_meta.json", run_meta_sha256))
  }) |>
    purrr::list_rbind()
}

#' The latest verified archived run (optionally for one season-week).
latest_valuation_run <- function(season = NULL, week = NULL, manifest = VAL_MANIFEST, root = VAL_ARCHIVE_ROOT) {
  v <- verify_valuation_archive(manifest, root)
  if (!nrow(v)) return(NULL)
  if (!is.null(season)) v <- v[v$season == season, ]
  if (!is.null(week)) v <- v[v$week == week, ]
  v <- v[v$verified, ]
  if (!nrow(v)) return(NULL)
  r <- v[order(v$run_id, decreasing = TRUE)[1], ]
  dir <- file.path(root, sprintf("season=%d", r$season), sprintf("week=%02d", r$week), paste0("run=", r$run_id))
  # mmap = FALSE: a memory-mapped file stays locked on Windows
  read <- function(f) if (file.exists(file.path(dir, f))) arrow::read_parquet(file.path(dir, f), mmap = FALSE) else NULL
  list(run_id = r$run_id, dir = dir, meta = jsonlite::read_json(file.path(dir, "run_meta.json")),
       values = read("values.parquet"), weekly = read("weekly.parquet"), baselines = read("baselines.parquet"),
       scarcity = read("scarcity.parquet"), rosters = read("rosters.parquet"),
       display_knots = read("display_knots.parquet"), sensitivity_values = read("sensitivity_values.parquet"),
       sensitivity_scarcity = read("sensitivity_scarcity.parquet"), consolidation = read("consolidation.parquet"))
}
