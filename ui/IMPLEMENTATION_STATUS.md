# Streamlit UI: implementation status and handoff

*Resume here. Read this file, then `git log --oneline -- ui docs/streamlit_audit .gitignore`, then run the tests.
Spec: `docs/streamlit_audit/` (approved A1–A6, 2026-10-15).*

Last updated: 2026-10-15 (session 1).

## State

| Phase | Status | Evidence |
|---|---|---|
| 0 Environment and contracts | COMPLETED | uv venv (Python 3.13, `uv.lock`); `.streamlit/config.toml` (127.0.0.1, no telemetry); `.gitignore` additions (2fdc1ae); adapter with trip-wires; schemas probed (names only) |
| 1 Foundation and read-only dashboards | COMPLETED | Command Center, Player Explorer, Research, Operations, Help; AppTest smoke on fixtures and real data |
| 2 Player analysis | COMPLETED | Player detail (weekly, P0 fan, value history), Compare; job runner (lock, timeout, cancel, recovery) with tests |
| 3 Decision tools | COMPLETED | Trade Lab (evaluate, search, saved), Lineup Lab (overrides, values3), Waivers, Season Outlook (odds, bands, what-if, standings, schedule, history) |
| 4 Research and operations depth | COMPLETED | Research allow-list op with sealed-season guard; health op; read-only scheduler query; cache management |
| 5 Hardening and validation | COMPLETED | 54 fixture tests + 6 real-data tests pass; final report `ui/FINAL_IMPLEMENTATION_REPORT.md` |
| Draft page | DEFERRED (by design) | Terminal tool exists; UI planned for the 2027 pre-draft window |

## Architecture decisions made during implementation

- The adapter lives at `ui/r/ui_adapter.R`, outside `R/`, so production scripts never source it, and the dispatcher's
  untracked-code check (R/, scripts/) is unaffected.
- Persistence is blocked by **process-local trip-wires**: functions reassigned after sourcing. No file in R/ changes.
  `write_once` is trip-wired too, so any archive write on a computation path aborts the job (exit 5).
- R partial matching: `p$team` would match `p$team_b`. Use `p[["team"]]`. (Fixed; keep using `[[ ]]` for new params.)
- The league context (`context` op, ≈4 s) loads only on a click, or from the cache. Opening a page starts no job.
- The `now` parameter of the lineup op defaults to the current hour, so the cache stays useful within the hour.
- Gate A: fingerprint and check targets were not rebuilt (that would be `tar_make`). Evidence instead:
  - no diff in R/, models/, scripts/, `_targets.R`, `renv.lock`;
  - the `models/` tree hash is unchanged across real-data runs;
  - the store records 0 errors for the 10 check targets.
  `tar_outdated` lists those targets as outdated. That status predates the UI work: the pipeline sources only `R/`.

## Tests

- `cd ui; uv run pytest`: 54 passed (fixtures; about 16 s).
- `FFUI_REAL=1 uv run pytest tests/test_e2e_real.py`: 6 passed (real archives; about 5 min). Timings (s): health 3.1,
  lineup 3.8, odds 11.4, trade_eval 11.1, trade_search 44.3, fa_board 15.9, values3 38.5 (2,000 simulations).
- R suite `testthat::test_dir('tests/testthat')`: 367 blocks, 0 failures (unchanged; no R file touched).
- `tmp/privacy_scan.R` before each commit: 0 hits.

## Known issues / limits

- The league snapshot was 46 h old at implementation time. Pages warn; refreshing is the owner's terminal step.
- Value and odds history charts are thin until more runs accrue (labelled "accruing").
- AppTest cannot tick `st.fragment(run_every=…)`, so the real-data UI test waits on the runner and reruns. Live
  progress-bar ticking was checked by HTTP boot only, not by a browser.
- `fragile` flags exist only on ledgered records (VL13 rule). UI what-ifs show the X11 noise note instead
  (|ΔP| < 0.005).

## Next exact action

None required. Optional follow-ups:
- the in-app draft board (2027 pre-draft);
- a browser-driven visual check;
- once R3 adopts horizon cells (early November), the adapter picks them up automatically through
  `r3_horizon_sd_fun`.
