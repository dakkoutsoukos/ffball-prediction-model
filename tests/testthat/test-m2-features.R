test_that("ewma_mean weights recent games more and skips missing values", {
  x <- c(10, 0, 0)
  e <- ewma_mean(x, 1)                       # weights 1, 0.5, 0.25 going back
  expect_equal(e[1], 10)
  expect_equal(e[2], (0 + 0.5 * 10) / 1.5)
  expect_equal(e[3], (0 + 0.5 * 0 + 0.25 * 10) / 1.75)
  expect_equal(ewma_mean(c(NA, 4, NA), 2), c(NA, 4, 4))
  expect_gt(ewma_mean(c(0, 0, 10), 1)[3], ewma_mean(c(0, 0, 10), 6)[3])   # short halflife reacts faster
})

test_that("trailing sums, sds and shrinkage behave", {
  expect_equal(trailing_sum(c(1, 2, 3, NA), 2), c(1, 3, 5, 3))
  expect_equal(trailing_sd(c(1, 3, 5), 2), c(NA, sd(c(1, 3)), sd(c(3, 5))))
  expect_equal(shrunk_rate(0, 0, 8, 30), 8)                 # no data -> prior
  expect_equal(shrunk_rate(1000, 100, 8, 30), (1000 + 240) / 130)
})

toy_m2 <- function() {
  inp <- toy_inputs()
  tg <- inp$team_games |>
    dplyr::mutate(kickoff_utc = as.POSIXct(paste0(season, "-09-01 17:00"), tz = "UTC") + week * 7 * 86400,
                  roof = ifelse(team == "AAA", "dome", "outdoors"), rest_days = 7)
  games <- dplyr::distinct(tg, season, week, team, opponent)
  team_pbp <- dplyr::transmute(games, season, week, team, plays = 60 + week, dropbacks = 35 + week,
                               pass_epa_per_db = 0.01 * week, neutral_pass_rate = 0.55)
  def_pbp <- dplyr::transmute(games, season, week, defense = opponent, db_faced = 35, pass_epa_allowed_sum = week)
  qb_game <- dplyr::transmute(games, season, week, team, qb_id = paste0("qb_", team, ifelse(week >= 3, "2", "1")),
                              dropbacks = 35, epa_sum = 3, starter = TRUE)
  rec <- dplyr::transmute(inp$stats, season, week, gsis_id, deep_targets = 1, yac = 10)
  usage <- dplyr::transmute(inp$stats, season, week, gsis_id, endzone_targets = 1)
  stats <- dplyr::mutate(inp$stats, rushing_yards = 0)
  h <- m2_histories(inp$player_games, inp$team_volume, inp$defense_allowed, rec, usage, stats,
                    team_pbp, def_pbp, qb_game)
  bio <- tibble::tibble(gsis_id = c("p1", "p2", "p3"), draft_pick = c(10, NA, 200),
                        birth_date = as.Date(c("1998-01-01", "2000-06-01", "1999-01-01")),
                        rookie_season = c(2020L, 2024L, 2023L))
  targets <- dplyr::left_join(toy_targets(inp), dplyr::select(tg, season, week, team, home, rest_days),
                              by = c("season", "week", "team"))
  list(inp = inp, histories = h, static = list(team_games = tg, bio = bio), targets = targets)
}

test_that("M2 features compute from prior games and priors from bio", {
  t <- toy_m2()
  f <- add_m2_features(t$targets, t$histories, t$static)
  expect_true(all(FEATURES_M2 %in% names(f)))
  p1 <- dplyr::filter(f, gsis_id == "p1", season == 2023L, week == 3L)
  expect_equal(p1$fantasy_pts_roll1, 20)                  # previous game only
  expect_equal(p1$targets_roll2, mean(c(1, 2)))
  expect_true(p1$qb_changed_last_game %in% FALSE)          # week-2 starter same as week 1
  p1w4 <- dplyr::filter(f, gsis_id == "p1", season == 2023L, week == 4L)
  expect_true(p1w4$qb_changed_last_game)                   # starter changed in week 3, known by week 4
  p2 <- dplyr::filter(f, gsis_id == "p2", season == 2024L, week == 1L)
  expect_true(p2$is_rookie)
  expect_true(p2$undrafted)
  expect_true(is.na(p2$fantasy_pts_ewma2))                # no history yet
  expect_true(dplyr::filter(f, team == "AAA")$dome[1])
})

test_that("corrupt_from changes everything except structural columns", {
  tbl <- tibble::tibble(season = 2024L, week = 1:2, qb_id = c("a", "b"), x = c(1, 2), flag = c(TRUE, TRUE))
  out <- corrupt_from(tbl, game_index(2024, 2))
  expect_equal(out$week, 1:2)
  expect_equal(out$x, c(1, 2 * 7 + 50))
  expect_equal(out$qb_id, c("a", "CORRUPT_b"))
  expect_equal(out$flag, c(TRUE, FALSE))
})

test_that("generic corruption test passes M2 features and catches leaks", {
  t <- toy_m2()
  targets <- t$targets
  expect_identical(check_leakage_generic(targets, t$histories, t$static, add_m2_features, n_cutoffs = 100),
                   character(0))
  leaky <- function(targets, histories, static) {
    same_week_qb <- dplyr::filter(histories$qb_game, starter) |> dplyr::select(season, week, team, now_qb = qb_id)
    add_m2_features(targets, histories, static) |>
      dplyr::left_join(same_week_qb, by = c("season", "week", "team"))
  }
  expect_true("now_qb" %in% check_leakage_generic(targets, t$histories, t$static, leaky, n_cutoffs = 100))
})

test_that("fast ewma_mean equals the recursive reference", {
  set.seed(5)
  x <- c(rnorm(160, 5, 3), NA, rnorm(20))
  x[c(3, 50)] <- NA
  for (h in c(1, 2, 6)) expect_equal(ewma_mean(x, h), ewma_mean_recursive(x, h), tolerance = 1e-10)
  expect_equal(ewma_mean(rep(1, 3000), 1), ewma_mean_recursive(rep(1, 3000), 1))   # overflow fallback
})

test_that("fast player_states_m2 matches the readable reference implementation", {
  t <- toy_m2()
  a <- player_states_m2(t$histories$player_games_m2)
  b <- player_states_m2_reference(t$histories$player_games_m2)[, names(a)]
  expect_equal(as.data.frame(dplyr::arrange(a, gsis_id, state_index)),
               as.data.frame(dplyr::arrange(b, gsis_id, state_index)), check.attributes = FALSE, tolerance = 1e-10)
})
