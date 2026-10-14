# Decision ledger (master plan F5) ----------------------------------------------------------------
# Every recommendation is recorded with its information state, so decision quality can be measured
# later without letting in-season outcomes shape later designs.
#   record    data/archive/decisions/<alias>/season=S/week=WW/<decision_id>.json  (write-once; private)
#   manifest  archive/decision_manifest.csv                                      (hash-only; committed)
#   actions   data/archive/decisions/<alias>/actions.csv  (what the owner did; private, append-only)
# Outcomes are SEALED (research/experiment_log.md E16 section 5; master plan 05 section 1):
#   1. the outcome join refuses to run on a season until 7 days after its last regular-season kickoff;
#   2. no outcome or regret report is produced until the decision-family pre-registrations
#      VL8-VL11 exist in research/valuation_log.md.
# Outcome of record: league-scored nflverse stats from the first live retrieval made on or after the
# Thursday 12:00 ET that follows the week's last game (after the weekly stat-correction window).

LEDGER_ROOT <- "data/archive/decisions"
LEDGER_MANIFEST <- "archive/decision_manifest.csv"
LEDGER_SCHEMA <- "decision_record_v1"
LEDGER_TYPES <- c("lineup", "trade_analyze", "trade_search", "trade_target", "trade_sell", "waivers", "odds", "trade_rescore")
LEDGER_UNSEAL_ENTRIES <- c("VL8", "VL9", "VL10", "VL11")

#' Record one recommendation. `recommendation`, `alternatives` and `metrics` are plain lists or
#' data frames (they may hold player names and ids: the record is private). Returns the decision id.
lg_ledger_record <- function(type, inputs, season, week, recommendation, alternatives = NULL, metrics = list(),
                             options = list(), model_versions = list(), now = Sys.time(),
                             root = LEDGER_ROOT, manifest = LEDGER_MANIFEST) {
  type <- match.arg(type, LEDGER_TYPES)
  alias <- inputs$league_alias %||% "synthetic"
  git <- git_state()
  body_core <- list(schema = LEDGER_SCHEMA, type = type, league_alias = alias, season = as.integer(season),
                    week = as.integer(week), as_of_utc = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                    inputs = inputs, options = options, recommendation = recommendation, alternatives = alternatives,
                    metrics = metrics, model_versions = c(model_versions, list(git_commit = git$commit, git_dirty = git$dirty)))
  id <- paste(utc_stamp(now), type, substr(digest_text(jsonlite::toJSON(body_core, auto_unbox = TRUE, digits = NA,
                                                                         null = "null", na = "null")), 1, 8), sep = "_")
  body <- c(list(decision_id = id), body_core)
  path <- file.path(root, alias, sprintf("season=%d", as.integer(season)), sprintf("week=%02d", as.integer(week)),
                    paste0(id, ".json"))
  path <- write_once(path, function(tmp) jsonlite::write_json(body, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                                                              na = "null", null = "null"))
  append_manifest(tibble::tibble(decision_id = id, league_alias = alias, season = as.integer(season), week = as.integer(week),
                                 type = type, as_of_utc = body$as_of_utc, record_sha256 = sha256_file(path),
                                 git_commit = git$commit), manifest)
  invisible(list(decision_id = id, path = path))
}

#' Ledger records verified against the manifest (a record whose hash differs is reported, not read).
lg_ledger_read <- function(alias = NULL, season = NULL, root = LEDGER_ROOT, manifest = LEDGER_MANIFEST) {
  if (!file.exists(manifest)) return(list(records = list(), verified = tibble::tibble()))
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c"))
  if (!is.null(alias)) m <- m[m$league_alias == alias, ]
  if (!is.null(season)) m <- m[as.integer(m$season) == season, ]
  m$path <- file.path(root, m$league_alias, sprintf("season=%d", as.integer(m$season)),
                      sprintf("week=%02d", as.integer(m$week)), paste0(m$decision_id, ".json"))
  m$verified <- vapply(seq_len(nrow(m)), function(i) file.exists(m$path[i]) && identical(sha256_file(m$path[i]), m$record_sha256[i]), TRUE)
  recs <- lapply(m$path[m$verified], function(p) jsonlite::read_json(p, simplifyVector = TRUE))
  list(records = stats::setNames(recs, m$decision_id[m$verified]), verified = m[, c("decision_id", "type", "season", "week", "verified")])
}

