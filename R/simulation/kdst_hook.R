# VL3d: v0 K and D/ST draws in S0's team totals (E23 result; owner approval X-029) -----------------
# X22's v0 (position-level empirical quantiles of team-game K and D/ST points under the league's
# scoring, fit on 2019-2023) is frozen once; S0 adds independent draws per team-week from its own
# random substream, identical across roster configurations.

KDST_V0_FILE <- "models/simulation/kdst_v0.yml"

#' Freeze X22's v0 quantiles (write-once; quantiles only, no league rules).
kdst_v0_freeze <- function(units, path = KDST_V0_FILE, seasons = X22_UNIT_SEASONS) {
  fit <- x22_fit(units, seasons)
  x <- list(version = "kdst_v0", pre_registration = "VL3d (E23 result)", seasons = as.integer(seasons),
            n_team_games = sum(units$season %in% seasons), tau = round(fit$tau, 2),
            K = round(fit$v0$K, 4), DST = round(fit$v0$DST, 4))
  write_frozen_yaml(x, path, "FROZEN (VL3d): X22 v0 K and D/ST quantiles of league-scored team-game points. Never edit.")
}

read_kdst_v0 <- function(path = KDST_V0_FILE) {
  p <- yaml::read_yaml(path)
  p$tau <- unlist(p$tau)
  p$K <- unlist(p$K)
  p$DST <- unlist(p$DST)
  p
}

#' S0's K/D-ST parameters for a league: the frozen quantiles and the league's starting K and D/ST
#' counts. NULL when the league starts neither (S0 then runs as before).
kdst_sim_params <- function(league, v0 = read_kdst_v0()) {
  ns <- league$nonskill_starters %||% list()
  n <- c(K = as.integer(ns[["K"]] %||% 0L), DST = as.integer(ns[["D/ST"]] %||% 0L))
  if (!any(n > 0)) return(NULL)
  list(tau = v0$tau, q = list(K = v0$K, DST = v0$DST), n = n, source = v0$version)
}

#' Inverse-CDF draws from one quantile vector (sim_qdraw's rule: flat beyond the grid, linear inside).
kdst_qdraw <- function(q, u, tau) stats::approx(tau, q, xout = pmin(pmax(u, tau[1]), tau[length(tau)]), ties = "ordered")$y

#' K/D-ST points for `teams` x `W` weeks x `S` simulations from the current RNG state.
kdst_draws <- function(kd, teams, W, S) {
  out <- array(0, c(teams, W, S))
  for (unit in c("K", "DST")) {
    for (r in seq_len(kd$n[[unit]])) {
      out <- out + kdst_qdraw(kd$q[[unit]], stats::runif(teams * W * S), kd$tau)
    }
  }
  out
}
