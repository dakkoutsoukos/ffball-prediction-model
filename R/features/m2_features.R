# Milestone 2 point-in-time features ---------------------------------------------
#
# Same contract as point_in_time.R: a target (player, season, week) only sees
# games with game_index strictly before its own. M2 features are ADDED on top of
# the frozen M1 feature engine (which is not modified).
#
# Inputs are grouped into:
#   histories - per-game OUTCOME tables; check_leakage_generic() corrupts every
#               non-structural column at/after a cutoff week to prove the
#               features never read them.
#   static    - information fixed before the game: the schedule (opponent,
#               home, rest, roof) and player bio (draft slot, birth date).
# Feature definitions and football hypotheses: docs/features.md.

# --- Temporal primitives -----------------------------------------------------------

#' Exponentially weighted mean including the current value; NA values are
#' skipped. Weight of a game k games ago is 0.5^(k / halflife).
ewma_mean <- function(x, halflife) {
  d <- 0.5^(1 / halflife)
  ok <- !is.na(x)
  s <- stats::filter(ifelse(ok, x, 0), d, method = "recursive")
  w <- stats::filter(as.numeric(ok), d, method = "recursive")
  out <- as.numeric(s / w)
  out[w == 0] <- NA_real_
  out
}

#' Sum of the last k values (including the current one); NA counts as 0.
trailing_sum <- function(x, k) {
  cs <- cumsum(ifelse(is.na(x), 0, x))
  cs - c(rep(0, k), cs)[seq_along(x)]
}

#' Standard deviation of the last k non-missing values (NA if fewer than 2).
trailing_sd <- function(x, k) {
  n <- trailing_sum(!is.na(x), k)
  s1 <- trailing_sum(x, k)
  s2 <- trailing_sum(x^2, k)
  v <- (s2 - s1^2 / n) / (n - 1)
  ifelse(n >= 2, sqrt(pmax(v, 0)), NA_real_)
}

#' Ratio estimate shrunk toward a fixed prior: (num + k * prior) / (den + k).
#' Priors and k are fixed football constants (docs/features.md), never fitted,
#' so shrinkage cannot leak information from other seasons.
shrunk_rate <- function(num, den, prior, k) (num + k * prior) / (den + k)

# --- Histories -------------------------------------------------------------------------

#' M1 player-games plus receiver detail used by M2 states.
build_player_games_m2 <- function(player_games, pbp_receiver, pbp_usage, stats) {
  keys <- c("season", "week", "gsis_id")
  player_games |>
    safe_left_join(dplyr::select(pbp_receiver, dplyr::all_of(keys), "deep_targets", "yac"), by = keys,
                   what = "m2 games+receiver") |>
    safe_left_join(dplyr::select(pbp_usage, dplyr::all_of(keys), "endzone_targets"), by = keys,
                   what = "m2 games+endzone") |>
    safe_left_join(dplyr::select(stats, dplyr::all_of(keys), "rushing_yards"), by = keys,
                   what = "m2 games+rush") |>
    dplyr::mutate(dplyr::across(c("deep_targets", "yac", "endzone_targets", "rushing_yards"),
                                ~ dplyr::coalesce(.x, 0)),
                  fp_over_xfp = .data$fantasy_pts - .data$xfp)
}

#' Target concentration per team-game, from player games (all positions).
build_team_concentration <- function(player_games) {
  player_games |>
    dplyr::filter(.data$team_targets > 0) |>
    dplyr::summarise(top_target_share = max(.data$target_share, na.rm = TRUE),
                     target_hhi = sum(.data$target_share^2, na.rm = TRUE),
                     .by = c("season", "week", "team")) |>
    dplyr::mutate(game_index = game_index(.data$season, .data$week))
}

with_index <- function(d) dplyr::mutate(d, game_index = game_index(.data$season, .data$week))

# --- States ("after game g") ---------------------------------------------------------

M2_EWMA_VARS <- c("fantasy_pts", "targets", "target_share", "air_yards_share", "snap_share",
                  "xfp", "deep_targets", "rz_targets", "endzone_targets", "carries")

