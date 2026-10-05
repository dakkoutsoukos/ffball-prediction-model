# Player-week dataset ----------------------------------------------------------------
# One row per (season, week, gsis_id) for players at the configured positions.
# Schema and population definitions: docs/player_week_schema.md.

#' Candidate universe + targets + pregame context, before features.
#'
#' Universe = union of (a) weekly-roster players at the position who were on
#' the game-day roster (ACT or INA), (b) players with a stat line at the
#' position, (c) ESPN-projected players at the position (when ESPN data exist).
#' Rows are never silently dropped: rows without a team game that week are
#' kept with `has_game = FALSE` and excluded later with counts reported.
build_player_week_base <- function(espn_weekly, espn_crosswalk, player_stats, rosters_weekly,
                                   team_games, injuries, positions = "WR") {
  keys <- c("season", "week", "gsis_id")

  espn <- espn_weekly |>
    dplyr::filter(.data$espn_position_id %in% unname(ESPN_POSITION_IDS[positions])) |>
    dplyr::inner_join(
      dplyr::filter(espn_crosswalk, !is.na(.data$gsis_id)) |> dplyr::select("espn_id", "gsis_id", "match_method"),
      by = "espn_id", relationship = "many-to-one"
    ) |>
    dplyr::mutate(espn_position = names(ESPN_POSITION_IDS)[match(.data$espn_position_id, ESPN_POSITION_IDS)]) |>
    dplyr::select(dplyr::all_of(keys), "espn_id", "espn_name", "espn_position", "espn_proj",
                  "espn_actual", dplyr::starts_with("espn_proj_"), espn_match_method = "match_method") |>
    assert_unique_key(keys, "espn rows")

  roster <- dplyr::filter(rosters_weekly, .data$roster_position %in% positions,
                          .data$roster_status %in% c("ACT", "INA"))
  stats_pos <- dplyr::filter(player_stats, .data$stats_position %in% positions)
  universe <- dplyr::bind_rows(
    dplyr::select(roster, dplyr::all_of(keys)),
    dplyr::select(stats_pos, dplyr::all_of(keys)),
    dplyr::select(espn, dplyr::all_of(keys))
  ) |>
    dplyr::distinct()

  stat_cols <- dplyr::select(
    player_stats, dplyr::all_of(keys), stat_name = "player_name", "stats_position",
    stat_team = "team", stat_opponent = "opponent", actual_pts = "fantasy_pts",
    actual_targets = "targets", actual_receptions = "receptions",
    actual_receiving_yards = "receiving_yards", actual_receiving_tds = "receiving_tds"
  )
  roster_cols <- dplyr::select(rosters_weekly, dplyr::all_of(keys), "roster_name", "roster_team",
                               "roster_position", "roster_status")
  inj <- injuries |>
    dplyr::transmute(.data$season, .data$week, .data$gsis_id,
                     inj_out = .data$report_status %in% "Out",
                     inj_doubtful = .data$report_status %in% "Doubtful",
                     inj_questionable = .data$report_status %in% "Questionable")
  context <- dplyr::select(team_games, "season", "week", "team", "game_id", "opponent", "home",
                           "kickoff", "team_spread", "total_line", "implied_team_total", "rest_days")

  out <- universe |>
    safe_left_join(stat_cols, by = keys, what = "universe+stats") |>
    safe_left_join(roster_cols, by = keys, what = "universe+rosters") |>
    safe_left_join(espn, by = keys, what = "universe+espn") |>
    safe_left_join(inj, by = keys, what = "universe+injuries") |>
    dplyr::mutate(
      team = dplyr::coalesce(.data$stat_team, .data$roster_team),
      player_name = dplyr::coalesce(.data$stat_name, .data$roster_name, .data$espn_name),
      position = dplyr::coalesce(.data$espn_position, .data$roster_position, .data$stats_position),
      has_stat_line = !is.na(.data$actual_pts),
      dplyr::across(c("inj_out", "inj_doubtful", "inj_questionable"), ~ dplyr::coalesce(.x, FALSE))
    ) |>
    safe_left_join(context, by = c("season", "week", "team"), what = "universe+schedule") |>
    dplyr::mutate(
      has_game = !is.na(.data$game_id),
      # A player with a team game but no stat line scored 0.
      actual = dplyr::if_else(.data$has_game, dplyr::coalesce(.data$actual_pts, 0), NA_real_)
    )

  # Consistency: a stat line's opponent must equal the schedule's opponent.
  bad <- dplyr::filter(out, .data$has_stat_line, .data$stat_opponent != .data$opponent)
  if (nrow(bad) > 0) cli::cli_abort("player_week: {nrow(bad)} stat lines disagree with the schedule opponent.")

  out |>
    dplyr::select(-"stat_team", -"stat_name", -"stat_opponent", -"roster_team", -"roster_name",
                  -"actual_pts", -"stats_position", -"roster_position") |>
    assert_unique_key(keys, "player_week_base") |>
    assert_in_range("espn_proj", 0, 80, "player_week_base")
}

