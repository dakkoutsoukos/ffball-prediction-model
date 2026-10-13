# 08 — Prioritization Matrix

*Every initiative in the roadmap is scored with one weighted framework. The scores are checked for
robustness under two alternative weightings, and the results are translated into an order of work.
Initiative ids match [07](07_master_roadmap.md).*

---

## 1. Scoring framework

Each initiative is scored from 1 to 5 on eight criteria. Two of them, effort and maintenance, are scored *inversely*: 5 means small effort or a light maintenance burden.

| Criterion | Code | Weight | 5 means | 1 means |
|---|---|---|---|---|
| Decision impact | DI | **0.20** | Directly improves frequent or high-leverage fantasy decisions | No direct decision effect |
| Predictive or calibration impact | PA | 0.10 | Large, measurable gain in forecast accuracy or calibration | None |
| Unlock and dependency value | UV | **0.20** | Prerequisite for many later capabilities | Leaf node |
| Evidence that it works | EV | 0.15 | Strong theory or replicated results | No evidence, or evidence against |
| Feasibility and data availability | FE | 0.15 | Free data in hand; no blockers | Blocked by data, terms or owner decisions |
| Effort (inverse) | EF | 0.10 | 1–2 sessions | More than 10 sessions |
| Maintenance burden (inverse) | MB | 0.05 | Set and forget | Constant upkeep or fragile scrapers |
| Strategic differentiation | SI | 0.05 | Something no other platform offers with documented methods | Commodity |

**Weighted score** = Σ weight × score, on a scale of 1–5.

Decision impact and unlock value carry the most weight, because the owner's goal is better decisions, and because the roadmap is a dependency chain where foundations multiply value.

**Two robustness views** are reported:
- **Equal weights** (every criterion 0.125).
- **Decision-heavy:** DI 0.35, PA 0.05, UV 0.15, EV 0.15, FE 0.10, EF 0.10, MB 0.05, SI 0.05.

**Classification rules:**

| Class | Rule |
|---|---|
| **Quick win** | Effort score ≥ 4, and weighted score ≥ 3.0, *or* time-critical |
| **Foundational** | UV ≥ 4 |
| **High-impact project** | DI ≥ 4, and not foundational |
| **Research bet** | EV ≤ 3, and not foundational |
| **Parked** | Weighted score < 2.2, or evidence against |

---

## 2. Initiative matrix

