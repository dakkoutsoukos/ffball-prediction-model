# Milestone 3 component research track ----------------------------------------------------
# Diagnostic, development seasons only (static season folds 2020-2023): where do
# projections differ from ESPN, component by component, and where does
# calibrated ESPN's error come from? Not used to select any challenger.

COMPONENTS <- tibble::tribble(
  ~component,          ~actual_col,               ~espn_col,                    ~points_weight,
  "targets",           "actual_targets",          "espn_proj_targets",          0,
  "receptions",        "actual_receptions",       "espn_proj_receptions",       1,
  "receiving_yards",   "actual_receiving_yards",  "espn_proj_receiving_yards",  0.1,
  "receiving_tds",     "actual_receiving_tds",    "espn_proj_receiving_tds",    6
)

#' Component predictions under four information levels, static season folds.
component_predictions <- function(dev, m2_cfg) {
  d <- dplyr::mutate(dev, dplyr::across(c("actual_targets", "actual_receptions", "actual_receiving_yards",
                                          "actual_receiving_tds"), ~ dplyr::coalesce(.x, 0)))
  purrr::pmap(COMPONENTS, function(component, actual_col, espn_col, points_weight) {
    dd <- dplyr::mutate(d, actual = .data[[actual_col]])
    specs <- list(
      espn_raw = list(name = "espn_raw", features = espn_col, fit = function(train) NULL,
                      predict = function(fit, nd) nd[[espn_col]]),
      espn_cal = spec_m2_linear("espn_cal", espn_col),
      ours_no_espn = spec_m2_linear("ours_no_espn", FEATURES_M2),
      espn_plus_ours = spec_m2_linear("espn_plus_ours", c(espn_col, FEATURES_M2))
    )
    purrr::map(specs, function(s) {
      static_season_folds(dd, s, unlist(m2_cfg$dev_seasons), m2_cfg$first_train_season) |>
        dplyr::mutate(component = component, level = s$name)
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}

#' Accuracy by component and information level, with the paired week-bootstrap
#' comparison of ESPN + ours vs calibrated ESPN for each component.
component_summary <- function(cp, reps = 1000, seed = 1) {
  acc <- cp |>
    dplyr::summarise(n = dplyr::n(), mae = mean(abs(.data$pred - .data$actual)),
                     rmse = sqrt(mean((.data$pred - .data$actual)^2)), bias = mean(.data$pred - .data$actual),
                     .by = c("component", "level"))
  inc <- purrr::map(unique(cp$component), function(cmp) {
    d <- dplyr::filter(cp, .data$component == cmp) |> dplyr::mutate(model = .data$level)
    dplyr::mutate(pooled_bootstrap(d, "espn_plus_ours", "espn_cal", reps, seed), component = cmp)
  }) |>
    purrr::list_rbind()
  list(accuracy = acc, incremental = inc)
}

#' Decompose calibrated ESPN's points error into component errors (in points),
#' and measure whether OUR disagreement with ESPN on each component points in
#' the direction of the realised error.
component_decomposition <- function(cp) {
  w <- dplyr::select(COMPONENTS, "component", "points_weight")
  wide <- cp |>
    dplyr::filter(.data$level %in% c("espn_cal", "ours_no_espn")) |>
    dplyr::select("season", "week", "gsis_id", "component", "level", "pred", "actual") |>
    tidyr::pivot_wider(names_from = "level", values_from = "pred") |>
    dplyr::left_join(w, by = "component") |>
    dplyr::mutate(err_pts = (.data$actual - .data$espn_cal) * .data$points_weight,
                  disagree_pts = (.data$ours_no_espn - .data$espn_cal) * .data$points_weight)
  scored <- dplyr::filter(wide, .data$points_weight > 0)
  total_var <- scored |>
    dplyr::summarise(e = sum(.data$err_pts), .by = c("season", "week", "gsis_id")) |>
    dplyr::summarise(v = stats::var(.data$e)) |>
    dplyr::pull("v")
  scored |>
    dplyr::summarise(
      err_sd_pts = stats::sd(.data$err_pts),
      share_of_error_variance = stats::var(.data$err_pts) / total_var,
      disagreement_sd_pts = stats::sd(.data$disagree_pts),
      # slope of realised error on our disagreement: 1 = our disagreement is
      # fully right, 0 = uninformative, < 0 = we disagree in the wrong direction
      disagreement_slope = stats::coef(stats::lm(err_pts ~ disagree_pts))[[2]],
      .by = "component"
    )
}
