# X22 (pre-registration E23, amendment E23a): K and D/ST distributions for lineup totals ------------
# E21's lineups and skill draws, plus one K unit and one D/ST unit per team-week (NFL teams drawn among
# those playing that week). v0 = position-level empirical quantiles; conditioned = quantiles within
# tertiles of the closing implied total (own for K, opponent's for D/ST). E21's coverage gate decides.

X22_UNIT_SEASONS <- 2019:2023

#' Team-game K and D/ST points (league scoring) with the closing implied totals.
x22_units <- function(team_k, dst_week, team_games, seasons = X22_UNIT_SEASONS) {
  tg <- dplyr::select(team_games, "season", "week", "team", "opponent", "implied_team_total")
  tg <- tg[tg$season %in% seasons, ]
  opp <- dplyr::select(tg, "season", "week", opponent = "team", opp_implied = "implied_team_total")
  tg |>
    dplyr::left_join(dplyr::select(team_k, "season", "week", "team", "k_points"), by = c("season", "week", "team")) |>
    dplyr::left_join(dplyr::select(dst_week, "season", "week", "team", "dst_points"), by = c("season", "week", "team")) |>
    dplyr::left_join(opp, by = c("season", "week", "opponent")) |>
    dplyr::filter(!is.na(.data$k_points), !is.na(.data$dst_points))
}

#' Fit v0 and conditioned K/D-ST quantiles on the training seasons (E21's tau grid).
x22_fit <- function(units, train_seasons, tau = P2_TAU) {
  tr <- units[units$season %in% train_seasons, ]
  q <- function(v) stats::quantile(v, tau, names = FALSE)
  med <- c(K = stats::median(tr$implied_team_total, na.rm = TRUE), DST = stats::median(tr$opp_implied, na.rm = TRUE))
  ik <- dplyr::coalesce(tr$implied_team_total, med[["K"]])
  id <- dplyr::coalesce(tr$opp_implied, med[["DST"]])
  edges <- list(K = stats::quantile(ik, c(1, 2) / 3, names = FALSE), DST = stats::quantile(id, c(1, 2) / 3, names = FALSE))
  bk <- findInterval(ik, edges$K) + 1L
  bd <- findInterval(id, edges$DST) + 1L
  list(tau = tau, median = med, edges = edges,
       v0 = list(K = q(tr$k_points), DST = q(tr$dst_points)),
       cond = list(K = lapply(1:3, function(b) q(tr$k_points[bk == b])), DST = lapply(1:3, function(b) q(tr$dst_points[bd == b]))))
}

#' Coverage, PIT and moments of a simulated total against the realised value.
x22_score <- function(tot, realised, prefix) {
  sims <- length(tot)
  lo <- function(l) stats::quantile(tot, (1 - l) / 2, names = FALSE)
  hi <- function(l) stats::quantile(tot, (1 + l) / 2, names = FALSE)
  out <- tibble::tibble(realised = realised, pit = (sum(tot < realised) + stats::runif(1) * sum(tot == realised)) / sims,
                        cover50 = realised >= lo(0.5) & realised <= hi(0.5), cover80 = realised >= lo(0.8) & realised <= hi(0.8),
                        cover90 = realised >= lo(0.9) & realised <= hi(0.9), mean_sim = mean(tot), var_sim = stats::var(tot))
  names(out) <- paste0(prefix, "_", names(out))
  out
}

#' Gate rows for one season: per lineup, the skill-only total and the totals with v0 and conditioned K/D-ST.
x22_gate_season <- function(frame_all, lineups, active_table, units, fit, sims = P3_SIMS, seed = 21L) {
  s <- lineups$season[1]
  train <- frame_all[frame_all$season < s & frame_all$active, ]
  rows <- frame_all[frame_all$season == s, ]
  key <- paste(rows$week, rows$gsis_id)
  q <- p3_candidate_q("C0", train, rows)
  p_act <- lab_p_active(rows$position, rows$base, active_table)
  us <- units[units$season == s, ]
  by_week <- split(seq_len(nrow(us)), us$week)
  pick <- withr::with_seed(seed * 7L + s, t(vapply(seq_len(nrow(lineups)), function(i) {
    cand <- by_week[[as.character(lineups$week[i])]]
    cand[sample.int(length(cand), 2L, replace = TRUE)]
  }, integer(2))))
  tau <- fit$tau
  qmat <- function(v) matrix(v, sims, length(tau), byrow = TRUE)
  band <- function(v, unit) findInterval(dplyr::coalesce(v, fit$median[[unit]]), fit$edges[[unit]]) + 1L
  set.seed(seed + s)
  out <- purrr::map(seq_len(nrow(lineups)), function(i) {
    k <- match(paste(lineups$week[i], lineups$starters[[i]]), key)
    k <- k[!is.na(k)]
    real_skill <- if (length(k)) sum(rows$y[k]) else 0
    tot <- if (length(k)) {
      u <- matrix(stats::runif(length(k) * sims), length(k), sims)
      a <- matrix(stats::runif(length(k) * sims), length(k), sims) < p_act[k]
      colSums(matrix(sim_qdraw(q[rep(k, times = sims), , drop = FALSE], as.vector(u), tau), length(k), sims) * a)
    } else numeric(sims)
    ku <- us[pick[i, 1], ]
    du <- us[pick[i, 2], ]
    uk <- stats::runif(sims)
    ud <- stats::runif(sims)
    k0 <- sim_qdraw(qmat(fit$v0$K), uk, tau)
    d0 <- sim_qdraw(qmat(fit$v0$DST), ud, tau)
    kc <- sim_qdraw(qmat(fit$cond$K[[band(ku$implied_team_total, "K")]]), uk, tau)
    dc <- sim_qdraw(qmat(fit$cond$DST[[band(du$opp_implied, "DST")]]), ud, tau)
    real_all <- real_skill + ku$k_points + du$dst_points
    dplyr::bind_cols(tibble::tibble(starters = length(k), k_points = ku$k_points, dst_points = du$dst_points),
                     x22_score(tot, real_skill, "none"), x22_score(tot + k0 + d0, real_all, "v0"),
                     x22_score(tot + kc + dc, real_all, "cond"))
  }) |>
    purrr::list_rbind()
  dplyr::bind_cols(lineups[c("season", "league", "n_teams", "team", "week")], out)
}

#' E21's gate for each variant (none = skill only, v0, conditioned) over lineups with starters.
x22_gate <- function(rows, register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", unique(rows$season), "development", register)
  rows <- rows[rows$starters > 0, ]
  purrr::map(c("none", "v0", "cond"), function(v) {
    x <- rows[c("season", "week", "n_teams", paste0(v, "_", c("realised", "pit", "cover50", "cover80", "cover90", "mean_sim", "var_sim")))]
    names(x) <- sub(paste0("^", v, "_"), "", names(x))
    x$stack <- FALSE
    g <- p3_gate(x)
    list(variant = v, cells = g$cells, fails = g$gate_fails, variance_ratio = g$variance_ratio, pit_hist = g$pit_hist,
         by_league_size = g$by_league_size)
  }) |> rlang::set_names(c("none", "v0", "cond"))
}
