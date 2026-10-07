# Valuation V2 methodology (`valuation_v2`): league-specific trade analysis

V2 extends V1 ([valuation_methodology.md](valuation_methodology.md)) and changes none of its outputs.
- Plan: [valuation_v2_plan.md](valuation_v2_plan.md).
- Decisions: `research/valuation_log.md` (VL0 onward).
- Projection research (M1–M4) is untouched.

> V1 asks what a player is worth in a generic league. V2 asks what acquiring or giving
> away a player does to **this** team, given who it already owns and who is actually
> available.

## 1. Inputs (all point-in-time and archived)

| Input | Source | Reproducibility |
|---|---|---|
| League settings, teams, rosters | `scripts/league_refresh.R`: one ESPN request using the owner's cookies | `data/snapshots/espn_league/<alias>/` is write-once. Hashes go to `archive/league_snapshot_manifest.csv`. |
| Weekly projections | the archived V1 valuation run for that week, preferably **valued in this league's format** (`valuation_run.R --league`) | the run id and values hash are recorded in every analysis |
| Generic value | V1 methodology (VOR, 0–100) in the league's format | same run |
| Configuration | `config/valuation.yml` `league_analysis` | fixed in VL0 |

- **Privacy.**
  - The league id and cookies are only in the git-ignored `config/local.yml`, or the environment variables `ESPN_S2` and `ESPN_SWID`.
  - Archives use a random alias.
  - Committed manifests contain only hashes, counts, times and that alias.
  - Team names, rosters and results stay local, and so does the V2 report.
- **Staleness.** The analyzer refuses a league snapshot older than 24 hours unless `--allow-stale` is given. It always prints the snapshot's age.

## 2. League settings mapping

ESPN `lineupSlotCounts` maps to V1 slots:

| ESPN slot | V1 slot |
|---|---|
| QB (0) | QB |
| RB (2) | RB |
| WR (4) | WR |
| TE (6) | TE |
| FLEX (23) | FLEX {RB,WR,TE} |
| RB/WR (3) | RB/WR |
| WR/TE (5) | WR/TE |
| OP (7) | SUPERFLEX {QB,RB,WR,TE} |

- **Roster size:** K and D/ST count toward it, but are not valued.
- **Bench:** slot 20. **IR:** slot 21, which does not count toward roster size.
- **Fail clearly:** TQB, IDP, P, HC and non-laminar slot sets.
- **Horizon:** the regular season and playoff weeks come from `scheduleSettings`.
- **Position limits** are enforced on drops and adds.

**Scoring:** `scoringItems` are mapped through ESPN stat ids.
- PPR identical to ESPN's default: the V1 ROS parameters and the M4 WR source apply unchanged.
- Any other scoring: projections are rescored with the league rules, M4 is not used (it predicts PPR), and the PPR-fit ROS calibration is an approximation.
- Unmapped bonuses and per-slot overrides are listed.

## 3. Team utility

`U(team)` = expected ROS starting-lineup points over the horizon (full ROS by default; regular season and playoffs also reported):
- **Weekly availability:** V1 Monte Carlo draws (200 draws, fixed seed, common random numbers, so results are deterministic). The current week is deterministic.
- **Lineup:** each draw seats the optimal legal lineup from **rostered** players (V1 slot greedy, exact for laminar slots).
- **Streaming policy `empty_slots`:**
  - A free agent at the **actual** weekly free-agent level fills a slot only when no rostered eligible player is active.
  - The level is the best FA expectation at the position that week, where the FA pool is the projected QB/RB/WR/TE not on any roster.
  - Bench players therefore have value, but less than starters: they cover byes and injuries at their own level instead of the FA level.
  - Players who are blocked never score.
  - Sensitivity runs use `none` and `unlimited` (V1-style).
- **Attribution:** started points and expected starts per player, points by slot, streamed points.

## 4. Trades

1. Apply the transfer.
   - A received player who was in an IR slot goes to the receiving team's IR slot, if it has a free one.
2. **Forced drops** for any team over its roster or position limit.
   - Drops are greedy: each one maximizes U.
   - Received players are eligible to be dropped.
   - Dropped players join the FA pool.
