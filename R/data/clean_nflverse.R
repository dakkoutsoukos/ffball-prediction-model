# Clean nflverse data ------------------------------------------------------------
# Turns raw nflverse files into validated tables keyed on stable IDs:
#   player stats  (season, week, gsis_id)   all positions, so team totals are complete
#   team games    (season, week, team)      schedule context, one row per team-game
#   snaps         (season, week, gsis_id)
#   injuries      (season, week, gsis_id)
#   pbp usage     (season, week, gsis_id)   red-zone targets, via DuckDB
#   xfp           (season, week, gsis_id)
# Regular season only (config: season_type).

PLAYER_STAT_COLS <- c(
  "completions", "attempts", "passing_yards", "passing_tds", "passing_interceptions",
  "passing_2pt_conversions", "sack_fumbles_lost",
  "carries", "rushing_yards", "rushing_tds", "rushing_2pt_conversions", "rushing_fumbles_lost",
  "targets", "receptions", "receiving_yards", "receiving_tds", "receiving_2pt_conversions",
  "receiving_fumbles_lost", "receiving_air_yards", "special_teams_tds", "fumble_recovery_tds",
  "fantasy_points_ppr"
)

clean_player_stats <- function(paths, scoring_rules, season_type = "REG") {
  df <- read_parquet_files(paths) |>
    dplyr::filter(.data$season_type == !!season_type) |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      game_id = .data$game_id, gsis_id = .data$player_id,
      player_name = .data$player_display_name, stats_position = .data$position,
      team = .data$team, opponent = .data$opponent_team,
      dplyr::across(dplyr::all_of(PLAYER_STAT_COLS), as.numeric)
    ) |>
    dplyr::rename(nflverse_ppr = "fantasy_points_ppr")

  df$fantasy_pts <- score_fantasy_points(df, scoring_rules)

  df |>
    assert_no_missing(c("season", "week", "gsis_id", "team", "game_id"), "player_stats") |>
    assert_unique_key(c("season", "week", "gsis_id"), "player_stats") |>
    assert_in_range("week", 1, 18, "player_stats") |>
    assert_in_range("targets", 0, Inf, "player_stats") |>
    assert_in_range("receptions", 0, Inf, "player_stats")
}

#' One row per team per regular-season game, with pregame game context.
#'
#' Vegas fields are nflverse's schedule lines, which are (approximately)
#' closing lines: valid only for predictions made at/near kickoff. See
#' docs/point_in_time_rules.md.
clean_team_games <- function(paths, season_type = "REG") {
  sch <- read_parquet_files(paths) |>
    dplyr::filter(.data$game_type == !!season_type)

  side <- function(is_home) {
    sch |>
      dplyr::transmute(
        season = as.integer(.data$season), week = as.integer(.data$week),
        game_id = .data$game_id,
        team = if (is_home) .data$home_team else .data$away_team,
        opponent = if (is_home) .data$away_team else .data$home_team,
        home = is_home & .data$location != "Neutral",
        kickoff = paste(.data$gameday, .data$gametime),
        # spread_line > 0 means the home team is favored by that many points
        team_spread = if (is_home) .data$spread_line else -.data$spread_line,
        total_line = .data$total_line,
        rest_days = if (is_home) .data$home_rest else .data$away_rest
      )
  }
  dplyr::bind_rows(side(TRUE), side(FALSE)) |>
    dplyr::mutate(
      implied_team_total = (.data$total_line + .data$team_spread) / 2,
      game_index = game_index(.data$season, .data$week)
    ) |>
    dplyr::arrange(.data$season, .data$week, .data$team) |>
    assert_unique_key(c("season", "week", "team"), "team_games") |>
    assert_unique_key(c("game_id", "team"), "team_games")
}

#' Chronological index for (season, week): later games always compare greater.
game_index <- function(season, week) as.integer(season) * 100L + as.integer(week)

