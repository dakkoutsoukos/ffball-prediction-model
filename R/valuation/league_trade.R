# Valuation V2: before/after trade simulation ------------------------------------------------
# A trade is evaluated by re-optimizing both rosters:
#   before  U_A, U_B on the current rosters
#   apply   transfer the players
#   resolve forced drops (greedy, maximizing U) for teams over their roster limit,
#           dropped players join the free-agent pool; then fill open spots with the
#           free agent that adds the most U (only if it adds anything)
#   after   U_A', U_B' with the post-transaction free-agent pool
#   delta   U' - U per team (full ROS, regular season, playoffs)
# Fairness metrics and the classification thresholds were fixed before any real
# trade was analysed (research/valuation_log.md, VL0).

LG_CLASSES <- c("harmful to both", "strong win-win", "mild win-win", "balanced", "strongly favors A", "favors A",
                "strongly favors B", "favors B")

#' Descriptive classification from the two utility changes (rules in order).
lg_classify <- function(dA, dB, eps = 5, strong = 20) {
  dplyr::case_when(
    dA < -eps & dB < -eps ~ "harmful to both",
    dA > strong & dB > strong ~ "strong win-win",
    dA > eps & dB > eps ~ "mild win-win",
    abs(dA - dB) <= eps ~ "balanced",
    dA - dB > strong ~ "strongly favors A",
    dA - dB > eps ~ "favors A",
    dB - dA > strong ~ "strongly favors B",
    TRUE ~ "favors B"
  )
}

lg_generic <- function(m, rows) {
  g <- m$generic
  if (is.null(g)) return(c(vor = NA_real_, trade_value = NA_real_))
  i <- match(m$sim$players$player_id[rows], g$player_id)
  c(vor = sum(g$vor[i], na.rm = TRUE), trade_value = sum(g$trade_value[i], na.rm = TRUE))
}

#' Apply a transaction and resolve rosters; returns the post-trade states and
#' the free-agent pool. Shared by lg_trade() and the search functions.
lg_apply_trade <- function(m, team_a, give_a, team_b, give_b, cand_per_pos = 6) {
  sa <- m$state[[as.character(team_a)]]
  sb <- m$state[[as.character(team_b)]]
  move <- function(s, give, get, other) {
    ir_free <- (m$league$ir_slots %||% 0) - length(setdiff(s$ir_rows, give))
    get_ir <- intersect(get, other$ir_rows)
    to_ir <- get_ir[seq_len(min(length(get_ir), max(0, ir_free)))]
    list(rows = c(setdiff(s$rows, give), setdiff(get, to_ir)), ir_rows = c(setdiff(s$ir_rows, give), to_ir))
  }
  na <- move(sa, give_a, give_b, sb)
  nb <- move(sb, give_b, give_a, sa)
  fa <- m$fa_rows
  # 1) forced drops for both teams (decided with the current free-agent levels)
  ra <- lg_resolve(m, team_a, na$rows, na$ir_rows, fa, m$stream, cand_per_pos, allow_adds = FALSE)
  rb <- lg_resolve(m, team_b, nb$rows, nb$ir_rows, fa, m$stream, cand_per_pos, allow_adds = FALSE)
  fa <- c(fa, ra$dropped, rb$dropped)
  st <- lg_stream(m, fa)
  # 2) open spots filled from the updated pool (team A first, then team B)
  aa <- lg_resolve(m, team_a, ra$rows, na$ir_rows, fa, st, cand_per_pos)
  fa <- aa$fa_rows
  ab <- lg_resolve(m, team_b, rb$rows, nb$ir_rows, fa, lg_stream(m, fa), cand_per_pos)
  fa <- ab$fa_rows
  list(a = list(rows = aa$rows, ir_rows = na$ir_rows, dropped = ra$dropped, drop_cost = ra$drop_cost,
                added = aa$added, add_gain = aa$add_gain),
       b = list(rows = ab$rows, ir_rows = nb$ir_rows, dropped = rb$dropped, drop_cost = rb$drop_cost,
                added = ab$added, add_gain = ab$add_gain),
       fa_rows = fa, stream = lg_stream(m, fa))
}

