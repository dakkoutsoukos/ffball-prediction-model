# FFball Prediction Model

A reproducible R research pipeline for **weekly fantasy football projections**.
The long-term goal is projections and decision tools that beat ESPN's.
The current question:

> Do our football features add **repeatable, prospective** information about weekly
> **WR** full-PPR scoring beyond a **calibrated** ESPN projection?

## Valuation V2 (league-specific trade analyzer)

V2 answers what acquiring or giving away a player does to **your actual team**:
- **Decision variable:** expected optimized ROS lineup points after a trade minus before, for both teams.
- **Rosters:** each team's actual roster, re-optimized week by week over Monte Carlo availability.
- **Replacement:** the league's **actual free agents**.
- **Uneven trades:** forced drops and waiver adds are part of the trade.
- **Context:** generic V1 value is always reported alongside.

Positional need, blocked bench players and consolidation emerge from the lineups; nothing is hand-set.

```bash
Rscript scripts/league_refresh.R                       # private league: cookies in git-ignored config/local.yml
Rscript scripts/valuation_run.R --league --capture     # V1 values in this league's format
Rscript scripts/trade_analyzer.R snapshot              # rankings, needs, real waiver levels, value matrix, win-win search
Rscript scripts/trade_analyzer.R analyze --a "Team A" --give-a "P1;P2" --b "Team B" --give-b "P3"
Rscript scripts/trade_analyzer.R fair --b "Team B" --win-win    |  target --player "X"  |  sell --player "X"
```

Privacy:
- League data, the league id and the cookies never enter Git.
- Committed manifests hold hashes under a random league alias.
- `reports/valuation_v2_report.html` is rendered locally.

Methodology: [docs/valuation_v2_methodology.md](docs/valuation_v2_methodology.md).

## Valuation V1 (separate track: rest-of-season player value)

Projection research is paused at M4 while the 2026 WR record accumulates. Valuation is
a separate namespace that never touches the frozen lineages:
- code in `R/valuation/`;
- settings in `config/valuation.yml`;
- fixed parameters in `models/valuation/`;
- decisions in `research/valuation_log.md`.

> A player's value is the expected contribution that owning him adds to a constrained
> fantasy roster, relative to the alternatives freely available at his position.

| Layer | V1 |
|---|---|
| Projections (QB/RB/WR/TE) | ESPN for QB/RB/TE. For WRs, the current week comes from the frozen `m4_two_stage_v1`, read from the archived official run. All sources sit behind a provider interface. |
| ROS | ESPN's posted future weeks (unvalidated, VE0) through a fixed historical horizon model (VE1: `L_avg4` level, quadratic, fit on 2019–2025), with byes and posted absences |
| League | ESPN standard PPR: 10 teams, 1 QB / 2 RB / 2 WR / 1 TE / 1 FLEX, bench 7, playoffs weeks 15–17. All configurable, superflex included. |
| Replacement | Exact weekly starter allocation (matroid). FLEX-aware exchange baselines. Rostered pool from starter shares (VE3). |
| Value | **ROS VOR** = Σ_t max(0, E − replacement), plus VAS and generic roster utility. The 0–100 display scale is monotone in VOR, with its curvature fitted from roster utility. |
| Packages | Roster-aware trade evaluation with waiver adds and forced drops (A + replacement vs B + C) |
| Validation | VE1 ROS backtest; projected vs realized VOR by position (2019–2025); sensitivity leagues; toy-league tests |

Run after a weekly prospective run (clean tree):

```bash
Rscript scripts/valuation_run.R --capture         # one ESPN request; values every QB/RB/WR/TE; archives the run
git add archive/valuation_*.csv && git commit -m "Valuation run 2026 W<week>"
```

The report is `reports/valuation_v1_report.html`, rendered by `tar_make()` from the latest archived
run. Like every report here, it contains ESPN-derived values and stays out of Git.
Methodology: [docs/valuation_methodology.md](docs/valuation_methodology.md).

## Status: Milestone 4 (availability intelligence and opportunity modeling)

