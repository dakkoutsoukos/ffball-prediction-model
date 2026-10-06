# Weekly prospective run: snapshot ESPN, refresh live data, archive predictions.
#
# Usage (from the project root, on a CLEAN, committed code tree):
#   Rscript scripts/weekly_run.R                    # current season, next week, ALL frozen lineages
#   Rscript scripts/weekly_run.R 2026 6             # explicit season and week
#   Rscript scripts/weekly_run.R 2026 6 m1,m2       # explicit lineages
#   options: --no-snapshot   reuse the latest ESPN snapshot (no ESPN request)
#            --commit        also make a LOCAL git commit of archive/*.csv
#                            (pushing is always left to you)
#
# Run before each slate's kickoffs (ET): Thu ~17:00, Sun ~08:00 (if an
# international game) and ~11:30, Mon ~17:00. The latest run before each
# game's kickoff is the official prediction for that game.
# Then, BEFORE kickoff:  git push   (and see: Rscript scripts/status.R)

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
flags <- args[startsWith(args, "--")]
pos <- args[!startsWith(args, "--")]
cfg <- read_project_config()
now <- Sys.time()
season <- if (length(pos) >= 1) as.integer(pos[[1]]) else as.integer(format(Sys.Date(), "%Y"))
lineages <- if (length(pos) >= 3) strsplit(pos[[3]], ",")[[1]] else frozen_lineages()

# --- preflight -------------------------------------------------------------------
g <- git_state()
if (!isFALSE(g$dirty)) stop("Code changes are not committed. Commit first so predictions map to a commit.")
if (!isTRUE(cfg$espn$enabled) && !"--no-snapshot" %in% flags) {
  stop("ESPN is not enabled (config/local.yml). Use --no-snapshot to reuse existing snapshots.")
}
cli::cli_h1("Weekly prospective run - {fmt_utc(now)}")

live <- refresh_live_data(season)
tg <- clean_team_games(live[["schedules"]], cfg$season_type)
week <- if (length(pos) >= 2) as.integer(pos[[2]]) else infer_target_week(tg, season, now)
if (is.na(week)) stop("No upcoming games in ", season, ".")
ko <- week_kickoffs(tg, season, week, now)
if (nrow(ko) == 0) stop("Week ", week, " has no games.")
if (all(ko$started)) stop("Every week-", week, " game has already kicked off; nothing can be predicted prospectively.")
cli::cli_text("Season {season}, week {.strong {week}}; lineages: {.val {lineages}}")
if (any(ko$started)) {
  cli::cli_alert_warning("{sum(ko$started)} game{?s} already kicked off; those players will NOT count prospectively.")
}

# --- capture and predict ---------------------------------------------------------------
if (!"--no-snapshot" %in% flags) {
  snap <- snapshot_espn_projections("WR", cfg$espn$league_defaults_id, week = week, enabled = TRUE)
  cli::cli_alert_success("ESPN snapshot {.file {basename(snap)}}")
}
invisible(fetch_espn_completed_weeks(season, tg, enabled = isTRUE(cfg$espn$enabled), pause = cfg$espn$request_pause_seconds))
res <- run_prospective(season, week, lineages)

# --- verify and report ------------------------------------------------------------------
ver <- verify_prediction_archive()
ok <- ver$verified[ver$run_id == res$meta$run_id]
cli::cli_alert_success("Archived {nrow(res$predictions)} predictions ({length(unique(res$predictions$model_id))} models, {res$meta$targets} WRs)")
cli::cli_text("  {.file {res$path}}")
cli::cli_text("  hash verified against manifest: {ok}; snapshot captured {res$meta$snapshot_captured_at_utc}")
nxt <- ko$kickoff_utc[!ko$started][1]
cli::cli_alert_info("Next kickoff: {fmt_utc(nxt)} ({round(as.numeric(difftime(nxt, Sys.time(), units = 'hours')), 1)} h)")

if ("--commit" %in% flags) {
  system2("git", c("add", "archive/prediction_manifest.csv", "archive/espn_snapshot_manifest.csv"))
  system2("git", c("commit", "-q", "-m", shQuote(sprintf("Prospective run %d W%d (%s)", season, week, paste(lineages, collapse = "+")))))
  cli::cli_alert_success("Committed the manifests locally.")
}
cli::cli_alert_warning("Push BEFORE {fmt_utc(nxt)}:{if (!'--commit' %in% flags) '  git add archive/*.csv && git commit -m \"Prospective run\" &&' else ''}  git push")
cli::cli_text("Then check: Rscript scripts/status.R")
