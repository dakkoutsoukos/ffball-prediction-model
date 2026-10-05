# Data validation helpers ------------------------------------------------------
# These fail loudly (cli_abort) on integrity problems. Each returns its input
# invisibly so it can be used inside a pipe.

assert_unique_key <- function(df, keys, what = "data") {
  dup <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = ".n") |>
    dplyr::filter(.data$.n > 1)
  if (nrow(dup) > 0) {
    cli::cli_abort(c(
      "{what}: {nrow(dup)} duplicated key{?s} on ({.val {keys}}).",
      "i" = "First: {paste(format(dup[1, keys]), collapse = ', ')}"
    ))
  }
  invisible(df)
}

assert_no_missing <- function(df, cols, what = "data") {
  n_na <- vapply(cols, function(c) sum(is.na(df[[c]])), integer(1))
  if (any(n_na > 0)) {
    bad <- n_na[n_na > 0]
    cli::cli_abort("{what}: missing values in {.val {names(bad)}} ({bad} row{?s}).")
  }
  invisible(df)
}

assert_in_range <- function(df, col, lower = -Inf, upper = Inf, what = "data") {
  x <- df[[col]]
  bad <- !is.na(x) & (x < lower | x > upper)
  if (any(bad)) {
    cli::cli_abort(
      "{what}: {sum(bad)} value{?s} of {.field {col}} outside [{lower}, {upper}] (e.g. {x[bad][1]})."
    )
  }
  invisible(df)
}

assert_values_in <- function(df, col, allowed, what = "data") {
  bad <- setdiff(unique(df[[col]]), allowed)
  if (length(bad) > 0) {
    cli::cli_abort("{what}: unexpected {.field {col}} value{?s}: {.val {bad}}.")
  }
  invisible(df)
}

#' Left join that fails loudly if it would duplicate rows of `x`.
#'
#' `y` must be unique on `by`. Unmatched rows of `x` are allowed but counted
#' and reported; set `max_unmatched_frac` to fail when too many go unmatched.
safe_left_join <- function(x, y, by, what = "join", max_unmatched_frac = 1) {
  out <- dplyr::left_join(x, y, by = by, relationship = "many-to-one")
  if (nrow(out) != nrow(x)) {
    cli::cli_abort("{what}: row count changed from {nrow(x)} to {nrow(out)}.")
  }
  matched <- dplyr::semi_join(x, y, by = by)
  frac_unmatched <- 1 - nrow(matched) / max(nrow(x), 1)
  if (frac_unmatched > max_unmatched_frac) {
    cli::cli_abort(
      "{what}: {round(100 * frac_unmatched, 1)}% of rows unmatched (limit {100 * max_unmatched_frac}%)."
    )
  }
  attr(out, "unmatched_frac") <- frac_unmatched
  out
}

#' One row per column: count and share of missing values.
missingness_report <- function(df) {
  tibble::tibble(
    column = names(df),
    n = nrow(df),
    n_missing = vapply(df, function(x) sum(is.na(x)), integer(1)),
    pct_missing = round(100 * .data$n_missing / pmax(.data$n, 1), 2)
  ) |>
    dplyr::arrange(dplyr::desc(.data$n_missing))
}
