# Milestone tracker

*Every milestone in [07](../07_master_roadmap.md), with dependencies, acceptance criteria and status.
A milestone is COMPLETED only when its acceptance criteria pass. Code being written is not enough.*

**Statuses:** NOT STARTED · IN PROGRESS · BLOCKED · VALIDATING · COMPLETED · FAILED EXPERIMENT · DEFERRED.
Some criteria can only be met over time (e.g. "≥ 95% of remaining 2026 games covered"). For those, the
milestone is marked COMPLETED (build) once everything checkable now passes, and the time-dependent criterion
is tracked in the "Ongoing criteria" table at the end.

Last updated: 2026-10-13.

## Summary

| id | Milestone | Phase | Depends on | Status | Commit(s) / notes |
|---|---|---|---|---|---|
| Step 0 | Manual W6 runs (owner) | 0 | — | DEFERRED (superseded) | F0's scheduled task covers the W6 Thu/Sun/Mon slates from 2026-10-15 if the PC is on and logged on; the owner still pushes, and the W6 Tuesday manifest (5d36f3b) was not yet on origin on 2026-10-13 |
| F0 | Prospective operations hardening | 0 | — | COMPLETED (build) 2026-10-13; ongoing criteria tracked | 6d7965c, 2fc776c, 75448a1. Task `FFball_dispatch` registered; smoke test and in-task self-test pass |
| F1 | Prospective analysis addendum (E16) + R3 outcome-free plan (E17) | 0 | — | COMPLETED 2026-10-13 (pending the owner's push) | E16/E17 committed before any 2026 scoring; power corrected (X-008) |
| D0 | Lineup helpers (FLEX slotting, game-time plan) | 1 | — (F5 optional) | COMPLETED 2026-10-13 | ea4a669; ledger rows to be hooked in F5; prior used for WR too (X-011) |
| F3 | League state v2 (lite now; full after O8 items) | 1 | — | F3-lite COMPLETED 2026-10-13; F3-full NOT STARTED (O8 items) | c9fc3dc; live checks all pass; ESPN playoff odds absent (X-004) |
| F5 | Decision ledger (records only; outcomes sealed) | 1 | — | NOT STARTED | |
| F2 | Evaluation framework (lite now; full after R1) | 1 | — | NOT STARTED | |
| P0 | Baseline outcome distributions (E18) | 1 | F2-lite | NOT STARTED | |
| S0 | In-season league simulator v0, shadow (VL3) | 1 | F3-lite, P0, F5 | NOT STARTED | Condition met: trade deadline 2026-12-02 (~7 weeks after 2026-10-13) |
| R1 | M5: score the 2026 record + VE-P1 | Season end | F1; season over | NOT STARTED | Jan 2027 |
| I1 | Platform runtime (renv profile) and modularisation | Season end | R1 | NOT STARTED | |
| F4 | Position-general historical frame | 2 | F2 | NOT STARTED | |
| F6 | Decision laboratory v1 | 2 | F2, F4 | NOT STARTED | |
| P1 | Availability v2 (with R2, E19, batch check 2019) | 2 | F2, F4 | NOT STARTED | |
| R2 | RB/TE/QB availability rules (with P1, E19) | 2/5 | F4 | NOT STARTED | |
| P2 | Calibrated distributions v1 (E20, batch check 2024) | 2 | P1, F4, F2 | NOT STARTED | |
| P3 | Dependence model (E21; gated) | 2 | P2 | NOT STARTED | |
| P4 | Season dynamics (VL4) | 2 | P2, F4 | NOT STARTED | |
| P5 | Scenario engine v1 | 2 | P1, P2, P4 (P3 optional) | NOT STARTED | |
| S1 | Matchup win probability v1 (VL5) | 3 | P5, F3, F6 | NOT STARTED | |
| S2 | Season and playoff simulator (thin → v1; VL6) | 3 | F3, S0 engine; P5, S1 for v1 | NOT STARTED | |
| S3 | Valuation v3 (VL7) | 3 | P4, P5, S2, F6 | NOT STARTED | |
| D1 | Lineup engine v1 (VL8; triage-gated) | 4 | S1, P5, F5, F6 | NOT STARTED | |
| D2 | Trade engine v3 | 4 | S2, S3, F3, F5 | NOT STARTED | |
| D3 | Waiver / free-agent assistant (VL9) | 4 | S2, S3, F3, F6 | NOT STARTED | League has no FAAB (`isUsingAcquisitionBudget = FALSE`): the FAAB part is gated off; waiver priority applies |
| D4 | Draft assistant (VL10; by Aug 2027) | 4 | S2, S3, O2/O8 captures | NOT STARTED | `keeperCount = 0`: keeper part gated off |
| D5 | Weekly intelligence briefing | 4 | D1–D3, F5, I3 | NOT STARTED | |
| VL11 | Decision-family batch check (2025 replays) | 4 | F6, D1–D3 pre-registrations | NOT STARTED | |
| R3 | Forecast-horizon study (E17; outcome-free) | 5 | F0 | NOT STARTED | Data accrues from F0 captures |
| R4 | Multi-source capture ◇ | 5 | O3 | NOT STARTED | Owner decision O3 (default: not captured) |
| R5 | As-of market context | 5 | F4 | NOT STARTED | Inside P2/P3 |
| R6 | ESPN-independent fallback ◇ | 5 | F4 | NOT STARTED | |
| R7 | Usage reliability, first-read share ◇ | 5 | F4 | NOT STARTED | |
| I2 | Local dashboard ◇ | 6 | D5 | NOT STARTED | |
| I3 | Monitoring and alerting | 6 | with D5 | NOT STARTED | |

## Acceptance criteria (from 07; checkable items first)

### F0 — Prospective operations hardening — COMPLETED (build) 2026-10-13
1. ✅ Dispatcher keyed to kickoff times (`R/live/dispatch.R`): early-week run; post-report run in [first kickoff − 3 h, − 1.5 h) per slate; catch-up until kickoff − 30 min; ≤ 2 attempts per slate. Verified by dry runs on the real W6 schedule (Thu, London Sun 09:30, Sun, Mon) and the W7 early-week run.
2. ✅ Each run: `weekly_run.R --commit` → `valuation_run.R --capture` → pathspec-limited local commit of `archive/valuation_*.csv` → status file + log. Never pushes; a dirty tree is skipped and logged.
3. ✅ New `post_report_coverage()` (existing `week_coverage()`/`injury_report_status()` untouched): per game, the latest pre-kickoff run and whether both teams' final reports were in that run's injury capture (or the capture was within 26 h of kickoff); games within 3 h of kickoff without one are flagged in `status.R` and `data/ops/status.txt`.
4. ✅ Git-ignored wrapper and XML task definition generated by `scripts/ops_setup.R`.
5. ✅ Tests: `test-dispatch.R` (80 expectations: Thursday, Saturday, international, Thanksgiving, DST, catch-up, attempts, coverage, lock, wrapper, status); full suite 175 blocks / 632 expectations / 0 failures. Fingerprints: no frozen code or target touched.
6. ✅ Task `FFball_dispatch` registered (hourly at :05, interactive token, hidden, on battery, missed triggers caught up). Manual trigger → decision logged, result 0. In-task self-test: subprocess, git HEAD, git identity, ESPN enabled, cookies present, clean tree all ok (after the HOME fix, 75448a1).
7. ✅ "Automation" section in `docs/prospective_protocol.md`; rules unchanged.
8. ⏳ *Ongoing:* ≥ 95% of remaining 2026 games with a post-report, pre-kickoff run; 0 scripted pushes; 0 runs on a dirty tree; all-position captures ≥ 2 times per week for ≥ 8 weeks. Measured with `ops_coverage_report()` and `capture_cadence()`.

Deviation from the prompt (recorded in decisions X-006): new functions instead of edits to `week_coverage()`/`injury_report_status()`; task in the root folder (`FFball_dispatch`) instead of a task folder.

### F1 — Prospective analysis addendum (E16) + E17 — COMPLETED 2026-10-13
1. ✅ `R/evaluation/power.R`: `week_level_diffs()`, `week_noise()`, `mde()`, `power_at()` (one-sided toward improvement), `mde_table()`, `f1_reference_table()`, `percentile_bootstrap_sim()`; 35 test expectations (closed-form MDE values 1.15/0.99/0.72 σ_w; power at the MDE ≈ 80%; pairing identical to `pooled_bootstrap()`; within-season σ_w).
2. ✅ σ_w from historical frames only (targets `f1_noise`, `f1_reference`, `f1_mde`, built with `shortcut = TRUE`: no upstream rebuild). The linearised SE matched the week bootstrap (0.00356 vs 0.00343), and the bootstrap reproduced E14's CI exactly.
3. ✅ E16: MDE/power table (MAE and MSE; W ∈ {8, 10, 13, 14}; σ_w × {1, 1.5}; pooled 2026 + 2027); W5 structural zero; S1–S8 secondaries; late-push rule; no interim looks; primaries unchanged.
4. ✅ E17: outcome-free horizon plan with fixed adoption rules (spread term, mean drift, martingale check).
5. ✅ No 2026 outcome loaded. Committed locally. **The owner's next push publishes it** (required before any scoring; R1 is in January).

Findings: power is lower than the plan said (X-008); the pre-registered bootstrap is anti-conservative at 13 weeks (S8 added). The anytime-valid analysis runs only at R1 (X-009). Push-time evidence added (X-010).

### D0 — Lineup helpers — COMPLETED 2026-10-13
1. ✅ `val_flex_slotting()`: the latest-kickoff starters take the flexible slots; tests show the starting set and expected points are unchanged, every starter is eligible for his slot, and ties keep the higher value in the specific slot.
2. ✅ `val_gametime_plan()`: P(active) from `config/availability_prior.yml` (Q 0.71, D 0.07, Out 0), decision time = kickoff − 90 min, the best pivot still unlocked then that fits the open slots (including cross-position moves via FLEX), plan EV, and advice; shared pivots are flagged. **Deviation:** the prior is used for WR too, because archived M4 runs do not store P(active) and M4 is never recomputed (X-011).
3. ✅ Bit-identity guard for `val_allocate()`/`val_assign_slots()`; CLI `trade_analyzer.R lineup`; toy weeks with known answers; the lock-at-kickoff rule (locked starters keep their ESPN slots, locked bench players cannot enter). 51 test expectations.
4. ✅ Real-league run (2026-10-13): structure correct. It found that the current ESPN lineup (snapshot 07:06Z) starts a player on bye; the recommended changes add +33.7 expected points (owner informed; names never printed in chat).
5. Ledger rows: deferred to F5 (D0 lists F5 as optional).

### F3 — League state v2 (lite) — COMPLETED 2026-10-13
1. ✅ `view=mMatchup` added to the existing single request (`LG_VIEWS`, `lg_league_url()`; test pins the exact view list). No additional requests.
2. ✅ Parsed (`R/valuation/league_state.R`, team ids only): schedule (period, home/away, bye, points, winner, playoff tier); standings (records, seeds, ranks, waiver rank, counters, ESPN playoff odds if returned); rules (playoff format and round lengths, tie rules, home bonus, top-half bonus, deadline, keepers, waiver/FAAB settings).
3. ✅ Hand-written synthetic responses (tie, bye, two-week final, tampered records); the V2 parse is identical with or without the schedule; privacy test over every tracked file (`test-privacy.R`); snapshots stay write-once under the alias with hash-only manifests.
4. ✅ First live response (2026-10-13): keys only in the earlier inspection; `league_refresh.R` prints a name-free summary. **All five invariants pass on the live league**: one game per team per period; all 8 teams in all 14 periods; records, points for and points against recomputed from the schedule equal ESPN's; seeds follow TOTAL_POINTS_SCORED. Deadline 2026-12-02 (49.8 days away).
5. Findings: 56 regular-season matchups; playoff matchups not yet created by ESPN (S0 must build the bracket from seeds: 4 teams, semifinal 1 week, final 2 weeks); `currentSimulationResults` absent (X-004).

### F5 — Decision ledger
1. `decision_record` schema (id, type, alias, season, week, `as_of_utc`, input hashes, recommendation, alternatives with metrics, model versions, owner-action flag).
2. Private rows in `data/archive/decisions/`; hash-only `archive/decision_manifest.csv`; hooks in `trade_analyzer.R` and D0.
3. Outcome of record = stats after the Thursday stat-correction pull; joins computed, **sealed** by a guard until the 2027 decision pre-registrations are committed.
4. Tests: schema, write-once, join, seal guard. *Ongoing:* ≥ 95% of recommendations ledgered.

### F2-lite — Scoring, register, PIT registry
1. `R/evaluation/scoring_v2.R`: CRPS from quantiles, randomised PIT, coverage, interval score, Brier + binned reliability; closed-form tests.
2. `research/contamination_register.yml` + `assert_family_seasons()` (05 §9 allocations, VE1c touches, 2026 sealed).
3. Draft `config/pit_registry.yml` (historical ESPN = late horizon).
4. Regression test reproducing `m2_holdout_comparisons`; M1–M4 fingerprints identical; no `renv.lock` change.

### P0 — Baseline outcome distributions (E18)
1. E18 committed before any computation.
2. POD table for QB/RB/WR/TE: new rolling-origin per-position linear calibration (MSE); empirical quantiles of (actual − base) on active rows by position × fixed bands; τ grid; interpolation and floor; POD_h = P(active | h)·F + (1 − P)·δ₀.
3. Production table fit on 2020–2023 only; nothing computed or viewed on 2024–2025.
4. `models/probabilistic/pod_baseline_v0.yml` re-derived by the pipeline + fingerprint; `validate_pod_table()`; prospective archive + manifest.
5. Development coverage meets the 05 §6 gate (descriptive).

### S0 — Shadow league simulator (VL3)
1. VL3 committed first (σ_L by simulation matching on 2019–2023; log L ~ N(−σ²/2, σ²); sensitivity bands; archive evaluation-only).
2. `R/simulation/season_sim.R`: availability draws, P0 noise, level shocks, 10,000 sims, L'Ecuyer-CMRG, common random numbers; new decision/realised lineup evaluator (V1/V2 bit-identity); league rules from F3.
3. Invariants (Σ P(playoffs) = slots, Σ P(title) = 1); Monte Carlo SE ≤ 0.5 pp; runtime ≤ 10 min; determinism.
4. Labelled "shadow / unvalidated"; CLI `trade_analyzer.R odds`; ledger rows; archived before each week's first kickoff.

### Later milestones
Criteria as written in [07](../07_master_roadmap.md) §5–9. Copied here when a milestone becomes active.

## Ongoing criteria (time-dependent)

| Milestone | Criterion | Measured by | Status |
|---|---|---|---|
| F0 | ≥ 95% of remaining 2026 games with an archived post-report, pre-kickoff run | `ops_coverage_report(2026, tg, dispatch_runs(), from_week = 6)` | Tracking from W6 (task live 2026-10-13 21:00Z) |
| F0 | 0 scripted pushes; 0 runs on a dirty tree | `data/ops/dispatch_log.csv` (a dirty tree is logged as SKIPPED, never run) | Tracking |
| F0 | All-position captures ≥ 2 times per week for ≥ 8 weeks | `capture_cadence(2026)` | W5 = 3, W6 = 1 so far |
| F5 | ≥ 95% of recommendations ledgered | ledger manifest vs CLI invocations | Not started |
