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
