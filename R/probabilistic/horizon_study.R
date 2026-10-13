# R3 forecast-horizon study (master plan R3; pre-registration E17, amended by E17a) -------------
# How far do ESPN's projections move between an early capture and ESPN's final (late-horizon)
# projection, by position, lead time, band and status? Are the revisions approximately a
# martingale? PROJECTIONS ONLY: the final-projection parser keeps ESPN source 1 (projections) and
# never reads source 0 (actual points), so the study is outcome-free and may run in season.
# Active rows: early value v > 0 and final f > 0; v > 0 with f = 0 are availability transitions.

HZ_HOUR_BREAKS <- c(0, 24, 72, 120, Inf)
HZ_HOUR_LABELS <- c("<24h", "24-72h", "72-120h", ">120h")
HZ_WEEK_LABELS <- c("1wk", "2wk", "3-4wk", "5-8wk", "9+wk")
HZ_MIN_WEEKS <- 4L
HORIZON_ROOT <- "data/archive/horizon_study"
HORIZON_MANIFEST <- "archive/horizon_manifest.csv"

#' All-position valuation captures of a season: early values v per (player, target week, capture).
hz_captures <- function(season, root = VAL_ESPN_SNAPSHOT_ROOT) {
  files <- list.files(file.path(root, sprintf("season=%d", season)), pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE)
  if (!length(files)) return(tibble::tibble())
  purrr::map(files, function(f) {
    x <- arrow::read_parquet(f, mmap = FALSE)
    cw <- as.integer(sub(".*week=([0-9]+).*", "\\1", f))
    at <- parse_utc_stamp(sub("^captured_at=(.*)[.]parquet$", "\\1", basename(f)))   # the write-once file's own stamp
    tibble::tibble(espn_id = as.character(x$espn_id), position = x$position, team = x$team, week = as.integer(x$week),
                   v = as.numeric(x$applied_total), status = x$injury_status,
                   captured_at = at, capture_week = cw, file = basename(f))
  }) |>
    purrr::list_rbind() |>
    dplyr::filter(.data$position %in% POD_POSITIONS)
}

#' ESPN's final (after-the-fact) projections for completed weeks: source 1 only, never actuals.
hz_finals <- function(season, weeks, qbrbte_root = VAL_ESPN_RAW_ROOT, wr_root = "data/raw/espn") {
  paths <- c(file.path(qbrbte_root, sprintf("season=%d", season), sprintf("espn_qbrbte_%d_w%02d.json.gz", season, weeks)),
             file.path(wr_root, sprintf("season=%d", season), sprintf("espn_wr_%d_w%02d.json.gz", season, weeks)))
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(tibble::tibble(espn_id = character(), week = integer(), f = numeric()))
  purrr::map(paths, function(p) {
    w <- as.integer(sub(".*_w([0-9]{2})[.]json[.]gz$", "\\1", p))
    val_parse_espn(read_gz_text(p), season, periods = w, sources = 1L)
  }) |>
    purrr::list_rbind() |>
    dplyr::filter(.data$source == 1L) |>
    dplyr::transmute(espn_id = as.character(.data$espn_id), week = as.integer(.data$week), f = .data$applied_total) |>
    dplyr::distinct(.data$espn_id, .data$week, .keep_all = TRUE)
}

hz_lead_bin <- function(lead_h, k) {
  out <- ifelse(k == 0, as.character(cut(lead_h, HZ_HOUR_BREAKS, labels = HZ_HOUR_LABELS, right = FALSE)), NA_character_)
  out[k == 1] <- "1wk"
  out[k == 2] <- "2wk"
  out[k >= 3 & k <= 4] <- "3-4wk"
  out[k >= 5 & k <= 8] <- "5-8wk"
  out[k >= 9] <- "9+wk"
  out
}

#' Analysis frame: captures joined to finals and to each player's kickoff.
hz_frame <- function(caps, finals, team_games) {
  ko <- dplyr::distinct(team_games, .data$week, team = .data$team, .data$kickoff_utc)
  caps |>
    dplyr::inner_join(finals, by = c("espn_id", "week")) |>
    dplyr::left_join(ko, by = c("week", "team")) |>
    dplyr::filter(!is.na(.data$kickoff_utc)) |>
    dplyr::mutate(lead_h = as.numeric(difftime(.data$kickoff_utc, .data$captured_at, units = "hours")),
                  k = .data$week - .data$capture_week) |>
    dplyr::filter(.data$lead_h > 0, .data$k >= 0) |>
    dplyr::mutate(lead_bin = hz_lead_bin(.data$lead_h, .data$k), band = pd_band(.data$v),
                  status3 = dplyr::case_when(.data$status %in% c("ACTIVE", "NORMAL") ~ "ACTIVE",
                                             .data$status == "QUESTIONABLE" ~ "QUESTIONABLE", TRUE ~ "OTHER"),
                  active = .data$v > 0 & .data$f > 0, transition = .data$v > 0 & .data$f == 0, r = .data$f - .data$v)
}

#' Player-cluster bootstrap of the mean and variance of revisions in one cell.
hz_boot <- function(r, player, reps = 2000, seed = 1) {
  groups <- split(r, player)
  set.seed(seed)
  b <- replicate(reps, {
    x <- unlist(groups[sample.int(length(groups), replace = TRUE)], use.names = FALSE)
    c(mean(x), stats::var(x))
  })
  list(mean_ci = unname(stats::quantile(b[1, ], c(0.025, 0.975))), var_ci = unname(stats::quantile(b[2, ], c(0.025, 0.975), na.rm = TRUE)))
}

