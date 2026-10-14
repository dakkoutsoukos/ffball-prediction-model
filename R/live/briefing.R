# D5 weekly briefing (pre-declaration VL13): one private report before each slate, assembled from the
# existing modules with their command settings. Robustness flags use VL3's sensitivity settings, VL3b's
# fallback prior and a second seed. No ESPN requests: the latest snapshot and capture are used.

D5_ALTERNATIVES <- list(sigma_x0.5 = list(sigma_scale = 0.5, noise_scale = 1, seed = 20261013L),
                        sigma_x1.5 = list(sigma_scale = 1.5, noise_scale = 1, seed = 20261013L),
                        noise_x0.8 = list(sigma_scale = 1, noise_scale = 0.8, seed = 20261013L),
                        noise_x1.2 = list(sigma_scale = 1, noise_scale = 1.2, seed = 20261013L),
                        seed_2 = list(sigma_scale = 1, noise_scale = 1, seed = 20261014L))
D5_ROOT <- file.path("data", "archive", "briefings")

#' Fragile when the best item under any alternative differs from the base best.
d5_fragile <- function(best, alt_best) length(alt_best) > 0 && any(is.na(alt_best) | alt_best != best)

#' Recommended starters (player ids) of a lineup advice.
d5_starters <- function(adv) sort(adv$lineup$player_id[!adv$lineup$slot %in% c("BE", "IR")])

#' Lineup and game-time plan with P1's provider; fragile if the starters change under the published prior.
d5_lineup <- function(m, team, team_games, now, avail) {
  adv <- lg_lineup_advice(m, team, team_games, now, p_active_fun = avail)
  alt <- lg_lineup_advice(m, team, team_games, now, p_active_fun = NULL)
  list(adv = adv, fragile = !identical(d5_starters(adv), d5_starters(alt)),
       changes = sum(adv$lineup$change %in% c("start", "bench", "move"), na.rm = TRUE))
}

#' S0 odds (10,000 simulations) and VL3's band (2,000 simulations per setting).
d5_odds <- function(m, state, avail, sims = 10000L) {
  od <- sim_league_odds(m, state, sims = sims, p_active_fun = avail)
  bands <- purrr::map(D5_ALTERNATIVES[1:4], function(a) {
    r <- sim_league_odds(m, state, sims = 2000, sigma_scale = a$sigma_scale, noise_scale = a$noise_scale,
                         p_active_fun = avail)$results$base$teams
    dplyr::select(r, "team_id", "p_playoffs", "p_title")
  }) |> purrr::list_rbind(names_to = "setting")
  list(od = od, bands = bands)
}

#' D3 board with drop advice and the streaming view; fragile if the best add by P(playoffs) changes.
d5_waivers <- function(m, state, team, avail, sims = 3000L, k = 8L) {
  sc <- d3_fa_screen(m, team)
  board <- sim_fa_rescore(m, state, team, sc, k = k, sims = sims, p_active_fun = avail)
  best <- if (nrow(board)) board$add_row[which.max(board$d_playoffs)] else NA_integer_
  alt_best <- if (nrow(board)) vapply(D5_ALTERNATIVES, function(a) {
    b <- sim_fa_rescore(m, state, team, sc, k = k, sims = sims, seed = a$seed, p_active_fun = avail,
                        sigma_scale = a$sigma_scale, noise_scale = a$noise_scale)
    b$add_row[which.max(b$d_playoffs)]
  }, 0L) else integer()
  list(board = board, best = best, fragile = if (nrow(board)) d5_fragile(best, alt_best) else FALSE,
       drops = d3_drop_advice(m, team), stream = d3_stream_view(m, team, p_active_fun = avail))
}

