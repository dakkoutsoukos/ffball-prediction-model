# Streamlit UI: final implementation report

*2026-10-15. Scope: `docs/streamlit_audit/` with approvals A1–A6. Start: `ui\run.ps1` → http://127.0.0.1:8765.*

## Features

**Completed**
- **Command Center**:
  - P(win), P(playoffs) and P(title) with sensitivity bands, from the ledgered odds;
  - latest ledgered lineup, waiver and trade recommendations, with fragility flags;
  - your roster with V1 values;
  - dispatcher health;
  - embedded weekly briefing, with a picker for past briefings.
- **Player Explorer**:
  - search, position, NFL-team and league-team filters, over all 452 players of a selectable valuation run;
  - V1 ROS points, VOR (full, regular, playoffs), trade value and ranks;
  - wins added, when a values3 result is cached;
  - detail view: weekly projections, a P0 outcome fan chart, and value history across runs.
- **Compare**: 2–4 players on one run. Weekly projections and P0 ranges side by side, with a warning when positions
  are mixed.
- **Trade Lab**:
  - multi-player trades with any partner;
  - V2 utility and fairness classification, with explanations;
  - optional S0 re-score: ΔP(playoffs/title), Δ wins, title decomposition, the partner's generic view, Nash summary;
  - package search with the X-021 invariant filter and top-k re-score;
  - a session comparison list.
- **Lineup Lab**:
  - D0 lineup for any team, at any clock time;
  - P1 provider or fixed prior;
  - per-player P(active) what-if overrides;
  - game-time plans;
  - values3 roster values (wins added, ΔP values, EVOR) and roster risk.
- **Waivers**: D3 board (utility screen, S0 re-score), drop advice, streaming view (informational), waiver priority.
  It shows the ledgered board until a fresh one is built.
- **Season Outlook**:
  - shadow odds, 5,000 or 10,000 simulations, with σ_L and noise bands;
  - add/drop what-if;
  - this week's matchups and leverage;
  - standings with V2 roster strength;
  - remaining schedule and schedule strength;
  - odds history from the ledger.
- **Research**:
  - registries, frozen parameter files and fingerprints;
  - source-of-truth table;
  - milestone tracker, registered results, contamination register with spent checks;
  - log browser;
  - stored results through an allow-list that refuses tables with 2026 rows.
- **Operations**:
  - dispatcher status and log;
  - manifests, and a manifest-to-archive audit;
  - valuation run metadata and hash check;
  - R3 horizon study;
  - I3 health checks;
  - read-only scheduler query;
  - app job history with cancel and logs;
  - cache management.
- **Help & limits**: guarantees, status labels, unsupported features, run times.

**Deferred or not built**
- **Draft page**: deferred to the 2027 pre-draft window, per the audit. The terminal tool exists.
- **Not supported by the models**, so not built: FAAB bids, keepers, acceptance prediction, ESPN playoff odds,
  player-level K/D-ST values, 2026 accuracy (sealed), league fairness monitor (January 2027). These are listed in
  the app.

## Architecture as built

The architecture is the audit's hybrid of Options A and C:
- **Pages** (`ui/views/`) read archives through `ui/ffui/artifacts.py`. Discovery goes through the manifests, with
  hash checks.
- **Computations** run through `ui/r/ui_adapter.R`. It uses the same core functions as `scripts/trade_analyzer.R`
  and is launched by `ui/ffui/jobs.py`:
  - background `Rscript`, one job at a time;
  - deterministic cache keys on params, league snapshot hash, valuation run, git HEAD and adapter hash;
  - atomic temp-then-rename writes;
  - timeout, cancel with process-tree kill, and recovery of interrupted jobs.
- **Persistence is blocked** inside the adapter by process-local trip-wires (exit 5):
  - functions: `append_manifest`, `lg_archive_query`, `lg_archive_analysis`, `lg_ledger_record`, `lg_ledger_action`,
    `lg_snapshot_league`, `lg_fetch_league`, `fetch_live_nflverse`, `refresh_live_data`, `write_once`,
    `write_frozen_yaml`, `write_fingerprint`;
  - network: httr2, httr, curl and `download.file`;
  - git: add, commit and push.
  No file in `R/` changed.

