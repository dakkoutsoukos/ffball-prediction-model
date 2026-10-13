# Lineup helpers (master plan D0) ---------------------------------------------------------------
# Two additions that never cost expected points, written as NEW functions (val_assign_slots(),
# val_allocate() and the V2 lineup code are untouched):
#   1. Kickoff-aware slotting. Which eligible starter sits in a flexible slot (FLEX, superflex)
#      does not change expected points, but ESPN locks each player at his own kickoff. Putting the
#      LATEST-kickoff starters in the most flexible slots keeps the most swap options open.
#   2. Game-time plans. For each starter with a game-time designation: P(active) from a fixed
#      published prior (config/availability_prior.yml; P1 replaces it), the decision time (inactives
#      are announced about 90 min before his kickoff), the best bench pivot still unlocked then,
#      and the plan's expected points.
# The starting set is the expected-points optimum on the current week's projections (the same
# values V2 uses), conditional on players already locked by kickoff.

AVAILABILITY_PRIOR_FILE <- "config/availability_prior.yml"

read_availability_prior <- function(path = AVAILABILITY_PRIOR_FILE) {
  p <- yaml::read_yaml(path)
  p$p_active <- unlist(p$p_active)
  p
}

#' P(active) for ESPN injury statuses under the fixed prior (unlisted statuses -> default 1).
val_designation_prior <- function(status, prior = read_availability_prior()) {
  v <- unname(prior$p_active[toupper(as.character(status))])
  v[is.na(v)] <- prior$default %||% 1
  v
}

val_one_team <- function(league) {
  league$teams <- 1L
  league
}

#' Expected-points starting set for one team, respecting players already locked by kickoff:
#' a locked starter keeps his slot (`fixed_slot`, a league slot name), a locked bench player
#' cannot enter, and the remaining slots are filled optimally from unlocked players.
val_lineup_locked <- function(value, position, league, locked = rep(FALSE, length(value)),
                              fixed_slot = rep(NA_character_, length(value))) {
  league1 <- val_one_team(league)
  starter <- locked & !is.na(fixed_slot)
  for (s in fixed_slot[starter]) {
    if (is.null(league1$slots[[s]])) cli::cli_abort("Locked player sits in unknown slot {.val {s}}.")
    league1$slots[[s]]$count <- league1$slots[[s]]$count - 1L
  }
  if (any(vapply(league1$slots, `[[`, 0L, "count") < 0)) cli::cli_abort("More locked starters than slots.")
  league1$slots <- Filter(function(s) s$count > 0, league1$slots)
  if (length(league1$slots)) {
    pick <- val_allocate(ifelse(locked, 0, value), position, val_hall_table(league1))
    starter <- starter | (pick & !locked)
  }
  starter
}

#' Slot assignment that puts the latest-kickoff starters in the most flexible slots. Slots are
#' filled from the most specific to the most flexible; within a slot the EARLIEST-kickoff eligible
#' starter goes first (ties: higher value, then input order), so flexible slots keep the latest
#' kickoffs. Exact for laminar slot sets, like val_assign_slots(). Players with a `fixed_slot`
#' (locked) keep it. Expected points are unchanged: the starting set is not altered.
val_flex_slotting <- function(value, position, starter, kickoff, league, fixed_slot = rep(NA_character_, length(value))) {
  league1 <- val_one_team(league)
  out <- ifelse(starter, fixed_slot, NA_character_)
  cap <- vapply(league1$slots, `[[`, 0L, "count")
  for (s in out[!is.na(out)]) cap[[s]] <- cap[[s]] - 1L
  if (any(cap < 0)) cli::cli_abort("More fixed starters than slots.")
  sl <- league1$slots[order(vapply(league1$slots, function(s) length(s$eligible), 0L))]
  left <- which(starter & is.na(out))
  k <- as.numeric(kickoff[left])
  k[is.na(k)] <- Inf
  left <- left[order(k, -value[left], left)]
  for (s in sl) {
    for (j in seq_len(cap[[s$name]])) {
      hit <- left[position[left] %in% s$eligible]
      if (!length(hit)) break
      out[hit[1]] <- s$name
      left <- left[left != hit[1]]
    }
  }
  if (length(left)) cli::cli_abort("{length(left)} starter{?s} could not be seated.")
  out
}

