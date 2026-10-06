# Milestone 4 candidates (docs/milestone4_plan.md section 9) -------------------------------
# Every candidate = calibrated ESPN (`base`, weekly rolling, the m2_espn_cal
# procedure) + an adjustment whose parameters are derived ONCE from the
# development seasons (2020-2023) by m4_derive_params(), rounded, written to
# research/m4_candidate_params.yml and recorded in the experiment log (E13)
# BEFORE the 2019 and 2024 checks are run.

# Groups that K1-K3 may adjust; groups with fewer than `min_n` development rows
# are pooled with all Questionable/Doubtful rows ("Q_pool").
M4_ADJ_GROUPS <- c("Q_DNP", "Q_LP", "Q_FP", "Q_other", "D", "listed_DNP_LP")

#' Map injury groups to the parameter group used by K1-K3 (NA = no adjustment).
m4_param_group <- function(group, pooled) {
  dplyr::case_when(!group %in% M4_ADJ_GROUPS ~ NA_character_, group %in% pooled ~ "Q_pool", TRUE ~ group)
}

#' Logistic design for K2: P(active | final practice status, Doubtful,
#' returning from an absence, consecutive weeks listed).
m4_active_design <- function(fr) {
  data.frame(
    dnp = as.numeric(fr$practice %in% "DNP"),
    lp = as.numeric(fr$practice %in% "LP"),
    doubtful = as.numeric(fr$designation %in% "Doubtful"),
    returning = as.numeric(dplyr::coalesce(fr$team_games_missed, 0L) > 0),
    streak = pmin(fr$weeks_listed_streak, 4)
  )
}

#' Derive all candidate parameters from development rows only.
m4_derive_params <- function(fr, seasons = M4_DEV, min_n = 100, digits = 2) {
  d <- dplyr::filter(fr, .data$season %in% seasons)
  stopifnot(!any(d$season %in% c(2019, 2024, 2025, 2026)))
  n_by <- table(factor(d$group, levels = M4_ADJ_GROUPS))
  pooled <- names(n_by)[n_by < min_n]
  d$pg <- m4_param_group(d$group, pooled)
  q <- d$designation %in% c("Questionable", "Doubtful")
  active <- d$roster_status %in% "ACT" | d$has_stat_line
  ratio <- function(num, den) sum(num) / sum(den) - 1
  groups <- c("Q_pool", setdiff(M4_ADJ_GROUPS, pooled))
  rows <- function(g) if (g == "Q_pool") q else d$pg %in% g
  half <- function(f) stats::setNames(vapply(groups, function(g) round(f(rows(g)) / 2, digits), numeric(1)), groups)
  k1 <- half(function(i) ratio(d$actual[i], d$base[i]))
  k3 <- half(function(i) ratio(d$actual_targets[i], d$cal_targets[i]))
  # K2: logistic P(active) on the adjustable rows; ratio of points to base when active.
  adj <- !is.na(d$pg)
  x <- m4_active_design(d[adj, ])
  glm_fit <- stats::glm(active[adj] ~ ., data = x, family = stats::binomial())
  r_active <- stats::setNames(vapply(groups, function(g) {
    i <- rows(g) & active
    round(sum(d$actual[i]) / sum(d$base[i]), digits)
  }, numeric(1)), groups)
  dis <- d$our_targets - d$cal_targets
  w <- stats::coef(stats::lm(I(d$actual_targets - d$cal_targets) ~ dis))[["dis"]]
  list(
    derived_from = paste(range(seasons), collapse = "-"),
    pooled_into_Q_pool = pooled,
    n_dev = as.list(c(n_by, Q_pool = sum(q))),
    k1_multiplier_adj = as.list(k1),
    k2_logit = as.list(round(stats::coef(glm_fit), 3)),
    k2_ratio_if_active = as.list(r_active),
    k3_target_ratio_adj = as.list(k3),
    k4_w = round(w, digits),
    b1_questionable = -0.09
  )
}

#' Multiplier on the calibrated-ESPN base for the availability rules (shared by
#' the candidate study and the frozen M4 registry specs):
#'   practice  (K1): 1 + m[group]
#'   two_stage (K2): P(active | practice, Doubtful, returning, streak) x r[group]
#' Rows outside the adjustable groups get 1.
m4_rule_multiplier <- function(newdata, rule) {
  pg <- m4_param_group(newdata$group, unlist(rule$pooled_into_Q_pool))
  switch(rule$kind,
    practice = ifelse(is.na(pg), 1, 1 + unlist(rule$multiplier_adj)[pg]),
    two_stage = {
      beta <- unlist(rule$logit)
      x <- as.matrix(cbind(1, m4_active_design(newdata)[, names(beta)[-1], drop = FALSE]))
      p_active <- stats::plogis(drop(x %*% beta))
      ifelse(is.na(pg), 1, p_active * unlist(rule$ratio_if_active)[pg])
    },
    cli::cli_abort("Unknown M4 rule kind {.val {rule$kind}}.")
  )
}

#' Rule objects for K1 and K2 from the fixed parameter list.
m4_rules <- function(p) {
  list(
    K1 = list(kind = "practice", pooled_into_Q_pool = unlist(p$pooled_into_Q_pool),
              multiplier_adj = p$k1_multiplier_adj),
    K2 = list(kind = "two_stage", pooled_into_Q_pool = unlist(p$pooled_into_Q_pool),
              logit = p$k2_logit, ratio_if_active = p$k2_ratio_if_active)
  )
}

