# Milestone 4: availability and opportunity research ---------------------------------------
# Protocol (docs/milestone4_plan.md, experiment log E12): every parameter is
# estimated on development seasons 2020-2023; 2019 (fresh) and 2024
# (contaminated) are checked once with parameters fixed.

M4_DEV <- 2020:2023
M4_TARGET_FEATURES <- c("targets_ewma2", "targets_ewma6", "target_share_ewma2", "target_share_ewma6",
                        "air_yards_share_ewma6", "snap_share_ewma2", "snap_share_ewma6", "xfp_ewma6",
                        "targets_roll2", "team_dropbacks_ewma", "team_neutral_pass_rate_ewma",
                        "log_career_games", "no_prev_season", "no_season_games", "played_team_prev_game")

#' Linear spec on an arbitrary target column (targets instead of points).
spec_on <- function(spec, target_col) {
  list(name = spec$name, features = spec$features,
       fit = function(train) spec$fit(dplyr::mutate(train, actual = .data[[target_col]])),
       predict = spec$predict)
}

#' Rolling predictions for 2019-2024: calibrated ESPN points (base), calibrated
#' ESPN targets, and our independent target model.
m4_rolling_bases <- function(frame, seasons = 2019:2024, min_train = 2018) {
  fr <- dplyr::mutate(frame, actual_targets = dplyr::coalesce(.data$actual_targets, 0))
  roll <- function(spec, col) {
    s <- if (is.null(col)) spec else spec_on(spec, col)
    p <- rolling_folds(fr, s, seasons, min_train)
    if (!is.null(col)) p$actual <- NULL
    p
  }
  base <- roll(spec_cal("components_recency"), NULL) |> dplyr::select("season", "week", "gsis_id", base = "pred")
  cal_tgt <- roll(spec_m2_linear("cal_targets", "espn_proj_targets"), "actual_targets") |>
    dplyr::select("season", "week", "gsis_id", cal_targets = "pred")
  our_tgt <- roll(spec_m2_linear("our_targets", M4_TARGET_FEATURES), "actual_targets") |>
    dplyr::select("season", "week", "gsis_id", our_targets = "pred")
  base |>
    dplyr::inner_join(cal_tgt, by = c("season", "week", "gsis_id")) |>
    dplyr::inner_join(our_tgt, by = c("season", "week", "gsis_id"))
}

#' Analysis frame: one row per ESPN-projected WR-week, 2019-2024.
m4_frame <- function(m3b_full, bases, detail, team_games) {
  m3b_full |>
    dplyr::filter(.data$season >= 2019, .data$season <= 2024) |>
    dplyr::inner_join(bases, by = c("season", "week", "gsis_id")) |>
    m4_add_features(detail, team_games) |>
    dplyr::mutate(
      actual_targets = dplyr::coalesce(.data$actual_targets, 0),
      # ESPN's own implied conversion rates (TDs untouched downstream)
      espn_rec_per_tgt = safe_ratio(.data$espn_proj_receptions, .data$espn_proj_targets),
      espn_yds_per_tgt = safe_ratio(.data$espn_proj_receiving_yards, .data$espn_proj_targets),
      pts_per_target_espn = dplyr::coalesce(.data$espn_rec_per_tgt, 0.62) * 1 +
        dplyr::coalesce(.data$espn_yds_per_tgt, 8) * 0.1,
      m3b_q = .data$own_questionable %in% TRUE
    ) |>
    # B1 = the frozen M3b rule, applied with its own inputs (verified against the
    # frozen predictions by target m4_b1_matches_frozen)
    dplyr::mutate(pred_b1 = .data$base + rule_questionable(list(own_questionable = .data$m3b_q),
                                                           .data$base, "multiplicative", -0.09))
}

#' Group table on development rows: shortfall vs calibrated ESPN in points and
#' targets, by season, with week-level standard errors.
group_ratios <- function(fr, seasons = M4_DEV) {
  d <- dplyr::filter(fr, .data$season %in% seasons)
  d |>
    dplyr::summarise(
      n = dplyr::n(),
      pts_ratio = sum(.data$actual - .data$base) / sum(.data$base),
      tgt_ratio = sum(.data$actual_targets - .data$cal_targets) / sum(.data$cal_targets),
      mean_resid = mean(.data$actual - .data$base),
      share_zero = mean(.data$actual == 0),
      seasons_negative = sum(tapply(.data$actual - .data$base, .data$season, mean) < 0),
      .by = "group"
    ) |>
    dplyr::arrange(dplyr::desc(.data$n))
}