#' Can these positions be seated in exactly these slots (a multiset of slot names)?
val_seatable_in <- function(positions, slot_names, league) {
  if (!length(positions)) return(TRUE)
  if (length(positions) > length(slot_names)) return(FALSE)
  counts_slot <- table(slot_names)
  l2 <- val_one_team(league)
  l2$slots <- lapply(names(counts_slot), function(n) utils::modifyList(league$slots[[n]], list(count = as.integer(counts_slot[[n]]))))
  names(l2$slots) <- names(counts_slot)
  cnt <- table(factor(positions, levels = VAL_POSITIONS))
  val_seatable(stats::setNames(as.numeric(cnt), names(cnt)), val_hall_table(l2))
}

#' Game-time plans for designated starters. `d`: one row per rostered player with player_name,
#' position, proj (expected points if he plays; ESPN's pre-inactive projection), status (ESPN),
#' kickoff_utc, starter, slot (assigned), is_ir. A pivot must be on the bench, play this week,
#' kick off after the starter's decision time (kickoff - lead) so it is still unlocked, and fit
#' the slots of the starters still unlocked at that time. Plan EV = p * proj + (1 - p) * E(pivot).
val_gametime_plan <- function(d, league, prior = read_availability_prior(), now = Sys.time()) {
  lead <- (prior$decision_lead_minutes %||% 90) * 60
  d$p <- val_designation_prior(d$status, prior)
  d$E <- d$p * d$proj
  plan_rows <- which(d$starter & d$p < 1)
  if (!length(plan_rows)) return(tibble::tibble())
  out <- purrr::map(plan_rows, function(s) {
    t_s <- d$kickoff_utc[s] - lead
    unlocked <- which(d$starter & !is.na(d$kickoff_utc) & d$kickoff_utc > t_s)
    others <- setdiff(unlocked, s)
    cand <- which(!d$starter & !d$is_ir & !is.na(d$kickoff_utc) & d$kickoff_utc > max(t_s, now) & d$p > 0 & d$proj > 0)
    ok <- vapply(cand, function(b) val_seatable_in(d$position[c(others, b)], d$slot[unlocked], league), TRUE)
    piv <- cand[ok]
    now_ok <- which(!d$starter & !d$is_ir & !is.na(d$kickoff_utc) & d$kickoff_utc > now & d$p > 0 & d$proj > 0)
    now_ok <- now_ok[vapply(now_ok, function(b) {
      un_now <- which(d$starter & !is.na(d$kickoff_utc) & d$kickoff_utc > now)
      val_seatable_in(d$position[c(setdiff(un_now, s), b)], d$slot[un_now], league)
    }, TRUE)]
    best <- if (length(piv)) piv[which.max(d$E[piv])] else NA_integer_
    alt <- if (length(now_ok)) now_ok[which.max(d$E[now_ok])] else NA_integer_
    e_piv <- if (is.na(best)) 0 else d$E[best]
    e_alt <- if (is.na(alt)) 0 else d$E[alt]
    start_ev <- d$p[s] * d$proj[s]
    plan_ev <- start_ev + (1 - d$p[s]) * e_piv
    advice <- if (d$p[s] == 0) {
      "ruled out: replace him now"
    } else if (!is.na(best) && d$proj[s] >= e_piv) {
      sprintf("start; if inactive at %s, swap in %s", fmt_et(t_s), d$player_name[best])
    } else if (!is.na(best)) {
      sprintf("start %s instead (higher expected points even if he plays)", d$player_name[best])
    } else if (start_ev >= e_alt) {
      "start; no pivot kicks off after his inactive announcement (slot scores 0 if he sits)"
    } else {
      sprintf("bench; no late pivot, and %s has higher expected points", d$player_name[alt])
    }
    tibble::tibble(player = d$player_name[s], position = d$position[s], slot = d$slot[s], status = d$status[s],
                   p_active = d$p[s], proj_if_active = d$proj[s], kickoff_utc = d$kickoff_utc[s], decision_utc = t_s,
                   pivot = if (is.na(best)) NA_character_ else d$player_name[best],
                   pivot_position = if (is.na(best)) NA_character_ else d$position[best],
                   pivot_kickoff_utc = if (is.na(best)) as.POSIXct(NA, tz = "UTC") else d$kickoff_utc[best],
                   pivot_E = e_piv, start_ev = start_ev, plan_ev = plan_ev, has_pivot = !is.na(best), advice = advice)
  }) |>
    purrr::list_rbind()
  # plans are computed one starter at a time: flag a pivot that two plans would both need
  shared <- !is.na(out$pivot) & (duplicated(out$pivot) | duplicated(out$pivot, fromLast = TRUE))
  out$advice[shared] <- paste0(out$advice[shared], " (pivot shared with another plan: only one can use it)")
  out
}

