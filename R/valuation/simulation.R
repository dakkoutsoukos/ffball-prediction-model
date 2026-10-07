# Valuation: generic league simulation ---------------------------------------------------
# A symmetric generic league is "re-drafted" from the current player pool to find
# which players are rostered (and so which are freely available on waivers),
# and to provide generic team rosters for roster-utility and package analysis.
#
#   U(roster) = expected ROS starting-lineup points of a team. Each week the team
#               starts its best eligible players; any slot can instead be
#               STREAMED at the waiver level W_p(t) (best undrafted player at the
#               position that week, by expectation). Weekly availability is Monte
#               Carlo: a player is active with probability A_i(t) and then scores
#               his if-active level; the current week is deterministic.
#   Draft      snake order; each pick maximizes Delta U for the picking team
#               (candidates: the best few available per position by ROS points).
#   Fixed point W depends on who is drafted: initial W from proportional bench
#               shares -> draft -> W from the undrafted -> redraft, until the
#               drafted set repeats (or max_iterations).
# Lineups are evaluated with a slot greedy (most specific slots first) that is
# exact for laminar slot sets (val_slots_laminar()).

#' Pre-draw Monte Carlo points for every pool player. `weekly` needs
#' player_id, position, week, E (expected), A (P(active)), lvl (if active).
#' Common random numbers: draws follow sorted player ids, so the same player
#' gets the same draws whatever the league settings.
val_sim_setup <- function(weekly, sims = 200, seed = 20261007) {
  pl <- dplyr::distinct(weekly, .data$player_id, .data$position) |> dplyr::arrange(.data$player_id)
  assert_unique_key(pl, "player_id", "simulation pool")
  weeks <- sort(unique(weekly$week))
  n <- nrow(pl)
  W <- length(weeks)
  fill <- function(col) {
    m <- matrix(0, n, W)
    m[cbind(match(weekly$player_id, pl$player_id), match(weekly$week, weeks))] <- weekly[[col]]
    m
  }
  E <- fill("E")
  A <- fill("A")
  L <- fill("lvl")
  withr::with_seed(seed, {
    u <- array(stats::runif(n * W * sims), c(n, W, sims))
  })
  P <- matrix(0, n, W * sims)
  for (s in seq_len(sims)) P[, (s - 1) * W + seq_len(W)] <- (u[, , s] < A) * L
  list(players = pl, weeks = weeks, sims = sims, seed = seed, E = E, P = P,
       colweek = rep(seq_len(W), times = sims), ros = rowSums(E))
}

#' Insert a row of values into a K x C matrix of column-wise sorted top-K values.
val_topk_insert <- function(Tm, v) {
  for (k in seq_len(nrow(Tm))) {
    hi <- pmax(Tm[k, ], v)
    v <- pmin(Tm[k, ], v)
    Tm[k, ] <- hi
  }
  Tm
}

#' Lineup structure for the evaluator: slots in order of increasing
#' eligibility, and K_p = the most players of a position that can start.
val_lineup_spec <- function(league) {
  if (!val_slots_laminar(league)) cli::cli_abort("The roster simulation needs laminar slot eligibility.")
  sl <- unname(league$slots[order(vapply(league$slots, function(s) length(s$eligible), 0L))])
  sl <- Filter(function(s) s$count > 0, sl)
  K <- vapply(VAL_POSITIONS, function(p) sum(vapply(sl, function(s) if (p %in% s$eligible) s$count else 0L, 0L)), 0)
  list(slots = sl, K = K[K > 0], positions = names(K)[K > 0])
}

#' Top-K matrices of a set of pool rows, by position.
val_team_tops <- function(rows, sim, spec) {
  C <- ncol(sim$P)
  rlang::set_names(lapply(spec$positions, function(p) {
    Tm <- matrix(-Inf, spec$K[[p]], C)
    for (i in rows[sim$players$position[rows] == p]) Tm <- val_topk_insert(Tm, sim$P[i, ])
    Tm
  }), spec$positions)
}

