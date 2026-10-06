# Milestone 3 plan: new pregame information and prospective edge discovery

Written on 2026-10-06, before any M3 challenger was frozen and before any 2026
outcome was evaluated.

## 1. Repository state found

- **Frozen lineages.**
  - M1 (`m1_*`, commit 9663ca7) and M2 (`m2_espn_cal`, `m2_no_espn`, `m2_espn_aug`, frozen 2026-10-05 22:42Z).
  - Each has a registry, a data vintage and a prediction fingerprint. Both re-verify as identical.
- **M2 conclusion (preserved).**
  - Calibrated ESPN beats raw ESPN (holdout −0.046 MAE).
  - M2 features do **not** improve calibrated ESPN (holdout +0.010, worse among the top 36 and top 60).
  - The ESPN-free model is about 0.19 MAE behind ESPN.
  - XGBoost and elastic net found nothing extra.
  - 2026 is the only clean evidence.
- **Prospective archive.**
  - 2 Week-5 runs (M1 at 20:37Z; M1+M2 at 22:49Z on 2026-10-05) and 1 ESPN snapshot (19:40Z).
  - All SHA-256-verified against committed manifests, which were pushed before kickoff.
  - First Week-5 kickoff: 2026-10-09 00:15Z.
- **Operations gaps found and fixed in this milestone** (commit dcbda4f):
  - lineages defaulted to `m1` only;
  - there was no week validation or kickoff warning;
  - there was no status or backup tooling;
  - snapshots had no hash verification.

## 2. M1/M2 prospective safeguards

- M1 and M2 registries, data vintages, fingerprints and archives are untouched.
  M3 code is additive.
- `weekly_run.R` now defaults to **all** frozen lineages. Each run records the
  SHA-256 of every registry it used. Manifests are append-only and refuse
  misaligned rows. `status.R` verifies every archived file.
- M3 challengers are a separate lineage. Their records start at their own freeze,
  and they never enter the M1/M2 primary test.
- Verified backup tooling exists. An interim same-machine backup was made; an
  off-machine destination is the owner's decision.

## 3–5. Source feasibility, ranking, and historical-valid vs prospective-only

See §13, which was filled in from the source investigations.

## 6. Hypothesis A: ESPN over-reacts to recent role change (`m3_role_adjust_v1`)

- **Metric.** `xfp_trend` = EWMA(2) − EWMA(6) of expected fantasy points over
  the player's prior games (M2 feature, point-in-time).
- **Rule.**
  - If `xfp_trend ≥ 1.42`, add **−0.30** to calibrated ESPN.
  - If `xfp_trend ≤ −1.65`, add **+0.25**.
  - Otherwise, and when the metric is missing, add 0.
- **Derivation.**
  - The thresholds are the development (2020–2023) 90th and 10th percentiles among ESPN-projected WRs.
  - The magnitudes are **half** the development mean residuals (top decile −0.61, negative in all 4 seasons; bottom decile +0.52, positive in 3 of 4). Halving guards against winner's curse.
- **One sensitivity variant (`m3_role_adjust_q20_v1`).** Quintile thresholds:
  ≥ 0.80 → −0.27, ≤ −1.11 → +0.16.

## 7. Hypothesis B: ESPN over-projects WRs returning from missed games (`m3_return_adjust_v1`)

- **Returning** means the player has at least one appearance earlier **this
  season**, and the team has played at least one game since then without the player.
  `team_games_missed` counts only scheduled team games, so byes are not misses.
  It is computed from the schedule and from appearances strictly before the target week.
- **Rule.** One game missed: **−0.2**. Two or more: **−0.4**. Otherwise 0.
- **Derivation.** Half the development mean residuals:
  - one missed game: −0.44 (seasons inconsistent);
  - two or more: −0.84 (negative in all 4 seasons).
- **Exclusions.**
  - The first appearance of a season, since a prior-season absence is not counted.
  - Players with no prior appearance this season.
- **No injury status is required.** Historical timestamps for injuries are
  examined separately in §13.

**Combined (`m3_combined_v1`).** The pre-registered sum of A and B, with no
re-estimation.

**Common base.** Calibrated ESPN, using the same calibration family and weekly
refit procedure as the frozen `m2_espn_cal` (components fit with recency
weights, from 2018). The adjustments are constants, and nothing is learned at run time.

**Benchmark and test (per challenger).**
- Compared with `m2_espn_cal`, archived in the same runs, on identical player-weeks.
- Primary test: ΔMAE with its 95% week-bootstrap interval entirely below 0, and RMSE no worse.
- Secondary: the top 60 and top 36 subsets, and the share of weeks won.
- Evaluated at the end of 2026 on archived runs only. Fewer than 8 completed
  archived weeks means **insufficient**.

