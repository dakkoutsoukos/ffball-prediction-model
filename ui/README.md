# FFball app (local Streamlit UI)

A local window onto the FFball pipeline: this week's state, player values, trade/lineup/waiver what-ifs, season
odds, research records and operations health. Design and audit: [docs/streamlit_audit/](../docs/streamlit_audit/).

## Start

```powershell
ui\run.ps1                        # syncs the environment (uv, frozen lock) and starts http://127.0.0.1:8501
```
or, from `ui/`: `uv run streamlit run app.py`. The first start creates `ui/.venv/` from `uv.lock` (Python 3.13).
Requirements: `uv` and R 4.5.1 (`C:\Program Files\R\R-4.5.1\bin\Rscript.exe`, or set `FFUI_RSCRIPT`).

## How it works

| Layer | What | Where |
|---|---|---|
| Pages | Streamlit pages; no modelling code | `views/*.py`, `app.py` |
| Read-only data | Manifest-driven discovery of valuation runs, distributions, league snapshot, ledger records, briefings, ops status, research records; schema contracts; id-only joins | `ffui/artifacts.py`, `ffui/contracts.py`, `ffui/research.py`, `ffui/playerdata.py` |
| R adapter | Exploratory computations with the same core R functions as `scripts/trade_analyzer.R`, minus its persistence | `r/ui_adapter.R` |
| Jobs and cache | Background `Rscript` processes, one at a time; deterministic cache keys; timeout, cancel, recovery | `ffui/jobs.py` → `data/archive/ui_cache/` |

**The adapter's safety boundary.** After sourcing `R/`, `ui_adapter.R` replaces every persistence and network
function with a trip-wire that aborts the process (exit 5): `append_manifest`, `lg_archive_query`, `lg_ledger_record`,
`lg_snapshot_league`, `fetch_live_nflverse`, `write_once`, `httr2::req_perform`, `git add/commit/push`, and others.
Its only output is a temp directory renamed into `data/archive/ui_cache/<op>/<key>/`. It refuses an `--out` outside
that folder. Ops: `noop, health, context, lineup, odds, trade_eval, trade_search, fa_board, values3, research_target`.

**What the app never does.** It never contacts ESPN (refresh stays a terminal step), and never writes the decision
ledger, the committed manifests, `models/`, `research/`, `R/` or `scripts/`. It never runs `tar_make`, research or
any spent or holdout check. It never listens beyond 127.0.0.1, and usage statistics are off.

## Pages

| Page | Data | Computation |
|---|---|---|
| Command Center | Ledgered odds/lineup/waivers/trades, snapshot roster + values, briefing HTML, ops status | none |
| Player Explorer, Compare | Valuation run (V1 values, weekly), P0 distributions, value history, snapshot ownership | none |
| Trade Lab | League context | `trade_eval` (≈10 s), `trade_search` (≈45 s) |
| Lineup Lab | League context | `lineup` (≈4 s, availability overrides), `values3` (≈40 s) |
| Waivers | Ledgered board, league analysis | `fa_board` (≈16–30 s) |
| Season Outlook | Standings, schedule, ledgered odds | `odds` (≈11–20 s, bands, add/drop what-if) |
| Research | Registries, fingerprints, tracker, results, contamination register, logs | `research_target` (allow-list; refuses 2026 rows) |
| Operations | status.txt, dispatch log, manifests audit, horizon study, app jobs/cache | `health` (≈3 s), read-only `schtasks /Query` |
| Draft (2027), Help & limits | Static | none |

Every number carries a status badge: Adopted, Shadow / Unvalidated, Informational, Exploratory · not ledgered,
Fragile, Ledgered. Each panel has a Provenance expander: snapshot hash, valuation run, model versions, seed and
simulation count, elapsed time, git commit.

## Tests

```powershell
cd ui
uv run pytest                     # 54 tests on a synthetic fixture repo (no R, no real data)
$env:FFUI_REAL="1"; uv run pytest tests/test_e2e_real.py   # real archives + real R adapter (≈5 min)
```
The real-data tests check decision-record isolation (Gate B). Manifests, ledger, query archive, `models/` and
`git status` must be byte-identical after every exploratory op and after clicking through the decision pages.
Failure messages contain counts and hashes only, never names.

## Troubleshooting

- **"League snapshot N h old"**: run `Rscript scripts/league_refresh.R` in a terminal. The app never refreshes.
- **"missing, stale or changed context" (exit 3)**: the snapshot or valuation run changed after the page loaded.
  Reload the page; the context reloads in about 4 s.
- **"Another calculation is running"**: one R job runs at a time. Wait, or cancel it under Operations ▸ App jobs.
- **"safety trip-wire fired"**: an R function tried to persist or fetch. Nothing was written. Report it with the job
  log from Operations.
- **Rscript not found**: set `FFUI_RSCRIPT` to the full path of `Rscript.exe`.
- **Stale cached results**: Operations ▸ Clear the app cache. Results are keyed on inputs, snapshot, valuation run
  and code version, so this is rarely needed.
- `FFUI_DEMO=1` runs the app on fixtures and shows a DEMONSTRATION DATA banner. It is never the default.