#' Decomposition of the Questionable shortfall (development seasons):
#' availability (active), workload if active (snaps, targets), efficiency
#' (points per target) relative to pregame expectations.
questionable_decomposition <- function(fr, seasons = M4_DEV) {
  fr |>
    dplyr::filter(.data$season %in% seasons) |>
    dplyr::mutate(active = .data$roster_status %in% "ACT" | .data$has_stat_line) |>
    dplyr::summarise(
      n = dplyr::n(),
      p_active = mean(.data$active),
      pts_ratio_all = sum(.data$actual) / sum(.data$base),
      pts_ratio_if_active = sum(.data$actual[.data$active]) / sum(.data$base[.data$active]),
      tgt_ratio_if_active = sum(.data$actual_targets[.data$active]) / sum(.data$cal_targets[.data$active]),
      pts_per_tgt_if_active = sum(.data$actual[.data$active]) / max(sum(.data$actual_targets[.data$active]), 1),
      espn_pts_per_tgt = sum(.data$base[.data$active]) / sum(.data$cal_targets[.data$active]),
      .by = "group"
    ) |>
    dplyr::filter(.data$group != "other_listed") |>
    dplyr::arrange(.data$group)
}

#' How far do actual targets move toward our independent target estimate when
#' it disagrees with calibrated ESPN? Slope of (actual - ESPN) on (ours - ESPN).
disagreement_slope <- function(fr, seasons = M4_DEV) {
  d <- dplyr::filter(fr, .data$season %in% seasons) |>
    dplyr::mutate(dis = .data$our_targets - .data$cal_targets, gap = .data$actual_targets - .data$cal_targets)
  overall <- stats::coef(stats::lm(gap ~ dis, data = d))[["dis"]]
  by_season <- d |> dplyr::summarise(w = stats::coef(stats::lm(gap ~ dis))[["dis"]], .by = "season")
  list(w = overall, by_season = by_season)
}

#' What Questionable represents for availability: game-day active rates of ALL
#' listed WRs vs those inside the historical ESPN evaluation population
#' (ESPN projection > 0). Historical ESPN projections are final values that
#' already zero most game-day inactives, so the two rates differ sharply.
availability_by_population <- function(detail, rosters_weekly, espn_weekly, espn_crosswalk, player_stats,
                                       seasons = M4_DEV) {
  key <- c("season", "week", "gsis_id")
  espn <- espn_weekly |>
    dplyr::inner_join(dplyr::select(espn_crosswalk, "espn_id", "gsis_id"), by = "espn_id") |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::summarise(espn_proj = max(.data$espn_proj), .by = dplyr::all_of(key))
  ros <- dplyr::distinct(dplyr::select(rosters_weekly, dplyr::all_of(key), "roster_status"),
                         dplyr::across(dplyr::all_of(key)), .keep_all = TRUE)
  stat <- dplyr::mutate(dplyr::distinct(dplyr::select(player_stats, dplyr::all_of(key))), stat = TRUE)
  detail |>
    dplyr::filter(.data$season %in% seasons, .data$position == "WR") |>
    dplyr::left_join(ros, by = key) |>
    dplyr::left_join(espn, by = key) |>
    dplyr::left_join(stat, by = key) |>
    dplyr::mutate(group = injury_group(.data$designation, .data$practice),
                  in_espn_pop = !is.na(.data$espn_proj) & .data$espn_proj > 0,
                  active = .data$roster_status %in% "ACT" | .data$stat %in% TRUE) |>
    dplyr::summarise(n_listed = dplyr::n(), p_active_all = mean(.data$active),
                     share_in_espn_pop = mean(.data$in_espn_pop),
                     p_active_in_espn_pop = mean(.data$active[.data$in_espn_pop]),
                     inactive_outside_espn_pop = sum(!.data$active & !.data$in_espn_pop),
                     .by = "group") |>
    dplyr::filter(.data$group != "other_listed") |>
    dplyr::arrange(.data$group)
}

