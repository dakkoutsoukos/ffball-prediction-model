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

> **Note added 2026-10-05 (after E1).** E1 used scoring that penalised only
> sack, rushing and receiving fumbles lost. Validation against ESPN's own actual
> totals (E2 below) showed ESPN also penalises fumbles lost on kick and punt
> returns. Scoring now uses `fumbles_lost_total`. This changes `actual` by −2 on
> about 1% of WR player-weeks. E1's numbers are left as originally recorded.

---

## 2026-10-05 — E2: ESPN benchmark and pre-registered ESPN comparison

**Data.**
- ESPN weekly WR projections and actuals for 2020–2025 (107 requests to the public `leaguedefaults/3` endpoint).
- Fetched after the owner opted in for private research (docs/espn_projections.md).
- 99.87% of ESPN-projected WR rows were matched to GSIS ids by ID only. 20 rows are ambiguous (two "DJ Turner"s) and excluded.

**Population.** `pop_espn` (ESPN projection > 0). Train 9,916 (2020–2023), validation 2,499 (2024), test 2,592 (2025).

**Changes made before the test season was opened.** All were committed in `3082abc` before E2's test run.
1. Scoring: `fumbles_lost_total`. Our scoring now matches ESPN actuals on **99.96% of 14,628** player-weeks (it was 99.01%).
2. Ridge bug: glmnet's default lambda path made a "tiny-penalty" ridge differ from OLS by up to 1 point. Fixed with an explicit path, and a unit test now guards it.
3. Parser: per-game ESPN actual entries are summed. This happened once, for a mid-week team change in 2020.

**ESPN benchmark by season** (all ESPN-projected WRs, actual = 0 when no stats):

| season | n | MAE | RMSE | bias | corr |
|---|---|---|---|---|---|
| 2020 | 2462 | 4.55 | 6.29 | −0.18 | 0.63 |
| 2021 | 2560 | 4.61 | 6.13 | +0.39 | 0.63 |
| 2022 | 2452 | 4.49 | 6.07 | +0.37 | 0.63 |
| 2023 | 2442 | 4.23 | 5.93 | +0.22 | 0.66 |
| 2024 | 2499 | 4.31 | 6.04 | +0.19 | 0.65 |
| 2025 | 2592 | 4.08 | 5.63 | +0.58 | 0.65 |

ESPN over-projected WRs on average in 5 of 6 seasons.

### Validation (2024), rolling: selection

| model | MAE | RMSE | ΔMAE vs ESPN [95% CI] |
|---|---|---|---|
| espn_recal_l1 (diag.) | 4.173 | 6.180 | −0.135 [−0.199, −0.075] |
| espn_recal_l2 (diag.) | 4.280 | 6.033 | −0.028 [−0.041, −0.015] |
| **ols_espn_plus** | **4.292** | 6.048 | −0.016 [−0.040, +0.006] |
| ridge_espn_plus | 4.292 | 6.047 | −0.016 [−0.040, +0.006] |
| espn | 4.308 | 6.038 | — |
| ols_usage | 4.494 | 6.254 | +0.186 [+0.112, +0.260] |
| naive_roll8 | 4.535 | 6.451 | +0.227 [+0.122, +0.347] |

**Selected (pre-registered rule): `ols_espn_plus`.** Note that on validation it
did *not* meet the "beats ESPN" criterion: the CI spans 0 and RMSE is slightly worse.

### Test (2025), rolling: opened once

| model | MAE | RMSE | bias | rank corr | ΔMAE vs ESPN [95% CI] | weeks better |
|---|---|---|---|---|---|---|
| espn_recal_l1 (diag.) | 3.866 | 5.630 | −0.80 | 0.691 | −0.211 [−0.269, −0.146] | 94% |
| **ols_espn_plus** | **4.001** | **5.571** | +0.35 | 0.697 | **−0.076 [−0.100, −0.053]** | **94%** |
| espn_recal_l2 (diag.) | 4.032 | 5.595 | +0.37 | 0.691 | −0.045 [−0.059, −0.031] | 94% |
| espn | 4.077 | 5.632 | +0.58 | 0.691 | — | — |
| ols_usage | 4.190 | 5.778 | +0.27 | 0.657 | +0.113 [+0.050, +0.177] | 11% |
| naive_roll8 | 4.313 | 6.027 | +0.37 | 0.631 | +0.236 [+0.134, +0.345] | 11% |

Top-60 relevant subset: ols_espn_plus ΔMAE −0.139 [−0.172, −0.108], better in 18 of 18 weeks.

**Headline: the pre-registered criterion is MET on 2025.** ESPN + lagged usage
features beat ESPN alone on MAE (CI excludes 0) and RMSE.

**But it should not be over-read.**
1. **It did not replicate on 2024.** There the same model was −0.016 (CI spans 0) with slightly worse RMSE. The evidence over two seasons is mixed.
2. **Much of it is calibration.** ESPN over-projected more in 2025 (bias +0.58 vs +0.19). A plain a + b·ESPN recalibration, which adds no player information, captures −0.045 of the −0.076. The gains concentrate where ESPN over-projects most (projections of 15+: ESPN bias +2.0).
3. **Ordering barely improves.** Rank correlation goes from 0.691 to 0.697. Start/sit decisions depend mainly on ordering, so the practical value is smaller than the MAE gain suggests.
4. **Diagnostic D2 confirms hypothesis 4.** Median-targeting "wins" 0.21 of MAE while RMSE does not improve.

**Hypotheses.**
- H1 (naive ≪ ESPN): confirmed.
- H2 (usage models close to but behind ESPN): confirmed overall, about 0.11–0.19 behind. On the 2025 top-60 subset they are level with ESPN, within noise.
- H3 (ESPN + features beats ESPN): 2025 yes, 2024 no. **Not yet repeatable.**
- H4 (MAE gains from median targeting): confirmed.

**Conclusion.** We have **not** shown a repeatable improvement over ESPN. We have
shown a correctly measured ESPN benchmark, a model that is at least as good as
ESPN in both held-out seasons, and a significant 2025 gain that is largely
level-calibration. Our ESPN-free models are clearly worse than ESPN.

**Next step.** Treat **2026** as the fresh, untouched holdout. Freeze `ols_espn_plus`
and `espn_recal_l2` now. Archive live ESPN snapshots weekly. Evaluate after the
season, or rolling-origin through it, without changing the models.

---

## 2026-10-05 — E3: Milestone 2 pre-registration (written before any M2 experiment and before any 2026 outcome was evaluated)

**Question.** Do our football features carry *player-level* information beyond a
**calibrated** ESPN forecast, repeatably and prospectively? Secondary: can the
ESPN-free model close its gap to ESPN?

**Status of seasons.** 2024 was used for M1 selection and 2025 was opened twice in
M1, so neither is pristine. **2026 is the only clean evidence.** Its use is fixed in
docs/prospective_protocol.md.

### Historical development protocol
- **Data:** nflverse extended to 2017 (feature warm-up); ESPN extended to 2018.
  Training rows run from 2018.
- **Development folds:** 2020, 2021, 2022, 2023. Each week is predicted after a
  weekly expanding-window refit on all rows from 2018 strictly before that week.
  **Every M2 decision** is made on these folds only: feature families,
  hyperparameters, calibration choice and model choice.
- **Hyperparameters:** chosen with static season-level fits on the same
  development seasons (predict each season from all earlier ones), from small
  fixed grids.
- **Historical holdout:** 2024 and 2025, with weekly rolling refits, run **once**
  after the M2 challengers are chosen. Not pristine, but no M2 decision is made on it.
- **Test isolation:** development code asserts that no season after 2023 enters
  development, and no season after 2025 enters any historical target.

### Benchmark hierarchy
1. **Raw ESPN.**
2. **Calibrated ESPN (`m2_espn_cal`):** the best, by pooled development MAE, of a
   pre-declared ESPN-only family:
   - linear a + b·ESPN;
   - natural spline of ESPN (df = 4);
   - linear on ESPN's projected stat components (points, receptions, targets,
     receiving yards and TDs, rushing yards);
   - the components model with recency weights (half-life 1 season).
   All are refit weekly.
3. **ESPN-free model.**
4. **ESPN + our information.**

**The primary scientific comparison is (4) vs (2).**

### Candidates, declared in advance
- **ESPN-free:**
  - `nf_ols` (OLS);
  - `nf_enet` (elastic net, mixture 0.5, penalty tuned);
  - `nf_xgb` (XGBoost, grid: depth {3, 5} × rounds {300, 600}, eta 0.03, subsample 0.8, colsample 0.8, min_child_weight 20).
- **Augmentation:**
  - `aug_ols` (OLS with ESPN components plus our features);
  - `aug_resid_enet` and `aug_resid_xgb` (calibrated ESPN plus a model of its residual);
  - `aug_xgb` (XGBoost with ESPN components plus our features).
- All are fit to the conditional mean (squared error).
- Betting lines and injury reports are **excluded** from all M2 models: they are
  not point-in-time.

### Feature policy
- Every family must:
  - state a football hypothesis;
  - pass the point-in-time review (docs/features.md);
  - pass the extended corruption leakage test.
- All valid families go into the candidate models. **Families are not dropped by
  searching ablations.** Ablations are run once on the development folds and
  reported descriptively.

### Selection rules
- **ESPN-free challenger:** lowest pooled development MAE among the ESPN-free candidates.
- **Augmentation challenger:** lowest pooled development MAE among the
  augmentation candidates whose pooled development RMSE ≤ `m2_espn_cal`'s.
  If none qualifies, take the lowest MAE and report the RMSE failure.
- Both challengers are then **frozen** (models/registry/m2.yml) together with `m2_espn_cal`.

### Pre-specified evaluation subsets and metrics
- **Subsets** (all defined pregame, by ESPN rank within the week):
  - all ESPN-projected WRs (**primary**);
  - top 60 ("relevant", continuity with M1);
  - top 36 ("startable").
  Projection buckets are descriptive only.
- **Metrics:**
  - MAE (primary) and RMSE (gate);
  - bias, Pearson correlation, weekly Spearman;
  - pairwise ordering accuracy within the top 60;
  - top-24 precision;
  - large-miss rate (|error| > 10);
  - calibration by projection bucket.
- **Uncertainty:** paired, week-clustered bootstrap (2,000 resamples). Pooled
  results resample weeks within season.

### Historical evidence criterion (holdout 2024–2025)
"Historical evidence of incremental signal" requires all of the following for the
augmentation challenger vs `m2_espn_cal`:
- pooled holdout ΔMAE 95% CI entirely below 0;
- pooled holdout RMSE no worse;
- ΔMAE below 0 in **each** of 2024 and 2025;
- the development-fold pooled ΔMAE CI also below 0.

### Primary prospective hypothesis (2026). Do not modify after seeing 2026 results.
> On prospectively captured 2026 WR player-weeks, the frozen Milestone 2
> ESPN-augmentation model will achieve lower MAE than the calibrated ESPN
> baseline, with the paired week-clustered 95% confidence interval for ΔMAE
> entirely below zero, while RMSE is no worse.

- Evaluated **once**, at the end of the 2026 regular season, on archived runs only
  (docs/prospective_protocol.md).
- Comparison with raw ESPN is also reported.
- If fewer than **10** prospective weeks have valid archived predictions for the
  frozen M2 models at that point, the result is declared **insufficient**. The
  criterion is not weakened.

### Secondary prospective hypotheses
1. The M2 ESPN-free challenger has lower MAE than `m1_no_espn` (CI below 0).
2. The augmentation challenger has a higher weekly Spearman than calibrated ESPN.
3. The primary result holds on the top-60 subset.
4. The augmentation challenger beats calibrated ESPN in more than half of prospective weeks.

The frozen M1 models (`m1_*`) are archived alongside, from 2026 Week 5.

---

## 2026-10-05 — E4: M2 development results and freeze (recorded BEFORE the 2024–2025 holdout was run)

**Calibrated ESPN.** Pooled development MAE across the ESPN-only family:
- components + recency weights: 4.449 (selected → `m2_espn_cal`);
- components: 4.456;
- linear: 4.457;
- spline: 4.457.

The four are essentially indistinguishable.

**Tuning** (static development folds):
- elastic net: best penalty 0.1 for both the ESPN-free model and the residual model;
- XGBoost: depth 3, 300 rounds, the smallest configuration, for all three XGBoost candidates;
- deeper or longer XGBoost fits were worse.

**Development folds 2020–2023** (weekly rolling refits, all ESPN-projected WRs, n = 9,916, 71 weeks):

