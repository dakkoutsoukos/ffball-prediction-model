# S0 shadow league simulator (master plan S0; pre-registration VL3) ------------------------------
# Season, playoff and title odds for the owner's league from the current rosters (frozen), the
# league's schedule and rules (F3-lite), the valuation run's weekly projections, the frozen P0
# weekly noise and the frozen level-shock scale (s0_params_v0):
#   points if active = L x F^-1(u | position, lvl)    L ~ lognormal(-s^2/2, s^2), constant per season
#   lineups are chosen on DECISION values (active x lvl: availability is known at lock; L and the
#   weekly noise are not) and scored on REALISED values. Free agents stream into empty slots at
#   the week's expected free-agent level (V2's empty_slots policy).
# Every roster configuration of a what-if is simulated in the same pass (common random numbers).
# Not modelled in v0: K and D/ST, correlation, trades and waivers, in-season learning. Outputs are
# shadow / unvalidated (VL3).

S0_LABEL <- paste("SHADOW / UNVALIDATED (VL3): inputs are early-week, so odds are too sharp until R3; rosters frozen;",
                  "players independent; K and D/ST not simulated")

#' Universe of simulated players with week-by-week availability and if-active levels.
#' `weekly` is a valuation run's weekly table; `player_ids` the players to simulate. In the current
#' week (A = 1 in the run), designated players get the designation prior.
sim_universe <- function(weekly, player_ids, positions, weeks, current_week, prior = read_availability_prior(),
                         p_active_fun = NULL, horizon_sd_fun = NULL) {
  n <- length(player_ids)
  W <- length(weeks)
  A <- matrix(0, n, W)
  lvl <- matrix(0, n, W)
  w <- dplyr::filter(weekly, .data$player_id %in% !!player_ids, .data$week %in% !!weeks)
  i <- match(w$player_id, player_ids)
  j <- match(w$week, weeks)
  A[cbind(i, j)] <- ifelse(w$has_game, w$p_active, 0)
  lvl[cbind(i, j)] <- ifelse(w$has_game, w$lvl, 0)
  cw <- match(current_week, weeks)
  extra <- NULL
  if (!is.na(cw)) {
    cur <- w[w$week == current_week, ]
    # VL3b: P1's frozen provider (E19c) when supplied; otherwise the fixed published prior
    p <- if (is.null(p_active_fun)) val_designation_prior(cur$availability_status, prior) else
      p_active_fun(cur$player_id, cur$availability_status, positions[match(cur$player_id, player_ids)])
    A[cbind(match(cur$player_id, player_ids), cw)] <- ifelse(cur$has_game, pmin(A[cbind(match(cur$player_id, player_ids), cw)], p), 0)
    # VL3c: R3's adopted horizon spread (extra SD of the current week's if-active draw), when supplied
    if (!is.null(horizon_sd_fun)) {
      extra <- numeric(n)
      extra[match(cur$player_id, player_ids)] <- horizon_sd_fun(cur$player_id, positions[match(cur$player_id, player_ids)], cur$team)
      if (!any(extra > 0)) extra <- NULL
    }
  }
  out <- list(player_id = player_ids, position = positions, weeks = weeks, A = A, lvl = lvl)
  if (!is.null(extra)) {
    out$extra_sd <- extra
    out$extra_week <- cw
  }
  out
}

