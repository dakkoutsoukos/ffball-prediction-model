# Valuation V2: loading a league analysis and archiving it point-in-time ------------------
# An analysis is built from three archived inputs, all point-in-time:
#   league snapshot   data/snapshots/espn_league/<alias>/ (rosters, settings)  [lg_latest_snapshot()]
#   valuation run     data/archive/valuation/ (weekly projections + generic values in the
#                     league's format when available)                          [latest_valuation_run()]
#   configuration     config/valuation.yml league_analysis (policy, thresholds, sims)
# lg_archive_analysis() writes rankings, waiver levels, the marginal-value matrix and
# team needs write-once under data/archive/league_analysis/<alias>/ (git-ignored) and
# appends hashes to archive/league_analysis_manifest.csv. No private league content
# (names, ids, rosters) is ever committed.

LG_ANALYSIS_ROOT <- "data/archive/league_analysis"
LG_ANALYSIS_MANIFEST <- "archive/league_analysis_manifest.csv"

lg_config <- function(cfg = read_valuation_config()) {
  utils::modifyList(list(policy = "empty_slots", eps = 5, strong = 20, sims = 200, seed = 20261007,
                         max_age_hours = 24, mtv_free_agents = 30), cfg$league_analysis %||% list())
}

#' League configuration (V1 league object + scoring) derived from a snapshot.
lg_league_config <- function(lg) {
  league <- lg_map_settings(lg$settings)
  ids <- vapply(lg$settings$scoringSettings$scoringItems %||% list(), function(i) as.character(i$statId), "")
  usage <- lg_skill_stat_usage(setdiff(ids, names(VAL_ESPN_STAT_MAP)))
  sc <- lg_map_scoring(lg$settings, usage = usage)
  league$scoring <- if (sc$equals_espn_ppr) "espn_ppr" else "league"
  list(league = league, scoring = sc, hash = val_league_hash(league))
}

