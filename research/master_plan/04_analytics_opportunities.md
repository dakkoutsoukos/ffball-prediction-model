# 04 — Analytics Opportunity Catalog

*A catalog of fantasy analytics capabilities FFball could build. It includes capabilities FFball already
has, capabilities the owner listed, and capabilities found during the research (marked ✦). Evidence and
methods are in [02](02_research_landscape.md) and [05](05_modeling_strategy.md); milestone ids refer to
[07](07_master_roadmap.md).*

**Legend**

| Column | Values |
|---|---|
| **Status** | ✅ exists · ◐ partial · ○ new |
| **Difficulty** | S / M / L / XL (sessions: 1–2 / 3–5 / 6–10 / >10) |
| **Evidence** (that it works) | Strong / Moderate / Weak / None |
| **Priority** | **Now** = Phases 0–1, 2026 season · **2027** = Phases 2–4 · **Later** = optional · **Park** = not recommended |
| **Ids** | Row ids OA1…OF14 are *catalog* ids. Milestone ids in the "Depends on" and "Priority" columns (F*, P*, S*, D*, R*, I*) refer to the roadmap. |

---

## A. Projections and forecasts

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OA1 | Calibrated base projections, all positions | ◐ | Unbiased weekly means | Weekly-refit linear calibration of ESPN (M2 family) | ESPN week-of history | E[points] per player-week | Core input everywhere | — | S | Strong (E2, E5) | Now |
| OA2 | Availability-adjusted projections (RB/TE/QB) | ○ | Correct systematic over-projection of listed players | Pre-registered rules (M4 template) | Injury reports, practice status | Adjusted means | Start/sit; valuation | F4 | M | Moderate (WR replicated) | 2027 (R2) |
| OA3 | ✦ Weekly outcome distributions (POD): floors, ceilings, boom/bust | ○ | Uncertainty for every decision | Empirical, then EMOS/IDR/conformal; CRPS | Base, status, context | Quantiles, P(≥ x) | Foundation for odds, risk, value | F2 | S (v0) → L | Strong methods; untested in fantasy | Now (P0) → 2027 (P2) |
| OA4 | ✦ Horizon-aware forecasts (Tue vs kickoff) | ○ | Match forecasts to decision time | Horizon-specific calibration | Multi-time captures | Horizon-specific POD | Waiver and trade decisions early in the week | F0 | S–M | Moderate (54–72% ESPN identity) | Now (data) → 2027 |
| OA5 | Rest-of-season projections with uncertainty | ◐ | Trades, drops, playoff odds | Level shocks + weekly noise + attrition | VE1 frame | ROS POD | High | P2 | M | Moderate (VE1c) | 2027 (P4) |
| OA6 | ✦ Stat-component projections and exact rescoring | ◐ | Any scoring format; structured uncertainty | Linear rescoring of E[stats]; component calibration | ESPN projected components | Points under the league's rules | Needed for non-PPR leagues | F3 scoring map | M | Strong (math) | 2027 |
| OA7 | Multi-source consensus | ○ | Only evidenced route to better means | Equal-weight forecast combination | Other free sources (terms) | Consensus mean | Moderate | Owner decision | M | Moderate (season-long) | Later (R4) |
| OA8 | ✦ ESPN-independent fallback model | ○ | Resilience if ESPN access is lost | Top-down volume × share × efficiency, shrinkage | nflverse, lines | Means at parity | Insurance | F4 | L | Weak | Later (R6) |
| OA9 | Team environment from market lines | ◐ | Game-script covariates for spread and correlation | Implied totals = (total ± spread)/2 | nfldata as-of lines | Team totals | Moderate | F4 | S | Moderate (markets) | 2027 (R5) |
| OA10 | ✦ K and D/ST distributions | ○ | Team-total variance for P(win) | Empirical v0; matchup-conditioned later | ESPN K/DST slot projections (O8), or nflverse scoring under league rules (points-allowed tiers, return TDs) | POD for K/DST | Needed for odds | F3 | M | Moderate (Subvertadown) | Now (S0, v0) |
| OA11 | Rookie / preseason projections | ○ | Draft-season value | Draft capital, priors | Draft, combine | Season means | Low in season | — | M | Weak | Park (2027 preseason uses ESPN) |
| OA12 | Aging curves, multi-season | ○ | Keeper and dynasty | Delta method with imputation | Multi-season stats | Age adjustments | Only if keepers | — | M | Weak (NFL) | Park |
| OA13 | Similarity (comparables) projections | ○ | Distribution shapes | k-NN | Player seasons | Comparable distributions | Low | — | M | None (NFL) | Park |
| OA14 | ✦ ESPN revision-dynamics model | ○ | Model how ESPN updates projections after a player's realised residual (E5: over-reaction). This is the empirical "learning" rule for simulated lineups. | Regression of next-week projection change on residual and usage change | ESPN week-of history | Revision-response parameters | Bench option value; realistic learning | F4 | S–M | Moderate (E5 residual study) | 2027 (P4, X26) |

