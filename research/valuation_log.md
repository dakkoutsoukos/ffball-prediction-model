# Valuation experiment log

This log is separate from the projection log (`research/experiment_log.md`).
Entries record methodological decisions, the rationale behind them and results.
- Pre-registrations are written before the analysis they govern and are not edited afterwards.
- A "Result" section is appended once the analysis has run.
- A methodology change needs a general justification and a version bump (`valuation_v1` → `valuation_v1.1`).
- Changes are never made because a specific player's value "looks wrong" (guardrail).

No valuation analysis uses a 2026 outcome to fit or select anything. 2026 inputs
are point-in-time projections, schedules and past-week data only.

---

## 2026-10-07 — VE0: Future-week information audit (before any valuation code)

**Request.** One request on 2026-10-07: `leaguedefaults/3`, slots QB/RB/WR/TE, all
2026 scoring periods, projection and actual sources, split types 0/1/2.

**Findings.**
- ESPN posts weekly projections for every remaining week (W5–W18): 570 players, one entry per player and week.
- Bye weeks are 0.
- Injured players are 0 for the weeks ESPN expects them out:
  - 41 of 50 `INJURY_RESERVE` players are 0 for every remaining week;
  - others are 0 for 1–2 weeks, then positive;
  - a backup RB whose starter is expected back drops to 0 when the starter returns. So zeros can also encode role.
- Healthy players' future weeks are nearly flat. The coefficient of variation across weeks
  among >50%-owned healthy players has a median of 0.049. This looks like a season rate with matchup adjustments.
- `statSplitTypeId 0` with source 1 (the season projection) **equals the sum of the remaining
  weekly projections exactly** (255.28 for one WR). So ESPN's ROS is these weekly values.
- Past weeks hold the final pregame projection. **Future-week projections as of an
  earlier date cannot be retrieved historically**, so they can only be validated prospectively.

**Decision.**
- The live ROS uses ESPN's posted future weeks as the if-healthy level `X_i(t)`.
  It treats a posted 0 in a game week as an expected absence.
- It falls back to the extrapolated level `L_i` (chosen in VE1) when no posted value exists.
- Historical attrition `A_p(h)` and calibration `c, d` are applied to both paths.
- The posted path is labelled `posted_future` everywhere and its accuracy is
  unverified. VE-P1 below pre-registers its prospective check.

---

## 2026-10-07 — VE1: Pre-registration of the ROS forecasting study (before any ROS analysis)

**Question.** Which simple, transparent construction of a player's future-week
expectation from information available at valuation week *w* forecasts ROS
fantasy points best? Is a schedule (opponent) adjustment worth keeping?

**Data.**
- ESPN week-of (final pregame) projections, QB/RB/WR/TE, 2019–2025:
  - WR from the existing cache;
  - QB/RB/TE fetched once, one request per season-week.
- nflverse player stats, scored with `espn_ppr` (actual points; a player without a stat line scores 0).
- Weekly rosters (team at *w*) and schedules (byes).
- Positions come from ESPN `defaultPositionId`, and ids from `build_espn_crosswalk()`.

**Population.**
- Players with an ESPN projection above 0 in week *w*, mapped to GSIS, with a known team at *w*.
- Valuation weeks *w* = 3…13.
- Horizon *t* ∈ (*w*, *H*]:
  - *H* = 16 for 2019–2020 (17-week seasons);
  - *H* = 17 for 2021+.
- Future weeks in which the player's *w*-team has no game are known byes. They are
  excluded from fitting and forecast as 0 by every method.

**Components (estimated on development seasons 2019–2023).**
- `A_p(h)` = share of rows with a stat line at *w + h*.
- `c_{p,b} + d_{p,b} · L` = least squares of points on rows with a stat line, by
  position and horizon bucket *b* ∈ {1, 2–3, 4–7, 8+}.
- Forecast: `E = A_p(h) · (c + d · L)`. The ROS total is the sum over the horizon.

**Candidate levels `L` (all known at *w*).**

| id | definition |
|---|---|
| `L_cur` | ESPN week-*w* projection |
| `L_avg4` | mean of the player's last up-to-4 positive ESPN projections in weeks ≤ *w* of the same season |
| `L_blend` | 0.5 · `L_avg4` + 0.5 · season-to-date actual points per game with a stat line (weeks < *w*). Used when there are ≥ 3 such games; otherwise `L_avg4`. |

**Metric and selection rule.**
- Primary metric: MAE of ROS totals per (player, *w*), development seasons, on the
  **relevant** subset. Relevant means rank at *w* by ESPN projection: QB ≤ 24, RB ≤ 48, WR ≤ 60, TE ≤ 24.
- Positions are pooled. Each position is also reported.
- Selected: the lowest development MAE, provided its RMSE is not worse than `L_cur`'s.
  A difference under 0.5% of MAE is a tie, and the simpler candidate wins (order
  `L_cur` < `L_avg4` < `L_blend`).
- 2024–2025 is reported once as the check and cannot change the choice.

**Schedule test.**
- Opponent factor = shrunk season-to-date fantasy points allowed to the position
  per game, through week *w* − 1, relative to the league mean. The prior is 4 games at the league mean.
- `E = A · (c + d · L · (1 + β · (opp − 1)))`, with β fit on development.
- β is kept only if weekly future MAE (*h* ≥ 1, relevant subset) improves in **both**
  development and 2024–2025. Otherwise β = 0.
- β only ever applies to extrapolated weeks, because posted ESPN weeks already include the opponent.

**Production parameters.**
- The selected design is re-estimated on 2019–2025 and written to `models/valuation/ros_params_v1.yml`.
- The current-week calibration `c_p0 + d_p0 · ESPN_w`, by position, is fit on 2019–2025 on the same population.
- The design does not change after this.

**Diagnostics only (no decisions).**
- Weekly residual SD by position and projection bucket, and ROS-total residual SD by
  position and horizon length (the V1 uncertainty layer).
- Future availability after a Questionable designation at *w* compared with non-listed players (evidence for §25).

---

## 2026-10-07 — VE1a: Amendment to the VE1 model form (written before any candidate comparison was computed)

**What was seen.** The study frame was built: 26,226 (player, *w*) rows and about
190,000 future team-game rows. Its raw availability table showed the share of
rows with a stat line at *h* = 1:
- QB 0.71, RB 0.83, TE 0.77 (the WR column was not displayed).

That is because the population (projection > 0) includes many deep backups who
rarely record a stat. Availability therefore depends strongly on the level `L`.

**Problem with the registered form.** `E = A_p(h) · (c + d · L)` uses an `A` that does not
depend on `L`. Every starter would be multiplied by a backup-diluted
availability, which biases the product. This is a general property of the
population, not a property of any player.

**Amended form.** The level candidates, population, metric, selection rule,
schedule test and seasons are all unchanged.
- `E = c_{p,b} + d_{p,b} · L [+ g_p · L · (opp − 1)]`, by least squares on **all**
  future team-game rows (0 without a stat line), by position and horizon bucket.
  Attrition is then inside `c` and `d` and depends on the horizon.
- `A = plogis(a_{p,b} + e_{p,b} · log L)`, a logistic model of having a stat line, by position and bucket.
  It is used **only** to draw availability in the roster simulation (`lvl = E / A`) and never enters `E`.
  A numerical guard `A ≥ E / 60` keeps `lvl` finite.
- Weeks with ESPN posted 0 in a game week have `E = 0` and `A = 0`.

---

## 2026-10-07 — VE1 result (linear form of VE1a)

The relevant subset, ROS-total errors in points:

| level | dev MAE | dev RMSE | check MAE | check RMSE |
|---|---|---|---|---|
| `L_cur` | 30.44 | 39.99 | 34.01 | 44.70 |
| **`L_avg4`** | **29.49** | **39.05** | **32.92** | **43.53** |
| `L_blend` | 29.39 | 39.15 | 32.82 | 43.53 |

- **Selected `L_avg4`.**
  - `L_blend` is 0.3% lower on development MAE, inside the 0.5% tie band, with a worse RMSE. The simpler level wins.
  - `L_avg4` beats `L_cur` by 3% on MAE in both development and check, and on RMSE, at every position.
  - Within-position rank correlation of ROS totals: 0.45–0.65.
- **Schedule term.** Weekly MAE improved in both splits, so by the rule it is **kept**.
  - Development 6.5639 → 6.5616; check 6.5968 → 6.5963.
  - The effect is negligible. The coefficient is `g` ≈ 0.09–0.21: a defence allowing 20% more than average adds about 2–4% to an extrapolated week.
  - It never applies to posted ESPN weeks, which already include the opponent.
