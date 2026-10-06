# Prospective prediction runs --------------------------------------------------------
# A run predicts an upcoming week with FROZEN models only, using data available
# at run time, and archives the result immutably:
#   data/archive/predictions/season=S/week=WW/run=<UTC>/predictions.parquet (+ run_meta.json)
# and appends a row (with SHA-256 hashes) to the committed, append-only
# archive/prediction_manifest.csv. Committing and pushing the manifest before
# kickoff gives a public, tamper-evident record that the predictions existed,
# without publishing ESPN-derived data. See docs/prospective_protocol.md.

PREDICTION_MANIFEST <- "archive/prediction_manifest.csv"
SNAPSHOT_MANIFEST <- "archive/espn_snapshot_manifest.csv"

#' Current commit and whether tracked CODE differs from it. The append-only
#' manifests under archive/ are excluded: a run legitimately appends to them.
git_state <- function() {
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_)
  changes <- tryCatch(system2("git", c("status", "--porcelain", "--untracked-files=no"), stdout = TRUE),
                      error = function(e) NA_character_)
  dirty <- if (anyNA(changes)) NA else any(!grepl("^.. archive/", changes))
  list(commit = commit[[1]], dirty = dirty)
}

#' Append one row to an append-only CSV manifest (creating it if needed).
append_manifest <- function(row, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  row <- dplyr::mutate(row, dplyr::across(dplyr::everything(), as.character))
  if (file.exists(path)) {
    old <- readr::read_csv(path, col_types = readr::cols(.default = "c"), n_max = 0)
    if (!setequal(names(old), names(row))) {
      cli::cli_abort("Manifest {.file {path}} columns differ from the new row; refusing to append.")
    }
    readr::write_csv(row[, names(old)], path, append = TRUE)
  } else {
    readr::write_csv(row, path)
  }
  invisible(path)
}

hist_paths <- function(dataset, seasons) {
  p <- vapply(seasons, function(s) raw_nflverse_path(dataset, s), character(1))
  p[file.exists(p)]
}

espn_raw_files <- function(root = "data/raw/espn", position = "wr") {
  list.files(root, pattern = paste0("^espn_", position, "_[0-9]{4}_w[0-9]{2}[.]json[.]gz$"),
             recursive = TRUE, full.names = TRUE)
}

#' Clean tables built from historical raw files plus the latest live retrievals
#' made at or before `as_of`. Mirrors the targets pipeline step for step.
assemble_live_inputs <- function(cfg, live_season, as_of = Sys.time()) {
  hs <- cfg$seasons_all
  live <- rlang::set_names(purrr::map_chr(LIVE_DATASETS, ~ latest_live_file(.x, live_season, as_of)),
                           LIVE_DATASETS)
  both <- function(ds) c(hist_paths(ds, hs), live[[ds]])
  rules <- read_scoring_rules(cfg$scoring_system)

  player_stats <- clean_player_stats(both("player_stats"), rules, cfg$season_type)
  team_games <- clean_team_games(both("schedules"), cfg$season_type)
  players <- read_parquet_files(live[["players"]])
  ff_playerids <- read_parquet_files(live[["ff_playerids"]])
  rosters <- clean_rosters_weekly(both("rosters_weekly"), player_stats, cfg$season_type)
  snaps <- clean_snap_counts(both("snap_counts"), players, cfg$season_type)
  injuries <- clean_injuries(both("injuries"), cfg$season_type)
  xfp <- clean_ff_opportunity(both("ff_opportunity"), cfg$season_type)
  pbp_usage <- pbp_target_usage(both("pbp"), cfg$season_type)
  espn_weekly <- parse_espn_files(tibble::tibble(path = espn_raw_files()))

  list(
    live_files = live, player_stats = player_stats, team_games = team_games,
    players = players, ff_playerids = ff_playerids, rosters = rosters, snaps = snaps,
    injuries = injuries, xfp = xfp, pbp_usage = pbp_usage, espn_weekly = espn_weekly,
    pbp_paths = both("pbp"),
    player_games = build_player_games(player_stats, snaps, pbp_usage, xfp),
    team_volume = build_team_volume(player_stats),
    defense_allowed = build_defense_allowed(player_stats, team_games, position = "WR")
  )
}

