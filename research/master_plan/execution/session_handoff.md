# Session handoff

*Exact instructions for resuming execution in a new Claude Code session. Update at the end of every
substantial work segment.*

Last updated: 2026-10-14 (session 2: Phases 2–4 largely built; see "Exact next action").

## Read first (in this order)

1. This file.
2. [progress.md](progress.md) and [milestone_tracker.md](milestone_tracker.md): what is done and what is next.
3. [decisions.md](decisions.md): owner decisions and execution decisions (do not re-ask O1, O8-`mMatchup`, captures).
4. The active milestone's section in [07_master_roadmap.md](../07_master_roadmap.md) and its prompt in [11_next_steps.md](../11_next_steps.md) §3.
5. The latest entries of `research/experiment_log.md` (E-entries) and `research/valuation_log.md` (VL-entries,
   LAB1, VL3–VL13).

## Owner's standing instruction (2026-10-14)

Continue autonomously through the whole roadmap in dependency order. Do not stop at phase ends, checkpoints or after
several commits; stop only for a genuine blocker that needs the owner's approval, or at a context limit (then save
this handoff). Keep every safeguard, test requirement, approval boundary and integrity rule.

## Non-negotiable guardrails (quote them in every session)

- Never modify frozen M1–M4 registries, fingerprints, prospective manifests, `models/valuation/ros_params_v1.yml`,
  frozen YAMLs (`pod_baseline_v0`, `s0_params_v0`, `p1_availability_v2`) or V1/V2 outputs. New functions instead of
  edits to V1/V2 ones, with bit-identity tests. An audit failure on a frozen artefact (or a V2 invariant failure) is
  logged, never fixed.
- 2026 outcomes are never development data. Ledger and shadow outcomes stay sealed until the 2027 decision
  pre-registrations. Pre-register (log entry, committed) before computing anything outcome-dependent. Never backfill.
  Spent checks (`spent_checks` in the contamination register) are never re-run.
- Historical ESPN week-of values are **late-horizon** (post-inactive) information.
- No `renv.lock` change before R1. In-season code uses base R plus lockfile packages (crew is not in the lockfile:
  runs are sequential; mgcv replaces lme4, X-018).
- Privacy: the league id, cookies, team names, rosters and manager profiles never go in Git or chat output. Never open
  `config/local.yml` (code uses `lg_credentials()`). On the real league, report aggregates only: validate with
  aggregate-only scratch scripts, never by printing CLI output (CLI commands print names). Fixtures are hand-written.
  Commit hashes and the alias only. `tmp/privacy_scan.R` before every commit.
- No new ESPN request types without the owner (O8 items pending: transactions/FAAB, box scores, past seasons, draft
  history, K/DST slots, 2018 history). No paid data; do not ask about it or about off-machine backups.
- Scripts never push. Only the owner pushes. Commits go on `main` (decision X-002); every commit must be safe to publish.
- Scheduled runs (F0) refuse to run on a dirty tree or with untracked files under `R/` or `scripts/`: **keep the tree
  clean around slate windows** (Thu ~17:15–18:45 ET, Sun ~10:00–11:30 ET, Mon ~17:15–18:45 ET; the first real window
  was Thu 2026-10-15 ~21:15Z). Ledger runs append to `archive/decision_manifest.csv`: commit it.
- Windows tooling: Rscript at `"C:/Program Files/R/R-4.5.1/bin/Rscript.exe"`. Bash heredocs and `Rscript -e` strings
  mangle backslashes and long `-e` strings can crash Rscript: write R code containing `\\` or long edits with the
  Write/Edit tools or a scratch script in `tmp/`. Read archived parquet with `mmap = FALSE`. Inside `tibble()`, earlier
  columns shadow local variables: compute vectors first. Foreground `sleep` is blocked: run long jobs with
  `run_in_background` and keep working.

## Commands

- Tests: `"C:/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "testthat::test_dir('tests/testthat')"`.
- Status and I3 health panel: `Rscript scripts/status.R`.
- Targets: `targets::tar_make(names = c(...), shortcut = TRUE)`; a brand-new upstream target must be in `names`;
  never two `tar_make` processes at once. The "object 'have' not found" lines come from tar_quarto scanning the V2
  report: ignore them.
