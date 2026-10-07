# Valuation V2 plan: league-specific trade analyzer

Written on 2026-10-07, before any league data was analysed. The first probe of the owner's
league returned HTTP 401, so the league is private and needs the owner's cookies.

V2 extends Valuation V1 and leaves it unchanged:
- V1 methodology, the archived V1 runs, the generic values and `valuation_v1` are all preserved;
- projection research is untouched (M1–M4 frozen, fingerprints re-checked, M5 paused).

> **Decision variable.** The expected optimized ROS roster utility of a team after a trade,
> minus the same quantity before it. Generic V1 value is reported alongside as context.

## 1. V1 architecture reused

| Need | Reused |
|---|---|
| Weekly expectations | an **archived V1 valuation run**, consumed as is. It holds `proj`, `p_active` and `lvl` per player-week and records the projection sources and ROS parameters. |
| Generic value in this league's format | `run_valuation()` with the league's settings and scoring. This is V1 methodology, archived as a separate run with its own league hash. |
| Lineup optimization | V1's slot greedy, which is exact for laminar slots, the top-K order statistics and the Monte Carlo availability draws with common random numbers (`val_sim_setup()`, `val_topk_insert()`, `val_lineup_spec()`) |
| Allocation and exchange | `val_hall_table()`, `val_allocate()` for league-wide checks |
| ESPN access | `espn_request()`, `ESPN_API`, `stop_if_espn_disabled()`, the opt-in in `config/local.yml` |
| Scoring | `VAL_ESPN_STAT_MAP`, `val_rescore()`, `read_scoring_rules()` |
| Archive | `write_once()`, `sha256_file()`, `append_manifest()` |

New code lives in `R/valuation/league_*.R` with an `lg_` prefix. The only exception is that `scripts/valuation_run.R` gains a `--league` option.

## 2. ESPN league integration

- **Endpoint:** `GET {ESPN_API}/seasons/{S}/segments/0/leagues/{id}?view=mSettings&view=mTeam&view=mRoster&view=mStatus`.
  - One request returns settings, teams, rosters (with ESPN player ids, lineup slot and acquisition type) and status.
- **Free agents:** the valuation pool minus every rostered player.
  - The pool is every QB/RB/WR/TE ESPN projects, drawn from the same point-in-time capture.
  - No extra request is needed.
  - Players on waivers count as available (assumption, §6).
- **IDs:** league entries carry ESPN player ids, the same id space as the valuation capture, so the join is by id, never by name.
- **Fetching** follows the existing opt-in (`espn.enabled`) and is done only by `scripts/league_refresh.R`.

## 3. Privacy and local configuration

- The league id and the private-league cookies are kept outside Git.
  - `espn_s2` and `SWID` go in the git-ignored `config/local.yml` (`league: {espn_league_id, espn_s2, swid}`), or in the environment variables `ESPN_S2` and `ESPN_SWID`.
  - They are never printed or logged. They are sent only as request cookies.
- **League alias:** a random alias (`league_<8 hex>`) is generated once and stored in `config/local.yml`. Manifests and archives use the alias, never the id, and never a hash of the id, which is brute-forceable.
- **Raw league data** (team names, rosters, settings) stays in `data/snapshots/espn_league/` and `data/archive/league_analysis/`. Both are git-ignored.
- Committed manifests hold only hashes, timestamps, counts and the alias.
- **My team** is detected by matching the configured SWID to `teams[].owners`, or set explicitly with `league.my_team_id`.

## 4. League settings mapping

ESPN `rosterSettings.lineupSlotCounts` maps to V1 `slots`:

| ESPN slot id | V1 slot |
|---|---|
| 0 | `QB` |
| 2 | `RB` |
| 4 | `WR` |
| 6 | `TE` |
| 23 | `FLEX {RB,WR,TE}` |
| 3 | `RB/WR` |
| 5 | `WR/TE` |
| 7 (OP) | `SUPERFLEX {QB,RB,WR,TE}` |

- **Outside the model:** 16 D/ST and 17 K are counted for roster size only. 20 is the bench. 21 is IR (does not count toward roster size).
- **Fail clearly:** TQB (1), IDP slots (8–15), P (18), HC (19), and slot sets that are not laminar (RB/WR with WR/TE). The fast evaluator would be inexact for those.
- **Teams:** `settings.size`.
- **Horizon:**
  - regular season = matchup periods 1…`matchupPeriodCount`;
  - playoffs = the following `ceil(log2(playoffTeamCount)) × playoffMatchupPeriodLength` weeks;
  - both are checked against the NFL schedule.
