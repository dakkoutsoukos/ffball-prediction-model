# Milestone 2 orchestration helpers (used by _targets.R) ------------------------------

assert_no_leakage_m2 <- function(base, histories, static, n_cutoffs = 12) {
  targets <- dplyr::filter(base, .data$has_game) |>
    dplyr::select("season", "week", "gsis_id", "team", "opponent", "home", "rest_days")
  leaks <- check_leakage_generic(targets, histories, static, add_m2_features, n_cutoffs = n_cutoffs)
  if (length(leaks) > 0) cli::cli_abort("M2 feature leakage detected in: {.val {leaks}}.")
  tibble::tibble(checked_at = Sys.time(), n_cutoffs = n_cutoffs, leaking_features = 0L,
                 histories = paste(names(histories), collapse = ","))
}

calibration_specs <- function() {
  purrr::map(c("linear", "spline", "components", "components_recency"), spec_cal)
}

#' Reference models evaluated under the M2 protocol for context.
reference_specs <- function() {
  list(
    spec_espn(),
    spec_naive(8),
    spec_linear("m1spec_no_espn", feature_set("usage"))   # M1's ESPN-free spec, M2 protocol
  )
}

ENET_GRID <- 10^seq(-3, 0, length.out = 7)
XGB_GRID <- tidyr::expand_grid(max_depth = c(3, 5), nrounds = c(300, 600))

#' Tune the pre-declared grids on static development folds. `cal` is the
#' selected calibration spec (base of the residual models).
tune_m2 <- function(dev, m2_cfg, cal) {
  aug_feats <- c(ESPN_COMPONENTS, FEATURES_M2)
  grids <- list(
    nf_enet = purrr::map(ENET_GRID, ~ spec_m2_linear(paste0("nf_enet_", .x), FEATURES_M2, penalty = .x)),
    aug_resid_enet = purrr::map(ENET_GRID, ~ spec_residual(
      paste0("aug_resid_enet_", .x), cal, spec_m2_linear("r", FEATURES_M2, penalty = .x))),
    nf_xgb = purrr::pmap(XGB_GRID, function(max_depth, nrounds)
      spec_xgb(paste0("nf_xgb_d", max_depth, "_n", nrounds), FEATURES_M2, max_depth, nrounds)),
    aug_xgb = purrr::pmap(XGB_GRID, function(max_depth, nrounds)
      spec_xgb(paste0("aug_xgb_d", max_depth, "_n", nrounds), aug_feats, max_depth, nrounds)),
    aug_resid_xgb = purrr::pmap(XGB_GRID, function(max_depth, nrounds)
      spec_residual(paste0("aug_resid_xgb_d", max_depth, "_n", nrounds), cal,
                    spec_xgb("r", FEATURES_M2, max_depth, nrounds)))
  )
  purrr::imap(grids, function(specs, family) {
    res <- tune_grid(dev, specs, m2_cfg)
    params <- if (grepl("enet", family)) tibble::tibble(penalty = ENET_GRID) else XGB_GRID
    dplyr::bind_cols(res, params) |> dplyr::mutate(family = family)
  })
}

best_params <- function(tuning, family) {
  t <- tuning[[family]]
  as.list(t[which.min(t$mae), setdiff(names(t), c("name", "mae", "rmse", "family"))])
}

#' The pre-registered M2 candidates with tuned hyperparameters.
m2_candidate_specs <- function(tuning, cal) {
  aug_feats <- c(ESPN_COMPONENTS, FEATURES_M2)
  p_nf_enet <- best_params(tuning, "nf_enet")
  p_r_enet <- best_params(tuning, "aug_resid_enet")
  p_nf_xgb <- best_params(tuning, "nf_xgb")
  p_aug_xgb <- best_params(tuning, "aug_xgb")
  p_r_xgb <- best_params(tuning, "aug_resid_xgb")
  specs <- list(
    spec_m2_linear("nf_ols", FEATURES_M2),
    spec_m2_linear("nf_enet", FEATURES_M2, penalty = p_nf_enet$penalty),
    spec_xgb("nf_xgb", FEATURES_M2, p_nf_xgb$max_depth, p_nf_xgb$nrounds),
    spec_m2_linear("aug_ols", aug_feats),
    spec_residual("aug_resid_enet", cal, spec_m2_linear("r", FEATURES_M2, penalty = p_r_enet$penalty)),
    spec_residual("aug_resid_xgb", cal, spec_xgb("r", FEATURES_M2, p_r_xgb$max_depth, p_r_xgb$nrounds)),
    spec_xgb("aug_xgb", aug_feats, p_aug_xgb$max_depth, p_aug_xgb$nrounds)
  )
  rlang::set_names(specs, purrr::map_chr(specs, "name"))
}

NF_CANDIDATES <- c("nf_ols", "nf_enet", "nf_xgb")
AUG_CANDIDATES <- c("aug_ols", "aug_resid_enet", "aug_resid_xgb", "aug_xgb")