- **Calibration diagnostic** (relevant subset, by level quintile):
  - The top quintile is **under-predicted** for QB (development forecast 17.1 against actual 19.1; check 16.9 against 19.0).
  - It is also under-predicted for WR (development 14.3 against 15.2) and for RB in the check seasons (14.4 against 16.5).
  - The bottom quintile is slightly over-predicted.
  - The reason is general, not player-specific. Decay with horizon is pooled across levels, and elite players keep their level across the horizon better than marginal ones, who lose roles.

## 2026-10-07 — VE1b: two-stage form (post-result check of the VE1a amendment)

The original registered idea with level-dependent availability:
`E = plogis(a + e · log L) · (c + d · L)`, fit on rows with a stat line.

| form | dev MAE | dev RMSE | check MAE |
|---|---|---|---|
| linear | 29.49 | 39.05 | 32.95 |
| two-stage | 29.91 | 39.44 | 33.29 |

By the VE1 rule the **linear form stays**. The two-stage form also worsens the top-quintile under-prediction (QB 15.9 against 19.1).

## 2026-10-07 — VE1c: Pre-registration of one functional-form alternative (written before running it)

**Why.** The top-quintile bias would compress elite players' ROS value, and so
their trade value, in every position. This matters for cross-position valuation.

**Candidate.** Add a quadratic term per position and horizon bucket:
`E = c + d · L + q · L² [+ g · L · (opp − 1)]`. One more parameter per cell, fit on the same rows.

**Rule.** Unchanged from VE1:
- lower development MAE (relevant subset) with RMSE not worse;
- a difference under 0.5% is a tie won by the linear form;
- check seasons are reported;
- the calibration by quintile is reported for both forms.

Nothing else is tried after this. If the quadratic form loses, the linear form is
production and the top-end bias is documented as a V1 limitation.

**Result.**

| form | dev MAE | dev RMSE | check MAE | check RMSE |
|---|---|---|---|---|
| linear | 29.49 | 39.05 | 32.95 | 43.58 |
| **quadratic** | **29.32** (−0.59%) | **38.95** | **32.74** | **43.42** |

- **The quadratic form is selected**: outside the tie band, with better RMSE, and also better in the check seasons.
- Top-quintile calibration, forecast against actual:

  | split | QB | WR | RB |
  |---|---|---|---|
  | dev | 18.7 / 19.1 | 15.0 / 15.2 | 14.6 / 14.5 |
  | check | 18.2 / 19.0 | 14.7 / 13.9 | 14.5 / 16.5 |

- Production ROS design (frozen as `models/valuation/ros_params_v1.yml`, re-estimated on 2019–2025):
  - level `L_avg4`;
  - quadratic form per position and horizon bucket;
  - opponent term kept (negligible);
  - availability for the simulation from the logistic `A(log L)`;
  - current-week calibration linear in ESPN's projection, with slopes 0.93–0.96.

**Diagnostics (no decisions).**
- **Weekly residual SD:** about 7–10 points for starter-level projections (10–20), and 2–4 for players projected under 5.
- **ROS-total residual SD:** about 45% of the forecast for QB/WR/TE and 48–53% for RB. It shrinks slightly with more remaining games.
- **Questionable at *w*:**
  - WR future availability is lower by about 4–5 points over the next 1–3 weeks (0.80 against 0.84 at *h* = 1), then converges.
  - RB and TE show no difference.
  - QB is confounded by level, since listed QBs are mostly starters.
  - V1 does not extrapolate the designation. The WR carry-over is noted for V2.

---

## 2026-10-07 — VE2: Pre-specification of the valuation methodology (before any value is computed)

Fixed now, so that no player-level output can steer them:

1. **League default:**
   - 10 teams;
   - QB 1, RB 2, WR 2, TE 1, FLEX(RB/WR/TE) 1;
   - bench 7;
   - `espn_ppr`;
   - regular season through week 14, playoffs weeks 15–17.
2. **Starter allocation:** exact weekly max-weight assignment (matroid greedy). Baselines come from exchange.
3. **Rostered pool:** a generic re-draft simulation.
   - Each pick maximizes Δ expected ROS lineup points with streaming at the waiver level.
   - Availability is Monte Carlo with S = 200 draws and seed 20261007.
   - Candidates at each pick: the 6 best available per position by ROS points.
   - Fixed-point iteration on waiver levels, at most 6 iterations. The starting levels come from proportional bench shares.
4. **Primary metric:** ROS VOR = Σ_t max(0, E_i(t) − R_p(t)).
   - Secondary metrics: VAS (unfloored) and MRU.
5. **Display:** TV = 100 · f(VOR) / f(max VOR), where *f* is an isotonic then
   monotone-spline fit of MRU on VOR over all pooled players with VOR > 0.
6. **Packages:**
   - roster-aware ΔU on the simulated teams;
   - waiver pickup for each freed spot;
   - forced drop of the least valuable player for each extra player received;
   - no penalty parameters.
7. **Valuation backtest** (2019–2025, *w* ∈ {4, 8, 12}, default league).
   - Realized decision-based VOR: Σ over weeks the player's projected VOR was > 0 of
     (actual points − realized replacement). Realized replacement is the mean actual
     points of the 3 best-projected undrafted players who can fill the slot.
   - Reported: Spearman correlation of projected and realized VOR within each position;
     realized/projected ratio and slope by position among each position's top
     *2 × league starters*; and the share of QBs in the top 30 projected versus realized.
   - **Flag**, not a tuning target: a position whose realized/projected ratio
     differs from the pooled ratio by more than 25% is documented as possible bias.

---

## VE-P1 (prospective, 2026): posted ESPN future weeks versus extrapolation

For every archived valuation run from 2026 week 5 on, at season end:
- compare ROS-total MAE, by position, of the posted-future path with the `L`-extrapolated path;
- use the same `A`, `c` and `d`, the same players, and actual 2026 points.

No valuation decision uses 2026 outcomes before then. This check is valuation-only
and separate from the WR projection record.

---

## 2026-10-07 — VE3: Rostered pool for the waiver baseline (methodology change, written before the production values were computed)

**What was run.** One trial valuation of 2026 week 5 under VE2 item 3: the generic re-draft
fixed point, without MRU. Its top-10 overall list was printed and seen. The
change below is justified by the **composition and convergence diagnostics**,
not by any player's value.

**Findings.**
1. **No fixed point.** Six iterations never repeated the drafted set: 4, 1, 2, 1 and 4 players changed.
2. **Self-reinforcing hoarding (multiple equilibria).**
   - The draft rostered **30 QBs** in a 10-team 1QB league. Ten of them came in rounds 8–9 as backups.
   - Once backups are rostered, the streaming level drops (best undrafted QB: 10.7 points a week).
   - A lower streaming level makes backups look worth drafting, so the hoarding sustains itself.
   - Starting from fewer rostered QBs, the streaming level is 13.7.
   - The fixed point therefore depends on where the iteration starts.
3. **Missing driver.** The draft values a bench player only for availability coverage
   (byes and injuries). It ignores ROS level uncertainty, which VE1 estimates at
   45–53% of the forecast. Level uncertainty is the main reason managers roster RB and WR depth.
   Without it, bench value is pushed toward high-floor positions.
4. **External reference (diagnostic only, not a target).** Rostered counts by position:

   | | QB | RB | WR | TE |
   |---|---|---|---|---|
   | proportional rule | 20 | 46 | 54 | 20 |
   | ESPN ≥50% owned | 20 | 45 | 57 | 19 |
   | re-draft fixed point | 30 | 41 | 47 | 22 |

**Decision (valuation_v1).**
- The rostered pool for the waiver baseline `R` is the **proportional pool**.
  - Each position's share of league starters, from the weekly allocation over the horizon, times teams × roster size.
  - Within each position the pool is filled by ROS points.
  - The shares come from the projections and the lineup rules. The only assumption is that bench shares mirror starter shares.
- The re-draft is run **once, with streaming at the proportional pool's waiver level**.
  It builds the generic teams used for MRU, the display map and packages.
- The fixed-point pool is reported as a sensitivity (`simulation.pool: simulation`).
- V2 should add level uncertainty to the simulation before its bench composition can define replacement.

---

## 2026-10-07 — VE2 results: first archived valuation (2026 week 5) and the historical backtest

**Run** `20261007T062429Z`.
- ESPN capture 06:24Z.
- WR current week from archived M4 run `20261006T062916Z` (145 WRs). The other 319 current-week rows are calibrated ESPN, and all 5,568 future rows are posted ESPN weeks.
- 464 players; 201 s.
- Methodology `valuation_v1`, ROS parameters `ros_v1`, git `c95aaea`.