#' Expected ROS lineup points from top-K matrices and streamer vectors.
val_lineup_value <- function(tops, stream, spec, sims) {
  C <- length(stream[[1]])
  idx <- seq_len(C)
  ptr <- lapply(tops, function(m) rep(1L, C))
  total <- numeric(C)
  for (s in spec$slots) {
    el <- intersect(s$eligible, spec$positions)
    for (u in seq_len(s$count)) {
      best <- rep(-Inf, C)
      who <- integer(C)
      use <- logical(C)
      for (j in seq_along(el)) {
        p <- el[j]
        r <- ptr[[p]]
        head <- rep(-Inf, C)
        ok <- r <= nrow(tops[[p]])
        head[ok] <- tops[[p]][cbind(r[ok], idx[ok])]
        val <- pmax(head, stream[[p]])
        b <- val > best
        best[b] <- val[b]
        who[b] <- j
        use[b] <- head[b] >= stream[[p]][b]
      }
      total <- total + best
      for (j in seq_along(el)) {
        adv <- who == j & use
        ptr[[el[j]]][adv] <- ptr[[el[j]]][adv] + 1L
      }
    }
  }
  sum(total) / sims
}

#' Streamer vectors (one value per Monte Carlo column) from a W table.
val_stream_vectors <- function(Wtab, sim, positions) {
  rlang::set_names(lapply(positions, function(p) {
    w <- Wtab$W[match(paste(p, sim$weeks), paste(Wtab$position, Wtab$week))]
    w[is.na(w)] <- 0
    w[sim$colweek]
  }), positions)
}

#' Waiver level W_p(t): best expected points among players not in `rostered`.
val_waiver_levels <- function(sim, rostered_rows) {
  free <- setdiff(seq_len(nrow(sim$players)), rostered_rows)
  tidyr::expand_grid(position = VAL_POSITIONS, wi = seq_along(sim$weeks)) |>
    dplyr::mutate(week = sim$weeks[.data$wi], W = purrr::map2_dbl(.data$position, .data$wi, function(p, wi) {
      r <- free[sim$players$position[free] == p]
      if (length(r)) max(0, max(sim$E[r, wi])) else 0
    })) |>
    dplyr::select(-"wi")
}

#' Proportional rostered pool (initial fixed-point guess and sensitivity
#' rule): each position's share of league starters (weekly allocation over the
#' horizon) times the league roster size, filled by ROS points.
val_proportional_pool <- function(sim, league) {
  hall <- val_hall_table(league)
  starts <- vapply(seq_along(sim$weeks), function(wi) {
    st <- val_allocate(sim$E[, wi], sim$players$position, hall)
    vapply(VAL_POSITIONS, function(p) sum(st & sim$players$position == p), 0)
  }, numeric(length(VAL_POSITIONS)))
  share <- rowMeans(starts) / sum(rowMeans(starts))
  n_ros <- round(share * league$teams * val_roster_size(league))
  rows <- unlist(lapply(VAL_POSITIONS, function(p) {
    r <- which(sim$players$position == p)
    r[order(-sim$ros[r])][seq_len(min(length(r), n_ros[[p]]))]
  }))
  list(rows = rows, counts = n_ros, starter_share = share)
}