- **Scoring:** `scoringItems` (statId → points) are mapped through `VAL_ESPN_STAT_MAP` into a rules object.
  - Non-zero items with no mapping (bonuses, per-slot overrides such as TE premium) are listed and reported.
  - If the league equals `espn_ppr`, the V1 ROS parameters and the M4 WR source apply unchanged.
    Otherwise, projections are rescored with the league rules, M4 is disabled (it is PPR-only), and the PPR-fit ROS calibration is an approximation, which is reported.
- `positionLimits` are enforced on drops and adds.

## 5. Roster snapshot schema

`data/snapshots/espn_league/<alias>/season=S/captured_at=<UTC>.{json.gz,parquet}` is written once. Each row holds:

`captured_at_utc, season, scoring_period, league_alias, team_id, team_abbrev, team_name,
espn_id, player_name, nfl_team, position, lineup_slot_id, lineup_slot, is_ir_slot,
acquisition_type, acquisition_date, injury_status, on_team_id`

Settings are stored as parsed JSON next to it. Hashes go to `archive/league_snapshot_manifest.csv`.

The analyzer refuses a snapshot older than `max_age_hours` (default 24) unless told
`--allow-stale`. Every output states the snapshot age.

**Diagnostics** (`lg_id_diagnostics()`):
- rostered QB/RB/WR/TE with no projection rows (kept, worth 0, flagged);
- duplicate ownership (an error);
- position and NFL-team mismatches between the league entry and the capture;
- K/D/ST counts.

## 6. Actual waiver pool

- **FA pool:** valuation-pool players not on any league roster, including IR slots.
- **Weekly FA level** per position: the best FA expectation that week. Curves show the k-th best FA by position.
- These are compared with V1's generic waiver level for the same settings.
- **Assumption:** the best available player can always be added. There is no FAAB, waiver priority or contention, and several teams may stream the same free agent.

## 7. Team utility and before/after trade simulation

`U(team)` = expected ROS starting-lineup points over the horizon, by week:
- each Monte Carlo draw (V1 availability, S = 200, fixed seed) seats the optimal legal lineup from **rostered players**;
- the current week is deterministic.

**Streaming policy** (pre-registered default `empty_slots`): a free agent at the weekly FA level fills a slot only when no
rostered eligible player is active for it, as with a bye or injury cover nobody on the roster can provide.
- Bench players therefore have positive value below that of starters: cover beyond what a free agent would supply.
- Open roster spots have value.
- Sensitivity runs use `none` and `unlimited` (V1-style).

A trade:
1. take both rosters;
2. apply the transfer;
3. resolve roster limits (§8, §9);
4. compute U after, with the same draws and policy, for both teams;
5. report `Δ = U_after − U_before` per team.

Totals are reported for the full ROS (default), regular season and playoffs.

## 8. Forced drops

If the post-trade roster exceeds the limit, drop players greedily, one at a time. Each drop is the one that maximizes the post-trade U.
- Candidates are skill players outside IR slots. Received players are eligible; a report flags it if one is chosen.
- `positionLimits` are respected.
- Dropped players join the FA pool, which updates the other team's FA level.
- Each drop and its utility cost are reported.

## 9. Open roster spots and waiver adds

For each freed spot, add the free agent with the largest U gain, but only if the gain is above 0.
Candidates are the best 6 per position by ROS points. The add is reported, and an added player leaves the FA pool.

## 10. Team-specific marginal value

- **For a player on another team:** `MTV(i, T) = U(T + i − best drop) − U(T)`.
- **For own players:** `MTV(i, T) = U(T) − U(T − i + best add)`.

The matrix `MTV(players × teams)` covers rostered players plus the top free agents by generic VOR. It is cached, and it powers pruning, sell destinations, team needs, the TE check and the generic-against-specific comparisons.

## 11. Trade fairness metrics and classification

Reported for every trade:
- `ΔA` and `ΔB`;
- **net surplus** `ΔA + ΔB`;
- **balance** `ΔA − ΔB`;
- **generic balance**: V1 VOR and trade value exchanged, in the league's own format;
- **consolidation effect**: Δ minus the naive VOR difference of the exchanged players;
- drops and adds.

Thresholds are fixed now, before any real trade is seen, in expected ROS lineup points:
ε = 5 (about 0.4 a week) and S = 20. The rules are checked in order:

1. **harmful to both:** ΔA < −ε and ΔB < −ε
2. **strong win-win:** ΔA > S and ΔB > S
3. **mild win-win:** ΔA > ε and ΔB > ε
4. **balanced:** |ΔA − ΔB| ≤ ε
5. **favors A (strongly):** ΔA − ΔB > ε (> S); likewise for B