## B. Player analytics and metrics

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OB1 | Usage dashboard (target/carry/snap share, xFP, role rank) | ◐ (features exist) | Explain projections; spot role changes | Lagged shares, EWMA | nflverse | Tables | Explanatory | F4 | S | Strong for description | Later (D5 panel) |
| OB2 | Regression indicators (FPOE, TDs over xTD) with shrinkage | ○ | Flag luck-driven scoring | Empirical-Bayes shrinkage | ffopportunity (pinned) | Shrunk indicators | Explanatory; trade timing | OB1 | S | Moderate (TDs regress) | Later |
| OB3 | ✦ Usage reliability / stabilisation table | ○ | Principled shrinkage constants | Split-half + Spearman–Brown | nflverse 2016–25 | k per feature | Research infrastructure | F4 | S | Strong method | Later (R7/X20) |
| OB4 | First-read target share | ○ | Test a claimed sticky metric | Incremental prediction | FTN (2023+) | Feature and test | Low | OB3 | M | Weak (proprietary) | Later (R7/X21) |
| OB5 | ✦ ESPN over-reaction and return-from-absence flags | ◐ (M3 rules) | Explain where ESPN errs | Residual rules (M3) | M3 features | Flags | Small but real | — | S | Moderate (E7) | Exists |
| OB6 | Breakout detection | ○ | Early pickups | Usage change vs ESPN at the same snapshot | Snapshots, usage | Candidates | Potentially high; unproven | R3 | M | None | Later (test in D3) |

## C. Valuation

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OC1 | Generic VOR / VAS / MRU / display value | ✅ (V1) | Cross-position comparison | Exact allocation, exchange baselines | ROS, league | Values | High | — | — | Moderate | Exists |
| OC2 | League-specific ΔU and marginal team value | ✅ (V2) | Team-context value | Before/after optimised lineups | League state | ΔU, MTV matrix | High | — | — | Strong (logic) | Exists |
| OC3 | ✦ Expected VOR (distribution-aware) | ○ | Bench upside | E[Σ max(0, X − R)] [Stuart 2013] | P4, P5 | EVOR | Fixes bench undervaluation | P4 | M | Moderate | 2027 (S3) |
| OC4 | Wins added and title-equity values | ○ | The currency that matters | Common-random-number with/without simulation; decision-time lineups | P5, S2 | ΔE[wins], ΔP(title) | Very high | S2 | M | Moderate (logic; ffsimulator) | 2027 (S3) |
| OC5 | Playoff-schedule-weighted value | ○ | Weeks 15–17 matter most | Falls out of title-equity simulation | S2 | Value by segment | High for contenders | S2 | S | Strong (logic) | 2027 |
| OC6 | ✦ Player risk profile (volatility, availability risk) | ○ | Risk-aware decisions | POD spread, P(active), hazard | P1, P2, P4 | Risk metrics | Moderate | P2 | S | Moderate | 2027 |
| OC7 | ✦ Market-perception value and buy-low / sell-high | ○ | Exploit gaps between perceived and contextual value | Partner lens vs context ΔU/ΔP | ESPN raw, S3 | Signals | High (trades) | D2 | M | Weak (behavioural) | 2027 (D2) |
| OC8 | Dynasty / keeper values | ○ | Multi-season | Age curves, discounting | Multi-season | Values | Only if keepers | OA12 | L | Weak | Park (conditional) |
| OC9 | Auction values | ○ | Auction drafts | Surplus value → dollars | ROS | Values | Only for auction leagues | — | M | Weak | Park (conditional) |

