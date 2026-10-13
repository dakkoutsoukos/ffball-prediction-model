# 05 — Statistical and Modelling Strategy

*Recommends the modelling approach for each layer of the platform, compares the alternatives, and fixes the
rules for validation, calibration, uncertainty and model selection. Evidence: [02](02_research_landscape.md).
Milestone ids (F*, P*, S*, D*, R*, I*) refer to [07](07_master_roadmap.md).*

*Revised after the adversarial review recorded in [07](07_master_roadmap.md) §10.*

---

## 1. Principles

1. **Borrow the mean where the market is efficient; build where nobody else does.**
   - Weekly means: calibrated ESPN plus narrow, validated adjustments.
   - FFball's distinctive value comes from:
     - calibrated *distributions* and *dependence*;
     - *information timing* (availability and forecast horizon);
     - *league-specific decision optimisation*;
     - *accountability*: prospective, pre-registered evaluation of forecasts **and** decisions.
2. **Distribution first.** Every forecast that feeds a decision is a predictive distribution at a stated horizon: P(active | h) together with F(points | active, information at h).
3. **Information-set discipline.**
   - Each output uses only information available at its *decision time*: the waiver run (Tuesday/Wednesday), lineup lock (each kickoff) or trade evaluation (any time).
   - Simulations choose lineups on what was knowable at lock, never on realised points.
4. **Score with the rule that matches the target** (§3). Judge decisions by decision metrics.
5. **Simple and calibrated beats complex.** Each layer starts from the simplest model that can be calibrated. A more complex candidate must beat it on a proper score under a pre-registered rule.
6. **Outcome-free triage before spending evidence.**
   - Before an experiment uses historical check seasons or prospective outcomes, compute everything that needs no outcomes:
     - decision flip rates;
     - model-implied gains;
     - revision variances;
     - the minimum detectable effect (MDE).
   - Skip experiments that cannot reach their MDE or cannot change a decision.
7. **The protocol is a feature.**
   - Pre-registration, frozen versions with fingerprints, rolling-origin evaluation, one-time checks, and prospective records that start at the freeze and are never backfilled.
   - A **contamination register** (question family × season, §9) governs which data each family may touch.
   - **2026 outcomes are never development data**, for any family.

---

## 2. The layered model

```
L1 base location      calibrated E[points | active, info at horizon h], per player-week      (providers)
L2 availability       P(active | info at h); h ∈ {early: Tue–Thu, post-report: Sat/Sun, late: post-inactive}  (P1)
L3 conditional shape  F(y | active, base, position, status, context), fit on active rows only    (P0 → P2)
L4 dependence         latent game/team factors + role loadings → Gaussian copula (gated)          (P3)
L5 season dynamics    persistent level shock L_i (mean 1), weekly noise, attrition, ESPN revision dynamics (P4)
L6 scenarios          joint draws: players × weeks × sims, common random numbers, decision-time lineups (P5)
L7 league layer       rules, rosters, schedule, standings → matchups, seasons, playoffs           (S0–S3)
L8 decisions          lineups, trades, waivers/FAAB, draft, as policies over scenarios           (D0–D5)
L9 evaluation         scoring rules, calibration, power, decision regret, ledger                  (F1, F2, F5, F6)
```

**Why this decomposition**
- Each layer can be estimated and evaluated separately, with its own proper score.
- Each can be replaced behind a typed interface (provider table, POD table, scenario set).
- Each is a fresh question family, so historical seasons can be used honestly for it under the register.

### 2.1 Horizons: the most important modelling convention

| Horizon | When | Information | Historical data available? |
|---|---|---|---|
| **late** (post-inactive) | Within about 90 min of kickoff | Game-day inactives known | **Yes.** Historical ESPN week-of values are *final pregame, post-inactive*: ESPN zeroes most inactives (E13: 115 of 136 zero-projected Q-LP WRs were inactive). |
| **post-report** (pre-inactive) | Saturday to Sunday morning | Final injury report, no inactives | Only through our own captures (2026 W5+); injury reports exist historically, ESPN values do not |
| **early** | Tuesday–Thursday | Practice reports, early ESPN values | Only through our own captures |

**Consequence.** A distribution fit on historical ESPN-projected rows is (approximately) *conditional on game-day news*. It must therefore be:
1. fit **only on rows where the player was active**: played at least one offensive snap; this is F(y | active, base);
2. combined for earlier horizons as

   **POD_h = P(active | h) · F(y | active, base_h) ⊕ (1 − P(active | h)) · δ₀**

   with a **horizon spread term** for the extra uncertainty of base_h compared with the final value.