| model | MAE | RMSE |
|---|---|---|
| aug_resid_enet | **4.437** | 6.082 |
| aug_ols | 4.437 | 6.078 |
| cal_components_recency (`m2_espn_cal`) | 4.449 | 6.101 |
| aug_xgb | 4.45 | 6.10 |
| aug_resid_xgb | 4.45 | 6.12 |
| raw ESPN | 4.469 | 6.108 |
| nf_ols | 4.59 | 6.235 |
| nf_xgb | 4.60 | 6.24 |
| m1spec_no_espn | 4.61 | 6.276 |
| nf_enet | 4.61 | 6.23 |
| naive_roll8 | 4.69 | 6.45 |

**Paired comparisons** (season-stratified week bootstrap):

| comparison | ΔMAE [95% CI] | weeks better | detail |
|---|---|---|---|
| aug_resid_enet vs calibrated ESPN | −0.012 [−0.025, +0.001] | 59% | ΔMAE < 0 and ΔRMSE < 0 in all 4 seasons (−0.015, −0.018, −0.003, −0.014) |
| aug_resid_enet vs raw ESPN | −0.033 [−0.047, −0.018] | — | — |
| calibrated vs raw ESPN | −0.020 [−0.028, −0.013] | — | calibration alone |
| nf_ols vs M1's ESPN-free spec | −0.011 [−0.031, +0.008] | — | RMSE 6.235 vs 6.276, better in 4 of 4 seasons |
| nf_ols vs calibrated ESPN | +0.146 [+0.101, +0.195] | — | still far behind |

**Selection (pre-registered rules).**
- ESPN-free challenger: `nf_ols` → `m2_no_espn`.
- Augmentation challenger: `aug_resid_enet` → `m2_espn_aug`, a calibrated-ESPN base plus an elastic-net residual (penalty 0.1, mixture 0.5) on all M2 features. Its RMSE is no worse than the benchmark.
- **Frozen** in models/registry/m2.yml, generated by `write_m2_registry()`. Parent commit `9f36579`, frozen at 2026-10-05T22:42Z.

**Status of the historical criterion.** It requires the development pooled CI to lie
below 0. The CI's upper bound is +0.001, so **the criterion is already not met**,
regardless of the holdout. The signal is consistent in direction but too small to
separate from noise over 71 weeks.

**Negative findings so far.**
- XGBoost did not beat linear models in any role.
- Elastic-net shrinkage did not help the ESPN-free model.
- The calibration family choice is immaterial.
- New features improved the ESPN-free model only modestly over M1's feature set.

**Next.** Run the 2024–2025 holdout once for the frozen M2 models. Run the
descriptive ablations, representation and residual studies on the development folds.

---

## 2026-10-05 — E5: One-time 2024–2025 holdout of the frozen M2 lineage, plus descriptive studies

**Holdout** (weekly rolling refits, all ESPN-projected WRs, n = 5,091, 36 weeks; frozen models unchanged):

| model | MAE | RMSE | bias | weekly Spearman | pairwise acc. (top 60) |
|---|---|---|---|---|---|
| m1_espn_plus (frozen M1) | 4.144 | 5.810 | +0.15 | 0.701 | 0.634 |
| **m2_espn_cal** | 4.144 | 5.816 | +0.12 | 0.698 | 0.635 |
| m1_espn_recal | 4.154 | 5.814 | +0.18 | 0.698 | 0.634 |
| **m2_espn_aug** | 4.154 | 5.816 | +0.24 | 0.700 | 0.637 |
| raw ESPN | 4.190 | 5.835 | +0.39 | 0.698 | 0.634 |
| m2_no_espn | 4.333 | 5.988 | +0.18 | 0.666 | 0.617 |
| m1_no_espn | 4.340 | 6.016 | +0.07 | 0.661 | 0.613 |
| naive_roll8 | 4.422 | 6.238 | +0.17 | 0.638 | 0.605 |

**Paired comparisons** (season-stratified week bootstrap):

| comparison | subset | ΔMAE [95% CI] | detail |
|---|---|---|---|
| m2_espn_aug vs m2_espn_cal | all | **+0.010 [−0.006, +0.027]** | worse in both 2024 (+0.010) and 2025 (+0.009); RMSE 5.816 vs 5.816 |
| m2_espn_aug vs m2_espn_cal | top 60 | +0.038 [+0.012, +0.065] | **significantly worse** |
| m2_espn_aug vs m2_espn_cal | top 36 | +0.048 [+0.011, +0.084] | **significantly worse** |
| m2_espn_cal vs raw ESPN | all | −0.046 [−0.060, −0.033] | calibration replicates |
| m1_espn_plus vs m2_espn_cal | all | −0.001 [−0.016, +0.014] | a tie |
| m2_no_espn vs m1_no_espn | all | −0.007 [−0.036, +0.022] | RMSE 5.988 vs 6.016 |
| m2_no_espn vs m2_espn_cal | all | +0.188 | — |

**Historical evidence criterion (E3): NOT MET.** It fails at both stages:
- development CI upper bound +0.001;
- holdout ΔMAE positive in both seasons.

**Interpretation.** The augmentation model ranks slightly better (pairwise 0.637 vs
0.635) but adds positive bias. Its small, direction-consistent development gain did
not survive out of sample, and it hurts among fantasy-relevant WRs. Calibration is
the only robust gain over raw ESPN, about −0.02 to −0.05 MAE across six seasons.

**M2 fingerprint.** The holdout predictions of the frozen models were written once to
models/fingerprints/m2_holdout_2024_2025.csv and re-verified as identical.

### Descriptive studies (development folds only; not used for any decision)

**Ablations** (static development folds; Δ = MAE without the family − MAE with it):
- **nf_ols:** opportunity +0.028, role change +0.026, history +0.021, priors +0.007,
  opponent +0.003, team +0.002, QB −0.001, efficiency −0.007, context −0.009.
- **aug_resid_enet:** every family within ±0.005. Opportunity +0.003 is the largest; removing context would have helped by 0.005.

**Temporal representation** (OLS, same base features):

| representation | MAE |
|---|---|
| EWMA + trend | 4.596 |
| EWMA 2/6 | 4.625 |
| trailing 1/2/4/8 | 4.641 |
| M1 trailing 3/8 | 4.644 |

**Residual study** (actual − calibrated ESPN, development rolling; uncertainty from week-level means):
- **Rising target share** (top two quintiles of trend): −0.37 and −0.38, CIs below 0.
- **Rising xFP:** −0.56 [−0.88, −0.23]. **Falling xFP:** +0.33 [+0.06, +0.60].
- **Did not play the team's previous game:** −0.63 [−1.02, −0.24].
- **Low points-over-xFP:** −0.34 [−0.59, −0.09].
- **Projection range 5–10:** −0.29 [−0.54, −0.04].

ESPN tends to **over-react to recent role changes and to over-project players
returning from an absence**. That is the opposite of the "ESPN is slow to recognise
role change" hypothesis. However, a residual model using these features did not
generalise to 2024–2025, so these patterns are not yet a usable edge.

**Decision.** The frozen M2 lineage is not modified. It enters the prospective record
from 2026 Week 5, alongside M1. The residual patterns above are recorded as
hypotheses for a future challenger (M3), to be pre-registered and tested
prospectively.

---

## 2026-10-06 — E6: Milestone 3 pre-registration of the rule challengers (before freezing; before any 2026 outcome was evaluated)

**Strategy change.** M2 showed that richer historical statistics and more flexible
models do not beat calibrated ESPN. M3 therefore tests:
- (i) a very small number of narrow, pre-registered hypotheses about systematic
  ESPN errors, as fixed rules rather than learned models;
- (ii) genuinely new pregame information (docs/milestone3_plan.md §13).

There is no broad model search.

**Base for every rule.** Calibrated ESPN with the same family and weekly refit
procedure as the frozen `m2_espn_cal` (components with recency weights, training
from 2018). The rules add **constants**. Nothing is learned at run time.

**Development evidence** (2020–2023 only; residual = actual − calibrated ESPN, weekly rolling):

| group | n | mean residual | by season (2020–23) |
|---|---|---|---|
| xfp_trend top decile (≥ 1.42) | 964 | −0.61 (se 0.24) | −0.80, −0.42, −0.56, −0.44 |
| xfp_trend bottom decile (≤ −1.65) | 964 | +0.52 (se 0.19) | +1.35, −0.42, +0.62, +0.49 |
| xfp_trend top / bottom quintile | — | −0.55 / +0.33 | — |
| returning, 1 team game missed | 325 | −0.44 (se 0.34) | inconsistent |
| returning, 2+ team games missed | 279 | −0.84 (se 0.33) | negative in all 4 |

**Frozen rules.** Magnitudes are half the development means, against winner's curse.

| id | rule |
|---|---|
| `m3_role_adjust_v1` (primary A) | xfp_trend ≥ 1.42 → −0.30; ≤ −1.65 → +0.25 |
| `m3_role_adjust_q20_v1` (A sensitivity) | xfp_trend ≥ 0.80 → −0.27; ≤ −1.11 → +0.16 |
| `m3_return_adjust_v1` (primary B) | 1 team game missed since the last appearance this season → −0.2; 2+ → −0.4 |
| `m3_combined_v1` | A primary + B primary, additive |

**Prospective hypotheses** (evaluated once, at the end of the 2026 regular season,
on archived pre-kickoff runs only):
- **H-A.** `m3_role_adjust_v1` has lower MAE than `m2_espn_cal` (from the same runs).
  The paired week-bootstrap 95% CI for ΔMAE must lie entirely below 0, with RMSE no worse.
- **H-B.** The same test for `m3_return_adjust_v1`.

Secondary analyses:
- `m3_combined_v1`, and the q20 sensitivity variant;
- the top 60 and top 36 subsets;
- the share of weeks won;
- the affected-subset view: ΔMAE restricted to players a rule touched. Descriptive only, because it is defined by the rule, not by outcomes.

**Insufficient** means fewer than 8 completed archived weeks for that lineage.
The criteria are not weakened.

**One-time historical check.** 2024–2025 rolling, run once **after** freezing and
reported. It cannot change the rules.

**Versioning.** Any later change becomes `*_v2`, with a new prospective start.
v1 records stay as they are.

---

## 2026-10-06 — E7: One-time 2024–2025 check of the frozen M3 rules (run after the freeze at 00:24Z; cannot change the rules)

**Process note.** The check first exposed a closure bug in `registry_spec_adjusted()`:
the combined challenger's role-rule function captured a variable that was later
reassigned. It was fixed (the registry was unchanged), and a test now covers it.
The frozen-spec targets now list their spec builders explicitly, because
dynamic lookup had hidden them from targets. After the change, M2's frozen
predictions were re-verified as identical.

**Results** vs `m2_espn_cal` (same base and procedure), weekly rolling, n = 5,091, 36 weeks:

| challenger | all ΔMAE [95% CI] | top 60 | top 36 | RMSE (vs 5.8155) |
|---|---|---|---|---|
| m3_role_adjust_v1 | −0.0017 [−0.0050, +0.0013] | −0.0081 [−0.0146, −0.0022] | −0.0093 [−0.0180, −0.0013] | 5.8137 |
| m3_role_adjust_q20_v1 | −0.0008 [−0.0037, +0.0019] | −0.0085 [−0.0141, −0.0026] | −0.0081 [−0.0158, −0.0007] | — |
| m3_return_adjust_v1 | −0.0035 [−0.0058, −0.0011] | −0.0010 (ns) | −0.0005 (ns) | 5.8164 (+0.0009) |
| m3_combined_v1 | **−0.0054 [−0.0089, −0.0022]** | −0.0094 (CI < 0) | −0.0098 (CI < 0) | **5.8147** |

**By season.**
- Role v1: +0.0002 (2024), −0.0036 (2025).
- Return v1: −0.0021, −0.0048.
- Combined: −0.0021, −0.0086. Its RMSE was +0.0013 in 2024 and −0.0064 in 2025.

**Rule-touched subsets** (descriptive):

| group | n | mean residual vs calibrated ESPN | MAE: calibrated → adjusted |
|---|---|---|---|
| rising role (adjusted down) | 509 | −0.37 | 5.62 → 5.56 |
| falling role (adjusted up) | 434 | +0.29 | 4.58 → 4.63 |
| returning (adjusted down) | 271 | −0.44 | 3.77 → 3.71 |

The falling-role adjustment moves the mean in the right direction yet worsens MAE,
because the outcome is skewed.

**Reading.**
- All three hypothesised directions held in two seasons that played no part in
  deriving the rules.
- The combined rule's interval excludes 0, with RMSE no worse.
- The effects are very small: about 0.1% of MAE over all WRs, and about 0.2% among likely starters.
- This is supporting, not confirmatory, evidence. The rules came from a
  development search, and one historical check is not a prospective test.

**Decision.** No change. The frozen rules proceed to the prospective record.

**M3 fingerprint.** Written once (models/fingerprints/m3_holdout_2024_2025.csv) and verified as identical.

---

## 2026-10-06 — E8: Live-run artifact (unfinished earlier game) found and fixed

