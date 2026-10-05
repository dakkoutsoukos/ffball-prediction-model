# ESPN weekly projections --------------------------------------------------------
#
# Source: ESPN's public fantasy API (no credentials), league-default PPR scoring
#   GET https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{S}/
#       segments/0/leaguedefaults/3?scoringPeriodId={W}&view=kona_player_info
#   with an X-Fantasy-Filter header selecting one lineup slot (WR = 4) and the
#   weekly projected (statSourceId 1) and actual (statSourceId 0) splits.
#
# As-of semantics and the evidence behind them: docs/espn_projections.md.
#
# TERMS OF USE: ESPN content is governed by the Disney Terms of Use, which
# restrict automated extraction and use in benchmarking ML models. Fetching is
# therefore DISABLED unless config `espn.enabled: true` is set deliberately by
# the project owner. Fetched data must never be committed to this repository.

ESPN_API <- "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl"
ESPN_POSITION_IDS <- c(QB = 1L, RB = 2L, WR = 3L, TE = 4L)
ESPN_SLOT_IDS <- c(QB = 0L, RB = 2L, WR = 4L, TE = 6L)
ESPN_STAT_IDS <- c(receptions = "53", targets = "58", receiving_yards = "42",
                   receiving_tds = "43", rushing_attempts = "23", rushing_yards = "24")

espn_filter_header <- function(week, slot_id, limit = 2000) {
  jsonlite::toJSON(list(players = list(
    filterSlotIds = list(value = list(slot_id)),
    limit = limit,
    sortPercOwned = list(sortPriority = 1, sortAsc = FALSE),
    filterStatsForSourceIds = list(value = list(0, 1)),
    filterStatsForSplitTypeIds = list(value = list(1)),
    filterStatsForScoringPeriodIds = list(value = list(week))
  )), auto_unbox = TRUE)
}

espn_request <- function(url, filter = NULL) {
  req <- httr2::request(url) |>
    httr2::req_headers(Accept = "application/json") |>
    httr2::req_user_agent("ffball-prediction-model (personal research)") |>
    httr2::req_retry(max_tries = 3, backoff = function(i) 5 * i) |>
    httr2::req_timeout(60)
  if (!is.null(filter)) req <- httr2::req_headers(req, `X-Fantasy-Filter` = filter)
  req
}

stop_if_espn_disabled <- function(enabled) {
  if (!isTRUE(enabled)) {
    cli::cli_abort(c(
      "ESPN fetching is disabled (config {.field espn.enabled} is not true).",
      "i" = "See docs/espn_projections.md (terms-of-use section) before enabling."
    ))
  }
}

espn_raw_path <- function(season, week, position, root = "data/raw/espn") {
  file.path(root, sprintf("season=%d", season),
            sprintf("espn_%s_%d_w%02d.json.gz", tolower(position), season, week))
}

