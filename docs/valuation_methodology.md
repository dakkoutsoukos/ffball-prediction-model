# Valuation methodology (`valuation_v1`)

This track is separate from projection research. Projection M5 is paused, and the
frozen lineages M1–M4 and their 2026 prospective record are untouched. Decisions
and results are logged in [research/valuation_log.md](../research/valuation_log.md)
(VE0–VE3). The plan is [docs/valuation_v1_plan.md](valuation_v1_plan.md).

> **What "value" means here.** A player's value is the expected contribution that
> owning him adds to a constrained fantasy roster, relative to the alternatives
> freely available at his position and in the player pool, over the rest of the
> fantasy season.

```
standardized weekly projections (providers)          R/valuation/providers.R
 └─ ROS weekly expectations E_i(t), byes, availability R/valuation/ros.R
     └─ weekly league starter allocation (exact, FLEX) R/valuation/allocation.R
         ├─ marginal-starter baseline S_p(t)  ──────── VAS
         └─ rostered pool -> waiver baseline R_p(t) ── VOR (primary)
             └─ generic teams (re-draft)              R/valuation/simulation.R
                 ├─ roster utility (MRU) ─ display scale f(VOR)   R/valuation/value.R
                 └─ trade evaluation with roster spots            R/valuation/packages.R
 point-in-time runs, archive, manifest                R/valuation/snapshot.R
 historical backtest                                  R/valuation/backtest.R
```

## 1. Inputs and point-in-time rules

| Input | Source | Point-in-time handling |
|---|---|---|
| Current week, QB/RB/TE | ESPN `leaguedefaults/3` capture taken by the valuation run | its capture time ≤ the valuation time |
| Current week, WR | `m4_two_stage_v1` from the latest **archived official** prospective run ≤ the valuation time | read only, hash-checked against `archive/prediction_manifest.csv`; used only if the capture still projects the WR above 0 |
| Future weeks | ESPN's **posted** future-week projections in the same capture | VE0; unvalidated, labelled `posted_future` |
| Fallback level | ESPN week-of (final pregame) projections of completed weeks | only weeks already played |
| Schedule, byes, opponents | latest live nflverse schedule ≤ the valuation time | — |
| Opponent factor | 2026 player stats of completed games | weeks before the valuation week |
| Model parameters | `models/valuation/ros_params_v1.yml`, derived from 2019–2025 | no 2026 outcome used |

Stored data:
- ESPN week-of history for QB/RB/TE is in `data/raw/espn_valuation/`. It takes one request per season-week (128 requests on 2026-10-07).
- Captures are in `data/snapshots/espn_valuation/` (write-once). Their hashes are in `archive/valuation_espn_capture_manifest.csv`.
- ESPN data is never committed. The ESPN terms-of-use position and opt-in are unchanged ([docs/espn_projections.md](espn_projections.md)).

## 2. Projection-provider abstraction

Valuation code only reads the standardized weekly table. `validate_projection_table()` enforces its schema:

`player_id, espn_id, player_name, position, team, season, week, opponent, has_game,
proj, proj_raw, proj_kind, source, source_version, as_of_utc, availability_status,
p_active, lvl`

- `proj = p_active · lvl`.
- `proj = 0` whenever `has_game` is false.

Providers are listed per position and slot (current week or future weeks) in
`config/valuation.yml`. The first provider that covers a player-week wins.

| Position | Current week | Future weeks |
|---|---|---|
| QB, RB, TE | `espn_calibrated` | `espn_posted_future`, then `extrapolated` |
| WR | `m4_archive`, then `espn_calibrated` | `espn_posted_future`, then `extrapolated` |

To add a QB/RB/TE model, write `provider_<name>(ctx, rows)` returning standard rows,
and list it first for that position. No other code changes.

Scoring: ESPN stat lines are rescored with `config/scoring/<league scoring>.yml`.
`espn_ppr` reproduces ESPN's totals (actuals exactly; projections to within 0.07 points).
The ROS calibration was fit on PPR, so a different scoring system needs refitted parameters (V2).

## 3. Rest-of-season projections

For valuation week *w*, the horizon covers weeks *w* to the last fantasy week (17), with segments:
- regular season: *w*–14;
- playoffs: 15–17.

The segments are configurable.

- **Current week (observed).**
  - QB/RB/TE: `E = c0_p + d0_p · ESPN`, a per-position linear calibration (slopes 0.93–0.96).
  - WR: the archived M4 prediction. It is already calibrated and includes the
    current-week Questionable/Doubtful availability model.
