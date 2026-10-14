# Session handoff

*Exact instructions for resuming execution in a new Claude Code session. Update at the end of every
substantial work segment.*

Last updated: 2026-10-13 (session 1, Phase 2 under way: F4 done, F6 and E19 in progress).

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

## Outcome distributions (P0, frozen)

`read_pod_table()` → frozen `pod_baseline_v0` table. `pd_quantiles(position, base, table)` gives F(y | active, base) quantiles on `POD_TAU`; `pd_pods()` gives PODs with p_active. The dispatcher archives current-week PODs after each capture (`scripts/pod_archive.R`; commit `archive/distribution_manifest.csv`). Never edit the YAML; a change is `pod_baseline_v1` with a new pre-registration. Write frozen files with LF endings (X-013).

## League odds (S0)

`Rscript scripts/league_refresh.R` then `Rscript scripts/trade_analyzer.R odds [--add X --drop Y]`. Frozen parameters: `models/simulation/s0_params_v0.yml` (σ_L). Engine: `sim_league_odds(m, state, ...)`. Shadow and unvalidated; every run is ledgered.

## Horizon study (R3)

`Rscript scripts/horizon_study.R`. The dispatcher also runs it after each early-week run. Outcome-free (ESPN source 1 only). Results go to `data/archive/horizon_study/`; commit `archive/horizon_manifest.csv`. The adoption table fires per position × lead bin at 4 target weeks (E17a).

## Phase 2 tools built in session 1 (continued)

- **F4 frame** (`R/data/player_week_all.R`, target `player_week_all`). QB/RB/WR/TE, 2019–2025, with ESPN components, P0's rolling base, injury features, roles, as-of lines and point-in-time flags. Docs: `docs/player_week_all.md`. Checks: `pwa_scoring`, `pwa_wr_check`, `pwa_leakage`, `pwa_injury_leakage`.
- **K/DST** (`R/data/kdst_week.R`). Rule-free stats from nflverse. League points come from the private snapshot's scoring items at build time (`kdst_rules`). Not ESPN-validated: blocker B-001.
- **F6 decision lab** (`R/lab/`, pre-registration LAB1 and LAB1a in `research/valuation_log.md`).
  - `lab_info()` is the firewall: policies only ever see truncated matrices.
  - Targets: `lab_replays` (2020–2023, 20 leagues per season, arms A–D), `lab_triage_x8`, `lab_triage_x9`.
  - `lab_dev` is **gated**: it refuses to build until "### LAB1 result 1" (the triage) is in the valuation log.
- **Injury stack** (E19 in `research/experiment_log.md`). P1 is `R/probabilistic/availability_v2.R`; R2 is `R/models/m6_candidates.R`.
  - Development targets: `p1_frame_dev`, `p1_dev_scored`, `p1_dev_covid`, `p1_dev`, `m6_rows`, `m6_params_derived`, `m6_dev`, `m6_mde_2019`.
  - The 2019 check (`e19_check`) is **gated** in two ways: E19b must be in the experiment log, and `research/m6_candidate_params.yml` (committed) must equal a fresh derivation.
- **Running new targets:** `tar_make(names = c(...), shortcut = TRUE)`. A brand-new upstream target must be in `names` too, otherwise shortcut cannot bootstrap it. Never run two `tar_make` processes at once.

## Exact next action

1. **F6:**
   - Read `lab_triage_x8` and `lab_triage_x9`, and record them as "### LAB1 result 1" in the valuation log (outcome-free). Commit.
   - Then build `lab_dev` and record "LAB1 result 2" (development, descriptive).
   - Update the tracker. F6 is COMPLETED when the replay ran in ≤ 2 h, firewall tests pass and the triage report exists.
2. **P1 + R2 (E19):**
   - Build the development targets and write E19b: P1 development scores, R2 parameters (write `research/m6_candidate_params.yml` from `m6_params_derived` plus `selected`, as YAML with LF line endings), the selection and the MDE. Commit **before** the check.
   - Then `tar_make(names = "e19_check")` **once**. Record E19c, add the 2019 entry to `spent_checks` in the contamination register, and freeze the outcomes (an m6 lineage if R2 passes; the P1 provider).
3. Then P2 (E20) → P3 (gated) → P4 → the E22 batch → P5 → the S2/D2 thin slice → S1/S2/S3 → D1–D5 → VL11 → I3, I2, R5–R7, in dependency order.
4. **In season:**
   - Check `data/ops/status.txt` after slates.
   - Keep the tree clean, and no untracked files under `R/` or `scripts/`, around slate windows: Thu ~17:15–18:45 ET, Sun ~10:00–11:30 ET, Mon ~17:15–18:45 ET.
   - Remind the owner to push.
   - When R3's adoption fires (about early November), wire it into S0 behind a flag (VL3 addendum).
5. **Season end (January 2027):** R1 (E3/E6/E9/E14 and E16 S1–S8), then I1, F2-full, F3-full (O8), and B-001 (K/DST ESPN match) if the owner approves O8 or the 2026 league data are unsealed.
