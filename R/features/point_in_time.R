# Point-in-time feature engineering --------------------------------------------
#
# CONTRACT: features for a target (player, season, week) may only use games
# with game_index strictly less than the target's game_index.
#
# Pattern used everywhere in this file:
#   1. Build an entity's game history (player-games, team-games, defense-games).
#   2. Compute "state after game g" summaries (trailing means INCLUDING game g).
#   3. Attach to each target row the state from the entity's most recent game
#      STRICTLY BEFORE the target week (as-of join with `closest(a > b)`).
# Because step 3 uses a strict inequality, a target week's own outcomes can
# never reach its features, whether or not the player played that week.
# tests/testthat/test-point-in-time.R and check_feature_leakage() enforce this.

#' Trailing mean over the last `k` non-missing-aware observations, including
#' the current one. Missing values are skipped (mean of the available values
#' in the window); NA if the window has no observed values.
trailing_mean <- function(x, k) {
  stopifnot(k >= 1)
  ok <- !is.na(x)
  cs <- cumsum(ifelse(ok, x, 0))
  cn <- cumsum(ok)
  n <- length(x)
  lag_k <- function(v) c(rep(0, k), v)[seq_len(n)]
  s <- cs - lag_k(cs)
  cnt <- cn - lag_k(cn)
  ifelse(cnt > 0, s / cnt, NA_real_)
}

#' Attach, for each row of `targets`, the latest row of `states` (same `by`
#' keys) whose `state_index` is strictly less than the target's `game_index`.
#' The matched `state_index` is dropped, or kept under the name `keep_index_as`.
#' Column-name collisions are an error.
asof_join <- function(targets, states, by, keep_index_as = NULL, what = "asof_join") {
  stopifnot("game_index" %in% names(targets), "state_index" %in% names(states))
  clash <- setdiff(intersect(names(targets), names(states)), by)
  if (length(clash) > 0) cli::cli_abort("{what}: clashing columns {.val {clash}}.")
  assert_unique_key(states, c(by, "state_index"), what)
  jb <- dplyr::join_by(!!!rlang::syms(by), closest(game_index > state_index))
  out <- dplyr::left_join(targets, states, by = jb, relationship = "many-to-one")
  if (nrow(out) != nrow(targets)) cli::cli_abort("{what}: row count changed.")
  if (is.null(keep_index_as)) {
    out$state_index <- NULL
  } else {
    names(out)[names(out) == "state_index"] <- keep_index_as
  }
  out
}

# --- Histories ---------------------------------------------------------------

#' One row per player appearance: a stat line or >= 1 offensive snap.
#' Snap-only appearances get zero stats (the player was on the field and
#' produced nothing), which keeps trailing means honest for low-usage players.
build_player_games <- function(stats, snaps, pbp_usage, xfp) {
  keys <- c("season", "week", "gsis_id")
  stat_part <- stats |>
    dplyr::select(dplyr::all_of(keys), "team", "targets", "receptions",
                  "receiving_yards", "receiving_tds", "receiving_air_yards",
                  "carries", "fantasy_pts")
  snap_only <- snaps |>
    dplyr::anti_join(stat_part, by = keys) |>
    dplyr::transmute(season = .data$season, week = .data$week,
                     gsis_id = .data$gsis_id, team = .data$snap_team)

  games <- dplyr::bind_rows(stat_part, snap_only) |>
    dplyr::mutate(dplyr::across(
      c("targets", "receptions", "receiving_yards", "receiving_tds",
        "receiving_air_yards", "carries", "fantasy_pts"),
      ~ dplyr::coalesce(.x, 0)
    )) |>
    safe_left_join(dplyr::select(snaps, dplyr::all_of(keys), "snap_share"), by = keys, what = "games+snaps") |>
    safe_left_join(dplyr::select(pbp_usage, dplyr::all_of(keys), "rz_targets"), by = keys, what = "games+pbp") |>
    safe_left_join(xfp, by = keys, what = "games+xfp") |>
    dplyr::mutate(rz_targets = dplyr::coalesce(.data$rz_targets, 0))

  team_totals <- games |>
    dplyr::summarise(
      team_targets = sum(.data$targets),
      team_air_yards = sum(.data$receiving_air_yards),
      team_rz_targets = sum(.data$rz_targets),
      .by = c("season", "week", "team")
    )

  games |>
    safe_left_join(team_totals, by = c("season", "week", "team"), what = "games+team_totals") |>
    dplyr::mutate(
      game_index = game_index(.data$season, .data$week),
      target_share = safe_ratio(.data$targets, .data$team_targets),
      air_yards_share = safe_ratio(.data$receiving_air_yards, .data$team_air_yards),
      rz_target_share = safe_ratio(.data$rz_targets, .data$team_rz_targets)
    ) |>
    assert_unique_key(keys, "player_games") |>
    dplyr::arrange(.data$gsis_id, .data$game_index)
}