This avoids double-counting the residual inactive mass, and avoids training earlier-horizon models on game-day information (a leakage of class L2).

---

## 3. Targets and scoring rules (what "better" means)

| Output | Target functional | Primary score | Diagnostics |
|---|---|---|---|
| Point projection used for sums (ROS, lineups, valuation) | **Mean** | **MSE/RMSE** | MAE; Murphy diagram [Ehm et al. 2016]; bias by band |
| Point projection reported as a "typical" outcome | Median (declare explicitly) | MAE | — |
| Weekly outcome distribution | Full distribution | **CRPS** | Randomised PIT; 50/80/90% coverage; interval score; MCB/DSC/UNC; threshold-weighted CRPS (boom weeks) |
| P(active), P(win), P(playoffs), P(title), boom/bust | Probability | **Brier** | CORP reliability and decomposition [Dimitriadis et al. 2021]; log loss |
| Joint outcomes (teammates, lineups) | Joint distribution | **CRPS and PIT of lineup totals and matchup margins** | Variogram score (p = 0.5); energy score secondary |
| Rankings | — | Not a proper score; descriptive | Within-position Kendall/Spearman; pairwise accuracy on close calls |
| Decisions | Realised outcome | **Regret** against the hindsight-optimal action; paired regret difference against the incumbent policy | Flip rate; realised Δwins (descriptive) |

**Transition rule.**
- Frozen tests keep their pre-registered metrics (MAE primary, RMSE gate).
- **New** point-forecast families use **MSE as primary** (their outputs are summed), with MAE reported [Gneiting 2011].
- Distributional families use CRPS. CRPS equals absolute error for a point forecast, so archived *point* forecasts can be scored as deterministic baselines on the same scale.

---

## 4. Layer by layer: recommended approach, alternatives and trade-offs

### 4.1 L1: Base location (point forecasts)

**Recommendation.** Keep the provider architecture. The base is *calibrated ESPN* for every position, plus validated FFball adjustments:
- WR: the frozen `m4_two_stage_v1`;
- other positions: R2 rules once frozen.

Move to **stat-component** bases where ESPN components are captured, so projections rescore exactly to any league.

| Alternative | Evidence | Verdict |
|---|---|---|
| Our own feature model replacing ESPN | Failed out of sample (E2, E5); outside evidence agrees | No |
| Broad residual model on calibrated ESPN | Failed on the holdout (E5) | No |
| Narrow, pre-registered rules on systematic ESPN errors | Replicated (E7, E10, E14) | **Yes** (R2) |
| Equal-weight average of several sources | Season-long quantitative evidence; weekly evidence qualitative only [Petersen 2026]; cannot be backtested | Prospective only (R4; owner decision) |
| Component (top-down) model as an ESPN-independent fallback | No evidence that it beats ESPN; the value is resilience | Low priority (R6) |

**Calibration.**
- For WR, `m2_espn_cal` refits weekly.
- **No rolling per-position calibration exists for QB/RB/TE.** Valuation uses one fit on 2019–2025 (VE1c). P0 and F4 must build a new rolling-origin per-position calibration (linear in ESPN points, refit weekly, MSE).
- **Horizon-specific calibration** comes from R3's outcome-free revision analysis (§4.3).

### 4.2 L2: Availability, P(active | h) (P1)

**Outcome:** played at least one offensive snap. This is the fantasy-relevant definition, not roster status alone.

**Post-report horizon (estimable historically).**
- *Population:* players on the team's final injury report, plus a sample of unlisted players for the base rate.
- It does **not** depend on ESPN, which avoids the post-inactive selection problem.
- *Features* (pregame-valid):
  - designation, final practice status, position;
  - returning-from-absence, consecutive weeks listed, previous designation;
  - day of week;
  - a shrunk team reporting effect.
- *Model:* a logistic GLMM (lme4/glmmTMB, toolchain-free).
- *Baseline:* a designation × practice × position rate table.
- *Published anchors:* Questionable players play about 71% and Doubtful about 7% [Hutchison 2025]. These serve as the **fixed prior used by D0/P0/S0 until P1 exists**.
- *Watch:* COVID-list absences distort 2020–21 base rates for unlisted players. Run a sensitivity check that excludes them.

**Early horizon (outcome-free construction).**

