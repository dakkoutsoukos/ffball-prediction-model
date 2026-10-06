# Milestone 3 rule-based challengers ------------------------------------------------------
# Each challenger = calibrated ESPN (refit weekly, identical procedure to the
# frozen m2_espn_cal) + a FIXED, pre-registered adjustment. The adjustment has
# no learned parameters: thresholds and magnitudes are constants written in the
# M3 registry before any prospective outcome (research/experiment_log.md, E6).

#' Team games a player missed since the player's last appearance, within the current
#' season. NA when there is no earlier appearance this season. Uses only the
#' schedule (known in advance) and appearances strictly before the target week.
add_absence_features <- function(targets, player_games, team_games) {
  gi_t <- game_index(targets$season, targets$week)
  last <- player_games |>
    dplyr::select("gsis_id", state_index = "game_index") |>
    dplyr::distinct()
  out <- targets |>
    dplyr::mutate(.gi = gi_t) |>
    dplyr::left_join(last, by = dplyr::join_by("gsis_id", closest(.gi > state_index)),
                     relationship = "many-to-one")
  sched <- dplyr::transmute(team_games, team = .data$team, sgi = game_index(.data$season, .data$week))
  missed <- purrr::pmap_int(list(out$team, out$state_index, out$.gi, out$season), function(tm, last_gi, gi, s) {
    if (is.na(last_gi) || last_gi %/% 100 != s) return(NA_integer_)
    sum(sched$team == tm & sched$sgi > last_gi & sched$sgi < gi)
  })
  out |>
    dplyr::mutate(team_games_missed = missed) |>
    dplyr::select(-".gi", -"state_index")
}

#' Signed role-change adjustment: down-weight sharp recent rises, up-weight
#' sharp recent falls of the chosen trend metric.
rule_role_change <- function(newdata, metric, hi, lo, adj_hi, adj_lo) {
  x <- newdata[[metric]]
  dplyr::case_when(is.na(x) ~ 0, x >= hi ~ adj_hi, x <= lo ~ adj_lo, TRUE ~ 0)
}

#' Return-from-absence adjustment by number of team games missed.
rule_return <- function(newdata, adj_one, adj_two_plus) {
  m <- newdata$team_games_missed
  dplyr::case_when(is.na(m) | m == 0 ~ 0, m == 1 ~ adj_one, TRUE ~ adj_two_plus)
}

#' Calibrated ESPN plus fixed adjustments. `rules` is a list of functions of
#' newdata returning additive point adjustments.
spec_adjusted <- function(name, base, rules) {
  list(
    name = name, features = base$features,
    fit = function(train) base$fit(train),
    predict = function(fit, newdata) {
      adj <- Reduce(`+`, lapply(rules, function(r) r(newdata)), 0)
      base$predict(fit, newdata) + adj
    }
  )
}

#' Registry builder for M3 adjusted challengers.
registry_spec_adjusted <- function(m, id) {
  rules <- list()
  if (!is.null(m$role_rule)) {
    r <- m$role_rule
    rules$role <- function(nd) rule_role_change(nd, r$metric, r$hi, r$lo, r$adj_hi, r$adj_lo)
  }
  if (!is.null(m$return_rule)) {
    r <- m$return_rule
    rules$return <- function(nd) rule_return(nd, r$adj_one, r$adj_two_plus)
  }
  spec_adjusted(id, spec_cal(m$calibration), rules)
}
