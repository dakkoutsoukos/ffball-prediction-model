# Milestone 4 plan: availability intelligence and opportunity modeling

Written on 2026-10-06 (06:10Z), before any M4 experiment, and before any 2026
outcome has been evaluated (no prospective week has completed).

## 1. Repository state

- **Frozen lineages, with fingerprints re-verified as identical at 1dc8280:**
  - M1 (5 models);
  - M2 (`m2_espn_cal`, `m2_no_espn`, `m2_espn_aug`);
  - M3 (role, role-q20, return, combined);
  - M3b (`m3_questionable_adjust_v1` = Questionable × 0.91, additive variant, A+B+D combined).
- **Prospective archive:**
  - 5 Week-5 runs (latest 2026-10-06 03:44Z, all lineages) and 2 ESPN snapshots, all hash-verified and pushed.
  - Every run's `run_meta.json` records the live injury-report retrieval it used, with its SHA-256.
- **M3 findings this plan builds on:**
  - the Questionable rule improved calibrated ESPN in 2024 (ΔMAE −0.013, CI below 0, also in the top 60 and top 36);
  - targets are the only component where our information helps;
  - when we disagree with ESPN, outcomes move about a third of the way toward us;
  - our touchdown modelling hurts.

## 2. Prospective safeguards (unchanged and extended)

- M1, M2, M3 and M3b are untouched. Their fingerprints are re-checked by the pipeline.
- Any M4 rule or model gets a new id in a new registry (`models/registry/m4.yml`).
  It is frozen only if the pre-registered criteria in §10 pass, and its record
  starts at its first archived run after the freeze.
- No 2026 outcome influences anything. The weekly cadence stays Thursday ~17:00 ET
  and Sunday ~11:30 ET, run by the owner, and the scripts never push.
- **Optional late horizon.** A run made after official inactives (about 90 minutes
  before kickoff) is a different forecast horizon. It would get a separate archive
  root and manifest (`late_pregame`), never mixed with the standard record.
  Its plumbing is built but it is not run by default.

## 3. Historical development protocol (contamination register)

| Season | Prior use | Injury timestamps | M4 role |
|---|---|---|---|
| 2017 | feature warm-up only | valid | history and lagged features only (no ESPN) |
| 2018 | training rows (M2/M3); first ESPN season | valid | training rows only (no prior ESPN season to calibrate on) |
| **2019** | training rows only; **never evaluated for any hypothesis** | valid | **primary final check, fresh** |
| 2020–2023 | M2 development folds; M3 discovery of A–E | valid | **M4 development**: hypothesis formation, fitting, selection |
| 2024 | M1 validation; M2 holdout; M3 checks E7 and **E10 (where D was confirmed)** | valid | secondary check, **contaminated for the injury family**; reported separately |
| 2025 | M1 test (twice); M2 holdout; M3 E7 | **none** | excluded from injury work |
| 2026 | prospective only | our captures | prospective only |

Evaluation conventions:
- Weekly expanding-window refits throughout. The calibrated-ESPN base is
  `m2_espn_cal`'s family and procedure.
- 2019 predictions are trained on 2018 plus the earlier 2019 weeks.
- The 2019 and 2024 checks run **once**, after the candidate set and its
  parameters are fixed on 2020–2023.

## 4. Injury and practice fields actually available

- **2017–2024:** one row per player-week, the final weekly report:
  - `report_status` (Out, Doubtful, Questionable, or none = listed without a game designation);
  - final `practice_status` (DNP, Limited, Full);
  - primary and secondary injury (body part), for both the game report and the practice report;
  - `date_modified` (about Friday 15:00 ET; ≥ 99.7% before kickoff; 2017–2020 stored as US Pacific time and corrected).
- **Not available historically:**
  - daily Wednesday/Thursday/Friday practice sequences;
  - designation changes within a week;
  - game-day inactives (weekly roster `INA` is only known about 90 minutes before kickoff).
- **2025:** the same fields but **no timestamps**, so excluded.
- **2026:** the same fields, captured by us at each run. If more than one capture is
  made in a week, the captures give a **prospective-only** within-week trajectory.

## 5. Timestamp and coverage assessment

| Measure | Value |
|---|---|
| WRs listed per season, 2017–2024 | 609–758 |
| Questionable | 184–225 |
| Doubtful | 13–30 |
| Out | 106–167 |
| Listed with no designation | 281–406 |
| ESPN-projected WR-weeks on a report | about 19% (446–507 per season) |
| Pregame-valid rows | ≥ 99.7% |

Missing states are kept distinct: not listed (healthy), listed without a
designation, no timestamp (dropped), and source missing (2025).

## 6. Proposed availability features (all point-in-time)

- **This week** (from a report with timestamp < kickoff):
  - designation (Q / D / O / listed-only);
  - final practice status (DNP / LP / FP);
  - a broad body-part group (lower body, upper body, head/concussion, illness, other), exploratory only.
- **Across weeks** (lagged; earlier reports and games only):
  - listed last week;
  - consecutive weeks listed;
  - designation last week;
  - `team_games_missed` (from M3);
  - "returning while still listed".
- **Prospective-only:** within-week practice progression from multiple 2026 captures.
  This is archived, but no model uses it until it has its own history.

## 7. Target-model structure

