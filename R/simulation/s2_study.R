# S2 v1 week-k calibration study (pre-registration VL6; estimation only) ------------------------
# For each F6 development replay league (arm A) and k in {4, 7, 10}: rosters frozen at week k; each
# rostered player's remaining weeks get P4's rolling-origin mean if active (by horizon bucket) and
# attrition (fit on seasons before s); P0 weekly noise around that mean; no level shock (sensitivity:
# S0's sigma_L, one shock per player held over the remaining weeks); decision-time lineups (S0's
# vectorised slot greedy on active x mean); the lab's playoff rule (top 4 by wins, then points for).
# Compared with the replay's realised qualification.

S2_K <- c(4L, 7L, 10L)
S2_SIMS <- 2000L

s2_lab_spec <- function() {
  list(positions = LAB_POSITIONS, K = list(QB = 1L, RB = 4L, WR = 4L, TE = 3L),
       slots = list(list(eligible = "QB", count = 1L), list(eligible = "RB", count = 2L), list(eligible = "WR", count = 2L),
                    list(eligible = "TE", count = 1L), list(eligible = LAB_FLEX, count = 2L)))
}

#' Realised wins (ties half) and points for of each team through week k (regular season).
s2_record <- function(tw, k, n) {
  x <- tw[tw$week <= k & tw$week %in% LAB_REG_WEEKS, c("team", "week", "opponent", "points")]
  x$opp_points <- x$points[match(paste(x$opponent, x$week), paste(x$team, x$week))]
  x$w <- (x$points > x$opp_points) + 0.5 * (x$points == x$opp_points)
  list(wins = vapply(seq_len(n), function(j) sum(x$w[x$team == j]), 0),
       pf = vapply(seq_len(n), function(j) sum(x$points[x$team == j]), 0))
}

#' P(playoffs) at week k for every team of one replay league. `sigma` (named by position) adds the
#' level-shock sensitivity; NULL = no shock (VL6's main specification).
s2_league_k <- function(S, tw, k, comp, table, sims = S2_SIMS, seed = 1L, sigma = NULL) {
  n <- max(tw$team)
  rec <- s2_record(tw, k, n)
  rosters <- lapply(seq_len(n), function(j) lab_ids(tw$roster[tw$team == j & tw$week == k]))
  future <- seq(k + 1L, max(LAB_REG_WEEKS))
  ids <- sort(unique(unlist(rosters)))
  L <- S$L[ids, k]
  team <- S$team_asof[ids, k]
  rows <- purrr::map(future, function(tt) {
    plays <- S$plays[cbind(match(team, S$teams), tt)]
    ok <- !is.na(plays) & plays & !is.na(L)
    tibble::tibble(pid = ids[ok], position = S$pos[ids[ok]], L = L[ok], t = rep(tt, sum(ok)))
  }) |> purrr::list_rbind()
  rows$h <- rows$t - k
  rows$bucket <- p4_bucket(rows$h)
  rows$lband <- pd_band(rows$L)
  rows <- p4_apply_components(rows, comp)
  q <- pd_quantiles(rows$position, pmax(rows$mu, 0), table)
  spec <- s2_lab_spec()
  team_pts <- array(0, c(n, length(future), sims))
  withr::with_seed(seed, {
    shock <- matrix(1, length(ids), sims)
    if (!is.null(sigma)) {
      s <- unname(sigma[S$pos[ids]])
      s[is.na(s)] <- 0
      shock <- exp(-s^2 / 2 + s * matrix(stats::rnorm(length(ids) * sims), length(ids), sims))
    }
    for (wi in seq_along(future)) {
      r <- which(rows$t == future[wi])
      if (!length(r)) next
      act <- matrix(stats::runif(length(r) * sims), length(r), sims) < rows$A[r]
      draw <- matrix(scn_qdraw(q, rep(r, times = sims), stats::runif(length(r) * sims), POD_TAU), length(r), sims)
      dec <- act * rows$mu[r]
      real <- act * draw * shock[match(rows$pid[r], ids), , drop = FALSE]
      for (j in seq_len(n)) {
        own <- which(rows$pid[r] %in% rosters[[j]])
        if (length(own)) team_pts[j, wi, ] <- sim_team_week(own, dec, real, rows$position[r], spec, list())
      }
    }
  })
  sim_w <- matrix(rec$wins, n, sims)
  sim_pf <- matrix(rec$pf, n, sims)
  for (wi in seq_along(future)) {
    o <- tw$opponent[tw$week == future[wi]][order(tw$team[tw$week == future[wi]])]
    x <- team_pts[, wi, ]
    xo <- x[o, , drop = FALSE]
    sim_w <- sim_w + (x > xo) + 0.5 * (x == xo)
    sim_pf <- sim_pf + x
  }
  made <- matrix(FALSE, n, sims)
  for (s in seq_len(sims)) made[order(-sim_w[, s], -sim_pf[, s], seq_len(n))[1:4], s] <- TRUE
  tibble::tibble(team = seq_len(n), k = k, p_playoffs = rowMeans(made), wins_k = rec$wins, pf_k = rec$pf)
}