The raw numbers are always shown. These are model estimates, not predictions of acceptance.

**Explanations** are built only from model outputs:
- lineup changes by week (who starts instead of whom, and for how many weeks);
- the position slot gained or lost;
- drops and adds with their utility cost;
- players blocked from the lineup (received players with low expected starts).

## 12. Fair and win-win trade search

- **Candidates per team:** players with own-team MTV or generic VOR above a minimum (configurable; default VOR > 5 or MTV > 2), capped at the top N = 12 by generic value.
- **Structures:** 1-for-1, 2-for-1, 1-for-2 and 2-for-2.
- **Generic-value pre-filter:** |Σ trade value given − Σ received| ≤ 40 display points. This removes elite-for-waiver offers.
- **Utility filter:** a cheap bound from the MTV matrix (single-player gains and losses) before the full evaluation.
- **Win-win:** ΔA > 0 and ΔB > 0, ranked by surplus, then min(ΔA, ΔB), then fewer players.
- **Fair:** |ΔA − ΔB| ≤ ε, ranked by surplus.

## 13. Target acquisition and selling

- **Target X on team B:**
  - packages from my roster (1–3 players), within the generic band of X's value;
  - the full evaluation keeps options with `ΔB ≥ −ε`;
  - results are ranked by my ΔA, and several options are returned.
- **Sell X:**
  - teams are ranked by `MTV(X, T)`;
  - for each of the top teams, the best returns (1–2 players) with ΔT > 0 are ranked by my Δ.

**Team needs**, all derived from marginal utility:
- weakest starter slot and strongest position (team's starter expectation against the league median by slot);
- deepest bench position;
- largest starter-to-backup drop;
- best waiver upgrade (an FA add with a forced drop).

**Power rankings:** U, starter points, bench contribution, and points by position from per-player attribution, labelled as projection-based.

## 14. Caching and performance

- **Cached:**
  - draws (one setup per analysis);
  - each team's top-K matrices with and without each player;
  - baseline U;
  - the FA candidate list;
  - the MTV matrix.
- Lineup evaluation is vectorized over 13 weeks × 200 draws.
- Search is profiled. The target is a full two-team search in about a minute.

## 15. Testing strategy

Toy leagues with hand-solved optima and synthetic ESPN JSON fixtures cover:
- parsing and settings mapping (including unsupported slots);
- ID diagnostics, the FA pool and lineup optimization (FLEX, superflex);
- byes, injuries, empty-slot streaming;
- 1-for-1, 2-for-1, 1-for-2, 2-for-2 and 3-for-1;
- forced drops, open spots, position limits, impossible trades;
- MTV and the search functions;
- stale snapshots and write-once archives;
- determinism.

**Invariants:**
- a traded player leaves his roster and is added exactly once;
- no player is on two teams;
- lineups satisfy slots;
- dropped players become free agents;
- adds were free agents;
- roster sizes are legal.

**Development data:** until the cookies are available, development uses a synthetic league built from V1's archived generic teams.

## 16. Expected repository changes

**New:**
- `R/valuation/league_espn.R`, `league_model.R`, `league_trade.R`, `league_search.R`;
- `scripts/league_refresh.R`, `scripts/trade_analyzer.R`;
- the `--league` option in `valuation_run.R`;
- `config/valuation.yml` `league_analysis:` (policy, thresholds, search bounds, staleness);
- `archive/league_snapshot_manifest.csv`, `archive/league_analysis_manifest.csv`;
- tests;
- `docs/valuation_v2_methodology.md`;
- entries VL1 onward in `research/valuation_log.md`;
- `reports/valuation_v2_report.qmd`, rendered locally and git-ignored.

**Unchanged:** V1 functions and frozen projection code.

## 17. Major limitations

- Expectation-based: no score distributions and no playoff probabilities.
- Free agents are always acquirable.
- Streaming happens only into empty slots.
- No modelling of manager behaviour or trade acceptance.
- ROS parameters are fit on PPR.
- K/D/ST are not valued.
- IR players need no roster spot when activated.
- No historical validation of trades. Point-in-time league histories do not exist; the archive enables later prospective checks.

## 18. Explicit non-goals

- new projection models or M5;
- playoff or season simulation;
- FAAB or waiver priority;
- acceptance prediction;
- dynasty, keepers or draft picks;
- K/D/ST valuation;
- paid data;
- tuning to public charts;
- manual positional need, player premiums or a TE discount;
- changing V1 outputs.
