# Models, lineages and evaluation protocol

## Frozen lineages

Every model that can enter a comparison is **frozen** in a registry file. Code
rebuilds its spec from that file, never from shared constants, so later work cannot
silently change it. Each registry records:
- the features and model type;
- the hyperparameters;
- the data window and population;
- the training procedure;
- the selection rationale;
- the commit and timestamp;
- package versions.

A committed **prediction fingerprint** (a hash of the frozen models' predictions on
a fixed historical span) is re-checked by the pipeline. It fails loudly if the
frozen predictions change on the same data version. It reports "unverifiable"
rather than passing if the inputs themselves changed.

| Lineage | File | Models | Frozen | Fingerprint |
|---|---|---|---|---|
| M1 | models/registry/m1.yml | `m1_espn_raw`, `m1_espn_recal`, `m1_espn_plus`, `m1_no_espn`, `m1_naive` | commit 9663ca7 | rolling 2024–2025 |
| M2 | models/registry/m2.yml | `m2_espn_cal`, `m2_no_espn`, `m2_espn_aug` | 2026-10-05T22:42Z (parent 9f36579) | rolling holdout 2024–2025 |
| M3 | models/registry/m3.yml | `m3_role_adjust_v1`, `m3_role_adjust_q20_v1`, `m3_return_adjust_v1`, `m3_combined_v1` | 2026-10-06T00:24Z (parent 7573bdf) | rolling 2024–2025 |
| M3b | models/registry/m3b.yml | `m3_questionable_adjust_v1`, `m3_questionable_add_v1`, `m3_combined_abd_v1` | 2026-10-06T00:41Z (parent 9401ed0) | rolling 2024 |
| M4 | models/registry/m4.yml | `m4_two_stage_v1` (primary), `m4_practice_rule_v1` | 2026-10-06T06:26Z (parent e4556f7) | rolling 2019 + 2024 |

**M3 and M3b are rule challengers.** Each is calibrated ESPN, refit weekly by the
same procedure as `m2_espn_cal`, plus **fixed, pre-registered adjustments** with
no learned parameters:

| Hypothesis | Rule |
|---|---|
| A, role change | `xfp_trend` ≥ 1.42 → −0.30; ≤ −1.65 → +0.25 |
| B, return from absence | 1 team game missed → −0.2; 2+ → −0.4 |
| D, Questionable designation | × (1 − 0.09), using an injury report that existed before kickoff |

The derivations are in experiment log E6 and E9. One-time historical checks are in
E7 and E10, and they cannot alter the rules.

**M4 availability challengers** (E12–E14) are calibrated ESPN multiplied by a fixed
availability multiplier. They use the pregame-valid final injury report (designation
and final practice status) and lagged report history. The groups and parameters are
in research/m4_candidate_params.yml:
- They were derived from 2020–2023 only and committed (39b8059) before the 2019 and 2024 checks.
- Groups with fewer than 100 development rows (Q + DNP, Doubtful) are pooled with all Questionable rows.

| id | multiplier |
|---|---|
| `m4_two_stage_v1` (K2, primary) | P̂(active) × r(group). P̂ = logistic(3.533 − 0.752·DNP + 0.058·LP − 3.179·Doubtful − 0.891·returning + 0.430·min(weeks listed, 4)). r = Q 0.83, Q+LP 0.82, Q+FP 0.93, listed-only DNP/LP 0.96 |
| `m4_practice_rule_v1` (K1) | Q −9%, Q+LP −9%, Q+FP −4%, listed-only DNP/LP −2% |

- Rows with no listing, or listed with full practice and no designation, are not adjusted.
- Historical checks:
  - 2019 (fresh): K2 −0.0185 vs `m2_espn_cal` and −0.011 vs M3b.
  - 2024 (contaminated): K2 −0.022 and −0.009.
  - Both vs-M3b intervals include 0.

Each lineage also keeps its own **data vintage**:
- M1 computes features from 2019+ history and trains from 2020.
- M2 uses 2017+ history and trains from 2018.

Extending the project's data window therefore never alters an earlier lineage.
This was verified after the extension to 2017.

**Changing a model means a new lineage** (M3, …) with its own registry, fingerprint
and prospective record, starting at its freeze date.

## Benchmark hierarchy

1. **Raw ESPN.** ESPN's final pregame projection.
2. **Calibrated ESPN (`m2_espn_cal`).** The best of a pre-declared ESPN-only
   calibration family, refit weekly. The family is:
   - linear a + b·ESPN;
   - a natural spline of ESPN;
   - linear on ESPN's projected stat components;
   - the components fit with recency weights (half-life one season), which was selected.

   It contains no player information beyond ESPN's own projection.
3. **ESPN-free model (`m2_no_espn`).** Our football information only.
4. **ESPN + our information (`m2_espn_aug`).** Calibrated ESPN plus an
   elastic-net model of calibrated ESPN's residual.

**The scientific question is (4) vs (2).** Beating raw ESPN is not enough: in
Milestone 1, most of the apparent edge over raw ESPN was calibration.

## Milestone 2 development protocol (pre-registered, experiment log E3)

| Stage | Seasons | Use |
|---|---|---|
| Feature warm-up | 2017 | history only |
| Training rows | 2018+ | every refit uses all eligible rows before the target week |
| Development folds | 2020–2023 | all decisions: calibration choice, hyperparameters (static season folds), model selection (weekly rolling refits) |
| Historical holdout | 2024–2025 | run **once** after freezing (not pristine, because M1 used them) |
| Prospective | 2026 from Week 5 | the only confirmatory evidence (docs/prospective_protocol.md) |

Rules that hold throughout:
- All models are fit to the conditional mean.
- MAE is primary, and RMSE must not get worse.
- Uncertainty comes from a paired, season-stratified bootstrap of whole weeks.
- The pre-specified subsets are: all ESPN-projected WRs (primary), the top 60 and the top 36 by ESPN projection.
- `assert_dev_only()` makes it impossible for development targets to see seasons after 2023.

## Results so far

See research/experiment_log.md (E1–E14) and reports/milestone{2,3,4}_report.html.
In short:
- calibration is the only robust gain over raw ESPN;
- the M2 augmentation model did **not** beat calibrated ESPN on the holdout;
- the ESPN-free model improved modestly but remains well behind ESPN.

## Adding a challenger (M3+)

1. Write and pre-register the hypothesis, candidates and selection rule in the
   experiment log **before** running anything.
2. Develop on historical seasons only. 2026 outcomes are off-limits.
3. Freeze with a generated registry file. Write its fingerprint once.
4. Add the lineage to `scripts/weekly_run.R` runs from the next week on. Its
   prospective record starts then.
