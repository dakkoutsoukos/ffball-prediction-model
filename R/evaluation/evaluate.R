# Evaluation of backtest predictions -----------------------------------------------

PROJECTION_BUCKETS <- c(0, 5, 10, 15, Inf)

#' Metrics on identical observations, overall and by subgroup, plus paired
#' week-clustered bootstrap comparisons against the benchmark.
evaluate_predictions <- function(preds, model_data, eval_cfg) {
  keys <- c("season", "week", "gsis_id")
  info <- dplyr::select(model_data, dplyr::all_of(keys), "relevant")
  baseline <- if ("espn" %in% preds$model) "espn" else "naive_roll8"

  per_protocol <- purrr::map(split(preds, preds$protocol), function(p) {
    aligned <- align_predictions(p) |>
      dplyr::left_join(info, by = keys) |>
      dplyr::mutate(proj_bucket = cut(.data$espn_proj, PROJECTION_BUCKETS, right = FALSE))
    list(
      n_kept = attr(aligned, "n_kept") %||% NA, n_dropped = attr(aligned, "n_dropped") %||% NA,
      aligned = aligned
    )
  })
  aligned <- purrr::map(per_protocol, "aligned") |> purrr::list_rbind()

  overall <- summarise_metrics(aligned, by = c("protocol", "season"))
  relevant <- summarise_metrics(dplyr::filter(aligned, .data$relevant), by = c("protocol", "season"))
  by_bucket <- if (all(is.na(aligned$espn_proj))) tibble::tibble() else
    summarise_metrics(aligned, by = c("protocol", "season", "proj_bucket"))
  by_week <- aligned |>
    dplyr::summarise(mae = mean(abs(.data$pred - .data$actual)),
                     bias = mean(.data$pred - .data$actual), n = dplyr::n(),
                     .by = c("protocol", "season", "week", "model"))
  residuals <- aligned |>
    dplyr::mutate(err = .data$pred - .data$actual) |>
    dplyr::summarise(
      q05 = stats::quantile(.data$err, 0.05), q25 = stats::quantile(.data$err, 0.25),
      q50 = stats::median(.data$err), q75 = stats::quantile(.data$err, 0.75),
      q95 = stats::quantile(.data$err, 0.95), share_over = mean(.data$err > 0),
      .by = c("protocol", "season", "model")
    )

  bootstrap <- tidyr::expand_grid(
    protocol = unique(aligned$protocol),
    model = setdiff(unique(aligned$model), baseline)
  ) |>
    purrr::pmap(function(protocol, model) {
      d <- dplyr::filter(aligned, .data$protocol == !!protocol)
      out <- paired_bootstrap_mae(d, model, baseline, eval_cfg$bootstrap_reps, eval_cfg$seed) |>
        dplyr::mutate(subset = "all")
      rel <- dplyr::filter(d, .data$relevant %in% TRUE)
      if (nrow(rel) > 0) {
        out <- dplyr::bind_rows(out, dplyr::mutate(
          paired_bootstrap_mae(rel, model, baseline, eval_cfg$bootstrap_reps, eval_cfg$seed),
          subset = "relevant"
        ))
      }
      dplyr::mutate(out, protocol = protocol)
    }) |>
    purrr::list_rbind()

  list(
    baseline = baseline,
    population = unique(model_data$population),
    alignment = purrr::imap(per_protocol, ~ tibble::tibble(protocol = .y, n_kept = .x$n_kept, n_dropped = .x$n_dropped)) |>
      purrr::list_rbind(),
    overall = overall, relevant = relevant, by_bucket = by_bucket, by_week = by_week,
    residuals = residuals, bootstrap = bootstrap
  )
}

#' Apply the pre-registered selection rule using validation results only:
#' lowest rolling-origin MAE among non-benchmark, non-diagnostic candidates.
select_primary_model <- function(eval_validation, splits) {
  tab <- eval_validation$overall |>
    dplyr::filter(.data$protocol == "rolling", .data$season == splits$validation_season,
                  !.data$model %in% c("espn", DIAGNOSTIC_MODELS, EXPLORATORY_MODELS)) |>
    dplyr::arrange(.data$mae)
  list(model = tab$model[[1]], table = tab)
}

#' The single pre-registered headline comparison on the test season.
headline_result <- function(eval_test, model_selection) {
  m <- model_selection$model
  base <- eval_test$baseline
  boot <- dplyr::filter(eval_test$bootstrap, .data$protocol == "rolling", .data$model == m)
  ov <- dplyr::filter(eval_test$overall, .data$protocol == "rolling", .data$model %in% c(m, base))
  rmse_ok <- ov$rmse[ov$model == m] <= ov$rmse[ov$model == base]
  all_boot <- dplyr::filter(boot, .data$subset == "all")
  list(
    primary_model = m, baseline = base, metrics = ov, bootstrap = boot,
    beats_baseline = nrow(all_boot) == 1 && all_boot$ci_high < 0 && rmse_ok
  )
}
