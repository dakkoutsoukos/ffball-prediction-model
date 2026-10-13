# League state v2 (master plan F3-lite) ---------------------------------------------------------
# What the single league request returns beyond rosters:
#   schedule   - view=mMatchup (approved by the owner 2026-10-13): matchup periods, home/away team
#                ids, points, winner, playoff tier;
#   standings  - mTeam: records, seeds, ranks, waiver rank, transaction counters, and ESPN's own
#                playoff odds (currentSimulationResults.playoffPct) when ESPN returns them;
#   rules      - mSettings: schedule and playoff format, tie rules, home bonus, top-half bonus,
#                trade deadline, keepers, waiver / FAAB settings.
# Parsing only, from the stored raw snapshot: nothing is fetched here. Outputs carry team ids, never
# names; names stay in the git-ignored snapshot. Field names follow the open-source ESPN clients
# (ffscrapr, espn-api), verified on the first live response by keys only.

lg_ms_to_utc <- function(ms) {
  if (is.null(ms) || !length(ms) || is.na(ms)) return(as.POSIXct(NA, tz = "UTC"))
  as.POSIXct(as.numeric(ms) / 1000, origin = "1970-01-01", tz = "UTC")
}

lg_int <- function(x) if (is.null(x) || !length(x)) NA_integer_ else as.integer(x)
lg_num <- function(x) if (is.null(x) || !length(x)) NA_real_ else as.numeric(x)
lg_chr <- function(x) if (is.null(x) || !length(x)) NA_character_ else as.character(x)

#' League rules that matter for simulation and decisions (mSettings).
lg_parse_rules <- function(settings) {
  ss <- settings$scheduleSettings %||% list()
  sc <- settings$scoringSettings %||% list()
  tr <- settings$tradeSettings %||% list()
  ac <- settings$acquisitionSettings %||% list()
  dr <- settings$draftSettings %||% list()
  mp <- ss$matchupPeriods %||% list()
  enh <- lg_chr(sc$scoringEnhancementType)
  list(
    teams = lg_int(settings$size),
    regular_periods = lg_int(ss$matchupPeriodCount),
    playoff_teams = lg_int(ss$playoffTeamCount),
    playoff_seeding_rule = lg_chr(ss$playoffSeedingRule),
    playoff_seeding_rule_by = lg_int(ss$playoffSeedingRuleBy),
    playoff_period_length = lg_int(ss$playoffMatchupPeriodLength),
    playoff_period_length_by_round = unlist(ss$playoffMatchupPeriodLengthByRound %||% list()),
    playoff_reseed = isTRUE(ss$playoffReseed),
    divisions = length(ss$divisions %||% list()),
    matchup_periods = tibble::tibble(matchup_period = as.integer(names(mp)),
                                     scoring_periods = unname(lapply(mp, function(x) as.integer(unlist(x))))),
    matchup_tie_rule = lg_chr(sc$matchupTieRule),
    matchup_tie_rule_by = lg_int(sc$matchupTieRuleBy),
    playoff_matchup_tie_rule = lg_chr(sc$playoffMatchupTieRule),
    home_team_bonus = lg_num(sc$homeTeamBonus %||% 0),
    playoff_home_team_bonus = lg_num(sc$playoffHomeTeamBonus %||% 0),
    scoring_enhancement_type = enh,
    top_half_bonus = identical(enh, "WIN_BONUS_TOP_HALF"),
    trade_deadline_utc = lg_ms_to_utc(tr$deadlineDate),
    veto_votes_required = lg_int(tr$vetoVotesRequired),
    trade_revision_hours = lg_int(tr$revisionHours),
    keeper_count = lg_int(dr$keeperCount %||% 0),
    faab = isTRUE(ac$isUsingAcquisitionBudget),
    acquisition_budget = lg_num(ac$acquisitionBudget),
    minimum_bid = lg_num(ac$minimumBid),
    acquisition_limit = lg_int(ac$acquisitionLimit),
    matchup_acquisition_limit = lg_int(ac$matchupAcquisitionLimit),
    waiver_hours = lg_int(ac$waiverHours),
    waiver_process_days = unlist(ac$waiverProcessDays %||% list()),
    waiver_process_hour = lg_int(ac$waiverProcessHour),
    waiver_order_reset = isTRUE(ac$waiverOrderReset)
  )
}

