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
    dplyr::filter(regular_season_weeks(raw_schedules), season >= config$espn$first_season)
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

  # ---- Frozen Milestone 1 lineage (models/registry/m1.yml) ----------------
  # M1 sees data exactly as it did when frozen (feature history from 2019), so
  # extending the data window for later milestones cannot alter it. The
  # fingerprint check fails the pipeline if M1 predictions change on the same
  # data version.
  tar_target(m1_registry_file, "models/registry/m1.yml", format = "file"),
  tar_target(m1_registry, read_registry("m1", dirname(m1_registry_file))),
  tar_target(
    player_week_m1,
    lineage_player_week(m1_registry, player_week_base, player_games, team_volume, defense_allowed,
                        team_games, config$splits, config$evaluation$relevant_top_n),
    format = "parquet"
  ),
  tar_target(m1_frame, frozen_frame(m1_registry, player_week_m1, max_season = 2025)),
  tar_target(m1_specs, registry_specs(m1_registry)),
  tar_target(
    m1_rolling,
    frozen_rolling_predictions(m1_frame, m1_specs, 2024:2025, m1_registry$data$min_train_season),
    format = "parquet"
  ),
  tar_target(m1_fingerprint_file, m1_registry$fingerprint, format = "file"),
  tar_target(m1_fingerprint_check,
             check_frozen_fingerprint(m1_rolling, m1_fingerprint_file, raw_manifest, m1_registry)),

  # ---- Milestone 1 experiment (E1/E2), on the M1 data vintage --------------
  # Nothing in this block depends on test-season rows; see tar_visnetwork().
  tar_target(model_data, {
    leakage_check  # the dataset must pass the leakage check before modelling
    modelling_frame(player_week_m1)
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

  # ---- Milestone 2: features ----------------------------------------------
  tar_target(pbp_receiver, pbp_receiver_detail(raw_pbp)),
  tar_target(pbp_team, pbp_team_game(raw_pbp)),
  tar_target(pbp_defense, pbp_defense_game(raw_pbp)),
  tar_target(pbp_qb, pbp_qb_game(raw_pbp)),
  tar_target(m2_hist, m2_histories(player_games, team_volume, defense_allowed, pbp_receiver,
                                   pbp_usage, player_stats, pbp_team, pbp_defense, pbp_qb)),
  tar_target(m2_static, list(team_games = team_games, bio = player_bio(players))),
  tar_target(
    player_week_m2,
    add_m2_features(dplyr::filter(player_week_base, has_game), m2_hist, m2_static,
                    windows = unlist(config$features$roll_windows)) |>
      finalize_player_week(config$splits, config$evaluation$relevant_top_n),
    format = "parquet"
  ),
  tar_target(leakage_check_m2, assert_no_leakage_m2(player_week_base, m2_hist, m2_static)),

  # ---- Milestone 2: development folds (2020-2023 only) ---------------------
  # Nothing here can see 2024+: m2_dev is built with max_season = last dev
  # season and assert_dev_only() fails otherwise.
  tar_target(m2_dev, {
    leakage_check_m2
    m2_frame(player_week_m2, config$m2, max(unlist(config$m2$dev_seasons))) |> assert_dev_only(config$m2)
  }),
  tar_target(m2_cal_specs, calibration_specs(), iteration = "list"),
  tar_target(m2_dev_cal_preds,
             rolling_folds(m2_dev, m2_cal_specs, unlist(config$m2$dev_seasons), config$m2$first_train_season),
             pattern = map(m2_cal_specs), format = "parquet"),
  tar_target(m2_cal_choice, select_calibration(m2_dev_cal_preds)),
  tar_target(m2_cal_spec, spec_cal(sub("^cal_", "", m2_cal_choice$model))),
  tar_target(m2_tuning, tune_m2(m2_dev, config$m2, m2_cal_spec)),
  tar_target(m2_specs, unname(c(m2_candidate_specs(m2_tuning, m2_cal_spec), reference_specs())),
             iteration = "list"),
  tar_target(m2_dev_preds,
             rolling_folds(m2_dev, m2_specs, unlist(config$m2$dev_seasons), config$m2$first_train_season),
             pattern = map(m2_specs), format = "parquet"),
  tar_target(m2_selection, select_challengers(dplyr::bind_rows(m2_dev_preds, m2_dev_cal_preds),
                                              m2_cal_choice$model, NF_CANDIDATES, AUG_CANDIDATES)),

  # ---- Milestone 2: descriptive development studies (2020-2023) ------------
  tar_target(m2_dev_aligned, m2_aligned(dplyr::bind_rows(m2_dev_preds, m2_dev_cal_preds), m2_dev),
             format = "parquet"),
  tar_target(m2_dev_tables, m2_metric_tables(m2_dev_aligned)),
  tar_target(m2_dev_comparisons, m2_comparisons(
    m2_dev_aligned, models = c(m2_selection$aug, m2_selection$nf, "aug_ols", "aug_xgb", "aug_resid_xgb",
                               "nf_xgb", "nf_enet", m2_cal_choice$model),
    benchmarks = c(m2_cal_choice$model, "espn", "m1spec_no_espn"),
    reps = config$evaluation$bootstrap_reps, seed = config$evaluation$seed)),
  tar_target(m2_dev_seasonal, dplyr::bind_rows(
    m2_seasonal(m2_dev_aligned, c(m2_selection$aug, "aug_ols", "aug_xgb", "aug_resid_xgb"), m2_cal_choice$model),
    m2_seasonal(m2_dev_aligned, c(m2_selection$nf, "nf_xgb", "nf_enet"), "m1spec_no_espn"))),
  tar_target(m2_ablation_aug, ablation_study(m2_dev, m2_tuning, m2_cal_spec, m2_selection$aug, config$m2)),
  tar_target(m2_ablation_nf, ablation_study(m2_dev, m2_tuning, m2_cal_spec, m2_selection$nf, config$m2)),
  tar_target(m2_representation, representation_study(m2_dev, config$m2)),
  tar_target(m2_residual_study, residual_study(m2_dev_cal_preds, m2_cal_choice$model, m2_dev)),

  # ---- Milestone 2: frozen lineage and one-time historical holdout ----------
  tar_target(m2_registry_file, "models/registry/m2.yml", format = "file"),
  tar_target(m2_registry, read_registry("m2", dirname(m2_registry_file))),
  tar_target(m2_frozen_specs, unname(registry_specs(m2_registry)), iteration = "list"),
  tar_target(m2_full, m2_frame(player_week_m2, config$m2, max_season = 2025)),
  tar_target(m2_holdout_preds,
             rolling_folds(m2_full, m2_frozen_specs, unlist(config$m2$holdout_seasons),
                           m2_registry$data$min_train_season),
             pattern = map(m2_frozen_specs), format = "parquet"),
  tar_target(m2_holdout_refs,
             purrr::map(list(spec_espn(), spec_naive(8)), ~ rolling_folds(
               m2_full, .x, unlist(config$m2$holdout_seasons), config$m2$first_train_season)) |>
               purrr::list_rbind(), format = "parquet"),
  tar_target(m2_holdout_aligned,
             m2_aligned(dplyr::bind_rows(m2_holdout_preds, m2_holdout_refs,
                                         dplyr::filter(m1_rolling, model != "m1_espn_raw")), m2_full),
             format = "parquet"),
  tar_target(m2_holdout_tables, m2_metric_tables(m2_holdout_aligned)),
  tar_target(m2_holdout_comparisons, m2_comparisons(
    m2_holdout_aligned,
    models = c("m2_espn_aug", "m2_no_espn", "m2_espn_cal", "m1_espn_plus", "m1_no_espn", "m1_espn_recal"),
    benchmarks = c("m2_espn_cal", "espn", "m1_espn_plus", "m1_no_espn"),
    reps = config$evaluation$bootstrap_reps, seed = config$evaluation$seed)),
  tar_target(m2_holdout_seasonal, dplyr::bind_rows(
    m2_seasonal(m2_holdout_aligned, c("m2_espn_aug", "m1_espn_plus"), "m2_espn_cal"),
    m2_seasonal(m2_holdout_aligned, "m2_no_espn", "m1_no_espn"))),
  tar_target(m2_fingerprint_check, {
    path <- m2_registry$fingerprint
    if (!file.exists(path)) write_fingerprint(m2_holdout_preds, path, raw_manifest, 2017, 2018)
    check_frozen_fingerprint(m2_holdout_preds, path, raw_manifest,
                             list(data = list(history_start_season = 2017, min_train_season = 2018)))
  }),

  # ---- Report -------------------------------------------------------------
  if (build_report) tar_quarto(report, report_file, quiet = TRUE)
)
