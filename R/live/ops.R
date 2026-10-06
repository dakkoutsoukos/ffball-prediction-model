# Operational helpers for the weekly prospective workflow --------------------------------
# Status reporting, git sync checks, archive integrity, and verified private
# backups. Nothing here pushes to git or contacts ESPN.

fmt_utc <- function(t) format(t, "%Y-%m-%d %H:%M UTC", tz = "UTC")

#' Lineages with a frozen registry file (default set for weekly runs).
frozen_lineages <- function(dir = "models/registry") {
  sort(tolower(sub("[.]yml$", "", list.files(dir, pattern = "^m[0-9]+[.]yml$"))))
}

#' The week to predict: the earliest regular-season week that still has a game
#' not yet kicked off at `now`.
infer_target_week <- function(team_games, season, now = Sys.time()) {
  upcoming <- dplyr::filter(team_games, .data$season == !!season, .data$kickoff_utc > now)
  if (nrow(upcoming) == 0) return(NA_integer_)
  min(upcoming$week)
}

#' Kickoff overview for one week: which games have started, which have not.
week_kickoffs <- function(team_games, season, week, now = Sys.time()) {
  team_games |>
    dplyr::filter(.data$season == !!season, .data$week == !!week, .data$home) |>
    dplyr::distinct(.data$game_id, .data$kickoff_utc) |>
    dplyr::mutate(started = .data$kickoff_utc <= now) |>
    dplyr::arrange(.data$kickoff_utc)
}

#' Is the committed archive state pushed? Reports uncommitted manifest changes
#' and local commits not yet on origin.
git_sync_state <- function() {
  run <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE), error = function(e) character())
  status <- run("status", "--porcelain")
  ahead <- run("rev-list", "--count", "@{u}..HEAD")
  list(
    branch = run("rev-parse", "--abbrev-ref", "HEAD")[1],
    manifests_uncommitted = any(grepl("archive/", status)),
    code_dirty = any(!grepl("archive/", status) & grepl("^ ?[MADR]", status)),
    commits_not_pushed = suppressWarnings(as.integer(ahead[1]))
  )
}

#' Recompute SHA-256 of every registered snapshot (parquet + raw) and compare
#' with the committed snapshot manifest.
verify_snapshot_archive <- function(manifest = SNAPSHOT_MANIFEST, root = "data/snapshots/espn") {
  if (!file.exists(manifest)) return(tibble::tibble())
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
  purrr::pmap(m, function(file, season, week, parquet_sha256, raw_sha256, ...) {
    dir <- file.path(root, paste0("season=", season), sprintf("week=%02d", as.integer(week)))
    pq <- file.path(dir, file)
    raw <- sub("[.]parquet$", ".json.gz", pq)
    tibble::tibble(
      file = file, season = as.integer(season), week = as.integer(week),
      parquet_ok = file.exists(pq) && identical(sha256_file(pq), parquet_sha256),
      raw_ok = file.exists(raw) && identical(sha256_file(raw), raw_sha256)
    )
  }) |>
    purrr::list_rbind()
}

