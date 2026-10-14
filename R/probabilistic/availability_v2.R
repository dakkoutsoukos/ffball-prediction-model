# P1: availability v2 at the post-report horizon (master plan P1; pre-registration E19, X5) --------
# P(active) for players on the team's final pregame injury report, without any ESPN input (so no
# post-inactive selection). Active = at least one offensive snap (a stat line counts where no snap
# record exists). Baseline R0: designation x practice x position rate table. Candidate G1: logistic
# GLMM in mgcv with a team-season random effect (X-018). Development 2020-2023 (rolling by season,
# training adds 2017-2018); the 2019 check runs once, in a gated target.

P1_POSITIONS <- c("QB", "RB", "WR", "TE")
P1_PRIMARY <- c("QB", "RB", "TE")
P1_TRAIN <- 2017:2018
P1_DEV <- 2020:2023
P1_CHECK <- 2019L
P1_DESIGNATIONS <- c("Out", "Doubtful", "Questionable", "Note", "listed_only")
P1_PRACTICE <- c("DNP", "LP", "FP", "none")
P1_MIN_CELL <- 30L

#' Kickoff day in US Eastern time: Thu, Sun, Mon or other.
p1_kickoff_day <- function(kickoff_utc) {
  wd <- as.POSIXlt(kickoff_utc, tz = "America/New_York")$wday
  dplyr::case_when(wd == 4 ~ "Thu", wd == 0 ~ "Sun", wd == 1 ~ "Mon", TRUE ~ "other")
}

#' Player-weeks that were active: at least one offensive snap, or a stat line where no snap record
#' exists (snap tables keep only players with offensive snaps).
p1_active_keys <- function(snaps, player_stats) {
  dplyr::bind_rows(
    dplyr::select(dplyr::filter(snaps, .data$offense_snaps >= 1), "season", "week", "gsis_id"),
    dplyr::select(player_stats, "season", "week", "gsis_id")
  ) |>
    dplyr::distinct() |>
    dplyr::mutate(active = TRUE)
}

#' The P1 frame for `seasons`: the report population (every player on his team's final pregame
#' injury report) and the unlisted base-rate population (unlisted players with an offensive snap in
#' the team's previous game of the season, on the team's roster this week), with features and the
#' outcome. Seasons are checked against the contamination register by the caller.
p1_frame <- function(injury_detail, snaps, player_stats, rosters_weekly, team_games, seasons) {
  tg <- dplyr::filter(team_games, .data$season %in% !!seasons)
  prev <- tg |>
    dplyr::distinct(.data$season, .data$week, .data$team) |>
    dplyr::arrange(.data$season, .data$team, .data$week) |>
    dplyr::mutate(prev_week = dplyr::lag(.data$week), .by = c("season", "team"))
  act <- p1_active_keys(dplyr::filter(snaps, .data$season %in% !!seasons),
                        dplyr::filter(player_stats, .data$season %in% !!seasons))
  report <- injury_detail |>
    dplyr::filter(.data$season %in% !!seasons, .data$position %in% P1_POSITIONS) |>
    dplyr::semi_join(tg, by = c("season", "week", "team")) |>
    dplyr::transmute(.data$season, .data$week, .data$team, .data$gsis_id, .data$position, population = "report")
  prev_snap <- snaps |>
    dplyr::filter(.data$season %in% !!seasons, .data$offense_snaps >= 1) |>
    dplyr::transmute(.data$season, prev_week = .data$week, .data$gsis_id, prev_team = standardize_team(.data$snap_team))
  unlisted <- rosters_weekly |>
    dplyr::filter(.data$season %in% !!seasons, .data$roster_position %in% P1_POSITIONS) |>
    dplyr::transmute(.data$season, .data$week, team = .data$roster_team, .data$gsis_id, position = .data$roster_position) |>
    dplyr::inner_join(prev, by = c("season", "week", "team")) |>
    dplyr::inner_join(prev_snap, by = c("season", "prev_week", "gsis_id")) |>
    dplyr::filter(.data$prev_team == .data$team) |>
    dplyr::anti_join(report, by = c("season", "week", "gsis_id")) |>
    dplyr::transmute(.data$season, .data$week, .data$team, .data$gsis_id, .data$position, population = "unlisted")
  pop <- dplyr::bind_rows(report, unlisted) |>
    dplyr::distinct(.data$season, .data$week, .data$gsis_id, .keep_all = TRUE)
  out <- add_availability_features(pop, injury_detail, team_games) |>
    dplyr::left_join(prev, by = c("season", "week", "team")) |>
    dplyr::left_join(dplyr::rename(act, prev_week = "week", prev_active = "active"), by = c("season", "prev_week", "gsis_id")) |>
    dplyr::left_join(act, by = c("season", "week", "gsis_id")) |>
    dplyr::left_join(dplyr::select(tg, "season", "week", "team", "kickoff_utc"), by = c("season", "week", "team")) |>
    dplyr::mutate(active = dplyr::coalesce(.data$active, FALSE),
                  returning = !is.na(.data$prev_week) & !dplyr::coalesce(.data$prev_active, FALSE),
                  streak = pmin(.data$weeks_listed_streak, 4L),
                  kickoff_day = p1_kickoff_day(.data$kickoff_utc),
                  team_season = paste(.data$team, .data$season, sep = "_"),
                  designation = factor(.data$designation, c(P1_DESIGNATIONS, "none")),
                  practice = factor(dplyr::if_else(.data$practice %in% P1_PRACTICE, .data$practice, "none"), P1_PRACTICE),
                  prev_designation = factor(dplyr::if_else(.data$prev_designation %in% P1_DESIGNATIONS,
                                                           .data$prev_designation, "none"), c("none", P1_DESIGNATIONS)),
                  position = factor(.data$position, P1_POSITIONS),
                  kickoff_day = factor(.data$kickoff_day, c("Sun", "Thu", "Mon", "other"))) |>
    dplyr::select(-"prev_active")
  assert_unique_key(out, c("season", "week", "gsis_id"), "p1_frame")
}

