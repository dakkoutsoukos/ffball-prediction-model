# S0 level-shock scale by simulation matching (master plan S0; pre-registration VL3) -------------
# Rest-of-season (ROS) totals vary more than independent weekly noise and availability explain:
# a player's whole-season level is uncertain. S0 models it as L ~ lognormal(-s^2/2, s^2) (mean 1),
# constant over the season. s (sigma_L) is chosen per position so that S0's own simulated ROS
# residual SD equals the observed one on development seasons 2019-2023 (val_frame$future rows,
# as-of weeks 5-11, frozen ROS forecasts). Availability and weekly noise are drawn separately, so
# attrition is not double-counted. No 2024-2026 outcome is used.

SIGMA_MATCH_SEASONS <- 2019:2023
SIGMA_MATCH_WEEKS <- 5:11

#' Draw points from quantile rows by inverse-CDF interpolation on the tau grid (tails held at the
#' end quantiles). `q` is n x K; `u` has length n.
sim_qdraw <- function(q, u, tau = POD_TAU) {
  K <- length(tau)
  k <- findInterval(u, tau)
  out <- numeric(length(u))
  lo <- k == 0
  hi <- k >= K
  mid <- !lo & !hi
  out[lo] <- q[cbind(which(lo), 1)]
  out[hi] <- q[cbind(which(hi), K)]
  if (any(mid)) {
    i <- which(mid)
    kk <- k[mid]
    w <- (u[mid] - tau[kk]) / (tau[kk + 1] - tau[kk])
    out[mid] <- q[cbind(i, kk)] + w * (q[cbind(i, kk + 1)] - q[cbind(i, kk)])
  }
  out
}

#' Development rows for the matching: frozen ROS forecasts (E, A, lvl) per (player, season, w, t).
sim_match_rows <- function(future, ros_params, seasons = SIGMA_MATCH_SEASONS, weeks = SIGMA_MATCH_WEEKS,
                           register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", setdiff(seasons, POD_WARMUP), "development", register)
  rows <- dplyr::filter(future, .data$season %in% !!seasons, .data$w %in% !!weeks)
  pred <- val_apply_ros(dplyr::mutate(rows, L = .data[[ros_params$level]]), ros_params$cd_tab, "L", ros_params$form)
  pred |>
    dplyr::mutate(group = paste(.data$gsis_id, .data$season, .data$w, sep = "_")) |>
    dplyr::select("group", "season", "w", "t", "gsis_id", "position", "E", "A", "lvl", "pts")
}

#' Pre-draw B[g, b] = sum over the group's weeks of active x F^-1(u | position, lvl), for b = 1..draws
#' (availability and P0 noise; common random numbers), plus the forecast total per group.
sim_match_prepare <- function(rows, table, draws = 200, seed = 20261013, noise_scale = 1) {
  q <- pd_quantiles(rows$position, rows$lvl, table)
  if (noise_scale != 1) q <- rows$lvl + noise_scale * (q - rows$lvl)
  gid <- match(rows$group, unique(rows$group))
  G <- max(gid)
  B <- matrix(0, G, draws)
  withr::with_seed(seed, {
    for (b in seq_len(draws)) {
      act <- stats::runif(nrow(rows)) < rows$A
      x <- ifelse(act, sim_qdraw(q, stats::runif(nrow(rows))), 0)
      B[, b] <- rowsum(x, gid, reorder = TRUE)[, 1]
    }
    Z <- matrix(stats::rnorm(G * draws), G, draws)
  })
  grp <- rows |>
    dplyr::summarise(forecast = sum(.data$E), actual = sum(.data$pts), position = dplyr::first(.data$position),
                     w = dplyr::first(.data$w), .by = "group")
  grp <- grp[match(unique(rows$group), grp$group), ]
  list(B = B, Z = Z, groups = grp)
}

#' Simulated residual SD for a level-shock scale s (pooled over groups and draws).
sim_match_sd <- function(prep, s, idx = seq_len(nrow(prep$groups))) {
  L <- exp(-s^2 / 2 + s * prep$Z[idx, , drop = FALSE])
  R <- L * prep$B[idx, , drop = FALSE] - prep$groups$forecast[idx]
  stats::sd(as.vector(R))
}

#' sigma_L per position: bisection on [0, upper] so that simulated SD = observed SD.
sim_match_sigma <- function(prep, upper = 1.5, tol = 1e-4) {
  purrr::map(intersect(POD_POSITIONS, unique(prep$groups$position)), function(p) {
    idx <- which(prep$groups$position == p)
    obs <- stats::sd(prep$groups$actual[idx] - prep$groups$forecast[idx])
    f <- function(s) sim_match_sd(prep, s, idx) - obs
    s <- if (f(0) >= 0) 0 else if (f(upper) < 0) upper else stats::uniroot(f, c(0, upper), tol = tol)$root
    sim_mean <- mean(exp(-s^2 / 2 + s * prep$Z[idx, ]) * prep$B[idx, ]) - mean(prep$groups$forecast[idx])
    tibble::tibble(position = p, groups = length(idx), sd_observed = obs, sd_sim_at_0 = sim_match_sd(prep, 0, idx),
                   sigma_L = s, capped = s >= upper, sd_sim_matched = sim_match_sd(prep, s, idx),
                   mean_bias_sim = sim_mean, mean_bias_observed = mean(prep$groups$actual[idx] - prep$groups$forecast[idx]))
  }) |>
    purrr::list_rbind()
}

S0_PARAMS_FILE <- "models/simulation/s0_params_v0.yml"

#' Frozen S0 parameters as a plain list (sigma_L by position, rounded; provenance).
sim_params_list <- function(sigma) {
  list(version = "s0_params_v0", pre_registration = "VL3", seasons = SIGMA_MATCH_SEASONS, asof_weeks = SIGMA_MATCH_WEEKS,
       pod_table = "pod_baseline_v0", ros_params = "ros_v1", draws = 200L, seed = 20261013L,
       sigma_L = as.list(stats::setNames(round(sigma$sigma_L, 4), sigma$position)),
       sd_observed = as.list(stats::setNames(round(sigma$sd_observed, 3), sigma$position)))
}

#' Write a frozen YAML once, with LF line endings and a comment header (decisions X-013).
write_frozen_yaml <- function(x, path, header) {
  if (file.exists(path)) cli::cli_abort("{.file {path}} is frozen and already exists.")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, "wb")
  on.exit(close(con))
  writeLines(c(paste("#", header), strsplit(yaml::as.yaml(x), "\n", fixed = TRUE)[[1]]), con, sep = "\n")
  invisible(path)
}

read_s0_params <- function(path = S0_PARAMS_FILE) {
  p <- yaml::read_yaml(path)
  p$sigma_L <- unlist(p$sigma_L)
  p
}

#' Observed vs matched SD by as-of week (descriptive).
sim_match_by_week <- function(prep, sigma) {
  purrr::map(seq_len(nrow(sigma)), function(i) {
    p <- sigma$position[i]
    purrr::map(sort(unique(prep$groups$w)), function(w) {
      idx <- which(prep$groups$position == p & prep$groups$w == w)
      tibble::tibble(position = p, w = w, groups = length(idx),
                     sd_observed = stats::sd(prep$groups$actual[idx] - prep$groups$forecast[idx]),
                     sd_matched = sim_match_sd(prep, sigma$sigma_L[i], idx))
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}
