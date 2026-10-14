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
| F5 | Decision ledger (records only; outcomes sealed) | 1 | — | COMPLETED 2026-10-13 | 781889c; S0 must add its own hook |
| F2 | Evaluation framework (lite now; full after R1) | 1 | — | F2-lite COMPLETED 2026-10-13; F2-full NOT STARTED (after R1) | 06b5d7a |
| P0 | Baseline outcome distributions (E18) | 1 | F2-lite | COMPLETED 2026-10-13 | E18 e2db81e (pre-registration); coverage gate passed in all 12 cells; frozen; archive started |
| S0 | In-season league simulator v0, shadow (VL3) | 1 | F3-lite, P0, F5 | COMPLETED 2026-10-13 | f4f1e06 (VL3), 136d766 (σ_L), 0012a18 (engine + CLI); runs need a fresh league snapshot |
| R1 | M5: score the 2026 record + VE-P1 | Season end | F1; season over | NOT STARTED | Jan 2027 |
| I1 | Platform runtime (renv profile) and modularisation | Season end | R1 | NOT STARTED | |
| F4 | Position-general historical frame | 2 | F2 | COMPLETED 2026-10-13 for QB/RB/WR/TE. K/DST built and internally validated, but its ESPN scoring-match criterion is BLOCKED (B-001) | aff54ca (part 1: R-004, X-016); part 2 K/DST (R-005, X-017). docs/player_week_all.md |
| F6 | Decision laboratory v1 | 2 | F2, F4 | COMPLETED 2026-10-13 | LAB1, LAB1a, LAB1b (a008083, 786b892, c46dd21); replay 23.7 min (≤ 2 h); firewall tests pass; triage (X8, X9) recorded before results (0c01edd); development results descriptive (b57719e). X9 kill rule fired: D1 gets no full P(win) mode |
| P1 | Availability v2 (with R2, E19, batch check 2019) | 2 | F2, F4 | VALIDATING: E19 (0447e38), E19b (0ad9e9b) committed; the 2019 batch check is running | Development: GLMM Brier skill 0.118 [0.084, 0.151] over the rate table |
| R2 | RB/TE/QB availability rules (with P1, E19) | 2/5 | F4 | VALIDATING: B1 selected on development (parameters committed); the 2019 check is running | H14 underpowered (MDE 0.128 vs development effect 0.067), stated in E19b |
| P2 | Calibrated distributions v1 (E20, batch check 2024) | 2 | P1, F4, F2 | IN PROGRESS: E20 committed (f98f3ca); candidates C0-C3 built and tested (d871c7f); development run next | |
| P3 | Dependence model (E21; gated) | 2 | P2 | IN PROGRESS: gate pre-registered (b382861) and built (8067cf6); runs after P2 development | |
| P4 | Season dynamics (VL4) | 2 | P2, F4 | IN PROGRESS: VL4, VL4a committed; code built and tested (46d8f08); development run after P2 | |
| P5 | Scenario engine v1 | 2 | P1, P2, P4 (P3 optional) | VALIDATING: engine built and tested (2b641eb); the 600 × 14 × 5,000 benchmark is pending; frozen P2/P4 components swap in after E22 | |
| S1 | Matchup win probability v1 (VL5) | 3 | P5, F3, F6 | COMPLETED (development) 2026-10-13 | VL5 (4d964c1); simulation non-inferior to the normal approximation (ΔBrier +0.0001, upper +0.0003) and the slope rule passes: S1-sim adopted; the check is in VL11; real-league calibration sealed until R1 |
| S2 | Season and playoff simulator (thin → v1; VL6) | 3 | F3, S0 engine; P5, S1 for v1 | IN PROGRESS: thin slice built on S0 (a84579b, f4714a0); v1 pending | |
| S3 | Valuation v3 (VL7) | 3 | P4, P5, S2, F6 | NOT STARTED | |
| D1 | Lineup engine v1 (VL8; triage-gated) | 4 | S1, P5, F5, F6 | NOT STARTED | |
| D2 | Trade engine v3 | 4 | S2, S3, F3, F5 | IN PROGRESS: thin slice (two-team ΔP re-scoring, partner-lens frontier, `rescore` CLI, ledgered); real league: 5 trades × 5,000 simulations in 0.56 min | |
| D3 | Waiver / free-agent assistant (VL9) | 4 | S2, S3, F3, F6 | NOT STARTED | League has no FAAB (`isUsingAcquisitionBudget = FALSE`): the FAAB part is gated off; waiver priority applies |
| D4 | Draft assistant (VL10; by Aug 2027) | 4 | S2, S3, O2/O8 captures | NOT STARTED | `keeperCount = 0`: keeper part gated off |
| D5 | Weekly intelligence briefing | 4 | D1–D3, F5, I3 | NOT STARTED | |
| VL11 | Decision-family batch check (2025 replays) | 4 | F6, D1–D3 pre-registrations | NOT STARTED | |
| R3 | Forecast-horizon study (E17 + E17a; outcome-free) | 5 | F0 | IN PROGRESS (tooling built c32408f; data accruing) | Refreshed weekly by the dispatcher; adoption per cell at 4 target weeks (about early November); then wire the spread/drift into S0's current-week draws |
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

