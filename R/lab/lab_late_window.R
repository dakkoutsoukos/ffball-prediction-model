# D1 late-window value study (master plan D1; pre-registration VL8) --------------------------------
# On the F6 arm-A development replays: the EV lineup (calibrated, late horizon) against a late-window
# policy that, before each decision point, re-chooses unlocked slots for P(win) given the realised
# points of locked starters (both teams) and P0 PODs of the unlocked players. One single swap per
# decision point, made only if its P(win) gain exceeds 2 Monte Carlo SE. Realised outcomes decide.

LW_SLOTS <- c("Thu", "SunE", "SunL", "SNF", "MNF")
LW_DECISIONS <- c("SunE", "SNF", "MNF")       # decisions are made right before these slots
LW_SIMS <- 2000L

#' Game slot of a kickoff in US Eastern time. Saturday and Friday games lock with Thursday's.
lw_slot <- function(kickoff_utc) {
  lt <- as.POSIXlt(kickoff_utc, tz = "America/New_York")
  wd <- lt$wday
  hr <- lt$hour
  dplyr::case_when(is.na(wd) ~ NA_character_,
                   wd == 0 & hr < 15 ~ "SunE", wd == 0 & hr < 20 ~ "SunL", wd == 0 ~ "SNF",
                   wd == 1 ~ "MNF", TRUE ~ "Thu")
}

#' One team-week: realised outcomes of the EV lineup and the late-window lineup against the
#' opponent's EV lineup. Vectors are indexed by player (season matrices' rows) for week t.
lw_team_week <- function(own, opp, slot_i, y, base, pos, startable, q, p_act, sims = LW_SIMS, seed = 1L) {
  ev <- function(r) {
    v <- ifelse(startable[r], dplyr::coalesce(base[r], 0), -Inf)
    r[lab_lineup(v, pos[r])]
  }
  L <- ev(own)
  O <- ev(opp)
  lw <- L
  swaps <- character(0)
  first_margin <- NA_real_
  set.seed(seed)
  for (d in LW_DECISIONS) {
    di <- match(d, LW_SLOTS)
    unl <- lw[slot_i[lw] >= di]
    bench <- setdiff(own[startable[own]], lw)
    bench <- bench[!is.na(slot_i[bench]) & slot_i[bench] >= di]
    if (!length(unl) || !length(bench)) next
    margin <- sum(y[lw[slot_i[lw] < di]]) - sum(y[O[slot_i[O] < di]])
    unl_opp <- O[slot_i[O] >= di]
    players <- unique(c(unl, bench, unl_opp))
    k <- length(players)
    draws <- matrix(scn_qdraw(q, rep(players, times = sims), stats::runif(k * sims), POD_TAU), k, sims) *
      (matrix(stats::runif(k * sims), k, sims) < p_act[players])
    row <- function(x) match(x, players)
    opp_tot <- if (length(unl_opp)) colSums(draws[row(unl_opp), , drop = FALSE]) else 0
    cur <- colSums(draws[row(unl), , drop = FALSE])
    win0 <- (margin + cur > opp_tot) + 0.5 * (margin + cur == opp_tot)
    best <- list(gain = 0)
    for (s in unl) for (b in bench) {
      new <- c(setdiff(lw, s), b)
      if (!lab_feasible(pos[new])) next
      tot <- cur - draws[row(s), ] + draws[row(b), ]
      dd <- ((margin + tot > opp_tot) + 0.5 * (margin + tot == opp_tot)) - win0
      g <- mean(dd)
      if (g > best$gain) best <- list(gain = g, se = stats::sd(dd) / sqrt(sims), s = s, b = b)
    }
    if (best$gain > 0 && best$gain > 2 * best$se) {
      lw <- c(setdiff(lw, best$s), best$b)
      swaps <- c(swaps, d)
      if (is.na(first_margin)) first_margin <- margin
    }
  }
  res <- function(x) sum(y[x])
  outcome <- function(a, b) (a > b) + 0.5 * (a == b)
  n_swaps <- length(swaps)                                        # computed first: tibble() columns shadow locals
  points_str <- paste(swaps, collapse = " ")
  tibble::tibble(pts_ev = res(L), pts_lw = res(lw), opp_pts = res(O), win_ev = outcome(res(L), res(O)),
                 win_lw = outcome(res(lw), res(O)), swaps = n_swaps, swap_points = points_str,
                 margin_at_first_swap = first_margin)
}

#' The study over one replayed season (arm A, regular season, every team-week from its own side).
lw_season <- function(replay, player_week_all, team_games, table, active_table, sims = LW_SIMS) {
  S <- lab_season_data(player_week_all, team_games, replay$season)
  tg <- team_games[team_games$season == replay$season, ]
  tw <- replay$team_weeks[replay$team_weeks$arm == "A" & replay$team_weeks$week %in% LAB_REG_WEEKS, ]
  purrr::map(sort(unique(tw$week)), function(t) {
    team_t <- S$team[, t]
    ko <- tg$kickoff_utc[tg$week == t][match(team_t, tg$team[tg$week == t])]
    slot_i <- match(lw_slot(ko), LW_SLOTS)
    startable <- !is.na(S$proj[, t])
    base <- dplyr::coalesce(S$base[, t], 0)
    y <- dplyr::coalesce(S$y[, t], 0)
    q <- pd_quantiles(S$pos, pmax(base, 0), table)
    p_act <- lab_p_active(S$pos, base, active_table)
    x <- tw[tw$week == t, ]
    purrr::map(seq_len(nrow(x)), function(i) {
      opp_row <- x[x$league == x$league[i] & x$team == x$opponent[i], ]
      lw_team_week(lab_ids(x$roster[i]), lab_ids(opp_row$roster), slot_i, y, base, S$pos, startable, q, p_act, sims,
                   seed = replay$season * 100000L + x$league[i] * 1000L + t * 20L + x$team[i]) |>
        dplyr::mutate(season = replay$season, league = x$league[i], week = t, team = x$team[i], .before = 1)
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}

#' VL8 estimate: win-rate difference (late window - EV) with a week-clustered, season-blocked CI.
lw_summary <- function(rows, reps = 2000L, seed = 8L) {
  d <- rows$win_lw - rows$win_ev
  b <- pd_cluster_boot(d, rows$season, rows$week, reps = reps, seed = seed)
  p <- rows$pts_lw - rows$pts_ev
  bp <- pd_cluster_boot(p, rows$season, rows$week, reps = reps, seed = seed + 1L)
  list(n = nrow(rows), d_win = mean(d), d_win_ci = unname(stats::quantile(b, c(0.025, 0.975))),
       d_pts = mean(p), d_pts_ci = unname(stats::quantile(bp, c(0.025, 0.975))),
       share_any_swap = mean(rows$swaps > 0),
       by_point = purrr::map(LW_DECISIONS, function(dp) {
         i <- grepl(dp, rows$swap_points)
         tibble::tibble(decision = dp, team_weeks_with_swap = sum(i), d_win_when_swapped = if (any(i)) mean(d[i]) else NA_real_)
       }) |> purrr::list_rbind(),
       by_margin = rows[rows$swaps > 0, ] |>
         dplyr::mutate(margin_band = cut(.data$margin_at_first_swap, c(-Inf, -30, -10, 0, 10, 30, Inf))) |>
         dplyr::summarise(n = dplyr::n(), d_win = mean(.data$win_lw - .data$win_ev), d_pts = mean(.data$pts_lw - .data$pts_ev),
                          .by = "margin_band") |>
         dplyr::arrange(.data$margin_band))
}