- **Opportunity first.** The quantities modelled are targets, receptions per target
  and yards per target. **ESPN's projected targets** (stat 58) is the benchmark.
- Hierarchy:
  1. ESPN projected targets;
  2. calibrated ESPN targets (a + b · ESPN targets, refit weekly);
  3. our independent target model (OLS on M2 opportunity and history features);
  4. ESPN targets plus availability adjustment.
- **Points conversion** goes through ESPN's own implied rates
  (projected receptions/targets and yards/targets) and the YAML scoring weights:
  Δpoints = Δtargets × (rec/tgt × 1 + yds/tgt × 0.1).
  **ESPN's touchdown expectation is kept unchanged.**

## 8. ESPN-disagreement method

- `target_disagreement = our_targets − calibrated ESPN targets`.
- On development data only, estimate w in `adjusted = ESPN + w · disagreement` by
  regressing realised (actual − ESPN) targets on the disagreement. M3 suggests w ≈ 0.3.
- Report w by season to check stability.

## 9. Candidate experiments (budget: 4 serious candidates plus 2 frozen baselines)

| id | Approach | Parameters |
|---|---|---|
| **B0** | `m2_espn_cal` (frozen) | — |
| **B1** | M3b `Questionable × 0.91` (frozen) | 1 |
| **K1** | Practice-refined designation rule: fixed multipliers for Q-DNP, Q-Limited, Q-Full, listed-only DNP/Limited, Doubtful. Development-group ratios, halved; groups with n < 100 pooled with Q. | ≤ 5 |
| **K2** | Two-stage availability: P(active \| designation, practice status, return, weeks listed) by logistic regression, × the development ratio of points to calibrated ESPN when active, by group | ~6 |
| **K3** | Availability-adjusted **targets**: injury-group ratios of actual to ESPN-projected targets (halved), converted to points via ESPN rates, TDs unchanged | ≤ 5 |
| **K4** | Target-disagreement blend (w from §8) on top of B1 | 1 + B1 |

Analyses that are not candidates:
- the C-decomposition (inactive probability vs workload vs efficiency for Questionable);
- one narrow teammate-absence-on-targets analysis, closed if negative;
- broad body-part groups (exploratory).

## 10. Comparison against M3b, and freeze criteria (pre-registered)

A candidate is frozen as an M4 challenger **only if all** of the following hold:
- (a) vs `m2_espn_cal`: the development pooled (2020–2023) ΔMAE 95% CI lies below 0,
  and 2019 ΔMAE < 0, with RMSE no worse in both;
- (b) vs **M3b `Questionable × 0.91`**: development pooled ΔMAE < 0 **and** 2019 ΔMAE < 0,
  with RMSE no worse in both. Simplicity rule: if (b) fails, M3b stays the
  injury model, and that counts as the "moderate success" outcome.
- 2024 is reported as a secondary, contaminated check. It cannot rescue a candidate
  that fails 2019.
- Among candidates that pass, the one with the **fewest parameters** wins unless
  another is better on both development and 2019.

**Reporting.**
- Subsets: all WRs, top 60, top 36, top 24 (by pregame ESPN rank), plus the
  injury-affected subsets with n, MAE before and after, bias, RMSE and the mean
  adjustment.
- Every candidate reports its parameter count, ΔMAE and ΔRMSE vs both baselines,
  stability by season, and its operational needs.

## 11. Leakage-test additions

- The generic corruption test is extended to injury-report tables:
  - reports for the target week and later are corrupted, and lagged injury features must not change;
  - target-week features may use only rows whose timestamp precedes kickoff.
- Planted leaks that must be detected:
  - next week's designation used as a feature;
  - a post-kickoff report;
  - the realised active status.
- Timestamp tests:
  - Pacific correction across both DST edges;
  - duplicate and corrected reports (the most severe status is kept, and the latest timestamp must still precede kickoff);
  - missing reports;
  - team changes mid-season;
  - postponed games (kickoff taken from the schedule).

## 12. Expected repository changes

- `R/data/injuries_pregame.R`: practice status, body-part groups, lagged trajectory features, and a missingness diagnostic.
- `R/features/availability.R`.
- `R/models/m4_*.R` for the candidates, and `R/evaluation/m4_*.R` for the decomposition, target and disagreement studies.
- Targets for M4 development, the 2019 check and the 2024 check.
- `scripts/status.R`: latest injury capture, and whether this week's final designations are available.
- Optional `late_pregame` horizon plumbing.
- Experiment log E12 onward; provenance and protocol updates; `reports/milestone4_report.qmd`.

## 13. Major risks

- The Questionable signal touches about 5% of rows. Refinements split it into small
  groups (about 50–130 per group per season), so most will be noise.
- Historical ESPN values are post-inactive, while our snapshots are pre-inactive.
  The P(active) mechanism may therefore matter more prospectively than history shows.
- 2019 calibration is trained on only one prior ESPN season, so it is a noisier base.
- There are no historical within-week practice sequences.

## 14. Not reopened

- Broad feature or model searches and hyperparameter grids.
- Paid data of any kind, and off-machine backups.
- Broad teammate-absence research (one narrow target analysis only).
- QB changes, betting lines, and touchdown modelling.
- Route data; FantasyPros and other terms-restricted sources.
- Any change to M1, M2, M3 or M3b.