- **Future weeks.** Expected points come from one fixed model of the weekly level `X`:
  `E = c_{p,b} + d_{p,b}·X + q_{p,b}·X² [+ g_p·X·(opp − 1)]`, by position and horizon bucket
  *b* ∈ {1, 2–3, 4–7, 8+}, least squares over all future team-game rows (0 without a stat line).
  - `X` is ESPN's posted projection for that week when present (**observed future projection**).
    Otherwise it is `L_avg4`, the mean of the player's last up-to-4 positive week-of projections,
    including the current week (**extrapolated**).
  - Decay with horizon is inside `c`, `d` and `q`. Expected attrition from new injuries and
    benchings is therefore included, and grows with the horizon.
  - **Byes** give 0 (from the schedule). **A posted 0 in a game week** is ESPN's
    expected absence, or no role, and gives 0 for that week only.
  - **Schedule.** Posted weeks already include the opponent. For extrapolated weeks only,
    an opponent term uses shrunk points allowed to the position. Its effect is negligible: it
    improved weekly MAE by under 0.04% and was kept only because the pre-registered rule
    allows it. There are no playoff-schedule bonuses.
- **Availability.**
  - The current designation affects the current week only. That means the M4 adjustment for
    WRs; QB/RB/TE get no adjustment because none has been validated.
  - Future availability comes from the model and ESPN's posted zeros. A designation is never extrapolated.
  - VE1 found WR Questionable carry-over of 4–5 points over 1–3 weeks. It is noted for V2 and not used.
  - For the roster simulation, `p_active = plogis(a_{p,b} + e_{p,b}·log X)` and
    `lvl = E / p_active`. It is used only to draw weekly availability.
- **Selection (VE1).**
  - `L_avg4` beat the current-week projection by 3% in ROS-total MAE. Blending in actual
    points per game did not help beyond the tie band.
  - The quadratic form removed most of the linear form's top-quintile under-prediction:
    for QB, 17.1 → 18.7 against an actual 19.1.
  - Selection used development seasons 2019–2023; check seasons were 2024–2025.

## 4. League settings (default: ESPN standard PPR)

| Setting | Default |
|---|---|
| Teams | 10 |
| Starters | 1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX (RB/WR/TE) |
| Bench | 7, assumed to hold QB/RB/WR/TE |
| Scoring | ESPN PPR |
| Regular season | weeks 1–14 |
| Playoffs | weeks 15–17 |

- D/ST and K are outside the model. They occupy their own slots only.
- The IR slot is ignored.
- Slots are `{name, eligible, count}`, so 2QB, superflex and WR/TE flex need configuration only.
- Sensitivity leagues are defined in `config/valuation.yml`.

## 5. Starter allocation and FLEX

Each week, the league's `teams × slots` starting spots are filled by an exact
maximum-weight assignment:
- The sets of players that can be seated are the independent sets of a transversal matroid.
- So greedy selection by expected points, with a Hall-condition check over position subsets, is optimal.
- Toy leagues with hand-solved optima are in the tests.

The FLEX composition is whatever the projections imply.

**Exchange baselines.** For a departing position-*p* starter, the replacement is the best
alternative *y* such that "starters − p + y" can still be seated. These are the minimal
LP dual slot prices:
- Positions that currently occupy FLEX share one baseline: the best flex-eligible alternative.
- A position absent from FLEX keeps its own baseline. This is usually TE.
- In superflex, the QB baseline joins the FLEX pool.

There are two baselines:
- `S_p(t)`, the **marginal starter**. The alternatives are all non-starters.
- `R_p(t)`, the **waiver replacement**. The alternatives are players outside the rostered pool,
  and the exchange is taken over the starters seated from rostered players.

## 6. Rostered pool and replacement level (VE3)

The league rosters `teams × (starters + bench)` players.
- Each position's share is its share of league starters, averaged over the horizon's
  weekly allocations, so FLEX usage and byes are included.
- Within a position, the pool is filled by ROS points.
- With bench = starters, as in the default 7 + 7, every position rosters twice its league starters.

**Why not the re-draft's fixed point (VE2)?** It did not converge, and it hoarded backup QBs:
- It rostered 30 QBs.
- Hoarding is self-reinforcing: a lower streaming level makes backups worth drafting.
- It values bench players only for injury and bye cover, not for upside. VE1 estimates ROS
  level uncertainty at 45–53% of the forecast, and upside is why managers carry RB and WR depth.

As a diagnostic only, the proportional pool (QB 20, RB 46, WR 54, TE 20) is close to ESPN's
≥50%-owned counts (20, 45, 57, 19). The fixed point is kept as a sensitivity.

The waiver level `W_p(t)` is the best non-rostered player's expectation that week. It assumes free weekly streaming.

## 7. Value metrics

| Metric | Definition | Role |
|---|---|---|
| ROS points | Σ_t E_i(t) | intermediate quantity; not value |
| **ROS VOR** | **Σ_t max(0, E_i(t) − R_p(t))** | **primary economic value** |
| ROS VOR (raw) | Σ_t (E_i(t) − R_p(t)) | assumes no substitution (reported) |
| ROS VAS | Σ_t (E_i(t) − S_p(t)) | strength against the marginal league starter (unfloored) |
| MRU | mean over simulated teams that do not own *i* of ΔU from adding *i* and dropping the team's least valuable player | generic roster utility; captures lineup slots and roster fit |
| Trade value | 100 · f(VOR) / f(max VOR) | display scale only |

