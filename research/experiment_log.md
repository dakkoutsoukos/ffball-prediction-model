# Experiment log

Each entry records the date, hypothesis, dataset version, features, training
period, evaluation period, model, metrics, result, conclusion and next step.
Metrics are produced by the targets pipeline (`tar_read(metrics_*)`). Entries are
written by hand and never edited after the fact, apart from adding a "Result"
section once the experiment has run.

Dataset versions are identified by the git commit plus the `raw_manifest` target,
which records the retrieval time and nflverse build timestamp of every raw file.

---

## 2026-10-05 — Pre-registration for Milestone 1 (written before any model was fit)

**Question.** Can we predict weekly WR full-PPR fantasy points more accurately
than ESPN's pregame projection?

**Evaluation population (primary).** WR player-weeks in regular-season weeks
where ESPN's pregame projection is greater than 0. This is defined with pregame
information only. Actual points are 0 when a projected player records no stats.
The **relevant** subset is the top 60 WRs by ESPN projection each week. Results
are also broken down by season, week and projection bucket.

**Splits.** History 2019 (feature warm-up only), train 2020–2023, validation
2024, test 2025. The test season must not influence any feature, preprocessing,
hyperparameter or model-selection decision.

**Protocols.**
- *static*: fit once on the training seasons and predict the validation season.
  The test season is predicted after refitting on training + validation.
- *rolling* (primary): for each week *w*, fit on every eligible row before *w*,
  then predict *w*. This mirrors weekly retraining in real time.

**Candidate models.** The feature groups are declared in `R/models/models.R`.

| id | model | features | role |
|---|---|---|---|
| M0 | `espn` | ESPN projection | benchmark |
| M1 | `naive_roll8` | trailing 8-game mean → previous-season mean → no-history mean | naive baseline |
| M2 | `ols_usage` | history + usage + matchup | simple regression, no ESPN |
| M3 | `ridge_usage` | same as M2, ridge penalty tuned on 2024 static | regularised regression |
| M4 | `ols_usage_vegas` | M2 + closing lines | tests the Vegas hypothesis |
| M5 | `ols_espn_plus` | ESPN projection + M4 features | ESPN adjusted by our features |
| M6 | `ridge_espn_plus` | same as M5, ridge penalty tuned on 2024 static | regularised M5 |
| D1 | `espn_recal_l2` | a + b · ESPN, least squares | diagnostic: ESPN calibration |
| D2 | `espn_recal_l1` | a + b · ESPN, least absolute deviations | diagnostic: how much MAE comes from targeting the median |

**Selection rule (fixed in advance).** The primary model is the non-diagnostic
candidate (M1–M6) with the lowest **2024 rolling-origin MAE** on the primary
population. Only the primary model's 2025 result against ESPN is the headline
claim. All other 2025 numbers are reported as secondary.

**What would count as beating ESPN.** For the 2025 rolling-origin primary
population, the paired, week-clustered bootstrap 95% CI of MAE(model) − MAE(ESPN)
must lie entirely below 0, **and** RMSE must not be worse. MAE alone rewards
predicting the conditional *median* of a right-skewed outcome (see D2), so an
MAE gain bought by shrinking projections is not counted as better projection.

**Hypotheses.**
1. M1 (naive) is clearly worse than ESPN. ESPN uses information we lack, such
   as depth-chart news, injuries and coaching tendencies.
2. M2/M3 come close to ESPN but do not beat it.
3. M5/M6 beat ESPN by a small margin, because combining a strong forecast with
   independent signals usually helps.
4. D2 has a lower MAE than ESPN even though it only rescales ESPN. That would
   show part of any "MAE win" is about distributional targeting, not information.
