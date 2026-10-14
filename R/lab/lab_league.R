# F6 decision laboratory v1: synthetic leagues, the weekly loop and replays (pre-registration LAB1) -

LAB_ARMS <- list(A = c(lineup = "raw", waiver = "raw"), B = c(lineup = "calibrated", waiver = "raw"),
                 C = c(lineup = "raw", waiver = "calibrated"), D = c(lineup = "calibrated", waiver = "calibrated"),
                 E = c(lineup = "raw", waiver = "stream"))           # E: X16 QB streaming (VL9)
LAB_CAPS <- c(QB = 2L, RB = 6L, WR = 6L, TE = 2L)

#' Starting-slot needs still open for a roster with position counts `n` (named QB/RB/WR/TE).
lab_open_needs <- function(n) {
  fixed <- max(0, 1 - n[["QB"]]) + max(0, 2 - n[["RB"]]) + max(0, 2 - n[["WR"]]) + max(0, 1 - n[["TE"]])
  flex_have <- max(0, n[["RB"]] - 2) + max(0, n[["WR"]] - 2) + max(0, n[["TE"]] - 1)
  fixed + max(0, LAB_SLOTS$FLEX - flex_have)
}

#' Snake draft on the pre-draft value (lab_draft_values(); LAB1b) minus the position's replacement
#' level (n-th QB/TE, 3n-th RB/WR) plus N(0, 1) noise per (team, player). Caps QB 2, TE 2, RB 6,
#' WR 6; every pick leaves enough picks to fill the starting slots. Returns player indices per team.
lab_draft <- function(S, n_teams, seed) {
  info <- lab_info(S, 1L, "draft")
  v <- info$draft_value
  # draftable: a positive value and a week-1 ESPN row (the preseason player pool; a player who joins
  # a team later in the season is not known at the draft)
  ok <- !is.na(v) & v > 0 & !is.na(info$proj[, 1])
  repl <- vapply(LAB_POSITIONS, function(p) {
    x <- sort(v[ok & info$pos == p], decreasing = TRUE)
    r <- if (p %in% c("QB", "TE")) n_teams else 3L * n_teams
    if (!length(x)) 0 else x[min(r, length(x))]
  }, 0)
  vor <- v - repl[info$pos]
  set.seed(seed)
  noise <- matrix(stats::rnorm(length(v) * n_teams), length(v), n_teams)
  rosters <- replicate(n_teams, integer(0), simplify = FALSE)
  taken <- !ok
  order1 <- seq_len(n_teams)
  for (round in seq_len(LAB_ROSTER)) {
    for (j in if (round %% 2 == 1) order1 else rev(order1)) {
      n <- table(factor(info$pos[rosters[[j]]], LAB_POSITIONS))
      left <- LAB_ROSTER - length(rosters[[j]]) - 1L
      allowed <- vapply(LAB_POSITIONS, function(p) {
        m <- n
        m[[p]] <- m[[p]] + 1L
        m[[p]] <= LAB_CAPS[[p]] && lab_open_needs(m) <= left
      }, TRUE)
      cand <- which(!taken & info$pos %in% LAB_POSITIONS[allowed])
      if (!length(cand)) cli::cli_abort("Draft pool exhausted (season {S$season}, team {j}).")
      score <- vor[cand] + noise[cand, j]
      pick <- cand[order(-score, cand)[1]]
      rosters[[j]] <- c(rosters[[j]], pick)
      taken[pick] <- TRUE
    }
  }
  rosters
}

#' Round-robin schedule (circle method) over `weeks`, team order permuted by the seed. Returns an
#' n x weeks matrix of opponents.
lab_schedule <- function(n_teams, weeks = length(LAB_REG_WEEKS), seed) {
  set.seed(seed)
  arr <- sample(n_teams)
  rounds <- vector("list", n_teams - 1)
  for (r in seq_len(n_teams - 1)) {
    opp <- integer(n_teams)
    for (i in seq_len(n_teams / 2)) {
      a <- arr[i]
      b <- arr[n_teams + 1 - i]
      opp[a] <- b
      opp[b] <- a
    }
    rounds[[r]] <- opp
    arr <- c(arr[1], arr[n_teams], arr[2:(n_teams - 1)])
  }
  sapply(seq_len(weeks), function(w) rounds[[(w - 1) %% (n_teams - 1) + 1]])
}

#' A league: size, seeds, draft, schedule and focal seat (shared by every arm).
lab_setup <- function(S, n_teams, league, seed) {
  list(season = S$season, league = league, n = n_teams, seed = seed, rosters = lab_draft(S, n_teams, seed),
       schedule = lab_schedule(n_teams, seed = seed + 1L), focal = (seed %% n_teams) + 1L)
}

