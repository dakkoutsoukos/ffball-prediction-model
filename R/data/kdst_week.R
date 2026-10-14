# F4 part 2: K and D/ST weekly outcomes (master plan F4; 05 section 4.6) ---------------------------
# Rule-free statistics from nflverse (kicker stat lines; team D/ST from play-by-play), then league
# points from the league's own K/DST scoring items, read at runtime from the private league snapshot
# (never committed). ESPN stat-id meanings: espn-api's football constant.py (public). 198 (made FG
# 50-59) and 209 (one-point safety on a try) are inferred: the map notes 74 = 50+ including 60+ and
# 201 = 60+; ESPN's support article describes the one-point try safety. ESPN's D/ST definitions
# (support.espn.com article 115003847231): points allowed exclude the opponent's interception- and
# fumble-return TDs against the team's offense, but special-teams points count; yards allowed are
# the opponent offense's yards; D/ST scores a fumble it recovers, not one the opponent loses.
# NOT validated against ESPN's own K/DST scoring: no ESPN K/DST actuals exist locally (owner
# decision O8, or the 2026 league data after R1).

KDST_SEASONS <- 2019:2025

# ESPN stat id -> statistic in these tables
KDST_ESPN_STATS <- c(
  `80` = "fg_made_0_39", `77` = "fg_made_40_49", `198` = "fg_made_50_59", `201` = "fg_made_60p", `74` = "fg_made_50p",
  `83` = "fg_made", `84` = "fg_att", `85` = "fg_missed", `86` = "pat_made", `87` = "pat_att", `88` = "pat_missed",
  `120` = "points_allowed", `89` = "pa_0", `90` = "pa_1_6", `91` = "pa_7_13", `92` = "pa_14_17", `121` = "pa_18_21",
  `122` = "pa_22_27", `123` = "pa_28_34", `124` = "pa_35_45", `125` = "pa_46p",
  `127` = "yards_allowed", `128` = "ya_0_99", `129` = "ya_100_199", `130` = "ya_200_299", `131` = "ya_300_349",
  `132` = "ya_350_399", `133` = "ya_400_449", `134` = "ya_450_499", `135` = "ya_500_549", `136` = "ya_550p",
  `93` = "blocked_kick_return_td", `94` = "def_td", `95` = "interceptions", `96` = "fumble_recoveries",
  `97` = "blocked_kicks", `98` = "safeties", `99` = "sacks", `101` = "kick_return_td", `102` = "punt_return_td",
  `103` = "int_return_td", `104` = "fumble_return_td", `105` = "def_st_td", `206` = "two_pt_return", `209` = "one_pt_safety"
)
KDST_K_STATS <- c("fg_made_0_39", "fg_made_40_49", "fg_made_50_59", "fg_made_60p", "fg_made_50p", "fg_made", "fg_att",
                  "fg_missed", "pat_made", "pat_att", "pat_missed")
KDST_DST_STATS <- setdiff(unname(KDST_ESPN_STATS), KDST_K_STATS)
# tier upper bounds (inclusive); the first tier is open below (negative yards are "less than 100")
KDST_PA_TIERS <- c(pa_0 = 0, pa_1_6 = 6, pa_7_13 = 13, pa_14_17 = 17, pa_18_21 = 21, pa_22_27 = 27, pa_28_34 = 34,
                   pa_35_45 = 45, pa_46p = Inf)
KDST_YA_TIERS <- c(ya_0_99 = 99, ya_100_199 = 199, ya_200_299 = 299, ya_300_349 = 349, ya_350_399 = 399,
                   ya_400_449 = 449, ya_450_499 = 499, ya_500_549 = 549, ya_550p = Inf)
KDST_PBP_COLS <- c("season", "season_type", "week", "game_id", "posteam", "defteam", "play_type", "td_team", "touchdown",
                   "interception", "sack", "safety", "punt_blocked", "field_goal_result", "extra_point_result",
                   "fumbled_1_team", "fumble_recovery_1_team", "fumbled_2_team", "fumble_recovery_2_team",
                   "defensive_two_point_conv", "defensive_extra_point_conv", "two_point_attempt", "extra_point_attempt",
                   "yards_gained", "kick_distance", "kicker_player_id", "total_home_score", "total_away_score",
                   "home_team", "away_team")

#' One-hot tier indicators (a tibble with one column per tier) for values x.
kdst_tiers <- function(x, tiers) {
  lower <- c(-Inf, utils::head(unname(tiers), -1))
  out <- lapply(seq_along(tiers), function(i) as.numeric(!is.na(x) & x > lower[i] & x <= tiers[i]))
  tibble::as_tibble(stats::setNames(out, names(tiers)))
}

