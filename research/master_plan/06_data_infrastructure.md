# 06 — Data and Infrastructure Strategy

*Recommends data sources, pipelines, architecture, storage, reproducibility practice and maintenance.
Facts about sources were verified on 2026-10-13 (see [10_sources.md](10_sources.md)). Milestone ids
refer to [07](07_master_roadmap.md).*

---

## 1. Principles (unchanged from today, made explicit)

1. **Point in time first.**
   - Every input carries the time it became available.
   - Every feature and decision is built by as-of joins (`available_at ≤ decision_time`).
   - Historical claims are allowed only for sources whose timestamps are trustworthy.
2. **Immutable raw data, provenance sidecars and hash manifests.** These already exist. Extend them to every new source.
3. **Free and terms-respecting.** No paid data (standing owner rule). Every source's licence is recorded, and so is what may be committed or published.
4. **Privacy.** League data, ids, cookies and anything derived from ESPN stay local. Git holds hashes, counts, aliases and code only.
5. **Prefer capturing over relying on history.** Where history cannot be reconstructed point in time (projections from other sources, ADP, lines, depth charts before 2025), start capturing now. History starts the day capture starts.

---

## 2. Current assets (verified in the repository)

| Asset | Coverage | Point-in-time status | Where |
|---|---|---|---|
| nflverse stats, play-by-play, schedules, rosters, snaps, injuries, depth charts, ffopportunity, ID maps | 2017–2025, plus 2026 live | Lagged features valid. Injuries valid 2017–2024 via `date_modified` (2025 has none). Depth charts valid from 2025. | `R/data/*`, `data/raw/` |
| nfldata git history (as-of lines, expected QB) | 2021–2025, plus prospective captures | Valid (commit time) | `R/data/nfldata_history.R` |
| ESPN week-of projections and actuals | WR 2018–2025; QB/RB/TE 2019–2025; 2026 completed weeks | Final pregame (Wayback-checked for 2019, 2023 and 2026) | `data/raw/espn*` (private) |
| ESPN live snapshots (WR) and valuation captures (QB/RB/WR/TE, all future weeks) | 2026 W5+ | True point in time (capture time) | `data/snapshots/` (private), `archive/*manifest.csv` |
| Owner's league snapshots (settings, teams, rosters, status) | 2026 W5+ | Point in time | `data/snapshots/espn_league/<alias>/` (private) |
| Prospective prediction and valuation archives | 2026 W5+ | Write-once, hash-verified | `data/archive/`, `archive/` |

---

## 3. Recommended data additions, in priority order

