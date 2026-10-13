# 01 — Executive Vision

*FFball master plan, written 2026-10-13 during 2026 Week 6. This is a research and planning deliverable
only: no models, data or frozen artefacts were changed.*

---

## The one-sentence vision

**FFball becomes a fantasy-football intelligence platform. It forecasts every player's outcomes as
calibrated probability distributions, simulates the owner's actual league week by week, recommends
lineups, trades, waiver claims and draft picks in the currency that matters (wins and championship
odds), and keeps a tamper-evident record that tests whether those recommendations work.**

---

## What the research established

### 1. Do not try to out-project the market on the mean

- FFball's own pre-registered milestones (M1–M4) showed that ESPN's final pregame projection, linearly recalibrated, beats or ties every feature model built from public data.
- The outside evidence points the same way:
  - crowd averages beat every single projection source;
  - betting markets beat models and experts on NFL games;
  - student and thesis ML models lose to ESPN or turn out to be leaky;
  - ESPN's own AI system feeds ESPN projections *into* its ensemble rather than replacing them.
- The only replicated gains are calibration and **availability information** (injury designation and practice status), plus averaging independent sources. The averaging evidence is season-long and quantitative, but only qualitative for weekly projections.

### 2. Uncertainty is the open frontier

- No fantasy platform publishes *systematic* calibration evidence (interval coverage, PIT, CRPS or Brier) for its floors, ceilings, boom/bust labels or win probabilities. One vendor reported a single preseason coverage figure.
- Weather and probabilistic forecasting have mature tools that transfer directly:
  - proper scoring rules;
  - ensemble post-processing (EMOS);
  - isotonic distributional regression;
  - conformal prediction.
- CRPS equals absolute error for a point forecast, so FFball's archived point forecasts become deterministic baselines on the same scale.
- One subtlety governs everything: historical ESPN values are *post-inactive*. Distributions are therefore built as P(active | horizon) × F(points | active) for each decision time.

### 3. Value is contextual, nonlinear and best measured in wins

- A point is worth more to a team on the playoff bubble than to a runaway leader.
- A trade can be "fair" in points yet decisive in title odds.
- FFball's existing ΔU engine already captures roster context. The missing pieces are:
  - **distributions**, for bench upside and risk;
  - **the league's schedule and rules**, for wins, playoffs and titles.

### 4. Better forecasts do not automatically mean better decisions

- Decisions are argmax and threshold operations, so tiny accuracy gains rarely change them.
- In season-long head-to-head play, maximising win probability changes few lineups before kickoff (0 of 208 team-weeks in the one direct measurement found). It matters more in late lock windows.
- FFball should therefore **measure decision quality directly**, on realised outcomes. No platform does this.

### 5. Proving improvements is a statistical-power problem

- The unit of evidence is the *week*.
- FFball's real effects are small (ΔMAE ≈ 0.01). Its 2026 prospective tests have roughly 35–50% power, and Week 5 was lost for the injury models.
- The answers:
  - a pre-registered **pooled 2026 + 2027 analysis**, with the frozen-model runtime pinned so 2027 runs the same models. Anytime-valid monitoring buys optional stopping, not power.
  - a contamination register that spends each historical check season **once, in batches**, so each new question family uses history honestly;
  - judge new work by its effect on decisions, measured on realised outcomes;
  - keep 2026 outcomes sealed from all development.

---

## What the platform will do (most valuable capabilities)

| Capability | What the owner gets | Why it is valuable | When |
|---|---|---|---|
| **Calibrated player outcome distributions** | For every player-week: P(active), median, floor, ceiling, boom/bust probabilities, coverage-checked | The foundation for every probability below. Nobody else validates theirs. | v0 this season (P0); calibrated v1 early 2027 (P2) |
| **League simulator** | P(win) for each matchup; E[wins], P(playoffs), P(bye), P(title); weekly leverage; what-if scenarios | Turns points into the outcomes that pay | Shadow v0 this season if the trade deadline allows (S0); end-to-end thin slice by April 2027; calibrated 2027 (S1, S2) |
| **Trade engine in wins units** | ΔP(playoffs/title) for **both** teams; win-win search; the frontier between your gain and what the other manager *perceives* (no fitted acceptance model); buy-low/sell-high signals; ΔP(title) explained by wins, seeding and playoff-week points | The highest-leverage in-season decision; no tool evaluates both teams' title odds | Thin slice early 2027; full 2027 (D2) |
| **Lineup engine** | EV lineups with latest-kickoff FLEX slotting; game-time decision plans; late-window win-probability moves; decision confidence | Small but certain weekly gains | Helpers this season (D0); full 2027 (D1) |
| **Waiver and FAAB assistant** | A free-agent board in ΔU and ΔP(playoffs); drop advice; streaming plan tested against contested claims; FAAB bids that shade correctly, if the league uses FAAB | Frequent decisions; no documented FAAB method exists anywhere | 2027 (D3) |
| **Draft assistant** | Pick advice that maximises season odds, using ADP survival and simulated opponents | Once a year, high leverage | August 2027 (D4) |
| **Weekly briefing** | One local report before each slate: everything above, explained from model numbers | Usability | 2027 (D5) |
| **Accountability** | A ledger of every forecast and recommendation, regret reports, calibration monitors, a decision laboratory | Proves, or disproves, that the platform helps | Ledger this season (F5); lab early 2027 (F6) |