#' Record what the owner did with a recommendation (private; append-only).
lg_ledger_action <- function(decision_id, action = c("followed", "partially", "ignored"), note = "", alias,
                             root = LEDGER_ROOT, now = Sys.time()) {
  action <- match.arg(action)
  append_manifest(tibble::tibble(decision_id = decision_id, action = action, note = note,
                                 recorded_at_utc = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                  file.path(root, alias, "actions.csv"))
}

# --- Outcomes of record (sealed) ----------------------------------------------------------------

#' Thursday 12:00 ET after the week's last kickoff: stat corrections are in by then.
lg_ledger_outcome_cutoff <- function(season, week, team_games) {
  last <- max(team_games$kickoff_utc[team_games$season == season & team_games$week == week])
  d <- as.Date(format(last, "%Y-%m-%d", tz = DISPATCH_TZ))
  thu <- d + ((4 - as.integer(format(d, "%u"))) %% 7)       # %u: Monday = 1 ... Thursday = 4
  if (thu == d) thu <- thu + 7                               # a Thursday game: the next Thursday
  t <- as.POSIXct(paste(thu, "12:00"), tz = DISPATCH_TZ)
  attr(t, "tzone") <- "UTC"
  t
}

#' The outcome source: the first live player_stats retrieval on or after the cutoff (NA if none yet).
lg_ledger_outcome_file <- function(season, week, team_games, root = LIVE_ROOT) {
  cutoff <- lg_ledger_outcome_cutoff(season, week, team_games)
  dir <- file.path(root, "player_stats", sprintf("season=%d", season))
  f <- list.files(dir, pattern = "^retrieved_at=.*[.]parquet$", full.names = TRUE)
  if (!length(f)) return(NA_character_)
  at <- parse_utc_stamp(sub("^retrieved_at=(.*)[.]parquet$", "\\1", basename(f)))
  ok <- which(at >= cutoff)
  if (!length(ok)) NA_character_ else f[ok][which.min(at[ok])]
}

#' Seal 1: may outcomes of this season be joined at `now`? Only once its regular season is over
#' (last regular-season kickoff + 7 days).
ledger_join_allowed <- function(season, team_games, now = Sys.time()) {
  last <- max(team_games$kickoff_utc[team_games$season == season])
  is.finite(last) && now >= last + 7 * 86400
}

#' Seal 2: may outcome or regret reports be produced? Only once VL8-VL11 are pre-registered.
ledger_reports_unsealed <- function(log = "research/valuation_log.md", entries = LEDGER_UNSEAL_ENTRIES) {
  if (!file.exists(log)) return(FALSE)
  heads <- grep("^## ", readLines(log, warn = FALSE), value = TRUE)
  all(vapply(entries, function(e) any(grepl(paste0("\\b", e, ":"), heads)), logical(1)))
}

#' Join a lineup decision with realised points (one row per rostered player): realised points of
#' the recommended lineup, the alternative (the lineup set in ESPN at decision time) and the
#' hindsight optimum. Refuses to run while seal 1 holds (`allowed` from ledger_join_allowed()).
lg_ledger_join_lineup <- function(record, points, league, allowed) {
  if (!isTRUE(allowed)) cli::cli_abort("Ledger outcomes are sealed for this season (E16 section 5): the join waits until the regular season is over.")
  r <- tibble::as_tibble(record$recommendation$roster)
  r$points <- unname(points[r$player_id])
  r$points[is.na(r$points)] <- 0
  hall <- val_hall_table(val_one_team(league))
  hind <- val_allocate(ifelse(r$is_ir, 0, r$points), r$position, hall)
  tibble::tibble(decision_id = record$decision_id,
                 recommended = sum(r$points[r$recommended_starter]),
                 alternative = sum(r$points[r$current_starter]),
                 hindsight = sum(r$points[hind]),
                 regret_recommended = sum(r$points[hind]) - sum(r$points[r$recommended_starter]),
                 regret_alternative = sum(r$points[hind]) - sum(r$points[r$current_starter]))
}

#' Outcome report over joined decisions. Refuses to run while seal 2 holds.
lg_ledger_report <- function(joined, unsealed = ledger_reports_unsealed()) {
  if (!isTRUE(unsealed)) cli::cli_abort("Ledger reports are sealed until the decision pre-registrations VL8-VL11 exist (master plan F5).")
  dplyr::summarise(joined, decisions = dplyr::n(), mean_regret_recommended = mean(.data$regret_recommended),
                   mean_regret_alternative = mean(.data$regret_alternative),
                   mean_gain_vs_alternative = mean(.data$recommended - .data$alternative))
}

#' Ledger content for a lineup query (private): every rostered player with ids, position, slots,
#' projection, lock state and status, plus the expected points and game-time plans.
lg_ledger_lineup_payload <- function(adv) {
  l <- adv$lineup
  list(recommendation = list(roster = dplyr::transmute(l, .data$player_id, .data$espn_id, .data$player, .data$position,
                                                       slot_recommended = .data$slot, slot_current = .data$espn_slot,
                                                       recommended_starter = !.data$slot %in% c("BE", "IR"),
                                                       current_starter = !.data$espn_slot %in% c("BE", "IR"),
                                                       is_ir = .data$slot == "IR", .data$proj, .data$locked, .data$status,
                                                       kickoff_utc = format(.data$kickoff_utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                              plans = adv$plan),
       alternatives = list(current_espn_lineup_ev = adv$ev_current),
       metrics = list(ev_recommended = adv$ev_recommended, ev_current = adv$ev_current))
}
