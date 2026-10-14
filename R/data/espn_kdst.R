# O8 (approved 2026-10-14, X-029): ESPN K and D/ST week-of files and live K/DST captures ----------
# Separate requests from the QB-TE files and captures, so their contents, parsers and manifests are
# unchanged. Same public endpoint (leaguedefaults), lineup slots 17 (K) and 16 (D/ST).
#   data/raw/espn_kdst/season=S/espn_kdst_S_wWW.json.gz        historical week-of (actuals + final pregame
#       projections; past weeks are retrieved retroactively)
#   data/snapshots/espn_kdst/season=S/week=WW/captured_at=<UTC>.{json.gz,parquet}   live captures
# Live captures are hashed into archive/kdst_espn_capture_manifest.csv (append-only, committed).

KDST_ESPN_RAW_ROOT <- "data/raw/espn_kdst"
KDST_ESPN_SNAPSHOT_ROOT <- "data/snapshots/espn_kdst"
KDST_ESPN_CAPTURE_MANIFEST <- "archive/kdst_espn_capture_manifest.csv"
KDST_ESPN_SLOTS <- c(DST = 16L, K = 17L)
KDST_ESPN_POSITION <- c(`5` = "K", `16` = "DST")

kdst_espn_raw_path <- function(season, week, root = KDST_ESPN_RAW_ROOT) {
  file.path(root, sprintf("season=%d", season), sprintf("espn_kdst_%d_w%02d.json.gz", season, week))
}

#' Fetch one season-week of ESPN K/DST week-of stat lines (actual and projected) in one request and
#' cache it immutably. Returns the path.
kdst_fetch_espn_week <- function(season, week, league_defaults_id = 3, pause = 1.5, root = KDST_ESPN_RAW_ROOT,
                                 enabled = FALSE, limit = 1000) {
  path <- kdst_espn_raw_path(season, week, root)
  if (file.exists(path)) return(path)
  stop_if_espn_disabled(enabled)
  url <- val_espn_url(season, week, league_defaults_id)
  body <- espn_request(url, val_espn_filter(week, KDST_ESPN_SLOTS, limit)) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  n <- length(jsonlite::fromJSON(body, simplifyVector = FALSE)$players)
  if (n >= limit) cli::cli_abort("ESPN returned {n} players (limit {limit}); the response may be truncated.")
  write_once(path, function(tmp) write_gz_text(tmp, body))
  jsonlite::write_json(list(
    provider = "ESPN", dataset = "kona_player_info weekly (K/DST)", season = season, week = week,
    slots = unname(KDST_ESPN_SLOTS), league_defaults_id = league_defaults_id, url = url, n_players = n,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    asof = "retrieved retroactively; past weeks hold ESPN's final pregame projection"
  ), paste0(path, ".json"), auto_unbox = TRUE, pretty = TRUE)
  Sys.sleep(pause)
  path
}