safe_ratio <- function(num, den) ifelse(den > 0, num / den, NA_real_)

#' Team pass volume per team-game (from player stats, all positions).
build_team_volume <- function(stats) {
  stats |>
    dplyr::summarise(
      team_pass_att = sum(.data$attempts, na.rm = TRUE),
      team_targets = sum(.data$targets, na.rm = TRUE),
      .by = c("season", "week", "team")
    ) |>
    dplyr::mutate(game_index = game_index(.data$season, .data$week)) |>
    assert_unique_key(c("season", "week", "team"), "team_volume")
}

#' Fantasy points allowed to a position by each defense, per game.
build_defense_allowed <- function(stats, team_games, position = "WR") {
  allowed <- stats |>
    dplyr::filter(.data$stats_position == !!position) |>
    dplyr::summarise(pts_allowed = sum(.data$fantasy_pts), .by = c("season", "week", "opponent"))
  # Start from the schedule so a defense that allowed 0 points still has a game.
  team_games |>
    dplyr::select("season", "week", defense = "team", "game_index") |>
    dplyr::left_join(allowed, by = c("season", "week", defense = "opponent")) |>
    dplyr::mutate(pts_allowed = dplyr::coalesce(.data$pts_allowed, 0))
}

# --- States ("after game g") -------------------------------------------------

PLAYER_ROLL_VARS <- c(
  "fantasy_pts", "targets", "receptions", "receiving_yards", "target_share",
  "air_yards_share", "snap_share", "rz_targets", "rz_target_share", "xfp"
)

player_states <- function(player_games, windows = c(3, 8)) {
  st <- player_games |>
    dplyr::arrange(.data$gsis_id, .data$game_index) |>
    dplyr::mutate(career_games = dplyr::row_number(), .by = "gsis_id") |>
    dplyr::mutate(
      season_games = dplyr::row_number(),
      season_pts_mean = cumsum(.data$fantasy_pts) / .data$season_games,
      season_targets_mean = cumsum(.data$targets) / .data$season_games,
      .by = c("gsis_id", "season")
    )
  for (k in windows) {
    for (v in PLAYER_ROLL_VARS) {
      st <- dplyr::mutate(
        st, "{v}_roll{k}" := trailing_mean(.data[[v]], k), .by = "gsis_id"
      )
    }
  }
  roll_cols <- grep("_roll[0-9]+$", names(st), value = TRUE)
  st |>
    dplyr::transmute(
      gsis_id = .data$gsis_id, state_index = .data$game_index,
      last_game_season = .data$season, last_game_team = .data$team,
      career_games = .data$career_games, season_games = .data$season_games,
      season_pts_mean = .data$season_pts_mean,
      season_targets_mean = .data$season_targets_mean,
      dplyr::across(dplyr::all_of(roll_cols))
    )
}

#' Previous-season per-game averages, keyed to the *following* season so they
#' can be joined directly to target rows (they are fully known before it).
player_prev_season <- function(player_games) {
  player_games |>
    dplyr::summarise(
      prev_season_games = dplyr::n(),
      prev_season_pts_mean = mean(.data$fantasy_pts),
      prev_season_target_share = mean(.data$target_share, na.rm = TRUE),
      .by = c("gsis_id", "season")
    ) |>
    dplyr::mutate(
      season = .data$season + 1L,
      prev_season_target_share = dplyr::if_else(
        is.nan(.data$prev_season_target_share), NA_real_, .data$prev_season_target_share
      )
    )
}

team_states <- function(team_volume, windows = c(8)) {
  st <- dplyr::arrange(team_volume, .data$team, .data$game_index)
  for (k in windows) {
    st <- dplyr::mutate(
      st,
      "team_pass_att_roll{k}" := trailing_mean(.data$team_pass_att, k),
      "team_targets_roll{k}" := trailing_mean(.data$team_targets, k),
      .by = "team"
    )
  }
  dplyr::select(st, "team", state_index = "game_index", dplyr::matches("_roll[0-9]+$"))
}

defense_states <- function(defense_allowed, k = 8) {
  defense_allowed |>
    dplyr::arrange(.data$defense, .data$game_index) |>
    dplyr::mutate(opp_pts_allowed_roll = trailing_mean(.data$pts_allowed, k), .by = "defense") |>
    dplyr::select(opponent = "defense", state_index = "game_index", "opp_pts_allowed_roll")
}

