# Valuation: projection providers ----------------------------------------------------------
# The valuation layer reads ONE standardized weekly table and never a source's
# own columns. A provider is a function(ctx) returning rows of that table for
# the player-weeks it covers; config/valuation.yml lists providers per
# position in priority order (first provider covering a player-week wins).
# A future RB/TE/QB model is added by writing provider_<name>() and listing it
# in the config; nothing downstream changes.
#
# Standard columns (one row per season, week, player_id):
#   player_id (gsis id, else "espn:<id>"), espn_id, player_name, position, team,
#   season, week, opponent, has_game, proj (expected points), proj_raw (the
#   source's own number), proj_kind (current_week | posted_future |
#   extrapolated), source, source_version, as_of_utc, availability_status,
#   p_active (P(active), used to draw availability in the simulation; 1 for the
#   current week, whose projection already includes availability), lvl
#   (points if active; proj = p_active * lvl).

VAL_PROJ_COLS <- c("player_id", "espn_id", "player_name", "position", "team", "season", "week", "opponent",
                   "has_game", "proj", "proj_raw", "proj_kind", "source", "source_version", "as_of_utc",
                   "availability_status", "p_active", "lvl")
VAL_PROJ_KINDS <- c("current_week", "posted_future", "extrapolated")

#' Check a standardized projection table; returns it invisibly.
validate_projection_table <- function(d, what = "projection table") {
  miss <- setdiff(VAL_PROJ_COLS, names(d))
  if (length(miss)) cli::cli_abort("{what}: missing column{?s} {.val {miss}}.")
  d |>
    assert_unique_key(c("season", "week", "player_id"), what) |>
    assert_no_missing(c("player_id", "position", "season", "week", "has_game", "proj", "proj_kind", "source"), what) |>
    assert_values_in("position", VAL_POSITIONS, what) |>
    assert_values_in("proj_kind", VAL_PROJ_KINDS, what) |>
    assert_in_range("proj", 0, 80, what) |>
    assert_in_range("p_active", 0, 1, what)
  if (any(d$proj[!d$has_game] != 0)) cli::cli_abort("{what}: positive projection without a game.")
  if (any(abs(d$proj - d$p_active * d$lvl) > 1e-6)) cli::cli_abort("{what}: proj != p_active * lvl.")
  invisible(d)
}

val_player_id <- function(gsis_id, espn_id) ifelse(is.na(gsis_id), paste0("espn:", espn_id), gsis_id)

#' Live valuation context: everything a provider may use, all as of `as_of`.
#' `capture` = parsed valuation capture (current + posted future weeks).
val_live_context <- function(season, week, as_of = Sys.time(), cfg = read_valuation_config(),
                             capture_path = latest_valuation_capture(season, week, as_of),
                             history_weeks = NULL) {
  if (is.na(capture_path)) cli::cli_abort("No valuation ESPN capture for {season} week {week} at or before {as_of}.")
  capture <- arrow::read_parquet(capture_path)
  rules <- read_scoring_rules(cfg$league$scoring)
  live <- function(ds) latest_live_file(ds, season, as_of)
  team_games <- clean_team_games(live("schedules"), "REG")
  stats <- clean_player_stats(live("player_stats"), rules, "REG")
  # ESPN week-of history of this season (final pregame values for completed weeks)
  hw <- history_weeks %||% seq_len(week - 1)
  qb <- val_espn_raw_path(season, hw)
  wr <- espn_raw_path(season, hw, "WR")
  hist <- val_espn_weekly(qb[file.exists(qb)], wr[file.exists(wr)])
  ids <- dplyr::bind_rows(dplyr::distinct(capture, .data$espn_id, .data$espn_name),
                          dplyr::distinct(hist, .data$espn_id, .data$espn_name)) |>
    dplyr::distinct(.data$espn_id, .keep_all = TRUE)
  rw <- read_parquet_files(c(hist_paths("rosters_weekly", season - (2:1)), live("rosters_weekly"))) |>
    dplyr::transmute(roster_espn_id = as.character(.data$espn_id), gsis_id = .data$gsis_id, roster_name = .data$full_name)
  crosswalk <- build_espn_crosswalk(ids, rw, read_parquet_files(live("players")), read_parquet_files(live("ff_playerids")))
  list(
    season = as.integer(season), week = as.integer(week), as_of = as_of, cfg = cfg, rules = rules,
    capture = capture, capture_path = capture_path, capture_sha256 = sha256_file(capture_path),
    team_games = team_games, player_stats = stats, history = hist, crosswalk = crosswalk,
    live_files = list(schedules = live("schedules"), player_stats = live("player_stats"),
                      rosters_weekly = live("rosters_weekly"), players = live("players"),
                      ff_playerids = live("ff_playerids")),
    ros = val_read_ros_params(cfg$ros_params_file), ros_params_sha256 = sha256_file(cfg$ros_params_file)
  )
}

