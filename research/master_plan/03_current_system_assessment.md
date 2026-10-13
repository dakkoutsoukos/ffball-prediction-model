# 03 — Current System Assessment

*Written 2026-10-13 (2026 Week 6), at commit `e0cfe70`, from a full read of the repository's
documentation, logs, configuration, registries, manifests and the relevant code. Research only:
nothing in the repository was changed apart from adding this folder.*

**Labels.**
- **[V]** = verified in the repository (file, log entry or code, cited).
- **[H]** = hypothesis or inference that still needs checking.
- **[C]** = calculation from documented numbers, with its assumptions stated.

---

## 1. What FFball is today, in one paragraph

FFball is a reproducible R research platform for fantasy football. It has two tracks, and both are
built on strict point-in-time discipline. The first is a **projection research programme** for
weekly WR full-PPR points, in milestones M1–M4. The second is a **valuation track**:
- V1 is rest-of-season (ROS) player value in a generic league.
- V2 is a league-specific trade analyzer for the owner's private ESPN league.

The projection programme has a clear scientific result, and it is mostly negative:
- ESPN's final pregame projection, linearly recalibrated, is very hard to beat.
- The only repeatable gains are small injury-availability adjustments for listed WRs.

The valuation track is economically sophisticated, with exact FLEX-aware lineup allocation,
roster-aware packages and before/after team utility. However, it is **expectation-only**: it
has no score distributions, no player correlations, no win or playoff probabilities, and no
decision-quality evaluation.

---

## 2. Architecture and environment [V]

| Component | State | Where |
|---|---|---|
| Language and runtime | R 4.5.1 on Windows. `Rscript` is not on PATH. renv lockfile pinned to a dated Posit Package Manager binary snapshot (2026-10-01), so no C++ toolchain is needed today. | `README.md`, `renv.lock`, `DESCRIPTION` |
| Orchestration | One `targets` DAG with 158 `tar_target` definitions plus 6 `tar_quarto` reports, covering milestones M1–M4 and valuation. `config` has cue "always", so `tar_outdated()` is noisy, although `tar_make()` skips correctly. | `_targets.R` (476 lines) |
| Storage | Immutable raw files with JSON provenance sidecars (`data/raw/`), Parquet in the targets store, DuckDB for play-by-play aggregation and ad-hoc SQL, write-once archives (`data/archive/`, `data/snapshots/`). Committed append-only SHA-256 manifests (`archive/*.csv`). | `docs/data_provenance.md` |
| Modelling stack | tidymodels (parsnip/recipes/workflows), glmnet, xgboost, base `lm`. No Bayesian, GAM, quantile or copula tooling yet. | `DESCRIPTION` |
| Code size | About 8,060 lines of R: data 1,149; features 951; models 979; evaluation 786; live 694; valuation 3,372; utils 130. Plus 369 lines of scripts and 2,206 lines of tests (17 test files plus a helper; 156 `test_that` blocks). | line counts |
| Interfaces | CLI scripts: `weekly_run.R`, `status.R`, `valuation_run.R`, `league_refresh.R`, `trade_analyzer.R` (queries: snapshot, analyze, fair, target, sell, needs, rankings, waivers, values). Quarto HTML reports, rendered locally and git-ignored when they contain ESPN data. | `scripts/`, `reports/` |
| Pace of construction | 60 commits between 2026-10-05 and 2026-10-13. | `git log` |

**Assessment.** The architecture is sound for a research platform:
- one DAG;
- immutable inputs;
- explicit provenance;
- tamper-evident manifests;
- a provider interface for projections.

The codebase is small enough to evolve without a rewrite. Nothing in this assessment justifies
switching language or adding services. The main structural risk is that a single `_targets.R`
is accumulating every milestone **[H]**. Splitting it into per-track target factories would help
it scale.

---