The first three Week-5 runs were made on Monday evening, while the Week-4
ATL–NO game was unfinished. They are 20261005T203755Z (M1),
20261005T224946Z (M1+M2) and 20261006T002822Z (M1+M2+M3).

For the **9 ATL/NO WRs** in each run, the feature engines treated that game as one
the player **missed**. The game had kicked off, but there was no stat line yet. This
affects M1/M2 `played_team_prev_game` and the M3 return rule.

It is not leakage: no future information was used. It is a staleness artifact that
cannot occur historically, where every game is final.

**Fix** (`drop_unfinished_games()`, live runs only, a no-op on history). Any earlier
game that is not final is removed from every history table and from the
"previous game" schedule, so it is neither played nor missed. nflverse can
publish partial in-game stats, so this also prevents partial stats from entering.
Each run's `run_meta.json` now lists any such games. No frozen model changed.

**Prospective handling.** The three runs stay archived as they are. ATL and NO kick
off on Sunday, so any later run before Sunday's kickoff, once Week 4 is final,
supersedes them as the official prediction under the existing latest-valid-run rule.
If none were made, the archived runs would remain official, and this note documents
their artifact.

---

## 2026-10-06 — E9: New-information hypotheses from pregame-timestamped injury reports (pre-registration of D; negative result for C)

**Source.** nflverse final weekly injury reports, 2017–2024. A row is used only if
its own `date_modified` is strictly before the team's kickoff. 2017–2020 stamps
are corrected from Pacific wall-clock time. 2025 has no timestamps and is
excluded, not backfilled. For 2026, the timestamp is our dated live retrieval time.
Of 23,081 designated rows, 2,690 were dropped as untimed or stamped after kickoff
(almost all of them 2025).

**Development evidence** (2020–2023; residual = actual − calibrated ESPN, weekly rolling):

| group | n | mean residual | by season |
|---|---|---|---|
| own **Questionable** | 577 | **−1.36** (se 0.27) | −1.17, −2.35, −1.73, −1.13 |
| as a share of calibrated ESPN | — | **−18%** | −13%, −26%, −19%, −13% |
| own Doubtful | 4 | — | too few (ESPN zeroes nearly all) |
| vacated teammate target share 0.10–0.20 | — | −0.32 | +0.73, −0.50, −0.58, −0.13 |
| vacated teammate target share > 0.20 | — | −0.56 | +0.05, −0.76, −0.68, +0.22 |

- **Hypothesis C, that ESPN under-adjusts for vacated targets, is NOT supported.**
  The sign is opposite to the hypothesis and inconsistent across seasons, so no rule
  is frozen. This is recorded as a negative finding.
- Questionable WRs are not more often zero (21% vs 24%). They play, but produce
  less, and the shortfall scales with the projection.

**Hypothesis D (pre-registered).** ESPN over-projects WRs whose pregame-valid
final injury designation is Questionable.

| id | rule |
|---|---|
| `m3_questionable_adjust_v1` (primary) | if Questionable: calibrated ESPN × (1 − 0.09) (half of −18%) |
| `m3_questionable_add_v1` (sensitivity) | if Questionable: −0.68 points (half of −1.36) |
| `m3_combined_abd_v1` (pre-registered combination) | `m3_role_adjust_v1` + `m3_return_adjust_v1` + D primary, all from the same base |

**Timing notes.**
- The designation must have been captured before the player's kickoff.
- Sunday games are designated in the Friday report. A Thursday run therefore
  sees no designation for them, and only later runs (Saturday or Sunday morning)
  can apply D.
- Historical ESPN values are final pregame values, which already absorb some
  game-day inactives. A prospective snapshot taken before inactives may leave
  more questionable players over-projected. The direction is the same; the size may differ.

**Prospective test (H-D).**
- `m3_questionable_adjust_v1` vs `m2_espn_cal` from the same runs.
- The ΔMAE 95% week-bootstrap CI must lie entirely below 0, with RMSE no worse.
- Evaluated at the end of 2026; fewer than 8 completed archived weeks means insufficient.
- The rule touches only about 6% of rows, so the affected-subset view will be reported descriptively.

**One-time historical check.** 2024 only, because 2025 has no timestamps. Run after
the freeze, it cannot change the rule.

**Lineage.** M3b (models/registry/m3b.yml), a separate registry, because M3's is
write-once.

---

## 2026-10-06 — E10: One-time 2024 check of the frozen hypothesis-D challengers (M3b frozen 00:41Z; cannot change the rules)

**Results** vs `m2_espn_cal`, weekly rolling 2024, n = 2,499, 18 weeks:

| challenger | all ΔMAE [95% CI] | top 60 | top 36 | weeks better | RMSE (vs 6.0441) |
|---|---|---|---|---|---|
| m3_questionable_adjust_v1 | **−0.0126 [−0.0204, −0.0056]** | −0.0242 [−0.0425, −0.0065] | −0.0262 [−0.0517, −0.0039] | 89% | **6.0372** |
| m3_questionable_add_v1 | −0.0108 [−0.0165, −0.0056] | −0.0153 [−0.0273, −0.0036] | −0.0150 [−0.0301, −0.0018] | 89% | 6.0390 |
| m3_combined_abd_v1 | −0.0142 [−0.0250, −0.0043] | −0.0296 [−0.0515, −0.0089] | −0.0322 [−0.0631, −0.0050] | 83% | 6.0391 |

**Affected rows.** 130 Questionable WR-weeks in 2024. Their mean residual vs
calibrated ESPN was −1.21 (−14% of the projection; development −18%). MAE on
these rows went from 4.73 to 4.49.

**Reading.**
- The development finding replicated in a season not used to derive it. Every
  interval excludes 0, RMSE improves, and 89% of weeks are better.
- This is the first new-information source in the project with incremental
  value over calibrated ESPN. The gain is small overall (about 0.3% of MAE),
  because only about 5% of rows are touched, but it is about 5% on those rows.
- Not confirmatory:
  - It rests on one historical season (2025 cannot be checked: no timestamps).
  - The prospective information timing differs. Our snapshots precede game-day
    inactives, while historical ESPN values are post-inactive.

**Decision.** No change. M3b enters the prospective record from Week 5. Because
designations for Sunday games appear in the Friday report, **Saturday or Sunday
runs are required** for D to act on Sunday games.

**M3b fingerprint.** Written once and verified as identical.

---

## 2026-10-06 — E11: Pregame expected QB from the nfldata git history (hypothesis E); examined, NOT frozen

**Source** (verified; docs/source_feasibility.csv). `nflverse/nfldata`
`data/games.csv` is committed every 10–20 minutes from 2021.
- The history is linear: 51,477 commits, no force pushes.
- Commit-to-push lag is about 1 s where verifiable (2023-04 onward).
- The expected-starter QB columns exist from 2021-03.

For every 2021–2025 game we take the version committed **strictly before
kickoff − 2 h** (`fetch_nfldata_asof()`):
- every selected commit precedes its cutoff;
- median staleness is 5–15 minutes;
- QB ids are missing in 4.5% of 2023 games and 0% otherwise;
- the expected starter matched the actual starter (dropback leader) in **92.5%** of team-games.

The repository has no license file, so this is used for private research only and
nothing derived is committed.

**Development evidence** (2021–2023; residual vs calibrated ESPN):

| group | n | mean residual | by season | share of projection |
|---|---|---|---|---|
| any expected QB change | 879 | −0.21 (se 0.33) | — | −4% |
| change to a backup (< 8 prior starts) | 273 | −0.54 (se 0.41) | −0.47, −0.66, −0.67 | −9% |
| change to an established starter | 606 | −0.20 | +0.04, +0.08, −0.59 | — |
| no change (reference) | 6,446 | −0.15 | — | — |

**Decision. Not frozen.**
- The only consistent pattern, a backup starting, is within noise (t ≈ 1.3, and about
  −0.4 relative to the reference).
- Its "< 8 starts" split was chosen after seeing the data.
- Freezing it would invite forking-paths optimism.

The expected-QB data remains available, historical-valid for 2021–2025 and
prospective via our dated schedule captures, for a future, larger test.

**Lines.** As-of-forecast spreads and totals (2021–2025) now exist, which
resolves the closing-line timing problem of M1/M2. They were not tested as a
new hypothesis: M2 found closing lines added nothing, and ESPN likely prices
game environment. This is recorded as available, not as evidence.

**Live-run hardening.** An earlier game now counts as complete only if it is
final **and** its stats are published, checked by `game_id`. The schedule can mark
a game final before nflverse's player stats include it. A test covers this.

---

## 2026-10-06 — E12: Milestone 4 pre-registration (before any M4 experiment; no 2026 week completed)

The full plan is in docs/milestone4_plan.md and is binding.

**Protocol.**
- Development: **2020–2023**, the same folds as M2/M3 (contaminated: the Questionable finding came from here).
- **Primary final check: 2019.** It was never evaluated for any hypothesis.
- Secondary check: 2024. It is contaminated, because it confirmed D.
- 2025 is excluded (no injury timestamps).
- 2026 is prospective only.

**Candidates** (budget 4, plus 2 frozen baselines):
- B0 `m2_espn_cal`; B1 `m3_questionable_adjust_v1`;
- K1 practice-refined designation rule;
- K2 two-stage availability;
- K3 availability-adjusted targets (TDs unchanged);
- K4 target-disagreement blend on top of B1.

**Freeze criteria.**
- vs B0: development pooled CI below 0, and 2019 ΔMAE < 0, with RMSE no worse.
- vs B1: development pooled ΔMAE < 0 and 2019 ΔMAE < 0, with RMSE no worse.
- Otherwise M3b remains the injury model.
- 2024 cannot rescue a candidate that fails 2019.

---

## 2026-10-06 — E13: Milestone 4 development findings and FIXED candidate parameters (written 06:20Z, before the 2019 and 2024 checks)

All numbers below come from development seasons 2020–2023 only.
- Residuals are measured against the weekly rolling calibrated-ESPN base (the `m2_espn_cal` procedure).
- B1 recomputed in the M4 frame equals the frozen M3b predictions to within 1e-9 (2,499 rows in 2024; target `m4_b1_matches_frozen`).

**Coverage** (`injury_coverage`). Rows that are valid pregame, by season:

| | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 |
|---|---|---|---|---|---|---|---|---|
| valid | 4,949 | 4,959 | 5,197 | 5,401 | 5,345 | 5,433 | 5,451 | 5,953 |
| dropped as stamped after kickoff | 0 | 2 | 5 | 13 | 3 | 0 | 0 | 1 |

- 2022 has 17 rows for a game missing from the schedule.
- 2025 has 5,783 rows, all untimed, and is excluded.

**What Questionable represents** (`m4_decomposition`, `m4_availability_pop`).

| group | n (ESPN pop.) | points vs base | P(active), ESPN pop. | P(active), all listed WRs | targets vs ESPN if active | points per target if active vs ESPN |
|---|---|---|---|---|---|---|
| Q + practice DNP | 73 | −30% | 0.93 | **0.49** | −7% | 1.36 vs 1.79 |
| Q + Limited | 388 | −19% | 0.97 | **0.76** | −9% | 1.58 vs 1.76 |
| Q + Full | 110 | −8% | 0.98 | **0.81** | −12% | 1.86 vs 1.76 |
| listed only, DNP/LP | 389 | −4% | 0.99 | 0.89 | −5% | 1.85 vs 1.83 |
| listed only, FP | 933 | −4% | 0.99 | 0.96 | −2% | 1.78 vs 1.80 |
| not listed | 8,013 | +1.6% | 0.99 | — | +0.5% | 1.77 vs 1.75 |

- **In historical evaluation, Questionable is a workload-and-efficiency signal, not an availability signal.**
  - Historical ESPN projections are final values. For most game-day inactives, ESPN has already set them to 0.
  - For example, 115 of the 136 Q-Limited WRs with an ESPN projection of 0 were inactive. Such players fall outside the evaluation population.
  - Inside that population, 93–98% of Questionable WRs play. Those who play earn about 9% fewer targets than ESPN expects and convert them worse.
  - Points per target falls sharply after a DNP week.
- **Prospectively the picture differs.** Our snapshots come before inactives are announced.
  - Of all Questionable WRs, 24% (Q-LP), 19% (Q-FP) and 51% (Q-DNP) are inactive.
  - Historical ESPN data cannot evaluate this component, because the inactive rows carry no pre-inactive ESPN projection.
  - This is recorded as the main open question for the prospective record (see M5).
- **Body part (exploratory)** has no signal. The Questionable shortfall is −18% for lower body (n 408), −17% upper (103), −19% non-injury (45) and −19% head (20).
- **Narrow teammate-absence check on targets** (`m4_teammate`; hypothesis: WRs whose teammates are Out/Doubtful get more targets than ESPN expects). **Rejected and closed.**
  - The slope of (actual − calibrated ESPN targets) on vacated target share is −0.50 (se 0.25), and negative in all four seasons (−0.06, −0.27, −1.34, −0.30).
  - ESPN already moves targets to the remaining WRs, if anything slightly too far. This matches E9's points result.
