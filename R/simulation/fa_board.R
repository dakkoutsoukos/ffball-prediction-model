# D3 (VL9): free-agent board, drop advice and streaming view. SHADOW, like S0 and the S2/D2 thin slice.
# The owner's league has no acquisition budget (F3-lite: isUsingAcquisitionBudget = FALSE), so claims go
# by waiver priority and no FAAB bids are modelled. New functions only; V2 is reused, not changed.

#' Streaming status per VL9: the tool recommends streaming only if X16's development CI excluded 0
#' in streaming's favour. Set from the recorded VL9 result.
D3_STREAMING_RECOMMENDED <- FALSE

#' V2's utility screen for free-agent adds: the best `cand_per_pos` free agents per position by
#' rest-of-season points, each added with V2's forced drop (lg_resolve). Returns the rows, the
#' resulting roster and the utility change dU, best first; adds that gain nothing are dropped.
d3_fa_screen <- function(m, team, cand_per_pos = 6L) {
  team <- lg_find_team(m, team)
  s <- m$state[[as.character(team)]]
  pos <- m$sim$players$position
  fa <- unlist(lapply(m$spec$positions, function(p) {
    r <- m$fa_rows[pos[m$fa_rows] == p]
    r[order(-m$sim$ros[r], r)][seq_len(min(length(r), cand_per_pos))]
  }))
  empty <- tibble::tibble(add_row = integer(), add = character(), position = character(), drop_rows = list(),
                          drop = character(), new_rows = list(), dU = double())
  if (!length(fa)) return(empty)
  u0 <- m$base[[as.character(team)]]$U
  out <- purrr::map(fa, function(f) {
    r <- lg_resolve(m, team, c(s$rows, f), s$ir_rows, setdiff(m$fa_rows, f), m$stream, allow_adds = FALSE)
    tibble::tibble(add_row = as.integer(f), add = lg_player_label(m, f), position = pos[f], drop_rows = list(as.integer(r$dropped)),
                   drop = paste(lg_player_label(m, r$dropped), collapse = " + "), new_rows = list(as.integer(r$rows)),
                   dU = lg_value(m, c(r$rows, s$ir_rows))$U - u0)
  }) |> purrr::list_rbind()
  kept <- vapply(seq_len(nrow(out)), function(i) !out$add_row[i] %in% out$drop_rows[[i]], TRUE)
  out <- out[out$dU > 1e-6 & kept, ]
  out[order(-out$dU, out$add_row), ]
}

#' Drop advice: the rostered (non-IR) players whose removal costs the least utility (V2's dU, with
#' the league's streaming policy filling any hole), cheapest first.
d3_drop_advice <- function(m, team, n = 3L) {
  team <- lg_find_team(m, team)
  s <- m$state[[as.character(team)]]
  u0 <- m$base[[as.character(team)]]$U
  out <- purrr::map(s$rows, function(r) {
    tibble::tibble(row = as.integer(r), player = lg_player_label(m, r), position = m$sim$players$position[r],
                   cost = u0 - lg_value(m, c(setdiff(s$rows, r), s$ir_rows))$U)
  }) |> purrr::list_rbind()
  utils::head(out[order(out$cost, out$row), ], n)
}

#' Streaming view for one week: per position, the best `n` free agents by that week's expected points
#' (posted, calibrated projection x P(active), with P1's provider when supplied) and the change in the
#' team's optimal lineup for that week if he were added (no drop; no streaming of other players).
d3_stream_view <- function(m, team, week = m$current_week, n = 5L, prior = read_availability_prior(),
                           p_active_fun = NULL, min_gain = 1) {
  team <- lg_find_team(m, team)
  s <- m$state[[as.character(team)]]
  pos <- m$sim$players$position
  pid <- m$sim$players$player_id
  cand <- unlist(lapply(m$spec$positions, function(p) m$fa_rows[pos[m$fa_rows] == p]))
  rows <- c(s$rows, cand)
  uni <- sim_universe(m$input_data$weekly, pid[rows], pos[rows], week, m$current_week, prior, p_active_fun)
  e <- matrix(uni$A[, 1] * uni$lvl[, 1], ncol = 1)
  spec <- val_lineup_spec(m$league)
  own <- seq_along(s$rows)
  value <- function(idx) sim_team_week(idx, e, e, uni$position, spec, list())
  v0 <- value(own)
  out <- purrr::map(seq_along(cand), function(k) {
    i <- length(s$rows) + k
    tibble::tibble(row = as.integer(cand[k]), player = lg_player_label(m, cand[k]), position = pos[cand[k]],
                   expected = e[i, 1], gain = value(c(own, i)) - v0)
  }) |> purrr::list_rbind()
  out <- dplyr::slice_head(dplyr::arrange(out, dplyr::desc(.data$expected), .data$row), n = n, by = "position")
  dplyr::mutate(out, week = as.integer(week), stream_candidate = .data$gain > min_gain,
                status = if (D3_STREAMING_RECOMMENDED) "recommended (X16)" else "informational (X16 not supported)")
}