#' R0: rate table by designation x practice x position; cells with fewer than `min_cell` training rows
#' fall back to designation x practice, then to designation, then to the overall rate.
p1_fit_rate_table <- function(train, min_cell = P1_MIN_CELL) {
  tab <- function(...) dplyr::summarise(train, n = dplyr::n(), p = mean(.data$active), .by = c(...))
  list(full = tab("designation", "practice", "position"), dp = tab("designation", "practice"), d = tab("designation"),
       overall = mean(train$active), min_cell = min_cell)
}

p1_predict_rate_table <- function(fit, newdata) {
  look <- function(t, by) {
    k <- dplyr::left_join(newdata[by], t, by = by)
    ifelse(k$n >= fit$min_cell, k$p, NA_real_)
  }
  p <- look(fit$full, c("designation", "practice", "position"))
  p <- dplyr::coalesce(p, look(fit$dp, c("designation", "practice")))
  p <- dplyr::coalesce(p, look(fit$d, "designation"))
  dplyr::coalesce(p, fit$overall)
}

P1_FORMULA <- active ~ designation * practice + position + returning + streak + prev_designation + kickoff_day +
  s(team_season, bs = "re")

#' G1: logistic GLMM (mgcv, REML) with a team-season random intercept.
p1_fit_glmm <- function(train) {
  train <- droplevels(dplyr::mutate(train, team_season = factor(.data$team_season)))
  # a factor with a single level in the training rows cannot be estimated: its term is dropped
  single <- names(Filter(function(x) is.factor(x) && nlevels(x) < 2, train))
  f <- P1_FORMULA
  if (length(single)) f <- stats::update(f, stats::as.formula(paste(". ~ . -", paste(single, collapse = " - "))))
  mgcv::gam(f, family = stats::binomial(), data = train, method = "REML")
}

#' G1 predictions with the random effect at 0 (team-seasons are never shared between training and
#' scored seasons). Factor combinations unseen in training predict through the remaining terms.
p1_predict_glmm <- function(fit, newdata) {
  nd <- newdata
  nd$team_season <- factor(levels(fit$model$team_season)[1], levels(fit$model$team_season))
  for (v in intersect(c("designation", "practice", "prev_designation", "position", "kickoff_day"), names(fit$model))) {
    nd[[v]] <- factor(as.character(nd[[v]]), levels(fit$model[[v]]))
  }
  unname(stats::predict(fit, nd, type = "response", exclude = "s(team_season)"))
}

log_loss <- function(p, o, eps = 1e-6) {
  p <- pmin(pmax(p, eps), 1 - eps)
  -mean(o * log(p) + (1 - o) * log(1 - p))
}

#' Calibration slope: logistic regression of the outcome on logit(p).
calibration_slope <- function(p, o, eps = 1e-6) {
  x <- stats::qlogis(pmin(pmax(p, eps), 1 - eps))
  unname(stats::coef(suppressWarnings(stats::glm(o ~ x, family = stats::binomial())))[2])
}

