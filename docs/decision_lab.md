# Decision laboratory v1 (F6)

**Code:** `R/lab/`.
**Pre-registration:** LAB1, with amendments LAB1a and LAB1b, in `research/valuation_log.md`.
**Pipeline targets:** `lab_replays`, `lab_triage_x8`, `lab_triage_x9`, and `lab_dev`. The last is gated behind the recorded triage.

The lab replays **synthetic fantasy leagues on real NFL seasons**. It evaluates weekly lineup policies and
contested add/drop policies on realised points, using out-of-sample forecasts. It answers the owner's core
question (X8): do better forecasts produce better decisions?

It is an instrument, not a test. The decision family's one batch check is VL11, on 2025 replays. The only
confirmatory evidence is the 2027 prospective season.

## Seasons and contamination

| Seasons | Role |
|---|---|
| 2020–2023 | Development (`decision_family`) |
| 2019 | Forecast warm-up only |
| 2024 | Excluded (the distribution-stack check) |
| 2025 | VL11 only |
| 2026 | Sealed |

Every replay calls `assert_family_seasons()`.

## Leagues

- 20 per season, with sizes cycling 8, 10 and 12 teams.
- Starting slots: QB, RB×2, WR×2, TE, FLEX×2 (RB/WR/TE). Bench 7: 15 skill players per team.
- **No K, no D/ST, no trades.** K/DST points are not ESPN-validated (B-001), and no policy under study touches them.
- **Draft:** a snake draft on a pre-draft value minus the position's replacement level (n-th QB and TE, 3n-th RB and WR), plus N(0, 1) noise per team and player.
  - The pre-draft value is the previous season's mean positive ESPN projection, else the week-1 projection (LAB1b; ESPN's 2023 week-1 file is defective).
  - Only players with a week-1 ESPN row are draftable.
  - Caps: QB 2, TE 2, RB 6, WR 6. Every pick must leave enough picks to fill the starting slots.
- **Schedule:** a 14-week round robin. Playoffs in weeks 15–16 for the top 4, descriptive only.

## Information firewall

Policies are functions `policy(state, info)`. They never see the engine's outcome matrices.
`lab_info(S, t, stage)` truncates every player × week matrix by column, so nothing later exists inside it:

| Stage | Visible |
|---|---|
| Draft | Pre-draft values; week-1 ESPN rows |
| Waivers before week t | Everything from weeks ≤ t−1; the season's bye schedule |
| Lineups at week t | Everything from weeks ≤ t−1, plus week t's ESPN projection and the F4 base (late horizon) |

The tests plant future data (outcomes of week ≥ t, projections of week > t). Every earlier decision must be
unchanged, and the realised scores of week t must change.

## Forecasts and policies

- **Lineup values.**
  - raw: ESPN's week-of projection.
  - calibrated: F4's rolling per-position OLS base.
  - Lineups are optimal for the slot structure: fixed slots first, then FLEX. Optimality is brute-force tested.
- **Waiver values.**
  - Per-game level L_avg4: the mean of the last (up to 4) positive ESPN projections through week t−1.
  - raw: L_avg4.
  - calibrated: a_p + b_p·L_avg4. Coefficients come from next-1-to-4-week points on seasons before s (rolling origin).
  - Byes scale the value by the share of the remaining weeks the team plays.
- **Waiver gain.** The change in optimal lineup value times the remaining weeks.
  - Candidates: the top 5 free agents per position and the 2 weakest roster players per position.
  - Claims need a gain > 2 points and a legal roster afterwards. At most 2 claims a week.
  - Claims are contested in priority order (fewest wins, then fewest points), and a team that claims moves to the back.
- **Arms** for one focal team per league; the other teams play raw/raw:

  | Arm | Lineup | Waivers |
  |---|---|---|
  | A | raw | raw |
  | B | calibrated | raw |
  | C | raw | calibrated |
  | D | calibrated | calibrated |

  All arms share the league's draft, schedule and seeds.

## Outputs and analyses

- **Per team-week:** lineup, realised points, the hindsight-optimal points (regret), roster, and opponent. Arm A also records *shadow* decisions: both lineup policies and both waiver policies on the same state.
- **Triage** (outcome-free, reported first). X8: lineup and waiver flip rates and model-implied gains. X9: P(win) of EV lineups vs single swaps, with P0 distributions and P(active) by position × band (LAB1a).
- **Development results** (descriptive, after the triage): paired lineup-point differences with week-clustered, season-blocked bootstrap CIs, regret, and season-level outcomes (descriptive only).

## Known limits

- **Synthetic opponents.** They are ESPN-trusting managers: raw lineups and raw waivers.
- **Simple drafts.**
- **Pseudo-replication.** Leagues share NFL weeks, so inference clusters by season-week.
- **The 2023 week-1 ESPN file is defective.** Most projections are 0, so week-1 lineups that season are close to arbitrary in every arm.
- **Late horizon only.** Historical ESPN values are late-horizon, so lineups use post-inactive information, and the availability policies of X8 (ii) need P1.