## D. League simulation

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OD1 | Matchup win probability | ○ | Weekly odds; lineup decisions | Simulation from POD + dependence; normal approximation as baseline | P0/P2, P3, F3 | P(win), margin | High | F3, P0 | M | Moderate (methods); no platform calibration | Now (S0, if the deadline allows) → 2027 (S1) |
| OD2 | Season, playoff and title odds | ○ | Trades, waivers, strategy | nflseedR-style Monte Carlo with level shocks | F3, P5 | E[wins], P(playoffs/bye/title) | Very high | F3 | M | Strong (architecture) | Now (S0) → 2027 (S2) |
| OD3 | ✦ Luck-adjusted standings (all-play, expected wins) | ○ | Separate luck from strength | All-play record; expected wins | F3 | Tables | Moderate; cheap | F3 | S | Strong (definition) | Now (with S0) |
| OD4 | Remaining fantasy strength of schedule | ○ | Contextualise odds | Opponents' simulated strength | S2 | SOS | Moderate | S2 | S | Moderate | 2027 |
| OD5 | Power rankings (points, wins, odds) | ◐ (V2 points) | League overview | — | S2 | Rankings | Moderate | S2 | S | — | 2027 |
| OD6 | What-if scenarios (injury, trade, waiver) | ○ | Decision exploration | Forced states in the simulation | S2 | ΔOdds | High | S2 | S | Strong (logic) | Now (S0) → 2027 |
| OD7 | ✦ Weekly leverage | ○ | Prioritise must-win weeks | P(playoffs \| win) − P(playoffs \| loss) | S0/S2 | Leverage by week | High late in season | S0 | S | Strong (logic) | Now (S0) |
| OD8 | ✦ ESPN playoff-odds comparator | ○ | External benchmark | Log ESPN's `playoffPct` field | F3 | Comparison | Credibility | F3 | S | — | Now |

