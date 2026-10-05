# Play-by-play aggregates for Milestone 2 features --------------------------------
# All aggregates are per completed game and computed in DuckDB directly from the
# nflverse play-by-play parquet files. They are outcomes of the game they
# summarise, so they are ONLY ever used as lagged history (as-of joins on
# strictly earlier games; see R/features/m2_features.R).

pbp_query <- function(pbp_paths, select_sql) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  files <- paste0("'", normalizePath(pbp_paths, winslash = "/"), "'", collapse = ", ")
  DBI::dbExecute(con, sprintf(
    "CREATE VIEW pbp AS SELECT * FROM read_parquet([%s], union_by_name = true) WHERE season_type = 'REG'", files
  ))
  tibble::as_tibble(DBI::dbGetQuery(con, select_sql))
}

#' Receiver detail per player-game: deep targets, air yards, yards after catch.
pbp_receiver_detail <- function(pbp_paths) {
  pbp_query(pbp_paths, "
    SELECT CAST(season AS INTEGER) AS season, CAST(week AS INTEGER) AS week,
           receiver_player_id AS gsis_id,
           COUNT(*) FILTER (WHERE air_yards >= 20) AS deep_targets,
           SUM(CASE WHEN complete_pass = 1 THEN COALESCE(yards_after_catch, 0) ELSE 0 END) AS yac
    FROM pbp
    WHERE play_type = 'pass' AND pass_attempt = 1 AND sack = 0
      AND COALESCE(two_point_attempt, 0) = 0 AND receiver_player_id IS NOT NULL
    GROUP BY ALL") |>
    assert_unique_key(c("season", "week", "gsis_id"), "pbp_receiver_detail")
}

#' Offensive environment per team-game. Neutral situation = 1st/2nd down,
#' win probability 20-80%, more than 2 minutes left in the half.
pbp_team_game <- function(pbp_paths) {
  pbp_query(pbp_paths, "
    SELECT CAST(season AS INTEGER) AS season, CAST(week AS INTEGER) AS week, posteam AS team,
           COUNT(*) FILTER (WHERE play_type IN ('pass', 'run')) AS plays,
           SUM(COALESCE(qb_dropback, 0)) AS dropbacks,
           AVG(CASE WHEN qb_dropback = 1 THEN epa END) AS pass_epa_per_db,
           AVG(CASE WHEN down IN (1, 2) AND wp BETWEEN 0.2 AND 0.8 AND half_seconds_remaining > 120
                     AND play_type IN ('pass', 'run') THEN qb_dropback END) AS neutral_pass_rate
    FROM pbp
    WHERE posteam IS NOT NULL AND COALESCE(two_point_attempt, 0) = 0
    GROUP BY ALL") |>
    dplyr::mutate(team = standardize_team(.data$team)) |>
    assert_no_missing("team", "pbp_team_game") |>
    assert_unique_key(c("season", "week", "team"), "pbp_team_game")
}

#' Pass defence per team-game: dropbacks faced and EPA allowed per dropback.
pbp_defense_game <- function(pbp_paths) {
  pbp_query(pbp_paths, "
    SELECT CAST(season AS INTEGER) AS season, CAST(week AS INTEGER) AS week, defteam AS defense,
           SUM(COALESCE(qb_dropback, 0)) AS db_faced,
           SUM(CASE WHEN qb_dropback = 1 THEN epa ELSE 0 END) AS pass_epa_allowed_sum
    FROM pbp
    WHERE defteam IS NOT NULL AND COALESCE(two_point_attempt, 0) = 0
    GROUP BY ALL") |>
    dplyr::mutate(defense = standardize_team(.data$defense)) |>
    assert_no_missing("defense", "pbp_defense_game") |>
    assert_unique_key(c("season", "week", "defense"), "pbp_defense_game")
}

#' Every quarterback's dropbacks and EPA per team-game, plus a `starter` flag
#' for the team's dropback leader in that game (known only after the game, so
#' it is used for LAGGED QB context only: the QB of the team's previous game).
pbp_qb_game <- function(pbp_paths) {
  pbp_query(pbp_paths, "
    WITH qb AS (
      SELECT CAST(season AS INTEGER) AS season, CAST(week AS INTEGER) AS week, posteam AS team,
             COALESCE(passer_player_id, rusher_player_id) AS qb_id,
             COUNT(*) AS dropbacks, SUM(COALESCE(epa, 0)) AS epa_sum
      FROM pbp
      WHERE qb_dropback = 1 AND COALESCE(two_point_attempt, 0) = 0 AND posteam IS NOT NULL
      GROUP BY ALL
    )
    SELECT *, ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY dropbacks DESC, qb_id) = 1 AS starter
    FROM qb WHERE qb_id IS NOT NULL") |>
    dplyr::mutate(team = standardize_team(.data$team)) |>
    assert_no_missing("team", "pbp_qb_game") |>
    assert_unique_key(c("season", "week", "team", "qb_id"), "pbp_qb_game")
}
