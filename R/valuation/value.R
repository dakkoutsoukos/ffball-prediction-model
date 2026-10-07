# Valuation: VOR, VAS, scarcity and the display scale ------------------------------------
#   weekly VOR_i(t) = E_i(t) - R_p(t)     R = waiver baseline (exchange over undrafted players)
#   ROS VOR         = sum_t max(0, VOR_i(t))   (primary; a manager starts the free
#                     replacement in any week the player is expected below it)
#   ROS VOR (raw)   = sum_t VOR_i(t)          (no substitution; reported)
#   weekly VAS_i(t) = E_i(t) - S_p(t)     S = marginal-starter baseline (all non-starters)
#   ROS VAS         = sum_t VAS_i(t)          (unfloored; negative = not startable at league level)

#' Player-week values joined to the weekly baselines.
val_weekly_values <- function(weekly, baselines) {
  weekly |>
    dplyr::left_join(dplyr::select(baselines, "week", "position", "S", "R"), by = c("week", "position")) |>
    dplyr::mutate(vor_week = .data$E - .data$R, vor_plus = pmax(0, .data$vor_week), vas_week = .data$E - .data$S,
                  league_starter = .data$E > 0 & .data$E >= .data$S)
}

#' ROS aggregates per player for the full horizon and its segments.
val_player_values <- function(wv, league, current_week, players = NULL) {
  seg <- list(regular = val_horizon_weeks(league, current_week, "regular"),
              playoffs = val_horizon_weeks(league, current_week, "playoffs"),
              full = val_horizon_weeks(league, current_week, "full"))
  agg <- function(d) {
    dplyr::summarise(d,
      ros_points = sum(.data$E), games_remaining = sum(.data$has_game),
      replacement_points = sum(.data$R[.data$has_game]), vor = sum(.data$vor_plus), vor_raw = sum(.data$vor_week),
      vas = sum(.data$vas_week), starter_weeks = sum(.data$league_starter),
      .by = c("player_id", "position"))
  }
  full <- agg(dplyr::filter(wv, .data$week %in% seg$full))
  bye <- wv |>
    dplyr::filter(.data$week %in% seg$full, !.data$has_game) |>
    dplyr::summarise(bye_weeks = paste(.data$week, collapse = ","), .by = "player_id")
  cur <- wv |>
    dplyr::filter(.data$week == current_week) |>
    dplyr::select("player_id", current_week_points = "E", current_source = "source")
  out <- full |>
    dplyr::left_join(dplyr::select(agg(dplyr::filter(wv, .data$week %in% seg$regular)), "player_id",
                                   ros_points_regular = "ros_points", vor_regular = "vor"), by = "player_id") |>
    dplyr::left_join(dplyr::select(agg(dplyr::filter(wv, .data$week %in% seg$playoffs)), "player_id",
                                   ros_points_playoffs = "ros_points", vor_playoffs = "vor"), by = "player_id") |>
    dplyr::left_join(bye, by = "player_id") |>
    dplyr::left_join(cur, by = "player_id") |>
    dplyr::mutate(dplyr::across(c("ros_points_regular", "vor_regular", "ros_points_playoffs", "vor_playoffs"),
                                ~ dplyr::coalesce(.x, 0)),
                  points_per_game = ifelse(.data$games_remaining > 0, .data$ros_points / .data$games_remaining, 0)) |>
    dplyr::arrange(dplyr::desc(.data$vor), dplyr::desc(.data$ros_points), .data$player_id) |>
    dplyr::mutate(overall_rank = dplyr::row_number()) |>
    dplyr::mutate(position_rank = dplyr::row_number(), .by = "position")
  if (!is.null(players)) out <- dplyr::left_join(out, players, by = c("player_id", "position"))
  out
}

#' Monotone map f from VOR to generic roster utility (MRU): isotonic
#' regression of MRU on VOR over players with VOR > 0, then a monotone
#' (Fritsch-Carlson) spline through the isotonic block means. f(0) = 0.
val_fit_display_map <- function(vor, mru) {
  ok <- is.finite(vor) & is.finite(mru) & vor > 0
  if (sum(ok) < 10) return(list(type = "identity", f = function(x) pmax(0, x)))
  o <- order(vor[ok])
  x <- vor[ok][o]
  y <- pmax(0, mru[ok][o])
  iso <- stats::isoreg(x, y)
  yf <- iso$yf
  # one knot per isotonic block (mean VOR of the block, block level)
  blk <- cumsum(c(TRUE, diff(yf) != 0))
  kx <- c(0, tapply(x, blk, mean))
  ky <- c(0, tapply(yf, blk, mean))
  keep <- !duplicated(kx)
  sf <- stats::splinefun(kx[keep], ky[keep], method = "monoH.FC")
  xmax <- max(kx)
  slope <- if (length(kx) >= 3) (ky[length(ky)] - ky[length(ky) - 1]) / max(kx[length(kx)] - kx[length(kx) - 1], 1e-9) else 1
  f <- function(v) {
    v <- pmax(0, v)
    ifelse(v <= xmax, pmax(0, sf(v)), sf(xmax) + slope * (v - xmax))
  }
  list(type = "isotonic_monotone_spline", f = f, knots = tibble::tibble(vor = kx[keep], mru = ky[keep]))
}

