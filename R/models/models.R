# Model specifications --------------------------------------------------------------
# A model spec is a list with:
#   name      unique id used in prediction tables
#   features  character vector of predictor columns (may be empty)
#   fit       function(train) -> fitted object (sees only training rows)
#   predict   function(fitted, newdata) -> numeric vector
# All preprocessing (imputation, indicators, scaling) is estimated inside `fit`
# from training rows only, so it cannot leak validation/test information.

#' ESPN's own projection, unchanged: the benchmark.
spec_espn <- function() {
  list(
    name = "espn", features = "espn_proj",
    fit = function(train) NULL,
    predict = function(fit, newdata) newdata$espn_proj
  )
}

#' Naive history baseline: trailing k-game mean of fantasy points, then the
#' previous-season mean, then the training mean for players with no history.
spec_naive <- function(k = 8) {
  roll <- paste0("fantasy_pts_roll", k)
  list(
    name = paste0("naive_roll", k), features = c(roll, "prev_season_pts_mean"),
    fit = function(train) list(no_history_mean = mean(train$actual[!train$has_history])),
    predict = function(fit, newdata) {
      dplyr::coalesce(newdata[[roll]], newdata$prev_season_pts_mean, fit$no_history_mean)
    }
  )
}

#' Linear recalibration of ESPN: actual ~ a + b * espn_proj.
#' loss = "l2" (least squares, targets the conditional mean) or
#' "l1" (least absolute deviations, targets the conditional median - which is
#' what minimises MAE for a right-skewed outcome; a diagnostic, see docs).
spec_espn_recal <- function(loss = c("l2", "l1")) {
  loss <- match.arg(loss)
  list(
    name = paste0("espn_recal_", loss), features = "espn_proj",
    fit = function(train) {
      ols <- stats::coef(stats::lm(actual ~ espn_proj, data = train))
      if (loss == "l2") return(ols)
      obj <- function(b) mean(abs(train$actual - b[1] - b[2] * train$espn_proj))
      stats::optim(ols, obj, method = "Nelder-Mead", control = list(maxit = 2000))$par
    },
    predict = function(fit, newdata) unname(fit[1] + fit[2] * newdata$espn_proj)
  )
}

#' Linear model (OLS, or ridge/lasso via glmnet) on point-in-time features
#' using a tidymodels workflow. Missing features are median-imputed with
#' missingness indicators; numeric predictors are standardised.
spec_linear <- function(name, features, penalty = NULL, mixture = 0) {
  list(
    name = name, features = features, penalty = penalty,
    fit = function(train) {
      d <- model_frame(train, features)
      rec <- recipes::recipe(actual ~ ., data = d) |>
        recipes::step_indicate_na(recipes::all_predictors()) |>
        recipes::step_impute_median(recipes::all_numeric_predictors()) |>
        recipes::step_zv(recipes::all_predictors()) |>
        recipes::step_normalize(recipes::all_numeric_predictors())
      mod <- if (is.null(penalty)) {
        parsnip::linear_reg() |> parsnip::set_engine("lm")
      } else {
        # glmnet's default lambda path can stop above small penalties, in which
        # case predictions silently use the path's smallest lambda (more
        # shrinkage than requested). Supplying an explicit path that contains
        # the requested penalty makes predictions exact.
        path <- sort(unique(c(10^seq(-5, 2, length.out = 71), penalty)), decreasing = TRUE)
        parsnip::linear_reg(penalty = penalty, mixture = mixture) |>
          parsnip::set_engine("glmnet", path_values = path)
      }
      workflows::workflow(rec, mod) |> parsnip::fit(data = d)
    },
    predict = function(fit, newdata) {
      stats::predict(fit, new_data = model_frame(newdata, features))$.pred
    }
  )
}

#' Predictor frame with logicals coerced to 0/1 (plus `actual` when present).
model_frame <- function(df, features) {
  missing <- setdiff(features, names(df))
  if (length(missing) > 0) cli::cli_abort("Missing feature column{?s}: {.val {missing}}.")
  cols <- intersect(c("actual", features), names(df))
  dplyr::mutate(df[, cols], dplyr::across(dplyr::where(is.logical), as.numeric))
}

# --- Feature sets (pre-declared; see research/experiment_log.md) --------------

FEATURES_HISTORY <- c(
  "fantasy_pts_roll3", "fantasy_pts_roll8", "season_pts_mean", "prev_season_pts_mean",
  "log_career_games", "played_team_prev_game", "changed_team"
)
FEATURES_USAGE <- c(
  "targets_roll3", "targets_roll8", "target_share_roll8", "air_yards_share_roll8",
  "snap_share_roll3", "rz_targets_roll8", "xfp_roll8", "team_pass_att_roll8"
)
FEATURES_MATCHUP <- c("home", "opp_pts_allowed_roll")
FEATURES_VEGAS <- c("implied_team_total", "team_spread", "total_line")
FEATURES_INJURY <- c("inj_questionable", "inj_doubtful")
