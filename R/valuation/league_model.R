# Valuation V2: team utility on actual rosters -----------------------------------------------
# U(team) = expected rest-of-season starting-lineup points of a team, week by week:
# each Monte Carlo draw (V1 availability draws, common random numbers) seats the
# optimal legal lineup from the team's ROSTERED players (V1 slot greedy, exact for
# laminar slots). Streaming policy (VL0):
#   empty_slots (default) - a free agent at the actual weekly FA level fills a slot
#                           only when no rostered eligible player is active for it
#   none                  - empty slots score 0
#   unlimited             - V1: any slot can be streamed (FA level floors every slot)
# Bench players therefore have value (they cover byes and injuries better than
# a free agent would) but less than starters, and open roster spots matter.

LG_POLICIES <- c("empty_slots", "none", "unlimited")

#' Build the league model from a valuation run's weekly projections and the
#' league's rosters. Rostered QB/RB/WR/TE without projection rows are kept
#' with 0 points (flagged by lg_id_diagnostics()).
lg_model <- function(weekly, roster, league, current_week, policy = "empty_slots", sims = 200, seed = 20261007,
                     generic = NULL, teams = NULL) {
  policy <- match.arg(policy, LG_POLICIES)
  weeks <- intersect(val_horizon_weeks(league, current_week, "full"), sort(unique(weekly$week)))
  if (!length(weeks)) cli::cli_abort("No overlap between the league horizon and the projection weeks.")
  w <- dplyr::filter(weekly, .data$week %in% weeks)
  ids <- dplyr::distinct(w, .data$espn_id, .data$player_id, .data$player_name, .data$position, .data$team)
  sk <- dplyr::filter(roster, .data$is_skill)
  miss <- dplyr::filter(sk, !.data$espn_id %in% ids$espn_id)
  if (nrow(miss)) {
    add <- tidyr::expand_grid(dplyr::transmute(miss, espn_id = .data$espn_id, player_id = paste0("espn:", .data$espn_id),
                                               player_name = .data$player_name, position = .data$position,
                                               team = .data$nfl_team), week = weeks) |>
      dplyr::mutate(proj = 0, p_active = 0, lvl = 0, has_game = FALSE)
    w <- dplyr::bind_rows(w, add)
    ids <- dplyr::bind_rows(ids, dplyr::distinct(add, .data$espn_id, .data$player_id, .data$player_name, .data$position, .data$team))
  }
  sim <- val_sim_setup(dplyr::transmute(w, .data$player_id, .data$position, .data$week, E = .data$proj,
                                        A = .data$p_active, lvl = .data$lvl), sims, seed)
  sim$players <- dplyr::left_join(sim$players, dplyr::select(ids, "player_id", "espn_id", "player_name", nfl_team = "team"),
                                  by = "player_id")
  row_of <- stats::setNames(seq_len(nrow(sim$players)), sim$players$espn_id)
  sk$row <- unname(row_of[sk$espn_id])
  team_ids <- sort(unique(roster$team_id))
  state <- lapply(team_ids, function(t) {
    r <- sk[sk$team_id == t, ]
    list(team_id = t, rows = r$row[!r$is_ir_slot], ir_rows = r$row[r$is_ir_slot],
         nonskill = sum(roster$team_id == t & !roster$is_skill & !roster$lineup_slot_id %in% LG_IR_SLOT))
  })
  names(state) <- as.character(team_ids)
  m <- list(sim = sim, league = league, spec = val_lineup_spec(league), policy = policy, weeks = weeks,
            current_week = current_week, state = state, teams = teams, generic = generic,
            segments = list(full = weeks, regular = intersect(weeks, val_horizon_weeks(league, current_week, "regular")),
                            playoffs = intersect(weeks, val_horizon_weeks(league, current_week, "playoffs"))))
  m$fa_rows <- lg_fa_rows(m)
  m$stream <- lg_stream(m, m$fa_rows)
  m$base <- lapply(m$state, function(s) lg_value(m, c(s$rows, s$ir_rows)))
  m
}

lg_all_rostered <- function(m, state = m$state) unlist(lapply(state, function(s) c(s$rows, s$ir_rows)))
lg_fa_rows <- function(m, state = m$state) setdiff(seq_len(nrow(m$sim$players)), lg_all_rostered(m, state))

