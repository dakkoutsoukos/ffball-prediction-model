# League-specific trade analyzer (Valuation V2).
#
# Usage (from the project root; after scripts/league_refresh.R and a valuation run):
#   Rscript scripts/trade_analyzer.R rankings
#   Rscript scripts/trade_analyzer.R needs [--team "Team"]
#   Rscript scripts/trade_analyzer.R waivers
#   Rscript scripts/trade_analyzer.R values --player "Player"
#   Rscript scripts/trade_analyzer.R analyze --a "Team A" --give-a "P1;P2" --b "Team B" --give-b "P3" [--horizon regular]
#   Rscript scripts/trade_analyzer.R fair --a "Team A" --b "Team B" [--win-win]
#   Rscript scripts/trade_analyzer.R target --player "Player" [--me "My team"]
#   Rscript scripts/trade_analyzer.R sell --player "Player" [--me "My team"]
#   Rscript scripts/trade_analyzer.R snapshot          # archive rankings, needs, waiver levels, value matrix
#   Rscript scripts/trade_analyzer.R lineup [--team "Team"] [--now 2026-10-18T14:00:00Z]
#        # this week's lineup: expected-points starters (players already locked by kickoff keep their ESPN
#        # slots), latest kickoffs in FLEX, and a game-time plan for every designated starter (master plan D0)
#   Rscript scripts/trade_analyzer.R odds [--sims 10000] [--add "Player"] [--drop "Player"]
#        # SHADOW season, playoff and title odds (master plan S0, VL3): this week's P(win), your leverage,
#        # sensitivity bands, and a what-if with common random numbers. Unvalidated; see the printed label.
#   Rscript scripts/trade_analyzer.R rescore --b "Team" [--k 5] [--sims 5000]
#        # SHADOW thin slice (master plan S2/D2): the top K trades with that team by the utility screen,
#        # re-scored by both teams' P(playoffs) and P(title) with common random numbers, plus the
#        # partner's generic-value view and the frontier. Unvalidated; see the printed label.
#   Rscript scripts/trade_analyzer.R faboard [--k 8] [--sims 5000] [--per-pos 6]
#        # SHADOW free-agent board (master plan D3, VL9): the utility screen of adds, the top K re-scored by
#        # your P(playoffs) and P(title) with common random numbers, drop advice, and this week's streaming view.
#   Rscript scripts/trade_analyzer.R ledger-action --decision <id> --action followed|partially|ignored [--note "..."]
# Recommendations (lineup, analyze, fair, target, sell, waivers, faboard) are recorded in the private decision
# ledger (master plan F5; data/archive/decisions/, hashes in archive/decision_manifest.csv). Their
# outcomes stay sealed until after the season and the 2027 decision pre-registrations.
# Common options: --allow-stale  --policy empty_slots|none|unlimited  --horizon full|regular|playoffs  --season 2026
#   --fixed-prior  use the published availability prior instead of P1's frozen provider (E19c) in lineup, odds, rescore
# Teams: name, abbreviation or id. Players: name (resolved to ESPN ids) or ESPN id. "--me" defaults
# to the team owned by the configured SWID. Results are model estimates of expected rest-of-season
# lineup points, not predictions that another manager will accept a trade.
# Query results are archived under data/archive/league_analysis/ (git-ignored) with hashes in
# archive/league_query_manifest.csv.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
a <- commandArgs(trailingOnly = TRUE)
if (!length(a)) stop("Usage: Rscript scripts/trade_analyzer.R <rankings|needs|waivers|faboard|values|analyze|fair|target|sell|snapshot|lineup|odds|rescore|ledger-action> [options]")
cmd <- a[[1]]
opt <- list()
i <- 2
while (i <= length(a)) {
  k <- sub("^--", "", a[[i]])
  if (i < length(a) && !startsWith(a[[i + 1]], "--")) { opt[[k]] <- a[[i + 1]]; i <- i + 2 } else { opt[[k]] <- TRUE; i <- i + 1 }
}
split_players <- function(x) trimws(strsplit(x, ";", fixed = TRUE)[[1]])
season <- as.integer(opt$season %||% nfl_season())  # January games belong to the previous season
horizon <- opt$horizon %||% "full"
options(width = 200, pillar.sigfig = 4, tibble.print_max = 40)