#' D2: V2's top `per_partner` candidates with every other team, re-scored together; the `top` best by
#' the owner's P(title) with explanations and the frontier; fragile if the best changes.
d5_trades <- function(m, state, team, avail, sims = 3000L, per_partner = 3L, top = 5L) {
  s <- m$la$search
  cands <- purrr::map(setdiff(as.integer(names(m$state)), team), function(tb) {
    r <- lg_trade_search(m, team, tb, NULL, top_n = s$top_n, tv_band = s$tv_band, max_eval = s$max_eval,
                         eps = m$la$eps, strong = m$la$strong, horizon = "full")
    if (!nrow(r)) return(NULL)
    dplyr::mutate(utils::head(r, per_partner), partner = tb)
  }) |> purrr::list_rbind()
  if (is.null(cands) || !nrow(cands)) return(list(top = NULL, fragile = FALSE, n = 0L, invalid = 0L))
  trades <- function(x) lapply(seq_len(nrow(x)), function(j) list(team_a = team, give_a = x$a_rows[[j]], team_b = x$partner[j],
                                                                   give_b = x$b_rows[[j]]))
  ok <- vapply(trades(cands), function(t) d2_trade_valid(m, t), TRUE)    # V2 invariant failures are excluded
  cands <- cands[ok, ]
  if (!nrow(cands)) return(list(top = NULL, fragile = FALSE, n = 0L, invalid = sum(!ok)))
  d <- sim_trade_rescore(m, state, trades(cands), sims = sims, p_active_fun = avail)
  all <- dplyr::bind_cols(cands[c("a_gives", "b_gives", "partner", "a_rows", "b_rows")], d)
  best_k <- utils::head(order(-all$d_title_a), top)
  tp <- all[best_k, ]
  alt_best <- vapply(D5_ALTERNATIVES, function(a) {
    x <- sim_trade_rescore(m, state, trades(tp), sims = sims, seed = a$seed, p_active_fun = avail,
                           sigma_scale = a$sigma_scale, noise_scale = a$noise_scale)
    which.max(x$d_title_a)
  }, 0L)
  tp$explanation <- trade_explain(tp)
  list(top = tp, n = nrow(all), invalid = sum(!ok), fragile = d5_fragile(1L, alt_best), frontier = trade_frontier(tp)$trade)
}

#' Markdown tables (private report).
d5_md_table <- function(x) {
  if (is.null(x) || !nrow(x)) return("(none)")
  as.character(knitr::kable(x, format = "pipe"))
}