#' Scores of R0 and G1 on scored rows: Brier, log loss, slope, Brier skill, by group.
p1_scores <- function(scored, by = character()) {
  scored |>
    dplyr::summarise(n = dplyr::n(), observed = mean(.data$active), brier_r0 = brier_score(.data$p_r0, .data$active),
                     brier_g1 = brier_score(.data$p_g1, .data$active),
                     logloss_r0 = log_loss(.data$p_r0, .data$active), logloss_g1 = log_loss(.data$p_g1, .data$active),
                     slope_g1 = calibration_slope(.data$p_g1, .data$active), .by = dplyr::all_of(by)) |>
    dplyr::mutate(skill = 1 - .data$brier_g1 / .data$brier_r0, .after = "brier_g1")
}

#' Week-clustered bootstrap of a ratio statistic over scored rows (weeks resampled within season).
p1_boot <- function(scored, stat, reps = 2000L, seed = 1L) {
  wk <- split(seq_len(nrow(scored)), paste(scored$season, scored$week))
  by_season <- split(names(wk), sub(" .*", "", names(wk)))
  set.seed(seed)
  replicate(reps, {
    i <- unlist(lapply(by_season, function(w) unlist(wk[sample(w, length(w), replace = TRUE)], use.names = FALSE)))
    stat(scored[i, ])
  })
}

#' Development evaluation (descriptive): for each development season s, fit R0 and G1 on 2017-2018
#' plus the development seasons before s, and score s. `exclude` drops seasons (COVID sensitivity).
p1_dev_evaluation <- function(frame, dev = P1_DEV, train0 = P1_TRAIN, exclude = integer(0),
                              register = read_contamination_register()) {
  assert_family_seasons("injury_stack", setdiff(dev, exclude), "development", register)
  assert_family_seasons("injury_stack", train0, "training", register)
  rep <- frame[frame$population == "report", ]
  purrr::map(setdiff(dev, exclude), function(s) {
    tr <- rep[rep$season %in% setdiff(c(train0, dev[dev < s]), exclude), ]
    te <- rep[rep$season == s, ]
    te$p_r0 <- p1_predict_rate_table(p1_fit_rate_table(tr), te)
    te$p_g1 <- p1_predict_glmm(p1_fit_glmm(tr), te)
    te
  }) |> purrr::list_rbind()
}

#' Development summary (descriptive): scores per season and position, the pooled RB/TE/QB Brier skill
#' with a season-blocked, week-clustered bootstrap CI, WR separately, the COVID sensitivity, and the
#' unlisted population's base rates.
p1_dev_summary <- function(scored, scored_covid, frame, reps = 2000L, seed = 1L) {
  prim <- scored[scored$position %in% P1_PRIMARY, ]
  skill <- function(d) 1 - brier_score(d$p_g1, d$active) / brier_score(d$p_r0, d$active)
  b <- p1_boot(prim, skill, reps, seed)
  un <- frame[frame$population == "unlisted", ]
  list(
    pooled_primary = dplyr::mutate(p1_scores(prim), skill_lo = unname(stats::quantile(b, 0.025)),
                                   skill_hi = unname(stats::quantile(b, 0.975))),
    by_season = p1_scores(prim, "season"),
    by_position = p1_scores(scored, "position"),
    covid_sensitivity = p1_scores(scored_covid[scored_covid$position %in% P1_PRIMARY, ]),
    unlisted_base_rate = dplyr::summarise(un, n = dplyr::n(), active = mean(.data$active), .by = c("season", "position")) |>
      dplyr::arrange(.data$position, .data$season)
  )
}

