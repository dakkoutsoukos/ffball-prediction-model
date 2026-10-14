# S2 v1: generalised season resolver (master plan S2; pre-registration VL6) -----------------------
# S0's resolver extended to the formats ESPN offers: 2/4/6/8 playoff teams (fixed brackets, no
# reseeding; the top 2 seeds get byes with 6 teams), divisions (winners seeded first), and the
# tiebreak after win share (TOTAL_POINTS_SCORED or head-to-head among the tied teams), then points
# for, then team id. Playoff ties go to the higher seed. On the owner's format it reproduces S0's
# sim_resolve() exactly (tested).

# Fixed brackets: "Sk" = seed k; "Wr.g" = winner of round r's game g. Round r is played in matchup
# period regular_periods + r.
S2_BRACKETS <- list(
  `2` = list(list(c("S1", "S2"))),
  `4` = list(list(c("S1", "S4"), c("S2", "S3")), list(c("W1.1", "W1.2"))),
  `6` = list(list(c("S3", "S6"), c("S4", "S5")), list(c("S1", "W1.2"), c("S2", "W1.1")), list(c("W2.1", "W2.2"))),
  `8` = list(list(c("S1", "S8"), c("S4", "S5"), c("S3", "S6"), c("S2", "S7")), list(c("W1.1", "W1.2"), c("W1.3", "W1.4")),
             list(c("W2.1", "W2.2")))
)

#' Order of teams for seeding within one simulation: win share, then the tiebreak among teams tied on
#' wins, then points for, then team id. `h2h` is a teams x teams matrix of head-to-head wins (ties
#' count half) for this simulation.
s2_order <- function(wins, pf, teams, tiebreak, h2h = NULL) {
  key <- rep(0.5, length(teams))
  if (tiebreak == "H2H" && !is.null(h2h)) {
    for (w in unique(wins)) {
      g <- which(wins == w)
      if (length(g) < 2) next
      won <- rowSums(h2h[g, g, drop = FALSE])
      games <- rowSums(h2h[g, g, drop = FALSE] + t(h2h[g, g, drop = FALSE]))
      key[g] <- ifelse(games > 0, won / games, 0.5)
    }
  }
  order(-wins, -key, -pf, teams)
}

#' Seeds for one simulation: with divisions, the division winners take the top seeds (in seeding
#' order), then the others; otherwise the seeding order.
s2_seed <- function(ord, teams, divisions = NULL) {
  if (is.null(divisions)) return(ord)
  div <- divisions[as.character(teams)]
  winners <- ord[!duplicated(div[ord])]
  c(winners, setdiff(ord, winners))
}

#' Resolve seasons from scores [team, week, sim] (S0's input): remaining regular-season games, seeds
#' and the bracket. `divisions`: named vector team id -> division (NULL = none).
s2_resolve <- function(scores, state, current_period, divisions = NULL,
                       tiebreak = c("TOTAL_POINTS_SCORED", "H2H")) {
  tiebreak <- match.arg(tiebreak)
  r <- state$rules
  teams <- as.integer(dimnames(scores)[[1]])
  weeks <- as.integer(dimnames(scores)[[2]])
  S <- dim(scores)[3]
  n <- length(teams)
  per_weeks <- stats::setNames(r$matchup_periods$scoring_periods, r$matchup_periods$matchup_period)
  period_score <- function(period) {
    wk <- per_weeks[[as.character(period)]] %||% period
    j <- match(wk, weeks)
    if (anyNA(j)) cli::cli_abort("Simulation weeks do not cover matchup period {period}.")
    apply(scores[, j, , drop = FALSE], c(1, 3), sum)
  }
  st <- state$standings[match(teams, state$standings$team_id), ]
  wins <- matrix(st$wins + 0.5 * st$ties, n, S)
  pf <- matrix(st$points_for, n, S)
  h2h <- if (tiebreak == "H2H") array(0, c(n, n, S)) else NULL
  if (tiebreak == "H2H") {                                   # completed games count too
    done <- state$schedule[state$schedule$matchup_period < current_period & !is.na(state$schedule$away_team), ]
    for (k in seq_len(nrow(done))) {
      h <- match(done$home_team[k], teams)
      a <- match(done$away_team[k], teams)
      hw <- switch(done$winner[k], HOME = 1, AWAY = 0, 0.5)
      h2h[h, a, ] <- h2h[h, a, ] + hw
      h2h[a, h, ] <- h2h[a, h, ] + (1 - hw)
    }
  }
  for (p in seq(current_period, r$regular_periods)) {
    ps <- period_score(p)
    g <- state$schedule[state$schedule$matchup_period == p & !is.na(state$schedule$away_team), ]
    for (k in seq_len(nrow(g))) {
      h <- match(g$home_team[k], teams)
      a <- match(g$away_team[k], teams)
      hw <- (ps[h, ] > ps[a, ]) + 0.5 * (ps[h, ] == ps[a, ])
      wins[h, ] <- wins[h, ] + hw
      wins[a, ] <- wins[a, ] + (1 - hw)
      if (!is.null(h2h)) {
        h2h[h, a, ] <- h2h[h, a, ] + hw
        h2h[a, h, ] <- h2h[a, h, ] + (1 - hw)
      }
    }
    pf <- pf + ps
  }
  seed <- matrix(0L, n, S)
  for (s in seq_len(S)) {
    o <- s2_order(wins[, s], pf[, s], teams, tiebreak, if (is.null(h2h)) NULL else h2h[, , s])
    o <- s2_seed(o, teams, divisions)
    seed[o, s] <- seq_along(o)
  }
  N <- r$playoff_teams
  bracket <- S2_BRACKETS[[as.character(N)]]
  if (is.null(bracket)) cli::cli_abort("S2 v1 supports 2, 4, 6 or 8 playoff teams.")
  col <- seq_len(S)
  seed_team <- lapply(seq_len(N), function(k) apply(seed, 2, function(x) which(x == k)))   # team index per sim
  winners <- list()
  for (ri in seq_along(bracket)) {
    ps <- period_score(r$regular_periods + ri)
    side <- function(lab) {
      if (startsWith(lab, "S")) return(seed_team[[as.integer(substring(lab, 2))]])
      rg <- as.integer(strsplit(substring(lab, 2), ".", fixed = TRUE)[[1]])
      winners[[rg[1]]][[rg[2]]]
    }
    winners[[ri]] <- lapply(bracket[[ri]], function(m) {
      a <- side(m[1])
      b <- side(m[2])
      sa <- seed[cbind(a, col)]
      sb <- seed[cbind(b, col)]
      hi <- ifelse(sa < sb, a, b)
      lo <- ifelse(sa < sb, b, a)
      ifelse(ps[cbind(hi, col)] >= ps[cbind(lo, col)], hi, lo)   # a tie goes to the higher seed
    })
  }
  champ <- winners[[length(bracket)]][[1]]
  list(teams = teams, seed = seed, champion = teams[champ], wins = wins, points_for = pf, playoff_teams = N)
}