#' Player-level M2 state after each game: EWMAs, short trailing windows, trends,
#' volatility and shrunk efficiency.
player_states_m2 <- function(pg) {
  st <- dplyr::arrange(pg, .data$gsis_id, .data$game_index)
  for (v in M2_EWMA_VARS) {
    st <- dplyr::mutate(st,
      "{v}_ewma2" := ewma_mean(.data[[v]], 2),
      "{v}_ewma6" := ewma_mean(.data[[v]], 6),
      .by = "gsis_id")
  }
  st |>
    dplyr::mutate(
      fantasy_pts_roll1 = .data$fantasy_pts,
      targets_roll2 = trailing_mean(.data$targets, 2),
      targets_roll4 = trailing_mean(.data$targets, 4),
      fantasy_pts_sd8 = trailing_sd(.data$fantasy_pts, 8),
      target_share_sd8 = trailing_sd(.data$target_share, 8),
      # Efficiency over the last 16 games, shrunk toward WR-typical constants.
      ypt_shrunk = shrunk_rate(trailing_sum(.data$receiving_yards, 16), trailing_sum(.data$targets, 16), 8, 30),
      catch_rate_shrunk = shrunk_rate(trailing_sum(.data$receptions, 16), trailing_sum(.data$targets, 16), 0.62, 30),
      adot_shrunk = shrunk_rate(trailing_sum(.data$receiving_air_yards, 16), trailing_sum(.data$targets, 16), 9, 30),
      yac_per_rec_shrunk = shrunk_rate(trailing_sum(.data$yac, 16), trailing_sum(.data$receptions, 16), 4.5, 20),
      fpoe_shrunk = shrunk_rate(trailing_sum(.data$fp_over_xfp, 16), trailing_sum(!is.na(.data$fp_over_xfp), 16), 0, 6),
      .by = "gsis_id"
    ) |>
    dplyr::mutate(
      target_share_trend = .data$target_share_ewma2 - .data$target_share_ewma6,
      snap_share_trend = .data$snap_share_ewma2 - .data$snap_share_ewma6,
      xfp_trend = .data$xfp_ewma2 - .data$xfp_ewma6
    ) |>
    dplyr::select("gsis_id", state_index = "game_index", last_game_week = "week",
                  dplyr::matches("_ewma[0-9]$"), "fantasy_pts_roll1", "targets_roll2", "targets_roll4",
                  "fantasy_pts_sd8", "target_share_sd8", dplyr::ends_with("_shrunk"), dplyr::ends_with("_trend"))
}

team_states_m2 <- function(team_pbp, concentration) {
  team_pbp |>
    with_index() |>
    dplyr::left_join(dplyr::select(concentration, -"game_index"), by = c("season", "week", "team")) |>
    dplyr::arrange(.data$team, .data$game_index) |>
    dplyr::mutate(
      team_plays_ewma = ewma_mean(.data$plays, 6),
      team_dropbacks_ewma = ewma_mean(.data$dropbacks, 6),
      team_neutral_pass_rate_ewma = ewma_mean(.data$neutral_pass_rate, 6),
      team_pass_epa_ewma = ewma_mean(.data$pass_epa_per_db, 6),
      team_top_share_ewma = ewma_mean(.data$top_target_share, 6),
      team_hhi_ewma = ewma_mean(.data$target_hhi, 6),
      .by = "team"
    ) |>
    dplyr::select("team", state_index = "game_index", dplyr::ends_with("_ewma"))
}

#' Opponent pass defence: EPA allowed per dropback over its last 8 games,
#' shrunk toward 0 (about league average) by 150 dropbacks.
defense_states_m2 <- function(def_pbp) {
  def_pbp |>
    with_index() |>
    dplyr::arrange(.data$defense, .data$game_index) |>
    dplyr::mutate(
      opp_pass_epa_allowed_shrunk = trailing_sum(.data$pass_epa_allowed_sum, 8) /
        (trailing_sum(.data$db_faced, 8) + 150),
      .by = "defense"
    ) |>
    dplyr::select(opponent = "defense", state_index = "game_index", "opp_pass_epa_allowed_shrunk")
}

#' QB-level state after each of the QB's games (any team): dropback-weighted
#' EPA shrunk toward 0 by 200 dropbacks, and dropbacks per game.
qb_states <- function(qb_game) {
  qb_game |>
    with_index() |>
    dplyr::summarise(dropbacks = sum(.data$dropbacks), epa_sum = sum(.data$epa_sum),
                     .by = c("qb_id", "season", "week", "game_index")) |>
    dplyr::arrange(.data$qb_id, .data$game_index) |>
    dplyr::mutate(
      qb_epa_shrunk = trailing_sum(.data$epa_sum, 16) / (trailing_sum(.data$dropbacks, 16) + 200),
      qb_db_per_game = trailing_mean(.data$dropbacks, 8),
      .by = "qb_id"
    ) |>
    dplyr::select("qb_id", state_index = "game_index", "qb_epa_shrunk", "qb_db_per_game")
}

