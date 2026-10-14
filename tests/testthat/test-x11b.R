# X11b (VL12a) design-study helpers. Synthetic indicators only.

x11b_toy <- function(p = c(0.5, 0.52, 0.60, 0.51), S = 20000L, seed = 3, common = TRUE) {
  withr::with_seed(seed, {
    u <- stats::runif(S)                                                  # common random numbers across configurations
    t(vapply(p, function(q) as.numeric((if (common) u else stats::runif(S)) < q), numeric(S)))
  })
}

test_that("gains are paired against the base row; a clear best is found by every design at zero regret", {
  ind <- x11b_toy()
  g <- x11b_gains(ind)
  expect_equal(dim(g), c(3L, 20000L))
  expect_true(all(g >= 0))                                                  # nested thresholds: gains never negative
  e <- x11b_evaluate(ind)
  expect_equal(e$candidates, 3L)
  expect_equal(c(e$d0_regret, e$d1_10k_regret, e$d2_regret), c(0, 0, 0))
  expect_true(e$d2_agree)
  expect_lt(e$d2_cost, 3 * 10000)                                           # racing stops early
  expect_equal(e$d0_cost, 3 * 2000)
  expect_equal(e$d3_covers, 1)
  expect_false(e$near_tie)
})

test_that("near-equal candidates are flagged as near-ties and kept together in the indifference set", {
  ind <- x11b_toy(p = c(0.5, 0.551, 0.55, 0.40), common = FALSE)   # noisy, as without CRN
  e <- x11b_evaluate(ind)
  expect_true(e$near_tie)
  expect_gte(e$d3_size, 2)
  expect_lt(e$d0_regret, 0.005)
})