| # | Addition | Purpose | Coverage / timing | Cost and terms | Milestone | Decision |
|---|---|---|---|---|---|---|
| 1 | **League state v2.** F3-lite: schedule via `mMatchup` in the *existing* request, plus parsing of the standings, rules, deadline and FAAB settings already returned. F3-full: transactions/bids, weekly lineups, previous seasons, draft history. | Win and playoff odds; FAAB; opponent-behaviour profiles; real-league decision benchmark | Current season; previous seasons (2018+) where the API allows | Same ESPN private access as V2. **Rule:** adding a view to the existing single request is within the current opt-in; **additional requests or endpoints are owner decision O8**. Exact views: §4 | F3 | **Do** (lite now; full per O8) |
| 2 | **Position-general historical frame**: QB/RB/WR/TE with ESPN week-of projections and stat components, actuals scored by league rules, injury features, kickoff times, pregame roles, active status | Base data for P0–P4 and the decision lab (F6) | 2019–2025 (QB/RB/TE ESPN cache starts in 2019) | Already cached (private) | F4 | **Do** |
| 3 | **K and D/ST outcomes** from nflverse kicking stats and play-by-play, scored with the league's K/D/ST rules | Team-score variance for P(win) | 2017+ | Free (CC BY) | F4, S0 | **Do** (no ESPN needed) |
| 4 | **Multi-time weekly ESPN captures for all positions.** `weekly_run.R` captures **WR only** (L50), so F0 adds `valuation_run.R --capture` (QB/RB/WR/TE, all weeks) to each scheduled run, via a dispatcher keyed to kickoff times | Horizon study (R3, outcome-free revision variance); horizon spread terms | Prospective from now | Same ESPN opt-in; one request per capture at the existing cadence | F0, R3 | **Do** |
| 4b | **ESPN K and D/ST projections**: add the K/DST slot ids to the valuation capture (confirm by inspecting keys only) | Player-specific K/DST distributions; streaming tests | Prospective | Changes the request's content, so it falls under owner decision O8 | S0, D3 | Owner decision |
| 4c | **League draft history** (`mDraftDetail`) | D4 opponent model; calibrating ESPN 8-team ADP deviations | Past seasons (2018+) | Additional requests: O8 | D4 | Owner decision |
| 5 | **Market lines captured at every run.** Already captured via dated schedule retrievals and the nfldata history; make it explicit | Variance and correlation covariates (P2, P3); team environment | 2021–2025 history plus prospective | Free; nfldata has no licence file, so private use only | R5 | **Do** |
| 6 | **Weekly roster status / snap participation** as the P(active) outcome | P1 | 2017+ | Free | P1 | **Do** |
| 7 | **ESPN ADP and auction values** (player ownership fields) captured preseason and weekly | Draft assistant (D4), market-perception lens | Prospective (start July 2027) | Same ESPN opt-in. **Owner confirmation** before expanding requests. | D4, D2 | Owner decision |
| 8 | **Other free projection sources** (via ffanalytics-style scrapers; Sleeper's undocumented projections) | Multi-source averaging test (R4) | Prospective | **Terms vary.** FantasyPros allows personal single-copy use; Sleeper projections are undocumented. | R4 | Owner decision |
| 9 | **FantasyPros ECR archive** (`nflreadr::load_ff_rankings`, via DynastyProcess, GPL-3 repository) | Historical draft or market-perception proxy; synthetic league drafts | Weekly from about 2019 (start not verified) | FantasyPros terms: personal use only | F6 (optional), D4 | Owner decision |
| 10 | **FTN charting** (`read_thrown` first-read flag, 2023+) | First-read share test (R7) | 2022+ (first reads 2023+); within 48 h of each game | CC BY-SA 4.0 (share-alike applies if derived data is published) | R7 | Low priority |
| 11 | **Open-Meteo Previous Runs** (fixed 1–7-day lead-time forecasts) | Weather test (parked) | Most models from Jan 2024; GFS from Mar 2021 | CC BY 4.0, free for non-commercial use, < 10,000 calls/day | — | Parked |
| 12 | **Public Sleeper leagues** (read-only API, no authentication) | Larger samples for calibrating P(win), lineup-efficiency and FAAB-bid priors | Live; history per league | "Free to use for non-commercial purposes"; < 1,000 calls/min. These are other people's leagues, so aggregate, anonymise and keep local. | S1, D3 (optional) | Owner decision |

**Explicitly excluded** (paid, per the standing rule): PFF, SIS DataHub, FTN premium, Fantasy Points Data, 4for4, ETR, RotoWire, The Odds API history, and player-prop histories.

---

## 4. ESPN league API: the views F3 needs

*Facts are verified from the code of two open-source clients: ffverse/ffscrapr (R) and cwendt94/espn-api
(Python). See [10_sources.md](10_sources.md) §V. ESPN publishes no documentation. On the first live
request, confirm each field by inspecting response **keys only**, and print no private values.*

| Need | View / endpoint (as used by the client code) | Fields read by the clients |
|---|---|---|
| Settings already used | `mSettings`, `mTeam`, `mRoster`, `mStatus` (FFball today) | — |
| Matchup schedule and scores | `view=mMatchup` (ffscrapr) or `view=mMatchupScore` (espn-api). Per-period box scores: `mMatchupScore` + `mScoreboard` with `scoringPeriodId` and an `x-fantasy-filter` on `filterMatchupPeriodIds` | `schedule[]`: `matchupPeriodId`, `home.teamId`, `away.teamId` (missing away = bye), `totalPoints`, `winner` (`UNDECIDED`/`TIE`/`HOME`/`AWAY`), `playoffTierType` |
| Weekly starting lineups | `view=mMatchupScore&view=mBoxscore&view=mSettings&view=mRosterSettings` with `scoringPeriodId` (ffscrapr starters) | `rosterForCurrentScoringPeriod`, `lineupSlotId`, `appliedStatTotal` |
| Standings / records | `mTeam` (already requested) | `record.overall.{wins, losses, ties, percentage, pointsFor, pointsAgainst, streakLength, streakType}`, `playoffSeed`, `rankCalculatedFinal`/`rankFinal`, `divisionId`. Also **`currentSimulationResults.playoffPct`**: ESPN's own playoff odds, usable as an external comparator. |
| Playoff, tiebreak, trade and keeper settings | `mSettings` (already requested) | `scheduleSettings.{matchupPeriodCount, matchupPeriods, playoffTeamCount, playoffSeedingRule, playoffMatchupPeriodLength, divisions}`; `scoringSettings.{matchupTieRule, playoffMatchupTieRule, scoringEnhancementType}` (`WIN_BONUS_TOP_HALF` = median/top-half bonus); `tradeSettings.{deadlineDate, vetoVotesRequired, revisionHours}`; `draftSettings.keeperCount` |
| Acquisition / FAAB settings and state | `mSettings` / `mTeam` | `acquisitionSettings.{isUsingAcquisitionBudget, acquisitionBudget, minimumBid, acquisitionLimit, matchupAcquisitionLimit, waiverProcessDays, waiverProcessHour}`; per team `waiverRank`, `transactionCounter.{acquisitionBudgetSpent, acquisitions, drops, trades, moveToIR}` |
| Transactions and FAAB bids, route A | `.../leagues/{id}/communication/?view=kona_league_communication` with an `x-fantasy-filter` for `ACTIVITY_TRANSACTIONS` and message types 178/179/180/181/239/244 | `topics[].messages[]`: `messageTypeId`, `targetId`, `from`, `to`. **The FAAB bid is `from` on type 180 (waiver add).** Seasons from 2019 only. |
| Transactions and FAAB bids, route B | `view=mTransactions2` per `scoringPeriodId`, filtered by type (FREEAGENT, WAIVER, WAIVER_ERROR, TRADE_ACCEPT, …) | `transactions[]`: `bidAmount`, `type`, `status`, dates, `items[]` (`playerId`, `fromTeamId`, `toTeamId`). Client caveat: other teams' trade items are often empty. Whether `WAIVER_ERROR` carries losing bids is **unverified**. |
| Previous seasons | 2018+: `seasons/{S}/segments/0/leagues/{id}`. Before 2018: `leagueHistory/{id}?seasonId={S}` (the response may be a list, so take the first element) | `status.previousSeasons`, `currentMatchupPeriod`, `firstScoringPeriod`, `finalScoringPeriod` |

**Implications for FFball:**
- Adding `view=mMatchup` (or `mMatchupScore`) to the existing league request gives the full schedule in the same request.
- Standings, playoff and tiebreak rules, the trade deadline, the top-half bonus and FAAB settings all come from views FFball **already requests** (`mTeam`, `mSettings`). They only need parsing.
- Bid history needs one extra request (route A) or one per week (route B).
- The top-half bonus (`WIN_BONUS_TOP_HALF`), if enabled, changes the weekly objective. Expected points then gain value relative to P(win) (see the verified issue #188 in [02](02_research_landscape.md) §6).

**Rules (unchanged from V2):**
- one request per snapshot where possible;
- write-once storage under the alias;
- hash-only manifests;
- refuse stale snapshots;
- never print cookies, ids or team names.

---

## 5. Point-in-time availability registry (new, F2/I1)

A committed `config/pit_registry.yml` that every feature builder consults:

```yaml
injuries_final_report: {timestamp: date_modified, valid_from: 2017, invalid: [2025], tz_fix: {2017-2020: US/Pacific}}
depth_charts:          {timestamp: dt, valid_from: 2025}
participation:         {availability: after_postseason, use: prior_seasons_only}
ftn_charting:          {availability: game_end + 48h}
nextgen_stats:         {availability: nightly, caveat: "thresholded rows; week 0 overwritten"}
snap_counts_pfr:       {availability: "refresh 0/6/12/18 UTC", lag_min: next_day}
schedule_lines:        {timestamp: none, use: closing_label_only, asof_source: nfldata_git_history}
nfldata_git:           {timestamp: commit_time, valid_from: 2021}
espn_weekly_history:   {semantics: final_pregame_post_inactive, use: late_horizon_only}   # ESPN zeroes most inactives (E13)
espn_snapshots:        {timestamp: captured_at}
weather_schedule_cols: {semantics: observed_at_game, use: label_only}
ffopportunity_xfp:     {model_train: 2006-2020, in_sample_through: 2020, pin: v1.0.0}
nflfastr_models:       {model_train: 2006-2019, in_sample_through: 2019}
```

The leakage tests (§8 of [05](05_modeling_strategy.md)) assert against this file.

---

## 6. Storage and formats

| Data | Format | Location | Committed? |
|---|---|---|---|
| Raw retrievals | Original format plus a JSON sidecar (provider, version, retrieval time, SHA-256) | `data/raw/...` | No |
| Snapshots and captures | Parquet / JSON.gz, write-once, hive-partitioned `source=/season=/week=/captured=` | `data/snapshots/...` | No (hashes only) |
| Archived forecasts (points and distributions) | Parquet: quantiles at fixed τ = {0.01, 0.05, 0.10, …, 0.95, 0.99}, plus mean and p_active | `data/archive/{predictions,distributions}/...` | No (hashes in `archive/*_manifest.csv`) |
| Scenario draws | In memory by default. Persist only for audits: long parquet `(run_id, season, week, sim, player_id, active, points)`, float32, partitioned by run/week | `data/archive/scenarios/` (optional) | No |
| Decision ledger | Parquet rows: decision id, type, as-of time, input hashes, chosen action, alternatives and metrics, later outcomes | `data/archive/decisions/` | No (hash manifest only) |
| Registries, parameters, contamination register | YAML | `models/`, `research/`, `config/` | **Yes** |

DuckDB views over the parquet trees serve ad-hoc analysis, as today.

---

## 7. Pipeline architecture

- **Keep `targets`.** Split `_targets.R` into per-track target factories (I1):
  - `targets/projection.R` (frozen M-lineages; untouched);
  - `targets/valuation.R`;
  - `targets/probabilistic.R`;
  - `targets/simulation.R`;
  - `targets/decisions.R`;
  - `targets/evaluation.R`.

  Each factory returns a list of targets, and `_targets.R` composes them. A frozen lineage's targets are never edited, only composed.
- **Typed interfaces between layers.** Validate with schema checks at each boundary (`pointblank` or the existing `validate_*` helpers):
  1. *provider table* (exists);
  2. *availability table*;
  3. *distribution table* (POD: quantiles, mean, p_active);
  4. *dependence spec*;
  5. *scenario set*;
  6. *league state*;
  7. *decision record*.
- **Parallelism:** a `crew` local controller for backtests and simulation chunks (toolchain-free).
- **Dynamic branching** over (season, week) for rolling-origin backtests.
- **CLI scripts stay thin wrappers** over pipeline functions. They never push.

---

## 8. Reproducibility

- `renv` with a dated Posit Package Manager snapshot (existing).
- **Two runtimes.**
  - The **frozen-lineage runtime** (R 4.5.1 with the 2026-10-01 snapshot) stays pinned **through the 2027 season**. The pre-registered pooled 2026+2027 analysis then evaluates the same models.
  - New tracks use a **separate renv profile** (R 4.6 with a new dated snapshot) from January 2027 (I1). Side-by-side R installs are simple on Windows.
  - **The main `renv.lock` does not change before R1.** In-season builds use base R.
- Seeds:
  - **Scenarios:** L'Ecuyer-CMRG streams per chunk.
  - **Bootstraps:** fixed seeds.
  - **Recording:** every run records its seeds, input hashes, registry hashes and git commit (extending `run_meta.json`).
- Fingerprints for every frozen distributional and decision version (as for M1–M4): a hash of predictions on a fixed historical span.
- **Common random numbers** for every counterfactual comparison (trades, lineups, policies).

---

## 9. Operations and automation

| Task | Today | Recommended |
|---|---|---|
| Pre-slate prospective runs | Manual (W5 had no post-Friday run) | A **dispatcher keyed to kickoff times**, not fixed weekdays. It covers Thursday, Saturday (weeks 15–17), international (09:30 ET) and Monday slates. Each run executes `weekly_run.R --commit` (local commit only), then `valuation_run.R --capture` (all positions), then `status.R`. Wrappers are `.cmd` files with quoted absolute paths (the path has spaces). **Task Scheduler registration is the owner's choice (O1); the owner always pushes before kickoff.** |
| Coverage alarm | `status.R` on demand | Extend `week_coverage()` and `injury_report_status()` to flag any slate within 3 h of kickoff that lacks a post-final-report run. A **status file** is enough; no webhook or email infrastructure is needed. |
| League refresh plus valuation | Manual | Chain after the Tuesday run: `league_refresh.R` → `valuation_run.R --league --capture` → `trade_analyzer.R snapshot` → simulator (S0) → briefing (D5) |
| Monitoring | None | I3: blind calibration-drift monitoring (e-processes; no outcome-driven changes during a prospective season), data freshness, ESPN 401 detection (cookie rotation), Monte Carlo SE checks |
| Backups | `scripts/backup_archives.R` (manual, verified) | Unchanged |

Note: scheduled tasks run only while the PC is on. Scripts must stay idempotent and refuse to run on a dirty tree, as they do today.

---

## 10. Licensing and privacy guardrails (what can go where)

| Content | Git (public) | Local only |
|---|---|---|
| Code, docs, registries, parameters fit on nflverse data | ✅ | |
| Aggregate metrics computed on ESPN data (as already published in the logs) | ✅ (owner's existing practice) | |
| Row-level ESPN data, snapshots, predictions containing ESPN values | | ✅ |
| League ids, cookies, team names, rosters, transactions | | ✅ (alias plus hashes only in Git) |
| Row-level PFR-derived tables (Sports Reference restrictions) | | ✅ |
| FTN, participation and xFP derivatives | If published: CC BY-SA attribution and share-alike | |
| FantasyPros ECR derivatives | | ✅ (personal use) |
| Public Sleeper league data (if used) | Aggregates only | ✅ |

---

## 11. Maintenance risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ESPN API change or cookie rotation (401) | Medium | High: base forecasts and league data lost | Detect 401 and alert. Keep the provider abstraction. R6 fallback model. Keep the nflverse-only paths working. |
| ESPN terms enforcement | Low to medium | High | Low request volume, private use (owner's accepted risk). No redistribution. |
| nflverse schema drift (e.g., `stat_type` deprecated) | Medium | Medium | Schema validation at ingest; pinned retrieval sidecars |
| ffverse packages unmaintained | High | Low | Don't depend on them; reimplement small pieces |
| R/package upgrades change fingerprints | Medium | Medium | Upgrade only between seasons; re-verify fingerprints |
| Scenario compute growth | Medium | Low | Chunking, crew workers, caching per run, two-stage search |