#' Realised lineup points of one team for one week across simulation columns: top-K by decision
#' value per position (carrying realised values), then the laminar slot greedy with streaming.
sim_team_week <- function(rows, dec, real, pos, spec, stream) {
  S <- ncol(dec)
  idx <- seq_len(S)
  tops <- lapply(spec$positions, function(p) {
    K <- spec$K[[p]]
    v <- matrix(-Inf, K, S)
    r <- matrix(0, K, S)
    for (i in rows[pos[rows] == p]) {
      x <- dec[i, ]
      y <- real[i, ]
      for (k in seq_len(K)) {
        take <- x > v[k, ]
        nv <- ifelse(take, x, v[k, ])
        nr <- ifelse(take, y, r[k, ])
        x <- ifelse(take, v[k, ], x)
        y <- ifelse(take, r[k, ], y)
        v[k, ] <- nv
        r[k, ] <- nr
      }
    }
    list(v = v, r = r)
  })
  names(tops) <- spec$positions
  ptr <- lapply(tops, function(t) rep(1L, S))
  total <- numeric(S)
  for (s in spec$slots) {
    el <- intersect(s$eligible, spec$positions)
    for (u in seq_len(s$count)) {
      best <- rep(-Inf, S)
      bestr <- numeric(S)
      who <- integer(S)
      sbest <- 0
      for (j in seq_along(el)) {
        p <- el[j]
        pr <- ptr[[p]]
        ok <- pr <= nrow(tops[[p]]$v)
        head <- rep(-Inf, S)
        hr <- numeric(S)
        head[ok] <- tops[[p]]$v[cbind(pr[ok], idx[ok])]
        hr[ok] <- tops[[p]]$r[cbind(pr[ok], idx[ok])]
        b <- head > best & head > 0
        best[b] <- head[b]
        bestr[b] <- hr[b]
        who[b] <- j
        sbest <- max(sbest, stream[[p]] %||% 0)
      }
      use <- who > 0
      total <- total + ifelse(use, bestr, sbest)
      for (j in seq_along(el)) {
        adv <- use & who == j
        ptr[[el[j]]][adv] <- ptr[[el[j]]][adv] + 1L
      }
    }
  }
  total
}

#' Simulate weekly team scores for every roster configuration in one pass (common random numbers).
#' `configs`: named list; each element a named list team_id -> universe row indices that may start.
#' `stream`: list by week (character) of named numeric FA levels by position. Returns, per config,
#' an array [team, week, sim] of realised scores.
sim_scores <- function(uni, configs, spec, stream, table, sigma, sims = 10000, chunk = 1000, seed = 20261013,
                       sigma_scale = 1, noise_scale = 1) {
  n <- length(uni$player_id)
  W <- length(uni$weeks)
  teams <- names(configs[[1]])
  out <- lapply(configs, function(cf) array(0, c(length(teams), W, sims), dimnames = list(teams, uni$weeks, NULL)))
  s_pl <- unname(sigma[uni$position]) * sigma_scale
  s_pl[is.na(s_pl)] <- 0
  qs <- lapply(seq_len(W), function(j) pd_quantiles(uni$position, pmax(uni$lvl[, j], 0), table))
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = globalenv())
  if (had_seed) old_seed <- get(".Random.seed", envir = globalenv())
  on.exit({
    RNGkind(old_kind[1], old_kind[2], old_kind[3])
    if (had_seed) assign(".Random.seed", old_seed, envir = globalenv())
  })
  RNGkind("L'Ecuyer-CMRG")
  set.seed(seed)
  stream_seed <- get(".Random.seed", envir = globalenv())
  starts <- seq(1, sims, by = chunk)
  # VL3c: positions' lowest P0 floor, for the horizon spread term
  floors <- tapply(table$floor, table$position, min)
  for (ci in seq_along(starts)) {
    assign(".Random.seed", stream_seed, envir = globalenv())
    chunk_seed <- stream_seed
    cols <- starts[ci]:min(sims, starts[ci] + chunk - 1)
    S <- length(cols)
    Z <- matrix(stats::rnorm(n * S), n, S)
    L <- exp(-s_pl^2 / 2 + s_pl * Z)
    for (j in seq_len(W)) {
      act <- matrix(stats::runif(n * S), n, S) < uni$A[, j]
      un <- matrix(stats::runif(n * S), n, S)
      draw <- matrix(sim_qdraw(qs[[j]][rep(seq_len(n), S), , drop = FALSE], as.vector(un)), n, S)
      draw <- uni$lvl[, j] + noise_scale * (draw - uni$lvl[, j])
      if (!is.null(uni$extra_sd) && identical(j, uni$extra_week)) {
        # an independent substream, so the main draws (and results without the term) are unchanged
        main <- get(".Random.seed", envir = globalenv())
        assign(".Random.seed", parallel::nextRNGSubStream(chunk_seed), envir = globalenv())
        e <- matrix(stats::rnorm(n * S), n, S) * uni$extra_sd
        assign(".Random.seed", main, envir = globalenv())
        fl <- unname(floors[uni$position])
        fl[is.na(fl)] <- -Inf
        draw <- pmax(draw + e, fl)
      }
      dec <- act * uni$lvl[, j]
      real <- act * L * draw
      st <- stream[[as.character(uni$weeks[j])]] %||% list()
      for (k in seq_along(configs)) {
        for (t in teams) {
          out[[k]][t, j, cols] <- sim_team_week(configs[[k]][[t]], dec, real, uni$position, spec, st)
        }
      }
    }
    stream_seed <- parallel::nextRNGStream(stream_seed)
  }
  out
}

