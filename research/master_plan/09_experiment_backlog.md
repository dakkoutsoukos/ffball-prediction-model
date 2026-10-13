# 09 — Research Questions and Experiment Backlog

*This document lists the important questions the literature cannot answer for FFball. Each becomes a controlled, leakage-safe experiment, pre-registered before it runs:*
- *E-entries in `research/experiment_log.md`;*
- *VL-entries in `research/valuation_log.md`.*

*Experiments use the contamination-register allocations in [05](05_modeling_strategy.md) §9. Ids X1–X26 are referenced from [07](07_master_roadmap.md). Revised after the adversarial review ([07](07_master_roadmap.md) §10).*

**Rules common to every experiment**
1. **Pre-register first.** Before computing any outcome in the experiment's seasons, write down:
   - the hypothesis, data, baseline and candidates (≤ 3–4);
   - the metrics, design and success criteria;
   - **one primary inference procedure**;
   - how each possible outcome will be interpreted.
2. **Outcome-free triage before spending evidence.** First compute flip rates, model-implied gains, revision variances and the minimum detectable effect (MDE).
   - Skip or redesign any experiment that cannot reach its MDE.
   - Skip or redesign any experiment that cannot change a decision.
3. **Inference.**
   - Week-level paired differences.
   - Primary procedure: a week-clustered bootstrap stratified by season.
   - Sensitivity analyses are pre-declared and never used for selection.
   - **Season-level outcomes are descriptive only.**
4. **Leakage safeguards.**
   - Every input satisfies `available_at ≤ decision_time`, checked against the point-in-time registry. **Historical ESPN values count as late-horizon (post-inactive) information.**
   - Rolling-origin fits only, with selection inside development.
   - Features derived from nflverse models are tagged with their training windows.
5. **Batched one-time checks.** Each family stack runs its historical checks **once, as one batch, with Holm correction**:
   - injury stack: 2019;
   - distribution stack: 2024;
   - decision family: 2025 replays.
6. **2026 outcomes are never development data.**
   - S0 and ledger outcomes stay sealed until the 2027 decision pre-registrations are committed.
   - **2027 is the confirmatory season.**
7. **Decision experiments use realised outcomes** (the F6 replays, or the real league), never model-simulated outcomes.

---

## 1. Summary table

