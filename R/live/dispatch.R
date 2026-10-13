# Kickoff-keyed run dispatcher (master plan F0) ------------------------------------------------
# Decides WHEN a prospective run is due, from the NFL schedule and the archive manifest:
#   - an early-week run, once per week (from the morning after the previous week's last game until
#     the day before the week's first kickoff);
#   - a post-report run per slate in [first kickoff - 3 h, first kickoff - 1.5 h): after every team's
#     final injury report and before game-day inactives (about kickoff - 90 min);
#   - a catch-up run until first kickoff - 30 min when the window was missed (PC off, failed run).
# A slate is the set of games on one US/Eastern calendar date. A morning game (before 12:00 ET,
# e.g. an international game) on a date with later games is its own slate.
# Pure decisions only: nothing here contacts ESPN, runs a model, commits or pushes. The scheduled
# entry point scripts/ops_dispatch.R executes due runs (docs/prospective_protocol.md, Automation).

DISPATCH_TZ <- "America/New_York"
DISPATCH_ROOT <- "data/ops"
DISPATCH_LOG <- file.path(DISPATCH_ROOT, "dispatch_log.csv")
DISPATCH_STATUS <- file.path(DISPATCH_ROOT, "status.txt")
DISPATCH_LOCK <- file.path(DISPATCH_ROOT, "dispatch.lock")
VALUATION_CAPTURE_MANIFEST <- "archive/valuation_espn_capture_manifest.csv"

DISPATCH_DEFAULTS <- list(
  window_start_h = 3, window_end_h = 1.5, catchup_end_min = 30,
  early_after_prev_h = 12, early_from_first_h = 72, early_until_first_h = 24,
  morning_split_hour = 12, post_report_fallback_h = 26, flag_within_h = 3,
  max_attempts = 2, lock_stale_h = 3
)

#' NFL season of a date: January-February games belong to the previous season.
nfl_season <- function(time = Sys.time()) {
  d <- as.POSIXlt(time, tz = DISPATCH_TZ)
  as.integer(d$year + 1900L - (d$mon < 2L))
}

#' The slates of one week, with their run windows.
dispatch_slates <- function(team_games, season, week, cfg = DISPATCH_DEFAULTS) {
  g <- team_games |>
    dplyr::filter(.data$season == !!season, .data$week == !!week) |>
    dplyr::distinct(.data$game_id, .data$kickoff_utc)
  if (!nrow(g)) {
    return(tibble::tibble(slate_id = character(), first_kickoff_utc = as.POSIXct(character(), tz = "UTC"),
                          last_kickoff_utc = as.POSIXct(character(), tz = "UTC"), n_games = integer(),
                          game_ids = list(), window_start = as.POSIXct(character(), tz = "UTC"),
                          window_end = as.POSIXct(character(), tz = "UTC"), catchup_end = as.POSIXct(character(), tz = "UTC")))
  }
  et_date <- format(g$kickoff_utc, "%Y-%m-%d", tz = DISPATCH_TZ)
  morning <- as.integer(format(g$kickoff_utc, "%H", tz = DISPATCH_TZ)) < cfg$morning_split_hour
  has_later <- tapply(!morning, et_date, any)[et_date]
  g$slate_id <- paste0(et_date, ifelse(morning & has_later, "_am", ""))
  g |>
    dplyr::summarise(first_kickoff_utc = min(.data$kickoff_utc), last_kickoff_utc = max(.data$kickoff_utc),
                     n_games = dplyr::n(), game_ids = list(sort(.data$game_id)), .by = "slate_id") |>
    dplyr::arrange(.data$first_kickoff_utc) |>
    dplyr::mutate(window_start = .data$first_kickoff_utc - cfg$window_start_h * 3600,
                  window_end = .data$first_kickoff_utc - cfg$window_end_h * 3600,
                  catchup_end = .data$first_kickoff_utc - cfg$catchup_end_min * 60)
}

