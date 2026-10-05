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

---

## 2026-10-05 — E1: ESPN-free run (active-roster population)

**Why this run.** ESPN fetching is disabled pending a terms-of-use decision
(docs/espn_projections.md). The pre-registered pipeline falls back to the
**game-day active WR population** (`pop_active`). The benchmark is `naive_roll8`,
not ESPN. ESPN-dependent candidates (M0, M5, M6, D1, D2) were not run.

**Dataset version.** Commit after `0783da2`. Raw nflverse files were retrieved
2026-10-05 (see `raw_manifest`). Population sizes: 11,210 train player-weeks
(2020–2023), 2,837 validation (2024), 2,836 test (2025).

**Features.**
- History: trailing 3/8-game PPR, season-to-date, previous season, career games, absence and team-change flags.
- Usage: trailing targets, target share, air-yards share, snap share, red-zone targets, xFP, team pass attempts.
- Matchup: home, opponent WR points allowed.
- Vegas: implied total, spread, total (closing).
- Injury: Questionable/Doubtful.

**Leakage check.** The empirical corruption test on the real dataset found 0 leaking features.

### Validation (2024): used for selection

| model | protocol | MAE | RMSE | bias | corr |
|---|---|---|---|---|---|
| ols_usage | rolling | **4.153** | 5.932 | −0.12 | 0.642 |
| ols_usage_vegas | rolling | 4.159 | 5.934 | −0.12 | 0.641 |
| ridge_usage | rolling | 4.160 | 5.933 | −0.11 | 0.642 |
| ols_usage_vegas_injury (exploratory) | rolling | 4.160 | 5.929 | −0.11 | 0.642 |
| naive_roll8 | rolling | 4.183 | 6.121 | −0.01 | 0.619 |

- The ridge penalty curve was flat (MAE 4.164 for penalties from 0.001 to 0.35), so there is little to shrink with about 11k rows and 17 features.
- **Selected (pre-registered rule): `ols_usage`.**
- Vegas and injury features did **not** improve validation MAE, so they were not adopted.
- ols_usage vs naive on validation: ΔMAE −0.030, 95% CI [−0.099, 0.034].

### Test (2025): opened once, after selection

| model | protocol | MAE | RMSE | bias | corr | rank corr |
|---|---|---|---|---|---|---|
| **ols_usage** | rolling | **3.957** | 5.560 | +0.26 | 0.637 | 0.676 |
| ols_usage_vegas | rolling | 3.967 | 5.556 | +0.28 | 0.638 | 0.675 |
| ridge_usage | rolling | 3.968 | 5.556 | +0.27 | 0.638 | 0.676 |
| naive_roll8 | rolling | 4.050 | 5.791 | +0.36 | 0.616 | 0.654 |

Headline: ols_usage − naive_roll8, rolling. ΔMAE **−0.092**, 95% week-clustered
bootstrap CI **[−0.152, −0.040]**. RMSE is better (5.56 vs 5.79), and the model is
better in 72% of weeks. **Criterion met against the naive baseline.**

**Observations.**
- Most of the gain over naive comes in **weeks 1–4**, when the 8-game window is mostly stale prior-season games. From mid-season the two are close.
- The median error is about +1 point for every mean-targeting model. WR scoring is right-skewed, so MAE rewards median-targeting. RMSE is the cleaner signal of better expected-points forecasts here.
- Static and rolling protocols give nearly identical results. Weekly refitting adds little for a linear model with this much history.

**Conclusion.** A simple, honest usage regression beats naive history out of
sample by about 0.09 PPR points of MAE, a small but statistically clear margin.
**This says nothing about ESPN.** Whether we can beat ESPN is still untested.

**Next step.** Run the ESPN comparison once the owner decides on ESPN terms of use.
The pre-registered candidates M0, M5, M6, D1 and D2 activate automatically. The
2025 test season has now been opened for the non-ESPN models. No model or feature
choice was changed after seeing it, and future feature work should be judged on
validation and then on 2026 as a fresh holdout.
