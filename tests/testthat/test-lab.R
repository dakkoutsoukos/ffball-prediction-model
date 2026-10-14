# F6 decision laboratory v1 (LAB1). Synthetic seasons only.

lab_toy_frame <- function(seed = 1, n_teams = 8, season = 2021L) {
  set.seed(seed)
  teams <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE")[seq_len(n_teams)]
  counts <- c(QB = 20, RB = 60, WR = 70, TE = 25)
  players <- tibble::tibble(position = rep(names(counts), counts)) |>
    dplyr::mutate(gsis_id = sprintf("%s%03d", .data$position, dplyr::row_number()),
                  team = sample(teams, dplyr::n(), replace = TRUE),
                  level = stats::rgamma(dplyr::n(), 2, 2 / c(QB = 16, RB = 8, WR = 8, TE = 6)[.data$position]))
  bye <- stats::setNames(rep(5:8, length.out = n_teams), teams)
  tg <- tidyr::expand_grid(season = season, week = 1:17, team = teams) |>
    dplyr::filter(.data$week != bye[.data$team])
  fr <- tidyr::expand_grid(players, week = 1:17) |>
    dplyr::semi_join(tg, by = c("week", "team")) |>
    dplyr::mutate(season = season,
                  espn_proj = pmax(0, .data$level * stats::rlnorm(dplyr::n(), 0, 0.15)),
                  base = 0.5 + 0.9 * .data$espn_proj,
                  actual = pmax(0, .data$espn_proj + stats::rnorm(dplyr::n(), 0, 5)),
                  active = TRUE)
  list(frame = fr, team_games = tg)
}

lab_toy_S <- function(...) {
  x <- lab_toy_frame(...)
  lab_season_data(x$frame, x$team_games, unique(x$frame$season))
}

lab_toy_calib <- function() tibble::tibble(position = LAB_POSITIONS, a = c(1, 0, -0.5, 0.3), b = c(0.75, 0.85, 0.9, 0.75))

test_that("L_avg4 averages the last up-to-4 positive values and carries them through gaps", {
  m <- rbind(c(4, 0, 8, NA, 6, 2, 10), c(NA, NA, NA, NA, NA, NA, NA))
  L <- lab_level_avg4(m)
  expect_equal(L[1, ], c(4, 4, 6, 6, 6, 5, 6.5))
  expect_true(all(is.na(L[2, ])))
})

test_that("the firewall truncates every matrix to the decision time", {
  S <- lab_toy_S()
  d <- lab_info(S, 1, "draft")
  expect_equal(c(ncol(d$proj), ncol(d$y), ncol(d$L)), c(1L, 0L, 0L))
  w <- lab_info(S, 6, "waiver")
  expect_equal(c(ncol(w$proj), ncol(w$base), ncol(w$y), ncol(w$L), ncol(w$has_row)), c(5L, 5L, 5L, 5L, 5L))
  l <- lab_info(S, 6, "lineup")
  expect_equal(c(ncol(l$proj), ncol(l$base), ncol(l$y), ncol(l$active), ncol(l$has_row)), c(6L, 6L, 5L, 5L, 5L))
  expect_error(lab_lineup_policy("raw")(list(roster = 1:15), w))       # a lineup policy refuses waiver-time info
})

test_that("the lineup is optimal for the slot structure (brute force)", {
  set.seed(3)
  for (rep in 1:20) {
    pos <- sample(c("QB", "QB", "RB", "RB", "RB", "RB", "WR", "WR", "WR", "WR", "WR", "TE", "TE", "RB", "WR"))
    v <- round(stats::runif(15, 0, 20), 1)
    v[sample(15, 2)] <- -Inf
    best <- -Inf
    ok <- which(is.finite(v))
    for (k in 1:8) {
      cmb <- utils::combn(ok, k)
      for (c in seq_len(ncol(cmb))) {
        s <- cmb[, c]
        if (lab_feasible(pos[s])) best <- max(best, sum(v[s]))
      }
    }
    expect_equal(lab_lineup_value(v, pos), best)
  }
})

test_that("the draft fills legal rosters deterministically", {
  S <- lab_toy_S()
  r1 <- lab_draft(S, 8L, seed = 42L)
  r2 <- lab_draft(S, 8L, seed = 42L)
  expect_identical(r1, r2)
  expect_true(all(lengths(r1) == LAB_ROSTER))
  expect_false(any(duplicated(unlist(r1))))
  for (r in r1) {
    n <- table(factor(S$pos[r], LAB_POSITIONS))
    expect_true(all(n <= LAB_CAPS[names(n)]))
    expect_equal(lab_open_needs(n), 0)
  }
  expect_false(identical(r1, lab_draft(S, 8L, seed = 43L)))
})