#' Regular-season play-by-play columns needed for K/DST, read from the raw parquet files via DuckDB.
kdst_read_pbp <- function(pbp_paths, seasons = KDST_SEASONS) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  files <- paste0("'", gsub("\\\\", "/", pbp_paths), "'", collapse = ", ")
  sql <- sprintf("SELECT %s FROM read_parquet([%s], union_by_name = true) WHERE season_type = 'REG' AND season IN (%s)",
                 paste(KDST_PBP_COLS, collapse = ", "), files, paste(seasons, collapse = ", "))
  tibble::as_tibble(DBI::dbGetQuery(con, sql)) |>
    dplyr::mutate(season = as.integer(.data$season), week = as.integer(.data$week),
                  dplyr::across(c("posteam", "defteam", "td_team", "fumbled_1_team", "fumble_recovery_1_team",
                                  "fumbled_2_team", "fumble_recovery_2_team", "home_team", "away_team"), standardize_team))
}

#' Team D/ST statistics per team-game from play-by-play plus final scores from the schedule.
#' Scrimmage plays: the D/ST is the defense. Kicks: both units are special teams (nflverse sets
#' posteam = receiving team on kickoffs, = kicking team on punts, field goals and tries).
kdst_dst_stats <- function(pbp, schedules) {
  scrim <- pbp$play_type %in% c("pass", "run", "qb_kneel", "qb_spike")
  kick <- pbp$play_type %in% c("kickoff", "punt", "field_goal", "extra_point")
  na0 <- function(x) dplyr::coalesce(as.numeric(x), 0)
  p <- dplyr::mutate(pbp, scrim = scrim, kick = kick,
                     dplyr::across(c("touchdown", "interception", "sack", "safety", "punt_blocked", "two_point_attempt",
                                     "extra_point_attempt", "defensive_two_point_conv", "defensive_extra_point_conv",
                                     "yards_gained"), na0))
  credit <- function(d, team_col, name) {
    d |> dplyr::filter(!is.na(.data[[team_col]])) |>
      dplyr::count(game_id = .data$game_id, team = .data[[team_col]], name = name)
  }
  # defensive and special-teams touchdowns, by type, credited to the scoring team
  td <- dplyr::filter(p, .data$touchdown == 1, !is.na(.data$td_team))
  st_returner <- dplyr::if_else(td$play_type == "kickoff", td$posteam, td$defteam)  # receiving team on kicks
  td_type <- dplyr::case_when(
    td$scrim & td$td_team == td$defteam & td$interception == 1 ~ "int_return_td",
    td$scrim & td$td_team == td$defteam ~ "fumble_return_td",
    td$kick & td$td_team == st_returner & (td$punt_blocked == 1 | td$field_goal_result %in% "blocked") ~ "blocked_kick_return_td",
    td$play_type == "kickoff" & td$td_team == td$posteam ~ "kick_return_td",
    td$play_type == "punt" & td$td_team == td$defteam ~ "punt_return_td",
    td$play_type == "field_goal" & td$td_team == td$defteam ~ "kick_return_td",      # a missed field goal returned
    td$kick & td$td_team != st_returner ~ "fumble_return_td",                        # kicking team recovers and scores
    TRUE ~ NA_character_
  )
  tds <- dplyr::filter(dplyr::mutate(td, type = td_type), !is.na(.data$type)) |>
    dplyr::count(game_id = .data$game_id, team = .data$td_team, type = .data$type) |>
    tidyr::pivot_wider(names_from = "type", values_from = "n", values_fill = 0)
  # fumble recoveries of the opponent's fumbles by the D/ST unit (the defense, or either kick unit)
  fr <- dplyr::bind_rows(
    dplyr::transmute(p, .data$game_id, .data$scrim, .data$kick, .data$defteam, fum = .data$fumbled_1_team,
                     rec = .data$fumble_recovery_1_team),
    dplyr::transmute(p, .data$game_id, .data$scrim, .data$kick, .data$defteam, fum = .data$fumbled_2_team,
                     rec = .data$fumble_recovery_2_team)
  ) |>
    dplyr::filter(!is.na(.data$fum), !is.na(.data$rec), .data$fum != .data$rec,
                  .data$kick | (.data$scrim & .data$rec == .data$defteam)) |>
    dplyr::count(game_id = .data$game_id, team = .data$rec, name = "fumble_recoveries")
  blocked <- dplyr::filter(p, .data$punt_blocked == 1 | .data$field_goal_result %in% "blocked" |
                             .data$extra_point_result %in% "blocked")
  try_safety <- (p$extra_point_attempt == 1 | p$two_point_attempt == 1) & p$safety == 1
  parts <- list(
    credit(dplyr::filter(p, .data$sack == 1), "defteam", "sacks"),
    credit(dplyr::filter(p, .data$interception == 1), "defteam", "interceptions"),
    credit(dplyr::filter(p, .data$safety == 1, !try_safety), "defteam", "safeties"),
    credit(dplyr::filter(p, try_safety), "defteam", "one_pt_safety"),
    credit(blocked, "defteam", "blocked_kicks"),
    credit(dplyr::filter(p, .data$defensive_two_point_conv == 1 | .data$defensive_extra_point_conv == 1), "defteam",
           "two_pt_return"),
    fr, tds,
    # opponent offense yards (scrimmage plays, tries excluded), credited to the defending team
    p |> dplyr::filter(.data$scrim, .data$two_point_attempt == 0, !is.na(.data$defteam)) |>
      dplyr::mutate(team = .data$defteam) |> dplyr::summarise(yards_allowed = sum(.data$yards_gained), .by = c("game_id", "team")),
    # the opponent's defensive return TDs against this team's offense (excluded from points allowed)
    td |> dplyr::filter(.data$scrim, .data$td_team == .data$defteam) |>
      dplyr::count(game_id = .data$game_id, team = .data$posteam, name = "pick6_against")
  )
  games <- schedules |>
    dplyr::filter(.data$game_type == "REG", !is.na(.data$home_score)) |>
    dplyr::transmute(season = as.integer(.data$season), week = as.integer(.data$week), .data$game_id,
                     home = standardize_team(.data$home_team), away = standardize_team(.data$away_team),
                     home_score = as.numeric(.data$home_score), away_score = as.numeric(.data$away_score))
  sides <- dplyr::bind_rows(
    dplyr::transmute(games, .data$season, .data$week, .data$game_id, team = .data$home, opponent = .data$away,
                     opp_score = .data$away_score),
    dplyr::transmute(games, .data$season, .data$week, .data$game_id, team = .data$away, opponent = .data$home,
                     opp_score = .data$home_score)
  ) |>
    dplyr::filter(.data$game_id %in% unique(pbp$game_id))
  out <- Reduce(function(a, b) dplyr::left_join(a, b, by = c("game_id", "team")), parts, sides)
  stat_cols <- c("sacks", "interceptions", "safeties", "one_pt_safety", "blocked_kicks", "two_pt_return", "fumble_recoveries",
                 "int_return_td", "fumble_return_td", "blocked_kick_return_td", "kick_return_td", "punt_return_td",
                 "yards_allowed", "pick6_against")
  for (c in setdiff(stat_cols, names(out))) out[[c]] <- 0
  out <- dplyr::mutate(out, dplyr::across(dplyr::all_of(stat_cols), ~ dplyr::coalesce(as.numeric(.x), 0)),
                       def_td = .data$int_return_td + .data$fumble_return_td,
                       def_st_td = .data$def_td + .data$blocked_kick_return_td + .data$kick_return_td + .data$punt_return_td,
                       points_allowed = .data$opp_score - 6 * .data$pick6_against,
                       points_allowed_total = .data$opp_score)
  dplyr::bind_cols(out, kdst_tiers(out$points_allowed, KDST_PA_TIERS), kdst_tiers(out$yards_allowed, KDST_YA_TIERS)) |>
    dplyr::arrange(.data$season, .data$week, .data$team) |>
    assert_unique_key(c("season", "week", "team"), "kdst_dst_stats")
}

