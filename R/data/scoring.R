# Fantasy scoring ----------------------------------------------------------------
# Scoring systems live in config/scoring/<name>.yml as named weights on stat
# columns, so new league formats need a new YAML file, not new code.

read_scoring_rules <- function(system = "espn_ppr", dir = "config/scoring") {
  path <- file.path(dir, paste0(system, ".yml"))
  if (!file.exists(path)) cli::cli_abort("Scoring system {.file {path}} not found.")
  rules <- yaml::read_yaml(path)
  w <- unlist(rules$weights)
  if (is.null(w) || !is.numeric(w) || anyNA(w) || any(names(w) == "")) {
    cli::cli_abort("{.file {path}}: `weights` must be a named list of numbers.")
  }
  rules$weights <- w
  rules$system <- system
  rules
}

#' Fantasy points for each row of `stats` under `rules`.
#'
#' Every stat named in the rules must exist as a column (fails loudly rather
#' than silently scoring a missing stat as zero). NA stat values count as 0,
#' matching how nflverse leaves stats a player did not record.
score_fantasy_points <- function(stats, rules) {
  w <- rules$weights
  missing_cols <- setdiff(names(w), names(stats))
  if (length(missing_cols) > 0) {
    cli::cli_abort("Stats are missing scoring column{?s}: {.val {missing_cols}}.")
  }
  pts <- numeric(nrow(stats))
  for (stat in names(w)) {
    v <- as.numeric(stats[[stat]])
    v[is.na(v)] <- 0
    pts <- pts + w[[stat]] * v
  }
  round(pts, 2)
}
