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
# Common options: --allow-stale  --policy empty_slots|none|unlimited  --horizon full|regular|playoffs  --season 2026
# Teams: name, abbreviation or id. Players: name (resolved to ESPN ids) or ESPN id. "--me" defaults
# to the team owned by the configured SWID. Results are model estimates of expected rest-of-season
# lineup points, not predictions that another manager will accept a trade.
# Query results are archived under data/archive/league_analysis/ (git-ignored) with hashes in
# archive/league_query_manifest.csv.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
a <- commandArgs(trailingOnly = TRUE)
if (!length(a)) stop("Usage: Rscript scripts/trade_analyzer.R <rankings|needs|waivers|values|analyze|fair|target|sell|snapshot> [options]")
cmd <- a[[1]]
opt <- list()
i <- 2
while (i <= length(a)) {
  k <- sub("^--", "", a[[i]])
  if (i < length(a) && !startsWith(a[[i + 1]], "--")) { opt[[k]] <- a[[i + 1]]; i <- i + 2 } else { opt[[k]] <- TRUE; i <- i + 1 }
}
split_players <- function(x) trimws(strsplit(x, ";", fixed = TRUE)[[1]])
season <- as.integer(opt$season %||% format(Sys.Date(), "%Y"))
horizon <- opt$horizon %||% "full"
options(width = 200, pillar.sigfig = 4, tibble.print_max = 40)

m <- lg_load(season, allow_stale = isTRUE(opt[["allow-stale"]]), policy = opt$policy)
la <- m$la
cli::cli_h1("Trade analyzer - {m$policy} streaming, weeks {paste(range(m$weeks), collapse = '-')}, horizon {horizon}")
cli::cli_text("League snapshot {m$inputs$league_captured_at_utc} ({round(m$inputs$league_age_hours, 1)} h old); valuation run {m$inputs$valuation_run_id}{if (!m$inputs$valuation_league_format) ' (default V1 format)' else ''}")
me <- if (!is.null(opt$me)) lg_find_team(m, opt$me) else lg_my_team(m$teams)
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
  stop("Unknown command ", cmd)
)
if (!is.null(res)) {
  q <- lg_archive_query(m, cmd, opt, res)
  cli::cli_text("Archived query {.file {basename(q)}}")
}