## 3. Capability inventory

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| nflverse ingestion 2017–2025 (stats, pbp, schedules, rosters, snaps, injuries, depth charts, ffopportunity, ID maps) | ✅ built | `R/data/ingest_nflverse.R`, `clean_nflverse.R` [V] | Validation of keys, ranges, team codes and ID maps |
| Live 2026 data layer (dated immutable retrievals) | ✅ built | `R/live/live_data.R` [V] | Every run stores a new file, so the inputs at any prediction time can be reconstructed |
| ESPN weekly projections 2018–2025 (WR); QB/RB/TE week-of 2019–2025 | ✅ cached locally (owner opt-in) | `docs/espn_projections.md` [V] | Final-pregame values, verified against Wayback for 2019, 2023 and 2026. Disney ToS risk is documented. |
| ESPN↔GSIS crosswalk | ✅ audited | `R/data/espn.R` [V] | 99.87% WR match. 20 ambiguous rows ("DJ Turner") excluded. |
| Scoring engine (YAML) | ✅ validated | `R/data/scoring.R`, `config/scoring/espn_ppr.yml` [V] | Matches ESPN actuals on 99.96% of 14,628 WR player-weeks |
| Point-in-time features + leakage corruption tests | ✅ strong | `R/features/point_in_time.R`, `m2_features.R`, `availability.R`, tests [V] | Corrupts every column of every history table. Planted-leak unit tests. |
| Pregame-valid injury reports 2017–2024 (timestamp-filtered, Pacific-time correction) | ✅ built | `R/data/injuries_pregame.R` [V] | 2025 has no timestamps and is excluded |
| As-of-kickoff lines and expected QB, 2021–2025 (nfldata git history) | ✅ built, unused in frozen models | `R/data/nfldata_history.R`, E11 [V] | Unlicensed repo, so private research only |
| Weekly WR projection lineages M1, M2, M3, M3b, M4 (frozen, fingerprinted) | ✅ | `models/registry/*.yml`, `models/fingerprints/` [V] | Primary M4: `m4_two_stage_v1` |
| Prospective archive (2026 W5+) with hash manifests and official-run selection | ✅ | `R/live/prospective.R`, `prospective_eval.R`, `archive/prediction_manifest.csv` [V] | Scoring happens once at season end |
| QB/RB/TE projection models | ❌ none of our own | `config/project.yml` `positions: [WR]` [V] | Valuation uses calibrated ESPN for these positions |
| ROS forecasting (posted ESPN weeks + fixed quadratic horizon model) | ✅ V1 | `R/valuation/ros.R`, `models/valuation/ros_params_v1.yml` [V] | Posted weeks are unvalidated (VE-P1 pending) |
| Exact weekly lineup allocation incl. FLEX/superflex; exchange baselines | ✅ | `R/valuation/allocation.R` [V] | Matroid greedy with a Hall check. Toy-league tests. |
| VOR, VAS, MRU, display value, packages, valuation backtest | ✅ | `R/valuation/value.R`, `packages.R`, `backtest.R` [V] | |
| Monte Carlo roster simulation | ⚠️ availability only | `R/valuation/simulation.R` L24–45 [V] | Draw = Bernoulli(active) × fixed if-active level. No score variance, no correlation, no persistent level uncertainty. |
| League ingestion, team utility, trades, search, needs, rankings | ✅ V2 | `R/valuation/league_*.R` [V] | Expected values only. Free agents always acquirable. |
| League matchup schedule / standings for simulation | ❌ schedule not captured; standings and rules fetched but not parsed | `league_espn.R` L3/L69 requests only `mSettings, mTeam, mRoster, mStatus` [V] | <ul><li>The schedule needs `view=mMatchup` (or `mMatchupScore`), verified in the ffscrapr and espn-api client code ([10](10_sources.md) §V).</li><li>Records, playoff and tiebreak rules, the trade deadline and FAAB settings are already in the `mTeam`/`mSettings` responses but are not parsed.</li></ul> |
| Score distributions, floors/ceilings, boom/bust | ❌ | — [V] | Residual SDs are reported as diagnostics only (VE1c) |
| Matchup win probability, season/playoff/title simulation | ❌ | `docs/valuation_v2_plan.md` §18 non-goals [V] | |
| Win-probability start/sit | ❌ | README roadmap item 5 [V] | |
| Waiver/FAAB tools | ⚠️ partial | `trade_analyzer.R waivers`, team needs [V] | The waiver-upgrade diagnostic exists. No bidding, contention or multi-week planning. |
| Draft tools, keeper/dynasty | ❌ | V2 non-goals [V] | |
| K / D/ST valuation | ❌ | V1/V2 limitations [V] | They occupy slots only |
| Decision-quality evaluation (lineup regret, trade outcomes) | ❌ | — [V] | All evaluation is of point forecasts |
| Probabilistic scoring rules (CRPS, PIT, coverage, Brier/log loss) | ❌ | `R/evaluation/metrics.R` holds MAE, RMSE, bias, median AE, correlation and weekly Spearman [V] | |
| Operations: weekly runner, status dashboard, verified backups | ✅ manual | `scripts/weekly_run.R`, `status.R`, `backup_archives.R` [V] | Runs are the owner's job. Scripts never push. |

