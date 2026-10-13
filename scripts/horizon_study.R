# R3 forecast-horizon study (master plan R3; E17 amended by E17a). Outcome-free: ESPN projections only.
#
# Usage (from the project root):   Rscript scripts/horizon_study.R [season]
# Compares every all-position capture with ESPN's final projection for completed weeks: revision drift
# and variance by position x lead bin, a martingale check and availability transitions, plus E17's
# adoption table (a lead bin is adopted once it holds >= 4 target weeks). Archives the result
# write-once under data/archive/horizon_study/ with a hash row in archive/horizon_manifest.csv
# (commit it). The scheduled dispatcher runs it after each early-week run.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1) as.integer(args[[1]]) else nfl_season()
tg <- clean_team_games(latest_live_file("schedules", season), "REG")
res <- hz_run(season, tg)
cli::cli_h1("Horizon study {season}: {res$active_rows} active revision rows, target weeks {paste(res$target_weeks, collapse = ', ')}")
options(width = 160)
print(dplyr::mutate(res$summary$pooled, dplyr::across(where(is.double), ~ round(.x, 3))))
cli::cli_text("Martingale check: {res$martingale$pairs} consecutive-capture pairs; correlation {round(res$martingale$cor, 3)} [{round(res$martingale$cor_lo, 3)}, {round(res$martingale$cor_hi, 3)}]")
ad <- res$adoption
cli::cli_text("Adoption (E17/E17a): {sum(ad$spread_var > 0)} of {nrow(ad)} current-week cells adopted; cells need 4 target weeks.")
cli::cli_alert_success("Archived {.file {res$path}}")