#' Validate a proposed trade; returns player rows.
lg_validate_trade <- function(m, team_a, give_a, team_b, give_b) {
  if (team_a == team_b) cli::cli_abort("A team cannot trade with itself.")
  if (!length(give_a) || !length(give_b)) cli::cli_abort("Both teams must send at least one player.")
  ga <- vapply(give_a, function(x) lg_find_player(m, x), 1L)
  gb <- vapply(give_b, function(x) lg_find_player(m, x), 1L)
  if (anyDuplicated(c(ga, gb))) cli::cli_abort("A player appears twice in the trade.")
  own <- function(t) { s <- m$state[[as.character(t)]]; c(s$rows, s$ir_rows) }
  if (!all(ga %in% own(team_a))) cli::cli_abort("{lg_team_label(m, team_a)} does not own {.val {lg_player_label(m, setdiff(ga, own(team_a)))}}.")
  if (!all(gb %in% own(team_b))) cli::cli_abort("{lg_team_label(m, team_b)} does not own {.val {lg_player_label(m, setdiff(gb, own(team_b)))}}.")
  list(a = unname(ga), b = unname(gb))
}

#' Invariants of a resolved trade (fail loudly if any is violated).
lg_check_invariants <- function(m, tr, team_a, ga, team_b, gb) {
  ra <- c(tr$a$rows, tr$a$ir_rows)
  rb <- c(tr$b$rows, tr$b$ir_rows)
  others <- unlist(lapply(m$state[setdiff(names(m$state), as.character(c(team_a, team_b)))], function(s) c(s$rows, s$ir_rows)))
  all_r <- c(ra, rb, others)
  stopifnot(
    "traded players left their team" = !any(ga %in% ra) && !any(gb %in% rb),
    "received players are on the new team once (unless dropped)" =
      all(setdiff(gb, tr$a$dropped) %in% ra) && all(setdiff(ga, tr$b$dropped) %in% rb),
    "no player on two teams" = !anyDuplicated(all_r),
    "adds were free agents" = !any(c(tr$a$added, tr$b$added) %in% c(m$state[[as.character(team_a)]]$rows,
                                                                    m$state[[as.character(team_b)]]$rows, others)),
    "dropped players are free agents" = all(c(tr$a$dropped, tr$b$dropped) %in% tr$fa_rows),
    "roster sizes are legal" = length(tr$a$rows) <= lg_capacity(m, team_a) && length(tr$b$rows) <= lg_capacity(m, team_b),
    "position limits are met" = !length(lg_over_limits(m, tr$a$rows, team_a)) && !length(lg_over_limits(m, tr$b$rows, team_b))
  )
  invisible(TRUE)
}