#' Live-data hygiene: in a live run, a game before the target week that is not
#' FINAL (in progress, or postponed) must look as if it has not happened yet. It
#' is removed from every history table (nflverse can publish partial in-game
#' stats) and from the schedule used for "previous game" features, so it is
#' neither a played nor a missed game. Target-week and later games are kept for
#' their pregame context. With all games final (every historical season) this is
#' a no-op.
drop_unfinished_games <- function(inputs, season, week) {
  target_gi <- game_index(season, week)
  # A game counts as complete only if it is final AND its stats have been
  # published (the schedule can mark a game final before player stats include it).
  # nflverse publishes a game's stats for both teams together, so check by game.
  tg <- inputs$team_games |>
    dplyr::mutate(game_final = .data$game_final & .data$game_id %in% unique(inputs$player_stats$game_id))
  inputs$team_games <- tg
  final <- dplyr::filter(tg, .data$game_final) |> dplyr::select("season", "week", "team")
  unfinished <- dplyr::filter(tg, !.data$game_final, game_index(.data$season, .data$week) < target_gi)
  inputs$unfinished_games <- dplyr::distinct(unfinished, .data$season, .data$week, .data$team)
  if (nrow(unfinished) == 0) return(inputs)
  keep_final <- function(d, team_col = "team") {
    dplyr::semi_join(d, dplyr::rename(final, !!team_col := "team"), by = c("season", "week", team_col))
  }
  inputs$player_stats <- keep_final(inputs$player_stats)
  inputs$snaps <- keep_final(inputs$snaps, "snap_team")
  inputs$pbp_usage <- keep_final(inputs$pbp_usage)
  inputs$xfp <- dplyr::semi_join(inputs$xfp, inputs$player_stats, by = c("season", "week", "gsis_id"))
  inputs$team_games <- dplyr::filter(tg, .data$game_final | game_index(.data$season, .data$week) >= target_gi)
  inputs$player_games <- build_player_games(inputs$player_stats, inputs$snaps, inputs$pbp_usage, inputs$xfp)
  inputs$team_volume <- build_team_volume(inputs$player_stats)
  inputs$defense_allowed <- build_defense_allowed(inputs$player_stats, inputs$team_games, position = "WR")
  inputs
}

#' Play-by-play aggregates for live M2/M3 features, restricted to final games.
live_pbp_histories <- function(inputs) {
  pbp <- inputs$pbp_paths
  final <- dplyr::filter(inputs$team_games, .data$game_final) |> dplyr::select("season", "week", "team")
  keep <- function(d, team_col = "team") {
    dplyr::semi_join(d, dplyr::rename(final, !!team_col := "team"), by = c("season", "week", team_col))
  }
  m2_histories(inputs$player_games, inputs$team_volume, inputs$defense_allowed,
               dplyr::semi_join(pbp_receiver_detail(pbp), inputs$player_stats, by = c("season", "week", "gsis_id")),
               inputs$pbp_usage, inputs$player_stats,
               keep(pbp_team_game(pbp)), keep(pbp_defense_game(pbp), "defense"), keep(pbp_qb_game(pbp)))
}

#' Training base restricted to FINAL games: an unplayed game must never be
#' labelled as 0 points.
final_games_only <- function(base, team_games) {
  final <- dplyr::filter(team_games, .data$game_final) |> dplyr::select("season", "week", "team")
  dplyr::semi_join(base, final, by = c("season", "week", "team"))
}

#' Target rows for the upcoming week from an ESPN snapshot: WRs ESPN projects
#' above 0, mapped to GSIS ids, with team from ESPN's live team id and game
#' context from the schedule.
prospective_targets <- function(snapshot, crosswalk, team_games, season, week) {
  snap <- snapshot |> dplyr::filter(.data$espn_position_id == ESPN_POSITION_IDS[["WR"]], .data$espn_proj > 0)
  mapped <- snap |>
    dplyr::inner_join(dplyr::filter(crosswalk, !is.na(.data$gsis_id)) |> dplyr::select("espn_id", "gsis_id"),
                      by = "espn_id", relationship = "many-to-one") |>
    dplyr::mutate(season = as.integer(season), week = as.integer(week),
                  team = espn_team(.data$espn_pro_team_id))
  ctx <- dplyr::select(team_games, "season", "week", "team", "game_id", "opponent", "home", "kickoff_utc",
                       "team_spread", "total_line", "implied_team_total", "rest_days")
  out <- dplyr::inner_join(mapped, ctx, by = c("season", "week", "team"), relationship = "many-to-one")
  attr(out, "excluded") <- tibble::tibble(
    projected = nrow(snap), unmatched_id = nrow(snap) - nrow(mapped),
    no_game_or_team = nrow(mapped) - nrow(out)
  )
  assert_unique_key(out, c("season", "week", "gsis_id"), "prospective targets")
}

