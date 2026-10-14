# I3 monitoring and alerting (pre-declaration VL13). The checks read local manifests and logs only:
# no ESPN request and no outcome. The calibration-drift e-processes are pure functions; loading outcomes
# for them goes through i3_drift_guard(), which refuses sealed seasons (2026 before R1).

I3_THRESHOLDS <- list(capture_warn_h = 30, capture_alert_h = 72, snapshot_warn_h = 24, snapshot_alert_h = 24 * 7,
                      valuation_warn_h = 30, dispatcher_alert_h = 3, mc_se_warn = 0.005, mc_se_alert = 0.01,
                      e_alarm = 20)

#' Parse the project's UTC stamps (20261007T060535Z or 2026-10-07T06:05:35Z).
i3_parse_utc <- function(x) {
  x <- as.character(x)
  a <- as.POSIXct(x, format = "%Y%m%dT%H%M%SZ", tz = "UTC")
  b <- as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  a[is.na(a)] <- b[is.na(a)]
  a
}

#' OK / WARN / ALERT for a value against thresholds (NA thresholds are skipped; a missing value warns).
i3_level <- function(value, warn = NA, alert = NA) {
  if (is.na(value)) return("WARN")
  if (!is.na(alert) && value > alert) return("ALERT")
  if (!is.na(warn) && value > warn) return("WARN")
  "OK"
}

#' Hours since the newest stamp in a CSV column (NA if the file or rows are missing).
i3_age_h <- function(path, column, now, filter = NULL) {
  if (!file.exists(path)) return(NA_real_)
  x <- readr::read_csv(path, col_types = readr::cols(.default = "c"), progress = FALSE)
  if (!is.null(filter)) x <- filter(x)
  if (!nrow(x) || !column %in% names(x)) return(NA_real_)
  t <- suppressWarnings(max(i3_parse_utc(x[[column]]), na.rm = TRUE))
  if (!is.finite(t)) return(NA_real_)
  as.numeric(difftime(now, t, units = "hours"))
}

#' Is there an NFL game within `days` of `now`? (Freshness thresholds apply in season only.)
i3_in_season <- function(team_games, now, days = 7) {
  if (is.null(team_games) || !nrow(team_games)) return(TRUE)
  any(abs(as.numeric(difftime(team_games$kickoff_utc, now, units = "days"))) <= days, na.rm = TRUE)
}

#' The VL13 health checks. `ledger_records`: the decision ledger's records (lg_ledger_read()$records);
#' `coverage`: post_report_coverage() rows for the target week (or NULL to skip).
i3_checks <- function(season, now = Sys.time(), team_games = NULL, coverage = NULL, ledger_records = NULL,
                      thresholds = I3_THRESHOLDS, capture_manifest = VALUATION_CAPTURE_MANIFEST,
                      snapshot_manifest = LG_SNAPSHOT_MANIFEST, valuation_manifest = VAL_MANIFEST,
                      dispatch_log = DISPATCH_LOG) {
  th <- thresholds
  in_season <- i3_in_season(team_games, now)
  of_season <- function(x) x[as.integer(x$season) == season, ]
  row <- function(check, value, unit, level, detail = "") tibble::tibble(check = check, value = value, unit = unit,
                                                                          level = level, detail = detail)
  fresh <- function(check, age, warn, alert) {
    if (!in_season) return(row(check, age, "h", "OK", "off season"))
    row(check, age, "h", i3_level(age, warn, alert), if (is.na(age)) "no record" else "")
  }
  cap <- i3_age_h(capture_manifest, "captured_at_utc", now, of_season)
  snap <- i3_age_h(snapshot_manifest, "captured_at_utc", now, of_season)
  val <- i3_age_h(valuation_manifest, "as_of_utc", now, of_season)
  disp <- i3_age_h(dispatch_log, "logged_at_utc", now)
  out <- list(fresh("capture_age", cap, th$capture_warn_h, th$capture_alert_h),
              fresh("league_snapshot_age", snap, th$snapshot_warn_h, th$snapshot_alert_h),
              fresh("valuation_run_age", val, th$valuation_warn_h, NA),
              row("dispatcher_last_entry", disp, "h", i3_level(disp, NA, th$dispatcher_alert_h),
                  if (is.na(disp)) "no dispatch log" else ""))
  # run coverage: games within the flag window without a post-report run (F0's flag)
  if (!is.null(coverage)) {
    n_flag <- if (nrow(coverage)) sum(coverage$flag) else 0L
    out <- c(out, list(row("games_without_post_report_run", n_flag, "games", if (n_flag > 0) "ALERT" else "OK")))
  }
  # ESPN refusals in the dispatch log (last 7 days)
  n401 <- 0L
  if (file.exists(dispatch_log)) {
    lg <- readr::read_csv(dispatch_log, col_types = readr::cols(.default = "c"), progress = FALSE)
    recent <- lg[!is.na(i3_parse_utc(lg$logged_at_utc)) & i3_parse_utc(lg$logged_at_utc) >= now - 7 * 86400, ]
    txt <- paste(recent$reason %||% "", recent$result %||% "")
    n401 <- sum(grepl("\\b401\\b", txt))
  }
  out <- c(out, list(row("espn_http_401_last_7_days", n401, "entries", if (n401 > 0) "ALERT" else "OK",
                         if (n401 > 0) "rotate the ESPN cookies (config/local.yml)" else "")))
  # Monte Carlo SE of the newest ledgered S0 odds
  odds <- Filter(function(r) identical(r$type, "odds"), ledger_records %||% list())
  if (length(odds)) {
    at <- vapply(odds, function(r) as.character(r$as_of_utc %||% NA), "")
    newest <- odds[[which.max(i3_parse_utc(at))]]
    sims <- suppressWarnings(as.numeric(newest$metrics$sims %||% NA))
    se <- if (is.na(sims) || sims <= 0) NA_real_ else sqrt(0.25 / sims)
    out <- c(out, list(row("odds_max_mc_se", se, "probability", i3_level(se, th$mc_se_warn, th$mc_se_alert),
                           if (is.na(sims)) "sims not recorded" else paste(sims, "simulations"))))
  }
  purrr::list_rbind(out)
}

