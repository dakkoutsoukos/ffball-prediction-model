# Risk register

*Severity and likelihood: H/M/L. Sorted by priority.*

| # | Risk | Sev | Lik | Mitigation | Verification |
|---|---|---|---|---|---|
| 1 | UI triggers CLI paths that append `archive/league_query_manifest.csv` or `decision_manifest.csv` and write ledger records, polluting the sealed 2026 decision record | H | H if CLIs are wrapped | Adapter calls core functions only; forbidden-call list | Static grep test; `git status --porcelain archive/` empty after the E2E session |
| 2 | Display of sealed 2026 outcomes (accuracy, calibration, ledger outcomes) | H | M | Research page shows registered results only; `research_target` allow-list reviewed against `contamination_register.yml`; no realized-points loader exists in `ui/` | Test: no `ui/` code references realized-points tables; allow-list review recorded |
| 3 | Private data in Git (names, alias folders, cached results, screenshots) | H | M | All writes under `data/archive/ui_cache/` (ignored); no fixtures from real data; add `data/draft/` ignore rule (A6) | `tmp/privacy_scan.R` + `test-privacy.R` before every commit; `git check-ignore` test for ui_cache |
| 4 | Accidental ESPN request | H | L | No wrapper for `league_refresh`/`valuation_run --capture`/`weekly_run`; the adapter never needs credentials | Grep test for `lg_snapshot_league`, `espn_`, `httr`, `curl` in the adapter; refresh is shown as a terminal command only |
| 5 | Scheduled runs skipped (dirty tracked code or untracked files under `R/`/`scripts/`) | H | M | No UI files under `R/` or `scripts/`; commits outside slate windows | `untracked_code()` returns empty; `status.txt` shows no SKIPPED after UI sessions |
| 6 | Frozen-model or fingerprint change | H | L | UI never writes `models/`; no `tar_make` except owner-approved check targets | `git diff --stat models/ research/*.yml` empty |
| 7 | Streamlit telemetry or network exposure | H | M (default telemetry is on) | `.streamlit/config.toml`: `server.address=127.0.0.1`, `browser.gatherUsageStats=false` | Test parses the config; `netstat` shows a 127.0.0.1-only listener |
| 8 | Misleading statistics (shadow odds shown as validated; ΔP ranking within noise) | H | M | Fixed badges; bands always shown; FRAGILE flags; X11 note on trade cards | AppTest asserts the badges on each panel |
| 9 | Memory exhaustion (one machine; ~5.5 GB free virtual at audit) | M | M | One job at a time; in-process; capped simulations; no PSOCK | Lock test; observe peak memory on the largest op in Phase 3 |
| 10 | Mismatched snapshots (roster from one capture, values from another) | M | M | Single context per page; sha check in the adapter (exit 3); mismatch banner | Test with two fixture contexts |
| 11 | Identifier errors (name joins, duplicate keys) | M | M | Join on `espn_id`/`gsis_id` only; uniqueness asserts | Contract tests on fixture duplicates |
| 12 | Streamlit caching staleness or bleed | M | M | Cache keyed on path, mtime and size, or on the full context hash; never cache by name | Cache tests: file change → new read |
| 13 | Windows subprocess issues (paths with spaces, orphaned R, consoles) | M | M | Arg lists not shell strings; `CREATE_NO_WINDOW`; terminate the process tree on cancel/timeout; PID lock | Cancel and timeout tests on Windows |
| 14 | Python/R dependency drift | M | L | Project venv with `uv.lock`; no R package changes; R pinned by renv | `uv sync --frozen` in tests; `renv.lock` diff empty |
| 15 | Scope creep (new models, a refresh button, ledger writes from the UI) | M | M | Approval list below; roadmap phases fixed | Session progress file lists each deviation |
| 16 | Mislabeled model versions | M | L | Labels from `meta.json`/`run_meta.json` `model_versions`, never hard-coded | Test: label equals the meta field |
| 17 | Schema evolution of archives | L | M | `contracts.py` checks; degrade per panel | Contract tests with missing/extra columns |

## Human approval boundaries

Stop and ask before any of the following:
- A1: installing packages or creating the venv.
- A2: the code location.
- A3: anything that writes the ledger or manifests.
- A4: anything that makes an ESPN or other network request.
- A5: editing an existing R, script or frozen file.
- A6: `.gitignore` changes beyond the listed additions.
- Running `tar_make`, the briefing, the X11b study or any spent or holdout check.
- Changing the scheduled task.
- Exposing the app beyond 127.0.0.1.
- Pushing.
