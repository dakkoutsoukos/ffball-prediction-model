# P4 season dynamics (VL4). Synthetic data only.

p4_toy <- function(seed = 1, season = 2021L, n_per_pos = 70) {
  set.seed(seed)
  teams <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE")
  players <- tibble::tibble(position = rep(c("QB", "RB", "WR", "TE"), each = n_per_pos)) |>
    dplyr::mutate(gsis_id = sprintf("%s%03d", .data$position, dplyr::row_number()), team = sample(teams, dplyr::n(), TRUE),
                  level = stats::runif(dplyr::n(), 2, 20), shock = stats::rlnorm(dplyr::n(), -0.045, 0.3))
  bye <- stats::setNames(rep(6:9, 2), teams)
  tg <- tidyr::expand_grid(season = season, week = 1:17, team = teams) |> dplyr::filter(.data$week != bye[.data$team])
  fr <- tidyr::expand_grid(players, week = 1:17) |>
    dplyr::semi_join(tg, by = c("week", "team")) |>
    dplyr::mutate(season = season, espn_proj = .data$level, base = .data$level,
                  active = stats::runif(dplyr::n()) < 0.92,
                  actual = ifelse(.data$active, .data$level * .data$shock + stats::rnorm(dplyr::n(), 0, 4), 0))
  list(frame = fr, team_games = tg)
}

test_that("horizon buckets", {
  expect_equal(as.character(p4_bucket(c(1, 2, 3, 4, 7, 8, 12))), c("1", "2-3", "2-3", "4-7", "4-7", "8+", "8+"))
})

test_that("ROS rows keep the relevant players, skip byes and score missing rows as 0", {
  x <- p4_toy()
  S <- lab_season_data(x$frame, x$team_games, 2021L)
  r <- p4_ros_rows(S, 4L)
  expect_true(all(r$t > 4 & r$t <= 16))
  n_rel <- dplyr::summarise(dplyr::distinct(r, .data$gsis_id, .data$position), n = dplyr::n(), .by = "position")
  expect_equal(n_rel$n[match(names(P4_RELEVANT), n_rel$position)], unname(pmin(P4_RELEVANT, 70)))
  # no row in a bye week of the player's team
  tm <- S$team_asof[match(r$gsis_id, S$ids), 4]
  expect_true(all(S$plays[cbind(match(tm, S$teams), r$t)]))
  expect_true(all(r$y[!r$active] == 0))
})

test_that("components recover the mean slope and the attrition share", {
  x <- p4_toy(seed = 2)
  S <- lab_season_data(x$frame, x$team_games, 2021L)
  rows <- p4_ros_rows(S, 1:12)
  comp <- p4_fit_components(rows)
  d <- rows[rows$position == "WR" & rows$bucket == "4-7" & rows$active, ]
  expect_equal(comp$mu$b[comp$mu$position == "WR" & comp$mu$bucket == "4-7"], unname(stats::coef(stats::lm(y ~ L, d))[2]))
  expect_true(abs(comp$mu$b[comp$mu$position == "WR" & comp$mu$bucket == "1"] - 1) < 0.25)   # 60 players: near 1
  expect_true(all(abs(comp$att_pb$A_pb - 0.92) < 0.05))
  ap <- p4_apply_components(rows, comp)
  expect_false(anyNA(ap$mu))
  expect_true(all(ap$A > 0.8 & ap$A <= 1))
})

test_that("simulation matching recovers a planted level-shock scale", {
  set.seed(5)
  G <- 3000
  f <- stats::runif(G, 40, 160)
  draws <- 300
  B <- f + matrix(stats::rnorm(G * draws, 0, 15), G, draws)
  s_true <- 0.3
  actual <- exp(-s_true^2 / 2 + s_true * stats::rnorm(G)) * (f + stats::rnorm(G, 0, 15))
  groups <- tibble::tibble(group = paste0("g", 1:G), position = "WR", L = f / 10, actual = actual, forecast = f)
  pre <- list(B = B, Z = matrix(stats::rnorm(G * draws), G, draws), group = groups$group)
  m <- p4_match_sigma(groups, pre)
  expect_true(all(abs(m$sigma$sigma_L - s_true) < 0.06))
  q <- p4_ros_quantiles(groups[1:5, ], list(B = B[1:5, ], Z = pre$Z[1:5, ], group = groups$group[1:5]), m)$q
  expect_true(all(apply(q, 1, function(x) !is.unsorted(x))))
  qn <- p4_normal_quantiles(dplyr::mutate(groups[1:5, ], w = 4L), tibble::tibble(position = "WR", w = 4L, sd = 20))
  expect_equal(qn[, 50], groups$forecast[1:5])
})

test_that("X2 finds persistent residuals and X26 recovers a revision slope", {
  x <- p4_toy(seed = 6)
  fr <- dplyr::mutate(x$frame, pop_espn = TRUE)
  ac <- p4_x2_autocorr(fr, lags = 1)
  expect_true(all(ac$autocorr > 0.05))                          # the planted season-long shock persists
  fr2 <- fr |>
    dplyr::arrange(.data$gsis_id, .data$week) |>
    dplyr::mutate(r = .data$actual - .data$base,
                  espn_proj = .data$base + 0.2 * dplyr::lag(.data$r, default = 0), .by = "gsis_id")
  rv <- p4_x26_revision(dplyr::select(fr2, -"r"))
  expect_true(all(rv$slope > 0.1))
})
