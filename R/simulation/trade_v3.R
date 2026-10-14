# D2 trade engine v3 (pre-registration VL12): the ΔP(title) decomposition, the Nash product (fairness
# summary only), buy-low / sell-high signals, explanations from model numbers, and X11's ΔU vs ΔP
# divergence analysis (outcome-free). SHADOW, on the S0 engine like the thin slice.

D2_SIGNAL_THRESHOLD <- 0.10      # model vs raw ESPN rest-of-season points
D2_SIGNAL_MIN_PPG <- 8           # relevant players: raw ESPN points per game played

#' Exact two-factor split of ΔP(title) = Δ[P(playoffs) · P(title | playoffs)] for one side ("a" or "b")
#' of sim_trade_deltas() output: qualification = Δx · mean(y), playoff strength = mean(x) · Δy.
trade_title_decomposition <- function(d, side = "a") {
  x0 <- d[[paste0("p_playoffs_", side, "0")]]
  x1 <- d[[paste0("p_playoffs_", side, "1")]]
  t0 <- d[[paste0("p_title_", side, "0")]]
  t1 <- d[[paste0("p_title_", side, "1")]]
  y0 <- ifelse(x0 > 0, t0 / x0, 0)
  y1 <- ifelse(x1 > 0, t1 / x1, 0)
  tibble::tibble(qualification = (x1 - x0) * (y0 + y1) / 2, playoff_strength = (x0 + x1) / 2 * (y1 - y0))
}

#' Nash product of the two sides' P(playoffs) gains (a fairness summary, not an acceptance model).
trade_nash <- function(d) pmax(0, d$d_playoffs_a) * pmax(0, d$d_playoffs_b)

#' One explanation line per re-scored trade, from model numbers only.
trade_explain <- function(d) {
  dec <- trade_title_decomposition(d, "a")
  f <- function(x, k = 3) formatC(x, format = "f", digits = k, flag = "+")
  paste0("Your P(playoffs) ", f(d$d_playoffs_a), " and P(title) ", f(d$d_title_a), " (qualification ",
         f(dec$qualification), ", playoff strength ", f(dec$playoff_strength), "); partner P(playoffs) ",
         f(d$d_playoffs_b), "; partner's generic view ", f(d$partner_lens_b, 1), "; utility ", f(d$v2_delta_a, 1),
         " for you, ", f(d$v2_delta_b, 1), " for them; Nash ", formatC(trade_nash(d), format = "f", digits = 4), ".")
}

#' Buy-low / sell-high signals: rostered players whose model rest-of-season points (calibrated) differ
#' from the raw ESPN posted rest-of-season points by more than `threshold`, among players with raw
#' >= `min_ppg` points per game played. Buy-low: other rosters, model above raw; sell-high: `me`'s roster,
#' model below raw.
d2_buy_sell <- function(m, me, threshold = D2_SIGNAL_THRESHOLD, min_ppg = D2_SIGNAL_MIN_PPG) {
  me <- lg_find_team(m, me)
  w <- m$input_data$weekly
  w <- w[w$week %in% m$sim$weeks, ]
  agg <- dplyr::summarise(w, model = sum(.data$proj), raw = sum(.data$proj_raw, na.rm = TRUE),
                          games = sum(.data$has_game), .by = "player_id")
  own <- lg_owner(m)
  pid <- m$sim$players$player_id
  rows <- which(!is.na(own))
  x <- tibble::tibble(row = rows, player = lg_player_label(m, rows), position = m$sim$players$position[rows],
                      team_id = own[rows]) |>
    dplyr::left_join(dplyr::mutate(agg, row = match(.data$player_id, pid)), by = "row") |>
    dplyr::filter(.data$games > 0, .data$raw / .data$games >= min_ppg) |>
    dplyr::mutate(ratio = .data$model / .data$raw - 1,
                  signal = dplyr::case_when(.data$team_id != me & .data$ratio > threshold ~ "buy_low",
                                            .data$team_id == me & .data$ratio < -threshold ~ "sell_high",
                                            TRUE ~ NA_character_))
  dplyr::arrange(x[!is.na(x$signal), c("row", "player", "position", "team_id", "model", "raw", "ratio", "signal")],
                 .data$signal, dplyr::desc(abs(.data$ratio)))
}

