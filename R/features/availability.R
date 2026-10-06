# Milestone 4 availability features --------------------------------------------------------
# Built on the official weekly injury report (one FINAL row per player-week):
# game designation, final practice status, body part. Rows are used only if
# their own timestamp precedes the team's kickoff (same rules as M3b's
# pregame_injuries(), which stays untouched because M3b is frozen):
#   2017-2024 date_modified (2017-2020 re-read as US Pacific), 2025 excluded,
#   2026 our capture time. No within-week practice sequence exists historically.

normalize_practice <- function(x) {
  dplyr::case_when(grepl("Did Not", x) ~ "DNP", grepl("Limited", x) ~ "LP", grepl("Full", x) ~ "FP",
                   TRUE ~ NA_character_)
}

#' Broad body-part groups only (no fine categories: samples are small).
body_group <- function(x) {
  x <- tolower(trimws(x))
  dplyr::case_when(
    is.na(x) | x == "" ~ NA_character_,
    grepl("concussion|head", x) ~ "head",
    grepl("illness|not injury|personal|rest|covid", x) ~ "non_injury",
    grepl("hamstring|knee|ankle|foot|toe|calf|groin|hip|quad|thigh|achilles|heel|shin|leg|glute", x) ~ "lower",
    grepl("shoulder|hand|wrist|finger|thumb|elbow|arm|rib|chest|back|neck|abdom|oblique|pectoral", x) ~ "upper",
    TRUE ~ "other"
  )
}

DESIGNATION_SEVERITY <- c("Out", "Doubtful", "Questionable", "Note", "listed_only")

#' Pregame-valid injury-report detail: one row per (season, week, gsis_id),
#' including players listed WITHOUT a game designation. `captured_at` is used
#' when the file has no date_modified (2026 live captures). Diagnostics on
#' dropped rows are attached as attribute "coverage".
pregame_injury_detail <- function(paths, team_games, captured_at = NULL, season_type = "REG") {
  raw <- read_parquet_files(paths) |>
    dplyr::filter(.data$game_type == !!season_type)
  has_dm <- "date_modified" %in% names(raw)
  d <- raw |>
    dplyr::transmute(
      season = as.integer(.data$season), week = as.integer(.data$week),
      team = standardize_team(.data$team), gsis_id = .data$gsis_id, position = .data$position,
      designation = dplyr::coalesce(.data$report_status, "listed_only"),
      practice = normalize_practice(.data$practice_status),
      body = body_group(dplyr::coalesce(.data$report_primary_injury, .data$practice_primary_injury)),
      known_at = if (has_dm) as.POSIXct(.data$date_modified, tz = "UTC") else as.POSIXct(NA, tz = "UTC")
    )
  if (has_dm) {
    early <- d$season <= 2020
    d$known_at[early] <- as.POSIXct(format(d$known_at[early], "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                                    tz = "America/Los_Angeles")
  } else if (!is.null(captured_at)) {
    d$known_at <- captured_at
  }
  d <- dplyr::left_join(d, dplyr::select(team_games, "season", "week", "team", "kickoff_utc"),
                        by = c("season", "week", "team"))
  d$status <- dplyr::case_when(
    is.na(d$gsis_id) ~ "no_player_id",
    is.na(d$kickoff_utc) ~ "no_game_on_schedule",
    is.na(d$known_at) ~ "untimed",
    d$known_at >= d$kickoff_utc ~ "after_kickoff",
    TRUE ~ "valid"
  )
  coverage <- dplyr::count(d, .data$season, .data$status, name = "rows")
  out <- d |>
    dplyr::filter(.data$status == "valid") |>
    dplyr::mutate(sev = match(.data$designation, DESIGNATION_SEVERITY)) |>
    dplyr::arrange(.data$sev, dplyr::desc(.data$known_at)) |>
    dplyr::distinct(.data$season, .data$week, .data$gsis_id, .keep_all = TRUE) |>
    dplyr::select("season", "week", "team", "gsis_id", "position", "designation", "practice", "body", "known_at")
  attr(out, "coverage") <- coverage
  out
}

#' Availability features for target rows (season, week, gsis_id, team).
#' This week: the pregame-valid report for the target week. Trajectory: the
#' player's reports for the team's PREVIOUS games (strictly earlier weeks).
add_availability_features <- function(targets, detail, team_games) {
  gi <- game_index(targets$season, targets$week)
  this <- dplyr::select(detail, "season", "week", "gsis_id", "designation", "practice", "body")
  out <- targets |>
    dplyr::left_join(this, by = c("season", "week", "gsis_id"), relationship = "many-to-one") |>
    dplyr::mutate(
      listed = !is.na(.data$designation),
      designation = dplyr::coalesce(.data$designation, "none"),
      practice = dplyr::coalesce(.data$practice, "none"),
      body = dplyr::coalesce(.data$body, "none")
    )
  # Previous team games (schedule) and the player's earlier report weeks.
  sched <- dplyr::distinct(dplyr::transmute(team_games, team = .data$team,
                                            sgi = game_index(.data$season, .data$week)))
  sched_by <- split(sched$sgi, sched$team)
  rep <- dplyr::transmute(detail, gsis_id = .data$gsis_id, rgi = game_index(.data$season, .data$week),
                          rdes = .data$designation)
  rep_by <- split(rep, rep$gsis_id)
  empty <- rep[0, ]
  prev <- purrr::pmap(list(out$gsis_id, out$team, gi), function(id, tm, g) {
    s <- sched_by[[tm]] %||% integer()
    team_prev <- sort(s[s < g], decreasing = TRUE)
    mine <- rep_by[[id]] %||% empty
    mine <- mine[mine$rgi < g, ]
    if (length(team_prev) == 0) return(list(prev_designation = "none", weeks_listed_streak = 0L))
    last_des <- mine$rdes[match(team_prev[1], mine$rgi)]
    streak <- 0L
    for (t in team_prev) if (t %in% mine$rgi) streak <- streak + 1L else break
    list(prev_designation = dplyr::coalesce(last_des, "none"), weeks_listed_streak = streak)
  })
  out$prev_designation <- purrr::map_chr(prev, "prev_designation")
  out$weeks_listed_streak <- purrr::map_int(prev, "weeks_listed_streak")
  out
}

#' Coverage diagnostic: valid vs dropped injury rows by season and reason.
injury_coverage_report <- function(detail) {
  attr(detail, "coverage") |>
    tidyr::pivot_wider(names_from = "status", values_from = "rows", values_fill = 0)
}
