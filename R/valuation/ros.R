# Valuation: rest-of-season (ROS) forecasts ---------------------------------------------
# Future-week expectation (docs/valuation_methodology.md, VE1):
#   E_i(t) = G_i(t) * A_p(h) * (c_{p,b(h)} + d_{p,b(h)} * X_i(t) [+ g_p * X * (opp - 1)])
#     h = t - w (valuation week w), b(h) in {1, 2-3, 4-7, 8+}
#     G = 0 on a bye or when ESPN posts 0 for a game week
#     X = ESPN's posted future-week projection, else the extrapolated level L
#     A = P(stat line at w+h | projected > 0 at w), historical attrition
#     c, d = historical "points if active" calibration
# The current week uses the provider's own calibrated projection.

VAL_RELEVANT_RANK <- c(QB = 24, RB = 48, WR = 60, TE = 24)
VAL_LEVELS <- c("L_cur", "L_avg4", "L_blend")

val_h_bucket <- function(h) {
  as.character(cut(h, c(0.5, 1.5, 3.5, 7.5, Inf), labels = c("h1", "h2_3", "h4_7", "h8p")))
}

#' Last fantasy week used historically: 17-week seasons (<= 2020) end the
#' fantasy year in week 16, 18-week seasons in week 17.
val_season_last_week <- function(season) ifelse(season <= 2020, 16L, 17L)

#' ESPN projections mapped to GSIS ids (crosswalk: ID-only, ambiguous dropped).
val_mapped_projections <- function(espn_weekly, crosswalk) {
  ids <- dplyr::filter(crosswalk, !is.na(.data$gsis_id)) |> dplyr::select("espn_id", "gsis_id")
  espn_weekly |>
    dplyr::filter(.data$position %in% VAL_POSITIONS, !is.na(.data$espn_proj)) |>
    dplyr::inner_join(ids, by = "espn_id", relationship = "many-to-one") |>
    dplyr::select("season", "week", "gsis_id", "espn_id", "espn_name", "position", "espn_proj") |>
    assert_unique_key(c("season", "week", "gsis_id"), "mapped ESPN projections")
}

#' Candidate levels at every (season, week, player) with a positive projection.
#'   L_cur   ESPN projection that week
#'   L_avg4  mean of the last up-to-4 positive projections (weeks <= w, same season)
#'   L_blend 0.5 L_avg4 + 0.5 season-to-date points per game with a stat line
#'           (weeks < w, at least 3 games), else L_avg4
val_levels <- function(proj, player_stats) {
  pos <- proj |>
    dplyr::filter(.data$espn_proj > 0) |>
    dplyr::arrange(.data$season, .data$gsis_id, .data$week) |>
    dplyr::mutate(k = dplyr::row_number(), cs = cumsum(.data$espn_proj), .by = c("season", "gsis_id")) |>
    dplyr::mutate(L_cur = .data$espn_proj,
                  L_avg4 = (.data$cs - dplyr::lag(.data$cs, 4, default = 0)) / pmin(.data$k, 4),
                  .by = c("season", "gsis_id")) |>
    dplyr::select(-"k", -"cs")
  cum <- player_stats |>
    dplyr::select("season", "week", "gsis_id", "fantasy_pts") |>
    dplyr::arrange(.data$season, .data$gsis_id, .data$week) |>
    dplyr::mutate(cum_pts = cumsum(.data$fantasy_pts), cum_games = dplyr::row_number(),
                  .by = c("season", "gsis_id")) |>
    dplyr::select("season", "gsis_id", stat_week = "week", "cum_pts", "cum_games")
  pos |>
    dplyr::left_join(cum, by = dplyr::join_by("season", "gsis_id", closest("week" > "stat_week"))) |>
    dplyr::mutate(
      cum_games = dplyr::coalesce(.data$cum_games, 0L),
      ppg = ifelse(.data$cum_games > 0, .data$cum_pts / .data$cum_games, NA_real_),
      L_blend = ifelse(.data$cum_games >= 3, 0.5 * .data$L_avg4 + 0.5 * .data$ppg, .data$L_avg4)
    ) |>
    dplyr::select(-"stat_week", -"cum_pts")
}