## Files

Created:
- `ui/`:
  - `app.py`, `run.ps1`, `pyproject.toml`, `uv.lock`, `.streamlit/config.toml`;
  - `ffui/`: `paths`, `artifacts`, `contracts`, `jobs`, `labels`, `research`, `playerdata`, `state`, `components`;
  - `views/` (11 pages), `r/ui_adapter.R`, `tests/` (6 files);
  - `README.md`, `IMPLEMENTATION_STATUS.md`, this report.
- `docs/streamlit_audit/` (7 planning documents).

Modified: `.gitignore` (additions only).

## Validation

| Gate | Result | Evidence |
|---|---|---|
| A Research integrity | PASS (by non-modification) | No diff in `R/`, `models/`, `scripts/`, `_targets.R`, `renv.lock`; `models/` tree hash identical before and after all real-data runs; R suite 367 blocks / 0 failures; the 10 fingerprint and check targets record 0 errors. They were not rebuilt (`tar_make` is an approval boundary); `tar_outdated` lists them, which predates this work (the pipeline sources only `R/`) |
| B Decision-record isolation | PASS | `test_gate_b_*` on real data: health, lineup with override, odds with add/drop, trade_eval with S0, trade_search with re-score, fa_board, values3. `archive/`, `data/archive/decisions/`, `data/archive/league_analysis/`, `models/` and protected `git status` were byte-identical. Same check after the AppTest click-through and after the live browser session (`sha256sum -c` of `archive/*.csv`: 0 changes) |
| C Privacy | PASS | Listener 127.0.0.1:8765 only (netstat); `gatherUsageStats=false`; `showErrorDetails=none`; ignore tests for the cache, venv, `data/draft`, pycache and secrets; UI code has no network imports and no credential access; privacy scan 0 hits before each commit |
| D Data correctness | PASS | Contracts per artifact; joins by ESPN id or gsis id only, with `validate=many_to_one`; duplicate ids surfaced; valuation and distribution run mismatch flagged; manifest hash checks |
| E Functional | PASS | 11 pages render (fixtures + real); real-data click-throughs of Trade, Lineup, Outlook and Waivers; adapter refusals (bad ids, sim caps, changed context, `--out` outside the cache, research allow-list) |
| F Performance | PASS | No job on page open (tested); cached repeat requests (tested); timeouts and cancel (tested). Real timings at 2,000 simulations: health 3.1 s, lineup 3.8, odds 11.4, trade_eval 11.1, trade_search 44.3, fa_board 15.9, values3 38.5 |
| G Git and ops safety | PASS | The tree was clean after each commit; all commits before the 21:15Z slate window; untracked work only under `ui/`, which the dispatcher ignores |
| H Final integration | PASS | Launched with `ui\run.ps1`. Browser check in Chrome: Command Center, Trade Lab (context load, live progress bar, result with badges), Player Explorer, Season Outlook. Two defects found and fixed: band shown as an up-arrow delta, and a port clash with another local app |

Tests: `uv run pytest` 54 passed (6 real-data tests skipped by default); `FFUI_REAL=1` 6 passed.

## Known limitations

- The league snapshot was 46–47 h old during validation. The app warns; refreshing is a terminal step.
- History charts accrue over the season.
- `fragile` exists only on ledgered records. What-ifs show the X11 noise note instead.
- Not every page was visually checked in the browser. Compare, Lineup Lab, Waivers, Research, Operations and Help
  were checked by AppTest only.
- PowerShell 5.1's `Set-Content -Encoding utf8` writes a BOM, which makes Streamlit ignore its config. A test now
  guards against it.

## Commits

`2fdc1ae` (ignore rules), `cd1edb5` (audit docs), `a331c3b` (app), plus the final validation commit with this
report. Nothing was pushed. `main` is ahead of origin by the earlier backlog plus these commits.

## Remaining owner actions

- Push when ready.
- Refresh the league snapshot before using the decision pages (`Rscript scripts/league_refresh.R`).
