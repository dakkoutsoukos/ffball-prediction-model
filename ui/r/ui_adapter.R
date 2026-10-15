# Streamlit UI adapter: exploratory, side-effect-free computations for the local UI (docs/streamlit_audit/).
#
# Usage (from anywhere):
#   Rscript ui/r/ui_adapter.R <op> --request <request.json> --out <output dir>
# Ops: noop, health, context, lineup, odds, trade_eval, trade_search, fa_board, values3, research_target.
#
# It composes the same core functions as scripts/trade_analyzer.R but never calls the CLI wrappers'
# persistence: no query archive, no decision ledger, no manifest rows, no ESPN or other network request,
# no git writes. Those functions are replaced by trip-wires after R/ is sourced (process-local; no file in
# R/ changes). Results are exploratory and are written only to the --out directory, which the UI places
# under data/archive/ui_cache/ (git-ignored). Writes go to a temporary sibling first and are renamed.
#
# Exit codes: 0 ok, 2 bad request, 3 missing or stale context, 4 compute error, 5 trip-wire fired.

ADAPTER_VERSION <- "ui_adapter_v1"
SIM_CAPS <- c(odds = 10000L, trade_eval = 5000L, trade_search = 5000L, fa_board = 5000L, values3 = 5000L)
RESEARCH_TARGETS <- c("vl11_result", "x22_result", "p3_gate_result", "s2_summary", "f1_mde", "e19_check",
                      "m4_dev_eval", "m2_holdout_tables")

args <- commandArgs(trailingOnly = FALSE)
script <- normalizePath(sub("^--file=", "", args[startsWith(args, "--file=")][1]), winslash = "/")
root <- normalizePath(file.path(dirname(script), "..", ".."), winslash = "/")
setwd(root)
a <- commandArgs(trailingOnly = TRUE)

fail <- function(code, msg) {
  cat(sprintf("UI_ADAPTER_ERROR %d: %s\n", code, msg), file = stderr())
  quit(save = "no", status = code)
}
if (!length(a)) fail(2L, "usage: ui_adapter.R <op> --request <json> --out <dir>")
op <- a[[1]]
opt <- list()
i <- 2
while (i <= length(a)) {
  k <- sub("^--", "", a[[i]])
  if (i < length(a) && !startsWith(a[[i + 1]], "--")) { opt[[k]] <- a[[i + 1]]; i <- i + 2 } else { opt[[k]] <- TRUE; i <- i + 1 }
}
if (is.null(opt$out)) fail(2L, "--out is required")
out_dir <- normalizePath(opt$out, winslash = "/", mustWork = FALSE)
cache_root <- normalizePath(file.path(root, "data", "archive", "ui_cache"), winslash = "/", mustWork = FALSE)
if (!startsWith(out_dir, paste0(cache_root, "/"))) fail(2L, "--out must be inside data/archive/ui_cache/")
req <- if (!is.null(opt$request)) jsonlite::fromJSON(opt$request, simplifyVector = TRUE) else list()
`%||%` <- function(x, y) if (is.null(x)) y else x
p <- req$params
if (is.null(p)) p <- list()

t0 <- Sys.time()
suppressMessages(for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f))

# ---- trip-wires: persistence, network and git writes are refused in this process ----
tripped <- function(name) function(...) {
  cat(sprintf("UI_ADAPTER_TRIPWIRE %s\n", name), file = stderr())
  quit(save = "no", status = 5L)
}
for (fn in c("append_manifest", "lg_archive_query", "lg_archive_analysis", "lg_ledger_record", "lg_ledger_action",
             "lg_snapshot_league", "lg_fetch_league", "fetch_live_nflverse", "refresh_live_data", "write_once",
             "write_frozen_yaml", "write_fingerprint")) {
  if (exists(fn, envir = globalenv())) assign(fn, tripped(fn), envir = globalenv())
}
block_ns <- function(pkg, fns) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(invisible())
  ns <- asNamespace(pkg)
  for (fn in fns) if (exists(fn, envir = ns, inherits = FALSE)) {
    unlockBinding(fn, ns); assign(fn, tripped(paste0(pkg, "::", fn)), envir = ns); lockBinding(fn, ns)
  }
}
block_ns("httr2", c("req_perform", "req_perform_parallel", "req_perform_sequential", "req_perform_stream"))
block_ns("httr", c("GET", "POST", "VERB"))
block_ns("curl", c("curl_fetch_memory", "curl_fetch_disk", "curl_download", "curl"))
assign("download.file", tripped("download.file"), envir = globalenv())
base_system2 <- base::system2
assign("system2", function(command, args = character(), ...) {
  if (identical(basename(command), "git") && any(args %in% c("add", "commit", "push", "reset", "checkout", "stash", "tag")))
    tripped(paste("git", paste(args, collapse = " ")))()
  base_system2(command, args, ...)
}, envir = globalenv())

