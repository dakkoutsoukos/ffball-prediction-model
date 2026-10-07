# Valuation: league-level starter allocation and baselines --------------------------------
# Each week the league's starting spots (slot count x teams) are filled by an
# EXACT maximum-weight assignment of players to slots. Players of one position
# are interchangeable for eligibility, so a set of players can be seated iff,
# for every subset P of positions, the number of chosen players in P does not
# exceed the capacity of slots accepting any position in P (Hall's condition).
# Those sets are the independent sets of a transversal matroid, so adding
# players in decreasing value whenever the set stays seatable is optimal.
#
# Baselines come from EXCHANGE: when a position-p starter leaves, the best
# replacement is the best alternative y such that "starters - p + y" can still
# be seated. If an RB currently sits in FLEX, it slides into the vacated RB slot
# and FLEX takes any flex-eligible player; if FLEX holds no RB, only an RB can
# fill the hole. These are the minimal LP dual slot prices: positions present
# in FLEX share one baseline, positions absent from it keep their own.

#' Hall-condition table: every non-empty subset of positions with the league
#' capacity of slots that accept at least one of its positions.
val_hall_table <- function(league, positions = VAL_POSITIONS) {
  k <- length(positions)
  masks <- as.matrix(expand.grid(rep(list(c(FALSE, TRUE)), k)))[-1, , drop = FALSE]
  colnames(masks) <- positions
  cap <- val_slot_capacity(league)
  el <- lapply(league$slots, `[[`, "eligible")
  n_cap <- apply(masks, 1, function(m) {
    P <- positions[m]
    sum(cap[vapply(el, function(e) any(e %in% P), TRUE)])
  })
  list(masks = masks, cap = n_cap, positions = positions, total = sum(cap))
}

#' Can players with these position counts all be seated?
val_seatable <- function(counts, hall) {
  x <- counts[hall$positions]
  x[is.na(x)] <- 0
  all(drop(hall$masks %*% x) <= hall$cap)
}

#' Optimal league starting set for one week. `value` = expected points;
#' players with value <= 0 never start. Ties are broken by input order, so pass
#' rows in a deterministic order. Returns a logical vector.
val_allocate <- function(value, position, hall) {
  n <- length(value)
  starter <- logical(n)
  counts <- stats::setNames(numeric(length(hall$positions)), hall$positions)
  ord <- order(-value, seq_len(n))
  ord <- ord[value[ord] > 0 & position[ord] %in% hall$positions]
  # masks containing each position, for an O(masks) check per candidate
  by_pos <- lapply(hall$positions, function(p) which(hall$masks[, p]))
  names(by_pos) <- hall$positions
  load <- numeric(nrow(hall$masks))
  filled <- 0
  for (i in ord) {
    if (filled >= hall$total) break
    m <- by_pos[[position[i]]]
    if (all(load[m] + 1 <= hall$cap[m])) {
      starter[i] <- TRUE
      load[m] <- load[m] + 1
      counts[position[i]] <- counts[position[i]] + 1
      filled <- filled + 1
    }
  }
  starter
}

#' Which exchanges keep the starting set seatable: entry [p, q] is TRUE when one
#' position-p starter can be replaced by a position-q player.
val_exchange_matrix <- function(counts, hall) {
  P <- hall$positions
  out <- matrix(FALSE, length(P), length(P), dimnames = list(out = P, `in` = P))
  for (p in P) {
    if ((counts[[p]] %||% 0) < 1) next
    for (q in P) {
      cc <- counts
      cc[[p]] <- cc[[p]] - 1
      cc[[q]] <- (cc[[q]] %||% 0) + 1
      out[p, q] <- val_seatable(cc, hall)
    }
  }
  out
}

