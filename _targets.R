# targets pipeline: raw sources -> validation -> clean data -> player-week
# dataset -> features -> ESPN benchmark -> models -> evaluation -> report.
#
# Run:      targets::tar_make()
# Inspect:  targets::tar_visnetwork(); targets::tar_read(evaluation_validation)
# Raw downloads are cached immutably in data/raw/ (see R/data/ingest_*.R).

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr"),
  format = "rds",
  error = "stop",
  seed = 20261005
)
tar_source("R")

# Quarto ships with RStudio; find_quarto() also checks RStudio's bundled copy.
report_file <- "reports/milestone1_report.qmd"
build_report <- nzchar(find_quarto()) && file.exists(report_file)

list(
  # ---- Configuration ------------------------------------------------------
  tar_target(config_file, "config/project.yml", format = "file"),
  # Always re-read so the optional git-ignored config/local.yml is honoured;
  # downstream targets rebuild only if the resulting value changes.
  tar_target(config, read_project_config(config_file), cue = tar_cue(mode = "always")),
  tar_target(seasons, config$seasons_all),
  tar_target(
    scoring_file,
    file.path("config", "scoring", paste0(config$scoring_system, ".yml")),
    format = "file"
  ),
  tar_target(scoring_rules, read_scoring_rules(basename(tools::file_path_sans_ext(scoring_file)))),

  # ---- Raw sources (immutable local cache) --------------------------------
  tar_target(raw_player_stats, fetch_nflverse("player_stats", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_schedules, fetch_nflverse("schedules", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_rosters_weekly, fetch_nflverse("rosters_weekly", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_snap_counts, fetch_nflverse("snap_counts", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_injuries, fetch_nflverse("injuries", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_ff_opportunity, fetch_nflverse("ff_opportunity", seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_pbp, fetch_nflverse_pbp(seasons), pattern = map(seasons), format = "file"),
  tar_target(raw_players, fetch_nflverse("players"), format = "file"),
  tar_target(raw_ff_playerids, fetch_nflverse("ff_playerids"), format = "file"),
  # ESPN is only needed for modelling seasons (the first season is feature warm-up).
  tar_target(
    espn_week_grid,
    dplyr::filter(regular_season_weeks(raw_schedules), season >= config$splits$first_train_season)
  ),
  tar_target(
    raw_espn,
    fetch_espn_weeks(espn_week_grid, position = "WR",
                     league_defaults_id = config$espn$league_defaults_id,
                     pause = config$espn$request_pause_seconds,
                     enabled = isTRUE(config$espn$enabled))
  ),
  tar_target(
    raw_manifest,
    raw_data_manifest(c(raw_player_stats, raw_schedules, raw_rosters_weekly, raw_snap_counts,
                        raw_injuries, raw_ff_opportunity, raw_pbp, raw_players,
                        raw_ff_playerids, raw_espn$path))
  ),

  # ---- Clean, validated tables --------------------------------------------
  tar_target(player_stats, clean_player_stats(raw_player_stats, scoring_rules, config$season_type), format = "parquet"),
  tar_target(team_games, clean_team_games(raw_schedules, config$season_type)),
  tar_target(players, read_parquet_files(raw_players), format = "parquet"),
  tar_target(ff_playerids, read_parquet_files(raw_ff_playerids), format = "parquet"),
  tar_target(rosters_weekly, clean_rosters_weekly(raw_rosters_weekly, player_stats, config$season_type), format = "parquet"),
  tar_target(snaps, clean_snap_counts(raw_snap_counts, players, config$season_type)),
  tar_target(injuries, clean_injuries(raw_injuries, config$season_type)),
  tar_target(xfp, clean_ff_opportunity(raw_ff_opportunity, config$season_type)),
  tar_target(pbp_usage, pbp_target_usage(raw_pbp, config$season_type)),
  tar_target(espn_weekly, parse_espn_files(raw_espn), format = "parquet"),

  # ---- IDs and scoring validation -----------------------------------------
  tar_target(espn_crosswalk, build_espn_crosswalk(espn_weekly, rosters_weekly, players, ff_playerids)),
  tar_target(scoring_validation, validate_scoring_against_espn(player_stats, espn_weekly, espn_crosswalk)),

  # ---- Histories and player-week dataset ----------------------------------
  tar_target(player_games, build_player_games(player_stats, snaps, pbp_usage, xfp), format = "parquet"),
  tar_target(team_volume, build_team_volume(player_stats)),
  tar_target(defense_allowed, build_defense_allowed(player_stats, team_games, position = "WR")),
  tar_target(
    player_week_base,
    build_player_week_base(espn_weekly, espn_crosswalk, player_stats, rosters_weekly,
                           team_games, injuries, positions = config$positions),
    format = "parquet"
  ),
  tar_target(
    player_week,
    add_point_in_time_features(player_week_base, player_games, team_volume, defense_allowed,
                               team_games, windows = unlist(config$features$roll_windows)) |>
      finalize_player_week(config$splits, config$evaluation$relevant_top_n),
    format = "parquet"
  ),
  tar_target(
    leakage_check,
    assert_no_leakage(player_week_base, player_games, team_volume, defense_allowed, team_games)
  ),
  tar_target(
    dataset_audit,
    audit_player_week(player_week, player_week_base, espn_weekly, espn_crosswalk, config$positions)
  ),
  tar_target(
    player_week_export,
    export_player_week(player_week, "data/processed/player_week_wr.parquet",
                       "data/processed/ffball.duckdb"),
    format = "file"
  ),

  # ---- Models: development (train + validation only) ----------------------
  # Nothing in this block depends on test-season rows; see tar_visnetwork().
  tar_target(model_data, {
    leakage_check  # the dataset must pass the leakage check before modelling
    modelling_frame(player_week)
  }),
  tar_target(model_data_dev, dev_frame(model_data)),
  tar_target(penalty_tuning, tune_penalties(model_data_dev, config$splits)),
  tar_target(model_specs, candidate_specs(penalty_tuning, espn_available(model_data_dev))),
  tar_target(
    predictions_validation,
    run_backtests(model_data_dev, model_specs, config$splits, config$splits$validation_season),
    format = "parquet"
  ),
  tar_target(evaluation_validation, evaluate_predictions(predictions_validation, model_data_dev, config$evaluation)),
  tar_target(model_selection, select_primary_model(evaluation_validation, config$splits)),

  # ---- Models: final test season (run after selection is fixed) -----------
  tar_target(
    predictions_test,
    {
      model_selection  # selection must exist before the test season is opened
      run_backtests(model_data, model_specs, config$splits, config$splits$test_season)
    },
    format = "parquet"
  ),
  tar_target(evaluation_test, evaluate_predictions(predictions_test, model_data, config$evaluation)),
  tar_target(headline, headline_result(evaluation_test, model_selection)),

  # ---- Report -------------------------------------------------------------
  if (build_report) tar_quarto(report, report_file, quiet = TRUE)
)