| id | Question | Milestone | Priority | Data window (dev → check → confirm) |
|---|---|---|---|---|
| X1 | What effect can each 2026 prospective test detect (MDE)? | F1 | **Now** | Historical comparisons only |
| X2 | Do a player's residuals against calibrated ESPN persist from week to week? | P4 (first) | High | Dev 2020–2023 |
| X3 | Which distributional method is best calibrated and sharpest? | P2 | **High** | 2020–23 → **2024 (E22 batch)** → 2027 |
| X4 | What predicts the *spread* of outcomes? | P2 | High | As X3 (lines 2021+) |
| X5 | Is P(active) calibrated, by position and horizon? | P1 | High | 2020–23 → **2019 (E19 batch)** → 2027 |
| X6 | Does independence mis-calibrate lineup totals (gate)? If so, which dependence model fixes it? | P3 | Medium | 2020–23 (gate) → 2024 batch |
| X7 | How does rest-of-season uncertainty split into level, weekly noise and attrition? | P4 | High | 2019–23 → 2024 batch |
| X8 | **Do better forecasts produce better lineup and waiver decisions?** | F6 | **High** | Triage → replays 2020–23 → **2025 replays (VL11)** → 2027 |
| X9 | Do P(win)-optimal lineups differ from EV lineups enough to matter? Do late-window decisions? | D1 | Medium | Triage → replays → VL11 → 2027 |
| X10 | Does level uncertainty end QB hoarding? Which value metric predicts realised gains from adds? | S3 | High | Re-draft (no outcomes); replays 2020–23 → VL11 |
| X11 | How often do ΔU and ΔP(playoffs/title) rank trades differently? | D2 | Medium | Outcome-free (model-implied); prospective ledger (descriptive) |
| X12 | Do the league's accepted trades show non-negative perceived gains under the partner lens? | D2 | Low–medium | League trades 2026+ (descriptive) |
| X13 | How much extra uncertainty do early-week forecasts carry? | R3 | **Now** (data) | 2026 captures + ESPN final projections (**no outcomes**) |
| X14 | Do injury and practice effects generalise to RB/TE/QB? | R2 | High | 2020–23 → **2019 (E19 batch)** → 2027 |
| X15 | Do as-of implied totals and spreads improve spread and correlation calibration? | R5 (in X4/X6) | Medium | 2021–23 → 2024 batch |
| X16 | Does streaming (K, D/ST, QB) with contested claims beat holding? | D3 | Medium | Replays 2020–23 → VL11 → 2027 |
| X17 | Can FAAB win probability at a given bid be predicted? | D3 | Low (gated) | League history (O8) + prospective |
| X18 | Is the ADP availability model calibrated for this league's drafts? | D4 | Medium (by Aug 2027) | League draft history (O8) + 2027 captures (O2) |
| X19 | Does an equal-weight average of free sources beat calibrated ESPN weekly? | R4 | Low (O3) | Prospective 2027–28 |
| X20 | How reliable are usage features week to week (shrinkage constants)? | R7 | Low | Descriptive 2017–2025 |
| X21 | Does first-read target share add information beyond target share? | R7 | Low | 2023–24 → 2025 → 2027 |
| X22 | Are v0 K and D/ST distributions adequate for team-total variance? | P0/S0 | Medium | 2020–23 → 2024 batch |
| X23 | Is simulated matchup P(win) better calibrated than the normal approximation? | S1 | High | Replays 2020–23 → VL11 → 2027; real league descriptive |
| X24 | How reliable are simulated P(playoffs) odds? | S2 | Medium | **Descriptive** (replays, real league, ESPN `playoffPct` comparator) |
| X25 | **Real-league decision benchmark:** how does FFball's ex-ante lineup compare with each manager's actual lineup? | F6 complement | High | Prospective 2026 (sealed) and 2027; history 2018+ only with the owner's consent (O8) |
| X26 | How do ESPN's projections revise in response to realised residuals? (The learning model for P4/P5.) | P4 | Medium | Historical week-of values, dev 2020–23 → 2024 batch |

---

## 2. Experiment specifications

### X1. Prospective power and MDE (F1; analysis)

| Field | Content |
|---|---|
| **Question** | What ΔMAE (and ΔMSE) can each pre-registered 2026 test detect at 80% power? |
| **Data** | Existing week-level paired differences (E4/E5, E7, E10, E13/E14). |
| **Method** | <ul><li>σ_w = SD of week-level paired differences.</li><li>MDE = (t₀.₉₇₅,W−1 + t₀.₈₀,W−1)·σ_w/√W for **W ∈ {8, 10, 13, 14}** (2026 has at most 14 weeks), at **σ_w × {1, 1.5}**. Prospective σ_w may be larger because pre-inactive zeros enlarge errors.</li><li>**W5 is a structural-zero week** for the injury lineages.</li></ul> |
| **Safeguards** | No 2026 outcome is used. Committed before any 2026 scoring. |
| **Interpretation** | Where the MDE exceeds the historical effect, "insufficient" or "CI spans 0" means *underpowered*. The pre-registered **fixed-sample pooled 2026+2027** analysis is the secondary. E-processes provide optional stopping only, not extra power. |

### X2. Do residuals persist? (P4 first diagnostic)

| Field | Content |
|---|---|
| **Hypothesis** | Residuals against the rolling-origin calibrated base show positive within-season autocorrelation, so σ_L > 0. |
| **Data / method** | F4, dev 2020–2023. A player-season random-intercept model (`lme4`); lag-1 to lag-4 autocorrelations by position and band. |
| **Output** | ICC and σ_L with CIs (a parameter study; no pass/fail). |
| **Interpretation** | <ul><li>**ICC ≈ 0:** ESPN's per-player errors are noise. Player-level mean corrections have no basis; uncertainty is weekly noise plus attrition.</li><li>**ICC > 0:** level shocks matter. Bench upside and learning have value.</li></ul> |