| Rank | id | Initiative | DI | PA | UV | EV | FE | EF | MB | SI | **Weighted** | Equal | Decision-heavy | Class |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | P2 | Calibrated outcome distributions v1 | 4 | 5 | 5 | 4 | 5 | 3 | 4 | 5 | **4.40** | 4.38 | 4.25 | Foundational |
| 2 | S2 | Season and playoff simulator v1 | 5 | 2 | 5 | 4 | 4 | 3 | 3 | 5 | **4.10** | 3.88 | 4.30 | Foundational |
| 3 | P4 | Season dynamics (ROS distributions) | 4 | 4 | 5 | 4 | 4 | 3 | 3 | 4 | **4.05** | 3.88 | 4.00 | Foundational |
| 4 | F2 | Evaluation framework v2 and contamination register | 2 | 3 | 5 | 5 | 5 | 3 | 4 | 4 | **3.90** | 3.88 | 3.55 | Foundational |
| 5 | F0 | Prospective operations hardening | 2 | 3 | 4 | 5 | 5 | 5 | 4 | 3 | **3.85** | 3.88 | 3.55 | Quick win + foundational |
| 5 | F3 | League state v2 | 4 | 1 | 5 | 4 | 4 | 4 | 3 | 4 | **3.85** | 3.63 | 3.95 | Foundational |
| 5 | P0 | Baseline outcome distributions (v0) | 3 | 3 | 4 | 4 | 5 | 4 | 4 | 4 | **3.85** | 3.88 | 3.70 | Quick win + foundational |
| 5 | S1 | Matchup win probability v1 | 4 | 3 | 4 | 4 | 4 | 3 | 4 | 5 | **3.85** | 3.88 | 3.90 | Foundational |
| 9 | P1 | Availability model v2 (all positions) | 4 | 4 | 4 | 4 | 4 | 3 | 3 | 3 | **3.80** | 3.63 | 3.80 | Foundational |
| 10 | F4 | Position-general historical frame | 3 | 3 | 5 | 4 | 4 | 3 | 4 | 3 | **3.75** | 3.63 | 3.60 | Foundational |
| 10 | P5 | Scenario engine v1 | 4 | 2 | 5 | 4 | 4 | 2 | 3 | 4 | **3.75** | 3.50 | 3.80 | Foundational |
| 12 | F5 | Decision ledger | 3 | 1 | 4 | 4 | 5 | 4 | 4 | 5 | **3.70** | 3.75 | 3.65 | Quick win + foundational |
| 13 | S3 | Valuation v3 (EVOR, wins and title value) | 4 | 2 | 4 | 4 | 4 | 3 | 3 | 4 | **3.65** | 3.50 | 3.75 | Foundational |
| 14 | R1 | M5: 2026 prospective scoring and inactive share | 2 | 3 | 3 | 5 | 5 | 4 | 5 | 3 | **3.60** | 3.75 | 3.35 | Time-critical (season end) |
| 15 | F6 | Decision laboratory v1 (lineups plus contested add/drop; trades excluded after review) | 3 | 2 | 5 | 3 | 4 | 3 | 3 | 5 | **3.55** | 3.50 | 3.45 | Foundational |
| 16 | D2 | Trade engine v3 (ΔP(playoffs/title), partner lens) | 5 | 1 | 3 | 3 | 4 | 3 | 3 | 5 | **3.45** | 3.38 | 3.80 | High-impact |
| 17 | P3 | Dependence model (**gated** on development lineup-total mis-calibration) | 3 | 3 | 4 | 3 | 4 | 3 | 3 | 4 | **3.40** | 3.38 | 3.30 | Foundational (gated) |
| 17 | R2 | RB/TE/QB availability rules | 3 | 4 | 3 | 4 | 4 | 3 | 3 | 3 | **3.40** | 3.38 | 3.30 | Research (evidence-backed) |
| 19 | S0 | In-season league simulator v0 (shadow; **only if ≥ about 2 weeks before the trade deadline**) | 4 | 2 | 3 | 3 | 4 | 3 | 3 | 5 | **3.35** | 3.38 | 3.50 | High-impact (conditional, time-critical) |
| 20 | F1 | Prospective analysis addendum | 1 | 1 | 3 | 5 | 5 | 5 | 5 | 3 | **3.30** | 3.50 | 3.00 | **Time-critical quick win** |
| 20 | I3 | Monitoring and alerting | 2 | 2 | 3 | 4 | 5 | 4 | 4 | 3 | **3.30** | 3.38 | 3.10 | Quick win (2027) |
| 22 | R3 | Forecast-horizon study | 3 | 3 | 3 | 3 | 3 | 4 | 4 | 4 | **3.20** | 3.38 | 3.20 | Research bet |
| 23 | D5 | Weekly intelligence briefing | 4 | 1 | 2 | 3 | 5 | 3 | 3 | 4 | **3.15** | 3.13 | 3.35 | High-impact |
| 24 | D0 | Lineup helpers (FLEX slotting, game-time plan) | 3 | 1 | 1 | 4 | 5 | 5 | 5 | 2 | **3.10** | 3.25 | 3.20 | Quick win |
| 25 | I1 | Modularisation, point-in-time registry, R 4.6 | 1 | 1 | 4 | 3 | 5 | 3 | 5 | 2 | **2.95** | 3.00 | 2.60 | Foundational (maintenance) |
| 26 | D3 | Waiver, free-agent and FAAB assistant | 4 | 1 | 2 | 3 | 3 | 3 | 3 | 4 | **2.85** | 2.88 | 3.15 | High-impact |
| 27 | R5 | Point-in-time market context covariates | 2 | 3 | 3 | 3 | 3 | 3 | 3 | 2 | **2.75** | 2.75 | 2.60 | Research bet |
| 28 | D4 | Draft and keeper assistant | 4 | 1 | 2 | 3 | 3 | 2 | 3 | 3 | **2.70** | 2.63 | 3.00 | High-impact (deadline Aug 2027) |
| 28 | I2 | Local dashboard ◇ | 3 | 1 | 2 | 2 | 5 | 3 | 2 | 3 | **2.70** | 2.63 | 2.75 | Optional |
| 30 | R6 | ESPN-independent fallback ◇ | 2 | 2 | 3 | 2 | 4 | 2 | 2 | 3 | **2.55** | 2.50 | 2.40 | Research bet (resilience) |
| 31 | R4 | Multi-source capture and averaging ◇ | 2 | 4 | 2 | 3 | 2 | 3 | 2 | 3 | **2.50** | 2.63 | 2.40 | Research bet (owner decision) |
| 32 | D1 | Lineup engine v1 (late window; full P(win) mode only if outcome-free triage shows ≥ 5% flips) | 2 | 1 | 2 | 2 | 4 | 3 | 3 | 4 | **2.45** | 2.63 | 2.40 | Research bet |
| 33 | R7 | Usage reliability and first-read share ◇ | 1 | 2 | 2 | 2 | 4 | 3 | 3 | 2 | **2.25** | 2.38 | 2.00 | Research bet |

