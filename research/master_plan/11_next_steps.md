# 11 — Recommended Next Steps

*This document gives the first concrete actions, why they come first, and implementation prompts for the next Claude Code sessions. Nothing here has been implemented: the only change this research made to the repository is adding this folder. The plan was revised after the adversarial review ([07](07_master_roadmap.md) §10).*

---

## 1. The first actions, in order

| Order | Action | When | Why now |
|---|---|---|---|
| **0** | **Step 0, owner action, no code: manual W6 runs.** Run `weekly_run.R` on **Thu Oct 15 at about 17:00 ET** (TNF kicks off 20:15 ET), and again on **Sat Oct 17 or early Sun Oct 18**, after Friday's final injury reports and before inactives. Each time run `status.R`, then commit and **push before kickoff**. Repeat every week until F0 is running. | **This week** | <ul><li>A missed post-report run cannot be recovered.</li><li>No W5 run happened after Friday's reports, so the injury lineages never acted on W5.</li></ul> |
| 1 | **F0. Prospective operations hardening** | Before the W7 slate | <ul><li>A dispatcher keyed to kickoff times covers Thursday, Saturday, international, Sunday and Monday slates.</li><li>All-position captures (`valuation_run.R --capture`) start R3's data, since `weekly_run.R` captures WR only.</li><li>The status file flags missing post-report runs.</li></ul> |
| 2 | **F1. Prospective analysis addendum (E16)**, together with **R3's outcome-free analysis plan (E17)** | **Before any 2026 outcome is scored** (W5 is complete but unscored) | <ul><li>Time-critical: an honest addendum can't be written after looking at outcomes.</li><li>It adds:<ul><li>an MDE table at σ_w × {1, 1.5};</li><li>W5 as a structural-zero week;</li><li>a pre-registered pooled 2026+2027 secondary;</li><li>a late-push rule;</li><li>blind monitoring.</li></ul></li></ul> |
| 3 | **D0. Lineup helpers** | Weeks 7–8 | <ul><li>Cannot lower expected points; useful immediately.</li><li>Uses a fixed designation prior (Q ≈ 0.71, D ≈ 0.07) for non-WR players until P1 exists.</li></ul> |
| 4 | **F3-lite. League state** (in the existing single request) | Weeks 7–8 | <ul><li>Schedule (`mMatchup`), standings, rules, trade deadline, top-half bonus, FAAB flag, and ESPN's `playoffPct`.</li><li>Whether S0 is worth building depends on `deadlineDate`.</li></ul> |
| 5 | **F5. Decision ledger** (records only; outcomes sealed) | Weeks 8–9 | Records every recommendation from now on without letting in-season outcomes shape the 2027 designs. |
| 6 | **F2-lite.** Base-R scoring, the contamination register and a point-in-time registry draft | Weeks 8–9 | <ul><li>CRPS, PIT, coverage and Brier need no new packages.</li><li>The register encodes the batched check allocations.</li><li>**Don't change `renv.lock` before R1.**</li></ul> |
| 7 | **P0. Baseline distributions (E18)** | Weeks 9–10 | <ul><li>F(y \| active, base), fit on 2020–23 active rows, combined by horizon.</li><li>The baseline P2 must beat.</li></ul> |
| 8 | **S0. Shadow league simulator (VL3)**, only if F3-lite shows **at least about 2 weeks before `deadlineDate`** | Weeks 10–11 | <ul><li>Approximate playoff, bye and title odds, matchup P(win), leverage, and ΔP for the `waivers` query.</li><li>Labelled shadow/unvalidated; inputs are early-week, so the odds are too sharp until R3.</li><li>If too late for the deadline, spend the effort on the 2027 S2 thin slice instead.</li></ul> |

**After the season (January 2027), in order:**
1. **R1:** score the 2026 tests and VE-P1.
2. **I1:** platform renv profile; the frozen-lineage runtime stays pinned through 2027.
3. **F2-full** and **F3-full** (O8).
4. **F4.**
5. **F6** (lineups and contested add/drop).
6. **P1 + R2:** injury batch, checked on 2019.
7. **P2, P3 (gated), P4:** distribution batch, checked on 2024.
8. **P5.**
9. **S2/D2 thin slice** by early April, then S1, S2 v1 and S3.
10. **D1–D5** and the **VL11** decision batch on 2025 replays, before the 2027 season.

See [07](07_master_roadmap.md) §1–2.

---

## 2. Decisions only the owner can make

These are listed, not asked. Each has a default that keeps the plan moving.

