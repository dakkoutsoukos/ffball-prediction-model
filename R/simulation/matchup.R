# S1: matchup win probability (master plan S1; pre-registration VL5, experiment X23) ----------------
# Both methods use the same player PODs at lineup lock: the frozen P0 table around the F4 base, with
# P(active) by position x base band (LAB1a). S1-sim convolves them exactly by simulation (P5 engine
# style draws, no level shock: one week); the baseline is the normal approximation from the same
# PODs' means and variances. Evaluated on the F6 development matchups (realised winners).

S1_SIMS <- 10000L

#' Mean and variance of PODs: X = A x Y, A ~ Bernoulli(p), Y with quantiles q on tau (trapezoid
#' weights; tails held at the end quantiles, as crps_quantiles()).
s1_pod_moments <- function(q, p, tau = POD_TAU) {
  K <- length(tau)
  w <- numeric(K)
  d <- diff(tau)
  w[-K] <- w[-K] + d / 2
  w[-1] <- w[-1] + d / 2
  w[1] <- w[1] + tau[1]
  w[K] <- w[K] + (1 - tau[K])
  m1 <- drop(q %*% w)
  m2 <- drop(q^2 %*% w)
  list(mean = p * m1, var = p * m2 - (p * m1)^2)
}

#' Regular-season matchups of arm A in a replayed season, one row per pair (team < opponent), with
#' both lineups (gsis ids) and the realised result for the first team (1 win, 0.5 tie, 0 loss).
s1_matchups <- function(replay, S) {
  tw <- replay$team_weeks
  tw <- tw[tw$arm == "A" & tw$week %in% LAB_REG_WEEKS, ]
  key <- paste(tw$league, tw$week, tw$team)
  a <- tw[tw$team < tw$opponent, ]
  b <- tw[match(paste(a$league, a$week, a$opponent), key), ]
  tibble::tibble(season = a$season, league = a$league, n_teams = a$n_teams, week = a$week, team = a$team, opponent = a$opponent,
                 lineup_a = lapply(a$lineup, function(x) S$ids[lab_ids(x)]), lineup_b = lapply(b$lineup, function(x) S$ids[lab_ids(x)]),
                 outcome = (a$points > b$points) + 0.5 * (a$points == b$points))
}

#' P(win) of the first team by simulation and by the normal approximation, for each matchup.
s1_predict <- function(matchups, frame, table, active_table, sims = S1_SIMS, seed = 23L) {
  rows <- frame[frame$season %in% unique(matchups$season) & !is.na(frame$espn_proj), ]
  key <- paste(rows$season, rows$week, rows$gsis_id)
  base <- dplyr::coalesce(rows$base, 0)
  q_all <- pd_quantiles(rows$position, base, table)
  p_all <- lab_p_active(rows$position, base, active_table)
  set.seed(seed)
  out <- purrr::map(seq_len(nrow(matchups)), function(i) {
    ka <- match(paste(matchups$season[i], matchups$week[i], matchups$lineup_a[[i]]), key)
    kb <- match(paste(matchups$season[i], matchups$week[i], matchups$lineup_b[[i]]), key)
    ka <- ka[!is.na(ka)]
    kb <- kb[!is.na(kb)]
    k <- c(ka, kb)
    side <- c(rep(1, length(ka)), rep(-1, length(kb)))
    u <- stats::runif(length(k) * sims)
    act <- matrix(stats::runif(length(k) * sims), length(k), sims) < p_all[k]
    x <- matrix(scn_qdraw(q_all, rep(k, times = sims), u, POD_TAU), length(k), sims) * act
    diff <- colSums(x * side)
    mo <- s1_pod_moments(q_all[k, , drop = FALSE], p_all[k])
    mu <- sum(mo$mean * side)
    sd <- sqrt(sum(mo$var))
    tibble::tibble(p_sim = mean(diff > 0) + 0.5 * mean(diff == 0), p_normal = stats::pnorm(mu / sd), mu_diff = mu, sd_diff = sd)
  }) |>
    purrr::list_rbind()
  dplyr::bind_cols(matchups[c("season", "league", "n_teams", "week", "team", "opponent", "outcome")], out)
}

#' VL5 evaluation: Brier, log loss, the non-inferiority bound and the slope rule.
s1_evaluate <- function(pred, reps = 2000L, seed = 1L) {
  bs <- function(p) (p - pred$outcome)^2
  d <- bs(pred$p_sim) - bs(pred$p_normal)
  b <- pd_cluster_boot(d, pred$season, pred$week, reps = reps, seed = seed)
  binary <- pred$outcome != 0.5
  slope <- calibration_slope(pred$p_sim[binary], pred$outcome[binary])
  ps <- split(seq_len(nrow(pred)), paste(pred$season, pred$week))
  by_season <- split(names(ps), sub(" .*", "", names(ps)))
  set.seed(seed + 1L)
  sb <- replicate(reps, {
    i <- unlist(lapply(by_season, function(w) unlist(ps[sample(w, length(w), replace = TRUE)], use.names = FALSE)))
    i <- i[binary[i]]
    calibration_slope(pred$p_sim[i], pred$outcome[i])
  })
  slope_ci <- unname(stats::quantile(sb, c(0.025, 0.975)))
  ll <- function(p) log_loss(p, pred$outcome)
  list(n = nrow(pred), brier_sim = mean(bs(pred$p_sim)), brier_normal = mean(bs(pred$p_normal)), d_brier = mean(d),
       d_brier_ci = unname(stats::quantile(b, c(0.025, 0.975))), non_inferior = unname(stats::quantile(b, 0.975)) <= 0.005,
       slope = slope, slope_ci = slope_ci, slope_rule = slope_ci[1] <= 1 && slope_ci[2] >= 1 && slope >= 0.8 && slope <= 1.2,
       logloss_sim = ll(pred$p_sim), logloss_normal = ll(pred$p_normal),
       corp_sim = brier_decomposition(pred$p_sim[binary], pred$outcome[binary]),
       corp_normal = brier_decomposition(pred$p_normal[binary], pred$outcome[binary]),
       reliability_sim = reliability_table(pred$p_sim[binary], pred$outcome[binary]),
       by_size = dplyr::summarise(pred, n = dplyr::n(), brier_sim = mean((.data$p_sim - .data$outcome)^2),
                                  brier_normal = mean((.data$p_normal - .data$outcome)^2), .by = "n_teams"))
}
