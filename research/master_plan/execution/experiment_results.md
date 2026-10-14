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

**Not yet run:** every experiment in the master plan's backlog ([09](../09_experiment_backlog.md)) except the
power analysis (X1) and the P0 development evaluation above.
