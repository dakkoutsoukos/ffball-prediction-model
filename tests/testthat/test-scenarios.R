# P5 scenario engine v1. Synthetic data only.

scn_toy_weekly <- function(n = 40, weeks = 1:4, seed = 1) {
  set.seed(seed)
  tidyr::expand_grid(player = sprintf("p%03d", seq_len(n)), week = weeks) |>
    dplyr::mutate(position = rep(rep(c("QB", "RB", "WR", "TE"), length.out = n), each = length(weeks)),
                  base = stats::runif(dplyr::n(), 2, 22), p_active = stats::runif(dplyr::n(), 0.85, 1))
}

scn_toy_q <- function(position, base) outer(base, stats::qnorm(POD_TAU) * 5, `+`)

test_that("quantile draws match sim_qdraw without replicating rows", {
  q <- scn_toy_q(rep("WR", 3), c(5, 10, 15))
  set.seed(1)
  ri <- sample(1:3, 50, TRUE)
  u <- stats::runif(50)
  expect_equal(scn_qdraw(q, ri, u, POD_TAU), sim_qdraw(q[ri, ], u, POD_TAU))
})

test_that("draws are deterministic, and adding a player leaves everyone else's draws unchanged", {
  w <- scn_toy_weekly()
  s1 <- scn_spec(w, scn_toy_q, sigma_L = function(p, b) rep(0.3, length(p)), sims = 300L, chunk = 150L)
  a <- scn_chunk(s1, 1L)
  expect_identical(a, scn_chunk(s1, 1L))
  b2 <- scn_chunk(s1, 2L)
  expect_false(isTRUE(all.equal(a$points[, 1:10], b2$points[, 1:10])))
  extra <- dplyr::bind_rows(w, tibble::tibble(player = "zzz", week = 1:4, position = "RB", base = 9, p_active = 0.9))
  s2 <- scn_spec(extra, scn_toy_q, sigma_L = function(p, b) rep(0.3, length(p)), sims = 300L, chunk = 150L)
  c1 <- scn_chunk(s2, 1L)
  keep <- s2$weekly$player != "zzz"
  expect_identical(c1$points[keep, ], a$points)
})

test_that("means are preserved: E[points] = p_active x E[F^-1] (the level shock has mean 1)", {
  w <- scn_toy_weekly(n = 8, weeks = 1)
  spec <- scn_spec(w, scn_toy_q, sigma_L = function(p, b) rep(0.4, length(p)), sims = 20000L, chunk = 5000L)
  m <- Reduce(`+`, scn_map(spec, function(ch) rowSums(ch$points))) / spec$sims
  tw <- c(diff(c(0, POD_TAU)) / 2 + diff(c(POD_TAU, 1)) / 2)
  expected <- spec$weekly$p_active * drop(spec$q %*% (tw / sum(tw)))
  expect_true(all(abs(m - expected) / expected < 0.03))
})

test_that("decision-time lineups use known availability and forecasts, and score realised points", {
  w <- scn_toy_weekly(n = 24, weeks = 1:2, seed = 3)
  spec <- scn_spec(w, scn_toy_q, sigma_L = function(p, b) rep(0.3, length(p)), sims = 50L, chunk = 50L)
  ch <- scn_chunk(spec, 1L)
  rosters <- list(A = sprintf("p%03d", 1:12), B = sprintf("p%03d", 13:24))
  sc <- scn_team_scores(spec, ch, rosters)
  expect_equal(dim(sc), c(2L, 2L, 50L))
  # reference: lab_lineup on decision values for team A, week 1, a few sims
  rows <- which(spec$weekly$player %in% rosters$A & spec$weekly$week == 1)
  for (s in 1:5) {
    dec <- ifelse(ch$active[rows, s], spec$weekly$base[rows], -Inf)
    pick <- lab_lineup(dec, spec$weekly$position[rows])
    pick <- pick[dec[pick] > 0]
    expect_equal(sc["A", "1", s], sum(ch$points[rows[pick], s]))
  }
  # hindsight lineups (on realised points) are never worse, and better on average
  hind <- vapply(1:50, function(s) {
    v <- ifelse(ch$active[rows, s], ch$points[rows, s], -Inf)
    sum(v[lab_lineup(v, spec$weekly$position[rows])])
  }, 0)
  expect_true(all(hind >= sc["A", "1", ] - 1e-9))
  expect_gt(mean(hind - sc["A", "1", ]), 0)
})