#' Pool and skeleton: every capture player at QB/RB/WR/TE with an NFL team and
#' a positive projection this week, a posted future week, or one of the last
#' `recent_weeks` weeks; one row per horizon week with schedule context.
val_pool_skeleton <- function(ctx, weeks) {
  cap <- val_capture_rescored(ctx)
  recent <- dplyr::filter(ctx$history, .data$week >= ctx$week - (ctx$cfg$pool$recent_weeks %||% 4),
                          .data$espn_proj > 0)
  keep <- unique(c(cap$espn_id[cap$proj_raw > 0], intersect(recent$espn_id, cap$espn_id)))
  players <- cap |>
    dplyr::filter(.data$espn_id %in% keep) |>
    dplyr::distinct(.data$espn_id, .data$espn_name, .data$position, .data$team, .data$injury_status,
                    .data$pct_owned, .data$pct_started) |>
    dplyr::left_join(dplyr::select(dplyr::filter(ctx$crosswalk, !is.na(.data$gsis_id)), "espn_id", "gsis_id"),
                     by = "espn_id") |>
    dplyr::mutate(player_id = val_player_id(.data$gsis_id, .data$espn_id))
  tg <- dplyr::filter(ctx$team_games, .data$season == ctx$season) |> dplyr::select("week", "team", "opponent")
  sk <- tidyr::expand_grid(players, week = weeks) |>
    dplyr::left_join(tg, by = c("week", "team")) |>
    dplyr::mutate(has_game = !is.na(.data$opponent), season = ctx$season) |>
    dplyr::left_join(dplyr::select(cap, "espn_id", "week", "proj_raw"), by = c("espn_id", "week"))
  list(players = players, skeleton = sk)
}

#' Capture rows at QB/RB/WR/TE with an NFL team, rescored under the league's rules.
val_capture_rescored <- function(ctx) {
  cap <- dplyr::filter(ctx$capture, .data$position %in% VAL_POSITIONS, !is.na(.data$team))
  cap$proj_raw <- val_rescore(cap, ctx$rules)
  cap
}

val_std_rows <- function(sk, proj, kind, source, version, as_of, p_active = 1, lvl = proj, proj_raw = sk$proj_raw) {
  tibble::tibble(
    player_id = sk$player_id, espn_id = sk$espn_id, player_name = sk$espn_name, position = sk$position,
    team = sk$team, season = sk$season, week = sk$week, opponent = sk$opponent, has_game = sk$has_game,
    proj = unname(as.numeric(proj)), proj_raw = unname(as.numeric(proj_raw)), proj_kind = kind, source = source,
    source_version = version, as_of_utc = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    availability_status = sk$injury_status, p_active = unname(as.numeric(p_active)), lvl = unname(as.numeric(lvl))
  )
}