---

## Architecture: one probabilistic backbone shared by every tool

```
                ┌───────────────────────────────────────────────────────────────┐
DATA            │ point-in-time warehouse: nflverse · ESPN captures · league state │  (immutable, hashed)
                └───────────────────────────────────────────────────────────────┘
                                  │ as-of joins only
FORECASTS       base means (calibrated ESPN + validated adjustments)  ─┐
                availability P(active | horizon)                       ├─► player outcome distributions (POD)
                conditional distributions (EMOS / IDR / conformal)    ─┘
                dependence (team & game factors, copula) · season dynamics (level shocks, attrition)
                                  │
SCENARIOS       joint draws: players × weeks × sims, common random numbers,
                lineups chosen at decision time (never in hindsight)
                                  │
LEAGUE          rules · rosters · schedule · standings  ─► matchup sim ─► season / playoff sim
                                  │
DECISIONS       lineups · trades (two-team, partner lens) · waivers / FAAB · draft
                                  │
EVIDENCE        ledger · decision laboratory · proper scores · anytime-valid monitors · contamination register
```

**Design commitments**
- **One scenario set per run feeds every tool,** so lineup, trade, waiver and playoff numbers are mutually consistent.
- **Information-set discipline:** every output is computed only from what was knowable at its decision time.
- **Typed interfaces between layers.** POD table, scenario set, league state and decision record make components swappable. The existing provider abstraction already proves the pattern.
- **Stay in R and `targets`. Stay toolchain-free on Windows. No services.** Every recommended method has a CRAN binary. Stan is optional and would be the owner's decision.
- **The protocol is part of the product:** pre-registration, frozen versions, fingerprints, prospective archives pushed before kickoff, never backfilling. It extends from projections to distributions and decisions.

---

## Strategic direction

1. **Protect the evidence now.**
   - **Step 0:** manual Week 6 runs on Thursday and Saturday/Sunday, pushed before kickoff.
   - **F0:** a dispatcher keyed to kickoff times, with all-position captures.
   - **F1:** a power and analysis addendum committed before any 2026 outcome is scored.
2. **Build the probabilistic backbone** (P0 → P5) on historical seasons that are still clean for these new questions, with pre-registration.
3. **Simulate the league** (S0 → S2) and **value in wins** (S3).
4. **Optimise decisions** (D0 → D5), each with an explicit kill rule where the evidence is thin.
5. **Measure everything that matters** (F2, F5, F6, I3), above all whether decisions improve.
6. **Keep a narrow projection-science track** (R1–R7) for the few places where an edge is plausible:
   - availability for other positions;
   - forecast horizons;
   - market context for variance;
   - resilience against losing ESPN.

## What success looks like by the end of the 2027 season

- Player distributions pass the coverage gate prospectively: clustered CIs of 50/80/90% coverage overlap ±3 pp at every position, with Holm adjustment.
- P(active) and matchup P(win) are reliable: the calibration-slope CI includes 1 and the estimate is within [0.8, 1.2]. Playoff odds are reported descriptively, because there are too few seasons to test them.
- Each decision policy's value (lineup, waiver, streaming) is *estimated with honest CIs* on 2025 replays and the 2027 prospective record. Kill rules have retired the ideas that didn't pay.
- Every recommendation is ledgered; hashes are pushed before kickoff; the 2026 pre-registered tests are scored exactly as written.
- The owner receives one coherent weekly briefing instead of a set of separate scripts.

## What we will deliberately *not* do

| Not doing | Why |
|---|---|
| Broad ML or feature searches for weekly means | Replicated nulls |
| Defence-vs-position, weather and similarity models | Weak or no evidence |
| Deep reinforcement learning, bandits, play-level game simulators | No faithful opponent simulator; circular validation; no evidence |
| News or LLM scraping | No point-in-time archive; terms risk |
| Paid data | Standing owner rule |
| Anything that changes frozen lineages, fingerprints or manifests, or that publishes private league or ESPN-derived row-level data | Protocol and privacy rules |

---

**Documents in this plan:**

| File | Contents |
|---|---|
| [02_research_landscape.md](02_research_landscape.md) | Evidence |
| [03_current_system_assessment.md](03_current_system_assessment.md) | Where FFball stands |
| [04_analytics_opportunities.md](04_analytics_opportunities.md) | 70-capability catalog |
| [05_modeling_strategy.md](05_modeling_strategy.md) | Methods |
| [06_data_infrastructure.md](06_data_infrastructure.md) | Data and infrastructure |
| [07_master_roadmap.md](07_master_roadmap.md) | **The plan** |
| [08_prioritization.md](08_prioritization.md) | Ranking |
| [09_experiment_backlog.md](09_experiment_backlog.md) | Experiments |
| [10_sources.md](10_sources.md) | Bibliography |
| [11_next_steps.md](11_next_steps.md) | First actions |