P(active | early) = Σ_d P(final designation = d | midweek status) × P(active | d)

- The transition matrix uses only designations: midweek → final, from FFball's 2026 dated captures. These are inputs, not game outcomes.
- P(active | d) comes from the historical post-report model.
- **No 2026 outcome enters.**

**Late horizon:** availability is known.

**Evaluation:** Brier and log loss with CORP reliability, by position, at the post-report horizon. Seasons are in §9 (injury batch).

### 4.3 L3: Conditional weekly distributions (P0 → P2)

**Target.** F(y | active, base, x) at the late horizon, fit on historical rows where active = 1 (§2.1). Earlier horizons are built by mixing in P1 and adding the horizon spread term.

**Horizon spread term (R3, outcome-free).** If ESPN's projection is approximately a martingale (revisions unpredictable from earlier values):

Var(y | early) ≈ Var(y | final) + Var(final − early)

The revision variance needs only FFball's dated 2026 captures and ESPN's after-the-fact *final projections*. These are forecasts, not outcomes. The martingale assumption itself is checked on the same captures: are revisions uncorrelated with earlier revisions?

**Candidates.** Pre-register at most three plus the baseline.

| id | Method | Strength | Weakness |
|---|---|---|---|
| C0 (P0, baseline) | **Empirical conditional quantiles** of (actual − base) on active rows, by position × fixed base band, from rolling-origin bases | Assumption-light; quick | Coarse; no covariates |
| C1 (benchmark) | **Isotonic distributional regression** of points on base, by position [Henzi et al. 2021] | Calibrated under monotonicity | No other covariates |
| C2 | **EMOS-style distributional regression**: location tied to base; scale and shape smooth in base, position and status; families `mgcv::shash`, `gamlss` ZAGA (shifted) or `mgcv::twlss` (shifted); likelihood fit, CRPS check [Gneiting et al. 2005] | Spread covariates | Family choice; tail risk |
| C3 | Best of C0/C2 plus **adaptive conformal** recalibration by position [Gibbs & Candès 2021] | Coverage under drift | Coverage is marginal only |

The compound component model (yards × TDs) is **not** a P2 candidate. It stays a future idea for non-PPR rescoring and bonuses.

**Spread covariates** (closed list):
- base level;
- position;
- injury status at the final report;
- TD-share of the projection (from ESPN components);
- implied team total and spread (2021+, as-of lines);
- shrunk player volatility history.

**Selection** (pre-registered):
1. Lowest development CRPS.
2. Coverage gate (§6).
3. A difference below 0.5% of CRPS is a tie, and the simpler candidate wins.
4. Then the one-time batch check (§9).

### 4.4 L4: Dependence (P3, gated)

**Gate.** Build P3 only if, on development seasons, independence mis-calibrates *lineup totals*: the PIT of random legal lineups shows over-dispersion or under-dispersion beyond tolerance. Our own arithmetic suggests correlation moves σ_Y only about 1–2% for typical rosters; the gate checks whether that holds.

**If built:**
- Normal scores of PIT values.
- z_i = λ_{r(i)}·T_team + κ_{r(i)}·G_game + ε_i, with pregame roles r(i) (QB; RB1/2; WR1/2/3; TE1, by projection rank within team and position).
- Loadings shrunk toward pooled role values.

| Alternative | Verdict |
|---|---|
| Independence | Baseline |
| Shrunk empirical role-pair matrix | Second candidate |
| Vine copulas; play-level simulation | Rejected |

**Evaluation:** CRPS and PIT of lineup totals (primary); variogram score (p = 0.5).

### 4.5 L5: Season dynamics (P4)

The rest-of-season residual SD (about 45–53% of forecast, VE1c) is the **total** of three sources:

| Source | Description |
|---|---|
| (i) Persistent level shock L_i | Role or talent the forecast missed |
| (ii) Weekly noise | From P2 |
| (iii) Attrition | Multi-week injury, benching or role loss |

The VE1c figure is not "level uncertainty" by itself.

**Model.**
- **Level shock:** log L_i ~ N(−σ²_L/2, σ²_L), so **E[L_i] = 1** and means are preserved.
- **σ_L by position and band**, estimated by **simulation matching**:
  - draw availability (attrition) and weekly noise *separately*;
  - choose σ_L so the simulated rest-of-season total SD matches the observed one on development seasons (2019–2023);
  - this avoids double-counting attrition.