### F5 — Decision ledger — COMPLETED 2026-10-13
1. ✅ `decision_record_v1` schema: id, type, alias, season, week, `as_of_utc`, input hashes, recommendation, alternatives, metrics, model versions (git commit, prior source, query file). The owner's action is a separate private append-only record (`ledger-action`).
2. ✅ Private write-once JSON in `data/archive/decisions/`; hash-only `archive/decision_manifest.csv`; hooks for every recommendation command of `trade_analyzer.R` (lineup, analyze, fair, target, sell, waivers).
3. ✅ Outcome of record: league-scored nflverse stats from the first live retrieval on or after the Thursday 12:00 ET following the week. The join (`lg_ledger_join_lineup()`, realised, alternative and hindsight points plus regret) is implemented and **sealed twice**: no join before the season ends plus 7 days (E16 §5), and no report before VL8–VL11 exist.
4. ✅ Tests (29 expectations): write-once, tamper detection, distinct ids, actions, cutoff, both seals, lineup regret. First real decision ledgered and verified.
5. ⏳ *Ongoing:* ≥ 95% of recommendations ledgered. Every current recommendation path ledgers; S0's `odds` must add its hook.

### F2-lite — Scoring, register, PIT registry — COMPLETED 2026-10-13
1. ✅ `R/evaluation/scoring_v2.R`: CRPS from quantile sets (dense-grid match to the analytic normal CRPS; within 3% on the POD τ grid; equals absolute error for point forecasts), quantile CDFs with jumps at ties, randomised PIT (uniform with an atom at 0), POD CDFs, coverage, interval score, Brier, binned reliability (Wilson CIs), CORP decomposition.
2. ✅ `research/contamination_register.yml` + `assert_family_seasons()`: 05 §9 allocations, VE1c touches, 2026 sealed until the season is over, spent checks refused, unknown families refused.
3. ✅ Draft `config/pit_registry.yml` (historical ESPN = late horizon).
4. ✅ Regression test reproduces `m2_holdout_comparisons` exactly. Stored M1–M4 fingerprint checks read "identical", and no frozen code, model artefact or `renv.lock` changed this session (git diff since e0cfe70 is empty). 50 test expectations.

### P0 — Baseline outcome distributions (E18) — COMPLETED 2026-10-13
1. ✅ E18 committed (e2db81e) before any computation. Schema-only inspection beforehand.
2. ✅ `R/probabilistic/pod_baseline.R` (`pd_`): active = at least one offensive snap; rolling-origin per-position OLS base (closed form; a planted outlier does not move its own week's base); residual quantiles by position × fixed bands with small-cell merging; τ grid with 0.25/0.75; floors; `pd_pods()` for POD_h = p·F + (1 − p)·δ₀.
3. ✅ Production table on 2020–2023 only; `pd_frame()` refuses 2024–2026 through the contamination register (tested).
4. ✅ `models/probabilistic/pod_baseline_v0.yml` frozen; the pipeline re-derives it exactly (`pd_table_check`, fingerprint 905e3ca0…); `validate_pod_table()`; prospective archive (`R/probabilistic/pod_archive.R`, `scripts/pod_archive.R`, run by the dispatcher after each capture; `archive/distribution_manifest.csv`). First archive: W6, 326 PODs.
5. ✅ **Coverage gate passed in all 12 cells** (development, out of sample by season). CRPS is 1–4% better than a normal reference. TE PIT deviates mildly (χ² p = 0.002, upper tail), recorded for P2.

Tests: 37 expectations (frame/activity, register refusal, rolling base without leakage, cell merging, floors, YAML round trip, archive write-once with a hash-only manifest).

### S0 — Shadow league simulator (VL3) — COMPLETED 2026-10-13
1. ✅ VL3 committed first (f4f1e06). σ_L by simulation matching on 2019–2023 (QB 0.368, RB 0.373, WR 0.345, TE 0.388). Without the shock the simulated ROS spread is only 54–64% of the observed. Frozen `models/simulation/s0_params_v0.yml`, re-derived by the pipeline.
2. ✅ `R/simulation/season_sim.R`: availability draws, P0 noise, level shocks, L'Ecuyer-CMRG streams per chunk, common random numbers (one pass per what-if); a new decision-vs-realised lineup evaluator (V1/V2 untouched); F3-lite rules (ties, TOTAL_POINTS_SCORED, 4-team bracket, two-week final).
3. ✅ Live league: Σ P(playoffs) = 4, Σ P(title) = 1, max MC SE 0.49 pp, 10,000 simulations in 11 s; determinism tested.
4. ✅ Label printed on every output; CLI `trade_analyzer.R odds` with sensitivity bands and what-ifs; ledger rows (type `odds`). ⏳ Weekly archiving depends on the owner refreshing the league snapshot; the dispatcher does not make league requests.

Limitations (VL3 result 2): early-week sharpness until R3; K/DST not simulated; frozen rosters; independence; the current period is simulated in full.

### Later milestones
Criteria as written in [07](../07_master_roadmap.md) §5–9. Copied here when a milestone becomes active.

## Ongoing criteria (time-dependent)

| Milestone | Criterion | Measured by | Status |
|---|---|---|---|
| F0 | ≥ 95% of remaining 2026 games with an archived post-report, pre-kickoff run | `ops_coverage_report(2026, tg, dispatch_runs(), from_week = 6)` | Tracking from W6 (task live 2026-10-13 21:00Z) |
| F0 | 0 scripted pushes; 0 runs on a dirty tree | `data/ops/dispatch_log.csv` (a dirty tree is logged as SKIPPED, never run) | Tracking |
| F0 | All-position captures ≥ 2 times per week for ≥ 8 weeks | `capture_cadence(2026)` | W5 = 3, W6 = 1 so far |
| F5 | ≥ 95% of recommendations ledgered | ledger manifest vs CLI invocations | Not started |
