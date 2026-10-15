# Architecture

*Labels: [V] verified · [I] inferred · [P] proposed.*

## 1. Alternatives

| Criterion | A: artifact reads only | B: Rscript the existing CLIs | C: dedicated R adapter | Shiny |
|---|---|---|---|---|
| Complexity | Low | Low | Medium (one R script plus contracts) | Medium |
| Interactivity | None (only what was last run) | Full | Full | Full |
| Research safety | Highest | **Poor**: each call appends committed manifests and ledger records [V] | High: core functions only, cache writes only | High |
| Privacy | Good (local) | Poor: results arrive as name-laden stdout | Good: structured files in an ignored dir | Good |
| Dependency isolation | Python venv only | Same | Same; no R package change | **Breaks rule**: shiny not installed [V]; renv change barred before I1 |
| Performance | Instant | 10 s–12 min plus R start-up | Same compute, no stdout parsing; ~1.4 s R start-up [V] plus loading `R/**` (est. 5–15 s [I]) | Warm R session, fastest |
| Windows fit | Good | Good | Good (`subprocess` → Rscript verified [V]) | Good |
| Extensibility | Limited | Fragile (stdout format) | Versioned JSON contracts | Good after I1 |

A persistent R server (plumber or callr session pool) was considered. Plumber is not installed [V]. callr and
processx are installed [V], but a resident R process would hold memory on a machine where free virtual memory was
about 5.5 GB at audit time [V]; that pressure killed the X11b run. Per-call subprocesses are simpler and release
memory.

## 2. Recommendation: hybrid of A and C

```
Streamlit (127.0.0.1, venv)  ──reads──▶  data/archive/{valuation,distributions,briefings,decisions,league_analysis}
     │                                   data/snapshots/espn_league/<alias>/*_roster.parquet
     │                                   data/ops/status.txt, dispatch_log.csv, archive/*.csv, models/**, research/**
     │
     └─job runner─▶ Rscript ui/r/ui_adapter.R <op> --request <req.json> --out <dir>
                         │  sources R/** (read-only), calls core fns, NO lg_archive_query / lg_ledger_record
                         └──writes──▶ data/archive/ui_cache/<op>/<cache_key>/{result.json|*.parquet, meta.json}
```

Why, with evidence:
- The tools a UI needs are thin wrappers over pure-ish core functions (`sim_league_odds`, `sim_trade_rescore`,
  `sim_fa_rescore`, `v3_live_values`, `lg_lineup_advice`, `lg_trade`, `lg_trade_search` + `d2_trade_valid`,
  `i3_health`) [V]. The side effects sit in the wrappers (`trade_analyzer.R:358-370`) [V]. Calling the core
  functions skips them without editing anything.
- The UI lives outside `R/` and `scripts/`. Every production script sources all of `R/**` [V], so a UI file there
  would be loaded by the scheduled runs. The dispatcher also skips runs when `R/` or `scripts/` hold untracked files
  (`R/live/dispatch.R:261`) [V]. Untracked or modified files elsewhere do not block it: `git_state()` ignores
  untracked files (`R/live/prospective.R:28-33`) [V].
- The Python stack is already present (streamlit 1.65, pandas 3.0.3, pyarrow 25.0.1, altair 6.3.0 on Python 3.13.7)
  [V]. The plan still uses a project venv for reproducibility.

## 3. Component boundaries [P]

```
ui/
  app.py                     # st.navigation entry; page registry
  pages/                     # one module per page (see ui_specification.md)
  ffui/
    paths.py                 # repo root, archive roots; pathlib only
    artifacts.py             # discovery: latest run per kind, via manifests first, filesystem second
    contracts.py             # schema checks for each artifact (required columns/keys, versions)
    provenance.py            # Provenance dataclass: source path, run_id, as_of_utc, model_versions, sha256, label
    jobs.py                  # job runner: subprocess, lock files, timeouts, cancel, status
    labels.py                # SHADOW / informational / adopted badges, fixed wording from VL3/VL13
    privacy.py               # guards: no writes outside data/archive/ui_cache; no network imports
  r/ui_adapter.R             # the only R entry point the UI calls
  tests/                     # pytest (Python), plus testthat file for the adapter (see roadmap)
  requirements.txt / pyproject.toml + uv.lock
.streamlit/config.toml       # server.address=127.0.0.1, browser.gatherUsageStats=false, server.headless=true
```

## 4. Data flow and provenance