#' Fetch one season-week of ESPN weekly projections + actuals for a position
#' and store the raw response (gzipped JSON) immutably. Returns the path.
fetch_espn_week <- function(season, week, position = "WR", league_defaults_id = 3,
                            pause = 1.5, root = "data/raw/espn", enabled = FALSE,
                            refresh = FALSE) {
  path <- espn_raw_path(season, week, position, root)
  if (file.exists(path) && !refresh) return(path)
  stop_if_espn_disabled(enabled)
  url <- sprintf("%s/seasons/%d/segments/0/leaguedefaults/%d?scoringPeriodId=%d&view=kona_player_info",
                 ESPN_API, season, league_defaults_id, week)
  body <- espn_request(url, espn_filter_header(week, ESPN_SLOT_IDS[[position]])) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(path, "w")
  writeLines(body, con)
  close(con)
  jsonlite::write_json(list(
    provider = "ESPN", dataset = "kona_player_info weekly", season = season, week = week,
    position = position, league_defaults_id = league_defaults_id, url = url,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    asof = "retrieved retroactively; stored value is ESPN's final pregame projection (see docs)"
  ), paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  Sys.sleep(pause)
  path
}

#' Fetch (or reuse cached) raw files for a grid of season-weeks. Returns a
#' tibble of paths and content hashes so downstream targets rebuild if a raw
#' file changes. With `enabled = FALSE`, only already-cached files are used.
fetch_espn_weeks <- function(grid, position = "WR", league_defaults_id = 3, pause = 1.5,
                             root = "data/raw/espn", enabled = FALSE) {
  paths <- purrr::map2_chr(grid$season, grid$week, function(s, w) {
    path <- espn_raw_path(s, w, position, root)
    if (file.exists(path)) return(path)
    if (!isTRUE(enabled)) return(NA_character_)
    fetch_espn_week(s, w, position, league_defaults_id, pause, root, enabled = TRUE)
  })
  paths <- paths[!is.na(paths)]
  tibble::tibble(path = paths, md5 = unname(tools::md5sum(paths)))
}

#' Regular-season (season, week) pairs from raw schedule files.
regular_season_weeks <- function(schedule_paths) {
  read_parquet_files(schedule_paths) |>
    dplyr::filter(.data$game_type == "REG") |>
    dplyr::distinct(season = as.integer(.data$season), week = as.integer(.data$week)) |>
    dplyr::arrange(.data$season, .data$week)
}

#' Parse one raw kona_player_info response into one row per player.
#' espn_proj / espn_actual are ESPN's appliedTotal for the weekly projected /
#' actual split of exactly this season and week (NA when ESPN has no entry).
parse_espn_week <- function(json, season, week) {
  doc <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  rows <- purrr::map(doc$players, function(p) {
    pl <- p$player
    pick <- function(source_id) {
      hits <- Filter(function(s) {
        identical(as.integer(s$seasonId), as.integer(season)) &&
          identical(as.integer(s$scoringPeriodId), as.integer(week)) &&
          identical(as.integer(s$statSplitTypeId), 1L) &&
          identical(as.integer(s$statSourceId), as.integer(source_id))
      }, pl$stats %||% list())
      if (length(hits) <= 1) return(if (length(hits) == 0) NULL else hits[[1]])
      # Actuals are keyed by game (externalId = ESPN game id). A player moved
      # between teams mid-week can carry an extra, empty game entry (seen once
      # in 2018-2025: 2020 W8). Per-game actuals are summed. Duplicate
      # projections have no such explanation and fail loudly.
      if (source_id != 0L) {
        cli::cli_abort("ESPN player {pl$id}: {length(hits)} projection entries for {season} week {week}.")
      }
      ids <- unique(unlist(lapply(hits, function(h) names(h$stats))))
      list(
        appliedTotal = sum(vapply(hits, function(h) as.numeric(h$appliedTotal %||% 0), numeric(1))),
        stats = stats::setNames(lapply(ids, function(id) {
          sum(vapply(hits, function(h) as.numeric(h$stats[[id]] %||% 0), numeric(1)))
        }), ids)
      )
    }
    stat_val <- function(entry, id) {
      if (is.null(entry)) return(NA_real_)
      v <- entry$stats[[id]]
      if (is.null(v)) 0 else as.numeric(v)
    }
    proj <- pick(1L)
    act <- pick(0L)
    out <- tibble::tibble(
      espn_id = as.character(pl$id),
      espn_name = pl$fullName %||% NA_character_,
      espn_position_id = as.integer(pl$defaultPositionId %||% NA),
      espn_pro_team_id = as.integer(pl$proTeamId %||% NA),
      espn_proj = if (is.null(proj)) NA_real_ else as.numeric(proj$appliedTotal %||% 0),
      espn_actual = if (is.null(act)) NA_real_ else as.numeric(act$appliedTotal %||% 0)
    )
    for (nm in names(ESPN_STAT_IDS)) out[[paste0("espn_proj_", nm)]] <- stat_val(proj, ESPN_STAT_IDS[[nm]])
    out
  })
  purrr::list_rbind(rows) |>
    dplyr::mutate(season = as.integer(season), week = as.integer(week), .before = 1)
}

#' Parse all cached raw files into one validated table.
parse_espn_files <- function(raw_espn) {
  if (nrow(raw_espn) == 0) return(empty_espn_weekly())
  purrr::map(raw_espn$path, function(path) {
    sw <- regmatches(basename(path), regexec("_(\\d{4})_w(\\d{2})", basename(path)))[[1]]
    parse_espn_week(paste(readLines(gzfile(path), warn = FALSE), collapse = "\n"),
                    as.integer(sw[2]), as.integer(sw[3]))
  }) |>
    purrr::list_rbind() |>
    assert_unique_key(c("season", "week", "espn_id"), "espn_weekly") |>
    assert_in_range("espn_proj", 0, 80, "espn_weekly")
}

empty_espn_weekly <- function() {
  out <- tibble::tibble(
    season = integer(), week = integer(), espn_id = character(), espn_name = character(),
    espn_position_id = integer(), espn_pro_team_id = integer(),
    espn_proj = double(), espn_actual = double()
  )
  for (nm in names(ESPN_STAT_IDS)) out[[paste0("espn_proj_", nm)]] <- double()
  out
}

# --- Forward archive of live projections ----------------------------------------

#' Snapshot ESPN's projections as they stand *right now* for a live week.
#' Writes data/snapshots/espn/season=S/week=WW/captured_at=<UTC>.parquet (+ raw
#' gzipped JSON). Each capture is a genuine point-in-time record; running it
#' repeatedly through the week (e.g. Tue, Thu, Sat, Sun 11:00 ET) builds the
#' pristine archive that historical retrieval cannot guarantee.
#' `week = NULL` uses ESPN's current scoring period (which rolls over on
#' Tuesdays); pass a week number to capture an upcoming week.
snapshot_espn_projections <- function(position = "WR", league_defaults_id = 3, week = NULL,
                                      root = "data/snapshots/espn", enabled = FALSE) {
  stop_if_espn_disabled(enabled)
  status <- espn_request(ESPN_API) |> httr2::req_perform() |> httr2::resp_body_json()
  season <- as.integer(status$currentSeason$id %||% status$seasonId)
  week <- as.integer(week %||% status$currentScoringPeriod$id)
  if (length(season) != 1 || is.na(season) || length(week) != 1 || is.na(week)) {
    cli::cli_abort("Could not determine the live ESPN season/week.")
  }
  captured_at <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")

  url <- sprintf("%s/seasons/%d/segments/0/leaguedefaults/%d?scoringPeriodId=%d&view=kona_player_info",
                 ESPN_API, season, league_defaults_id, week)
  body <- espn_request(url, espn_filter_header(week, ESPN_SLOT_IDS[[position]])) |>
    httr2::req_perform() |>
    httr2::resp_body_string()

  # Snapshots are immutable: write_once() refuses to overwrite an existing file.
  dir <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week))
  stem <- sprintf("captured_at=%s_%s", captured_at, tolower(position))
  raw_path <- write_once(file.path(dir, paste0(stem, ".json.gz")), function(tmp) {
    con <- gzfile(tmp, "w")
    writeLines(body, con)
    close(con)
  })
  snap <- parse_espn_week(body, season, week) |>
    dplyr::mutate(
      provider = "ESPN", position = position, captured_at_utc = captured_at,
      team = espn_team(.data$espn_pro_team_id),  # live team id = team at capture time
      league_defaults_id = as.integer(league_defaults_id), source_url = url,
      raw_sha256 = sha256_file(raw_path)
    )
  out <- write_once(file.path(dir, paste0(stem, ".parquet")), function(tmp) arrow::write_parquet(snap, tmp))
  register_snapshot(out, raw_path)
  out
}