#' Resolve seasons from simulated scores: remaining regular-season games (completed records fixed),
#' seeds by win share then points for, a 4-team bracket (1 v 4, 2 v 3), multi-week rounds summed,
#' playoff ties to the higher seed. `scores` is [team, week, sim]; returns per-sim seeds, champion,
#' final wins and the current period's results.
sim_resolve <- function(scores, state, current_period) {
  r <- state$rules
  teams <- as.integer(dimnames(scores)[[1]])
  weeks <- as.integer(dimnames(scores)[[2]])
  S <- dim(scores)[3]
  per_weeks <- stats::setNames(r$matchup_periods$scoring_periods, r$matchup_periods$matchup_period)
  period_score <- function(period) {
    wk <- per_weeks[[as.character(period)]] %||% period
    j <- match(wk, weeks)
    if (anyNA(j)) cli::cli_abort("Simulation weeks do not cover matchup period {period}.")
    apply(scores[, j, , drop = FALSE], c(1, 3), sum)
  }
  st <- state$standings[match(teams, state$standings$team_id), ]
  wins <- matrix(st$wins + 0.5 * st$ties, length(teams), S)
  pf <- matrix(st$points_for, length(teams), S)
  cur_games <- NULL
  for (p in seq(current_period, r$regular_periods)) {
    ps <- period_score(p)
    g <- state$schedule[state$schedule$matchup_period == p & !is.na(state$schedule$away_team), ]
    for (k in seq_len(nrow(g))) {
      h <- match(g$home_team[k], teams)
      a <- match(g$away_team[k], teams)
      hw <- (ps[h, ] > ps[a, ]) + 0.5 * (ps[h, ] == ps[a, ])
      wins[h, ] <- wins[h, ] + hw
      wins[a, ] <- wins[a, ] + (1 - hw)
      if (p == current_period) {
        cur_games <- c(cur_games, list(list(home = g$home_team[k], away = g$away_team[k], margin = ps[h, ] - ps[a, ])))
      }
    }
    pf <- pf + ps
  }
  # seeds: win share (equal games for all), then points for, then team id
  seed <- matrix(0L, length(teams), S)
  for (s in seq_len(S)) {
    o <- order(-wins[, s], -pf[, s], teams)
    seed[o, s] <- seq_along(o)
  }
  champ <- integer(S)
  if (r$playoff_teams == 4) {
    sf <- period_score(r$regular_periods + 1)
    fin <- period_score(r$regular_periods + 2)
    by_seed <- function(k) apply(seed, 2, function(x) which(x == k))
    s1 <- by_seed(1); s2 <- by_seed(2); s3 <- by_seed(3); s4 <- by_seed(4)
    col <- seq_len(S)
    w14 <- ifelse(sf[cbind(s1, col)] >= sf[cbind(s4, col)], s1, s4)    # tie: higher seed
    w23 <- ifelse(sf[cbind(s2, col)] >= sf[cbind(s3, col)], s2, s3)
    hi <- ifelse(seed[cbind(w14, col)] < seed[cbind(w23, col)], w14, w23)
    lo <- ifelse(hi == w14, w23, w14)
    champ <- ifelse(fin[cbind(hi, col)] >= fin[cbind(lo, col)], hi, lo)
  } else {
    cli::cli_abort("S0 v0 supports 4-team playoffs only (this league's format).")
  }
  list(teams = teams, seed = seed, champion = teams[champ], wins = wins, points_for = pf, current = cur_games,
       playoff_teams = r$playoff_teams)
}