#' Parse a K/DST response into one row per (player, scoring period, source): ESPN's appliedTotal,
#' the team on the stat entry (the team at the time, for actuals) and every ESPN stat id as a
#' column `s<id>` (0 when absent). Per-game entries in one week are summed.
kdst_parse_espn <- function(json, season, periods = NULL, sources = c(0L, 1L)) {
  doc <- if (is.character(json)) jsonlite::fromJSON(json, simplifyVector = FALSE) else json
  season <- as.integer(season)
  recs <- list()
  for (p in doc$players) {
    pl <- p$player
    pos <- unname(KDST_ESPN_POSITION[as.character(pl$defaultPositionId %||% NA)])
    if (is.na(pos)) next
    for (s in pl$stats %||% list()) {
      if (!identical(as.integer(s$seasonId), season) || !identical(as.integer(s$statSplitTypeId), 1L)) next
      if (!as.integer(s$statSourceId) %in% sources) next
      if (!is.null(periods) && !as.integer(s$scoringPeriodId) %in% periods) next
      v <- s$stats %||% list()
      recs[[length(recs) + 1]] <- c(list(
        espn_id = as.character(pl$id), position = pos, espn_pro_team_id = as.integer(pl$proTeamId %||% NA),
        stat_pro_team_id = as.integer(s$proTeamId %||% NA), season = season, week = as.integer(s$scoringPeriodId),
        source = as.integer(s$statSourceId), applied_total = as.numeric(s$appliedTotal %||% NA)),
        if (length(v)) stats::setNames(lapply(v, as.numeric), paste0("s", names(v))) else list())
    }
  }
  if (!length(recs)) return(tibble::tibble())
  out <- dplyr::bind_rows(recs)
  sc <- grep("^s[0-9]+$", names(out), value = TRUE)
  out[sc] <- lapply(out[sc], function(x) dplyr::coalesce(x, 0))
  out |>
    dplyr::summarise(dplyr::across(dplyr::all_of(c("applied_total", sc)), sum),
                     stat_pro_team_id = kdst_first_team(.data$stat_pro_team_id),
                     .by = c("espn_id", "position", "espn_pro_team_id", "season", "week", "source"))
}

kdst_first_team <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (length(x)) x[[1]] else NA_integer_
}

#' League points of parsed ESPN K/DST stat lines under the league's K/DST rules (kdst_rules_from_settings):
#' sum over scoring items of points x the ESPN statistic with that id (K points for K rows, D/ST
#' points for D/ST rows). Kicker offensive plays (fakes) are not included.
kdst_espn_league_points <- function(parsed, rules) {
  out <- numeric(nrow(parsed))
  for (i in seq_len(nrow(rules))) {
    col <- paste0("s", rules$stat_id[i])
    if (!col %in% names(parsed)) next
    w <- ifelse(parsed$position == "K", rules$points_k[i], rules$points_dst[i])
    out <- out + w * dplyr::coalesce(parsed[[col]], 0)   # stats absent from a file (bound across files) are 0
  }
  round(out, 2)
}

#' B-001: scoring match between F4 part 2's league-scored tables (nflverse) and ESPN's actual K/DST
#' stat lines under the same league rules, per team-game. K compares team totals (kickers summed;
#' F4's K table includes kicker offensive points, so those team-weeks are flagged); D/ST compares
#' each team's unit. A row matches when the difference is below `tol`.
kdst_espn_match <- function(espn_actual, rules, team_k, dst_week, tol = 0.01) {
  a <- dplyr::filter(espn_actual, .data$source == 0L)
  a$league_points <- kdst_espn_league_points(a, rules)
  a$team <- espn_team(dplyr::coalesce(a$stat_pro_team_id, a$espn_pro_team_id))
  ek <- dplyr::summarise(dplyr::filter(a, .data$position == "K"), espn = sum(.data$league_points),
                         .by = c("season", "week", "team"))
  ed <- dplyr::summarise(dplyr::filter(a, .data$position == "DST"), espn = sum(.data$league_points),
                         .by = c("season", "week", "team"))
  k <- dplyr::inner_join(dplyr::select(team_k, "season", "week", "team", ours = "k_points"), ek,
                         by = c("season", "week", "team"))
  d <- dplyr::inner_join(dplyr::select(dst_week, "season", "week", "team", ours = "dst_points"), ed,
                         by = c("season", "week", "team"))
  rows <- dplyr::bind_rows(dplyr::mutate(k, position = "K"), dplyr::mutate(d, position = "DST")) |>
    dplyr::mutate(diff = .data$ours - .data$espn, match = abs(.data$diff) < tol)
  summary <- dplyr::summarise(rows, n = dplyr::n(), match_rate = mean(.data$match),
                              mean_abs_diff = mean(abs(.data$diff)), .by = "position")
  list(rows = rows, summary = summary,
       unmatched_ours = c(K = nrow(dplyr::anti_join(dplyr::filter(team_k, .data$season %in% unique(a$season), .data$k_points != 0),
                                                    ek, by = c("season", "week", "team"))),
                          DST = nrow(dplyr::anti_join(dplyr::filter(dst_week, .data$season %in% unique(a$season)),
                                                      ed, by = c("season", "week", "team")))))
}