### X3. Which distributional method is best? (P2; E20 → E22 batch)

| Field | Content |
|---|---|
| **Hypothesis** | An EMOS-style location–scale–shape model (C2), possibly with adaptive conformal recalibration (C3), beats C0 (P0) and C1 (IDR) on CRPS for F(y \| active, base), with coverage in the gate. |
| **Data** | F4, active rows of the ESPN-projected population. Dev 2020–2023 (2019 warm-up). **Check 2024 only**, in the distribution-stack batch (2025 lacks injury timestamps). |
| **Baselines** | C0 (empirical quantiles by position × fixed band); C1 (IDR on base). |
| **Candidates** | C2 (`mgcv::shash` or shifted ZAGA/Tweedie; family chosen in dev by CRPS); C3 (best plus ACI by position). |
| **Metrics** | <ul><li>**Primary:** CRPS (skill vs C0).</li><li>**Gate:** coverage ([05](05_modeling_strategy.md) §6).</li><li>**Secondary:** randomised PIT, MCB/DSC/UNC, interval score, threshold-weighted CRPS (≥ 20 points).</li></ul> |
| **Safeguards** | Bands and quantile levels are fixed beforehand. Fits are rolling-origin. Earlier horizons are built only via P1 and R3, never trained on historical post-inactive values. |
| **Success** | On 2024, ΔCRPS vs C0 < 0 (week-clustered CI) and not worse than C1; coverage gate passed. |
| **Interpretation** | <ul><li>**C0 or C1 wins:** spread is mainly a function of level, so keep the simple model.</li><li>**C2/C3 wins:** status and TD-share carry spread information.</li><li>**Position-specific coverage failure:** add a conformal correction.</li></ul> |

### X4. What predicts spread? (inside P2; closed covariate list)

| Field | Content |
|---|---|
| **Hypothesis** | Beyond level, spread rises with the TD-share of the projection, Questionable status and implied team total. It does not depend on defence-vs-position. |
| **Candidates** | Add one block at a time: status; TD-share; implied total and spread (2021+); shrunk volatility history. |
| **Keep rule** | Dev ΔCRPS < 0 (CI), with the sign stable in ≥ 3 of 4 dev seasons. The final model is chosen by X3's rule. |
| **Answers** | "How much does matchup or environment matter?" — for **spread**. The evidence says it barely matters for means. |

### X5. Calibration of P(active) (P1; E19 batch with X14)

| Field | Content |
|---|---|
| **Hypothesis** | A logistic GLMM (designation, practice, return, streak, previous designation, day of week, shrunk team effect) is better calibrated than a rate table at the **post-report** horizon for RB/TE/QB. |
| **Outcome** | Played at least one offensive snap. |
| **Data** | Final injury reports 2017–2024. Dev 2020–2023 (2017–18 extra training). **Check 2019** (batch). WR reported separately (contaminated). COVID-list sensitivity on 2020–21. |
| **Baseline** | Designation × practice × position rate table. |
| **Metrics** | Brier (primary); log loss; reliability; calibration slope. |
| **Early horizon** | Built outcome-free (designation transitions from 2026 captures × post-report model). Not a test target in 2026. |
| **Success** | 2019 pooled RB/TE/QB Brier-skill CI excludes 0 (Holm within the batch); slope rule per 05 §6. |
| **Interpretation** | <ul><li>**Pass:** P1 feeds PODs, scenarios and D0.</li><li>**Fail:** the rate table is the honest model.</li></ul> |

### X6. Does dependence matter? (P3 gate; E21)

| Field | Content |
|---|---|
| **Gate test (dev 2020–23)** | Under independence, are lineup totals calibrated? Use PIT and coverage of 1,000 random legal lineups per week from actual rosters. |
| **If the gate fails** | Candidates: team factor; team plus game factors; shrunk role-pair matrix. Pregame roles. Normal scores of PIT values. Batch-check on 2024. |
| **Metrics** | Lineup-total CRPS and PIT (primary); variogram score. |
| **Success** | 2024 lineup-total ΔCRPS CI < 0 against independence; coverage gate passed. |
| **Interpretation** | Answers "how important is modelling correlations?" A null at the gate is a useful finding: practitioner correlations are largely absorbed by shared projections. |

