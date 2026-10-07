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
