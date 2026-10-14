# D4 draft assistant (master plan D4; pre-registration VL10): projections-only under the O2/O8 defaults
# (no ADP, no league draft history). New functions (prefix d4_) on top of V1's simulation; V1 unchanged.
# The opponent model is an assumption fixed in VL10, not an estimate. K and D/ST take the last two rounds
# and are outside the skill draft simulated here.

D4_TAU <- 3
D4_HERD <- 1.5
D4_CAPS <- c(QB = 2L, TE = 2L)
D4_CANDS_PER_POS <- 4L
D4_ROLLOUTS <- 100L
D4_SIMS <- 100L

#' Snake order: the team on the clock at each overall pick.
d4_snake <- function(teams, rounds) {
  unlist(lapply(seq_len(rounds), function(r) if (r %% 2 == 1) seq_len(teams) else rev(seq_len(teams))))
}

#' Draft pool: V1's simulation (100 availability draws), the league's lineup spec, the proportional pool's
#' streaming levels (all players are free agents at the draft), and VOR with its overall rank.
d4_pool <- function(weekly, league, current_week, sims = D4_SIMS, seed = 20261007, cand_per_pos = 6) {
  weekly <- dplyr::filter(weekly, .data$week %in% val_horizon_weeks(league, current_week))
  sim <- val_sim_setup(weekly, sims, seed)
  spec <- val_lineup_spec(league)
  vals <- val_value_league(weekly, league, current_week, list(sims = sims, seed = seed, candidates_per_position = cand_per_pos,
                                                              max_iterations = 1, pool = "proportional"),
                           with_mru = FALSE, sim = sim)
  k <- match(sim$players$player_id, vals$values$player_id)
  vor <- dplyr::coalesce(vals$values$vor[k], 0)
  list(sim = sim, spec = spec, stream = vals$league_sim$stream, vor = vor, rank = rank(-vor, ties.method = "first"),
       pos = sim$players$position, rows = which(sim$players$position %in% spec$positions), league = league,
       rounds = val_roster_size(league))
}

#' Unfilled starting slots of a roster (V1 slot order, most specific first): their eligible positions.
d4_unfilled <- function(roster_pos, spec) {
  left <- roster_pos
  out <- list()
  for (s in spec$slots) for (u in seq_len(s$count)) {
    k <- which(left %in% s$eligible)
    if (length(k)) left <- left[-k[1]] else out[[length(out) + 1]] <- s$eligible
  }
  out
}

#' Positions an opponent may take now: caps before the last three rounds, and only unfilled starting
#' positions once its remaining picks equal its unfilled starting slots.
d4_allowed <- function(roster_pos, picks_left, spec, late, caps = D4_CAPS) {
  allowed <- spec$positions
  if (!late) for (p in intersect(names(caps), allowed)) if (sum(roster_pos == p) >= caps[[p]]) allowed <- setdiff(allowed, p)
  un <- d4_unfilled(roster_pos, spec)
  if (length(un) && picks_left <= length(un)) {
    need <- unique(unlist(un))
    allowed <- if (length(intersect(allowed, need))) intersect(allowed, need) else need
  }
  allowed
}

#' Opponent pick by the VL10 model, drawn by inverse CDF from the uniform `u` (so two policies can share
#' the opponents' randomness): weights exp(-(rank - best rank) / tau), herding x `herd` after two picks
#' at one position.
d4_opponent_pick <- function(avail, pool, allowed, recent, u, tau = D4_TAU, herd = D4_HERD) {
  cand <- avail[pool$pos[avail] %in% allowed]
  if (!length(cand)) cand <- avail
  cand <- cand[order(pool$rank[cand])]
  w <- exp(-(pool$rank[cand] - pool$rank[cand[1]]) / tau)
  if (length(recent) >= 2 && !is.na(recent[2]) && recent[1] == recent[2]) {
    h <- pool$pos[cand] == recent[1]
    w[h] <- w[h] * herd
  }
  cand[min(length(cand), which(cumsum(w) / sum(w) >= u)[1])]
}

#' The need-aware VOR rule (VOR-greedy policy and the owner's later picks inside rollouts): the best VOR
#' among positions of unfilled starting slots while any are unfilled, otherwise the best VOR.
d4_owner_rule <- function(avail, pool, roster_pos) {
  un <- d4_unfilled(roster_pos, pool$spec)
  cand <- if (length(un)) avail[pool$pos[avail] %in% unique(unlist(un))] else avail
  if (!length(cand)) cand <- avail
  cand[order(-pool$vor[cand], cand)][1]
}