**One-time historical check.**
- 2024–2025 rolling, run once after freezing.
- It is reported, but cannot change the rules.
- A challenger is frozen whatever this check shows.

## 8. Component modeling plan (diagnostic research track)

- Components: targets, receptions, receiving yards, receiving TDs.
- Each component is compared under four information levels: ESPN raw, ESPN calibrated,
  ours without ESPN, and ESPN plus ours. Static development season folds, 2020–2023.
- Two analyses:
  - Decompose calibrated ESPN's points error by component.
  - Regress the realised error on our disagreement with ESPN (in points) to measure
    how informative the disagreement is.
- First results:
  - **Targets** is the only component where ESPN plus ours beats calibrated ESPN
    (ΔMAE −0.016 [−0.026, −0.007]).
  - Receiving TDs get **worse** with our information.
  - Disagreement slopes are about 0.33 for every component: our disagreement is
    partly informative, but mostly noise.
- Not used to select any challenger.

## 9. Prospective start weeks

- **Rule challengers (A, B, combined).** Freeze before the first Week-5 kickoff
  (2026-10-09 00:15Z). Their prospective record starts in **Week 5** if a run
  archives them before that kickoff; otherwise in the first week that has such a run.
- **New-information challengers.** They start at their own freeze, after their
  development (see §13).

## 10. Expected repository changes

- `R/live/ops.R` and `scripts/status.R`, `backup_archives.R`, and the new `weekly_run.R` (done).
- `R/models/m3_rules.R` and `m3_freeze.R`, plus `models/registry/m3.yml` (on freeze).
- Ingestion for the new sources in §13, with snapshot or as-of logic and leakage
  tests.
- `R/evaluation/m3_components.R`.
- Experiment log E6 and later, provenance updates, and `reports/milestone3_report.qmd`.

## 11. Major risks

- Effects are small (about 0.3 points on 10–20% of player-weeks). Several seasons
  of prospective data may be needed to resolve them.
- Prospective evidence depends on weekly runs being made.
- ESPN may already price current-week information (injuries, QB news) into its
  final projection, which leaves little room for new information.
- Terms and licensing limit which projection and market sources can be used.

## 12. Explicitly not pursued

- Broad model or feature searches.
- Hyperparameter grids.
- New learners (random forest, neural networks, ensembles).
- Any change to M1 or M2.
- Back-filled prospective predictions.
- Any use of 2026 outcomes for development.
- Untimestamped injury, depth-chart or closing-line data used as pregame.
- Paid data, or sources whose terms prohibit this use, unless the owner decides otherwise.
- Long-TD or "boom" modelling.

## 13. Source feasibility matrix

*(Filled in from the source investigations; see below.)*

**Status (2026-10-06).**
- Sections 1–12 were committed at 7573bdf.
- The M3 rules were frozen at 00:24Z (64ef35d), and their one-time 2024–2025
  check is in experiment log E7.
- The source investigations are complete:
  - `docs/source_feasibility.csv` is the full matrix.
  - The `nfldata` git-history row is updated when that investigation reports.

**Ranked new sources** (value × reliability):
1. **nflverse injury reports, 2017–2024.** Historical-valid via `date_modified`; 2026 prospective via our captures.
   - It produced hypothesis D (Questionable).
   - Hypothesis C (vacated targets) was rejected on development evidence (E9).
2. **nflverse depth charts, 2025+.** Timestamped and historical-valid from 2025, captured every run.
   It has too little history to develop a rule; a candidate for later.
3. **`nfldata` git history** (lines and expected QB). Pending verification.
4. **Projection markets** (FantasyPros, Sleeper) and **The Odds API.** Blocked by terms or cost;
   the owner's decision.

**Historical-valid vs prospective-only.**

| Class | Sources |
|---|---|
| Historical-valid | injury designations 2017–2024; depth charts 2025+ |
| Prospective-only | injury designations 2026 (our capture time); ESPN injury status (not used) |
| Rejected as pregame | depth charts ≤ 2024; closing lines; routes and participation (post-season) |

**Hypothesis D** (Questionable designation, lineage M3b) is pre-registered in E9.

**Final status (2026-10-06 03:50Z).**
- **Frozen:** M3 (hypotheses A and B) and M3b (hypothesis D). All are archived from 2026 Week 5.
- **Rejected:** hypothesis C (vacated targets).
- **Inconclusive and not frozen:** hypothesis E (expected-QB change from the nfldata git history).
- **New historical-valid data built:**
  - pregame injury designations, 2017–2024;
  - as-of-kickoff − 2 h schedule state (lines and expected QB), 2021–2025.
- **Prospective-only captures running:** injury reports, depth charts and schedules,
  each as a dated retrieval with every run.