3. **Open spots** are filled with the free agent that adds the most U. They are filled only while the gain is positive, so an empty slot that streaming would cover anyway earns nothing.
4. Compute U after for both teams, using the post-transaction FA pool.
5. Δ = U after − U before.
6. **Invariants:**
   - traded players leave their team;
   - received players are added once;
   - no player is on two teams;
   - adds were free agents and drops become free agents;
   - roster sizes and position limits are legal.

**Metrics:**
- ΔA and ΔB;
- surplus ΔA + ΔB;
- balance ΔA − ΔB;
- generic VOR and display value exchanged;
- consolidation effect (Δ minus the generic VOR difference);
- drops and adds with their utility.

**Classification** (VL0; ε = 5 and S = 20 points), checked in order:

1. harmful to both
2. strong win-win (both above S)
3. mild win-win (both above ε)
4. balanced (|ΔA − ΔB| ≤ ε)
5. favors A or B (strongly if the balance exceeds S)

**Explanations** are generated only from model numbers:
- starts and started points of received and departing players;
- who gains or loses lineup time;
- the slot with the largest change;
- forced drops and waiver adds;
- changes in streaming;
- the generic comparison.

## 5. Marginal team value, search, needs

- `MTV(i, T) = U(T + i − best drop) − U(T)` for players not on T.
- `MTV(i, T) = U(T) − U(T − i + best add)` for T's own players.
- The matrix covers rostered players and the top free agents. It is cached in the analysis archive.

| Function | How it works |
|---|---|
| **Fair and win-win search** (`lg_trade_search`) | Up to 12 candidates per team with VOR > 5 or MTV > 2, structures 1-for-1, 2-for-1, 1-for-2 and 2-for-2. Packages are kept when generic display values are within 40 points. The 250 most promising by the MTV approximation are fully evaluated. Results are ranked as win-win first, then by surplus, then by the smaller of the two gains, then by fewer players. |
| **Target offers** | Packages of 1–3 of my candidates within 25 display points of the target, kept when the target's team loses at most ε, ranked by my gain |
| **Sell destinations** | Teams ranked by MTV of the player. The best returns of 1–2 players that improve that team are ranked by my gain. |
| **Team needs** | Slot points against the league median (weakest and strongest slot); bench contribution by position; starter-to-backup drop, where the backup is the better of the next rostered player and the best free agent; best waiver upgrade (FA add with a forced drop) |
| **Power rankings** | U, segments, points by position, FLEX, bench and streamed contributions. These are projections, not standings. |

## 6. Interfaces

```bash
Rscript scripts/league_refresh.R                      # league snapshot (one request)
Rscript scripts/valuation_run.R --league --capture    # V1 values in this league's format
Rscript scripts/trade_analyzer.R snapshot             # archive rankings, needs, waivers, MTV matrix
Rscript scripts/trade_analyzer.R analyze --a "Team A" --give-a "P1;P2" --b "Team B" --give-b "P3"
Rscript scripts/trade_analyzer.R fair --b "Team B" --win-win     # --a defaults to my team
Rscript scripts/trade_analyzer.R target --player "Name"
Rscript scripts/trade_analyzer.R sell --player "Name"
Rscript scripts/trade_analyzer.R rankings | needs | waivers | values --player "Name"
```

In R: `m <- lg_load()`, then `lg_trade()`, `lg_trade_search()`, `lg_target_offers()`,
`lg_sell_destinations()`, `lg_team_needs()`, `lg_power_rankings()` and `lg_mtv_matrix()`.

Every query is archived write-once (`archive/league_query_manifest.csv`).

## 7. Limitations

- Expected values only. There are no score distributions, playoff probabilities or acceptance predictions.
- Free agents are always acquirable: no FAAB, priority or contention, and several teams may stream the same player.
- Streaming fills empty slots only. A team never streams over a rostered starter, even a weak one; the waiver-upgrade diagnostic shows those cases.
- The quality of QB/RB/TE projections is V1's: ESPN, with posted future weeks unvalidated.
- K and D/ST are not valued. IR players need no roster spot when activated.
- No historical trade validation, because historical point-in-time rosters and waiver pools do not exist. The archive enables prospective checks.