#' The early-week window of a week: from `early_after_prev_h` after the previous week's last
#' kickoff (and no earlier than `early_from_first_h` before the first kickoff) until
#' `early_until_first_h` before the week's first kickoff.
dispatch_early_window <- function(team_games, season, week, cfg = DISPATCH_DEFAULTS) {
  ko <- team_games$kickoff_utc[team_games$season == season & team_games$week == week]
  if (!length(ko)) return(list(start = NA, end = NA))
  first <- min(ko)
  prev <- team_games$kickoff_utc[team_games$season == season & team_games$week < week]
  start <- first - cfg$early_from_first_h * 3600
  if (length(prev)) start <- max(start, max(prev) + cfg$early_after_prev_h * 3600)
  list(start = start, end = first - cfg$early_until_first_h * 3600)
}

#' Standard-horizon runs from the prediction manifest, with parsed times.
dispatch_runs <- function(manifest = PREDICTION_MANIFEST) {
  if (!file.exists(manifest)) {
    return(tibble::tibble(run_id = character(), season = integer(), week = integer(),
                          predicted_at = as.POSIXct(character(), tz = "UTC")))
  }
  readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::transmute(run_id = .data$run_id, season = as.integer(.data$season), week = as.integer(.data$week),
                     predicted_at = as.POSIXct(.data$predicted_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}

#' Number of earlier dispatch attempts for one slate (from the dispatch log).
dispatch_attempts <- function(log, season, week, slate_id) {
  if (is.null(log) || !nrow(log)) return(0L)
  sum(log$action == "run" & as.integer(log$season) == season & as.integer(log$week) == week &
        log$slate_id == slate_id, na.rm = TRUE)
}

read_dispatch_log <- function(path = DISPATCH_LOG) {
  if (!file.exists(path)) return(NULL)
  readr::read_csv(path, col_types = readr::cols(.default = "c"))
}

#' Is a run due at `now`? Returns a list: action ("run" / "none"), kind ("slate", "catch-up",
#' "early-week"), reason, season, week, slate_id, and the next due time when none is due.
dispatch_decision <- function(now, team_games, season, runs, log = NULL, cfg = DISPATCH_DEFAULTS) {
  out <- function(action, reason, week = NA_integer_, kind = NA_character_, slate_id = NA_character_, next_due = NA) {
    list(action = action, kind = kind, reason = reason, season = as.integer(season), week = as.integer(week),
         slate_id = slate_id, next_due = next_due)
  }
  week <- infer_target_week(team_games, season, now)
  if (is.na(week)) return(out("none", "no upcoming regular-season game"))
  slates <- dispatch_slates(team_games, season, week, cfg)
  wk <- runs[runs$season == season & runs$week == week, ]
  pending <- slates[slates$first_kickoff_utc > now, ]
  for (i in seq_len(nrow(pending))) {
    s <- pending[i, ]
    if (now < s$window_start || now >= s$catchup_end) next
    if (any(wk$predicted_at >= s$window_start & wk$predicted_at < s$first_kickoff_utc)) next
    if (dispatch_attempts(log, season, week, s$slate_id) >= cfg$max_attempts) {
      return(out("none", sprintf("slate %s: attempt limit (%d) reached; check data/ops logs", s$slate_id, cfg$max_attempts),
                 week, "slate", s$slate_id))
    }
    kind <- if (now < s$window_end) "slate" else "catch-up"
    return(out("run", sprintf("slate %s (first kickoff %s): %s", s$slate_id, fmt_utc(s$first_kickoff_utc),
                              if (kind == "slate") "post-report window" else "window missed, catching up before kickoff"),
               week, kind, s$slate_id))
  }
  ew <- dispatch_early_window(team_games, season, week, cfg)
  if (!is.na(ew$start) && now >= ew$start && now < ew$end && !nrow(wk)) {
    if (dispatch_attempts(log, season, week, "early") >= cfg$max_attempts) {
      return(out("none", "early-week run: attempt limit reached", week, "early-week", "early"))
    }
    return(out("run", "early-week run (no run for this week yet)", week, "early-week", "early"))
  }
  # nothing due: when is the next window?
  cand <- pending$window_start[pending$window_start > now &
                                 !vapply(seq_len(nrow(pending)), function(i) any(wk$predicted_at >= pending$window_start[i] &
                                                                                    wk$predicted_at < pending$first_kickoff_utc[i]), logical(1))]
  if (!is.na(ew$start) && !nrow(wk) && ew$start > now) cand <- c(cand, ew$start)
  out("none", "no run due", week, next_due = if (length(cand)) min(cand) else NA)
}

#' Teams whose FINAL injury report is in a run's injury capture, from its run_meta.json.
run_final_teams <- function(run_id, season, week, team_games, root = FORECAST_HORIZONS$standard_pregame$archive_root) {
  meta <- file.path(root, sprintf("season=%d", season), sprintf("week=%02d", week), paste0("run=", run_id), "run_meta.json")
  none <- list(final = character(), captured_at = as.POSIXct(NA, tz = "UTC"))
  if (!file.exists(meta)) return(none)
  inj <- jsonlite::read_json(meta)$live_files$injuries
  if (is.null(inj) || !file.exists(inj)) return(none)
  captured <- parse_utc_stamp(sub("^retrieved_at=(.*)[.]parquet$", "\\1", basename(inj)))
  d <- live_injury_detail(inj, team_games, captured, season, week)
  list(final = attr(d, "final_teams"), captured_at = captured)
}

#' Per game of a week: the latest run made before kickoff (and before `now`), and whether it was
#' made after BOTH teams' final injury reports. A team counts as reported if its final report
#' (>= 1 game designation) is in the run's injury capture, or if the capture is within
#' `post_report_fallback_h` of kickoff (teams with no designations never show a "final" report).
#' `flag` marks games within `flag_within_h` of kickoff that still lack a post-report run.
post_report_coverage <- function(season, week, team_games, runs, now = Sys.time(), cfg = DISPATCH_DEFAULTS,
                                 final_fn = run_final_teams) {
  games <- team_games |>
    dplyr::filter(.data$season == !!season, .data$week == !!week) |>
    dplyr::summarise(kickoff_utc = min(.data$kickoff_utc), teams = list(sort(unique(.data$team))), .by = "game_id") |>
    dplyr::arrange(.data$kickoff_utc)
  if (!nrow(games)) return(tibble::tibble())
  wk <- runs[runs$season == season & runs$week == week & runs$predicted_at <= now, ]
  memo <- list()
  finals <- function(run_id) {
    if (is.null(memo[[run_id]])) memo[[run_id]] <<- final_fn(run_id, season, week, team_games)
    memo[[run_id]]
  }
  slates <- dispatch_slates(team_games, season, week, cfg)
  slate_of <- stats::setNames(rep(slates$slate_id, lengths(slates$game_ids)), unlist(slates$game_ids))
  rows <- purrr::map(seq_len(nrow(games)), function(i) {
    k <- games$kickoff_utc[i]
    ok <- wk$predicted_at < k
    run <- if (any(ok)) wk$run_id[ok][which.max(wk$predicted_at[ok])] else NA_character_
    at <- if (any(ok)) max(wk$predicted_at[ok]) else as.POSIXct(NA, tz = "UTC")
    post <- FALSE
    if (!is.na(run)) {
      f <- finals(run)
      late_enough <- !is.na(f$captured_at) && f$captured_at >= k - cfg$post_report_fallback_h * 3600
      post <- all(games$teams[[i]] %in% f$final) || late_enough
    }
    hours <- as.numeric(difftime(k, now, units = "hours"))
    tibble::tibble(game_id = games$game_id[i], slate_id = unname(slate_of[games$game_id[i]]), kickoff_utc = k,
                   teams = paste(games$teams[[i]], collapse = "-"), started = k <= now,
                   latest_run = run, run_at = at, post_report = post,
                   hours_to_kickoff = round(hours, 2),
                   flag = !(k <= now) && !post && hours <= cfg$flag_within_h)
  })
  purrr::list_rbind(rows)
}

#' Season-to-date operations record (F0 success criteria): games that have kicked off since
#' `from_week` with a pre-kickoff run and with a post-report run. No outcome is read.
ops_coverage_report <- function(season, team_games, runs, from_week, now = Sys.time(), cfg = DISPATCH_DEFAULTS,
                                final_fn = run_final_teams) {
  weeks <- sort(unique(team_games$week[team_games$season == season & team_games$week >= from_week &
                                         team_games$kickoff_utc <= now]))
  cov <- purrr::map(weeks, function(w) {
    post_report_coverage(season, w, team_games, runs, now, cfg, final_fn) |>
      dplyr::filter(.data$started) |>
      dplyr::mutate(week = w, .before = 1)
  }) |>
    purrr::list_rbind()
  if (!nrow(cov)) {
    return(list(games = cov, n_games = 0L, share_any_run = NA_real_, share_post_report = NA_real_))
  }
  list(games = cov, n_games = nrow(cov), share_any_run = mean(!is.na(cov$latest_run)),
       share_post_report = mean(cov$post_report))
}

#' All-position ESPN capture cadence per week (F0 criterion: >= 2 capture times per week).
capture_cadence <- function(season, manifest = VALUATION_CAPTURE_MANIFEST) {
  if (!file.exists(manifest)) return(tibble::tibble(week = integer(), captures = integer()))
  readr::read_csv(manifest, col_types = readr::cols(.default = "c")) |>
    dplyr::filter(as.integer(.data$season) == !!season) |>
    dplyr::summarise(captures = dplyr::n_distinct(.data$captured_at_utc), .by = "week") |>
    dplyr::mutate(week = as.integer(.data$week)) |>
    dplyr::arrange(.data$week)
}

fmt_et <- function(t) if (length(t) == 0 || all(is.na(t))) "-" else format(t, "%a %Y-%m-%d %H:%M ET", tz = DISPATCH_TZ)

#' Human-readable status lines for the status file and the console.
dispatch_status_lines <- function(now, decision, coverage, cadence = NULL, git = NULL, last = NULL) {
  l <- c(sprintf("FFball dispatcher status - %s (%s)", fmt_utc(now), fmt_et(now)),
         sprintf("Decision: %s%s - %s", decision$action, if (is.na(decision$kind)) "" else paste0(" [", decision$kind, "]"),
                 decision$reason))
  if (!is.na(decision$week)) l <- c(l, sprintf("Target: season %d week %d", decision$season, decision$week))
  if (length(decision$next_due) && !is.na(decision$next_due)) l <- c(l, sprintf("Next window opens: %s", fmt_et(decision$next_due)))
  if (!is.null(last)) l <- c(l, sprintf("Last run attempt: %s", last))
  if (!is.null(coverage) && nrow(coverage)) {
    up <- coverage[!coverage$started, ]
    l <- c(l, sprintf("Upcoming games: %d; with a pre-kickoff run: %d; with a post-report run: %d",
                      nrow(up), sum(!is.na(up$latest_run)), sum(up$post_report)))
    fl <- coverage[coverage$flag, ]
    if (nrow(fl)) {
      l <- c(l, sprintf("ALERT: %d game(s) within 3 h of kickoff lack a post-report run: %s", nrow(fl),
                        paste(sprintf("%s (%s)", fl$teams, fmt_et(fl$kickoff_utc)), collapse = "; ")))
    }
  }
  if (!is.null(cadence) && nrow(cadence)) {
    l <- c(l, sprintf("All-position captures per week: %s", paste(sprintf("W%d=%d", cadence$week, cadence$captures), collapse = " ")))
  }
  if (!is.null(git)) {
    if (isTRUE(git$manifests_uncommitted)) l <- c(l, "COMMIT NEEDED: archive manifests have uncommitted changes (git add archive/*.csv && git commit).")
    if (isTRUE(git$commits_not_pushed > 0)) l <- c(l, sprintf("PUSH NEEDED: %d local commit(s) not on origin (git push before kickoff).", git$commits_not_pushed))
    if (isTRUE(git$code_dirty)) l <- c(l, "WARNING: tracked code has uncommitted changes; scheduled runs will be skipped until it is committed.")
  }
  l
}

#' Lock against overlapping dispatcher runs; a lock older than `stale_h` is ignored.
dispatch_lock <- function(path = DISPATCH_LOCK, now = Sys.time(), stale_h = DISPATCH_DEFAULTS$lock_stale_h) {
  if (file.exists(path)) {
    age <- as.numeric(difftime(now, file.mtime(path), units = "hours"))
    if (age < stale_h) return(FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(as.character(Sys.getpid()), fmt_utc(now)), path)
  TRUE
}

dispatch_unlock <- function(path = DISPATCH_LOCK) if (file.exists(path)) unlink(path)

#' Console section for scripts/status.R: dispatcher decision (dry), post-report coverage of the
#' upcoming games, all-position capture cadence, and the scheduled task's last status file.
print_ops_status <- function(season, now = Sys.time()) {
  sched <- tryCatch(latest_live_file("schedules", season, now), error = function(e) NA_character_)
  if (is.na(sched)) return(invisible(NULL))
  tg <- clean_team_games(sched, read_project_config()$season_type)
  runs <- dispatch_runs()
  dec <- dispatch_decision(now, tg, season, runs, read_dispatch_log())
  cli::cli_h2("Scheduled operations (F0)")
  cli::cli_text("Dispatcher now: {dec$action}{if (is.na(dec$kind)) '' else paste0(' [', dec$kind, ']')} - {dec$reason}")
  if (length(dec$next_due) && !is.na(dec$next_due)) cli::cli_text("Next run window opens {fmt_et(dec$next_due)}.")
  week <- infer_target_week(tg, season, now)
  if (!is.na(week)) {
    cov <- tryCatch(post_report_coverage(season, week, tg, runs, now), error = function(e) NULL)
    if (!is.null(cov) && nrow(cov)) {
      up <- cov[!cov$started, ]
      cli::cli_text("Week {week}: {sum(up$post_report)} of {nrow(up)} upcoming game{?s} have a post-report run.")
      for (i in which(cov$flag)) {
        cli::cli_alert_danger("{cov$teams[i]} kicks off {fmt_et(cov$kickoff_utc[i])} with no post-report run.")
      }
    }
  }
  cad <- capture_cadence(season)
  if (nrow(cad)) cli::cli_text("All-position captures per week: {paste(sprintf('W%d=%d', cad$week, cad$captures), collapse = ' ')}")
  if (file.exists(DISPATCH_STATUS)) {
    cli::cli_text("Scheduled-task status file last written {fmt_utc(file.mtime(DISPATCH_STATUS))}: {.file {DISPATCH_STATUS}}")
  } else {
    cli::cli_alert_info("No scheduled-task status file yet ({.file {DISPATCH_STATUS}}); see scripts/ops_setup.R.")
  }
  invisible(dec)
}

# --- Task Scheduler wrapper (owner decision O1) -----------------------------------------------

#' Windows path with backslashes.
win_path <- function(p) gsub("/", "\\\\", normalizePath(p, winslash = "/", mustWork = FALSE))

#' Contents of the git-ignored .cmd wrapper the scheduled task runs (quoted absolute paths:
#' the project path contains spaces). A scheduled task has no HOME; R on Windows then sets HOME to
#' Documents, and git (called from R) misses the user's ~/.gitconfig identity, so HOME defaults to
#' the user profile, as in an interactive shell.
ops_wrapper_cmd <- function(project_root, rscript) {
  c("@echo off",
    "rem Generated by scripts/ops_setup.R (FFball master plan F0). Local commits only; never pushes.",
    'if not defined HOME set "HOME=%USERPROFILE%"',
    sprintf('cd /d "%s"', win_path(project_root)),
    'if not exist "data\\ops\\logs" mkdir "data\\ops\\logs"',
    sprintf('"%s" scripts\\ops_dispatch.R %%* >> "data\\ops\\logs\\wrapper.log" 2>&1', win_path(rscript)),
    "exit /b %ERRORLEVEL%")
}

xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

#' Task Scheduler definition: hourly at :05 from `start` (local time), only while `user` is
#' logged on (no stored password), hidden via conhost --headless, allowed on battery, started as
#' soon as possible after a missed trigger, one instance at a time, killed after 2 hours.
ops_task_xml <- function(cmd_path, project_root, user, start) {
  c('<?xml version="1.0" encoding="UTF-16"?>',
    '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">',
    "  <RegistrationInfo>",
    "    <Description>FFball pre-slate dispatcher (master plan F0). Hourly; runs a prospective run only when one is due (scripts/ops_dispatch.R). Local commits only; never pushes.</Description>",
    "  </RegistrationInfo>",
    "  <Triggers>",
    "    <TimeTrigger>",
    "      <Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>",
    sprintf("      <StartBoundary>%s</StartBoundary>", format(start, "%Y-%m-%dT%H:%M:%S")),
    "      <Enabled>true</Enabled>",
    "    </TimeTrigger>",
    "  </Triggers>",
    "  <Principals>",
    '    <Principal id="Author">',
    sprintf("      <UserId>%s</UserId>", xml_escape(user)),
    "      <LogonType>InteractiveToken</LogonType>",
    "      <RunLevel>LeastPrivilege</RunLevel>",
    "    </Principal>",
    "  </Principals>",
    "  <Settings>",
    "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>",
    "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>",
    "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>",
    "    <AllowHardTerminate>true</AllowHardTerminate>",
    "    <StartWhenAvailable>true</StartWhenAvailable>",
    "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>",
    "    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>",
    "    <AllowStartOnDemand>true</AllowStartOnDemand>",
    "    <Enabled>true</Enabled>",
    "    <Hidden>false</Hidden>",
    "    <RunOnlyIfIdle>false</RunOnlyIfIdle>",
    "    <WakeToRun>false</WakeToRun>",
    "    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>",
    "    <Priority>7</Priority>",
    "  </Settings>",
    '  <Actions Context="Author">',
    "    <Exec>",
    "      <Command>C:\\Windows\\System32\\conhost.exe</Command>",
    sprintf('      <Arguments>--headless "%s"</Arguments>', xml_escape(win_path(cmd_path))),
    sprintf("      <WorkingDirectory>%s</WorkingDirectory>", xml_escape(win_path(project_root))),
    "    </Exec>",
    "  </Actions>",
    "</Task>")
}

# --- Push-time records for the late-push sensitivity analysis (E16 section 4) ----------------
PUSH_LOG <- file.path(DISPATCH_ROOT, "push_log.csv")
UPSTREAM_LOG <- file.path(DISPATCH_ROOT, "upstream_log.csv")

#' Contents of the git pre-push hook: logs every push attempt (UTC time, remote, remote ref,
#' pushed commit) to data/ops/push_log.csv. It always exits 0, so it never blocks a push.
push_log_hook <- function() {
  c("#!/bin/sh",
    "# FFball (master plan F1, E16): log push attempts for the late-push sensitivity analysis.",
    "# Installed by scripts/ops_setup.R --install-push-log. Never blocks a push.",
    "mkdir -p data/ops",
    "[ -f data/ops/push_log.csv ] || echo 'attempted_at_utc,remote,remote_ref,local_sha' > data/ops/push_log.csv",
    "while read local_ref local_sha remote_ref remote_sha; do",
    "  printf '%s,%s,%s,%s\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \"$1\" \"$remote_ref\" \"$local_sha\" >> data/ops/push_log.csv",
    "done",
    "exit 0")
}

#' Record the remote-tracking ref (what origin had at the last push or fetch) when it changes.
#' The first observation of a commit bounds its push time from above (hourly resolution).
record_upstream <- function(path = UPSTREAM_LOG, now = Sys.time()) {
  sha <- tryCatch(suppressWarnings(system2("git", c("rev-parse", "@{u}"), stdout = TRUE, stderr = FALSE)),
                  error = function(e) character())
  if (length(sha) != 1 || !grepl("^[0-9a-f]{40}$", sha)) return(invisible(NA_character_))
  last <- if (file.exists(path)) utils::tail(readr::read_csv(path, col_types = "cc")$upstream_sha, 1) else NA_character_
  if (!identical(last, sha)) {
    append_manifest(tibble::tibble(observed_at_utc = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), upstream_sha = sha), path)
  }
  invisible(sha)
}

#' Write lines as UTF-16LE with a byte-order mark (what schtasks /XML expects).
write_utf16 <- function(lines, path) {
  txt <- paste0(paste(lines, collapse = "\r\n"), "\r\n")
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.raw(c(0xFF, 0xFE)), con)
  writeBin(iconv(txt, "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]], con)
  invisible(path)
}
