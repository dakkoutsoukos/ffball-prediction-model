# Valuation: historical backtest (VE2 item 7) ------------------------------------------
# At weeks `val_weeks` of each historical season, value the pool exactly as a
# live run would (extrapolated future weeks; historical seasons have no posted
# future projections), then compare projected VOR with REALIZED decision-based
# VOR:
#   realized VOR_i = sum over weeks the projection said "above replacement"
#                    (E_i(t) > R_p(t)) of [actual_i(t) - realized replacement_p(t)]
#   realized replacement_p(t) = mean actual points of the 3 best-projected
#                    non-rostered players who could fill a vacated p spot (exchange)
# Parameters come from the development seasons only (2019-2023), so 2024-2025
# are out of sample; the generic league is the default league with its
# horizon ending in the season's last fantasy week.

#' League for a historical season: same slots, horizon ending at the season's
#' last fantasy week (16 for 17-week seasons, 17 after).
val_backtest_league <- function(league, season) {
  last <- val_season_last_week(season)
  val_league_override(league, list(regular_season_weeks = c(1, last - 3), playoff_weeks = c(last - 2, last)))
}

#' Weekly projected and actual points for one (season, w) from the study frame.
val_backtest_weekly <- function(frame, season, w, tabs) {
  pop <- dplyr::filter(frame$population, .data$season == !!season, .data$w == !!w)
  cur <- dplyr::filter(frame$current, .data$season == !!season, .data$week == !!w) |>
    dplyr::semi_join(pop, by = "gsis_id") |>
    dplyr::left_join(tabs$c0_tab, by = "position") |>
    dplyr::transmute(player_id = .data$gsis_id, .data$position, week = .data$week,
                     E = pmax(0, .data$c0 + .data$d0 * .data$espn_proj), A = 1, lvl = .data$E, actual = .data$pts)
  fut <- dplyr::filter(frame$future, .data$season == !!season, .data$w == !!w) |>
    dplyr::mutate(L = .data$L_avg4)
  fut <- val_apply_ros(fut, tabs$cd_tab, "L", val_ros_form(tabs)) |>
    dplyr::transmute(player_id = .data$gsis_id, .data$position, week = .data$t, E = .data$E, A = .data$A,
                     lvl = .data$lvl, actual = .data$pts)
  dplyr::bind_rows(cur, fut) |>
    dplyr::mutate(has_game = TRUE, proj_kind = ifelse(.data$week == w, "current_week", "extrapolated"),
                  source = "backtest")
}

#' Realized replacement per (week, position): mean actual of the `k` best-projected
#' non-rostered players eligible to fill a vacated spot (exchange rule).
val_realized_replacement <- function(weekly, league, rostered, k = 3) {
  hall <- val_hall_table(league)
  weekly <- dplyr::arrange(weekly, .data$week, .data$player_id)
  purrr::map(split(weekly, weekly$week), function(d) {
    ros <- d$player_id %in% rostered
    st <- val_allocate(ifelse(ros, d$E, 0), d$position, hall)
    counts <- stats::setNames(vapply(hall$positions, function(p) sum(st & d$position == p), 0), hall$positions)
    ex <- val_exchange_matrix(counts, hall)
    tibble::tibble(week = d$week[1], position = hall$positions, R_realized = vapply(hall$positions, function(p) {
      q <- if (counts[[p]] >= 1) hall$positions[ex[p, ]] else p
      i <- which(!ros & d$position %in% q)
      if (!length(i)) return(0)
      i <- i[order(-d$E[i])][seq_len(min(k, length(i)))]
      mean(d$actual[i])
    }, 0))
  }) |>
    purrr::list_rbind()
}