| # | Decision | Default if undecided |
|---|---|---|
| O1 | Enable scheduled pre-slate runs (Task Scheduler; local commits; the owner pushes)? (F0) | Dispatcher plus status file; the owner runs manually |
| O2 | Capture ESPN ADP and auction values in preseason 2027 (additional requests)? (D4) | Projections-only drafting, or league draft history if O8 allows |
| O3 | Capture other free projection sources weekly (terms vary)? (R4) | Not captured |
| O4 | Use the FantasyPros ECR archive via nflreadr (personal-use terms)? | Not used |
| O5 | Use public Sleeper leagues (non-commercial API), anonymised and local, for aggregate calibration and FAAB priors? | Not used |
| O6 | Accept RTools if a Stan model is ever justified? | Not needed; stay toolchain-free |
| O7 | Show S0's shadow odds in the local report during 2026? | Shown, with sensitivity bands and an "unvalidated, too sharp" label |
| **O8** | **ESPN request expansions beyond the existing cadence:** <ul><li>transactions and FAAB bids (`kona_league_communication`);</li><li>weekly lineups and box scores;</li><li>previous seasons (2018+);</li><li>league draft history (`mDraftDetail`);</li><li>K and D/ST slot ids in the valuation capture;</li><li>2018 QB/RB/TE week-of history.</li></ul> | **F3-lite only.** Adding a view to the existing single request is treated as within the current opt-in; additional requests or endpoints wait for the owner. |

---

## 3. Implementation prompts

**Guardrails.** Every prompt below assumes these, and each implementing session should quote them.