#' gsis_id <-> pfr_id map from the nflverse player master. Ambiguous ids dropped.
pfr_gsis_map <- function(players) {
  players |>
    dplyr::filter(!is.na(.data$pfr_id), !is.na(.data$gsis_id)) |>
    dplyr::distinct(.data$pfr_id, .data$gsis_id) |>
    dplyr::add_count(.data$pfr_id, name = "n_pfr") |>
    dplyr::add_count(.data$gsis_id, name = "n_gsis") |>
    dplyr::filter(.data$n_pfr == 1, .data$n_gsis == 1) |>
    dplyr::select("pfr_id", "gsis_id")
}

clean_snap_counts <- function(paths, players, season_type = "REG") {
  idmap <- pfr_gsis_map(players)
  snaps <- read_parquet_files(paths) |>
    dplyr::filter(.data$game_type == !!season_type, .data$offense_snaps > 0) |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      pfr_id = .data$pfr_player_id, snap_team = .data$team,
      offense_snaps = as.numeric(.data$offense_snaps),
      snap_share = as.numeric(.data$offense_pct)
    ) |>
    assert_in_range("snap_share", 0, 1, "snap_counts")

  out <- dplyr::inner_join(snaps, idmap, by = "pfr_id", relationship = "many-to-one")
  attr(out, "unmapped_frac") <- 1 - nrow(out) / nrow(snaps)
  out |>
    dplyr::select(-"pfr_id") |>
    assert_unique_key(c("season", "week", "gsis_id"), "snap_counts")
}

#' Final weekly injury-report designation (Out/Doubtful/Questionable).
#' Reports are published before the game; nflverse provides no capture
#' timestamp, so this is treated as "pregame, final report" (see docs).
clean_injuries <- function(paths, season_type = "REG") {
  read_parquet_files(paths) |>
    dplyr::filter(.data$game_type == !!season_type, !is.na(.data$gsis_id)) |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      gsis_id = .data$gsis_id, report_status = .data$report_status
    ) |>
    # A handful of players appear twice in a week (e.g. traded mid-week);
    # keep the most severe designation.
    dplyr::mutate(severity = match(.data$report_status, c("Out", "Doubtful", "Questionable"))) |>
    dplyr::arrange(.data$severity) |>
    dplyr::distinct(.data$season, .data$week, .data$gsis_id, .keep_all = TRUE) |>
    dplyr::select(-"severity")
}

#' Expected fantasy points (ffopportunity). The ffopportunity models were fit
#' on historical seasons; we only ever use *lagged* xFP as a feature.
clean_ff_opportunity <- function(paths, season_type = "REG") {
  read_parquet_files(paths) |>
    dplyr::filter(!is.na(.data$player_id)) |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      gsis_id = .data$player_id,
      xfp = as.numeric(.data$total_fantasy_points_exp)
    ) |>
    dplyr::summarise(xfp = sum(.data$xfp, na.rm = TRUE), .by = c("season", "week", "gsis_id"))
}

#' Red-zone and end-zone targets per player-game, aggregated in DuckDB
#' directly from the play-by-play parquet files (never loaded fully into R).
pbp_target_usage <- function(pbp_paths, season_type = "REG") {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  files <- paste0("'", normalizePath(pbp_paths, winslash = "/"), "'", collapse = ", ")
  sql <- sprintf("
    SELECT CAST(season AS INTEGER) AS season, CAST(week AS INTEGER) AS week,
           posteam AS team, receiver_player_id AS gsis_id,
           COUNT(*) AS pbp_targets,
           COUNT(*) FILTER (WHERE yardline_100 <= 20) AS rz_targets,
           COUNT(*) FILTER (WHERE yardline_100 <= 10) AS inside10_targets,
           COUNT(*) FILTER (WHERE air_yards >= yardline_100) AS endzone_targets
    FROM read_parquet([%s], union_by_name = true)
    WHERE season_type = '%s' AND play_type = 'pass' AND pass_attempt = 1
      AND sack = 0 AND COALESCE(two_point_attempt, 0) = 0
      AND receiver_player_id IS NOT NULL
    GROUP BY ALL", files, season_type)
  tibble::as_tibble(DBI::dbGetQuery(con, sql)) |>
    assert_unique_key(c("season", "week", "gsis_id"), "pbp_target_usage")
}