#' Waiver priority: fewest wins (ties count half), then fewest points for, then reverse draft order.
lab_priority <- function(wins, pf, n) order(wins, pf, -seq_len(n))

#' Contested claims. Teams go in priority order; each processes its claims in its own order and
#' stops at the first one that is still possible (the player is unrostered and was not dropped this
#' week, the drop is still rostered, the roster stays legal). A team that claims moves to the back
#' and the pass restarts, until no claim succeeds.
lab_resolve_claims <- function(lists, rosters, prio, pos) {
  dropped <- integer(0)
  log <- list()
  repeat {
    done <- TRUE
    for (j in prio) {
      cl <- lists[[j]]
      while (nrow(cl)) {
        k <- cl[1, ]
        cl <- cl[-1, ]
        avail <- !k$add %in% unlist(rosters) && !k$add %in% dropped && k$drop %in% rosters[[j]]
        new <- c(rosters[[j]][rosters[[j]] != k$drop], k$add)
        if (avail && lab_roster_legal(pos[new])) {
          rosters[[j]] <- new
          dropped <- c(dropped, k$drop)
          log[[length(log) + 1]] <- tibble::tibble(team = j, add = k$add, drop = k$drop, gain = k$gain)
          prio <- c(prio[prio != j], j)
          done <- FALSE
          break
        }
      }
      lists[[j]] <- cl
      if (!done) break
    }
    if (done) break
  }
  list(rosters = rosters,
       log = if (length(log)) purrr::list_rbind(log) else tibble::tibble(team = integer(), add = integer(), drop = integer(),
                                                                           gain = double()))
}