- Owner-facing commands (all SHADOW; run by the owner after `scripts/league_refresh.R`):
  `trade_analyzer.R lineup | odds | rescore --b T | faboard | signals | values3`, and `scripts/briefing.R` (D5).

## Operations now running (F0)

- Task Scheduler task `FFball_dispatch` fires hourly at :05 (owner logged on) → `scripts/ops_dispatch.R`. Check
  `data/ops/status.txt`, `data/ops/dispatch_log.csv`, `data/ops/logs/`; `Rscript scripts/ops_setup.R --status`.
- Self-test: create `data/ops/self_test.flag`, then `Rscript scripts/ops_setup.R --run-now`.
- The dispatcher also refreshes the R3 horizon study and the P0 POD archive after each capture.

## What exists (built this execution)

- **Phase 0/1:** F0 dispatcher, F1 (E16/E17), D0 lineup helpers, F3-lite league state, F5 ledger, F2-lite scoring and
  contamination register, P0 (`pod_baseline_v0`), S0 shadow simulator (`s0_params_v0`), R3 tooling.
- **F4** frame `player_week_all` (QB/RB/WR/TE 2019–2025) and K/DST tables (B-001 blocks the ESPN match).
- **F6 lab** `R/lab/` (LAB1/1a/1b): arms A–E (E = X16 QB streaming, VL9), replays 2020–2023, triage, `lab_dev`.
- **P1** frozen provider (rate table R0, `p1_availability_v2.yml`), live via `p1_live_availability()` in D0/S0/D3/S3.
  R2 failed (no m6). P2 failed (P0 stays). P3 gate null (independence). P4 failed. E22 not run (X-020). P5 engine.
- **S1** S1-sim adopted (VL5). **S2** thin slice + v1 resolver + week-k calibration (VL6).
- **D1** (VL8): late-window value null → informational only. **D3** (VL9): `faboard` (board, drop advice, streaming
  view; `R/simulation/fa_board.R`). **S3** (VL7): X10a `R/valuation/v3_redraft.R`, X10b `R/lab/lab_x10b.R`, live
  `values3` (`R/simulation/values_v3.R`). **D2 v3** (VL12): decomposition, Nash, signals, explanations, X11
  (`R/simulation/trade_v3.R`); candidates failing V2's invariants are excluded and counted. **I3** (VL13):
  `R/live/monitor.R` + status panel. **D5** (VL13): `scripts/briefing.R`, `R/live/briefing.R`.

## Exact next action

(See the tracker for statuses; this list is the queue at the time of writing.)

1. Read `lab_stream` (X16) once the lab rebuild finishes; check that arms A–D results are unchanged against
   `tmp/lab_snapshot_before_armE.rds` (lab_triage_x8/x9, lab_dev, s1_eval, s2_summary, lw_result, p3_gate_result).
   Record "VL9 result"; set `D3_STREAMING_RECOMMENDED` only if the CI excludes 0 in streaming's favour.
2. `tar_make(names = c("x10a_weekly_file", "x10a_result", "x10b_rows", "x10b_result"), shortcut = TRUE)`; record
   "VL7 result" (X10a supported or not; X10b selection by the pre-registered rule; note the timing run saw one
   iteration-1 QB count). S3 complete if the live display exists (it does) and V1/V2 tests pass.
3. X11 (`tmp/x11_run.R`, output in `data/archive/league_analysis/x11_*.rds`, aggregates in `tmp/x11_run.log`):
   record "VL12 result" (aggregates only, with the count of V2-invariant exclusions as a finding). D2 complete.
4. D5 briefing validation (`tmp/briefing_run.log`, console is name-free): record; commit
   `archive/decision_manifest.csv`.
5. VL11: pre-register the decision-family batch on 2025 replays (X8, X9-late window, X10b, X16, X23; Holm), with the
   2025 waiver calibration on 2019–2023 only (2024 is excluded for decisions). Run once; add to `spent_checks`.
6. D4 (VL10, projections-only draft assistant under the O2/O8 defaults), then R5/R6/R7/I2 dispositions.
7. In season: keep the tree clean around slate windows, remind the owner to push, and when R3's adoption fires
   (about early November) wire it into S0 behind a flag (VL3 addendum).
8. Season end (January 2027): R1, then I1, F2-full, F3-full (O8), B-001.
