# Pregame schedule state from the nflverse/nfldata git history ---------------------------
# nfldata's data/games.csv (source of nflreadr::load_schedules) is committed
# every 10-20 minutes since 2021, with a linear history (no force pushes) and
# commit-to-push lags of ~1 s where verifiable (2023-04+). Its betting lines are
# live until kickoff and its QB columns list the EXPECTED starter days ahead.
# Reading the last version committed before a forecast cutoff therefore gives
# what that file said at forecast time: HISTORICAL-VALID for 2021-2025
# (lines also late 2020; QB columns exist from 2021). See
# docs/source_feasibility.csv. The repository has no license file: private
# research only; nothing derived is committed or redistributed.

NFLDATA_REPO_URL <- "https://github.com/nflverse/nfldata.git"
NFLDATA_DIR <- "data/raw/nfldata_git"
NFLDATA_COLS <- c("game_id", "spread_line", "total_line", "home_qb_id", "away_qb_id", "home_qb_name", "away_qb_name")

git_out <- function(dir, ...) system2("git", c("-C", dir, ...), stdout = TRUE, stderr = FALSE)

#' Blob-less clone (metadata only, ~20 MB); file versions are fetched on demand.
clone_nfldata <- function(dir = NFLDATA_DIR) {
  if (!dir.exists(dir)) {
    system2("git", c("clone", "-q", "--filter=blob:none", "--no-checkout", NFLDATA_REPO_URL, dir))
  }
  dir
}

#' The games.csv version committed strictly before `t` (sha and commit time).
nfldata_version_before <- function(t, dir = NFLDATA_DIR) {
  iso <- format(t - 1, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")   # strictly before
  sha <- git_out(dir, "rev-list", "-1", paste0("--before=", iso), "HEAD", "--", "data/games.csv")
  if (length(sha) == 0) return(list(sha = NA_character_, committed = as.POSIXct(NA, tz = "UTC")))
  ct <- git_out(dir, "show", "-s", "--format=%cI", sha)
  list(sha = sha, committed = as.POSIXct(sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", ct),
                                         format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"))
}

#' As-of schedule state for each game at `kickoff - hours_before`.
#' Returns one row per game with the committed values and the commit metadata.
nfldata_asof <- function(games, hours_before = 2, dir = NFLDATA_DIR) {
  g <- games |>
    dplyr::distinct(.data$game_id, .data$kickoff_utc) |>
    dplyr::mutate(cutoff_utc = .data$kickoff_utc - hours_before * 3600)
  purrr::map(split(g, g$cutoff_utc), function(gg) {
    v <- nfldata_version_before(gg$cutoff_utc[1], dir)
    if (is.na(v$sha)) return(dplyr::mutate(gg, commit_sha = NA_character_, committed_utc = v$committed))
    txt <- git_out(dir, "show", paste0(v$sha, ":data/games.csv"))
    snap <- readr::read_csv(I(paste(txt, collapse = "\n")), show_col_types = FALSE, col_types = readr::cols(.default = "c"))
    cols <- intersect(NFLDATA_COLS, names(snap))
    snap <- dplyr::select(snap, dplyr::all_of(cols))
    for (c in setdiff(NFLDATA_COLS, cols)) snap[[c]] <- NA_character_   # e.g. QB columns before 2021
    gg |>
      dplyr::left_join(snap, by = "game_id") |>
      dplyr::mutate(commit_sha = v$sha, committed_utc = v$committed)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(spread_line = as.numeric(.data$spread_line), total_line = as.numeric(.data$total_line))
}

#' Cache one season's as-of table (immutable raw file, like other raw data).
fetch_nfldata_asof <- function(season, team_games, hours_before = 2, root = "data/raw/nfldata_asof", refresh = FALSE) {
  path <- file.path(root, sprintf("asof_kickoff_minus_%gh_%d.parquet", hours_before, season))
  if (file.exists(path) && !refresh) return(path)
  clone_nfldata()
  games <- dplyr::filter(team_games, .data$season == !!season, .data$home)
  out <- nfldata_asof(games, hours_before)
  if (any(out$committed_utc >= out$cutoff_utc, na.rm = TRUE)) cli::cli_abort("A commit at/after its cutoff was selected.")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(out, path)
  jsonlite::write_json(list(provider = "nflverse/nfldata git history", season = season, hours_before = hours_before,
                            rows = nrow(out), retrieved_at_utc = utc_stamp(),
                            head_sha = git_out(NFLDATA_DIR, "rev-parse", "HEAD")),
                       paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  path
}

#' Per team-game pregame state: expected QB, line, implied total (as of cutoff),
#' plus whether the expected QB differs from the team's previous-game starter.
pregame_team_state <- function(asof, team_games, qb_game) {
  sides <- team_games |>
    dplyr::select("season", "week", "team", "game_id", "home") |>
    dplyr::inner_join(asof, by = "game_id") |>
    dplyr::mutate(
      expected_qb_id = dplyr::if_else(.data$home, .data$home_qb_id, .data$away_qb_id),
      asof_spread = dplyr::if_else(.data$home, .data$spread_line, -.data$spread_line),
      asof_implied_total = (.data$total_line + .data$asof_spread) / 2,
      game_index = game_index(.data$season, .data$week)
    )
  last_start <- qb_game |>
    dplyr::filter(.data$starter) |>
    dplyr::slice_max(.data$dropbacks, n = 1, with_ties = FALSE, by = c("season", "week", "team")) |>
    dplyr::transmute(team = .data$team, state_index = game_index(.data$season, .data$week), last_starter_id = .data$qb_id)
  starts <- qb_game |>
    dplyr::filter(.data$starter) |>
    dplyr::transmute(qb_id = .data$qb_id, gi = game_index(.data$season, .data$week))
  sides |>
    asof_join(last_start, by = "team", what = "previous starter") |>
    dplyr::mutate(
      expected_prior_starts = purrr::map2_int(.data$expected_qb_id, .data$game_index,
                                              ~ sum(starts$qb_id == .x & starts$gi < .y)),
      expected_qb_change = !is.na(.data$expected_qb_id) & !is.na(.data$last_starter_id) &
        .data$expected_qb_id != .data$last_starter_id
    ) |>
    dplyr::select("season", "week", "team", "commit_sha", "committed_utc", "cutoff_utc", "expected_qb_id",
                  "last_starter_id", "expected_prior_starts", "expected_qb_change", "asof_spread",
                  "asof_total" = "total_line", "asof_implied_total")
}