#' Kicker statistics per player-game from nflverse's weekly player stats (position K, regular season).
#' Missed field goals include blocked ones (attempts = made + missed + blocked in nflverse).
kdst_k_stats <- function(raw_player_stats, seasons = KDST_SEASONS) {
  num <- function(x) dplyr::coalesce(as.numeric(x), 0)
  read_parquet_files(raw_player_stats) |>
    dplyr::filter(.data$season_type == "REG", .data$season %in% !!seasons, .data$position %in% "K") |>
    dplyr::transmute(season = as.integer(.data$season), week = as.integer(.data$week), gsis_id = .data$player_id,
                     player_name = .data$player_display_name, team = standardize_team(.data$team),
                     opponent = standardize_team(.data$opponent_team), .data$game_id,
                     fg_made_0_39 = num(.data$fg_made_0_19) + num(.data$fg_made_20_29) + num(.data$fg_made_30_39),
                     fg_made_40_49 = num(.data$fg_made_40_49), fg_made_50_59 = num(.data$fg_made_50_59),
                     fg_made_60p = num(.data$fg_made_60_), fg_made = num(.data$fg_made), fg_att = num(.data$fg_att),
                     pat_made = num(.data$pat_made), pat_att = num(.data$pat_att)) |>
    dplyr::mutate(fg_made_50p = .data$fg_made_50_59 + .data$fg_made_60p, fg_missed = .data$fg_att - .data$fg_made,
                  pat_missed = .data$pat_att - .data$pat_made) |>
    assert_unique_key(c("season", "week", "gsis_id"), "kdst_k_stats")
}

