# Execution progress

*Overall status of executing the master plan ([07](../07_master_roadmap.md)). Per-milestone detail is in
[milestone_tracker.md](milestone_tracker.md); decisions in [decisions.md](decisions.md); results in
[experiment_results.md](experiment_results.md); blockers in [blockers.md](blockers.md); how to resume in
[session_handoff.md](session_handoff.md).*

## Status at a glance

| Category | Milestones |
|---|---|
| Completed | F0 (build; season-long criteria tracked) |
| In progress | F1 |
| Next (ready) | D0 → F3-lite → F5 → F2-lite → P0 → S0 |
| Blocked | — |
| Deferred | — |

**Capability labels** (kept distinct, as the brief requires):

| Label | Meaning | Items |
|---|---|---|
| Implemented | Code exists and its tests pass | (existing M1–M4, V1, V2); F0 dispatcher and scheduled task (operational, no statistical claim) |
| Statistically validated | Passed a pre-registered evaluation | (existing: M3b/M4 historical checks; prospective tests pending R1) |
| Experimental | Built, not yet validated | — |
| Planned | Not built | Everything in the tracker not listed above |

## Baseline at the start of execution (2026-10-13)

- `main` at `e0cfe70`; `research/master_plan/` untracked (now committed with this tracker).
- Test suite: 156 `test_that` blocks, 550 expectations, 0 failures (22 s).
- Prospective record: W5 runs (all Mon–Tue, so M3b/M4 equalled calibrated ESPN for W5); W6 one Tuesday run (07:02Z).
- Owner decisions taken: see [decisions.md](decisions.md) X-001.

## Session log

| Date | Session | Work |
|---|---|---|
| 2026-10-13 | 1 | Read the full plan; inspected the repo; owner decisions O1, O8 (`mMatchup`), captures; execution tracker created. **F0 completed** (dispatcher, scheduled task registered and self-tested; three bugs fixed, X-007). Started F1. |