---

## 4. Verified strengths (keep these)

1. **Point-in-time integrity is best-in-class for a hobby or academic project.** It rests on
   - as-of joins;
   - corruption-based leakage tests run on real data;
   - timestamp validation of injury reports, including the 2017–2020 Pacific-time bug;
   - the "unfinished earlier game" live fix (E8).
   No external project reviewed in `docs/prior_work.md` comes close. One reviewed thesis has a
   severe target leak.
2. **Honest benchmark hierarchy.** Raw ESPN, then calibrated ESPN, then ESPN-free, then ESPN plus
   ours (`docs/models.md`). The project has shown that most apparent "edges" over raw ESPN are
   level calibration (E2, E4, E5). This lesson is not widely appreciated, and it protects
   against self-deception.
3. **Pre-registration with frozen lineages and fingerprints.** A change creates a new lineage, and
   every decision is logged before its results (E1–E15, VE0–VL2). Negative results are recorded
   (C, E, K3, K4, the M2 augmentation).
4. **Tamper-evident prospective archive.** Manifests are pushed before kickoff, and only hash-verified
   runs are scored (`R/live/prospective_eval.R`).
5. **Valuation economics are correct where many tools are naive:**
   - weekly (not aggregate) replacement with byes;
   - an exact FLEX allocation (matroid);
   - exchange baselines that are the LP duals of slot constraints;
   - roster-aware package evaluation with forced drops and waiver adds;
   - team-specific ΔU that captures positional need and consolidation without hand-set penalties
     (VE2 results, VL1).
6. **A provider abstraction** separates where projections come from and what consumes them
   (`R/valuation/providers.R`). That is the right seam for plugging in distributional forecasts.
7. **Privacy engineering.** League data, ids and cookies stay out of Git. A random alias and
   hash-only manifests are used. Reports with ESPN content are git-ignored.
8. **Tests:** 156 `test_that` blocks, including toy leagues with hand-solved optima, planted leaks and
   archive integrity.

---

## 5. Weaknesses, limitations and technical debt

### 5.1 Statistical

**W1 — The projection programme has hit the "market ceiling" for point forecasts [V].**
- Calibrated ESPN beat or tied every feature model out of sample (E2, E5).
- XGBoost never beat linear models (E4).
- The ESPN-free model is about 0.19 MAE behind ESPN (E5).
- Replicated gains are injury-availability adjustments worth about 0.3–0.6% of MAE overall
  (E10, E14), and about 5% on the affected rows.

*Implication:* further broad feature or model searches for weekly WR means have a poor expected
return. The research below (doc 02) explains why: consensus and market forecasts aggregate
information that public box-score features cannot add to.

**W2 — Only WR has been studied for projections [V].**
QB, RB and TE flow through `espn_calibrated` (`config/valuation.yml`). The injury-availability
result has never been tested on other positions. Those tests are **fresh** question families,
with uncontaminated historical seasons for them **[H, needs a contamination check]**.

**W3 — There is no probabilistic layer [V].**
- Every output is an expectation.
- The simulation draws availability only (`simulation.R` L39–42): `P = (u < A) × L`.
- So a player's realised weekly points are either 0 or exactly his if-active level.

Consequences:
- **No upside:** bench value comes only from injury and bye cover. VE3 *hypothesised* this as the
  reason the VE2 re-draft hoarded 30 QBs. S3 tests that hypothesis.
- **No team-score variance,** so win probability, playoff odds and risk-sensitive lineups are
  impossible.
- **No correlation:** a QB–WR stack and two players from different games are treated identically.
- **Rest-of-season uncertainty is unused.** The *total* ROS residual SD is about 45–53% of the
  forecast (VE1c). It combines a persistent level component, weekly noise and attrition (P4
  decomposes it). `R/valuation` contains no uncertainty term (grep [V]).

**W4 — Evaluation is point-forecast-centric [V].**
`R/evaluation/metrics.R` holds MAE, RMSE, bias, median AE, Pearson and weekly Spearman. The M2
protocol adds pairwise ordering, top-24 precision and large-miss rate. Missing:
- proper scoring rules for distributions (CRPS, log score), PIT and coverage;
- Brier or log loss for probabilities such as M4's P̂(active);
- any **decision** metric: lineup regret, start/sit accuracy within a roster, realised ΔU of
  recommended trades.

There is therefore no way yet to test the owner's key question: do better projections mean
better decisions?