**Parked** (scored for transparency; not in the roadmap):

| Idea | DI | PA | UV | EV | FE | EF | MB | SI | Weighted | Reason |
|---|---|---|---|---|---|---|---|---|---|---|
| Defence-vs-position matchup adjustments | 1 | 1 | 1 | 1 | 5 | 4 | 4 | 1 | 2.05 | Persistence r ≈ 0.16–0.27; VE1 opponent term below 0.04% of MAE |
| Play-level game simulator | 2 | 2 | 2 | 1 | 3 | 1 | 1 | 2 | 1.85 | No evidence over factor models; must be re-anchored to ESPN means |
| Dynasty and keeper modelling (unless the league has keepers) | 2 | 1 | 1 | 2 | 3 | 2 | 2 | 2 | 1.85 | Conditional on league format |
| Auction tools (unless an auction league) | 2 | 1 | 1 | 2 | 3 | 2 | 2 | 2 | 1.85 | Conditional on league format |
| Broad ML or feature search for weekly means | 1 | 1 | 1 | 1 | 5 | 2 | 2 | 1 | 1.75 | Replicated nulls (E2–E5); markets near-efficient |
| Multi-team trades / top trading cycles | 2 | 1 | 1 | 1 | 3 | 2 | 2 | 3 | 1.75 | Bundle complementarity breaks the theory; acceptance compounds |
| Similarity (comparables) projections | 1 | 1 | 1 | 1 | 3 | 3 | 3 | 2 | 1.65 | No NFL out-of-sample evidence |
| Weather features | 1 | 1 | 1 | 1 | 2 | 3 | 3 | 1 | 1.45 | Weak evidence; priced into totals; forecasts available only 2021+/2024+ |
| Deep RL / MDP season management | 2 | 1 | 1 | 1 | 2 | 1 | 1 | 2 | 1.40 | No faithful opponent simulator; validation would be circular |
| LLM / news NLP | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 2 | 1.35 | No point-in-time archive; terms risk; no gain shown over ESPN |

---

## 3. How sensitive the ranking is

- **The top tier is stable under all three weightings:** P2, S2, P4, S1, F2, F0, F3, P0, P1.
  - P2 is first or second in every view.
  - S2 and P4 stay in the top three under the weighted and decision-heavy views.