- **Target disagreement** (`m4_disagreement`). Realised targets move w = 0.25 of the way from calibrated ESPN toward our independent target model (by season 0.16, 0.27, 0.28, 0.30). M3's points-based estimate was about 0.33.

**Fixed parameters** (research/m4_candidate_params.yml; the pipeline re-derives them and fails on any difference).
- Groups with n < 100 in development are pooled with all Questionable/Doubtful rows (`Q_pool`, n = 581): Q-DNP 73, Q-other 6, Doubtful 4.

| id | rule | parameters |
|---|---|---|
| K1 | base × (1 + m), with m = Q_pool −0.09, Q-LP −0.09, Q-FP **−0.04**, listed-only DNP/LP −0.02 (half the development ratios) | 4 |
| K2 | base × P̂(active) × r on the same groups. Logit: 3.533 − 0.752·DNP + 0.058·LP − 3.179·Doubtful − 0.891·returning + 0.430·min(streak, 4). r = Q_pool 0.83, Q-LP 0.82, Q-FP 0.93, listed DNP/LP 0.96 | 10 |
| K3 | base + a · calibrated ESPN targets × ESPN points/target, with a = Q_pool −0.05, Q-LP −0.05, Q-FP −0.07, listed DNP/LP −0.02 (half the target ratios). TDs unchanged | 4 |
| K4 | B1 + 0.25 · (our targets − calibrated ESPN targets) × ESPN points/target | 2 |

Interpretations fixed before the checks:
- K2 follows the plan text literally, so it is **not halved**. It therefore also tests full against half shrinkage.
- K1 to K3 do not adjust listed-only full-practice rows.
- "ESPN points/target" = ESPN rec/target × 1 + ESPN yards/target × 0.1. In development it ranges 1.10–1.93.

**Development results** (in-sample for the parameters; pooled 2020–2023, n = 9,916, ΔMAE with 95% week-bootstrap CI):

| | vs B0 (all) | vs B1 (all) | vs B1 top 60 | vs B1 top 36 | RMSE (B0 6.1007, B1 6.0884) |
|---|---|---|---|---|---|
| B1 | −0.0136 [−0.0185, −0.0094] | — | — | — | 6.0884 |
| K1 | −0.0146 [−0.0195, −0.0103] | −0.0010 [−0.0023, 0.0004] | −0.0027 | −0.0037 | 6.0879 |
| K2 | −0.0270 [−0.0375, −0.0181] | −0.0134 [−0.0197, −0.0079] | −0.0201 | −0.0297 | 6.0825 |
| K3 | −0.0078 [−0.0104, −0.0056] | +0.0059 [0.0035, 0.0084] | +0.0085 | +0.0131 | 6.0939 |
| K4 | −0.0114 [−0.0202, −0.0028] | +0.0023 [−0.0055, 0.0099] | −0.0166 | −0.0113 | **6.0745** |

Development status under the pre-registered criteria:
- K1 and K2 pass both development conditions.
- K3 fails vs B1: the target-only path misses the efficiency loss.
- K4 fails vs B1 on all-row MAE, although it has the best RMSE and the best top-60 result.
- **The 2019 check decides between K1 and K2.** By the simplicity rule, K1 (4 parameters) wins unless K2 is better than K1 in both development and 2019.

The 2019 (primary) and 2024 (secondary) checks are run **once**, after this entry is committed.

---

## 2026-10-06 — E14: One-time 2019 (primary) and 2024 (secondary) checks of the fixed M4 candidates; decision

The checks ran once at about 06:25Z, after E13 and the parameter file were committed and pushed (39b8059).

**2019, the fresh primary check** (never used before; n = 2,384, 17 weeks; base trained on 2018 plus earlier 2019 weeks):

| | vs B0 `m2_espn_cal` | vs B1 M3b | top 60 vs B0 | top 36 vs B0 | RMSE |
|---|---|---|---|---|---|
| B0 | — | — | — | — | 6.3686 |
| **B1** | **−0.0075 [−0.0143, −0.0005]** | — | −0.0056 | +0.0007 | 6.3633 |
| K1 | −0.0098 [−0.0168, −0.0025] | −0.0023 [−0.0046, −0.0001] | −0.0111 | −0.0067 | 6.3608 |
| **K2** | **−0.0185 [−0.0347, −0.0009]** | **−0.0111 [−0.0216, +0.0011]** | −0.0157 | −0.0143 | **6.3591** |
| K3 | −0.0054 [−0.0083, −0.0022] | +0.0021 | −0.0062 | −0.0051 | 6.3635 |
| K4 | +0.0057 [−0.0188, 0.0313] | +0.0131 | −0.0154 | −0.0106 | 6.3547 |

- **The M3b Questionable rule replicates in a season never used before** (CI below 0). Before this check it had only the contaminated 2024 confirmation.
- Injury-affected rows (n = 207):

  | | B0 | B1 | K1 | K2 |
  |---|---|---|---|---|
  | MAE | 5.25 | 5.16 | 5.13 | **5.03** |
  | bias | +1.52 | — | — | +0.21 |

**2024, the secondary contaminated check** (n = 2,499):

| | vs B0 | vs B1 | RMSE (B0 6.0441, B1 6.0372) |
|---|---|---|---|
| B1 | −0.0126 [−0.0203, −0.0048] (= E10) | — | 6.0372 |
| K1 | −0.0120 | +0.0006 | 6.0380 |
| K2 | −0.0219 [−0.0400, −0.0058] | −0.0092 [−0.0204, 0.0000] | 6.0387 (slightly worse than B1) |
| K3 | −0.0066 | +0.0061 | 6.0407 |
| K4 | +0.0100 | +0.0226 [0.0068, 0.0378] | 6.0396 |

- On the affected rows (n = 214), K2's MAE is 4.85 vs 4.96 for B1, but its bias is −0.51: it over-corrects in 2024.
- In the 2024 top-36 and top-24 subsets, K2's RMSE is worse than B0's.

**Decision** (pre-registered rule; target `m4_decision`):

| | vs B0 | vs B1 | eligible |
|---|---|---|---|
| K1 | pass | pass | yes |
| K2 | pass | pass | yes |
| K3 | pass | **fail** | no |
| K4 | **fail** | **fail** | no |

- K2 is better than K1 in both development (−0.0270 vs −0.0146) and 2019 (−0.0185 vs −0.0098). By the plan's exception to the fewest-parameters rule, **K2 is the primary M4 challenger: `m4_two_stage_v1`.**
- K1 also met every criterion and is frozen as a secondary: `m4_practice_rule_v1`.
- **Process note.** The first coded version of `m4_freeze_decision()` implemented only "fewest parameters wins" and returned K1. It was corrected to the committed plan text (section 10, restated in E13) before anything was frozen. A test now covers both branches.

**How strong is this?** It is a moderate, not decisive, improvement over M3b:
- K2 vs B1 is −0.011 in 2019 and −0.009 in 2024, but neither CI excludes 0.
- K2 has 10 parameters and is not shrunk.
- Its bias on affected rows swings: −0.10 in development, +0.21 in 2019, −0.51 in 2024.
- Its RMSE is slightly worse than B1's in 2024.
- What K2 adds over B1 is mostly magnitude. It applies about −20% to Questionable rows where B1 applies −9%, plus small listed-only adjustments. The practice-status split itself (K1 vs B1) is worth only about −0.002.
- K3 (adjusting targets only) underperforms B1. **The Questionable shortfall is not only opportunity: efficiency matters too.**
- K4 (target disagreement) improves RMSE but not MAE. Closed.

**Pre-registered prospective test (H-M4).**
- `m4_two_stage_v1` vs `m3_questionable_adjust_v1` and vs `m2_espn_cal`, using the same archived runs.
- Success: the ΔMAE 95% week-bootstrap CI lies below 0, with RMSE no worse.
- Evaluated at the end of 2026; fewer than 8 completed weeks counts as insufficient.
- `m4_practice_rule_v1` is reported descriptively.

**Horizon notes** (fixed now):
1. Our snapshots precede game-day inactives, so K2's P(active), learned on the post-inactive ESPN population (about 0.97), probably under-states prospective inactivity. If K2 is wrong prospectively, it is most likely too mild.
2. Live rows of the target week are used only after the team's final report is out (at least one designation; `live_injury_detail`). Thursday runs therefore leave Sunday games unadjusted, as with M3b.
3. Earlier weeks of the live capture feed only lagged features.

---

## 2026-10-06 — E15: M4 frozen; first prospective run; live and operational rules

**Freeze.** models/registry/m4.yml was written at 06:26Z (parent e4556f7).
- It holds `m4_two_stage_v1` (primary) and `m4_practice_rule_v1`.
- The registry rebuilds the 2019 + 2024 predictions, which equal the candidate study
  to within 1e-9 (9,766 rows; target `m4_frozen_matches_candidates`).
- The fingerprint is models/fingerprints/m4_checks_2019_2024.csv.
- The M1, M2, M3 and M3b fingerprints remain identical.

**First prospective run.** Run 20261006T062916Z (2026 W5) covers all five lineages and
was pushed about 66 hours before kickoff.
- It reused the 03:44Z ESPN snapshot, so M4 made no ESPN requests.
- The Monday ATL–NO game had been flagged unfinished at 03:44Z and is final in this
  run. This run supersedes the earlier ones as the official W5 prediction for every lineage.
- No team's Week-5 final injury report exists yet, so M3b and M4 currently equal
  calibrated ESPN for W5. A run after Friday's reports is needed for them to act.

**Live rules** (written before any 2026 outcome; `live_injury_detail()`):
- Target-week rows count only after the team's final report (≥ 1 designation) is in
  our capture.
- Earlier weeks feed lagged features only.
- Historically, about 2% of team-weeks have listings without any designation.

**Evaluation tooling.**
- `score_prospective()` now includes `m3_questionable_adjust_v1` as a benchmark.
- It pairs each comparison over the player-weeks both models predicted, so a later
  lineage never shrinks the comparison set of an earlier one.

**Optional `late_pregame` horizon.**
- Plumbing only: `--late-pregame`, a separate archive root and manifest, and `horizon`
  recorded in `run_meta.json`.
- Not run. If it is ever used, it gets its own analysis and is never pooled with
  `standard_pregame`.

**Influence on later choices.** None of E13–E15 used a 2026 outcome.

---

## 2026-10-13 — E16: Prospective analysis addendum for the 2026 record (master plan F1; written before any 2026 outcome was scored)

**Status.** Written during 2026 Week 6, before any 2026 outcome was loaded by an evaluation routine
(`score_prospective()` has never been run on 2026). The frozen procedure's use of completed 2026 weeks
as training rows (docs/prospective_protocol.md) is unchanged, and it is not scoring.

**What does not change.** Every primary hypothesis and insufficiency rule stays exactly as written:
- **H-M2** (E3): `m2_espn_aug` vs `m2_espn_cal`; fewer than 10 weeks is insufficient.
- **H-A, H-B** (E6), **H-D** (E9): fewer than 8 weeks is insufficient.
- **H-M4** (E14): vs M3b and vs calibrated ESPN; fewer than 8 weeks is insufficient.

Success always means the paired week-bootstrap 95% CI of ΔMAE lies entirely below 0, with RMSE no
worse. Official predictions, population and bootstrap are those of the protocol and `score_prospective()`.
**Nothing below can turn a failed primary into a success.**

### 1. Power: how a null must be read

**Method** (`R/evaluation/power.R`; targets `f1_noise`, `f1_reference`, `f1_mde`; historical frames only):
- **σ_w**, the week-level noise, is the within-season SD of each week's linearised contribution to the
  pre-registered statistic Σs/Σn.
  - Check on 2019 H-D: linearised SE 0.00356 vs week-bootstrap SD 0.00343.
  - The same bootstrap reproduces E14's interval [−0.0143, −0.0005].
- **σ_w is pooled** over the available seasons:
  - H-M2: 2020–2025;
  - H-A and H-B: 2024–2025;
  - H-D and H-M4: 2019–2024, the E13/E14 frame.
- **MDE** = (t₀.₉₇₅,W−1 + t₀.₈₀,W−1)·σ_w/√W.
- **Power** is for the actual criterion (CI entirely below 0): a one-sided noncentral t toward improvement.
- **Reference effect** (the plausible true effect) is the cleanest historical check:
  - 2019 for H-D and H-M4 (fresh, E14);
  - the 2024–2025 holdout for H-M2, H-A and H-B (E5, E7).

  Development seasons are not used, because they are in-sample for the M4 parameters.
- **Informative weeks:** W5–W18 = 14. For H-D and H-M4, W5 is a structural zero (§2), so at most 13.

**MAE, the primary family.** Baseline MAE is 4.52 (2019) and 4.14 (2024–2025).