#' Exchange baseline per position: the best value among `candidate` players
#' that can replace a departing starter of that position. A position with no
#' starter gets its entry price instead (the weakest starter it could
#' displace); a position no slot accepts gets Inf. No feasible candidate -> 0.
val_exchange_baselines <- function(value, position, starter, candidate, hall) {
  P <- hall$positions
  counts <- stats::setNames(vapply(P, function(p) sum(starter & position == p), 0), P)
  ex <- val_exchange_matrix(counts, hall)
  best <- vapply(P, function(q) {
    v <- value[candidate & position == q]
    if (length(v)) max(0, max(v)) else 0
  }, 0)
  accepts <- vapply(P, function(p) val_seatable(stats::setNames(as.numeric(P == p), P), hall), TRUE)
  base <- vapply(P, function(p) {
    if (!accepts[[p]]) return(Inf)
    if (counts[[p]] >= 1) {
      ok <- ex[p, ]
      return(if (any(ok)) max(best[ok]) else 0)
    }
    # entry price: weakest starter x such that x -> p keeps the set seatable
    sv <- value[starter]
    sp <- position[starter]
    ok <- vapply(seq_along(sv), function(j) {
      cc <- counts
      cc[[sp[j]]] <- cc[[sp[j]]] - 1
      cc[[p]] <- cc[[p]] + 1
      val_seatable(cc, hall)
    }, TRUE)
    if (any(ok)) min(sv[ok]) else 0
  }, 0)
  via <- vapply(P, function(p) {
    if (counts[[p]] < 1 || !any(ex[p, ])) return(NA_character_)
    names(which.max(best[ex[p, ]]))
  }, "")
  list(baseline = base, via = via, exchange = ex, counts = counts)
}

#' Assign chosen starters to slots for reporting (which ones sit in FLEX).
#' Slots are filled in order of increasing eligibility; within a position the
#' best players take the most specific slots. Exact for laminar slot sets.
val_assign_slots <- function(value, position, starter, league) {
  out <- rep(NA_character_, length(value))
  sl <- league$slots[order(vapply(league$slots, function(s) length(s$eligible), 0L))]
  left <- which(starter)
  left <- left[order(-value[left])]
  for (s in sl) {
    cap <- s$count * league$teams
    for (k in seq_len(cap)) {
      hit <- left[position[left] %in% s$eligible]
      if (!length(hit)) break
      i <- hit[1]
      out[i] <- s$name
      left <- setdiff(left, i)
    }
  }
  out
}

#' Weekly league baselines from a weekly projection table (player_id,
#' position, week, E). Returns, per week and position:
#'   S - marginal-starter baseline (alternatives: every non-starter)
#'   R - waiver baseline (alternatives: players outside `rostered`), with the
#'       exchange taken over the starting set seated from rostered players
#'   W - best player outside `rostered` at the position itself (the streamer)
#' plus league starter counts and slot usage. With `rostered = NULL`, R and W are NA.
val_weekly_baselines <- function(weekly, league, rostered = NULL) {
  hall <- val_hall_table(league)
  weekly <- dplyr::arrange(weekly, .data$week, .data$player_id)
  purrr::map(split(weekly, weekly$week), function(d) {
    st <- val_allocate(d$E, d$position, hall)
    sb <- val_exchange_baselines(d$E, d$position, st, !st, hall)
    slot <- val_assign_slots(d$E, d$position, st, league)
    res <- tibble::tibble(
      week = d$week[1], position = hall$positions, S = unname(sb$baseline[hall$positions]),
      S_via = unname(sb$via[hall$positions]), n_starters = unname(sb$counts[hall$positions]),
      n_in_multi_slots = unname(vapply(hall$positions, function(p) {
        sum(st & d$position == p & !slot %in% names(Filter(function(s) length(s$eligible) == 1, league$slots)))
      }, 0))
    )
    if (!is.null(rostered)) {
      ros <- d$player_id %in% rostered
      st_r <- val_allocate(ifelse(ros, d$E, 0), d$position, hall)
      rb <- val_exchange_baselines(d$E, d$position, st_r, !ros, hall)
      res$R <- unname(rb$baseline[hall$positions])
      res$R_via <- unname(rb$via[hall$positions])
      res$W <- unname(vapply(hall$positions, function(p) {
        v <- d$E[!ros & d$position == p]
        if (length(v)) max(0, max(v)) else 0
      }, 0))
    } else {
      res$R <- NA_real_
      res$R_via <- NA_character_
      res$W <- NA_real_
    }
    res
  }) |>
    purrr::list_rbind()
}