# --- Assemble features for target rows ----------------------------------------

#' Add point-in-time features to `targets` (one row per player-week, with
#' season, week, gsis_id, team, opponent). Uses only games before each row.
add_point_in_time_features <- function(targets, player_games, team_volume,
                                       defense_allowed, team_games,
                                       windows = c(3, 8)) {
  targets <- dplyr::mutate(targets, game_index = game_index(.data$season, .data$week))

  # The team's previous game (to detect a player who missed it).
  team_prev <- team_games |>
    dplyr::arrange(.data$team, .data$game_index) |>
    dplyr::mutate(team_prev_game_index = dplyr::lag(.data$game_index), .by = "team") |>
    dplyr::select("season", "week", "team", "team_prev_game_index")

  out <- targets |>
    asof_join(player_states(player_games, windows), by = "gsis_id",
              keep_index_as = "player_last_index", what = "player state") |>
    safe_left_join(player_prev_season(player_games), by = c("gsis_id", "season"), what = "prev season") |>
    asof_join(team_states(team_volume), by = "team", what = "team state") |>
    asof_join(defense_states(defense_allowed), by = "opponent", what = "defense state") |>
    safe_left_join(team_prev, by = c("season", "week", "team"), what = "team prev game")

  out |>
    dplyr::mutate(
      career_games = dplyr::coalesce(.data$career_games, 0L),
      has_history = .data$career_games > 0,
      # Season-to-date stats only count if the last game was this season.
      same_season = !is.na(.data$last_game_season) & .data$last_game_season == .data$season,
      season_games = dplyr::if_else(.data$same_season, .data$season_games, 0L),
      season_pts_mean = dplyr::if_else(.data$same_season, .data$season_pts_mean, NA_real_),
      season_targets_mean = dplyr::if_else(.data$same_season, .data$season_targets_mean, NA_real_),
      played_team_prev_game = !is.na(.data$player_last_index) &
        !is.na(.data$team_prev_game_index) &
        .data$player_last_index == .data$team_prev_game_index &
        .data$last_game_team == .data$team,
      changed_team = !is.na(.data$last_game_team) & .data$last_game_team != .data$team,
      log_career_games = log1p(.data$career_games)
    ) |>
    dplyr::select(-"same_season", -"player_last_index", -"team_prev_game_index",
                  -"last_game_season", -"last_game_team")
}

#' Empirical leakage check. For each of `n_cutoffs` randomly chosen weeks,
#' corrupt every outcome at or after that week (same-week AND future data)
#' and recompute the features of that week's target rows. Any feature that
#' changes depended on information unavailable before kickoff.
#' Returns the names of leaking feature columns (character(0) when clean).
check_feature_leakage <- function(targets, player_games, team_volume,
                                  defense_allowed, team_games, n_cutoffs = 6, seed = 1,
                                  feature_fn = add_point_in_time_features) {
  targets <- dplyr::mutate(targets, game_index = game_index(.data$season, .data$week))
  set.seed(seed)
  idx <- unique(targets$game_index)
  cutoffs <- idx[sample.int(length(idx), min(n_cutoffs, length(idx)))]
  num <- intersect(
    c("fantasy_pts", "targets", "receptions", "receiving_yards", "target_share",
      "air_yards_share", "snap_share", "rz_targets", "rz_target_share", "xfp"),
    names(player_games)
  )
  leaks <- purrr::map(cutoffs, function(cut) {
    probe <- dplyr::filter(targets, .data$game_index == cut) |> dplyr::select(-"game_index")
    base <- feature_fn(probe, player_games, team_volume, defense_allowed, team_games)

    pg <- player_games
    hit <- pg$game_index >= cut
    pg[hit, num] <- pg[hit, num] * 7 + 50
    tv <- team_volume
    hit <- tv$game_index >= cut
    tv$team_pass_att[hit] <- tv$team_pass_att[hit] + 500
    tv$team_targets[hit] <- tv$team_targets[hit] + 500
    da <- defense_allowed
    hit <- da$game_index >= cut
    da$pts_allowed[hit] <- da$pts_allowed[hit] + 500

    pert <- feature_fn(probe, pg, tv, da, team_games)
    cols <- setdiff(names(base), names(probe))
    cols[!vapply(cols, function(c) identical(base[[c]], pert[[c]]), logical(1))]
  })
  sort(unique(unlist(leaks)))
}
