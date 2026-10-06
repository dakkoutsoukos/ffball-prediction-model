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
  # Missing states are kept distinct (rules treat all non-listed rows alike,
  # but diagnostics must not call them all "healthy"):
  #   listed / not_listed (the team's valid report exists, player not on it) /
  #   no_team_report (no valid row for the team-week: missing, late, or a live
  #   final report not out yet) / source_missing (no valid report that season).
  tw <- dplyr::mutate(dplyr::distinct(detail, .data$season, .data$week, .data$team), .tw = TRUE)
  out <- dplyr::left_join(out, tw, by = c("season", "week", "team"))
  out$report_state <- dplyr::case_when(
    out$listed ~ "listed",
    !out$season %in% detail$season ~ "source_missing",
    out$.tw %in% TRUE ~ "not_listed",
    TRUE ~ "no_team_report"
  )
  out$.tw <- NULL
  out
}

#' Coverage diagnostic: valid vs dropped injury rows by season and reason.
injury_coverage_report <- function(detail) {
  attr(detail, "coverage") |>
    tidyr::pivot_wider(names_from = "status", values_from = "rows", values_fill = 0)
}

#' Richer coverage diagnostics (plan section 11; prompt: by season, week, team,
#' player, designation, practice status; missing states kept distinct).
injury_coverage_detail <- function(detail, team_games, m4_full) {
  wr <- dplyr::filter(detail, .data$position == "WR")
  list(
    designation_by_practice = dplyr::count(wr, .data$season, .data$designation, .data$practice),
    team_weeks = team_games |>
      dplyr::filter(.data$season %in% unique(detail$season)) |>
      dplyr::distinct(.data$season, .data$week, .data$team) |>
      dplyr::left_join(dplyr::count(detail, .data$season, .data$week, .data$team, name = "rows"),
                       by = c("season", "week", "team")) |>
      dplyr::summarise(team_weeks = dplyr::n(), without_valid_report = sum(is.na(.data$rows)), .by = "season"),
    per_week = dplyr::count(wr, .data$season, .data$week, name = "wr_rows") |>
      dplyr::summarise(min_wr_rows = min(.data$wr_rows), median_wr_rows = stats::median(.data$wr_rows),
                       max_wr_rows = max(.data$wr_rows), .by = "season"),
    players = dplyr::summarise(wr, players = dplyr::n_distinct(.data$gsis_id),
                               mean_weeks_listed = dplyr::n() / dplyr::n_distinct(.data$gsis_id), .by = "season"),
    report_state = dplyr::count(m4_full, .data$season, .data$report_state) |>
      tidyr::pivot_wider(names_from = "report_state", values_from = "n", values_fill = 0)
  )
}

#' Pre-registered injury groups (plan section 9): designation x final practice status.
injury_group <- function(designation, practice) {
  dplyr::case_when(
    designation == "Questionable" & practice == "DNP" ~ "Q_DNP",
    designation == "Questionable" & practice == "LP" ~ "Q_LP",
    designation == "Questionable" & practice == "FP" ~ "Q_FP",
    designation == "Questionable" ~ "Q_other",
    designation == "Doubtful" ~ "D",
    designation == "listed_only" & practice %in% c("DNP", "LP") ~ "listed_DNP_LP",
    designation == "listed_only" ~ "listed_FP",
    designation %in% c("Out", "Note") ~ "other_listed",
    TRUE ~ "not_listed"
  )
}

#' M4 model inputs: availability features plus the injury group used by the
#' frozen M4 rules (R/models/m4_candidates.R).
m4_add_features <- function(targets, detail, team_games) {
  out <- add_availability_features(targets, detail, team_games)
  out$group <- injury_group(out$designation, out$practice)
  out
}