#' D0 advice for one team of the league model: recommended starters (locks respected), kickoff
#' slotting, game-time plans, and the expected points of the recommended vs current ESPN lineup.
lg_lineup_advice <- function(m, team, team_games, now = Sys.time(), prior = read_availability_prior()) {
  wk <- m$current_week
  ros <- dplyr::filter(m$input_data$roster, .data$team_id == !!team, .data$is_skill)
  w <- dplyr::filter(m$input_data$weekly, .data$week == !!wk) |>
    dplyr::select("espn_id", "player_id", "proj", "has_game", nfl = "team", "opponent")
  ko <- team_games |>
    dplyr::filter(.data$season == !!m$season, .data$week == !!wk) |>
    dplyr::distinct(nfl = .data$team, .data$kickoff_utc)
  d <- ros |>
    dplyr::left_join(w, by = "espn_id") |>
    dplyr::left_join(ko, by = "nfl") |>
    dplyr::mutate(proj = dplyr::coalesce(.data$proj, 0), has_game = dplyr::coalesce(.data$has_game, FALSE),
                  proj = ifelse(.data$has_game, .data$proj, 0),
                  kickoff_utc = dplyr::if_else(.data$has_game, .data$kickoff_utc, as.POSIXct(NA, tz = "UTC")),
                  status = .data$injury_status, is_ir = .data$is_ir_slot,
                  locked = !is.na(.data$kickoff_utc) & .data$kickoff_utc <= now,
                  espn_slot = vapply(as.character(.data$lineup_slot_id), function(i) LG_SLOT_MAP[[i]]$name %||% NA_character_, ""),
                  current_starter = !is.na(.data$espn_slot))
  # IR players cannot start; locked players keep their ESPN placement
  value <- ifelse(d$is_ir, 0, d$proj)
  st <- val_lineup_locked(value, d$position, m$league, d$locked | d$is_ir, ifelse(d$locked, d$espn_slot, NA_character_))
  d$starter <- st
  d$slot <- val_flex_slotting(value, d$position, st, d$kickoff_utc, m$league, ifelse(d$locked, d$espn_slot, NA_character_))
  plan <- val_gametime_plan(dplyr::transmute(d, .data$player_name, .data$position, .data$proj, .data$status, .data$kickoff_utc,
                                             .data$starter, .data$slot, .data$is_ir), m$league, prior, now)
  lineup <- d |>
    dplyr::transmute(slot = dplyr::coalesce(.data$slot, ifelse(.data$is_ir, "IR", "BE")), player = .data$player_name,
                     .data$player_id, .data$espn_id,
                     .data$position, nfl = .data$nfl, kickoff_utc = .data$kickoff_utc, .data$proj, .data$status, .data$locked,
                     espn_slot = dplyr::coalesce(.data$espn_slot, ifelse(.data$is_ir, "IR", "BE")),
                     change = dplyr::case_when(.data$starter & !.data$current_starter ~ "start",
                                               !.data$starter & .data$current_starter ~ "bench",
                                               .data$starter & .data$slot != .data$espn_slot ~ "move",
                                               TRUE ~ ""))
  order_slots <- c(names(m$league$slots), "BE", "IR")
  lineup <- lineup[order(match(lineup$slot, order_slots), lineup$kickoff_utc), ]
  list(team = team, week = wk, now = now, lineup = lineup, plan = plan,
       ev_recommended = sum(d$proj[d$starter]), ev_current = sum(d$proj[d$current_starter]),
       prior_source = prior$source)
}