### X7. ROS uncertainty decomposition (P4; VL4)

| Field | Content |
|---|---|
| **Hypothesis** | ROS variance = level shock + weekly noise + attrition. Simulated rest-of-season distributions are calibrated. |
| **Method** | <ul><li>log L ~ N(−σ²/2, σ²).</li><li>σ_L by **simulation matching** on 2019–2023, with availability and noise drawn separately (no double counting).</li><li>Discrete-time attrition hazard.</li><li>Learning from X26.</li></ul> |
| **Baseline** | VE1 point forecast with a normal spread at the VE1c residual SD. |
| **Metrics** | Rest-of-season CRPS; coverage by position and w ∈ {4, 8, 12}. |
| **Success** | 2024 batch: coverage gate passed; CRPS skill CI < 0 against the baseline. |

### X8. Do better forecasts produce better decisions? (F6; VL11 batch) ★

| Field | Content |
|---|---|
| **Hypothesis** | Lineup and contested add/drop policies driven by (i) calibrated ESPN, (ii) calibrated ESPN plus availability adjustments, and (iii) distribution-aware values earn more realised lineup points than raw-ESPN policies. The gains are smaller than the accuracy differences suggest. |
| **Triage (outcome-free, first)** | Flip rates between policies. Per-position linear calibration with positive slope preserves within-position order, so (i) mostly changes FLEX choices. Compute this before spending any check. |
| **Data** | F6 replays: dev 2020–2023; **check 2025 (VL11 batch)**. Policy (ii) needs injury timestamps, so it runs on dev only and is confirmed in 2027. |
| **Metrics** | **Primary:** realised lineup points per team-week (week-clustered, season-blocked). **Secondary:** regret against hindsight-optimal; flip rate. Wins and playoffs descriptive. |
| **Safeguards** | Information firewall. ESPN week-t values are available only at kickoff. Tuesday decisions use data through t−1 only. |
| **Success** | Gains reported as estimates with CIs; MDE pre-declared. |
| **Interpretation** | Quantifies the translation from accuracy (ΔMAE, ΔCRPS) to decisions. This answers the owner's core question. |

### X9. Expected points vs P(win), and late-window decisions (D1; VL8, VL11)

| Field | Content |
|---|---|
| **Hypothesis** | Pre-kickoff, P(win) lineups differ from EV lineups in < 5% of team-weeks, with mean ΔP(win) < 0.005 (one prior measurement: 0/208 [alhart2015 2026]). Late-window conditional decisions flip more often. |
| **Triage (outcome-free)** | Model-implied flip rates and ΔP(win) on replay rosters. |
| **Kill rule** | If triage shows < 5% flips *or* model-implied mean ΔP(win) < 0.005, skip the full P(win) mode. Keep slotting and late-window features only. |
| **Note** | The top-half bonus (F3), if present, shifts the answer toward EV. |

### X10. Valuation metrics and the QB-hoarding hypothesis (S3; VL7)

| Field | Content |
|---|---|
| **(a)** | With level uncertainty and learning, the V1 fixed-point re-draft converges and rosters QBs within ±3 of the proportional pool. Model-based; **no outcomes needed**. This tests VE3's hypothesis about the cause of hoarding. |
| **(b)** | Among VOR, EVOR, MRU and wins added, which metric best predicts the **realised lineup-point gain from adding a player** at week w? F6 replays, week-level outcomes; dev 2020–23 → VL11. |
| **Success** | (a) as stated; (b) pre-registered selection of the primary display metric. |

### X11. Trades in wins units vs points (D2; outcome-free, plus ledger)

| Field | Content |
|---|---|
| **Question** | How often, and for which team states (contender, bubble, out of contention), do ΔU and ΔP(playoffs/title) rank candidate trades differently? |
| **Method** | Model-implied only, on 2026–27 league states. Kendall agreement; share of top-10 lists that differ. |
| **Outcome evaluation** | Prospective ledger (descriptive, sealed until VL11). |
| **Why no lab test** | Season-level outcomes (effective n ≈ seasons), synthetic opponents and missing historical as-of future weeks make historical trade tests invalid. |
| **Answers** | "Are probabilistic projections materially better for trade decisions?" Directly: how often they change the decision. Indirectly: prospective outcomes. |