| Hypothesis | Reference Δ (seasons) | σ_w | MDE, W = 13 / 14 | Power at reference, W = 13 / 14 | Power if σ_w × 1.5 | Power with the reference season's own σ_w | Pooled 2026 + 2027 (§3 S5), σ_w × 1 / × 1.5 |
|---|---|---|---|---|---|---|---|
| H-M2 aug vs cal | **+0.0098** (2024–25: aug *worse*) | 0.057 | 0.048 / 0.046 | ≈ 0.01 | ≈ 0.01 | ≈ 0.01 | ≈ 0 / ≈ 0 |
| H-A role rule | −0.0017 (2024–25) | 0.010 | 0.0085 / 0.0081 | 0.08 / 0.09 | 0.06 | 0.08 / 0.09 | 0.15 / 0.09 |
| H-B return rule | −0.0035 (2024–25) | 0.0071 | 0.0060 / 0.0058 | 0.37 / 0.40 | 0.19 / 0.21 | 0.37 / 0.40 | 0.77 / 0.44 |
| H-D Questionable | −0.0075 (2019) | 0.019 | **0.016** / 0.0155 | **0.25** / 0.27 | 0.14 / 0.15 | 0.39 / 0.42 (σ_w 0.0147) | 0.56 / 0.29 |
| H-M4 vs cal | −0.0185 (2019) | 0.041 | **0.0345** / 0.033 | **0.32** / 0.35 | 0.17 / 0.18 | 0.39 / 0.42 (σ_w 0.0363) | 0.69 / 0.37 |
| H-M4 vs M3b | −0.0111 (2019) | 0.025 | **0.021** / 0.020 | **0.32** / 0.34 | 0.17 / 0.18 | 0.33 / 0.36 (σ_w 0.0240) | 0.68 / 0.36 |

Bold marks the attainable horizon for the injury families (13 informative weeks). Pooled W = 13 + 18
(injury families) or 14 + 18. MSE family: power ≤ 0.12 for every hypothesis at 13–14 weeks.

**The pre-registered bootstrap is anti-conservative at this sample size.** I simulated normal
week-level differences, 4,000 seasons of W = 13 with 400 resamples each
(`percentile_bootstrap_sim(13, c(0, -0.39, -0.45, -0.51))`, seed 7). The percentile week bootstrap
put its 95% CI entirely below 0 for:
- **4.9% of seasons with no true effect.** The nominal rate is 2.5%. This is the known few-clusters problem (Cameron et al. 2008).
- **36% of seasons at H-D's effect-to-noise ratio** (0.39 σ_w), against 25% from the t-based formula above.
- 41% at 0.45 σ_w, against 32%.

The table's t-based power figures are therefore conservative by about 10 points. The primary keeps its
pre-registered bootstrap; S8 adds the small-sample check.

**Reading rules (pre-declared).**
1. If a primary CI spans 0, the result is reported as "not supported; the test was under-powered (power at the reference effect ≈ x%)". It is never reported as evidence that the effect is absent.
2. If the realised number of informative weeks falls short of 13 or 14, the MDE at the realised W is reported.
3. **H-M2 is expected to fail.** Its holdout effect had the wrong sign (E5). A pass would be surprising, and would be reported as such.
4. **H-A cannot be informative in 2026.** Its reference effect is about a fifth of the MDE, so it is reported descriptively.

**Correction to the master plan.**
- *What the plan said:* about 45–50% power for M3b/M4 vs calibrated ESPN and about 35–40% for M4 vs M3b (03 W5, 01, 11).
- *Why it was optimistic:* that figure used only 2019's week-level variance, the least noisy injury season (σ_w ranges from 0.0147 in 2019 to 0.0249 in 2022), and a normal approximation.
- *The corrected figures* (pooled σ_w, t quantiles):
  - 25–35% for the injury families and 37–40% for H-B;
  - 14–21% if prospective noise is 1.5× historical, which is plausible because pre-inactive snapshots add zeros;
  - 55–77% for the injury and return families in the pooled 2026 + 2027 analysis.

### 2. Structural-zero weeks

- **Definition** (outcome-free): a week in which a challenger's official prediction equals its comparator's for every paired player-week (max |difference| < 1e-9).
- **2026 W5** is a structural-zero week for H-D and for both H-M4 comparisons:
  - every W5 run preceded every team's final injury report (E15);
  - this is verified at R1 from the archived predictions alone.
- **The primary keeps W5 as specified.** It contributes zero differences and counts toward the minimum-week rules, as those rules are written.
- Secondary S1 repeats each primary without structural-zero weeks and states the number of informative weeks.

### 3. Pre-registered secondary analyses

These are reported at R1. None can change a primary verdict.

