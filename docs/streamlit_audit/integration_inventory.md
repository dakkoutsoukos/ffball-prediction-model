# Integration inventory

*Labels: [V] verified · [I] inferred · [P] proposed. "Privacy" is one of:*
- *P0: public or code-level.*
- *P1: private but name-free (ids, hashes, aliases).*
- *P2: league-private (names, rosters).*

*All P1 and P2 data stays under git-ignored paths.*

## 1. Read-only artifacts (Option A)

| Artifact | Path pattern | Format / key fields | Freshness | Privacy | Interface |
|---|---|---|---|---|---|
| Valuation values | `data/archive/valuation/season=S/week=WW/run=<TS>/values.parquet` | 34 cols incl. `run_id, player_id, gsis_id, espn_id, espn_name, position, team, ros_points, vor, vor_regular, vor_playoffs, ros_points_playoffs, current_week_points, current_source, overall_rank, position_rank, injury_status, pct_owned, rostered, sim_team, mru, trade_value, methodology_version` [V] | Dispatcher capture each slate (~4 min, X-006) | P2 (`sim_team`, rostered) | Stable; adapter not needed |
| Valuation siblings | same dir: `weekly, baselines, consolidation, display_knots, rosters, scarcity, sensitivity_*`.parquet + `run_meta.json` [V] | schemas to be read in Phase 0 | same | P2 | Stable |
| Valuation index | `archive/valuation_manifest.csv` (run_id, season, week, as_of_utc, methodology_version, …sha256, m4_run_id, git_commit) [V] | 3 runs | append-only | P1 | Stable |
| Predictions (frozen lineages) | `data/archive/predictions/season=S/week=WW/run=<TS>/{predictions.parquet,run_meta.json}`; manifest `archive/prediction_manifest.csv` [V] | `(season, week, gsis_id)` | each dispatcher run | P1 | Stable |
| Distributions (P0) | `data/archive/distributions/season=S/week=WW/run=<TS>/pods.parquet`; `archive/distribution_manifest.csv` (`pod_version`) [V] | schema TBD Phase 0 | after each capture | P1 | Stable |
| League snapshot | `data/snapshots/espn_league/<alias>/captured_at=<TS>.json.gz` + `_roster.parquet`; `archive/league_snapshot_manifest.csv` [V] | team_id, espn ids | **manual** `league_refresh.R` | P2 | Roster: stable; standings/schedule: parse via adapter `context`/`standings` |
| League analysis run | `data/archive/league_analysis/<alias>/season=S/run=<TS>/{power_rankings,team_needs,mtv,my_team_trades,waiver_curves,waiver_levels}.parquet + analysis_meta.json` [V] | | only when `trade_analyzer.R snapshot` runs | P2 | Stable |
| Query results | `.../league_analysis/<alias>/season=S/queries/<TS>_<cmd>.json` (`result` = full tables, `inputs`, `methodology_version`, `git_commit`) [V] | | per CLI call | P2 | Usable read-only ("last CLI result") |
| Decision ledger | `data/archive/decisions/<alias>/season=S/week=WW/<TS>_<type>_<sha8>.json` (`decision_record_v1`; types lineup, odds, waivers, trade_rescore); `archive/decision_manifest.csv` (6 records) [V] | | per CLI/briefing call | P2 | Read via JSON. **Recommendations and inputs only. Never join with outcomes (sealed).** Prefer reading through `lg_ledger_read` semantics: verify `record_sha256` against the manifest |
| Briefing | `data/archive/briefings/season=S/week=WW/briefing_<TS>.{md,html}` [V] | self-contained HTML | manual, 12.2 min | P2 | Embed via `st.components.v1.html` (no external resources [V, X-024]) |
| Ops status | `data/ops/status.txt` (7 lines, name-free), `dispatch_log.csv` (`logged_at_utc, decided_for_utc, action, kind, season, week, slate_id, reason, result`), `upstream_log.csv`, `logs/` [V] | | hourly | P1 | Stable text; parse loosely |
| Manifests (11) | `archive/*.csv` (headers in the data audit) [V] | | append-only | P1 | Stable |
| Frozen registry | `models/registry/m{1,2,3,3b,4}.yml`, `models/fingerprints/*.csv`, `models/{probabilistic,simulation,valuation}/*.yml` [V] | | frozen | P0 | Read-only, never write |
| Research records | `research/experiment_log.md`, `valuation_log.md`, `research/master_plan/execution/{milestone_tracker,experiment_results,decisions,progress}.md`, `research/contamination_register.yml`, `docs/*.md` [V] | Markdown tables/prose | on commit | P0 | Parse Markdown tables; link prose |
| targets store | `_targets/` (≈265 objects; e.g. `vl11_result, m4_dev_eval, p3_gate_result, s2_summary, x22_result`) [V names] | R serialized | static | P0/P1 | Via adapter op `research_target` (read with `tar_read`, allow-list only) [P]; never `tar_make` |

