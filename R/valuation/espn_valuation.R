# Valuation: ESPN inputs for all skill positions ------------------------------------------
# Separate from the projection track's WR-only ESPN code (R/data/espn.R), which
# is reused for requests and team ids but never modified. Data locations
# (all git-ignored):
#   data/raw/espn_valuation/season=S/espn_qbrbte_S_wWW.json.gz   historical week-of
#       projections + actuals for QB/RB/TE (WR history comes from data/raw/espn/)
#   data/snapshots/espn_valuation/season=S/week=WW/captured_at=<UTC>.{json.gz,parquet}
#       point-in-time captures of the current week AND every posted future week
# Captures are hashed into the committed, append-only
# archive/valuation_espn_capture_manifest.csv. Same ESPN opt-in as the
# projection track (config `espn.enabled`, docs/espn_projections.md).

VAL_ESPN_RAW_ROOT <- "data/raw/espn_valuation"
VAL_ESPN_SNAPSHOT_ROOT <- "data/snapshots/espn_valuation"
VAL_ESPN_CAPTURE_MANIFEST <- "archive/valuation_espn_capture_manifest.csv"
VAL_POSITIONS <- c("QB", "RB", "WR", "TE")

#' ESPN stat ids -> scoring-rule stat names (config/scoring/*.yml). Verified on
#' 2026 captures: rescoring ESPN's projected and actual stat lines with
#' espn_ppr reproduces ESPN's appliedTotal (actuals exactly; projections to
#' < 0.07 points for 14 of 5,620 rows, 0 otherwise). Return TDs (101 kick,
#' 102 punt) both map to special_teams_tds.
VAL_ESPN_STAT_MAP <- c(
  `3` = "passing_yards", `4` = "passing_tds", `19` = "passing_2pt_conversions",
  `20` = "passing_interceptions", `24` = "rushing_yards", `25` = "rushing_tds",
  `26` = "rushing_2pt_conversions", `53` = "receptions", `42` = "receiving_yards",
  `43` = "receiving_tds", `44` = "receiving_2pt_conversions", `72` = "fumbles_lost_total",
  `101` = "special_teams_tds", `102` = "special_teams_tds", `63` = "fumble_recovery_tds"
)

val_espn_position <- function(position_id) {
  unname(c(`1` = "QB", `2` = "RB", `3` = "WR", `4` = "TE")[as.character(position_id)])
}

#' X-Fantasy-Filter for several lineup slots, scoring periods, sources and split types.
val_espn_filter <- function(periods, slot_ids, limit = 3000, sources = c(0, 1), split_types = 1) {
  jsonlite::toJSON(list(players = list(
    filterSlotIds = list(value = as.list(unname(slot_ids))),
    limit = limit,
    sortPercOwned = list(sortPriority = 1, sortAsc = FALSE),
    filterStatsForSourceIds = list(value = as.list(unname(sources))),
    filterStatsForSplitTypeIds = list(value = as.list(split_types)),
    filterStatsForScoringPeriodIds = list(value = as.list(unname(periods)))
  )), auto_unbox = TRUE)
}

val_espn_url <- function(season, week, league_defaults_id = 3) {
  sprintf("%s/seasons/%d/segments/0/leaguedefaults/%d?scoringPeriodId=%d&view=kona_player_info",
          ESPN_API, season, league_defaults_id, week)
}

val_espn_raw_path <- function(season, week, root = VAL_ESPN_RAW_ROOT) {
  file.path(root, sprintf("season=%d", season), sprintf("espn_qbrbte_%d_w%02d.json.gz", season, week))
}

write_gz_text <- function(path, body) {
  con <- gzfile(path, "w")
  on.exit(close(con))
  writeLines(body, con)
}

read_gz_text <- function(path) paste(readLines(gzfile(path), warn = FALSE), collapse = "\n")

