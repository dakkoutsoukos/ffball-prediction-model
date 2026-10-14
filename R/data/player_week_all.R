# F4: position-general point-in-time player-week frame (master plan F4) --------------------------
# One row per (season, week, gsis_id) for QB/RB/WR/TE with a team game, 2019-2025: the substrate for
# P1-P4 and F6. Built with the existing build_player_week_base() (player_week.R is untouched); WR
# rows keep the frozen WR source (espn_weekly), and pwa_check_wr_reproduction() checks them against
# the frozen WR frame. Adds:
#   kickoff_utc; projection components for every position (re-parsed from the cached raw files);
#   a rolling-origin per-position calibrated base (MSE; P0's procedure, pd_rolling_base());
#   pregame-valid injury features (M4's, 2017-2024 timestamps; 2025 untimed = source_missing);
#   pregame role ranks (ESPN late horizon, and previous team game's offensive snaps);
#   as-of lines and expected QB at kickoff - 2 h (2021-2025; neutral-site games filled from the
#   local nfldata clone); point-in-time flags.
# Realised (outcome) columns, never features: actual / y, active (>= 1 offensive snap; a stat line
# counts where no snap record exists), offense_snaps, snap_share, has_stat_line, espn_actual,
# actual_* stats, roster_status (game day). Infrastructure only: nothing is selected here, and
# analyses that use the frame call assert_family_seasons() first.

PWA_POSITIONS <- c("QB", "RB", "WR", "TE")
PWA_SEASONS <- 2019:2025
PWA_ROLE_DEPTH <- c(QB = 1L, RB = 2L, WR = 3L, TE = 1L)
# ESPN projection components (ESPN stat ids): the WR frame's six (ESPN_STAT_IDS) plus passing and
# rushing touchdowns. Written out so this file does not depend on source order.
PWA_COMPONENT_IDS <- c(receptions = "53", targets = "58", receiving_yards = "42", receiving_tds = "43",
                       rushing_attempts = "23", rushing_yards = "24", passing_attempts = "0", passing_completions = "1",
                       passing_yards = "3", passing_tds = "4", passing_interceptions = "20", rushing_tds = "25")

#' Season and week from a raw ESPN file name (..._2024_w07.json.gz).
pwa_file_season_week <- function(path) {
  sw <- regmatches(basename(path), regexec("_(\\d{4})_w(\\d{2})", basename(path)))
  tibble::tibble(path = path, season = as.integer(vapply(sw, `[`, "", 2)), week = as.integer(vapply(sw, `[`, "", 3)))
}

