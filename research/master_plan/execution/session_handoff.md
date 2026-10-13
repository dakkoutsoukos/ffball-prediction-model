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

## Exact next action

Implement F0 (see the tracker's F0 criteria): `R/live/dispatch.R` (slate plan, due logic, post-report coverage), `scripts/ops_dispatch.R`, wrapper generator, tests, protocol "Automation" section; commit; register the Task Scheduler task (O1 approved) and verify with a manual trigger before Thu 2026-10-15 21:15Z.