- **Weekly, not aggregate.** The calculation follows byes, injuries and week-specific baselines. A
  week below replacement is floored at 0, because a manager would start the free
  replacement instead. Lineups are set on expectations, so the floor applies to expectations.
- **VAS versus VOR.**
  - VAS asks how much better than the league's last starter a player is.
  - It goes negative for bench-level players, and it compresses QB/TE values more than VOR does,
    because their starter and replacement levels are close.
  - VAS is reported for comparison and is not the primary metric.
- **Generic teams and MRU.**
  - A snake re-draft with streaming at the pool's waiver level builds the generic teams.
  - Each pick maximizes Δ expected ROS lineup points.
  - Monte Carlo weekly availability uses 200 draws with common random numbers.
  - The lineup evaluator is exact for laminar slots.
- **Display map `f`.**
  - Isotonic regression of MRU on VOR over all players with VOR > 0, then a monotone spline.
  - The display value is a monotone transformation of VOR whose curvature comes from lineup
    economics: low-VOR players mostly displace near-equivalents or sit on a bench.
  - No "stud premium" is assumed. The raw VOR is in every table.

## 8. Packages and consolidation

A 2-for-1 is evaluated as **A + replacement versus B + C** on a simulated team
(`val_trade_eval()`):
- the side receiving fewer players fills each freed roster spot with the best free player;
- the side receiving more players drops its least valuable players;
- lineup slots and the team's existing starters decide how much of B + C is usable.

`val_consolidation_study()` compares this with naive VOR sums on elite-for-two trades
between simulated teams with equal VOR sums. No package penalty parameter exists.

## 9. Uncertainty (structure for later use)

From the VE1 diagnostics:
- **Weekly residual SD:** about 7–10 points for starter-level projections.
- **ROS-total residual SD:** about 45% of the forecast (RB about 50%).

These are reported but not yet used in value. Per-player level uncertainty is the main V2 addition,
in the simulation and in risk-adjusted values.

## 10. Point-in-time valuation snapshots

`scripts/valuation_run.R` (after a weekly run; `--capture` takes a new ESPN capture) writes
`data/archive/valuation/season=S/week=WW/run=<UTC>/`. Each run holds:
- values, weekly rows, baselines, scarcity, generic rosters, display knots,
  sensitivity results, consolidation, and `run_meta.json`.

The meta records:
- time, season and week;
- the league and its hash;
- the scoring file hash;
- provider configuration;
- the ESPN capture hash;
- the archived M4 run id and hash;
- the ROS parameter hash;
- the methodology version, simulation settings, live nflverse files and git commit.

Hashes go to `archive/valuation_manifest.csv`. VE-P1 pre-registers the prospective comparison
of posted and extrapolated future weeks.

## 11. Validation

1. **VE1 ROS backtest.** Development 2019–2023, check 2024–2025. Results are in the log.
2. **Valuation backtest** (`val_backtest()`, 2019–2025, weeks 4/8/12, parameters from 2019–2023):
   - projected VOR against realized decision-based VOR;
   - realized replacement is the mean actual points of the 3 best-projected non-rostered eligible players.
   - Reported: within-position Spearman correlation, realized/projected ratio and slope by position
     (flag at ±25% of the pooled ratio), and QB and TE counts in the top 30.
3. **Sensitivity** to league size, FLEX, 3 WR, bench, superflex and the rostered-pool rule.
4. **Toy-league unit tests:**
   - allocation optimality, FLEX and exchange baselines, superflex, byes;
   - VOR floor, display monotonicity, scoring;
   - providers, posted zeros, extrapolation;
   - lineup evaluator, Monte Carlo cover, draft, MRU;
   - 2-for-1 accounting, league size, archive integrity, M4 hash check.
5. **Secondary diagnostics, never targets:** ESPN %owned and ESPN's own ROS.

No public trade chart is used.

## 12. Limitations

- Generic, symmetric league. There are no actual league rosters, free agents or waiver priority.
  Streaming is free and unlimited at the best waiver level.
- QB, RB and TE use ESPN only. ESPN's posted future weeks and injury timelines are unvalidated
  until VE-P1. ROS parameters are PPR-specific.
- Values are expectations. Level uncertainty is not used. The generic draft ignores upside,
  which is why it does not define replacement.
- Availability draws are independent across players. There are no handcuff or teammate correlations.
- K, D/ST and IR slots are not modelled. The bench is assumed to hold skill players.
- Historical backtests use extrapolated future weeks only, because posted future weeks cannot be recovered.