#' Expected season lineup points U of a roster (V1's evaluator with the proportional pool's streaming).
d4_utility <- function(rows, pool) val_lineup_value(val_team_tops(rows, pool$sim, pool$spec), pool$stream, pool$spec, pool$sim$sims)

#' Play the draft from overall pick `from` to the end. `owner_pick(avail, roster_pos, p)` chooses the
#' owner's picks; opponents follow the model with uniforms `u[p]`. Returns rosters and the pick log.
d4_play <- function(rosters, taken, from, order, owner, pool, u, owner_pick, recent = character()) {
  n <- length(order)
  log <- integer(n)
  if (from > n) return(list(rosters = rosters, taken = taken, log = log))
  late_from <- n - 3L * max(order) + 1L
  for (p in seq(from, n)) {
    t <- order[p]
    avail <- pool$rows[!pool$rows %in% taken]
    if (!length(avail)) break
    rp <- pool$pos[rosters[[t]]]
    x <- if (t == owner) owner_pick(avail, rp, p) else
      d4_opponent_pick(avail, pool, d4_allowed(rp, sum(order[p:n] == t), pool$spec, p >= late_from), recent, u[p])
    rosters[[t]] <- c(rosters[[t]], x)
    taken <- c(taken, x)
    log[p] <- x
    recent <- c(pool$pos[x], recent)[1:2]
  }
  list(rosters = rosters, taken = taken, log = log)
}

#' Recommendation at the owner's pick `p` (VL10): for the 4 best available per position by VOR, `rollouts`
#' completions of the draft (common uniforms across candidates); mean U of the owner's final roster with
#' its SE, and each candidate's survival to the owner's next pick from the other candidates' rollouts.
d4_recommend <- function(rosters, taken, p, order, owner, pool, recent = character(), rollouts = D4_ROLLOUTS,
                         per_pos = D4_CANDS_PER_POS, seed = 1L) {
  avail <- pool$rows[!pool$rows %in% taken]
  cands <- unlist(lapply(pool$spec$positions, function(q) {
    x <- avail[pool$pos[avail] == q]
    utils::head(x[order(-pool$vor[x], x)], per_pos)
  }))
  n <- length(order)
  nxt <- which(order == owner & seq_len(n) > p)
  nxt <- if (length(nxt)) nxt[1] else NA_integer_
  U <- withr::with_seed(seed, matrix(stats::runif(rollouts * n), rollouts, n))
  rule <- function(a, rp, q) d4_owner_rule(a, pool, rp)
  res <- lapply(cands, function(c) {
    r0 <- rosters
    r0[[owner]] <- c(r0[[owner]], c)
    rec <- c(pool$pos[c], recent)[1:2]
    out <- lapply(seq_len(rollouts), function(j) {
      g <- d4_play(r0, c(taken, c), p + 1L, order, owner, pool, U[j, ], rule, rec)
      gone <- if (is.na(nxt)) integer() else g$log[seq_len(nxt - 1L)[seq_len(nxt - 1L) > p]]
      list(u = d4_utility(g$rosters[[owner]], pool), gone = gone)
    })
    list(u = vapply(out, `[[`, 0, "u"), gone = lapply(out, `[[`, "gone"))
  })
  surv <- vapply(seq_along(cands), function(i) {
    other <- unlist(lapply(res[-i], function(r) vapply(r$gone, function(g) !cands[i] %in% g, TRUE)))
    if (!length(other)) NA_real_ else mean(other)
  }, 0)
  tibble::tibble(row = cands, position = pool$pos[cands], vor = pool$vor[cands],
                 mean_u = vapply(res, function(r) mean(r$u), 0),
                 se_u = vapply(res, function(r) stats::sd(r$u) / sqrt(length(r$u)), 0),
                 survival_next = surv) |>
    dplyr::arrange(dplyr::desc(.data$mean_u), .data$row)
}

