# D4 draft assistant (master plan D4; pre-registration VL10). Projections-only under the O2/O8 defaults
# (no ADP, no league draft history); keepers are off (keeperCount = 0). SHADOW: the opponent model is an
# assumption, not an estimate.
#
# Usage (from the project root; after scripts/league_refresh.R and a preseason valuation run):
#   Rscript scripts/draft_assistant.R --picks data/archive/draft/season=2027/picks.csv [--rollouts 100] [--odds]
#
# The pick log is written by the owner during the draft (git-ignored under data/archive/): one row per pick in
# draft order, columns `team` (name, abbreviation or id) and `player` (name or ESPN id; "K" or "DST" for a
# kicker or defense pick). No ESPN draft request is made. When you are on the clock, the assistant ranks
# the 4 best available per position by your final roster's expected season lineup points over rollouts of
# the rest of the draft, with each player's chance of lasting to your next pick. --odds adds week-0
# E[wins] and P(playoffs) for the top 3 (about a minute more).

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
a <- commandArgs(trailingOnly = TRUE)
opt <- list()
i <- 1
while (i <= length(a)) {
  k <- sub("^--", "", a[[i]])
  if (i < length(a) && !startsWith(a[[i + 1]], "--")) { opt[[k]] <- a[[i + 1]]; i <- i + 2 } else { opt[[k]] <- TRUE; i <- i + 1 }
}
season <- nfl_season()
m <- suppressMessages(lg_load(season, allow_stale = TRUE))
teams <- sort(as.integer(names(m$state)))
owner <- match(m$my_team, teams)
if (is.na(owner)) stop("Your team could not be detected (set league.my_team_id in config/local.yml).")
pool <- d4_pool(val_weekly_frame(m$input_data$weekly), m$league, m$current_week)
picks <- if (!is.null(opt$picks) && file.exists(opt$picks)) readr::read_csv(opt$picks, col_types = "cc") else
  tibble::tibble(team = character(), player = character())
seat_of <- function(x) {        # a digit-only value is a team id (V2's lookup tries names first)
  if (grepl("^[0-9]+$", x) && as.integer(x) %in% teams) match(as.integer(x), teams) else match(lg_find_team(m, x), teams)
}
seat <- unname(vapply(picks$team, seat_of, 0L))
nonskill <- toupper(picks$player) %in% c("K", "DST", "D/ST")
row <- rep(NA_integer_, nrow(picks))
row[!nonskill] <- match(m$sim$players$player_id[vapply(picks$player[!nonskill], function(x) lg_find_player(m, x), 0L)],
                        pool$sim$players$player_id)
if (anyNA(row[!nonskill])) stop("Some picked players are not in the valuation pool: check the pick log.")
n_nonskill <- sum(unlist(m$league$nonskill_starters %||% list()))
st <- d4_live_state(tibble::tibble(seat = seat, row = row), length(teams), pool$rounds, n_nonskill)
label <- function(r) m$sim$players$player_name[match(pool$sim$players$player_id[r], m$sim$players$player_id)]
cli::cli_alert_warning("SHADOW (VL10): projections only; opponents follow an assumed model (rank by VOR, temperature 3, needs, herding).")
if (is.na(st$on_clock)) {
  cli::cli_text("The draft is complete.")
} else if (st$on_clock != owner) {
  cli::cli_text("Pick {st$next_index}: {lg_team_label(m, teams[st$on_clock])} is on the clock.")
} else if (!st$next_is_skill) {
  cli::cli_text("Pick {st$next_index}: take your kicker or defense (the last rounds are reserved for them).")
} else {
  recent <- rev(utils::tail(pool$pos[stats::na.omit(row)], 2))
  t0 <- Sys.time()
  rec <- d4_recommend(st$rosters, st$taken, st$next_index, st$order, owner, pool, recent,
                      rollouts = as.integer(opt$rollouts %||% D4_ROLLOUTS))
  vor_pick <- d4_owner_rule(pool$rows[!pool$rows %in% st$taken], pool, pool$pos[st$rosters[[owner]]])
  cli::cli_h2("Pick {st$next_index}: your recommendation ({round(as.numeric(difftime(Sys.time(), t0, units = 'secs')))} s)")
  top <- utils::head(rec, 5)
  print(tibble::tibble(player = label(top$row), position = top$position, vor = round(top$vor, 1),
                       season_points = round(top$mean_u, 1), se = round(top$se_u, 1),
                       lasts_to_next_pick = round(top$survival_next, 2)))
  cli::cli_text("VOR-greedy pick (the baseline): {label(vor_pick)}. Primary display: {if (D4_ASSISTANT_PRIMARY) 'the assistant' else 'VOR-greedy (the mock drafts did not show the assistant ahead)'}.")
  if (isTRUE(opt$odds)) {
    state <- lg_state_from_snapshot(lg_latest_snapshot(season))
    weeks <- intersect(pool$sim$weeks, seq(m$league$regular_season_weeks[1], m$league$regular_season_weeks[2]))
    od <- d4_rescore_odds(st$rosters, st$taken, st$next_index, st$order, owner, pool, utils::head(rec$row, 3),
                          m$input_data$weekly, read_pod_table(), read_s0_params()$sigma_L, d4_schedule(state, weeks),
                          state$rules$playoff_teams, recent)
    print(tibble::tibble(player = label(od$row), e_wins = round(od$e_wins, 2), p_playoffs = round(od$p_playoffs, 3)))
  }
}