| Item | State |
|---|---|
| Prospective record (2026 from Week 5) | ✅ intact. 6 Week-5 runs hash-verified and pushed; all five lineages run since 06:29Z. 0 completed weeks. |
| Frozen fingerprints M1, M2, M3, M3b, M4 | ✅ identical |
| Injury / practice features | ✅ pregame-valid final reports 2017–2024 with designation, final practice status, broad body group, listed-only rows, lagged trajectory and explicit missing states. Leakage-tested with planted leaks. |
| New lineage **M4** | ✅ `m4_two_stage_v1` (primary) and `m4_practice_rule_v1`, frozen after pre-registered checks (log E12–E14) |
| `reports/milestone4_report.html` | rendered by the pipeline (sections A–J) |

**What Questionable means.**
- Historical ESPN projections are post-inactive. Inside them, 93–98% of Questionable
  WRs play, earning about 9% fewer targets and fewer points per target. The M3b effect
  is therefore workload and efficiency.
- Of *all* Questionable WRs, 24–51% are inactive. Our pre-inactive snapshots face that
  as well, so the prospective shortfall should be larger.

**Pre-registered checks** (ΔMAE, all ESPN-projected WRs; parameters fixed from
2020–2023 and committed before the checks):

| | development 2020–23 | **2019 (fresh)** | 2024 (contaminated) |
|---|---|---|---|
| M3b `Questionable × 0.91` vs calibrated ESPN | −0.014 [−0.019, −0.009] | **−0.0075 [−0.014, −0.001]** | −0.013 [−0.020, −0.005] |
| **M4 `m4_two_stage_v1`** vs calibrated ESPN | −0.027 [−0.038, −0.018] | **−0.019 [−0.035, −0.001]** | −0.022 [−0.040, −0.006] |
| M4 vs M3b | −0.013 [−0.020, −0.008] | −0.011 [−0.022, +0.001] | −0.009 [−0.020, 0.000] |

- M3b replicated in a season never used before.
- M4 beats calibrated ESPN with intervals below 0 in every block, and with better RMSE.
- Against M3b, M4 is consistently better but not securely: the intervals touch 0, and its 2024 RMSE is slightly worse.
- The 2026 record decides (H-M4, at least 8 weeks).

**Negative findings:**
- Our independent target model is worse than ESPN's projected targets.
- Availability through targets alone loses to M3b, because efficiency matters too.
- The target-disagreement blend helps RMSE, not MAE.
- Body part adds nothing.
- ESPN already redistributes targets for absent teammates.

## Status: Milestone 3 (new pregame information; narrow pre-registered hypotheses)

| Item | State |
|---|---|
| M1/M2 prospective record (2026 from Week 5) | ✅ intact. Runs hash-verified and pushed before kickoff. |
| Weekly operations | ✅ `scripts/status.R` dashboard, safer `scripts/weekly_run.R` (all lineages by default), verified backups via `scripts/backup_archives.R` |
| New-source feasibility ([docs/source_feasibility.csv](docs/source_feasibility.csv)) | ✅ The 2017–2024 injury reports turned out to be **pregame-timestamped**. Depth charts 2025+ are captured. |
| Rule challengers M3 (role change, return from absence) and M3b (Questionable designation) | ✅ frozen and pre-registered (log E6, E9). Prospective from Week 5. |
| `reports/milestone3_report.html` | rendered by the pipeline |

**One-time historical checks** of the frozen rules (vs calibrated ESPN; not confirmatory):

| challenger | season(s) | ΔMAE all WRs [95% CI] | top 36 | RMSE |
|---|---|---|---|---|
| Questionable × 0.91 (`m3_questionable_adjust_v1`) | 2024 | **−0.013 [−0.020, −0.006]** | −0.026 (CI < 0) | better |
| role + return (`m3_combined_v1`) | 2024–25 | −0.005 [−0.009, −0.002] | −0.010 (CI < 0) | better |
| role change only (`m3_role_adjust_v1`) | 2024–25 | −0.002 [−0.005, +0.001] | −0.009 (CI < 0) | better |

These are the first gains over calibrated ESPN that held outside the seasons used
to derive them. They are **small**: about 0.1–0.3% of MAE overall, and about 5% on
the Questionable WRs the rule touches.

**2026 prospective: no completed weeks yet. "Not enough prospective evidence" is the
current verdict.**

Other outcomes:
- **Rejected:** ESPN under-reacting to vacated teammate targets (E9).
- **Inconclusive, not frozen:** an expected-QB change, from the timestamped nflverse
  schedule git history, which also provides pregame betting lines for 2021–2025 (E11).

## Status: Milestone 2