- **Movers under the decision-heavy view:**
  - Up: **D2** (16th → about 8th), **D3**, **D4**, **D5**, **S0**.
  - Down: **F1** and **I1**, which are low on direct decision impact.
- None of the parked ideas rises above 2.1 in any view.
- **Uncertainty.** The scores are expert judgements, informed by the evidence in [02](02_research_landscape.md).
  - The least certain scores are DI for D1 (it depends on the X9 result) and PA for R4 (it depends on terms and capture).
  - The roadmap therefore gives both an explicit kill rule or decision gate rather than a commitment.

---

## 4. From scores to sequence

The score ranks *value*. The **sequence** in [07](07_master_roadmap.md) also respects three constraints:

1. **Time-criticality.**
   - The W6 slate needs manual runs now (Step 0).
   - F0 must be in place before the remaining late-week slates.
   - F1 must be committed before any 2026 outcome is scored.
   - S0 is worth building only if F3-lite shows at least about 2 weeks before the trade deadline.
   - D4 must exist before the late-August 2027 draft.
   - R1 runs at season end.
2. **Dependencies.**
   - Evaluation before models: F2 before P*.
   - Data before models: F4 before P1–P4.
   - Distributions before calibrated simulation: P2/P4 before P5/S1/S2 v1.
   - Simulation before decision engines.
   - A **thin S2+D2 slice** on S0-level inputs comes first (early April 2027), so one failed P-gate cannot stall the 2027 engines.
3. **Evidence protection** (added after the critical review, [07](07_master_roadmap.md) §10):
   - check seasons are spent in batches (2019 injury, 2024 distributions, 2025 replays for decisions);
   - 2026 outcomes stay sealed;
   - the frozen runtime is pinned through 2027;
   - in-season work is base R.

**The resulting order:**

| Window | Milestones |
|---|---|
| This week | **Step 0** (owner: manual W6 runs) → F0 → F1 (+ E17 outcome-free R3 pre-registration) |
| Weeks 7–14 | D0 → F3-lite → F5 (records only) → F2-lite → P0 → S0 (conditional); R3 captures accrue |
| Season end | R1 → I1 (platform profile; frozen runtime pinned) → F2-full, F3-full (O8) |
| Jan–Mar 2027 | F4 → F6 v1; P1 + R2 (batch check 2019); P2 → P3 (gated), P4 (batch check 2024) → P5 |
| Mar–May 2027 | S2 + D2 thin slice → S1 → S2 v1 → S3 |
| May–Aug 2027 | D1 (triage-gated), D2, D3, D4 (by the draft), D5; VL11 decision batch on 2025 replays |
| 2027 season | Confirmatory prospective records; I3; I2◇ |
| Later | R4–R7 as capacity allows |

---

## 5. Why some attractive ideas wait

- **Win-probability lineup optimisation (D1)** sounds advanced, but the only direct season-long measurement found zero flips in 208 team-weeks [alhart2015 2026], and our arithmetic puts typical gains below 1 projected point. It is built only behind a kill rule, after the calibrated simulation exists.
- **Trade optimisation in wins units (D2)** has the highest decision impact.
  - Without calibrated distributions (P2, P4) and a season simulator (S2), ΔP(playoffs) would be precise-looking noise.
  - In 2026 the existing ΔU analyzer plus (conditionally) S0's shadow odds are the honest best.
  - A thin S2+D2 slice comes first in 2027, and calibrated parts are swapped in as they pass.
  - Trades are *not* evaluated in the decision lab: season-level outcomes have an effective n of about the number of seasons.
- **Multi-source averaging (R4)** is the only mean-improvement route with outside evidence. It cannot be backtested and depends on terms, so it starts as capture-only, under an owner decision.
- **Draft tools (D4)** are high-leverage but used once a year. They are scheduled for the 2027 preseason deadline and not built earlier.
