# 07 — Master Development Roadmap

*The ordered plan for turning FFball from strong but separate models into an integrated fantasy-football
decision platform. The platform should predict player outcomes **as distributions at stated horizons**,
simulate the owner's league, optimise decisions, and keep testing whether its recommendations work.*

*Written 2026-10-13, during 2026 Week 6, and revised after an adversarial review (§10). It builds on
[03](03_current_system_assessment.md) (current state), [02](02_research_landscape.md) (evidence),
[05](05_modeling_strategy.md) (methods) and [06](06_data_infrastructure.md) (data). Priorities are justified
in [08](08_prioritization.md), the experiments behind each milestone are in [09](09_experiment_backlog.md),
and the first actions are in [11](11_next_steps.md).*

---

## 0. How to use this roadmap

- **Milestone ids** use new prefixes that never collide with existing names (M1–M4, V1–V2, E*, VE*, VL*):

  | Prefix | Track |
  |---|---|
  | **F** | Foundations and operations |
  | **P** | Probabilistic forecasting |
  | **S** | Simulation and valuation |
  | **D** | Decision engines |
  | **R** | Projection science |
  | **I** | Integration |
- **Every milestone is self-contained.** A future session implements one by reading its section here and the cited sections of 05, 06 and 09.
- **Log entries.** Pre-registrations go in `research/experiment_log.md` (projection, availability and distribution families) or `research/valuation_log.md` (simulation, valuation and decision families). Indicative ids, in the expected order of work (always use the next free id):

  | Log | Planned entries |
  |---|---|
  | Experiment log | E16 F1 · E17 R3 (outcome-free) · E18 P0 · E19 P1+R2 (injury stack) · E20 P2 · E21 P3 (if gated in) · E22 distribution-stack batch check |
  | Valuation log | VL3 S0 · VL4 P4 · VL5 S1 · VL6 S2 · VL7 S3 · VL8 D1 · VL9 D3 · VL10 D4 · VL11 decision-family batch check |
- **Never touched:**
  - frozen M1–M4 registries, fingerprints and prospective manifests;
  - `models/valuation/ros_params_v1.yml`;
  - V1/V2 methodology and outputs (protected by bit-identity tests whenever new code sits next to them).

  An audit failure on a frozen artefact is *logged*, never "fixed".
- **Binding conventions** ([05](05_modeling_strategy.md)):

  | Convention | Rule |
  |---|---|
  | Horizons | Historical ESPN values = **late** (post-inactive). Distributions = P(active \| h) × F(y \| active, base_h) + a horizon spread term. |
  | 2026 outcomes | Never development data. Shadow and ledger outcomes stay sealed until the 2027 decision pre-registrations are committed. |
  | Check seasons | Spent in **batches** (05 §9). |
  | Runtime | The frozen-lineage runtime (R 4.5.1 and the 2026-10-01 snapshot) is pinned through 2027. In-season builds use base R. |
- **Difficulty scale** (a session is roughly one focused Claude Code working session):

  | Size | Sessions |
  |---|---|
  | **S** | 1–2 |
  | **M** | 3–5 |
  | **L** | 6–10 |
  | **XL** | more than 10 |
- **Markers:** ★ foundational (unlocks several later milestones); ◇ optional.

---

## 1. Phases at a glance

| Phase | Window | Goal | Milestones |
|---|---|---|---|
| **0. Protect the evidence** | **Now** (W6 slate: TNF Thu Oct 15, Sunday Oct 18) → W7 | No more lost late-week runs. Make the 2026 record interpretable. | **Step 0** (owner, manual W6 runs), F0, F1 (+ the R3 outcome-free pre-registration) |
| **1. In-season essentials** | W7 → W14 (Oct–Dec 2026) | Cheap, certain helpers; league rules and schedule; a decision record; first distributions and (conditionally) shadow odds | D0, F3-lite, F5, F2-lite, P0, S0 (only if ≥ about 2 weeks remain before the trade deadline), R3 data accrual |
| **Season end** | Jan 2027 | Score the 2026 record; set up the platform runtime | R1; I1 (platform renv profile, modularisation); F2-full; F3-full (owner decision O8) |
| **2. Probabilistic core** | Jan → Mar 2027 | Availability, distributions, dynamics and scenarios, all checked in batches; the decision laboratory | F4★, F6★, P1+R2 (injury batch, check 2019), P2★, P3 (gated), P4★, P5★, distribution batch check (2024) |
| **3. Thin slice, then simulation and valuation v3** | Mar → May 2027 | An **end-to-end S2+D2 slice on P0-level inputs first**, then calibrated components swapped in | S2★ (thin → v1), D2-thin, S1, S3 |
| **4. Decision engines** | May → Aug 2027 (ready for the 2027 draft) | Lineup, trade, waiver/FAAB and draft engines; weekly briefing; decision batch check (2025 replays) | D1 (scoped), D2, D3, D4, D5, VL11 batch |
| **5. Projection science (parallel)** | Continuous | Narrow, pre-registered projection improvements; resilience | R2 (with P1), R3, R4–R7 |
| **6. Integration** | Continuous | Maintainability, dashboard, monitoring | I1, I2◇, I3 |

**Confirmatory evidence:** 2027 is the confirmatory season for every new family. Historical checks are one-time and batched.

---

## 2. Dependency graph

```
PHASE 0   Step 0 (owner: manual W6 Thu + Sat/Sun runs, push before kickoff)
          F0 ops (kickoff-keyed dispatcher; all-position captures) ──► R3 captures
          F1 addendum + E17 R3 outcome-free pre-reg ── before any 2026 scoring

PHASE 1   D0 lineup helpers (fixed designation prior)
          F3-lite league state (mMatchup in the existing request; parse mTeam/mSettings)
          F5 ledger (records only; outcomes sealed)
          F2-lite (base-R scoring + contamination register)
          P0 baseline POD (fit 2020–23) ──► S0 shadow odds (conditional on deadline timing)

JAN 2027  R1 scoring ─► I1 (platform profile; frozen runtime pinned) ─► F2-full, F3-full (O8)

PHASE 2   F4 frame ─┬─► P1 + R2 ── injury batch check (2019)
                    ├─► P2 ─► P3 (gated) ─┐
                    │        └─► P4 ──────┴─► distribution batch check (2024) ─► P5
                    └─► F6 decision lab v1 (lineups + contested add/drop)

PHASE 3   S2-thin + D2-thin on P0/S0 engine ─► S1 ─► S2 v1 ─► S3   (swap in P-stack as gates pass)

PHASE 4   D1 (scoped by triage) · D2 · D3 (FAAB gated on isUsingAcquisitionBudget) · D4 (by Aug) · D5
          VL11 decision batch check (2025 replays) before the season; 2027 prospective = confirmatory
```

---

## 3. Phase 0: Protect the evidence

### Step 0. Manual W6 runs (owner action; no code)

The W6 Thursday game kicks off **Thu Oct 15, 20:15 ET**; the Sunday slate is **Oct 18**. A missed post-report run cannot be recovered.

