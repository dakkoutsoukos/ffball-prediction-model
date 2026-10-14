# Valuation v3 (master plan S3; pre-registration VL7): X10a, the V1 re-draft with level uncertainty and
# learning. New functions only (prefix v3_); V1's simulation code is reused and never modified.
#
# Each player gets a season-long level shock m per simulation. Lineups are chosen on decision values
# (prior levels until the learning lag ends, learned levels afterwards) and scored on realised values.
# With sigma = 0 every function here reproduces V1's draft and fixed point exactly (tested).

X10A_RUN <- "20261007T062429Z"     # the archived 2026 week-5 run VE3's trial used
X10A_WEEK <- 5L
X10A_SHOCK_SEED <- 20261014L
X10A_WEEKLY_FILE <- file.path("data", "archive", "valuation", "season=2026", "week=05", "run=20261007T062429Z", "weekly.parquet")

#' Level-uncertainty simulation on top of V1's availability draws. `sigma` is named by position;
#' `lag` is the number of weeks from `current_week` decided on prior levels (Inf = no learning).
#' Columns are V1's: (simulation s, week j) at (s - 1) * W + j.
v3_lu_setup <- function(weekly, sigma, current_week, lag = 3, sims = 200, seed = 20261007, shock_seed = X10A_SHOCK_SEED) {
  sim <- val_sim_setup(weekly, sims, seed)
  n <- nrow(sim$players)
  W <- length(sim$weeks)
  s <- unname(sigma[sim$players$position])
  s[is.na(s)] <- 0
  Z <- withr::with_seed(shock_seed, matrix(stats::rnorm(n * sims), n, sims))
  m <- exp(-s^2 / 2 + s * Z)
  scol <- rep(seq_len(sims), each = W)
  learned <- rep(sim$weeks >= current_week + lag, times = sims)
  M <- m[, scol, drop = FALSE]
  Mhat <- M
  Mhat[, !learned] <- 1
  E <- sim$E[, sim$colweek, drop = FALSE]
  list(sim = sim, D = sim$P * Mhat, R = sim$P * M, ED = E * Mhat, ER = E * M, shock = m, learned = learned,
       sigma = sigma, lag = lag)
}

#' Insert decision values v (carrying realised values r) into column-wise sorted top-K matrices.
v3_topk_insert <- function(Tp, v, r) {
  for (k in seq_len(nrow(Tp$v))) {
    take <- v > Tp$v[k, ]
    if (!any(take)) next
    ov <- Tp$v[k, take]
    or <- Tp$r[k, take]
    Tp$v[k, take] <- v[take]
    Tp$r[k, take] <- r[take]
    v[take] <- ov
    r[take] <- or
  }
  Tp
}

#' Top-K decision/realised matrices of a set of rows, by position.
v3_team_tops <- function(rows, lu, spec) {
  C <- ncol(lu$D)
  pos <- lu$sim$players$position
  rlang::set_names(lapply(spec$positions, function(p) {
    Tp <- list(v = matrix(-Inf, spec$K[[p]], C), r = matrix(0, spec$K[[p]], C))
    for (i in rows[pos[rows] == p]) Tp <- v3_topk_insert(Tp, lu$D[i, ], lu$R[i, ])
    Tp
  }), spec$positions)
}

#' Stream per position and column: the best undrafted player by decision value E * m-hat, who scores
#' E * m. Floored at 0 like V1's waiver level.
v3_stream <- function(lu, undrafted, positions) {
  pos <- lu$sim$players$position
  C <- ncol(lu$D)
  out <- lapply(positions, function(p) {
    r <- undrafted[pos[undrafted] == p]
    if (!length(r)) return(list(dec = numeric(C), real = numeric(C)))
    d <- lu$ED[r, , drop = FALSE]
    k <- max.col(t(d), ties.method = "first")
    dec <- d[cbind(k, seq_len(C))]
    real <- lu$ER[r, , drop = FALSE][cbind(k, seq_len(C))]
    neg <- dec <= 0
    dec[neg] <- 0
    real[neg] <- 0
    list(dec = dec, real = real)
  })
  rlang::set_names(out, positions)
}

#' Mean realised lineup points: V1's slot greedy on decision values (a slot is streamed when the
#' stream's decision value beats the best roster candidate), summing realised values.
v3_lineup_value <- function(tops, stream, spec, sims) {
  C <- ncol(tops[[1]]$v)
  idx <- seq_len(C)
  ptr <- lapply(tops, function(m) rep(1L, C))
  total <- numeric(C)
  for (s in spec$slots) {
    el <- intersect(s$eligible, spec$positions)
    for (u in seq_len(s$count)) {
      best_d <- rep(-Inf, C)
      best_r <- numeric(C)
      who <- integer(C)
      use <- logical(C)
      for (j in seq_along(el)) {
        p <- el[j]
        r <- ptr[[p]]
        hd <- rep(-Inf, C)
        hr <- numeric(C)
        ok <- r <= nrow(tops[[p]]$v)
        hd[ok] <- tops[[p]]$v[cbind(r[ok], idx[ok])]
        hr[ok] <- tops[[p]]$r[cbind(r[ok], idx[ok])]
        roster <- hd >= stream[[p]]$dec
        vd <- ifelse(roster, hd, stream[[p]]$dec)
        vr <- ifelse(roster, hr, stream[[p]]$real)
        b <- vd > best_d
        best_d[b] <- vd[b]
        best_r[b] <- vr[b]
        who[b] <- j
        use[b] <- roster[b]
      }
      total <- total + best_r
      for (j in seq_along(el)) {
        adv <- who == j & use
        ptr[[el[j]]][adv] <- ptr[[el[j]]][adv] + 1L
      }
    }
  }
  sum(total) / sims
}

