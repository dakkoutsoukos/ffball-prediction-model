# Valuation V2: marginal team value, trade search, team diagnostics --------------------------
#   MTV(i, T) for i not on T = U(T + i - best drop) - U(T)    (0 if T would drop i himself)
#   MTV(i, T) for i on T     = U(T) - U(T - i + best free-agent add)
# The matrix uses the current free-agent levels and ignores position limits (the full
# trade evaluation enforces them); it is used for pruning, destinations and diagnostics.

lg_tops_insert <- function(tops, p, x) {
  tops[[p]]$v <- val_topk_insert(tops[[p]]$v, x)
  tops
}

#' Per-team cache: full top-K matrices and those without each roster player.
lg_team_cache <- function(m, team) {
  s <- m$state[[as.character(team)]]
  all_rows <- c(s$rows, s$ir_rows)
  pos <- m$sim$players$position
  full <- lg_tops(m, all_rows)
  without <- lapply(s$rows, function(j) {
    t <- full
    t[[pos[j]]] <- lg_tops(m, setdiff(all_rows[pos[all_rows] == pos[j]], j))[[pos[j]]]
    t
  })
  list(team = team, rows = s$rows, ir_rows = s$ir_rows, full = full, without = without,
       u = m$base[[as.character(team)]]$U, full_roster = length(s$rows) >= lg_capacity(m, team))
}

lg_u_tops <- function(m, tops, stream = m$stream) sum(lg_lineup(m, tops, stream)) / m$sim$sims

#' Marginal team value of player rows for each team.
lg_mtv_matrix <- function(m, rows, caches = NULL, cand_per_pos = 6) {
  caches <- caches %||% lapply(names(m$state), function(t) lg_team_cache(m, as.integer(t)))
  pos <- m$sim$players$position
  owner <- lg_owner(m)
  out <- lapply(caches, function(cc) {
    vapply(rows, function(i) {
      if (!pos[i] %in% m$spec$positions) return(0)
      if (i %in% c(cc$rows, cc$ir_rows)) {
        # own player: loss when removed, refilled with the best free-agent add
        r <- lg_resolve(m, cc$team, setdiff(cc$rows, i), setdiff(cc$ir_rows, i), m$fa_rows, m$stream, cand_per_pos)
        return(cc$u - lg_value(m, c(r$rows, setdiff(cc$ir_rows, i)))$U)
      }
      if (!cc$full_roster) return(lg_u_tops(m, lg_tops_insert(cc$full, pos[i], m$sim$P[i, ])) - cc$u)
      best <- cc$u
      for (k in seq_along(cc$rows)) {
        best <- max(best, lg_u_tops(m, lg_tops_insert(cc$without[[k]], pos[i], m$sim$P[i, ])))
      }
      best - cc$u
    }, 0)
  })
  mat <- do.call(cbind, out)
  colnames(mat) <- names(m$state)
  tibble::tibble(row = rows, player_id = m$sim$players$player_id[rows], player_name = lg_player_label(m, rows),
                 position = pos[rows], owner = owner[rows]) |>
    dplyr::bind_cols(tibble::as_tibble(mat, .name_repair = "minimal") |> stats::setNames(paste0("team_", colnames(mat))))
}

lg_owner <- function(m) {
  own <- rep(NA_integer_, nrow(m$sim$players))
  for (t in names(m$state)) own[c(m$state[[t]]$rows, m$state[[t]]$ir_rows)] <- as.integer(t)
  own
}

#' Candidate players of a team for trade search: generic VOR or own-team MTV above
#' a minimum, top `top_n` by generic trade value (non-IR players only).
lg_trade_candidates <- function(m, team, mtv = NULL, top_n = 12, min_vor = 5, min_mtv = 2) {
  s <- m$state[[as.character(team)]]
  r <- s$rows
  g <- m$generic
  vor <- if (is.null(g)) m$sim$ros[r] else dplyr::coalesce(g$vor[match(m$sim$players$player_id[r], g$player_id)], 0)
  tv <- if (is.null(g)) vor else dplyr::coalesce(g$trade_value[match(m$sim$players$player_id[r], g$player_id)], 0)
  own <- if (!is.null(mtv)) mtv[[paste0("team_", team)]][match(r, mtv$row)] else rep(NA, length(r))
  keep <- vor > min_vor | dplyr::coalesce(own, 0) > min_mtv
  r <- r[keep]
  tv <- tv[keep]
  r[order(-tv)][seq_len(min(length(r), top_n))]
}

lg_tv <- function(m, rows) {
  g <- m$generic
  if (is.null(g)) return(sum(m$sim$ros[rows]))
  sum(dplyr::coalesce(g$trade_value[match(m$sim$players$player_id[rows], g$player_id)], 0))
}

