# Feature catalog (Milestone 2)

Every M2 feature is computed by `add_m2_features()` (R/features/m2_features.R).
It extends the frozen M1 engine, which is left unmodified.

**Point-in-time rule.** Features for a target week use only games with
`game_index` strictly before that week. They are attached with as-of joins.
`check_leakage_generic()` proves this on the real data in the pipeline target
`leakage_check_m2`. For random cutoff weeks it corrupts **every** column of
**every** history table from the cutoff onward:
- numbers are scaled and shifted;
- ids are rewritten;
- flags are flipped.

It then requires the cutoff week's features to be unchanged. Unit tests
(tests/testthat/test-m2-features.R) show that it catches planted leaks, such as
the same week's starting QB.

**Shrinkage constants** are fixed football priors chosen in advance, never fitted.
Fitting them would let other seasons leak into a feature.

Measured signal (descriptive ablations on the development folds) is in
§ Results at the end. Families were **not** chosen by ablation (pre-registered, E3).

## Included families

### 1. History and temporal representation (`history`)
- **Hypothesis.** Recent scoring predicts future scoring. Different horizons
  trade responsiveness for noise. A role change shows up first in short windows.
- **Features.**
  - EWMAs of PPR points with half-lives of 2 and 6 games (`fantasy_pts_ewma2/6`).
  - The last game alone (`fantasy_pts_roll1`) and the M1 trailing 8-game mean.
  - Season-to-date and previous-season means.
  - Volatility: SD of the last 8 games.
  - Career games, the "played the team's previous game" flag, the team-change flag,
    and weeks since the last appearance.
- **Point-in-time.** Strictly prior games only. EWMAs skip missing values.
  Windows count games, not weeks.

### 2. Opportunity (`opportunity`)
- **Hypothesis.** Volume and its quality (targets, air yards, red zone, end zone,
  deep looks, snaps, expected points) are more stable than points and drive them.
- **Features.** Short and long EWMAs of:
  - targets and target share;
  - air-yards share and snap share (PFR);
  - xFP;
  - deep targets (air yards ≥ 20), red-zone targets and end-zone targets;
  - WR carries.
  Also trailing 2- and 4-game targets.
- **Point-in-time.** Per-game play-by-play aggregates (DuckDB), used lagged only.

### 3. Role change (`role_change`)
- **Hypothesis.** Projections lean on season-level priors and update slowly. A WR
  whose target or snap share is rising (an injury ahead of them on the depth
  chart, a demotion, a trade) is mispriced for a few weeks.
- **Features.**
  - Short-minus-long EWMA trends of target share, snap share and xFP.
  - Target-share volatility (SD of the last 8 games).
- **Point-in-time.** Built from the lagged EWMAs above.

### 4. Efficiency (`efficiency`)
- **Hypothesis.** Per-target efficiency is noisy, but persistent skill exists.
  Shrinking toward a fixed prior keeps small samples from dominating.
- **Features.** Over the last 16 games, each shrunk toward a fixed prior:

  | Feature | Prior | Shrinkage weight |
  |---|---|---|
  | Yards per target | 8.0 | 30 targets |
  | Catch rate | 0.62 | 30 targets |
  | aDOT | 9 | 30 targets |
  | YAC per reception | 4.5 | 20 receptions |
  | Fantasy points over xFP per game | 0 | 6 games |

- **Point-in-time.** Trailing sums of strictly prior games.

### 5. Team environment (`team`)
- **Hypothesis.** A pass-heavy, high-tempo, efficient offence creates more and
  better WR opportunities. Concentrated target trees favour their top receivers.
- **Features.** Team EWMAs (half-life 6 games) of:
  - plays and dropbacks per game;
  - neutral-situation pass rate (1st/2nd down, win probability 20–80%, more than 2 minutes left in the half);
  - pass EPA per dropback;
  - top target share and target HHI.
- **Point-in-time.** The player's team for the target week comes from the schedule
  and roster. The state is the team's own prior games.

### 6. Quarterback, lagged only (`qb`)
- **Hypothesis.** QB quality and stability drive WR production, and a QB change
  disrupts targets.
- **Features.**
  - Whether the team's starter changed in its **previous** game.
  - Share of the last 4 games started by the most recent starter.
  - That QB's dropback-weighted EPA over his last 16 games (shrunk toward 0 by 200 dropbacks) and his dropbacks per game.
- **Point-in-time.** **This week's starter is never used.** The starter is defined
  as the dropback leader, which is only known after a game, so only the previous
  game's starter enters. A QB benching is therefore seen one week late, which is
  deliberately conservative. A unit test proves that a same-week starter feature
  is flagged as leakage.

### 7. Opponent (`opponent`)
- **Hypothesis.** Weak pass defences concede more WR production. Matchup effects
  are small and noisy, so they are heavily shrunk.
- **Features.**
  - Opponent pass EPA allowed per dropback over its last 8 games, shrunk toward 0 by 150 dropbacks.
  - WR fantasy points allowed over the last 8 games (from M1).
- **Point-in-time.** The defence's prior games only.

### 8. Priors for rookies and limited history (`priors`)
- **Hypothesis.** With little NFL history, draft capital and age carry information.
  Explicit missing-history flags let models treat rookies differently.
- **Features.**
  - log overall draft pick (undrafted = 300) and an undrafted flag;
  - age at kickoff;
  - years of experience and a rookie flag;
  - no-previous-season and no-games-this-season flags.
- **Point-in-time.** The draft slot is fixed at the draft. Age comes from birth date
  and kickoff date.

### 9. Schedule context (`context`)
- **Features.** Home, rest days, fixed dome (`roof == "dome"` only; retractable
  roofs are decided near kickoff, so they are excluded), and week of season.
- **Point-in-time.** All known when the schedule is published. **No betting lines.**

## Excluded, with reasons

| Candidate | Why excluded |
|---|---|
| Closing spreads/totals and implied team totals | nflverse lines are overwritten in-week and hold approximately closing values, with no timestamps. They are not valid for a pre-kickoff prediction in history. (M1's frozen `m1_espn_plus` uses them; M2 does not.) |
| Injury designations, game-day inactives | Untimestamped (injuries), or known only about 90 minutes before kickoff (inactives). |
| Teammate absence ("vacated targets") | Needs this week's injury or inactive status, which fails the same point-in-time test. Only lagged absences are used, via role-change trends. |
| Routes run, route participation (FTN/NGS) | FTN participation is published only after the season, so it cannot be computed prospectively in 2026. Snap share is the in-season proxy. |
| Depth charts | The source changed in 2025. Pre-2025 snapshot times are unknown, and 2025+ timestamped history is too short to train on. |
| Next Gen Stats separation/cushion | Rows exist only for players with at least 5 targets, and the week-0 season aggregate updates in place, a leakage hazard. |
| Weather | No historical forecast archive. Observed game-day weather is not pregame. |
| This week's starting QB | Not reliably known pregame in the historical data. |

## Results

See [research/experiment_log.md](../research/experiment_log.md) (E4) and
`reports/milestone2_report.html`. The family ablations are summarised there.