#' One snake draft given streamer levels. Returns team rosters (pool rows).
val_draft <- function(sim, league, stream, spec, cand_per_pos = 6) {
  teams <- league$teams
  R <- val_roster_size(league)
  rosters <- vector("list", teams)
  tops <- lapply(seq_len(teams), function(k) val_team_tops(integer(), sim, spec))
  u <- rep(val_lineup_value(tops[[1]], stream, spec, sim$sims), teams)
  avail <- rep(TRUE, nrow(sim$players))
  order_k <- unlist(lapply(seq_len(R), function(r) if (r %% 2 == 1) seq_len(teams) else rev(seq_len(teams))))
  picks <- vector("list", length(order_k))
  pos <- sim$players$position
  for (pk in seq_along(order_k)) {
    k <- order_k[pk]
    cands <- unlist(lapply(spec$positions, function(p) {
      r <- which(avail & pos == p)
      r[order(-sim$ros[r], sim$players$player_id[r])][seq_len(min(length(r), cand_per_pos))]
    }))
    if (!length(cands)) break
    gains <- vapply(cands, function(i) {
      tp <- tops[[k]]
      tp[[pos[i]]] <- val_topk_insert(tp[[pos[i]]], sim$P[i, ])
      val_lineup_value(tp, stream, spec, sim$sims) - u[k]
    }, 0)
    best <- cands[order(-round(gains, 8), -sim$ros[cands], sim$players$player_id[cands])][1]
    tops[[k]][[pos[best]]] <- val_topk_insert(tops[[k]][[pos[best]]], sim$P[best, ])
    u[k] <- u[k] + gains[match(best, cands)]
    rosters[[k]] <- c(rosters[[k]], best)
    avail[best] <- FALSE
    picks[[pk]] <- tibble::tibble(pick = pk, round = (pk - 1) %/% teams + 1, team = k, row = best,
                                  gain = gains[match(best, cands)])
  }
  list(rosters = rosters, utility = u, picks = purrr::list_rbind(picks))
}

#' Generic league. pool = "proportional" (production, VE3): the rostered pool
#' (and so the waiver level W) is the proportional pool; one snake draft with
#' streaming at that W builds the generic teams used for roster utility and
#' packages. pool = "simulation" (VE2, sensitivity): fixed-point iteration
#' between W and the drafted set, which then also defines the rostered pool.
val_league_sim <- function(sim, league, cand_per_pos = 6, max_iterations = 6,
                           pool = c("proportional", "simulation")) {
  pool <- match.arg(pool)
  spec <- val_lineup_spec(league)
  init <- val_proportional_pool(sim, league)
  Wtab <- val_waiver_levels(sim, init$rows)
  if (pool == "proportional") max_iterations <- 1
  history <- list()
  prev <- NULL
  for (it in seq_len(max_iterations)) {
    stream <- val_stream_vectors(Wtab, sim, spec$positions)
    d <- val_draft(sim, league, stream, spec, cand_per_pos)
    drafted <- sort(unlist(d$rosters))
    history[[it]] <- tibble::tibble(iteration = it, n_drafted = length(drafted),
                                    changed = if (is.null(prev)) NA_integer_ else length(setdiff(drafted, prev)),
                                    by_position = paste(names(table(sim$players$position[drafted])),
                                                        table(sim$players$position[drafted]), collapse = " "))
    if (pool == "simulation") Wtab <- val_waiver_levels(sim, drafted)
    if (!is.null(prev) && identical(drafted, prev)) break
    prev <- drafted
  }
  pool_rows <- if (pool == "simulation") drafted else init$rows
  stream <- val_stream_vectors(Wtab, sim, spec$positions)
  rosters <- purrr::imap(d$rosters, function(r, k) {
    tibble::tibble(team = k, row = r, player_id = sim$players$player_id[r], position = sim$players$position[r])
  }) |>
    purrr::list_rbind()
  list(sim = sim, league = league, spec = spec, rosters = rosters, picks = d$picks, waiver = Wtab,
       stream = stream, utility = vapply(seq_len(league$teams), function(k) {
         val_lineup_value(val_team_tops(rosters$row[rosters$team == k], sim, spec), stream, spec, sim$sims)
       }, 0),
       pool = pool, rostered_pool = sim$players$player_id[pool_rows],
       converged = if (pool == "simulation") isTRUE(history[[length(history)]]$changed == 0) else NA,
       iterations = purrr::list_rbind(history), initial_pool = init)
}

