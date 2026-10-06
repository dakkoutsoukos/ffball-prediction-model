# Prospective protocol (2026)

2026 is the only season no model has been developed on. It is evidence, never
a development target. This document fixes how prospective predictions are made,
archived, selected and scored. It was committed before any 2026 outcome was evaluated.

## What counts as prospective

- **Weeks 1–4 of 2026 are excluded.** They were played before any prediction was
  archived, so a regenerated prediction for them is a backtest, not a prospective
  record. Their outcomes are used only as *training rows* by the frozen
  expanding-window procedure. They are never used for evaluation or development.
- **The prospective record starts in Week 5** (first archived run 2026-10-05).
- A model's prospective record starts at its **freeze date**. A model frozen
  mid-season has no record for earlier weeks.

## ESPN snapshots

- `scripts/snapshot_espn.R` and `scripts/weekly_run.R` capture ESPN's live WR projections into
  `data/snapshots/espn/season=S/week=WW/captured_at=<UTC>_wr.{parquet,json.gz}`.
- Files are **write-once**: the writer refuses to overwrite.
- Every capture is hashed (SHA-256) into the committed, append-only
  `archive/espn_snapshot_manifest.csv`.
- Each snapshot records season, week, capture time, ESPN id, name, live team
  (from ESPN's live team id, mapped and validated against nflverse), projected
  points and projected stat components, source URL, scoring settings
  (`leaguedefaults/3`), and the raw-file hash.
- **Official pregame projection policy:** for a game kicking off at time *K*, the
  official ESPN projection is the **latest snapshot captured strictly before *K***
  (`official_snapshot()`). Earlier snapshots are kept. Snapshots taken after *K* are never used.
- Snapshot data is ESPN content. It stays local and git-ignored. Only hashes are committed.

## Prediction runs

`scripts/weekly_run.R <season> <week> <lineages>` performs one **official run**. It requires a clean,
committed code tree, and the append-only `archive/` manifests are exempt. A run:

1. snapshots ESPN;
2. retrieves all live nflverse data as new immutable files (`data/raw/nflverse_live/`);
3. fetches ESPN's after-the-fact values only for **completed** 2026 weeks, used as training rows;
4. for each frozen lineage, refits each model with its registered procedure on
   all eligible rows from **final** games strictly before the target week, and predicts
   every WR in the snapshot with a projection above 0;
5. writes `data/archive/predictions/season=S/week=WW/run=<UTC>/predictions.parquet`
   and `run_meta.json`, both write-once;
6. appends their SHA-256 hashes, commit, snapshot hash and times to the committed
   `archive/prediction_manifest.csv`.

**Commit and push the manifest before the week's first kickoff.** GitHub then
holds a public, tamper-evident record that the predictions existed, without
publishing ESPN-derived data. Each prediction row carries:
- the model id;
- season and week;
- player ids and name;
- team, opponent and game id;
- kickoff (UTC);
- the prediction;
- the ESPN projection used;
- the snapshot capture time and hash;
- the run time;
- the git commit.

Recommended run times (ET):
- Thursday ~17:00, for the Thursday game;
- Sunday ~08:00 if there is an international game, and ~11:30 for the Sunday games;
- Monday ~17:00, for the Monday game.

## Scoring a prospective week

Scoring happens only after all of the week's games are final:

1. For each player-week and model, take the **latest archived run with
   `predicted_at < kickoff` and `snapshot_captured_at < kickoff`**. Runs made after
   kickoff never count.
2. Compare every model with ESPN **from the same run's snapshot**, so all models
   had identical information timing. ESPN's later after-the-fact value is reported only as context.
3. The population is the WRs that run predicted, defined pregame by the snapshot.
   A player ruled out later still counts, with an actual of 0.
4. Archived files are verified against the manifest hashes before scoring.
   Regenerated predictions are never mixed with archived ones.

## Weekly checklist (operations)

| When (ET) | Do |
|---|---|
| Tue/Wed (after the previous week is final) | `Rscript scripts/status.R`, which checks integrity and push state. Optionally make an early run. |
| **Thu ~17:00** | `Rscript scripts/weekly_run.R`. With no arguments it uses the inferred week and **all** frozen lineages. Then `git add archive/*.csv && git commit -m "Prospective run" && git push` |
| **Sun ~08:00** (international game weeks) and **~11:30** | Same run and push. The latest run before each kickoff is the official one for that game. |
| **Mon ~17:00** | Same run and push, for the Monday game. |
| Any time after a run | `Rscript scripts/backup_archives.R "<private folder>"`, which copies and SHA-256-verifies the evidence |

`scripts/status.R` reports:
- the next kickoff;
- which upcoming games already have an archived pre-kickoff run;
- whether every prediction and snapshot file still matches its committed hash;
- whether the manifests are committed and pushed;
- whether evidence changed since the last verified backup.

`scripts/weekly_run.R`:
- refuses to run on uncommitted code;
- refuses weeks whose games have all kicked off;
- warns about games already started (those players earn no prospective credit);
- re-verifies the new run's hash.

It never pushes. `--commit` makes only a local commit.

**Optional scheduling (not enabled).** Windows Task Scheduler could run
`weekly_run.R` at the times above, for example:

```
schtasks /Create /TN "ffball_thu" /SC WEEKLY /D THU /ST 17:00 /TR "<Rscript.exe> scripts/weekly_run.R"
```

with the start-in directory set to the project root. Because it makes ESPN requests
and pushing remains manual, enable it only deliberately.

## Separate prospective records per lineage

| Lineage | Models | Prospective record starts |
|---|---|---|
| M1 | `m1_*` (frozen 2026-10-05) | 2026 Week 5 |
| M2 | `m2_*` (frozen 2026-10-05) | 2026 Week 5 |
| M3 | `m3_role_adjust_v1`, `m3_role_adjust_q20_v1`, `m3_return_adjust_v1`, `m3_combined_v1` (frozen 2026-10-06 00:24Z) | 2026 Week 5 (first run 00:28Z) |
| M3b | `m3_questionable_adjust_v1`, `m3_questionable_add_v1`, `m3_combined_abd_v1` (frozen 2026-10-06 00:41Z) | 2026 Week 5 (first run 00:43Z) |

**M3b needs late-week runs.** Its rule uses the injury designation from **our**
capture of the official report, timestamped by our retrieval. Game-status
designations for Sunday games appear in the Friday report. Only a run made after
that (Saturday, or Sunday morning) and before kickoff can apply hypothesis D to
Sunday games.

Each lineage is scored only on weeks where it has archived runs. A changed
challenger becomes a new id (`*_v2`) with its own start. Earlier weeks are
never regenerated or back-filled. M3 results never enter the M1/M2 primary test.

## Guardrails

2026 outcomes are never used to select features or models, tune
hyperparameters, choose transformations, subsets or ensemble weights, or modify a
model after a poor week. Changing a model means registering a **new** lineage id
with a new prospective record. Interim results are descriptive monitoring only.
The pre-registered primary test (research/experiment_log.md, E3) is evaluated
once, at the end of the 2026 regular season.
