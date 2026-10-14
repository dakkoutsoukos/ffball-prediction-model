# P5: scenario engine v1 (master plan P5; 05 section 4.7) ------------------------------------------
# Joint draws for every downstream tool. Per simulation: a level shock L_i ~ lognormal(-s^2/2, s^2)
# per player (mean 1), then per player-week: active ~ Bernoulli(p_active); points = L_i x F^-1(u | base)
# from a quantile function. Draws are chunked; each player's random numbers come from his own stream
# (seed + player hash + chunk), so common random numbers hold when the universe changes (adding a
# player never moves anyone else's draws). Lineups are chosen per sim-week on DECISION values
# (availability known at lock times the forecast; never L or u) and scored on REALISED values.
# Components are pluggable: today P0's table and S0's sigma_L; P2/P4 swap in when frozen.

SCN_CHUNK <- 500L

#' Integer hash of player ids (stable across sessions).
scn_hash <- function(ids) {
  vapply(ids, function(x) {
    b <- utf8ToInt(x)
    h <- 0
    for (v in b) h <- (h * 31 + v) %% 2147483647
    as.integer(h)
  }, 0L, USE.NAMES = FALSE)
}

#' Interpolated quantile draws without materialising per-draw quantile rows: `q` is rows x K, `ri`
#' indexes rows for each draw, `u` the uniforms (tails held at the end quantiles).
scn_qdraw <- function(q, ri, u, tau) {
  K <- length(tau)
  k <- findInterval(u, tau)
  out <- numeric(length(u))
  lo <- k == 0
  hi <- k >= K
  mid <- !lo & !hi
  out[lo] <- q[cbind(ri[lo], 1L)]
  out[hi] <- q[cbind(ri[hi], K)]
  if (any(mid)) {
    kk <- k[mid]
    w <- (u[mid] - tau[kk]) / (tau[kk + 1] - tau[kk])
    a <- q[cbind(ri[mid], kk)]
    out[mid] <- a + w * (q[cbind(ri[mid], kk + 1)] - a)
  }
  out
}

#' A scenario specification. `weekly`: one row per (player, week) with position, base (mean if
#' active), p_active; `sigma_L`: per row of `weekly`'s players (named by player) or a function of
#' (position, base); `quantiles`: function(position, base) -> rows x K matrix on `tau`.
scn_spec <- function(weekly, quantiles, sigma_L, tau = POD_TAU, sims = 2000L, seed = 20261013L, chunk = SCN_CHUNK) {
  stopifnot(all(c("player", "week", "position", "base", "p_active") %in% names(weekly)))
  weekly <- weekly[order(weekly$player, weekly$week), ]
  players <- unique(weekly$player)
  s <- if (is.function(sigma_L)) {
    first <- weekly[match(players, weekly$player), ]
    sigma_L(first$position, first$base)
  } else unname(sigma_L[players])
  s[is.na(s)] <- 0
  list(weekly = weekly, players = players, sigma = s, q = quantiles(weekly$position, weekly$base), tau = tau,
       sims = as.integer(sims), seed = as.integer(seed), chunk = as.integer(chunk),
       hash = digest_text(paste(nrow(weekly), sum(weekly$base), sum(weekly$p_active), sims, seed, sep = "|")))
}

#' One chunk of draws: realised points and activity (rows of spec$weekly x sims in the chunk).
scn_chunk <- function(spec, chunk_id) {
  n_sim <- min(spec$chunk, spec$sims - (chunk_id - 1L) * spec$chunk)
  if (n_sim <= 0) return(NULL)
  w <- spec$weekly
  pid <- match(w$player, spec$players)
  h <- scn_hash(spec$players)
  points <- matrix(0, nrow(w), n_sim)
  active <- matrix(FALSE, nrow(w), n_sim)
  for (j in seq_along(spec$players)) {
    rows <- which(pid == j)
    set.seed((spec$seed + h[j] + 7919L * chunk_id) %% 2147483647L)
    z <- stats::rnorm(n_sim)
    Lj <- exp(-spec$sigma[j]^2 / 2 + spec$sigma[j] * z)
    u <- matrix(stats::runif(length(rows) * n_sim), length(rows), n_sim)
    a <- matrix(stats::runif(length(rows) * n_sim), length(rows), n_sim) < w$p_active[rows]
    x <- scn_qdraw(spec$q, rep(rows, times = n_sim), as.vector(u), spec$tau)
    points[rows, ] <- matrix(x, length(rows), n_sim) * rep(Lj, each = length(rows)) * a
    active[rows, ] <- a
  }
  list(points = points, active = active, chunk = chunk_id, sims = n_sim)
}

#' Apply `f(chunk)` to every chunk and return the list of results.
scn_map <- function(spec, f) {
  n <- ceiling(spec$sims / spec$chunk)
  lapply(seq_len(n), function(i) f(scn_chunk(spec, i)))
}

#' Decision-time team scores for one chunk: per team and week, the lineup optimal on decision values
#' (availability known at lock x base) scored on realised points. `rosters`: named list team ->
#' players. Returns an array [team, week, sim].
scn_team_scores <- function(spec, chunk, rosters, weeks = sort(unique(spec$weekly$week))) {
  w <- spec$weekly
  out <- array(0, c(length(rosters), length(weeks), chunk$sims), dimnames = list(names(rosters), weeks, NULL))
  slots <- list(positions = LAB_POSITIONS, K = list(QB = 1L, RB = 4L, WR = 4L, TE = 3L),
                slots = list(list(eligible = "QB", count = 1L), list(eligible = "RB", count = 2L),
                             list(eligible = "WR", count = 2L), list(eligible = "TE", count = 1L),
                             list(eligible = LAB_FLEX, count = 2L)))
  for (ti in seq_along(rosters)) {
    for (wi in seq_along(weeks)) {
      rows <- which(w$player %in% rosters[[ti]] & w$week == weeks[wi])
      if (!length(rows)) next
      dec <- chunk$active[rows, , drop = FALSE] * w$base[rows]
      dec[!chunk$active[rows, , drop = FALSE]] <- -Inf                 # known inactive at lock: cannot start
      out[ti, wi, ] <- sim_team_week(seq_along(rows), dec, chunk$points[rows, , drop = FALSE], w$position[rows], slots, list())
    }
  }
  out
}
