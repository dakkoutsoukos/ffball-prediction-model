# Point-in-time (leakage) rules

This is the most important modelling rule in the project:

> A prediction for a player's Week *N* game may only use information that
> was actually available **before that game kicked off**.

A slightly weaker honest model is preferable to an artificially strong leaked one.
When it is unclear whether a variable leaks, it stays out until shown to be safe.

## Prediction timestamp

Milestone 1 predicts each player-week **at lineup lock, just before the player's
game kicks off**. This matches the benchmark: the ESPN projection we compare
against is ESPN's final pregame projection, which already includes injury news
from the week.

Each input is classified by when it becomes known:

| As-of class | Meaning | Examples | Allowed for Week *N*? |
|---|---|---|---|
| `prior_games` | Outcomes of games played before Week *N* | Trailing targets, snap share, fantasy points | Yes, if strictly earlier games only |
| `schedule` | Fixed in advance | Opponent, home/away, the team's previous game, rest days | Yes |
| `pregame_report` | Published before kickoff | Final injury-report designation (Fri/Sat) | Yes, as an explicitly flagged feature group |
| `closing_line` | Final pregame betting market | `spread_line`, `total_line` from nflverse schedules | Yes for a kickoff-time prediction, but flagged. Not valid for an earlier prediction time such as Tuesday |
| `vendor_pregame` | Third-party pregame projection | ESPN weekly projection | Yes. As-of semantics in [espn_projections.md](espn_projections.md) |
| `postgame` | Known only after kickoff | Same-week stats, snaps, inactive-turned-injured, final scores | **Never** |

## How the code enforces it

1. **One rule for all lagged features.** `R/features/point_in_time.R` builds
   "state after game *g*" summaries, such as trailing means that include game *g*.
   Each target row gets the state from the entity's most recent game with
   `game_index < target game_index` (`asof_join()`, `closest(a > b)`). The strict
   inequality means a target week's own outcome can never enter its features,
   whether or not the player played that week.
2. **Windows count games, not weeks.** A trailing 3-game window for Week 8 after a
   Week 6 bye uses the player's three most recent prior games, never Week 8.
3. **Season-to-date features** only count games from the current season played before
   Week *N*. In Week 1 they are missing, and `season_games = 0`.
4. **Previous-season aggregates** are keyed to the *following* season, because they
   are fully known before it starts.
5. **Game context comes from the schedule, never from the player's stat row.** A
   player who did not play still has a schedule row with the same home/away, line,
   and opponent values. This prevents the
   ["missing context = player didn't play" leak](prior_work.md#jimwill830princeton-orfe-thesis-2026)
   that we found in prior work.
6. **Preprocessing is fitted on training rows only.** Imputation medians,
   missingness indicators and standardisation live inside each model's `fit()`
   (tidymodels recipes), so validation and test rows never shape them.
7. **Evaluation populations are defined with pregame information**, such as
   ESPN projecting the player for more than 0 points. They are never defined as
   "players who recorded a stat", which would select on the outcome.

## Automated checks

- `tests/testthat/test-point-in-time.R` covers trailing windows, strict as-of
  joins, season boundaries, missed games, players with no history, and lagged
  team and opponent context.
- `check_feature_leakage()` picks random cutoff weeks, corrupts **every outcome
  at or after the cutoff** (same-week and future), and recomputes features for the
  cutoff week's rows. Any feature that changes is reported as leaking. It runs:
  - in the test suite on synthetic data, including a test that proves it catches
    a deliberately leaky same-week feature and a full-season-average feature;
  - in the targets pipeline on the **real** dataset (`leakage_check` target). The
    pipeline fails if any feature leaks.
- Backtests assert `max(train game_index) < min(test game_index)`.
- **Milestone 2 generic check** (`check_leakage_generic()`, target `leakage_check_m2`):
  - At each cutoff, every column of **all seven** history tables is corrupted from the cutoff on:
    player games, team volume, defence allowances, receiver detail, team play-by-play,
    defence play-by-play and QB games. Numbers are shifted, ids rewritten and flags flipped.
  - Only `season`, `week` and `game_index` keep rows in place.
  - Static inputs are not corrupted, because they are known in advance: the schedule
    (opponent, home, rest, roof) and player bio (draft slot, birth date).
  - A unit test proves it flags a same-week starting-QB feature.
- **QB context is lagged by design.** The starter is defined as the dropback leader,
  which is known only after a game, so only the *previous* game's starter is used.
- **Prospective runs** add three guards:
  - training rows come only from games with a final score;
  - live inputs are dated, immutable retrievals;
  - a prediction counts only if it was archived, with an ESPN snapshot, before
    that game's kickoff (docs/prospective_protocol.md).

## Known residual risks

- **Closing lines** finalise at kickoff. For a kickoff-time prediction they are
  legitimate. Earlier prediction times would need line snapshots we do not have.
- **Injury reports** have no capture timestamp in nflverse. They are the final
  pregame designations, which is why they are a separate, flagged feature group.
- **Player identity and position.** Positions come from nflverse rosters and
  ESPN. Neither is a weekly point-in-time snapshot. This is low risk for WRs.
- **ESPN's historical projections** were retrieved after the fact. See
  [espn_projections.md](espn_projections.md) for what is and is not verified about
  them being pregame values.
- **Stat corrections.** nflverse data can be revised after a game. A real-time
  system would have seen the uncorrected stats. The effect is tiny and ignored.
- **xFP model vintage.** The `ffopportunity` expected-points models were trained
  on historical seasons. We only use *lagged* xFP. Some training-season plays may
  have informed the xFP model's coefficients, which is negligible and does not
  affect the 2024/2025 evaluation seasons.