#' Fetch one season-week of ESPN week-of projections + actuals for QB, RB and TE
#' in ONE request and cache it immutably (WR history already exists). Returns
#' the path. Past weeks hold ESPN's final pregame values (docs/espn_projections.md).
val_fetch_espn_week <- function(season, week, league_defaults_id = 3, pause = 1.5,
                                root = VAL_ESPN_RAW_ROOT, enabled = FALSE, limit = 3000) {
  path <- val_espn_raw_path(season, week, root)
  if (file.exists(path)) return(path)
  stop_if_espn_disabled(enabled)
  url <- val_espn_url(season, week, league_defaults_id)
  body <- espn_request(url, val_espn_filter(week, ESPN_SLOT_IDS[c("QB", "RB", "TE")], limit)) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  n <- length(jsonlite::fromJSON(body, simplifyVector = FALSE)$players)
  if (n >= limit) cli::cli_abort("ESPN returned {n} players (limit {limit}); the response may be truncated.")
  write_once(path, function(tmp) write_gz_text(tmp, body))
  jsonlite::write_json(list(
    provider = "ESPN", dataset = "kona_player_info weekly (QB/RB/TE)", season = season, week = week,
    slots = unname(ESPN_SLOT_IDS[c("QB", "RB", "TE")]), league_defaults_id = league_defaults_id,
    url = url, n_players = n, retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    asof = "retrieved retroactively; past weeks hold ESPN's final pregame projection"
  ), paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  Sys.sleep(pause)
  path
}

#' Cached (or, when enabled, fetched) QB/RB/TE files for a grid of season-weeks.
val_fetch_espn_weeks <- function(grid, league_defaults_id = 3, pause = 1.5, root = VAL_ESPN_RAW_ROOT,
                                 enabled = FALSE) {
  paths <- purrr::map2_chr(grid$season, grid$week, function(s, w) {
    path <- val_espn_raw_path(s, w, root)
    if (file.exists(path)) return(path)
    if (!isTRUE(enabled)) return(NA_character_)
    val_fetch_espn_week(s, w, league_defaults_id, pause, root, enabled = TRUE)
  })
  paths <- paths[!is.na(paths)]
  tibble::tibble(path = paths, md5 = unname(tools::md5sum(paths)))
}

#' Parse a kona_player_info response into one row per (player, scoring period,
#' source): ESPN appliedTotal plus the scoring-relevant stat line (named by
#' VAL_ESPN_STAT_MAP) and player-level fields (injury status, ownership).
#' `periods` restricts scoring periods; only `season` entries with split type 1
#' (single week) are kept. Per-game actual entries in one week are summed.
val_parse_espn <- function(json, season, periods = NULL, sources = c(0L, 1L)) {
  doc <- if (is.character(json)) jsonlite::fromJSON(json, simplifyVector = FALSE) else json
  ids <- names(VAL_ESPN_STAT_MAP)
  stat_names <- unique(unname(VAL_ESPN_STAT_MAP))
  # ESPN stat id -> stat name aggregation matrix (two return-TD ids share one name)
  agg <- outer(unname(VAL_ESPN_STAT_MAP), stat_names, `==`) * 1
  season <- as.integer(season)
  recs <- vector("list", length(doc$players))
  for (i in seq_along(doc$players)) {
    pl <- doc$players[[i]]$player
    st <- pl$stats %||% list()
    if (!length(st)) next
    num <- function(f, d = NA) vapply(st, function(s) as.numeric(s[[f]] %||% d), 0)
    keep <- num("seasonId") == season & num("statSplitTypeId") == 1 & num("statSourceId") %in% sources
    if (!is.null(periods)) keep <- keep & num("scoringPeriodId") %in% periods
    st <- st[keep]
    if (!length(st)) next
    m <- vapply(st, function(s) {
      v <- s$stats
      out <- numeric(length(ids))
      if (length(v)) {
        hit <- match(names(v), ids)
        ok <- !is.na(hit)
        out[hit[ok]] <- as.numeric(unlist(v[ok]))
      }
      out
    }, numeric(length(ids)))
    own <- pl$ownership %||% list()
    recs[[i]] <- list(
      espn_id = rep(as.character(pl$id), length(st)), espn_name = rep(pl$fullName %||% NA_character_, length(st)),
      espn_position_id = rep(as.integer(pl$defaultPositionId %||% NA), length(st)),
      espn_pro_team_id = rep(as.integer(pl$proTeamId %||% NA), length(st)),
      injury_status = rep(pl$injuryStatus %||% NA_character_, length(st)),
      pct_owned = rep(as.numeric(own$percentOwned %||% NA), length(st)),
      pct_started = rep(as.numeric(own$percentStarted %||% NA), length(st)),
      week = as.integer(num("scoringPeriodId")), source = as.integer(num("statSourceId")),
      applied_total = num("appliedTotal", 0), n_stats = vapply(st, function(s) length(s$stats), 0),
      stats = t(m) %*% agg
    )
  }
  recs <- Filter(Negate(is.null), recs)
  if (!length(recs)) return(val_empty_espn_long())
  cols <- setdiff(names(recs[[1]]), "stats")
  out <- tibble::as_tibble(lapply(stats::setNames(cols, cols), function(cn) unlist(lapply(recs, `[[`, cn))))
  sm <- do.call(rbind, lapply(recs, `[[`, "stats"))
  colnames(sm) <- stat_names
  out <- dplyr::bind_cols(out, tibble::as_tibble(sm))
  # actuals can come as one entry per game (a mid-week trade); projections must be unique
  dup <- dplyr::count(dplyr::filter(out, .data$source == 1L), .data$espn_id, .data$week) |> dplyr::filter(.data$n > 1)
  if (nrow(dup)) cli::cli_abort("ESPN player {dup$espn_id[1]}: duplicate projection entries for {season}.")
  out <- out |>
    dplyr::summarise(dplyr::across(c("applied_total", "n_stats", dplyr::all_of(stat_names)), sum),
                     .by = c("espn_id", "espn_name", "espn_position_id", "espn_pro_team_id", "injury_status",
                             "pct_owned", "pct_started", "week", "source"))
  out |>
    dplyr::mutate(season = season, position = val_espn_position(.data$espn_position_id), .before = 1)
}

val_empty_espn_long <- function() {
  out <- tibble::tibble(season = integer(), position = character(), espn_id = character(), espn_name = character(),
                        espn_position_id = integer(), espn_pro_team_id = integer(), injury_status = character(),
                        pct_owned = double(), pct_started = double(), week = integer(), source = integer(),
                        applied_total = double(), n_stats = double())
  for (nm in unique(unname(VAL_ESPN_STAT_MAP))) out[[nm]] <- double()
  out
}

#' Week-of projections and actuals for QB/RB/WR/TE in one wide table, one row per
#' (season, week, espn_id): `espn_proj`, `espn_actual` (NA when ESPN has no
#' entry). WR rows come from the projection track's raw files (read-only).
val_espn_weekly <- function(qbrbte_paths, wr_paths) {
  parse_file <- function(path) {
    sw <- regmatches(basename(path), regexec("_(\\d{4})_w(\\d{2})", basename(path)))[[1]]
    s <- as.integer(sw[2])
    w <- as.integer(sw[3])
    val_parse_espn(read_gz_text(path), s, periods = w)
  }
  long <- purrr::map(c(qbrbte_paths, wr_paths), parse_file) |> purrr::list_rbind()
  if (!nrow(long)) long <- val_empty_espn_long()
  long <- dplyr::filter(long, .data$position %in% VAL_POSITIONS)
  # WR files filter on the WR slot; QB/RB/TE files on their slots. A player can
  # appear in both only through multi-slot eligibility; keep his default position.
  long <- dplyr::distinct(long, .data$season, .data$week, .data$espn_id, .data$source, .keep_all = TRUE)
  proj <- dplyr::filter(long, .data$source == 1L) |>
    dplyr::select("season", "week", "espn_id", "espn_name", "position", "espn_pro_team_id", espn_proj = "applied_total")
  act <- dplyr::filter(long, .data$source == 0L) |>
    dplyr::select("season", "week", "espn_id", espn_actual = "applied_total", espn_actual_n_stats = "n_stats")
  dplyr::full_join(proj, act, by = c("season", "week", "espn_id")) |>
    dplyr::left_join(dplyr::distinct(dplyr::select(long, "season", "espn_id", name2 = "espn_name", pos2 = "position")),
                     by = c("season", "espn_id"), relationship = "many-to-many") |>
    dplyr::mutate(espn_name = dplyr::coalesce(.data$espn_name, .data$name2),
                  position = dplyr::coalesce(.data$position, .data$pos2)) |>
    dplyr::select(-"name2", -"pos2") |>
    dplyr::distinct(.data$season, .data$week, .data$espn_id, .keep_all = TRUE) |>
    assert_unique_key(c("season", "week", "espn_id"), "val_espn_weekly") |>
    assert_in_range("espn_proj", -2, 80, "val_espn_weekly")
}

# --- Point-in-time capture (current + all posted future weeks) ------------------------------

#' Capture ESPN's posted projections for the current week and every later week
#' of the season, for QB/RB/WR/TE, in one request. Writes the raw response and a
#' parsed long parquet write-once, and registers both hashes in the committed
#' capture manifest. Returns the parquet path.
capture_espn_valuation <- function(week = NULL, league_defaults_id = 3, last_period = 18,
                                   root = VAL_ESPN_SNAPSHOT_ROOT, manifest = VAL_ESPN_CAPTURE_MANIFEST,
                                   enabled = FALSE, limit = 3000) {
  stop_if_espn_disabled(enabled)
  status <- espn_request(ESPN_API) |> httr2::req_perform() |> httr2::resp_body_json()
  season <- as.integer(status$currentSeason$id %||% status$seasonId)
  week <- as.integer(week %||% status$currentScoringPeriod$id)
  if (length(season) != 1 || is.na(season) || length(week) != 1 || is.na(week)) {
    cli::cli_abort("Could not determine the live ESPN season/week.")
  }
  captured_at <- utc_stamp()
  url <- val_espn_url(season, week, league_defaults_id)
  body <- espn_request(url, val_espn_filter(week:last_period, ESPN_SLOT_IDS[VAL_POSITIONS], limit, sources = 1)) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  doc <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  if (length(doc$players) >= limit) cli::cli_abort("ESPN capture may be truncated ({length(doc$players)} players).")

  dir <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week))
  stem <- sprintf("captured_at=%s", captured_at)
  raw_path <- write_once(file.path(dir, paste0(stem, ".json.gz")), function(tmp) write_gz_text(tmp, body))
  snap <- val_parse_espn(doc, season, periods = week:last_period, sources = 1L) |>
    dplyr::filter(.data$position %in% VAL_POSITIONS) |>
    dplyr::mutate(capture_week = as.integer(week), captured_at_utc = captured_at,
                  team = espn_team(.data$espn_pro_team_id),  # live team id = team at capture time
                  league_defaults_id = as.integer(league_defaults_id), source_url = url,
                  raw_sha256 = sha256_file(raw_path))
  out <- write_once(file.path(dir, paste0(stem, ".parquet")), function(tmp) arrow::write_parquet(snap, tmp))
  append_manifest(tibble::tibble(
    file = basename(out), season = season, week = week, captured_at_utc = captured_at,
    n_players = dplyr::n_distinct(snap$espn_id), n_rows = nrow(snap),
    periods = paste(range(snap$week), collapse = "-"),
    parquet_sha256 = sha256_file(out), raw_sha256 = sha256_file(raw_path)
  ), manifest)
  out
}

