# F6 decision laboratory v1: season data and the information firewall (pre-registration LAB1) -----
# The lab replays synthetic leagues on real NFL seasons. A season is held as player x week matrices
# built from the F4 frame. Policies never see these matrices: they receive lab_info(), which
# TRUNCATES them to what is known at the decision time, so future data cannot leak by construction.

LAB_WEEKS <- 1:16               # fantasy weeks: regular season 1-14, playoffs 15-16
LAB_REG_WEEKS <- 1:14
LAB_POSITIONS <- c("QB", "RB", "WR", "TE")
LAB_SLOTS <- list(QB = 1L, RB = 2L, WR = 2L, TE = 1L, FLEX = 2L)
LAB_FLEX <- c("RB", "WR", "TE")
LAB_ROSTER <- 15L               # 8 starters + 7 bench
LAB_DEV_SEASONS <- 2020:2023
LAB_WARMUP <- 2019L

#' Mean of the last up-to-4 positive values in each row, as of each column (NA before the first).
lab_level_avg4 <- function(proj) {
  P <- nrow(proj)
  buf <- matrix(NA_real_, P, 4)
  out <- matrix(NA_real_, P, ncol(proj))
  for (w in seq_len(ncol(proj))) {
    hit <- !is.na(proj[, w]) & proj[, w] > 0
    if (any(hit)) {
      buf[hit, 2:4] <- buf[hit, 1:3]
      buf[hit, 1] <- proj[hit, w]
    }
    n <- rowSums(!is.na(buf))
    out[, w] <- ifelse(n > 0, rowSums(buf, na.rm = TRUE) / pmax(n, 1), NA_real_)
  }
  out
}

#' Last known value along each row, as of each column.
lab_carry_forward <- function(m) {
  for (w in seq_len(ncol(m))[-1]) {
    miss <- is.na(m[, w])
    m[miss, w] <- m[miss, w - 1]
  }
  m
}

#' One season as player x week matrices (fantasy weeks 1-16) from the F4 frame. Position per
#' player-season is his most frequent position (ties: alphabetical).
lab_season_data <- function(frame, team_games, season, weeks = LAB_WEEKS) {
  d <- frame[frame$season == season & frame$week %in% weeks & frame$position %in% LAB_POSITIONS, ]
  if (!nrow(d)) cli::cli_abort("No F4 rows for season {season}.")
  pos <- dplyr::count(d, .data$gsis_id, .data$position) |>
    dplyr::arrange(.data$gsis_id, dplyr::desc(.data$n), .data$position) |>
    dplyr::distinct(.data$gsis_id, .keep_all = TRUE)
  ids <- sort(unique(d$gsis_id))
  P <- length(ids)
  W <- length(weeks)
  ij <- cbind(match(d$gsis_id, ids), match(d$week, weeks))
  mat <- function(x, fill = NA_real_) {
    m <- matrix(fill, P, W)
    m[ij] <- x
    m
  }
  has_row <- mat(TRUE, FALSE)
  team <- mat(d$team, NA_character_)
  tg <- team_games[team_games$season == season & team_games$week %in% weeks, ]
  teams <- sort(unique(tg$team))
  plays <- matrix(FALSE, length(teams), W, dimnames = list(teams, NULL))
  plays[cbind(match(tg$team, teams), match(tg$week, weeks))] <- TRUE
  proj <- mat(d$espn_proj)
  list(season = as.integer(season), weeks = weeks, ids = ids, pos = pos$position[match(ids, pos$gsis_id)],
       proj = proj, base = mat(d$base), y = mat(d$actual), active = mat(d$active, NA), has_row = has_row,
       team = team, team_asof = lab_carry_forward(team), L = lab_level_avg4(proj), plays = plays, teams = teams,
       draft_value = lab_draft_values(frame, season, ids, proj[, 1]))
}

#' Pre-draft value (LAB1b): the player's mean positive ESPN projection in the previous season (at
#' least 4 projected weeks); otherwise his week-1 projection when positive; otherwise NA (not
#' drafted). Robust to a defective week-1 file (2023 week 1 has 64 positive projections of 784).
lab_draft_values <- function(frame, season, ids, week1, min_weeks = 4L) {
  prev <- frame[frame$season == season - 1L & !is.na(frame$espn_proj) & frame$espn_proj > 0, ]
  pm <- dplyr::summarise(prev, n = dplyr::n(), v = mean(.data$espn_proj), .by = "gsis_id")
  pm <- pm[pm$n >= min_weeks, ]
  v <- pm$v[match(ids, pm$gsis_id)]
  w1 <- ifelse(!is.na(week1) & week1 > 0, week1, NA_real_)
  dplyr::coalesce(v, w1)
}

#' The information firewall. What a policy may see at a decision time:
#'   draft          week-1 pregame values (ESPN week-of projection, base), positions
#'   waiver before t everything from weeks <= t-1; the season's bye schedule
#'   lineup at t    everything from weeks <= t-1, plus week t's ESPN projection and base
#' Matrices are truncated by column, so nothing later exists inside the object.
lab_info <- function(S, t, stage = c("draft", "waiver", "lineup")) {
  stage <- match.arg(stage)
  past <- switch(stage, draft = 0L, waiver = t - 1L, lineup = t - 1L)
  pre <- switch(stage, draft = 1L, waiver = t - 1L, lineup = as.integer(t))
  cut <- function(m, k) m[, seq_len(k), drop = FALSE]
  structure(list(stage = stage, t = as.integer(t), season = S$season, ids = S$ids, pos = S$pos,
                 draft_value = S$draft_value, proj = cut(S$proj, pre), base = cut(S$base, pre),
                 y = cut(S$y, past), active = cut(S$active, past), has_row = cut(S$has_row, past),
                 team = cut(S$team, past), team_asof = cut(S$team_asof, past), L = cut(S$L, past),
                 plays = S$plays, teams = S$teams, n_weeks = length(S$weeks)),
            class = "lab_info")
}

#' Rolling-origin waiver calibration: per position, OLS of the points in each of the next 1-4 weeks
#' the player's team plays (0 without a row) on L_avg4 as of week w (weeks 1-15), over the training
#' seasons. The lab applies the coefficients of seasons < s to season s.
lab_waiver_calibration <- function(frame, team_games, train_seasons, horizon = 4L) {
  rows <- purrr::map(train_seasons, function(s) {
    S <- lab_season_data(frame, team_games, s)
    W <- length(S$weeks)
    purrr::map(seq_len(W - 1), function(w) {
      ok <- !is.na(S$L[, w]) & !is.na(S$team_asof[, w])
      if (!any(ok)) return(NULL)
      i <- which(ok)
      purrr::map(seq(w + 1, min(w + horizon, W)), function(u) {
        plays <- S$plays[cbind(match(S$team_asof[i, w], S$teams), u)]
        plays[is.na(plays)] <- FALSE
        k <- i[plays]
        if (!length(k)) return(NULL)
        tibble::tibble(position = S$pos[k], L = S$L[k, w], y = dplyr::coalesce(S$y[k, u], 0))
      }) |> purrr::list_rbind()
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
  purrr::map(LAB_POSITIONS, function(p) {
    r <- rows[rows$position == p, ]
    co <- stats::coef(stats::lm(y ~ L, data = r))
    tibble::tibble(position = p, a = unname(co[1]), b = unname(co[2]), n = nrow(r))
  }) |> purrr::list_rbind()
}