#' Candidate predictions (long format) for every row of the M4 frame.
m4_candidate_preds <- function(fr, p) {
  pg <- m4_param_group(fr$group, unlist(p$pooled_into_Q_pool))
  lookup <- function(tab) { v <- unlist(tab)[pg]; ifelse(is.na(v), 0, v) }
  ppt <- fr$pts_per_target_espn
  rules <- m4_rules(p)
  preds <- list(
    B0 = fr$base,
    B1 = fr$pred_b1,
    K1 = fr$base * m4_rule_multiplier(fr, rules$K1),
    K2 = fr$base * m4_rule_multiplier(fr, rules$K2),
    K3 = fr$base + lookup(p$k3_target_ratio_adj) * fr$cal_targets * ppt,
    K4 = fr$pred_b1 + p$k4_w * (fr$our_targets - fr$cal_targets) * ppt
  )
  keys <- dplyr::select(fr, "season", "week", "gsis_id", "actual", "relevant", "startable", "espn_rank", "group")
  purrr::imap(preds, function(v, m) dplyr::mutate(keys, model = m, pred = v)) |>
    purrr::list_rbind() |>
    # injury-affected rows: any Questionable/Doubtful or listed-only DNP/LP row
    dplyr::mutate(adjusted = .data$group %in% M4_ADJ_GROUPS)
}

M4_PARAM_COUNT <- c(B0 = 0, B1 = 1, K1 = 4, K2 = 10, K3 = 4, K4 = 2)

#' Comparisons of each candidate vs B0 and B1 (and B1 vs B0) for the given
#' seasons, by subset, with paired season-stratified week bootstraps.
m4_evaluate <- function(preds, seasons, reps = 2000, seed = 1) {
  d <- dplyr::filter(preds, .data$season %in% seasons)
  subsets <- list(all = d, top60 = dplyr::filter(d, .data$relevant), top36 = dplyr::filter(d, .data$startable),
                  top24 = dplyr::filter(d, .data$espn_rank <= 24))
  pairs <- tibble::tribble(~model, ~baseline,
                           "B1", "B0", "K1", "B0", "K2", "B0", "K3", "B0", "K4", "B0",
                           "K1", "B1", "K2", "B1", "K3", "B1", "K4", "B1")
  comp <- purrr::imap(subsets, function(s, nm) {
    purrr::pmap(pairs, function(model, baseline) pooled_bootstrap(s, model, baseline, reps, seed)) |>
      purrr::list_rbind() |>
      dplyr::mutate(subset = nm)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(params = M4_PARAM_COUNT[.data$model])
  seasonal <- purrr::pmap(pairs, function(model, baseline) seasonal_deltas(d, model, baseline)) |>
    purrr::list_rbind()
  metrics <- summarise_m2(d)
  affected <- d |>
    dplyr::filter(.data$adjusted) |>
    dplyr::left_join(dplyr::select(dplyr::filter(d, .data$model == "B0"), "season", "week", "gsis_id", b0 = "pred"),
                     by = c("season", "week", "gsis_id")) |>
    dplyr::summarise(n = dplyr::n(), mae = mean(abs(.data$pred - .data$actual)),
                     rmse = sqrt(mean((.data$pred - .data$actual)^2)), bias = mean(.data$pred - .data$actual),
                     mean_adjustment = mean(.data$pred - .data$b0), .by = "model")
  list(seasons = seasons, comparisons = comp, seasonal = seasonal, metrics = metrics, affected = affected)
}

#' Pre-registered freeze decision (plan section 10) from the development and
#' 2019 evaluations. 2024 is reported but cannot change the decision.
m4_freeze_decision <- function(dev, check19) {
  get <- function(ev, base) dplyr::filter(ev$comparisons, .data$subset == "all", .data$baseline == base)
  out <- purrr::map(c("K1", "K2", "K3", "K4"), function(k) {
    a_dev <- dplyr::filter(get(dev, "B0"), .data$model == k)
    a_19 <- dplyr::filter(get(check19, "B0"), .data$model == k)
    b_dev <- dplyr::filter(get(dev, "B1"), .data$model == k)
    b_19 <- dplyr::filter(get(check19, "B1"), .data$model == k)
    crit_a <- a_dev$ci_high < 0 && a_19$mae_diff < 0 && a_dev$rmse_model <= a_dev$rmse_baseline &&
      a_19$rmse_model <= a_19$rmse_baseline
    crit_b <- b_dev$mae_diff < 0 && b_19$mae_diff < 0 && b_dev$rmse_model <= b_dev$rmse_baseline &&
      b_19$rmse_model <= b_19$rmse_baseline
    tibble::tibble(model = k, params = M4_PARAM_COUNT[[k]], vs_B0_pass = crit_a, vs_B1_pass = crit_b,
                   freeze = crit_a && crit_b, dev_mae_diff = a_dev$mae_diff, mae_diff_2019 = a_19$mae_diff)
  }) |>
    purrr::list_rbind()
  # Plan section 10: the fewest parameters wins, unless another passing
  # candidate is better on BOTH development and 2019 (same rows, so comparing
  # ΔMAE vs B0 compares MAE).
  passing <- dplyr::filter(out, .data$freeze)
  winner <- NA_character_
  if (nrow(passing)) {
    simplest <- passing[which.min(passing$params), ]
    better <- dplyr::filter(passing, .data$dev_mae_diff < simplest$dev_mae_diff,
                            .data$mae_diff_2019 < simplest$mae_diff_2019)
    winner <- if (nrow(better)) better$model[which.min(better$dev_mae_diff)] else simplest$model
  }
  list(table = out, winner = winner)
}
