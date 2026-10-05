# Milestone 2 model specifications ---------------------------------------------------
# Same spec interface as R/models/models.R: list(name, features, fit, predict).
# Everything is fit to the conditional MEAN (squared error), so MAE gains can't
# come from switching to median targeting. All preprocessing is learned from
# training rows only.

ESPN_COMPONENTS <- c("espn_proj", "espn_proj_receptions", "espn_proj_targets",
                     "espn_proj_receiving_yards", "espn_proj_receiving_tds", "espn_proj_rushing_yards")

# --- Calibrated ESPN family (ESPN-only information) ------------------------------------

#' Approximate week counter used for recency weights.
week_clock <- function(season, week) (season - 2000) * 18 + week

spec_cal <- function(type = c("linear", "spline", "components", "components_recency")) {
  type <- match.arg(type)
  form <- switch(type,
    linear = actual ~ espn_proj,
    spline = actual ~ splines::ns(espn_proj, df = 4),
    components = , components_recency = stats::reformulate(ESPN_COMPONENTS, "actual")
  )
  feats <- if (type %in% c("components", "components_recency")) ESPN_COMPONENTS else "espn_proj"
  list(
    name = paste0("cal_", type), features = feats,
    fit = function(train) {
      if (type != "components_recency") return(stats::lm(form, data = train))
      age <- max(week_clock(train$season, train$week)) - week_clock(train$season, train$week)
      train$.w <- 0.5^(age / 17)                # half-life: one season
      # lm() evaluates `weights` inside `data`, so the weights live there.
      stats::lm(form, data = train, weights = .w)
    },
    predict = function(fit, newdata) unname(stats::predict(fit, newdata = newdata))
  )
}

# --- Linear / elastic net ------------------------------------------------------------------

#' Linear model with median imputation (explicit missingness indicators are
#' part of FEATURES_M2, so no automatic duplicate indicators are created).
spec_m2_linear <- function(name, features, penalty = NULL, mixture = 0.5) {
  list(
    name = name, features = features, penalty = penalty, mixture = mixture,
    fit = function(train) {
      d <- model_frame(train, features)
      rec <- recipes::recipe(actual ~ ., data = d) |>
        recipes::step_impute_median(recipes::all_numeric_predictors()) |>
        recipes::step_zv(recipes::all_predictors()) |>
        recipes::step_normalize(recipes::all_numeric_predictors())
      mod <- if (is.null(penalty)) {
        parsnip::linear_reg() |> parsnip::set_engine("lm")
      } else {
        path <- sort(unique(c(10^seq(-5, 2, length.out = 71), penalty)), decreasing = TRUE)
        parsnip::linear_reg(penalty = penalty, mixture = mixture) |>
          parsnip::set_engine("glmnet", path_values = path)
      }
      workflows::workflow(rec, mod) |> parsnip::fit(data = d)
    },
    predict = function(fit, newdata) stats::predict(fit, new_data = model_frame(newdata, features))$.pred
  )
}

# --- Gradient boosting ------------------------------------------------------------------------

XGB_FIXED <- list(objective = "reg:squarederror", eta = 0.03, subsample = 0.8,
                  colsample_bytree = 0.8, min_child_weight = 20, nthread = 4, seed = 20261005)

xgb_matrix <- function(df, features) {
  x <- as.matrix(dplyr::mutate(df[, features], dplyr::across(dplyr::everything(), as.numeric)))
  x
}

#' XGBoost regressor. Missing values are handled natively. Seeds and thread
#' count are fixed so frozen models reproduce exactly.
spec_xgb <- function(name, features, max_depth = 3, nrounds = 300) {
  list(
    name = name, features = features, max_depth = max_depth, nrounds = nrounds,
    fit = function(train) {
      d <- xgboost::xgb.DMatrix(xgb_matrix(train, features), label = train$actual, missing = NA)
      xgboost::xgb.train(params = c(XGB_FIXED, list(max_depth = max_depth)), data = d,
                         nrounds = nrounds, verbose = 0)
    },
    predict = function(fit, newdata) {
      stats::predict(fit, xgboost::xgb.DMatrix(xgb_matrix(newdata, features), missing = NA))
    }
  )
}

# --- Residual on calibrated ESPN ---------------------------------------------------------

#' Prediction = calibrated ESPN + a model of what calibrated ESPN misses.
#' Both parts are fitted on the training rows only; the residual model never
#' sees ESPN directly, so it can only add information ESPN's level lacks.
spec_residual <- function(name, base_spec, resid_spec) {
  list(
    name = name, features = unique(c(base_spec$features, resid_spec$features)),
    fit = function(train) {
      b <- base_spec$fit(train)
      r <- train
      r$actual <- train$actual - base_spec$predict(b, train)
      list(base = b, resid = resid_spec$fit(r))
    },
    predict = function(fit, newdata) {
      base_spec$predict(fit$base, newdata) + resid_spec$predict(fit$resid, newdata)
    }
  )
}

# --- Registry builders for the M2 lineage ------------------------------------------------

registry_spec_cal <- function(m, id) spec_cal(m$calibration)
registry_spec_m2_linear <- function(m, id) spec_m2_linear(id, unlist(m$features), m$penalty, m$mixture %||% 0.5)
registry_spec_xgb <- function(m, id) spec_xgb(id, unlist(m$features), m$max_depth, m$nrounds)
registry_spec_residual <- function(m, id) {
  base <- spec_cal(m$calibration)
  resid <- switch(m$residual_model,
    m2_linear = spec_m2_linear(paste0(id, "_resid"), unlist(m$features), m$penalty, m$mixture %||% 0.5),
    xgb = spec_xgb(paste0(id, "_resid"), unlist(m$features), m$max_depth, m$nrounds)
  )
  spec_residual(id, base, resid)
}
