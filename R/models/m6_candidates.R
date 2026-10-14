# R2: RB/TE/QB designation and practice adjustments (master plan R2; pre-registration E19, X14) ----
# The M4 template on F4's rolling calibrated ESPN (`base`) for RB, TE and QB, with position-specific
# parameters derived from development seasons 2020-2023 only (rounded to 2 decimals):
#   B0 base; B1 one halved Questionable/Doubtful multiplier; K1 halved group multipliers (groups
#   with < 100 development rows pool into Q_pool); K2 logistic P(active | practice, Doubtful,
#   returning, streak) x the group's ratio of points to base when active (not halved, as in M4).
# M4's own code (R/models/m4_candidates.R) is untouched.

M6_POSITIONS <- c("RB", "TE", "QB")
M6_DEV <- 2020:2023
M6_CHECK <- 2019L
M6_CHECK_WEEKS <- 5:17
M6_CANDIDATES <- c("B1", "K1", "K2")       # simplest first (the selection rule's order)
M6_PARAMS_FILE <- "research/m6_candidate_params.yml"

#' R2 rows: F4 RB/TE/QB player-weeks with an ESPN projection > 0.
m6_frame <- function(player_week_all) {
  player_week_all |>
    dplyr::filter(.data$position %in% M6_POSITIONS, .data$pop_espn) |>
    dplyr::transmute(.data$season, .data$week, .data$gsis_id, .data$position, .data$base, .data$actual,
                     .data$active, .data$group, .data$designation, .data$practice, .data$weeks_listed_streak,
                     .data$prev_offense_snaps)
}

#' K2's logistic design (M4's terms; returning = no offensive snap in the team's previous game).
m6_active_design <- function(fr) {
  data.frame(dnp = as.numeric(fr$practice %in% "DNP"), lp = as.numeric(fr$practice %in% "LP"),
             doubtful = as.numeric(fr$designation %in% "Doubtful"),
             returning = as.numeric(fr$prev_offense_snaps %in% 0), streak = pmin(fr$weeks_listed_streak, 4))
}

#' Candidate parameters per position from development rows only.
m6_derive_params <- function(fr, seasons = M6_DEV, min_n = 100, digits = 2, register = read_contamination_register()) {
  assert_family_seasons("injury_stack", seasons, "development", register)
  d <- fr[fr$season %in% seasons, ]
  ratio <- function(i) sum(d$actual[i]) / sum(d$base[i])
  out <- lapply(M6_POSITIONS, function(p) {
    dp <- d$position == p
    qd <- dp & d$designation %in% c("Questionable", "Doubtful")
    n_by <- table(factor(d$group[dp], levels = M4_ADJ_GROUPS))
    pooled <- names(n_by)[n_by < min_n]
    groups <- c("Q_pool", setdiff(M4_ADJ_GROUPS, pooled))
    rows <- function(g) if (g == "Q_pool") qd else dp & d$group %in% g
    adj <- dp & d$group %in% M4_ADJ_GROUPS
    fit <- stats::glm(d$active[adj] ~ ., data = m6_active_design(d[adj, ]), family = stats::binomial())
    beta <- stats::coef(fit)
    beta[is.na(beta)] <- 0                                       # an aliased term contributes nothing
    list(
      n_dev = as.list(c(n_by, Q_pool = sum(qd))),
      pooled_into_Q_pool = pooled,
      b1_multiplier_adj = round((ratio(qd) - 1) / 2, digits),
      k1_multiplier_adj = as.list(stats::setNames(vapply(groups, function(g) round((ratio(rows(g)) - 1) / 2, digits), 0), groups)),
      k2_logit = as.list(round(beta, 3)),
      k2_ratio_if_active = as.list(stats::setNames(vapply(groups, function(g) round(ratio(rows(g) & d$active), digits), 0), groups))
    )
  })
  c(list(derived_from = paste(range(seasons), collapse = "-")), stats::setNames(out, M6_POSITIONS))
}