#' Team's starter in each game plus whether he differed from the previous
#' game's starter (both known once that game was played).
team_qb_states <- function(qb_game) {
  qb_game |>
    dplyr::filter(.data$starter) |>
    with_index() |>
    dplyr::arrange(.data$team, .data$game_index) |>
    dplyr::mutate(qb_changed_last_game = dplyr::coalesce(.data$qb_id != dplyr::lag(.data$qb_id), FALSE),
                  .by = "team") |>
    # Share of the team's last 4 games started by its most recent starter.
    dplyr::mutate(qb_same_as_last4 = purrr::map_dbl(seq_along(.data$qb_id), function(i) {
      lo <- max(1, i - 3)
      mean(.data$qb_id[lo:i] == .data$qb_id[i])
    }), .by = "team") |>
    dplyr::select("team", state_index = "game_index", last_qb_id = "qb_id", "qb_changed_last_game",
                  "qb_same_as_last4")
}

# --- Assemble -------------------------------------------------------------------------

#' Player bio fixed before any game: draft slot and birth date.
player_bio <- function(players) {
  players |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::distinct(.data$gsis_id, .keep_all = TRUE) |>
    dplyr::transmute(gsis_id = .data$gsis_id, draft_pick = as.numeric(.data$draft_pick),
                     birth_date = as.Date(.data$birth_date), rookie_season = as.integer(.data$rookie_season))
}

#' Bundle M2 histories (outcome tables) for feature building and leakage tests.
m2_histories <- function(player_games, team_volume, defense_allowed, pbp_receiver, pbp_usage, stats,
                         team_pbp, def_pbp, qb_game) {
  list(
    player_games = player_games, team_volume = team_volume, defense_allowed = defense_allowed,
    player_games_m2 = build_player_games_m2(player_games, pbp_receiver, pbp_usage, stats),
    team_pbp = team_pbp, def_pbp = def_pbp, qb_game = qb_game
  )
}

#' Full M2 feature set for target rows (season, week, gsis_id, team, opponent).
#' `static` = list(team_games, bio). Starts from the frozen M1 engine, then adds
#' M2 families. Only strictly earlier games enter any feature.
add_m2_features <- function(targets, histories, static, windows = c(3, 8)) {
  h <- histories
  out <- add_point_in_time_features(targets, h$player_games, h$team_volume, h$defense_allowed,
                                    static$team_games, windows = windows)
  conc <- build_team_concentration(h$player_games)
  ctx <- static$team_games |>
    dplyr::select("season", "week", "team", "kickoff_utc", "roof") |>
    dplyr::mutate(dome = .data$roof %in% "dome", game_date = as.Date(.data$kickoff_utc)) |>
    dplyr::select(-"roof", -"kickoff_utc")

  out <- out |>
    asof_join(player_states_m2(h$player_games_m2), by = "gsis_id", what = "m2 player state") |>
    asof_join(team_states_m2(h$team_pbp, conc), by = "team", what = "m2 team state") |>
    asof_join(defense_states_m2(h$def_pbp), by = "opponent", what = "m2 defense state") |>
    asof_join(team_qb_states(h$qb_game), by = "team", what = "m2 team qb") |>
    dplyr::left_join(
      dplyr::rename(qb_states(h$qb_game), last_qb_id = "qb_id", qb_state_index = "state_index"),
      by = dplyr::join_by("last_qb_id", closest(game_index > qb_state_index)), relationship = "many-to-one"
    ) |>
    dplyr::select(-"qb_state_index") |>
    safe_left_join(ctx, by = c("season", "week", "team"), what = "m2 schedule context") |>
    safe_left_join(static$bio, by = "gsis_id", what = "m2 bio")

  out |>
    dplyr::mutate(
      weeks_since_last_game = dplyr::if_else(.data$season_games > 0, .data$week - .data$last_game_week, NA_real_),
      age = as.numeric(.data$game_date - .data$birth_date) / 365.25,
      years_exp = .data$season - .data$rookie_season,
      is_rookie = .data$years_exp %in% 0,
      undrafted = is.na(.data$draft_pick),
      log_draft_pick = log(dplyr::coalesce(.data$draft_pick, 300)),
      no_prev_season = is.na(.data$prev_season_pts_mean),
      no_season_games = .data$season_games == 0
    ) |>
    dplyr::select(-"last_game_week", -"birth_date", -"rookie_season", -"draft_pick", -"game_date", -"last_qb_id")
}

# --- Generic leakage test ---------------------------------------------------------------

#' Corrupt every non-structural column of every history table at or after
#' `cutoff`: numbers are scaled and shifted, strings rewritten, logicals
#' flipped. Structural columns (season, week, game_index) are kept so rows stay
#' in place.
corrupt_from <- function(tbl, cutoff) {
  idx <- if ("game_index" %in% names(tbl)) tbl$game_index else game_index(tbl$season, tbl$week)
  hit <- idx >= cutoff
  if (!any(hit)) return(tbl)
  for (col in setdiff(names(tbl), c("season", "week", "game_index"))) {
    x <- tbl[[col]]
    if (is.numeric(x)) x[hit] <- x[hit] * 7 + 50
    else if (is.character(x)) x[hit] <- paste0("CORRUPT_", x[hit])
    else if (is.logical(x)) x[hit] <- !x[hit]
    tbl[[col]] <- x
  }
  tbl
}