#' Latest valuation capture for a season-week made at or before `as_of`.
latest_valuation_capture <- function(season, week, as_of = Sys.time(), root = VAL_ESPN_SNAPSHOT_ROOT) {
  dir <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week))
  files <- list.files(dir, pattern = "^captured_at=.*[.]parquet$", full.names = TRUE)
  stamps <- parse_utc_stamp(sub("^captured_at=([0-9TZ]+)[.]parquet$", "\\1", basename(files)))
  ok <- !is.na(stamps) & stamps <= as_of
  if (!any(ok)) return(NA_character_)
  files[ok][which.max(stamps[ok])]
}

#' Verify every registered capture against the manifest hashes.
verify_valuation_captures <- function(manifest = VAL_ESPN_CAPTURE_MANIFEST, root = VAL_ESPN_SNAPSHOT_ROOT) {
  if (!file.exists(manifest)) return(tibble::tibble())
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
  purrr::pmap(m, function(file, season, week, parquet_sha256, raw_sha256, ...) {
    pq <- file.path(root, paste0("season=", season), sprintf("week=%02d", as.integer(week)), file)
    raw <- sub("[.]parquet$", ".json.gz", pq)
    tibble::tibble(file = file, parquet_ok = file.exists(pq) && identical(sha256_file(pq), parquet_sha256),
                   raw_ok = file.exists(raw) && identical(sha256_file(raw), raw_sha256))
  }) |>
    purrr::list_rbind()
}

#' Rescore an ESPN stat line (columns named as in VAL_ESPN_STAT_MAP) under any
#' scoring rules; stats a rule needs but ESPN does not project count as 0.
val_rescore <- function(d, rules) {
  missing <- setdiff(names(rules$weights), names(d))
  for (m in missing) d[[m]] <- 0
  score_fantasy_points(d, rules)
}