### X12. Partner-lens check (D2; private, descriptive)

Does the partner lens show non-negative perceived gains for both sides of the league's **2026+** accepted trades, at λ ∈ [1, 2]?
- As-of reconstruction is impossible before 2026, because no historical posted future weeks exist (VE0).
- Rejections are unobservable.
- The lens is not refitted on these data before 2027.

### X13. Forecast horizon (R3; E17; outcome-free)

| Field | Content |
|---|---|
| **Hypothesis** | Early-week ESPN projections carry extra uncertainty, Var(final − early) > 0, that grows with lead time. The revisions are approximately martingale (uncorrelated successive revisions). |
| **Data** | FFball's dated 2026 captures (all positions via F0) and ESPN's after-the-fact **final projections**. **No outcomes.** |
| **Method** | Revision variance by position, band, lead time and status; correlation of successive revisions (martingale check). |
| **Output** | A horizon spread-inflation table with CIs, adopted into PODs by a pre-registered rule. |
| **Interpretation** | Sets how much early-week tools (waivers, trades) widen uncertainty. If revisions are *not* martingale (e.g., systematic early over-projection), a horizon-specific mean calibration is needed. That would be fit only on 2027+ data or outcome-free quantities. |

### X14. RB/TE/QB injury and practice effects (R2; E19 batch with X5)

- **Template:** M4.
- **Hypothesis:** calibrated ESPN over-projects RB (and TE) with Questionable or limited-practice status, with half-ratio multipliers.
- **Metrics:** primary **MSE** (MDE computed on MSE first, since heavy tails and small TE/QB samples cut power); MAE reported.
- **Seasons:** dev 2020–2023; **check 2019** (in-season calibration warm-up, weeks 1–4 excluded; a 2018 fetch is owner option O8).
- **Success:** dev pooled ΔMSE CI < 0 and 2019 ΔMSE < 0 (Holm within the batch).
- **Interpretation:** frozen lineages with a 2027 record. A null for some positions means ESPN already prices the effect there.

### X15. As-of implied totals (R5; inside X4/X6)

Implied totals and spreads as spread covariates (X4) and game-factor covariates (X6). Data: dev 2021–2023, then the 2024 batch. A null means markets add nothing beyond ESPN, even for variance.

### X16. Streaming with contested claims (D3; VL9, VL11)

- **Policies:** hold; stream by base projection; stream by distribution-aware value.
- **Opponents:** they also claim, by their projections and waiver order.
- **Primary metric:** realised points from the streamed slots (week-level).
- **Seasons:** dev 2020–23, then VL11 on 2025.
- **Success:** gain CI > 0 is required before D3 recommends streaming.

### X17. FAAB bidding (D3; gated)

Runs only if `isUsingAcquisitionBudget`.
- **Model:** b* = argmax P(win at b)·(v − λ_F b).
- **Inputs:** competitor-bid priors from public data; league bid history via `kona_league_communication` (type 180 bids, 2019+; O8).
- **Metrics:** calibration of P(win at b); surplus captured.
- **If history is thin:** present guidance as rules with stated assumptions.

### X18. ADP availability for this league's drafts (D4)

- **Model:** a two-piece normal around ESPN ADP with spread σ ≈ a + b·pick, wider for QB/TE.
- **Calibration data:** the league's own draft history (`mDraftDetail`, O8) and 2027 preseason ADP captures (O2).
- **Metric:** Brier of P(available at pick k).

### X19. Multi-source averaging (R4; O3)

Equal-weight average of calibrated ESPN plus at least two terms-permitting free sources, against calibrated ESPN. Weekly MSE; prospective only (2027–28 captures). Answers "which projection ensemble performs best?"

### X20. Usage-feature reliability (R7)

Within-season split-half reliability by position, 2017–2025 (seasons ingested from 2017). Gives empirical-Bayes shrinkage constants k = n(1−r)/r. Descriptive; no outcome model.

