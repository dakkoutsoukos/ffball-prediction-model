# X10b (master plan S3; pre-registration VL7): which value metric (VOR, EVOR, MRU, wins added) best
# predicts the realised lineup-point gain from adding a free agent? F6 arm-A development replays.

X10B_STAGES <- 2:13
X10B_PER_POS <- 5L
X10B_METRICS <- c("vor", "evor", "mru", "wins_added")

#' Calibrated per-game level at a waiver stage (clamped at 0: expected points cannot be negative) and
#' the players' week-by-week plays indicator for weeks w >= t (last known team).
x10b_levels <- function(info, calib) {
  t <- info$t
  k <- match(info$pos, calib$position)
  per_game <- pmax(0, calib$a[k] + calib$b[k] * info$L[, t - 1])
  plays <- info$plays[match(info$team_asof[, t - 1], info$teams), , drop = FALSE]
  plays[is.na(plays)] <- FALSE
  list(per_game = per_game, plays = plays)
}

#' E[max(0, Y - R)] for POD quantile rows q (one per R) with trapezoid weights (as s1_pod_moments).
x10b_excess <- function(q, R, tau = POD_TAU) {
  K <- length(tau)
  w <- numeric(K)
  d <- diff(tau)
  w[-K] <- w[-K] + d / 2
  w[-1] <- w[-1] + d / 2
  w[1] <- w[1] + tau[1]
  w[K] <- w[K] + (1 - tau[K])
  drop(pmax(q - R, 0) %*% w)
}

#' Best drop for adding `c` to roster `r` by the LAB1 pair gain (calibrated ROS values v; the 2 lowest
#' per position as drop candidates; the roster stays legal). Returns the drop (c itself = no add) and
#' the gain (>= 0).
x10b_best_drop <- function(v, pos, r, c, n_weeks) {
  cur <- lab_lineup_value(dplyr::coalesce(v[r], 0), pos[r])
  drops <- unlist(lapply(LAB_POSITIONS, function(p) {
    x <- r[pos[r] == p]
    utils::head(x[order(dplyr::coalesce(v[x], 0), x)], 2L)
  }))
  best <- list(drop = c, gain = 0)
  for (d in drops) {
    nr <- c(r[r != d], c)
    if (!lab_roster_legal(pos[nr])) next
    g <- (lab_lineup_value(dplyr::coalesce(v[nr], 0), pos[nr]) - cur) * n_weeks
    if (g > best$gain) best <- list(drop = d, gain = g)
  }
  best
}

#' Realised points of the raw-policy lineup of roster r in weeks `weeks` (week-w information).
x10b_realised <- function(S, r, weeks, infos) {
  vapply(weeks, function(w) {
    info <- infos[[as.character(w)]]
    lu <- r[lab_lineup(lab_lineup_values(info, r, "raw"), S$pos[r])]
    sum(dplyr::coalesce(S$y[lu, w], 0))
  }, 0)
}

#' Team mean and variance of the e(w)-optimal lineup from POD moments (one week).
x10b_team_moments <- function(r, e_w, pos, mom_mean, mom_var) {
  lu <- r[lab_lineup(e_w[r], pos[r])]
  c(mean = sum(mom_mean[lu]), var = sum(mom_var[lu]))
}