#' Play one league with one arm for the focal team (others: raw lineup and raw waivers).
#' `shadow = TRUE` also records, for every team-week, both lineup policies' choices and realised
#' points on the same roster, and both waiver policies' claims on the same state (triage inputs).
lab_run_league <- function(S, setup, arm = "A", calib, shadow = FALSE) {
  n <- setup$n
  a <- LAB_ARMS[[arm]]
  pol_lineup <- list(raw = lab_lineup_policy("raw"), calibrated = lab_lineup_policy("calibrated"))
  pol_waiver <- list(raw = lab_waiver_policy("raw"), calibrated = lab_waiver_policy("calibrated", calib),
                     stream = lab_stream_policy(calib))
  team_lineup <- function(j) if (j == setup$focal) a[["lineup"]] else "raw"
  team_waiver <- function(j) if (j == setup$focal) a[["waiver"]] else "raw"
  rosters <- setup$rosters
  wins <- numeric(n)
  pf <- numeric(n)
  recs <- vector("list", length(LAB_WEEKS))
  claims_log <- list()
  wtriage <- list()
  scores <- matrix(NA_real_, n, length(LAB_WEEKS))
  for (t in LAB_WEEKS) {
    # ---- waivers (before week t) ----
    if (t >= 2) {
      info <- lab_info(S, t, "waiver")
      rostered <- unlist(rosters)
      fa <- setdiff(which(rowSums(info$has_row) > 0), rostered)     # seen in weeks <= t-1 only
      lists <- lapply(seq_len(n), function(j) {
        st <- list(team = j, roster = rosters[[j]], free_agents = fa)
        cl <- pol_waiver[[team_waiver(j)]](st, info)
        if (shadow) {
          other <- if (team_waiver(j) == "raw") pol_waiver$calibrated(st, info) else pol_waiver$raw(st, info)
          raw_cl <- if (team_waiver(j) == "raw") cl else other
          cal_cl <- if (team_waiver(j) == "raw") other else cl
          vcal <- lab_ros_values(info, "calibrated", calib)
          top_gain <- function(x) if (!nrow(x)) 0 else {
            r <- c(rosters[[j]][rosters[[j]] != x$drop[1]], x$add[1])
            (lab_lineup_value(dplyr::coalesce(vcal[r], 0), info$pos[r]) -
               lab_lineup_value(dplyr::coalesce(vcal[rosters[[j]]], 0), info$pos[rosters[[j]]])) * (info$n_weeks - t + 1)
          }
          wtriage[[length(wtriage) + 1]] <<- tibble::tibble(
            week = t, team = j, focal = j == setup$focal, raw_claims = nrow(raw_cl), cal_claims = nrow(cal_cl),
            flip = !identical(paste(raw_cl$add, raw_cl$drop), paste(cal_cl$add, cal_cl$drop)),
            model_gain_cal_vs_raw = top_gain(cal_cl) - top_gain(raw_cl))
        }
        cl
      })
      prio <- if (t == 2) rev(seq_len(n)) else lab_priority(wins, pf, n)
      res <- lab_resolve_claims(lists, rosters, prio, S$pos)
      rosters <- res$rosters
      if (nrow(res$log)) claims_log[[length(claims_log) + 1]] <- dplyr::mutate(res$log, week = t, .before = 1)
    }
    # ---- lineups at week t, realised scores ----
    info <- lab_info(S, t, "lineup")
    yt <- S$y[, t]
    real <- function(ids) sum(dplyr::coalesce(yt[ids], 0))
    recs[[t]] <- purrr::map(seq_len(n), function(j) {
      r <- rosters[[j]]
      lu <- pol_lineup[[team_lineup(j)]](list(team = j, roster = r), info)
      hv <- ifelse(S$has_row[r, t], dplyr::coalesce(yt[r], 0), -Inf)
      out <- tibble::tibble(week = t, team = j, focal = j == setup$focal,
                            opponent = if (t %in% LAB_REG_WEEKS) setup$schedule[j, t] else NA_integer_,
                            points = real(lu), hindsight = sum(hv[lab_lineup(hv, S$pos[r])]),
                            lineup = paste(sort(lu), collapse = " "), roster = paste(sort(r), collapse = " "))
      if (shadow) {
        lr <- pol_lineup$raw(list(team = j, roster = r), info)
        lc <- pol_lineup$calibrated(list(team = j, roster = r), info)
        b <- dplyr::coalesce(info$base[, t], 0)
        out <- dplyr::mutate(out, shadow_raw = real(lr), shadow_cal = real(lc),
                             lineup_flip = !setequal(lr, lc), model_gain = sum(b[lc]) - sum(b[lr]),
                             lineup_raw = paste(sort(lr), collapse = " "), lineup_cal = paste(sort(lc), collapse = " "))
      }
      out
    }) |> purrr::list_rbind()
    scores[, t] <- recs[[t]]$points
    if (t %in% LAB_REG_WEEKS) {
      opp <- setup$schedule[, t]
      wins <- wins + (scores[, t] > scores[opp, t]) + 0.5 * (scores[, t] == scores[opp, t])
      pf <- pf + scores[, t]
    }
  }
  # playoffs (descriptive): seeds by wins, then points for; 1v4 and 2v3 in week 15, final week 16
  seeds <- order(-wins, -pf, seq_len(n))[1:4]
  semi <- function(x, y) if (scores[x, 15] >= scores[y, 15]) x else y   # a tie goes to the higher seed
  f1 <- semi(seeds[1], seeds[4])
  f2 <- semi(seeds[2], seeds[3])
  champ <- if (scores[f1, 16] >= scores[f2, 16]) f1 else f2
  meta <- tibble::tibble(season = setup$season, league = setup$league, n_teams = n, arm = arm)
  with_meta <- function(parts) {
    if (!length(parts)) return(NULL)
    x <- purrr::list_rbind(parts)
    dplyr::bind_cols(meta[rep(1, nrow(x)), ], x)
  }
  list(
    team_weeks = dplyr::bind_cols(meta[rep(1, sum(vapply(recs, nrow, 0L))), ], purrr::list_rbind(recs)),
    standings = dplyr::bind_cols(meta[rep(1, n), ], tibble::tibble(team = seq_len(n), focal = seq_len(n) == setup$focal,
                                                                   wins = wins, pf = pf, playoffs = seq_len(n) %in% seeds,
                                                                   title = seq_len(n) == champ)),
    claims = with_meta(claims_log),
    waiver_triage = with_meta(wtriage)
  )
}

#' Replay one season: `leagues` synthetic leagues (sizes cycling 8/10/12), every arm on each.
#' Arm A also records the shadow lineups and waiver triage.
lab_replay_season <- function(frame, team_games, season, leagues = 20L, arms = names(LAB_ARMS),
                              register = read_contamination_register()) {
  assert_family_seasons("decision_family", season, "development", register)
  assert_family_seasons("decision_family", LAB_WARMUP, "warmup", register)
  S <- lab_season_data(frame, team_games, season)
  calib <- lab_waiver_calibration(frame, team_games, seq(LAB_WARMUP, season - 1L))
  sizes <- rep(c(8L, 10L, 12L), length.out = leagues)
  runs <- purrr::map(seq_len(leagues), function(l) {
    setup <- lab_setup(S, sizes[l], l, seed = season * 1000L + l)
    purrr::map(arms, function(arm) lab_run_league(S, setup, arm, calib, shadow = arm == "A"))
  }) |> purrr::list_flatten()
  pick <- function(el) purrr::list_rbind(purrr::compact(purrr::map(runs, el)))
  list(season = season, calib = dplyr::mutate(calib, season = season), team_weeks = pick("team_weeks"),
       standings = pick("standings"), claims = pick("claims"), waiver_triage = pick("waiver_triage"))
}
