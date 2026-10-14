# Experiment results

*Findings from executing the plan, including negative and inconclusive results. Each entry points to its
pre-registration in `research/experiment_log.md` (E-entries) or `research/valuation_log.md` (VL-entries),
which remain the binding records. Nothing here may be used to change a pre-registered criterion after its
results are seen.*

| id | Date | Family | Pre-registration | Result | Classification |
|---|---|---|---|---|---|
| R-001 | 2026-10-13 | Power of the 2026 prospective tests (analysis, historical data only) | E16 §1 | Power at 13–14 informative weeks (σ_w × 1): H-D 25–27%, H-M4 32–35%, H-B 37–40%, H-A 8–9%, H-M2 ≈ 1%. At σ_w × 1.5: 14–21%. Pooled 2026 + 2027: 55–77% for H-B, H-D and H-M4. The plan's 45–50% was optimistic (2019 variance only, normal approximation). | Negative for the plan's assumption; corrected (X-008) |
| R-002 | 2026-10-13 | Small-sample behaviour of the pre-registered week bootstrap (simulation) | E16 §1, S8 | At W = 13, the percentile bootstrap's one-sided size is 4.9% (nominal 2.5%); its power is about 10 points above the t-based figures | Methodological caveat; S8 sensitivity added |
| R-003 | 2026-10-13 | P0 baseline outcome distributions (distribution stack; development 2020–2023, out of sample by season) | E18 | Coverage gate passed in all 12 position × level cells (e.g. WR 50/80/90% = 0.501/0.806/0.902). CRPS 1–4% better than a normal reference. TE PIT departs from uniform (χ² 26.1, p 0.002; upper tail slightly too wide). Frozen as `pod_baseline_v0`. | Success (baseline frozen); TE shape recorded for P2 |
| R-004 | 2026-10-13 | F4 position-general frame: data validation (not a hypothesis test) | X-016 (criteria fixed in code before the first build) | Scoring match: QB 99.963%, RB 99.980%, WR 99.976%, TE 99.969% (on stat-line rows only: 99.912–99.964%). Frozen WR rows reproduced: 34,685 rows; 0 missing; 0 core differences; 118 ESPN-position reassignments; 0 new. No leaks in the outcome-corruption test (6 weeks) or the injury-corruption test (6 weeks, all positions). Base equals P0's on 2019–2023 (31,225 rows, maximum difference 0). | Success (data checks) |
| R-005 | 2026-10-13 | F4 part 2, K and D/ST tables: internal cross-source checks (not a hypothesis test) | X-017 (thresholds fixed before the first build) | FG bands, attempts and tries match play-by-play on 100% of 3,737 kicker-games. 3,742 D/ST rows with 0 team-games missing. Interceptions 100%, final scores 100%, sacks 98.3% (team sacks credited to no defender). Descriptive, 2019–2023 only: D/ST 5.8 points per game (SD 6.6), K 7.7 (SD 4.5). | Success (internal); ESPN-match not checkable (B-001) |
| R-006 | 2026-10-13 | F6 triage (X8, X9), outcome-free, development replays 2020–2023 | LAB1, LAB1a, LAB1b | Lineup flips raw vs calibrated 2.9% (model-implied gain 0.004 points per team-week). Waiver claim flips 7–20%. X9: 2.9% significant P(win) flips, mean ΔP(win) 0.0013, so the kill rule fires (no full P(win) mode in D1). Replay 23.7 min. | Success (instrument); D1's full P(win) mode killed |
| R-007 | 2026-10-13 | F6 development results (descriptive) | LAB1 | Shadow calibrated − raw lineups +0.003 [−0.029, +0.034]; focal arms B/C/D − A +0.06/+0.02/+0.08 with wide CIs; regret and season outcomes equal across arms | Inconclusive / null at the late horizon (no detectable decision gain from calibration) |
| R-008 | 2026-10-13 | S1 matchup P(win), development matchups (X23) | VL5 | 5,544 matchups: ΔBrier (simulation − normal) +0.0001 [−0.0001, +0.0003], non-inferior; slope 0.92 [0.72, 1.09] | Success (S1-sim adopted; equivalent, not better) |
| R-009 | 2026-10-13 | Injury stack development (P1, R2) | E19, E19b | P1: GLMM vs rate table Brier skill 0.118 [0.084, 0.151], positive every season. R2: B1 and K1 qualify, B1 selected; 2019 MDE 0.128 vs development effect 0.067 (H14 underpowered) | Development success; 2019 check pending |

**Not yet run:** every experiment in the master plan's backlog ([09](../09_experiment_backlog.md)) except the
power analysis (X1) and the P0 development evaluation above.