#' A complete mock draft: the owner sits in `seat` and follows `policy` ("assistant" or "vor");
#' opponents follow the model with uniforms drawn from `seed` (identical across policies).
d4_mock_draft <- function(pool, seat, policy = c("assistant", "vor"), seed = 1L, rollouts = D4_ROLLOUTS,
                          per_pos = D4_CANDS_PER_POS) {
  policy <- match.arg(policy)
  teams <- pool$league$teams
  order <- d4_snake(teams, pool$rounds)
  u <- withr::with_seed(seed, stats::runif(length(order)))
  rosters <- replicate(teams, integer(), simplify = FALSE)
  taken <- integer()
  recent <- character()
  for (p in seq_along(order)) {
    t <- order[p]
    avail <- pool$rows[!pool$rows %in% taken]
    rp <- pool$pos[rosters[[t]]]
    x <- if (t != seat) {
      d4_opponent_pick(avail, pool, d4_allowed(rp, sum(order[p:length(order)] == t), pool$spec,
                                               p >= length(order) - 3L * teams + 1L), recent, u[p])
    } else if (policy == "vor") {
      d4_owner_rule(avail, pool, rp)
    } else {
      d4_recommend(rosters, taken, p, order, seat, pool, recent, rollouts, per_pos, seed = seed * 1000L + p)$row[1]
    }
    rosters[[t]] <- c(rosters[[t]], x)
    taken <- c(taken, x)
    recent <- c(pool$pos[x], recent)[1:2]
  }
  list(rosters = rosters, owner_u = d4_utility(rosters[[seat]], pool))
}

#' Week-0 E[wins] and P(playoffs) of every team for completed rosters: S0 engine draws (S0's sigma_L) over
#' the pool's regular-season weeks; the schedule is `schedule` (one 2-column matrix of seat pairs per week)
#' or a round robin; the top `playoff_teams` by wins (ties half) then points, as S2's resolver for a
#' format without divisions and with the points tiebreak. Mock-draft evidence only.
d4_week0_odds <- function(rosters, pool, weekly, table, sigma, playoff_teams = 4L, sims = 1000L, seed = 20261013L,
                          prior = list(p_active = c(QUESTIONABLE = 0.71, DOUBTFUL = 0.07, OUT = 0), default = 1),
                          schedule = NULL) {
  league <- pool$league
  weeks <- intersect(pool$sim$weeks, seq(league$regular_season_weeks[1], league$regular_season_weeks[2]))
  ids <- pool$sim$players$player_id[unique(unlist(rosters))]
  pos <- pool$sim$players$position[match(ids, pool$sim$players$player_id)]
  uni <- sim_universe(weekly, ids, pos, weeks, min(weeks), prior)
  cfg <- lapply(rosters, function(r) match(pool$sim$players$player_id[r], ids)) |> rlang::set_names(as.character(seq_along(rosters)))
  wt <- tibble::tibble(position = rep(pool$spec$positions, each = length(weeks)), wi = rep(seq_along(weeks), length(pool$spec$positions)))
  stream <- lapply(seq_along(weeks), function(j) {
    stats::setNames(as.list(vapply(pool$spec$positions, function(q) {
      s <- pool$stream[[q]]
      if (is.null(s)) 0 else s[match(weeks[j], pool$sim$weeks)]
    }, 0)), pool$spec$positions)
  }) |> rlang::set_names(as.character(weeks))
  sc <- sim_scores(uni, list(base = cfg), pool$spec, stream, table, sigma, sims, chunk = 500L, seed = seed)$base
  n <- length(rosters)
  W <- length(weeks)
  sched <- schedule %||% lapply(seq_len(W), function(w) {           # circle-method round robin, repeated
    k <- (w - 1) %% (n - 1)
    ring <- c(1L, ((seq_len(n - 1) - 1 + k) %% (n - 1)) + 2L)
    cbind(ring[seq_len(n / 2)], rev(ring)[seq_len(n / 2)])
  })
  if (length(sched) != W) cli::cli_abort("The schedule must have one matrix per regular-season week ({W}).")
  wins <- matrix(0, n, sims)
  pts <- matrix(0, n, sims)
  for (w in seq_len(W)) {
    s <- sc[, w, ]
    pts <- pts + s
    for (g in seq_len(nrow(sched[[w]]))) {
      a <- sched[[w]][g, 1]
      b <- sched[[w]][g, 2]
      wins[a, ] <- wins[a, ] + (s[a, ] > s[b, ]) + 0.5 * (s[a, ] == s[b, ])
      wins[b, ] <- wins[b, ] + (s[b, ] > s[a, ]) + 0.5 * (s[a, ] == s[b, ])
    }
  }
  key <- wins + pts / (max(pts) + 1)
  rk <- apply(-key, 2, rank, ties.method = "first")
  tibble::tibble(team = seq_len(n), e_wins = rowMeans(wins), p_playoffs = rowMeans(rk <= playoff_teams))
}