#' Narrow teammate-absence check on TARGETS (plan section 9): do WRs whose
#' teammates are Out/Doubtful on the pregame report (vacated target share, M3b
#' definition) get more targets than calibrated ESPN expects? Closed if not.
teammate_absence_targets <- function(fr, seasons = M4_DEV) {
  d <- dplyr::filter(fr, .data$season %in% seasons) |>
    dplyr::mutate(gap = .data$actual_targets - .data$cal_targets,
                  bin = cut(.data$vacated_target_share, c(-Inf, 0.0001, 0.10, 0.20, Inf),
                            labels = c("none", "0-0.10", "0.10-0.20", ">0.20")))
  fit <- summary(stats::lm(gap ~ vacated_target_share, data = d))$coefficients
  list(
    slope = fit["vacated_target_share", "Estimate"], se = fit["vacated_target_share", "Std. Error"],
    by_season = dplyr::summarise(d, slope = stats::coef(stats::lm(gap ~ vacated_target_share))[[2]],
                                 .by = "season"),
    by_bin = dplyr::summarise(d, n = dplyr::n(), mean_target_gap = mean(.data$gap), .by = "bin") |>
      dplyr::arrange(.data$bin)
  )
}

#' Exploratory: Questionable shortfall by broad body-part group (development).
body_part_questionable <- function(fr, seasons = M4_DEV) {
  fr |>
    dplyr::filter(.data$season %in% seasons, .data$designation == "Questionable") |>
    dplyr::summarise(n = dplyr::n(), pts_ratio = sum(.data$actual - .data$base) / sum(.data$base),
                     tgt_ratio = sum(.data$actual_targets - .data$cal_targets) / sum(.data$cal_targets),
                     .by = "body") |>
    dplyr::arrange(dplyr::desc(.data$n))
}

#' Section D: how well is opportunity (targets) predicted? Compares ESPN's raw
#' projected targets, calibrated ESPN targets, our independent target model,
#' the disagreement blend (w from development) and the availability-adjusted
#' calibrated targets (K3 ratios), by evaluation block.
target_model_table <- function(fr, p) {
  pg <- m4_param_group(fr$group, unlist(p$pooled_into_Q_pool))
  a <- unlist(p$k3_target_ratio_adj)[pg]
  d <- dplyr::mutate(fr,
    block = dplyr::case_when(.data$season %in% M4_DEV ~ "development 2020-23", .data$season == 2019 ~ "2019 (fresh)",
                             TRUE ~ "2024 (contaminated)"),
    espn_raw = dplyr::coalesce(.data$espn_proj_targets, 0),
    blend = .data$cal_targets + p$k4_w * (.data$our_targets - .data$cal_targets),
    availability_adjusted = .data$cal_targets * (1 + ifelse(is.na(a), 0, a))
  )
  long <- tidyr::pivot_longer(d, c("espn_raw", "cal_targets", "our_targets", "blend", "availability_adjusted"),
                              names_to = "target_model", values_to = "pred_targets")
  dplyr::bind_rows(
    dplyr::mutate(long, rows = "all"),
    dplyr::mutate(dplyr::filter(long, .data$group %in% M4_ADJ_GROUPS), rows = "injury-affected")
  ) |>
    dplyr::summarise(n = dplyr::n(), mae = mean(abs(.data$pred_targets - .data$actual_targets)),
                     rmse = sqrt(mean((.data$pred_targets - .data$actual_targets)^2)),
                     bias = mean(.data$pred_targets - .data$actual_targets),
                     .by = c("block", "rows", "target_model"))
}

#' Section J: the primary M4 model and M3b against RAW ESPN (paired bootstrap).
m4_vs_raw <- function(fr, preds, seasons_list = list(development = M4_DEV, `2019` = 2019, `2024` = 2024)) {
  raw <- dplyr::transmute(fr, .data$season, .data$week, .data$gsis_id, .data$actual, model = "ESPN_raw",
                          pred = .data$espn_proj)
  long <- dplyr::bind_rows(raw, dplyr::select(dplyr::filter(preds, .data$model %in% c("B0", "B1", "K2")),
                                              "season", "week", "gsis_id", "actual", "model", "pred"))
  purrr::imap(seasons_list, function(s, nm) {
    d <- dplyr::filter(long, .data$season %in% s)
    purrr::map(c("B0", "B1", "K2"), ~ pooled_bootstrap(d, .x, "ESPN_raw")) |>
      purrr::list_rbind() |>
      dplyr::mutate(block = nm)
  }) |>
    purrr::list_rbind()
}