- **Discovery.** The latest valuation run is the last row of `archive/valuation_manifest.csv` whose `run_id`
  folder exists. Distributions use `distribution_manifest.csv`, decisions use `decision_manifest.csv` (filtered to
  the alias folder present), and the league snapshot uses `league_snapshot_manifest.csv`. Manifest sha256 values
  are checked against files on first load [P]. A mismatch shows a red provenance badge and does not block reading.
- **Point-in-time consistency.** A page shows one *context*:
  (league snapshot `captured_at`, valuation `run_id`, distribution run).
  The adapter's `m$inputs` already records `league_raw_sha256`, `valuation_run_id` and `seed` [V], and the UI
  echoes them. A panel never mixes artifacts from different contexts without a visible "mixed snapshot" warning.
- **Joins.**
  - Player joins use `espn_id`, or `gsis_id` where both sides have it. `values.parquet` carries both [V].
  - Names are never join keys.
  - `player_id` in simulation outputs maps through `val$weekly` (`lg_id_diagnostics`) [V].
  - Team keys are integer ESPN `team_id`.

## 5. R integration contract [P]

`Rscript ui/r/ui_adapter.R <op> --request <path.json> --out <dir>`
- **Ops (v1):** `health`, `context`, `odds`, `lineup`, `trade_eval`, `trade_search`, `fa_board`, `values3`,
  `standings`, `draft` (Phase 5+).
- **Request:** `{op, schema_version, params, context: {league_raw_sha256, valuation_run_id}, sims, seed}`.
- **Process:**
  1. Load `R/**` exactly as the scripts do.
  2. Build `m` with `lg_load(allow_stale = TRUE)`.
  3. Check the requested context sha against the loaded one (409-style error on mismatch).
  4. Call the core function.
  5. Write to a temp dir, then rename atomically to `--out`.
- **Output:** `result.json` (tables as records) or `*.parquet`, plus `meta.json` with: op, request, elapsed_seconds,
  inputs (`m$inputs`), model_versions, git_commit, git_dirty, labels, warnings.
- **Exit codes:** 0 ok, 2 bad request, 3 stale or mismatched context, 4 compute error.
- **Forbidden inside the adapter:**
  - `lg_archive_query`, `lg_ledger_record`, `append_manifest`;
  - any `espn_*` fetch or `lg_snapshot_league`;
  - `system2("git", c("add"|"commit"))`.
  A static test greps the adapter for these names (see roadmap).

## 6. Caching and background execution [P]

- **Cache key:** sha256 of (op, normalized params, league_raw_sha256, valuation_run_id, distribution run id, sims,
  seed, adapter version, git HEAD). Seeds are fixed by the core functions (e.g. 20261013L) [V], so the same key gives
  the same result.
- **Python-side caching:**
  - `st.cache_data` for artifact reads, keyed on (path, mtime, size).
  - Job results are read from `ui_cache` by key, never re-computed on rerun.
- **Jobs:**
  - At most **one** adapter job at a time (global lock file `data/archive/ui_cache/.lock` with PID and start time;
    a stale lock is cleared if the PID is dead).
  - `subprocess.Popen` with `creationflags=CREATE_NO_WINDOW`; timeout per op; cancel = terminate the process tree.
  - Status and progress go to `jobs/<key>/status.json`. The page polls with `st.fragment(run_every=2s)`.
- **Simulation caps:** odds ≤ 10k simulations, rescore/fa_board ≤ 5k, values3 ≤ 5k. The adapter runs in-process
  only; no PSOCK clusters (X11b memory lesson).
- **No accidental runs:** opening a page never starts a job. Jobs start only from an explicit button. A button shows
  the expected runtime from the inventory, and a cached result is offered first.
- **Recovery:** on start-up the app scans `jobs/*/status.json` with state `running` and no live PID, and marks them
  `interrupted`. Partial outputs never exist because of the atomic rename.

## 7. Privacy and safety controls [P]

- Streamlit binds to `127.0.0.1`; `browser.gatherUsageStats=false` (it defaults to true). No external fonts, CDNs or
  components. Altair renders locally.
- Every UI write goes under `data/archive/ui_cache/`, which is already ignored by `data/archive/*` [V]. The UI never
  writes to `archive/`, `models/`, `research/`, `R/`, `scripts/` or `config/`.
- The UI never reads `config/local.yml`. The R side resolves credentials itself, and the adapter never needs them
  because it makes no requests.
- The UI shows names (local screen). Logs written by the UI contain op names, keys and timings only.
- The privacy scan (`tmp/privacy_scan.R`) and `tests/testthat/test-privacy.R` run before every UI commit. A pytest
  checks that no file under `ui/` contains a league id pattern or loads `config/local.yml`.