test_that("draft values use last season's mean projection (>= 4 weeks), else the week-1 projection", {
  fr <- tibble::tibble(season = 2021L, gsis_id = rep(c("a", "b"), c(5, 3)), espn_proj = c(10, 12, 8, 10, 0, 6, 6, 6))
  v <- lab_draft_values(fr, 2022L, ids = c("a", "b", "c", "d"), week1 = c(3, 4, 7, 0))
  expect_equal(v, c(10, 4, 7, NA))                              # a: mean of 4 positive weeks; b: only 3 weeks
})

test_that("the schedule is a round robin", {
  for (n in c(8L, 10L, 12L)) {
    s <- lab_schedule(n, seed = 7L)
    expect_equal(dim(s), c(n, 14L))
    for (w in 1:14) {
      expect_true(all(s[cbind(s[, w], w)] == seq_len(n)))
      expect_false(any(s[, w] == seq_len(n)))
    }
    expect_true(all(apply(s[, 1:(n - 1)], 1, function(x) length(unique(x)) == n - 1)))
  }
})

test_that("claims are contested in priority order and the claimant moves to the back", {
  pos <- c(rep("QB", 2), rep("RB", 4), rep("WR", 4), rep("TE", 2), "WR", "WR")   # players 13, 14 are free agents
  rosters <- list(c(1, 3, 4, 7, 8, 11), c(2, 5, 6, 9, 10, 12))
  lists <- list(tibble::tibble(add = c(13L, 14L), drop = c(7L, 8L), gain = c(9, 4)),
                tibble::tibble(add = c(13L, 14L), drop = c(9L, 10L), gain = c(8, 6)))
  res <- lab_resolve_claims(lists, rosters, prio = c(2L, 1L), pos)
  expect_equal(res$log$team, c(2L, 1L))                         # team 2 has priority and takes player 13
  expect_equal(res$log$add, c(13L, 14L))                        # team 1 falls back to 14; team 2 is at the back
  expect_setequal(res$rosters[[2]], c(2, 5, 6, 10, 12, 13))
  expect_setequal(res$rosters[[1]], c(1, 3, 4, 7, 11, 14))
  # an illegal result (no TE left) is skipped
  bad <- list(tibble::tibble(add = 13L, drop = 11L, gain = 5), tibble::tibble(add = integer(), drop = integer(), gain = double()))
  expect_equal(nrow(lab_resolve_claims(bad, rosters, 1:2, pos)$log), 0)
})

test_that("claims replace the weakest relevant starter and respect the minimum gain", {
  pos <- c("QB", "RB", "RB", "WR", "WR", "TE", "RB", "WR", "QB", "WR")
  v <- c(18, 12, 10, 11, 9, 7, 3, 2, 10, 14)                   # players 9 (QB) and 10 (WR) are free agents
  cl <- lab_claims(v, pos, roster = 1:8, free_agents = 9:10, n_weeks = 10)
  expect_equal(nrow(cl), 1)                                     # a backup QB adds nothing to the lineup
  expect_equal(c(cl$add, cl$drop), c(10L, 8L))                 # WR 14 starts; the lowest WR (2) leaves: lineup 72 -> 84
  expect_equal(cl$gain, (84 - 72) * 10)
  expect_equal(nrow(lab_claims(v, pos, 1:8, 9:10, n_weeks = 10, min_gain = 200)), 0)
})

test_that("the waiver calibration recovers a linear relation on future points", {
  x <- lab_toy_frame(seed = 5)
  x$frame$actual <- 1 + 0.8 * x$frame$espn_proj                # points are a known function of the projection
  cal <- lab_waiver_calibration(x$frame, x$team_games, 2021L)
  expect_equal(nrow(cal), 4)
  expect_true(all(abs(cal$b - 0.8) < 0.15))
})

