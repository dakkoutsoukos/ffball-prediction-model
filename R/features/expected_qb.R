# Expected starting QB (prospective-only feature) -----------------------------------------
# nflverse's live schedule lists the EXPECTED starting QB of upcoming games a few
# days before kickoff. Our dated live retrievals of that file therefore give a
# timestamped pregame record of the expected starter. This feature is
# PROSPECTIVE-ONLY: the current schedule file is overwritten after games, so
# history cannot be reconstructed from it (git history is a separate question,
# see docs/source_feasibility.csv). No frozen model uses it yet.

#' Expected starter per team for a target week, from ONE captured schedule file,
#' compared with the team's actual starter in its previous final game.
#' Valid only if the capture time precedes the team's kickoff.
expected_qb_features <- function(schedule_capture, captured_at, qb_game, season, week) {
  s <- schedule_capture |>
    dplyr::filter(.data$season == !!season, .data$week == !!week, .data$game_type == "REG")
  ko <- kickoff_to_utc(s$gameday, s$gametime)
  sides <- dplyr::bind_rows(
    tibble::tibble(team = standardize_team(s$home_team), expected_qb_id = s$home_qb_id, kickoff_utc = ko),
    tibble::tibble(team = standardize_team(s$away_team), expected_qb_id = s$away_qb_id, kickoff_utc = ko)
  ) |>
    dplyr::filter(captured_at < .data$kickoff_utc)            # pregame captures only
  gi <- game_index(season, week)
  last <- qb_game |>
    dplyr::filter(.data$starter, game_index(.data$season, .data$week) < gi) |>
    dplyr::mutate(gi = game_index(.data$season, .data$week)) |>
    dplyr::slice_max(.data$gi, n = 1, with_ties = FALSE, by = "team") |>
    dplyr::select("team", last_starter_id = "qb_id")
  starts <- qb_game |>
    dplyr::filter(.data$starter, game_index(.data$season, .data$week) < gi) |>
    dplyr::count(.data$qb_id, name = "prior_starts")
  sides |>
    dplyr::left_join(last, by = "team") |>
    dplyr::left_join(starts, by = c(expected_qb_id = "qb_id")) |>
    dplyr::mutate(
      season = as.integer(season), week = as.integer(week), captured_at = captured_at,
      prior_starts = dplyr::coalesce(.data$prior_starts, 0L),
      expected_qb_change = !is.na(.data$expected_qb_id) & !is.na(.data$last_starter_id) &
        .data$expected_qb_id != .data$last_starter_id
    )
}