#' Actual weekly FA level per position: best free-agent expectation that week.
lg_fa_levels <- function(m, fa_rows) {
  tidyr::expand_grid(position = VAL_POSITIONS, wi = seq_along(m$sim$weeks)) |>
    dplyr::mutate(week = m$sim$weeks[.data$wi], W = purrr::map2_dbl(.data$position, .data$wi, function(p, wi) {
      r <- fa_rows[m$sim$players$position[fa_rows] == p]
      if (length(r)) max(0, max(m$sim$E[r, wi])) else 0
    })) |>
    dplyr::select(-"wi")
}

lg_stream <- function(m, fa_rows) {
  if (m$policy == "none") return(rlang::set_names(lapply(m$spec$positions, function(p) rep(0, ncol(m$sim$P))), m$spec$positions))
  val_stream_vectors(lg_fa_levels(m, fa_rows), m$sim, m$spec$positions)
}

#' Top-K matrices (values, and player rows when ids = TRUE) by position.
lg_tops <- function(m, rows, ids = FALSE) {
  C <- ncol(m$sim$P)
  pos <- m$sim$players$position
  rlang::set_names(lapply(m$spec$positions, function(p) {
    K <- m$spec$K[[p]]
    v <- matrix(-Inf, K, C)
    id <- if (ids) matrix(0L, K, C) else NULL
    for (i in rows[pos[rows] == p]) {
      x <- m$sim$P[i, ]
      xi <- rep(as.integer(i), C)
      for (k in seq_len(K)) {
        if (ids) {
          take <- x > v[k, ]
          hid <- ifelse(take, xi, id[k, ])
          xi <- ifelse(take, id[k, ], xi)
          id[k, ] <- hid
        }
        hi <- pmax(x, v[k, ])
        x <- pmin(x, v[k, ])
        v[k, ] <- hi
      }
    }
    list(v = v, id = id)
  }), m$spec$positions)
}

#' Lineup per Monte Carlo column under the streaming policy. Returns column
#' totals; with `attrib = TRUE` also the started points and starts per player
#' row and per slot, and streamed points.
lg_lineup <- function(m, tops, stream, attrib = FALSE) {
  spec <- m$spec
  unlimited <- m$policy == "unlimited"
  C <- ncol(m$sim$P)
  base_idx <- seq_len(C) - 1L
  K <- vapply(tops, function(t) nrow(t$v), 1L)
  off <- lapply(K, function(k) base_idx * k)   # linear index offsets per position
  ptr <- lapply(tops, function(t) rep(1L, C))
  total <- numeric(C)
  if (attrib) {
    pick_id <- list()
    pick_val <- list()
    slot_pts <- list()
  }
  for (s in spec$slots) {
    el <- intersect(s$eligible, spec$positions)
    for (u in seq_len(s$count)) {
      rbest <- rep(-Inf, C)
      rwho <- integer(C)
      sbest <- numeric(C)
      for (j in seq_along(el)) {
        p <- el[j]
        r <- ptr[[p]]
        ok <- r <= K[[p]]
        head <- rep(-Inf, C)
        head[ok] <- tops[[p]]$v[off[[p]][ok] + r[ok]]
        st <- stream[[p]]
        if (unlimited) {
          val <- pmax(head, st)
          b <- val > rbest
          rbest[b] <- val[b]
          rwho[b] <- j
          rwho[b & head < st] <- -j  # negative: the streamer of position j
        } else {
          b <- head > rbest & head > 0
          rbest[b] <- head[b]
          rwho[b] <- j
          sbest <- pmax(sbest, st)
        }
      }
      use <- rwho > 0
      if (unlimited) {
        val <- rbest
      } else {
        val <- sbest
        val[use] <- rbest[use]
      }
      total <- total + val
      if (attrib) {
        pid <- integer(C)
        for (j in seq_along(el)) {
          adv <- use & rwho == j
          if (any(adv)) pid[adv] <- tops[[el[j]]]$id[off[[el[j]]][adv] + ptr[[el[j]]][adv]]
        }
        pick_id[[length(pick_id) + 1]] <- pid
        pick_val[[length(pick_val) + 1]] <- val
        slot_pts[[s$name]] <- (slot_pts[[s$name]] %||% 0) + sum(val) / m$sim$sims
      }
      for (j in seq_along(el)) {
        adv <- use & rwho == j
        ptr[[el[j]]][adv] <- ptr[[el[j]]][adv] + 1L
      }
    }
  }
  if (!attrib) return(total)
  ids <- unlist(pick_id)
  vals <- unlist(pick_val)
  wk <- rep(m$sim$colweek, length(pick_id))
  started <- ids > 0
  per_player <- tibble::tibble(row = ids[started], week = m$sim$weeks[wk[started]], pts = vals[started]) |>
    dplyr::summarise(started_pts = sum(.data$pts) / m$sim$sims, starts = dplyr::n() / m$sim$sims, .by = c("row", "week"))
  list(total = total, per_player_week = per_player, slot_points = unlist(slot_pts),
       streamed_points = sum(vals[!started]) / m$sim$sims)
}

