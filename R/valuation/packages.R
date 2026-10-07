# Valuation: packages and consolidation -----------------------------------------------------
# A 2-for-1 trade is not A = B + C. The team receiving one player (A) frees a
# roster spot and adds the best free player; the team receiving two must drop
# its least valuable player. Lineup slots also limit how much of B + C can be
# used. val_trade_eval() (simulation.R) evaluates exactly that on a generic
# simulated team; here we study it systematically against naive sums.

#' Naive package values: sums of ROS VOR and of display trade value.
val_package_naive <- function(values, ids) {
  v <- values[match(ids, values$player_id), ]
  c(vor = sum(v$vor), trade_value = sum(v$trade_value))
}

#' Consolidation study on the generic league. For each of the `n_elite`
#' highest-VOR rostered players A (owned by team Y) and each other team X,
#' take the pair (B, C) on X's roster, both with lower VOR than A, whose VOR
#' sum is closest to A's (within `tol`). Evaluate both sides with roster-spot
#' accounting:
#'   X: gives B + C, gets A, adds the best free player for the freed spot
#'   Y: gives A, gets B + C, drops its least valuable player
#' Returns one row per trade with naive sums and utility changes. A positive
#' `consolidation_edge` (X's gain minus Y's gain) means the side receiving the
#' single better player gains more than VOR sums suggest.
val_consolidation_study <- function(ls, values, n_elite = 15, tol = 0.15, max_trades = 40) {
  sim <- ls$sim
  vrow <- match(sim$players$player_id, values$player_id)
  vor <- values$vor[vrow]
  tv <- values$trade_value[vrow]
  ros <- ls$rosters
  ros$vor <- vor[ros$row]
  elite <- ros[order(-ros$vor), ][seq_len(min(n_elite, nrow(ros))), ]
  trades <- list()
  for (a in seq_len(nrow(elite))) {
    A <- elite$row[a]
    Y <- elite$team[a]
    for (X in setdiff(seq_len(ls$league$teams), Y)) {
      r <- ros[ros$team == X & ros$vor < elite$vor[a] & ros$vor > 0, ]
      if (nrow(r) < 2) next
      pr <- utils::combn(seq_len(nrow(r)), 2)
      s <- r$vor[pr[1, ]] + r$vor[pr[2, ]]
      j <- which.min(abs(s - elite$vor[a]))
      if (abs(s[j] - elite$vor[a]) > tol * elite$vor[a]) next
      trades[[length(trades) + 1]] <- list(A = A, Y = Y, X = X, B = r$row[pr[1, j]], C = r$row[pr[2, j]])
    }
  }
  if (!length(trades)) return(tibble::tibble())
  # spread over elites: at most ceiling(max_trades / n_elite) per A, deterministic
  per <- ceiling(max_trades / max(1, nrow(elite)))
  keep <- unlist(lapply(split(seq_along(trades), vapply(trades, `[[`, 0, "A")), utils::head, per))
  trades <- trades[sort(keep)][seq_len(min(max_trades, length(keep)))]
  purrr::map(trades, function(t) {
    ex <- val_trade_eval(ls, t$X, give = c(t$B, t$C), get = t$A)
    ey <- val_trade_eval(ls, t$Y, give = t$A, get = c(t$B, t$C))
    id <- function(i) sim$players$player_id[i]
    tibble::tibble(
      A = id(t$A), B = id(t$B), C = id(t$C), team_single = t$X, team_pair = t$Y,
      vor_A = vor[t$A], vor_BC = vor[t$B] + vor[t$C], tv_A = tv[t$A], tv_BC = tv[t$B] + tv[t$C],
      gain_single_side = ex$delta, gain_pair_side = ey$delta,
      single_side_added = paste(id(ex$added), collapse = "+"), pair_side_dropped = paste(id(ey$dropped), collapse = "+"),
      consolidation_edge = ex$delta - ey$delta
    )
  }) |>
    purrr::list_rbind()
}