#' Current week, calibrated ESPN: c0 + d0 * ESPN (per position, fixed in the
#' ROS parameters); 0 when ESPN projects 0 or the team does not play.
provider_espn_calibrated <- function(ctx, sk) {
  d <- dplyr::filter(sk, .data$week == ctx$week, !is.na(.data$proj_raw)) |>
    dplyr::left_join(ctx$ros$c0_tab, by = "position")
  e <- ifelse(d$has_game & d$proj_raw > 0, pmax(0, d$c0 + d$d0 * d$proj_raw), 0)
  val_std_rows(d, e, "current_week", "espn_calibrated", paste0("ros_params ", ctx$ros$version), ctx$as_of)
}

#' Current week, WR: the frozen M4 primary model's prediction from the latest
#' ARCHIVED official run made at or before `as_of` (read only; never
#' recomputed). Used only for WRs that the valuation capture still projects
#' above 0 (newer information wins over an older run).
provider_m4_archive <- function(ctx, sk) {
  run <- val_latest_m4_run(ctx$season, ctx$week, ctx$as_of)
  if (is.null(run)) return(NULL)
  p <- arrow::read_parquet(run$path) |>
    dplyr::filter(.data$model_id == (ctx$cfg$m4_model_id %||% "m4_two_stage_v1")) |>
    dplyr::select("gsis_id", m4 = "pred", m4_espn = "espn_proj")
  d <- dplyr::filter(sk, .data$week == ctx$week, .data$position == "WR", .data$has_game,
                     .data$proj_raw > 0) |>
    dplyr::inner_join(p, by = "gsis_id")
  val_std_rows(d, pmax(0, d$m4), "current_week", "m4_archive", paste0("run=", run$run_id), ctx$as_of,
               proj_raw = d$m4_espn)
}

#' Latest verified official prospective run for a week made at or before as_of.
val_latest_m4_run <- function(season, week, as_of, manifest = PREDICTION_MANIFEST,
                              root = "data/archive/predictions") {
  if (!file.exists(manifest)) return(NULL)
  m <- readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::filter(as.integer(.data$season) == !!season, as.integer(.data$week) == !!week,
                  grepl("m4", .data$lineages)) |>
    dplyr::mutate(at = as.POSIXct(.data$predicted_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) |>
    dplyr::filter(.data$at <= as_of)
  if (!nrow(m)) return(NULL)
  r <- m[which.max(m$at), ]
  path <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", r$run_id),
                    "predictions.parquet")
  if (!file.exists(path) || !identical(sha256_file(path), r$predictions_sha256)) {
    cli::cli_abort("Archived run {r$run_id} is missing or does not match its manifest hash.")
  }
  list(run_id = r$run_id, path = path, sha256 = r$predictions_sha256, snapshot_captured_at_utc = r$snapshot_captured_at_utc)
}

#' Future weeks from ESPN's POSTED future-week projection X (VE0): E = f(X)
#' with the fixed ROS model (position, horizon bucket); a posted 0 in a game
#' week is ESPN's expected absence (E = 0). Posted values already include
#' the opponent, so no schedule term (opp = 1).
provider_espn_posted_future <- function(ctx, sk) {
  d <- dplyr::filter(sk, .data$week > ctx$week, !is.na(.data$proj_raw)) |>
    dplyr::mutate(bucket = val_h_bucket(.data$week - ctx$week), opp = 1, X = .data$proj_raw)
  f <- val_apply_ros(d, ctx$ros$cd_tab, "X", val_ros_form(ctx$ros))
  ok <- d$has_game & d$X > 0
  val_std_rows(d, ifelse(ok, f$E, 0), "posted_future", "espn_posted_future",
               paste0("capture ", basename(ctx$capture_path), "; ros_params ", ctx$ros$version), ctx$as_of,
               p_active = ifelse(ok, f$A, 0), lvl = ifelse(ok, f$lvl, 0))
}

