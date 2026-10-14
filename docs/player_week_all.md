# Position-general player-week frame (F4)

**Grain:** one row per `(season, week, gsis_id)` with a team game, regular season, **2019–2025**.
**Positions:** QB, RB, WR, TE. K and D/ST are a separate table (see the end).
**Target:** `player_week_all` (pipeline; built when the valuation track's ESPN history is cached).
**Built by:** `build_player_week_all()` in `R/data/player_week_all.R`. It calls the existing
`build_player_week_base()` with all four positions; `player_week.R` and every frozen WR table are untouched.

The frame is infrastructure for the master plan's Phase 2 (P1–P4, F6). No model is selected here.
Every analysis on it must first call `assert_family_seasons()`, which enforces the
contamination register (`research/contamination_register.yml`).

## Universe and position

The universe is the same as the WR frame's (`docs/player_week_schema.md`), at all four positions:
- weekly game-day roster (`ACT`/`INA`);
- nflverse stat lines;
- ESPN-projected players.

Bye rows are dropped. Position priority is ESPN's default position, then the weekly roster, then stats.

A few rows (38 in 2019–2025) carry a defensive roster position (DB/DL/LB). These are players who
entered through a skill-position stat line but whose roster position is defensive. None is
ESPN-projected; per-position analyses filter `position %in% PWA_POSITIONS`. The frozen WR frame
contains the same rows.

## ESPN sources

| Position | Week-of projection and actual | Components |
|---|---|---|
| WR | `espn_weekly`, the frozen WR source, restricted to ESPN default position WR | Its six columns (receptions, targets, receiving yards and TDs, rushing attempts and yards). Passing components and rushing TDs are re-parsed from the same raw files. |
| QB/RB/TE | `val_espn_hist`, the valuation track's week-of history | All twelve `espn_proj_*` columns, re-parsed from the cached raw files (`pwa_espn_components()`) |

A player inside the WR file whose ESPN default position is RB/TE/QB is taken from his own
position's file, never twice. The crosswalk is the union of `espn_crosswalk` and `val_crosswalk`;
the WR one wins on shared ids, so WR rows map exactly as before.

All historical ESPN week-of values are **late horizon**: published after inactives
(`espn_horizon = "late"`).

## Columns added to the base frame

| Column | Meaning | Valid from |
|---|---|---|
| `kickoff_utc`, `roof` | From the schedule | Pregame |
| `base`, `base_a`, `base_b`, `base_train_rows` | Rolling-origin per-position OLS calibration of ESPN's projection, fit on active rows of strictly earlier weeks (P0's `pd_rolling_base()`); identity until 200 training rows | Pregame (late horizon, because it uses ESPN's week-of value) |
| `designation`, `practice`, `body`, `listed`, `prev_designation`, `weeks_listed_streak`, `report_state`, `group` | M4's availability features (`m4_add_features()`), from reports timestamped before kickoff. 2025 has no timestamps, so `report_state = "source_missing"`. | Pregame (`injury_timed`) |
| `role_rank`, `role` | Rank within team × position by ESPN's projection. Roles: QB1, RB1–2, WR1–3, TE1, else `<pos>_depth`. | Pregame, late horizon |
| `prev_week`, `prev_offense_snaps`, `role_rank_prev`, `role_prev` | Offensive snaps in the team's previous game of the season, and the role ranked by them. A missing snap record is 0 snaps; the first game is NA. | After the previous game: every horizon |
| `asof_spread`, `asof_total`, `asof_implied_total`, `asof_expected_qb_id`, `asof_expected_starter`, `asof_cutoff_utc`, `asof_committed_utc` | Lines and expected QB from the nflverse/nfldata git history, as committed before kickoff − 2 h. The team's view of the designated home team (the last token of the game id), including neutral sites. | Kickoff − 2 h, 2021–2025 (`asof_available`) |
| `espn_horizon`, `schedule_lines`, `injury_timed`, `asof_available` | Point-in-time flags. `schedule_lines = "closing"`: the base frame's `team_spread`/`total_line` are nflverse closing lines. | — |

**Realised columns, never features:**
- `actual` and `y`: league (ESPN PPR) points, 0 without a stat line.
- `active`: at least one offensive snap; a stat line counts where no snap record exists.
- `offense_snaps`, `snap_share`, `has_stat_line`, `espn_actual`, `actual_*` stats.
- `roster_status`: game-day status, known about 90 minutes before kickoff.

**Neutral-site as-of lines.** E11's caches (`data/raw/nfldata_asof/asof_kickoff_minus_2h_<season>.parquet`)
hold home games only (X-007). Neutral-site games are computed once from the local nfldata clone by
the same method. They are cached under new names, `..._neutral_<season>.parquet`, and E11's files
are never rewritten. A table with any missing line is not cached. Nothing derived from nfldata is
committed: the repository has no license file.

## Checks

Each one is a pipeline target that aborts on failure. Both criteria were fixed before the first build.

| Target | Criterion | Result (2026-10-13) |
|---|---|---|
| `pwa_scoring` | Per position: the share of rows with an ESPN actual whose league points equal ESPN's to within 0.011 must be ≥ 99.9%. Rows without a stat line count as 0 points. | QB 99.963% (10,780 rows), RB 99.980% (19,545), WR 99.976% (28,876), TE 99.969% (16,229). On stat-line rows only: 99.912–99.964%. |
| `pwa_wr_check` | Every frozen WR-frame row (2019–2025, with a game) is present. Every shared column is identical, except where ESPN's default position is QB/RB/TE: the WR frame saw only ESPN's WR file, so there the ESPN columns, position and name come from the other position's file. No new WR rows. | Pass: 34,685 rows; 0 missing; 0 core differences; 118 reassigned rows; 0 unexplained; 0 new WR rows |
| `pwa_components_check` | Re-parsed WR components equal `espn_weekly`'s | 45,857 rows, 0 differ |
| `pwa_leakage` | For 6 random cutoff weeks g: every outcome of weeks ≥ g is rewritten (points, active, snaps, ESPN actuals). `base`, `prev_offense_snaps`, `role_rank` and `role_rank_prev` of week-g rows must not change. As-of commits must precede kickoff − 2 h. | No leaks |
| `pwa_injury_leakage` | M4's injury corruption test (`check_injury_leakage()`) on all four positions, 6 weeks from 2019–2024 | No leaks |

**Consistency with P0 (descriptive, development seasons only).** On 2019–2023, F4's base equals
P0's `pd_based` on all 31,225 projected rows (maximum difference 0).

## K and D/ST

These rows are built separately: see the K/DST section of the master-plan execution tracker (F4, part 2).
