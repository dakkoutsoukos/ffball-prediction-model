# Execution progress

*Overall status of executing the master plan ([07](../07_master_roadmap.md)). Per-milestone detail is in
[milestone_tracker.md](milestone_tracker.md); decisions in [decisions.md](decisions.md); results in
[experiment_results.md](experiment_results.md); blockers in [blockers.md](blockers.md); how to resume in
[session_handoff.md](session_handoff.md).*

## Status at a glance

| Category | Milestones |
|---|---|
| Completed | F0 (build; season-long criteria tracked), F1 (E16/E17; the owner's push publishes it), D0, F3-lite, F5, F2-lite, P0 |
| In progress | S0 |
| Next (ready) | Phase 1 then complete; R3 analysis once ≥ 4 weeks of captures (E17); season-end milestones from Jan 2027 |
| Blocked | — |
| Deferred | — |

**Capability labels** (kept distinct, as the brief requires):

| Label | Meaning | Items |
|---|---|---|
| Implemented | Code exists and its tests pass | (existing M1–M4, V1, V2); F0 dispatcher and scheduled task (operational, no statistical claim); F1 power tools; D0 lineup helpers (advisory: kickoff slotting is exact; game-time plans use an unvalidated published prior) |
| Statistically validated | Passed a pre-registered evaluation | (existing: M3b/M4 historical checks; prospective tests pending R1); P0 distributions: development coverage gate passed (descriptive, development only; the 2024 batch check comes with P2) |
| Experimental | Built, not yet validated | D0 game-time plans (published prior, unvalidated) |
| Planned | Not built | Everything in the tracker not listed above |

## Baseline at the start of execution (2026-10-13)

- `main` at `e0cfe70`; `research/master_plan/` untracked (now committed with this tracker).
- Test suite: 156 `test_that` blocks, 550 expectations, 0 failures (22 s).
- Prospective record: W5 runs (all Mon–Tue, so M3b/M4 equalled calibrated ESPN for W5); W6 one Tuesday run (07:02Z).
- Owner decisions taken: see [decisions.md](decisions.md) X-001.

## Session log

| Date | Session | Work |
|---|---|---|
| 2026-10-13 | 1 | Read the full plan; inspected the repo; owner decisions O1, O8 (`mMatchup`), captures; execution tracker created. **F0 completed** (dispatcher, scheduled task registered and self-tested; three bugs fixed, X-007). **F1 completed**: E16 (power corrected downward, X-008; bootstrap anti-conservative, S8) and E17. **D0 completed** (kickoff slotting, game-time plans, `lineup` CLI; on the real league it found a bye-week starter in the current ESPN lineup). **F3-lite completed** (schedule via `mMatchup`; all live invariants pass). **F5 completed** (ledger, two seals). **F2-lite completed** (scoring, register, PIT registry; fingerprints identical). **P0 completed** (E18; gate passed; frozen; W6 archive). Started S0. |