#' Team value for a set of rows: expected points per horizon week, the full-ROS
#' total and segment totals.
lg_value <- function(m, rows, stream = m$stream) {
  cols <- lg_lineup(m, lg_tops(m, rows), stream)
  per_week <- as.numeric(rowsum(cols, m$sim$colweek)) / m$sim$sims
  names(per_week) <- m$sim$weeks
  seg <- vapply(m$segments, function(wk) sum(per_week[as.character(wk)]), 0)
  list(U = sum(per_week), per_week = per_week, regular = seg[["regular"]], playoffs = seg[["playoffs"]])
}

#' Detailed attribution for a roster: started points / expected starts per player,
#' points by slot, streamed points, bench contribution.
lg_attribution <- function(m, rows, stream = m$stream) {
  a <- lg_lineup(m, lg_tops(m, rows, ids = TRUE), stream, attrib = TRUE)
  pp <- a$per_player_week |>
    dplyr::summarise(started_pts = sum(.data$started_pts), starts = sum(.data$starts), .by = "row")
  pl <- tibble::tibble(row = rows) |>
    dplyr::left_join(pp, by = "row") |>
    dplyr::mutate(started_pts = dplyr::coalesce(.data$started_pts, 0), starts = dplyr::coalesce(.data$starts, 0),
                  player_id = m$sim$players$player_id[.data$row], player_name = m$sim$players$player_name[.data$row],
                  position = m$sim$players$position[.data$row], ros_points = m$sim$ros[.data$row],
                  games = rowSums(m$sim$E[.data$row, , drop = FALSE] > 0))
  list(players = pl, per_player_week = a$per_player_week, slot_points = a$slot_points,
       streamed_points = a$streamed_points, U = sum(a$total) / m$sim$sims)
}

#' Roster capacity for QB/RB/WR/TE outside IR slots.
lg_capacity <- function(m, team) {
  st <- m$state[[as.character(team)]]
  (m$league$roster_size %||% val_roster_size(m$league)) - st$nonskill
}

lg_over_limits <- function(m, rows) {
  lim <- unlist(m$league$position_limits %||% list())
  if (!length(lim)) return(character())
  cnt <- table(factor(m$sim$players$position[rows], VAL_POSITIONS))
  names(lim)[cnt[names(lim)] > lim]
}