- **S1. Without structural-zero weeks** (§2).
- **S2. MSE.** ΔMSE with the same pairing and week bootstrap, next to every ΔMAE. MSE is consistent for the mean, which is what sums of projections need (Gneiting 2011).
- **S3. By horizon.** Each comparison within two strata of official predictions:
  - *post-report:* both teams' final reports are in the run's injury capture, or the capture was made at most 26 h before kickoff (F0's definition, `post_report_coverage()`);
  - *early-week:* all other official predictions.

  The stratum is fixed before kickoff, so it is a pregame split. Descriptive.
- **S4. Decision relevance** (outcome-free). For each challenger vs its comparator, by week:
  - (a) the share of the comparator's top 36 that leaves the challenger's top 36;
  - (b) the share of within-top-36 pairs whose order flips;
  - (c) the share of player-weeks whose predictions differ by at least 0.5 points.

  Reported as weekly means with ranges. Computable at any time from predictions alone.
- **S5. Pooled fixed-sample 2026 + 2027** (the cross-season confirmatory secondary).
  - *Design:* the same hypotheses, models, population and `pooled_bootstrap()` (weeks resampled within season), on every 2026 and 2027 prospective week.
  - *Validity condition:* the frozen lineages must run unchanged through the 2027 regular season. The frozen-lineage runtime (R 4.5.1, renv snapshot 2026-10-01, `renv.lock` unchanged) stays pinned, and fingerprints stay identical.
  - *Insufficiency and timing:* fewer than 16 informative weeks in total is insufficient. Evaluated once, after the 2027 regular season.
  - *Expected power:* see §1.
- **S6. Anytime-valid sensitivity.** Computed once at R1. No interim computation (§5).
  - Each week w gives X_w = d̄_w / c_w, where c_w is the week's mean |ŷ_challenger − ŷ_comparator| over paired player-weeks. This is a predictable bound, since |Δ absolute error| ≤ |Δ prediction|.
  - Weeks with c_w = 0 (structural zeros) are skipped.
  - **E-process** for H₀: E[X_w | past] ≥ 0 (no improvement), written in base R (Choe & Ramdas 2024):
    - wealth K_w = Π_{v ≤ w} (1 − λ_v X_v), with K_0 = 1;
    - betting fraction λ_v = min(½, max(0, −μ̂/(σ̂² + μ̂²))), where μ̂ and σ̂² are the running mean and variance of earlier X;
    - priors μ̂ = 0 and σ̂² = ¼ before the first informative week (so λ = 0).

    Under H₀, K is a non-negative supermartingale, since X ∈ [−1, 1] and λ ∈ [0, ½]. Reported: K at season end and the first week with K ≥ 20 (α = 0.05), if any.
  - The season-end e-value may be multiplied by 2027's (Grünwald et al. 2024). It gives validity under monitoring, not extra power.
- **S7. Late-push sensitivity** (§4).
- **S8. Small-sample interval.** A t-interval on the linearised week contributions, with W − 1 degrees of freedom (`week_noise()`), reported next to every primary.
  - A primary that passes with the bootstrap but whose t-interval spans 0 is reported as "passed the pre-registered test; not robust to the small-sample correction".
  - The verdict stays the pre-registered one.

### 4. Late-push rule

- **Primary (unchanged):** the latest archived run with `predicted_at` before kickoff and a snapshot captured before kickoff, hash-verified against the manifest (`official_predictions()`).
- **Sensitivity S7:** additionally requires that a commit containing the run's manifest row reached origin before the game's kickoff.
- **Push times** are established at R1, in this order of preference:
  1. GitHub's record of pushes to the repository;
  2. the local pre-push log `data/ops/push_log.csv` (from 2026-10-13);
  3. the dispatcher's hourly record of the remote-tracking ref (`data/ops/upstream_log.csv`), which is an upper bound.

  Runs with no established push time are counted and excluded from S7 only.
- If S7 and the primary disagree, both are reported, and the primary stands.

### 5. No interim looks

- **No 2026 outcome is loaded by any evaluation routine before R1** (the end of the 2026 regular season). This covers `score_prospective()`, the F2 scoring tools, the F5 ledger join and the S0 archives. Two things are exempt:
  - the frozen procedure's training rows;
  - ESPN's after-the-fact final **projections**, which are forecasts, not outcomes (used by E17).
- **In-season monitoring of the frozen lineages is outcome-free:** run coverage, structural zeros, and S4.
- **"Blind e-process monitoring" in the master plan is implemented as S6 at R1.** An in-season look would turn 2026 outcomes into development data for later work, which the plan forbids.

**Influence on later choices.** No 2026 outcome was used. No frozen artefact changed.

---

## 2026-10-13 — E17: Forecast-horizon study, R3 (outcome-free pre-registration)

**Question.**
- How much extra uncertainty do earlier ESPN projections carry, compared with ESPN's final, late-horizon projection?
- How does that uncertainty vary by position, projection band, lead time and injury status?
- Are ESPN's revisions approximately a martingale?

**Why it is outcome-free.** It uses ESPN projections only:
- FFball's dated captures:
  - all positions: the valuation captures (`archive/valuation_espn_capture_manifest.csv`, every week through 18);
  - WR: the weekly snapshots.
- ESPN's after-the-fact final week-of projection for the same player-week. This is the same source as the historical ESPN data, and it is late-horizon (post-inactive).

No actual points are used, so the analysis may run in season without unsealing 2026 outcomes.

**Data.**
- **Unit:** (player, season, target week, capture). Captures from 2026 W5; from W6, F0's schedule adds two or more per week.
- **Values:** the early value v is the capture's projection for the target week; the final value f is ESPN's final projection, fetched once the week is complete.
- **Lead time:** current week, by hours from capture to the player's kickoff (< 24, 24–72, 72–120, > 120). Future weeks, by weeks ahead (1, 2, 3–4, 5–8, 9+).
- **Bands** of v, the same as P0: 0–3, 3–6, 6–9, 9–12, 12–15, 15–20, 20+.
- **Status at capture** (ESPN `injury_status`): ACTIVE; QUESTIONABLE; other (DOUBTFUL, OUT, DAY_TO_DAY, IR).
- **Active rows:** v > 0 and f > 0. Rows with v > 0 and f = 0 are availability transitions (most zero finals are inactives). They are reported separately, by status and lead bin, and belong to P(active | h), not to the spread term.

**Estimands** (active rows; 95% CIs by a player-cluster bootstrap, 2,000 resamples, seed 1):
1. **Revision drift** b = E[f − v], and **revision variance** V = Var(f − v), by position × lead bin, and by position × lead bin × band where the cell has at least 200 rows.
2. **Martingale check.** For player-weeks with at least two captures before the final, the correlation between successive revisions (v₂ − v₁) and (f − v₂), and the slope of (f − v₂) on (v₂ − v₁). A martingale implies both are 0.
3. **Transition shares:** P(f = 0 | v > 0) by status and lead bin. Descriptive; this feeds P1's early-horizon design.

**Adoption rules** (fixed now; applied mechanically at every refresh; outcome-free):
- **Spread term.** Applies to the early-horizon PODs of P0/P2, and to S0's inputs, which are early-week. In each position × current-week lead bin, F(y | active, base_h) is widened by an independent N(0, V̂) component if the CI of V̂ excludes 0. Otherwise no term is added. The band-level V̂ is used where its cell qualifies, and the pooled V̂ otherwise.
- **Mean drift.** If the CI of b̂ excludes 0 in a cell, the early-horizon base is shifted by b̂ before calibration. That is, E[f | v] = v + b̂, and the late-horizon calibration is then applied. The shift uses projections only. Otherwise no shift is made.
- **Martingale failure.** If the CI of the successive-revision correlation excludes 0, the result is recorded as a martingale failure. It informs X26 (the revision-dynamics model). No further correction is fitted on 2026 data.

**Timing.**
- First analysis once at least 4 weeks have both a capture more than 72 h before the week's first kickoff and final projections.
- Refreshed weekly. Each refresh is archived with its inputs' hashes.
- Final analysis at the end of the 2026 season. The frozen M-lineages are never touched.

**Interpretation.**
- V̂ ≈ 0: early-week tools need no extra spread, and the horizon matters only through availability.
- V̂ > 0 and growing with lead time: early-week PODs and S0 odds widen accordingly.
- Martingale failure: early projections are predictably revised, and X26 must model it.

**Influence on later choices.** No 2026 outcome is used.

---

## 2026-10-13 — E18: Baseline outcome distributions P0 (distribution stack; pre-registration, written before any computation)

**Question.** What is the distribution of a player's weekly points if he plays, given a calibrated ESPN base?
P0 is an assumption-light baseline. It feeds S0 (shadow odds), and P2 must beat it.

**Register.** Family `distribution_stack` (research/contamination_register.yml):
- 2019 is warm-up;
- **2020–2023 is development**;
- 2024 is the one batch check, which P0 does not use;
- 2025 is excluded;
- 2027 is confirmatory.

**Nothing is computed or viewed on 2024–2025 for this family.**

**Data.** `val_frame$current` (ESPN final week-of projections joined to GSIS ids, regular season):
- **Population:** QB/RB/WR/TE player-weeks with ESPN projection > 0, seasons 2019–2023.
- **Active:** at least one offensive snap (nflverse snap counts, `snaps`). A player-week with no snap record but a stat line also counts as active (id-mapping gaps).
  - Only active rows enter F(y | active).
  - The share of inactive rows among projected rows is reported by position (descriptive). It is the late-horizon P(active), and ESPN zeroes most inactives.
- **Outcome y:** league (ESPN PPR) points from nflverse stats; 0 for an active player with no stat line.

**Base (location).** A new rolling-origin, per-position linear calibration:
- base = a + b·ESPN, fit by least squares (MSE) on that position's active rows strictly before the target week;
- expanding window from 2019 week 1, refit every week;
- while a position has fewer than 200 training rows (early 2019), base = ESPN.

**Residual quantile table.**
- **Residuals:** r = y − base on active rows.
- **Bands of base:** [0,3), [3,6), [6,9), [9,12), [12,15), [15,20), [20,∞).
- **Levels:** τ ∈ {0.01, 0.05, 0.10, 0.20, 0.25, 0.30, 0.40, 0.50, 0.60, 0.70, 0.75, 0.80, 0.90, 0.95, 0.99}. The 0.25/0.75 pair makes the 50% interval exact.
- **Quantiles:** empirical, R type 7, per position × band.
- **Small cells:** a cell with fewer than 200 rows merges with its neighbouring lower band, repeated until n ≥ 200.
- **Predictive quantiles:** q_τ = max(base + r_τ, floor_pos), where floor_pos is the minimum active-row points of that position in the table's training rows.

**Horizon construction** (prospective use; 05 §2.1): POD_h = p_h·F(y | active, base_h) + (1 − p_h)·δ₀.
- **Location:** the base for prospective PODs is the valuation run's projection, the same mean V1, V2 and S0 use (for WRs, the frozen M4 prediction). The table is indexed by the band of that base. Development fits used P0's own calibration, so this mismatch is a stated limitation for P2 to test.
- **Availability:** p_h is the designation prior (`config/availability_prior.yml`) for designated players and 1 otherwise, until P1.
- **Spread:** the horizon spread term comes from R3 (E17) once its adoption rule fires. Until then none is added, and S0 states that its odds are too sharp.

**Development evaluation** (descriptive; out-of-sample within development):
- **Rolling by season:** each season s ∈ {2020, …, 2023} is scored with a table built from active rows of seasons 2019 … s − 1, using the rolling base.
- **Reported by position:**
  - mean CRPS from quantiles (`crps_quantiles()`);
  - the randomised PIT histogram (10 bins) and a uniformity statistic;
  - central 50/80/90% coverage with week-clustered bootstrap 95% CIs (weeks resampled within season, 2,000 resamples, seed 1);
  - the interval score.
- **Coverage gate (05 §6):** for each position × level (12 cells), the clustered CI must overlap [nominal − 3 pp, nominal + 3 pp], with Holm across the 12 cells.
- **Reference only:** a normal distribution around the same base, with SD = the training residual SD by position × band. Not a selection criterion.

**Production table and freeze.**
- **Fit:** the production table uses active rows of **2020–2023 only**. 2019 is used only as calibration warm-up.
- **Frozen file:** `models/probabilistic/pod_baseline_v0.yml`. It holds the τ grid, bands after merging, the quantile table, floors, cell counts, and the final 2023 per-position calibration coefficients (documentation only).
- **Re-derivation:** the pipeline re-derives the table and fails on any difference, plus a fingerprint hash.
- **P0 is frozen as the baseline whatever the gate says.** A gate failure is reported. S0 then states that its noise component failed the gate, and P2 must fix it.

**Prospective archive.** From the freeze, the PODs used by any downstream run are archived write-once, with a hash manifest (`archive/distribution_manifest.csv`).

**Interpretation.**
- Passing the gate: a usable calibrated baseline.
- Failing cells: where spread depends on more than base level and position (status, TD share, game script). These are the covariates P2 (X4) tests.

**Influence on later choices.** No 2024–2026 outcome is used. The development results cannot change the bands, τ grid or method fixed here.

### E18 Result (development 2020–2023, out of sample by season; computed after the entry above was committed in e2db81e)

**Frame.** 31,225 projected player-weeks for 2019–2023, of which 29,197 were active. Active share among projected rows,
2020–2023 (the late-horizon P(active)):

| Position | Active share | Comment |
|---|---|---|
| QB | 0.75 | Backup QBs carry small ESPN projections and rarely take a snap; 25% of QB rows have no snap record |
| RB | 0.95 | |
| TE | 0.98 | |
| WR | 0.98 | |

**Coverage gate (05 §6): PASSED in all 12 cells.** Empirical coverage, with week-clustered 95% CI:

| Position | 50% | 80% | 90% |
|---|---|---|---|
| QB | 0.512 [0.490, 0.535] | 0.800 [0.785, 0.815] | 0.898 [0.886, 0.909] |
| RB | 0.491 [0.477, 0.503] | 0.797 [0.787, 0.807] | 0.898 [0.891, 0.905] |
| WR | 0.501 [0.492, 0.509] | 0.806 [0.798, 0.815] | 0.902 [0.896, 0.908] |
| TE | 0.504 [0.489, 0.517] | 0.813 [0.802, 0.823] | 0.902 [0.894, 0.910] |

Holm-adjusted p = 1 in every cell: no cell's interval excludes the ±3 pp band.

**Scores and calibration by position:**

| Position | n | CRPS | Normal reference CRPS | Difference | 80% interval score | PIT uniformity χ² (9 df) |
|---|---|---|---|---|---|---|
| QB | 2,383 | 3.97 | 4.02 | −1.2% | 25.5 | 10.5 (p 0.31) |
| RB | 6,140 | 2.92 | 3.03 | −3.5% | 18.8 | 8.0 (p 0.53) |
| WR | 9,701 | 3.09 | 3.21 | −3.7% | 19.8 | 5.5 (p 0.79) |
| TE | 5,267 | 2.26 | 2.35 | −3.9% | 15.0 | **26.1 (p 0.002)** |

- The empirical quantiles beat a normal distribution with the same base and spread by 1–4% CRPS: they capture skew.
- **TE's PIT departs from uniformity** even though its coverage passes. The top decile holds 8.8% of outcomes and the 9th holds 11.0%: the extreme upper quantile is slightly too wide. This is a target for P2 (spread covariates, X4).

**Frozen production table.**
- File: `models/probabilistic/pod_baseline_v0.yml`, 21 cells. Merges: QB 0–12; RB, WR and TE top bands into 15+, 15+ and 12+.
- Floors: QB −5.74, RB −2, WR −4, TE −0.7.
- The pipeline re-derivation passes (target `pd_table_check`). Fingerprint `905e3ca0e663a0c0bfd8b5424bf48859bbbb03f1ae05d7bacf270b3b6877e80b`.

**Prospective archive** started 2026-10-13: W6, 326 PODs from valuation run 20261013T070931Z
(`archive/distribution_manifest.csv`). From now on the dispatcher archives the PODs after every capture.

**Reading.** P0 is a calibrated baseline at the late horizon for active players. It is suitable as S0's weekly-noise
component and as the bar P2 must beat. Its known gaps:
- no horizon spread term, until R3;
- availability from a published prior, until P1;
- TE upper-tail shape;
- the prospective base is the valuation projection rather than P0's own calibration.

---

## 2026-10-13 — E17a: Amendment to E17's readiness condition (written before any R3 computation)

**Defect.** E17 says the first analysis waits until at least 4 weeks have "a capture more than 72 h before the
week's first kickoff". The earliest scheduled capture is the early-week run on Tuesday. A week opens on Thursday
night, 59–65 h later. As written, the condition cannot be met in normal weeks, so the adoption rules could
never fire.

**Amendment.** Lead time is measured to each player's own kickoff, as E17 already defines it. Two changes:
1. **Readiness is per cell.** A position × lead-bin cell is analysed, and its adoption rules applied, once it holds active rows from **at least 4 distinct target weeks**. The early bins (72–120 h, > 120 h) fill from Tuesday–Wednesday captures of Sunday and Monday games.
2. **Current week and future weeks.** The current week is the target week equal to the capture's own week (from its archive path); future weeks are 1, 2, 3–4, 5–8 and 9+ weeks ahead.

Everything else in E17 is unchanged: estimands, active-row definition, bootstrap, adoption rules, timing.
No R3 quantity had been computed when this was written.

---

## 2026-10-13 — E19: Injury stack, P1 availability v2 (X5) and R2 RB/TE/QB designation rules (X14); one batch check on 2019 (pre-registration, written before any computation)

**Family.** `injury_stack` in the contamination register:
- development 2020–2023;
- training 2017–2018 (extra training rows, no selection);
- **one check on 2019** (P1 and R2 together, Holm across both primaries);
- confirmatory 2027;
- 2024 and 2025 excluded.

WR results are reported separately (contaminated by M3/M4). Every routine calls `assert_family_seasons()`, and
the 2019 check is recorded under `spent_checks` when it runs.

### P1 (X5): P(active) at the post-report horizon

- **Unit:** player-week at QB/RB/WR/TE, regular season, with a team game.
- **Outcome:** active, meaning ≥ 1 offensive snap; where no snap record exists, a stat line counts (as in F4 and P0).
- **Population (primary): the report population.** Every player on his team's final, pregame-valid injury report that week (`pregame_injury_detail()`; designation Out, Doubtful, Questionable, or listed without one). No ESPN input, so there is no post-inactive selection.
- **Secondary population:** unlisted players with ≥ 1 offensive snap in the team's previous game of the season (week 1 excluded). This gives the base rate and is reported separately.
- **Features** (pregame-valid, from `add_availability_features()` and the schedule):
  - designation, final practice status, position;
  - returning: no offensive snap in the team's previous game;
  - consecutive weeks listed (capped at 4);
  - previous designation;
  - kickoff day (Thursday / Sunday / Monday / other, Eastern time);
  - team-season.
- **Baseline R0:** a rate table by designation × practice × position. A cell with fewer than 30 training rows falls back to designation × practice (all positions), then to designation.
- **Candidate G1:** logistic GLMM in mgcv:
  `active ~ designation * practice + position + returning + streak + prev_designation + kickoff_day + s(team_season, bs = "re")`.
  - The `re` smooth gives the shrunk team-reporting effect; lme4 and glmmTMB are not in the lockfile (decision X-018).
  - An unseen team-season predicts with its random effect at 0.
  - G1 is the only candidate.
- **Development evaluation** (descriptive, rolling origin by season): for s in 2020–2023, fit on 2017–2018 plus the development seasons before s, then score s. Report Brier, log loss, calibration slope and CORP reliability, by position.
- **Check model.** G1 and R0 are fit on 2017–2018 plus 2020–2023, frozen, and scored once on 2019.
- **Primary H5.** On the 2019 report population, RB/TE/QB pooled: Brier skill of G1 over R0, 1 − Brier(G1)/Brier(R0).
  - Inference: week-clustered bootstrap, 2,000 replicates over 2019's weeks.
  - One-sided p-value: (1 + #{replicates ≤ 0}) / (1 + 2,000).
- **Slope rule (also required).** The 2019 calibration slope of G1 must have a bootstrap 95% CI that includes 1 and a point estimate in [0.8, 1.2]. The slope comes from logistic regression of the outcome on logit(p).
- **Secondary** (reported, never used to select):
  - log-loss skill; reliability by position;
  - WR (contaminated);
  - the unlisted population;
  - **COVID sensitivity:** development refit and evaluation without 2020–2021 rows.
- **Interpretation.**
  - **Pass:** G1 becomes the `p_active` provider for PODs, S0 and D0, replacing the published fixed prior.
  - **Fail:** R0, the rate table, is the honest model and becomes the provider.

**Early horizon** (outcome-free construction, not a test target):
P(active | early) = Σ_d P(final designation = d | midweek status) × P(active | d).
- The transition matrix comes from FFball's dated 2026 injury captures: designations only, no game outcomes.
- P(active | d) comes from the frozen post-report model.
- It is built once enough weeks of captures exist.

### R2 (X14): designation and practice adjustments to calibrated ESPN, RB/TE/QB (template M4)

- **Rows:** F4 `player_week_all`, RB/TE/QB, with an ESPN projection > 0. This is the late-horizon evaluation population; historical ESPN values are post-inactive. The base is F4's rolling-origin calibrated ESPN.
- **Injury groups:** M4's `injury_group()`. Adjustable: Q_DNP, Q_LP, Q_FP, Q_other, D, listed_DNP_LP. Every other row keeps the base.
- **Candidates.** Position-specific parameters for RB, TE and QB, derived from development rows (2020–2023) only, rounded to 2 decimals:
  - **B0:** base (baseline).
  - **B1:** one multiplier per position on Questionable and Doubtful rows: half of (Σ points / Σ base − 1).
  - **K1:** M4 K1. Halved group ratios; groups with fewer than 100 development rows pool into Q_pool.
  - **K2:** M4 K2. A logistic P(active | practice, Doubtful, returning, streak), times the group's ratio of points to base when active.
    - "Active" here is the F4 definition (≥ 1 offensive snap). M4 used game-day status or a stat line.
    - As in M4, the ratio is not halved.
- **Development:** pooled RB/TE/QB ΔMSE against B0 over 2020–2023, with week-clustered, season-blocked bootstrap 95% CIs. In sample for the parameters; halving guards against the winner's curse, as in M4.
- **Selection** (fixed now):
  1. A candidate qualifies if its development pooled ΔMSE CI lies below 0.
  2. Among qualifiers, take the lowest development MSE, unless a simpler qualifier (B1 < K1 < K2) is within the tie band of 0.5% of B0's MSE; then the simpler one wins.
  3. If none qualifies, R2 has no 2019 primary; the result is "ESPN already prices the effect"; Holm runs over H5 alone.
- **Primary H14.** The selected candidate's pooled RB/TE/QB ΔMSE against B0 on 2019, weeks 5–17. Weeks 1–4 are excluded as calibration warm-up, because QB/RB/TE ESPN history starts in 2019.
  - Inference: week-clustered bootstrap, 2,000 replicates.
  - One-sided p-value for ΔMSE < 0.
- **Reported (not primary):** every candidate's 2019 ΔMSE and ΔMAE, by position.
- **MDE.** Computed on development data **before** the check, in the parameter addendum E19b: the 2019 MDE on MSE for the selected candidate, from σ_w of the week-level pooled ΔMSE.

### Batch

- **Holm** at familywise α = 0.05 across the primaries present (H5, H14). The smaller p-value is tested at 0.025, then the other at 0.05.
- **Success.**
  - X5: H5 rejected under Holm **and** the slope rule holds.
  - X14: development qualification **and** H14 rejected under Holm.
- **Order.**
  1. This entry is committed.
  2. Development results, R2 parameters and the MDE go in E19b, committed **before** the 2019 check.
  3. The check runs once; its target is gated on E19b existing.
  4. Results go in E19c, with `spent_checks` updated.
- **Frozen artefacts.**
  - A passing R2 candidate becomes a new lineage, `m6_*` (registry, fingerprints, prospective from freeze).
  - The P1 provider is frozen with a content fingerprint.
  - Nothing from M1–M4 changes.

---

## 2026-10-13 — E20: P2 calibrated outcome distributions v1 (distribution stack; pre-registration, written before any P2 computation)

**Family.** `distribution_stack`:
- development 2020–2023; warm-up 2019;
- **one batch check on 2024**: E22, pre-registered separately after development, covering P2 and P4, and P3 if gated in;
- confirmatory 2027; 2025 excluded; 2026 sealed.

Nothing is computed or viewed on 2024–2025 for this family before E22.

**Target.** F(y | active, base, x) at the **late horizon**: the league points of F4 rows that are ESPN-projected
(projection > 0) and active (≥ 1 offensive snap), at QB/RB/WR/TE. The base is F4's rolling-origin calibrated ESPN.

**Scoring grid.**
- Every candidate produces quantiles at τ = 0.01, 0.02, …, 0.99 (99 levels).
- CRPS: `crps_quantiles()` on that grid (trapezoid rule, tails held at the end quantiles).
- Coverage: the central 50/80/90% intervals from the grid.
- PIT: randomised, from the grid CDF.

**Development protocol.** Out of sample by season, as in E18: for s = 2020…2023, every candidate is fit on seasons
2019…s−1 and scored on s. Pooled development metrics are over all four positions; position results are reported too.

**Candidates** (three plus the baseline):

| id | Method |
|---|---|
| **C0** (baseline; P0's procedure) | Empirical quantiles of (y − base) by position × P0 band, with P0's merging rule (cells ≥ 200) and position floors, on the 99-level grid |
| **C1** (IDR benchmark) | Per position, isotonic distributional regression of y on base [Henzi et al. 2021]. P(y ≤ z) is antitonic in base, fitted by PAVA (`stats::isoreg`) at 199 thresholds: the training quantiles of y at 0.005, 0.010, …, 0.995. Predictions at a new base interpolate linearly between neighbouring training bases, held constant outside their range. Quantiles come from inverting the CDF, linear between thresholds. |
| **C2** (EMOS-style) | Per position, `mgcv::gam(list(y ~ s(base, k = 10), ~ s(base, k = 10) + status + td_share + implied_total + spread + vol_shrunk, ~ 1, ~ 1), family = mgcv::shash(), method = "REML")`, with quantiles from the family's quantile function, floored at the position floor. Location is smooth in base; log-scale is smooth in base plus the closed covariate list; skewness and kurtosis are constant per position. |
| **C3** (adaptive conformal) | The better of C0 and C2 by development CRPS (decided before C3 is scored), plus per-position adaptive level tracking [Gibbs & Candès 2021]. For each τ, the week-t level is τ + δ, clipped to [0.005, 0.995]. After each week, δ ← δ + 0.01 × (τ − ĉ), where ĉ is the share of that week's rows with y ≤ q_τ. δ resets to 0 at each season's start. |

**Closed covariate list for C2** (05 §4.3), all pregame-valid at the late horizon:
- base;
- **status:** not listed / listed without a designation / Questionable or Doubtful (F4's timed report features);
- **td_share:** the share of ESPN's projected points that comes from touchdowns, (6 × (receiving TDs + rushing TDs) + 4 × passing TDs) / projection, clipped to [0, 1];
- **implied_total** and **spread:** the schedule's closing values, valid at kickoff. The as-of lines are reserved for earlier horizons (R5).
- **vol_shrunk:** the player's residual SD over his earlier projected active weeks (all earlier seasons in the frame, plus earlier weeks of the season), shrunk toward the position's training residual SD: sqrt((n·sd_player² + 8·sd_position²)/(n + 8)).

**Selection** (fixed now):
1. The lowest pooled development CRPS wins.
2. **Coverage gate** (05 §6), on development: in each position × level cell (50/80/90%), the week-clustered 95% CI of coverage must overlap [nominal − 3 pp, nominal + 3 pp], with Holm across the 12 cells. A candidate that fails is not selected.
3. A CRPS difference below 0.5% of the best is a tie; the simpler candidate wins (C0 < C1 < C2 < C3).

**Development inference** (reported, not a test): paired week-clustered, season-blocked bootstrap (2,000 replicates)
of ΔCRPS against C0 and against C1. Also reported: PIT histograms, MCB/DSC/UNC via the CORP decomposition of
threshold Brier scores, and threshold-weighted CRPS above 20 points, by position and band.

**Then E22** (2024, one batch): the selected candidate's ΔCRPS against C0 must have a CI below 0, it must be no worse
than C1, and it must pass the coverage gate.

**POD assembly and freezing.**
- POD_h = p_active(h) × F(y | active, base_h, x) + (1 − p_active(h)) × δ₀, with p_active from P1's provider (E19 outcome). The R3 horizon spread term enters once R3 adopts it.
- The selected candidate is frozen as `models/probabilistic/pod_v1.yml` with a fingerprint, and archived prospectively like P0.

---

## 2026-10-13 — E21: P3 dependence, gate test (pre-registration, written before any lineup-total computation)

**Question** (master plan P3's gate). On development seasons, does independence across players mis-calibrate
**lineup totals**? P3 (team and game factors) is built only if it does. Otherwise the null is recorded and P5
uses independence.

**Lineups.** Realistic legal lineups, not random ones: every regular-season starting lineup of arm A in the F6
development replays (2020–2023; LAB1, LAB1a, LAB1b), all teams. These carry same-team pairs at realistic rates.

**Player distributions** (out of sample by season s, refit on 2019…s−1):
- the E20-selected P2 candidate's F(y | active, base, x), applied to every starter of season s, including starters who turned out inactive;
- P(active), from the position × P0-band development active share (LAB1a's table);
- each starter's predictive distribution: p_active · F + (1 − p_active) · δ₀;
- a starter without a week-t ESPN row contributes 0.

**Independence prediction.** Lineup totals are simulated with 2,000 independent draws per lineup (inverse CDF on the
99-level grid, tails held at the end quantiles), with a fixed seed per season.

**Gate statistics** (pooled over 2020–2023):
- the randomised PIT of each realised lineup total;
- coverage of the 50/80/90% central intervals;
- the coverage gate of 05 §6 over the three levels: week-clustered, season-blocked 95% CI; a cell fails when the Holm-adjusted test (across the 3 cells) rejects overlap with nominal ± 3 pp.

**Decision rule.**
- **Gate fails** (independence mis-calibrates lineup totals): build P3 with its four candidates (independence; team factor; team and game factors; shrunk role-pair matrix), to be batch-checked with P2 on 2024.
- **Gate passes:** record the null; P5 uses independence.

**Descriptive** (no decision use):
- the variance ratio Var(realised − simulated mean) / mean simulated variance;
- coverage for lineups with at least one same-team QB–pass-catcher pair versus without;
- the same by league size.

---

## 2026-10-13 — E19b: injury stack development results, fixed R2 parameters and MDE (written before the 2019 check)

All numbers come from development seasons 2020–2023 (training 2017–2018), out of sample by season. 2019 has not been built or viewed.

**P1 (X5), report population, RB/TE/QB pooled** (n = 3,835; observed active 0.628).

| | R0 rate table | G1 GLMM |
|---|---|---|
| Brier | 0.1155 | 0.1019 |
| Log loss | 0.368 | 0.323 |

- **Brier skill 0.118**, season-blocked week-clustered 95% CI [0.084, 0.151].
- G1's pooled calibration slope is 0.86.
- **By season:** skill 0.177 (2020), 0.034 (2021), 0.120 (2022), 0.130 (2023).
- **By position:** QB 0.25, RB 0.07, TE 0.08; WR 0.06 (contaminated, reported only).
- **COVID sensitivity** (2020–2021 excluded): skill 0.121, slope 0.85.
- **Unlisted base rates** (players with a snap in the previous game): QB 0.81–0.86, RB 0.89–0.94, WR 0.90–0.94, TE 0.92–0.97.
- **Fit notes.**
  - mgcv reports "step failure" in the smoothing-parameter search for some folds. The fits converged and the scores above come from them.
  - Two designation × practice cells are empty (rank deficiency 2). Their coefficients are 0 by mgcv's identifiability constraints.
  - Prediction keeps the team-season effect at 0, as E19 fixed.

**R2 (X14), development pooled RB/TE/QB** (14,970 rows; B0 MSE 30.68). ΔMSE against B0, week-clustered season-blocked CIs:

| | ΔMSE | 95% CI | ΔMAE | Qualifies |
|---|---|---|---|---|
| B1 | −0.067 | [−0.104, −0.032] | −0.0069 | yes |
| K1 | −0.054 | [−0.097, −0.013] | −0.0056 | yes |
| K2 | −0.013 | [−0.126, +0.100] | −0.0101 | no |

**Selection (E19's rule): B1** (lowest development MSE among the qualifiers, and the simplest).
- Questionable/Doubtful multipliers: RB −0.04, TE −0.11, QB −0.10, i.e. ×0.96, ×0.89, ×0.90.
- Every group of the three positions pools into Q_pool except RB/TE Q_LP and listed_DNP_LP. The QB rows are small: 74 Q/D in development.

**Fixed parameters:** `research/m6_candidate_params.yml` (sha256 `bc89ca47abac598b18b49b593a77ebd7b95d07b67d8ebf02db4f7dd23828841a`).
It is checked against a fresh derivation by the target `m6_params_check`.

**MDE for H14 on 2019** (weeks 5–17; 13 weeks): σ_w of the week-level pooled ΔMSE = 0.165, so MDE = 0.128 at one-sided
α = 0.025 and power 0.8. The development effect (−0.067) is about half the MDE. **H14 is underpowered**, and a null in
2019 would be uninformative about R2. This is stated now so a null cannot be read as evidence of no effect.

**Next:** `e19_check` runs once, then E19c, and `spent_checks` is updated.

---

## 2026-10-13 — E19c: injury stack, one-time 2019 batch check (P1 X5, R2 X14); decision

Run once (`e19_check`, 4.2 min), after E19b and the parameter file were committed (0ad9e9b). The parameter file
matched a fresh development derivation (`m6_params_check`). 2019 is now spent for the injury stack.

**H5, P1** (report population, RB/TE/QB pooled; n = 906; observed active 0.600).
- Brier: R0 0.0830, G1 0.0699. **Skill 0.158**, CI [0.079, 0.228].
- One-sided p = 0.0005; **Holm-adjusted p = 0.001: H5 is rejected.**
- Log loss: R0 0.271, G1 0.232.
- **Slope rule fails.** G1's slope is **1.246**, CI [1.042, 1.548]: the CI excludes 1 and the point estimate is above 1.2. G1 was *under*-confident in 2019 after being slightly over-confident in development (0.86).
- **X5 success = FALSE** (E19 requires both).

**H14, R2** (B1; 2019 weeks 5–17; n = 2,953).
- ΔMSE = **+0.029**, CI [−0.066, +0.140]; one-sided p = 0.685; Holm-adjusted 0.685. **Not rejected.**
- **X14 success = FALSE.** As stated in E19b, H14 was underpowered (MDE 0.128): the null is uninformative, not evidence of no effect.

**Secondary** (no decision use).
- **P1 by position (G1 skill):** RB 0.171, TE 0.001, QB 0.308. WR 0.106 (contaminated).
- **Unlisted base rates 2019:** QB 0.85, RB 0.94, WR 0.93, TE 0.95.
- **R2, 2019 ΔMSE by position:**

  | | QB | RB | TE |
  |---|---|---|---|
  | B1 | +0.22 | −0.05 | −0.03 |
  | K1 | +0.34 | −0.06 | −0.05 |
  | K2 | +1.23 | −0.11 | −0.10 |

  For RB and TE the signs agree with development. QB, the smallest group, goes the other way.

**Decisions (E19's interpretation rules, applied as written).**
1. **P1 provider = R0**, the designation × practice × position rate table, fit on 2017–2018 and 2020–2023. G1's better Brier does not override the failed slope rule. R0 replaces the published fixed prior (Q 0.71, D 0.07) as the post-report `p_active` provider. It is frozen as `models/probabilistic/p1_availability_v2.yml` with a fingerprint and a pipeline re-derivation check. The live tools (D0, S0) switch to it behind a new function, with the prior kept as the documented fallback.
2. **R2: no m6 lineage is frozen.** ESPN's late-horizon RB/TE/QB projections are not shown to under-price designations in 2019. The RB/TE development signal (small, consistent in sign) is a candidate for the 2027 prospective record only if re-registered.
3. **A future G1:** a recalibrated G1, e.g. logistic recalibration of its linear predictor fit on development, would be a new family member. It could not use 2019 again; its evidence would be prospective (2027).

`research/contamination_register.yml`: `spent_checks` gains injury_stack 2019 (E19c).

---

## 2026-10-14 — E20a: C2 fitting repair (development only; written after C2's development failure, before any 2024 computation)

**What happened.** As specified, C2 is `gam(list(y ~ s(base), ~ s(base) + covariates, ~1, ~1), family = shash())`.
Its development CRPS was 12.37, against 2.97 for C0. QB was fine (3.99); RB, WR and TE were not (6.2–19.4).

The diagnosis (TE, fit on 2019–2021 and scored on 2022) points to a **degenerate optimum**, not a code error:
- The location predictor stays near 0 for most rows and ignores the base.
- δ = exp(−1.43) gives very heavy tails, with strong skew (ε = 0.93).
- The mean 10–90% width is 277 points.

The quantile code matches mgcv's own `qf` (unit test).

**Repair.**
- Fit the same shash model to the residual r = y − base: `list(r ~ s(base, k = 10), ~ s(base, k = 10) + covariates, ~ 1, ~ 1)`.
- Quantiles of y are base + quantiles of r, floored at the position floor.
- The model space is unchanged: a smooth function of base absorbs the linear base term. Only the optimiser's starting region changes, since the residual location is near 0 by construction.

**Rules.**
- **One attempt.** C2 and C3 (whose base may change) are re-run on development; C0 and C1 are unchanged.
- E20's selection rule (CRPS, coverage gate, 0.5% tie band) applies unchanged to the new results.
- If the repaired C2 still fails the gate or loses, the selection stays as the rule gives it. No further variants.

**Record.** The first development results, with C0 selected, are kept here. They appear in E20's result entry beside the repaired run.

---

## 2026-10-14 — E20 result: P2 development (with E20a) — C0 selected; no calibrated candidate beats P0

Development 2020–2023, out of sample by season (fit on 2019…s−1); 23,491 active projected rows; 99-level grid.

| Candidate | CRPS | ΔCRPS vs C0 [95% CI] | Coverage 50/80/90 | Gate (12 cells, Holm) |
|---|---|---|---|---|
| C0 (P0's procedure) | 2.9706 | — | 0.500 / 0.805 / 0.900 | **passes** |
| C1 (IDR) | 2.9614 | −0.0092 [−0.0130, −0.0051] (−0.31%) | 0.572 / 0.845 / 0.922 | **fails** (5 cells; intervals too wide) |
| C2 (shash EMOS), first run | 12.37 | +9.40 | 0.472 / 0.641 / 0.729 | fails (7 cells) |
| C2 after E20a (residual fit) | 12.39 | +9.42 | 0.476 / 0.644 / 0.728 | fails (7 cells) |
| C3 (C0 + adaptive conformal) | 2.9703 | −0.0002 [−0.0005, +0.00003] | 0.500 / 0.805 / 0.901 | passes |

**Selection (E20's rule).** The candidates passing the gate are C0 and C3. C3's advantage is 0.01%, inside the 0.5% tie
band, so the simpler candidate wins: **C0**.

**C2.** QB fits well (CRPS 3.99, as good as C0). RB, WR and TE converge to degenerate shash optima, with the log-scale
predictor ranging from −17 to +2. E20a's residual parameterisation did not change that, so the one-attempt rule closes
C2.

**Interpretations** (X3, X4):
- **X3:** "C0 or C1 wins: spread is mainly a function of level, so keep the simple model." IDR is slightly sharper but over-covers its central intervals out of sample.
- **X4** (which covariates predict spread) is **inconclusive**: the only candidate carrying the covariates failed to fit.

**Outcome.** P2 v1 adds no new distribution. **The frozen P0 table (`pod_baseline_v0`) stays the production
F(y | active, base).** P2 has no primary in E22. A future P2 v2, such as a different family or a fitting strategy for
C2's covariates, needs its own pre-registration. It could still be checked on 2024 (see E22 below).

---

## 2026-10-14 — E21 result: P3 gate — independence is adequate; P3 not built

There are 11,052 regular-season lineups (F6 arm A, 2020–2023). Player PODs came out of sample from the E20-selected
candidate (C0) with position × band P(active); 2,000 independent draws per lineup.

| Interval | Coverage | 95% CI | Holm p |
|---|---|---|---|
| 50% | 0.498 | [0.485, 0.512] | 1 |
| 80% | 0.794 | [0.780, 0.807] | 1 |
| 90% | 0.892 | [0.881, 0.902] | 1 |

- **The gate passes**, so **P3 is not built** and the null is recorded. P5 uses independence.
- **Descriptive:**
  - variance ratio 1.04; PIT deciles 0.09–0.11;
  - lineups with a same-team QB–pass-catcher stack: 80% coverage 0.782, variance ratio 1.11. Without one: 0.797, ratio 1.02. A small stack effect, inside the gate;
  - by league size: 80% coverage 0.785 / 0.795 / 0.799 at 8 / 10 / 12 teams.

---

## 2026-10-14 — E22: distribution-stack batch check on 2024 — NOT RUN (no development winner)

E20, E21 and VL4 planned one batch check on 2024 for the stack members that reached it. After development:
- **P2:** C0 (= P0) is selected, so P2 has no primary.
- **P3:** not built (its gate passed).
- **P4:** worse than its VE1-normal baseline even in sample (VL4 result).

The batch would only re-confirm development failures, and it would **spend 2024** for the whole family.

**Decision:** the 2024 batch is not run now. 2024 stays unspent for the distribution stack. A future pre-registered
P2 v2 or P4 v2 can use it once it wins in development.

This decision uses no 2024 data and does not change any criterion in favour of a result. It declines to test candidates
that development already rejected. `spent_checks` is unchanged. The frozen P0 table remains in production. Its
prospective record continues (2026 archive, 2027 confirmatory).

## 2026-10-14 — E23: X22, K and D/ST distributions for lineup totals (distribution stack, P0/S0; pre-registration, written before any K/D-ST distribution or lineup-total computation)

**Question (X22).** Are v0 K and D/ST distributions adequate for team-total variance? The live simulators (S0, S1,
D2–D5) leave K and D/ST out and say so. 05 §4.6 asks for v0 position-level distributions, upgraded to
matchup-conditioned ones **only if lineup-total calibration fails**.

**Family.** `distribution_stack`: development 2020–2023, warm-up 2019. No 2024 batch. E22 is not run (X-020), and a
pass needs no batch (as in E21).

**Lineups and skill draws.** E21's, unchanged:
- F6 arm-A development replays, all teams, regular season;
- C0 refit on 2019 … s − 1;
- position × band P(active);
- 2,000 independent draws per lineup.

**K and D/ST units.** The lab has none, so each team-week is given one K unit and one D/ST unit.
- Two NFL teams are drawn uniformly among the teams playing that week, seeded by season, league, team and week.
- Realised points: F4 part 2's tables under the league's scoring (the team's kicker points in the game; the team's
  D/ST points).
- This is a construction; real managers choose their K and D/ST.

**Distributions** (for season s, fit on all team-games of 2019 … s − 1):
- **v0:** per unit, the empirical quantiles of points on E21's τ grid (position-level, independent of the matchup).
- **Conditioned:** per unit, empirical quantiles within tertiles of the as-of implied total (F4's kickoff − 2 h
  lines). K uses the team's own implied total; D/ST uses the opponent's. Tertile edges come from the training seasons.
- K and D/ST draws are independent of each other and of the skill draws.

**Gate (E21's, applied to the lineup total of skill + K + D/ST):** central 50/80/90% interval coverage, week-clustered
season-blocked bootstrap. A level fails if its coverage lies outside nominal ± 0.03 with a Holm-adjusted p < 0.05.

**Decision.**
- **v0 passes:** v0 is adequate. A later VL3 addendum may add v0 draws to S0's team totals, and nothing else is built.
- **v0 fails, conditioned passes:** S0 may adopt the conditioned distributions (VL3 addendum).
- **Both fail:** K and D/ST stay outside the simulators, with the limitation stated.

**Reported either way:** coverage, variance ratio and PIT histogram, with and without K/D-ST; results by league size.
No 2024 or 2025 K/D-ST row is read: the K/D-ST tables cover 2019–2025, and the code restricts them through the
register.

### E23a (2026-10-14, amendment before any K/D-ST distribution or lineup total was computed)

E23's conditioned variant named F4's as-of implied totals (kickoff − 2 h). A schema check, with no values or results
viewed, shows those lines exist only from 2021. E20 also reserves them for earlier horizons (R5) and uses the
schedule's **closing** lines at the late horizon.

**Amended.** The conditioned variant uses `team_games$implied_team_total`: the closing total and spread, valid at
kickoff, as in E20's C2. It exists for every season. K uses the team's own value; D/ST uses the opponent's. A missing
line takes the training median. Nothing else in E23 changes.

### E23 result: X22 — v0 K and D/ST distributions pass E21's gate (2026-10-14; run in the previous session, written up from the stored target `x22_result`)

Lineup total = skill + K + D/ST; 11,052 team-weeks, development 2020–2023.

| Variant | 50% coverage | 80% | 90% | Variance ratio | Fails |
|---|---|---|---|---|---|
| Without K/D-ST units ("none") | 0.498 | 0.794 | 0.891 | 1.04 | no |
| **v0** | 0.505 | 0.799 | 0.898 | 1.01 | no |
| Conditioned (closing implied totals) | 0.502 | 0.800 | 0.895 | 1.02 | no |

- 80% coverage by league size (v0): 8 teams 0.792, 10 teams 0.802, 12 teams 0.802.
- PIT histograms are flat; every decile is between 0.086 and 0.105.
- **Decision (E23's rule):** v0 passes, so v0 is adequate.
  - A later VL3 addendum may add v0 K/D-ST draws to S0's team totals.
  - Nothing else is built; the conditioned variant is not adopted.
