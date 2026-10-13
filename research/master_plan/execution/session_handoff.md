# Session handoff

*Exact instructions for resuming execution in a new Claude Code session. Update at the end of every
substantial work segment.*

Last updated: 2026-10-13 (session 1, start of execution).

## Read first (in this order)

1. This file.
2. [progress.md](progress.md) and [milestone_tracker.md](milestone_tracker.md): what is done and what is next.
3. [decisions.md](decisions.md): owner decisions and execution decisions (do not re-ask O1, O8-`mMatchup`, captures).
4. The active milestone's section in [07_master_roadmap.md](../07_master_roadmap.md) and its prompt in [11_next_steps.md](../11_next_steps.md) §3.
5. The latest entries of `research/experiment_log.md` and `research/valuation_log.md`.

## Non-negotiable guardrails (quote them in every session)

- Never modify frozen M1–M4 registries, fingerprints, prospective manifests, `models/valuation/ros_params_v1.yml`, or V1/V2 outputs. New functions instead of edits to V1/V2 ones, with bit-identity tests. An audit failure on a frozen artefact is logged, never fixed.
- 2026 outcomes are never development data. Ledger and shadow outcomes stay sealed until the 2027 decision pre-registrations. Pre-register (log entry, committed) before computing anything outcome-dependent. Never backfill.
- Historical ESPN week-of values are **late-horizon** (post-inactive) information.
- No `renv.lock` change before R1. In-season code is base R (plus packages already in the lockfile).
- Privacy: the league id, cookies, team names, rosters and manager profiles never go in Git or chat output. Fixtures are hand-written. Commit hashes and the alias only.
- Scripts never push. Only the owner pushes. Commits go on `main` (decision X-002), and every commit must be safe to publish when made.
- Scheduled runs (F0) refuse to run on a dirty tree: **do not leave tracked files modified around run windows** (about kickoff − 3 h to − 1.5 h for each slate; e.g. Thu ~17:15–18:45 ET, Sun ~10:00–11:30 ET, Mon ~17:15–18:45 ET). Commit or revert before them.
- Windows: Rscript at `"C:/Program Files/R/R-4.5.1/bin/Rscript.exe"`; scratch R scripts go in git-ignored `tmp/` via the Write tool; read archived parquet with `mmap = FALSE`.

## Commands

- Tests: `"C:/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "testthat::test_dir('tests/testthat')"` (baseline 2026-10-13: 156 blocks, 550 expectations, 0 failures).
- Status: `Rscript scripts/status.R`.

## Operations now running (F0)

- Task Scheduler task `FFball_dispatch` fires hourly at :05 (owner logged on) → `scripts/ops_dispatch.R`. Check `data/ops/status.txt`, `data/ops/dispatch_log.csv`, `data/ops/logs/`. `Rscript scripts/ops_setup.R --status` shows the last result.
- If you change the wrapper logic, regenerate it with `Rscript scripts/ops_setup.R` (no re-registration needed; the task points at the same `.cmd`).
- Self-test inside the task environment: create `data/ops/self_test.flag`, then `Rscript scripts/ops_setup.R --run-now`; the result is the last `self-test` row of the dispatch log.

## Binding analysis rules added by F1 (research/experiment_log.md E16, E17)

- No 2026 outcome is loaded by any evaluation routine before R1 (end of the 2026 regular season), except the frozen procedure's training rows and ESPN's final *projections* (E17).
- E17 (R3) may run in season: it uses projections only, and its adoption rules are mechanical.
- Pipeline targets `f1_noise`, `f1_reference` and `f1_mde` hold the power table. Build new report-only targets with `tar_make(names = ..., shortcut = TRUE)` so upstream frozen targets are never rebuilt by accident.

## League state (F3-lite)

`lg_state_from_snapshot(lg_latest_snapshot(2026))` → rules, schedule (team ids), standings, status. Live checks pass (2026-10-13). Playoff matchups are not in the schedule until ESPN creates them: build the bracket from seeds (4 teams; semifinal = period 15, one week; final = period 16, weeks 16–17).

## Decision ledger (F5)

Every recommendation command of `trade_analyzer.R` writes a private record (`data/archive/decisions/`) and a hash row (`archive/decision_manifest.csv`; commit it). Two seals guard outcomes: `ledger_join_allowed()` (season over + 7 days) and `ledger_reports_unsealed()` (VL8–VL11 exist). New recommendation tools (S0 `odds`) must call `lg_ledger_record()`.

## Evaluation tools (F2-lite)

`R/evaluation/scoring_v2.R` (CRPS from quantiles, PIT, coverage, Brier/CORP); `assert_family_seasons(family, seasons, role)` must be called before any analysis touches outcomes (register: `research/contamination_register.yml`; record batch checks under `spent_checks`).

## Exact next action

P0 (E18): FIRST write and commit E18 in `research/experiment_log.md` (population, base, bands, τ grid, horizon construction, development evaluation design, coverage gate, production fit 2020–2023), with nothing computed on outcomes. Then `R/probabilistic/pod_baseline.R` (`pd_`), `models/probabilistic/pod_baseline_v0.yml` (re-derived by the pipeline) + fingerprint, `validate_pod_table()`, prospective archive and manifest. Register check: `assert_family_seasons("distribution_stack", 2020:2023, "development")`; never touch 2024–2025.