#' K and D/ST scoring rules from league settings: points per statistic for the K slot (17) and the
#' D/ST slot (16), slot overrides first. Items whose statistic these tables do not compute abort if
#' they could score for K or D/ST.
kdst_rules_from_settings <- function(settings) {
  items <- settings$scoringSettings$scoringItems %||% list()
  ov <- function(i, slot) {
    o <- i$pointsOverrides %||% list()
    if (!is.null(o[[slot]])) as.numeric(o[[slot]]) else as.numeric(i$points %||% 0)
  }
  tab <- tibble::tibble(stat_id = vapply(items, function(i) as.character(i$statId), ""),
                        points_k = vapply(items, ov, 0, slot = "17"),
                        points_dst = vapply(items, ov, 0, slot = "16"))
  tab$stat <- unname(KDST_ESPN_STATS[tab$stat_id])
  # only items in the K/DST id ranges matter here; skill items are scored by player_stats
  kd <- dplyr::filter(tab, as.integer(.data$stat_id) %in% c(74:140, 187:215))
  unmapped <- dplyr::filter(kd, is.na(.data$stat), .data$points_k != 0 | .data$points_dst != 0)
  if (nrow(unmapped)) cli::cli_abort("Unmapped K/DST scoring item{?s}: stat id {.val {unmapped$stat_id}}.")
  dplyr::filter(kd, !is.na(.data$stat)) |>
    dplyr::select("stat_id", "stat", "points_k", "points_dst")
}

#' Points of a K or D/ST table under the rules (sum of points x statistic). Only the unit's own
#' statistics count: an item's base points reach every slot, but a D/ST records no kicks and a
#' kicker no defensive plays.
kdst_points <- function(stats, rules, unit = c("K", "DST")) {
  unit <- match.arg(unit)
  pts <- if (unit == "K") rules$points_k else rules$points_dst
  own <- if (unit == "K") KDST_K_STATS else KDST_DST_STATS
  keep <- pts != 0 & rules$stat %in% own
  missing <- setdiff(rules$stat[keep], names(stats))
  if (length(missing)) cli::cli_abort("{unit} statistics missing for scored item{?s}: {.val {missing}}.")
  out <- numeric(nrow(stats))
  for (i in which(keep)) out <- out + pts[i] * stats[[rules$stat[i]]]
  round(out, 2)
}

