# Decisions

*Architectural, methodological and operational decisions made while executing the master plan, with
rationale. Newest last. Owner decisions are marked **[owner]**. A decision that changes a research
conclusion of the plan is marked **[plan change]** and cross-referenced in the affected document.*

---

## X-001 · 2026-10-13 · Owner decisions taken at the start of execution [owner]

Asked once, at the start of execution (AskUserQuestion), because each needs the owner's authorisation:

| Plan id | Question | Answer |
|---|---|---|
| O8 (part) | Add `view=mMatchup` to the existing single league request (F3-lite)? | **Approved.** Same single request; keys inspected only on the first response. |
| O1 | Register Windows Task Scheduler tasks for pre-slate runs (F0)? | **Approved.** Local commits only; the owner pushes. |
| F0/R3 | Each scheduled run also makes the all-position ESPN capture (`valuation_run.R --capture`)? | **Approved.** One extra request per run. |

Not asked (defaults from [11](../11_next_steps.md) §2 stand until a milestone needs them): O2 (ADP capture),
O3 (other sources), O4 (FantasyPros ECR), O5 (Sleeper leagues), O6 (RTools/Stan), O7 (S0 odds shown with
labels), and the other O8 items (transactions, box scores, previous seasons, draft history, K/DST slots,
2018 QB/RB/TE history). Each will be asked when its milestone becomes active.

## X-002 · 2026-10-13 · Milestone commits go directly on `main`

**Decision.** Milestones are committed locally on `main`, as all earlier work in this repository was.

**Rationale.** Scheduled prospective runs commit their manifests to whatever branch is checked out, and the
owner pushes `main` before kickoff. A development branch would capture manifest commits off `main` and
break the push-before-kickoff record. Consequence: the owner's pre-kickoff push also publishes any
milestone commits made before it, so every commit must be safe to publish (privacy-checked) at the time it
is made.

## X-003 · 2026-10-13 · Facts from the existing league snapshot (no new request)

A keys-only inspection of the latest local league snapshot (taken 2026-10-13 07:06Z with the existing
views) established, without printing any private value:

| Field | Value | Consequence |
|---|---|---|
| `tradeSettings.deadlineDate` | 2026-12-02 | ≈ 7 weeks remain: **S0's build condition (≥ about 2 weeks) is met** |
| `acquisitionSettings.isUsingAcquisitionBudget` | FALSE | No FAAB: D3's FAAB bidding and X17 are gated off for this league; waiver priority (`waiverRank`) applies |
| `draftSettings.keeperCount` | 0 | No keepers: D4's keeper valuation is gated off |
| `scoringSettings.scoringEnhancementType` | absent | No top-half (median) bonus |
| `scoringSettings.matchupTieRule` / `playoffMatchupTieRule` | NONE / NONE | Regular-season ties are possible; S0 must carry ties |
| `scheduleSettings` | 14 matchup periods; 4 playoff teams; seeding rule `TOTAL_POINTS_SCORED`; 1 division | S0 rules |
| `teams[].currentSimulationResults` | **absent** | See X-004 |
| `schedule` | absent | Needs `view=mMatchup` (approved, X-001) |

## X-004 · 2026-10-13 · ESPN's `playoffPct` is not in this league's `mTeam` response [plan change]

**Finding.** The plan (06 §4, 07 F3/S0/S2, 09 X24, 04 OD8) assumed `teams[].currentSimulationResults.playoffPct`
is returned by `mTeam`, based on the espn-api client code (10 §V). In this league's response at 2026 W6 the
key is absent.

**Decision.** The ESPN external comparator is recorded as *unavailable from the current request*. S0 and S2
proceed without it. Requesting another view to obtain it would be a new O8 item and is not done. F3-lite's
parser reads the field if ESPN later returns it (it may appear later in the season), and records its absence
otherwise.

**Affected documents.** The claim in 06 §4 and 10 §V remains true of the client code; its availability for
this league is now qualified here.

## X-005 · 2026-10-13 · F3-lite split: parse existing fields first, then add `mMatchup`

The settings, records, seeds, waiver ranks and transaction counters are already in the stored snapshots
(`mSettings`, `mTeam`). Their parser needs no request change. Only the schedule needs the newly approved
`view=mMatchup`. Both parts belong to F3-lite and are validated together.

## X-006 · 2026-10-13 · F0 design choices

| Choice | Decision | Why |
|---|---|---|
| Slate | Games on one US/Eastern date; a morning game (before 12:00 ET) on a date with later games is its own slate | One run per day-slate meets "a post-report run before every game" with the fewest ESPN requests. A London 09:30 game needs its own earlier run. |
| Windows | Slate run in [first kickoff − 3 h, − 1.5 h); catch-up until − 30 min; early-week run from 12 h after last week's final kickoff to 24 h before the first kickoff, only if the week has no run | After every final report (Wed/Thu/Fri/Sat by slate), before inactives (~ − 90 min). The hourly trigger at :05 always lands inside a 90-minute window. |
| Retries | ≤ 2 attempts per slate | A persistent failure (e.g. ESPN 401) must not hammer the API |
| "Post-report" check | Both teams' final reports (≥ 1 designation) in the run's own injury capture, **or** the capture within 26 h of kickoff | Healthy teams never show a "final" report. 26 h is after the Wednesday report for Thursday games and the Friday report for Sunday games. |
| New functions | `post_report_coverage()` etc. are new; `week_coverage()` and `injury_report_status()` are untouched | Lower regression risk than editing functions `print_status()` relies on |
| Scheduling | XML task definition via `schtasks /XML`, root folder name `FFball_dispatch`, `conhost --headless`, interactive token (no stored password), allowed on battery, `StartWhenAvailable`, `IgnoreNew`, 2 h limit | `/TR` cannot set battery or missed-trigger behaviour. Root-folder tasks need no admin rights. Headless avoids an hourly console flash. |
| Capture step | `valuation_run.R --capture` (full V1 valuation + capture, about 4 min) rather than a capture-only script | Exactly the V1 runbook command the owner approved; each capture also yields an archived valuation |