#' Fit every frozen model of a lineage on rows strictly before the target week
#' and predict the target rows. Lineage-specific frame/feature builders are
#' looked up as `<lineage>_live_frames()`.
predict_lineage <- function(reg, inputs, targets, cfg) {
  builder <- get(paste0(tolower(reg$lineage), "_live_frames"), mode = "function")
  frames <- builder(reg, inputs, targets, cfg)
  cutoff <- min(frames$targets$game_index)
  specs <- registry_specs(reg)
  purrr::map(specs, function(spec) {
    train <- dplyr::filter(frames$train, .data$season >= reg$data$min_train_season, .data$game_index < cutoff)
    fit <- spec$fit(train)
    tibble::tibble(
      model_id = spec$name, lineage = reg$lineage, gsis_id = frames$targets$gsis_id,
      pred = spec$predict(fit, frames$targets),
      train_rows = nrow(train), train_max_game_index = max(train$game_index)
    )
  }) |>
    purrr::list_rbind()
}

#' M1 frames for a live run: M1's data vintage (history from 2019), its
#' population, completed games only; targets get M1 features.
m1_live_frames <- function(reg, inputs, targets, cfg) {
  base <- build_player_week_base(inputs$espn_weekly, inputs$crosswalk, inputs$player_stats, inputs$rosters,
                                 inputs$team_games, inputs$injuries, positions = cfg$positions) |>
    final_games_only(inputs$team_games)
  pw <- lineage_player_week(reg, base, inputs$player_games, inputs$team_volume, inputs$defense_allowed,
                            inputs$team_games, cfg$splits, cfg$evaluation$relevant_top_n)
  train <- frozen_frame(reg, pw, max_season = max(targets$season))

  hs <- reg$data$history_start_season
  keep <- function(d) dplyr::filter(d, .data$season >= hs)
  tg <- add_point_in_time_features(targets, keep(inputs$player_games), keep(inputs$team_volume),
                                   keep(inputs$defense_allowed), keep(inputs$team_games),
                                   windows = unlist(reg$data$feature_windows))
  list(train = train, targets = tg)
}

#' M2 frames for a live run: full M2 feature engine (history from 2017),
#' ESPN population from 2018, completed games only for training rows.
m2_live_frames <- function(reg, inputs, targets, cfg) {
  hist <- live_pbp_histories(inputs)
  static <- list(team_games = inputs$team_games, bio = player_bio(inputs$players))
  windows <- unlist(reg$data$feature_windows)
  base <- build_player_week_base(inputs$espn_weekly, inputs$crosswalk, inputs$player_stats, inputs$rosters,
                                 inputs$team_games, inputs$injuries, positions = cfg$positions) |>
    final_games_only(inputs$team_games) |>
    dplyr::filter(.data$has_game)
  pw <- add_m2_features(base, hist, static, windows) |>
    finalize_player_week(cfg$splits, cfg$evaluation$relevant_top_n)
  train <- m2_frame(pw, list(first_train_season = reg$data$min_train_season,
                             startable_top_n = cfg$m2$startable_top_n), max_season = max(targets$season))
  tg <- add_m2_features(targets, hist, static, windows) |>
    dplyr::mutate(dplyr::across(dplyr::all_of(setdiff(ESPN_COMPONENTS, "espn_proj")), ~ dplyr::coalesce(.x, 0)))
  list(train = train, targets = tg)
}

#' M3 frames: the M2 frames plus the point-in-time absence feature on targets
#' (the rule challengers' base calibration only needs ESPN components).
m3_live_frames <- function(reg, inputs, targets, cfg) {
  f <- m2_live_frames(reg, inputs, targets, cfg)
  f$targets <- add_absence_features(f$targets, inputs$player_games, inputs$team_games)
  f
}

#' M3b frames: M3 frames plus injury features from OUR captured injury report,
#' valid only if our retrieval happened before the player's kickoff.
m3b_live_frames <- function(reg, inputs, targets, cfg) {
  f <- m3_live_frames(reg, inputs, targets, cfg)
  path <- inputs$live_files[["injuries"]]
  captured <- parse_utc_stamp(sub("^retrieved_at=(.*)[.]parquet$", "\\1", basename(path)))
  inj <- pregame_injuries(path, inputs$team_games, captured_at = captured)
  f$targets <- add_injury_features(f$targets, inj, live_pbp_histories(inputs)$player_games_m2)
  f
}

#' M4 frames: M3 frames plus availability features from OUR captured injury
#' report (live_injury_detail(): own-kickoff timing and final-report rule).
m4_live_frames <- function(reg, inputs, targets, cfg) {
  f <- m3_live_frames(reg, inputs, targets, cfg)
  path <- inputs$live_files[["injuries"]]
  captured <- parse_utc_stamp(sub("^retrieved_at=(.*)[.]parquet$", "\\1", basename(path)))
  det <- live_injury_detail(path, inputs$team_games, captured, unique(targets$season), unique(targets$week))
  f$targets <- m4_add_features(f$targets, det, inputs$team_games)
  f
}