- **Attrition:** a weekly discrete-time hazard by position × level band, starting from VE1's horizon-bucket availability.
- **Learning:** simulated lineup policies update their beliefs about players the way **ESPN's own revisions** respond to realised residuals. This dynamic is identifiable from historical week-of values; E5 suggests ESPN over-reacts to role changes. Use it in place of a theoretical normal–normal update, which stays the fallback.
- **First diagnostic (X2):** are a player's residuals autocorrelated? That tells us whether σ_L > 0.

**Evaluation:** CRPS and coverage of rest-of-season totals at w = 4/8/12.

**Downstream test (S3):** re-run the VE2 fixed-point re-draft with level uncertainty plus learning. Prediction: it converges, and QB hoarding disappears. That was VE3's *hypothesis* about its cause.

### 4.6 K and D/ST

These are needed for team-score variance, not valuation.
- **v0:** position-level empirical distributions, independent of matchup.
- **Better:** ESPN's own K and D/ST projections. These are probably available by adding the K and D/ST slot ids to the existing valuation request; confirm by inspecting keys only. That would be an expansion of the request content, so it is an owner decision (O8).
- **Not trivial:** scoring nflverse-derived D/ST under the league's rules (points-allowed tiers, return TDs) is size M, not S.

Upgrade only if lineup-total calibration fails.

### 4.7 Scenario generation (P5)