## X-007 · 2026-10-13 · Bugs found and fixed during F0

| Bug | Effect | Fix |
|---|---|---|
| `week_kickoffs()` kept only games with a home row | The 9 neutral-site international games of 2026 (e.g. W6 HOU–JAX in London) were missing from `status.R` counts and `weekly_run.R`'s kickoff checks. Predictions were unaffected (`prospective_targets()` uses team rows). | One row per `game_id`; regression test |
| Default season = calendar year | A manual week-18 run in January 2027 without arguments would have looked for 2027 games | `nfl_season()` (January–February → previous season) in `weekly_run.R`, `valuation_run.R`, `status.R` |
| Scheduled task had no HOME | R set HOME to Documents, so git called from R found no identity: the runs' local commits would have failed (caught by the in-task self-test) | Wrapper sets `HOME=%USERPROFILE%` if undefined |

**Technical debt logged, not fixed:** `R/data/nfldata_history.R` (L93) also filters on `home`, so as-of lines
for neutral-site games are missing from the E11 history (2021–2025). It feeds no frozen model. It is to be fixed when
R5/F4 first uses as-of lines, behind a new target (not by editing the E11 targets).

## X-008 · 2026-10-13 · The 2026 tests have less power than the plan said [plan change]

**Finding (F1, E16).** The plan put power at 45–50% for M3b/M4 vs calibrated ESPN and 35–40% for M4 vs M3b
(03 W5). That figure came from 2019's week-level variance alone, the least noisy injury season (σ_w 0.0147,
against 0.0249 in 2022), and a normal approximation. Using within-season σ_w pooled over all historical
seasons, t quantiles and the cleanest reference effects, power at 13–14 informative weeks is:

| Hypothesis | Power |
|---|---|
| H-D | 25–27% |
| H-M4 (both comparisons) | 32–35% |
| H-B | 37–40% |
| H-A | 8–9% |
| H-M2 | ≈ 1% (holdout effect had the wrong sign) |

With 1.5× noise, the H-B, H-D and H-M4 figures fall to 14–21%. The pooled 2026 + 2027 analysis reaches
55–77% for H-B, H-D and H-M4.

**Second finding.** The pre-registered percentile week bootstrap is anti-conservative at 13 weeks:
- simulated one-sided size 4.9% against a nominal 2.5%;
- power about 10 points above the t-based figures.

**Decisions.**
1. The primaries are unchanged (pre-registered).
2. E16 pre-declares the reading rules: a null means "under-powered", and H-M2 is expected to fail.
3. E16 adds sensitivity S8 (a small-sample t-interval), consistent with 05 §5's declared sensitivities.
4. 01, 03 W5 and 07 F1 carry a dated correction note instead of a silent edit.
5. The pooled 2026 + 2027 analysis (S5) becomes the main route to an informative answer. This raises the importance of
   keeping the frozen runtime pinned through 2027 (I1).

## X-009 · 2026-10-13 · "Blind e-process monitoring" is computed only at season end

The plan (07 F1, I3) asked for blind in-season e-process monitoring. Any in-season computation on 2026
outcomes would expose them to the developer and make them development data, which 05 §1 forbids.

**Decision.** The anytime-valid analysis (E16 S6) is computed once at R1, with its betting rule fixed in E16.
In-season monitoring of the frozen lineages is outcome-free (coverage, structural zeros, decision
relevance). No optional-stopping action exists for frozen lineages anyway.

## X-010 · 2026-10-13 · Push-time evidence for the late-push rule

The late-push sensitivity analysis (E16 §4) needs the time each manifest reached GitHub, and git records no push times.

**Decision.** Three sources, used in order at R1:
1. GitHub's push record.
2. A local `pre-push` hook that only logs (`scripts/ops_setup.R --install-push-log`; installed 2026-10-13; it never
   blocks a push).
3. The dispatcher's hourly record of `@{u}` (an upper bound).

The pushes before 2026-10-13 have only GitHub's record.

## X-011 · 2026-10-13 · D0 uses the published prior for every position, WR included

The plan (07 D0) said P(active) should come from M4 for WRs. The archived M4 predictions store only the
final prediction, not M4's P̂(active), and the valuation rules forbid recomputing M4. D0 therefore uses the
fixed prior (`config/availability_prior.yml`) for all positions until P1 supplies calibrated P(active).

**Related assumption.** ESPN's current-week (pre-inactive) projection is treated as the player's
expected points *if he plays*, and the prior supplies availability. This is consistent with E13: before
inactives, ESPN does not price most of the inactive risk. For WRs from the M4 archive the prediction already
includes M4's post-inactive P̂(active), 0.93–0.98 for listed groups, so the plan EV double-counts availability
by at most a few percent. P1 and R3 will replace both pieces.

## X-012 · 2026-10-13 · D0 advises; it never changes the recommended starters

The starting set is the expected-points optimum on the same projections V2 uses. The designation prior
enters only the game-time plan, never the optimiser. D0 can therefore never lower expected points
relative to the existing logic, which is the plan's requirement. Whether starters should be re-chosen with
availability-adjusted values is a D1 question for 2027.