#' For each upcoming game of a week, the latest archived run made before its
#' kickoff (if any) and which lineages it covered.
week_coverage <- function(season, week, kickoffs, manifest = PREDICTION_MANIFEST) {
  m <- if (file.exists(manifest)) readr::read_csv(manifest, col_types = readr::cols(.default = "c")) else tibble::tibble()
  m <- dplyr::filter(m, as.integer(.data$season) == !!season, as.integer(.data$week) == !!week) |>
    dplyr::mutate(predicted_at = as.POSIXct(.data$predicted_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  kickoffs |>
    dplyr::mutate(
      latest_valid_run = purrr::map_chr(.data$kickoff_utc, function(k) {
        ok <- m$predicted_at < k
        if (!any(ok)) NA_character_ else m$run_id[ok][which.max(m$predicted_at[ok])]
      }),
      lineages = m$lineages[match(.data$latest_valid_run, m$run_id)]
    )
}

#' Directories holding irreplaceable prospective evidence or needed to rebuild it.
BACKUP_DIRS <- c("data/archive", "data/snapshots", "data/raw/nflverse_live", "data/raw/espn/season=2026")

#' Copy the evidence directories to a private destination (an external drive or
#' a private folder of your choosing), then verify every copied file by SHA-256.
#' Never deletes anything at the destination.
backup_archives <- function(dest, dirs = BACKUP_DIRS, marker = "data/.last_backup") {
  if (!dir.exists(dest)) cli::cli_abort("Backup destination {.file {dest}} does not exist. Create it first.")
  stamp <- utc_stamp()
  rows <- purrr::map(dirs[dir.exists(dirs)], function(d) {
    files <- list.files(d, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    purrr::map(files, function(f) {
      target <- file.path(dest, f)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      src_hash <- sha256_file(f)
      if (!file.exists(target) || !identical(sha256_file(target), src_hash)) file.copy(f, target, overwrite = TRUE)
      tibble::tibble(path = f, sha256 = src_hash, verified = identical(sha256_file(target), src_hash))
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
  readr::write_csv(rows, file.path(dest, paste0("backup_manifest_", stamp, ".csv")))
  # Record when the last verified backup happened (local, git-ignored).
  writeLines(c(stamp, dest), marker)
  if (!all(rows$verified)) cli::cli_abort("{sum(!rows$verified)} file{?s} failed verification at the destination.")
  rows
}

last_backup <- function() {
  if (!file.exists("data/.last_backup")) return(NULL)
  x <- readLines("data/.last_backup")
  list(at = parse_utc_stamp(x[1]), dest = x[2])
}

#' Newest modification time among the evidence directories.
newest_evidence <- function(dirs = BACKUP_DIRS) {
  files <- unlist(lapply(dirs[dir.exists(dirs)], list.files, recursive = TRUE, full.names = TRUE))
  if (length(files) == 0) return(NA)
  max(file.mtime(files))
}

#' Print a weekly status dashboard.
print_status <- function(season, now = Sys.time()) {
  cfg <- read_project_config()
  sched <- tryCatch(latest_live_file("schedules", season, now), error = function(e) NA_character_)
  cli::cli_h1("FFball prospective status - {fmt_utc(now)}")
  if (is.na(sched)) {
    cli::cli_alert_danger("No live schedule retrieval for {season}. Run scripts/weekly_run.R.")
    return(invisible(NULL))
  }
  tg <- clean_team_games(sched, cfg$season_type)
  week <- infer_target_week(tg, season, now)
  cli::cli_text("Season {season}; next week to predict: {.strong {week}}. ESPN fetching enabled: {isTRUE(cfg$espn$enabled)}")
  ko <- week_kickoffs(tg, season, week, now)
  cov <- week_coverage(season, week, ko)
  nxt <- ko$kickoff_utc[!ko$started][1]
  cli::cli_text("Next kickoff: {fmt_utc(nxt)} ({round(as.numeric(difftime(nxt, now, units = 'hours')), 1)} h from now).")
  cli::cli_text("Games started this week: {sum(ko$started)} of {nrow(ko)}.")
  uncovered <- dplyr::filter(cov, !.data$started, is.na(.data$latest_valid_run))
  if (nrow(uncovered) > 0) {
    cli::cli_alert_warning("{nrow(uncovered)} upcoming game{?s} have NO archived prediction run yet.")
  } else {
    cli::cli_alert_success("Every upcoming game has an archived run (lineages: {paste(unique(cov$lineages), collapse = ', ')}).")
  }
  snaps <- list_snapshots(season, week)
  cli::cli_text("ESPN snapshots for week {week}: {nrow(snaps)}{if (nrow(snaps)) paste0(' (latest ', fmt_utc(max(snaps$captured_at)), ')') else ''}.")
  pv <- verify_prediction_archive()
  sv <- verify_snapshot_archive()
  if (all(pv$verified) && all(sv$parquet_ok & sv$raw_ok)) {
    cli::cli_alert_success("Archive integrity: {nrow(pv)} prediction run{?s} and {nrow(sv)} snapshot{?s} match their committed hashes.")
  } else {
    cli::cli_alert_danger("Archive integrity FAILURE: missing or altered files. See verify_prediction_archive() / verify_snapshot_archive().")
  }
  g <- git_sync_state()
  if (isTRUE(g$manifests_uncommitted)) cli::cli_alert_warning("Manifests have uncommitted changes: commit and push before the next kickoff.")
  if (isTRUE(g$commits_not_pushed > 0)) cli::cli_alert_warning("{g$commits_not_pushed} local commit{?s} not pushed: run git push before the next kickoff.")
  if (!isTRUE(g$manifests_uncommitted) && isTRUE(g$commits_not_pushed == 0)) cli::cli_alert_success("Manifests committed and pushed.")
  lb <- last_backup()
  ne <- newest_evidence()
  if (is.null(lb)) {
    cli::cli_alert_warning("No private backup recorded. Run: Rscript scripts/backup_archives.R <private folder>")
  } else if (!is.na(ne) && ne > lb$at) {
    cli::cli_alert_warning("Evidence changed since the last backup ({fmt_utc(lb$at)}). Back up again.")
  } else {
    cli::cli_alert_success("Last verified backup {fmt_utc(lb$at)} -> {lb$dest}")
  }
  invisible(list(week = week, kickoffs = ko, coverage = cov))
}