#' Common-random-number deltas of roster changes on the S0 engine: each change is list(team, rows)
#' (universe rows replacing that team's roster). Returns the team's change in expected wins,
#' P(playoffs) and P(title) against the unchanged league, with the invariants' sums.
sim_roster_deltas <- function(uni, base_config, changes, state, spec, stream, table, sigma, sims = 10000L,
                              chunk = 1000L, seed = 20261013L) {
  configs <- c(list(base = base_config), lapply(changes, function(ch) {
    cfg <- base_config
    cfg[[as.character(ch$team)]] <- ch$rows
    cfg
  }))
  names(configs) <- c("base", paste0("change", seq_along(changes)))
  scores <- sim_scores(uni, configs, spec, stream, table, sigma, sims, chunk, seed)
  cp <- state$status$current_matchup_period
  summ <- lapply(scores, function(sc) sim_summarise(sim_resolve(sc, state, cp))$teams)
  b <- summ$base
  purrr::map(seq_along(changes), function(k) {
    a <- summ[[k + 1]]
    t <- as.integer(changes[[k]]$team)
    i <- match(t, a$team_id)
    j <- match(t, b$team_id)
    tibble::tibble(change = k, team = t, d_wins = a$e_wins[i] - b$e_wins[j], d_playoffs = a$p_playoffs[i] - b$p_playoffs[j],
                   d_title = a$p_title[i] - b$p_title[j], sum_p_playoffs = sum(a$p_playoffs), sum_p_title = sum(a$p_title))
  }) |> purrr::list_rbind()
}

#' Owner's league wrapper: the top `k` adds of the utility screen re-scored by the team's change in
#' P(playoffs) and P(title) (common random numbers; streaming levels from the current free-agent pool,
#' as in V2 and the thin slice).
sim_fa_rescore <- function(m, state, team, screen, k = 8L, table = read_pod_table(), params = read_s0_params(),
                           prior = read_availability_prior(), sims = 5000L, chunk = 1000L, seed = 20261013L,
                           p_active_fun = NULL) {
  team <- lg_find_team(m, team)
  top <- utils::head(screen, k)
  if (!nrow(top)) return(dplyr::mutate(top, d_wins = double(), d_playoffs = double(), d_title = double()))
  weeks <- seq(m$current_week, max(m$league$playoff_weeks))
  pid <- m$sim$players$player_id
  team_rows <- lapply(m$state, function(s) s$rows)
  ids <- unique(c(pid[unlist(team_rows)], pid[top$add_row]))
  pos <- m$sim$players$position[match(ids, pid)]
  uni <- sim_universe(m$input_data$weekly, ids, pos, weeks, m$current_week, prior, p_active_fun)
  to_uni <- function(rows) {
    r <- match(pid[rows], ids)
    r[!is.na(r)]
  }
  base <- lapply(team_rows, to_uni)
  changes <- lapply(top$new_rows, function(r) list(team = team, rows = to_uni(r)))
  fa <- lg_fa_levels(m, m$fa_rows)
  stream <- lapply(weeks, function(w) {
    x <- fa[fa$week == w, ]
    stats::setNames(as.list(x$W), x$position)
  }) |> rlang::set_names(as.character(weeks))
  d <- sim_roster_deltas(uni, base, changes, state, val_lineup_spec(m$league), stream, table, params$sigma_L,
                         sims, chunk, seed)
  dplyr::bind_cols(top, dplyr::select(d, "d_wins", "d_playoffs", "d_title", "sum_p_playoffs", "sum_p_title"))
}