#' Full evaluation of a candidate trade (no explanations): deltas for both teams.
lg_eval_trade <- function(m, team_a, ga, team_b, gb, horizon = "full") {
  tr <- lg_apply_trade(m, team_a, ga, team_b, gb)
  seg <- function(v) switch(horizon, full = v$U, regular = v$regular, playoffs = v$playoffs)
  ua <- seg(lg_value(m, c(tr$a$rows, tr$a$ir_rows), tr$stream)) - seg(m$base[[as.character(team_a)]])
  ub <- seg(lg_value(m, c(tr$b$rows, tr$b$ir_rows), tr$stream)) - seg(m$base[[as.character(team_b)]])
  c(delta_a = ua, delta_b = ub, n_drop = length(tr$a$dropped) + length(tr$b$dropped),
    n_add = length(tr$a$added) + length(tr$b$added))
}

lg_combos <- function(x, sizes) {
  out <- list()
  for (k in sizes) if (length(x) >= k) out <- c(out, utils::combn(x, k, simplify = FALSE))
  out
}

#' Search trades between two teams. Structures: sizes sent by A x sizes sent by B
#' (default 1-for-1, 2-for-1, 1-for-2, 2-for-2). Pruning: generic display-value
#' balance within `tv_band`, then the `max_eval` most promising candidates by the
#' MTV approximation min(approx dA, approx dB) are fully evaluated.
lg_trade_search <- function(m, team_a, team_b, mtv = NULL, sizes_a = 1:2, sizes_b = 1:2, top_n = 12,
                            tv_band = 40, max_eval = 250, eps = 5, strong = 20, horizon = "full") {
  team_a <- lg_find_team(m, team_a)
  team_b <- lg_find_team(m, team_b)
  ca <- lg_trade_candidates(m, team_a, mtv, top_n)
  cb <- lg_trade_candidates(m, team_b, mtv, top_n)
  mtv <- mtv %||% lg_mtv_matrix(m, unique(c(ca, cb)))
  mv <- function(rows, team) sum(mtv[[paste0("team_", team)]][match(rows, mtv$row)], na.rm = TRUE)
  pa <- lg_combos(ca, sizes_a)
  pb <- lg_combos(cb, sizes_b)
  grid <- tidyr::expand_grid(i = seq_along(pa), j = seq_along(pb))
  grid$tv_a <- vapply(grid$i, function(i) lg_tv(m, pa[[i]]), 0)
  grid$tv_b <- vapply(grid$j, function(j) lg_tv(m, pb[[j]]), 0)
  grid <- grid[abs(grid$tv_a - grid$tv_b) <= tv_band, ]
  if (!nrow(grid)) return(tibble::tibble())
  # MTV approximation (ignores interactions between moved players and roster resolution)
  grid$approx_a <- vapply(seq_len(nrow(grid)), function(k) mv(pb[[grid$j[k]]], team_a) - mv(pa[[grid$i[k]]], team_a), 0)
  grid$approx_b <- vapply(seq_len(nrow(grid)), function(k) mv(pa[[grid$i[k]]], team_b) - mv(pb[[grid$j[k]]], team_b), 0)
  grid <- grid[order(-pmin(grid$approx_a, grid$approx_b), -(grid$approx_a + grid$approx_b)), ]
  grid <- utils::head(grid, max_eval)
  res <- purrr::map(seq_len(nrow(grid)), function(k) {
    ga <- pa[[grid$i[k]]]
    gb <- pb[[grid$j[k]]]
    e <- lg_eval_trade(m, team_a, ga, team_b, gb, horizon)
    tibble::tibble(a_gives = paste(lg_player_label(m, ga), collapse = " + "), b_gives = paste(lg_player_label(m, gb), collapse = " + "),
                   a_rows = list(ga), b_rows = list(gb), n_players = length(ga) + length(gb),
                   tv_a_gives = grid$tv_a[k], tv_b_gives = grid$tv_b[k],
                   delta_a = e[["delta_a"]], delta_b = e[["delta_b"]], approx_a = grid$approx_a[k], approx_b = grid$approx_b[k],
                   n_drop = e[["n_drop"]], n_add = e[["n_add"]])
  }) |>
    purrr::list_rbind()
  res |>
    dplyr::mutate(surplus = .data$delta_a + .data$delta_b, balance = .data$delta_a - .data$delta_b,
                  classification = lg_classify(.data$delta_a, .data$delta_b, eps, strong),
                  win_win = .data$delta_a > 0 & .data$delta_b > 0, fair = abs(.data$balance) <= eps) |>
    dplyr::arrange(dplyr::desc(.data$win_win), dplyr::desc(.data$surplus), dplyr::desc(pmin(.data$delta_a, .data$delta_b)),
                   .data$n_players)
}

