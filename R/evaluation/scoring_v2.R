# Proper scoring and calibration tools (master plan F2-lite) ------------------------------------
# Base R only (no new packages; renv.lock unchanged). For distributional forecasts given as
# quantile sets, as the POD tables are (05 section 3):
#   CRPS        - pinball (quantile-score) approximation: CRPS = 2 * integral_0^1 QS_tau(q_tau, y) dtau,
#                 integrated over the tau grid with the trapezoid rule; the uncovered tails
#                 (below the lowest and above the highest tau) are added with the end quantiles.
#                 Exact in the limit of a dense grid; tested against the analytic normal CRPS.
#   PIT         - randomised PIT (Czado et al. 2009), so a point mass (e.g. 0 for inactive players)
#                 still gives a uniform PIT under calibration.
#   intervals   - empirical coverage and the interval score (Gneiting & Raftery 2007).
#   probability - Brier score; binned reliability table; CORP decomposition with isotonic
#                 recalibration via stats::isoreg (Dimitriadis et al. 2021): BS = MCB - DSC + UNC.

#' Quantile (pinball) score of quantile forecasts q at level tau for outcomes y.
quantile_score <- function(q, y, tau) (as.numeric(y < q) - tau) * (q - y)

#' CRPS of quantile-set forecasts. `q` is an n x K matrix (or a length-K vector for one forecast) of
#' quantiles at increasing levels `tau` (length K, in (0, 1)); `y` has length n.
crps_quantiles <- function(q, y, tau) {
  q <- if (is.matrix(q)) q else matrix(q, nrow = 1)
  stopifnot(ncol(q) == length(tau), nrow(q) == length(y), !is.unsorted(tau), all(tau > 0 & tau < 1))
  qs <- vapply(seq_along(tau), function(k) quantile_score(q[, k], y, tau[k]), numeric(length(y)))
  qs <- matrix(qs, nrow = length(y))
  K <- length(tau)
  w <- numeric(K)                               # trapezoid weights over the tau grid
  if (K > 1) {
    d <- diff(tau)
    w[-K] <- w[-K] + d / 2
    w[-1] <- w[-1] + d / 2
  }
  w[1] <- w[1] + tau[1]                         # lower tail [0, tau_1] scored with q_1
  w[K] <- w[K] + (1 - tau[K])                   # upper tail [tau_K, 1] scored with q_K
  2 * drop(qs %*% w)
}

#' Analytic CRPS of a normal forecast (reference for tests and for normal baselines).
crps_normal <- function(y, mu, sigma) {
  z <- (y - mu) / sigma
  sigma * (z * (2 * stats::pnorm(z) - 1) + 2 * stats::dnorm(z) - 1 / sqrt(pi))
}

#' Predictive CDF of a quantile set, linear between quantiles, at y (and just below y). Outside
#' the quantile range the CDF is linear toward 0 or 1 over the same spacing as the end quantiles,
#' clamped to [0, 1]. Returns list(F = F(y), F_minus = F(y-)).
cdf_from_quantiles <- function(y, q, tau) {
  q <- if (is.matrix(q)) q else matrix(q, nrow = 1)
  K <- length(tau)
  f1 <- function(i, yi) {
    qi <- q[i, ]
    if (yi < qi[1]) {
      span <- max(qi[min(2, K)] - qi[1], 1e-9)
      return(max(0, tau[1] - (qi[1] - yi) / span * (tau[min(2, K)] - tau[1])))
    }
    if (yi > qi[K]) {
      span <- max(qi[K] - qi[max(1, K - 1)], 1e-9)
      return(min(1, tau[K] + (yi - qi[K]) / span * (tau[K] - tau[max(1, K - 1)])))
    }
    # ties among quantiles (a flat stretch, e.g. many quantiles at 0) give a jump: take the top
    hi <- max(which(qi <= yi))
    if (hi == K) return(tau[K])
    if (qi[hi + 1] == qi[hi]) return(tau[hi])
    tau[hi] + (yi - qi[hi]) / (qi[hi + 1] - qi[hi]) * (tau[hi + 1] - tau[hi])
  }
  # Tied quantiles q_lo = ... = q_hi = c make the CDF jump at c from tau_lo to tau_hi: F(c-) = tau_lo.
  fm <- function(i, yi) {
    at <- which(q[i, ] == yi)
    if (length(at)) tau[min(at)] else f1(i, yi)
  }
  list(F = vapply(seq_along(y), function(i) f1(i, y[i]), 0),
       F_minus = vapply(seq_along(y), function(i) fm(i, y[i]), 0))
}

#' Randomised PIT values: F(y-) + U * (F(y) - F(y-)), uniform under calibration even with atoms.
pit_randomised <- function(F, F_minus, u = stats::runif(length(F))) {
  F_minus + u * pmax(F - F_minus, 0)
}

#' Predictive CDF of a POD: P(active) * F_active + (1 - P(active)) * point mass at 0.
pod_cdf <- function(y, q_active, tau, p_active) {
  a <- cdf_from_quantiles(y, q_active, tau)
  list(F = (1 - p_active) * (y >= 0) + p_active * a$F,
       F_minus = (1 - p_active) * (y > 0) + p_active * a$F_minus)
}

#' Empirical coverage of central intervals.
interval_coverage <- function(y, lower, upper) mean(y >= lower & y <= upper)

#' Interval score of central (1 - alpha) intervals (lower is better).
interval_score <- function(y, lower, upper, alpha) {
  (upper - lower) + (2 / alpha) * (lower - y) * (y < lower) + (2 / alpha) * (y - upper) * (y > upper)
}

#' Brier score of probabilities p for binary outcomes o (0/1).
brier_score <- function(p, o) mean((p - o)^2)

#' Binned reliability table: mean forecast vs observed frequency per bin, with counts and a Wilson
#' 95% interval for the observed frequency.
reliability_table <- function(p, o, bins = 10) {
  br <- seq(0, 1, length.out = bins + 1)
  b <- cut(p, br, include.lowest = TRUE)
  d <- data.frame(b = b, p = p, o = o)
  out <- do.call(rbind, lapply(split(d, d$b, drop = TRUE), function(x) {
    n <- nrow(x); k <- sum(x$o); z <- 1.959964
    ph <- k / n
    centre <- (ph + z^2 / (2 * n)) / (1 + z^2 / n)
    half <- z * sqrt(ph * (1 - ph) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
    data.frame(bin = as.character(x$b[1]), n = n, mean_forecast = mean(x$p), observed = ph,
               lower = centre - half, upper = centre + half)
  }))
  rownames(out) <- NULL
  out
}

#' CORP decomposition of the Brier score (isotonic recalibration): BS = MCB - DSC + UNC.
brier_decomposition <- function(p, o) {
  ord <- order(p)
  iso <- stats::isoreg(p[ord], o[ord])
  cal <- numeric(length(p))
  cal[ord] <- iso$yf
  bs <- mean((p - o)^2)
  bs_cal <- mean((cal - o)^2)
  unc <- mean((mean(o) - o)^2)
  list(brier = bs, mcb = bs - bs_cal, dsc = unc - bs_cal, unc = unc)
}