#' Analyze a trade: team_a sends give_a, team_b sends give_b (player names, ESPN ids or rows).
lg_trade <- function(m, team_a, give_a, team_b, give_b, eps = 5, strong = 20, explain = TRUE,
                     horizon = c("full", "regular", "playoffs")) {
  horizon <- match.arg(horizon)
  team_a <- lg_find_team(m, team_a)
  team_b <- lg_find_team(m, team_b)
  g <- lg_validate_trade(m, team_a, give_a, team_b, give_b)
  tr <- lg_apply_trade(m, team_a, g$a, team_b, g$b)
  lg_check_invariants(m, tr, team_a, g$a, team_b, g$b)
  side <- function(team, s_after, gives, gets) {
    before <- m$base[[as.character(team)]]
    after <- lg_value(m, c(s_after$rows, s_after$ir_rows), tr$stream)
    gg <- lg_generic(m, gives)
    gr <- lg_generic(m, gets)  # computed first: tibble() columns below shadow `gives`/`gets`
    tibble::tibble(
      team_id = team, team = lg_team_label(m, team),
      gives = paste(lg_player_label(m, gives), collapse = " + "), gets = paste(lg_player_label(m, gets), collapse = " + "),
      U_before = before$U, U_after = after$U, delta = after$U - before$U,
      delta_regular = after$regular - before$regular, delta_playoffs = after$playoffs - before$playoffs,
      dropped = paste(lg_player_label(m, s_after$dropped), collapse = " + "),
      drop_cost = sum(s_after$drop_cost), added = paste(lg_player_label(m, s_after$added), collapse = " + "),
      add_gain = sum(s_after$add_gain),
      generic_vor_gives = gg[["vor"]], generic_vor_gets = gr[["vor"]],
      tv_gives = gg[["trade_value"]], tv_gets = gr[["trade_value"]]
    )
  }
  sa <- side(team_a, tr$a, g$a, g$b)
  sb <- side(team_b, tr$b, g$b, g$a)
  pick <- function(x) switch(horizon, full = x$delta, regular = x$delta_regular, playoffs = x$delta_playoffs)
  dA <- pick(sa)
  dB <- pick(sb)
  metrics <- tibble::tibble(horizon = horizon,
    team_a = sa$team, team_b = sb$team, delta_a = dA, delta_b = dB, surplus = dA + dB, balance = dA - dB,
    generic_vor_net_a = sa$generic_vor_gets - sa$generic_vor_gives,
    generic_tv_net_a = sa$tv_gets - sa$tv_gives,
    consolidation_a = dA - (sa$generic_vor_gets - sa$generic_vor_gives),
    consolidation_b = dB - (sb$generic_vor_gets - sb$generic_vor_gives),
    classification = lg_classify(dA, dB, eps, strong),
    horizon_weeks = paste(range(m$weeks), collapse = "-"), policy = m$policy
  )
  out <- list(teams = dplyr::bind_rows(sa, sb), metrics = metrics, transaction = tr, gives = g)
  if (explain) {
    out$lineups <- list(a = lg_lineup_change(m, team_a, tr$a, tr$stream), b = lg_lineup_change(m, team_b, tr$b, tr$stream))
    out$explanations <- c(lg_explain_side(m, team_a, sa, out$lineups$a, g$b, g$a, tr$a),
                          lg_explain_side(m, team_b, sb, out$lineups$b, g$a, g$b, tr$b),
                          lg_explain_trade(metrics))
  }
  out
}

#' Per-player started points / expected starts before and after, and slot points.
lg_lineup_change <- function(m, team, s_after, stream_after) {
  st <- m$state[[as.character(team)]]
  b <- lg_attribution(m, c(st$rows, st$ir_rows))
  a <- lg_attribution(m, c(s_after$rows, s_after$ir_rows), stream_after)
  pl <- dplyr::full_join(dplyr::select(b$players, "row", "player_name", "position", before_pts = "started_pts",
                                       before_starts = "starts"),
                         dplyr::select(a$players, "row", "player_name", "position", after_pts = "started_pts",
                                       after_starts = "starts"),
                         by = c("row", "player_name", "position")) |>
    dplyr::mutate(dplyr::across(c("before_pts", "before_starts", "after_pts", "after_starts"), ~ dplyr::coalesce(.x, 0)),
                  change_pts = .data$after_pts - .data$before_pts) |>
    dplyr::arrange(dplyr::desc(abs(.data$change_pts)))
  slots <- tibble::tibble(slot = union(names(b$slot_points), names(a$slot_points))) |>
    dplyr::mutate(before = unname(b$slot_points[.data$slot]), after = unname(a$slot_points[.data$slot]),
                  before = dplyr::coalesce(.data$before, 0), after = dplyr::coalesce(.data$after, 0),
                  change = .data$after - .data$before)
  list(players = pl, slots = slots, streamed_before = b$streamed_points, streamed_after = a$streamed_points)
}