# ---- helpers ----
iso <- function(x) if (inherits(x, "POSIXct")) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else x
clean_df <- function(d) {
  if (is.null(d)) return(NULL)
  d <- as.data.frame(d, stringsAsFactors = FALSE)
  for (n in names(d)) {
    if (inherits(d[[n]], "POSIXct")) d[[n]] <- iso(d[[n]])
    else if (is.list(d[[n]])) d[[n]] <- vapply(d[[n]], function(v) paste(unlist(v), collapse = ";"), "")
    else if (is.factor(d[[n]])) d[[n]] <- as.character(d[[n]])
  }
  d
}
season <- as.integer(p$season %||% nfl_season())
sims_for <- function(op, default) {
  s <- as.integer(p$sims %||% default)
  if (is.na(s) || s < 200L || s > SIM_CAPS[[op]]) fail(2L, sprintf("sims must be between 200 and %d for %s", SIM_CAPS[[op]], op))
  s
}
load_m <- function() {
  m <- tryCatch(suppressWarnings(lg_load(season, allow_stale = TRUE)), error = function(e) fail(3L, conditionMessage(e)))
  want <- req$context$league_raw_sha256
  if (!is.null(want) && nzchar(want) && !identical(want, m$inputs$league_raw_sha256))
    fail(3L, "the league snapshot changed since the page loaded its context; reload the context")
  want <- req$context$valuation_run_id
  if (!is.null(want) && nzchar(want) && !identical(want, m$inputs$valuation_run_id))
    fail(3L, "the valuation run changed since the page loaded its context; reload the context")
  m
}
rows_of <- function(m, ids) {
  ids <- as.character(unlist(ids))
  r <- match(ids, m$sim$players$player_id)
  if (anyNA(r)) fail(2L, sprintf("%d player id(s) are not in the league pool", sum(is.na(r))))
  r
}
team_of <- function(m, t) {
  t <- suppressWarnings(as.integer(t))
  if (length(t) != 1 || is.na(t) || !(t %in% as.integer(names(m$state)))) fail(2L, "unknown team id")
  t
}
my_team <- function(m) {
  t <- if (!is.null(p[["team"]])) team_of(m, p[["team"]]) else m$my_team
  if (is.null(t) || is.na(t)) fail(2L, "team not given and the owner's team could not be detected")
  t
}
league_state <- function() {
  st <- lg_state_from_snapshot(lg_latest_snapshot(season))
  if (!isTRUE(st$has_schedule)) fail(3L, "the league snapshot has no schedule; run scripts/league_refresh.R in a terminal")
  st
}
availability <- function(m, now = Sys.time()) {
  base <- if (isTRUE(p$fixed_prior)) NULL else p1_live_availability(season, m$current_week, now)
  ov <- p$overrides
  if (is.null(ov) || !length(ov) || (is.data.frame(ov) && !nrow(ov))) return(base)
  ov <- as.data.frame(ov)
  if (!all(c("player_id", "p_active") %in% names(ov))) fail(2L, "overrides need player_id and p_active")
  if (any(ov$p_active < 0 | ov$p_active > 1)) fail(2L, "p_active must be in [0, 1]")
  prior <- read_availability_prior()
  f <- function(gsis_id, status, position) {
    v <- if (is.null(base)) val_designation_prior(status, prior) else base(gsis_id, status, position)
    hit <- match(gsis_id, ov$player_id)
    v[!is.na(hit)] <- ov$p_active[hit[!is.na(hit)]]
    v
  }
  attr(f, "source") <- paste0(if (is.null(base)) prior$source else attr(base, "source"), "; UI what-if overrides for ",
                              nrow(ov), " player(s)")
  f
}
horizon_fun <- function(m) tryCatch(r3_horizon_sd_fun(r3_latest_adoption(season),
  clean_team_games(latest_live_file("schedules", season, Sys.time()), "REG"), season, m$current_week, Sys.time()),
  error = function(e) NULL)
