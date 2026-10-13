# Contamination register guard (master plan F2-lite) ----------------------------------------------
# research/contamination_register.yml says which seasons each question family may use and for what
# (05 section 9). Every new analysis calls assert_family_seasons() before it touches outcomes, so a
# check season cannot be spent twice and a sealed season cannot become development data.

CONTAMINATION_REGISTER <- "research/contamination_register.yml"
REGISTER_ROLES <- c("development", "training", "warmup", "check", "confirmatory", "descriptive", "outcome_free")

read_contamination_register <- function(path = CONTAMINATION_REGISTER) {
  r <- yaml::read_yaml(path)
  r$families <- lapply(r$families, function(f) {
    for (k in c(REGISTER_ROLES, "excluded", "contaminated")) f[[k]] <- as.integer(unlist(f[[k]]))
    f
  })
  r
}

#' Abort unless every season is allowed for `role` in `family`. Also refuses:
#'   - a sealed season for any role other than outcome_free or confirmatory;
#'   - confirmatory use of a sealed season before `now` passes the season's end (the caller passes
#'     `season_over = TRUE` once the regular season is over, as at R1);
#'   - a check season that spent_checks already records for this family.
assert_family_seasons <- function(family, seasons, role, register = read_contamination_register(), season_over = FALSE) {
  role <- match.arg(role, REGISTER_ROLES)
  f <- register$families[[family]]
  if (is.null(f)) cli::cli_abort("Family {.val {family}} is not in the contamination register; add it before using any data.")
  seasons <- as.integer(seasons)
  bad <- setdiff(seasons, f[[role]])
  if (length(bad)) cli::cli_abort("Family {.val {family}} may not use season{?s} {bad} for {role}.")
  sealed <- intersect(seasons, as.integer(names(register$sealed_seasons %||% list())))
  if (length(sealed) && !role %in% c("outcome_free", "confirmatory")) {
    cli::cli_abort("Season{?s} {sealed} {?is/are} sealed: outcomes are never development data.")
  }
  if (length(sealed) && role == "confirmatory" && !isTRUE(season_over)) {
    cli::cli_abort("Season{?s} {sealed} {?is/are} sealed until the season is over (E16 section 5).")
  }
  if (role == "check") {
    spent <- Filter(function(s) identical(s$family, family), register$spent_checks %||% list())
    used <- intersect(seasons, as.integer(unlist(lapply(spent, `[[`, "season"))))
    if (length(used)) cli::cli_abort("The {family} check on season{?s} {used} was already spent.")
  }
  invisible(TRUE)
}
