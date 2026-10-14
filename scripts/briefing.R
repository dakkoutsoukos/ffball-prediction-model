# D5 weekly briefing (master plan D5; pre-declaration VL13): one private report before each slate.
#
# Usage (from the project root; after scripts/league_refresh.R and a valuation run):
#   Rscript scripts/briefing.R [--sims 3000] [--now 2026-10-18T14:00:00Z]
#
# Sections: lineup and game-time plan (D0, P1), S0 odds with VL3's band, the D3 waiver board, D2 trades
# with every other team, S3 values and roster risk, and I3's health panel. Each recommendation carries a
# robustness flag (VL13) and is ledgered (F5). The report is written to data/archive/briefings/
# (git-ignored), with a self-contained HTML copy (I2); the console shows only counts and flags. No ESPN
# request is made: refresh the league snapshot first (a stale snapshot is used and flagged). Outputs are
# SHADOW / UNVALIDATED (S0's label).

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
a <- commandArgs(trailingOnly = TRUE)
opt <- list()
i <- 1
while (i <= length(a)) {
  k <- sub("^--", "", a[[i]])
  if (i < length(a) && !startsWith(a[[i + 1]], "--")) { opt[[k]] <- a[[i + 1]]; i <- i + 2 } else { opt[[k]] <- TRUE; i <- i + 1 }
}
sims <- as.integer(opt$sims %||% 3000)
now <- if (!is.null(opt$now)) as.POSIXct(opt$now, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else Sys.time()
if (is.na(now)) stop("--now must look like 2026-10-18T14:00:00Z")
season <- nfl_season(now)
m <- suppressMessages(lg_load(season, allow_stale = TRUE))
me <- lg_my_team(m$teams)
if (is.na(me)) stop("Your team could not be detected (set league.my_team_id in config/local.yml).")
state <- lg_state_from_snapshot(lg_latest_snapshot(season))
if (!state$has_schedule) stop("The league snapshot has no schedule: run scripts/league_refresh.R (view=mMatchup).")
avail <- p1_live_availability(season, m$current_week, now)
tg <- clean_team_games(latest_live_file("schedules", season, now), "REG")
t0 <- Sys.time()
b <- list(team = me, team_label = lg_team_label(m, me), label = function(x) lg_team_label(m, x), week = m$current_week,
          now = now, snapshot_utc = m$inputs$league_captured_at_utc, snapshot_age_h = m$inputs$league_age_hours,
          git = git_state()$commit)
b$lineup <- d5_lineup(m, me, tg, now, avail)
b$odds <- d5_odds(m, state, avail)
b$waivers <- d5_waivers(m, state, me, avail, sims)
b$trades <- d5_trades(m, state, me, avail, sims)
b$values <- list(values = v3_live_values(m, state, me, sims = sims, p_active_fun = avail))
b$values$risk <- v3_roster_risk(m, me, b$values$values, p_active_fun = avail)
b$health <- i3_health(season, now)

# Ledger (F5): every recommendation with its robustness flag; outcomes stay sealed
mv <- list(briefing = "D5 (VL13)", simulator = "s0_v0 (VL3, VL3b)", pod = "pod_baseline_v0")
ids <- character()
p <- lg_ledger_lineup_payload(b$lineup$adv)
ids <- c(ids, lg_ledger_record("lineup", m$inputs, season, m$current_week, p$recommendation, p$alternatives,
                               c(p$metrics, list(fragile = b$lineup$fragile)), options = list(source = "briefing"),
                               model_versions = c(mv, list(methodology = "valuation_v2", prior = b$lineup$adv$prior_source)))$decision_id)
od <- b$odds$od
base <- od$results$base
ids <- c(ids, lg_ledger_record("odds", m$inputs, season, m$current_week,
                               list(teams = base$teams, matchups = base$matchups, leverage = base$leverage, bands = b$odds$bands,
                                    invariants = as.list(base$invariants), label = od$label),
                               NULL, list(sims = od$sims, seed = od$seed, elapsed_seconds = od$elapsed_seconds),
                               options = list(source = "briefing"),
                               model_versions = c(mv, list(s0_params = "s0_params_v0", sigma_L = as.list(od$sigma_L),
                                                           availability = od$availability_source)))$decision_id)
wb <- b$waivers
ids <- c(ids, lg_ledger_record("waivers", m$inputs, season, m$current_week,
                               list(board = if (nrow(wb$board)) dplyr::select(wb$board, -"drop_rows", -"new_rows") else NULL,
                                    drop_advice = wb$drops, stream_view = wb$stream),
                               NULL, list(fragile = wb$fragile, sims = sims, streaming_recommended = D3_STREAMING_RECOMMENDED),
                               options = list(source = "briefing"), model_versions = c(mv, list(board = "D3 (VL9)")))$decision_id)
if (!is.null(b$trades$top)) {
  ids <- c(ids, lg_ledger_record("trade_rescore", m$inputs, season, m$current_week,
                                 list(top = dplyr::select(b$trades$top, -"a_rows", -"b_rows"), frontier = b$trades$frontier),
                                 NULL, list(fragile = b$trades$fragile, sims = sims, candidates = b$trades$n,
                                            invalid_candidates = b$trades$invalid),
                                 options = list(source = "briefing"), model_versions = c(mv, list(trades = "D2 v3 (VL12)")))$decision_id)
}
b$ledger <- ids

path <- file.path(D5_ROOT, sprintf("season=%d", season), sprintf("week=%02d", m$current_week),
                  paste0("briefing_", format(now, "%Y%m%dT%H%M%SZ", tz = "UTC"), ".md"))
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
md <- d5_markdown(b)
writeLines(md, path, useBytes = TRUE)
# I2 (optional): the same report as a self-contained local HTML page (no external resources)
html <- sub("[.]md$", ".html", path)
writeLines(d5_md_to_html(md, title = paste("Briefing week", b$week)), html, useBytes = TRUE)
cat(d5_console(b, path), sep = "\n")
cat("Local page:", html, "\n")
cat(sprintf("Elapsed %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