#' E19's one batch check on 2019 (run once, from a gated target). P1: R0 and G1 fit on the 2017-2018
#' and 2020-2023 report rows, scored on 2019's report population (RB/TE/QB pooled: H5, plus the slope
#' rule). R2: the selected candidate's pooled dMSE against B0 on 2019 weeks 5-17 (H14). Holm across
#' the primaries present.
e19_batch_check <- function(injury_detail, snaps, player_stats, rosters_weekly, team_games, p1_frame_dev, m6_rows,
                            m6_params, m6_selected, register, reps = 2000L, seed = 19L) {
  assert_family_seasons("injury_stack", P1_CHECK, "check", register)
  tr <- p1_frame_dev[p1_frame_dev$population == "report", ]
  r0 <- p1_fit_rate_table(tr)
  g1 <- p1_fit_glmm(tr)
  f19 <- p1_frame(injury_detail, snaps, player_stats, rosters_weekly, team_games, P1_CHECK)
  te <- f19[f19$population == "report", ]
  te$p_r0 <- p1_predict_rate_table(r0, te)
  te$p_g1 <- p1_predict_glmm(g1, te)
  prim <- te[te$position %in% P1_PRIMARY, ]
  skill <- function(d) 1 - brier_score(d$p_g1, d$active) / brier_score(d$p_r0, d$active)
  sb <- p1_boot(prim, skill, reps, seed)
  slope_b <- p1_boot(prim, function(d) calibration_slope(d$p_g1, d$active), reps, seed + 1L)
  p5 <- (1 + sum(sb <= 0)) / (1 + reps)
  slope <- calibration_slope(prim$p_g1, prim$active)
  slope_ci <- unname(stats::quantile(slope_b, c(0.025, 0.975)))
  h14 <- NULL
  if (!is.na(m6_selected)) {
    rows <- m6_rows[m6_rows$season == M6_CHECK & m6_rows$week %in% M6_CHECK_WEEKS, ]
    e <- m6_errors(rows, m6_params)
    x <- e[[paste0("dse_", m6_selected)]]
    b <- pd_cluster_boot(x, e$season, e$week, reps = reps, seed = seed + 2L)
    h14 <- list(candidate = m6_selected, n = length(x), d_mse = mean(x), ci = unname(stats::quantile(b, c(0.025, 0.975))),
                p = (1 + sum(b >= 0)) / (1 + reps))
  }
  ps <- c(H5 = p5, H14 = if (is.null(h14)) NA_real_ else h14$p)
  ps <- ps[!is.na(ps)]
  adj <- stats::p.adjust(ps, "holm")
  un19 <- f19[f19$population == "unlisted", ]
  all19 <- if (is.na(m6_selected)) NULL else {
    rows <- m6_rows[m6_rows$season == M6_CHECK & m6_rows$week %in% M6_CHECK_WEEKS, ]
    e <- m6_errors(rows, m6_params)
    purrr::map(M6_CANDIDATES, function(k) {
      dplyr::summarise(e, n = dplyr::n(), d_mse = mean(.data[[paste0("dse_", k)]]), d_mae = mean(.data[[paste0("dae_", k)]]),
                       .by = "position") |> dplyr::mutate(candidate = k, .before = 1)
    }) |> purrr::list_rbind()
  }
  list(
    h5 = list(n = nrow(prim), scores = p1_scores(prim), skill_ci = unname(stats::quantile(sb, c(0.025, 0.975))), p = p5,
              p_holm = unname(adj["H5"]), slope = slope, slope_ci = slope_ci,
              slope_rule = slope_ci[1] <= 1 && slope_ci[2] >= 1 && slope >= 0.8 && slope <= 1.2),
    h14 = if (is.null(h14)) NULL else c(h14, p_holm = unname(adj["H14"])),
    success_x5 = unname(adj["H5"]) <= 0.05 &&
      (slope_ci[1] <= 1 && slope_ci[2] >= 1 && slope >= 0.8 && slope <= 1.2),
    success_x14 = !is.null(h14) && unname(adj["H14"]) <= 0.05,
    secondary = list(by_position = p1_scores(te, "position"), wr = p1_scores(te[te$position == "WR", ]),
                     unlisted = dplyr::summarise(un19, n = dplyr::n(), active = mean(.data$active), .by = "position"),
                     r2_all_candidates = all19)
  )
}

P1_PROVIDER_FILE <- "models/probabilistic/p1_availability_v2.yml"

#' The frozen provider as a plain list: G1's fixed effects (the team-season effect is 0 at
#' prediction, as E19 fixed), the factor levels and the formula's parametric part.
p1_provider_list <- function(fit, check) {
  b <- stats::coef(fit)
  fixed <- b[!startsWith(names(b), "s(")]
  lv <- lapply(c(designation = "designation", practice = "practice", prev_designation = "prev_designation",
                 position = "position", kickoff_day = "kickoff_day"), function(v) levels(fit$model[[v]]))
  list(version = "p1_availability_v2", pre_registration = "E19", fitted_on = "report population 2017-2018 + 2020-2023",
       formula = "active ~ designation * practice + position + returning + streak + prev_designation + kickoff_day (team-season effect 0)",
       levels = lv, coefficients = as.list(round(fixed, 8)), check_2019 = check)
}

#' P(active) from the frozen provider for rows with the P1 features.
p1_provider_predict <- function(provider, newdata) {
  lv <- provider$levels
  nd <- newdata
  for (v in names(lv)) nd[[v]] <- factor(as.character(nd[[v]]), unlist(lv[[v]]))
  nd$returning <- as.logical(nd$returning)
  X <- stats::model.matrix(~ designation * practice + position + returning + streak + prev_designation + kickoff_day,
                           data = nd)
  b <- unlist(provider$coefficients)
  miss <- setdiff(colnames(X), names(b))
  b[miss] <- 0                                            # empty interaction cells: 0, as in the fit
  unname(stats::plogis(drop(X[, names(b)[names(b) %in% colnames(X)], drop = FALSE] %*% b[names(b) %in% colnames(X)])))
}