#' Matchup schedule (view=mMatchup): one row per matchup; a missing away team is a bye.
lg_parse_schedule <- function(doc) {
  sch <- doc$schedule %||% list()
  empty <- tibble::tibble(matchup_id = integer(), matchup_period = integer(), home_team = integer(), away_team = integer(),
                          home_points = numeric(), away_points = numeric(), winner = character(), playoff_tier = character())
  if (!length(sch)) return(empty)
  purrr::map(sch, function(g) {
    tibble::tibble(matchup_id = lg_int(g$id), matchup_period = lg_int(g$matchupPeriodId),
                   home_team = lg_int(g$home$teamId), away_team = lg_int(g$away$teamId),
                   home_points = lg_num(g$home$totalPoints), away_points = lg_num(g$away$totalPoints),
                   winner = lg_chr(g$winner), playoff_tier = lg_chr(g$playoffTierType))
  }) |>
    purrr::list_rbind()
}

#' Standings and team state (mTeam). ESPN's playoff odds are NA when ESPN does not return them.
lg_parse_standings <- function(doc) {
  purrr::map(doc$teams %||% list(), function(t) {
    o <- t$record$overall %||% list()
    tc <- t$transactionCounter %||% list()
    tibble::tibble(team_id = lg_int(t$id), wins = lg_int(o$wins), losses = lg_int(o$losses), ties = lg_int(o$ties),
                   percentage = lg_num(o$percentage), points_for = lg_num(o$pointsFor), points_against = lg_num(o$pointsAgainst),
                   games_back = lg_num(o$gamesBack), streak_length = lg_int(o$streakLength), streak_type = lg_chr(o$streakType),
                   playoff_seed = lg_int(t$playoffSeed), rank_calculated_final = lg_int(t$rankCalculatedFinal),
                   rank_final = lg_int(t$rankFinal), current_projected_rank = lg_int(t$currentProjectedRank),
                   division_id = lg_int(t$divisionId), waiver_rank = lg_int(t$waiverRank),
                   budget_spent = lg_num(tc$acquisitionBudgetSpent), acquisitions = lg_int(tc$acquisitions),
                   drops = lg_int(tc$drops), trades = lg_int(tc$trades), move_to_ir = lg_int(tc$moveToIR),
                   espn_playoff_pct = lg_num(t$currentSimulationResults$playoffPct))
  }) |>
    purrr::list_rbind()
}

#' Full league state from a raw league response (text or parsed list).
lg_league_state <- function(json) {
  doc <- if (is.character(json)) jsonlite::fromJSON(json, simplifyVector = FALSE) else json
  st <- doc$status %||% list()
  list(rules = lg_parse_rules(doc$settings %||% list()), schedule = lg_parse_schedule(doc),
       standings = lg_parse_standings(doc),
       status = list(current_matchup_period = lg_int(st$currentMatchupPeriod), latest_scoring_period = lg_int(st$latestScoringPeriod),
                     first_scoring_period = lg_int(st$firstScoringPeriod), final_scoring_period = lg_int(st$finalScoringPeriod),
                     scoring_period = lg_int(doc$scoringPeriodId)),
       has_schedule = length(doc$schedule %||% list()) > 0)
}

#' League state of a stored snapshot (lg_latest_snapshot()), re-read from its verified raw file.
lg_state_from_snapshot <- function(lg) lg_league_state(read_gz_text(lg$raw_path))

#' Regular-season records recomputed from decided matchups (ties and byes handled).
lg_recompute_records <- function(schedule, regular_periods) {
  done <- dplyr::filter(schedule, .data$matchup_period <= regular_periods, .data$winner %in% c("HOME", "AWAY", "TIE"))
  home <- dplyr::transmute(done, team_id = .data$home_team, pf = .data$home_points, pa = .data$away_points,
                           w = .data$winner == "HOME", l = .data$winner == "AWAY", t = .data$winner == "TIE")
  away <- dplyr::filter(done, !is.na(.data$away_team)) |>
    dplyr::transmute(team_id = .data$away_team, pf = .data$away_points, pa = .data$home_points,
                     w = .data$winner == "AWAY", l = .data$winner == "HOME", t = .data$winner == "TIE")
  dplyr::bind_rows(home, away) |>
    dplyr::summarise(wins = sum(.data$w), losses = sum(.data$l), ties = sum(.data$t),
                     points_for = sum(.data$pf), points_against = sum(.data$pa), .by = "team_id") |>
    dplyr::arrange(.data$team_id)
}

