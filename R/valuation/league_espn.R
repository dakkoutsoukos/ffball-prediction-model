# Valuation V2: the owner's actual ESPN league ----------------------------------------------
# One request returns settings, teams, rosters and status:
#   GET {ESPN_API}/seasons/{S}/segments/0/leagues/{id}?view=mSettings&view=mTeam&view=mRoster&view=mStatus
# Private leagues need the owner's espn_s2 and SWID cookies, read from the git-ignored
# config/local.yml (league: {espn_league_id, espn_s2, swid}) or from the environment
# variables ESPN_S2 / ESPN_SWID. They are never printed, logged or archived.
#
# Privacy: raw league data (team names, rosters, settings) is written only to the
# git-ignored data/snapshots/espn_league/<alias>/. The committed manifest
# (archive/league_snapshot_manifest.csv) holds hashes, counts, times and a RANDOM
# league alias - never the league id (a hash of a 10-digit id is brute-forceable).

LG_SNAPSHOT_ROOT <- "data/snapshots/espn_league"
LG_SNAPSHOT_MANIFEST <- "archive/league_snapshot_manifest.csv"

# ESPN lineup slot ids (documented by the open-source espn-api client and verified on
# league responses). Skill slots map to V1 slots; others are counted or rejected.
LG_SLOT_MAP <- list(
  `0` = list(name = "QB", eligible = "QB"),
  `2` = list(name = "RB", eligible = "RB"),
  `3` = list(name = "RB_WR", eligible = c("RB", "WR")),
  `4` = list(name = "WR", eligible = "WR"),
  `5` = list(name = "WR_TE", eligible = c("WR", "TE")),
  `6` = list(name = "TE", eligible = "TE"),
  `7` = list(name = "SUPERFLEX", eligible = c("QB", "RB", "WR", "TE")),
  `23` = list(name = "FLEX", eligible = c("RB", "WR", "TE"))
)
LG_NONSKILL_SLOTS <- c(`16` = "D/ST", `17` = "K")
LG_BENCH_SLOT <- 20L
LG_IR_SLOT <- 21L
LG_UNSUPPORTED_SLOTS <- c(`1` = "TQB", `8` = "DT", `9` = "DE", `10` = "LB", `11` = "DL", `12` = "CB", `13` = "S",
                          `14` = "DB", `15` = "DP", `18` = "P", `19` = "HC", `24` = "ER")
LG_SLOT_LABEL <- c(`0` = "QB", `1` = "TQB", `2` = "RB", `3` = "RB/WR", `4` = "WR", `5` = "WR/TE", `6` = "TE",
                   `7` = "OP", `16` = "D/ST", `17` = "K", `20` = "BE", `21` = "IR", `23` = "FLEX")

#' League credentials and id from local config / environment (never printed).
lg_credentials <- function(cfg = read_project_config()) {
  lc <- cfg$league %||% list()
  s2 <- Sys.getenv("ESPN_S2", lc$espn_s2 %||% "")
  swid <- Sys.getenv("ESPN_SWID", lc$swid %||% "")
  list(league_id = as.character(lc$espn_league_id %||% NA), espn_s2 = if (nzchar(s2)) s2 else NA_character_,
       swid = if (nzchar(swid)) swid else NA_character_, my_team_id = lc$my_team_id %||% NA,
       alias = if (file.exists(file.path(LG_SNAPSHOT_ROOT, "alias.txt"))) lg_alias() else NA_character_)
}

#' The league's random alias, created once and kept in the git-ignored snapshot
#' root (config/local.yml is the owner's file and is never rewritten by code).
lg_alias <- function(root = LG_SNAPSHOT_ROOT) {
  f <- file.path(root, "alias.txt")
  if (file.exists(f)) return(readLines(f, warn = FALSE)[1])
  alias <- paste0("league_", paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = ""))
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  writeLines(alias, f)
  alias
}

lg_request <- function(url, cred) {
  req <- espn_request(url)
  if (!is.na(cred$espn_s2) && !is.na(cred$swid)) {
    req <- httr2::req_headers(req, Cookie = paste0("espn_s2=", cred$espn_s2, "; SWID=", cred$swid))
  }
  httr2::req_error(req, is_error = function(r) FALSE)
}

