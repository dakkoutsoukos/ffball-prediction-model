# FFball Prediction Model

A reproducible R research pipeline for **weekly fantasy football projections**.
The long-term goal is projections and decision tools that beat ESPN's.
Milestone 1 builds the foundation for one question:

> Can we predict weekly **WR** full-PPR fantasy points more accurately than ESPN's pregame projections?

## Status: Milestone 1

| Component | State |
|---|---|
| Reproducible project (renv, targets, tests) | ✅ |
| WR player-week dataset, 2019–2025 (nflverse + ESPN) | ✅ about 2,450–2,600 ESPN-projected WR player-weeks per season, keyed on GSIS id |
| ESPN-PPR scoring, configurable and validated | ✅ matches **ESPN's own actual totals on 99.96%** of 14,628 WR player-weeks |
| Point-in-time features + automated leakage checks | ✅ 0 leaking features on the real dataset |
| Chronological evaluation (static + weekly rolling-origin) | ✅ |
| Historical ESPN pregame projections, 2020–2025 | ✅ public API, owner opt-in, verified pregame against Wayback captures. See [docs/espn_projections.md](docs/espn_projections.md). |
| ESPN held-out benchmark | ✅ |
| Baselines and ESPN comparison | ✅ pre-registered. See the results below. |

### Results (pre-registered; 2024 used for selection, 2025 opened once)

Population: WR player-weeks with an ESPN pregame projection above 0. Actual = 0 when the player
recorded no stats. Weekly rolling refit.

| Model | 2024 MAE | 2025 MAE | 2025 RMSE | 2025 ΔMAE vs ESPN [95% CI] |
|---|---|---|---|---|
| **ESPN pregame projection** | 4.308 | 4.077 | 5.632 | — |
| `ols_espn_plus`: ESPN + lagged usage (selected) | 4.292 | **4.001** | **5.571** | **−0.076 [−0.100, −0.053]** |
| `espn_recal_l2`: a + b·ESPN (diagnostic, no new info) | 4.280 | 4.032 | 5.595 | −0.045 [−0.059, −0.031] |
| `ols_usage`: our features, no ESPN | 4.494 | 4.190 | 5.778 | +0.113 [+0.050, +0.177] |
| `naive_roll8`: trailing 8-game mean | 4.535 | 4.313 | 6.027 | +0.236 [+0.134, +0.345] |

**Bottom line:**
- **Our standalone models do not beat ESPN.**
- ESPN combined with our lagged usage features met the pre-registered criterion on
  2025, beating ESPN on both MAE and RMSE and winning in 17 of 18 weeks.
- That gain **did not replicate on 2024**, where the difference was −0.016 with a CI spanning 0.
- Most of the 2025 gain is recalibrating ESPN's over-projection: a + b·ESPN alone gets −0.045.
- Rank correlation barely moves (0.691 → 0.697).

A repeatable edge over ESPN has **not** been demonstrated yet. 2026 is the next
untouched holdout. Details: [research/experiment_log.md](research/experiment_log.md)
and the rendered report.

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

**ESPN (opt-in).** ESPN fetching is off by default because of ESPN's terms of
use ([docs/espn_projections.md](docs/espn_projections.md)). To opt in for your
own private research, create the git-ignored file `config/local.yml` containing
`espn: {enabled: true}`, then run `tar_make()`. Without it, the pipeline runs
the ESPN-free experiment on the game-day-active population.

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

1. **ESPN terms of use.** The Disney/ESPN Terms of Use restrict scripted
   extraction and ML benchmarking. ESPN data was fetched only after the owner
   opted in for private research. It is kept out of Git, and the public default is off.
2. **ESPN history was retrieved after the fact.** Wayback captures support final-pregame
   values for 2019, 2023 and 2026, but 2020–2022 and 2024–2025 could not be checked
   directly.
3. **No repeatable edge over ESPN yet.** The 2025 gain did not appear in 2024, and two
   seasons give only 36 weekly clusters. 2026 is the fresh holdout.
4. Betting lines are approximately **closing** lines, valid only for kickoff-time predictions.
5. Injury designations have no capture timestamps.
6. There are no route or participation features. That data is published only after each season.
7. The ID history starts in 2019, so `career_games` undercounts veterans.
8. 20 ESPN-projected WR rows (0.13%) are excluded because of an ambiguous ID (two "DJ Turner"s).
9. The 2025 test season has now been used: once for the ESPN-free experiment, once
   for the ESPN comparison. Future model changes must not be judged on it.

## Roadmap

1. **Next:** freeze the current models and evaluate them on **2026** as an untouched
   holdout, rolling week by week. Archive live ESPN snapshots weekly
   (`scripts/snapshot_espn.R`) so the 2026 benchmark is point-in-time by construction.
2. Distributional outputs: floor, median, ceiling, boom and bust probabilities via quantile models.
3. Extend to RB/TE/QB.
4. Rest-of-season valuation, then trade calculator and market comparison, then win-probability start/sit.

## Prior work

We reviewed `jimwill830/princeton-orfe-thesis-2026`, ffanalytics, ffscrapr,
DynastyProcess and nflverse; see [docs/prior_work.md](docs/prior_work.md).
No code was copied.

## License

The code is MIT licensed ([LICENSE.md](LICENSE.md)). Third-party data is not included and remains under its providers' terms.