#' Odds table and this week's matchups from a resolved season; `owner` adds the leverage.
sim_summarise <- function(res, owner = NA_integer_) {
  S <- ncol(res$seed)
  po <- res$seed <= res$playoff_teams
  tab <- tibble::tibble(team_id = res$teams, e_wins = rowMeans(res$wins), p_playoffs = rowMeans(po),
                        p_title = vapply(res$teams, function(t) mean(res$champion == t), 0),
                        mean_points_for = rowMeans(res$points_for))
  for (k in seq_len(res$playoff_teams)) tab[[paste0("p_seed", k)]] <- rowMeans(res$seed == k)
  tab$mc_se_playoffs <- sqrt(tab$p_playoffs * (1 - tab$p_playoffs) / S)
  games <- purrr::map(res$current %||% list(), function(g) {
    tibble::tibble(home = g$home, away = g$away, p_home = mean(g$margin > 0) + 0.5 * mean(g$margin == 0),
                   margin_q10 = unname(stats::quantile(g$margin, 0.1)), margin_q50 = unname(stats::quantile(g$margin, 0.5)),
                   margin_q90 = unname(stats::quantile(g$margin, 0.9)))
  }) |>
    purrr::list_rbind()
  lev <- NULL
  if (!is.na(owner) && length(res$current)) {
    g <- Filter(function(x) owner %in% c(x$home, x$away), res$current)
    if (length(g)) {
      won <- if (g[[1]]$home == owner) g[[1]]$margin > 0 else g[[1]]$margin < 0
      oi <- match(owner, res$teams)
      lev <- tibble::tibble(team_id = owner, p_win_this_week = mean(won),
                            p_playoffs_if_win = mean(po[oi, won]), p_playoffs_if_loss = mean(po[oi, !won]),
                            leverage = mean(po[oi, won]) - mean(po[oi, !won]))
    }
  }
  invariants <- c(sum_p_playoffs = sum(tab$p_playoffs), sum_p_title = sum(tab$p_title),
                  max_mc_se = max(sqrt(c(tab$p_playoffs, tab$p_title) * (1 - c(tab$p_playoffs, tab$p_title)) / S)))
  list(teams = tab, matchups = games, leverage = lev, invariants = invariants, sims = S)
}

#' League odds for the owner's league: build the universe from the league model `m` (lg_load()),
#' the league state (F3-lite), the frozen P0 table and S0 parameters. `what_if` = list(team, add,
#' drop) of universe player ids gives a second configuration simulated with common random numbers.
sim_league_odds <- function(m, state, table = read_pod_table(), params = read_s0_params(),
                            prior = read_availability_prior(), sims = 10000, chunk = 1000, seed = 20261013,
                            what_if = NULL, sigma_scale = 1, noise_scale = 1, p_active_fun = NULL,
                            horizon_sd_fun = NULL) {
  t0 <- Sys.time()
  weekly <- m$input_data$weekly
  league <- m$league
  last_week <- max(league$playoff_weeks)
  weeks <- seq(m$current_week, last_week)
  rost <- m$input_data$roster |> dplyr::filter(.data$is_skill)
  pid <- m$sim$players$player_id
  team_rows <- lapply(m$state, function(s) s$rows)                 # non-IR rostered pool rows per team
  extra <- if (!is.null(what_if)) what_if$add else character()
  ids <- unique(c(pid[unlist(team_rows)], extra))
  pos <- m$sim$players$position[match(ids, pid)]
  uni <- sim_universe(weekly, ids, pos, weeks, m$current_week, prior, p_active_fun, horizon_sd_fun)
  cfg <- function(add = character(), drop = character(), team = NA) {
    lapply(names(team_rows), function(t) {
      r <- match(pid[team_rows[[t]]], ids)
      if (!is.na(team) && t == as.character(team)) {
        r <- setdiff(r, match(drop, ids))
        r <- c(r, match(add, ids))
      }
      r[!is.na(r)]
    }) |> rlang::set_names(names(team_rows))
  }
  configs <- list(base = cfg())
  if (!is.null(what_if)) configs$what_if <- cfg(what_if$add, what_if$drop, what_if$team)
  fa <- lg_fa_levels(m, m$fa_rows)
  stream <- lapply(weeks, function(w) {
    x <- fa[fa$week == w, ]
    stats::setNames(as.list(x$W), x$position)
  }) |> rlang::set_names(as.character(weeks))
  spec <- val_lineup_spec(league)
  scores <- sim_scores(uni, configs, spec, stream, table, params$sigma_L, sims, chunk, seed, sigma_scale, noise_scale)
  cp <- state$status$current_matchup_period
  res <- lapply(scores, function(sc) sim_summarise(sim_resolve(sc, state, cp), m$my_team))
  list(results = res, label = S0_LABEL, current_period = cp, sims = sims, seed = seed,
       sigma_scale = sigma_scale, noise_scale = noise_scale, sigma_L = params$sigma_L,
       espn_playoff_pct = state$standings[, c("team_id", "espn_playoff_pct")],
       availability_source = if (is.null(p_active_fun)) prior$source else attr(p_active_fun, "source") %||% "P1 provider",
       elapsed_seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
}