#' Fetch the league (settings, teams, rosters, status) as raw JSON text.
lg_fetch_league <- function(season, cred = lg_credentials(), enabled = FALSE) {
  stop_if_espn_disabled(enabled)
  if (is.na(cred$league_id)) cli::cli_abort("No league id: set {.field league.espn_league_id} in config/local.yml.")
  url <- sprintf("%s/seasons/%d/segments/0/leagues/%s?view=mSettings&view=mTeam&view=mRoster&view=mStatus",
                 ESPN_API, season, cred$league_id)
  resp <- httr2::req_perform(lg_request(url, cred))
  st <- httr2::resp_status(resp)
  if (st == 401) {
    cli::cli_abort(c("ESPN refused the league request (HTTP 401): the league is private.",
                     "i" = "Add {.field espn_s2} and {.field swid} under {.field league:} in config/local.yml (git-ignored)."))
  }
  if (st != 200) cli::cli_abort("ESPN league request failed with HTTP {st}.")
  httr2::resp_body_string(resp)
}

#' Map ESPN roster settings to a V1 league (slots, bench, IR, roster size).
#' Fails clearly on slots the valuation cannot model.
lg_map_settings <- function(settings, schedule_weeks = 18L) {
  rs <- settings$rosterSettings
  counts <- unlist(rs$lineupSlotCounts)
  counts <- counts[counts > 0]
  cnt <- function(id) { v <- unname(counts[as.character(id)]); if (length(v) != 1 || is.na(v)) 0L else as.integer(v) }
  bad <- intersect(names(counts), names(LG_UNSUPPORTED_SLOTS))
  unknown <- setdiff(names(counts), c(names(LG_SLOT_MAP), names(LG_NONSKILL_SLOTS), LG_BENCH_SLOT, LG_IR_SLOT,
                                      names(LG_UNSUPPORTED_SLOTS)))
  if (length(bad) || length(unknown)) {
    cli::cli_abort(c("League uses roster slots the valuation cannot model: {.val {c(LG_UNSUPPORTED_SLOTS[bad], unknown)}}.",
                     "i" = "Supported: QB, RB, WR, TE, FLEX (RB/WR/TE), RB/WR, WR/TE, OP (superflex), K, D/ST, bench, IR."))
  }
  skill <- intersect(names(counts), names(LG_SLOT_MAP))
  slots <- lapply(skill, function(id) c(LG_SLOT_MAP[[id]], list(count = as.integer(counts[[id]]))))
  sched <- settings$scheduleSettings %||% list()
  reg_n <- as.integer(sched$matchupPeriodCount %||% 14)
  n_po <- as.integer(sched$playoffTeamCount %||% 4)
  rounds <- as.integer(ceiling(log2(max(n_po, 2))))
  mp <- sched$matchupPeriods
  if (!is.null(mp) && length(mp) >= reg_n) {
    # scoring periods of each matchup period (a playoff round can span two weeks)
    weeks_of <- function(ids) sort(as.integer(unlist(mp[as.character(ids)])))
    reg_weeks <- weeks_of(seq_len(reg_n))
    if (!identical(reg_weeks, seq_len(reg_n))) cli::cli_abort("Regular-season matchup periods are not one week each; not supported.")
    po_weeks <- weeks_of(reg_n + seq_len(rounds))
    if (!length(po_weeks)) po_weeks <- reg_n + seq_len(rounds)
  } else {
    po_len <- max(1L, as.integer(sched$playoffMatchupPeriodLength %||% 1))
    po_weeks <- reg_n + seq_len(rounds * po_len)
  }
  if (!identical(po_weeks, seq(min(po_weeks), max(po_weeks)))) cli::cli_abort("Fantasy playoff weeks are not contiguous.")
  reg_last <- reg_n
  po_last <- max(po_weeks)
  if (po_last > schedule_weeks) cli::cli_abort("League playoffs end in week {po_last}, after the NFL season.")
  nonskill <- intersect(names(counts), names(LG_NONSKILL_SLOTS))
  league <- val_league(list(
    name = "espn_league", teams = as.integer(settings$size), scoring = "league",
    slots = slots, bench = cnt(LG_BENCH_SLOT),
    regular_season_weeks = c(1L, reg_last), playoff_weeks = c(min(po_weeks), po_last)
  ))
  if (!val_slots_laminar(league)) {
    cli::cli_abort("League slot eligibility is not laminar (e.g. RB/WR together with WR/TE); the lineup evaluator would be inexact.")
  }
  pl <- unlist(rs$positionLimits %||% list())
  lim <- function(k) { v <- unname(pl[k]); if (length(v) != 1 || is.na(v)) 0 else v }
  pos_limits <- c(QB = lim("1"), RB = lim("2"), WR = lim("3"), TE = lim("4"))
  league$ir_slots <- cnt(LG_IR_SLOT)
  league$nonskill_starters <- as.list(stats::setNames(as.integer(counts[nonskill]), LG_NONSKILL_SLOTS[nonskill]))
  league$roster_size <- as.integer(sum(counts[names(counts) != as.character(LG_IR_SLOT)]))
  league$position_limits <- as.list(pos_limits[pos_limits > 0])
  league
}