lg_explain_side <- function(m, team, s, lc, gets, gives, tr) {
  nw <- length(m$weeks)
  lbl <- s$team
  out <- sprintf("%s %s %.1f expected ROS lineup points (%+.1f per week over %d weeks; regular season %+.1f, playoffs %+.1f).",
                 lbl, if (s$delta >= 0) "gains" else "loses", abs(s$delta), s$delta / nw, nw, s$delta_regular, s$delta_playoffs)
  p <- lc$players
  for (r in gets) {
    x <- p[p$row == r, ]
    if (!nrow(x)) next
    games <- sum(m$sim$E[r, ] > 0)
    if (x$after_starts < 0.5 * max(games, 1)) {
      out <- c(out, sprintf("%s would start only %.1f of %d weeks for %s (%.1f started points): mostly blocked by current starters.",
                            x$player_name, x$after_starts, nw, lbl, x$after_pts))
    } else {
      out <- c(out, sprintf("%s would start %.1f of %d weeks for %s, contributing %.1f started points.",
                            x$player_name, x$after_starts, nw, lbl, x$after_pts))
    }
  }
  for (r in gives) {
    x <- p[p$row == r, ]
    if (nrow(x)) out <- c(out, sprintf("%s loses %s's %.1f started points (%.1f starts).", lbl, x$player_name, x$before_pts, x$before_starts))
  }
  own <- p[!p$row %in% c(gets, gives), ]
  promo <- own[own$change_pts > 1, ]
  demo <- own[own$change_pts < -1, ]
  if (nrow(promo)) out <- c(out, sprintf("%s: more lineup time for %s (%s started points).", lbl,
                                         paste(utils::head(promo$player_name, 3), collapse = ", "),
                                         paste(sprintf("%+.1f", utils::head(promo$change_pts, 3)), collapse = ", ")))
  if (nrow(demo)) out <- c(out, sprintf("%s: less lineup time for %s (%s started points).", lbl,
                                        paste(utils::head(demo$player_name, 3), collapse = ", "),
                                        paste(sprintf("%+.1f", utils::head(demo$change_pts, 3)), collapse = ", ")))
  sl <- lc$slots[order(-abs(lc$slots$change)), ]
  if (nrow(sl) && abs(sl$change[1]) > 1) {
    out <- c(out, sprintf("%s: largest slot change is %s (%+.1f points).", lbl, sl$slot[1], sl$change[1]))
  }
  if (length(tr$dropped)) {
    out <- c(out, sprintf("%s must drop %s to meet roster limits (cost %.1f points).", lbl,
                          paste(lg_player_label(m, tr$dropped), collapse = " + "), sum(tr$drop_cost)))
  }
  if (length(tr$added)) {
    out <- c(out, sprintf("%s fills the open roster spot with free agent %s (+%.1f points).", lbl,
                          paste(lg_player_label(m, tr$added), collapse = " + "), sum(tr$add_gain)))
  }
  if (abs(lc$streamed_after - lc$streamed_before) > 1) {
    out <- c(out, sprintf("%s: free-agent streaming for empty slots changes by %+.1f points.", lbl,
                          lc$streamed_after - lc$streamed_before))
  }
  out
}

lg_explain_trade <- function(mt) {
  c(sprintf("Classification: %s (A %+.1f, B %+.1f; surplus %+.1f; balance %+.1f).", mt$classification, mt$delta_a,
            mt$delta_b, mt$surplus, mt$balance),
    sprintf("Generic V1 value: %s receives %+.1f VOR (%+.1f display points) net; roster-specific change differs by %+.1f for %s and %+.1f for %s.",
            mt$team_a, mt$generic_vor_net_a, mt$generic_tv_net_a, mt$consolidation_a, mt$team_a, mt$consolidation_b, mt$team_b))
}