## 2. Computational entry points (via `ui/r/ui_adapter.R`) [P built on V functions]

| Adapter op | Core function(s) [V] | Params | Runtime evidence | Existing side effects bypassed |
|---|---|---|---|---|
| `health` | `i3_health` (`R/live/monitor.R:148`), `ops` git state | none | seconds [I] | none (status.R prints only) |
| `context` | `lg_load` (`league_analysis.R:50`), `lg_state_from_snapshot`, `lg_latest_snapshot` (`league_espn.R:286`) | season | ≈10–20 s [I] | none |
| `odds` | `sim_league_odds` (`season_sim.R:275`) + 4×2,000 sensitivity bands | sims ≤ 10k, add/drop, horizon | 11 s (15 s with K/D-ST) [V L567/L1647] | ledger `odds` record (`trade_analyzer.R:211`) |
| `lineup` | `lg_lineup_advice` (`lineup_helpers.R:151`) | team, now, fixed_prior, availability overrides [P: new parameter applied to the provider output in the adapter, not in R/] | seconds [I] | query JSON + manifest; ledger `lineup` |
| `trade_eval` | `lg_trade` + `sim_trade_rescore` (`trade_rescore.R:54`), `trade_frontier/trade_explain/trade_title_decomposition/trade_nash` (`trade_v3.R`) | team_a, give_a, team_b, give_b, sims ≤ 5k, horizon | ≤ 0.56 min for top-5 [V L1216]; a single trade is less [I] | query JSON + manifest; ledger `trade_rescore`/`trade_analyze` |
| `trade_search` | `lg_trade_search` → `d2_trade_valid` (X-021) → optional rescore top-k | b, k ≤ 5, win_win | 0.56 min [V] | same |
| `fa_board` | `d3_fa_screen`, `sim_fa_rescore` (`fa_board.R:103`), `d3_drop_advice`, `d3_stream_view` | k ≤ 8, per_pos, sims ≤ 5k | 0.8 min [V L1357] | ledger `waivers` |
| `values3` | `v3_live_values` (`values_v3.R:54`), `v3_roster_risk` | team, sims ≤ 5k | 1.3 min for 15 players [V L1443] | query JSON + manifest |
| `standings` | parse from snapshot via `lg_state_from_snapshot` | — | seconds [I] | none |
| `draft` (later) | `d4_pool, d4_live_state, d4_recommend, d4_rescore_odds` (`v3_draft.R`) | picks csv (owner, git-ignored), rollouts | 19 s/pick, +~1 min with odds [V] | none (console only) |
| `research_target` | `targets::tar_read` on an allow-list | name | seconds | none |

Never wrapped (operations that are not user-triggerable):
- `league_refresh.R` (ESPN request);
- `valuation_run.R --capture` (ESPN plus a clean-tree commit path);
- `weekly_run.R` (network plus `git commit`);
- `ops_dispatch.R`;
- `ops_setup.R` except `--status`;
- `briefing.R` (writes ledger records): it stays a terminal command; the UI only displays its output;
- `pod_archive.R`, `horizon_study.R`, `backup_archives.R`;
- any `tar_make`;
- the X11b run.

## 3. Identifier and join rules

- **Canonical key:** `gsis_id`. `espn_id` maps via `espn_crosswalk` ∪ `val_crosswalk`; ambiguous pairs are rejected
  upstream [V, docs/data_provenance.md].
- `values.parquet` has both ids, so UI joins go through it [V].
- **Known data issue:** 13 duplicated player-week keys exist in weekly rosters [V docs]. Adapter and UI joins must
  assert uniqueness and surface duplicates instead of fanning out.
- **Team:** ESPN integer `team_id`. Team names come only from the snapshot, at display time.

## 4. Failure modes the UI must handle

- No valuation run for the current week: fall back to the latest one, with a stale badge.
- Snapshot older than 24 h: the UI shows its age. The adapter passes `allow_stale = TRUE` and labels the result
  "stale context".
- Manifest row without a folder (or the reverse): list it in the Ops page and skip it.
- Parquet schema drift: `contracts.py` lists missing or extra columns. Missing required columns hide that panel
  only.
- Adapter exit 3 (context changed mid-session): prompt to reload the context.
- Memory pressure: one job at a time, in-process only.
- R start-up failure: show stderr in the Ops page. Logs hold no names (the adapter writes structured results, not
  prints).

## 5. Unknowns to resolve in Phase 0 (cheap, read-only)

- Schemas of `weekly, baselines, rosters, pods, power_rankings, team_needs, mtv, waiver_*` (pyarrow `read_schema`).
- The JSON structure of a ledger record and a query JSON: print keys only.
- Exact signatures of the core functions: their formals, read from source.
- Time to source `R/**` cold. Measure with an adapter `--op noop`.