LG_SKILL_SLOT_IDS <- c("0", "2", "3", "4", "5", "6", "7", "20", "21", "23")

#' How much skill players (QB/RB/WR/TE) actually record each ESPN stat id, from the
#' local ESPN projection/actual history (week-of files and valuation captures).
#' Cached as a small table of counts (no player data) in the git-ignored snapshot root.
lg_skill_stat_usage <- function(ids, cache = file.path(LG_SNAPSHOT_ROOT, "skill_stat_usage.csv")) {
  ids <- as.character(ids)
  old <- if (file.exists(cache)) readr::read_csv(cache, col_types = "cdd") else
    tibble::tibble(stat_id = character(), entries = double(), abs_total = double())
  need <- setdiff(ids, old$stat_id)
  if (length(need)) {
    files <- c(list.files(VAL_ESPN_RAW_ROOT, pattern = "json[.]gz$", recursive = TRUE, full.names = TRUE),
               list.files("data/raw/espn", pattern = "^espn_wr_.*json[.]gz$", recursive = TRUE, full.names = TRUE),
               list.files(VAL_ESPN_SNAPSHOT_ROOT, pattern = "json[.]gz$", recursive = TRUE, full.names = TRUE))
    tot <- stats::setNames(numeric(length(need)), need)
    n <- 0
    for (f in files) {
      doc <- jsonlite::fromJSON(read_gz_text(f), simplifyVector = FALSE)
      for (p in doc$players) {
        if (!(p$player$defaultPositionId %||% 0) %in% 1:4) next
        for (st in p$player$stats %||% list()) {
          v <- unlist(st$stats)
          if (!length(v)) next
          n <- n + 1
          h <- intersect(names(v), need)
          if (length(h)) tot[h] <- tot[h] + abs(as.numeric(v[h]))
        }
      }
    }
    if (n == 0) return(NULL)
    old <- dplyr::bind_rows(old, tibble::tibble(stat_id = need, entries = n, abs_total = unname(tot)))
    dir.create(dirname(cache), recursive = TRUE, showWarnings = FALSE)
    readr::write_csv(old, cache)
  }
  dplyr::filter(old, .data$stat_id %in% ids)
}

#' League scoring as V1 scoring rules. Unmapped items (stat ids outside
#' VAL_ESPN_STAT_MAP) are RELEVANT to skill-player valuation only if they can score
#' for a skill player (base points, or a per-slot override on a skill slot) AND skill
#' players actually record the stat at >= `min_points` per player-week in ESPN's own
#' history (`usage`). Without usage evidence every scoring unmapped item counts.
lg_map_scoring <- function(settings, scoring_dir = "config/scoring", usage = NULL, min_points = 0.01) {
  items <- settings$scoringSettings$scoringItems %||% list()
  tab <- tibble::tibble(
    stat_id = vapply(items, function(i) as.character(i$statId), ""),
    points = vapply(items, function(i) as.numeric(i$points %||% 0), 0),
    skill_override = vapply(items, function(i) any(names(i$pointsOverrides %||% list()) %in% LG_SKILL_SLOT_IDS), TRUE),
    overrides = vapply(items, function(i) paste(names(i$pointsOverrides %||% list()), collapse = ","), "")
  )
  tab$stat <- unname(VAL_ESPN_STAT_MAP[tab$stat_id])
  mapped <- dplyr::filter(tab, !is.na(.data$stat))
  w <- tapply(mapped$points, mapped$stat, function(p) unique(p))
  if (any(lengths(w) > 1)) cli::cli_abort("Conflicting league points for one stat: {.val {names(w)[lengths(w) > 1]}}.")
  w <- unlist(w)
  base <- read_scoring_rules("espn_ppr", scoring_dir)
  weights <- stats::setNames(rep(0, length(base$weights)), names(base$weights))
  weights[names(w)] <- w
  rules <- list(name = "ESPN league scoring", weights = weights, system = "league")
  unm <- dplyr::filter(tab, is.na(.data$stat)) |>
    dplyr::mutate(can_score_skill = .data$points != 0 | .data$skill_override)
  if (!is.null(usage)) {
    unm <- dplyr::left_join(unm, usage, by = "stat_id") |>
      dplyr::mutate(points_per_player_week = abs(.data$points) * dplyr::coalesce(.data$abs_total, 0) /
                      pmax(dplyr::coalesce(.data$entries, 1), 1),
                    relevant = .data$can_score_skill & (.data$skill_override | .data$points_per_player_week >= min_points))
  } else {
    unm <- dplyr::mutate(unm, relevant = .data$can_score_skill)
  }
  rel <- dplyr::filter(unm, .data$relevant)
  list(rules = rules, unmapped = rel, ignored = dplyr::filter(unm, !.data$relevant),
       equals_espn_ppr = isTRUE(all.equal(unname(weights[names(base$weights)]), unname(base$weights))) &&
         !nrow(rel) && !any(mapped$skill_override),
       items = tab)
}

