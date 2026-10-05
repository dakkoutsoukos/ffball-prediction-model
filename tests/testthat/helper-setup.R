# Source project code and provide small synthetic fixtures for tests.
project_root <- normalizePath(testthat::test_path("..", ".."))
for (f in list.files(file.path(project_root, "R"), pattern = "\\.[Rr]$",
                     recursive = TRUE, full.names = TRUE)) {
  source(f)
}

#' Toy league: two teams (AAA, BBB) playing each other weeks 1-4 of 2023 and
#' 2024 (BBB has a bye in 2024 week 3). Player p1 (AAA) plays every game except
#' 2024 week 2; p2 (BBB) plays only 2024; p3 (AAA) only has a snap-only game.
toy_inputs <- function() {
  sched <- tidyr::expand_grid(season = c(2023L, 2024L), week = 1:4) |>
    dplyr::filter(!(season == 2024L & week == 3L)) |>
    dplyr::mutate(game_id = paste(season, week, sep = "_"))
  team_games <- dplyr::bind_rows(
    dplyr::mutate(sched, team = "AAA", opponent = "BBB", home = TRUE),
    dplyr::mutate(sched, team = "BBB", opponent = "AAA", home = FALSE)
  ) |>
    dplyr::mutate(
      team_spread = ifelse(home, 3, -3), total_line = 44,
      implied_team_total = (total_line + team_spread) / 2,
      game_index = game_index(season, week)
    )

  p1 <- sched |>
    dplyr::filter(!(season == 2024L & week == 2L)) |>
    dplyr::mutate(gsis_id = "p1", team = "AAA", opponent = "BBB",
                  fantasy_pts = 10 * week + (season - 2023) * 100, targets = week)
  p2 <- sched |>
    dplyr::filter(season == 2024L) |>
    dplyr::mutate(gsis_id = "p2", team = "BBB", opponent = "AAA",
                  fantasy_pts = 5, targets = 3)
  stats <- dplyr::bind_rows(p1, p2) |>
    dplyr::mutate(
      stats_position = "WR", receptions = targets, receiving_yards = 10 * targets,
      receiving_tds = 0, receiving_air_yards = 8 * targets, carries = 0, attempts = 0
    )
  snaps <- dplyr::bind_rows(
    dplyr::transmute(stats, season, week, gsis_id, snap_team = team, snap_share = 0.8),
    tibble::tibble(season = 2024L, week = 1L, gsis_id = "p3", snap_team = "AAA", snap_share = 0.1)
  )
  pbp_usage <- dplyr::transmute(stats, season, week, gsis_id, rz_targets = 1)
  xfp <- dplyr::transmute(stats, season, week, gsis_id, xfp = fantasy_pts / 2)

  player_games <- build_player_games(stats, snaps, pbp_usage, xfp)
  list(
    stats = stats, team_games = team_games, player_games = player_games,
    team_volume = build_team_volume(stats),
    defense_allowed = build_defense_allowed(stats, team_games)
  )
}

toy_targets <- function(inp) {
  # Every scheduled (player, week) for p1/p2/p3 - including weeks they missed.
  tidyr::expand_grid(gsis_id = c("p1", "p2", "p3"), dplyr::distinct(inp$team_games, season, week)) |>
    dplyr::mutate(team = ifelse(gsis_id == "p2", "BBB", "AAA"),
                  opponent = ifelse(gsis_id == "p2", "AAA", "BBB")) |>
    dplyr::semi_join(inp$team_games, by = c("season", "week", "team"))
}

toy_features <- function(inp = toy_inputs()) {
  add_point_in_time_features(
    toy_targets(inp), inp$player_games, inp$team_volume, inp$defense_allowed, inp$team_games
  )
}