#' Future weeks from the EXTRAPOLATED level L_avg4 (mean of the last up-to-4
#' positive ESPN week-of projections, weeks <= current) with the schedule term.
provider_extrapolated <- function(ctx, sk) {
  cur <- dplyr::filter(val_capture_rescored(ctx), .data$week == ctx$week) |> dplyr::select("espn_id", cur = "proj_raw")
  hist <- dplyr::filter(ctx$history, .data$espn_proj > 0, .data$week < ctx$week) |>
    dplyr::select("espn_id", "week", x = "espn_proj")
  lv <- dplyr::bind_rows(hist, dplyr::filter(dplyr::transmute(cur, .data$espn_id, week = ctx$week, x = .data$cur), .data$x > 0)) |>
    dplyr::arrange(.data$espn_id, dplyr::desc(.data$week)) |>
    dplyr::slice_head(n = 4, by = "espn_id") |>
    dplyr::summarise(L = mean(.data$x), .by = "espn_id")
  opp <- val_opponent_factor(ctx$player_stats, ctx$team_games, ctx$season, weeks = ctx$week) |>
    dplyr::select(opponent = "defense", "position", "opp")
  d <- dplyr::filter(sk, .data$week > ctx$week) |>
    dplyr::inner_join(lv, by = "espn_id") |>
    dplyr::left_join(opp, by = c("opponent", "position")) |>
    dplyr::mutate(opp = dplyr::coalesce(.data$opp, 1), bucket = val_h_bucket(.data$week - ctx$week))
  f <- val_apply_ros(d, ctx$ros$cd_tab, "L", val_ros_form(ctx$ros))
  val_std_rows(d, ifelse(d$has_game, f$E, 0), "extrapolated", "extrapolated",
               paste0("L_avg4; ros_params ", ctx$ros$version), ctx$as_of,
               p_active = ifelse(d$has_game, f$A, 0), lvl = ifelse(d$has_game, f$lvl, 0), proj_raw = d$L)
}

val_ros_form <- function(ros) if (identical(ros$form, "two_stage")) "two_stage" else "linear"

#' Standardized weekly table for the horizon: current week and future weeks
#' from each position's provider list (first covering provider wins); player
#' weeks no provider covers get 0 (proj_kind of the last provider tried).
val_build_weekly <- function(ctx, weeks) {
  ps <- val_pool_skeleton(ctx, weeks)
  sk <- ps$skeleton
  src <- ctx$cfg$projection_sources
  run_list <- function(slot, rows) {
    out <- NULL
    for (p in VAL_POSITIONS) {
      todo <- dplyr::filter(rows, .data$position == p)
      for (nm in unlist(src[[slot]][[p]])) {
        if (!nrow(todo)) break
        fn <- get(paste0("provider_", nm), mode = "function")
        got <- fn(ctx, todo)
        if (is.null(got) || !nrow(got)) next
        out <- dplyr::bind_rows(out, got)
        todo <- dplyr::anti_join(todo, got, by = c("player_id", "week"))
      }
      if (nrow(todo)) {
        kind <- if (slot == "current_week") "current_week" else "extrapolated"
        out <- dplyr::bind_rows(out, val_std_rows(todo, rep(0, nrow(todo)), kind, "none", NA_character_, ctx$as_of,
                                                  p_active = 0, lvl = 0))
      }
    }
    out
  }
  cur <- run_list("current_week", dplyr::filter(sk, .data$week == ctx$week))
  fut <- run_list("future_weeks", dplyr::filter(sk, .data$week > ctx$week))
  out <- dplyr::bind_rows(cur, fut) |> dplyr::arrange(.data$week, .data$player_id)
  validate_projection_table(out, "valuation weekly projections")
  attr(out, "players") <- ps$players
  out
}

#' Valuation-ready weekly frame (E, A, lvl) from a standardized table.
val_weekly_frame <- function(proj) {
  proj |>
    dplyr::transmute(.data$player_id, .data$position, .data$week, E = .data$proj, A = .data$p_active,
                     lvl = .data$lvl, .data$has_game, .data$proj_kind, .data$source)
}