| Component | State |
|---|---|
| Frozen, fingerprinted M1 and M2 model lineages ([docs/models.md](docs/models.md)) | ✅ M1 and M2 predictions re-verified identical |
| M2 feature engine, 9 families ([docs/features.md](docs/features.md)) | ✅ 0 leaking features under all-table corruption |
| Benchmark hierarchy: raw ESPN → calibrated ESPN → ESPN-free → ESPN + ours | ✅ |
| Pre-registered development protocol (2020–23), one-time holdout (2024–25) | ✅ (experiment log E3–E5) |
| 2026 prospective archive: ESPN snapshots + predictions, hash manifests committed before kickoff ([docs/prospective_protocol.md](docs/prospective_protocol.md)) | ✅ from Week 5 |
| Report | `reports/milestone2_report.html` (rendered by the pipeline) |

### Milestone 2 results (WR player-weeks with an ESPN projection > 0, weekly rolling refits)

| Model | Dev 2020–23 MAE | Holdout 2024–25 MAE | Holdout RMSE | Holdout ΔMAE vs calibrated ESPN [95% CI] |
|---|---|---|---|---|
| Raw ESPN | 4.469 | 4.190 | 5.835 | +0.046 [+0.033, +0.060] |
| **Calibrated ESPN (`m2_espn_cal`)** | 4.449 | **4.144** | 5.816 | — |
| ESPN + our features (`m2_espn_aug`, frozen) | **4.437** | 4.154 | 5.816 | **+0.010 [−0.006, +0.027]** |
| M1 ESPN + features (`m1_espn_plus`, frozen) | — | 4.144 | 5.810 | −0.001 [−0.016, +0.014] |
| ESPN-free M2 (`m2_no_espn`) | 4.59 | 4.333 | 5.988 | +0.188 |
| ESPN-free M1 (`m1_no_espn`) | 4.61* | 4.340 | 6.016 | — |

\*M1's ESPN-free feature set refit under the M2 protocol.

**Bottom line: no repeatable edge over calibrated ESPN.**
- The augmentation model's small development gain (−0.012, CI spanning 0, better
  in 4 of 4 seasons) **reversed on the holdout**. It was slightly worse in both
  seasons and significantly worse among the top-60 and top-36 WRs.
- **Calibrating ESPN** is the one robust improvement over raw ESPN. It carries no player information.
- The ESPN-free model improved modestly over M1 (RMSE 6.016 → 5.988), but
  remains about 0.19 MAE behind ESPN.
- **2026 prospective:**
  - Week 5 is archived for both frozen lineages.
  - No archived week has been played yet.
  - The pre-registered primary test runs at the end of the 2026 season and needs at least 10 completed weeks.

<details><summary>Milestone 1 results (archived)</summary>

### Milestone 1 results (pre-registered; 2024 used for selection, 2025 opened once)

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

</details>

## Weekly prospective runbook (2026)

On a clean, committed tree, before each slate's kickoff (Thu ~17:00 ET, Sun
~08:00/11:30 ET, Mon ~17:00 ET):

```bash
Rscript scripts/weekly_run.R                        # next week, ALL frozen lineages: snapshot ESPN, refresh live data, archive
Rscript scripts/status.R                            # kickoffs, coverage, injury-report readiness, hashes, push state
git add archive/*.csv && git commit -m "Prospective run 2026 W<week>" && git push   # BEFORE kickoff
```

The latest run before each game's kickoff is the official prediction for that game.
M3b and M4 need a run **after** a team's final injury report, which comes Friday
for Sunday games, so make a Saturday or early-Sunday run.

