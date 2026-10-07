# Valuation V1 plan: rest-of-season player value

> **Status (end of V1).** This plan is kept as written. Three logged changes followed:
> - VE1a/VE1c: the ROS functional form, now quadratic, fit on all rows.
> - VE3: the waiver baseline uses the proportional rostered pool. The re-draft builds the generic teams only.
>
> See `research/valuation_log.md` and `docs/valuation_methodology.md`.

Written 2026-10-07, before any valuation experiment was run. This is a separate
track from projection research: Projection M5 is paused, and the frozen lineages
M1–M4 and their 2026 prospective record are not touched.

> **Value definition.** A player's value is the expected contribution that owning
> him adds to a constrained fantasy roster, relative to the alternatives available
> at his position and in the player pool.

Pipeline: weekly projections → rest-of-season (ROS) weekly expectations →
league starter allocation → replacement and marginal-starter baselines → VOR →
generic roster utility → display trade value → package evaluation.

## 1. Existing infrastructure reused (not duplicated, not modified)

| Need | Reused piece |
|---|---|
| ESPN requests, team ids | `espn_request()`, `ESPN_API`, `ESPN_SLOT_IDS`, `ESPN_POSITION_IDS`, `espn_team()` (R/data/espn.R, R/live/live_data.R) |
| ESPN ↔ GSIS ids | `build_espn_crosswalk()`: ID-only, ambiguous ids left unmatched |
| Scoring | `read_scoring_rules()`, `score_fantasy_points()`, `config/scoring/espn_ppr.yml` |
| Actual points, rosters, schedule, byes | `clean_player_stats()` (all positions), `clean_rosters_weekly()` (status `RES`), `clean_team_games()` (opponent, kickoff, byes = weeks with no row) |
| Live 2026 inputs | `latest_live_file()` over `data/raw/nflverse_live/`, which each weekly run refreshes |
| WR current-week forecast | Archived official prospective runs (`data/archive/predictions`, verified against `archive/prediction_manifest.csv`). These are read only, and `m4_two_stage_v1` predictions are used as-is. |
| Immutability, hashing | `write_once()`, `sha256_file()`, `append_manifest()`, `utc_stamp()` |
| Validation | `assert_unique_key()`, `assert_no_missing()`, `assert_in_range()` |
| Tooling | targets, renv, Parquet, YAML config, Quarto, testthat |

Nothing in R/data, R/features, R/models, R/evaluation or R/live is edited. The
weekly runner, registries, fingerprints and manifests are unchanged.

**What ESPN publishes for future weeks.** This was checked with one request on 2026-10-07:
- ESPN posts a weekly projection for **every remaining week (W5–W18)** for about 570 QB/RB/WR/TE.
- Bye weeks are 0.
- Injured players are 0 for the weeks ESPN expects them out. For example, an IR
  receiver is 0 in W5–W6 and positive from W7. 41 IR players are 0 for the rest of the season.
- Healthy players' future weeks are nearly flat: the median coefficient of variation is 5%, so they look like a season rate with small matchup adjustments.
- ESPN's season projection (`statSplitTypeId 0`) equals the sum of the remaining weekly values exactly.
- Past weeks are overwritten with the final pregame value. **Historical future-week projections therefore cannot be recovered, and they cannot be validated historically.**

## 2. Projection-provider abstraction

Valuation code reads one standardized weekly table and never ESPN columns.
Key `(season, week, player_id)`:

`player_id, espn_id, player_name, position, team, season, week, opponent, has_game,
proj (expected PPR points, calibrated), proj_raw, proj_kind (current_week |
posted_future | extrapolated), source, source_version, as_of_utc,
availability_status, p_active`

`validate_projection_table()` enforces the schema.

Providers are functions keyed by name in `config/valuation.yml`, and for each
position the first provider that covers a player-week wins:

| Position | Current week | Future weeks |
|---|---|---|
| WR | `m4_archive`: `m4_two_stage_v1` from the latest archived official run at or before the valuation time; falls back to `espn_calibrated` | `ros_v1` from ESPN |
| QB, RB, TE | `espn_calibrated` | `ros_v1` from ESPN |

Our own RB, TE and QB models can later be added as providers. That is a
configuration change and needs no valuation code.

## 3. ROS projections

For valuation week *w* and future week *t = w + h*:

- **Current week (h = 0), observed.**
  - WR: the M4 prediction.
  - Others: `c_p0 + d_p0 · ESPN_w`, a per-position linear calibration of ESPN's
    week-of projection, fit on 2019–2025.