Per the README runbook:
1. Run `Rscript scripts/weekly_run.R` on **Thursday at about 17:00 ET** and again on **Saturday or early Sunday** (after Friday's final injury reports, before inactives).
2. Run `status.R`.
3. Commit and **push before kickoff**.

The same applies to every week until F0 lands.

### F0. Prospective operations hardening ★ (quick win)

| Field | Content |
|---|---|
| **Objective** | Every remaining 2026 slate gets an archived official run *after* each team's final injury report and *before* inactives and kickoff. All-position ESPN captures accrue for R3. Scripts never push. |
| **Research justification** | <ul><li>All archived W5 runs were made Mon 20:37Z – Tue 06:29Z (`archive/prediction_manifest.csv`), so M3b/M4 equalled calibrated ESPN for every W5 game (E15).</li><li>The 2026 tests are underpowered ([03](03_current_system_assessment.md) W5).</li><li>`weekly_run.R` snapshots **WR only** (L50), so the multi-time captures for all positions need `valuation_run.R --capture` too.</li></ul> |
| **Capabilities** | <ol><li>A **dispatcher keyed to kickoff times**, not fixed weekdays. It covers Thursday, Saturday (weeks 15–17), international (09:30 ET), Sunday and Monday slates. It schedules a standard run at about kickoff − 2 h (pre-inactive) after the final report, plus an early-week run.</li><li>Each scheduled run: `weekly_run.R --commit` (local commit only), then `valuation_run.R --capture` (all positions; this is also the R3 capture), then `status.R`.</li><li>Extends the existing `week_coverage()` and `injury_report_status()` (`R/live/ops.R` L63, L121) to flag any slate within 3 h of kickoff lacking a post-report run.</li><li>Notification is a status file only.</li></ol> |
| **Data requirements** | None new. ESPN requests stay at one capture per run (existing opt-in). |
| **Statistical methodology** | None. |
| **Technical approach** | <ul><li>Extend `R/live/ops.R`.</li><li>Git-ignored `scripts/ops/` `.cmd` wrappers with quoted absolute paths (the path has spaces).</li><li>Optional Windows Task Scheduler registration via `taskscheduleR`/`schtasks`, **only if the owner chooses** (O1).</li><li>Append an "Automation" section to `docs/prospective_protocol.md`; its rules are unchanged.</li></ul> |
| **Dependencies** | None |
| **Difficulty** | S |
| **Risks and limitations** | <ul><li>The PC must be on.</li><li>Cookie rotation (401).</li><li>Local commits still need the owner's **push before kickoff** for external tamper evidence (F1 states how late pushes are treated).</li></ul> |
| **Evaluation** | Weekly coverage table. |
| **Success criteria** | <ul><li>≥ 95% of remaining 2026 games have an archived post-report, pre-kickoff run.</li><li>0 scripted pushes; 0 runs on a dirty tree.</li><li>All-position captures at ≥ 2 times per week for ≥ 8 weeks.</li></ul> |
| **Expected impact** | Protects the only clean evidence stream and starts R3's data. |

### F1. Prospective analysis addendum (E16), bundled with R3's outcome-free pre-registration (E17)

| Field | Content |
|---|---|
| **Objective** | Make the 2026 results interpretable **without changing the pre-registered primary tests**. |
| **Research justification** | <ul><li>Power: 40–50% for two tests, about 35–40% for M4 vs M3b, assuming about 13 usable weeks ([03](03_current_system_assessment.md) W5). *Corrected by E16 (2026-10-13): about 25–35% for the injury families, see 03 W5.*</li><li>Week-level inference [Cameron et al. 2008].</li><li>MSE vs MAE [Gneiting 2011].</li><li>Anytime-valid monitoring [Choe & Ramdas 2024].</li></ul> |
| **Capabilities** | <ol><li>An **MDE table** for H-M2, H-A, H-B, H-D and H-M4 at W ∈ {8, 10, 13, 14} and σ_w × {1, 1.5}. σ_w comes from historical paired comparisons; prospective σ_w may be larger because pre-inactive zeros enlarge errors.</li><li>**W5 is declared a structural-zero week** for the injury lineages (identical predictions).</li><li>**Secondary analyses**, all pre-declared:<ul><li>results by horizon (early-week vs post-report runs);</li><li>MSE alongside MAE;</li><li>a **pre-registered fixed-sample pooled 2026+2027 analysis**, valid because the frozen-lineage runtime is pinned through 2027;</li><li>**blind** e-process monitoring (no outcome-driven action), using the exact predictable bound for absolute-error differences;</li><li>decision relevance: how often a frozen rule changes top-36 ordering.</li></ul></li><li>**Late-push rule:** runs whose manifest commit reached the remote only after kickoff are reported in a sensitivity analysis. The primary analysis follows the protocol (`predicted_at` < kickoff, hash-verified).</li><li>Primary tests and insufficiency rules are textually unchanged.</li></ol> |
| **Data requirements** | Existing historical comparison targets only. **No 2026 outcome.** |
| **Statistical methodology** | MDE ≈ (t₀.₉₇₅,W−1 + t₀.₈₀,W−1)·σ_w/√W. |
| **Technical approach** | <ul><li>`R/evaluation/power.R::mde_table()` (base R) with tests.</li><li>E16, plus E17 (R3's outcome-free analysis plan, §8), in `research/experiment_log.md`.</li><li>Committed and pushed before any scoring code reads a 2026 outcome.</li></ul> |
| **Dependencies** | None. **Must precede any 2026 scoring**, including informal looks. |
| **Difficulty** | S |
| **Risks** | Peeking (mitigated by committing first). |
| **Success criteria** | E16 and E17 pushed before any 2026 outcome is loaded by a scoring routine. |
| **Expected impact** | An informative, honest reading of 2026; a valid cross-season design. |

---

## 4. Phase 1: In-season essentials (W7–W14, 2026)

### D0. Lineup helpers (quick win)

| Field | Content |
|---|---|
| **Objective** | Two improvements that never cost expected points: (1) put the **latest-kickoff** eligible player in FLEX; (2) a **game-time decision plan**. |
| **Research justification** | <ul><li>Practitioner consensus on late-FLEX option value.</li><li>Value-of-information logic.</li><li>Published availability anchors (Questionable about 71% play, Doubtful about 7%) [Hutchison 2025].</li></ul> |
| **Capabilities** | <ul><li>**Slotting:** among equal-EV assignments, the latest-kickoff eligible starter goes in FLEX.</li><li>**Game-time plan:** for each Questionable starter, P(active), the best pivot whose game starts *after* the starter's inactive announcement (about 90 min before his kickoff), and whether one exists.</li><li>Ledger rows (F5).</li></ul> |
| **Data requirements** | Kickoffs (nflverse schedule). P(active): M4 for WR; otherwise a **fixed designation prior** until P1 exists. VE1's A(log L) is *not* used: it models having a stat line, by level. |
| **Statistical methodology** | Expectations only. |
| **Technical approach** | <ul><li>A **new** pure function `val_flex_slotting()` after the allocator, plus a game-time-plan function.</li><li>V1/V2 bit-identity tests.</li><li>CLI `trade_analyzer.R lineup`.</li></ul> |
| **Dependencies** | None (F5 optional). |
| **Difficulty** | S |
| **Risks** | ESPN locks each player at his own kickoff; international and Saturday slates. |
| **Evaluation** | Tests: slotting never changes EV; toy weeks with known answers. |
| **Success criteria** | Tests pass. The weekly lineup output includes slotting and the game-time plan. |
| **Expected impact** | Small, certain gains, this season. |

### F3. League state v2 (F3-lite in season; F3-full after owner decision O8) ★

| Field | Content |
|---|---|
| **Objective** | Capture what simulation and decisions need about the owner's league. |
| **Research justification** | <ul><li>Win and playoff odds need the schedule and rules.</li><li>FAAB needs settings.</li><li>A real-league decision benchmark needs lineups.</li><li>Views verified in client code ([06](06_data_infrastructure.md) §4, [10](10_sources.md) §V).</li></ul> |
| **Capabilities, F3-lite** (inside the **existing single request**) | <ul><li>Add `view=mMatchup` → `schedule` (matchup periods, home/away, scores, `winner`, `playoffTierType`).</li><li>Parse what `mTeam`/`mSettings` already return:<ul><li>**standings:** `record.overall.*`, `playoffSeed`, `rankCalculatedFinal`, and **ESPN's own `currentSimulationResults.playoffPct`**, logged as an external baseline;</li><li>**rules:** `scheduleSettings.*` (playoff count, round lengths, seeding), `scoringSettings.matchupTieRule`, `playoffMatchupTieRule`, **`scoringEnhancementType` (top-half bonus)**, `tradeSettings.deadlineDate`, `draftSettings.keeperCount`;</li><li>**FAAB:** `acquisitionSettings.*`, `waiverRank`, `transactionCounter.acquisitionBudgetSpent`.</li></ul></li></ul> |
| **Capabilities, F3-full** (additional requests; owner decision O8) | <ul><li>Transactions via `kona_league_communication` (the bid is `from` on message type 180; 2019+) or `mTransactions2`.</li><li>Weekly starting lineups via `mMatchupScore`+`mBoxscore` with `scoringPeriodId` (for the real-league decision benchmark and manager profiles).</li><li>Previous seasons (2018+).</li><li>Draft history (`mDraftDetail`, for D4).</li><li>K and D/ST slot ids in the valuation capture.</li></ul> |
| **Data requirements** | ESPN private league (existing cookies). |
| **Statistical methodology** | Manager profiles (lineup efficiency, activity), shrunk to league means. **Profiles never appear in committed logs, even under the alias.** |
| **Technical approach** | <ul><li>Extend `R/valuation/league_espn.R` (`lg_`).</li><li>**Hand-written** synthetic JSON fixtures, never redacted real responses.</li><li>Write-once alias snapshots; hash-only manifests; a privacy grep test.</li><li>`lg_synthetic_league()` must not ship ESPN-derived rosters.</li><li>Inspect keys only on the first live response.</li></ul> |
| **Dependencies** | None (lite); O8 (full). |
| **Difficulty** | S (lite), M (full) |
| **Risks** | Undocumented fields; multi-week playoff rounds; divisions; losing FAAB bids possibly not exposed. |
| **Evaluation** | <ul><li>Invariants: one game per team per period.</li><li>Recomputed standings equal ESPN's seeds.</li></ul> |
| **Success criteria** | <ul><li>Schedule and rules parsed.</li><li>Standings reproduce ESPN's.</li><li>Top-half bonus detected.</li><li>`deadlineDate` known (decides whether S0 is worth building this season).</li><li>0 private values in Git.</li></ul> |
| **Expected impact** | Unlocks S0, S2, D2 and D3; the real-league benchmark. |

### F5. Decision ledger ★ (quick win; records only in 2026)

| Field | Content |
|---|---|
| **Objective** | Archive every recommendation with its information state so decision quality can be measured, **without** in-season outcome analysis shaping later designs. |
| **Research justification** | <ul><li>Forecast quality ≠ value [Murphy 1993].</li><li>No platform evaluates decisions prospectively.</li><li>2026 outcomes must not become development data ([05](05_modeling_strategy.md) §1).</li></ul> |
| **Capabilities** | <ul><li>A `decision_record` schema: id, type, alias, season, week, `as_of_utc`, input hashes, recommendation, alternatives and metrics, model versions, owner-action flag.</li><li>An **outcome of record**, defined as stats after the Thursday stat-correction pull.</li><li>Outcome joins are computed but **sealed**: no regret or outcome report is generated until the 2027 decision-family pre-registrations (VL8–VL11) are committed.</li></ul> |
| **Technical approach** | `R/valuation/ledger.R`; private rows; hash-only `archive/decision_manifest.csv`; hooks in `trade_analyzer.R`, D0, S0. |
| **Dependencies** | None. |
| **Difficulty** | S |
| **Risks** | Private content, so it stays local. |
| **Success criteria** | ≥ 95% of recommendations ledgered; outcome join automated; no outcome report produced before unsealing. |
| **Expected impact** | Turns FFball into a platform that tests whether its advice works, with uncontaminated evidence. |

### F2. Evaluation framework (F2-lite in season; F2-full after R1) ★

| Field | Content |
|---|---|
| **Objective** | Tested scoring, inference and decision metrics; the **contamination register**; extended leakage audits. |
| **Research justification** | [Gneiting & Raftery 2007; Gneiting 2011; Czado et al. 2009; Dimitriadis et al. 2021; Kapoor & Narayanan 2023; Murphy 1993]. |
| **Capabilities, F2-lite** (base R, no new packages, in season) | <ul><li>CRPS from quantiles; randomised PIT; coverage; interval score; Brier with a binned reliability table.</li><li>`mde_table()`.</li><li>`research/contamination_register.yml` plus `assert_family_seasons()`, with the 05 §9 allocations and the VE1c touches recorded.</li><li>A draft `config/pit_registry.yml` (historical ESPN = **late horizon**).</li></ul> |
| **Capabilities, F2-full** (after R1, in the platform renv profile) | <ul><li>CORP (`reliabilitydiag`), Murphy diagrams.</li><li>Sensitivity inference (block bootstrap, HLN, season random effect).</li><li>MCS; e-process monitoring (`seqcomp`).</li><li>Decision metrics (regret, flip rate).</li><li>Leakage audits L1.2 / L1.3 / L1.4 / L2.</li></ul> |
| **Statistical methodology** | **One primary procedure per family** (the week-clustered paired bootstrap); the rest are sensitivities only ([05](05_modeling_strategy.md) §5). |
| **Technical approach** | <ul><li>`R/evaluation/scoring_v2.R`, `inference_v2.R`, `decision_metrics.R`; `R/utils/contamination.R`.</li><li>Tests with closed-form answers.</li><li>A regression test reproducing `m2_holdout_comparisons` exactly.</li><li>**No change to the main `renv.lock` before R1.**</li></ul> |
| **Dependencies** | None. |
| **Difficulty** | S (lite), M (full) |
| **Risks** | Package additions shifting shared dependencies. Hence the platform profile, and the frozen runtime stays pinned. |
| **Success criteria** | <ul><li>Tests pass; the M2 comparison is reproduced.</li><li>The register is enforced.</li><li>Leakage audits implemented. **Any failure on a frozen lineage is logged (new entry), never fixed.**</li><li>M1–M4 fingerprints identical.</li></ul> |
| **Expected impact** | Honest evaluation for every later milestone. |

### P0. Baseline outcome distributions (E18)

| Field | Content |
|---|---|
| **Objective** | A simple, pre-registered weekly distribution for every QB/RB/WR/TE player-week. It powers S0 and is **the baseline P2 must beat**. |
| **Research justification** | <ul><li>An assumption-light baseline ([05](05_modeling_strategy.md) §4.3).</li><li>Heavy tails (WR MAE/SD ≈ 0.68–0.75).</li><li>No calibrated fantasy distributions exist anywhere.</li></ul> |
| **Capabilities** | A POD table (quantiles τ ∈ {0.01, 0.05, …, 0.95, 0.99}, mean, `p_active`) built per horizon: POD_h = P(active \| h) · F(y \| active, base) + a horizon spread term. |
| **Data requirements** | ESPN week-of history (QB/RB/TE 2019–2025; WR 2018–2025) plus nflverse-scored actuals and snap data for "active". |
| **Statistical methodology** | <ul><li>**New** rolling-origin per-position linear calibration (refit weekly, MSE). None exists for QB/RB/TE.</li><li>Empirical quantiles of (actual − base) on **active rows only**, by position × fixed bands (0–3, 3–6, 6–9, 9–12, 12–15, 15–20, 20+).</li><li>Interpolation and a floor.</li><li>P(active \| h): M4 for WR; the fixed prior otherwise.</li><li>Spread inflation for early-week runs from R3 when available, else none, with S0's sharpness flagged.</li><li>**Production table fit on 2020–2023 only** (2019 warm-up). **No diagnostic on 2024–2025 is computed or viewed.**</li></ul> |
| **Technical approach** | `R/probabilistic/pod_baseline.R` (`pd_`), base R; `models/probabilistic/pod_baseline_v0.yml` plus a fingerprint; `validate_pod_table()`; prospective POD archive and manifest from the freeze. |
| **Dependencies** | F2-lite. |
| **Difficulty** | S–M |
| **Risks** | Coarse; horizon spread unknown until R3. |
| **Evaluation** | Development 2020–2023, descriptive: CRPS, PIT, coverage by position. |
| **Success criteria** | Development coverage meets the [05](05_modeling_strategy.md) §6 gate (descriptive); frozen and fingerprinted; archived from the freeze. |
| **Expected impact** | First calibrated uncertainty; unlocks S0. |

### S0. In-season league simulator v0 (shadow; VL3) (conditional)

| Field | Content |
|---|---|
| **Objective** | Shadow-mode playoff, bye and title odds, matchup P(win) and weekly leverage for 2026, and ΔP for the existing `waivers` query. **Build only if F3-lite shows at least about 2 weeks before `deadlineDate`.** Otherwise put the effort into the 2027 S2 thin slice. |
| **Research justification** | <ul><li>No platform publishes a calibrated method.</li><li>nflseedR contract.</li><li>Level shocks are needed to avoid overconfidence.</li><li>Decision-time lineups.</li></ul> |
| **Capabilities** | <ul><li>Per team: E[wins], P(playoffs), P(bye), P(title), rank distribution.</li><li>P(win) for every matchup this week; the owner's weekly leverage.</li><li>A what-if API.</li><li>ΔP(playoffs) for free-agent adds (pairs with `waivers`).</li><li>ESPN `playoffPct` shown alongside.</li></ul> |
| **Data requirements** | F3-lite; the latest league-format valuation run; P0; K/D/ST v0. |
| **Statistical methodology** | <ul><li>Availability: Bernoulli draws.</li><li>Weekly noise: P0.</li><li>**Level shock:** log L ~ N(−σ²_L/2, σ²_L), so the mean is preserved. σ_L is set in VL3 by **simulation matching**: S0's own ROS-total SD, with its availability draws and P0 noise, matched to the observed ROS SD on **2019–2023 only**.</li><li>Otherwise independent; 10,000 sims; common random numbers.</li><li>Top-half bonus if enabled.</li><li>Sensitivity bands: σ_L × {0.5, 1, 1.5}; noise × {0.8, 1.2}.</li></ul> |
| **Technical approach** | <ul><li>`R/simulation/season_sim.R` (`sim_`) with `sim_compute_week()`.</li><li>**New** lineup evaluator separating decision and realised values; `val_lineup_value()` untouched, with V1/V2 bit-identity tests.</li><li>CLI `trade_analyzer.R odds`; ledger rows; local report labelled "shadow / unvalidated".</li></ul> |
| **Dependencies** | F3-lite, P0, F5. |
| **Difficulty** | M |
| **Risks and limitations** | <ul><li>**Inputs are early-week valuation captures.** Until R3's spread term exists, odds are too sharp; this is stated on every output.</li><li>Independence; approximate K/D/ST.</li><li>Real-league calibration is untestable (descriptive only).</li></ul> |
| **Evaluation** | <ul><li>Invariants: Σ P(playoffs) = slots; Σ P(title) = 1.</li><li>Monte Carlo SE.</li><li>**Archive is evaluation-only; never used to recalibrate.**</li></ul> |
| **Success criteria** | Invariants hold; Monte Carlo SE ≤ 0.5 pp; runtime ≤ 10 min; archived before each week's first kickoff from its freeze. |
| **Expected impact** | 2026 trade-deadline and playoff decisions move from points to (approximate) wins. Seeds the thin slice. |

---

## 5. Season end and Phase 2: Probabilistic core (Jan–Mar 2027)

### R1. M5: score the 2026 prospective record and VE-P1 (season end)

As already recommended.
- Score H-M2, H-A, H-B, H-D and H-M4 exactly as pre-registered, plus the F1 secondaries.
- Study inactivity at our forecast time from archived captures (outcome analysis *after* season end).
- Optional `late_pregame`.
- Score **VE-P1**.

**Difficulty:** M. **Success:** reported exactly as pre-registered ("insufficient" when applicable).

### I1. Platform runtime and modularisation (Jan 2027, after R1)

| Field | Content |
|---|---|
| **Objective** | Scale the codebase without touching frozen lineages. |
| **Capabilities** | <ul><li>A **separate renv profile** (R 4.6 with a new dated snapshot) for the new tracks.</li><li>The **frozen-lineage runtime stays R 4.5.1 with the 2026-10-01 snapshot through 2027**, which keeps the pooled test valid.</li><li>`_targets.R` composed from per-track factories ([06](06_data_infrastructure.md) §7).</li><li>`config/pit_registry.yml` enforced.</li></ul> |
| **Dependencies** | R1. |
| **Difficulty** | M |
| **Risks** | Two runtimes add operational care: a documented script per runtime. |
| **Success criteria** | <ul><li>Weekly runs keep using the pinned runtime.</li><li>New tracks build in their profile.</li><li>Fingerprints identical.</li></ul> |

### F4. Position-general historical frame ★

| Field | Content |
|---|---|
| **Objective** | One point-in-time player-week table, 2019–2025, for QB/RB/WR/TE plus K and D/ST. |
| **Capabilities** | `player_week_all` with: <ul><li>ids, kickoff, ESPN projection and components;</li><li>a **rolling-origin per-position calibrated base** (MSE);</li><li>actuals in league scoring;</li><li>**active = played at least one offensive snap**;</li><li>pregame-valid injury features (2017–2024);</li><li>pregame role ranks;</li><li>as-of lines (2021–2025);</li><li>point-in-time flags (historical ESPN = late horizon);</li><li>K and D/ST rows (nflverse scoring under league rules; size M).</li></ul> |
| **Technical approach** | New `R/data/player_week_all.R` (`player_week.R` untouched); corruption leakage test extended; scoring validation by position. |
| **Dependencies** | F2. |
| **Difficulty** | M |
| **Risks** | Some ESPN components may be missing for QB/RB/TE; D/ST scoring complexity; 2025 injuries untimed. |
| **Success criteria** | <ul><li>Scoring match ≥ 99.9% per position.</li><li>WR rows reproduce the existing frame exactly.</li><li>Tests pass.</li></ul> |
| **Expected impact** | The substrate for P1–P4 and F6. |

### F6. Decision laboratory v1 (historical league replay) ★

| Field | Content |
|---|---|
| **Objective** | Evaluate **weekly lineup and contested add/drop policies** on realised NFL points with out-of-sample forecasts, to answer whether better forecasts produce better decisions. |
| **Research justification** | <ul><li>Decisions must be judged on realised outcomes.</li><li>No point-in-time history exists for private leagues.</li></ul> |
| **Capabilities** | <ul><li>**Synthetic leagues** (8/10/12 teams): drafts by a **simple projection- or ADP-style rule** (not the V1 re-draft, which inherits the VE3 bench flaw and takes about 200 s per run).</li><li>A weekly loop with a lineup policy and a **contested** add/drop policy: opponents also claim, by their own projections and waiver order. Realised scores; standings.</li><li>**Trades are out of scope** for the lab.</li><li>**Information set:**<ul><li>week-t ESPN values become available only at kickoff (late horizon);</li><li>Tuesday decisions use only data through week t−1 and ROS by extrapolation (L_avg4), because historical as-of future-week projections don't exist (VE0).</li></ul></li><li>**Outcome-free triage tools:** flip rates and model-implied gains, computed before any check is spent.</li></ul> |
| **Data requirements** | F4 plus rolling-origin forecasts. |
| **Statistical methodology** | <ul><li>Paired policy comparisons on identical leagues and outcomes.</li><li>**Week-level metrics** (lineup points, regret) with season-blocked, week-clustered inference.</li><li>**Season-level metrics** (wins, playoffs, titles) are **descriptive only**; effective n is about the number of seasons.</li><li>Availability policies are evaluated on development seasons only (2025 lacks injury timestamps), and are confirmed prospectively in 2027.</li></ul> |
| **Technical approach** | <ul><li>`R/lab/` (`lab_`).</li><li>Policies are `policy(state, info_at_t)`, behind an **information firewall** asserted by tests.</li><li>Dynamic branching; crew workers.</li></ul> |
| **Dependencies** | F2, F4. |
| **Difficulty** | L |
| **Risks** | <ul><li>Synthetic opponents.</li><li>Pseudo-replication: inference clusters by season-week.</li><li>Draft simplicity.</li></ul> |
| **Evaluation** | <ul><li>Determinism.</li><li>Firewall tests (planted future data refused).</li><li>Toy seasons.</li></ul> |
| **Success criteria** | <ul><li>Full development replay of 2020–2023 with 20 leagues per season completes in ≤ 2 h.</li><li>Firewall tests pass.</li><li>The triage report (X8, X9) is produced before VL11.</li></ul> |
| **Expected impact** | An objective, out-of-sample testbed for lineup and waiver policies. |

**Complement: the real-league decision benchmark** (F3-full, prospective). Each week, compare FFball's ex-ante lineup with each of the 8 managers' actual lineups, using the realised points of both. This uses real rosters and real opponents with no synthetic assumptions. With the owner's consent, the comparison extends back through league history (2018+). Results are sealed under the same rule as F5.

### P1 + R2. Injury stack: availability v2 and RB/TE/QB rules (E19; one batch check on 2019)

| Field | Content |
|---|---|
| **Objective** | <ul><li>**P1:** calibrated P(active \| h) for every position at the post-report horizon. The early horizon is built from designation transitions; the late horizon is known.</li><li>**R2:** test whether designation and practice effects on calibrated ESPN generalise to RB/TE/QB.</li></ul> |
| **Research justification** | <ul><li>FFball's only replicated edge (E10, E14).</li><li>Published play rates [Hutchison 2025].</li><li>Practitioner Q/D output effects for RB/TE/QB [Raybon 2018].</li></ul> |
| **Capabilities** | <ul><li>A `p_active` provider column.</li><li>New lineage(s) `m6_*` for RB/TE/QB adjustments (registry, fingerprints, prospective from freeze).</li></ul> |
| **Data requirements** | Injury reports 2017–2024; snaps (outcome); F4; FFball's 2026 captures, *designations only*, for the early-horizon transition matrix. |
| **Statistical methodology** | <ul><li>**P1:** rate table (baseline) vs logistic GLMM, with a COVID-list sensitivity.</li><li>**R2:** the M4 template (halved effects; ≤ 4 candidates per position group; **MSE primary**, MAE reported; MDE computed on MSE first).</li><li>**One batch check on 2019** for P1 and R2 together, with Holm across both primaries.</li><li>The 2019 calibration warms up in season (weeks 1–4 excluded) because QB/RB/TE ESPN history starts in 2019. A 2018 fetch is owner option O8.</li><li>WR reported separately (contaminated).</li><li>No 2024 check (reserved for the distribution stack).</li></ul> |
| **Technical approach** | `R/probabilistic/availability_v2.R`; `R/models/m6_*.R`; registries; fingerprints. |
| **Dependencies** | F2, F4. |
| **Difficulty** | M |
| **Risks** | Small TE/QB samples; ESPN may already price effects. |
| **Evaluation** | <ul><li>P1: Brier, log loss, reliability.</li><li>R2: ΔMSE vs calibrated ESPN by position.</li></ul> |
| **Success criteria** | <ul><li>**P1:** 2019 pooled RB/TE/QB Brier skill CI excludes 0 (Holm); slope criteria per [05](05_modeling_strategy.md) §6.</li><li>**R2:** development pooled ΔMSE CI below 0 and 2019 ΔMSE < 0. A prospective record follows in 2027.</li></ul> |
| **Expected impact** | Better game-time decisions, start/sit and P(win); small mean gains for listed RB/TE/QB. |

### P2. Calibrated outcome distributions v1 (E20) ★

| Field | Content |
|---|---|
| **Objective** | Calibrated, sharp F(y \| active, base, x), combined by horizon into PODs, beating P0 and IDR on CRPS. |
| **Research justification** | EMOS [Gneiting et al. 2005]; IDR [Henzi et al. 2021]; conformal methods [Gibbs & Candès 2021]; the industry-wide calibration gap. |
| **Capabilities** | POD tables at every horizon; spread covariates; boom/bust probabilities. |
| **Statistical methodology** | <ul><li>Candidates C1–C3 ([05](05_modeling_strategy.md) §4.3); baseline C0 = P0. No compound model.</li><li>A closed covariate list.</li><li>Development selection by CRPS with the coverage gate and a 0.5% tie band.</li><li>Then the **distribution-stack batch check on 2024 (E22)**.</li></ul> |
| **Technical approach** | `R/probabilistic/pod_v1.R`; registry `prob_pod_v1.yml` plus a fingerprint; prospective archive; `validate_pod_table()`. |
| **Dependencies** | P1, F4, F2. |
| **Difficulty** | L |
| **Risks** | Tail misfit; family choice; overfitting (closed list). |
| **Evaluation** | CRPS, PIT, coverage, MCB/DSC/UNC, threshold-weighted CRPS, by position and band. |
| **Success criteria** | <ul><li>On 2024: ΔCRPS vs P0 below 0 (CI) and not worse than IDR.</li><li>Coverage gate passed ([05](05_modeling_strategy.md) §6).</li><li>Frozen and archived.</li></ul> |
| **Expected impact** | Core differentiator. |

### P3. Dependence model (E21; **gated**)

| Field | Content |
|---|---|
| **Gate** | Build only if, on development seasons, independence mis-calibrates lineup totals (PIT of random legal lineups outside the coverage gate). Otherwise **record the null** and use independence in P5. |
| **Objective** | Correlated joint outcomes (team and game factors) that calibrate lineup totals. |
| **Research justification** | QB–WR1 ≈ +0.31 and QB–TE ≈ +0.27 unconditional [Huntington 2026]; copula precedent [McHale & Scarf 2011]. |
| **Methodology** | <ul><li>Normal scores of PIT values.</li><li>Candidates: independence; team factor; team plus game factors; a shrunk role-pair matrix.</li><li>Batch-checked with P2 (2024).</li></ul> |
| **Difficulty** | M (if built) |
| **Success criteria** | On 2024, lineup-total ΔCRPS CI below 0 against independence, with coverage in the gate. |
| **Expected impact** | Calibrated odds for stacked rosters, if needed. |

### P4. Season dynamics (VL4) ★

| Field | Content |
|---|---|
| **Objective** | Decompose and simulate rest-of-season uncertainty: level shock, weekly noise, attrition, plus learning modelled on ESPN's revision dynamics. |
| **Research justification** | <ul><li>VE1c: ROS-total SD is about 45–53% of the forecast. This is a total, not level uncertainty alone.</li><li>VE3's hypothesis that missing level uncertainty causes QB hoarding.</li><li>EVBD [Stuart 2013].</li></ul> |
| **Capabilities** | σ_L by position and band; attrition hazards; an **ESPN revision-response model** (how next-week projections react to realised residuals; identifiable from historical week-of values); ROS PODs. |
| **Statistical methodology** | <ul><li>log L ~ N(−σ²/2, σ²).</li><li>σ_L by **simulation matching** on 2019–2023, with availability and noise drawn separately.</li><li>Discrete-time hazard.</li><li>First diagnostic X2 (residual autocorrelation).</li><li>Batch-checked with P2 on 2024.</li></ul> |
| **Technical approach** | `R/probabilistic/season_dynamics.R`; `models/probabilistic/season_dyn_v1.yml`. |
| **Dependencies** | P2, F4. |
| **Difficulty** | M |
| **Success criteria** | On 2024: ROS coverage within the gate; CRPS skill vs VE1-normal CI below 0. |
| **Expected impact** | Bench and upside value; realistic playoff odds; tests VE3's hypothesis (S3). |

### P5. Scenario engine v1 ★

| Field | Content |
|---|---|
| **Objective** | One engine producing joint draws for every downstream tool, with lineups chosen at decision time. |
| **Capabilities** | `scenario_set` (active, realised points, decision values); seeds and hashes; policy hooks; optional parquet persistence. |
| **Methodology** | [05](05_modeling_strategy.md) §4.7: mean-1 level shocks; horizon PODs; copula only if P3 passed. |
| **Technical approach** | `R/simulation/scenarios.R`; chunked L'Ecuyer-CMRG; vectorised R; tests (mean preservation, correlation recovery, common-random-number invariance, hindsight-vs-decision gap on toy rosters). |
| **Dependencies** | P1, P2, P4 (P3 optional). The S0 engine stays in service until P5 passes. |
| **Difficulty** | L |
| **Success criteria** | 600 × 14 × 5,000 in ≤ 5 min (chunked); invariants pass; deterministic for a fixed seed. |
| **Expected impact** | The shared foundation behind every simulation and decision. |

---

## 6. Phase 3: Thin slice, then simulation and valuation v3 (Mar–May 2027)

**Thin slice first.** By early April 2027, build **S2-thin + D2-thin** on the S0 engine and P0 inputs:
- the season simulator on the real schedule and rules;
- trade re-scoring of ΔP(playoffs/title) for both teams;
- the partner-lens frontier.

Calibrated components (P2, P4, P5) are then swapped in **behind the same interfaces** as they pass their gates. One failed gate cannot stall the 2027 decision engines.

### S1. Matchup win probability v1 (VL5)

| Field | Content |
|---|---|
| **Objective** | Matchup P(win) and margin distributions, with realistic opponent lineup forecasts. |
| **Methodology** | <ul><li>Simulation from P5 against the normal-approximation baseline.</li><li>Opponents: projection-optimal lineups, adjusted by F3 profiles.</li><li>Top-half bonus term if enabled.</li></ul> |
| **Evaluation** | <ul><li>F6 replays: week-level matchups, clustered by week.</li><li>Real league: descriptive only (about 56 matchups per season).</li></ul> |
| **Success criteria** | <ul><li>Non-inferior to the normal approximation (upper CI of ΔBrier ≤ +0.005).</li><li>Slope criteria per [05](05_modeling_strategy.md) §6 on replays.</li><li>Otherwise ship the normal approximation.</li></ul> |
| **Dependencies** | P5, F3, F6. |
| **Difficulty** | M |

### S2. Season and playoff simulator (thin → v1; VL6) ★

| Field | Content |
|---|---|
| **Objective** | E[wins], P(playoffs), P(bye), P(title), rank distributions and what-ifs for any league state. |
| **Capabilities** | <ul><li>Exact league rules (tiebreakers, multi-week rounds, byes, divisions).</li><li>All-play and schedule luck.</li><li>**ESPN `playoffPct` logged as the external baseline**, recalibrated once enough seasons accrue.</li><li>A ΔP(title) decomposition into regular-season wins, seeding/bye and playoff-week points.</li></ul> |
| **Evaluation** | <ul><li>Season-level calibration is **descriptive** (replays and real league).</li><li>Rule-reproduction tests.</li><li>Week-k P(playoffs) reliability across replay leagues is reported with season-blocked CIs, as estimation only.</li></ul> |
| **Success criteria** | <ul><li>Rules reproduced exactly; invariants pass.</li><li>Calibration estimates reported with honest CIs.</li><li>Prospective comparison with ESPN's `playoffPct` logged in 2027.</li></ul> |
| **Dependencies** | F3, S0 engine (thin); P5, S1 (v1). |
| **Difficulty** | M |

### S3. Valuation v3 (VL7)

| Field | Content |
|---|---|
| **Objective** | EVOR, wins added and ΔP(playoffs/title) values, plus a roster risk report. V1/V2 stay unchanged as references. |
| **Methodology** | <ul><li>**Pre-registered hypothesis:** with level uncertainty and learning, the V1 fixed-point re-draft converges, and QBs rostered are within ±3 of the proportional pool. This tests VE3's hypothesis.</li><li>Which value metric best predicts realised lineup-point gain from an add, measured in the F6 development replays with week-level outcomes.</li></ul> |
| **Dependencies** | P4, P5, S2, F6. |
| **Difficulty** | L |
| **Success criteria** | <ul><li>Hypothesis reported either way.</li><li>Primary display metric selected by the pre-registered rule.</li><li>V1/V2 bit-identical.</li></ul> |

---

## 7. Phase 4: Decision engines (May–Aug 2027)

### D1. Lineup engine v1 (VL8), scoped by triage

| Field | Content |
|---|---|
| **Objective** | EV lineups with D0 slotting, a **late-window conditional P(win)** module, and decision confidence. A full pre-kickoff P(win) mode is added **only if** outcome-free triage in F6 shows ≥ 5% flips *and* a model-implied mean ΔP(win) ≥ 0.005. |
| **Research justification** | The only direct measurement found 0/208 flips [alhart2015 2026]; late-window leverage (arithmetic). |
| **Data requirements** | Live box scores for the late window (F3-full). These are additional ESPN requests, an owner decision (O8). |
| **Evaluation** | <ul><li>Triage (flip rates, model-implied ΔP) is outcome-free.</li><li>The VL11 batch on 2025 replays.</li><li>2027 prospective, via the ledger.</li></ul> |
| **Success criteria** | Triage reported; kill rule applied; late-window value estimated with CI. |
| **Dependencies** | S1, P5, F5, F6. |
| **Difficulty** | M |

### D2. Trade engine v3

| Field | Content |
|---|---|
| **Objective** | Find and evaluate trades by both teams' ΔP(playoffs/title), with a realistic view of what the partner perceives. |
| **Capabilities** | <ul><li>Two-stage search: the existing ΔU screen, then common-random-number re-scoring of the top K.</li><li>A **frontier of own gain vs partner-lens gain** (raw ESPN posted projections and generic values; λ sweep).</li><li>Nash product as a fairness summary only.</li><li>Buy-low / sell-high signals.</li><li>The ΔP(title) decomposition.</li><li>An optional league trade-fairness monitor (other teams' trades, for veto votes).</li><li>Ledger rows.</li></ul> |
| **Evaluation** | <ul><li>No lab evaluation (trades excluded from F6).</li><li>Model-implied ΔU vs ΔP divergence analysis, which is outcome-free.</li><li>Prospective ledger (descriptive, sealed until VL11).</li><li>The partner-lens check (X12) on the league's **2026+** trades only, since as-of reconstruction before 2026 is impossible.</li></ul> |
| **Success criteria** | <ul><li>Top-K re-score ≤ 10 min.</li><li>Divergence analysis reported.</li><li>Every recommendation explained from model numbers.</li></ul> |
| **Dependencies** | S2 (thin first), S3, F3, F5. |
| **Difficulty** | L |

### D3. Waiver, free-agent and FAAB assistant (VL9)

| Field | Content |
|---|---|
| **Objective** | A free-agent board (ΔU, ΔP(playoffs), k-week lookahead), drop advice, streaming plan, and — **only if `isUsingAcquisitionBudget`** — FAAB bids. |
| **Methodology** | <ul><li>**FAAB bid** b* = argmax_b P(win at b)·(v − λ_F·b): v in ΔP units; λ_F the shadow price of FAAB in ΔP per dollar, declining over the season.</li><li>Competitor-bid priors from public data, updated with league history (F3-full).</li><li>Streaming policies tested in the F6 replays with **contested** claims.</li></ul> |
| **Evaluation** | <ul><li>F6: streaming vs hold (development; VL11 on 2025).</li><li>FAAB calibration only if league bid history allows.</li></ul> |
| **Success criteria** | <ul><li>Streaming recommended only if the replay gain CI excludes 0.</li><li>FAAB guidance states its assumptions.</li></ul> |
| **Dependencies** | S2, S3, F3, F6. |
| **Difficulty** | M–L |

### D4. Draft and keeper assistant (VL10; by late Aug 2027)

| Field | Content |
|---|---|
| **Objective** | Live draft recommendations maximising E[wins] or P(playoffs) at week 0. |
| **Methodology** | <ul><li>ADP survival: a two-piece normal recalibrated to ESPN 8-team drafts using the **league's own draft history** (`mDraftDetail`, O8) and preseason ADP captures (O2).</li><li>Monte Carlo opponents (ADP + noise + need + herding).</li><li>The S2 objective.</li><li>Keeper valuation only if `keeperCount` > 0.</li></ul> |
| **Evaluation** | Mock drafts (labelled simulation evidence); prospective availability calibration after the draft. |
| **Dependencies** | S2, S3, O2/O8 captures. |
| **Difficulty** | L |

### D5. Weekly intelligence briefing

| Field | Content |
|---|---|
| **Objective** | One local report before each slate that integrates everything. |
| **Capabilities** | <ul><li>Lineup and game-time plan; P(win); odds and leverage.</li><li>Waiver board and FAAB bids; trade frontier; roster risk.</li><li>A model-health panel.</li><li>**Decision robustness flags:** a recommendation is "fragile" if it flips under the pre-declared alternative settings.</li><li>Explanations from model numbers only.</li><li>Every recommendation ledgered.</li></ul> |
| **Dependencies** | D1–D3, F5, I3. |
| **Difficulty** | M |
| **Success criteria** | Produced for ≥ 90% of 2027 weeks before first kickoff. |

### VL11. Decision-family batch check (before the 2027 season)

All decision experiments (X8, X9, X10, X16, X23) are pre-registered **together**, then run **once** on the **2025 replays**:
- Holm correction across their primaries.
- Policies that need injury timestamps are excluded on 2025.
- After this, 2025 is contaminated for decisions.
- **2027 prospective results are the only confirmatory evidence for decisions.**

---

## 8. Phase 5: Projection science (parallel track)

| id | Objective | Justification | Method and protocol | Dependencies | Difficulty | Success |
|---|---|---|---|---|---|---|
| **R2** | RB/TE/QB availability rules | See the injury stack (§5) | Batch with P1 (E19) | F4 | M | §5 |
| **R3** Forecast-horizon study (**outcome-free**, E17) | Horizon spread terms and horizon calibration | Only 54–72% of Wed/Thu ESPN captures equalled final values (three Wayback captures); waiver and trade decisions happen early in the week | <ul><li>Revision variance Var(final − early) by position and band, from FFball's 2026 captures plus ESPN's after-the-fact final **projections**.</li><li>A martingale check (correlation of successive revisions).</li><li>**No 2026 outcomes.**</li></ul> | F0 | S–M | Spread-inflation table with CIs, adopted into P0/P2 PODs by pre-registered rule |
| **R4** (◇, owner decision O3) | Multi-source capture and averaging | The only mean-improvement route with outside evidence | Capture-only in 2026–27; a pre-registered prospective test (MSE) later | O3 | M | ≥ 90% capture coverage; test run |
| **R5** | As-of market context | Variance and correlation covariates | Inside the P2/P3 closed lists (2021–2025 lines) | F4 | S | Reported within P2/P3 |
| **R6** (◇) | ESPN-independent fallback | Resilience | Top-down component model; target parity with `m2_no_espn` (MSE) | F4 | L | Pipeline runs with ESPN disabled |
| **R7** (◇) | Usage reliability and first-read share | Shrinkage constants; weak claim test | <ul><li>Reliability: descriptive, 2017–2025.</li><li>First-read share: development 2023–2024, check 2025, prospective 2027.</li></ul> | F4 | M | Reliability table; test result |

---

## 9. Phase 6: Integration

| id | Objective | When | Success |
|---|---|---|---|
| **I1** | Platform runtime and modularisation (§5) | Jan 2027 | Pinned frozen runtime; fingerprints identical |
| **I2◇** | Local dashboard (Quarto or Shiny on 127.0.0.1) | After D5 | Nothing private leaves the machine |
| **I3** | Monitoring and alerting | With D5 | Alerts for calibration drift (blind e-process), data freshness, ESPN 401, run coverage, Monte Carlo SE |

---

## 10. Critical review (Stage 8): findings and how the plan changed

An independent reviewer read documents 01–11 and the relevant repository files (README, protocol, logs, manifests, `simulation.R`, `league_espn.R`, configs). It verified the repository facts:
- code and test counts;
- `simulation.R` L39–42 drawing `(u < A) * lvl`;
- the four ESPN views requested;
- W5 run times;
- the VE1c figures;
- the power arithmetic.

It then raised five critical and nine important issues. All were accepted. How each was resolved:

| # | Finding | Resolution |
|---|---|---|
| C1 | **Horizon mislabel.** Historical ESPN values are post-inactive, so labelling them "post-report" leaks game-day information and double-counts zero mass. | <ul><li>Historical ESPN = **late** horizon (06 §5).</li><li>POD = P(active \| h) · F(y \| active, base_h) + a horizon spread term, fit on active rows (05 §2.1).</li><li>S0's sharpness from early-week inputs is disclosed.</li></ul> |
| C2 | **2026 outcomes used as development** (R3, pre-report P1, S0 recalibration, ledger reports) | <ul><li>R3 made **outcome-free** (revision variance).</li><li>Early-horizon P(active) built from designation transitions.</li><li>S0 archive evaluation-only.</li><li>Ledger and benchmark outcomes **sealed** until the 2027 decision pre-registrations.</li></ul> |
| C3 | **Check seasons reused adaptively across nested families** | Batched checks with Holm: <ul><li>injury stack on **2019**;</li><li>distribution stack on **2024**;</li><li>decision family on **2025 replays**.</li></ul>2027 is confirmatory. P0 is fit on 2020–23. VE1c touches recorded in the register. |
| C4 | **Decision-lab inference and information set invalid** | <ul><li>F6 v1 scoped to lineups plus contested add/drop with simple drafts.</li><li>Trades removed.</li><li>Season-level metrics descriptive.</li><li>Information set defined (ESPN at kickoff; no historical as-of future weeks).</li><li>Availability policies on development only.</li><li>Outcome-free triage before spending checks.</li><li>Runtime target made realistic.</li></ul> |
| C5 | **W6 unprotected; F0 incomplete** (WR-only captures; push timing) | <ul><li>**Step 0** (manual W6 runs).</li><li>F0 dispatcher keyed to kickoff times, with all-position captures.</li><li>F1 late-push rule.</li><li>First steps reordered (11 §1).</li></ul> |
| I6 | Level-shock mean bias; attrition double-counted | log L ~ N(−σ²/2, σ²); σ_L by simulation matching on 2019–2023 with availability drawn separately; 03 wording corrected |
| I7 | Untestable or inconsistent success criteria | Estimation-first conventions (05 §6): clustered-CI coverage gate with Holm; explicit non-inferiority margins; real-league calibration descriptive; one slope rule everywhere |
| I8 | Power framed optimistically | E-values = optional stopping, not power. Fixed-sample pooled 2026+2027 secondary; MDE at σ_w × {1, 1.5}; W5 structural zero; MSE MDE for R2. |
| I9 | Pooling conflicts with the R upgrade | Frozen-lineage runtime pinned through 2027; platform profile for new tracks; no lockfile change before R1 |
| I10 | Audits presuppose passing; V1 code modified | Failures logged, never fixed; new functions plus bit-identity tests (S0, D0) |
| I11 | Data gaps (K/DST, 2019 calibration, 2025 injuries, pre-2026 trades, request expansion, availability prior) | Owner option O8 for K/DST slots, 2018 QB/RB/TE history, draft history and other new requests. Fixed published availability prior. X12 restricted to 2026+. |
| I12 | FAAB and trade objectives mis-specified | b* = argmax P(win at b)·(v − λ_F b), gated on FAAB; trade frontier instead of a Nash-product "acceptance" |
| I13 | Id collisions and numbering | Catalog ids prefixed OA–OF; log ids re-sequenced; R7 and X1 windows fixed |
| I14 | Overbuilding and a serial chain | One primary inference procedure per family; compound model dropped from P2; P3 gated; D1 full mode gated; trades out of the lab; **thin S2+D2 slice first** |

**Overlooked opportunities that the review added:**
1. Outcome-free triage.
2. A real-league decision benchmark.
3. An ESPN revision-dynamics model as the learning mechanism.
4. ESPN K/DST projections (O8).
5. League draft history (O8).
6. ESPN `playoffPct` as the baseline to beat.
7. The ΔP(title) decomposition for explanations.
8. ΔP for the existing `waivers` query in 2026.

**Kept unchanged** (the reviewer endorsed these):
- the borrow-the-mean strategy and the parked list;
- protocol continuity;
- decision-time lineups and common random numbers;
- the nflseedR contract;
- MSE for new mean families with CRPS, PIT and CORP for distributions;
- the privacy practice.

---

## 11. Platform-level success measures (end of the 2027 season)

Estimation-first, per [05](05_modeling_strategy.md) §6.

| Dimension | Measure | Target |
|---|---|---|
| Forecast calibration | Prospective 2027 PIT and 50/80/90% coverage by position | Coverage gate passed (clustered CI overlaps ±3 pp; Holm) |
| Probability calibration | P(active) and matchup P(win): pooled prospective plus replay reliability | Slope CI includes 1, point estimate in [0.8, 1.2]. P(playoffs) and P(title): descriptive. |
| Decision quality | Lineup and waiver policy values (replays VL11; 2027 prospective; real-league benchmark) | Estimated with CIs; kill rules applied; no claim beyond the evidence |
| Accountability | Ledger coverage; hashes pushed before kickoff | ≥ 95%; 100% |
| Science | 2026 tests scored as pre-registered; R2 lineages with a 2027 record; pooled 2026+2027 analysis run | Done |
| Reliability | Weekly runs and briefing produced | ≥ 90% of weeks |

---

## 12. Final self-check (the brief's closing questions)

**1. What important applications might be overlooked?**
- *Added during this check:*
  - decision robustness flags (D5);
  - a league trade-fairness monitor (D2, optional);
  - the real-league decision benchmark (F6 complement);
  - ESPN `playoffPct` as the baseline to beat.
- *Out of scope:* DFS and best-ball play, IDP, commissioner tooling.
- *Conditional on league format:* dynasty, keeper and auction tools.

**2. Which methods from other fields are used?**
- Weather post-processing (EMOS, IDR); conformal prediction;
- copulas and factor models (gated);
- survival and frailty models;
- forecast reconciliation;
- sequential testing (for monitoring);
- value of information;
- auction and bargaining theory;
- simulation with rollout policies;
- revision-dynamics modelling (forecast evaluation).

Rejected: RL, bandits, play-level simulation, LLM news, Kelly sizing.

**3. Which current assumptions are challenged?**
- MAE for mean forecasts.
- Independent outcomes.
- Expectation-only value.
- Per-draw lineups once score noise exists.
- Free unlimited streaming.
- **Final-pregame (post-inactive) history applied to early-week decisions.**
- One-season verdicts.
- Season-stratified bootstraps for new-season claims.

**4. Which features actually improve decisions?**

| Rating | Features |
|---|---|
| Evidence-backed | Calibration; availability; wins-based trade evaluation (theory); late-FLEX slotting (logic) |
| Likely small | Pre-kickoff P(win) lineups |
| Unproven | FAAB shading, streaming, partner-lens perception |
| Not useful | Matchup, weather, efficiency metrics |

F6 and the real-league benchmark measure the uncertain ones.

**5. What would a professional team add?**
- Information timing as a first-class variable.
- Decision ledgers and policy backtests.
- Opponent modelling.
- Monte Carlo error control and common random numbers.
- Champion/challenger for policies.
- Model-risk robustness flags.
- Power planning.
- Outcome-free triage before spending evidence.

**6. What makes this better than a collection of tools?**
- One scenario set feeds every tool, so their numbers agree.
- League-specific context throughout.
- Prospectively verified calibration.
- A ledger that shows whether advice helped.

**7. Which foundations unlock the most?** F2, F3, P2/P4, P5, S2 and F6. Directly or transitively, 18 of the other 26 milestones depend on them.