versions <- function(m, avail = NULL, hz = NULL, kd = NULL, extra = list()) c(list(
  methodology = "valuation_v2", simulator = "s0_v0 (VL3, VL3b)", s0_params = "s0_params_v0", pod = "pod_baseline_v0",
  availability = if (is.null(avail)) "published designation prior (fixed)" else attr(avail, "source") %||% "P1 provider",
  horizon = attr(hz, "source") %||% "none (no adopted R3 cell)", kdst = kd$source %||% "none"), extra)
with_ids <- function(m, d) {
  if (is.null(d) || !is.data.frame(d)) return(d)
  for (n in intersect(c("row", "add_row"), names(d))) d[[sub("row$", "player_id", n)]] <- m$sim$players$player_id[d[[n]]]
  d
}
roster_rows <- function(m, t) { s <- m$state[[as.character(t)]]; c(s$rows, s$ir_rows) }

# ---- ops ----
run_op <- function(op) switch(op,
  noop = list(result = list(r_version = R.version.string, n_files = length(list.files("R", recursive = TRUE)))),
  health = list(result = list(health = clean_df(i3_health(season)))),
  context = {
    m <- load_m()
    pl <- m$sim$players
    owner <- rep(NA_integer_, nrow(pl)); ir <- rep(FALSE, nrow(pl))
    for (t in names(m$state)) { s <- m$state[[t]]; owner[s$rows] <- as.integer(t); owner[s$ir_rows] <- as.integer(t); ir[s$ir_rows] <- TRUE }
    g <- m$generic[match(pl$player_id, m$generic$player_id), ]
    players <- data.frame(row = seq_len(nrow(pl)), player_id = pl$player_id, espn_id = as.character(pl$espn_id),
                          player_name = pl$player_name, position = pl$position, nfl_team = pl$nfl_team,
                          team_id = owner, on_ir = ir, free_agent = seq_len(nrow(pl)) %in% m$fa_rows,
                          ros_points = round(m$sim$ros, 2), vor = g$vor, trade_value = g$trade_value,
                          overall_rank = g$overall_rank, position_rank = g$position_rank, stringsAsFactors = FALSE)
    st <- tryCatch(lg_state_from_snapshot(lg_latest_snapshot(season)), error = function(e) NULL)
    rules <- if (is.null(st)) list() else st$rules[c("teams", "regular_periods", "playoff_teams", "playoff_seeding_rule",
      "matchup_tie_rule", "top_half_bonus", "keeper_count", "faab", "acquisition_budget", "acquisition_limit",
      "waiver_order_reset", "trade_deadline_utc", "scoring_enhancement_type")]
    rules$trade_deadline_utc <- iso(rules$trade_deadline_utc)
    base_u <- do.call(rbind, lapply(names(m$base), function(t) data.frame(team_id = as.integer(t),
      U = m$base[[t]]$U, U_regular = m$base[[t]]$regular, U_playoffs = m$base[[t]]$playoffs)))
    list(result = list(
      inputs = m$inputs, season = season, current_week = m$current_week, weeks = m$weeks, my_team = m$my_team,
      policy = m$policy, teams = clean_df(dplyr::select(m$teams, "team_id", "team_abbrev", "team_name")),
      team_utility = base_u,
      league = list(slots = m$league$slots, bench = m$league$bench, roster_size = m$league$roster_size,
                    regular_season_weeks = m$league$regular_season_weeks, playoff_weeks = m$league$playoff_weeks),
      rules = rules, players = players,
      standings = if (is.null(st)) NULL else clean_df(dplyr::select(st$standings, "team_id", "wins", "losses", "ties",
        "points_for", "points_against", "games_back", "playoff_seed", "waiver_rank", "acquisitions", "trades")),
      schedule = if (is.null(st)) NULL else clean_df(st$schedule), status = if (is.null(st)) NULL else st$status,
      has_schedule = isTRUE(st$has_schedule),
      id_diagnostics = list(rows = if (is.data.frame(m$diagnostics)) nrow(m$diagnostics) else length(m$diagnostics))))
  },
  lineup = {
    m <- load_m(); team <- my_team(m)
    now <- if (!is.null(p$now)) as.POSIXct(p$now, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else Sys.time()
    if (is.na(now)) fail(2L, "now must look like 2026-10-18T14:00:00Z")
    tg <- clean_team_games(latest_live_file("schedules", season, now), "REG")
    av <- availability(m, now)
    adv <- lg_lineup_advice(m, team, tg, now, p_active_fun = av)
    list(result = list(team = team, week = adv$week, now = iso(now), lineup = clean_df(adv$lineup), plan = clean_df(adv$plan),
                       ev_recommended = adv$ev_recommended, ev_current = adv$ev_current, prior_source = adv$prior_source),
         inputs = m$inputs, model_versions = versions(m, av, extra = list(lineup = "D0 lineup helpers (lg_lineup_advice)")))
  },
  odds = {
    m <- load_m(); st <- league_state(); sims <- sims_for("odds", 10000L)
    av <- availability(m); hz <- horizon_fun(m); kd <- kdst_sim_params(m$league)
    wi <- NULL
    if (length(p$add) || length(p$drop)) wi <- list(team = my_team(m), add = m$sim$players$player_id[rows_of(m, p$add)],
                                                    drop = m$sim$players$player_id[rows_of(m, p$drop)])
    od <- sim_league_odds(m, st, sims = sims, what_if = wi, p_active_fun = av, horizon_sd_fun = hz, kdst = kd)
    base <- od$results$base
    bands <- NULL
    if (!isFALSE(p$bands)) bands <- do.call(rbind, lapply(list(c(0.5, 1), c(1.5, 1), c(1, 0.8), c(1, 1.2)), function(b) {
      r <- sim_league_odds(m, st, sims = 2000, sigma_scale = b[1], noise_scale = b[2], p_active_fun = av, horizon_sd_fun = hz, kdst = kd)$results$base$teams
      data.frame(team_id = r$team_id, p_playoffs = r$p_playoffs, p_title = r$p_title, sigma_scale = b[1], noise_scale = b[2])
    }))
    delta <- NULL
    if (!is.null(wi)) {
      alt <- od$results$what_if$teams
      j <- merge(base$teams, alt, by = "team_id", suffixes = c("", "_alt"))
      delta <- data.frame(team_id = j$team_id, d_playoffs = j$p_playoffs_alt - j$p_playoffs, d_title = j$p_title_alt - j$p_title)
    }
    list(result = list(teams = clean_df(base$teams), matchups = clean_df(base$matchups), leverage = base$leverage, bands = bands,
                       what_if = delta, label = od$label, current_period = od$current_period, sims = sims, seed = od$seed,
                       espn_playoff_pct_available = !all(is.na(od$espn_playoff_pct$espn_playoff_pct)),
                       sigma_L = od$sigma_L, elapsed_seconds = od$elapsed_seconds),
         inputs = m$inputs, model_versions = versions(m, av, hz, kd))
  },
  trade_eval = {
    m <- load_m(); ta <- team_of(m, p$team_a); tb <- team_of(m, p$team_b)
    ga <- rows_of(m, p$give_a); gb <- rows_of(m, p$give_b)
    if (!length(ga) && !length(gb)) fail(2L, "a trade needs at least one player")
    if (!all(ga %in% roster_rows(m, ta)) || !all(gb %in% roster_rows(m, tb))) fail(2L, "every player must be on the giving team's roster")
    horizon <- p$horizon %||% "full"
    tr <- tryCatch(lg_trade(m, ta, ga, tb, gb, m$la$eps, m$la$strong, horizon = horizon),
                   error = function(e) fail(4L, paste("the trade fails V2's checks:", conditionMessage(e))))
    out <- list(teams = clean_df(tr$teams), metrics = clean_df(tr$metrics), explanations = tr$explanations)
    if (!isFALSE(p$simulate)) {
      st <- league_state(); sims <- sims_for("trade_eval", 5000L)
      av <- availability(m); hz <- horizon_fun(m); kd <- kdst_sim_params(m$league)
      t1 <- list(team_a = ta, give_a = ga, team_b = tb, give_b = gb)
      if (!d2_trade_valid(m, t1)) fail(4L, "the trade fails V2's trade invariants (X-021)")
      d <- sim_trade_rescore(m, st, list(t1), sims = sims, p_active_fun = av, horizon_sd_fun = hz, kdst = kd)
      out$rescore <- clean_df(dplyr::bind_cols(dplyr::select(d, -dplyr::any_of("label")), trade_title_decomposition(d, "a"),
                                               nash = trade_nash(d)))
      out$sim_explanations <- trade_explain(d)
      out$label <- S0_LABEL; out$sims <- sims
      return(list(result = out, inputs = m$inputs, model_versions = versions(m, av, hz, kd, list(trade = "V2 lg_trade + D2 v3 (VL12)"))))
    }
    list(result = out, inputs = m$inputs, model_versions = versions(m, extra = list(trade = "V2 lg_trade")))
  },
  trade_search = {
    m <- load_m(); ta <- my_team(m); tb <- team_of(m, p$team_b)
    if (ta == tb) fail(2L, "pick a different partner team")
    horizon <- p$horizon %||% "full"; s <- m$la$search
    r <- lg_trade_search(m, ta, tb, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                         eps = m$la$eps, strong = m$la$strong, horizon = horizon)
    if (isTRUE(p$win_win)) r <- dplyr::filter(r, .data$win_win)
    k <- min(as.integer(p$k %||% 5L), 8L)
    out <- list(n_evaluated = nrow(r), candidates = NULL, rescore = NULL, excluded_invariants = 0L)
    if (nrow(r)) {
      rr <- r
      rr$a_ids <- vapply(r$a_rows, function(x) paste(m$sim$players$player_id[x], collapse = ";"), "")
      rr$b_ids <- vapply(r$b_rows, function(x) paste(m$sim$players$player_id[x], collapse = ";"), "")
      out$candidates <- clean_df(utils::head(dplyr::select(rr, -"a_rows", -"b_rows"), 25))
      if (!isFALSE(p$simulate)) {
        top <- utils::head(r, k)
        trades <- lapply(seq_len(nrow(top)), function(i) list(team_a = ta, give_a = top$a_rows[[i]], team_b = tb, give_b = top$b_rows[[i]]))
        ok <- vapply(trades, function(t) d2_trade_valid(m, t), TRUE)
        out$excluded_invariants <- sum(!ok)
        if (any(ok)) {
          st <- league_state(); sims <- sims_for("trade_search", 5000L)
          av <- availability(m); hz <- horizon_fun(m); kd <- kdst_sim_params(m$league)
          d <- sim_trade_rescore(m, st, trades[ok], sims = sims, p_active_fun = av, horizon_sd_fun = hz, kdst = kd)
          o <- dplyr::bind_cols(top[ok, c("a_gives", "b_gives")], d)
          out$rescore <- clean_df(dplyr::bind_cols(dplyr::select(o, -dplyr::any_of("label")), trade_title_decomposition(o, "a"), nash = trade_nash(o)))
          out$explanations <- trade_explain(o); out$frontier_trades <- trade_frontier(o)$trade
          out$label <- S0_LABEL; out$sims <- sims
          return(list(result = out, inputs = m$inputs, model_versions = versions(m, av, hz, kd, list(trade = "V2 search + D2 v3 (VL12)"))))
        }
      }
    }
    list(result = out, inputs = m$inputs, model_versions = versions(m, extra = list(trade = "V2 lg_trade_search")))
  },
  fa_board = {
    m <- load_m(); me <- my_team(m); st <- league_state(); sims <- sims_for("fa_board", 5000L)
    av <- availability(m); hz <- horizon_fun(m); kd <- kdst_sim_params(m$league)
    k <- min(as.integer(p$k %||% 8L), 12L); per <- min(as.integer(p$per_pos %||% 6L), 10L)
    sc <- d3_fa_screen(m, me, cand_per_pos = per)
    board <- sim_fa_rescore(m, st, me, sc, k = k, sims = sims, p_active_fun = av, horizon_sd_fun = hz, kdst = kd)
    board_out <- if (nrow(board)) {
      b <- board
      if ("new_rows" %in% names(b)) b$add_ids <- vapply(b$new_rows, function(x) paste(m$sim$players$player_id[x], collapse = ";"), "")
      if ("drop_rows" %in% names(b)) b$drop_ids <- vapply(b$drop_rows, function(x) paste(m$sim$players$player_id[x], collapse = ";"), "")
      clean_df(with_ids(m, dplyr::select(b, -dplyr::any_of(c("drop_rows", "new_rows")))))
    } else NULL
    list(result = list(screen = clean_df(with_ids(m, dplyr::select(sc, -dplyr::any_of(c("drop_rows", "new_rows"))))), board = board_out,
                       drop_advice = clean_df(with_ids(m, d3_drop_advice(m, me))), stream_view = clean_df(with_ids(m, d3_stream_view(m, me, p_active_fun = av))),
                       streaming_recommended = D3_STREAMING_RECOMMENDED, faab = isTRUE(st$rules$faab),
                       waiver_rank = st$standings$waiver_rank[st$standings$team_id == me] %||% NA, label = S0_LABEL, sims = sims),
         inputs = m$inputs, model_versions = versions(m, av, hz, kd, list(waivers = "D3 (VL9)")))
  },
  values3 = {
    m <- load_m(); team <- my_team(m); st <- league_state(); sims <- sims_for("values3", 5000L)
    av <- availability(m); hz <- horizon_fun(m); kd <- kdst_sim_params(m$league)
    vals <- v3_live_values(m, st, team, sims = sims, p_active_fun = av, horizon_sd_fun = hz, kdst = kd)
    risk <- v3_roster_risk(m, team, vals, p_active_fun = av)
    list(result = list(team = team, values = clean_df(with_ids(m, vals)), risk = lapply(risk, function(x) if (is.data.frame(x)) clean_df(with_ids(m, x)) else x),
                       label = S0_LABEL, sims = sims),
         inputs = m$inputs, model_versions = versions(m, av, hz, kd, list(values = "S3 values3 (VL7; X10b wins added)")))
  },
  research_target = {
    nm <- p$name
    if (is.null(nm) || !(nm %in% RESEARCH_TARGETS)) fail(2L, "target is not on the research allow-list")
    x <- tryCatch(targets::tar_read_raw(nm), error = function(e) fail(4L, paste("cannot read target:", conditionMessage(e))))
    flat <- if (is.data.frame(x)) list(table = clean_df(x)) else if (is.list(x))
      Filter(Negate(is.null), lapply(x, function(v) if (is.data.frame(v)) clean_df(v) else if (is.atomic(v) && length(v) <= 200) v else NULL))
      else list(value = if (is.atomic(x)) x else NULL)
    # sealed-season guard: refuse any table that carries 2026 rows (outcomes of 2026 are never displayed)
    sealed <- vapply(flat, function(v) is.data.frame(v) && any(c("season", "test_season") %in% names(v)) &&
                       any(unlist(v[intersect(c("season", "test_season"), names(v))]) %in% 2026L), TRUE)
    if (any(sealed)) fail(2L, "the object contains 2026 rows (sealed season); it is not shown")
    list(result = list(name = nm, content = flat))
  },
  fail(2L, paste("unknown op", op))
)

res <- tryCatch(run_op(op), error = function(e) fail(4L, conditionMessage(e)))
meta <- list(op = op, adapter_version = ADAPTER_VERSION, request = req, started_at_utc = iso(t0),
             elapsed_seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2),
             inputs = res$inputs, model_versions = res$model_versions,
             git_commit = tryCatch(base_system2("git", c("rev-parse", "HEAD"), stdout = TRUE)[1], error = function(e) NA_character_),
             exploratory = TRUE, ledgered = FALSE)
tmp <- paste0(out_dir, ".tmp", Sys.getpid())
unlink(tmp, recursive = TRUE)
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(res$result, file.path(tmp, "result.json"), auto_unbox = TRUE, digits = 8, na = "null", null = "null",
                     dataframe = "rows", POSIXt = "ISO8601")
jsonlite::write_json(meta, file.path(tmp, "meta.json"), auto_unbox = TRUE, digits = 8, na = "null", null = "null", pretty = TRUE)
unlink(out_dir, recursive = TRUE)
if (!file.rename(tmp, out_dir)) fail(4L, "could not move the result into place")
cat("UI_ADAPTER_OK\n")