#' Agreement of two rankings of the same candidates: Kendall tau, top-1 and top-3 set disagreement.
x11_agreement <- function(u, p) {
  n <- length(u)
  tau <- if (n >= 2 && stats::sd(u) > 0 && stats::sd(p) > 0) stats::cor(u, p, method = "kendall") else NA_real_
  k <- min(3L, n)
  tibble::tibble(n = n, tau = tau, top1_differs = which.max(u) != which.max(p),
                 top3_differs = !setequal(order(-u)[seq_len(k)], order(-p)[seq_len(k)]))
}

#' X11 (VL12): for every ordered team pair, V2's top `k` candidates re-scored on the S0 engine with two
#' seeds; per-list agreement of ΔU_A with ΔP(playoffs)_A and ΔP(title)_A, the seed-to-seed noise floor,
#' and A's current state (contender / bubble / out from S0 P(playoffs)). Team ids only.
x11_divergence <- function(m, state, k = 10L, sims = 2000L, seeds = c(20261013L, 20261014L), odds_sims = 10000L,
                           p_active_fun = NULL) {
  la <- m$la
  s <- la$search
  od <- sim_league_odds(m, state, sims = odds_sims, p_active_fun = p_active_fun)
  po <- od$results$base$teams
  teams <- as.integer(names(m$state))
  pairs <- tidyr::expand_grid(a = teams, b = teams)
  pairs <- pairs[pairs$a != pairs$b, ]
  purrr::map(seq_len(nrow(pairs)), function(i) {
    ta <- pairs$a[i]
    tb <- pairs$b[i]
    r <- lg_trade_search(m, ta, tb, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                         eps = la$eps, strong = la$strong, horizon = "full")
    if (nrow(r) < 3) return(NULL)
    top <- utils::head(r, k)
    trades <- lapply(seq_len(nrow(top)), function(j) list(team_a = ta, give_a = top$a_rows[[j]], team_b = tb,
                                                          give_b = top$b_rows[[j]]))
    d1 <- sim_trade_rescore(m, state, trades, sims = sims, seed = seeds[1], p_active_fun = p_active_fun)
    d2 <- sim_trade_rescore(m, state, trades, sims = sims, seed = seeds[2], p_active_fun = p_active_fun)
    p_a <- po$p_playoffs[match(ta, po$team_id)]
    dplyr::bind_cols(
      tibble::tibble(team_a = ta, team_b = tb, p_playoffs_a = p_a,
                     state = dplyr::case_when(p_a >= 0.75 ~ "contender", p_a >= 0.25 ~ "bubble", TRUE ~ "out")),
      dplyr::rename_with(x11_agreement(d1$v2_delta_a, d1$d_playoffs_a), ~ paste0(.x, "_playoffs")),
      dplyr::rename_with(x11_agreement(d1$v2_delta_a, d1$d_title_a), ~ paste0(.x, "_title")),
      dplyr::rename_with(x11_agreement(d1$d_playoffs_a, d2$d_playoffs_a), ~ paste0(.x, "_seed_playoffs")),
      dplyr::rename_with(x11_agreement(d1$d_title_a, d2$d_title_a), ~ paste0(.x, "_seed_title")))
  }) |> purrr::list_rbind()
}

#' X11 summary: means and shares overall and by A's state.
x11_summary <- function(rows) {
  f <- function(x) dplyr::summarise(x, lists = dplyr::n(), candidates = mean(.data$n_playoffs),
                                    tau_playoffs = mean(.data$tau_playoffs, na.rm = TRUE),
                                    tau_title = mean(.data$tau_title, na.rm = TRUE),
                                    top1_differs_playoffs = mean(.data$top1_differs_playoffs),
                                    top1_differs_title = mean(.data$top1_differs_title),
                                    top3_differs_playoffs = mean(.data$top3_differs_playoffs),
                                    top3_differs_title = mean(.data$top3_differs_title),
                                    noise_top1_playoffs = mean(.data$top1_differs_seed_playoffs),
                                    noise_top1_title = mean(.data$top1_differs_seed_title),
                                    noise_tau_playoffs = mean(.data$tau_seed_playoffs, na.rm = TRUE))
  list(overall = f(rows), by_state = dplyr::arrange(f(dplyr::group_by(rows, .data$state)), .data$state))
}
