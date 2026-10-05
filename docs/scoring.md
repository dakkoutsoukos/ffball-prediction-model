# Fantasy scoring

Scoring is explicit, tested R code (`R/data/scoring.R`) driven by a YAML file
per format (`config/scoring/<name>.yml`). To add a format, such as half-PPR or
TE premium, add a YAML file and set `scoring_system` in `config/project.yml`.

## ESPN full PPR (`espn_ppr.yml`)

| Stat (nflverse column) | Points |
|---|---|
| Reception | 1 |
| Receiving / rushing yard | 0.1 (fractional; ESPN does not floor to 10-yard blocks) |
| Receiving / rushing TD | 6 |
| Passing yard | 0.04 |
| Passing TD | 4 |
| Interception thrown | −2 |
| 2-pt conversion (pass, rush, receive) | 2 |
| Fumble lost (sack, rushing, receiving) | −2 |
| Kick/punt return or blocked-kick TD (`special_teams_tds`) | 6 |
| Offensive fumble recovered for a TD (`fumble_recovery_tds`) | 6 |

Points are rounded to 2 decimals.

## Validation

| Reference | Result |
|---|---|
| nflverse `fantasy_points_ppr`, all QB/RB/WR/TE weeks 2019–2025 | Identical (±0.01) on all but 16 player-weeks, every one an offensive fumble-recovery TD. nflverse omits these and ESPN's default scoring includes them. |
| ESPN's own actual weekly totals (`leaguedefaults/3`) | Spot check during the ESPN investigation: 117 of 117 WRs in 2024 W5 matched exactly. Full validation runs automatically (target `scoring_validation`) when ESPN is enabled. |

Known open question: fumbles lost **on returns** are counted in nflverse's
`fumbles_lost_total` but not in the three components we penalise (23 WR-weeks
in 2025). ESPN's treatment will be settled by the automated comparison with
ESPN actuals once ESPN is enabled.

Unit tests are in `tests/testthat/test-scoring.R`.