#' Revision drift and variance by position x lead bin (and x band where a cell has >= 200 rows).
hz_summary <- function(frame, reps = 2000, seed = 1) {
  act <- frame[frame$active, ]
  cell <- function(d, by) {
    d |>
      dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
      dplyr::group_modify(function(x, key) {
        bt <- hz_boot(x$r, x$espn_id, reps, seed)
        tibble::tibble(n = nrow(x), n_weeks = dplyr::n_distinct(x$week), drift = mean(x$r), drift_lo = bt$mean_ci[1],
                       drift_hi = bt$mean_ci[2], var = stats::var(x$r), var_lo = bt$var_ci[1], var_hi = bt$var_ci[2])
      }) |>
      dplyr::ungroup()
  }
  pooled <- cell(act, c("position", "lead_bin"))
  banded <- cell(act, c("position", "lead_bin", "band")) |> dplyr::filter(.data$n >= 200)
  list(pooled = pooled, banded = banded)
}

#' Martingale check: consecutive captures of the same player-week (v1 before v2) and the final f.
hz_martingale <- function(frame, reps = 2000, seed = 1) {
  pairs <- frame[frame$active, ] |>
    dplyr::arrange(.data$espn_id, .data$week, .data$captured_at) |>
    dplyr::mutate(v_next = dplyr::lead(.data$v), .by = c("espn_id", "week")) |>
    dplyr::filter(!is.na(.data$v_next)) |>
    dplyr::mutate(r1 = .data$v_next - .data$v, r2 = .data$f - .data$v_next)
  if (nrow(pairs) < 10) return(tibble::tibble(pairs = nrow(pairs), cor = NA_real_, cor_lo = NA_real_, cor_hi = NA_real_))
  groups <- split(seq_len(nrow(pairs)), pairs$espn_id)
  set.seed(seed)
  b <- replicate(reps, {
    i <- unlist(groups[sample.int(length(groups), replace = TRUE)], use.names = FALSE)
    suppressWarnings(stats::cor(pairs$r1[i], pairs$r2[i]))
  })
  # computed before tibble(): a column named "pairs" would shadow the local data frame
  n_pairs <- nrow(pairs)
  rho <- stats::cor(pairs$r1, pairs$r2)
  slope <- unname(stats::coef(stats::lm(r2 ~ r1, data = pairs))[2])
  tibble::tibble(pairs = n_pairs, cor = rho, cor_lo = unname(stats::quantile(b, 0.025, na.rm = TRUE)),
                 cor_hi = unname(stats::quantile(b, 0.975, na.rm = TRUE)), slope = slope)
}

#' Availability transitions: share of v > 0 rows whose final projection is 0, by status x lead bin.
hz_transitions <- function(frame) {
  frame[frame$v > 0, ] |>
    dplyr::summarise(n = dplyr::n(), share_final_zero = mean(.data$f == 0), .by = c("status3", "lead_bin"))
}

#' E17 adoption table (with E17a readiness): per position x current-week lead bin, the spread term
#' is the revision variance if the cell has >= 4 target weeks and the variance CI excludes 0; the
#' drift is applied if its CI excludes 0 (same readiness). Otherwise both are 0.
hz_adoption <- function(summary, min_weeks = HZ_MIN_WEEKS) {
  summary$pooled |>
    dplyr::filter(.data$lead_bin %in% HZ_HOUR_LABELS) |>
    dplyr::mutate(ready = .data$n_weeks >= min_weeks,
                  spread_var = ifelse(.data$ready & .data$var_lo > 0, .data$var, 0),
                  drift = ifelse(.data$ready & (.data$drift_lo > 0 | .data$drift_hi < 0), .data$drift, 0)) |>
    dplyr::select("position", "lead_bin", "n", "n_weeks", "ready", "spread_var", "drift")
}

#' Run the study for a season and archive the result write-once with its input hashes.
hz_run <- function(season, team_games, archive = TRUE, reps = 2000, root = HORIZON_ROOT, manifest = HORIZON_MANIFEST) {
  caps <- hz_captures(season)
  if (!nrow(caps)) cli::cli_abort("No valuation captures for {season}.")
  done <- team_games |>
    dplyr::filter(.data$season == !!season) |>
    dplyr::summarise(final = all(.data$game_final), .by = "week") |>
    dplyr::filter(.data$final)
  finals <- hz_finals(season, done$week)
  fr <- hz_frame(caps, finals, dplyr::filter(team_games, .data$season == !!season))
  sm <- hz_summary(fr, reps)
  res <- list(season = season, created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
              target_weeks = sort(unique(fr$week)), rows = nrow(fr), active_rows = sum(fr$active),
              summary = sm, martingale = hz_martingale(fr, reps), transitions = hz_transitions(fr),
              adoption = hz_adoption(sm), capture_files = sort(unique(caps$file)))
  if (archive) {
    path <- file.path(root, sprintf("season=%d", season), paste0("run=", utc_stamp(), ".json"))
    path <- write_once(path, function(tmp) jsonlite::write_json(res, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 8))
    git <- git_state()
    append_manifest(tibble::tibble(created_at_utc = res$created_at_utc, season = season, rows = res$rows,
                                   active_rows = res$active_rows, target_weeks = paste(res$target_weeks, collapse = "+"),
                                   adopted_cells = sum(res$adoption$spread_var > 0), result_sha256 = sha256_file(path),
                                   git_commit = git$commit), manifest)
    res$path <- path
  }
  res
}