- **Future weeks (h ≥ 1):** `E_i(t) = G_i(t) · A_p(h) · (c_{p,b(h)} + d_{p,b(h)} · X_i(t))`
  - `G_i(t) = 0` on a bye. It is also 0 when ESPN posts 0 in a game week, which
    is ESPN's expected absence or no role (ESPN signal).
  - `X_i(t)` is ESPN's **posted** future-week projection when it exists. Otherwise
    it is the **extrapolated** level `L_i`, built from recent ESPN week-of
    projections; its definition is chosen in the pre-registered study VE1.
  - `A_p(h)` is the historical probability that a player projected active at *w*
    records a stat line at *w + h*. This is the attrition from *new* injuries and benchings.
  - `c, d` are the historical calibration for points if active, by position and
    horizon bucket `b(h) ∈ {1, 2–3, 4–7, 8+}`.
  - `A`, `c` and `d` are fit on 2019–2025 with `L` as the predictor. They are frozen in
    `models/valuation/ros_params_v1.yml`, and the pipeline checks that a
    re-derivation equals the committed file.
- **Schedule.**
  - Posted ESPN weeks already include the opponent.
  - An opponent factor for extrapolated weeks is tested in VE1 and kept only if it
    helps in both the development and the check seasons.
  - No playoff-schedule bonus is applied.
- **Availability.** A current Questionable designation affects the current week
  only, through M4 for WRs. QB, RB and TE get no Q adjustment because none has been validated.
  Future weeks use `A_p(h)` plus ESPN's posted zeros. No designation is
  extrapolated across the ROS.
- **Output horizons.**
  - rest of regular season (*w*–14);
  - fantasy playoffs (15–17);
  - full (*w*–17).
  - Every row is labelled `current_week`, `posted_future` or `extrapolated`.

## 4. Default league (ESPN standard PPR; all configurable)

