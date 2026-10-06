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
