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
