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

## Guardrails

2026 outcomes are never used to select features or models, tune
hyperparameters, choose transformations, subsets or ensemble weights, or modify a
model after a poor week. Changing a model means registering a **new** lineage id
with a new prospective record. Interim results are descriptive monitoring only.
The pre-registered primary test (research/experiment_log.md, E3) is evaluated
once, at the end of the 2026 regular season.