#' Append a snapshot's hashes to the committed, append-only snapshot manifest.
register_snapshot <- function(parquet_path, raw_path, manifest = SNAPSHOT_MANIFEST) {
  snap <- arrow::read_parquet(parquet_path)
  if (file.exists(manifest)) {
    old <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
    if (basename(parquet_path) %in% old$file) cli::cli_abort("Snapshot {.file {parquet_path}} already registered.")
  }
  append_manifest(tibble::tibble(
    file = basename(parquet_path), season = unique(snap$season), week = unique(snap$week),
    position = unique(snap$position), captured_at_utc = unique(snap$captured_at_utc),
    n_players = nrow(snap), n_projected = sum(snap$espn_proj > 0, na.rm = TRUE),
    parquet_sha256 = sha256_file(parquet_path), raw_sha256 = sha256_file(raw_path)
  ), manifest)
}

#' Retroactively fetch ESPN weekly data for weeks of a live season whose games
#' are ALL final (training rows only; never used as the prospective benchmark).
fetch_espn_completed_weeks <- function(season, team_games, enabled = FALSE, pause = 1.5) {
  done <- team_games |>
    dplyr::filter(.data$season == !!season) |>
    dplyr::summarise(all_final = all(.data$game_final), .by = "week") |>
    dplyr::filter(.data$all_final)
  purrr::map_chr(sort(done$week), ~ fetch_espn_week(season, .x, enabled = enabled, pause = pause))
}

# --- ESPN <-> nflverse identity -------------------------------------------------

normalize_name <- function(x) {
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- tolower(x)
  x <- gsub("[.'`-]", "", x)
  x <- gsub("\\s+(jr|sr|ii|iii|iv|v)$", "", x)
  trimws(gsub("\\s+", " ", x))
}

