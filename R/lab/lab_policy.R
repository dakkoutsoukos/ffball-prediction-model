# F6 decision laboratory v1: policies (pre-registration LAB1) --------------------------------------
# A policy is a function(state, info): `state` is the team's own situation (roster, standings,
# free agents), `info` a lab_info() object. Policies never receive outcomes beyond `info`.

#' Optimal lineup for values `v` (finite = may start): fixed slots by position first, then FLEX
#' from the remaining RB/WR/TE. Optimal for this laminar slot structure. Ties go to the lower index.
#' Returns positions within `v` of the starters.
lab_lineup <- function(v, pos) {
  ok <- is.finite(v)
  pick <- integer(0)
  for (p in LAB_POSITIONS) {
    cand <- which(ok & pos == p)
    cand <- cand[order(-v[cand], cand)]
    pick <- c(pick, utils::head(cand, LAB_SLOTS[[p]]))
  }
  rest <- which(ok & pos %in% LAB_FLEX)
  rest <- rest[!rest %in% pick]
  rest <- rest[order(-v[rest], rest)]
  c(pick, utils::head(rest, LAB_SLOTS$FLEX))
}

#' Value of the optimal lineup (empty slots count 0).
lab_lineup_value <- function(v, pos) {
  s <- lab_lineup(v, pos)
  sum(v[s])
}

#' Week-t lineup values for the given players: the ESPN projection (raw) or the F4 base
#' (calibrated). A player without a week-t ESPN row cannot start (-Inf); a missing value is 0.
lab_lineup_values <- function(info, players, kind = c("raw", "calibrated")) {
  kind <- match.arg(kind)
  t <- info$t
  startable <- !is.na(info$proj[players, t])
  v <- if (kind == "raw") info$proj[players, t] else info$base[players, t]
  v[is.na(v)] <- 0
  v[!startable] <- -Inf
  v
}

lab_lineup_policy <- function(kind = c("raw", "calibrated")) {
  kind <- match.arg(kind)
  function(state, info) {
    stopifnot(inherits(info, "lab_info"), info$stage == "lineup")
    r <- state$roster
    r[lab_lineup(lab_lineup_values(info, r, kind), info$pos[r])]
  }
}

#' Rest-of-season per-week values at a waiver stage (before week t), for all players: the per-game
#' level (raw L_avg4, or the season's calibration a + b L_avg4) times the share of the remaining
#' weeks t..16 in which the player's last known team plays. NA when the player has no level yet.
lab_ros_values <- function(info, kind = c("raw", "calibrated"), calib = NULL) {
  kind <- match.arg(kind)
  t <- info$t
  L <- info$L[, t - 1]
  per_game <- if (kind == "raw") L else {
    k <- match(info$pos, calib$position)
    calib$a[k] + calib$b[k] * L
  }
  team <- info$team_asof[, t - 1]
  rem <- seq(t, info$n_weeks)
  games <- rowSums(info$plays[match(team, info$teams), rem, drop = FALSE])
  games[is.na(games)] <- 0
  per_game * games / length(rem)
}

#' Legal roster composition after a move: QB 1-3, TE 1-3, RB >= 2, WR >= 2.
lab_roster_legal <- function(pos) {
  n <- table(factor(pos, LAB_POSITIONS))
  n[["QB"]] >= 1 && n[["QB"]] <= 3 && n[["TE"]] >= 1 && n[["TE"]] <= 3 && n[["RB"]] >= 2 && n[["WR"]] >= 2
}

#' Contested add/drop policy: candidate pairs (the best `per_pos_fa` free agents per position by
#' value; the `per_pos_drop` lowest-value roster players per position). The gain of a pair is the
#' change in the optimal lineup value times the remaining weeks. Returns up to `max_claims` claims
#' with gain > `min_gain`, distinct adds and drops, best first.
lab_waiver_policy <- function(kind = c("raw", "calibrated"), calib = NULL, max_claims = 2L, min_gain = 2,
                              per_pos_fa = 5L, per_pos_drop = 2L) {
  kind <- match.arg(kind)
  if (kind == "calibrated" && is.null(calib)) cli::cli_abort("A calibrated waiver policy needs coefficients.")
  function(state, info) {
    stopifnot(inherits(info, "lab_info"), info$stage == "waiver")
    v <- lab_ros_values(info, kind, calib)
    lab_claims(v, info$pos, state$roster, state$free_agents, n_weeks = info$n_weeks - info$t + 1,
               max_claims = max_claims, min_gain = min_gain, per_pos_fa = per_pos_fa, per_pos_drop = per_pos_drop)
  }
}

#' Claim list for a roster given per-week values `v` (all players; NA = no value).
lab_claims <- function(v, pos, roster, free_agents, n_weeks, max_claims = 2L, min_gain = 2, per_pos_fa = 5L,
                       per_pos_drop = 2L) {
  empty <- tibble::tibble(add = integer(), drop = integer(), gain = double())
  vr <- dplyr::coalesce(v[roster], 0)
  cur <- lab_lineup_value(vr, pos[roster])
  fa <- free_agents[!is.na(v[free_agents]) & v[free_agents] > 0]
  if (!length(fa)) return(empty)
  adds <- unlist(lapply(LAB_POSITIONS, function(p) {
    x <- fa[pos[fa] == p]
    utils::head(x[order(-v[x], x)], per_pos_fa)
  }))
  drops <- unlist(lapply(LAB_POSITIONS, function(p) {
    x <- roster[pos[roster] == p]
    utils::head(x[order(dplyr::coalesce(v[x], 0), x)], per_pos_drop)
  }))
  if (!length(adds) || !length(drops)) return(empty)
  pairs <- expand.grid(add = adds, drop = drops, KEEP.OUT.ATTRS = FALSE)
  pairs$gain <- vapply(seq_len(nrow(pairs)), function(k) {
    r <- c(roster[roster != pairs$drop[k]], pairs$add[k])
    if (!lab_roster_legal(pos[r])) return(-Inf)
    (lab_lineup_value(dplyr::coalesce(v[r], 0), pos[r]) - cur) * n_weeks
  }, 0)
  pairs <- pairs[pairs$gain > min_gain, ]
  pairs <- pairs[order(-pairs$gain, pairs$add, pairs$drop), ]
  out <- empty
  for (k in seq_len(nrow(pairs))) {
    if (nrow(out) >= max_claims) break
    if (pairs$add[k] %in% out$add || pairs$drop[k] %in% out$drop) next
    out <- dplyr::bind_rows(out, tibble::tibble(add = pairs$add[k], drop = pairs$drop[k], gain = pairs$gain[k]))
  }
  out
}