**W5 — The 2026 prospective tests are probably under-powered [C].**
Assumptions:
- the week-level variance of paired differences is like 2019's (17 weeks; E14);
- the true effects equal the 2019 point estimates;
- the 95% CI half-width scales as 1/√weeks;
- there are about 13 usable weeks (W6–W18; see W7).

| Test | 2019 estimate [95% CI] | Implied CI half-width at 13 weeks | Approximate power to exclude 0 |
|---|---|---|---|
| M3b vs `m2_espn_cal` | −0.0075 [−0.0143, −0.0005] | ≈ 0.008 | ≈ 45–50% |
| M4 K2 vs `m2_espn_cal` | −0.0185 [−0.0347, −0.0009] | ≈ 0.019 | ≈ 45–50% |
| M4 K2 vs M3b | −0.011 [−0.022, +0.001] | ≈ 0.013 | ≈ 35–40% |

So even if the effects are real, "insufficient" or "CI spans 0" is roughly as likely as success.

> **Correction (2026-10-13, F1/E16).** These figures were optimistic: they used only 2019's week-level variance (the
> quietest injury season) and a normal approximation. With within-season σ_w pooled over all historical seasons and
> t quantiles, power at 13–14 informative weeks is about 25–35% (H-D, H-M4) and 37–40% (H-B); 14–21% if prospective
> noise is 1.5× historical; about 8% for H-A; ≈ 0 for H-M2 (its holdout effect had the wrong sign). The pre-registered
> percentile bootstrap passes about 10 points more often than these t-based figures, but its one-sided size is about
> 5% rather than 2.5%. The pooled 2026 + 2027 analysis reaches 55–77% for the injury and return families. See
> `research/experiment_log.md` E16 and [execution/decisions.md](execution/decisions.md) X-008.

The picture may be worse:
- W5 is a **structural-zero week** for M3b and M4, whose predictions were identical to the base.
- Prospective σ_w may exceed the historical value, because pre-inactive snapshots include more zeros.
- The prospective effect itself may differ, because snapshots are pre-inactive (E13).

This argues for:
- a pre-registered, **fixed-sample pooled 2026 + 2027 analysis**, written down before outcomes are
  examined. The frozen runtime must stay pinned so the 2027 models are identical.
- Anytime-valid e-processes only for blind monitoring. They give optional stopping, not extra power.
- weighing these effects by their **decision** value rather than pooled MAE.

**W6 — The historical evaluation budget is exhausted for the WR weekly-points family [V].**
2019 was the last fresh WR season (E12–E14). Seasons are not exhausted for **other** question
families, such as distributional calibration, other positions, ROS uncertainty, correlation
structure, decision policies and draft. The current registers, however, are per milestone and
not per question family.

A project-wide **contamination register** keyed by (question family × season) would make that
explicit **[H: the proposed mechanism]**.

**W7 — There is a horizon mismatch between development and prospective use [V fact; H consequence].**
- *Fact:* historical ESPN values are **final pregame** projections (`docs/espn_projections.md` §2).
  They are effectively **post-inactive**: ESPN zeroes most inactives. In E13, 115 of 136
  zero-projected Q-LP WRs were inactive.
- *Fact:* the archived 2026 W5 runs were all made on Monday–Tuesday, 2026-10-05/06
  (`archive/prediction_manifest.csv`), and W6 so far has one Tuesday run.
- *Fact:* Wednesday/Thursday ESPN captures matched final values for only 54–72% of players
  (§2 of the same doc).
- *Consequence [H]:* the weekly calibration was fit to final values and is being applied to
  early-week snapshots. The prospective record therefore measures a different forecast horizon
  than the one the models were developed on.
- *Consequence [V]:* no W5 run captured Friday's final injury reports, so **M3b and M4 equalled
  calibrated ESPN for every W5 game** (E15: "No team's Week-5 final injury report exists yet").
  The injury lineages' prospective test has effectively lost W5.

**W8 — The ROS and valuation layers have known, documented biases [V]:**
- the remaining top-quintile under-prediction for QB (VE1c);
- QB mildly under-valued in the backtest;
- TE team value per VOR point is 0.64 against about 0.88 (VL1);
- ESPN's posted future weeks are unvalidated (VE-P1 is pending to season end);
- the ROS parameters are PPR-specific.

### 5.2 Decision tooling

**W9 — The trade analyzer is a strong expected-value engine, but [V]:**
- there is no acceptance model, so "win-win" means win-win in the model;
- free agents are always acquirable, with no waiver priority, FAAB or contention;
- streaming happens only into empty slots;
- K and D/ST are not valued;
- there are no playoff or title probabilities. A contender and a rebuilding team value the same
  trade identically.
