# Valuation: league configuration ---------------------------------------------------------
# A league is a plain list: teams, slots (name, eligible positions, count per
# team), bench, scoring, regular-season and playoff weeks. Nothing about a
# specific format (1QB, FLEX, superflex) is hard-coded: everything the
# allocation and simulation need is derived from `slots`.

read_valuation_config <- function(path = "config/valuation.yml") {
  cfg <- yaml::read_yaml(path)
  cfg$league <- val_league(cfg$league)
  cfg$path <- path
  cfg
}

#' Validate and normalise a league definition.
val_league <- function(x) {
  slots <- purrr::map(x$slots, function(s) {
    list(name = as.character(s$name), eligible = as.character(unlist(s$eligible)), count = as.integer(s$count))
  })
  names(slots) <- vapply(slots, `[[`, "", "name")
  league <- list(
    name = x$name %||% "custom", teams = as.integer(x$teams), scoring = x$scoring %||% "espn_ppr",
    slots = slots, bench = as.integer(x$bench %||% 0),
    regular_season_weeks = as.integer(unlist(x$regular_season_weeks)),
    playoff_weeks = as.integer(unlist(x$playoff_weeks))
  )
  stopifnot(
    "teams must be a positive integer" = length(league$teams) == 1 && league$teams >= 1,
    "every slot needs eligible positions and a count >= 0" =
      all(vapply(slots, function(s) length(s$eligible) > 0 && length(s$count) == 1 && s$count >= 0, TRUE)),
    "slot positions must be QB/RB/WR/TE" = all(unlist(lapply(slots, `[[`, "eligible")) %in% VAL_POSITIONS),
    "slot names must be unique" = !anyDuplicated(names(slots)),
    "bench must be >= 0" = league$bench >= 0,
    "regular season is [first, last]" = length(league$regular_season_weeks) == 2,
    "playoffs are [first, last]" = length(league$playoff_weeks) == 2,
    "playoffs follow the regular season" = league$playoff_weeks[1] > league$regular_season_weeks[2],
    "week ranges are [first, last] with first <= last" =
      league$regular_season_weeks[1] <= league$regular_season_weeks[2] && league$playoff_weeks[1] <= league$playoff_weeks[2]
  )
  league
}

#' A league with some fields overridden (sensitivity analyses).
val_league_override <- function(league, override, name = NULL) {
  base <- list(name = league$name, teams = league$teams, scoring = league$scoring,
               slots = unname(league$slots), bench = league$bench,
               regular_season_weeks = league$regular_season_weeks, playoff_weeks = league$playoff_weeks)
  out <- utils::modifyList(base, override[setdiff(names(override), "slots")])
  if (!is.null(override$slots)) out$slots <- override$slots
  out$name <- name %||% out$name
  val_league(out)
}

val_starters_per_team <- function(league) sum(vapply(league$slots, `[[`, 0L, "count"))
val_roster_size <- function(league) val_starters_per_team(league) + league$bench

#' Fantasy weeks in a segment that are still to be played from `current_week`.
val_horizon_weeks <- function(league, current_week, segment = c("full", "regular", "playoffs")) {
  segment <- match.arg(segment)
  rs <- league$regular_season_weeks
  po <- league$playoff_weeks
  weeks <- switch(segment,
    regular = seq(rs[1], rs[2]),
    playoffs = seq(po[1], po[2]),
    full = seq(rs[1], po[2])
  )
  weeks[weeks >= current_week]
}

#' Slot capacity of the whole league by slot (count x teams).
val_slot_capacity <- function(league) {
  vapply(league$slots, function(s) s$count * league$teams, 0)
}

#' Are the slot eligibility sets laminar (any two are nested or disjoint)? The
#' fast lineup evaluator in the simulation requires it; the league-level
#' allocation does not.
val_slots_laminar <- function(league) {
  el <- lapply(league$slots, `[[`, "eligible")
  for (a in el) for (b in el) {
    i <- intersect(a, b)
    if (length(i) && !(setequal(i, a) || setequal(i, b))) return(FALSE)
  }
  TRUE
}

#' Stable hash of a league definition (recorded in every valuation snapshot).
val_league_hash <- function(league) {
  digest_text(yaml::as.yaml(league[c("teams", "scoring", "slots", "bench", "regular_season_weeks", "playoff_weeks")]))
}

digest_text <- function(x) {
  h <- as.character(openssl::sha256(charToRaw(enc2utf8(x))))
  attributes(h) <- NULL
  h
}
