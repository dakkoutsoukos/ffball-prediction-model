# FFball Prediction Model

A reproducible R research pipeline for **weekly fantasy football projections**.
The long-term goal is projections and decision tools that beat ESPN's.
Milestone 1 builds the foundation for one question:

> Can we predict weekly **WR** full-PPR fantasy points more accurately than ESPN's pregame projections?

## Status: Milestone 1

| Component | State |
|---|---|
| Reproducible project (renv, targets, tests) | ✅ |
| WR player-week dataset, 2019–2025 (nflverse) | ✅ about 3,200 rows per season, keyed on GSIS id |
| ESPN-PPR scoring, configurable and validated | ✅ matches nflverse PPR on 99.96% of 40,330 offensive player-weeks. All 16 differences are fumble-recovery TDs, which ESPN scores. |
| Point-in-time features + automated leakage checks | ✅ 0 leaking features on the real dataset |
| Chronological evaluation (static + weekly rolling-origin) | ✅ |
| Simple baselines: naive, OLS, ridge | ✅ |
| **ESPN historical projections** | ⚠️ **Available, but not fetched pending a terms-of-use decision.** See [docs/espn_projections.md](docs/espn_projections.md). |
| ESPN benchmark measured | ⏸ blocked by the item above. The interface is built and tested, and enabling it is one config flag. |

### Results so far: ESPN-free, game-day-active WR population

Pre-registered in [research/experiment_log.md](research/experiment_log.md).
Selection used 2024 only. 2025 was held out until the end.

| 2025 test, weekly rolling refit | MAE | RMSE | corr |
|---|---|---|---|
| `ols_usage` (selected on 2024) | **3.957** | **5.560** | 0.637 |
| `naive_roll8` (trailing 8-game mean) | 4.050 | 5.791 | 0.616 |

ΔMAE = −0.092 (95% week-clustered bootstrap CI −0.152 to −0.040). **This is a
comparison with a naive baseline, not with ESPN. Nothing here shows that ESPN can be beaten.**

## Architecture

