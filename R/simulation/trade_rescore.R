# S2-thin / D2-thin (master plan section 6 thin slice): trade re-scoring on the S0 engine ---------
# Re-scores candidate trades by BOTH teams' change in E[wins], P(playoffs) and P(title), on the S0
# engine (P0 noise, S0 sigma_L, decision-time lineups) with common random numbers across every
# configuration. Shadow and unvalidated, like S0. The partner-lens frontier pairs the owner's
# simulated gain with the partner's generic-value view (V2's generic VOR, the lens a typical manager
# uses). Calibrated components replace S0's behind the same interface when P2/P4/P5 pass.

#' Core: deltas for trades given as post-trade universe rows of the two teams.
#' `trades`: list of list(team_a, rows_a, team_b, rows_b) with team ids as in `base_config` names.
sim_trade_deltas <- function(uni, base_config, trades, state, spec, stream, table, sigma, sims = 10000L,
                             chunk = 1000L, seed = 20261013L) {
  configs <- c(list(base = base_config), lapply(trades, function(tr) {
    cfg <- base_config
    cfg[[as.character(tr$team_a)]] <- tr$rows_a
    cfg[[as.character(tr$team_b)]] <- tr$rows_b
    cfg
  }))
  names(configs) <- c("base", paste0("trade", seq_along(trades)))
  scores <- sim_scores(uni, configs, spec, stream, table, sigma, sims, chunk, seed)
  cp <- state$status$current_matchup_period
  summ <- lapply(scores, function(sc) sim_summarise(sim_resolve(sc, state, cp))$teams)
  b <- summ$base
  purrr::map(seq_along(trades), function(k) {
    tr <- trades[[k]]
    a <- summ[[k + 1]]
    side <- function(team) {
      i <- match(team, a$team_id)
      j <- match(team, b$team_id)
      c(d_wins = a$e_wins[i] - b$e_wins[j], d_playoffs = a$p_playoffs[i] - b$p_playoffs[j],
        d_title = a$p_title[i] - b$p_title[j])
    }
    sa <- side(as.integer(tr$team_a))
    sb <- side(as.integer(tr$team_b))
    tibble::tibble(trade = k, team_a = tr$team_a, team_b = tr$team_b,
                   d_wins_a = sa[["d_wins"]], d_playoffs_a = sa[["d_playoffs"]], d_title_a = sa[["d_title"]],
                   d_wins_b = sb[["d_wins"]], d_playoffs_b = sb[["d_playoffs"]], d_title_b = sb[["d_title"]],
                   sum_p_playoffs = sum(a$p_playoffs), sum_p_title = sum(a$p_title))
  }) |> purrr::list_rbind()
}

#' Owner's league wrapper: V2 trades (each list(team_a, give_a, team_b, give_b) of names or ids) are
#' resolved with V2's lg_apply_trade() (forced drops, adds), then re-scored on the S0 engine. Adds
#' V2's utility deltas and the partner lens (the partner's generic VOR net).
sim_trade_rescore <- function(m, state, trades, table = read_pod_table(), params = read_s0_params(),
                              prior = read_availability_prior(), sims = 10000L, chunk = 1000L, seed = 20261013L,
                              p_active_fun = NULL) {
  weeks <- seq(m$current_week, max(m$league$playoff_weeks))
  pid <- m$sim$players$player_id
  team_rows <- lapply(m$state, function(s) s$rows)
  resolved <- lapply(trades, function(t) {
    ta <- lg_find_team(m, t$team_a)
    tb <- lg_find_team(m, t$team_b)
    g <- lg_validate_trade(m, ta, t$give_a, tb, t$give_b)
    tr <- lg_apply_trade(m, ta, g$a, tb, g$b)
    lg_check_invariants(m, tr, ta, g$a, tb, g$b)
    v2 <- lg_trade(m, ta, t$give_a, tb, t$give_b, explain = FALSE)
    list(team_a = ta, team_b = tb, tr = tr, v2 = v2$metrics, generic_b = v2$teams$generic_vor_gets[2] - v2$teams$generic_vor_gives[2])
  })
  ids <- unique(c(pid[unlist(team_rows)], unlist(lapply(resolved, function(r) pid[c(r$tr$a$rows, r$tr$b$rows)]))))
  pos <- m$sim$players$position[match(ids, pid)]
  uni <- sim_universe(m$input_data$weekly, ids, pos, weeks, m$current_week, prior, p_active_fun)
  to_uni <- function(rows) {
    r <- match(pid[rows], ids)
    r[!is.na(r)]
  }
  base <- lapply(team_rows, to_uni)
  tr_list <- lapply(resolved, function(r) list(team_a = r$team_a, rows_a = to_uni(r$tr$a$rows),
                                               team_b = r$team_b, rows_b = to_uni(r$tr$b$rows)))
  fa <- lg_fa_levels(m, m$fa_rows)
  stream <- lapply(weeks, function(w) {
    x <- fa[fa$week == w, ]
    stats::setNames(as.list(x$W), x$position)
  }) |> rlang::set_names(as.character(weeks))
  d <- sim_trade_deltas(uni, base, tr_list, state, val_lineup_spec(m$league), stream, table, params$sigma_L,
                        sims, chunk, seed)
  d$v2_delta_a <- vapply(resolved, function(r) r$v2$delta_a, 0)
  d$v2_delta_b <- vapply(resolved, function(r) r$v2$delta_b, 0)
  d$partner_lens_b <- vapply(resolved, function(r) r$generic_b, 0)
  d$label <- S0_LABEL
  d
}

#' The partner-lens frontier: trades not dominated in (own simulated gain, partner-lens gain).
trade_frontier <- function(d, own = "d_title_a", partner = "partner_lens_b") {
  x <- d[[own]]
  y <- d[[partner]]
  keep <- vapply(seq_along(x), function(i) !any(x >= x[i] & y >= y[i] & (x > x[i] | y > y[i])), TRUE)
  d[keep, ][order(-d[[own]][keep]), ]
}
