# P0: baseline weekly outcome distributions (master plan P0; pre-registration E18) ---------------
# F(y | active, base): empirical quantiles of (actual - base) on ACTIVE player-weeks (at least one
# offensive snap), by position x fixed band of the base. The base is a rolling-origin per-position
# linear calibration of ESPN's final week-of projection (historical ESPN values are late-horizon).
# Production table: development seasons 2020-2023 only (2019 = calibration warm-up). Nothing here
# reads 2024-2026 outcomes: the frame refuses other seasons (contamination register).
# Prospective PODs: POD_h = p_h * F(y | active, base_h) + (1 - p_h) * point mass at 0.

POD_TAU <- c(0.01, 0.05, 0.10, 0.20, 0.25, 0.30, 0.40, 0.50, 0.60, 0.70, 0.75, 0.80, 0.90, 0.95, 0.99)
POD_BANDS <- c(3, 6, 9, 12, 15, 20)            # upper edges; the last band is 20+
POD_MIN_CELL <- 200L
POD_TABLE_FILE <- "models/probabilistic/pod_baseline_v0.yml"
POD_POSITIONS <- c("QB", "RB", "WR", "TE")
POD_DEV_SEASONS <- 2020:2023
POD_WARMUP <- 2019L

#' Development frame: projected QB/RB/WR/TE player-weeks with an active flag (at least one
#' offensive snap; a stat line counts where no snap record exists) and points y.
pd_frame <- function(current, snaps, seasons = c(POD_WARMUP, POD_DEV_SEASONS), register = read_contamination_register()) {
  assert_family_seasons("distribution_stack", setdiff(seasons, POD_WARMUP), "development", register)
  if (POD_WARMUP %in% seasons) assert_family_seasons("distribution_stack", POD_WARMUP, "warmup", register)
  sn <- snaps |>
    dplyr::filter(.data$season %in% !!seasons) |>
    dplyr::summarise(offense_snaps = sum(.data$offense_snaps, na.rm = TRUE), .by = c("season", "week", "gsis_id"))
  current |>
    dplyr::filter(.data$season %in% !!seasons, .data$position %in% POD_POSITIONS, .data$espn_proj > 0) |>
    dplyr::left_join(sn, by = c("season", "week", "gsis_id")) |>
    dplyr::mutate(stat_line = .data$active,
                  active = dplyr::if_else(is.na(.data$offense_snaps), .data$stat_line, .data$offense_snaps >= 1),
                  y = .data$pts) |>
    dplyr::select("season", "week", "gsis_id", "position", "espn_proj", "y", "active", "offense_snaps", "stat_line") |>
    dplyr::arrange(.data$position, .data$season, .data$week, .data$gsis_id)
}

#' Rolling-origin per-position linear calibration: for each week, OLS of y on ESPN over the
#' position's active rows strictly before that week (expanding from the first season). Base = ESPN
#' while fewer than `min_rows` training rows exist. Closed form from cumulative sums.
pd_rolling_base <- function(frame, min_rows = POD_MIN_CELL) {
  frame$gi <- frame$season * 100L + frame$week
  out <- lapply(split(frame, frame$position), function(d) {
    act <- d[d$active, ]
    wk <- act |>
      dplyr::summarise(n = dplyr::n(), sx = sum(.data$espn_proj), sy = sum(.data$y),
                       sxx = sum(.data$espn_proj^2), sxy = sum(.data$espn_proj * .data$y), .by = "gi") |>
      dplyr::arrange(.data$gi)
    cum <- dplyr::mutate(wk, dplyr::across(c("n", "sx", "sy", "sxx", "sxy"), cumsum))
    # coefficients available for week g use every week strictly before g
    gis <- sort(unique(d$gi))
    coef <- t(vapply(gis, function(g) {
      k <- which(cum$gi < g)
      if (!length(k) || cum$n[max(k)] < min_rows) return(c(a = 0, b = 1, n = if (length(k)) cum$n[max(k)] else 0))
      c_ <- cum[max(k), ]
      den <- c_$n * c_$sxx - c_$sx^2
      b <- (c_$n * c_$sxy - c_$sx * c_$sy) / den
      c(a = (c_$sy - b * c_$sx) / c_$n, b = b, n = c_$n)
    }, numeric(3)))
    cf <- tibble::tibble(gi = gis, a = coef[, "a"], b = coef[, "b"], n_train = coef[, "n"])
    d |>
      dplyr::left_join(cf, by = "gi") |>
      dplyr::mutate(base = .data$a + .data$b * .data$espn_proj, resid = .data$y - .data$base)
  })
  dplyr::bind_rows(out) |> dplyr::select(-"gi")
}

