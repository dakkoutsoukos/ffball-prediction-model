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

See research/experiment_log.md (E1–E5) and reports/milestone2_report.html.
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