#' The study over all development replays (arm A); `comps`: P4 components per season (fit on
#' earlier seasons), named by season.
s2_week_k_study <- function(replays, player_week_all, team_games, comps, table, ks = S2_K, sims = S2_SIMS,
                            sigma = NULL, register = read_contamination_register()) {
  assert_family_seasons("decision_family", vapply(replays, function(r) as.integer(r$season), 0L), "development", register)
  purrr::map(replays, function(rp) {
    S <- lab_season_data(player_week_all, team_games, rp$season)
    tw <- rp$team_weeks[rp$team_weeks$arm == "A", ]
    st <- rp$standings[rp$standings$arm == "A", ]
    comp <- comps[[as.character(rp$season)]]
    purrr::map(sort(unique(tw$league)), function(l) {
      x <- tw[tw$league == l, ]
      purrr::map(ks, function(k) s2_league_k(S, x, k, comp, table, sims, seed = rp$season * 1000L + l * 10L + k,
                                             sigma = sigma)) |>
        purrr::list_rbind() |>
        dplyr::mutate(season = rp$season, league = l, n_teams = max(x$team), .before = 1) |>
        dplyr::left_join(dplyr::select(st[st$league == l, ], "team", made = "playoffs"), by = "team")
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}

#' P4 components per development season, each fit on the seasons before it (2019 warm-up).
s2_components <- function(player_week_all, team_games, seasons = LAB_DEV_SEASONS) {
  rows <- purrr::map(seq(LAB_WARMUP, max(seasons) - 1L), function(s) {
    p4_ros_rows(lab_season_data(player_week_all, team_games, s), 1:15)
  }) |> purrr::list_rbind()
  stats::setNames(lapply(seasons, function(s) p4_fit_components(rows[rows$season < s, ])), as.character(seasons))
}

#' VL6 estimates by k: Brier, the calibration slope and the reliability table, with league-clustered,
#' season-blocked bootstrap CIs (leagues resampled within season).
s2_week_k_summary <- function(study, reps = 2000L, seed = 1L) {
  purrr::map(sort(unique(study$k)), function(kk) {
    d <- study[study$k == kk, ]
    o <- as.numeric(d$made)
    groups <- split(seq_len(nrow(d)), d$season)
    lg <- lapply(groups, function(i) split(i, d$league[i]))
    set.seed(seed + kk)
    b <- replicate(reps, {
      i <- unlist(lapply(lg, function(L) unlist(L[sample(length(L), length(L), replace = TRUE)], use.names = FALSE)))
      c(brier = mean((d$p_playoffs[i] - o[i])^2), slope = calibration_slope(d$p_playoffs[i], o[i]))
    })
    tibble::tibble(k = kk, n = nrow(d), brier = mean((d$p_playoffs - o)^2),
                   brier_lo = unname(stats::quantile(b["brier", ], 0.025)), brier_hi = unname(stats::quantile(b["brier", ], 0.975)),
                   base_rate_brier = mean((mean(o) - o)^2), slope = calibration_slope(d$p_playoffs, o),
                   slope_lo = unname(stats::quantile(b["slope", ], 0.025)), slope_hi = unname(stats::quantile(b["slope", ], 0.975)))
  }) |> purrr::list_rbind()
}
