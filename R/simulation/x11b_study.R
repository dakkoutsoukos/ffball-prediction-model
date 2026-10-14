# X11b (VL12a): can trade-ranking instability be reduced by simulation design? Outcome-free design
# study. Per-simulation team-A outcomes for the base and each candidate trade come from one large
# run; the first half is the reference, the second the evaluation pool. Not a production method.

#' Per-simulation outcomes of team A (playoff and title indicators, wins) for the base configuration
#' and each candidate trade, on the live S0 engine (same set-up as sim_trade_rescore()).
#' Returns list(playoffs, title, wins), each a [1 + K, sims] matrix (row 1 = base).
x11b_persim <- function(m, state, trades, sims = 20000L, chunk = 1000L, seed = 20261015L, p_active_fun = NULL, kdst = NULL,
                        table = read_pod_table(), params = read_s0_params(), prior = read_availability_prior()) {
  weeks <- seq(m$current_week, max(m$league$playoff_weeks))
  pid <- m$sim$players$player_id
  team_rows <- lapply(m$state, function(s) s$rows)
  resolved <- lapply(trades, function(t) {
    ta <- lg_find_team(m, t$team_a)
    tb <- lg_find_team(m, t$team_b)
    g <- lg_validate_trade(m, ta, t$give_a, tb, t$give_b)
    list(team_a = ta, team_b = tb, tr = lg_apply_trade(m, ta, g$a, tb, g$b))
  })
  ids <- unique(c(pid[unlist(team_rows)], unlist(lapply(resolved, function(r) pid[c(r$tr$a$rows, r$tr$b$rows)]))))
  pos <- m$sim$players$position[match(ids, pid)]
  uni <- sim_universe(m$input_data$weekly, ids, pos, weeks, m$current_week, prior, p_active_fun)
  uni$kdst <- kdst
  to_uni <- function(rows) {
    r <- match(pid[rows], ids)
    r[!is.na(r)]
  }
  base <- lapply(team_rows, to_uni)
  configs <- c(list(base = base), lapply(resolved, function(r) {
    cfg <- base
    cfg[[as.character(r$team_a)]] <- to_uni(r$tr$a$rows)
    cfg[[as.character(r$team_b)]] <- to_uni(r$tr$b$rows)
    cfg
  }))
  fa <- lg_fa_levels(m, m$fa_rows)
  stream <- lapply(weeks, function(w) {
    x <- fa[fa$week == w, ]
    stats::setNames(as.list(x$W), x$position)
  }) |> rlang::set_names(as.character(weeks))
  scores <- sim_scores(uni, configs, val_lineup_spec(m$league), stream, table, params$sigma_L, sims, chunk, seed)
  cp <- state$status$current_matchup_period
  ta <- as.integer(resolved[[1]]$team_a)
  out <- lapply(scores, function(sc) {
    res <- sim_resolve(sc, state, cp)
    i <- match(ta, res$teams)
    rbind(playoffs = as.numeric(res$seed[i, ] <= res$playoff_teams), title = as.numeric(res$champion == ta), wins = res$wins[i, ])
  })
  list(playoffs = do.call(rbind, lapply(out, function(x) x["playoffs", ])),
       title = do.call(rbind, lapply(out, function(x) x["title", ])),
       wins = do.call(rbind, lapply(out, function(x) x["wins", ])))
}

#' Paired per-simulation gains of each candidate over the base: [K, sims].
x11b_gains <- function(ind) sweep(ind[-1, , drop = FALSE], 2, ind[1, ])

#' Choice of a fixed-budget design on simulation columns `cols`: the arg-max mean gain.
x11b_fixed <- function(g, cols) which.max(rowMeans(g[, cols, drop = FALSE]))

#' Sequential racing on columns `cols` in batches; drops candidates whose paired mean difference from
#' the current leader is below 0 by more than z paired SEs. Returns the choice and candidate-simulations used.
x11b_race <- function(g, cols, batch = 1000L, z = 2.5) {
  alive <- seq_len(nrow(g))
  used <- 0
  n <- 0L
  for (b in seq(batch, length(cols), by = batch)) {
    n <- b
    used <- used + length(alive) * batch
    x <- g[alive, cols[seq_len(n)], drop = FALSE]
    lead <- which.max(rowMeans(x))
    d <- sweep(x, 2, x[lead, ])
    se <- apply(d, 1, stats::sd) / sqrt(n)
    mu <- rowMeans(d)
    keep <- mu + z * se >= 0 | seq_along(alive) == lead
    alive <- alive[keep]
    if (length(alive) == 1) break
  }
  list(choice = alive[which.max(rowMeans(g[alive, cols[seq_len(n)], drop = FALSE]))], used = used)
}

#' Indifference set at a fixed budget: candidates not significantly worse than the leader (paired, z).
x11b_set <- function(g, cols, z = 2.0) {
  x <- g[, cols, drop = FALSE]
  lead <- which.max(rowMeans(x))
  d <- sweep(x, 2, x[lead, ])
  se <- apply(d, 1, stats::sd) / sqrt(length(cols))
  which(rowMeans(d) + z * se >= 0)
}

#' VL12a measures for one list and one outcome (indicator matrix incl. base row).
x11b_evaluate <- function(ind, n_ref = 10000L, d0 = 2000L) {
  g <- x11b_gains(ind)
  K <- nrow(g)
  S <- ncol(g)
  ref_cols <- seq_len(n_ref)
  ev <- seq(n_ref + 1L, S)
  ref <- rowMeans(g[, ref_cols, drop = FALSE])
  best <- which.max(ref)
  regret <- function(k) ref[best] - ref[k]
  blocks <- function(size) split(ev, ceiling(seq_along(ev) / size))[seq_len(floor(length(ev) / size))]
  fixed <- function(size) {
    ch <- vapply(blocks(size), function(c) x11b_fixed(g, c), 1L)
    c(regret = mean(regret(ch)), agree = mean(ch == best), cost = K * size)
  }
  r <- x11b_race(g, ev)
  sets <- lapply(blocks(d0), function(c) x11b_set(g, c))
  top2 <- sort(ref, decreasing = TRUE)[1:2]
  dd <- g[order(-ref)[1], ev[seq_len(d0)]] - g[order(-ref)[2], ev[seq_len(d0)]]
  tibble::tibble(
    candidates = K, ref_best_gain = ref[best],
    d0_regret = fixed(d0)[["regret"]], d0_agree = fixed(d0)[["agree"]], d0_cost = K * d0,
    d1_5k_regret = fixed(5000L)[["regret"]], d1_5k_agree = fixed(5000L)[["agree"]],
    d1_10k_regret = fixed(10000L)[["regret"]], d1_10k_agree = fixed(10000L)[["agree"]],
    d2_regret = regret(r$choice), d2_agree = r$choice == best, d2_cost = r$used,
    d3_size = mean(lengths(sets)), d3_covers = mean(vapply(sets, function(s) best %in% s, TRUE)),
    near_tie = (top2[1] - top2[2]) < stats::sd(dd) / sqrt(d0))
}