#' Current seeding order under the league's rule: win share, then the tiebreaker. Supported:
#' TOTAL_POINTS_SCORED (points for). Other rules return NA (not needed for this league yet).
lg_seed_order <- function(records, rule) {
  if (!identical(rule, "TOTAL_POINTS_SCORED")) return(rep(NA_integer_, nrow(records)))
  g <- records$wins + records$losses + records$ties
  share <- ifelse(g > 0, (records$wins + 0.5 * records$ties) / g, 0)
  o <- order(-share, -records$points_for, records$team_id)
  seed <- integer(nrow(records))
  seed[o] <- seq_along(o)
  seed
}

#' Invariants of a league state. Returns a tibble of named checks (TRUE = passed, NA = not checkable).
lg_state_checks <- function(state) {
  r <- state$rules
  sch <- state$schedule
  chk <- function(name, ok, detail = "") tibble::tibble(check = name, passed = ok, detail = detail)
  if (!state$has_schedule) return(chk("schedule present", FALSE, "no schedule in this snapshot (taken before view=mMatchup)"))
  reg <- dplyr::filter(sch, .data$matchup_period <= r$regular_periods)
  long <- dplyr::bind_rows(dplyr::transmute(reg, .data$matchup_period, team = .data$home_team),
                           dplyr::transmute(dplyr::filter(reg, !is.na(.data$away_team)), .data$matchup_period, team = .data$away_team))
  per <- dplyr::count(long, .data$matchup_period, .data$team)
  per_period <- dplyr::count(long, .data$matchup_period)
  rec <- lg_recompute_records(sch, r$regular_periods)
  espn <- dplyr::select(state$standings, "team_id", "wins", "losses", "ties", "points_for", "points_against", "playoff_seed")
  cmp <- dplyr::inner_join(rec, espn, by = "team_id", suffix = c("", "_espn"))
  rec_ok <- nrow(cmp) == nrow(espn) && all(cmp$wins == cmp$wins_espn & cmp$losses == cmp$losses_espn & cmp$ties == cmp$ties_espn)
  pts_ok <- nrow(cmp) == nrow(espn) && all(abs(cmp$points_for - cmp$points_for_espn) < 0.01 &
                                             abs(cmp$points_against - cmp$points_against_espn) < 0.01)
  seeds <- lg_seed_order(cmp, r$playoff_seeding_rule)
  seed_ok <- if (all(is.na(seeds)) || all(is.na(cmp$playoff_seed))) NA else all(seeds == cmp$playoff_seed)
  dplyr::bind_rows(
    chk("one game per team per regular period", all(per$n == 1)),
    chk("every team plays every regular period", all(per_period$n == r$teams) && nrow(per_period) == r$regular_periods,
        sprintf("%d periods with games", nrow(per_period))),
    chk("records recomputed from the schedule equal ESPN's", rec_ok, sprintf("%d teams compared", nrow(cmp))),
    chk("points for/against equal ESPN's", pts_ok),
    chk("seeds follow the league's seeding rule", seed_ok, r$playoff_seeding_rule)
  )
}

#' Non-identifying one-line summary of the rules (safe for logs and chat).
lg_rules_summary <- function(r, now = Sys.time()) {
  days <- as.numeric(difftime(r$trade_deadline_utc, now, units = "days"))
  plen <- if (length(r$playoff_period_length_by_round)) paste(r$playoff_period_length_by_round, collapse = "/") else
    as.character(r$playoff_period_length)
  sprintf(paste("%d teams; %d regular periods; %d playoff teams (seeding %s, round lengths %s); tie rule %s / playoffs %s;",
                "home bonus %s; top-half bonus %s; FAAB %s; keepers %d; trade deadline %s (%s days from now)"),
          r$teams, r$regular_periods, r$playoff_teams, r$playoff_seeding_rule, plen,
          r$matchup_tie_rule, r$playoff_matchup_tie_rule, r$home_team_bonus, r$top_half_bonus, r$faab, r$keeper_count,
          format(r$trade_deadline_utc, "%Y-%m-%d"), round(days, 1))
}
