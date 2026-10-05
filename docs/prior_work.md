# Prior work reviewed

We reviewed these projects for methodology, not to copy their code. Everything
in this repository is our own implementation.

## jimwill830/princeton-orfe-thesis-2026

An MIT-licensed public repo with three R scripts: an ESPN-ensemble model, a
played-only variant, and a figures script. It contains no data files. We
reviewed it on 2026-10-05.

| Question | Finding |
|---|---|
| How ESPN projections are obtained | `kona_player_info` from ESPN's `lm-api-reads` fantasy API, for a **specific private league**, authenticated with session cookies and filtered to projected weekly stats (`statSourceId = 1`, `statSplitTypeId = 1`). It uses the league's `appliedTotal`, so the scoring is that league's undocumented settings. It does not recompute points from the projected stat lines. |
| Pregame? | **Not verified.** All 2025 weeks are fetched in one loop, months after the season. There are no snapshots, timestamps or archive comparisons. The 500-player pull is sorted by ownership *at query time*, so each week's player population is chosen with hindsight. |
| Seasons | nflverse 2022–2025. ESPN projections for 2025 only, for RB/WR/TE. |
| ID mapping | `espn_id` → `gsis_id` via `nflreadr::load_players()`. Unmatched players are dropped silently and no match rate is reported. |
| Leakage controls | Rolling player features are correctly lagged. However, current-week game context (implied total, spread, temperature, rest) is taken from the player's **stat row**. A player who did not play has no stat row, so those features become NA and then 0. `implied_team_total == 0` therefore identifies exactly the rows where actual points are 0, which is a severe target leak. It probably explains why Vegas features and temperature rank as the most important features. |
| Vegas lines | `spread_line` and `total_line` from `nflreadr::load_schedules()` (approximately closing). Implied totals are computed correctly. |
| Features | About 80 features: lagged and EWMA points, usage, red-zone usage, snaps, opponent allowances, Vegas, weather, injuries, age. They are pruned by gain. |
| Backtest | Expanding window with weekly refits. However, hyperparameters, feature pruning, post-processing thresholds and ensemble weights were tuned on the same 2023–24 seasons used for the backtest, and model changes were judged against the 2025 holdout. No sample sizes are reported. Its injury features are all 0 in 2025 because injury data was loaded only through 2024. |
| Scoring | The "actual" points omit fumbles lost, 2-pt conversions and return TDs, while ESPN's numbers use a private league's scoring. The two sides are not scored identically. |
| Reported result | WR MAE 2.97 vs ESPN 3.15 (2025). Given the leak and the tuning on the test seasons, we do **not** treat this as evidence that ESPN is beatable by that margin. |

**What we adopted:** the overall idea of an expanding-window weekly refit, and
paired bootstraps clustered by week.

**What we do differently:**
- Game context comes from the schedule, never from stat rows.
- Our evaluation population is defined pregame and includes non-players with an actual of 0.
- Both sides are scored identically under ESPN default PPR, and our scoring is validated against ESPN's own actuals.
- Model selection and tuning use the validation season only.
- We use no credentials or private leagues.
- ID mapping is audited and match rates are reported.

## Other projects

The ESPN API probe and the review of ffanalytics, ffscrapr, DynastyProcess
and nflverse projection data are summarised in
[espn_projections.md](espn_projections.md).
