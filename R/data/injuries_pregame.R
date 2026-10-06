# Point-in-time injury designations (Milestone 3, hypothesis C) -------------------------
# Historical rows are used ONLY when their own timestamp shows they existed
# before the team's kickoff:
#   2017-2024: nflverse `date_modified` (last modification of the player's weekly
#              final report). 2017-2020 values are US Pacific wall-clock times
#              stored as UTC (verified: they cluster at Friday 07:00 PT and shift
#              with US daylight time), so they are re-read as Pacific.
#   2025:      no timestamp column -> excluded from history (not backfilled).
#   2026+:     prospective only; the timestamp is OUR dated live retrieval time.
# See docs/source_feasibility.csv.

#' Pregame-valid injury designations: one row per (season, week, gsis_id) with
#' report_status and the time it is known to have existed. Rows whose time is
#' not strictly before the team's kickoff are dropped and counted.
pregame_injuries <- function(paths, team_games, captured_at = NULL, season_type = "REG") {
  raw <- read_parquet_files(paths) |>
    dplyr::filter(.data$game_type == !!season_type, !is.na(.data$gsis_id), !is.na(.data$report_status))
  has_dm <- "date_modified" %in% names(raw)
  raw <- raw |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      team = standardize_team(.data$team), gsis_id = .data$gsis_id, report_status = .data$report_status,
      known_at = if (has_dm) as.POSIXct(.data$date_modified, tz = "UTC") else as.POSIXct(NA, tz = "UTC")
    )
  if (has_dm) {
    early <- raw$season <= 2020
    raw$known_at[early] <- as.POSIXct(format(raw$known_at[early], "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                                      tz = "America/Los_Angeles")
  } else if (!is.null(captured_at)) {
    raw$known_at <- captured_at        # prospective capture: our retrieval time
  }
  kick <- dplyr::select(team_games, "season", "week", "team", "kickoff_utc")
  d <- dplyr::left_join(raw, kick, by = c("season", "week", "team"))
  valid <- !is.na(d$known_at) & !is.na(d$kickoff_utc) & d$known_at < d$kickoff_utc
  out <- d[valid, ] |>
    dplyr::mutate(severity = match(.data$report_status, c("Out", "Doubtful", "Questionable", "Note"))) |>
    dplyr::arrange(.data$severity) |>
    dplyr::distinct(.data$season, .data$week, .data$gsis_id, .keep_all = TRUE) |>
    dplyr::select("season", "week", "team", "gsis_id", "report_status", "known_at")
  attr(out, "dropped") <- tibble::tibble(rows = nrow(d), not_pregame_or_untimed = sum(!valid))
  out
}

#' Own designation and vacated opportunity per target row. Vacated shares sum
#' the PREGAME (as-of) target-share and xFP EWMAs of teammates designated Out
#' or Doubtful for that game, excluding the player.
add_injury_features <- function(targets, injuries, player_games_m2) {
  t <- dplyr::mutate(targets, game_index = game_index(.data$season, .data$week))
  own <- dplyr::select(injuries, "season", "week", "gsis_id", own_status = "report_status")
  out_tm <- injuries |>
    dplyr::filter(.data$report_status %in% c("Out", "Doubtful")) |>
    dplyr::mutate(game_index = game_index(.data$season, .data$week))
  states <- player_states_m2(player_games_m2) |>
    dplyr::select("gsis_id", "state_index", "target_share_ewma6", "xfp_ewma6")
  vac <- out_tm |>
    asof_join(states, by = "gsis_id", what = "injured teammate state") |>
    dplyr::mutate(dplyr::across(c("target_share_ewma6", "xfp_ewma6"), ~ dplyr::coalesce(.x, 0)))
  team_vac <- dplyr::summarise(vac, vac_ts = sum(.data$target_share_ewma6), vac_xfp = sum(.data$xfp_ewma6),
                               .by = c("season", "week", "team"))
  self <- dplyr::select(vac, "season", "week", "gsis_id", self_ts = "target_share_ewma6", self_xfp = "xfp_ewma6")
  t |>
    safe_left_join(own, by = c("season", "week", "gsis_id"), what = "own injury") |>
    safe_left_join(team_vac, by = c("season", "week", "team"), what = "team vacated") |>
    safe_left_join(self, by = c("season", "week", "gsis_id"), what = "self vacated") |>
    dplyr::mutate(
      vacated_target_share = dplyr::coalesce(.data$vac_ts, 0) - dplyr::coalesce(.data$self_ts, 0),
      vacated_xfp = dplyr::coalesce(.data$vac_xfp, 0) - dplyr::coalesce(.data$self_xfp, 0),
      own_questionable = .data$own_status %in% "Questionable",
      own_doubtful = .data$own_status %in% "Doubtful"
    ) |>
    dplyr::select(-"vac_ts", -"vac_xfp", -"self_ts", -"self_xfp", -"own_status")
}
