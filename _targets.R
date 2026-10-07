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
report2_file <- "reports/milestone2_report.qmd"
build_report <- nzchar(find_quarto()) && file.exists(report_file)
build_valuation <- isTRUE(read_project_config()$espn$enabled) || dir.exists(VAL_ESPN_RAW_ROOT)

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
  # Builders are found by dynamic lookup inside registry_specs(); listing them
  # here makes targets rebuild the specs when their code changes.
  tar_target(m2_frozen_specs, {
    list(registry_spec_cal, registry_spec_m2_linear, registry_spec_residual, registry_spec_xgb)
    unname(registry_specs(m2_registry))
  }, iteration = "list"),
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

  # ---- Milestone 3: component research track (development seasons only) ----
  tar_target(m3_component_preds, component_predictions(m2_dev, config$m2), format = "parquet"),
  tar_target(m3_component_summary, component_summary(m3_component_preds, 1000, config$evaluation$seed)),
  tar_target(m3_component_decomposition, component_decomposition(m3_component_preds)),

  # ---- Milestone 3: frozen rule challengers, one-time 2024-2025 check -------
  # Built only once models/registry/m3.yml exists (frozen before this runs).
  if (file.exists("models/registry/m3.yml")) list(
    tar_target(m3_registry_file, "models/registry/m3.yml", format = "file"),
    tar_target(m3_registry, read_registry("m3", dirname(m3_registry_file))),
    tar_target(m3_frozen_specs, {
      list(registry_spec_adjusted, rule_role_change, rule_return, spec_adjusted)  # explicit deps
      unname(registry_specs(m3_registry))
    }, iteration = "list"),
    tar_target(m3_full, add_absence_features(m2_full, player_games, team_games)),
    tar_target(m3_holdout_preds,
               rolling_folds(m3_full, m3_frozen_specs, unlist(config$m2$holdout_seasons),
                             m3_registry$data$min_train_season),
               pattern = map(m3_frozen_specs), format = "parquet"),
    tar_target(m3_holdout_aligned,
               m2_aligned(dplyr::bind_rows(m3_holdout_preds,
                                           dplyr::filter(m2_holdout_preds, model == "m2_espn_cal")), m3_full),
               format = "parquet"),
    tar_target(m3_holdout_comparisons, m2_comparisons(
      m3_holdout_aligned, models = unique(m3_holdout_preds$model), benchmarks = "m2_espn_cal",
      reps = config$evaluation$bootstrap_reps, seed = config$evaluation$seed)),
    tar_target(m3_holdout_seasonal, m2_seasonal(m3_holdout_aligned, unique(m3_holdout_preds$model), "m2_espn_cal")),
    tar_target(m3_fingerprint_check, {
      path <- m3_registry$fingerprint
      if (!file.exists(path)) write_fingerprint(m3_holdout_preds, path, raw_manifest, 2017, 2018)
      check_frozen_fingerprint(m3_holdout_preds, path, raw_manifest,
                               list(data = list(history_start_season = 2017, min_train_season = 2018)))
    })
  ),

  # ---- Milestone 3b: hypothesis D (Questionable), one-time 2024 check ---------
  tar_target(pregame_injury_reports, pregame_injuries(raw_injuries, team_games, season_type = config$season_type)),
  if (file.exists("models/registry/m3b.yml")) list(
    tar_target(m3b_registry_file, "models/registry/m3b.yml", format = "file"),
    tar_target(m3b_registry, read_registry("m3b", dirname(m3b_registry_file))),
    tar_target(m3b_frozen_specs, {
      list(registry_spec_adjusted, rule_questionable, rule_role_change, rule_return, spec_adjusted)
      unname(registry_specs(m3b_registry))
    }, iteration = "list"),
    tar_target(m3b_full, add_injury_features(m3_full, pregame_injury_reports, m2_hist$player_games_m2)),
    # 2025 has no injury timestamps, so the check uses 2024 only (E9).
    tar_target(m3b_holdout_preds,
               rolling_folds(m3b_full, m3b_frozen_specs, 2024, m3b_registry$data$min_train_season),
               pattern = map(m3b_frozen_specs), format = "parquet"),
    tar_target(m3b_holdout_aligned,
               m2_aligned(dplyr::bind_rows(m3b_holdout_preds,
                                           dplyr::filter(m2_holdout_preds, model == "m2_espn_cal", season == 2024)),
                          m3b_full), format = "parquet"),
    tar_target(m3b_holdout_comparisons, m2_comparisons(
      m3b_holdout_aligned, models = unique(m3b_holdout_preds$model), benchmarks = "m2_espn_cal",
      reps = config$evaluation$bootstrap_reps, seed = config$evaluation$seed)),
    tar_target(m3b_fingerprint_check, {
      path <- m3b_registry$fingerprint
      if (!file.exists(path)) write_fingerprint(m3b_holdout_preds, path, raw_manifest, 2017, 2018)
      check_frozen_fingerprint(m3b_holdout_preds, path, raw_manifest,
                               list(data = list(history_start_season = 2017, min_train_season = 2018)))
    })
  ),

  # ---- Milestone 4: availability and opportunity (docs/milestone4_plan.md) ----
  tar_target(injury_detail, pregame_injury_detail(raw_injuries, team_games, season_type = config$season_type)),
  tar_target(injury_coverage, injury_coverage_report(injury_detail)),
  if (file.exists("models/registry/m3b.yml")) list(
    tar_target(m4_bases, m4_rolling_bases(m2_full), format = "parquet"),
    tar_target(m4_data, m4_frame(m3b_full, m4_bases, injury_detail, team_games), format = "parquet"),
    # B1 recomputed here must equal the frozen M3b predictions (2024 rows).
    tar_target(m4_b1_matches_frozen, {
      frozen <- dplyr::filter(m3b_holdout_preds, model == "m3_questionable_adjust_v1") |>
        dplyr::select("season", "week", "gsis_id", frozen = "pred")
      cmp <- dplyr::inner_join(frozen, m4_data, by = c("season", "week", "gsis_id"))
      stopifnot(nrow(cmp) > 2000, max(abs(cmp$frozen - cmp$pred_b1)) < 1e-9)
      nrow(cmp)
    }),
    tar_target(m4_groups, group_ratios(m4_data)),
    tar_target(m4_decomposition, questionable_decomposition(m4_data)),
    tar_target(m4_disagreement, disagreement_slope(m4_data)),
    tar_target(m4_availability_pop, availability_by_population(injury_detail, rosters_weekly, espn_weekly,
                                                               espn_crosswalk, player_stats)),
    tar_target(m4_teammate, teammate_absence_targets(m4_data)),
    tar_target(m4_body, body_part_questionable(m4_data)),
    # Candidate parameters: derived from 2020-2023 only, then fixed in a committed
    # file (pre-registration, E13). The pipeline fails if they ever disagree.
    tar_target(m4_params_derived, m4_derive_params(m4_data))
  ),
  if (file.exists("research/m4_candidate_params.yml")) list(
    tar_target(m4_params_file, "research/m4_candidate_params.yml", format = "file"),
    tar_target(m4_params, {
      p <- yaml::read_yaml(m4_params_file)
      stopifnot(isTRUE(all.equal(p, m4_params_derived, check.attributes = FALSE)))
      p
    }),
    tar_target(m4_preds, m4_candidate_preds(m4_data, m4_params), format = "parquet"),
    tar_target(m4_dev_eval, m4_evaluate(m4_preds, M4_DEV)),
    # One-time checks, first run after the parameters were committed (39b8059, E13).
    tar_target(m4_check_2019, m4_evaluate(m4_preds, 2019)),
    tar_target(m4_check_2024, m4_evaluate(m4_preds, 2024)),
    tar_target(m4_decision, m4_freeze_decision(m4_dev_eval, m4_check_2019)),
    # Report-only summaries (no decisions are taken from these).
    tar_target(m4_target_table, target_model_table(m4_data, m4_params)),
    tar_target(m4_raw_comparisons, m4_vs_raw(m4_data, m4_preds))
  ),
  # Frozen M4 lineage (E14): regenerate the 2019 + 2024 predictions from the
  # registry, require equality with the candidate study, check the fingerprint.
  if (file.exists("models/registry/m4.yml")) list(
    tar_target(m4_registry_file, "models/registry/m4.yml", format = "file"),
    tar_target(m4_registry, read_registry("m4", dirname(m4_registry_file))),
    tar_target(m4_frozen_specs, {
      list(registry_spec_availability_adjusted, m4_rule_multiplier, m4_active_design, m4_param_group, spec_cal)
      unname(registry_specs(m4_registry))
    }, iteration = "list"),
    tar_target(m4_full, m4_add_features(m3b_full, injury_detail, team_games), format = "parquet"),
    tar_target(m4_coverage_detail, injury_coverage_detail(injury_detail, team_games, m4_full)),
    # Injury-table corruption test on real data: future reports, post-kickoff
    # reports and realised outcomes must not change any M4 feature.
    tar_target(leakage_check_m4, {
      raw <- dplyr::filter(read_parquet_files(raw_injuries), .data$season %in% 2018:2024, .data$game_type == "REG")
      fn <- function(t, rows, tg) {
        p <- tempfile(fileext = ".parquet")
        on.exit(unlink(p))
        arrow::write_parquet(rows, p)
        m4_add_features(t, pregame_injury_detail(p, tg), tg)
      }
      probe <- dplyr::select(dplyr::filter(m4_full, .data$season %in% 2019:2024), "season", "week", "gsis_id", "team",
                             "roster_status", "has_stat_line", "actual", "actual_targets")
      set.seed(4)
      gis <- sample(unique(game_index(probe$season, probe$week)), 6)
      leaks <- check_injury_leakage(probe, raw, team_games, fn, weeks = gis)
      if (length(leaks)) cli::cli_abort("M4 injury features leak: {.val {leaks}}")
      list(weeks = gis, leaks = leaks)
    }),
    tar_target(m4_holdout_preds,
               rolling_folds(m4_full, m4_frozen_specs, c(2019, 2024), m4_registry$data$min_train_season),
               pattern = map(m4_frozen_specs), format = "parquet"),
    tar_target(m4_frozen_matches_candidates, {
      ids <- c(m4_two_stage_v1 = "K2", m4_practice_rule_v1 = "K1")
      cmp <- m4_holdout_preds |>
        dplyr::mutate(model = unname(ids[.data$model])) |>
        dplyr::inner_join(dplyr::select(m4_preds, "season", "week", "gsis_id", "model", cand = "pred"),
                          by = c("season", "week", "gsis_id", "model"))
      stopifnot(nrow(cmp) == nrow(m4_holdout_preds), max(abs(cmp$pred - cmp$cand)) < 1e-9)
      nrow(cmp)
    }),
    tar_target(m4_fingerprint_check, {
      path <- m4_registry$fingerprint
      if (!file.exists(path)) write_fingerprint(m4_holdout_preds, path, raw_manifest, 2017, 2018)
      check_frozen_fingerprint(m4_holdout_preds, path, raw_manifest,
                               list(data = list(history_start_season = 2017, min_train_season = 2018)))
    })
  ),

  # ---- Valuation V1 (separate track: docs/valuation_v1_plan.md) -------------
  # Historical studies only; live valuations are point-in-time runs made by
  # scripts/valuation_run.R. Nothing here feeds any projection lineage. Built
  # when ESPN is enabled or the QB/RB/TE week-of history is cached.
  if (build_valuation) list(
    tar_target(val_config_file, "config/valuation.yml", format = "file"),
    tar_target(val_config, read_valuation_config(val_config_file)),
    tar_target(val_week_grid, dplyr::filter(regular_season_weeks(raw_schedules), season >= 2019)),
    tar_target(val_raw_espn, val_fetch_espn_weeks(val_week_grid, league_defaults_id = config$espn$league_defaults_id,
                                                  pause = config$espn$request_pause_seconds,
                                                  enabled = isTRUE(config$espn$enabled))),
    tar_target(val_espn_hist, {
      wr <- raw_espn$path[as.integer(sub(".*_([0-9]{4})_w.*", "\\1", basename(raw_espn$path))) >= 2019]
      val_espn_weekly(val_raw_espn$path, wr)
    }, format = "parquet"),
    tar_target(val_crosswalk, build_espn_crosswalk(dplyr::distinct(val_espn_hist, espn_id, espn_name),
                                                   rosters_weekly, players, ff_playerids)),
    tar_target(val_frame, val_history_frame(val_espn_hist, val_crosswalk, player_stats, rosters_weekly, team_games)),
    # VE1 (levels, schedule term; linear form of VE1a), VE1b (two-stage), VE1c (quadratic)
    tar_target(val_ve1, val_ve1_study(val_frame)),
    tar_target(val_ve1b, val_ve1b_form(val_frame, val_ve1$selected, val_ve1$keep_opponent, alternative = "two_stage")),
    tar_target(val_ve1c, val_ve1b_form(val_frame, val_ve1$selected, val_ve1$keep_opponent, alternative = "quadratic")),
    tar_target(val_ros_params_derived, val_derive_ros_params(val_frame, val_ve1$selected, val_ve1$keep_opponent,
                                                             form = val_ve1c$chosen)),
    # The committed parameters must equal a fresh derivation (fails otherwise).
    tar_target(val_ros_params_file, val_config$ros_params_file, format = "file"),
    tar_target(val_ros_params_check, {
      p <- yaml::read_yaml(val_ros_params_file)
      ok <- isTRUE(all.equal(p, val_ros_params_derived, check.attributes = FALSE, tolerance = 1e-8))
      if (!ok) cli::cli_abort("{.file {val_ros_params_file}} differs from the derived ROS parameters.")
      p$version
    }),
    tar_target(val_ros_fit, val_fit_ros(val_frame$future, val_ve1$selected, 2019:2025,
                                        opponent = val_ve1$keep_opponent, form = val_ve1c$chosen)),
    tar_target(val_ros_diag, val_ros_diagnostics(val_frame, val_ros_fit, injuries)),
    tar_target(val_backtest_results, {
      val_ros_params_check
      val_backtest(val_frame, val_config$league, level = val_ve1$selected, opponent = val_ve1$keep_opponent,
                   form = val_ve1c$chosen)
    })
  ),

  # ---- Reports ------------------------------------------------------------
  if (build_report) tar_quarto(report, report_file, quiet = TRUE),
  # Always re-render: it reads the latest archived valuation run.
  if (build_report && build_valuation && file.exists("reports/valuation_v1_report.qmd"))
    tar_quarto(report_valuation, "reports/valuation_v1_report.qmd", quiet = TRUE, cue = tar_cue(mode = "always")),
  # V2 (league-specific): only where the owner's league snapshots exist locally; reads the archives.
  if (build_report && file.exists("reports/valuation_v2_report.qmd") && file.exists(LG_SNAPSHOT_MANIFEST) &&
      dir.exists(LG_SNAPSHOT_ROOT))
    tar_quarto(report_valuation_v2, "reports/valuation_v2_report.qmd", quiet = TRUE, cue = tar_cue(mode = "always")),
  # Always re-render: its prospective section reads the live archive.
  if (build_report && file.exists("reports/milestone3_report.qmd"))
    tar_quarto(report_m3, "reports/milestone3_report.qmd", quiet = TRUE, cue = tar_cue(mode = "always")),
  if (build_report && file.exists("models/registry/m4.yml") && file.exists("reports/milestone4_report.qmd"))
    tar_quarto(report_m4, "reports/milestone4_report.qmd", quiet = TRUE, cue = tar_cue(mode = "always")),
  if (build_report && file.exists(report2_file))
    tar_quarto(report_m2, report2_file, quiet = TRUE, cue = tar_cue(mode = "always"))
)