#' K table with league points: kicking items plus any offensive points the kicker scored (a fake),
#' from the cleaned player stats (league offense = ESPN PPR).
kdst_k_week <- function(k_stats, player_stats, rules) {
  k_stats |>
    dplyr::left_join(dplyr::select(player_stats, "season", "week", "gsis_id", offense_pts = "fantasy_pts"),
                     by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(offense_pts = dplyr::coalesce(.data$offense_pts, 0),
                  k_points = kdst_points(k_stats, rules, "K") + .data$offense_pts)
}

#' D/ST table with league points; `dst_points_pa_total` is the sensitivity variant that counts every
#' opponent point as allowed.
kdst_dst_week <- function(dst_stats, rules) {
  alt <- dplyr::select(dst_stats, -dplyr::any_of(names(KDST_PA_TIERS)))
  alt <- dplyr::bind_cols(alt, kdst_tiers(dst_stats$points_allowed_total, KDST_PA_TIERS))
  alt$points_allowed <- alt$points_allowed_total
  dplyr::mutate(dst_stats, dst_points = kdst_points(dst_stats, rules, "DST"),
                dst_points_pa_total = kdst_points(alt, rules, "DST"))
}

#' Team K points per team-game (the sum over the team's kickers; 0 when no kicker recorded a stat).
kdst_team_k <- function(k_week, team_games, seasons = KDST_SEASONS) {
  team_games |>
    dplyr::filter(.data$season %in% !!seasons) |>
    dplyr::select("season", "week", "team", "opponent", "game_id") |>
    dplyr::left_join(dplyr::summarise(k_week, k_points = sum(.data$k_points), kickers = dplyr::n(),
                                      .by = c("season", "week", "team")), by = c("season", "week", "team")) |>
    dplyr::mutate(k_points = dplyr::coalesce(.data$k_points, 0), kickers = dplyr::coalesce(.data$kickers, 0L))
}

#' Internal cross-source checks (aggregates). K: field goals by distance band and tries from
#' play-by-play vs the kicker stat lines. D/ST: sacks and interceptions vs defenders' stat lines;
#' final scores in play-by-play vs the schedule; one D/ST row per team-game.
kdst_checks <- function(dst_stats, k_stats, pbp, raw_player_stats, team_games, seasons = KDST_SEASONS) {
  fg <- pbp |>
    dplyr::filter(.data$play_type %in% "field_goal", !is.na(.data$kicker_player_id)) |>
    dplyr::mutate(gsis_id = .data$kicker_player_id, made = .data$field_goal_result %in% "made",
                  band = cut(.data$kick_distance, c(-Inf, 39, 49, 59, Inf), labels = c("0_39", "40_49", "50_59", "60p"))) |>
    dplyr::summarise(pbp_fg_att = dplyr::n(), pbp_0_39 = sum(.data$made & .data$band == "0_39"),
                     pbp_40_49 = sum(.data$made & .data$band == "40_49"), pbp_50_59 = sum(.data$made & .data$band == "50_59"),
                     pbp_60p = sum(.data$made & .data$band == "60p"), .by = c("season", "week", "gsis_id"))
  xp <- pbp |>
    dplyr::filter(.data$play_type %in% "extra_point", !is.na(.data$kicker_player_id)) |>
    dplyr::mutate(gsis_id = .data$kicker_player_id) |>
    dplyr::summarise(pbp_pat_made = sum(.data$extra_point_result %in% "good"), pbp_pat_att = dplyr::n(),
                     .by = c("season", "week", "gsis_id"))
  k <- k_stats |>
    dplyr::left_join(fg, by = c("season", "week", "gsis_id")) |>
    dplyr::left_join(xp, by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("pbp_"), ~ dplyr::coalesce(as.numeric(.x), 0)))
  ps <- read_parquet_files(raw_player_stats) |>
    dplyr::filter(.data$season_type == "REG", .data$season %in% !!seasons) |>
    dplyr::mutate(season = as.integer(.data$season), week = as.integer(.data$week), team = standardize_team(.data$team)) |>
    dplyr::summarise(ps_sacks = sum(as.numeric(.data$def_sacks), na.rm = TRUE),
                     ps_ints = sum(as.numeric(.data$def_interceptions), na.rm = TRUE), .by = c("season", "week", "team"))
  d <- dplyr::left_join(dst_stats, ps, by = c("season", "week", "team"))
  final <- pbp |>
    dplyr::summarise(home = dplyr::first(.data$home_team), away = dplyr::first(.data$away_team),
                     hs = max(.data$total_home_score, na.rm = TRUE), as = max(.data$total_away_score, na.rm = TRUE),
                     .by = "game_id")
  sc <- dplyr::left_join(dst_stats, final, by = "game_id") |>
    dplyr::mutate(pbp_opp = dplyr::if_else(.data$team == .data$home, .data$as, .data$hs))
  tg <- dplyr::filter(team_games, .data$season %in% !!seasons)
  list(
    k_rows = nrow(k),
    k_fg_bands_match = mean(k$fg_made_0_39 == k$pbp_0_39 & k$fg_made_40_49 == k$pbp_40_49 &
                              k$fg_made_50_59 == k$pbp_50_59 & k$fg_made_60p == k$pbp_60p),
    k_fg_att_match = mean(k$fg_att == k$pbp_fg_att),
    k_pat_made_match = mean(k$pat_made == k$pbp_pat_made),
    dst_rows = nrow(dst_stats), team_games = nrow(tg),
    dst_rows_missing = nrow(dplyr::anti_join(tg, dst_stats, by = c("season", "week", "team"))),
    dst_sacks_match = mean(abs(d$sacks - d$ps_sacks) < 1e-9, na.rm = TRUE),
    dst_ints_match = mean(abs(d$interceptions - d$ps_ints) < 1e-9, na.rm = TRUE),
    dst_score_match = mean(sc$opp_score == sc$pbp_opp, na.rm = TRUE)
  )
}