**Replacement levels** (points per game, horizon mean) and scarcity:

| | QB | RB | WR | TE |
|---|---|---|---|---|
| waiver replacement R | 13.7 | 8.9 | 8.9 | 7.2 |
| marginal starter S | 14.3 | 9.6 | 9.6 | 8.9 |
| elite (top-3) points per game | 17.2 | 19.6 | 18.9 | 13.7 |
| elite (top-3) VOR | 44 | 130 | 119 | 77 |
| players with VOR > 50 | 1 | 12 | 11 | 3 |

- RB and WR share one baseline through FLEX: FLEX holds 2.8 RBs and 7.2 WRs.
- TE has the largest starter − replacement gap (1.7 points per game against 0.6–0.7).
- Overall top 30: 12 RB, 12 WR, 5 TE, 1 QB. QB1 is 18th overall.

**VOR against VAS.**
- Spearman correlation 0.96.
- VAS compresses QB and TE further. The floored and raw VOR differ only for players with byes or absences ahead.

**Roster utility (MRU) and display.** MRU/VOR rises with VOR:

| VOR band | 0–15 | 15–30 | 30–60 | 60–100 | 100+ |
|---|---|---|---|---|---|
| MRU/VOR | 0.54 | 0.50 | 0.64 | 0.80 | 0.89 |

So the display map is convex. VOR 75 maps to about TV 41 and VOR 121 to TV 72 (top = 159 → 100).

**Consolidation** (40 equal-VOR elite-for-two trades between generic teams; median VOR_A − VOR_BC = +0.06):
- The single-player side gained more in 30 of 40.
- Median edge +8.3 points of expected ROS lineup points; mean +12.2.
- The edge correlates with the TV difference (0.44) and with the VOR difference (0.56).
- It is largest when the pair side cannot start the second player because the position is already filled (roster fit).

**Sensitivity** (waiver replacement QB/RB/WR/TE; elite VOR in parentheses):

| league | replacement QB / RB / WR / TE | elite VOR QB / RB / WR / TE |
|---|---|---|
| 8 teams | 14.6 / 9.0 / 9.0 / 7.9 | 35 / 129 / 118 / 69 |
| **10 teams (default)** | **13.7 / 8.9 / 8.9 / 7.2** | **44 / 130 / 119 / 77** |
| 12 teams | 12.5 / 6.9 / 6.9 / 6.5 | 57 / 154 / 143 / 86 |
| 14 teams | 12.3 / 6.1 / 6.2 / 5.8 | 59 / 165 / 152 / 94 |
| no FLEX | 12.9 / 8.3 / 8.7 / 6.8 | 53 / 136 / 122 / 83 |
| 2 FLEX | 13.9 / 8.2 / 8.2 / 7.4 | 41 / 139 / 128 / 76 |
| 3 WR | identical to 2 FLEX (FLEX already prefers ~32 WRs) | |
| bench 5 / 9 | QB 14.6 / 12.8, RB 9.0 / 8.0 | |
| superflex | 9.0 / 9.0 / 9.0 / 7.3 | 99 / 129 / 118 / 77 (11 QBs in the top 30) |
| re-draft pool (VE2) | QB 10.7 | QB 80: the hoarding effect VE3 removed |

**Secondary diagnostics.**
- The modelled rostered pool sits close to ESPN ≥50%-owned:

  | | QB | RB | WR | TE |
  |---|---|---|---|---|
  | rostered pool | 20 | 46 | 54 | 20 |
  | ESPN ≥50% owned | 20 | 45 | 57 | 19 |

- Our ROS against ESPN's own ROS (the sum of its posted weeks), on fantasy-relevant players: Spearman 0.993, median ratio 0.81.
  - The difference is calibration plus attrition. ESPN's future weeks are "if healthy".

**Historical valuation backtest** (2019–2025, weeks 4/8/12, parameters from 2019–2023).
Projected VOR is compared with realized decision-based VOR among each position's top 2 × league starters:

| | QB | RB | WR | TE | pooled |
|---|---|---|---|---|---|
| realized/projected, dev | 1.32 | 1.04 | 1.15 | 0.86 | 1.11 |
| realized/projected, check | 1.44 | 1.22 | 1.25 | 1.23 | 1.26 |
| Spearman, dev | 0.50 | 0.56 | 0.58 | 0.38 | |
| Spearman, check | 0.49 | 0.66 | 0.47 | 0.41 | |

- **No position is flagged.** The largest deviation is QB in development, +19% against pooled.
- The ratios exceed 1 everywhere because realized replacement averages the 3 best waiver options, while projected replacement is the single best expected one.
- **QBs are not over-valued.**
  - They have the highest ratio, a mild under-valuation.
  - The top 30 holds 3.5 QBs projected against 5.3 realized (development), and 3.7 against 5.7 (check).
  - TE in the top 30: 2.1 against 2.3 (development) and 1.0 against 2.0 (check).
- Nothing was changed in response. Per VE2 these are reported, not tuned. The QB under-valuation is consistent with the remaining top-end
  under-prediction after VE1c (QB top quintile 18.7 against 19.1). It is listed for V2.

---

## 2026-10-07 — VL0: Valuation V2 pre-specification (before any league data was analysed)

**Plan.** `docs/valuation_v2_plan.md`. One unauthenticated probe of the owner's league returned
HTTP 401: the league is private, so the owner's cookies are needed. No league content has been seen.

Fixed now:
1. **Decision variable.** `ΔU = U_after − U_before` per team.
   - U is the expected ROS optimized starting-lineup points from rostered players.
   - Weekly availability is Monte Carlo (S = 200, seed 20261007, common random numbers).
2. **Streaming policy `empty_slots`.**
   - A free agent at the actual weekly FA level fills a slot only when no rostered eligible player is active.
   - Sensitivity runs use `none` and `unlimited`.
3. **Forced drops** are greedy, maximizing post-trade U. **Adds** take the best FA by U gain, only if the gain is above 0. Candidates are the top 6 per position.
4. **Classification thresholds:** ε = 5 and S = 20 expected ROS lineup points, with the rule order of plan §11.
5. **Search bounds:**
   - candidates: VOR > 5 or MTV > 2, top 12 per team;
   - structures: 1-for-1, 2-for-1, 1-for-2, 2-for-2;
   - generic pre-filter: |ΔTV| ≤ 40.
6. **V1 is unchanged.** Generic values in the league's format come from a separate V1-methodology run under the league's settings.

---

## 2026-10-07 — VL1: V2 on the owner's league (league alias `league_605d88d7`)

**Inputs.**
- League snapshot `20261007T193259Z`: 8 teams, 141 rostered players.
- League-format valuation run `20261007T193931Z`.
- Analysis `20261007T200628Z`: streaming policy `empty_slots`, 200 draws, seed 20261007.
- No league content is committed; only the alias and hashes are.

**Settings mapped from ESPN.**
- 8 teams; QB 1, RB 2, WR 2, TE 1, FLEX(RB/WR/TE) 2; bench 7; IR 1; roster 17 (K and D/ST each 1).
- Position limits QB 4, RB 8, WR 8, TE 3.
- Regular season 1–14; playoffs 15–17 (4 teams, two-week final).
- **Scoring is ESPN PPR for QB/RB/WR/TE**, so the V1 ROS parameters and the M4 WR source apply unchanged.

The 31 unmapped scoring items are K or D/ST stats, or negligible for skill players. The evidence:
- across 124,829 skill-player stat lines in the local ESPN history, at most 0.00015 points per player-week (return TDs);
- items 95–99 score only through D/ST-slot overrides.

The general rule now in `lg_map_scoring()`: an unmapped item is relevant only if it can score for a skill slot and reaches 0.01 points per player-week.

**ID coverage.** 124 skill players, all joined by ESPN id. No skill player without projections, no duplicate owners, no position or team mismatches. The 17 K and D/ST players are not valued.

**Bugs found on real data, fixed generally and tested, before any result was used:**
1. The playoff horizon came out as 15–14. ESPN reports `playoffMatchupPeriodLength = 0` with variable per-round lengths. Weeks now come from the matchup-period map, and `val_league()` rejects reversed ranges.
2. Position limits counted IR players: a team with 8 active RBs plus 1 on IR was forced into an RB drop on every trade. Limits now apply to active players, and a pre-existing excess never forces a drop.

Report-only fixes:
- the summary previously counted only the archived top 15 per opponent; now every evaluated trade is archived;
- a `summarise()` ordering bug in the TE ratio table;
- the free-agent team label.