#' Resolve roster limits after a transfer. Drops (greedy, maximizing U) while
#' the roster is over capacity or over a position limit; then fills open spots
#' with the free agent adding the most U, only while the gain is positive.
#' `all_rows` = rows + IR rows used for utility.
lg_resolve <- function(m, team, rows, ir_rows, fa_rows, stream, cand_per_pos = 6, allow_adds = TRUE) {
  cap <- lg_capacity(m, team)
  pos <- m$sim$players$position
  dropped <- integer()
  drop_cost <- numeric()
  tops <- lg_tops(m, c(rows, ir_rows))
  u_of <- function(t) sum(lg_lineup(m, t, stream)) / m$sim$sims
  u_cur <- u_of(tops)
  # top-K matrices of one position rebuilt without player c (others unchanged)
  without <- function(t, c) {
    p <- pos[c]
    keep <- setdiff(c(rows, ir_rows)[pos[c(rows, ir_rows)] == p], c)
    t[[p]] <- lg_tops_pos(m, keep, p)
    t
  }
  repeat {
    over <- lg_over_limits(m, c(rows, ir_rows))
    if (length(rows) <= cap && !length(over)) break
    cands <- if (length(over)) rows[pos[rows] %in% over] else rows
    if (!length(cands)) cli::cli_abort("Team {team}: roster limits cannot be met by dropping players.")
    tw <- lapply(cands, function(c) without(tops, c))
    u <- vapply(tw, u_of, 0)
    k <- order(-u, m$sim$ros[cands])[1]
    dropped <- c(dropped, cands[k])
    drop_cost <- c(drop_cost, u_cur - u[k])
    u_cur <- u[k]
    tops <- tw[[k]]
    rows <- setdiff(rows, cands[k])
  }
  added <- integer()
  add_gain <- numeric()
  if (allow_adds) {
    lim <- unlist(m$league$position_limits %||% list())
    while (length(rows) < cap && length(fa_rows)) {
      full_pos <- names(lim)[table(factor(pos[c(rows, ir_rows)], VAL_POSITIONS))[names(lim)] >= lim]
      cands <- unlist(lapply(setdiff(m$spec$positions, full_pos), function(p) {
        r <- fa_rows[pos[fa_rows] == p]
        r[order(-m$sim$ros[r], m$sim$players$player_id[r])][seq_len(min(length(r), cand_per_pos))]
      }))
      if (!length(cands)) break
      tw <- lapply(cands, function(c) lg_tops_insert(tops, pos[c], m$sim$P[c, ]))
      u <- vapply(tw, u_of, 0)
      k <- order(-round(u, 8), -m$sim$ros[cands])[1]
      if (u[k] - u_cur <= 1e-9) break
      added <- c(added, cands[k])
      add_gain <- c(add_gain, u[k] - u_cur)
      u_cur <- u[k]
      tops <- tw[[k]]
      rows <- c(rows, cands[k])
      fa_rows <- setdiff(fa_rows, cands[k])
    }
  }
  list(rows = rows, dropped = dropped, drop_cost = drop_cost, added = added, add_gain = add_gain, fa_rows = fa_rows)
}

#' Top-K matrix of one position from a set of rows (values only).
lg_tops_pos <- function(m, rows, p) {
  v <- matrix(-Inf, m$spec$K[[p]], ncol(m$sim$P))
  for (i in rows) v <- val_topk_insert(v, m$sim$P[i, ])
  list(v = v, id = NULL)
}

#' Resolve a player reference (ESPN id, player id or name) to a model row.
lg_find_player <- function(m, x) {
  pl <- m$sim$players
  if (is.numeric(x)) return(as.integer(x))
  hit <- which(pl$espn_id == x | pl$player_id == x)
  if (length(hit) == 1) return(hit)
  nm <- normalize_name(pl$player_name)
  hit <- which(nm == normalize_name(x))
  if (length(hit) == 1) return(hit)
  if (length(hit) > 1) cli::cli_abort("Player {.val {x}} is ambiguous; use the ESPN id.")
  part <- which(grepl(normalize_name(x), nm, fixed = TRUE))
  if (length(part) == 1) return(part)
  cli::cli_abort("Player {.val {x}} not found in the league pool.")
}

#' Resolve a team reference (id, abbreviation or name).
lg_find_team <- function(m, x) {
  ids <- as.integer(names(m$state))
  if (is.numeric(x) && x %in% ids) return(as.integer(x))
  tm <- m$teams
  if (!is.null(tm)) {
    hit <- tm$team_id[toupper(tm$team_abbrev) == toupper(x) | tolower(tm$team_name) == tolower(x)]
    if (length(hit) == 1) return(hit)
    hit <- tm$team_id[grepl(tolower(x), tolower(tm$team_name), fixed = TRUE)]
    if (length(hit) == 1) return(hit)
  }
  if (!is.na(suppressWarnings(as.integer(x))) && as.integer(x) %in% ids) return(as.integer(x))
  cli::cli_abort("Team {.val {x}} not found.")
}

lg_team_label <- function(m, team) {
  tm <- m$teams
  if (is.null(tm)) return(paste("Team", team))
  lbl <- tm$team_name[tm$team_id == team]
  if (length(lbl) && !is.na(lbl) && nzchar(lbl)) lbl else paste("Team", team)
}

lg_player_label <- function(m, rows) {
  ifelse(is.na(m$sim$players$player_name[rows]), m$sim$players$player_id[rows], m$sim$players$player_name[rows])
}