#' Live capture of ESPN's posted K/DST projections for the current and later weeks (one request),
#' write-once, registered in the K/DST capture manifest. Returns the parquet path.
capture_espn_kdst <- function(season, week, league_defaults_id = 3, last_period = 18, root = KDST_ESPN_SNAPSHOT_ROOT,
                              manifest = KDST_ESPN_CAPTURE_MANIFEST, enabled = FALSE, limit = 1000) {
  stop_if_espn_disabled(enabled)
  captured_at <- utc_stamp()
  url <- val_espn_url(season, week, league_defaults_id)
  body <- espn_request(url, val_espn_filter(week:last_period, KDST_ESPN_SLOTS, limit, sources = 1)) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  doc <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  if (length(doc$players) >= limit) cli::cli_abort("ESPN K/DST capture may be truncated ({length(doc$players)} players).")
  dir <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week))
  stem <- sprintf("captured_at=%s", captured_at)
  raw_path <- write_once(file.path(dir, paste0(stem, ".json.gz")), function(tmp) write_gz_text(tmp, body))
  snap <- kdst_parse_espn(doc, season, periods = week:last_period, sources = 1L) |>
    dplyr::mutate(capture_week = as.integer(week), captured_at_utc = captured_at,
                  team = espn_team(.data$espn_pro_team_id), source_url = url, raw_sha256 = sha256_file(raw_path))
  out <- write_once(file.path(dir, paste0(stem, ".parquet")), function(tmp) arrow::write_parquet(snap, tmp))
  append_manifest(tibble::tibble(
    file = basename(out), season = season, week = week, captured_at_utc = captured_at,
    n_players = dplyr::n_distinct(snap$espn_id), n_rows = nrow(snap),
    periods = if (nrow(snap)) paste(range(snap$week), collapse = "-") else NA_character_,
    parquet_sha256 = sha256_file(out), raw_sha256 = sha256_file(raw_path)
  ), manifest)
  out
}

#' B-001 v2 D/ST definitions, found by matching ESPN's actual stat lines on 2019-2023 (F4's v1
#' tables are not changed): points allowed exclude safeties scored against the team's offense, and
#' fumble recoveries count every opponent fumble the team recovers, whatever the play type.
#' Returns `dst_stats` with both columns and the PA tiers replaced.
kdst_dst_stats_v2 <- function(dst_stats, pbp) {
  fr <- dplyr::bind_rows(
    dplyr::transmute(pbp, .data$game_id, fum = .data$fumbled_1_team, rec = .data$fumble_recovery_1_team),
    dplyr::transmute(pbp, .data$game_id, fum = .data$fumbled_2_team, rec = .data$fumble_recovery_2_team)
  ) |>
    dplyr::filter(!is.na(.data$fum), !is.na(.data$rec), .data$fum != .data$rec) |>
    dplyr::count(game_id = .data$game_id, team = .data$rec, name = "fr_v2")
  opp <- dplyr::select(dst_stats, "game_id", opponent = "team", opp_safeties = "safeties")
  out <- dst_stats |>
    dplyr::left_join(fr, by = c("game_id", "team")) |>
    dplyr::left_join(opp, by = c("game_id", "opponent")) |>
    dplyr::mutate(fumble_recoveries = as.numeric(dplyr::coalesce(.data$fr_v2, 0L)),
                  points_allowed = .data$points_allowed - 2 * dplyr::coalesce(.data$opp_safeties, 0)) |>
    dplyr::select(-"fr_v2", -"opp_safeties", -dplyr::any_of(names(KDST_PA_TIERS)))
  dplyr::bind_cols(out, kdst_tiers(out$points_allowed, KDST_PA_TIERS))
}
