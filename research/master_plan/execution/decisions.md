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
