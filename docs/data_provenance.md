# Data provenance

Every external input is downloaded by code in `R/data/ingest_*.R` into
`data/raw/`. Each file gets a JSON sidecar recording:
- the provider and loader version;
- the nflverse build timestamp;
- the retrieval time in UTC;
- the row and column counts.

The `raw_manifest` target collects all of them. Raw files are immutable: an
existing file is reused unless deliberately refreshed. No data is committed to
Git, and `targets::tar_make()` re-downloads everything from scratch.

Current raw inputs were retrieved on **2026-10-05**:
- nflverse seasons **2017–2025**, about 200 MB. 2017 is feature warm-up for M2,
  and M1 still uses only 2019+.
- ESPN seasons **2018–2025**.

The in-progress **2026** season lives in a separate live layer (below).

## nflverse (primary source)

Accessed via `nflreadr` 1.5.1 from
`github.com/nflverse/nflverse-data/releases`. The data is licensed **CC-BY 4.0**
("data via nflverse"). Some underlying sources carry extra terms, noted per
dataset below. nflverse files are **re-derived and overwritten** over time, for
example through stat corrections and full rebuilds. The sidecars record which
build we used.

| Dataset | Loader / URL | Fields used | History | As-of semantics | Limitations |
|---|---|---|---|---|---|
| Weekly player stats | `load_player_stats(s, summary_level = "week")` (release `stats_player`) | IDs, team, opponent, targets, receptions, yards, TDs, air yards, attempts, fumbles lost, 2-pt, return TDs, `fantasy_points_ppr` | 1999– | Post-game outcomes. Used only as targets or lagged history. | Only players who recorded a stat appear. Team-level placeholder rows have no player id (dropped, after asserting 0 points). In 2019, team codes differ from schedules (`LV` vs `OAK`), so they are normalised. |
| Play-by-play | Release parquet `pbp/play_by_play_{s}.parquet` (direct download) | `receiver_player_id`, `yardline_100`, `air_yards`, `pass_attempt`, `sack`, `two_point_attempt` | 1999– | Post-game. Used only as lagged red-zone usage. | About 20 MB per season. Aggregated in DuckDB. Targets match box-score targets exactly. |
| Schedules | `load_schedules(s)` (from Lee Sharpe's `nfldata` games file) | Teams, home/away, kickoff, rest, `spread_line`, `total_line` | 1999– | Schedule: known in advance. **Lines are overwritten during the week and hold approximately closing lines for completed games.** Valid only for kickoff-time predictions. | No opening lines or timestamps. A few known data errors (for example, sign-flipped spreads, nfldata issue #34). The pbp dictionary attributes historical lines to Pro-Football-Reference. |
| Weekly rosters | `load_rosters_weekly(s)` | gsis/espn ids, team, position, `status` | 2002– | `status` is effectively **game-day** status (`INA` = inactive), known about 90 minutes before kickoff. **Never used as a feature.** Used only to define the ESPN-free population. | 13 duplicated player-week keys (one gsis id shared by two players), resolved by rule. ESPN id is missing for up to 32% of WR rows in some seasons. |
| Snap counts | `load_snap_counts(s)` (source: **Pro-Football-Reference**) | `offense_pct` | 2013– | Post-game. Lagged only. | Joined via `pfr_id` → `gsis_id` (load_players). 0.15% unmapped. Sports Reference's terms (§5(j)) restrict using *their site's* content to train AI models. We obtain these facts from nflverse, not from SR, but owners of commercial uses should review this. |
| Injuries | `load_injuries(s)` | Final weekly `report_status` | 2009– | Final pregame designation (Fri/Sat). **No capture timestamp** for 2025+. The source broke during 2025 and was backfilled in Aug 2026. | Treated as a separate, flagged feature group. |
| ffopportunity expected points | `load_ff_opportunity(s, "weekly")` | `total_fantasy_points_exp` | 2006– | Post-game (computed from each play). Lagged only. | The xFP models were **trained on 2006–2020**, so lagged xFP in the 2020 training rows is mildly in-sample. Validation and test seasons are unaffected. GPL-3. |
| Player master | `load_players()` | gsis/espn/pfr ids, names | current snapshot | Not point-in-time (identity only). | Used for ID maps. |
| DynastyProcess ID map | `load_ff_playerids()` | espn/gsis ids, names | current snapshot | Identity only. | Contains a few duplicated gsis ids, which the crosswalk handles. GPL-3. |

Considered and **not used** in Milestone 1:
- **Participation and route data:** FTN data is published only after each season, so it is not available in real time.
- **Next Gen Stats:** Week 0 is a season-to-date total that updates, which is a leakage hazard, and weekly rows require at least 5 targets.
- **Depth charts:** the format and source changed in 2025, and pre-2025 snapshot times are unknown.
- **FantasyPros ECR:** these are rankings, not points.

## ESPN

See [espn_projections.md](espn_projections.md).

| Provider | Endpoint | Fields | History | As-of | Status |
|---|---|---|---|---|---|
| ESPN fantasy API (public, no auth) | `lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{S}/segments/0/leaguedefaults/3?scoringPeriodId={W}&view=kona_player_info` | Weekly projected and actual PPR `appliedTotal`, projected receptions/targets/yards/TDs | 2018– (we use 2020–2025) | Final pregame projection, retrieved retroactively on 2026-10-05. Supported by Wayback captures of real API responses. | Fetched after the owner's opt-in (`config/local.yml`, git-ignored). 107 raw responses are cached in `data/raw/espn/`. The committed default is off. **Never commit ESPN data.** Disney Terms of Use apply. |
| ESPN live snapshots | same endpoint, current/upcoming week | as above + `captured_at_utc`, live team (mapped from ESPN `proTeamId`), source URL, scoring id, raw-file SHA-256 | from 2026 W5 | **True point-in-time** (capture timestamp) | Write-once files in `data/snapshots/espn/` (git-ignored). Hashes go in the committed `archive/espn_snapshot_manifest.csv`. First capture 2026-10-05 19:40 UTC (W5). |
| ESPN completed 2026 weeks | `leaguedefaults/3` as above | weekly projections and actuals | 2026 W1–W3 so far | Retrieved after **all** of a week's games were final. **Training rows only**, never the prospective benchmark | `fetch_espn_completed_weeks()` |

ESPN request log, all on 2026-10-05:
- 107 requests for 2020–2025;
- 34 for 2018–2019;
- 3 for 2026 W1–W3;
- 1 test request;
- 2 for the live snapshot;
- about 57 exploratory requests before the opt-in.

## Live 2026 layer and archives

| Item | Where | Semantics |
|---|---|---|
| Live nflverse retrievals (stats, schedules, rosters, snaps, injuries, xFP, pbp, player and ID maps) | `data/raw/nflverse_live/<dataset>/season=2026/retrieved_at=<UTC>.parquet` (+ JSON sidecar with SHA-256) | A new immutable file on every retrieval, so the data available at any prediction time can be reconstructed |
| Prospective predictions | `data/archive/predictions/season=S/week=WW/run=<UTC>/predictions.parquet` + `run_meta.json` | Write-once. Contains ESPN projections, so it is git-ignored |
| Prediction manifest | `archive/prediction_manifest.csv` (**committed**) | Append-only SHA-256 hashes of every run, plus commit, snapshot hash and times. It is pushed before kickoff as tamper evidence |
| Snapshot manifest | `archive/espn_snapshot_manifest.csv` (**committed**) | Append-only hashes of every ESPN snapshot |
| M1 historical predictions | `data/archive/m1_backtest/` | Local copy of the frozen M1 rolling predictions behind its fingerprint |

**Back up `data/archive/` and `data/snapshots/` privately** (they are not in Git).
The committed manifests prove what existed and when, but the files themselves
are needed to score the prospective record.

## Milestone 2 play-by-play aggregates

Computed in DuckDB from the nflverse play-by-play files (`R/data/pbp_features.R`)
and used **lagged only**:
- receiver detail per player-game (deep targets with air yards ≥ 20, yards after catch);
- team per game (plays, dropbacks, neutral-situation pass rate, pass EPA per dropback);
- defence per game (dropbacks faced, pass EPA allowed);
- QB per team-game (dropbacks, EPA, starter = dropback leader).

The EPA and win-probability fields come from nflfastR's fixed models, applied
retroactively. Their training years are not documented in the data.

## Derived data

| Artifact | Where | Regenerate with |
|---|---|---|
| Clean tables, features, models | `_targets/` (object store, parquet and rds) | `targets::tar_make()` |
| Analysis dataset | `data/processed/player_week_wr.parquet` | target `player_week_export` |
| DuckDB file for ad-hoc SQL | `data/processed/ffball.duckdb` (table `player_week_wr`) | target `player_week_export` |
| Report | `reports/milestone1_report.html` | target `report` |