test_that("planted future data never changes a decision made before it (end-to-end firewall)", {
  S <- lab_toy_S(seed = 2)
  setup <- lab_setup(S, 8L, 1L, seed = 99L)
  ref <- lab_run_league(S, setup, "D", lab_toy_calib(), shadow = TRUE)
  t0 <- 7L
  bad <- S
  later <- seq(t0 + 1, length(S$weeks))
  bad$proj[, later] <- 99
  bad$base[, later] <- 99
  bad$L[, t0:length(S$weeks)] <- 99
  bad$y[, t0:length(S$weeks)] <- 1e4 * stats::runif(length(bad$y[, t0:length(S$weeks)]))
  bad$active[, t0:length(S$weeks)] <- FALSE
  got <- lab_run_league(bad, setup, "D", lab_toy_calib(), shadow = TRUE)
  keep <- function(x, k) if (is.null(x)) NULL else x[x$week <= k, ]
  expect_identical(keep(ref$team_weeks, t0)$lineup, keep(got$team_weeks, t0)$lineup)
  expect_identical(keep(ref$team_weeks, t0)$lineup_cal, keep(got$team_weeks, t0)$lineup_cal)
  expect_identical(keep(ref$claims, t0), keep(got$claims, t0))
  expect_identical(keep(ref$waiver_triage, t0), keep(got$waiver_triage, t0))
  # the planted data do change realised scores, and later decisions may change
  expect_false(identical(ref$team_weeks$points[ref$team_weeks$week == t0], got$team_weeks$points[got$team_weeks$week == t0]))
})

test_that("a league replays identically for identical seeds, and the arms share the league", {
  S <- lab_toy_S(seed = 4)
  setup <- lab_setup(S, 8L, 2L, seed = 7L)
  a1 <- lab_run_league(S, setup, "A", lab_toy_calib(), shadow = TRUE)
  a2 <- lab_run_league(S, setup, "A", lab_toy_calib(), shadow = TRUE)
  expect_identical(a1, a2)
  b <- lab_run_league(S, setup, "B", lab_toy_calib())
  expect_identical(a1$team_weeks$roster[a1$team_weeks$week == 1], b$team_weeks$roster[b$team_weeks$week == 1])
  expect_equal(sum(a1$standings$playoffs), 4)
  expect_equal(sum(a1$standings$title), 1)
  expect_true(all(a1$team_weeks$hindsight >= a1$team_weeks$points - 1e-9))
  # non-focal teams use the raw lineup, which equals their shadow raw lineup
  nf <- a1$team_weeks[!a1$team_weeks$focal, ]
  expect_identical(nf$lineup, nf$lineup_raw)
})

test_that("the X9 team-week triage is a valid probability comparison", {
  S <- lab_toy_S(seed = 6)
  setup <- lab_setup(S, 8L, 1L, seed = 11L)
  info <- lab_info(S, 3L, "lineup")
  tab <- read_pod_table(file.path(project_root, POD_TABLE_FILE))
  at <- tidyr::expand_grid(position = LAB_POSITIONS, band = 1:7) |>
    dplyr::mutate(rows = 100L, active_share = ifelse(.data$band >= 3, 0.98, 0.6))
  out <- lab_x9_team_week(info, setup$rosters[[1]], setup$rosters[[2]], tab, at, sims = 400L, seed = 1L)
  expect_true(out$p_win_ev >= 0 && out$p_win_ev <= 1)
  expect_true(out$delta_best >= 0)
  expect_identical(out, lab_x9_team_week(info, setup$rosters[[1]], setup$rosters[[2]], tab, at, sims = 400L, seed = 1L))
})

test_that("P(active) comes from the position x base-band table, with the position share as fallback", {
  at <- tibble::tibble(position = c("QB", "QB", "RB"), band = c(1L, 7L, 4L), rows = c(300L, 100L, 50L),
                       active_share = c(0.4, 0.99, 0.95))
  p <- lab_p_active(c("QB", "QB", "QB", "RB"), c(1, 25, 10, 10), at)
  expect_equal(p, c(0.4, 0.99, (0.4 * 300 + 0.99 * 100) / 400, 0.95))
})

test_that("replays refuse seasons outside the decision family's development set", {
  reg <- read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))
  x <- lab_toy_frame()
  expect_error(lab_replay_season(x$frame, x$team_games, 2024L, leagues = 1L, register = reg), "may not use")
  expect_error(lab_replay_season(x$frame, x$team_games, 2025L, leagues = 1L, register = reg), "may not use")
  expect_error(lab_replay_season(x$frame, x$team_games, 2026L, leagues = 1L, register = reg), "may not use|sealed")
})