#' Opponent factor at each (season, week w, defense, position): shrunk
#' season-to-date fantasy points allowed to the position per game through
#' week w - 1, relative to the league mean (prior: `k` games at the mean).
val_opponent_factor <- function(player_stats, team_games, seasons, weeks = 1:18, k = 4) {
  allowed <- player_stats |>
    dplyr::filter(.data$season %in% seasons) |>
    dplyr::mutate(position = dplyr::if_else(.data$stats_position == "FB", "RB", .data$stats_position)) |>
    dplyr::filter(.data$position %in% VAL_POSITIONS) |>
    dplyr::rename(defense = "opponent") |>
    dplyr::summarise(pts = sum(.data$fantasy_pts), .by = c("season", "week", "defense", "position"))
  games <- team_games |>
    dplyr::filter(.data$season %in% seasons, .data$game_final) |>
    dplyr::distinct(.data$season, .data$week, defense = .data$team)
  grid <- tidyr::expand_grid(dplyr::distinct(games, .data$season, .data$defense), w = weeks, position = VAL_POSITIONS)
  g <- grid |>
    dplyr::left_join(games, by = c("season", "defense"), relationship = "many-to-many") |>
    dplyr::filter(.data$week < .data$w) |>
    dplyr::count(.data$season, .data$defense, .data$w, .data$position, name = "games")
  a <- grid |>
    dplyr::left_join(allowed, by = c("season", "defense", "position"), relationship = "many-to-many") |>
    dplyr::filter(.data$week < .data$w) |>
    dplyr::summarise(allowed = sum(.data$pts), .by = c("season", "defense", "w", "position"))
  grid |>
    dplyr::left_join(g, by = c("season", "defense", "w", "position")) |>
    dplyr::left_join(a, by = c("season", "defense", "w", "position")) |>
    dplyr::mutate(games = dplyr::coalesce(.data$games, 0L), allowed = dplyr::coalesce(.data$allowed, 0)) |>
    dplyr::mutate(league_mean = sum(.data$allowed) / max(sum(.data$games), 1), .by = c("season", "w", "position")) |>
    dplyr::mutate(opp = ifelse(.data$league_mean > 0,
                               ((.data$allowed + k * .data$league_mean) / (.data$games + k)) / .data$league_mean, 1)) |>
    dplyr::select("season", w = "w", "defense", "position", "opp")
}

