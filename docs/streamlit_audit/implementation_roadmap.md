# Implementation roadmap

*For a later, separately authorized session. All [P].*

## 1. Standing boundaries (quote these at the start of each session)

- **Never edit** `R/`, `scripts/`, `models/`, `archive/`, `research/` (except a progress file; see §4), `renv.lock`,
  `.Rprofile`, `_targets.R`, `config/`.
  - UI code lives in `ui/` and `.streamlit/`.
  - `.gitignore` may get **additions** only: `ui/.venv/`, `data/draft/` (A6).
- **The adapter** (`ui/r/ui_adapter.R`) composes existing functions. It must never call `lg_archive_query`,
  `lg_ledger_record`, `append_manifest`, network fetchers, `tar_make` or git writes.
- **Write locations:** UI writes go only to `data/archive/ui_cache/`. No ESPN requests and no scheduled-task
  changes.
- **Tests and checks before each commit:**
  - pytest;
  - the adapter's testthat file;
  - the full R suite (`testthat::test_dir('tests/testthat')`), which must stay 0 failures;
  - `tmp/privacy_scan.R`.
- **Commits:**
  - Commit outside slate windows (Thu/Mon ~17:15–18:45 ET, Sun ~10:00–11:30 ET).
  - Commits are local only, on `main` (X-002). Never push.
- **Runtime limits:** one adapter job at a time, no PSOCK clusters, simulations at or below the documented defaults.

## 2. Phases

### Phase 0: environment and contracts (0.5 day)
- **Prerequisites:** owner approval of A1, A2 and A3.
- **Files:**
  - `ui/pyproject.toml` and `uv.lock` (streamlit, pandas, pyarrow, altair, pytest; versions pinned to those already
    on the machine);
  - `.streamlit/config.toml`;
  - `.gitignore` additions;
  - `ui/ffui/{paths,artifacts,contracts,provenance}.py`;
  - `ui/r/ui_adapter.R` with the `noop`, `health` and `context` ops;
  - `ui/tests/`;
  - `tests/testthat/test-ui-adapter.R`. This new file is the only addition under `tests/`. Committed together with
    the adapter, it avoids untracked-code skips.
- **Work:** resolve the §5 unknowns in the inventory (schemas, JSON keys, function formals, cold-start time). Record
  them in `docs/streamlit_audit/contracts.md`.
- **Acceptance:**
  - `uv run streamlit hello`-free smoke: the app boots on 127.0.0.1 and telemetry is off.
  - The adapter `noop` returns valid `meta.json`.
  - A static forbidden-call test passes.
- **Stop for approval if:** any core function needs a change to be callable.

### Phase 1: foundation and read-only dashboards, the MVP (2–3 days)
- **Pages:** shell and context bar, Command Center, Player Explorer (without wins added), Operations (file-based),
  Research (registry, tracker, results, contamination).
- **Acceptance:**
  - Every panel has provenance.
  - Missing artifacts degrade gracefully (tested with fixtures).
  - No job can start from these pages.
  - The manifest/folder audit matches a hand count.
- **Commit:** at the end of each page.

### Phase 2: player analysis (2 days)
- **Work:**
  - player detail (weekly, pods fan chart, history);
  - Compare;
  - adapter op `values3`, plus the job runner (`jobs.py`: lock, timeout, cancel, status, recovery).
- **Acceptance:**
  - The cache key is deterministic and a repeat request is served from the cache.
  - Cancel kills the R process tree on Windows.
  - An interrupted job is recovered as `interrupted`.
  - `values3` from the adapter equals the CLI `values3` result on the same context (one comparison run with
    `--allow-stale`). **This one CLI run appends one query-manifest row: do it only with the owner's approval, or
    compare against an existing query JSON instead.**

### Phase 3: decision tools (3–4 days)
- **Work:** adapter ops `lineup`, `trade_eval`, `trade_search`, `fa_board`, `odds`, `standings`; pages Trade Lab,
  Lineup Lab, Waivers, Season Outlook.
- **Acceptance:**
  - Each op matches its core-function output on a fixture context. Use synthetic league fixtures in the style of
    `tests/testthat/fixtures/espn_kona_synthetic*.json`.
  - Invariant-failing trades are excluded and counted.
  - Labels and bands are present.
  - Runtimes are within 1.5× of the inventory.
  - `git status` is unchanged after a full UI session (no manifest or ledger rows).

### Phase 4: research and operations depth (1.5 days)
- **Work:** `research_target` allow-list (read-only `tar_read`), source-of-truth table, scheduler read-only query,
  cache management.
- **Acceptance:**
  - The allow-list excludes any target holding 2026 outcomes. The list is reviewed against
    `contamination_register.yml` and recorded.

### Phase 5: hardening and UX (1.5 days)
- **Work:** end-to-end smoke (`streamlit.testing.v1.AppTest` per page), error-state review, accessibility pass,
  `docs/ui.md` user guide. The draft page is deferred to the 2027 pre-draft window.
- **Acceptance:**
  - All tests are green.
  - Fingerprint targets are unchanged: run only the cheap `*_fingerprint_check` and `*_check` targets, and only if
    the owner OKs a `tar_make` of those names. Otherwise compare `git diff --stat models/` as empty.
  - The privacy scan is clean.

### Parallelism

- Phase 1 pages and the Phase 2/3 adapter ops touch disjoint files. They can run in parallel worktrees once Phase 0
  contracts are committed.
- Never run two R adapter jobs or two R test runs at once (memory).

## 3. Tests per milestone

| Test | P0 | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|---|
| contracts/schema (pytest, fixtures) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| adapter forbidden-call grep + `noop` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| no-network guard (adapter run with no proxy; grep for `httr`/`curl` calls in the adapter) | ✓ | | ✓ | ✓ | | ✓ |
| cache key/invalidation, job lock/timeout/cancel | | | ✓ | ✓ | | ✓ |
| op parity vs core functions (synthetic fixtures) | | | ✓ | ✓ | | ✓ |
| stale/missing/mismatch behaviour | | ✓ | ✓ | ✓ | | ✓ |
| AppTest page smoke | | ✓ | ✓ | ✓ | ✓ | ✓ |
| `git status` clean after the session; no `archive/` diff | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| full R suite + privacy scan | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Synthetic data appears only in tests. If the app ever runs on fixtures (`FFUI_DEMO=1`), a persistent
"DEMONSTRATION DATA" banner is shown.

## 4. Interruption and recovery

- Progress lives in `docs/streamlit_audit/progress.md`: phase, last commit, next step, open approvals. It is updated
  at every commit.
- Each phase ends in a committed, green state. Work in progress lives only in `ui/` and never blocks the dispatcher,
  because untracked files outside `R/` and `scripts/` are ignored by the dirty check [V].
- Resumption: read `progress.md`, then `git log -- ui/`, then run the tests.