#' Candidate rows for one replay season: arm A, the focal team of each league, stages 2-13.
x10b_season <- function(replay, player_week_all, team_games, table, active_table, stages = X10B_STAGES,
                        per_pos = X10B_PER_POS) {
  S <- lab_season_data(player_week_all, team_games, replay$season)
  calib <- replay$calib
  tw <- replay$team_weeks[replay$team_weeks$arm == "A", ]
  last_reg <- max(LAB_REG_WEEKS)
  infos <- lapply(LAB_REG_WEEKS, function(w) lab_info(S, w, "lineup"))
  names(infos) <- as.character(LAB_REG_WEEKS)
  purrr::map(sort(unique(tw$league)), function(lg) {
    x <- tw[tw$league == lg, ]
    focal <- x$team[x$focal][1]
    n_teams <- max(x$team)
    purrr::map(stages, function(t) {
      roster_at <- function(j) lab_ids(x$roster[x$team == j & x$week == t - 1])
      rosters <- lapply(seq_len(n_teams), roster_at)
      info <- lab_info(S, t, "waiver")
      fa <- setdiff(which(rowSums(info$has_row) > 0), unlist(rosters))
      v <- lab_ros_values(info, "calibrated", calib)
      lv <- x10b_levels(info, calib)
      fa <- fa[!is.na(v[fa])]
      cands <- unlist(lapply(LAB_POSITIONS, function(p) {
        y <- fa[S$pos[fa] == p]
        utils::head(y[order(-v[y], y)], per_pos)
      }))
      if (length(cands) < 5) return(NULL)
      weeks <- seq(t, last_reg)
      n_weeks <- info$n_weeks - t + 1
      E <- lv$per_game * lv$plays[, weeks, drop = FALSE]          # players x remaining regular weeks
      E[is.na(E)] <- 0
      # replacement: the best e(w) among the other free agents at the position
      repl <- function(c) {
        o <- fa[S$pos[fa] == S$pos[c] & fa != c]
        if (!length(o)) return(numeric(length(weeks)))
        apply(E[o, , drop = FALSE], 2, max)
      }
      # PODs around e/p (p by position x band of e); per-player moments for wins added
      players <- unique(c(cands, unlist(rosters)))
      pg <- lv$per_game[players]
      pg[is.na(pg)] <- 0
      p_act <- lab_p_active(S$pos[players], pg, active_table)
      b <- ifelse(p_act > 0, pg / p_act, 0)
      q <- pd_quantiles(S$pos[players], b, table)
      mom <- s1_pod_moments(q, p_act)
      mom_mean <- mom_var <- numeric(length(S$ids))
      mom_mean[players] <- ifelse(pg > 0, mom$mean, 0)
      mom_var[players] <- ifelse(pg > 0, mom$var, 0)
      r0 <- rosters[[focal]]
      base_pts <- x10b_realised(S, r0, weeks, infos)
      opp <- vapply(weeks, function(w) x$opponent[x$team == focal & x$week == w][1], 0L)
      pwin <- function(r) vapply(seq_along(weeks), function(k) {
        w <- weeks[k]
        e_w <- E[, k]
        mw <- mom_mean * lv$plays[, w]
        vw <- mom_var * lv$plays[, w]
        f <- x10b_team_moments(r, e_w, S$pos, mw, vw)
        o <- x10b_team_moments(rosters[[opp[k]]], e_w, S$pos, mw, vw)
        s <- sqrt(f[["var"]] + o[["var"]])
        if (s <= 0) return(as.numeric(f[["mean"]] > o[["mean"]]))
        stats::pnorm((f[["mean"]] - o[["mean"]]) / s)
      }, 0)
      p0 <- sum(pwin(r0))
      purrr::map(cands, function(c) {
        R <- repl(c)
        k <- match(c, players)
        vor <- sum(pmax(0, E[c, ] - R))
        evor <- if (pg[k] > 0) {
          on <- E[c, ] > 0
          sum(p_act[k] * x10b_excess(q[rep(k, sum(on)), , drop = FALSE], R[on]))
        } else 0
        mru <- mean(vapply(seq_len(n_teams), function(j) x10b_best_drop(v, S$pos, rosters[[j]], c, n_weeks)$gain, 0))
        bd <- x10b_best_drop(v, S$pos, r0, c, n_weeks)
        if (bd$drop == c) {
          g <- 0
          wa <- 0
        } else {
          r1 <- c(r0[r0 != bd$drop], c)
          g <- sum(x10b_realised(S, r1, weeks, infos) - base_pts)
          wa <- sum(pwin(r1)) - p0
        }
        tibble::tibble(season = S$season, league = lg, stage = t, candidate = c, position = S$pos[c],
                       vor = vor, evor = evor, mru = mru, wins_added = wa, added = bd$drop != c, gain = g)
      }) |> purrr::list_rbind()
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}

#' Spearman (or Pearson) correlation of each metric with the realised gain per stage; NA when the stage
#' has fewer than 5 candidates or a constant gain or metric.
x10b_stage_cor <- function(rows, method = "spearman") {
  dplyr::summarise(rows, n = dplyr::n(), dplyr::across(dplyr::all_of(X10B_METRICS), function(m) {
    if (dplyr::n() < 5 || stats::sd(.data$gain) == 0 || stats::sd(m) == 0) NA_real_ else
      stats::cor(m, .data$gain, method = method)
  }), .by = c("season", "league", "stage"))
}

#' X10b summary (VL7): mean stage correlations, paired differences vs VOR with week-clustered,
#' season-blocked CIs, the selection rule, and the secondary displays.
x10b_summary <- function(rows, reps = 2000L, seed = 10L, register = read_contamination_register()) {
  assert_family_seasons("decision_family", unique(rows$season), "development", register)
  sc <- x10b_stage_cor(rows)
  primary <- purrr::map(X10B_METRICS, function(mt) {
    ok <- !is.na(sc[[mt]]) & !is.na(sc$vor)
    d <- sc[[mt]][ok] - sc$vor[ok]
    ci <- if (mt == "vor" || !any(ok)) c(NA_real_, NA_real_) else
      unname(stats::quantile(pd_cluster_boot(d, sc$season[ok], sc$stage[ok], reps = reps, seed = seed), c(0.025, 0.975)))
    tibble::tibble(metric = mt, stages = sum(!is.na(sc[[mt]])), mean_cor = mean(sc[[mt]], na.rm = TRUE),
                   diff_vs_vor = if (mt == "vor") 0 else mean(d), ci_lo = ci[1], ci_hi = ci[2])
  }) |> purrr::list_rbind()
  top <- primary$metric[which.max(primary$mean_cor)]
  selected <- if (top != "vor" && isTRUE(primary$ci_lo[primary$metric == top] > 0)) top else "vor"
  pc <- x10b_stage_cor(rows, "pearson")
  hit <- dplyr::summarise(rows, dplyr::across(dplyr::all_of(X10B_METRICS), function(m) {
    if (stats::sd(.data$gain) == 0) NA_real_ else as.numeric(.data$gain[which.max(m)] == max(.data$gain))
  }), .by = c("season", "league", "stage"))
  by_pos <- purrr::map(LAB_POSITIONS, function(p) {
    x <- x10b_stage_cor(rows[rows$position == p, ])
    tibble::tibble(position = p, metric = X10B_METRICS, mean_cor = vapply(X10B_METRICS, function(mt) mean(x[[mt]], na.rm = TRUE), 0))
  }) |> purrr::list_rbind()
  by_half <- purrr::map(c("early", "late"), function(h) {
    x <- sc[if (h == "early") sc$stage <= 7 else sc$stage >= 8, ]
    tibble::tibble(half = h, metric = X10B_METRICS, mean_cor = vapply(X10B_METRICS, function(mt) mean(x[[mt]], na.rm = TRUE), 0))
  }) |> purrr::list_rbind()
  list(n_rows = nrow(rows), n_stages = nrow(sc), share_added = mean(rows$added), share_zero_gain = mean(rows$gain == 0),
       primary = primary, top = top, selected = selected,
       pearson = vapply(X10B_METRICS, function(mt) mean(pc[[mt]], na.rm = TRUE), 0),
       top1_hit = vapply(X10B_METRICS, function(mt) mean(hit[[mt]], na.rm = TRUE), 0),
       by_position = by_pos, by_half = by_half)
}