`--late-pregame` archives a separate, optional post-inactive horizon. It is never
mixed with the standard record (docs/prospective_protocol.md).
After the season, `score_prospective()` scores only archived, hash-verified runs
(R/live/prospective_eval.R). Back up `data/archive/` and `data/snapshots/`
privately: they hold ESPN-derived data and are not in Git.

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
R/data/        ingestion (nflverse, ESPN), cleaning, scoring, play-by-play aggregates, player-week assembly
R/features/    point-in-time feature engines (M1 frozen; M2 extends it) + leakage checks
R/models/      model specs (tidymodels, glmnet, xgboost), frozen-lineage registry, M2 candidates
R/evaluation/  metrics, chronological backtests, bootstraps, M2 protocol and studies
R/live/        live 2026 data layer, prospective runs, archive verification and scoring
R/valuation/   rest-of-season valuation (separate track): providers, ROS, allocation, VOR, simulation
R/utils/       config and validation helpers
models/        frozen registries (m1.yml, m2.yml) and prediction fingerprints
archive/       committed append-only SHA-256 manifests (prospective predictions, ESPN snapshots)
config/        project.yml (seasons, protocols, flags) and scoring/*.yml
tests/         testthat suite (scoring, leakage, features, models, registry, live, prospective scoring)
docs/          models, features, prospective protocol, provenance, point-in-time rules, schema, ESPN, prior work
research/      experiment log (pre-registrations E3 + results E1-E5)
reports/       Quarto reports (Milestones 1 and 2) rendered by the pipeline
scripts/       weekly prospective run, ESPN snapshot (ESPN opt-in required)
data/          raw / live / snapshots / archive / processed (all git-ignored)
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
targets::tar_make()                      # downloads ~200 MB on first run, then builds everything
targets::tar_visnetwork()                # view the DAG
targets::tar_read(m2_holdout_comparisons) # Milestone 2 holdout comparisons
targets::tar_read(m2_fingerprint_check)  # frozen-model integrity (also m1_fingerprint_check)
targets::tar_read(dataset_audit)         # coverage, exclusions, missingness, ID matching
```

The reports are at `reports/milestone1_report.html` and
`reports/milestone2_report.html`. Tests:

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
(opt-in only). Each source's fields, history, as-of semantics, license
and limitations are in [docs/data_provenance.md](docs/data_provenance.md).
**No data is committed to this repository.**

## Evaluation philosophy

- **No future information.** Features use only games strictly before the target
  week, and an automated corruption test proves it on the real data
  ([docs/point_in_time_rules.md](docs/point_in_time_rules.md)).
- **Chronological protocol** ([docs/models.md](docs/models.md)).
  - All M2 decisions were made on development folds 2020–2023.
  - The 2024–2025 holdout was run once, after freezing.
  - **2026 is prospective only.** Every protocol refits weekly on all prior weeks.
  - Frozen models are versioned lineages with prediction fingerprints.
- **Compare against calibrated ESPN, not just raw ESPN.** A simple recalibration
  of ESPN's level is a free improvement and must not be mistaken for player-level information.
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
3. **Only a small, injury-specific historical edge over calibrated ESPN** (M3b/M4,
   about 0.3–0.6% of MAE, confined to listed WRs). It has replicated in the fresh
   2019 check. The general feature models (M2) showed no edge. 2019 has now been
   used, so only 2026 is clean.
4. **The prospective record depends on running the weekly script.** It has 0
   completed weeks so far. If runs are missed, those weeks simply have no
   prospective record.
5. Closing betting lines are excluded from M2; only the frozen `m1_espn_plus` uses them.
   Injury reports are used only through their own pregame timestamps (M3b, M4). 2025
   has none, so it cannot be checked. Historical ESPN values are post-inactive, so the
   availability component cannot be validated historically.
6. There are no route or participation features. That data is published only after
   each season. QB context is lagged one game by design.
7. 20 ESPN-projected WR rows (0.13%) are excluded because of an ambiguous ID (two "DJ Turner"s).
8. The newly added 2018 ESPN season has no archived captures to verify its
   pregame values against. 2019 does, and it matched exactly.

## Roadmap

1. **Keep the 2026 prospective record running** (weekly runbook above) and score it
   once at season end with the pre-registered test.
2. **M5 (recommended):** prospective availability.
   - Score H-M4 and H-D on the 2026 record.
   - Quantify, from our own archived snapshots and captures, how much of the
     Questionable shortfall is inactivity at our forecast time.
   - Consider running the optional `late_pregame` horizon.
   - Do not add complexity unless 2026 supports M4 over M3b.
3. Distributional outputs: floor, median, ceiling, boom and bust probabilities via quantile models.
4. Extend to RB/TE/QB.
5. Rest-of-season valuation: **V1 done** (see above). V2 adds our own QB/RB/TE providers, level
   uncertainty, actual league rosters for team-specific trades, and the prospective VE-P1 check.
   Then win-probability start/sit.

## Prior work

We reviewed `jimwill830/princeton-orfe-thesis-2026`, ffanalytics, ffscrapr,
DynastyProcess and nflverse; see [docs/prior_work.md](docs/prior_work.md).
No code was copied.

## License

The code is MIT licensed ([LICENSE.md](LICENSE.md)). Third-party data is not included and remains under its providers' terms.
