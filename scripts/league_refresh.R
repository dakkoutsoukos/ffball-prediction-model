# Refresh the owner's ESPN league snapshot (settings, teams, rosters) - Valuation V2.
#
# Usage (from the project root):
#   Rscript scripts/league_refresh.R [season]
#
# Needs ESPN opted in (config/local.yml: espn: {enabled: true}) and, for a private
# league, the owner's cookies in config/local.yml (never committed):
#   league: {espn_league_id: <id>, espn_s2: "<espn_s2>", swid: "{<SWID>}"}
# One request. Writes data/snapshots/espn_league/<alias>/ (git-ignored) and appends
# hashes (no names, no ids) to archive/league_snapshot_manifest.csv - commit that file.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1) as.integer(args[[1]]) else nfl_season()  # January games belong to the previous season
pcfg <- read_project_config()
cred <- lg_credentials(pcfg)
cli::cli_h1("League refresh {season}")
cli::cli_text("Credentials: {if (is.na(cred$espn_s2) || is.na(cred$swid)) 'none (public league only)' else 'espn_s2 + SWID from local config'}")
snap <- lg_snapshot_league(season, cred, enabled = isTRUE(pcfg$espn$enabled))
lg <- snap$league
lc <- lg_league_config(lg)
cli::cli_alert_success("Snapshot {.file {basename(snap$raw)}}: {nrow(lg$teams)} teams, {nrow(lg$roster)} rostered players, scoring period {lg$scoring_period}")
lgx <- lc$league
cli::cli_text("Slots: {paste(vapply(lgx$slots, function(s) paste0(s$count, ' ', s$name), ''), collapse = ', ')}; bench {lgx$bench}; IR {lgx$ir_slots}; roster {lgx$roster_size}; non-skill starters {paste(names(lgx$nonskill_starters), unlist(lgx$nonskill_starters), collapse = ', ')}")
cli::cli_text("Regular season weeks {paste(lgx$regular_season_weeks, collapse = '-')}, playoffs {paste(lgx$playoff_weeks, collapse = '-')}")
cli::cli_text("Scoring for QB/RB/WR/TE: {if (lc$scoring$equals_espn_ppr) 'identical to ESPN PPR (V1 parameters and M4 apply)' else 'differs from ESPN PPR'}; relevant unmapped items: {nrow(lc$scoring$unmapped)}; K/D-ST-only or negligible items ignored: {nrow(lc$scoring$ignored)}")
if (nrow(lc$scoring$unmapped)) print(lc$scoring$unmapped)
me <- lg_my_team(lg$teams, cred)
cli::cli_text("My team: {if (is.na(me)) 'not detected (set league.my_team_id)' else lg$teams$team_name[lg$teams$team_id == me]}")
# League state v2 (master plan F3-lite): schedule, standings, rules - no names printed
st <- lg_league_state(read_gz_text(snap$raw))
cli::cli_h2("League state")
cli::cli_text("Rules: {lg_rules_summary(st$rules)}")
if (st$has_schedule) {
  cli::cli_text("Schedule: {nrow(st$schedule)} matchups over {length(unique(st$schedule$matchup_period))} periods; current period {st$status$current_matchup_period}.")
} else {
  cli::cli_alert_warning("No schedule in the response (view=mMatchup missing?).")
}
cli::cli_text("ESPN playoff odds in the response: {if (all(is.na(st$standings$espn_playoff_pct))) 'absent' else 'present'}")
chk <- lg_state_checks(st)
for (i in seq_len(nrow(chk))) {
  f <- if (isTRUE(chk$passed[i])) cli::cli_alert_success else if (is.na(chk$passed[i])) cli::cli_alert_info else cli::cli_alert_danger
  f("{chk$check[i]}{if (nzchar(chk$detail[i])) paste0(' (', chk$detail[i], ')') else ''}: {if (is.na(chk$passed[i])) 'not checkable' else if (chk$passed[i]) 'ok' else 'FAILED'}")
}
cli::cli_text("Commit the manifest:  git add archive/league_snapshot_manifest.csv && git commit -m \"League snapshot\"")