#' Weekly projection components of every player in one raw kona_player_info file (the projection
#' entry of exactly this season and week, split type 1; a missing stat is 0, as in parse_espn_week()).
pwa_parse_components <- function(path, ids = PWA_COMPONENT_IDS) {
  sw <- pwa_file_season_week(path)
  doc <- jsonlite::fromJSON(read_gz_text(path), simplifyVector = FALSE)
  rows <- lapply(doc$players, function(p) {
    pl <- p$player
    hits <- Filter(function(s) {
      identical(as.integer(s$seasonId), sw$season) && identical(as.integer(s$scoringPeriodId), sw$week) &&
        identical(as.integer(s$statSplitTypeId), 1L) && identical(as.integer(s$statSourceId), 1L)
    }, pl$stats %||% list())
    if (!length(hits)) return(NULL)
    if (length(hits) > 1) cli::cli_abort("ESPN player {pl$id}: {length(hits)} projection entries in {.file {basename(path)}}.")
    st <- hits[[1]]$stats %||% list()
    c(espn_id = as.character(pl$id), vapply(ids, function(id) as.numeric(st[[id]] %||% 0), 0))
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(NULL)
  m <- do.call(rbind, rows)
  out <- tibble::tibble(season = sw$season, week = sw$week, espn_id = unname(m[, "espn_id"]))   # a 1-row matrix keeps names
  for (nm in names(ids)) out[[paste0("espn_proj_", nm)]] <- as.numeric(unname(m[, nm]))
  out
}

#' Components from every cached raw file of the seasons (WR files and QB/RB/TE files). A player in
#' two files of one week must carry identical components.
pwa_espn_components <- function(paths, seasons = PWA_SEASONS) {
  sw <- pwa_file_season_week(paths)
  comp <- purrr::map(sw$path[sw$season %in% seasons], pwa_parse_components) |> purrr::list_rbind()
  keys <- c("season", "week", "espn_id")
  dup <- dplyr::distinct(comp) |> dplyr::count(dplyr::across(dplyr::all_of(keys))) |> dplyr::filter(.data$n > 1)
  if (nrow(dup)) cli::cli_abort("{nrow(dup)} player-week{?s} with conflicting ESPN components across files.")
  dplyr::distinct(comp, dplyr::across(dplyr::all_of(keys)), .keep_all = TRUE)
}

#' ESPN week-of history of the four positions in espn_weekly's layout. WR rows are espn_weekly's
#' WR-position rows (the frozen WR source, unchanged); QB/RB/TE rows come from the valuation history.
#' Components the frozen source lacks are joined from the re-parsed files.
pwa_espn_all <- function(espn_weekly, val_espn_hist, components, seasons = PWA_SEASONS) {
  wr <- dplyr::filter(espn_weekly, .data$season %in% !!seasons, .data$espn_position_id == ESPN_POSITION_IDS[["WR"]])
  extra <- c("season", "week", "espn_id", setdiff(names(components), names(wr)))
  wr <- dplyr::left_join(wr, components[extra], by = c("season", "week", "espn_id"))
  qrt <- val_espn_hist |>
    dplyr::filter(.data$season %in% !!seasons, .data$position %in% c("QB", "RB", "TE")) |>
    dplyr::transmute(.data$season, .data$week, espn_id = as.character(.data$espn_id), .data$espn_name,
                     espn_position_id = unname(ESPN_POSITION_IDS[.data$position]), .data$espn_pro_team_id,
                     .data$espn_proj, .data$espn_actual) |>
    dplyr::left_join(components, by = c("season", "week", "espn_id"))
  dplyr::bind_rows(wr, qrt) |>
    assert_unique_key(c("season", "week", "espn_id"), "pwa_espn_all")
}

#' Check: the re-parsed WR-style components equal the frozen espn_weekly values on its WR rows.
pwa_check_components <- function(espn_weekly, components, seasons = PWA_SEASONS) {
  cols <- paste0("espn_proj_", names(ESPN_STAT_IDS))
  wr <- dplyr::filter(espn_weekly, .data$season %in% !!seasons, .data$espn_position_id == ESPN_POSITION_IDS[["WR"]],
                      !is.na(.data$espn_proj))
  j <- dplyr::inner_join(wr[c("season", "week", "espn_id", cols)], components[c("season", "week", "espn_id", cols)],
                         by = c("season", "week", "espn_id"), suffix = c(".frozen", ".parsed"))
  differ <- Reduce(`|`, lapply(cols, function(c) abs(j[[paste0(c, ".frozen")]] - j[[paste0(c, ".parsed")]]) > 1e-9))
  list(wr_projected_rows = nrow(wr), matched = nrow(j), differing = sum(differ, na.rm = TRUE))
}

#' Union of the WR crosswalk and the valuation crosswalk; the WR one wins on shared ids, so WR rows
#' map exactly as in the frozen frame.
pwa_crosswalk <- function(espn_crosswalk, val_crosswalk) {
  extra <- dplyr::filter(val_crosswalk, !.data$espn_id %in% espn_crosswalk$espn_id)
  dplyr::bind_rows(espn_crosswalk, extra) |>
    assert_unique_key("espn_id", "pwa_crosswalk")
}

#' As-of schedule state (kickoff - 2 h) for every game of a season: the cached E11 file for games
#' with a home team, plus neutral-site games computed from the local nfldata clone and cached under
#' a new name (E11's caches are never rewritten). NULL when the season has no E11 cache.
pwa_asof_games <- function(season, team_games, root = "data/raw/nfldata_asof", dir = NFLDATA_DIR) {
  home_file <- file.path(root, sprintf("asof_kickoff_minus_2h_%d.parquet", season))
  if (!file.exists(home_file)) return(NULL)
  home <- arrow::read_parquet(home_file, mmap = FALSE)
  tg <- dplyr::filter(team_games, .data$season == !!season)
  neutral_ids <- setdiff(unique(tg$game_id), unique(tg$game_id[tg$home]))
  neutral <- NULL
  if (length(neutral_ids)) {
    nf <- file.path(root, sprintf("asof_kickoff_minus_2h_neutral_%d.parquet", season))
    if (!file.exists(nf)) {
      if (!dir.exists(dir)) cli::cli_abort("No local nfldata clone at {.file {dir}} for neutral-site as-of lines.")
      games <- dplyr::distinct(dplyr::filter(tg, .data$game_id %in% neutral_ids), .data$game_id, .data$kickoff_utc)
      out <- nfldata_asof(games, 2, dir)
      if (any(out$committed_utc >= out$cutoff_utc, na.rm = TRUE)) cli::cli_abort("A commit at/after its cutoff was selected.")
      # a failed version fetch yields empty lines: never cache an incomplete table
      if (anyNA(out$commit_sha) || anyNA(out$spread_line) || anyNA(out$total_line)) {
        cli::cli_abort("Neutral-site as-of lines for {season} are incomplete (fetch failed?); nothing cached.")
      }
      arrow::write_parquet(out, nf)
      jsonlite::write_json(list(provider = "nflverse/nfldata git history", season = season, hours_before = 2,
                                neutral_site = TRUE, rows = nrow(out), retrieved_at_utc = utc_stamp(),
                                head_sha = git_out(dir, "rev-parse", "HEAD")),
                           paste0(nf, ".json"), auto_unbox = TRUE, pretty = TRUE)
    }
    neutral <- arrow::read_parquet(nf, mmap = FALSE)
  }
  dplyr::bind_rows(home, neutral) |>
    dplyr::distinct(.data$game_id, .keep_all = TRUE) |>
    dplyr::select("game_id", "spread_line", "total_line", "home_qb_id", "away_qb_id", "cutoff_utc", "committed_utc")
}

#' Team-perspective as-of state for every team-game: spread, total, implied total and expected QB.
#' The designated home team (last token of the nflverse game_id) carries spread_line and the home
#' QB column, also at neutral sites.
pwa_asof_lines <- function(team_games, seasons = 2021:2025, ...) {
  g <- purrr::map(seasons, function(s) pwa_asof_games(s, team_games, ...)) |> purrr::list_rbind()
  if (is.null(g) || !nrow(g)) {
    return(tibble::tibble(season = integer(), week = integer(), team = character(), asof_spread = double(),
                          asof_total = double(), asof_implied_total = double(), asof_expected_qb_id = character(),
                          asof_cutoff_utc = as.POSIXct(character(), tz = "UTC")))
  }
  team_games |>
    dplyr::filter(.data$season %in% !!seasons) |>
    dplyr::select("season", "week", "team", "game_id") |>
    dplyr::inner_join(g, by = "game_id") |>
    dplyr::mutate(is_home = .data$team == standardize_team(sub(".*_", "", .data$game_id)),
                  asof_spread = dplyr::if_else(.data$is_home, .data$spread_line, -.data$spread_line),
                  asof_total = .data$total_line,
                  asof_implied_total = (.data$asof_total + .data$asof_spread) / 2,
                  asof_expected_qb_id = dplyr::if_else(.data$is_home, .data$home_qb_id, .data$away_qb_id)) |>
    dplyr::select("season", "week", "team", "asof_spread", "asof_total", "asof_implied_total", "asof_expected_qb_id",
                  asof_cutoff_utc = "cutoff_utc", asof_committed_utc = "committed_utc")
}

#' Offensive snaps in the team's previous game of the season: 0 when the player has no snap record
#' for that game (snap tables keep only players with snaps; an unmapped id also reads as 0), NA in
#' the team's first game. Known once that game ends.
pwa_prev_snaps <- function(frame, snaps, team_games) {
  prev <- team_games |>
    dplyr::distinct(.data$season, .data$week, .data$team) |>
    dplyr::arrange(.data$season, .data$team, .data$week) |>
    dplyr::mutate(prev_week = dplyr::lag(.data$week), .by = c("season", "team"))
  sn <- snaps |>
    dplyr::summarise(prev_offense_snaps = sum(.data$offense_snaps), .by = c("season", "week", "gsis_id")) |>
    dplyr::rename(prev_week = "week")
  frame |>
    dplyr::select("season", "week", "team", "gsis_id") |>
    dplyr::left_join(prev, by = c("season", "week", "team")) |>
    dplyr::left_join(sn, by = c("season", "prev_week", "gsis_id")) |>
    dplyr::mutate(prev_offense_snaps = dplyr::if_else(is.na(.data$prev_week), NA_real_,
                                                      dplyr::coalesce(.data$prev_offense_snaps, 0))) |>
    dplyr::select("season", "week", "gsis_id", "prev_week", "prev_offense_snaps")
}

#' Pregame role ranks within team x position: by ESPN's week-of projection (late horizon; rank 1 =
#' top) and by the previous team game's offensive snaps (valid at every horizon). Roles beyond the
#' position's depth (QB1, RB1-2, WR1-3, TE1) are "<pos>_depth".
pwa_role_ranks <- function(frame) {
  role <- function(pos, r) {
    dplyr::case_when(is.na(r) ~ NA_character_, r <= PWA_ROLE_DEPTH[pos] ~ paste0(pos, r), TRUE ~ paste0(pos, "_depth"))
  }
  frame |>
    dplyr::mutate(role_rank = dplyr::if_else(.data$pop_espn, rank(-.data$espn_proj, ties.method = "first"), NA_real_),
                  .by = c("season", "week", "team", "position")) |>
    dplyr::mutate(role_rank_prev = dplyr::if_else(.data$prev_offense_snaps %in% NA, NA_real_,
                                                  rank(-dplyr::coalesce(.data$prev_offense_snaps, -1), ties.method = "first")),
                  .by = c("season", "week", "team", "position")) |>
    dplyr::mutate(role = role(.data$position, .data$role_rank), role_prev = role(.data$position, .data$role_rank_prev))
}

#' The F4 frame (QB/RB/WR/TE). `injury_detail` = pregame_injury_detail(); `snaps` = clean_snap_counts().
build_player_week_all <- function(espn_weekly, val_espn_hist, components, espn_crosswalk, val_crosswalk, player_stats,
                                  rosters_weekly, team_games, injuries, injury_detail, snaps, seasons = PWA_SEASONS,
                                  asof_root = "data/raw/nfldata_asof") {
  espn <- pwa_espn_all(espn_weekly, val_espn_hist, components, seasons)
  cw <- pwa_crosswalk(espn_crosswalk, val_crosswalk)
  in_seasons <- function(d) dplyr::filter(d, .data$season %in% !!seasons)
  fr <- build_player_week_base(espn, cw, in_seasons(player_stats), in_seasons(rosters_weekly), in_seasons(team_games),
                               in_seasons(injuries), positions = PWA_POSITIONS) |>
    dplyr::filter(.data$has_game)
  sn <- in_seasons(snaps) |>
    dplyr::summarise(offense_snaps = sum(.data$offense_snaps, na.rm = TRUE), snap_share = max(.data$snap_share),
                     .by = c("season", "week", "gsis_id"))
  fr <- fr |>
    dplyr::left_join(dplyr::select(team_games, "season", "week", "team", "kickoff_utc", "roof"),
                     by = c("season", "week", "team")) |>
    dplyr::left_join(sn, by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(pop_espn = !is.na(.data$espn_proj) & .data$espn_proj > 0,
                  active = dplyr::if_else(is.na(.data$offense_snaps), .data$has_stat_line, .data$offense_snaps >= 1),
                  y = .data$actual)
  # rolling-origin per-position calibrated base (P0's procedure) on ESPN-projected rows
  based <- pd_rolling_base(dplyr::transmute(dplyr::filter(fr, .data$pop_espn), .data$season, .data$week, .data$gsis_id,
                                            .data$position, .data$espn_proj, .data$y, .data$active))
  # (a position with a single week gets named coefficients from a one-row matrix: drop the names)
  based <- dplyr::mutate(based, dplyr::across(c("base", "a", "b", "n_train"), unname))
  fr <- dplyr::left_join(fr, dplyr::select(based, "season", "week", "gsis_id", "base", base_a = "a", base_b = "b",
                                           base_train_rows = "n_train"), by = c("season", "week", "gsis_id"))
  fr <- m4_add_features(fr, injury_detail, team_games)
  fr <- dplyr::left_join(fr, pwa_prev_snaps(fr, in_seasons(snaps), team_games), by = c("season", "week", "gsis_id"))
  fr <- pwa_role_ranks(fr)
  fr <- dplyr::left_join(fr, pwa_asof_lines(team_games, intersect(2021:2025, seasons), root = asof_root),
                         by = c("season", "week", "team")) |>
    dplyr::mutate(asof_expected_starter = dplyr::if_else(.data$position == "QB" & !is.na(.data$asof_expected_qb_id),
                                                         .data$gsis_id == .data$asof_expected_qb_id, NA))
  fr |>
    dplyr::mutate(espn_horizon = "late", schedule_lines = "closing", injury_timed = .data$season <= 2024,
                  asof_available = !is.na(.data$asof_spread)) |>
    dplyr::arrange(.data$season, .data$week, .data$position, .data$gsis_id) |>
    assert_unique_key(c("season", "week", "gsis_id"), "player_week_all")
}

#' Corruption leakage test for the frame's outcome-derived features (the injury features have their
#' own test, check_injury_leakage()). For each cutoff week g, every realised outcome of weeks >= g
#' (points, active, snaps, ESPN actuals) is rewritten; the base, previous-game snaps and both role
#' ranks of week-g rows must not change. As-of lines must come from commits strictly before a cutoff
#' of kickoff - 2 h. Returns the names of leaking features (empty = pass).
pwa_check_leakage <- function(frame, snaps, team_games, weeks) {
  gi <- game_index(frame$season, frame$week)
  feats <- c("base", "prev_offense_snaps", "role_rank", "role_rank_prev")
  derive <- function(fr, sn) {
    b <- pd_rolling_base(dplyr::transmute(dplyr::filter(fr, .data$pop_espn), .data$season, .data$week, .data$gsis_id,
                                          .data$position, .data$espn_proj, .data$y, .data$active))
    fr <- dplyr::select(fr, -dplyr::any_of(c("base", "prev_week", "prev_offense_snaps", "role_rank", "role_rank_prev",
                                             "role", "role_prev")))
    fr <- dplyr::left_join(fr, dplyr::select(b, "season", "week", "gsis_id", "base"), by = c("season", "week", "gsis_id"))
    fr <- dplyr::left_join(fr, pwa_prev_snaps(fr, sn, team_games), by = c("season", "week", "gsis_id"))
    pwa_role_ranks(fr)
  }
  ref <- derive(frame, snaps)
  sgi <- game_index(snaps$season, snaps$week)
  leaks <- purrr::map(weeks, function(g) {
    late <- gi >= g
    bad <- frame
    bad$y[late] <- bad$y[late] * 3 + 11
    bad$actual[late] <- bad$y[late]
    bad$active[late] <- !bad$active[late]
    bad$espn_actual[late] <- bad$espn_actual[late] * 3 + 11
    bad_sn <- snaps
    bad_sn$offense_snaps[sgi >= g] <- bad_sn$offense_snaps[sgi >= g] * 3 + 11
    got <- derive(bad, bad_sn)
    at <- gi == g
    feats[!vapply(feats, function(f) identical(ref[[f]][at], got[[f]][at]), logical(1))]
  })
  asof_ok <- with(frame, all(is.na(asof_cutoff_utc) | (asof_committed_utc < asof_cutoff_utc &
                                                        abs(as.numeric(kickoff_utc - asof_cutoff_utc, units = "hours") - 2) < 1e-9)))
  sort(unique(c(unlist(leaks), if (!asof_ok) "asof_lines")))
}

#' Audit: rows, populations and coverage by season and position (aggregates only).
pwa_audit <- function(frame) {
  list(
    by_season_position = frame |>
      dplyr::summarise(rows = dplyr::n(), projected = sum(.data$pop_espn), active = sum(.data$active),
                       with_base = sum(!is.na(.data$base)), with_asof = sum(.data$asof_available),
                       with_prev_snaps = sum(!is.na(.data$prev_offense_snaps)), listed = sum(.data$listed),
                       source_missing = sum(.data$report_state == "source_missing"), .by = c("season", "position")) |>
      dplyr::arrange(.data$season, .data$position),
    other_positions = dplyr::count(dplyr::filter(frame, !.data$position %in% PWA_POSITIONS), .data$position,
                                   projected = .data$pop_espn),
    projected_missing_components = frame |>
      dplyr::filter(.data$pop_espn) |>
      dplyr::summarise(dplyr::across(dplyr::starts_with("espn_proj_"), ~ sum(is.na(.x))), .by = "position")
  )
}

#' F4 criterion (fixed before the first build): per position, the share of rows with an ESPN actual
#' whose league-scored points (0 without a stat line) equal ESPN's to within 0.011 points. Must be
#' at least 99.9% for every position. Secondary: the same on rows with a stat line.
pwa_scoring_match <- function(frame, tol = 0.011) {
  frame |>
    dplyr::filter(!is.na(.data$espn_actual)) |>
    dplyr::mutate(ok = abs(.data$actual - .data$espn_actual) < tol) |>
    dplyr::summarise(rows = dplyr::n(), match_share = mean(.data$ok),
                     rows_stat_line = sum(.data$has_stat_line), match_share_stat_line = mean(.data$ok[.data$has_stat_line]),
                     mismatches = sum(!.data$ok), .by = "position") |>
    dplyr::arrange(match(.data$position, PWA_POSITIONS))
}

#' F4 criterion (fixed before the first build): the frozen WR frame's rows (player_week_base, with a
#' team game, 2019-2025) are reproduced. Every frozen key must be present, and every shared column
#' identical, except on rows whose ESPN default position is QB/RB/TE: the WR frame saw only ESPN's WR
#' rows, so there the ESPN columns, position and name legitimately come from the other position's
#' file. Those rows are counted; any other difference fails. No frame WR row may be new.
pwa_check_wr_reproduction <- function(frame, player_week_base, seasons = PWA_SEASONS) {
  keys <- c("season", "week", "gsis_id")
  old <- dplyr::filter(player_week_base, .data$has_game, .data$season %in% !!seasons)
  cols <- setdiff(intersect(names(old), names(frame)), keys)
  espn_dep <- c(grep("^espn_", cols, value = TRUE), "position", "player_name")
  j <- dplyr::inner_join(old[c(keys, cols)], frame[c(keys, cols)], by = keys, suffix = c(".old", ".new"))
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  diff_by_col <- vapply(cols, function(c) !same(j[[paste0(c, ".old")]], j[[paste0(c, ".new")]]), logical(nrow(j)))
  if (!is.matrix(diff_by_col)) diff_by_col <- matrix(diff_by_col, nrow = nrow(j), dimnames = list(NULL, cols))
  reassigned <- j$espn_position.new %in% c("QB", "RB", "TE")
  core_cols <- setdiff(cols, espn_dep)
  core_diff <- rowSums(diff_by_col[, core_cols, drop = FALSE]) > 0
  espn_diff <- rowSums(diff_by_col[, intersect(espn_dep, cols), drop = FALSE]) > 0
  new_wr <- dplyr::anti_join(dplyr::filter(frame, .data$position == "WR"), old, by = keys)
  out <- list(rows_old = nrow(old), missing_in_new = nrow(old) - nrow(j), core_columns = length(core_cols),
              rows_core_differ = sum(core_diff), rows_reassigned = sum(reassigned),
              rows_espn_differ_unexplained = sum(espn_diff & !reassigned), new_wr_rows = nrow(new_wr),
              differing_columns = cols[colSums(diff_by_col[!reassigned, , drop = FALSE]) > 0])
  out$pass <- out$missing_in_new == 0 && out$rows_core_differ == 0 && out$rows_espn_differ_unexplained == 0 &&
    out$new_wr_rows == 0
  out
}
