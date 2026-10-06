# Live (in-season) data layer ------------------------------------------------------
# Completed seasons live in data/raw/ and never change. The in-progress season
# changes daily, so every retrieval is stored as a NEW immutable file:
#   data/raw/nflverse_live/<dataset>/season=<S>/retrieved_at=<UTC>.parquet
# A prospective run records exactly which retrievals it used, so what was
# known at prediction time can always be reconstructed.

LIVE_ROOT <- "data/raw/nflverse_live"
# Captured every run for FUTURE prospective-only features; no model uses them yet.
LIVE_CAPTURE_ONLY <- c("depth_charts")
LIVE_DATASETS <- c("player_stats", "schedules", "rosters_weekly", "snap_counts",
                   "injuries", "ff_opportunity", "pbp", "players", "ff_playerids")

utc_stamp <- function(time = Sys.time()) format(time, "%Y%m%dT%H%M%SZ", tz = "UTC")
parse_utc_stamp <- function(x) as.POSIXct(x, format = "%Y%m%dT%H%M%SZ", tz = "UTC")

#' Write a file only if it does not exist yet. Immutability guard for archives.
write_once <- function(path, writer) {
  if (file.exists(path)) cli::cli_abort("Refusing to overwrite immutable file {.file {path}}.")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".part")
  writer(tmp)
  if (!file.rename(tmp, path)) cli::cli_abort("Could not finalise {.file {path}}.")
  path
}

sha256_file <- function(path) {
  h <- as.character(openssl::sha256(file(path)))
  attributes(h) <- NULL  # plain hex string (openssl returns a classed "hash")
  h
}

#' Retrieve one live dataset now and store it as a new immutable file.
fetch_live_nflverse <- function(dataset, season, root = LIVE_ROOT, stamp = utc_stamp()) {
  path <- file.path(root, dataset, sprintf("season=%d", season), sprintf("retrieved_at=%s.parquet", stamp))
  if (dataset == "pbp") {
    url <- sprintf("%s/pbp/play_by_play_%s.parquet", NFLVERSE_RELEASE_URL, season)
    write_once(path, function(tmp) utils::download.file(url, tmp, mode = "wb", quiet = TRUE))
    meta <- list(url = url)
  } else {
    df <- nflverse_loaders[[dataset]](season)
    write_once(path, function(tmp) arrow::write_parquet(as.data.frame(df), tmp))
    meta <- list(nflverse_timestamp = as.character(attr(df, "nflverse_timestamp") %||% NA))
  }
  jsonlite::write_json(c(list(provider = "nflverse", dataset = dataset, season = season,
                              retrieved_at_utc = stamp, sha256 = sha256_file(path)), meta),
                       paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  path
}

#' Latest live retrieval of a dataset made at or before `as_of`.
latest_live_file <- function(dataset, season, as_of = Sys.time(), root = LIVE_ROOT) {
  files <- list.files(file.path(root, dataset, sprintf("season=%d", season)),
                      pattern = "^retrieved_at=.*[.]parquet$", full.names = TRUE)
  stamps <- parse_utc_stamp(sub("^retrieved_at=(.*)[.]parquet$", "\\1", basename(files)))
  ok <- !is.na(stamps) & stamps <= as_of
  if (!any(ok)) cli::cli_abort("No live {dataset} retrieval for {season} at or before {as_of}.")
  files[ok][which.max(stamps[ok])]
}

#' Refresh every live dataset (one new retrieval each) and return their paths.
refresh_live_data <- function(season, datasets = c(LIVE_DATASETS, LIVE_CAPTURE_ONLY), root = LIVE_ROOT) {
  stamp <- utc_stamp()
  rlang::set_names(purrr::map_chr(datasets, ~ fetch_live_nflverse(.x, season, root, stamp)), datasets)
}

# --- ESPN teams --------------------------------------------------------------------

#' ESPN proTeamId -> nflverse team code. ESPN's ids are stable; the mapping is
#' validated against nflverse rosters by validate_espn_team_map().
ESPN_TEAM_IDS <- c(
  `1` = "ATL", `2` = "BUF", `3` = "CHI", `4` = "CIN", `5` = "CLE", `6` = "DAL", `7` = "DEN",
  `8` = "DET", `9` = "GB", `10` = "TEN", `11` = "IND", `12` = "KC", `13` = "LV", `14` = "LA",
  `15` = "MIA", `16` = "MIN", `17` = "NE", `18` = "NO", `19` = "NYG", `20` = "NYJ", `21` = "PHI",
  `22` = "ARI", `23` = "PIT", `24` = "LAC", `25` = "SF", `26` = "SEA", `27` = "TB", `28` = "WAS",
  `29` = "CAR", `30` = "JAX", `33` = "BAL", `34` = "HOU"
)

espn_team <- function(pro_team_id) unname(ESPN_TEAM_IDS[as.character(pro_team_id)])

#' Agreement between ESPN's current team ids (live snapshot) and the players'
#' most recent nflverse team. Returns per-team agreement; fails if any mapped
#' team agrees on fewer than half of its matched players.
validate_espn_team_map <- function(snapshot, crosswalk, recent_team) {
  d <- snapshot |>
    dplyr::filter(!is.na(.data$espn_pro_team_id), .data$espn_pro_team_id != 0) |>
    dplyr::inner_join(dplyr::filter(crosswalk, !is.na(.data$gsis_id)) |> dplyr::select("espn_id", "gsis_id"),
                      by = "espn_id") |>
    dplyr::inner_join(recent_team, by = "gsis_id") |>
    dplyr::mutate(mapped = espn_team(.data$espn_pro_team_id))
  agree <- dplyr::summarise(d, n = dplyr::n(), agree = mean(.data$mapped == .data$recent_team),
                            .by = c("espn_pro_team_id", "mapped"))
  bad <- dplyr::filter(agree, .data$n >= 3, .data$agree < 0.5)
  if (nrow(bad) > 0) cli::cli_abort("ESPN team map disagrees with nflverse for ids {.val {bad$espn_pro_team_id}}.")
  agree
}

# --- Snapshots -----------------------------------------------------------------------

#' All archived ESPN snapshots for a season-week, with capture times.
list_snapshots <- function(season, week, root = "data/snapshots/espn", position = "wr") {
  dir <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week))
  files <- list.files(dir, pattern = paste0("^captured_at=.*_", position, "[.]parquet$"), full.names = TRUE)
  tibble::tibble(
    path = files,
    captured_at = parse_utc_stamp(sub("^captured_at=([0-9TZ]+)_.*$", "\\1", basename(files)))
  ) |>
    dplyr::arrange(.data$captured_at)
}

#' OFFICIAL SNAPSHOT POLICY: for a game kicking off at `kickoff_utc`, the
#' official ESPN pregame projection is the LATEST snapshot captured STRICTLY
#' BEFORE kickoff. Earlier snapshots are kept; later ones are never used.
#' Returns NA when no snapshot precedes kickoff.
official_snapshot <- function(snapshots, kickoff_utc) {
  vapply(kickoff_utc, function(k) {
    ok <- snapshots$captured_at < k
    if (!any(ok)) NA_character_ else snapshots$path[ok][which.max(snapshots$captured_at[ok])]
  }, character(1))
}