#' Two-sided betting e-process for a binary indicator with null mean p0 (e.g. 80%-interval coverage):
#' the mean of two wealth processes betting on the indicator being above and below p0. Under the null
#' (conditional mean p0) it is a nonnegative martingale with mean 1, so P(sup >= 1/alpha) <= alpha.
i3_eprocess_coverage <- function(hit, p0 = 0.8, lambda = 0.5) {
  stopifnot(all(hit %in% c(0, 1)), lambda > 0, lambda < 1)
  up <- cumprod(1 + (lambda / p0) * (hit - p0))
  dn <- cumprod(1 - (lambda / (1 - p0)) * (hit - p0))
  (up + dn) / 2
}

#' One-sided e-process for "B beats A" on absolute errors (E16): d = |e_A| - |e_B| is bounded by the
#' predictable |pred_A - pred_B|, so x = d / bound lies in [-1, 1]. Mixture over fixed bets.
i3_eprocess_diff <- function(d, bound, lambdas = c(0.1, 0.25, 0.5)) {
  x <- ifelse(bound > 0, d / bound, 0)
  if (any(abs(x) > 1 + 1e-9)) cli::cli_abort("A difference exceeds its predictable bound.")
  x <- pmax(-1, pmin(1, x))
  w <- vapply(lambdas, function(l) cumprod(1 + l * x), numeric(length(x)))
  if (is.null(dim(w))) w <- matrix(w, nrow = length(x))
  rowMeans(w)
}

#' First index at which an e-process reaches the alarm level (NA if never).
i3_alarm_at <- function(e, level = I3_THRESHOLDS$e_alarm) {
  k <- which(e >= level)
  if (length(k)) k[1] else NA_integer_
}

#' Guard for loading outcomes into the drift monitor: the season must be usable for confirmatory
#' monitoring by the contamination register (2026 is sealed until the season is over), and in-season
#' (blind) use needs the season's prospective protocol to approve it (VL13).
i3_drift_guard <- function(season, family = "distribution_stack", register = read_contamination_register(),
                           season_over = FALSE, approved_in_season = FALSE) {
  assert_family_seasons(family, season, "confirmatory", register, season_over = season_over)
  if (!season_over && !approved_in_season) {
    cli::cli_abort("In-season drift monitoring of {season} needs approval in that season's prospective protocol (VL13).")
  }
  invisible(TRUE)
}

#' Print the I3 health panel (scripts/status.R and the D5 briefing): local files only.
print_health <- function(season, now = Sys.time()) {
  x <- i3_health(season, now)
  cli::cli_h2("Model and data health (I3)")
  for (i in seq_len(nrow(x))) {
    v <- if (is.na(x$value[i])) "NA" else format(round(x$value[i], 4))
    msg <- paste0(x$check[i], ": ", v, " ", x$unit[i], if (nzchar(x$detail[i])) paste0(" (", x$detail[i], ")") else "")
    switch(x$level[i], OK = cli::cli_alert_success("{msg}"), WARN = cli::cli_alert_warning("{msg}"),
           ALERT = cli::cli_alert_danger("{msg}"))
  }
  invisible(x)
}

#' The I3 checks with the live inputs: the schedule, this week's run coverage and the ledger.
i3_health <- function(season, now = Sys.time()) {
  sched <- tryCatch(latest_live_file("schedules", season, now), error = function(e) NA_character_)
  tg <- if (is.na(sched)) NULL else clean_team_games(sched, read_project_config()$season_type)
  cov <- NULL
  if (!is.null(tg)) {
    week <- infer_target_week(tg, season, now)
    if (!is.na(week)) cov <- tryCatch(post_report_coverage(season, week, tg, dispatch_runs(), now), error = function(e) NULL)
  }
  recs <- tryCatch(lg_ledger_read(alias = lg_credentials()$alias, season = season)$records, error = function(e) NULL)
  i3_checks(season, now, tg, cov, recs)
}