#' What could `me` offer for a target player on another team? Packages of 1-3 of my
#' candidates within `tv_band` of the target's generic value; kept if the target's
#' team does not lose more than eps; ranked by my gain.
lg_target_offers <- function(m, me, target, mtv = NULL, sizes = 1:3, top_n = 10, tv_band = 25, max_eval = 120,
                             eps = 5, strong = 20, horizon = "full") {
  me <- lg_find_team(m, me)
  x <- lg_find_player(m, target)
  owner <- lg_owner(m)[x]
  if (is.na(owner)) cli::cli_abort("{lg_player_label(m, x)} is a free agent: add him instead of trading.")
  if (owner == me) cli::cli_abort("{lg_player_label(m, x)} is already on your team.")
  cand <- lg_trade_candidates(m, me, mtv, top_n)
  mtv <- mtv %||% lg_mtv_matrix(m, unique(c(cand, x)))
  mv <- function(rows, team) sum(mtv[[paste0("team_", team)]][match(rows, mtv$row)], na.rm = TRUE)
  tvx <- lg_tv(m, x)
  pk <- Filter(function(p) abs(lg_tv(m, p) - tvx) <= tv_band, lg_combos(cand, sizes))
  if (!length(pk)) return(tibble::tibble())
  approx <- vapply(pk, function(p) min(mv(x, me) - mv(p, me), mv(p, owner) - mv(x, owner)), 0)
  pk <- pk[order(-approx)][seq_len(min(length(pk), max_eval))]
  purrr::map(pk, function(p) {
    e <- lg_eval_trade(m, me, p, owner, x, horizon)
    tibble::tibble(offer = paste(lg_player_label(m, p), collapse = " + "), offer_rows = list(p), target = lg_player_label(m, x),
                   target_team = lg_team_label(m, owner), tv_offer = lg_tv(m, p), tv_target = tvx,
                   delta_me = e[["delta_a"]], delta_them = e[["delta_b"]], n_drop = e[["n_drop"]], n_add = e[["n_add"]])
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(classification = lg_classify(.data$delta_me, .data$delta_them, eps, strong)) |>
    dplyr::filter(.data$delta_them >= -eps) |>
    dplyr::arrange(dplyr::desc(.data$delta_me), dplyr::desc(.data$delta_them))
}

#' Where could `me` sell a player? Teams ranked by MTV of the player; for the top
#' teams, returns of 1-2 of their candidates that improve them, ranked by my gain.
lg_sell_destinations <- function(m, me, player, mtv = NULL, n_teams = 4, sizes = 1:2, top_n = 10, tv_band = 30,
                                 eps = 5, strong = 20, horizon = "full") {
  me <- lg_find_team(m, me)
  x <- lg_find_player(m, player)
  if (!x %in% c(m$state[[as.character(me)]]$rows, m$state[[as.character(me)]]$ir_rows)) {
    cli::cli_abort("{lg_player_label(m, x)} is not on your team.")
  }
  others <- setdiff(as.integer(names(m$state)), me)
  mtv <- mtv %||% lg_mtv_matrix(m, x)
  dest <- tibble::tibble(team_id = others, team = vapply(others, function(t) lg_team_label(m, t), ""),
                         mtv = vapply(others, function(t) mtv[[paste0("team_", t)]][match(x, mtv$row)], 0)) |>
    dplyr::arrange(dplyr::desc(.data$mtv))
  offers <- purrr::map(utils::head(dest$team_id, n_teams), function(t) {
    cand <- lg_trade_candidates(m, t, NULL, top_n)
    pk <- Filter(function(p) abs(lg_tv(m, p) - lg_tv(m, x)) <= tv_band, lg_combos(cand, sizes))
    purrr::map(pk, function(p) {
      e <- lg_eval_trade(m, me, x, t, p, horizon)
      tibble::tibble(team = lg_team_label(m, t), team_id = t, returns = paste(lg_player_label(m, p), collapse = " + "),
                     return_rows = list(p), tv_return = lg_tv(m, p), delta_me = e[["delta_a"]], delta_them = e[["delta_b"]])
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
  if (nrow(offers)) {
    offers <- offers |>
      dplyr::mutate(classification = lg_classify(.data$delta_me, .data$delta_them, eps, strong)) |>
      dplyr::filter(.data$delta_them > 0) |>
      dplyr::arrange(dplyr::desc(.data$delta_me))
  }
  list(player = lg_player_label(m, x), destinations = dest, offers = offers)
}

#' Projection-based power rankings with positional breakdown.
lg_power_rankings <- function(m) {
  purrr::map(names(m$state), function(t) {
    s <- m$state[[t]]
    a <- lg_attribution(m, c(s$rows, s$ir_rows))
    v <- m$base[[t]]
    bypos <- a$players |> dplyr::summarise(pts = sum(.data$started_pts), .by = "position")
    pp <- stats::setNames(bypos$pts, bypos$position)
    bench <- a$players |> dplyr::filter(.data$starts < 0.5 * pmax(.data$games, 1))
    tibble::tibble(team_id = as.integer(t), team = lg_team_label(m, as.integer(t)), U = v$U, U_regular = v$regular,
                   U_playoffs = v$playoffs, starter_points = v$U - a$streamed_points, streamed_points = a$streamed_points,
                   QB = pp["QB"] %||% 0, RB = pp["RB"] %||% 0, WR = pp["WR"] %||% 0, TE = pp["TE"] %||% 0,
                   flex_points = sum(a$slot_points[grepl("FLEX|RB_WR|WR_TE|SUPERFLEX", names(a$slot_points))]),
                   bench_points = sum(bench$started_pts), bench_ros_points = sum(bench$ros_points),
                   roster_skill = length(s$rows), ir = length(s$ir_rows))
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(dplyr::across(c("QB", "RB", "WR", "TE"), ~ unname(as.numeric(.x)))) |>
    dplyr::arrange(dplyr::desc(.data$U)) |>
    dplyr::mutate(rank = dplyr::row_number(), .before = 1)
}

#' Team needs, from lineup attribution and marginal utility (nothing declared).
lg_team_needs <- function(m, team, rankings = NULL, cand_per_pos = 6) {
  team <- lg_find_team(m, team)
  rankings <- rankings %||% lg_power_rankings(m)
  s <- m$state[[as.character(team)]]
  a <- lg_attribution(m, c(s$rows, s$ir_rows))
  slots <- purrr::map(names(m$state), function(t) {
    st <- m$state[[t]]
    sp <- lg_attribution(m, c(st$rows, st$ir_rows))$slot_points
    tibble::tibble(team_id = as.integer(t), slot = names(sp), pts = unname(sp))
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(league_median = stats::median(.data$pts), .by = "slot") |>
    dplyr::filter(.data$team_id == team) |>
    dplyr::mutate(vs_median = .data$pts - .data$league_median) |>
    dplyr::arrange(.data$vs_median)
  pl <- a$players |> dplyr::mutate(ppg = ifelse(.data$games > 0, .data$ros_points / .data$games, 0))
  ded <- vapply(m$spec$positions, function(p) sum(vapply(m$league$slots, function(x) if (identical(x$eligible, p)) x$count else 0L, 0L)), 0)
  fa_ppg <- vapply(m$spec$positions, function(p) {
    r <- m$fa_rows[m$sim$players$position[m$fa_rows] == p]
    if (!length(r)) return(0)
    max(m$sim$ros[r] / pmax(rowSums(m$sim$E[r, , drop = FALSE] > 0), 1))
  }, 0)
  depth <- purrr::map(m$spec$positions, function(p) {
    x <- pl[pl$position == p, ]
    x <- x[order(-x$ppg), ]
    n <- max(1, ded[[p]])
    # the backup is the better of the next rostered player and the best free agent
    tibble::tibble(position = p, n_rostered = nrow(x),
                   starter_ppg = if (nrow(x) >= 1) mean(utils::head(x$ppg, n)) else 0,
                   rostered_backup_ppg = if (nrow(x) > n) x$ppg[n + 1] else 0, best_fa_ppg = fa_ppg[[p]],
                   best_backup_ppg = max(if (nrow(x) > n) x$ppg[n + 1] else 0, fa_ppg[[p]]),
                   bench_started_pts = sum(x$started_pts[x$starts < 0.5 * pmax(x$games, 1)]))
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(starter_to_backup_drop = .data$starter_ppg - .data$best_backup_ppg)
  # best waiver upgrade: free agent added with the best forced drop
  pos <- m$sim$players$position
  fa <- unlist(lapply(m$spec$positions, function(p) {
    r <- m$fa_rows[pos[m$fa_rows] == p]
    r[order(-m$sim$ros[r])][seq_len(min(length(r), cand_per_pos))]
  }))
  ups <- purrr::map(fa, function(f) {
    r <- lg_resolve(m, team, c(s$rows, f), s$ir_rows, setdiff(m$fa_rows, f), m$stream, allow_adds = FALSE)
    tibble::tibble(add = lg_player_label(m, f), position = pos[f],
                   drop = paste(lg_player_label(m, r$dropped), collapse = " + "),
                   gain = lg_value(m, c(r$rows, s$ir_rows))$U - m$base[[as.character(team)]]$U)
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(dplyr::desc(.data$gain))
  list(team = lg_team_label(m, team), rank = rankings$rank[rankings$team_id == team], slots = slots, depth = depth,
       weakest_slot = slots$slot[1], strongest_slot = slots$slot[nrow(slots)],
       deepest_bench_position = depth$position[which.max(depth$bench_started_pts)],
       largest_drop_position = depth$position[which.max(depth$starter_to_backup_drop)],
       waiver_upgrades = utils::head(ups, 5), players = a$players)
}