## E. Decision optimisation

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OE1 | Expected-points lineup optimiser (exact FLEX) | ✅ | Weekly lineups | Matroid greedy | Projections, league | Lineup | High | — | — | Strong | Exists |
| OE2 | ✦ Latest-kickoff FLEX slotting | ○ | Keep options open at zero cost | Lexicographic allocation | Kickoffs | Slotting | Small, certain | OE1 | S | Strong (logic) | Now (D0) |
| OE3 | ✦ Game-time decision plan | ○ | Handle Questionable starters | P(active) × pivot availability | P(active), kickoffs | Pivot plan | Moderate | OE2 | S | Moderate | Now (D0) |
| OE4 | Late-window conditional optimiser | ○ | Use realised early scores | Conditional P(win) | Live scores, S1 | Lineup changes | Moderate, occasional | S1 | M | Theory; frequency unknown | 2027 (D1) |
| OE5 | Win-probability lineup mode | ○ | Variance-aware lineups | Mean–variance threshold [Haugh & Singal] | S1 | Lineup | Small pre-kickoff | S1 | M | Weak (0/208 flips) | 2027, behind a kill rule |
| OE6 | ✦ Decision confidence: P(A beats B) | ○ | Communicate certainty | Paired scenarios | P5 | Probabilities | High for trust | P5 | S | Strong (logic) | 2027 |
| OE7 | Trade analyzer in wins and title units, both teams | ○ | Highest-leverage decisions | Common-random-number season simulation | S2, S3 | ΔE[wins], ΔP | Very high | S2 | L | Moderate | 2027 (D2) |
| OE8 | Trade finder with partner lens and Nash ranking | ◐ (V2 search) | Find acceptable win-win trades | Nash product; loss-aversion sensitivity | D2 inputs | Ranked offers | High | OE7 | M | Weak (acceptance) | 2027 (D2) |
| OE9 | Multi-team trades | ○ | Complex deals | Exchange cycles | — | — | Low | — | L | None | Park |
| OE10 | Free-agent and waiver board with drop recommendations | ◐ (V2 diagnostics) | Frequent decisions | ΔU / ΔP over a k-week lookahead | S3 | Ranked adds and drops | High | S3 | M | Moderate | 2027 (D3) |
| OE11 | FAAB bid guidance | ○ | Win claims without overpaying | First-price auction with a common value; shading | Bid priors, league history | Bid | High (FAAB leagues) | F3 | M | Weak (practitioner) | 2027 (D3) |
| OE12 | ✦ Waiver-priority option value | ○ | When to spend priority | Option value via simulation | S2 | Claim / hold advice | Moderate | OE10 | S | None (gap) | 2027 |
| OE13 | Streaming planner (K, D/ST, QB) | ○ | Cheap weekly gains | Matchup-driven POD | A10, R5 | Schedule | Moderate | F6 test | S | Moderate (self-reported) | 2027 (X16) |
| OE14 | ✦ Bye-week and roster-construction planner | ◐ | Avoid bye stacks; roster balance | Weekly allocation over the rest of the season | ROS, schedule | Warnings | Moderate | — | S | Strong (logic) | 2027 (S3 risk report) |
| OE15 | ✦ Handcuff / contingent value | ○ | Value backups correctly | Joint availability (starter out → backup role) | P1, depth charts | Contingent value | Moderate | P5 | M | Weak (Lee & Liu found no win-rate effect) | Later |
| OE16 | Draft assistant and mock simulator | ○ | Once-a-year, high-leverage | ADP survival, Monte Carlo opponents, S2 objective | ADP capture | Pick advice | High (August) | S2 | L | Weak–moderate | 2027 (D4, by Aug) |
| OE17 | Keeper decisions | ○ | Keeper leagues | Multi-season value | OC8 | Keep or cut | Only if keepers | OC8 | M | Weak | Park (conditional) |
| OE18 | ✦ Trade-deadline timing / value of waiting | ○ | When to act | Value of information under injury uncertainty | S2, P1 | Act / wait | Moderate | S2 | S | Moderate (decision theory) | 2027 |
| OE19 | ✦ League trade-fairness monitor | ○ | Evaluate other teams' trades, e.g., for veto votes | Two-lens ΔU / ΔP for both sides | League transactions (O8) | Fairness report | Low–moderate | D2 | S | Strong (logic) | Later (optional) |

## F. Evaluation, accountability and platform

