# Blockers

*Issues that prevent progress on a milestone. Resolved blockers move to the bottom with their resolution.*

## Open

| id | Since | Milestone(s) | Blocker | Needed to unblock | Workaround / independent work |
|---|---|---|---|---|---|
| B-001 | 2026-10-13 | F4 (K and D/ST criterion only) | F4's "scoring match ≥ 99.9% per position" cannot be checked for K and D/ST: no ESPN K/DST actuals exist locally (historical files cover QB/RB/WR/TE slots only) | Owner decision O8 (K/DST slot ids in the capture, or historical K/DST week-of files), **or** the 2026 league data once R1 unseals 2026 outcomes | K/DST tables built and internally validated (R-005), and labelled "not ESPN-validated". QB/RB/WR/TE criteria met; Phase 2 proceeds on them |
| B-002 | 2026-10-14 | S0 K/D-ST addendum (E23 result permits v0 K/D-ST draws in S0 team totals) | S0 needs the league's K and D/ST slots, rostered units and scoring; live captures do not include K/DST slot ids | Owner decision O8 (K/DST slots in the capture) | Simulators keep excluding K and D/ST and say so; X22 shows v0 would be adequate |

## Waiting on owner decisions (not blocking current work)

| Decision | Blocks | Default meanwhile |
|---|---|---|
| O2 ADP/auction capture (preseason 2027) | D4 calibration | Projections-only drafting |
| O3 other projection sources | R4 | Not captured |
| O4 FantasyPros ECR archive | F6 drafts (optional), D4 | Not used |
| O5 public Sleeper leagues | S1/D3 priors (optional) | Not used |
| O6 RTools / Stan | none required | Toolchain-free |
| O8 remaining items (transactions, box scores, past seasons, draft history, K/DST slots, 2018 history) | F3-full, X25, D4 history, K/DST projections | F3-lite only |

## Resolved

| id | Resolved | Blocker | Resolution |
|---|---|---|---|
| B-000 | 2026-10-13 | O1, O8 (`mMatchup`) and the capture cadence needed owner authorisation | Approved by the owner (decisions X-001) |