#' Multiplier on the base for one candidate (rows outside the adjustable groups get 1).
m6_multiplier <- function(fr, params, candidate = c("B0", "B1", "K1", "K2")) {
  candidate <- match.arg(candidate)
  m <- rep(1, nrow(fr))
  if (candidate == "B0") return(m)
  for (p in M6_POSITIONS) {
    pr <- params[[p]]
    i <- fr$position == p
    pg <- m4_param_group(fr$group[i], unlist(pr$pooled_into_Q_pool))
    m[i] <- switch(candidate,
      B1 = ifelse(fr$designation[i] %in% c("Questionable", "Doubtful"), 1 + pr$b1_multiplier_adj, 1),
      K1 = ifelse(is.na(pg), 1, 1 + unlist(pr$k1_multiplier_adj)[pg]),
      K2 = {
        beta <- unlist(pr$k2_logit)
        x <- as.matrix(cbind(1, m6_active_design(fr[i, ])[, names(beta)[-1], drop = FALSE]))
        ifelse(is.na(pg), 1, stats::plogis(drop(x %*% beta)) * unlist(pr$k2_ratio_if_active)[pg])
      })
  }
  unname(m)
}

#' Squared-error differences (candidate minus B0) per row for each candidate.
m6_errors <- function(fr, params) {
  out <- dplyr::select(fr, "season", "week", "gsis_id", "position")
  e0 <- (fr$actual - fr$base)^2
  for (k in M6_CANDIDATES) {
    pred <- fr$base * m6_multiplier(fr, params, k)
    out[[paste0("dse_", k)]] <- (fr$actual - pred)^2 - e0
    out[[paste0("dae_", k)]] <- abs(fr$actual - pred) - abs(fr$actual - fr$base)
  }
  out$se0 <- e0
  out
}

#' Development qualification and selection (E19): pooled RB/TE/QB development dMSE against B0 with a
#' week-clustered, season-blocked bootstrap CI; qualifiers have CI upper < 0; the lowest MSE wins
#' unless a simpler qualifier is within 0.5% of B0's MSE.
m6_dev_selection <- function(fr, params, reps = 2000L, seed = 1L, tie = 0.005) {
  e <- m6_errors(fr[fr$season %in% M6_DEV, ], params)
  res <- purrr::map(M6_CANDIDATES, function(k) {
    x <- e[[paste0("dse_", k)]]
    b <- pd_cluster_boot(x, e$season, e$week, reps = reps, seed = seed)
    tibble::tibble(candidate = k, n = length(x), d_mse = mean(x), lo = unname(stats::quantile(b, 0.025)),
                   hi = unname(stats::quantile(b, 0.975)), d_mae = mean(e[[paste0("dae_", k)]]))
  }) |> purrr::list_rbind()
  mse0 <- mean(e$se0)
  q <- res[res$hi < 0, ]
  selected <- NA_character_
  if (nrow(q)) {
    best <- q$candidate[which.min(q$d_mse)]
    simpler <- q$candidate[match(q$candidate, M6_CANDIDATES) < match(best, M6_CANDIDATES) &
                             q$d_mse <= min(q$d_mse) + tie * mse0]
    selected <- if (length(simpler)) simpler[1] else best
  }
  list(results = res, mse_b0 = mse0, selected = selected)
}

#' 2019 MDE on pooled dMSE for the selected candidate, from development week-level variability:
#' (z_{1 - alpha} + z_{power}) x sd(week-level dMSE) / sqrt(weeks), alpha the stricter Holm level.
m6_mde <- function(fr, params, candidate, weeks = length(M6_CHECK_WEEKS), alpha = 0.025, power = 0.8) {
  e <- m6_errors(fr[fr$season %in% M6_DEV, ], params)
  wk <- dplyr::summarise(e, d = mean(.data[[paste0("dse_", candidate)]]), .by = c("season", "week"))
  sd_w <- stats::sd(wk$d)
  list(candidate = candidate, sd_week = sd_w, weeks = weeks,
       mde = (stats::qnorm(1 - alpha) + stats::qnorm(power)) * sd_w / sqrt(weeks))
}