#' Live (2026) injury detail for target week `week`. A capture contains no
#' date_modified, so every row is stamped with OUR retrieval time:
#' - target-week rows count only if retrieved before the player's own kickoff
#'   (as historically), and only once the team's FINAL report is out, i.e. the
#'   team-week carries at least one game designation. Earlier in the week the
#'   rows are practice-only reports, which history never contains (about 2% of
#'   historical team-weeks have listings but no designation; E14).
#' - earlier weeks' rows feed only the LAGGED trajectory features of the target
#'   week, for which the requirement is retrieval before the target kickoff.
live_injury_detail <- function(path, team_games, captured_at, season, week) {
  far <- as.POSIXct("9999-12-31", tz = "UTC")
  tg <- dplyr::mutate(team_games, kickoff_utc = dplyr::if_else(
    .data$season == !!season & .data$week < !!week, far, .data$kickoff_utc))
  d <- pregame_injury_detail(path, tg, captured_at = captured_at)
  final <- d |>
    dplyr::filter(.data$season == !!season, .data$week == !!week) |>
    dplyr::summarise(final = any(.data$designation %in% c("Out", "Doubtful", "Questionable")),
                     .by = c("season", "week", "team"))
  not_final <- dplyr::filter(final, !.data$final)
  out <- dplyr::anti_join(d, not_final, by = c("season", "week", "team"))
  attr(out, "coverage") <- attr(d, "coverage")
  attr(out, "final_teams") <- final$team[final$final]
  out
}

#' Injury-table leakage check (plan section 11). For each target week, three
#' corruptions must leave every feature of that week's rows unchanged:
#'   future    - reports of LATER weeks are rewritten (Out / DNP) and an Out row
#'               is added for every target player in the next week;
#'   late      - an Out/DNP report for the target week stamped AFTER kickoff is
#'               added for every target player;
#'   realised  - realised outcomes on the target rows (roster status, stat line,
#'               points, targets) are corrupted.
#' `feature_fn(targets, raw_rows, team_games)` builds features from raw report
#' rows. Returns the names of leaking feature columns.
check_injury_leakage <- function(targets, raw_rows, team_games, feature_fn, weeks = NULL) {
  weeks <- weeks %||% sort(unique(game_index(targets$season, targets$week)))
  outcome_cols <- intersect(c("roster_status", "has_stat_line", "actual", "actual_targets"), names(targets))
  leaks <- purrr::map(weeks, function(g) {
    probe <- targets[game_index(targets$season, targets$week) == g, ]
    s <- g %/% 100
    w <- g %% 100
    base <- feature_fn(probe, raw_rows, team_games)
    cols <- setdiff(names(base), names(probe))
    same <- function(x) cols[!vapply(cols, function(c) identical(base[[c]], x[[c]]), logical(1))]
    kick <- dplyr::left_join(dplyr::select(probe, "season", "week", "team", "gsis_id"),
                             dplyr::select(team_games, "season", "week", "team", "kickoff_utc"),
                             by = c("season", "week", "team"))
    out_row <- function(d, wk, at) tibble::tibble(season = d$season, game_type = "REG", team = d$team, week = wk,
                                                  gsis_id = d$gsis_id, position = "WR", report_status = "Out",
                                                  practice_status = "Did Not Participate In Practice",
                                                  report_primary_injury = "Knee", practice_primary_injury = NA,
                                                  date_modified = at)
    later <- game_index(raw_rows$season, raw_rows$week) > g
    future <- raw_rows
    future$report_status[later] <- "Out"
    future$practice_status[later] <- "Did Not Participate In Practice"
    future <- dplyr::bind_rows(future, out_row(kick, kick$week + 1L, kick$kickoff_utc + 3600 * 24 * 5))
    late <- dplyr::bind_rows(raw_rows, out_row(kick, kick$week, kick$kickoff_utc + 3600))
    realised <- probe
    for (c in outcome_cols) {
      realised[[c]] <- if (is.character(realised[[c]])) "INA" else if (is.logical(realised[[c]])) !realised[[c]] else
        realised[[c]] * 3 + 11
    }
    r_feat <- feature_fn(realised, raw_rows, team_games)
    c(same(feature_fn(probe, future, team_games)), same(feature_fn(probe, late, team_games)),
      setdiff(same(r_feat), outcome_cols))
  })
  sort(unique(unlist(leaks)))
}
