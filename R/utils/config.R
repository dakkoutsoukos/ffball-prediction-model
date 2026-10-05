# Project configuration ------------------------------------------------------

#' Read and lightly validate config/project.yml.
#'
#' A git-ignored `config/local.yml`, if present, is deep-merged on top. It
#' holds machine- or owner-specific choices that must not be published, such
#' as opting in to ESPN fetching (`espn: {enabled: true}`).
read_project_config <- function(path = "config/project.yml",
                                local_path = file.path(dirname(path), "local.yml")) {
  cfg <- yaml::read_yaml(path)
  if (file.exists(local_path)) cfg <- utils::modifyList(cfg, yaml::read_yaml(local_path))
  cfg$seasons_all <- seq.int(cfg$seasons$first, cfg$seasons$last)

  s <- cfg$splits
  stopifnot(
    "splits must be strictly chronological" =
      s$first_train_season <= s$train_last_season &&
      s$train_last_season < s$validation_season &&
      s$validation_season < s$test_season,
    "test season must be ingested" = s$test_season <= cfg$seasons$last,
    "first train season needs a prior season of feature history" =
      s$first_train_season > cfg$seasons$first
  )
  cfg
}

#' Assign each season to its evaluation split.
#'
#' Seasons before `first_train_season` are "history" (feature warm-up only).
season_split <- function(season, splits) {
  dplyr::case_when(
    season < splits$first_train_season ~ "history",
    season <= splits$train_last_season ~ "train",
    season == splits$validation_season ~ "validation",
    season == splits$test_season ~ "test",
    TRUE ~ "unused"
  )
}

#' Locate the Quarto CLI, including the copy bundled with RStudio on Windows.
#' Sets QUARTO_PATH so the quarto R package can find it. Returns "" if absent.
find_quarto <- function() {
  candidates <- c(
    Sys.getenv("QUARTO_PATH"),
    Sys.which("quarto"),
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe",
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto",
    "/usr/lib/rstudio/resources/app/bin/quarto/bin/quarto"
  )
  hit <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (length(hit) == 0) return("")
  Sys.setenv(QUARTO_PATH = hit[[1]])
  hit[[1]]
}