**Results.**
- **Actual waiver levels** (points per game, horizon mean of the best free agent each week) against V1 generic replacement in the league's format:

  | | QB | RB | WR | TE |
  |---|---|---|---|---|
  | actual | 14.8 | 8.3 | 8.6 | 8.8 |
  | generic | 14.8 | 9.0 | 9.0 | 8.1 |

  RB and WR waivers are thinner than generic, TE waivers deeper.
- **Power rankings** (expected ROS lineup points): 1,710 down to 1,507. The owner's team is 4th (1,603).
- **Team-specific against generic value.**
  - Mean team value / generic VOR = 0.86; correlation 0.99 for VOR > 10.
  - The widest destination spreads are QBs, for example 32–67 for the top QB, set by whether a team's own QB is weak or on bye.
- **TE.** Team value per generic VOR point: TE 0.64, against RB 0.89, WR 0.87 and QB 0.96. With actual rosters the V1 pooled display scale does overstate TEs; generic teams in V1 gave 0.51. The scale is not changed. Team-specific Δ is the decision variable, and V1 stays as registered.
- **QB.** 1QB values stay below generic VOR. Under a hypothetical superflex slot (same rosters), the top QBs' value to other teams roughly doubles to triples (for example 48 → 93, 21 → 58).
- **Search** (owner's team against all 7 opponents, 1,750 trades fully evaluated):
  - 338 have both sides gaining;
  - 33 are mild win-wins (both above ε = 5);
  - 499 are fair (|ΔA − ΔB| ≤ 5);
  - the largest surplus is +24.5.
  - Model estimates only; acceptance is not modelled.

## 2026-10-13 — VL2: `--capture` runs used an older ESPN capture (fixed)

**Bug.** `scripts/valuation_run.R` took its as-of time before the ESPN capture. Inputs are looked up "at or before as_of", so the capture taken in the same invocation was always skipped. The run silently fell back to the newest earlier capture of that week, or stopped if there was none.

**Affected runs** (archives are write-once and stay as they are; nothing is re-run):
- `20261007T062429Z` (week 5) used capture `20261007T060535Z`, not `20261007T062430Z`.
- `20261007T193931Z` (week 5, league format) used capture `20261007T062430Z`, not `20261007T193933Z` as the commit message of e9597dd states.
- The first week 6 attempt on 2026-10-13 stopped with "No valuation ESPN capture for 2026 week 6". Run `20261013T070931Z` was then made without `--capture` and used capture `20261013T070639Z` as intended.

**Fix.** The as-of time is now taken again right after the capture. Stamps are truncated to the second, so a capture always sorts at or before it. `scripts/weekly_run.R` is not affected: it does not pass the earlier time to `run_prospective()`.

## 2026-10-13 — VL3: S0 shadow league simulator (master plan S0; pre-registration, written before σ_L or any simulation was computed)

**Purpose.** Approximate playoff, title and weekly win odds for the owner's league in 2026, before the trade deadline
(2026-12-02) and the playoffs. **Shadow and unvalidated.** S0 also seeds the 2027 thin slice (S2).

**Inputs** (all point in time):
- the latest league snapshot: rosters, plus the F3-lite schedule, records and rules;
- the latest valuation run in the league's format: E, A and lvl per player-week through week 17;
- the frozen P0 table (`pod_baseline_v0`);
- the designation prior for designated players in the current week.

**Model.**
1. **Level shock.** Each simulation draws, per rostered player, L ~ lognormal(−σ_L²/2, σ_L²), so E[L] = 1, held constant over the season. σ_L is set by simulation matching (below).
2. **Availability.** Each player-week is active ~ Bernoulli(A_t), with A_t from the valuation run. In the current week (where the run has A = 1), A is the designation prior for designated players and 1 otherwise.
3. **Points if active.** L × (lvl_t + r_t), floored at the position floor. r_t comes from P0's residual distribution for (position, band of lvl_t), by inverse CDF interpolated on the τ grid, with tails held at the end quantiles.
4. **Lineups use decision values.** A manager knows availability at lock, but not L or r. Each team each week starts the legal lineup that is optimal on active × lvl, from its current roster: laminar slot greedy, with V2's `empty_slots` streaming (an empty slot is filled at the week's free-agent level, at expected points). The team score is the **realised** points of those starters plus streamed points. No in-season learning in v0.
5. **Rosters** are frozen at the snapshot: no trades or waivers are simulated.
6. **League rules** (F3-lite):
   - completed results stay fixed (ESPN records);
   - equal scores are ties and count as half wins;
   - seeds go by win share, then points for (TOTAL_POINTS_SCORED);
   - 4-team bracket: semifinals in period 15 (week 15), seed 1 v 4 and 2 v 3; final in period 16 (weeks 16 and 17 combined);
   - a playoff tie goes to the higher seed.
7. **Correlation:** players and teams are otherwise independent in v0.
8. **Simulation size and streams:** 10,000 simulations in chunks of 1,000, with L'Ecuyer-CMRG streams per chunk. Every what-if uses the same seeds (common random numbers).

**σ_L by simulation matching** (development seasons 2019–2023 only):
- **Rows:** `val_frame$future` rows of 2019–2023 with as-of weeks w ∈ {5, …, 11}. The forecasts E, A and lvl come from the frozen ROS parameters (`models/valuation/ros_params_v1.yml`). The ROS total is the sum over the remaining weeks t > w through the season's last week.
- **Observed:** the residual R = Σ_t points − Σ_t E, per (player, season, w).
- **Simulated:** the same rows with S0's components (availability from A_t, P0 noise around lvl_t, the level shock), 200 draws per row with common random numbers.
- **Matching:** per position, σ_L solves SD(simulated R) = SD(observed R) by bisection on [0, 1.5]. If SD(simulated R) at σ_L = 0 already reaches the observed SD, σ_L = 0.
- **Reported:** σ_L by position, the mean bias of simulated vs forecast totals, and the matched and observed SD by w (descriptive).

**Sensitivity bands** (reported with every output): σ_L × {0.5, 1, 1.5}; noise (P0 residuals) × {0.8, 1.2}.

**Outputs.**
- Per team: E[wins], P(playoffs), P(each seed), P(title).
- This week's P(win) and margin quantiles per matchup.
- The owner's leverage this week: P(playoffs | win) − P(playoffs | loss).
- What-ifs: ΔP(playoffs) and ΔP(title) for a roster change, with common random numbers.
- ESPN's `playoffPct` alongside, if ESPN ever returns it (it currently does not; decisions X-004).

**Label on every output:** "shadow / unvalidated: inputs are early-week, so odds are too sharp until R3; rosters frozen; players independent".

**Checks.**
- Per simulation: Σ_teams P(playoffs) = 4 and Σ P(title) = 1, exactly.
- Monte Carlo SE ≤ 0.5 pp for every probability at 10,000 simulations.
- Deterministic for a fixed seed.
- Runtime ≤ 10 min.

**Evaluation.**
- The odds archive is evaluation-only, and never used to recalibrate σ_L or anything else in 2026.
- Real-league calibration is descriptive: about 56 matchups and 4 playoff places per season.
- Every odds query is ledgered (type `odds`).

**Influence on later choices.** No 2024–2026 outcome is used: σ_L comes from 2019–2023 development rows, and P0 from 2020–2023.

### VL3 result 1: σ_L by simulation matching (computed after the entry above was committed in f4f1e06)

Rows: 93,709 player-weeks (11,756 player-season-as-of groups), 2019–2023, as-of weeks 5–11. ROS totals run
through each season's last week.

| Position | Groups | Observed ROS residual SD | S0 SD without a level shock | σ_L | Matched SD | Mean bias: simulated / observed |
|---|---|---|---|---|---|---|
| QB | 1,593 | 41.1 | 22.3 (54%) | **0.368** | 41.1 | −1.5 / −2.2 |
| RB | 3,025 | 31.3 | 18.1 (58%) | **0.373** | 31.3 | −0.2 / −1.4 |
| WR | 4,646 | 29.1 | 18.5 (64%) | **0.345** | 29.1 | −1.2 / −0.1 |
| TE | 2,492 | 23.2 | 14.1 (61%) | **0.388** | 23.2 | −0.0 / −0.9 |