#' Utility of an arbitrary set of pool rows under the league's streaming levels.
val_utility <- function(ls, rows) {
  val_lineup_value(val_team_tops(rows, ls$sim, ls$spec), ls$stream, ls$spec, ls$sim$sims)
}

#' Best roster of size `size` reachable from `rows` by dropping the least
#' valuable players one at a time (greedy) or adding the best free players.
val_fit_roster <- function(ls, rows, size, free_rows, cand_per_pos = 6) {
  sim <- ls$sim
  while (length(rows) > size) {
    loss <- vapply(rows, function(j) val_utility(ls, setdiff(rows, j)), 0)
    rows <- setdiff(rows, rows[which.max(loss)])
  }
  free_rows <- setdiff(free_rows, rows)
  added <- integer()
  while (length(rows) < size && length(free_rows)) {
    pos <- sim$players$position
    cands <- unlist(lapply(ls$spec$positions, function(p) {
      r <- free_rows[pos[free_rows] == p]
      r[order(-sim$ros[r])][seq_len(min(length(r), cand_per_pos))]
    }))
    gain <- vapply(cands, function(i) val_utility(ls, c(rows, i)), 0)
    pick <- cands[order(-round(gain, 8), -sim$ros[cands])][1]
    rows <- c(rows, pick)
    added <- c(added, pick)
    free_rows <- setdiff(free_rows, pick)
  }
  list(rows = rows, added = added)
}

#' Generic marginal roster utility (MRU) of pool players: mean over the teams
#' that do not own the player of the gain from adding him and dropping that
#' team's least valuable player (possibly him: then the gain is 0).
val_mru <- function(ls, rows = seq_len(nrow(ls$sim$players))) {
  sim <- ls$sim
  spec <- ls$spec
  teams <- ls$league$teams
  owner <- ls$rosters$team[match(seq_len(nrow(sim$players)), ls$rosters$row)]
  pos <- sim$players$position
  # per team: top-K matrices with each roster player removed (cached)
  cache <- lapply(seq_len(teams), function(k) {
    r <- ls$rosters$row[ls$rosters$team == k]
    full <- val_team_tops(r, sim, spec)
    without <- lapply(r, function(j) {
      t <- full
      t[[pos[j]]] <- val_team_tops(setdiff(r[pos[r] == pos[j]], j), sim, spec)[[pos[j]]]
      t
    })
    list(rows = r, full = full, without = without, u = ls$utility[k])
  })
  vapply(rows, function(i) {
    p <- pos[i]
    if (!p %in% spec$positions) return(0)
    gains <- vapply(setdiff(seq_len(teams), owner[i]), function(k) {
      cc <- cache[[k]]
      best <- cc$u  # dropping the new player himself
      for (jj in seq_along(cc$rows)) {
        t <- cc$without[[jj]]
        t[[p]] <- val_topk_insert(t[[p]], sim$P[i, ])
        best <- max(best, val_lineup_value(t, ls$stream, spec, sim$sims))
      }
      best - cc$u
    }, 0)
    mean(gains)
  }, 0)
}

#' Roster-aware trade evaluation for one simulated team: it sends `give` and
#' receives `get` (pool rows). A team receiving fewer players than it sends
#' fills each freed spot with the best free player (A + replacement vs B + C);
#' one receiving more drops its least valuable players. Returns the utility
#' change and the roster adjustments.
val_trade_eval <- function(ls, team, give, get) {
  r <- ls$rosters$row[ls$rosters$team == team]
  if (!all(give %in% r)) cli::cli_abort("Team {team} does not own every player it gives.")
  u0 <- ls$utility[team]
  new <- c(setdiff(r, give), get)
  free <- setdiff(seq_len(nrow(ls$sim$players)), c(ls$rosters$row, get))
  fit <- val_fit_roster(ls, new, length(r), free)
  dropped <- setdiff(new, fit$rows)
  list(delta = val_utility(ls, fit$rows) - u0, added = fit$added, dropped = dropped, rows = fit$rows)
}