The pipeline is a [`targets`](https://docs.ropensci.org/targets/) DAG (`_targets.R`); no script needs to be run by hand in a set order.

```
raw sources (nflverse via nflreadr; ESPN API, gated)       data/raw/  immutable + JSON provenance sidecars
  └─ validation + cleaning (R/data/clean_nflverse.R)       unique keys, ranges, team codes, ID maps
      └─ ESPN↔GSIS crosswalk (R/data/espn.R)               ID-only, ambiguous ⇒ unmatched, audited
          └─ player-week universe (R/data/player_week.R)   pregame-defined populations
              └─ point-in-time features (R/features/)      as-of join, strictly prior games
                  ├─ leakage check (corrupt future ⇒ features must not move)
                  └─ models (R/models/) ─ dev path: tune + select on 2024 only
                                          └─ test path: 2025, opened after selection
                                              └─ evaluation (R/evaluation/) ─ report (reports/)
```

Intermediate tables are stored as Parquet in the targets store. Play-by-play is
aggregated with **DuckDB** directly from parquet files. The final dataset is
exported to `data/processed/player_week_wr.parquet` and a DuckDB file
(`ffball.duckdb`, table `player_week_wr`) for ad-hoc SQL.

```
R/data/        ingestion (nflverse, ESPN), cleaning, scoring, player-week assembly
R/features/    point-in-time feature engine + leakage check
R/models/      model specs (tidymodels recipes/parsnip, glmnet) and candidate set
R/evaluation/  metrics, chronological backtests, bootstrap, model selection
R/utils/       config and validation helpers
config/        project.yml (seasons, splits, flags) and scoring/*.yml
tests/         testthat suite (scoring, lagging, rolling windows, joins, ESPN parsing, metrics)
docs/          provenance, point-in-time rules, schema, scoring, ESPN investigation, prior work
research/      experiment log (pre-registration + results)
reports/       Quarto report rendered by the pipeline
scripts/       one-off entry points (ESPN live snapshot, disabled by default)
data/          raw / interim / processed / snapshots (all git-ignored)
```

Adding RB/TE/QB is designed to be a configuration change: `positions` in
`config/project.yml`, `ESPN_SLOT_IDS` (already mapped), and a position-specific
feature set. The universe, scoring, features and evaluation are all position-agnostic.

## Setup

Requirements: **R ≥ 4.5**, Git, internet access. RStudio is optional; open
`FFballPredictionModel.Rproj`. Quarto is needed only for the report, and the copy
bundled with RStudio is found automatically. No Rtools is needed, because packages
install as binaries.

```r
# In R, from the project root (renv bootstraps itself via .Rprofile):
renv::restore()          # installs the exact package versions in renv.lock
```

The lockfile pins a dated Posit Package Manager snapshot (`2026-10-01`), so
Windows and macOS restores use binaries. If `Rscript` is not on your PATH on
Windows, call it by full path, for example
`"C:/Program Files/R/R-4.5.1/bin/Rscript.exe"`.

## Run

```r
targets::tar_make()                      # downloads ~160 MB on first run, then builds everything
targets::tar_visnetwork()                # view the DAG
targets::tar_read(evaluation_test)       # metrics tables
targets::tar_read(dataset_audit)         # coverage, exclusions, missingness, ID matching
```

The report is at `reports/milestone1_report.html`. Tests:

```r
testthat::test_dir("tests/testthat")
```

Raw downloads are cached in `data/raw/` and never silently refreshed. To pick up
nflverse stat corrections, delete the relevant files (or call
`fetch_nflverse(..., refresh = TRUE)`) and rerun.

## Data sources

The main source is [nflverse](https://github.com/nflverse/nflverse-data) (CC-BY 4.0):
- weekly player stats
- play-by-play
- schedules and betting lines
- weekly rosters
- snap counts (PFR)
- injury reports
- ffopportunity expected points
- player ID maps

ESPN's public fantasy API serves weekly projections and actuals for 2018 onward
(currently disabled). Each source's fields, history, as-of semantics, license
and limitations are in [docs/data_provenance.md](docs/data_provenance.md).
**No data is committed to this repository.**

## Evaluation philosophy

- **No future information.** Features use only games strictly before the target
  week, and an automated corruption test proves it on the real data
  ([docs/point_in_time_rules.md](docs/point_in_time_rules.md)).
- **Chronological splits.**
  - Train 2020–2023, validate 2024, test 2025.
  - The primary protocol refits every week on all prior weeks.
  - The test season never influences features, preprocessing, hyperparameters or model choice. The targets DAG separates the development and test paths.
- **Pregame-defined populations.** Rows are never selected because a player
  recorded stats. Players who were expected to play and scored 0 count as 0.
- **Identical observations.** All models are scored on the same player-weeks, and exclusions are counted.
- **Uncertainty.** Paired bootstrap of MAE differences, resampling whole weeks.
- **MAE alone is not enough.** MAE favours predicting the median of a right-skewed
  outcome. A claim of beating a benchmark also requires RMSE not to get worse.
- **Pre-registration.** Candidate models and the selection rule are written down
  before results are seen ([research/experiment_log.md](research/experiment_log.md)).

## Current limitations

1. **The ESPN benchmark has not been measured.** Fetching ESPN data is a terms-of-use decision for the project owner.
2. Betting lines are approximately **closing** lines, valid only for kickoff-time predictions.
3. Injury designations have no capture timestamps.
4. One test season gives 18 weekly clusters. Whether gains repeat must be shown on 2026 as a fresh holdout.
5. There are no route or participation features. That data is published only after each season.
6. The ID history starts in 2019, so `career_games` undercounts veterans.
7. The 2025 test season has been opened once for the ESPN-free experiment. See the experiment log.

## Roadmap

1. **Next:** decide on ESPN. Then measure ESPN's held-out accuracy and run the pre-registered ESPN-augmented models.
2. Start a timestamped live-projection archive for 2026 (`scripts/snapshot_espn.R`) to get a pristine point-in-time benchmark.
3. Distributional outputs: floor, median, ceiling, boom and bust probabilities via quantile models.
4. Extend to RB/TE/QB.
5. Rest-of-season valuation, then trade calculator and market comparison, then win-probability start/sit.

## Prior work

We reviewed `jimwill830/princeton-orfe-thesis-2026`, ffanalytics, ffscrapr,
DynastyProcess and nflverse; see [docs/prior_work.md](docs/prior_work.md).
No code was copied.

## License

The code is MIT licensed ([LICENSE.md](LICENSE.md)). Third-party data is not included and remains under its providers' terms.