- No historical validation is possible, because historical league states are not archived. The
  new archive enables prospective checks.

**W10 — Missing decision products [V]:** win-probability start/sit, waiver or FAAB bidding,
draft assistant, playoff-odds simulation, luck-adjusted standings, and a weekly briefing that
combines all of them.

### 5.3 Technical debt and operations

**W11 — Prospective operations are manual and fragile [V].**
The record depends on the owner running scripts before each slate (Thu, Sat/Sun, Mon). W5 shows
the cost: the runs made were all early in the week (W7). The prospective protocol already
describes optional Task Scheduler runs (not enabled).

**W12 — Code paths fail on first contact with real data [V].**
Real-data bugs were caught at first contact:
- the E7 closure bug;
- the E8 unfinished-game artifact;
- two VL1 league bugs;
- the VL2 capture-time bug.

Each was caught and logged, which is good discipline. The pattern argues for running new
decision tools in shadow mode, logging recommendations but not acting on them, before they
are relied on.

**W13 — Projection code is WR-specific in places [H].**
The README claims RB/TE/QB is "a configuration change", but the M2 feature families, M3/M4 rules
and populations were designed for WR. Each position needs its own feature review and
pre-registration.

**W14 — There is no Bayesian or hierarchical tooling, and adding it may need a C++ toolchain [H].**
Stan-based packages compile models. Toolchain-free alternatives exist (see doc 06).

**W15 — The project depends on ESPN as a single source [V].**
ESPN is the projection backbone for every position and for future weeks. The Disney Terms of Use
risk is documented and accepted by the owner for private research. A change in API access would
remove the base forecast and the league connection at once. No free, terms-clean consensus
alternative is in place (`docs/source_feasibility.csv`).

---

## 6. Opportunities that follow directly from the assessment

| # | Opportunity | Why it is high-leverage | Section |
|---|---|---|---|
| O1 | **Distributional layer around the calibrated base**: P(active) × a conditional points distribution, calibrated on history | Doesn't require beating ESPN's mean. Historical seasons are fresh for this question family. It unlocks win probability, risk, bench upside and the VE3 fix. | W1, W3, W6 |
| O2 | **Correlated scenario engine** extending `val_sim_setup()` (players × weeks × sims) | The array structure and common random numbers already exist; the change is in the draw. | W3 |
| O3 | **League schedule and standings ingestion, then a season simulator** | One extra view in an existing request. It turns ΔU into Δ wins, playoff odds and title odds. | W9, W10 |
| O4 | **Decision ledger and decision metrics** | Answers "do better forecasts make better decisions?" and gives every tool a prospective record. | W4, W12 |
| O5 | **Evaluation upgrade**: CRPS, PIT, coverage, Brier, power analysis, contamination register, sequential monitoring | Makes every later milestone testable. | W4, W5, W6 |
| O6 | **Position generalisation of the injury-availability result** (RB/TE/QB), pre-registered | The best-evidenced projection gain so far. New positions are fresh families. | W2 |
| O7 | **Operational automation** (scheduled pre-slate runs; the owner still pushes) | Protects the only clean evidence stream at almost no cost. | W7, W11 |
| O8 | **Horizon-aware distributions** (early-week, post-report, late), built **outcome-free** from the revision variance of our own dated snapshots | Matches the forecast horizon to the decision time (waivers on Tue/Wed, lineups at lock) without using 2026 outcomes. | W7 |

---

## 7. Verified findings vs hypotheses (summary)

| Statement | Label |
|---|---|
| Calibrated ESPN is the best weekly WR point forecast found; feature models fail out of sample | V (E2, E4, E5) |
| Injury-availability adjustments give small replicated gains for WRs | V (E10, E14) |
| Simulation draws availability only; no score noise, correlation or level uncertainty | V (`simulation.R`; grep) |
| League snapshot does not fetch matchups or schedule | V (`league_espn.R` L3, L69) |
| W5 injury lineages equal calibrated ESPN (no post-Friday run) | V (manifest, E15) |
| The 2026 prospective tests have about 35–50% power (less if prospective variance is higher) | C (assumptions in W5) |
| Calibration fit on final-pregame values is miscalibrated for early-week snapshots | H (testable with our snapshots) |
| RB/TE/QB injury effects exist and are fresh question families | H |
| `_targets.R` will become hard to maintain as tracks grow | H |