| # | Capability | Status | Purpose | Statistical foundation | Inputs | Outputs | Usefulness | Depends on | Diff. | Evidence | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OF1 | Prospective forecast archive and pre-registration | ✅ | Honest evidence | Hash manifests, frozen lineages | — | Records | Very high | — | — | Strong | Exists (extend to POD) |
| OF2 | ✦ Decision ledger and regret | ○ | Test whether recommendations work | Regret against hindsight-optimal | All tools | Ledger now; regret reports after unsealing (2027 pre-registrations) | Very high | — | S | Strong (Murphy 1993) | Now (F5, records only) |
| OF3 | ✦ Decision laboratory (historical replay) | ○ | Out-of-sample policy evaluation on realised outcomes | Paired replays, clustered inference | F4 | Policy comparisons | Very high | F4 | L | Moderate (simulation literature) | 2027 (F6) |
| OF4 | ✦ Calibration monitors and anytime-valid alarms | ○ | Detect drift | E-processes; reliability diagrams | Archives | Alerts | High | F2 | S | Strong (theory) | 2027 (I3) |
| OF5 | ✦ Contamination register and leakage audits | ○ | Protect holdout integrity | Register; Kapoor–Narayanan taxonomy | — | Asserts | Very high | — | S | Strong | Now (F2) |
| OF6 | ✦ Opponent / manager behaviour profiles | ○ | Realistic opponent lineups; acceptance priors | Lineup efficiency; activity stats (shrunk) | League history | Profiles | Moderate | F3 | S | Moderate | Now (F3) |
| OF7 | Accuracy scoreboard (aggregate metrics may be committed, as in the existing logs; row-level data stays private) | ◐ | Transparent accountability | Proper scores | Archives | Scoreboard | High (credibility) | F2 | S | — | 2027 |
| OF8 | Weekly intelligence briefing with explanations | ◐ (V2 report) | Usable product | Model-number explanations | All | Report | Very high | D1–D3 | M | — | 2027 (D5) |
| OF9 | Local dashboard | ○ | Navigation | — | Briefing | UI | Moderate | OF8 | M | — | Later (I2) |
| OF10 | ✦ Experiment scaffolds (templates for pre-registration, registry, fingerprint, check) | ◐ | Faster, safer research | Protocol automation | — | Templates | High (velocity) | F2 | S | — | 2027 (I1) |
| OF11 | ✦ Operations automation and coverage alarms | ○ | Never miss a slate | Scheduling | — | Runs, alerts | Very high | — | S | Strong (W5 gap) | Now (F0) |
| OF12 | ✦ ESPN API health and cookie-rotation detection | ○ | Reliability | 401 detection | — | Alerts | High | — | S | — | Now (F0/I3) |
| OF13 | ✦ Real-league decision benchmark | ○ | Compare FFball's ex-ante lineup with each manager's actual lineup on realised points: real rosters, real opponents | Paired realised-points comparison; regret per manager | Weekly lineups and box scores (F3-full, O8) | Benchmark (private; sealed in 2026) | Very high | F3, F5 | S–M | Strong (logic) | 2027 (X25) |
| OF14 | ✦ Outcome-free triage toolkit | ○ | Spend no evidence on experiments that cannot matter | Flip rates, model-implied gains, revision variance, MDE | Forecasts only | Triage reports | High (protects data) | F2, F6 | S | Strong (logic) | 2027 |

---

## Opportunities found independently during the research (✦), and why they matter

1. **Decision ledger plus decision laboratory (OF2, OF3; roadmap F5, F6).** No platform measures decision quality. Without these, FFball cannot answer its central question (X8).
2. **Horizon-aware forecasting (OA4; roadmap R3).** ESPN's early-week projections differed from the final ones for 28–46% of players in the three Wayback comparisons FFball made (`docs/espn_projections.md`). Tools used on Tuesday need wider distributions than tools used at lock. FFball can estimate the gap **without outcomes**, from revision variance. Historical ESPN values are post-inactive, which makes this horizon distinction essential.
3. **Contamination register (OF5; roadmap F2).** All historical seasons are spent for WR means, but *not* for other question families. Making this explicit unlocks honest development for the new layers.
4. **Lineup helpers at zero cost (OE2, OE3; roadmap D0) and weekly leverage (OD7; roadmap S0).** Small, certain gains, available this season.
5. **ESPN playoff-odds comparator (OD8; roadmap F3).** ESPN already computes playoff odds (`currentSimulationResults.playoffPct`) without documenting a method. Logging it gives a free benchmark.
6. **Partner lens and buy-low/sell-high signals (OC7; roadmap D2).** These separate "fair" (perceived) from "advantageous" (contextual), which is the distinction the owner asked about.
7. **Manager-behaviour profiles (OF6; roadmap F3).** Opponents' lineup efficiency moves P(win). ffsimulator assumes 77.5% efficiency for every team. FFball can measure each team's actual efficiency.
8. **Stat-component rescoring (OA6).** Prerequisite for any non-PPR league, and for exact threshold bonuses.