### X21. First-read share (R7)

FTN-derived first-read target share (2023+) against the target-share EWMA, for next-week targets. Dev 2023–2024 → check 2025 → prospective 2027. Answers "do advanced usage metrics improve predictions?" The prior is low, given M2's null.

### X22. K and D/ST adequacy (P0/S0; distribution batch)

Lineup-total PIT with v0 K/DST distributions against matchup-conditioned ones (implied totals, or ESPN K/DST projections if O8 allows). Dev 2020–23, then the 2024 batch. Upgrade only if team-total calibration fails.

### X23. Matchup P(win) calibration (S1; VL5, VL11)

- **Question:** simulated P(win) against the normal approximation.
- **Data:** F6 replays; matchups clustered by week. Dev 2020–23, then VL11 on 2025.
- **Metrics:** Brier, log loss, reliability.
- **Success:** non-inferior (upper CI of ΔBrier ≤ +0.005); slope rule per 05 §6.
- **Real league:** about 56 matchups per season, descriptive only.

### X24. Playoff-odds reliability (S2; descriptive)

Season-level outcomes have an effective n of about the number of seasons, so they are reported as **estimates only**:
- reliability across replay leagues (season-blocked);
- the real league;
- a prospective comparison with ESPN's own `playoffPct` (the external baseline).

### X25. Real-league decision benchmark (F6 complement) ★

| Field | Content |
|---|---|
| **Question** | Each week, how does FFball's ex-ante recommended lineup compare with each manager's actual lineup, on realised points? |
| **Data** | F3-full weekly lineups and box scores (O8). Prospective 2026 (outcomes sealed) and 2027. With the owner's consent, league history 2018+, scored with FFball's point-in-time forecasts where they exist; otherwise as-of ESPN final values, labelled late-horizon. |
| **Metrics** | Realised points: recommended vs actual lineup. Regret against hindsight-optimal, per manager. |
| **Why** | Real rosters and real opponents, with no synthetic assumptions. It also yields the manager-behaviour profiles S1 needs. |
| **Privacy** | Results stay local. Only hashes are committed. |

### X26. ESPN revision dynamics (P4 learning model)

| Field | Content |
|---|---|
| **Question** | How does ESPN's next-week projection respond to the player's realised residual this week (over-reaction to role changes; E5)? |
| **Data** | Historical week-of (final) ESPN values and actuals, dev 2020–2023; 2024 in the distribution batch. |
| **Method** | Regress the next-week projection change on the residual and on usage changes, by position and band. |
| **Use** | The empirical learning rule for simulated lineup policies (P4/P5), replacing a theoretical normal–normal update. |

---

## 3. How the experiments answer the owner's example questions

| Owner's question | Experiment(s) | What the evidence already says |
|---|---|---|
| Which projection ensemble performs best? | X19 (prospective) | Averages beat single sources season-long; weekly evidence is qualitative; cannot be backtested |
| Do advanced usage metrics improve predictions? | X20, X21 (and M2's null) | No evidence of gains beyond ESPN or consensus |
| How much does matchup adjustment help? | X4 (for spread) | Little to nothing for means |
| Are probabilistic projections materially better for trade decisions? | X11 (decision divergence), prospective ledger | Theory says yes for nonlinear objectives; historical tests invalid |
| Which valuation method best predicts actual roster improvement? | X10(b) | No outside validation of any VBD baseline |
| How important is modelling player correlations? | X6 gate, X23 | Real but conditional effects unknown; may be absorbed by projections |
| Does optimising expected points differ from optimising win probability? | X9 (triage first) | 0/208 flips in the one measurement; late windows untested |
| Which data sources justify their cost? | X15, X19, X21, plus the protocol below | Free sources only; markets likely help variance, not means |

**Source-value protocol** (for any proposed new data source):
1. Point-in-time audit: timestamps, licence, coverage, horizon.
2. Outcome-free triage: could it change any decision?
3. A pre-registered closed experiment adding only that source to the current best model, with the MDE stated.
4. Adopt it only if the gain outweighs its maintenance cost ([08](08_prioritization.md)).