#' Generic version of check_feature_leakage(): for random cutoff weeks, corrupt
#' ALL history tables from the cutoff onward and require that features of the
#' cutoff week's rows do not change. Returns leaking column names.
check_leakage_generic <- function(targets, histories, static, feature_fn, n_cutoffs = 6, seed = 1) {
  targets <- dplyr::mutate(targets, .gi = game_index(.data$season, .data$week))
  set.seed(seed)
  idx <- unique(targets$.gi)
  cutoffs <- idx[sample.int(length(idx), min(n_cutoffs, length(idx)))]
  leaks <- purrr::map(cutoffs, function(cut) {
    probe <- dplyr::filter(targets, .data$.gi == cut) |> dplyr::select(-".gi")
    base <- feature_fn(probe, histories, static)
    bad_h <- purrr::map(histories, corrupt_from, cutoff = cut)
    pert <- feature_fn(probe, bad_h, static)
    cols <- setdiff(names(base), names(probe))
    cols[!vapply(cols, function(c) identical(base[[c]], pert[[c]]), logical(1))]
  })
  sort(unique(unlist(leaks)))
}

FEATURES_M2 <- c(
  # history / temporal representations
  "fantasy_pts_ewma2", "fantasy_pts_ewma6", "fantasy_pts_roll1", "fantasy_pts_roll8",
  "season_pts_mean", "prev_season_pts_mean", "fantasy_pts_sd8",
  "log_career_games", "played_team_prev_game", "changed_team", "weeks_since_last_game",
  # opportunity
  "targets_ewma2", "targets_ewma6", "targets_roll2", "targets_roll4",
  "target_share_ewma2", "target_share_ewma6", "air_yards_share_ewma6",
  "snap_share_ewma2", "snap_share_ewma6", "xfp_ewma2", "xfp_ewma6",
  "deep_targets_ewma6", "rz_targets_ewma6", "endzone_targets_ewma6", "carries_ewma6",
  # role change
  "target_share_trend", "snap_share_trend", "xfp_trend", "target_share_sd8",
  # efficiency (shrunk)
  "ypt_shrunk", "catch_rate_shrunk", "adot_shrunk", "yac_per_rec_shrunk", "fpoe_shrunk",
  # team environment
  "team_plays_ewma", "team_dropbacks_ewma", "team_neutral_pass_rate_ewma", "team_pass_epa_ewma",
  "team_top_share_ewma", "team_hhi_ewma",
  # quarterback (lagged)
  "qb_changed_last_game", "qb_same_as_last4", "qb_epa_shrunk", "qb_db_per_game",
  # opponent
  "opp_pass_epa_allowed_shrunk", "opp_pts_allowed_roll",
  # priors
  "log_draft_pick", "undrafted", "age", "years_exp", "is_rookie",
  "no_prev_season", "no_season_games",
  # schedule context (no betting lines)
  "home", "rest_days", "dome", "week"
)

M2_FAMILIES <- list(
  history = c("fantasy_pts_ewma2", "fantasy_pts_ewma6", "fantasy_pts_roll1", "fantasy_pts_roll8",
              "season_pts_mean", "prev_season_pts_mean", "fantasy_pts_sd8", "log_career_games",
              "played_team_prev_game", "changed_team", "weeks_since_last_game"),
  opportunity = c("targets_ewma2", "targets_ewma6", "targets_roll2", "targets_roll4", "target_share_ewma2",
                  "target_share_ewma6", "air_yards_share_ewma6", "snap_share_ewma2", "snap_share_ewma6",
                  "xfp_ewma2", "xfp_ewma6", "deep_targets_ewma6", "rz_targets_ewma6",
                  "endzone_targets_ewma6", "carries_ewma6"),
  role_change = c("target_share_trend", "snap_share_trend", "xfp_trend", "target_share_sd8"),
  efficiency = c("ypt_shrunk", "catch_rate_shrunk", "adot_shrunk", "yac_per_rec_shrunk", "fpoe_shrunk"),
  team = c("team_plays_ewma", "team_dropbacks_ewma", "team_neutral_pass_rate_ewma", "team_pass_epa_ewma",
           "team_top_share_ewma", "team_hhi_ewma"),
  qb = c("qb_changed_last_game", "qb_same_as_last4", "qb_epa_shrunk", "qb_db_per_game"),
  opponent = c("opp_pass_epa_allowed_shrunk", "opp_pts_allowed_roll"),
  priors = c("log_draft_pick", "undrafted", "age", "years_exp", "is_rookie", "no_prev_season", "no_season_games"),
  context = c("home", "rest_days", "dome", "week")
)
