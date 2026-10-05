# Player-week schema

**Grain:** one row per `(season, week, gsis_id)`, regular season only.
**File:** `data/processed/player_week_wr.parquet` (DuckDB table `player_week_wr`).
**Built by:** `build_player_week_base()` → `add_point_in_time_features()` → `finalize_player_week()`.

## Universe

The universe is the union of three sources, all at the configured position(s):
1. players on the weekly game-day roster (`ACT` or `INA`);
2. players with an nflverse stat line;
3. ESPN-projected players, when ESPN data are enabled.

Rows whose team had no game that week (byes) are excluded and counted in
`dataset_audit$excluded_no_game`. Players on IR or the practice squad who
neither played nor were projected are not in the universe.

## Identity

| Column | Description |
|---|---|
| `gsis_id` | NFL GSIS id. **The canonical key across all sources.** |
| `espn_id` | ESPN player id (NA when ESPN is disabled or unmatched) |
| `espn_match_method` | `id_unanimous` or `id_conflict_name_resolved` (see the crosswalk below) |
| `player_name`, `position` | Display name and position. Position priority: ESPN → weekly roster → stats. |

**ID crosswalk** (`build_espn_crosswalk()`) works as follows:
- Candidate `(espn_id, gsis_id)` pairs come from the nflverse player master, weekly rosters and the DynastyProcess map.
- A pair is accepted if all sources agree.
- On conflict, it is accepted only if exactly one candidate's normalised name equals ESPN's name.
- Two ESPN ids pointing at one gsis id are both rejected.
- **There is no fuzzy matching, and nothing is matched silently.** Unmatched and ambiguous ESPN players are listed in `dataset_audit$espn_unmatched_projected`.

Name normalisation transliterates to ASCII, lower-cases, and strips punctuation
and generational suffixes.

## Game context (as-of: schedule; lines = closing)

`team`, `opponent`, `home`, `game_id`, `kickoff`, `rest_days`, `team_spread`
(positive = favoured), `total_line`, `implied_team_total` = (total + spread) / 2.
The team is the stat-line team, or else the weekly-roster team. Context always
comes from the **schedule**, never from the player's stat row.

## Targets (as-of: post-game, used only as the target)

| Column | Description |
|---|---|
| `actual` | ESPN-PPR fantasy points from our scoring code. **0 if the player's team played and the player recorded no stat line.** |
| `has_stat_line` | Whether nflverse has a stat line for the player-week |
| `actual_targets`, `actual_receptions`, `actual_receiving_yards`, `actual_receiving_tds` | Box-score outcomes, never features |
| `espn_actual` | ESPN's own actual PPR total (validation reference) |

## Benchmark (as-of: ESPN final pregame)

`espn_proj` (PPR points), `espn_proj_receptions`, `espn_proj_targets`,
`espn_proj_receiving_yards`, `espn_proj_receiving_tds`, `espn_proj_rushing_*`.
`espn_proj` is NA when ESPN has no projection entry, which is different from a projection of 0.

## Point-in-time features (as-of: strictly prior games)

All features are computed from games with `game_index < (season, week)`.
Windows are counted in **games played**, not calendar weeks. See
[point_in_time_rules.md](point_in_time_rules.md).

| Column(s) | Description |
|---|---|
| `fantasy_pts_roll{3,8}` | Trailing mean of PPR points over the last 3 or 8 appearances. Crosses season boundaries. |
| `targets_roll*`, `receptions_roll*`, `receiving_yards_roll*` | Trailing usage and production |
| `target_share_roll*` | Targets ÷ team targets, per game, trailing mean |
| `air_yards_share_roll*` | Air yards ÷ team air yards |
| `snap_share_roll*` | Offensive snap share (PFR) |
| `rz_targets_roll*`, `rz_target_share_roll*` | Targets inside the opponent 20, from play-by-play |
| `xfp_roll*` | Expected fantasy points (ffopportunity) |
| `season_games`, `season_pts_mean`, `season_targets_mean` | Current season, prior weeks only. 0 or NA in week 1. |
| `prev_season_games`, `prev_season_pts_mean`, `prev_season_target_share` | Full previous season |
| `career_games`, `log_career_games`, `has_history` | Appearances before this week (since 2019) |
| `played_team_prev_game` | Whether the player appeared in the team's previous game (absence signal) |
| `changed_team` | Whether the team differs from the team of the player's last appearance |
| `team_pass_att_roll8`, `team_targets_roll8` | Team passing volume over its last 8 games |
| `opp_pts_allowed_roll` | PPR points the opponent's defence allowed to WRs over its last 8 games |
| `inj_out`, `inj_doubtful`, `inj_questionable` | Final injury-report designation (as-of: pregame report). Flagged group. |

An *appearance* is a stat line or at least one offensive snap. Snap-only
appearances count as zero production.

## Splits and populations

| Column | Description |
|---|---|
| `split` | `history` (2019, feature warm-up), `train` (2020–2023), `validation` (2024), `test` (2025) |
| `pop_espn` | ESPN projection > 0. **Primary population when ESPN is enabled.** |
| `pop_active` | On the game-day active roster. ESPN-free population, known about 90 minutes pregame and never a feature. |
| `espn_rank`, `relevant` | Rank by ESPN projection within the week. `relevant` = the top 60. |

## Scoring

See [scoring.md](scoring.md).