#' The private Markdown report.
d5_markdown <- function(b) {
  me <- b$team
  od <- b$odds$od$results$base
  mine <- od$teams[od$teams$team_id == me, ]
  band <- b$odds$bands[b$odds$bands$team_id == me, ]
  flag <- function(x) if (isTRUE(x)) "**FRAGILE** (flips under a pre-declared alternative)" else "robust"
  c(paste0("# Weekly briefing: ", b$team_label, ", week ", b$week),
    "", paste0("Generated ", format(b$now, "%Y-%m-%d %H:%M UTC", tz = "UTC"), "; league snapshot ",
               b$snapshot_utc, " (", round(b$snapshot_age_h, 1), " h old); git ", b$git, "."),
    "", paste0("> ", S0_LABEL), "",
    "## Lineup and game-time plan (D0, P1)", "",
    paste0("Expected points: recommended ", round(b$lineup$adv$ev_recommended, 1), " vs current ESPN lineup ",
           round(b$lineup$adv$ev_current, 1), ". Robustness: ", flag(b$lineup$fragile), "."), "",
    d5_md_table(dplyr::transmute(b$lineup$adv$lineup, .data$slot, .data$player, .data$position, .data$nfl,
                                 proj = round(.data$proj, 1), .data$status, .data$locked, espn = .data$espn_slot, .data$change)),
    "", d5_md_table(b$lineup$adv$plan),
    "", "## Odds (S0)", "",
    paste0("P(win) this week ", round(od$leverage$p_win_this_week %||% NA, 3), "; leverage ",
           round(od$leverage$leverage %||% NA, 3), ". Season: E[wins] ", round(mine$e_wins, 2), ", P(playoffs) ",
           round(mine$p_playoffs, 3), " (VL3 band ", round(min(band$p_playoffs), 3), "-", round(max(band$p_playoffs), 3),
           "), P(title) ", round(mine$p_title, 3), " (band ", round(min(band$p_title), 3), "-", round(max(band$p_title), 3), ")."),
    "", d5_md_table(dplyr::transmute(dplyr::arrange(od$teams, dplyr::desc(.data$p_title)),
                                     team = vapply(.data$team_id, function(x) b$label(x), ""), e_wins = round(.data$e_wins, 2),
                                     p_playoffs = round(.data$p_playoffs, 3), p_title = round(.data$p_title, 3))),
    "", "## Waivers (D3)", "", paste0("Best add by P(playoffs): ", flag(b$waivers$fragile), "."), "",
    d5_md_table(if (nrow(b$waivers$board)) dplyr::transmute(b$waivers$board, .data$add, .data$position, .data$drop, dU = round(.data$dU, 1),
                                                            dP_playoffs = round(.data$d_playoffs, 3), dP_title = round(.data$d_title, 3)) else NULL),
    "", "Drop advice:", "", d5_md_table(dplyr::transmute(b$waivers$drops, .data$player, .data$position, cost_dU = round(.data$cost, 1))),
    "", paste0("Streaming view (", b$waivers$stream$status[1] %||% "informational", "):"), "",
    d5_md_table(dplyr::transmute(b$waivers$stream, .data$position, .data$player, expected = round(.data$expected, 1),
                                 gain = round(.data$gain, 1), .data$stream_candidate)),
    "", "## Trades (D2)", "",
    if (is.null(b$trades$top)) "No candidate trades passed the utility screen." else
      c(paste0(b$trades$n, " candidates re-scored; best by your P(title): ", flag(b$trades$fragile),
               ". Frontier trades: ", paste(b$trades$frontier, collapse = ", "), "."), "",
        d5_md_table(dplyr::transmute(b$trades$top, partner = vapply(.data$partner, function(x) b$label(x), ""),
                                     you_give = .data$a_gives, you_get = .data$b_gives,
                                     dP_playoffs = round(.data$d_playoffs_a, 3), dP_title = round(.data$d_title_a, 3))),
        "", paste0("- ", b$trades$top$explanation)),
    "", "## Player values and roster risk (S3)", "",
    d5_md_table(dplyr::transmute(b$values$values, .data$player, .data$position, wins_added = round(.data$wins_added, 2),
                                 playoffs_value = round(.data$playoffs_value, 3), title_value = round(.data$title_value, 3),
                                 evor = round(.data$evor, 1), vor = round(.data$vor, 1))),
    "", paste0("Top two players supply ", round(100 * b$values$risk$top2_share), "% of expected lineup points; ",
               "largest single-player P(playoffs) value ", round(b$values$risk$max_playoffs_value, 3), "."),
    "", d5_md_table(b$values$risk$holes), "", d5_md_table(b$values$risk$designated),
    "", "## Model and data health (I3)", "", d5_md_table(b$health),
    "", "## Ledger", "", paste0("- ", b$ledger))
}

#' Console summary without names (counts, flags, the report path).
d5_console <- function(b, path) {
  mine <- b$odds$od$results$base$teams
  mine <- mine[mine$team_id == b$team, ]
  h <- table(factor(b$health$level, c("OK", "WARN", "ALERT")))
  c(sprintf("Briefing week %d written to %s", b$week, path),
    sprintf("Lineup: %d change(s); EV %+.1f vs current; %s", b$lineup$changes,
            b$lineup$adv$ev_recommended - b$lineup$adv$ev_current, if (b$lineup$fragile) "FRAGILE" else "robust"),
    sprintf("Odds: P(playoffs) %.3f, P(title) %.3f", mine$p_playoffs, mine$p_title),
    sprintf("Waivers: %d adds re-scored; best dP(playoffs) %+.3f; %s", nrow(b$waivers$board),
            if (nrow(b$waivers$board)) max(b$waivers$board$d_playoffs) else 0, if (b$waivers$fragile) "FRAGILE" else "robust"),
    sprintf("Trades: %d re-scored; best dP(title) %+.3f; %s", b$trades$n %||% 0L,
            if (is.null(b$trades$top)) 0 else max(b$trades$top$d_title_a), if (isTRUE(b$trades$fragile)) "FRAGILE" else "robust"),
    sprintf("Health: %d OK, %d WARN, %d ALERT", h[["OK"]], h[["WARN"]], h[["ALERT"]]),
    sprintf("Ledgered: %d record(s)", length(b$ledger)))
}
