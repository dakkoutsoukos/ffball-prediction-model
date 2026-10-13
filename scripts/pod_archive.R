# Archive this week's P0 outcome distributions from the latest valuation run (master plan P0, E18).
#
# Usage (from the project root, after scripts/valuation_run.R):
#   Rscript scripts/pod_archive.R [season] [week]
# Writes data/archive/distributions/... (git-ignored) and appends archive/distribution_manifest.csv
# (commit it). No ESPN request and no outcome. The scheduled dispatcher runs it after each capture.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1) as.integer(args[[1]]) else nfl_season()
week <- if (length(args) >= 2) as.integer(args[[2]]) else {
  infer_target_week(clean_team_games(latest_live_file("schedules", season), "REG"), season)
}
res <- pd_archive_run(season, week)
cli::cli_alert_success("Archived {res$n} PODs (pod_baseline_v0) for {season} week {week} from valuation run {res$run}: {.file {res$path}}")