- **Without a season-long level shock, S0 would understate ROS spread by 36–46%.** Odds built on independent weeks would be badly overconfident (the plan's concern; master plan 02 §9).
- With one σ_L per position, the matched SD is within −4% to +8% of the observed SD at every as-of week from 5 to 11 (`s0_sigma_by_week`). A constant shock fits all the horizons S0 faces.
- Mean biases are small against ROS totals of around 50–150 points.
- **Frozen:** `models/simulation/s0_params_v0.yml`. The pipeline re-derives it (`s0_params_check`), fingerprint `2632efe5…`. A synthetic test recovers a known σ_L = 0.30 within 0.05.

### VL3 result 2: simulator built and run on the owner's league (2026-10-13, matchup period 6)

**Engine.** `R/simulation/season_sim.R`.
- **Draws:** availability, P0 noise and level shocks (s0_params_v0).
- **Lineups:** chosen on decision values and scored on realised values. This is a new evaluator; V1/V2 are untouched.
- **Rules:** completed records fixed, ties counted as half wins, seeds by win share then points for, a 4-team bracket with the two-week final summed.
- **Randomness:** L'Ecuyer-CMRG streams per chunk of 1,000; every configuration of a what-if runs in the same pass (common random numbers).
- **CLI:** `trade_analyzer.R odds`.

**Checks on the live league.**
- 10,000 simulations ran in 11 s, against a target of 10 min or less.
- Σ P(playoffs) = 4.000 and Σ P(title) = 1.000 exactly.
- Maximum Monte Carlo SE 0.49 pp, against a target of 0.5 pp or less.
- Odds across the 8 teams: P(playoffs) 0.22–0.78; P(title) 0.05–0.23.

**Sensitivity.** Bands (σ_L × 0.5–1.5, noise × 0.8–1.2) moved the owner's P(playoffs) within about ±1.2 pp and P(title) within ±1.2 pp.

**Ledger.** Every run is ledgered (type `odds`); outcomes are sealed (F5).

**Tests** (synthetic leagues; 18 expectations): lineups choose on decision values but score realised ones; empty slots stream; ties; seeding and bracket; invariants; determinism and the caller's RNG left untouched; common random numbers give exactly zero difference for an identical what-if.

**Limitations, stated on every output.**
- Inputs are early-week, so the odds are too sharp until R3 adds the horizon spread term.
- K and D/ST are not simulated: every team starts one of each, so the means largely cancel, but P(win) is too extreme.
- Rosters are frozen, players are independent, and there is no in-season learning.
- The current matchup period is simulated in full, so runs should be made before its first kickoff.
- Odds are produced only when a fresh league snapshot exists: the owner runs `league_refresh.R`. The dispatcher does not refresh the league.

## 2026-10-13 — LAB1: F6 decision laboratory v1 (instrument; X8/X9 triage plan; pre-registration written before any replay was run)

**Purpose.** An out-of-sample testbed for weekly **lineup** and **contested add/drop** policies (master plan F6;
experiment X8), plus outcome-free triage for X8 and X9. LAB1 is an instrument, not a test:
- the decision family's one batch check is VL11 (2025 replays);
- confirmation is the 2027 prospective season;
- nothing below selects a policy for VL11 without VL11's own pre-registration.

**Data.**
- The F4 frame `player_week_all` (QB/RB/WR/TE) and the team schedules.
- Development seasons 2020–2023: the lab calls `assert_family_seasons("decision_family", 2020:2023, "development")`.
- 2019 is a forecast warm-up only. The contamination register's decision family gains `warmup: [2019]` in this commit.
- 2024 is excluded; 2025 is used only at VL11; 2026 is sealed.

**Leagues.**
- 20 synthetic leagues per season, sizes cycling 8/10/12.
- Roster: QB, RB×2, WR×2, TE, FLEX×2 (RB/WR/TE), bench 7. That is 15 skill players, no IR.
- **No K or D/ST.** Their points are not ESPN-validated (B-001), and no policy under study touches them.
- No trades.
- Regular season: weeks 1–14. Playoffs (descriptive only): 4 teams, semifinals in week 15, final in week 16.

**Draft.**
- Snake draft.
- Value: ESPN's week-1 week-of projection, minus the position's replacement level (the projection of the n-th QB and TE and the 3n-th RB and WR, with n teams), plus N(0, 1) noise per (league, team, player).
- Caps: QB 2, TE 2, RB 6, WR 6. Remaining picks must be able to fill every starting slot.
- The week-1 projection is late-horizon at week-1 kickoff. That is a deliberate simplification: it is policy-neutral, because every arm shares the draft.

**Schedule.** Circle-method round robin over 14 weeks, with the team order permuted per league.

**Information set** (the firewall `lab_info()` truncates by construction):
- **Draft:** week-1 pregame values only.
- **Waivers before week t** (t ≥ 2): everything from weeks ≤ t−1, plus the season's bye schedule. Nothing from weeks ≥ t.
- **Lineups at week t:** everything from weeks ≤ t−1, plus week t's pregame values: ESPN's week-of projection and the F4 base.
- No week-t outcome is visible: points, active, snaps, stat line, ESPN actual, game-day status.
- Policies are functions `policy(state, info)`. They never see the engine's outcome table.

**Forecasts** (rolling origin).
- **Lineup values:**
  - raw = ESPN's week-of projection;
  - calibrated = the F4 `base` (per-position OLS on earlier weeks).
- **Waiver values** are built on the per-game level L_avg4: the mean of the last (up to 4) positive ESPN projections through week t−1.
  - raw = L_avg4.
  - calibrated = a_p + b_p·L_avg4. The coefficients are per position, from OLS of the points over the next 1–4 weeks on L_avg4. Only weeks the player's team plays count, with 0 points when there is no row. Fitting uses seasons 2019..s−1, as-of weeks 1–15.
- **Byes:** a per-game value is scaled by the share of the remaining weeks (t..16) in which the player's team plays.

**Policies.**
- **Lineup:** optimal by value (greedy: fixed slots first, then FLEX). A player without a week-t row cannot start.
- **Waivers (contested):**
  - Gain of adding a and dropping d = [optimal lineup value of the roster with the swap − without] × remaining weeks (t..16).
  - Candidates: the 5 best free agents per position by value, and the 2 lowest-value roster players per position.
  - A claim needs a gain > 2 points and a legal roster afterwards: QB 1–3, TE 1–3, RB ≥ 2, WR ≥ 2. At most 2 claims per week.
  - Claims resolve in rounds by waiver priority: fewest wins, then fewest points for; week 2 uses reverse draft order. A team that claims successfully moves to the end of the order for the rest of that week. A dropped player is not claimable the same week.
- **Opponents:** raw lineup and raw waivers.
- **Focal team** (one per league, seat drawn from the league seed), one of four arms:
  - A: raw lineup, raw waivers (control);
  - B: calibrated lineup, raw waivers;
  - C: raw lineup, calibrated waivers;
  - D: calibrated lineup, calibrated waivers.
- The arms share each league's draft, schedule, focal seat and seeds.

**Engine outputs per team-week:**
- the lineup and its realised points;
- the hindsight-optimal lineup points and the regret;
- **shadow lineups**: both lineup policies applied to the same roster, with their realised points (arm A, all teams).

**Triage** (outcome-free; computed and reported *before* any realised comparison).
- **X8:**
  - (a) lineup flip rate between raw and calibrated on arm-A rosters (all teams);
  - (b) model-implied lineup gain: Σ base over the calibrated lineup − Σ base over the raw lineup;
  - (c) waiver flip rate, and model-implied gain (calibrated values) of the two policies' top claims, on arm-A states.
- **X9:** on arm-A focal team-weeks (weeks 1–14):
  - Compare the P(win) of the EV-optimal (calibrated) lineup with every legal single swap (starter ↔ bench). The opponent plays its calibrated EV lineup.
  - Points come from the frozen P0 table, with p_active = P0's development active share by position: 2,000 common-random-number draws.
  - A flip is a swap that beats EV by more than 2 Monte Carlo SE of the paired difference.
  - Report the flip rate and the mean ΔP(win). X9's kill rule for D1 applies: under 5% flips, or a mean ΔP below 0.005, means no full P(win) mode.

**Development results** (after the triage; descriptive, development only):
- the shadow-lineup difference (calibrated − raw on identical rosters, all teams);
- the focal arms' paired differences in realised lineup points per team-week: B−A, C−A, D−A;
- for each: week-clustered, season-blocked bootstrap 95% intervals (2,000 replicates; weeks resampled within season);
- regret by arm;
- wins, playoffs and titles, descriptive only.

**Instrument success criteria:**
1. The full development replay (2020–2023, 20 leagues per season, 4 arms) completes in ≤ 2 h.
2. Firewall tests pass. Planted future data must leave every decision unchanged: week-≥ t outcomes and week-> t projections rewritten.
3. Determinism: identical seeds give identical results.
4. Toy-league tests pass.
5. The X8/X9 triage report is produced before the realised development comparison, and long before VL11.

### LAB1a (2026-10-13, amendment before any replay or triage was computed)

LAB1's X9 triage set p_active to "P0's development active share by position". That share mixes starters with
backups who carry small positive projections. For QB it is 0.752: about 25% of projected QBs take no snap. Read
literally, it would sit a starting QB in a quarter of the simulations.

**Amended.** p_active is the development active share (2020–2023, P0's `pd_based` rows) by **position × P0 base
band** (`pd_band()`), falling back to the position's share for an empty band (`lab_active_table()`,
`lab_p_active()`). The amendment was made after seeing only the position-level input shares, before any replay,
X9 draw or lab output existed. No other part of LAB1 changes.

### LAB1b (2026-10-13, amendment after a data-feasibility failure; no triage or outcome had been viewed)

The first full replay stopped in 2023 with "draft pool exhausted". The historical ESPN week-1 file for 2023 is
defective: 64 of its 784 projections are positive, against 386–445 in 2019–2022. The frozen WR source shows the
same (26 of 398). LAB1's draft value, the week-1 projection, therefore cannot form a draft in 2023.

**Amended draft value.**
- The player's mean positive ESPN projection in the previous season, if he had at least 4 projected weeks.
- Otherwise his positive week-1 projection.
- Otherwise he is not drafted.
- Only players with a week-1 ESPN row (the preseason pool) are draftable. A player who joins a team later is not known at the draft.

The rule is applied to every season, so all four are re-replayed.

**Order of events.** Before this amendment, three seasons' replays were stored. Nothing from them was read: no
triage, no lineup or waiver output, no outcome. Everything else in LAB1 and LAB1a is unchanged.

## 2026-10-13 — VL4: P4 season dynamics (X2, X7, X26; pre-registration, written before any P4 computation)

**Family.** `distribution_stack`:
- development 2020–2023; warm-up 2019;
- **check 2024 in the E22 batch** (with P2, and with P3 if its gate builds it);
- 2025 excluded; 2026 sealed.

Rest-of-season (ROS) forecasts are **rolling origin** (refit on seasons < s). The frozen `ros_v1` parameters were
derived from 2019–2025 and are not used, so the 2024 check stays clean.

**ROS rows.**
- **As-of weeks:** w ∈ {4, 8, 12}.
- **Population:** players at QB/RB/WR/TE ranked within their position at week w by L_avg4 (the mean of the last, up to 4, positive ESPN projections through w): top 24 QB, 48 RB, 60 WR, 24 TE (VE1's relevance thresholds).
- **Future weeks:** t = w+1 … 16 in which the player's last known team plays (byes are not attrition).
- **Realised ROS total:** Σ_t points, with 0 when there is no row.

**Model components** (fit on seasons < s; F4 data):
- **Mean if active:** μ_h. Per position and horizon bucket h = t − w ∈ {1, 2–3, 4–7, 8+}, OLS of points on L_avg4(w) over active future rows.
- **Attrition:** A_h. The share of future team-game weeks in which the player was active, by position × L band (P0's bands applied to L_avg4) × horizon bucket.
- **Weekly noise:** the E20-selected P2 candidate's F(y | active, base = μ_h).
  - Covariates at future weeks are their as-of values: status "none", the week-w TD share, implied total 22, spread 0, and the as-of volatility.
- **Level shock:** L ~ lognormal(−σ_L²/2, σ_L²), held for the season. σ_L is set per position × L band (3 bands: the position's tertiles of L_avg4 on 2019–2023) by **simulation matching** on development rows (2019–2023, all three w):
  - SD of simulated ROS residuals = SD of observed ones, with availability and noise drawn separately;
  - 200 draws per row; common random numbers; bisection on [0, 1.5]. This is VL3's procedure, by band.
- **ROS distribution:** 2,000 draws per (player, w) of Σ_t active_t · L · F⁻¹(u | μ_h).
- **Baseline, VE1-normal:** the same mean Σ_t A_h μ_h, with a normal spread at the training residual SD of ROS totals by position × w (seasons < s).

**Diagnostics** (parameter studies; development 2020–2023; no pass/fail):
- **X2:** lag-1 to lag-4 within-player-season autocorrelation of r = y − base (active projected rows), by position × P0 band. ICC from `gam(r ~ s(player_season, bs = "re"))` per position. Player-season bootstrap CIs.
- **X26** (ESPN's learning rule): OLS of the projection change proj_{t+1} − proj_t on the residual r_t, by position (both weeks projected and active), with player-season-clustered CIs. This becomes the empirical learning rule for P5's simulated policies.

**Development evaluation** (descriptive; σ_L is matched in sample): CRPS and 50/80/90% coverage of ROS totals by
position × w, for the P4 model against VE1-normal.

**E22 primary for P4** (one-time, 2024; Holm with the batch's other primaries):
- ΔCRPS(P4 − VE1-normal) on ROS totals, pooled over positions and w;
- player-clustered bootstrap: players resampled within the season, keeping all their as-of weeks;
- success: CI below 0 **and** the ROS coverage gate passed. The gate covers position × level (12 cells, pooled over w), uses the same cluster, and applies Holm across cells.

**Frozen artefact if E22 passes:** `models/probabilistic/season_dyn_v1.yml`, containing σ_L by position × band, the
attrition table, μ_h, and the learning coefficients, all fitted on 2019–2023, plus a fingerprint.

### VL4a (2026-10-13, before any P4 computation)

VL4 lists 2019–2023 as the σ_L matching rows. F4 starts in 2019, so no earlier season exists to fit 2019's rolling
components on, and 2019's ROS cannot be forecast out of sample. **σ_L is therefore matched on 2020–2023 rows**,
each season's components fit on the seasons before it (2019 only for 2020). The band tertiles are taken on the same
rows. Nothing else changes.

## 2026-10-13 — VL5: S1 matchup win probability (X23; pre-registration, written before any computation)

**Family.** `decision_family` (X23):
- development: the F6 replays of 2020–2023 (warm-up 2019);
- one check in the VL11 batch (2025 replays);
- confirmatory 2027.

Real-league calibration is descriptive and, for 2026, sealed until R1.

**Matchups.** Every regular-season matchup in the F6 arm-A development replays (LAB1/LAB1a/LAB1b): both teams'
actual starting lineups, realised winner (ties count ½).

**Player distributions at lineup lock** (late horizon), identical for both methods:
- the frozen P0 table (`pod_baseline_v0`) around the F4 base;
- P(active) by position × P0 base band (LAB1a's development table);
- a starter without a week-t ESPN row contributes 0.

**Methods.**
- **S1-sim** (P5 engine, σ_L = 0): 10,000 independent common-random-number draws per matchup of the lineup totals. P(win) = P(A > B) + ½ P(A = B).
  - **No level shock.** For one week, P0's empirical residuals already contain each player's level uncertainty; a season-long shock on top would double-count it.
- **Baseline (normal approximation):** Φ(μ_diff/σ_diff), with each player's mean and variance taken from the same POD (mixture with the point mass at 0).

**Primary:** non-inferiority of S1-sim against the normal approximation.
- ΔBrier = Brier(sim) − Brier(normal) over all development matchups.
- Week-clustered, season-blocked bootstrap, 2,000 replicates.
- Success: the upper 95% bound ≤ +0.005 (05 §6).

**Also required:** the slope rule. S1-sim's calibration slope (logistic regression of the outcome on logit(P)) must have
a 95% CI that includes 1 and a point estimate in [0.8, 1.2].

**Decision.**
- **Both hold:** S1-sim is the matchup P(win) engine.
- **Otherwise:** ship the normal approximation (07 S1).

**Reported:**
- Brier and log loss for both methods;
- CORP decomposition;
- reliability tables;
- results by league size and by favourite strength.

### LAB1 result 1: outcome-free triage (X8, X9), recorded before any realised comparison was computed

**Scale.** The full development replay (2020–2023; 20 leagues per season; arms A–D) ran in **23.7 min**
(`lab_replays`; criterion ≤ 2 h). The lab tests pass, including the end-to-end firewall test with planted future data.

**X8, lineups** (arm A, regular season, all teams; 11,088 team-weeks).
- Calibrated and raw-ESPN lineups differ in **2.9%** of team-weeks; by season and league size the range is 1.3–5.2%.
- Model-implied gain under the calibrated model: **0.004 points per team-week** on average, **0.16** points when the lineups differ.
- This is what the triage predicted. Per-position linear calibration with positive slopes keeps each position's order, so only FLEX choices across positions can change.

**X8, waivers** (arm A states; 10,296 team-weeks).
- Claim lists differ in 6.7% of team-weeks in 2020, the first lab season, calibrated on 2019 only. In 2021–2023 they differ in 15–20%.
- Claims run at about 0.7–1.1 per team-week under either policy.
- Model-implied gain of the calibrated top claim over the raw one (ROS points, calibrated model): −0.01 (2020), +0.22 (2021), +0.29 (2022), +0.46 (2023).

**X9** (arm A focal team-weeks; 1,120). P(win) of the calibrated EV lineup against single swaps, with P0 PODs and
P(active) by position × band (LAB1a).
- A significant flip occurs in **2.9%** of team-weeks; mean ΔP(win) is **0.0013** (90th percentile 0.0055).
- The EV lineup's mean P(win) is 0.508.
- **X9's kill rule fires** (flips < 5% *and* mean ΔP < 0.005). D1 gets **no full pre-kickoff P(win) mode**: EV lineups, slotting and late-window features only.
- This agrees with the one earlier measurement (0/208).

**Reading for VL11.** Calibration alone barely changes lineups, so a realised lineup effect of calibration will sit far
below any plausible MDE. The waiver arm, and the availability and distribution arms once P1/P2 exist, carry the
decision question. VL11's pre-registration should size its primaries with these flip rates in mind.

### LAB1 result 2: development results (descriptive; computed after result 1 was committed in 0c01edd)

Regular-season team-weeks, 2020–2023. Week-clustered, season-blocked bootstrap 95% intervals.

| Comparison | n | Mean (points per team-week) | 95% CI |
|---|---|---|---|
| Shadow: calibrated − raw lineup on identical rosters (all teams, arm A) | 11,088 | +0.003 | [−0.029, +0.034] |
| Focal arm B − A (calibrated lineups) | 1,120 | +0.059 | [−0.075, +0.208] |
| Focal arm C − A (calibrated waivers) | 1,120 | +0.022 | [−0.406, +0.454] |
| Focal arm D − A (both) | 1,120 | +0.081 | [−0.369, +0.545] |

- **Regret** (hindsight-optimal minus realised, focal team): A 12.32, B 12.31, C 12.73, D 12.70.
- **Season level** (descriptive; 80 leagues per arm): wins 6.96–6.98, playoffs 0.375–0.400, titles 0.113–0.125.

**Reading.** At the late horizon, calibrating ESPN changes few decisions and no detectable realised points. That was
the triage's prediction for lineups. For waivers it is an estimate with a wide interval. Accuracy gains of this size
(calibration) do not translate into decision gains. The X8 arms that remain open are availability (needs P1) and
distribution-aware values (needs P2). Development only: the decision family's check is VL11 (2025).

### VL5 result: S1 matchup P(win) on the F6 development matchups (computed after VL5 was committed in 4d964c1)

5,544 regular-season matchups (2020–2023, arm A).

| | Simulation | Normal approximation |
|---|---|---|
| Brier | 0.21743 | 0.21731 |
| Log loss | 0.6252 | 0.6246 |

- **ΔBrier (simulation − normal) = +0.00011**, 95% CI [−0.00007, +0.00034]. The upper bound is ≤ +0.005, so **non-inferior**.
- **Slope rule passes:** slope 0.92, CI [0.72, 1.09].
- **CORP:** MCB 0.0018 vs 0.0018; DSC 0.0339 vs 0.0341; UNC 0.2496. Results are identical by league size.
- **Reliability:** good throughout, except the top bin: forecast 0.94, observed 0.83 (n = 94).

**Decision (VL5's rule): S1-sim is the matchup P(win) engine.** The simulation is not better than the normal
approximation; it is equivalent at the late horizon with these PODs. Its value is consistency with the scenario
engine's joint draws (S2, D-track). The normal approximation stays the documented fallback.

Real-league calibration remains descriptive and sealed until R1. The decision family's check is VL11.

### VL3b (2026-10-14): S0's current-week availability from P1's frozen provider

VL3 gave designated players in the current week the published fixed prior (Q 0.71, D 0.07) "until P1 exists".
E19c froze P1's post-report provider: the rate table by designation × final practice status × position,
`models/probabilistic/p1_availability_v2.yml`.

From now on S0 (`odds`, and the thin slice's `rescore`) uses it through `p1_live_availability()`:
- the ESPN status gives the designation;
- the official practice status counts only once the team's final report is captured (M4's live rule); before that, the designation-level rate applies;
- IR and suspension are 0; unlisted players are 1.

`--fixed-prior` restores the published prior. The ledger records the source in `model_versions$availability`.
Everything else in VL3 is unchanged: σ_L, P0 noise, rules, label. S0 stays shadow and unvalidated.

## 2026-10-14 — VL6: S2 v1 season and playoff simulator (pre-registration; estimation only, written before any computation)

**Scope.** S0's resolver generalised to the formats ESPN offers, plus a week-k calibration study on the F6 replays.
S0, the shadow engine, stays in service for the owner's league until S2 v1 is built and passes its rule tests.

**Rules engine (`s2_resolve`).**
- 2, 4, 6 or 8 playoff teams; byes for the top 2 seeds when there are 6 playoff teams; multi-week rounds.
- Divisions: division winners take the top seeds, then wild cards by record.
- Tiebreaks: win share, then the configured rule (TOTAL_POINTS_SCORED or head-to-head), then points for, then team id.
- No reseeding (ESPN does not reseed). Playoff ties go to the higher seed.
- **Rule-reproduction tests:**
  - On the owner's format (4 teams, 1-week semifinal, 2-week final) S2 must reproduce S0's `sim_resolve()` exactly on identical score arrays.
  - Hand-computed fixtures cover 6-team byes, divisions and both tiebreaks.

**Week-k calibration study** (`decision_family` development 2020–2023, F6 arm A, all teams; descriptive estimation):
- **When:** at k ∈ {4, 7, 10}, each replay league's rosters are frozen at week k.
- **Simulation:**
  - The remaining regular-season weeks are simulated with P4's rolling-origin components (mean if active by horizon bucket, attrition) fit on seasons before s.
  - Weekly noise is P0, and there is no level shock. S0's σ_L is calibrated to ROS totals, not to team-score week sequences. A level-shock sensitivity at S0's σ_L is reported.
  - Lineups are decision-time (lab optimiser on active × mean); 2,000 simulations; the lab's playoff rule (top 4 by wins, then points for).
- **Compared with:** each team's realised playoff qualification in the replay. Rosters keep evolving there through waivers, which the forecast ignores; that is a stated limitation.
- **Reported:** Brier, the reliability table, and the calibration slope with season-blocked bootstrap CIs, by k.
- **No hypothesis test:** season-level outcomes have effective n ≈ seasons (05 §6).

**Also reported:**
- all-play records and schedule luck (realised wins minus all-play expected wins) for the replay leagues;
- the ΔP(title) decomposition for a roster change, into regular-season wins, seeding/bye and playoff-week points. The decomposition uses common random numbers, combining configurations week by week.

**Success (07 S2):** rules reproduced exactly; invariants (Σ P(playoffs) = playoff teams, Σ P(title) = 1); calibration
estimates with honest CIs. The prospective comparison with ESPN's `playoffPct` is logged only if ESPN ever returns it
(X-004: absent for this league).

### VL4 result: P4 development (descriptive; σ_L matched in sample, 2020–2023)

**σ_L** by position × L-tertile band (simulation matching, 200 draws):

| | Band 1 | Band 2 | Band 3 |
|---|---|---|---|
| QB | 0.446 | 0.387 | 0.253 |
| RB | 0.501 | 0.401 | 0.361 |
| TE | 0.410 | 0.332 | 0.424 |
| WR | 0.355 | 0.370 | 0.290 |

All are uncapped. For comparison, S0's position-level σ_L is 0.35–0.39.

**ROS evaluation against VE1-normal** (same mean; normal spread at the training residual SD):
- P4's CRPS is **worse** in every position × w cell, by 0.2% to 3.5%.
- P4's coverage at 50% is 0.32–0.48, too low. At 80% it is 0.68–0.80; at 90%, 0.76–0.88.
- So the multiplicative lognormal shock on summed weekly draws has the right SD (by construction) but the wrong shape: too peaked, with heavy tails.

**Parameter studies (X2, X26).**
- **X2:** lag-1 autocorrelation of residuals against the calibrated week-of base is QB 0.035 [−0.012, 0.085], RB 0.027 [−0.005, 0.058], WR 0.002, TE −0.006. ICC is ≤ 0.003. Residuals against the week-of projection do not persist.
- **X26:** ESPN moves next week's projection by 0.114–0.142 of the residual, depending on position (tight CIs). This is the empirical learning rule.
- **Reading:** ROS level uncertainty comes from ESPN's future revisions, not from a persistent bias in its current projection.

**Outcome.** P4 v1 fails in development, so it is **not advanced** (E22 not run) and not adopted. S0's VL3 engine stays
in shadow use with its label. The X26 learning slope is recorded for P5/S3's simulated policies. A future P4 v2, for
example an additive level shock or a revision-path model built on X26, needs its own pre-registration.

## 2026-10-14 — VL8: D1 lineup engine — late-window value (X9 second part; pre-registration, written before any computation)

**Scope after triage.** X9's kill rule fired (LAB1 result 1), so D1 has no full pre-kickoff P(win) mode. D1 =
- EV lineups with D0's kickoff slotting and game-time plans (P1 provider);
- decision confidence (shown, not tested);
- a **late-window module**, whose value this entry estimates.

**Question.** Lineups lock per game. Once earlier games are final, does re-optimising the still-unlocked slots for
P(win), given the realised score so far, win more matchups than keeping the EV lineup?

**Data.** F6 arm-A development replays (2020–2023; `decision_family` development). Every regular-season matchup is
analysed from the focal side of each team-week, so both teams of a matchup appear.

**Decision points** (each player's NFL game slot from the F4 kickoff, US Eastern):
- Thursday;
- Sunday early (before 15:00);
- Sunday late (15:00–19:59);
- Sunday night and Monday (20:00 or later, Sunday or Monday).

Decisions happen before each of: Sunday early (Thursday final), Sunday night (all Sunday daytime final), Monday (all
Sunday final). The Sunday-late slot shares the Sunday-early decision, because early games are not final at 16:05.

**Policies** (team scored on realised points; the opponent keeps its EV lineup):
- **EV:** the lab's calibrated EV lineup (F4 base, late horizon).
- **Late window:** at each decision point, the starters in unlocked slots are re-chosen among unlocked roster players.
  - The objective is P(win), given the realised points of both teams' locked starters and the PODs of all unlocked players.
  - PODs come from the frozen P0 table with position × band P(active).
  - P(win) is computed by simulation (2,000 common-random-number draws), searching over single swaps between an unlocked starter and an unlocked bench player (as X9).
  - A swap is made only if ΔP(win) exceeds 2 Monte Carlo SE.

**Primary estimate** (no hypothesis test; D1's criterion is "late-window value estimated with CI"):
- the difference in win rate per team-week (late window − EV);
- week-clustered, season-blocked bootstrap 95% CI.

**Also reported:**
- realised points difference;
- share of team-weeks with any late-window swap;
- results by decision point;
- results by the realised margin before the decision.

**Interpretation and use.**
- **CI excludes 0 in favour of the late window:** the late-window module ships, with live use gated on live box scores (owner decision O8).
- **Otherwise:** it ships only as an informational display.

VL11 re-tests on 2025 replays.

### VL6 result: S2 v1 (computed after VL6 was committed in a52b165; estimation only)

**Rules engine.** `s2_resolve()` reproduces S0's resolver exactly on the owner's format (tests). Hand-computed fixtures
pass for 6-team byes, divisions and head-to-head tiebreaks. Σ P(playoffs) = 4 in every simulated league and k.

**Week-k P(playoffs) calibration.** F6 arm-A development replays, 2020–2023; 80 leagues; 792 team cases per k. The CIs
are league-clustered and season-blocked; the base-rate Brier is 0.241.

| k | Brier (main: no level shock) | Slope (main) | Brier (S0 σ_L) | Slope (S0 σ_L) |
|---|---|---|---|---|
| 4 | 0.192 [0.177, 0.207] | 0.68 [0.56, 0.82] | 0.190 [0.178, 0.201] | 1.01 [0.85, 1.22] |
| 7 | 0.153 [0.138, 0.170] | 0.79 [0.67, 0.93] | 0.153 [0.140, 0.167] | 1.07 [0.92, 1.26] |
| 10 | 0.124 [0.110, 0.138] | 0.74 [0.64, 0.87] | 0.120 [0.108, 0.132] | 0.94 [0.82, 1.09] |

**Reading.**
- Without a level shock, playoff odds are **over-confident** at every k. The top bins over-forecast, e.g. at k = 4: 0.93 forecast vs 0.79 observed.
- With S0's frozen σ_L the slopes are ≈ 1 and Brier improves slightly.
- This is descriptive support for S0's design (VL3), which is what the owner's live odds use. It holds although P4's ROS-total distribution failed on shape (VL4 result): season odds depend on correlated week-to-week deviations, which the level shock supplies.
- Season-level calibration stays descriptive (05 §6).
- Limitation: the forecast freezes rosters at week k, while replay rosters keep evolving through waivers.

**Status.** S2 v1's success criteria are met: rules reproduced, invariants hold, calibration reported with CIs. The
prospective `playoffPct` comparison is not possible while ESPN omits it (X-004).

## 2026-10-14 — VL9: D3 waiver and free-agent assistant; X16 QB streaming (pre-registration, written before any computation)

**League facts** (F3-lite): no FAAB (`isUsingAcquisitionBudget = FALSE`), so the FAAB bid model is gated off and claims
go by waiver priority. Keepers 0.

**Tool** (live; shadow ΔP like S0):
- the free-agent board: V2's ΔU screen;
- the top candidates re-scored by ΔP(playoffs) and ΔP(title) with common random numbers, as in the thin slice;
- drop advice: the roster player whose removal costs the least ΔU;
- a streaming view by next-week posted ESPN projection, calibrated, which the live capture provides;
- ledgered as `waivers`.

**X16 in the lab** (F6 development replays 2020–2023; `decision_family` development).
- **Limitation.** Historical replays have no posted future-week projections (VE0), so lab streaming can use only levels and byes, not matchups. A null therefore means "level-based streaming does not help"; it says nothing about matchup-based streaming.
- **Arm E (QB streaming), focal team.**
  1. Each waiver stage starts with a streaming pass. The starting QB's next-week value is compared with the best free-agent QB's: per-game calibrated L_avg4, times whether the team plays week t.
  2. If the free agent is better by more than 1 point for week t, claim him and drop the roster QB with the lower rest-of-season value. The roster must stay legal; the claim is contested like any other.
  3. Then the calibrated waiver policy runs as in arm C.
- **Paired with arm C** (calibrated lineups are not part of C, so E uses arm C's raw lineups): same leagues, drafts and seeds.
- **Primary estimate** (no test; D3's criterion): ΔE − C in focal realised lineup points per team-week, regular season. Week-clustered, season-blocked bootstrap 95% CI.
- **Also reported:** QB claims per season; realised QB points of the focal starter.
- **Use:** streaming is recommended by the tool only if the CI excludes 0 in its favour. Otherwise the streaming view is informational. VL11 re-tests on 2025.

### VL8 result: D1 late-window value (computed after VL8 was committed in 6a23352; estimation only)

**Data.** 11,088 team-weeks: F6 arm-A development replays 2020–2023, 80 leagues, regular season, both sides of every
matchup. 2,000 common-random-number draws per evaluation; a swap is made only if ΔP(win) > 2 Monte Carlo SE.

| Quantity (late window − EV, per team-week) | Estimate | 95% CI (week-clustered, season-blocked) |
|---|---|---|
| Win rate | +0.0003 | [−0.0005, +0.0012] |
| Realised points | +0.010 | [−0.014, +0.032] |
| Team-weeks with any swap | 2.4% (268) | — |

**By decision point** (team-weeks with a swap; win-rate difference among them):
- before Sunday early (Thursday final): 265, +0.015, about 4 net wins;
- before Sunday night: 3, −0.33 (one loss);
- before Monday: 1, 0.

**By the realised margin before the first swap** (268 swapped team-weeks; small cells, descriptive):

| Margin | ≤ −30 | (−30, −10] | (−10, 0] | (0, 10] | (10, 30] | > 30 |
|---|---|---|---|---|---|---|
| n | 9 | 39 | 142 | 34 | 37 | 7 |
| Win-rate difference | 0 | +0.077 | +0.014 | +0.029 | −0.081 | 0 |

**Reading.**
- The CI includes 0, so by VL8's rule the late-window module ships **only as an informational display**; it makes no
  live recommendation.
- Opportunities are rare: 0.34 swaps per team-season, almost all after the Thursday game. By Sunday night few rosters
  still have an unlocked bench player whose swap moves P(win) by more than 2 SE.
- Even at the point estimate the gain is about 0.005 wins per team-season. This agrees with X9's outcome-free triage
  (LAB1 result 1: P(win)-optimal lineups rarely differ from EV lineups in this format).
- Limitations: the opponent keeps its EV lineup; no in-game information (injuries during games); K and D/ST are not in
  the lab; the PODs assume independence (P3's gate found a variance ratio of 1.04).

**Status.** D1's success criteria are met: triage reported, kill rule applied, late-window value estimated with a CI.
VL11 re-tests on 2025 replays.