#' The valuation run to use: the latest verified run for the season-week valued in
#' this league's format (league hash), else the latest default-format run (flagged).
lg_pick_valuation <- function(season, week, league_hash, manifest = VAL_MANIFEST) {
  if (!file.exists(manifest)) cli::cli_abort("No valuation runs: run {.code Rscript scripts/valuation_run.R --capture}.")
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::filter(as.integer(.data$season) == !!season, as.integer(.data$week) == !!week)
  if (!nrow(m)) cli::cli_abort("No valuation run for {season} week {week}.")
  same <- m[m$league_hash == league_hash, ]
  pick <- if (nrow(same)) same else m
  r <- pick[order(pick$run_id, decreasing = TRUE)[1], ]
  dir <- file.path(VAL_ARCHIVE_ROOT, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", r$run_id))
  ok <- verify_valuation_archive(manifest)
  if (!isTRUE(ok$verified[ok$run_id == r$run_id])) cli::cli_abort("Valuation run {r$run_id} failed hash verification.")
  list(run_id = r$run_id, league_format = nrow(same) > 0,
       weekly = arrow::read_parquet(file.path(dir, "weekly.parquet"), mmap = FALSE),
       values = arrow::read_parquet(file.path(dir, "values.parquet"), mmap = FALSE),
       values_sha256 = r$values_sha256, meta = jsonlite::read_json(file.path(dir, "run_meta.json")))
}

#' Build the league model from the latest league snapshot and valuation run.
lg_load <- function(season = as.integer(format(Sys.Date(), "%Y")), as_of = Sys.time(), allow_stale = FALSE,
                    policy = NULL, cfg = read_valuation_config(), lg = NULL) {
  la <- lg_config(cfg)
  lg <- lg %||% lg_latest_snapshot(season, as_of = as_of)
  lg_check_fresh(lg, la$max_age_hours, allow_stale)
  lc <- lg_league_config(lg)
  week <- lg$scoring_period
  val <- lg_pick_valuation(season, week, lc$hash)
  if (!val$league_format) {
    cli::cli_warn(c("Valuation run {val$run_id} is in the default V1 league format, not this league's.",
                    "i" = "Generic values follow the default league; run {.code Rscript scripts/valuation_run.R --league}."))
  }
  m <- lg_model(val$weekly, lg$roster, lc$league, week, policy = policy %||% la$policy, sims = la$sims, seed = la$seed,
                generic = dplyr::select(val$values, "player_id", "vor", "trade_value", "overall_rank", "position_rank"),
                teams = lg$teams)
  m$inputs <- list(league_alias = lg$roster$league_alias[1], league_captured_at_utc = lg$roster$captured_at_utc[1],
                   league_raw_sha256 = lg$raw_sha256, league_age_hours = lg$age_hours, league_hash = lc$hash,
                   valuation_run_id = val$run_id, valuation_values_sha256 = val$values_sha256,
                   valuation_league_format = val$league_format, scoring_equals_espn_ppr = lc$scoring$equals_espn_ppr,
                   unmapped_scoring_items = nrow(lc$scoring$unmapped), policy = m$policy, sims = la$sims, seed = la$seed)
  m$season <- as.integer(season)
  m$input_data <- list(weekly = val$weekly, roster = lg$roster, league = lc$league)  # for hypothetical rebuilds
  m$my_team <- lg_my_team(lg$teams)
  m$diagnostics <- lg_id_diagnostics(lg$roster, dplyr::distinct(val$weekly, .data$espn_id, .data$player_id, .data$position, .data$team))
  m$la <- la
  m$scoring <- lc$scoring
  m
}

#' Generic (V1 run) waiver level vs the league's actual free-agent level, per position.
lg_waiver_comparison <- function(m, generic_baselines = NULL) {
  act <- lg_fa_levels(m, m$fa_rows) |> dplyr::summarise(actual_fa_level = mean(.data$W), .by = "position")
  k <- purrr::map(m$spec$positions, function(p) {
    r <- m$fa_rows[m$sim$players$position[m$fa_rows] == p]
    ppg <- sort(m$sim$ros[r] / pmax(rowSums(m$sim$E[r, , drop = FALSE] > 0), 1), decreasing = TRUE)
    tibble::tibble(position = p, fa_rank = seq_len(min(10, length(ppg))), ppg = utils::head(ppg, 10))
  }) |>
    purrr::list_rbind()
  best <- purrr::map(m$spec$positions, function(p) {
    r <- m$fa_rows[m$sim$players$position[m$fa_rows] == p]
    r <- r[order(-m$sim$ros[r])][seq_len(min(3, length(r)))]
    tibble::tibble(position = p, best_free_agents = paste(lg_player_label(m, r), collapse = ", "))
  }) |>
    purrr::list_rbind()
  out <- dplyr::left_join(act, best, by = "position")
  if (!is.null(generic_baselines)) {
    g <- generic_baselines |>
      dplyr::filter(.data$week %in% m$weeks) |>
      dplyr::summarise(generic_replacement = mean(.data$R), .by = "position")
    out <- dplyr::left_join(out, g, by = "position") |>
      dplyr::mutate(actual_minus_generic = .data$actual_fa_level - .data$generic_replacement)
  }
  list(levels = out, curves = k)
}

#' Compute and archive the standard analysis outputs for the current snapshot.
lg_archive_analysis <- function(m, root = LG_ANALYSIS_ROOT, manifest = LG_ANALYSIS_MANIFEST, mtv_rows = NULL) {
  t0 <- Sys.time()
  pr <- lg_power_rankings(m)
  fa_extra <- m$fa_rows[order(-m$sim$ros[m$fa_rows])][seq_len(min(length(m$fa_rows), m$la$mtv_free_agents %||% 30))]
  mtv_rows <- mtv_rows %||% unique(c(lg_all_rostered(m), fa_extra))
  mtv <- lg_mtv_matrix(m, mtv_rows)
  needs <- purrr::map(names(m$state), function(t) {
    n <- lg_team_needs(m, as.integer(t), pr)
    tibble::tibble(team_id = as.integer(t), team = n$team, rank = n$rank, weakest_slot = n$weakest_slot,
                   strongest_slot = n$strongest_slot, deepest_bench = n$deepest_bench_position,
                   largest_drop = n$largest_drop_position,
                   best_waiver_add = n$waiver_upgrades$add[1] %||% NA_character_,
                   best_waiver_drop = n$waiver_upgrades$drop[1] %||% NA_character_,
                   best_waiver_gain = n$waiver_upgrades$gain[1] %||% NA_real_)
  }) |>
    purrr::list_rbind()
  wc <- lg_waiver_comparison(m)
  # my team against every other team: win-win and fair trades (model estimates)
  my <- m$my_team %||% NA_integer_
  searches <- NULL
  if (!is.na(my)) {
    sc <- m$la$search %||% list(top_n = 12, tv_band = 40, max_eval = 250)
    searches <- purrr::map(setdiff(as.integer(names(m$state)), my), function(t) {
      r <- lg_trade_search(m, my, t, mtv, top_n = sc$top_n, tv_band = sc$tv_band, max_eval = sc$max_eval,
                           eps = m$la$eps, strong = m$la$strong)
      if (!nrow(r)) return(NULL)
      dplyr::mutate(utils::head(dplyr::select(r, -"a_rows", -"b_rows"), 15), other_team_id = t,
                    other_team = lg_team_label(m, t), .before = 1)
    }) |>
      purrr::list_rbind()
  }
  run_id <- utc_stamp()
  alias <- m$inputs$league_alias %||% "synthetic"
  dir <- file.path(root, alias, sprintf("season=%d", m$season %||% 2026L), paste0("run=", run_id))
  wp <- function(name, d) write_once(file.path(dir, paste0(name, ".parquet")), function(tmp) arrow::write_parquet(d, tmp))
  paths <- list(rankings = wp("power_rankings", pr), mtv = wp("mtv", mtv), needs = wp("team_needs", needs),
                waiver = wp("waiver_levels", wc$levels), waiver_curves = wp("waiver_curves", wc$curves))
  if (!is.null(searches) && nrow(searches)) paths$my_team_trades <- wp("my_team_trades", searches)
  git <- git_state()
  meta <- c(list(run_id = run_id, methodology_version = "valuation_v2", git_commit = git$commit, git_dirty = git$dirty,
                 league = m$league, horizon_weeks = m$weeks, elapsed_seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)),
            m$inputs, list(files_sha256 = lapply(paths, sha256_file)))
  mp <- write_once(file.path(dir, "analysis_meta.json"), function(tmp) jsonlite::write_json(meta, tmp, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"))
  append_manifest(tibble::tibble(
    run_id = run_id, league_alias = alias, captured_league_at_utc = m$inputs$league_captured_at_utc %||% "",
    league_raw_sha256 = m$inputs$league_raw_sha256 %||% "", valuation_run_id = m$inputs$valuation_run_id %||% "",
    policy = m$policy, rankings_sha256 = sha256_file(paths$rankings), mtv_sha256 = sha256_file(paths$mtv),
    meta_sha256 = sha256_file(mp), git_commit = git$commit
  ), manifest)
  list(dir = dir, rankings = pr, mtv = mtv, needs = needs, waiver = wc, searches = searches, meta = meta)
}

#' Latest archived analysis (verified), read back for reports.
lg_latest_analysis <- function(alias, root = LG_ANALYSIS_ROOT, manifest = LG_ANALYSIS_MANIFEST) {
  if (!file.exists(manifest)) return(NULL)
  r <- readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |> dplyr::filter(.data$league_alias == !!alias)
  if (!nrow(r)) return(NULL)
  r <- r[order(r$run_id, decreasing = TRUE)[1], ]
  d <- list.files(file.path(root, alias), pattern = paste0("^run=", r$run_id, "$"), include.dirs = TRUE, recursive = TRUE,
                  full.names = TRUE)[1]
  meta_path <- file.path(d, "analysis_meta.json")
  if (!identical(sha256_file(meta_path), r$meta_sha256)) cli::cli_abort("Analysis {r$run_id} does not match its manifest hash.")
  read <- function(f) if (file.exists(file.path(d, f))) arrow::read_parquet(file.path(d, f), mmap = FALSE) else NULL
  list(run_id = r$run_id, dir = d, meta = jsonlite::read_json(meta_path), rankings = read("power_rankings.parquet"),
       mtv = read("mtv.parquet"), needs = read("team_needs.parquet"), waiver = read("waiver_levels.parquet"),
       waiver_curves = read("waiver_curves.parquet"), my_team_trades = read("my_team_trades.parquet"))
}

#' Rebuild the model under a hypothetical league format (same rosters and projections),
#' e.g. a superflex slot added, to compare marginal values.
lg_hypothetical <- function(m, league) {
  h <- lg_model(m$input_data$weekly, m$input_data$roster, league, m$current_week, policy = m$policy,
                sims = m$sim$sims, seed = m$sim$seed, generic = m$generic, teams = m$teams)
  h$inputs <- m$inputs
  h
}

#' Latest archived analysis whose inputs match the model (to reuse its MTV matrix).
lg_cached_mtv <- function(m, root = LG_ANALYSIS_ROOT, manifest = LG_ANALYSIS_MANIFEST) {
  if (!file.exists(manifest) || is.null(m$inputs)) return(NULL)
  r <- readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::filter(.data$league_alias == m$inputs$league_alias, .data$league_raw_sha256 == m$inputs$league_raw_sha256,
                  .data$valuation_run_id == m$inputs$valuation_run_id, .data$policy == m$policy)
  if (!nrow(r)) return(NULL)
  r <- r[order(r$run_id, decreasing = TRUE)[1], ]
  f <- list.files(file.path(root, r$league_alias), pattern = "^mtv[.]parquet$", recursive = TRUE, full.names = TRUE)
  f <- f[grepl(paste0("run=", r$run_id), f)]
  if (!length(f) || !identical(sha256_file(f[1]), r$mtv_sha256)) return(NULL)
  arrow::read_parquet(f[1], mmap = FALSE)
}

LG_QUERY_MANIFEST <- "archive/league_query_manifest.csv"

#' Archive one analyzer query (its options, inputs and result tables) write-once;
#' the committed manifest gets the command, input hashes and result hash only.
lg_archive_query <- function(m, cmd, opt, res, root = LG_ANALYSIS_ROOT, manifest = LG_QUERY_MANIFEST) {
  qid <- utc_stamp()
  alias <- m$inputs$league_alias %||% "synthetic"
  path <- file.path(root, alias, sprintf("season=%d", m$season %||% 2026L), "queries", paste0(qid, "_", cmd, ".json"))
  git <- git_state()
  body <- list(query_id = qid, command = cmd, options = opt, inputs = m$inputs, horizon_weeks = m$weeks,
               methodology_version = "valuation_v2", git_commit = git$commit, result = res)
  path <- write_once(path, function(tmp) jsonlite::write_json(body, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 6,
                                                              na = "null", null = "null"))
  append_manifest(tibble::tibble(query_id = qid, league_alias = alias, command = cmd,
                                 league_raw_sha256 = m$inputs$league_raw_sha256 %||% "",
                                 valuation_run_id = m$inputs$valuation_run_id %||% "", policy = m$policy,
                                 result_sha256 = sha256_file(path), git_commit = git$commit), manifest)
  path
}