#' Display trade value 0-100: monotone transformation of ROS VOR.
val_trade_value <- function(vor, map) {
  top <- map$f(max(vor, na.rm = TRUE))
  if (!is.finite(top) || top <= 0) return(rep(0, length(vor)))
  round(100 * map$f(vor) / top, 1)
}

#' Positional value curves (rank 1..n) for the scarcity diagnostics.
val_value_curves <- function(values, n = c(QB = 30, RB = 60, WR = 80, TE = 30)) {
  values |>
    dplyr::filter(.data$position_rank <= n[.data$position]) |>
    dplyr::select("position", "position_rank", "player_id", dplyr::any_of(c("player_name", "espn_name")),
                  "ros_points", "vor", "vas", dplyr::any_of(c("mru", "trade_value")))
}

#' Scarcity summary per position: elite, marginal starter and replacement
#' levels (ROS points), drop-offs, counts above VOR thresholds, and FLEX use.
val_scarcity <- function(values, baselines, league, current_week) {
  wk <- val_horizon_weeks(league, current_week, "full")
  # per-week levels averaged over the horizon (bye weeks change them week to week)
  lvl <- dplyr::filter(baselines, .data$week %in% wk) |>
    dplyr::summarise(starter_level = mean(.data$S), replacement_level = mean(.data$R),
                     league_starters = mean(.data$n_starters), in_flex = mean(.data$n_in_multi_slots),
                     .by = "position")
  values |>
    dplyr::arrange(dplyr::desc(.data$vor)) |>
    dplyr::summarise(
      elite_ppg = mean(utils::head(.data$points_per_game, 3)),
      elite_vor = mean(utils::head(.data$vor, 3)),
      vor_rank12 = .data$vor[12] %||% NA_real_,
      n_vor_gt_0 = sum(.data$vor > 0), n_vor_gt_25 = sum(.data$vor > 25), n_vor_gt_50 = sum(.data$vor > 50),
      n_vor_gt_100 = sum(.data$vor > 100),
      .by = "position") |>
    dplyr::left_join(lvl, by = "position") |>
    dplyr::mutate(elite_minus_replacement_ppg = .data$elite_ppg - .data$replacement_level,
                  starter_minus_replacement_ppg = .data$starter_level - .data$replacement_level) |>
    dplyr::arrange(match(.data$position, VAL_POSITIONS))
}

#' Full valuation for one league: baselines from the simulated rostered pool,
#' weekly and ROS values, MRU and the display scale.
val_value_league <- function(weekly, league, current_week, sim_cfg, players = NULL, with_mru = TRUE,
                             mru_top = c(QB = 40, RB = 90, WR = 110, TE = 40), pool = sim_cfg$pool %||% "proportional",
                             sim = NULL) {
  weekly <- dplyr::filter(weekly, .data$week %in% val_horizon_weeks(league, current_week))
  sim <- sim %||% val_sim_setup(weekly, sim_cfg$sims, sim_cfg$seed)
  ls <- val_league_sim(sim, league, sim_cfg$candidates_per_position, sim_cfg$max_iterations, pool = pool)
  base <- val_weekly_baselines(weekly, league, rostered = ls$rostered_pool)
  wv <- val_weekly_values(weekly, base)
  values <- val_player_values(wv, league, current_week, players)
  values$rostered <- values$player_id %in% ls$rostered_pool
  values$sim_team <- ls$rosters$team[match(values$player_id, ls$rosters$player_id)]
  map <- list(type = "identity", f = function(x) pmax(0, x))
  if (with_mru) {
    rows <- which(sim$players$player_id %in% dplyr::filter(values, .data$position_rank <= mru_top[.data$position])$player_id)
    m <- val_mru(ls, rows)
    values$mru <- m[match(values$player_id, sim$players$player_id[rows])]
    values$mru[is.na(values$mru)] <- 0
    map <- val_fit_display_map(values$vor, values$mru)
  }
  values$trade_value <- val_trade_value(values$vor, map)
  list(values = values, weekly_values = wv, baselines = base, league_sim = ls, display_map = map,
       scarcity = val_scarcity(values, base, league, current_week))
}
