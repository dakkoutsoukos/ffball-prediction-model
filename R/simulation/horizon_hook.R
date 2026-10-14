# VL3c: R3's adopted horizon spread for S0's current-week draws (E17's mechanical spread rule). Inert
# (NULL) until the newest archived horizon study adopts a position x lead-bin cell.

#' The newest archived horizon-study adoption table for a season, or NULL.
r3_latest_adoption <- function(season, root = HORIZON_ROOT) {
  files <- sort(list.files(file.path(root, sprintf("season=%d", season)), pattern = "^run=.*[.]json$", full.names = TRUE))
  if (!length(files)) return(NULL)
  res <- jsonlite::read_json(files[length(files)], simplifyVector = TRUE)
  ad <- tibble::as_tibble(res$adoption %||% list())
  if (!nrow(ad)) return(NULL)
  attr(ad, "source") <- basename(files[length(files)])
  ad
}

#' A function(ids, positions, teams) giving each current-week player's extra SD: sqrt(V-hat) of his
#' adopted position x lead-bin cell, 0 elsewhere (no kickoff this week, kickoff passed, unadopted cell).
#' Lead = the team's kickoff this week minus `now`. NULL when no cell is adopted (S0 unchanged).
r3_horizon_sd_fun <- function(adoption, team_games, season, week, now = Sys.time()) {
  if (is.null(adoption) || !any(adoption$spread_var > 0)) return(NULL)
  tg <- team_games[team_games$season == season & team_games$week == week, c("team", "kickoff_utc")]
  f <- function(ids, positions, teams) {
    ko <- tg$kickoff_utc[match(teams, tg$team)]
    lead <- as.numeric(difftime(ko, now, units = "hours"))
    bin <- hz_lead_bin(lead, rep(0L, length(lead)))
    v <- adoption$spread_var[match(paste(positions, bin), paste(adoption$position, adoption$lead_bin))]
    v[is.na(v) | is.na(lead) | lead < 0] <- 0
    sqrt(pmax(v, 0))
  }
  attr(f, "source") <- attr(adoption, "source") %||% "horizon study"
  f
}