#' One official prospective run: refresh nothing itself (call
#' refresh_live_data() and snapshot_espn_projections() first), predict the
#' week with every requested frozen lineage, archive immutably, append the
#' manifest. Requires a clean git tree so predictions map to a commit.
run_prospective <- function(season, week, lineages = "m1", as_of = Sys.time(),
                            require_clean_git = TRUE, archive_root = "data/archive/predictions") {
  git <- git_state()
  if (require_clean_git && !isFALSE(git$dirty)) {
    cli::cli_abort("Official runs need a clean git tree (commit first) so predictions map to a commit.")
  }
  cfg <- read_project_config()
  snaps <- list_snapshots(season, week)
  snaps <- snaps[snaps$captured_at <= as_of, ]
  if (nrow(snaps) == 0) cli::cli_abort("No ESPN snapshot for {season} week {week} at or before {as_of}.")
  snap_path <- snaps$path[nrow(snaps)]
  snapshot <- arrow::read_parquet(snap_path)

  inputs <- assemble_live_inputs(cfg, season, as_of)
  inputs$crosswalk <- build_espn_crosswalk(
    dplyr::bind_rows(inputs$espn_weekly, dplyr::select(snapshot, "season", "week", "espn_id", "espn_name")),
    inputs$rosters, inputs$players, inputs$ff_playerids
  )
  targets <- prospective_targets(snapshot, inputs$crosswalk, inputs$team_games, season, week)
  if (any(targets$kickoff_utc <= as_of)) {
    cli::cli_warn("{sum(targets$kickoff_utc <= as_of)} target rows already kicked off; they will not count prospectively.")
  }
  inputs <- drop_unfinished_games(inputs, season, week)
  if (nrow(inputs$unfinished_games) > 0) {
    cli::cli_warn(c("Earlier games not yet final are treated as not played: {.val {unique(inputs$unfinished_games$team)}}.",
                    "i" = "Re-run after they are final for complete features."))
  }

  preds <- purrr::map(lineages, function(l) predict_lineage(read_registry(l), inputs, targets, cfg)) |>
    purrr::list_rbind() |>
    dplyr::left_join(dplyr::select(targets, "gsis_id", "espn_id", "espn_name", "team", "opponent", "game_id",
                                   "kickoff_utc", "espn_proj"), by = "gsis_id") |>
    dplyr::mutate(season = as.integer(season), week = as.integer(week), .before = 1)

  run_id <- utc_stamp(as_of)
  dir <- file.path(archive_root, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", run_id))
  stamp_cols <- list(run_id = run_id, predicted_at_utc = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                     snapshot_captured_at_utc = format(snaps$captured_at[nrow(snaps)], "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                     snapshot_sha256 = sha256_file(snap_path), git_commit = git$commit)
  preds <- dplyr::mutate(preds, !!!stamp_cols)
  pred_path <- write_once(file.path(dir, "predictions.parquet"), function(tmp) arrow::write_parquet(preds, tmp))
  meta <- c(stamp_cols, list(
    season = season, week = week, lineages = lineages, git_dirty = git$dirty,
    unfinished_earlier_games = paste(inputs$unfinished_games$season, inputs$unfinished_games$week,
                                     inputs$unfinished_games$team, sep = "-"),
    # exact frozen definitions used (their hashes are covered by run_meta_sha256)
    registry_sha256 = as.list(stats::setNames(
      vapply(lineages, function(l) sha256_file(read_registry(l)$path), character(1)), lineages)),
    snapshot_path = snap_path, live_files = as.list(inputs$live_files),
    live_sha256 = as.list(vapply(inputs$live_files, sha256_file, character(1))),
    espn_retro_files = length(espn_raw_files()),
    targets = nrow(targets), excluded = as.list(attr(targets, "excluded")),
    feature_cutoff_game_index = max(inputs$player_games$game_index),
    first_kickoff_utc = format(min(targets$kickoff_utc), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
  meta_path <- write_once(file.path(dir, "run_meta.json"), function(tmp) {
    jsonlite::write_json(meta, tmp, auto_unbox = TRUE, pretty = TRUE)
  })
  append_manifest(tibble::tibble(
    run_id = run_id, season = season, week = week, lineages = paste(lineages, collapse = "+"),
    models = paste(unique(preds$model_id), collapse = "+"), n_rows = nrow(preds),
    predicted_at_utc = stamp_cols$predicted_at_utc, first_kickoff_utc = meta$first_kickoff_utc,
    snapshot_captured_at_utc = stamp_cols$snapshot_captured_at_utc, snapshot_sha256 = stamp_cols$snapshot_sha256,
    predictions_sha256 = sha256_file(pred_path), run_meta_sha256 = sha256_file(meta_path),
    git_commit = git$commit
  ), PREDICTION_MANIFEST)
  list(path = pred_path, meta = meta, predictions = preds)
}