**Read first:** [07](07_master_roadmap.md) (the milestone's section), [05](05_modeling_strategy.md) §2.1 (horizons), §5–6 and §9 (register), [06](06_data_infrastructure.md) as cited, and the latest entries in `research/experiment_log.md` and `research/valuation_log.md`.

**Never modify:**
- frozen M1–M4 registries, fingerprints or prospective manifests;
- `models/valuation/ros_params_v1.yml`;
- V1/V2 outputs.

Write **new** functions instead of editing V1/V2 ones, and add bit-identity tests. An audit failure on a frozen artefact is logged in a new entry, never "fixed".

**Protocol:**
- Pre-register (log entry) and commit before computing any outcome-dependent result.
- **2026 outcomes are never development data.**
- Never backfill.
- Ledger and shadow outcomes stay sealed until the 2027 decision pre-registrations.
- Respect the register's batched allocations.

**Horizons:** historical ESPN week-of values are **late** (post-inactive) information.

**Runtime:** don't change the main `renv.lock` before R1. In-season code is base R. Re-run fingerprint checks after any change and confirm they stay "identical".

**Privacy:**
- The league id, cookies, team names and manager-level profiles never go in Git or chat output.
- ESPN and league data stay local; commit hashes and aliases only.
- Test fixtures are hand-written, never redacted real responses.
- Scripts never push.

**Windows:**
- Rscript is at `"C:/Program Files/R/R-4.5.1/bin/Rscript.exe"`.
- Write scratch R scripts with the Write tool (heredocs mangle backslashes) and put them in the git-ignored `tmp/`.
- Read archived parquet with `mmap = FALSE`.

**Quality:** testthat tests for every new function; `tar_make()` passes; docs updated in the same commit.

### Prompt F0: Prospective operations hardening

> Implement **F0** ([07](07_master_roadmap.md) §3).
>
> 1. Extend the existing `week_coverage()` and `injury_report_status()` in `R/live/ops.R`. Report, per upcoming game, whether an archived run exists after that team's final report and before about kickoff − 90 min (pre-inactive). Surface this in `scripts/status.R`.
> 2. Build a **dispatcher keyed to kickoff times** (not fixed weekdays). For each slate it computes run times:
>    - an early-week run;
>    - a post-report run at about kickoff − 2 h, the latest before inactives (this handles 09:30 ET international games and Saturday slates).
> 3. Create git-ignored `.cmd` wrappers with quoted absolute paths. Each wrapper:
>    - runs `weekly_run.R --commit` (local only);
>    - then runs `valuation_run.R --capture` (all positions; one ESPN request);
>    - then runs `status.R`;
>    - then writes a status file.
> 4. Document optional Task Scheduler registration, but **do not register tasks** unless the owner says so (O1). Scripts never push.
> 5. Add tests with synthetic manifests and schedules (including Saturday, international and holiday slates).
> 6. Append an "Automation" section to `docs/prospective_protocol.md` without changing its rules.

### Prompt F1 + R3 pre-registration: Prospective analysis addendum (E16) and outcome-free horizon plan (E17)

> Implement **F1** ([07](07_master_roadmap.md) §3). **Load no 2026 outcome.**
>
> 1. Write `R/evaluation/power.R::mde_table()` in base R, with tests. Compute σ_w (the SD of week-level paired MAE and MSE differences) from the *historical* comparison targets: M2 dev/holdout, M3 E7, M3b E10, M4 E13/E14. Report the MDE for H-M2, H-A, H-B, H-D and H-M4 at W ∈ {8, 10, 13, 14} and σ_w × {1, 1.5}.
> 2. Write log entry **E16**:
>    - the MDE table;
>    - W5 declared a structural-zero week for M3b/M4;
>    - secondary analyses: results by horizon (early-week vs post-report runs, from run times and injury-capture state); MSE alongside MAE; decision relevance (how often top-36 ordering changes);
>    - a **pre-registered fixed-sample pooled 2026+2027 analysis**, valid because the frozen-lineage runtime stays pinned through 2027;
>    - **blind** e-process monitoring, which gives optional stopping, not power, using the exact bound |Δabs-error| ≤ |Δprediction|;
>    - a **late-push rule**: runs whose manifest commit reached the remote after kickoff go to a sensitivity analysis;
>    - the statement that the primary tests and insufficiency rules are unchanged.
> 3. Write log entry **E17**, R3's outcome-free plan:
>    - revision variance Var(final − early) by position, band, lead time and status, using FFball's dated captures and ESPN's after-the-fact final **projections** only;
>    - a martingale check (correlation of successive revisions);
>    - the rule for adopting the spread-inflation table into PODs.
> 4. Commit. The owner pushes before any scoring.

### Prompt D0: Lineup helpers

> Implement **D0** ([07](07_master_roadmap.md) §4) with **new** functions and V1/V2 bit-identity tests.
>
> 1. `val_flex_slotting()` is pure post-processing after the allocator. Among equal-EV assignments, put the latest-kickoff eligible starter in each FLEX slot. Test that expected points never change.
> 2. Add a game-time plan. For each Questionable starter, report:
>    - P(active): M4 for WR; otherwise a **fixed prior** (Q ≈ 0.71, D ≈ 0.07 [Hutchison 2025]) recorded in a small YAML;
>    - the best pivot whose game kicks off after the starter's inactive announcement (about 90 min before his kickoff);
>    - whether such a pivot exists.
> 3. Add CLI `trade_analyzer.R lineup` and ledger rows (once F5 exists).
> 4. Tests: toy weeks with known answers; ESPN's lock-at-kickoff rule.

### Prompt F3-lite: League state in the existing request

> Implement **F3-lite** in `R/valuation/league_espn.R` (`lg_`). Make **no additional requests**: add `view=mMatchup` to the existing league GET.
>
> Parse:
> - `schedule[]`: `matchupPeriodId`, `home/away.teamId` (a missing away team means a bye), `totalPoints`, `winner`, `playoffTierType`;
> - `teams[]`: `record.overall.*`, `playoffSeed`, `rankCalculatedFinal`, and `currentSimulationResults.playoffPct` (store as an external comparator);
> - `settings.scheduleSettings.*` (`matchupPeriodCount`, `matchupPeriods`, `playoffTeamCount`, `playoffSeedingRule`, `playoffMatchupPeriodLength`, `divisions`);
> - `settings.scoringSettings.{matchupTieRule, playoffMatchupTieRule, scoringEnhancementType}`: flag `WIN_BONUS_TOP_HALF`;
> - `tradeSettings.deadlineDate`;
> - `draftSettings.keeperCount`;
> - `acquisitionSettings.*`;
> - team `waiverRank` and `transactionCounter.acquisitionBudgetSpent`.
>
> On the first live response, **print keys only**. Use hand-written JSON fixtures. Add invariant tests:
> - one game per team per period;
> - recomputed standings equal ESPN's seeds.
>
> Add a privacy grep test. Store snapshots write-once under the alias, with hash-only manifests. Report `deadlineDate` relative to today, since this decides S0.

### Prompt F5: Decision ledger (records only)

> Implement **F5**: `R/valuation/ledger.R` (`lg_ledger_*`).
>
> 1. Define a `decision_record` schema: id, type, alias, season, week, `as_of_utc`, input hashes, recommended action, alternatives with metrics, model versions, owner-action flag.
> 2. Store rows privately in `data/archive/decisions/`, with a hash-only `archive/decision_manifest.csv`. Add hooks in `trade_analyzer.R` and D0.
> 3. Define the **outcome of record** as stats after the Thursday stat-correction pull. Outcome joins are computed and stored, but **no regret or outcome report may be generated** until the 2027 decision pre-registrations (VL8–VL11) are committed. Enforce this with a guard flag.
> 4. Tests: schema, write-once behaviour, join, seal guard.

### Prompt F2-lite: Scoring, register and point-in-time registry (base R)

> Implement **F2-lite** in base R, with **no new packages and no `renv.lock` change**.
>
> 1. `R/evaluation/scoring_v2.R`: CRPS from quantile sets (piecewise-linear or pinball approximation, documented), randomised PIT, interval coverage, interval score, Brier with a binned reliability table. Add closed-form tests (normal CRPS against its analytic formula on dense quantiles; PIT uniformity on simulated calibrated forecasts).
> 2. `research/contamination_register.yml`, with the [05](05_modeling_strategy.md) §9 allocations:
>    - injury stack: check 2019;
>    - distribution stack: check 2024;
>    - decisions: check 2025 replays, with 2027 confirmatory;
>    - the VE1c touches;
>    - 2026 sealed.
>
>    Also `R/utils/contamination.R::assert_family_seasons()`.
> 3. A draft `config/pit_registry.yml` ([06](06_data_infrastructure.md) §5), with historical ESPN marked as late horizon.
> 4. A regression test reproducing `m2_holdout_comparisons` with the existing bootstrap. Confirm M1–M4 fingerprints stay identical.

### Prompt P0: Baseline outcome distributions (E18)

> First write and commit **E18**:
> - **Population:** QB/RB/WR/TE ESPN-projected player-weeks, **active rows only** (at least one offensive snap).
> - **Base:** a **new** rolling-origin per-position linear calibration of ESPN, refit weekly, MSE. None exists for QB/RB/TE.
> - **Residuals:** actual − base.
> - **Fixed bands:** 0–3, 3–6, 6–9, 9–12, 12–15, 15–20, 20+.
> - **Quantile levels:** τ ∈ {0.01, 0.05, 0.10, …, 0.95, 0.99}, with interpolation and a floor.
> - **Horizon construction:** POD_h = P(active | h) · F(y | active, base_h) ⊕ (1 − P(active | h))·δ₀. P(active | h) comes from M4 for WR and the fixed prior otherwise. Spread inflation comes from R3 when available.
> - **Development evaluation**, descriptive: 2020–2023 CRPS, PIT and coverage by position.
>
> **The production table is fit on 2020–2023 only.** Compute or view **no** diagnostic on 2024–2025.
>
> Implement `R/probabilistic/pod_baseline.R` (`pd_`) in base R, plus `models/probabilistic/pod_baseline_v0.yml` (re-derived by the pipeline) and a fingerprint. Add `validate_pod_table()`. Archive PODs prospectively from the freeze, with `archive/distribution_manifest.csv`.

### Prompt S0: Shadow league simulator (VL3; build only if ≥ about 2 weeks before `deadlineDate`)

> First write **VL3**:
> - σ_L by **simulation matching**. S0's own rest-of-season total SD, with its availability draws and P0 noise, is matched to the observed ROS residual SD on **2019–2023 only**.
> - log L ~ N(−σ²_L/2, σ²_L), so E[L] = 1.
> - Sensitivity bands: σ_L × {0.5, 1, 1.5}; noise × {0.8, 1.2}.
> - The archive is used for evaluation only, never for recalibration.
>
> Then implement `R/simulation/season_sim.R` (`sim_`) with `sim_compute_week(state, week, draws)`:
> - **Draws:** availability Bernoulli; P0 noise; level shocks; independence otherwise; 10,000 sims; L'Ecuyer-CMRG; common random numbers.
> - **Lineup evaluator:** a **new** one that chooses lineups on **decision values** and scores **realised** points (do not modify `val_lineup_value()`; bit-identity tests). Model the top-half bonus if F3 flags it.
> - **Outputs:** E[wins], P(playoffs), P(bye), P(title) and rank distributions; this week's P(win) and margin; weekly leverage; what-ifs; ΔP(playoffs) for adds (pairing with `waivers`); ESPN `playoffPct` alongside.
> - **Label:** "shadow / unvalidated; inputs are early-week, so odds are too sharp until R3".
> - **Tests:** invariants (Σ P(playoffs) = slots, Σ P(title) = 1), determinism, Monte Carlo SE ≤ 0.5 pp, separation of decision and realised values.
> - **Interfaces:** CLI `trade_analyzer.R odds`; ledger rows.

---

## 4. What not to start yet (and why)

| Not yet | Why |
|---|---|
| New WR mean models | Replicated nulls; R1 scores the existing lineages at season end |
| Full F2 inference stack and new packages | Wait for R1 and the platform profile; in-season work is base R |
| Trade engine v3 (D2) or P(win) lineups (D1) | Need calibrated distributions and season simulation. D1's full mode is gated by outcome-free triage. |
| Any analysis of 2026 outcomes | Sealed until the season-end R1 and the 2027 pre-registrations |
| R upgrade of the frozen-lineage runtime | Pinned through 2027 (pooled test validity) |
| Draft tools (D4) | Needed by August 2027 |
| Any parked idea ([05](05_modeling_strategy.md) §8) | Evidence against, or no evidence |

---

## 5. Critical review

An independent reviewer challenged the first draft and found five critical and nine important issues. All were accepted: the horizon mislabel, 2026 outcomes used as development data, adaptive reuse of check seasons, the decision lab's inference, and W6 protection, among others. The resolutions are in [07](07_master_roadmap.md) §10.
