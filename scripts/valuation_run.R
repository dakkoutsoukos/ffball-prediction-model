# Point-in-time rest-of-season valuation run (Valuation V1).
#
# Usage (from the project root, on a CLEAN, committed code tree):
#   Rscript scripts/valuation_run.R                  # current season, next week, latest capture
#   Rscript scripts/valuation_run.R --capture        # first capture ESPN's current + posted future weeks
#   Rscript scripts/valuation_run.R 2026 6 --capture
#   options: --capture       one ESPN request (QB/RB/WR/TE, this week .. week 18); ESPN opt-in required
#            --no-archive    compute and print only (nothing written)
#            --no-sensitivity skip the sensitivity leagues (faster)
#            --league        value in the owner's ACTUAL league format (settings and scoring from the
#                            latest league snapshot, scripts/league_refresh.R); generic V1 methodology,
#                            archived as its own run (league hash). Used by the V2 trade analyzer.
#
# Uses the latest live nflverse retrieval (refreshed by scripts/weekly_run.R) and,
# for WRs, the latest ARCHIVED official M4 run of the week (read only). Run it
# after a weekly run so both describe the same moment. Writes
#   data/archive/valuation/season=S/week=WW/run=<UTC>/   (git-ignored)
# and appends hashes to archive/valuation_manifest.csv (commit it; nothing is pushed).
# Independent of the projection record: no frozen model, registry or
# prospective manifest is touched.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
flags <- args[startsWith(args, "--")]
pos <- args[!startsWith(args, "--")]
pcfg <- read_project_config()
cfg <- read_valuation_config()
now <- Sys.time()
season <- if (length(pos) >= 1) as.integer(pos[[1]]) else as.integer(format(Sys.Date(), "%Y"))
archive <- !"--no-archive" %in% flags

g <- git_state()
if (archive && !isFALSE(g$dirty)) stop("Code changes are not committed. Commit first so values map to a commit.")
tg <- clean_team_games(latest_live_file("schedules", season, now), "REG")
week <- if (length(pos) >= 2) as.integer(pos[[2]]) else infer_target_week(tg, season, now)
if (is.na(week)) stop("No upcoming games in ", season, ".")
cli::cli_h1("Valuation run {season} week {week} - {fmt_utc(now)}")

# Week-of ESPN history for completed weeks (QB/RB/TE; WR comes from the weekly run's retro fetch).
done <- tg |>
  dplyr::filter(.data$season == !!season, .data$week < !!week) |>
  dplyr::summarise(all_final = all(.data$game_final), .by = "week") |>
  dplyr::filter(.data$all_final)
if (nrow(done)) {
  invisible(val_fetch_espn_weeks(dplyr::transmute(done, season = !!season, week = .data$week),
                                 pause = pcfg$espn$request_pause_seconds, enabled = isTRUE(pcfg$espn$enabled)))
}
if ("--capture" %in% flags) {
  if (!isTRUE(pcfg$espn$enabled)) stop("ESPN is not enabled (config/local.yml).")
  cap <- capture_espn_valuation(week = week, league_defaults_id = pcfg$espn$league_defaults_id, enabled = TRUE)
  cli::cli_alert_success("ESPN capture {.file {basename(cap)}}")
}

if ("--league" %in% flags) {
  lgs <- lg_latest_snapshot(season, as_of = now)
  if (is.null(lgs)) stop("No league snapshot: run scripts/league_refresh.R first.")
  lc <- lg_league_config(lgs)
  cfg$league <- lc$league
  if (!lc$scoring$equals_espn_ppr) {
    cfg$scoring_rules <- lc$scoring$rules
    # the frozen M4 WR model predicts ESPN PPR points: not used for other scoring
    cfg$projection_sources$current_week$WR <- setdiff(unlist(cfg$projection_sources$current_week$WR), "m4_archive")
  }
  cli::cli_alert_info("League format: {paste(vapply(lc$league$slots, function(s) paste0(s$count, ' ', s$name), ''), collapse = ', ')}, {lc$league$teams} teams, bench {lc$league$bench}; scoring {if (lc$scoring$equals_espn_ppr) 'ESPN PPR' else 'league-specific'}")
}
res <- run_valuation(season, week, as_of = now, cfg = cfg, archive = archive,
                     sensitivity = !"--no-sensitivity" %in% flags && !"--league" %in% flags)
v <- res$values
cli::cli_alert_success("Valued {nrow(v)} players in {res$meta$elapsed_seconds} s; M4 run {res$meta$provider_versions$m4_run_id %||% 'none'}")
print(utils::head(dplyr::select(v, "overall_rank", "espn_name", "position", "team", "ros_points", "vor", "trade_value"), 25))
if (archive) {
  cli::cli_alert_success("Archived {.file {res$dir}}")
  cli::cli_text("Commit the manifests:  git add archive/valuation_*.csv && git commit -m \"Valuation run {season} W{week}\"")
}
