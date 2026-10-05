# Raw nflverse ingestion -------------------------------------------------------
# Each fetch writes one parquet file under data/raw/nflverse/<dataset>/ plus a
# JSON sidecar recording provenance (source, loader, package version, nflverse
# build timestamp, retrieval time, shape). Raw files are treated as immutable:
# an existing file is reused unless `refresh = TRUE`, so destroying the targets
# store never silently re-downloads (and changes) historical inputs.
#
# Functions return the parquet path so they can back `format = "file"` targets.

NFLVERSE_RELEASE_URL <- "https://github.com/nflverse/nflverse-data/releases/download"

nflverse_loaders <- list(
  player_stats   = function(season) nflreadr::load_player_stats(season, summary_level = "week"),
  schedules      = function(season) nflreadr::load_schedules(season),
  rosters_weekly = function(season) nflreadr::load_rosters_weekly(season),
  snap_counts    = function(season) nflreadr::load_snap_counts(season),
  injuries       = function(season) nflreadr::load_injuries(season),
  ff_opportunity = function(season) nflreadr::load_ff_opportunity(season, stat_type = "weekly"),
  ff_playerids   = function(season) nflreadr::load_ff_playerids(),
  players        = function(season) nflreadr::load_players()
)

raw_nflverse_path <- function(dataset, season = NULL, root = "data/raw/nflverse") {
  file <- if (is.null(season)) paste0(dataset, ".parquet") else paste0(dataset, "_", season, ".parquet")
  file.path(root, dataset, file)
}

write_raw_parquet <- function(df, path, meta) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(as.data.frame(df), path)
  meta$rows <- nrow(df)
  meta$cols <- ncol(df)
  meta$retrieved_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  jsonlite::write_json(meta, paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  path
}

#' Download one nflverse dataset (optionally one season) to data/raw.
#' `season = NULL` is for season-less snapshots such as the player ID map.
fetch_nflverse <- function(dataset, season = NULL, root = "data/raw/nflverse", refresh = FALSE) {
  path <- raw_nflverse_path(dataset, season, root)
  if (file.exists(path) && !refresh) return(path)
  loader <- nflverse_loaders[[dataset]]
  if (is.null(loader)) cli::cli_abort("Unknown nflverse dataset {.val {dataset}}.")

  df <- loader(season)
  if (!is.null(season) && "season" %in% names(df)) {
    seasons_found <- unique(df$season)
    if (!identical(as.integer(seasons_found), as.integer(season))) {
      cli::cli_abort("{dataset}: asked for {season}, got season{?s} {seasons_found}.")
    }
  }
  write_raw_parquet(df, path, meta = list(
    provider = "nflverse",
    dataset = dataset,
    season = season,
    loader = paste0("nflreadr ", utils::packageVersion("nflreadr")),
    nflverse_type = attr(df, "nflverse_type") %||% NA_character_,
    nflverse_timestamp = as.character(attr(df, "nflverse_timestamp") %||% NA)
  ))
}

#' Download a season of play-by-play as the published release parquet file.
fetch_nflverse_pbp <- function(season, root = "data/raw/nflverse", refresh = FALSE) {
  path <- raw_nflverse_path("pbp", season, root)
  if (file.exists(path) && !refresh) return(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  url <- sprintf("%s/pbp/play_by_play_%s.parquet", NFLVERSE_RELEASE_URL, season)
  tmp <- paste0(path, ".part")
  utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
  file.rename(tmp, path)
  meta <- list(
    provider = "nflverse", dataset = "pbp", season = season, url = url,
    rows = arrow::open_dataset(path)$num_rows,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  jsonlite::write_json(meta, paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  path
}

#' Read every sidecar under data/raw into one provenance table.
raw_data_manifest <- function(paths) {
  purrr::map(paths, function(p) {
    meta <- jsonlite::read_json(paste0(p, ".json"))
    meta[vapply(meta, is.null, logical(1))] <- NA
    tibble::as_tibble(lapply(meta, as.character)) |>
      dplyr::mutate(path = p, bytes = file.size(p))
  }) |>
    purrr::list_rbind()
}

read_parquet_files <- function(paths) {
  purrr::map(paths, arrow::read_parquet) |>
    purrr::list_rbind() |>
    tibble::as_tibble()
}