#' V1's snake draft (val_draft) with the v3 evaluator: each pick maximises the change in mean realised
#' lineup points; candidates are the best few available per position by ROS points.
v3_draft <- function(lu, league, stream, spec, cand_per_pos = 6) {
  sim <- lu$sim
  teams <- league$teams
  R <- val_roster_size(league)
  rosters <- vector("list", teams)
  tops <- lapply(seq_len(teams), function(k) v3_team_tops(integer(), lu, spec))
  u <- rep(v3_lineup_value(tops[[1]], stream, spec, sim$sims), teams)
  avail <- rep(TRUE, nrow(sim$players))
  order_k <- unlist(lapply(seq_len(R), function(r) if (r %% 2 == 1) seq_len(teams) else rev(seq_len(teams))))
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
      tp[[pos[i]]] <- v3_topk_insert(tp[[pos[i]]], lu$D[i, ], lu$R[i, ])
      v3_lineup_value(tp, stream, spec, sim$sims) - u[k]
    }, 0)
    best <- cands[order(-round(gains, 8), -sim$ros[cands], sim$players$player_id[cands])][1]
    tops[[k]][[pos[best]]] <- v3_topk_insert(tops[[k]][[pos[best]]], lu$D[best, ], lu$R[best, ])
    u[k] <- u[k] + gains[match(best, cands)]
    rosters[[k]] <- c(rosters[[k]], best)
    avail[best] <- FALSE
  }
  list(rosters = rosters, utility = u)
}

#' X10a fixed point: draft -> undrafted pool -> stream, from the proportional pool, until the drafted
#' set repeats or `max_iterations`. Returns the per-iteration history and the convergence flag.
v3_fixed_point <- function(lu, league, cand_per_pos = 6, max_iterations = 6) {
  spec <- val_lineup_spec(league)
  sim <- lu$sim
  all_rows <- seq_len(nrow(sim$players))
  init <- val_proportional_pool(sim, league)
  stream <- v3_stream(lu, setdiff(all_rows, init$rows), spec$positions)
  prev <- NULL
  history <- list()
  converged <- FALSE
  for (it in seq_len(max_iterations)) {
    d <- v3_draft(lu, league, stream, spec, cand_per_pos)
    drafted <- sort(unlist(d$rosters))
    tab <- table(factor(sim$players$position[drafted], VAL_POSITIONS))
    history[[it]] <- tibble::tibble(iteration = it, n_drafted = length(drafted),
                                    changed = if (is.null(prev)) NA_integer_ else length(setdiff(drafted, prev)),
                                    QB = tab[["QB"]], RB = tab[["RB"]], WR = tab[["WR"]], TE = tab[["TE"]])
    if (!is.null(prev) && identical(drafted, prev)) {
      converged <- TRUE
      break
    }
    prev <- drafted
    stream <- v3_stream(lu, setdiff(all_rows, drafted), spec$positions)
  }
  list(history = purrr::list_rbind(history), converged = converged, drafted = drafted,
       proportional = init$counts, rosters = d$rosters)
}

#' X10a (VL7): the harness check (V1's own fixed point) and the three variants (lag 3 primary, lag 0,
#' no learning) on the archived run's weekly inputs. Projections only.
x10a_study <- function(weekly, league, sigma, current_week = X10A_WEEK, sims = 200, seed = 20261007,
                       max_iterations = 6, cand_per_pos = 6) {
  sim <- val_sim_setup(weekly, sims, seed)
  v1 <- val_league_sim(sim, league, cand_per_pos, max_iterations, pool = "simulation")
  v1_qb <- sum(sim$players$position[match(v1$rostered_pool, sim$players$player_id)] == "QB")
  variants <- c(lag3 = 3, lag0 = 0, none = Inf)
  runs <- purrr::imap(variants, function(lag, nm) {
    t0 <- Sys.time()
    lu <- v3_lu_setup(weekly, sigma, current_week, lag = lag, sims = sims, seed = seed)
    fp <- v3_fixed_point(lu, league, cand_per_pos, max_iterations)
    list(variant = nm, lag = lag, history = dplyr::mutate(fp$history, variant = nm, .before = 1), converged = fp$converged,
         qb_final = utils::tail(fp$history$QB, 1), proportional = fp$proportional,
         minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")))
  })
  prop_qb <- runs$lag3$proportional[["QB"]]
  list(harness = list(qb = v1_qb, converged = isTRUE(v1$converged), iterations = v1$iterations,
                      reproduces = v1_qb >= 25 && !isTRUE(v1$converged)),
       variants = runs, proportional_qb = prop_qb,
       supported = runs$lag3$converged && abs(runs$lag3$qb_final - prop_qb) <= 3)
}