#' Map ESPN player ids to gsis ids using ID columns only (no fuzzy matching).
#'
#' Candidate (espn_id, gsis_id) pairs come from three nflverse sources: the
#' player master, weekly rosters, and the DynastyProcess ID map. A pair is
#' accepted when every source agrees ("id_unanimous"). When sources conflict,
#' the conflict is resolved only if exactly one candidate's normalised name
#' equals ESPN's name ("id_conflict_name_resolved"); otherwise the ESPN id is
#' left unmatched ("ambiguous"). ESPN ids with no candidate are "unmatched".
build_espn_crosswalk <- function(espn_weekly, rosters_weekly, players, ff_playerids) {
  pairs <- dplyr::bind_rows(
    players = dplyr::transmute(players, espn_id = as.character(.data$espn_id), gsis_id = .data$gsis_id,
                               nfl_name = .data$display_name),
    rosters = dplyr::transmute(rosters_weekly, espn_id = as.character(.data$roster_espn_id),
                               gsis_id = .data$gsis_id, nfl_name = .data$roster_name),
    ff_playerids = dplyr::transmute(ff_playerids, espn_id = as.character(.data$espn_id),
                                    gsis_id = .data$gsis_id, nfl_name = .data$name),
    .id = "source"
  ) |>
    dplyr::filter(!is.na(.data$espn_id), !is.na(.data$gsis_id), .data$espn_id != "") |>
    dplyr::distinct(.data$source, .data$espn_id, .data$gsis_id, .keep_all = TRUE)

  espn_ids <- espn_weekly |>
    dplyr::distinct(.data$espn_id, .data$espn_name) |>
    dplyr::distinct(.data$espn_id, .keep_all = TRUE)

  cand <- pairs |>
    dplyr::semi_join(espn_ids, by = "espn_id") |>
    dplyr::summarise(sources = paste(sort(unique(.data$source)), collapse = "+"),
                     nfl_name = dplyr::first(.data$nfl_name), .by = c("espn_id", "gsis_id")) |>
    dplyr::left_join(espn_ids, by = "espn_id") |>
    dplyr::mutate(n_cand = dplyr::n(), .by = "espn_id") |>
    dplyr::mutate(name_match = normalize_name(.data$nfl_name) == normalize_name(.data$espn_name))

  resolved <- cand |>
    dplyr::mutate(n_name = sum(.data$name_match), .by = "espn_id") |>
    dplyr::filter(.data$n_cand == 1 | (.data$name_match & .data$n_name == 1)) |>
    dplyr::mutate(match_method = dplyr::if_else(.data$n_cand == 1, "id_unanimous", "id_conflict_name_resolved"))

  out <- espn_ids |>
    dplyr::left_join(dplyr::select(resolved, "espn_id", "gsis_id", "match_method", "sources", "name_match"),
                     by = "espn_id") |>
    dplyr::mutate(match_method = dplyr::case_when(
      !is.na(.data$match_method) ~ .data$match_method,
      .data$espn_id %in% cand$espn_id ~ "ambiguous",
      TRUE ~ "unmatched"
    ))
  # Two ESPN ids must never map to the same gsis id.
  dup_gsis <- out |> dplyr::filter(!is.na(.data$gsis_id)) |> dplyr::count(.data$gsis_id) |> dplyr::filter(.data$n > 1)
  out |>
    dplyr::mutate(
      match_method = dplyr::if_else(.data$gsis_id %in% dup_gsis$gsis_id, "ambiguous", .data$match_method),
      gsis_id = dplyr::if_else(.data$match_method == "ambiguous", NA_character_, .data$gsis_id)
    ) |>
    assert_unique_key("espn_id", "espn_crosswalk")
}

#' Compare our ESPN-PPR scoring of nflverse stats to ESPN's own actual totals.
validate_scoring_against_espn <- function(player_stats, espn_weekly, espn_crosswalk, tol = 0.011) {
  if (nrow(espn_weekly) == 0) {
    return(list(available = FALSE, summary = tibble::tibble(), mismatches = tibble::tibble()))
  }
  cmp <- espn_weekly |>
    dplyr::filter(!is.na(.data$espn_actual)) |>
    dplyr::inner_join(dplyr::filter(espn_crosswalk, !is.na(.data$gsis_id)) |> dplyr::select("espn_id", "gsis_id"),
                      by = "espn_id") |>
    dplyr::inner_join(player_stats, by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(diff = .data$fantasy_pts - .data$espn_actual,
                  nflverse_diff = .data$nflverse_ppr - .data$espn_actual)
  list(
    available = TRUE,
    summary = cmp |>
      dplyr::summarise(
        n = dplyr::n(),
        share_exact_ours = mean(abs(.data$diff) < tol),
        share_exact_nflverse = mean(abs(.data$nflverse_diff) < tol),
        mean_abs_diff_ours = mean(abs(.data$diff)),
        .by = "season"
      ),
    mismatches = dplyr::filter(cmp, abs(.data$diff) >= tol) |>
      dplyr::select("season", "week", "gsis_id", "player_name", "fantasy_pts", "espn_actual",
                    "nflverse_ppr", "fumbles_lost_total", "receiving_fumbles_lost",
                    "fumble_recovery_tds", "special_teams_tds", "receiving_2pt_conversions")
  )
}
