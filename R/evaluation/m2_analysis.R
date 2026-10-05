# Milestone 2 analysis: development summaries, ablations, residual study --------------

#' Attach pregame subset flags and restrict to player-weeks every model predicted.
m2_aligned <- function(preds, frame) {
  flags <- dplyr::select(frame, "season", "week", "gsis_id", "relevant", "startable", "espn_rank")
  preds |>
    dplyr::select(-dplyr::any_of(c("relevant", "startable", "espn_rank"))) |>
    align_predictions() |>
    dplyr::left_join(flags, by = c("season", "week", "gsis_id"))
}

#' Metrics pooled and by season for each pre-specified subset.
m2_metric_tables <- function(aligned) {
  subsets <- list(all = aligned,
                  relevant = dplyr::filter(aligned, .data$relevant),
                  startable = dplyr::filter(aligned, .data$startable))
  purrr::imap(subsets, function(d, s) {
    dplyr::bind_rows(
      dplyr::mutate(summarise_m2(d), season = "pooled"),
      dplyr::mutate(summarise_m2(d, "season"), season = as.character(.data$season))
    ) |> dplyr::mutate(subset = s)
  }) |>
    purrr::list_rbind()
}

#' Paired season-stratified bootstraps of each model against each benchmark.
m2_comparisons <- function(aligned, models, benchmarks, reps, seed) {
  tidyr::expand_grid(model = models, baseline = benchmarks, subset = c("all", "relevant", "startable")) |>
    dplyr::filter(.data$model != .data$baseline) |>
    purrr::pmap(function(model, baseline, subset) {
      d <- if (subset == "all") aligned else dplyr::filter(aligned, .data[[subset]])
      dplyr::mutate(pooled_bootstrap(d, model, baseline, reps, seed), subset = subset)
    }) |>
    purrr::list_rbind()
}

m2_seasonal <- function(aligned, models, baseline) {
  purrr::map(setdiff(models, baseline), ~ seasonal_deltas(aligned, .x, baseline)) |> purrr::list_rbind()
}

#' Descriptive feature-family ablations (static development folds): drop one
#' family at a time from a selected model and report the change in pooled MAE.
#' Positive delta = the family helped. NOT used to select features (E3).
ablation_study <- function(dev, tuning, cal, model_name, m2_cfg) {
  run <- function(features) {
    spec <- m2_candidate_specs(tuning, cal, features)[[model_name]]
    p <- static_season_folds(dev, spec, unlist(m2_cfg$dev_seasons), m2_cfg$first_train_season)
    dplyr::summarise(p, mae = mean(abs(.data$pred - .data$actual)), rmse = sqrt(mean((.data$pred - .data$actual)^2)))
  }
  full <- run(FEATURES_M2)
  purrr::imap(M2_FAMILIES, function(fam, name) {
    r <- run(setdiff(FEATURES_M2, fam))
    tibble::tibble(model = model_name, family = name, n_features = length(fam),
                   mae_without = r$mae, mae_full = full$mae, delta_mae = r$mae - full$mae,
                   delta_rmse = r$rmse - full$rmse)
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(dplyr::desc(.data$delta_mae))
}

#' Temporal-representation comparison (OLS, static development folds): the
#' same base features with different ways of summarising player history.
representation_study <- function(dev, m2_cfg) {
  base <- c("season_pts_mean", "prev_season_pts_mean", "log_career_games", "played_team_prev_game",
            "no_prev_season", "no_season_games", "log_draft_pick", "undrafted", "home")
  reps <- list(
    m1_trailing_3_8 = c("fantasy_pts_roll3", "fantasy_pts_roll8", "targets_roll3", "targets_roll8",
                        "target_share_roll8", "snap_share_roll3"),
    trailing_1_2_4_8 = c("fantasy_pts_roll1", "fantasy_pts_roll8", "targets_roll2", "targets_roll4",
                         "targets_roll8", "target_share_roll8", "snap_share_roll3"),
    ewma_2_6 = c("fantasy_pts_ewma2", "fantasy_pts_ewma6", "targets_ewma2", "targets_ewma6",
                 "target_share_ewma2", "target_share_ewma6", "snap_share_ewma2", "snap_share_ewma6"),
    ewma_plus_trend = c("fantasy_pts_ewma2", "fantasy_pts_ewma6", "targets_ewma2", "targets_ewma6",
                        "target_share_ewma2", "target_share_ewma6", "snap_share_ewma2", "snap_share_ewma6",
                        "target_share_trend", "snap_share_trend", "fantasy_pts_sd8")
  )
  purrr::imap(reps, function(f, name) {
    spec <- spec_m2_linear(name, c(base, f))
    p <- static_season_folds(dev, spec, unlist(m2_cfg$dev_seasons), m2_cfg$first_train_season)
    tibble::tibble(representation = name, n_features = length(f),
                   mae = mean(abs(p$pred - p$actual)), rmse = sqrt(mean((p$pred - p$actual)^2)))
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(.data$mae)
}

#' Exploratory residual study on the development folds: what does calibrated
#' ESPN systematically miss? Residual = actual - calibrated ESPN (rolling).
#' Uncertainty uses week-level means (weeks as the independent unit).
residual_study <- function(cal_preds, cal_model, dev) {
  d <- cal_preds |>
    dplyr::filter(.data$model == cal_model) |>
    dplyr::select("season", "week", "gsis_id", "pred", "actual") |>
    dplyr::inner_join(dev, by = c("season", "week", "gsis_id"), suffix = c("", ".dev")) |>
    dplyr::mutate(resid = .data$actual - .data$pred)
  q <- function(x, k) dplyr::ntile(x, k)
  groupings <- list(
    projection_bucket = cut(d$espn_proj, PROJECTION_BUCKETS, right = FALSE),
    target_share_trend_q5 = q(d$target_share_trend, 5),
    snap_share_trend_q5 = q(d$snap_share_trend, 5),
    xfp_trend_q5 = q(d$xfp_trend, 5),
    fpoe_shrunk_q5 = q(d$fpoe_shrunk, 5),
    years_exp = cut(d$years_exp, c(-Inf, 0, 1, 2, 5, Inf), labels = c("rookie", "2nd", "3rd", "4-6th", "7th+")),
    qb_changed_last_game = d$qb_changed_last_game,
    changed_team = d$changed_team,
    team_neutral_pass_rate_q3 = q(d$team_neutral_pass_rate_ewma, 3),
    played_team_prev_game = d$played_team_prev_game
  )
  purrr::imap(groupings, function(g, name) {
    dd <- dplyr::mutate(d, group = as.character(g)) |> dplyr::filter(!is.na(.data$group))
    wk <- dplyr::summarise(dd, r = mean(.data$resid), .by = c("group", "season", "week"))
    dplyr::summarise(wk, mean_resid = mean(.data$r), se = stats::sd(.data$r) / sqrt(dplyr::n()), weeks = dplyr::n(),
                     .by = "group") |>
      dplyr::left_join(dplyr::count(dd, .data$group, name = "n"), by = "group") |>
      dplyr::mutate(factor = name, ci_low = .data$mean_resid - 1.96 * .data$se,
                    ci_high = .data$mean_resid + 1.96 * .data$se, .before = 1)
  }) |>
    purrr::list_rbind()
}
