# S3 live display (pre-registration VL7): per-player values on the owner's roster and a roster risk
# report. SHADOW (S0's engine and label). New functions only; V1/V2 values are shown, never changed.

#' EVOR per player: sum over weeks of P(active) x E[max(0, Y - R_p(w))], where Y follows the frozen P0
#' POD around the if-active level and R_p(w) is V2's waiver level (best free agent's expected points).
#' `A` and `lvl` are players x weeks matrices; `R` is a positions x weeks matrix (row names = positions).
v3_evor <- function(position, A, lvl, R, table) {
  vapply(seq_along(position), function(i) {
    on <- A[i, ] > 0 & lvl[i, ] > 0
    if (!any(on)) return(0)
    q <- pd_quantiles(rep(position[i], sum(on)), lvl[i, on], table)
    sum(A[i, on] * x10b_excess(q, R[position[i], on]))
  }, 0)
}

#' Starting slots a roster cannot fill in each week (no eligible player with positive expected
#' points): byes and absences that would have to be streamed.
v3_holes <- function(m, rows) {
  spec <- val_lineup_spec(m$league)
  pos <- m$sim$players$position
  purrr::map(seq_along(m$sim$weeks), function(wi) {
    e <- m$sim$E[rows, wi]
    used <- rep(FALSE, length(rows))
    miss <- character()
    for (s in spec$slots) {
      for (u in seq_len(s$count)) {
        ok <- which(!used & pos[rows] %in% s$eligible & e > 0)
        if (length(ok)) used[ok[which.max(e[ok])]] <- TRUE else miss <- c(miss, s$name)
      }
    }
    tibble::tibble(week = m$sim$weeks[wi], holes = length(miss), slots = paste(miss, collapse = " "))
  }) |> purrr::list_rbind()
}

#' This week's designated players on a roster with P(active): P1's provider when supplied, otherwise
#' the published prior.
v3_designated <- function(m, rows, prior = read_availability_prior(), p_active_fun = NULL) {
  w <- m$input_data$weekly
  pid <- m$sim$players$player_id[rows]
  cur <- w[w$week == m$current_week & w$player_id %in% pid, ]
  st <- toupper(dplyr::coalesce(as.character(cur$availability_status), ""))
  cur <- cur[!st %in% c("", "ACTIVE", "NORMAL"), ]
  if (!nrow(cur)) return(tibble::tibble(player = character(), position = character(), status = character(), p_active = double()))
  rr <- rows[match(cur$player_id, pid)]
  ps <- m$sim$players$position[rr]
  pa <- if (is.null(p_active_fun)) val_designation_prior(cur$availability_status, prior) else
    p_active_fun(cur$player_id, cur$availability_status, ps)
  tibble::tibble(player = lg_player_label(m, rr), position = ps, status = cur$availability_status, p_active = pa)
}

#' Live values for a team's (non-IR) roster: wins added, P(playoffs) and P(title) values from common-
#' random-number removal on the S0 engine (the vacated slot streamed), EVOR, and V1/V2's VOR and trade
#' value for reference.
v3_live_values <- function(m, state, team, table = read_pod_table(), params = read_s0_params(),
                           prior = read_availability_prior(), sims = 5000L, chunk = 1000L, seed = 20261013L,
                           p_active_fun = NULL) {
  team <- lg_find_team(m, team)
  weeks <- seq(m$current_week, max(m$league$playoff_weeks))
  pid <- m$sim$players$player_id
  team_rows <- lapply(m$state, function(s) s$rows)
  own <- team_rows[[as.character(team)]]
  ids <- unique(pid[unlist(team_rows)])
  pos <- m$sim$players$position[match(ids, pid)]
  uni <- sim_universe(m$input_data$weekly, ids, pos, weeks, m$current_week, prior, p_active_fun)
  to_uni <- function(rows) {
    r <- match(pid[rows], ids)
    r[!is.na(r)]
  }
  base <- lapply(team_rows, to_uni)
  changes <- lapply(own, function(r) list(team = team, rows = to_uni(setdiff(own, r))))
  fa <- lg_fa_levels(m, m$fa_rows)
  stream <- lapply(weeks, function(w) {
    x <- fa[fa$week == w, ]
    stats::setNames(as.list(x$W), x$position)
  }) |> rlang::set_names(as.character(weeks))
  d <- sim_roster_deltas(uni, base, changes, state, val_lineup_spec(m$league), stream, table, params$sigma_L,
                         sims, chunk, seed)
  R <- t(vapply(VAL_POSITIONS, function(p) fa$W[fa$position == p][match(weeks, fa$week[fa$position == p])], numeric(length(weeks))))
  R[is.na(R)] <- 0
  if (length(weeks) == 1) R <- matrix(R, ncol = 1, dimnames = list(VAL_POSITIONS, NULL))
  k <- to_uni(own)
  ev <- v3_evor(uni$position[k], uni$A[k, , drop = FALSE], uni$lvl[k, , drop = FALSE], R, table)
  g <- m$generic
  gi <- if (is.null(g)) rep(NA_integer_, length(own)) else match(pid[own], g$player_id)
  tibble::tibble(row = as.integer(own), player = lg_player_label(m, own), position = m$sim$players$position[own],
                 wins_added = -d$d_wins, playoffs_value = -d$d_playoffs, title_value = -d$d_title, evor = ev,
                 vor = if (is.null(g)) NA_real_ else g$vor[gi], trade_value = if (is.null(g)) NA_real_ else g$trade_value[gi],
                 sum_p_playoffs = d$sum_p_playoffs, sum_p_title = d$sum_p_title) |>
    dplyr::arrange(dplyr::desc(.data$wins_added), .data$row)
}

#' Roster risk report (VL7): concentration (share of expected lineup points from the top two players;
#' the largest removal P(playoffs) value), coverage holes by week, and this week's designated players.
v3_roster_risk <- function(m, team, values, prior = read_availability_prior(), p_active_fun = NULL) {
  team <- lg_find_team(m, team)
  s <- m$state[[as.character(team)]]
  a <- lg_attribution(m, c(s$rows, s$ir_rows))
  sp <- sort(a$players$started_pts, decreasing = TRUE)
  holes <- v3_holes(m, s$rows)
  list(top2_share = if (sum(sp) > 0) sum(utils::head(sp, 2)) / sum(sp) else NA_real_,
       max_playoffs_value = if (nrow(values)) max(values$playoffs_value) else NA_real_,
       holes = holes[holes$holes > 0, ],
       designated = v3_designated(m, s$rows, prior, p_active_fun))
}
