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