#' Add splits and pregame-defined evaluation populations.
#'   pop_espn    ESPN projected the player for > 0 points (primary population)
#'   pop_active  player was on the game-day active roster (ESPN-free population;
#'               known ~90 minutes before kickoff, never used as a feature)
#'   relevant    pop_espn and in the top-N ESPN projections that week
finalize_player_week <- function(df, splits, top_n = 60) {
  df |>
    dplyr::filter(.data$has_game) |>
    dplyr::mutate(
      split = season_split(.data$season, splits),
      pop_espn = !is.na(.data$espn_proj) & .data$espn_proj > 0,
      pop_active = .data$roster_status %in% "ACT"
    ) |>
    dplyr::mutate(
      espn_rank = dplyr::if_else(.data$pop_espn, rank(-.data$espn_proj, ties.method = "first"), NA_real_),
      .by = c("season", "week")
    ) |>
    dplyr::mutate(relevant = .data$pop_espn & .data$espn_rank <= top_n) |>
    dplyr::arrange(.data$season, .data$week, .data$gsis_id)
}

#' Run the empirical leakage check on the real dataset; fail the pipeline on
#' any leaking feature.
assert_no_leakage <- function(base, player_games, team_volume, defense_allowed, team_games) {
  targets <- dplyr::filter(base, .data$has_game) |>
    dplyr::select("season", "week", "gsis_id", "team", "opponent")
  leaks <- check_feature_leakage(targets, player_games, team_volume, defense_allowed,
                                 team_games, n_cutoffs = 12)
  if (length(leaks) > 0) cli::cli_abort("Feature leakage detected in: {.val {leaks}}.")
  tibble::tibble(checked_at = Sys.time(), n_cutoffs = 12, leaking_features = 0L)
}

#' Coverage, exclusions, missingness and ID-match audit for the dataset.
audit_player_week <- function(player_week, base, espn_weekly, espn_crosswalk, positions = "WR") {
  espn_pos <- espn_weekly |>
    dplyr::filter(.data$espn_position_id %in% unname(ESPN_POSITION_IDS[positions])) |>
    dplyr::left_join(dplyr::select(espn_crosswalk, "espn_id", "match_method"), by = "espn_id")
  list(
    # Output names are prefixed n_ so they never mask the input columns that
    # later expressions in the same summarise() refer to.
    by_season = player_week |>
      dplyr::summarise(
        n_rows = dplyr::n(), n_pop_espn = sum(.data$pop_espn), n_pop_active = sum(.data$pop_active),
        n_relevant = sum(.data$relevant), n_with_stat_line = sum(.data$has_stat_line),
        n_espn_projected_no_stat_line = sum(.data$pop_espn & !.data$has_stat_line),
        n_espn_projected_actual_zero = sum(.data$pop_espn & .data$actual == 0),
        n_stat_line_not_espn_projected = sum(.data$has_stat_line & !.data$pop_espn),
        n_pop_espn_no_history = sum(.data$pop_espn & !.data$has_history),
        .by = c("season", "split")
      ),
    excluded_no_game = base |>
      dplyr::filter(!.data$has_game) |>
      dplyr::summarise(rows = dplyr::n(),
                       espn_proj_positive = sum(.data$espn_proj > 0, na.rm = TRUE),
                       .by = "season"),
    espn_match = espn_pos |>
      dplyr::mutate(projected = !is.na(.data$espn_proj) & .data$espn_proj > 0) |>
      dplyr::count(.data$season, .data$projected, .data$match_method),
    espn_unmatched_projected = espn_pos |>
      dplyr::filter(.data$espn_proj > 0, .data$match_method %in% c("ambiguous", "unmatched")) |>
      dplyr::select("season", "week", "espn_id", "espn_name", "espn_proj", "match_method"),
    missingness = missingness_report(player_week)
  )
}

#' Write the analysis dataset to Parquet and register it in a DuckDB file for
#' ad-hoc SQL. Both files are regenerable and git-ignored.
export_player_week <- function(player_week, parquet_path, duckdb_path) {
  dir.create(dirname(parquet_path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(player_week, parquet_path)
  if (file.exists(duckdb_path)) file.remove(duckdb_path)
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = duckdb_path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE player_week_wr AS SELECT * FROM read_parquet('%s')",
    normalizePath(parquet_path, winslash = "/")
  ))
  c(parquet_path, duckdb_path)
}