test_that("the QB streaming policy claims a clearly better free-agent QB first and keeps the roster legal", {
  S <- lab_toy_S(seed = 8)
  setup <- lab_setup(S, 8L, 1L, seed = 21L)
  calib <- lab_toy_calib()
  info <- lab_info(S, 6L, "waiver")
  r <- setup$rosters[[1]]
  fa <- setdiff(which(rowSums(info$has_row) > 0), unlist(setup$rosters))
  pol <- lab_stream_policy(calib, min_gain = 1)
  cl <- pol(list(team = 1L, roster = r, free_agents = fa), info)
  k <- match(info$pos, calib$position)
  v <- calib$a[k] + calib$b[k] * info$L[, 5]
  plays <- info$plays[cbind(match(info$team_asof[, 5], info$teams), 6)]
  nv <- ifelse(!is.na(plays) & plays, v, 0)
  qb_fa <- fa[info$pos[fa] == "QB" & !is.na(v[fa])]
  qbs <- r[info$pos[r] == "QB"]
  gain <- max(nv[qb_fa]) - max(dplyr::coalesce(nv[qbs], 0))
  if (gain > 1) {
    expect_equal(cl$add[1], qb_fa[which.max(nv[qb_fa])])
    expect_true(cl$drop[1] %in% qbs)
  } else {
    expect_false(any(info$pos[cl$add] == "QB" & cl$gain == gain))
  }
  expect_lte(nrow(cl), 2)
  strict <- lab_stream_policy(calib, min_gain = 1e6)(list(team = 1L, roster = r, free_agents = fa), info)
  expect_identical(strict, lab_waiver_policy("calibrated", calib)(list(team = 1L, roster = r, free_agents = fa), info))
})

test_that("the X16 estimate pairs arms C and E within league-weeks and counts the focal team's claims", {
  x <- lab_toy_frame(seed = 3)
  S <- lab_season_data(x$frame, x$team_games, 2021L)
  setup <- lab_setup(S, 8L, 1L, seed = 5L)
  runs <- lapply(c("C", "E"), function(a) lab_run_league(S, setup, a, lab_toy_calib()))
  pick <- function(el) purrr::list_rbind(purrr::compact(purrr::map(runs, el)))
  rp <- list(season = 2021L, team_weeks = pick("team_weeks"), standings = pick("standings"), claims = pick("claims"))
  reg <- read_contamination_register(file.path(project_root, "research", "contamination_register.yml"))
  out <- lab_stream_result(list(rp), x$frame, x$team_games, reps = 50L, register = reg)
  tw <- rp$team_weeks[rp$team_weeks$focal & rp$team_weeks$week %in% LAB_REG_WEEKS, ]
  expect_equal(out$n, length(LAB_REG_WEEKS))
  expect_equal(out$mean, mean(tw$points[tw$arm == "E"] - tw$points[tw$arm == "C"]))
  expect_true(out$ci[1] <= out$mean + 1e-9 || out$ci[2] >= out$mean - 1e-9)
  cl <- rp$claims[rp$claims$team == setup$focal, ]
  expect_equal(out$claims$claims, c(sum(cl$arm == "C"), sum(cl$arm == "E")))
  expect_equal(out$claims$qb_claims, c(sum(cl$arm == "C" & S$pos[cl$add] == "QB"), sum(cl$arm == "E" & S$pos[cl$add] == "QB")))
  expect_error(lab_stream_result(list(utils::modifyList(rp, list(season = 2024L))), x$frame, x$team_games, reps = 10L, register = reg),
               "may not use")
})

test_that("planted future data never change a streaming decision made before it", {
  S <- lab_toy_S(seed = 2)
  setup <- lab_setup(S, 8L, 1L, seed = 99L)
  ref <- lab_run_league(S, setup, "E", lab_toy_calib())
  t0 <- 7L
  bad <- S
  later <- seq(t0 + 1, length(S$weeks))
  bad$proj[, later] <- 99
  bad$base[, later] <- 99
  bad$L[, t0:length(S$weeks)] <- 99
  bad$y[, t0:length(S$weeks)] <- 1e4 * stats::runif(length(bad$y[, t0:length(S$weeks)]))
  got <- lab_run_league(bad, setup, "E", lab_toy_calib())
  keep <- function(x, k) if (is.null(x)) NULL else x[x$week <= k, ]
  expect_identical(keep(ref$team_weeks, t0)$lineup, keep(got$team_weeks, t0)$lineup)
  expect_identical(keep(ref$claims, t0), keep(got$claims, t0))
})