#' Fixed band index of a base value (1 = below 3, ..., 7 = 20+). Negative bases fall in band 1.
pd_band <- function(base) findInterval(base, POD_BANDS) + 1L

pod_band_label <- function(lo, hi) {
  edges <- c(0, POD_BANDS, Inf)
  paste0(edges[lo], "-", ifelse(is.infinite(edges[hi + 1]), "inf", edges[hi + 1]))
}

#' Residual quantile table from active rows: per position, bands merged until every group has at
#' least `min_cell` rows (a small band merges with its lower neighbour; the lowest with the next).
pd_residual_table <- function(rows, tau = POD_TAU, min_cell = POD_MIN_CELL) {
  rows <- rows[rows$active, ]
  rows$band <- pd_band(rows$base)
  purrr::map(POD_POSITIONS, function(p) {
    r <- rows[rows$position == p, ]
    n <- tabulate(r$band, nbins = length(POD_BANDS) + 1)
    groups <- lapply(seq_along(n), function(i) i)       # list of band index sets
    repeat {
      sizes <- vapply(groups, function(g) sum(n[g]), 0)
      small <- which(sizes < min_cell)
      if (!length(small) || length(groups) == 1) break
      i <- max(small)
      j <- if (i > 1) i - 1 else 2
      groups[[min(i, j)]] <- sort(c(groups[[i]], groups[[j]]))
      groups[[max(i, j)]] <- NULL
    }
    purrr::map(groups, function(g) {
      x <- r$resid[r$band %in% g]
      q <- stats::quantile(x, tau, type = 7, names = FALSE)
      tibble::tibble(position = p, band_lo = min(g), band_hi = max(g), label = pod_band_label(min(g), max(g)),
                     n = length(x), sd = stats::sd(x), q = list(q))
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(floor = unname(vapply(.data$position, function(p) min(rows$y[rows$position == p]), 0)))
}

#' Predictive quantiles (n x length(tau)) of F(y | active, base) for positions and bases.
pd_quantiles <- function(position, base, table, tau = POD_TAU) {
  band <- pd_band(base)
  out <- matrix(NA_real_, length(base), length(tau))
  for (i in seq_len(nrow(table))) {
    hit <- position == table$position[i] & band >= table$band_lo[i] & band <= table$band_hi[i]
    if (any(hit)) {
      out[hit, ] <- pmax(outer(base[hit], table$q[[i]], `+`), table$floor[i])
    }
  }
  out
}

#' Normal reference (not a selection criterion): base + N(0, sd of the training residuals of the cell).
pd_normal_sd <- function(position, base, table) {
  band <- pd_band(base)
  vapply(seq_along(base), function(i) {
    k <- which(table$position == position[i] & band[i] >= table$band_lo & band[i] <= table$band_hi)
    if (length(k)) table$sd[k[1]] else NA_real_
  }, 0)
}

#' Week-clustered bootstrap replicates of a per-row statistic's mean (weeks resampled within season).
pd_cluster_boot <- function(x, season, week, reps = 2000, seed = 1) {
  wk <- dplyr::summarise(tibble::tibble(x = x, season = season, week = week), s = sum(.data$x), n = dplyr::n(),
                         .by = c("season", "week"))
  set.seed(seed)
  groups <- split(seq_len(nrow(wk)), wk$season)
  replicate(reps, {
    i <- unlist(lapply(groups, function(g) g[sample.int(length(g), replace = TRUE)]))
    sum(wk$s[i]) / sum(wk$n[i])
  })
}

#' E18 development evaluation: each season s in 2020-2023 scored with a table built from seasons
#' 2019..s-1 (out of sample within development). Coverage gate per 05 section 6 (Holm, 12 cells).
pd_dev_evaluation <- function(based, tau = POD_TAU, seasons = POD_DEV_SEASONS, reps = 2000, seed = 1) {
  pred <- purrr::map(seasons, function(s) {
    tab <- pd_residual_table(based[based$season < s, ], tau)
    d <- based[based$season == s & based$active, ]
    q <- pd_quantiles(d$position, d$base, tab, tau)
    cdf <- cdf_from_quantiles(d$y, q, tau)
    set.seed(seed + s)
    lv <- function(lo, hi) d$y >= q[, match(lo, tau)] & d$y <= q[, match(hi, tau)]
    tibble::tibble(season = d$season, week = d$week, position = d$position, y = d$y, base = d$base,
                   crps = crps_quantiles(q, d$y, tau),
                   crps_normal = crps_normal(d$y, d$base, pd_normal_sd(d$position, d$base, tab)),
                   pit = pit_randomised(cdf$F, cdf$F_minus),
                   cover50 = lv(0.25, 0.75), cover80 = lv(0.10, 0.90), cover90 = lv(0.05, 0.95),
                   is80 = interval_score(d$y, q[, match(0.10, tau)], q[, match(0.90, tau)], 0.2))
  }) |>
    purrr::list_rbind()
  cells <- tidyr::expand_grid(position = POD_POSITIONS, level = c(50, 80, 90))
  gate <- purrr::pmap(cells, function(position, level) {
    d <- pred[pred$position == position, ]
    x <- as.numeric(d[[paste0("cover", level)]])
    b <- pd_cluster_boot(x, d$season, d$week, reps, seed)
    est <- mean(x)
    nom <- level / 100
    p <- if (est < nom - 0.03) min(1, 2 * mean(b >= nom - 0.03)) else if (est > nom + 0.03) min(1, 2 * mean(b <= nom + 0.03)) else 1
    tibble::tibble(position = position, level = level, n = length(x), coverage = est,
                   ci_low = unname(stats::quantile(b, 0.025)), ci_high = unname(stats::quantile(b, 0.975)), p = p)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(p_holm = stats::p.adjust(.data$p, "holm"), fails_gate = .data$p_holm < 0.05)
  by_pos <- pred |>
    dplyr::summarise(n = dplyr::n(), crps = mean(.data$crps), crps_normal_ref = mean(.data$crps_normal),
                     interval_score80 = mean(.data$is80), pit_mean = mean(.data$pit),
                     pit_chisq = stats::chisq.test(tabulate(pmin(floor(.data$pit * 10) + 1, 10), 10))$statistic,
                     .by = "position")
  pit_hist <- pred |>
    dplyr::mutate(bin = pmin(floor(.data$pit * 10) + 1, 10)) |>
    dplyr::count(.data$position, .data$bin) |>
    dplyr::mutate(share = .data$n / sum(.data$n), .by = "position")
  list(by_position = by_pos, gate = gate, pit_hist = pit_hist, gate_passed = !any(gate$fails_gate),
       seasons = seasons, rows = nrow(pred))
}

#' Inactive share among projected rows by position (late-horizon P(active); descriptive).
pd_active_share <- function(frame, seasons = POD_DEV_SEASONS) {
  frame[frame$season %in% seasons, ] |>
    dplyr::summarise(rows = dplyr::n(), active_share = mean(.data$active),
                     no_snap_record = mean(is.na(.data$offense_snaps)), .by = "position")
}

#' The production table (2020-2023 active rows) as a plain list for the frozen YAML.
pd_freeze_table <- function(based, tau = POD_TAU) {
  prod <- based[based$season %in% POD_DEV_SEASONS, ]
  tab <- pd_residual_table(prod, tau)
  last_coef <- based |>
    dplyr::filter(.data$season == max(POD_DEV_SEASONS)) |>
    dplyr::slice_max(.data$week, n = 1, with_ties = TRUE) |>
    dplyr::distinct(.data$position, .data$a, .data$b)
  list(
    version = "pod_baseline_v0", pre_registration = "E18", seasons = POD_DEV_SEASONS, warmup = POD_WARMUP,
    tau = POD_TAU, band_upper_edges = POD_BANDS, min_cell = POD_MIN_CELL, quantile_type = 7L,
    cells = lapply(seq_len(nrow(tab)), function(i) list(position = tab$position[i], band_lo = tab$band_lo[i],
                                                         band_hi = tab$band_hi[i], label = tab$label[i], n = tab$n[i],
                                                         resid_quantiles = round(tab$q[[i]], 6))),
    floors = as.list(stats::setNames(round(tab$floor[!duplicated(tab$position)], 6), tab$position[!duplicated(tab$position)])),
    calibration_end_2023 = lapply(split(last_coef, last_coef$position), function(x) list(a = round(x$a, 6), b = round(x$b, 6))),
    rows_active = sum(prod$active)
  )
}

#' The frozen table as a residual table for pd_quantiles().
pd_table_from_yaml <- function(y) {
  tibble::tibble(position = vapply(y$cells, `[[`, "", "position"),
                 band_lo = vapply(y$cells, function(c) as.integer(c$band_lo), 0L),
                 band_hi = vapply(y$cells, function(c) as.integer(c$band_hi), 0L),
                 label = vapply(y$cells, `[[`, "", "label"),
                 n = vapply(y$cells, function(c) as.integer(c$n), 0L),
                 q = lapply(y$cells, function(c) as.numeric(unlist(c$resid_quantiles)))) |>
    dplyr::mutate(floor = as.numeric(unlist(y$floors[.data$position])), sd = NA_real_)
}

read_pod_table <- function(path = POD_TABLE_FILE) pd_table_from_yaml(yaml::read_yaml(path))

#' Check a POD table: quantiles non-decreasing in tau, probabilities in [0, 1], finite means.
validate_pod_table <- function(pods, tau = POD_TAU) {
  qcols <- paste0("q", sprintf("%02d", round(tau * 100)))
  stopifnot(all(qcols %in% names(pods)))
  q <- as.matrix(pods[, qcols])
  bad_order <- sum(apply(q, 1, function(r) any(diff(r) < -1e-9)))
  problems <- c(
    if (bad_order) sprintf("%d rows with decreasing quantiles", bad_order),
    if (any(pods$p_active < 0 | pods$p_active > 1, na.rm = TRUE)) "p_active outside [0, 1]",
    if (any(!is.finite(pods$mean))) "non-finite means"
  )
  if (length(problems)) cli::cli_abort("Invalid POD table: {problems}")
  invisible(TRUE)
}

#' PODs for players: quantiles of F(y | active, base) plus p_active and the POD mean
#' (p_active * mean of the active distribution, approximated by the quantile average).
pd_pods <- function(players, table, tau = POD_TAU) {
  q <- pd_quantiles(players$position, players$base, table, tau)
  colnames(q) <- paste0("q", sprintf("%02d", round(tau * 100)))
  w <- c(diff(c(0, tau)) / 2 + diff(c(tau, 1)) / 2)    # trapezoid weights over tau, tails to the end quantiles
  w <- w / sum(w)
  mean_active <- drop(q %*% w)
  dplyr::bind_cols(players, tibble::as_tibble(q)) |>
    dplyr::mutate(mean_active = mean_active, mean = .data$p_active * mean_active)
}