1. **Per sim:** draw L_i (mean 1) for every player, then game factors G and team factors T for each week (if P3 passed its gate).
2. **Per player-week:** active ~ Bernoulli(P(active | h)). If active, draw u (from the copula, or independently), set points = F⁻¹(u | active, base_h) × L_i, and apply the horizon spread term.
3. **Decision-time lineups (critical).**
   - Lineups are chosen per sim-week on **decision values** and scored on **realised values**.
   - Decision value = E[points | availability known at lock, the policy's current belief].
   - Hindsight lineups inflate bench value (ffsimulator's flaw, patched there by a 77.5% "efficiency" factor).
   - **New functions are written for this.** `val_lineup_value()` and other V1/V2 code are not modified. Bit-identity tests protect V1/V2 outputs.
4. **Reproducibility:** L'Ecuyer-CMRG streams per chunk; seeds and input hashes recorded; common random numbers across counterfactuals.
5. **Compute:**
   - About 600 players × 14 weeks × 2,000–10,000 sims.
   - Run in chunks (crew/future).
   - Vectorised R. Rcpp needs RTools (owner decision O6).

### 4.8 League, valuation and decision models (S, D)

| Model | Recommended form | Notes |
|---|---|---|
| Matchup P(win) | Simulate from P5 with policy lineups; opponents' lineups projection-optimal, adjusted by F3 behaviour profiles | Baseline to beat: normal approximation Φ(μ_Y/σ_Y) |
| Season and playoffs | nflseedR-style weekly `compute_results()` over the real schedule, tiebreakers and playoff format (multi-week rounds), on the same draws | **External baseline:** ESPN's own `playoffPct`, logged prospectively and, once enough seasons accrue, recalibrated |
| Player value | Keep V1 VOR as the generic display. Add **EVOR** = E[Σₜ max(0, X − R)], **wins added** (common-random-number removal with decision-time lineups) and **ΔP(playoffs/title)** per roster | Explain ΔP(title) by decomposing it into regular-season wins, seeding/bye and playoff-week points |
| Trades | (1) ΔU screen (existing V2 search). (2) Top K re-scored with common random numbers for ΔE[wins], ΔP(playoffs/title) for both teams. (3) Show the **frontier** of own gain vs partner-lens gain. The partner lens = raw ESPN posted projections and generic values. Loss aversion λ ∈ [1, 2.2] is a sensitivity sweep. | The Nash product is reported as a *fairness* summary, **not** an acceptance model. No acceptance model is fitted. |
| Lineups | EV allocator; latest-kickoff FLEX tie-break; game-time plan; late-window conditional P(win). A full P(win) mode is built only if outcome-free triage shows flips in ≥ 5% of team-weeks. | The top-half bonus (`WIN_BONUS_TOP_HALF`), if enabled, adds a P(beat the median) term |
| Waivers / FAAB | ΔU and ΔP(playoffs) of add+drop over a k-week lookahead with a rest-of-season terminal value. **FAAB bid** b* = argmax_b P(win at b) · (v − λ_F·b), with v in ΔP(playoffs) units and λ_F the shadow price of FAAB in ΔP per dollar (declining over the season) | Gated on `isUsingAcquisitionBudget`; competitor-bid priors from public data, updated with league history |
| Draft | Point-in-time ADP snapshot, skewed availability model, Monte Carlo opponents (ADP + noise + need + herding), policy evaluated by S2 at week 0. Opponent model can be calibrated on the league's own draft history (`mDraftDetail`; owner decision O8). | Deterministic DP [Fry et al. 2007] as a fast heuristic |

---

## 5. Validation protocol (applies to every new family)

1. **Pre-register before computing.** Record the family, candidates (≤ 3–4 plus baseline), parameters, metrics, selection rule, seasons, success criteria and **one primary inference procedure**.
   - Projection, distribution and availability families go in `research/experiment_log.md`.
   - Valuation, simulation and decision families go in `research/valuation_log.md`.
2. **Contamination register** (`research/contamination_register.yml`, F2). Family × season status, enforced by an `assert_family_seasons()` guard.
3. **Rolling-origin evaluation**, expanding window, at a pre-declared refit cadence. Selection happens inside each origin wherever it is automated.
4. **Inference: one primary procedure per family; everything else is sensitivity.**
   - **Default primary:** paired, week-clustered bootstrap of week-level loss differences, stratified by season. This is FFball's existing method.
   - **Pre-declared sensitivities** (reported, never used for selection): block bootstrap; HLN-corrected t; season random effect.
   - **Season-level outcomes** (wins, playoffs, titles) are **descriptive only**. Their effective sample size is the number of seasons.
5. **Batched one-time checks** (§9).
   - Each family stack is frozen on development seasons, then all of its historical checks run in **one pre-registered batch**, with Holm correction across the batch's primary hypotheses.
   - Later families treat those seasons as contaminated.
6. **Prospective records.**
   - Archive before kickoff; never backfill; score at season end.
   - Cross-season evidence uses a **pre-registered, fixed-sample pooled analysis** (e.g., 2026 + 2027).
   - **E-processes give optional stopping, not extra power.** Only more weeks add power. They are used for *blind monitoring* (no outcome-driven changes), not as the pooled test.
   - For absolute-error differences, |Δ| ≤ |Δprediction| gives an exact predictable bound, as Choe & Ramdas require.
7. **Power first.**
   - Compute σ_w from history, and the MDE at σ_w × {1, 1.5}, because prospective σ_w may be larger (pre-inactive zeros).
   - If the expected effect is below the MDE, pre-register pooling or non-inferiority.
   - Structural-zero weeks (e.g., 2026 W5 for the injury lineages) count as weeks with no information.
8. **Leakage audits** [Kapoor & Narayanan 2023]:

   | Class | Check |
   |---|---|
   | L1.2 | Preprocessing fit inside each origin |
   | L1.3 | Selection inside development only |
   | L1.4 | No duplicate keys across sources |
   | L2 | Every input `available_at ≤ decision_time`. Historical ESPN values count as **late-horizon** information. |

   Tag nflverse model-derived features with their training windows. **An audit failure on a frozen lineage is logged as a new log entry and never "fixed"** (the frozen artefact stays as it is).
9. **Decision evaluation uses realised outcomes, never model-simulated ones** (F6).

---

## 6. Success-criterion conventions (estimation first)

- **Coverage gate.** For each position × level (50/80/90%), the week-clustered 95% CI of empirical coverage must overlap [nominal − 3 pp, nominal + 3 pp]. Treat a cell as failed only when its CI, with Holm adjustment across all position × level cells, excludes that band.
- **Calibration slopes (probabilities).** The CI of the slope must include 1, and its point estimate must lie in [0.8, 1.2]. This applies wherever there is enough data (F6 replays, pooled prospective).
- **Real-league probability calibration is descriptive only.** About 56 matchups and 8 playoff outcomes per season are too few to test.
- **Non-inferiority** uses explicit margins. For example, the upper CI bound of ΔBrier must be ≤ +0.005 against the baseline.
- **Policy value is reported as an estimate with CI.** Success means the estimate is reported honestly and the kill rules are applied. It does not mean "at least one policy wins".
- **Tie band:** < 0.5% of the primary score; the simpler model wins.
- **Halved effects:** development-derived rule magnitudes are halved against the winner's curse (E6, E9 convention).
- **Kill rules:** D1's full P(win) mode needs ≥ 5% outcome-free flip rate *and* model-implied mean ΔP(win) ≥ 0.005.

---

## 7. Toolchain and runtime policy

- **Two runtimes.**
  - The **frozen-lineage runtime** stays R 4.5.1 with the 2026-10-01 package snapshot through the 2027 season, so the pooled 2026+2027 tests evaluate the same models.
  - New tracks may later use a **separate renv profile** (R 4.6). Side-by-side R installs are simple on Windows.
- **Do not change the main `renv.lock` before R1** (2026 season scoring).
- **In-season builds (F2-lite, P0, S0, D0) use base R.** CRPS from quantiles, PIT, coverage and Brier need no new packages.
- **Toolchain-free packages for later tracks** (CRAN Windows binaries):

  | Need | Packages |
  |---|---|
  | Distributional regression | `mgcv`, `gamlss`, `crch`, `qgam` |
  | Mixed models | `lme4`, `glmmTMB` |
  | Calibration | `isodistrreg` |
  | Scoring | `scoringRules`, `scoringutils`, `reliabilitydiag` |
  | Inference | `MCS`, `clubSandwich`, `seqcomp` |
  | Conformal | `conformalForecast`, `probably` |
  | Dependence | `copula`, `mvtnorm` |
  | Optimisation | `highs`, `ompr` |
- **Stan** (brms, rstan, cmdstanr) needs RTools45 and is the owner's decision (O6). No layer requires it.

---

## 8. What not to model (and why)

| Not doing | Why |
|---|---|
| Broad feature or ML searches for weekly means | Replicated nulls (E2–E5) |
| Defence-vs-position matchups | Persistence r ≈ 0.16–0.27; VE1 opponent term < 0.04% MAE |
| Weather | Weak evidence; priced into totals; forecast history 2021+/2024+ |
| Similarity projections | No NFL out-of-sample evidence |
| Deep RL, MDPs, bandits | No faithful opponent simulator; circular validation; no exploration value |
| LLM / news NLP | No point-in-time archive; terms risk |
| Play-level simulation | Must be re-anchored to ESPN means; no evidence |
| EVT, vine copulas | Too little data per player |
| Kelly sizing for FAAB | The budget doesn't compound |
| Compound component model as a P2 candidate | Complexity without evidence; kept for future rescoring work |

---

## 9. Contamination register: allocations for new families (revised)

| Family | Development | One-time check (batched) | Confirmatory | Notes |
|---|---|---|---|---|
| Weekly WR points (M lineages) | — | — | 2026+ | Exhausted historically |
| **Injury stack** (P1 availability, R2 RB/TE/QB rules) | 2020–2023 (2017–18 extra training for P1) | **2019, one batch for P1 + R2** | 2027 | <ul><li>QB/RB/TE ESPN history starts 2019, so the 2019 check uses an in-season calibration warm-up (weeks 1–4 excluded). Fetching 2018 QB/RB/TE ESPN values is an owner option (O8).</li><li>VE1c examined RB/TE future availability after Questionable (mild contamination, recorded).</li><li>WR reported separately (contaminated).</li><li>2024 is **not** used, so the distribution stack keeps it clean.</li></ul> |
| **Distribution stack** (P0 baseline, P2, P3 if gated in, P4) | 2020–2023 (2019 warm-up). P0's production table is fit on 2020–2023 only. | **2024, one batch for P2 + P3 + P4** | 2027 | <ul><li>2025 is not used: no injury timestamps, so status covariates are missing.</li><li>VE1c's weekly and ROS residual SD diagnostics touched 2019–2025 (scale roughly known); recorded as mild.</li></ul> |
| **Decision family** (F6 experiments) | Replays 2020–2023 | **2025 replays, one batch** (VL11). Policies needing injury timestamps are excluded on 2025. | **2027 prospective** (the only confirmatory evidence for decisions) | <ul><li>Forecasts inside the lab are rolling-origin.</li><li>Trades are not evaluated in the lab.</li><li>2024 is not used, because the distribution-stack check results will have been seen.</li></ul> |
| Usage features (R7) | First-read share 2023–2024; reliability study descriptive 2017–2025 | 2025 | 2027 | Separate family |
| Horizon study (R3) | **Outcome-free:** 2026 captures and ESPN final projections only | — | — | No 2026 outcomes used |
| 2026 shadow outputs (S0, ledger) | — | — | Evaluation only | **Sealed:** no outcome-joined analysis until the 2027 decision pre-registrations are committed |