#' Historical study frame. `current`: every player-week with a positive ESPN
#' projection and a team game (h = 0 calibration). `future`: for valuation weeks
#' `val_weeks`, every later fantasy week in which the player's week-w team plays,
#' with the actual points (0 without a stat line) and the candidate levels.
val_history_frame <- function(espn_weekly, crosswalk, player_stats, rosters, team_games,
                              seasons = 2019:2025, val_weeks = 3:13) {
  proj <- dplyr::filter(val_mapped_projections(espn_weekly, crosswalk), .data$season %in% seasons)
  stats <- player_stats |>
    dplyr::filter(.data$season %in% seasons) |>
    dplyr::select("season", "week", "gsis_id", stat_team = "team", pts = "fantasy_pts")
  team_at <- proj |>
    dplyr::select("season", "week", "gsis_id") |>
    dplyr::left_join(dplyr::select(rosters, "season", "week", "gsis_id", "roster_team", "roster_status"),
                     by = c("season", "week", "gsis_id")) |>
    dplyr::left_join(dplyr::select(stats, "season", "week", "gsis_id", "stat_team"), by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(team = dplyr::coalesce(.data$roster_team, .data$stat_team)) |>
    dplyr::select("season", "week", "gsis_id", "team", "roster_status")
  tg <- dplyr::filter(team_games, .data$season %in% seasons) |>
    dplyr::select("season", "week", "team", "opponent")
  lv <- val_levels(proj, player_stats)

  current <- proj |>
    dplyr::filter(.data$espn_proj > 0) |>
    dplyr::inner_join(team_at, by = c("season", "week", "gsis_id")) |>
    dplyr::semi_join(tg, by = c("season", "week", "team")) |>
    dplyr::left_join(dplyr::select(stats, "season", "week", "gsis_id", "pts"), by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(active = !is.na(.data$pts), pts = dplyr::coalesce(.data$pts, 0),
                  rank = rank(-.data$espn_proj, ties.method = "first"), .by = c("season", "week", "position")) |>
    dplyr::mutate(relevant = .data$rank <= VAL_RELEVANT_RANK[.data$position])

  pop <- current |>
    dplyr::filter(.data$week %in% val_weeks, !is.na(.data$team)) |>
    dplyr::select("season", w = "week", "gsis_id", "position", "espn_name", "team", "roster_status", "rank", "relevant") |>
    dplyr::left_join(dplyr::select(lv, "season", w = "week", "gsis_id", dplyr::all_of(VAL_LEVELS), "cum_games", "ppg"),
                     by = c("season", "w", "gsis_id"))
  future <- pop |>
    dplyr::inner_join(dplyr::rename(tg, t = "week"), by = c("season", "team"), relationship = "many-to-many") |>
    dplyr::filter(.data$t > .data$w, .data$t <= val_season_last_week(.data$season)) |>
    dplyr::left_join(dplyr::select(stats, "season", t = "week", "gsis_id", "pts"), by = c("season", "t", "gsis_id")) |>
    dplyr::mutate(h = .data$t - .data$w, bucket = val_h_bucket(.data$h),
                  active = !is.na(.data$pts), pts = dplyr::coalesce(.data$pts, 0))
  opp <- val_opponent_factor(player_stats, team_games, seasons)
  future <- future |>
    dplyr::left_join(dplyr::rename(opp, opponent = "defense"), by = c("season", "w", "opponent", "position")) |>
    dplyr::mutate(opp = dplyr::coalesce(.data$opp, 1))
  list(current = current, future = future, population = pop)
}

#' Fit the future-week model for one level, by position and horizon bucket b.
#' form = "two_stage" (VE1b, production):
#'   A = plogis(a + e * log L)              P(stat line at t)
#'   m = c + d * L [+ g * L * (opp - 1)]    points if a stat line (least squares on those rows)
#'   E = A * m
#' form = "linear" (VE1a): E = c + d * L [+ g ...] on all rows; A as above is
#'   used only for the simulation's availability draws (lvl = E / A).
#' form = "quadratic" (VE1c): as linear plus q * L^2.
val_fit_ros <- function(future, level, seasons, opponent = FALSE, form = c("two_stage", "linear", "quadratic")) {
  form <- match.arg(form)
  d <- dplyr::filter(future, .data$season %in% seasons) |>
    dplyr::mutate(L = .data[[level]], Lopp = .data$L * (.data$opp - 1), logL = log(pmax(.data$L, 0.1)))
  cd <- purrr::map(VAL_POSITIONS, function(p) {
    x <- dplyr::filter(d, .data$position == p)
    xm <- if (form == "two_stage") dplyr::filter(x, .data$active) else x
    rhs <- c("0", "bucket", "bucket:L", if (form == "quadratic") "bucket:L2", if (opponent) "Lopp")
    f <- stats::lm(stats::reformulate(rhs, "pts"), data = dplyr::mutate(xm, L2 = .data$L^2))
    co <- stats::coef(f)
    b <- sort(unique(x$bucket))
    av <- purrr::map(b, function(bb) {
      xb <- dplyr::filter(x, .data$bucket == bb)
      stats::coef(suppressWarnings(stats::glm(active ~ logL, data = xb, family = stats::binomial())))
    })
    tibble::tibble(position = p, bucket = b, c = unname(co[paste0("bucket", b)]),
                   d = unname(co[paste0("bucket", b, ":L")]),
                   q = if (form == "quadratic") unname(co[paste0("bucket", b, ":L2")]) else 0,
                   g = if (opponent) unname(co[["Lopp"]]) else 0,
                   a = vapply(av, `[[`, 0, 1), e = vapply(av, `[[`, 0, 2),
                   n = as.integer(table(x$bucket)[b]))
  }) |>
    purrr::list_rbind()
  list(level = level, seasons = seasons, opponent = opponent, form = form, cd = cd)
}

#' Weekly expectations for rows with columns position, bucket, opp and the
#' level (or a posted value) in `x_col`. Returns E, A (P(active)) and lvl
#' (points if active), with E = A * lvl.
val_apply_ros <- function(rows, cd, x_col, form = "two_stage") {
  out <- rows |>
    dplyr::left_join(dplyr::select(cd, "position", "bucket", "c", "d", "q", "g", "a", "e"), by = c("position", "bucket")) |>
    dplyr::mutate(
      m = pmax(0, .data$c + .data$d * .data[[x_col]] + .data$q * .data[[x_col]]^2 +
                 .data$g * .data[[x_col]] * (.data$opp - 1)),
      A = stats::plogis(.data$a + .data$e * log(pmax(.data[[x_col]], 0.1)))
    )
  if (form == "two_stage") {
    out <- dplyr::mutate(out, E = .data$A * .data$m, lvl = .data$m)
  } else {
    # numerical guard A >= E / 60 keeps lvl = E / A finite
    out <- dplyr::mutate(out, E = .data$m, A = pmax(.data$A, pmin(1, .data$E / 60)),
                         lvl = ifelse(.data$A > 0, .data$E / .data$A, 0))
  }
  dplyr::select(out, -"c", -"d", -"q", -"g", -"a", -"e", -"m")
}

#' Weekly expectations for study rows from a fit.
val_predict_ros <- function(future, fit) {
  val_apply_ros(dplyr::mutate(future, L = .data[[fit$level]]), fit$cd, "L", fit$form %||% "two_stage")
}

#' ROS totals per (player, valuation week) and their errors.
val_ros_totals <- function(pred) {
  pred |>
    dplyr::summarise(forecast = sum(.data$E), actual = sum(.data$pts), games = dplyr::n(),
                     .by = c("season", "w", "gsis_id", "position", "relevant", "rank")) |>
    dplyr::mutate(err = .data$forecast - .data$actual)
}

val_error_summary <- function(tot, by = character()) {
  tot |>
    dplyr::summarise(n = dplyr::n(), mae = mean(abs(.data$err)), rmse = sqrt(mean(.data$err^2)),
                     bias = mean(.data$err), .by = dplyr::all_of(by))
}

#' VE1: compare the pre-registered levels and the schedule term; apply the
#' fixed selection rule. Development = `dev`, check = `check` (reported only).
val_ve1_study <- function(frame, dev = 2019:2023, check = 2024:2025, form = "linear") {
  fut <- frame$future
  runs <- purrr::map(VAL_LEVELS, function(lv) {
    fit <- val_fit_ros(fut, lv, dev, form = form)
    pr <- val_predict_ros(fut, fit)
    tot <- val_ros_totals(pr) |> dplyr::mutate(split = ifelse(.data$season %in% dev, "dev", "check"), level = lv)
    list(fit = fit, pred = pr, tot = tot)
  }) |>
    rlang::set_names(VAL_LEVELS)
  tot <- purrr::map(runs, "tot") |> purrr::list_rbind()
  pooled <- dplyr::bind_rows(
    val_error_summary(dplyr::filter(tot, .data$relevant), c("level", "split")) |> dplyr::mutate(subset = "relevant"),
    val_error_summary(tot, c("level", "split")) |> dplyr::mutate(subset = "all")
  )
  by_pos <- val_error_summary(dplyr::filter(tot, .data$relevant), c("level", "split", "position"))
  rank_cor <- tot |>
    dplyr::filter(.data$relevant) |>
    dplyr::summarise(rho = suppressWarnings(stats::cor(.data$forecast, .data$actual, method = "spearman")),
                     .by = c("level", "split", "season", "w", "position")) |>
    dplyr::summarise(rho = mean(.data$rho, na.rm = TRUE), .by = c("level", "split", "position"))

  # Selection rule (VE1): lowest dev MAE (relevant) with RMSE not worse than
  # L_cur; differences < 0.5% of MAE are ties, won by the simpler level.
  dv <- dplyr::filter(pooled, .data$subset == "relevant", .data$split == "dev")
  ref <- dv[dv$level == "L_cur", ]
  ok <- dv[dv$rmse <= ref$rmse | dv$level == "L_cur", ]
  best <- ok$level[which.min(ok$mae)]
  tol <- 0.005 * min(ok$mae)
  ties <- ok$level[ok$mae <= min(ok$mae) + tol]
  selected <- VAL_LEVELS[min(match(ties, VAL_LEVELS))]

  # Schedule term for the selected level: kept only if weekly future MAE
  # (relevant) improves in BOTH development and check.
  fit0 <- runs[[selected]]$fit
  fit1 <- val_fit_ros(fut, selected, dev, opponent = TRUE, form = form)
  wk <- function(fit) {
    val_predict_ros(fut, fit) |>
      dplyr::filter(.data$relevant) |>
      dplyr::mutate(split = ifelse(.data$season %in% dev, "dev", "check")) |>
      dplyr::summarise(mae = mean(abs(.data$E - .data$pts)), rmse = sqrt(mean((.data$E - .data$pts)^2)),
                       n = dplyr::n(), .by = "split")
  }
  sched <- dplyr::bind_rows(dplyr::mutate(wk(fit0), model = "no_opponent"), dplyr::mutate(wk(fit1), model = "opponent"))
  m <- function(model, split) sched$mae[sched$model == model & sched$split == split]
  keep_opp <- m("opponent", "dev") < m("no_opponent", "dev") && m("opponent", "check") < m("no_opponent", "check")
  list(pooled = pooled, by_position = by_pos, rank_cor = rank_cor, selected = selected,
       selected_raw_best = best, schedule = sched, opponent_coef = dplyr::distinct(fit1$cd, .data$position, .data$g),
       keep_opponent = keep_opp, dev = dev, check = check, form = form)
}

#' VE1b: model form for the selected level (linear E vs two-stage A(L) x m(L)),
#' chosen by the VE1 rule on development ROS-total MAE (relevant); check
#' seasons reported. Also returns calibration by level quintile.
val_ve1b_form <- function(frame, level, opponent, dev = 2019:2023, check = 2024:2025,
                          alternative = "two_stage") {
  fut <- frame$future
  res <- purrr::map(c("linear", alternative), function(fm) {
    fit <- val_fit_ros(fut, level, dev, opponent = opponent, form = fm)
    pr <- val_predict_ros(fut, fit)
    tot <- val_ros_totals(pr) |> dplyr::mutate(split = ifelse(.data$season %in% dev, "dev", "check"), form = fm)
    cal <- pr |>
      dplyr::filter(.data$relevant) |>
      dplyr::mutate(split = ifelse(.data$season %in% dev, "dev", "check"), q = dplyr::ntile(.data$L, 5),
                    .by = "position") |>
      dplyr::summarise(L = mean(.data$L), forecast = mean(.data$E), actual = mean(.data$pts), n = dplyr::n(),
                       .by = c("split", "position", "q")) |>
      dplyr::mutate(form = fm)
    list(tot = tot, cal = cal)
  })
  tot <- purrr::map(res, "tot") |> purrr::list_rbind()
  pooled <- val_error_summary(dplyr::filter(tot, .data$relevant), c("form", "split"))
  by_pos <- val_error_summary(dplyr::filter(tot, .data$relevant), c("form", "split", "position"))
  dv <- dplyr::filter(pooled, .data$split == "dev")
  lin <- dv[dv$form == "linear", ]
  alt <- dv[dv$form == alternative, ]
  # same rule as VE1: lower MAE, RMSE not worse, < 0.5% is a tie won by the simpler (linear) form
  chosen <- if (alt$mae < lin$mae - 0.005 * lin$mae && alt$rmse <= lin$rmse) alternative else "linear"
  list(pooled = pooled, by_position = by_pos, calibration = purrr::map(res, "cal") |> purrr::list_rbind(),
       chosen = chosen)
}

#' Production ROS parameters (VE1 design, re-estimated on `seasons`): level,
#' future-week calibration and availability by position and horizon bucket,
#' opponent coefficient, and the current-week calibration of ESPN's week-of
#' projection by position (least squares, rows projected > 0 with a team game).
val_derive_ros_params <- function(frame, level, opponent, form = "two_stage", seasons = 2019:2025, digits = 4) {
  fit <- val_fit_ros(frame$future, level, seasons, opponent = opponent, form = form)
  cur <- frame$current |> dplyr::filter(.data$season %in% seasons)
  c0 <- purrr::map(VAL_POSITIONS, function(p) {
    x <- dplyr::filter(cur, .data$position == p)
    co <- stats::coef(stats::lm(pts ~ espn_proj, data = x))
    list(c = round(unname(co[1]), digits), d = round(unname(co[2]), digits), n = nrow(x))
  }) |>
    rlang::set_names(VAL_POSITIONS)
  fut <- split(fit$cd, fit$cd$position) |>
    purrr::map(function(x) {
      purrr::pmap(x, function(bucket, c, d, q, a, e, n, ...) {
        list(c = round(c, digits), d = round(d, digits), q = round(q, 6), a = round(a, digits),
             e = round(e, digits), n = n)
      }) |>
        rlang::set_names(x$bucket)
    })
  g <- split(fit$cd, fit$cd$position) |> purrr::map(function(x) round(x$g[1], digits))
  list(
    version = "ros_v1", derived_from = paste(range(seasons), collapse = "-"), level = level, form = form,
    opponent_adjustment = isTRUE(opponent),
    buckets = list(h1 = "1", h2_3 = "2-3", h4_7 = "4-7", h8p = "8+"),
    current_week = c0, future = fut, opponent_coef = g,
    n_future_rows = nrow(dplyr::filter(frame$future, .data$season %in% seasons))
  )
}

#' Read committed ROS parameters into lookup tables.
val_read_ros_params <- function(path) {
  p <- yaml::read_yaml(path)
  val_ros_tables(p)
}

val_ros_tables <- function(p) {
  p$cd_tab <- purrr::imap(p$future, function(x, pos) {
    tibble::tibble(position = pos, bucket = names(x), c = vapply(x, `[[`, 0, "c"), d = vapply(x, `[[`, 0, "d"),
                   q = vapply(x, function(y) y$q %||% 0, 0),
                   a = vapply(x, `[[`, 0, "a"), e = vapply(x, `[[`, 0, "e"),
                   g = if (isTRUE(p$opponent_adjustment)) p$opponent_coef[[pos]] %||% 0 else 0)
  }) |> purrr::list_rbind()
  p$c0_tab <- purrr::imap(p$current_week, function(x, pos) tibble::tibble(position = pos, c0 = x$c, d0 = x$d)) |>
    purrr::list_rbind()
  p$form <- p$form %||% "two_stage"
  p
}

#' Diagnostics (no decisions): weekly residual SD by position and projection
#' bucket; ROS-total residual SD by position and remaining games; future
#' availability after a Questionable designation at w.
val_ros_diagnostics <- function(frame, params_fit, injuries, seasons = 2019:2025) {
  cur <- dplyr::filter(frame$current, .data$season %in% seasons)
  cal <- purrr::map(VAL_POSITIONS, function(p) {
    x <- dplyr::filter(cur, .data$position == p)
    f <- stats::lm(pts ~ espn_proj, data = x)
    dplyr::mutate(x, fit = stats::fitted(f))
  }) |>
    purrr::list_rbind()
  weekly_sd <- cal |>
    dplyr::mutate(proj_bucket = cut(.data$espn_proj, c(0, 5, 10, 15, 20, Inf), right = FALSE)) |>
    dplyr::summarise(n = dplyr::n(), mean_proj = mean(.data$espn_proj), sd = stats::sd(.data$pts - .data$fit),
                     .by = c("position", "proj_bucket")) |>
    dplyr::arrange(.data$position, .data$proj_bucket)
  pr <- val_predict_ros(dplyr::filter(frame$future, .data$season %in% seasons), params_fit)
  tot <- val_ros_totals(pr)
  ros_sd <- tot |>
    dplyr::filter(.data$relevant) |>
    dplyr::mutate(games_bucket = cut(.data$games, c(0, 4, 8, 12, Inf))) |>
    dplyr::summarise(n = dplyr::n(), mean_forecast = mean(.data$forecast), sd = stats::sd(.data$err),
                     sd_rel = stats::sd(.data$err) / mean(.data$forecast), .by = c("position", "games_bucket")) |>
    dplyr::arrange(.data$position, .data$games_bucket)
  q <- dplyr::filter(injuries, .data$season %in% seasons) |>
    dplyr::select("season", w = "week", "gsis_id", "report_status")
  qa <- frame$future |>
    dplyr::filter(.data$season %in% seasons) |>
    dplyr::left_join(q, by = c("season", "w", "gsis_id")) |>
    dplyr::mutate(status_w = dplyr::coalesce(.data$report_status, "none")) |>
    dplyr::filter(.data$status_w %in% c("none", "Questionable")) |>
    dplyr::mutate(hb = cut(.data$h, c(0, 1, 3, 7, Inf), labels = c("h1", "h2_3", "h4_7", "h8p"))) |>
    dplyr::summarise(n = dplyr::n(), A = mean(.data$active), .by = c("position", "status_w", "hb")) |>
    dplyr::arrange(.data$position, .data$hb, .data$status_w)
  list(weekly_sd = weekly_sd, ros_sd = ros_sd, questionable_future = qa)
}
