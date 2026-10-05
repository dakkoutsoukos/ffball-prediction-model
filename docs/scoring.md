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
| **Any** fumble lost, including on kick/punt returns (`fumbles_lost_total`) | −2 |
| Kick/punt return or blocked-kick TD (`special_teams_tds`) | 6 |
| Fumble recovered for a TD (`fumble_recovery_tds`) | 6 |

Points are rounded to 2 decimals.

## Validation

The target `scoring_validation` compares our points with ESPN's own actual
weekly totals on every run.

| Reference | Result |
|---|---|
| **ESPN's own actual weekly PPR totals**, all ESPN-projected WRs 2020–2025 | **14,622 of 14,628 identical (99.96%)**. 2022, 2023 and 2025 are 100% exact. |
| nflverse `fantasy_points_ppr` | Differs by design on about 1% of WR weeks. nflverse ignores return fumbles and fumble-recovery TDs. |

How the rules were settled, using ESPN actuals as the reference:
- **Fumbles.** Penalising only the sack, rushing and receiving fumble components
  matched ESPN on 99.01% of rows. Nearly every mismatch was a kick or punt
  returner losing a fumble on a return, which ESPN penalises. Switching to
  `fumbles_lost_total` raised agreement to 99.96%.
- **Fumble-recovery TDs.** ESPN credited 6 of 9 cases (offensive recoveries). The
  3 it did not credit were special-teams coverage recoveries, which nflverse's
  column does not distinguish. We keep +6 and accept those 3 known misses.
- **Special-teams TDs.** Credited in 57 of 58 cases. The exception is a
  missed-field-goal return TD.
- **Remaining 6 mismatches:**
  - the 3 coverage fumble-recovery TDs;
  - the missed-field-goal return TD;
  - two receiving 2-pt conversions that ESPN did not credit.

Unit tests are in `tests/testthat/test-scoring.R`.