# Record what you did with a ledgered recommendation (master plan F5); no league model needed.
if (cmd == "ledger-action") {
  if (is.null(opt$decision) || is.null(opt$action)) stop("Usage: trade_analyzer.R ledger-action --decision <id> --action followed|partially|ignored [--note \"...\"]")
  lg_ledger_action(opt$decision, opt$action, opt$note %||% "", alias = lg_credentials()$alias)
  cli::cli_alert_success("Recorded {opt$action} for {opt$decision} (private).")
  quit(save = "no", status = 0)
}

m <- lg_load(season, allow_stale = isTRUE(opt[["allow-stale"]]), policy = opt$policy)
la <- m$la
cli::cli_h1("Trade analyzer - {m$policy} streaming, weeks {paste(range(m$weeks), collapse = '-')}, horizon {horizon}")
cli::cli_text("League snapshot {m$inputs$league_captured_at_utc} ({round(m$inputs$league_age_hours, 1)} h old); valuation run {m$inputs$valuation_run_id}{if (!m$inputs$valuation_league_format) ' (default V1 format)' else ''}")
me <- if (!is.null(opt$me)) lg_find_team(m, opt$me) else lg_my_team(m$teams)
# Post-report P(active) for D0 and S0: P1's frozen provider (E19c) unless --fixed-prior (the published prior)
avail <- if (isTRUE(opt[["fixed-prior"]])) NULL else p1_live_availability(season, m$current_week, Sys.time())
mtv_for <- function(rows) {
  cached <- lg_cached_mtv(m)
  if (!is.null(cached) && all(rows %in% cached$row)) return(cached)
  lg_mtv_matrix(m, rows)
}
res <- switch(cmd,
  rankings = {
    r <- lg_power_rankings(m)
    print(dplyr::select(r, "rank", "team", "U", "U_regular", "U_playoffs", "QB", "RB", "WR", "TE", "flex_points", "bench_points", "streamed_points"))
    cli::cli_text("Projection-based expected ROS lineup points, not a standings prediction.")
    list(rankings = r)
  },
  needs = {
    teams <- if (!is.null(opt$team)) lg_find_team(m, opt$team) else if (!is.na(me)) me else as.integer(names(m$state))
    out <- purrr::map(teams, function(t) {
      n <- lg_team_needs(m, t)
      cli::cli_h2("{n$team} (rank {n$rank})")
      print(n$slots)
      print(n$depth)
      cli::cli_text("Weakest slot {n$weakest_slot}; strongest {n$strongest_slot}; deepest bench {n$deepest_bench_position}; largest starter-to-backup drop {n$largest_drop_position}")
      print(n$waiver_upgrades)
      n[c("team", "slots", "depth", "waiver_upgrades")]
    })
    list(needs = out)
  },
  waivers = {
    run <- lg_pick_valuation(season, m$current_week, m$inputs$league_hash)
    base <- arrow::read_parquet(file.path(VAL_ARCHIVE_ROOT, sprintf("season=%d", season), sprintf("week=%02d", m$current_week),
                                          paste0("run=", run$run_id), "baselines.parquet"), mmap = FALSE)
    w <- lg_waiver_comparison(m, base)
    print(w$levels)
    list(waivers = w$levels)
  },
  values = {
    x <- lg_find_player(m, opt$player)
    mt <- lg_mtv_matrix(m, x)
    long <- tidyr::pivot_longer(mt, dplyr::starts_with("team_"), names_to = "team_id", values_to = "mtv") |>
      dplyr::mutate(team_id = as.integer(sub("team_", "", .data$team_id)),
                    team = vapply(.data$team_id, function(t) lg_team_label(m, t), "")) |>
      dplyr::arrange(dplyr::desc(.data$mtv))
    g <- m$generic[match(m$sim$players$player_id[x], m$generic$player_id), ]
    cli::cli_text("{lg_player_label(m, x)}: generic VOR {round(g$vor, 1)}, display value {g$trade_value}")
    print(dplyr::select(long, "team", "mtv"))
    list(values = long)
  },
  analyze = {
    tr <- lg_trade(m, opt$a, split_players(opt[["give-a"]]), opt$b, split_players(opt[["give-b"]]),
                   la$eps, la$strong, horizon = horizon)
    print(dplyr::select(tr$teams, "team", "gives", "gets", "U_before", "U_after", "delta", "delta_regular", "delta_playoffs",
                        "dropped", "added", "generic_vor_gives", "generic_vor_gets", "tv_gives", "tv_gets"))
    print(tr$metrics)
    cat("\n", paste0("- ", tr$explanations, collapse = "\n"), "\n", sep = "")
    tr[c("teams", "metrics", "explanations")]
  },
  fair = {
    ta <- lg_find_team(m, opt$a %||% me)
    tb <- lg_find_team(m, opt$b)
    s <- la$search
    r <- lg_trade_search(m, ta, tb, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                         eps = la$eps, strong = la$strong, horizon = horizon)
    if (isTRUE(opt[["win-win"]])) r <- dplyr::filter(r, .data$win_win)
    print(utils::head(dplyr::select(r, "a_gives", "b_gives", "delta_a", "delta_b", "surplus", "balance", "classification", "n_drop", "n_add"), 25))
    cli::cli_text("{sum(r$win_win)} of {nrow(r)} evaluated trades improve both teams (model estimate; acceptance is not modelled).")
    list(search = dplyr::select(r, -"a_rows", -"b_rows"))
  },
  target = {
    if (is.na(me)) stop("Set --me (your team).")
    s <- la$target
    r <- lg_target_offers(m, me, opt$player, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                          eps = la$eps, strong = la$strong, horizon = horizon)
    print(utils::head(dplyr::select(r, "offer", "target", "target_team", "tv_offer", "tv_target", "delta_me", "delta_them", "classification"), 15))
    list(target = dplyr::select(r, -"offer_rows"))
  },
  sell = {
    if (is.na(me)) stop("Set --me (your team).")
    s <- la$sell
    r <- lg_sell_destinations(m, me, opt$player, NULL, n_teams = s$n_teams, top_n = s$top_n, tv_band = s$tv_band,
                              eps = la$eps, strong = la$strong, horizon = horizon)
    print(r$destinations)
    if (nrow(r$offers)) print(utils::head(dplyr::select(r$offers, "team", "returns", "tv_return", "delta_me", "delta_them", "classification"), 15))
    list(destinations = r$destinations, offers = if (nrow(r$offers)) dplyr::select(r$offers, -"return_rows") else r$offers)
  },
  snapshot = {
    s <- lg_archive_analysis(m)
    print(dplyr::select(s$rankings, "rank", "team", "U", "QB", "RB", "WR", "TE", "bench_points"))
    cli::cli_alert_success("Archived {.file {s$dir}} ({s$meta$elapsed_seconds} s)")
    NULL
  },
  odds = {
    lgs <- lg_latest_snapshot(season)
    state <- lg_state_from_snapshot(lgs)
    if (!state$has_schedule) stop("The league snapshot has no schedule: run scripts/league_refresh.R (view=mMatchup).")
    sims <- as.integer(opt$sims %||% 10000)
    wi <- NULL
    if (!is.null(opt$add) || !is.null(opt$drop)) {
      pick <- function(x) if (is.null(x)) character() else m$sim$players$player_id[lg_find_player(m, x)]
      wi <- list(team = me, add = pick(opt$add), drop = pick(opt$drop))
    }
    od <- sim_league_odds(m, state, sims = sims, what_if = wi, p_active_fun = avail)
    base <- od$results$base
    lab <- function(t) vapply(t, function(x) lg_team_label(m, x), "")
    cli::cli_alert_warning(od$label)
    cli::cli_h2("Season odds ({sims} simulations, {od$elapsed_seconds} s); matchup period {od$current_period}")
    print(dplyr::transmute(dplyr::arrange(base$teams, dplyr::desc(.data$p_title)), team = lab(.data$team_id),
                           e_wins = round(.data$e_wins, 2), p_playoffs = round(.data$p_playoffs, 3),
                           p_seed1 = round(.data$p_seed1, 3), p_title = round(.data$p_title, 3)))
    cli::cli_text("This week's matchups:")
    print(dplyr::transmute(base$matchups, home = lab(.data$home), away = lab(.data$away), p_home = round(.data$p_home, 3),
                           margin_q10 = round(.data$margin_q10, 1), margin_q50 = round(.data$margin_q50, 1),
                           margin_q90 = round(.data$margin_q90, 1)))
    if (!is.null(base$leverage)) {
      lv <- base$leverage
      cli::cli_text("Your leverage this week: P(playoffs) {round(lv$p_playoffs_if_win, 3)} if you win vs {round(lv$p_playoffs_if_loss, 3)} if you lose ({round(lv$leverage, 3)}).")
    }
    cli::cli_text("ESPN's own playoff odds: {if (all(is.na(od$espn_playoff_pct$espn_playoff_pct))) 'not provided by ESPN for this league' else 'see ledger record'}")
    # VL3 sensitivity bands (2,000 simulations each, same seed)
    bands <- purrr::map(list(c(0.5, 1), c(1.5, 1), c(1, 0.8), c(1, 1.2)), function(b) {
      r <- sim_league_odds(m, state, sims = 2000, sigma_scale = b[1], noise_scale = b[2], p_active_fun = avail)$results$base$teams
      dplyr::mutate(dplyr::select(r, "team_id", "p_playoffs", "p_title"), sigma_scale = b[1], noise_scale = b[2])
    }) |>
      purrr::list_rbind()
    if (!is.na(me)) {
      mine <- dplyr::filter(bands, .data$team_id == me)
      cli::cli_text("Your sensitivity range (sigma_L x 0.5-1.5, noise x 0.8-1.2): P(playoffs) {round(min(mine$p_playoffs), 3)}-{round(max(mine$p_playoffs), 3)}, P(title) {round(min(mine$p_title), 3)}-{round(max(mine$p_title), 3)}")
    }
    delta <- NULL
    if (!is.null(wi)) {
      alt <- od$results$what_if$teams
      delta <- dplyr::transmute(dplyr::inner_join(base$teams, alt, by = "team_id", suffix = c("", "_alt")), .data$team_id,
                                d_playoffs = .data$p_playoffs_alt - .data$p_playoffs, d_title = .data$p_title_alt - .data$p_title)
      cli::cli_text("What-if (common random numbers): your change in P(playoffs) {round(delta$d_playoffs[delta$team_id == me], 3)}, P(title) {round(delta$d_title[delta$team_id == me], 3)}")
    }
    rec <- list(teams = base$teams, matchups = base$matchups, leverage = base$leverage, bands = bands, what_if = delta,
                invariants = as.list(base$invariants), label = od$label, espn_playoff_pct = od$espn_playoff_pct)
    d <- lg_ledger_record("odds", m$inputs, season, m$current_week, rec, if (!is.null(wi)) list(what_if = wi) else NULL,
                          list(sims = sims, seed = od$seed, elapsed_seconds = od$elapsed_seconds),
                          options = opt, model_versions = list(simulator = "s0_v0 (VL3, VL3b)", s0_params = "s0_params_v0",
                                                               pod = "pod_baseline_v0", sigma_L = as.list(od$sigma_L),
                                                               availability = od$availability_source))
    cli::cli_text("Ledgered {.val {d$decision_id}} (shadow odds; evaluation-only archive).")
    NULL
  },
  rescore = {
    # S2/D2 thin slice: V2's utility screen, then the top K re-scored by both teams' P(playoffs) and
    # P(title) on the S0 engine (common random numbers); partner lens = the partner's generic VOR net.
    if (is.na(me)) stop("Set --me (your team).")
    if (is.null(opt$b)) stop("Usage: trade_analyzer.R rescore --b \"Team\" [--k 5] [--sims 5000]")
    tb <- lg_find_team(m, opt$b)
    k <- as.integer(opt$k %||% 5)
    sims <- as.integer(opt$sims %||% 5000)
    s <- la$search
    r <- lg_trade_search(m, me, tb, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                         eps = la$eps, strong = la$strong, horizon = horizon)
    if (!nrow(r)) {
      cli::cli_alert_info("No candidate trades passed the utility screen.")
      NULL
    } else {
      top <- utils::head(r, k)
      trades <- lapply(seq_len(nrow(top)), function(i) list(team_a = me, give_a = top$a_rows[[i]], team_b = tb,
                                                            give_b = top$b_rows[[i]]))
      state <- lg_state_from_snapshot(lg_latest_snapshot(season))
      if (!state$has_schedule) stop("The league snapshot has no schedule: run scripts/league_refresh.R (view=mMatchup).")
      d <- sim_trade_rescore(m, state, trades, sims = sims, p_active_fun = avail)
      out <- dplyr::bind_cols(top[c("a_gives", "b_gives")], d)
      cli::cli_alert_warning(S0_LABEL)
      print(dplyr::transmute(out, you_give = .data$a_gives, you_get = .data$b_gives,
                             your_dP_playoffs = round(.data$d_playoffs_a, 3), your_dP_title = round(.data$d_title_a, 3),
                             their_dP_playoffs = round(.data$d_playoffs_b, 3), their_dP_title = round(.data$d_title_b, 3),
                             their_generic_view = round(.data$partner_lens_b, 1), your_dU = round(.data$v2_delta_a, 1),
                             their_dU = round(.data$v2_delta_b, 1)))
      fr <- trade_frontier(out)
      cli::cli_text("Frontier (your simulated title gain vs the partner's generic-value view): trades {paste(fr$trade, collapse = ', ')}.")
      list(rescore = dplyr::select(out, -"label"), frontier_trades = fr$trade, sims = sims)
    }
  },
  faboard = {
    # D3 (VL9): V2's utility screen of free-agent adds, the top K re-scored by your P(playoffs) and
    # P(title) on the S0 engine (common random numbers), drop advice, and this week's streaming view.
    if (is.na(me)) stop("Set --me (your team).")
    k <- as.integer(opt$k %||% 8)
    sims <- as.integer(opt$sims %||% 5000)
    state <- lg_state_from_snapshot(lg_latest_snapshot(season))
    if (!state$has_schedule) stop("The league snapshot has no schedule: run scripts/league_refresh.R (view=mMatchup).")
    sc <- d3_fa_screen(m, me, cand_per_pos = as.integer(opt[["per-pos"]] %||% 6))
    board <- sim_fa_rescore(m, state, me, sc, k = k, sims = sims, p_active_fun = avail)
    drops <- d3_drop_advice(m, me)
    sv <- d3_stream_view(m, me, p_active_fun = avail)
    cli::cli_alert_warning(S0_LABEL)
    cli::cli_text("{if (isTRUE(state$rules$faab)) 'FAAB league: bids are not modelled yet.' else 'No FAAB: claims go by waiver priority.'} Your waiver rank: {state$standings$waiver_rank[state$standings$team_id == me] %||% NA}.")
    cli::cli_h3("Free-agent board (top {k} adds by the utility screen)")
    if (nrow(board)) {
      print(dplyr::transmute(board, .data$add, .data$position, .data$drop, dU = round(.data$dU, 1),
                             dP_playoffs = round(.data$d_playoffs, 3), dP_title = round(.data$d_title, 3),
                             d_wins = round(.data$d_wins, 2)))
    } else {
      cli::cli_text("No free agent improves your expected rest-of-season lineup.")
    }
    cli::cli_h3("Drop advice (cheapest roster players to release)")
    print(dplyr::transmute(drops, .data$player, .data$position, cost_dU = round(.data$cost, 1)))
    if (any(drops$cost < 0)) cli::cli_text("A negative cost means streaming free agents in that player's slot is worth more than keeping him.")
    cli::cli_h3("Streaming view, week {m$current_week} (expected points; gain = change in this week's best lineup)")
    print(dplyr::transmute(sv, .data$position, .data$player, expected = round(.data$expected, 1), gain = round(.data$gain, 1),
                           .data$stream_candidate))
    cli::cli_text("Streaming is {sv$status[1] %||% 'informational'} (VL9). Board deltas below about 0.005 are within simulation noise.")
    list(board = dplyr::select(board, -"drop_rows", -"new_rows"), drop_advice = drops, stream_view = sv, sims = sims,
         streaming_recommended = D3_STREAMING_RECOMMENDED)
  },
  lineup = {
    team <- if (!is.null(opt$team)) lg_find_team(m, opt$team) else me
    if (is.na(team)) stop("Set --team (your team could not be detected).")
    now <- if (!is.null(opt$now)) as.POSIXct(opt$now, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else Sys.time()
    if (is.na(now)) stop("--now must look like 2026-10-18T14:00:00Z")
    tg <- clean_team_games(latest_live_file("schedules", season, now), "REG")
    # the provider as of --now (the lineup's own clock), unless --fixed-prior
    adv <- lg_lineup_advice(m, team, tg, now,
                            p_active_fun = if (is.null(avail)) NULL else p1_live_availability(season, m$current_week, now))
    cli::cli_h2("{lg_team_label(m, team)}: week {adv$week} lineup as of {fmt_et(now)}")
    print(dplyr::transmute(adv$lineup, .data$slot, .data$player, .data$position, .data$nfl,
                           kickoff = ifelse(is.na(.data$kickoff_utc), "-", format(.data$kickoff_utc, "%a %H:%M", tz = DISPATCH_TZ)),
                           proj = round(.data$proj, 1), .data$status, .data$locked, espn = .data$espn_slot, .data$change))
    cli::cli_text("Expected points: recommended {round(adv$ev_recommended, 1)} vs current ESPN lineup {round(adv$ev_current, 1)}. Flexible slots hold the latest kickoffs (no change in expected points).")
    if (nrow(adv$plan)) {
      cli::cli_h3("Game-time plans")
      print(dplyr::transmute(adv$plan, .data$player, .data$status, p_active = .data$p_active,
                             if_active = round(.data$proj_if_active, 1), decide_by = format(.data$decision_utc, "%a %H:%M", tz = DISPATCH_TZ),
                             .data$pivot, pivot_E = round(.data$pivot_E, 1), plan_ev = round(.data$plan_ev, 1), .data$advice))
    } else {
      cli::cli_text("No designated starters: no game-time plan needed.")
    }
    cli::cli_text("P(active) prior: {adv$prior_source}. Projections are this week's (pre-inactive); a plan is advice, not a forecast.")
    list(lineup = adv$lineup, plan = adv$plan,
         ev = tibble::tibble(recommended = adv$ev_recommended, current = adv$ev_current, as_of_utc = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  },
  stop("Unknown command ", cmd)
)
if (!is.null(res)) {
  q <- lg_archive_query(m, cmd, opt, res)
  cli::cli_text("Archived query {.file {basename(q)}}")
  # Decision ledger (master plan F5): every recommendation, with its information state; outcomes sealed
  ledger_type <- unname(c(lineup = "lineup", analyze = "trade_analyze", fair = "trade_search", target = "trade_target",
                          sell = "trade_sell", waivers = "waivers", faboard = "waivers", rescore = "trade_rescore")[cmd])
  if (!is.na(ledger_type)) {
    p <- if (cmd == "lineup") lg_ledger_lineup_payload(adv) else list(recommendation = res, alternatives = NULL, metrics = list())
    d <- lg_ledger_record(ledger_type, m$inputs, season, m$current_week, p$recommendation, p$alternatives, p$metrics,
                          options = opt, model_versions = list(methodology = "valuation_v2", query_file = basename(q),
                                                               prior = if (cmd == "lineup") adv$prior_source else NULL))
    cli::cli_text("Ledgered decision {.val {d$decision_id}} (record it with: ledger-action --decision {d$decision_id} --action followed|partially|ignored)")
  }
}