| Setting | Default |
|---|---|
| Teams | 10 |
| Starters | 1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX (RB/WR/TE). D/ST and K are outside the model. |
| Bench | 7, assumed to hold QB/RB/WR/TE. The IR slot is ignored. |
| Scoring | `espn_ppr` (ESPN's `leaguedefaults/3`) |
| Regular season | weeks 1–14 |
| Playoffs | weeks 15–17. Week 18 is excluded. |

Slots are a list of `{name, eligible positions, count}`. Superflex is
`{SUPERFLEX, [QB,RB,WR,TE], 1}`, so 2QB and superflex leagues need configuration only.

## 5. Replacement level: generic league equilibrium

- The rostered pool has `teams × (starters + bench)` players.
- Its composition **emerges** from a deterministic generic **re-draft simulation**:
  - snake order;
  - each pick maximizes the team's expected ROS starting-lineup points;
  - availability is Monte Carlo per player-week from `A_p(h)` and `G`, with fixed seeds and common random numbers;
  - empty or bye slots can be streamed at the waiver level.
- Bench value therefore comes from covering byes and injuries, net of what waivers
  would supply. Deep positions such as QB need little bench. Injury-prone
  positions need more. No bench quota is declared by position.
- The waiver level used inside the draft depends on who is drafted. It is solved
  by fixed-point iteration: initial levels → draft → undrafted → new levels. The iteration stops when the rostered set is stable, with a cap of 6 iterations.
- **Waiver baseline `R_p(t)`:** the best undrafted alternative in week *t* that can
  fill a vacated position-*p* starting spot, using the exchange rule of §6.
- **Sensitivity rule:** bench shares proportional to starter shares (reported, not used).

## 6. FLEX allocation

- Each week the league's `teams × slots` starting spots are filled by an **exact**
  max-weight assignment.
  - Eligibility sets form a transversal matroid, so greedy selection with a Hall-condition feasibility check over position subsets is optimal.
  - FLEX composition emerges from projected points.
- Position baselines come from **exchange**: the best non-starter *y* such that
  "starters − x + y" is still feasible. These are the minimal LP dual slot prices.
  - With FLEX, the baselines of positions present in FLEX equalize at the best flex-eligible alternative.
  - A position absent from FLEX keeps its own baseline.
- **Marginal-starter baseline `S_p(t)`:** the alternatives are all non-starters.
- **Waiver baseline `R_p(t)`:** the alternatives are undrafted players only.

## 7. VOR (primary)

`VOR_i(t) = E_i(t) − R_p(t)`, and **ROS VOR = Σ_t max(0, VOR_i(t))** over the horizon.
- The weekly calculation follows byes, injuries and the week-specific replacement.
- Totals are reported for the regular season, the playoffs and the full horizon.
- The raw unfloored sum and `ROS points − Σ_t R_p(t)` are also reported.

**Value Above Starter (VAS)** = `Σ_t (E_i(t) − S_p(t))`, unfloored. It is
compared with VOR and is not the primary metric.

## 8. Negative values

- Weekly VOR is **floored at 0**. A manager facing a week below replacement (a bye,
  an injury or a bad role) starts the free replacement instead. Lineup decisions
  are made on expectations, so the floor applies to expectations, not to outcomes.
- This assumes free weekly streaming at `R_p(t)`. The raw sum, which assumes no
  substitution, is shown for comparison.
- VAS stays unfloored. Its negative values flag players who are not startable at league level.

## 9. Scarcity

Scarcity is not declared. It emerges from the allocation. The reported diagnostics are:
- `R_p(t)` and `S_p(t)` by week;
- FLEX composition by week;
- value curves by positional rank (QB1–30, RB1–60, WR1–80, TE1–30) for ROS points, VOR, VAS and trade value;
- elite − replacement and marginal starter − replacement drop-offs;
- the number of players above value thresholds.

## 10. Trade-value display scale

Display value `TV = 100 · f(VOR) / f(max VOR)`.
- `f` is a monotone fit (isotonic regression, then a monotone spline) of the **generic
  marginal roster utility** on ROS VOR, pooled over positions.
- So TV is a monotone transformation of VOR, and any curvature comes from lineup
  economics, not from a chosen premium.
- If the roster simulation is disabled, `f` is the identity.
- Raw VOR stays in every table.

**Generic marginal roster utility (MRU), secondary.** For player *i*, MRU is the mean over the
simulated teams that do not own *i* of the gain in expected ROS lineup points from
adding *i* and dropping that team's least valuable player.

## 11. Packages and consolidation

- Naive package value is the sum of VOR or of TV. It is reported for comparison only.
- **Roster-aware evaluation** on the simulated generic teams:
  `ΔU = U(roster − give + get ± roster-spot adjustment) − U(roster)`.
  - The side that receives fewer players **adds the best waiver player** for each freed spot (A + replacement versus B + C).
  - The side that receives more players **drops** its least valuable players.
- Consolidation is studied by comparing ΔU with summed VOR for elite-for-two
  trades between actual simulated teams. No package penalty is introduced.

## 12. Validation

1. **VE1 ROS backtest.**
   - Development 2019–2023, check 2024–2025.
   - Metrics: MAE and RMSE of ROS totals by position, rank correlation, and calibration by horizon.
2. **Valuation backtest.** At weeks 4, 8 and 12 of 2019–2025, projected VOR is compared with realized
   **decision-based** VOR. Realized VOR counts actual points minus the realized
   replacement, in weeks the projection said to start the player.
   - The comparison is within positions (rank correlation).
   - It is also across positions (realized/projected ratio and slope by position). This is the quantitative check for QB over-valuation.
3. **Sanity checks.**
   - Ordering within positions.
   - QB versus RB/WR values in 1QB leagues.
   - Whether TE scarcity emerges.
   - Bye handling.
   - Sensitivity to 8, 10, 12 and 14 teams, no FLEX versus 2 FLEX, 3 WR, bench 5 versus 7 versus 9, and superflex (illustrative only).
   - Consolidation examples.
4. **Toy-league unit tests** with known solutions (allocation, FLEX, exchange baselines, VOR, packages, snapshots).
5. **Secondary diagnostics, never targets.**
   - ESPN's own ROS projection.
   - ESPN %rostered against our modeled rostered pool.
   - No public trade chart is scraped or matched.

## 13. Repository changes

New:
- `R/valuation/` (providers, ESPN capture and parsing, ROS, allocation, baselines,
  VOR, simulation, trade value, packages, snapshots, studies);
- `config/valuation.yml`;
- `models/valuation/ros_params_v1.yml`;
- `scripts/valuation_run.R`;
- `archive/valuation_manifest.csv` and `archive/valuation_espn_capture_manifest.csv` (hashes only);
- `tests/testthat/test-valuation-*.R`;
- `docs/valuation_methodology.md`;
- `research/valuation_log.md`;
- `reports/valuation_v1_report.qmd`, rendered to `reports/valuation_v1_report.html`.

The rendered HTML is git-ignored like every other report, because it contains ESPN-derived values.

Data, all git-ignored and never committed:
- `data/raw/espn_valuation/` (historical QB/RB/TE week-of projections, one request per season-week);
- `data/snapshots/espn_valuation/` (point-in-time captures of current and future weeks);
- `data/archive/valuation/` (write-once valuation runs).

`_targets.R` gets an appended valuation block. Existing targets and fingerprints are unaffected.

## 14. Major limitations

- No league-specific rosters, ownership or free agents. The league is generic and symmetric.
- QB, RB and TE use ESPN only, with no validated Questionable adjustment.
- ESPN's posted future weeks are unvalidated, including their injury timelines. A prospective comparison is pre-registered.
- The value is an expectation. Per-player uncertainty is estimated and reported but not used in the value.
- Weekly availability is independent within the simulation. Teammate and handcuff correlation is ignored.
- K, D/ST and the IR slot are excluded. Waiver priority and FAAB are not modelled.
- ESPN terms of use apply (owner opt-in, private research, nothing committed).

## 15. Not attempted in V1

- team-specific trade recommendations, contender or rebuilder logic, dynasty, keepers or auctions;
- our own QB, RB or TE projection models;
- start/sit or win probability;
- connecting to a private ESPN league;
- K and D/ST;
- tuning to consensus or trade charts;
- playoff-schedule bonuses;
- hand-set scarcity, player or "stud" adjustments;
- any change to M1–M4 or their prospective record.
