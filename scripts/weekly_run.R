# Weekly prospective run: snapshot ESPN, refresh live data, archive predictions.
#
# Usage (from the project root, on a CLEAN, committed git tree):
#   Rscript scripts/weekly_run.R <season> <week> [lineages]       e.g. 2026 6 m1,m2a
#   Rscript scripts/weekly_run.R <season> <week> [lineages] --no-snapshot
#
# Recommended schedule (all times ET), each before the relevant kickoffs:
#   Thu ~17:00 (covers Thursday game) | Sun ~08:00 (London) or ~11:30 (Sunday games)
#   | Mon ~17:00 (Monday game). The latest run before each game's kickoff is the
#   official prediction for that game (docs/prospective_protocol.md).
# Afterwards, BEFORE kickoff: commit and push archive/*.csv (hashes only).

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript scripts/weekly_run.R <season> <week> [lineages] [--no-snapshot]")
season <- as.integer(args[[1]])
week <- as.integer(args[[2]])
lineages <- if (length(args) >= 3 && !startsWith(args[[3]], "--")) strsplit(args[[3]], ",")[[1]] else "m1"
cfg <- read_project_config()
espn_ok <- isTRUE(cfg$espn$enabled)

if (!"--no-snapshot" %in% args) {
  snap <- snapshot_espn_projections("WR", cfg$espn$league_defaults_id, week = week, enabled = espn_ok)
  cli::cli_alert_success("Snapshot {.file {snap}}")
}
live <- refresh_live_data(season)
cli::cli_alert_success("Live data refreshed ({length(live)} datasets)")
tg <- clean_team_games(live[["schedules"]], cfg$season_type)
fetch_espn_completed_weeks(season, tg, enabled = espn_ok, pause = cfg$espn$request_pause_seconds)

res <- run_prospective(season, week, lineages)
cli::cli_alert_success("Archived {nrow(res$predictions)} predictions: {.file {res$path}}")
cli::cli_alert_info("Now commit and push the manifests BEFORE kickoff ({res$meta$first_kickoff_utc} UTC):")
cli::cli_text("  git add archive/*.csv && git commit -m \"Prospective run {season} W{week}\" && git push")