#' Backtest one (season, w): projected and realized VOR per player.
val_backtest_one <- function(frame, season, w, tabs, league) {
  lg <- val_backtest_league(league, season)
  weekly <- val_backtest_weekly(frame, season, w, tabs)
  weekly <- dplyr::filter(weekly, .data$week %in% val_horizon_weeks(lg, w))
  sim <- val_sim_setup(dplyr::select(weekly, -"actual"), sims = 1, seed = 1)
  pool <- val_proportional_pool(sim, lg)
  rostered <- sim$players$player_id[pool$rows]
  base <- val_weekly_baselines(dplyr::select(weekly, -"actual"), lg, rostered)
  rr <- val_realized_replacement(weekly, lg, rostered)
  weekly |>
    dplyr::left_join(dplyr::select(base, "week", "position", "R"), by = c("week", "position")) |>
    dplyr::left_join(rr, by = c("week", "position")) |>
    dplyr::mutate(start = .data$E > .data$R) |>
    dplyr::summarise(
      ros_points = sum(.data$E), ros_actual = sum(.data$actual),
      vor = sum(pmax(0, .data$E - .data$R)),
      vor_realized = sum(ifelse(.data$start, .data$actual - .data$R_realized, 0)),
      .by = c("player_id", "position")) |>
    dplyr::mutate(season = as.integer(season), w = as.integer(w), rostered = .data$player_id %in% rostered,
                  league_starters = list(pool$counts)) |>
    dplyr::arrange(dplyr::desc(.data$vor)) |>
    dplyr::mutate(position_rank = dplyr::row_number(), .by = "position")
}

#' Full backtest and its pre-specified summaries.
val_backtest <- function(frame, league, level = "L_avg4", opponent = TRUE, form = "quadratic",
                         seasons = 2019:2025, val_weeks = c(4, 8, 12), dev = 2019:2023) {
  tabs <- val_ros_tables(val_derive_ros_params(frame, level, opponent, form = form, seasons = dev))
  rows <- purrr::map(seasons, function(s) purrr::map(val_weeks, function(w) val_backtest_one(frame, s, w, tabs, league))) |>
    purrr::list_flatten() |>
    purrr::list_rbind() |>
    dplyr::select(-"league_starters") |>
    dplyr::mutate(split = ifelse(.data$season %in% dev, "dev", "check"))
  # each position's top 2 x league starters: with bench = starters (7 + 7), the
  # proportional rostered count at a position is exactly twice its league starters
  k_tab <- rows |>
    dplyr::filter(.data$rostered) |>
    dplyr::count(.data$season, .data$w, .data$position, name = "k")
  top <- rows |>
    dplyr::left_join(k_tab, by = c("season", "w", "position")) |>
    dplyr::filter(.data$position_rank <= .data$k)
  calib <- top |>
    dplyr::summarise(n = dplyr::n(), projected = mean(.data$vor), realized = mean(.data$vor_realized),
                     ratio = sum(.data$vor_realized) / sum(.data$vor),
                     slope = unname(stats::coef(stats::lm(vor_realized ~ vor))[2]), .by = c("split", "position"))
  pooled <- top |>
    dplyr::summarise(ratio = sum(.data$vor_realized) / sum(.data$vor), .by = "split")
  calib <- dplyr::left_join(calib, dplyr::rename(pooled, pooled_ratio = "ratio"), by = "split") |>
    dplyr::mutate(flag_bias = abs(.data$ratio / .data$pooled_ratio - 1) > 0.25)
  spear <- rows |>
    dplyr::filter(.data$rostered) |>
    dplyr::summarise(rho = suppressWarnings(stats::cor(.data$vor, .data$vor_realized, method = "spearman")),
                     .by = c("split", "season", "w", "position")) |>
    dplyr::summarise(rho = mean(.data$rho, na.rm = TRUE), .by = c("split", "position"))
  qb_share <- rows |>
    dplyr::mutate(rank_proj = rank(-.data$vor, ties.method = "first"),
                  rank_real = rank(-.data$vor_realized, ties.method = "first"), .by = c("season", "w")) |>
    dplyr::summarise(qb_top30_projected = sum(.data$position == "QB" & .data$rank_proj <= 30),
                     qb_top30_realized = sum(.data$position == "QB" & .data$rank_real <= 30),
                     te_top30_projected = sum(.data$position == "TE" & .data$rank_proj <= 30),
                     te_top30_realized = sum(.data$position == "TE" & .data$rank_real <= 30),
                     .by = c("split", "season", "w")) |>
    dplyr::summarise(dplyr::across(dplyr::starts_with(c("qb_", "te_")), mean), .by = "split")
  list(rows = rows, calibration = calib, spearman = spear, top30_shares = qb_share)
}