#' Parse a league response into settings, teams and roster tables.
lg_parse_league <- function(json, captured_at_utc, alias) {
  doc <- if (is.character(json)) jsonlite::fromJSON(json, simplifyVector = FALSE) else json
  teams <- purrr::map(doc$teams %||% list(), function(t) {
    nm <- t$name %||% trimws(paste(t$location %||% "", t$nickname %||% ""))
    tibble::tibble(team_id = as.integer(t$id), team_abbrev = t$abbrev %||% NA_character_, team_name = nm,
                   owners = paste(unlist(t$owners %||% list()), collapse = ","))
  }) |>
    purrr::list_rbind()
  roster <- purrr::map(doc$teams %||% list(), function(t) {
    purrr::map(t$roster$entries %||% list(), function(e) {
      pl <- e$playerPoolEntry$player %||% list()
      tibble::tibble(
        team_id = as.integer(t$id), espn_id = as.character(e$playerId %||% pl$id),
        player_name = pl$fullName %||% NA_character_,
        position = val_espn_position(pl$defaultPositionId %||% NA) %||% NA_character_,
        espn_position_id = as.integer(pl$defaultPositionId %||% NA),
        nfl_team = espn_team(pl$proTeamId %||% NA) %||% NA_character_,
        lineup_slot_id = as.integer(e$lineupSlotId %||% NA),
        acquisition_type = e$acquisitionType %||% NA_character_,
        acquisition_date = as.numeric(e$acquisitionDate %||% NA),
        injury_status = e$injuryStatus %||% pl$injuryStatus %||% NA_character_
      )
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
  if (nrow(roster)) {
    roster <- roster |>
      dplyr::mutate(lineup_slot = unname(LG_SLOT_LABEL[as.character(.data$lineup_slot_id)]),
                    is_ir_slot = .data$lineup_slot_id %in% LG_IR_SLOT,
                    is_skill = .data$position %in% VAL_POSITIONS,
                    captured_at_utc = captured_at_utc, league_alias = alias, .before = 1) |>
      dplyr::left_join(dplyr::select(teams, "team_id", "team_abbrev", "team_name"), by = "team_id")
  }
  list(season = as.integer(doc$seasonId %||% NA), scoring_period = as.integer(doc$scoringPeriodId %||% NA),
       league_name = doc$settings$name %||% NA_character_, settings = doc$settings, status = doc$status,
       teams = teams, roster = roster)
}

#' Fetch, parse and archive a league snapshot write-once; register hashes.
lg_snapshot_league <- function(season, cred = lg_credentials(), enabled = FALSE, root = LG_SNAPSHOT_ROOT,
                               manifest = LG_SNAPSHOT_MANIFEST, body = NULL) {
  alias <- cred$alias
  if (is.na(alias)) alias <- lg_alias(root)
  body <- body %||% lg_fetch_league(season, cred, enabled)  # `body`: tests / offline replay
  captured <- utc_stamp()
  dir <- file.path(root, alias, sprintf("season=%d", season))
  stem <- paste0("captured_at=", captured)
  raw_path <- write_once(file.path(dir, paste0(stem, ".json.gz")), function(tmp) write_gz_text(tmp, body))
  lg <- lg_parse_league(body, captured, alias)
  if (anyDuplicated(lg$roster$espn_id)) cli::cli_abort("A player appears on two fantasy rosters.")
  pq <- write_once(file.path(dir, paste0(stem, "_roster.parquet")), function(tmp) arrow::write_parquet(lg$roster, tmp))
  append_manifest(tibble::tibble(
    league_alias = alias, season = season, scoring_period = lg$scoring_period, captured_at_utc = captured,
    n_teams = nrow(lg$teams), n_rostered = nrow(lg$roster), n_skill = sum(lg$roster$is_skill),
    raw_sha256 = sha256_file(raw_path), roster_sha256 = sha256_file(pq)
  ), manifest)
  list(raw = raw_path, roster = pq, league = lg)
}

#' Latest league snapshot at or before `as_of`, verified against the manifest.
#' Returns the parsed league plus its age; NULL if none.
lg_latest_snapshot <- function(season, alias = lg_credentials()$alias, as_of = Sys.time(), root = LG_SNAPSHOT_ROOT,
                               manifest = LG_SNAPSHOT_MANIFEST) {
  if (is.na(alias) || !file.exists(manifest)) return(NULL)
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::filter(.data$league_alias == !!alias, as.integer(.data$season) == !!season) |>
    dplyr::mutate(at = parse_utc_stamp(.data$captured_at_utc)) |>
    dplyr::filter(.data$at <= as_of)
  if (!nrow(m)) return(NULL)
  r <- m[which.max(m$at), ]
  dir <- file.path(root, alias, sprintf("season=%d", season))
  raw <- file.path(dir, paste0("captured_at=", r$captured_at_utc, ".json.gz"))
  if (!file.exists(raw) || !identical(sha256_file(raw), r$raw_sha256)) {
    cli::cli_abort("League snapshot {r$captured_at_utc} is missing or does not match its manifest hash.")
  }
  lg <- lg_parse_league(read_gz_text(raw), r$captured_at_utc, alias)
  lg$raw_path <- raw
  lg$raw_sha256 <- r$raw_sha256
  lg$age_hours <- as.numeric(difftime(as_of, r$at, units = "hours"))
  lg
}

#' Refuse stale league snapshots unless allowed.
lg_check_fresh <- function(lg, max_age_hours = 24, allow_stale = FALSE) {
  if (is.null(lg)) cli::cli_abort("No league snapshot: run {.code Rscript scripts/league_refresh.R} first.")
  if (lg$age_hours > max_age_hours) {
    msg <- sprintf("League snapshot is %.1f hours old (limit %s); rosters may have changed.", lg$age_hours, max_age_hours)
    if (!allow_stale) cli::cli_abort(c(msg, "i" = "Refresh with {.code Rscript scripts/league_refresh.R}, or pass --allow-stale."))
    cli::cli_warn(msg)
  }
  invisible(lg)
}

#' ID diagnostics: rostered players vs the valuation pool (joined by ESPN id).
lg_id_diagnostics <- function(roster, players) {
  sk <- dplyr::filter(roster, .data$is_skill)
  j <- dplyr::left_join(sk, dplyr::select(players, "espn_id", "player_id", pool_position = "position",
                                          pool_team = "team"), by = "espn_id")
  list(
    rostered = nrow(roster), skill = nrow(sk), nonskill = sum(!roster$is_skill),
    nonskill_by_position = as.list(table(roster$espn_position_id[!roster$is_skill])),
    duplicate_owners = roster$espn_id[duplicated(roster$espn_id)],
    no_projection = dplyr::filter(j, is.na(.data$player_id)) |>
      dplyr::select("team_name", "espn_id", "player_name", "position", "nfl_team", "lineup_slot", "injury_status"),
    position_mismatch = dplyr::filter(j, !is.na(.data$pool_position), .data$pool_position != .data$position) |>
      dplyr::select("espn_id", "player_name", "position", "pool_position"),
    team_mismatch = dplyr::filter(j, !is.na(.data$pool_team), !is.na(.data$nfl_team), .data$pool_team != .data$nfl_team) |>
      dplyr::select("espn_id", "player_name", "nfl_team", "pool_team")
  )
}

#' "My" team: configured id, else the team whose owners include the SWID.
lg_my_team <- function(teams, cred = lg_credentials()) {
  if (!is.na(cred$my_team_id)) return(as.integer(cred$my_team_id))
  if (is.na(cred$swid)) return(NA_integer_)
  hit <- teams$team_id[grepl(cred$swid, teams$owners, fixed = TRUE)]
  if (length(hit) == 1) hit else NA_integer_
}
