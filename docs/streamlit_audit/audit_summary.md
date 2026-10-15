# Streamlit UI audit: summary

*Audit date 2026-10-15 (2026 W6). Planning only: nothing was installed, built or run beyond read-only checks.
Evidence labels used in every file in this folder: **[V]** verified by inspection or a safe check, **[I]** inferred,
**[P]** proposed, **[B]** blocked on information or approval.*

Files: [feasibility_report](feasibility_report.md) · [architecture](architecture.md) ·
[integration_inventory](integration_inventory.md) · [ui_specification](ui_specification.md) ·
[implementation_roadmap](implementation_roadmap.md) · [risk_register](risk_register.md).

## Bottom line

A local Streamlit app is feasible and practical. Most of the value can come from **reading artifacts the system
already writes**. Interactive what-ifs need **one new, narrow R adapter**. It calls existing core functions and
writes only to a git-ignored cache. It must never write the committed `archive/*.csv` manifests or the decision
ledger. That is the main integration finding: today's CLI tools have side effects that a UI cannot trigger freely.

## Final decision gate

1. **Is Streamlit the best practical framework?** Yes, for 2026–27.
   - Streamlit 1.65, pandas 3.0, pyarrow 25 and altair 6.3 are already in the system Python 3.13 **[V]**.
   - Shiny is not installed **[V]**. Adding it changes the R environment, which is barred before R1/I1
     (decisions.md X-024; 07 §I1).
   - Revisit Shiny only at I1 (January 2027), when a separate renv profile exists.
2. **Which architecture?** A hybrid of Options A and C:
   - The UI reads archived artifacts directly (parquet, JSON, status files).
   - A single R adapter script (`ui/r/ui_adapter.R`) is invoked as a subprocess for what-ifs. It returns
     JSON or parquet into `data/archive/ui_cache/`, which is git-ignored.
   - There is no persistent R server: plumber is not installed, and Rscript start-up is cheap (1.4 s bare **[V]**).
3. **What can use existing outputs?**
   - Status and dispatcher health.
   - Valuation tables (`values.parquet`, `weekly.parquet`, and others).
   - Briefing HTML and Markdown.
   - Odds, lineup, waiver and trade-rescore results already recorded in ledger JSONs.
   - League-analysis parquet files (power rankings, team needs, waiver curves, MTV).
   - Score distributions (`pods.parquet`).
   - Manifests, the frozen-model registry and the research logs.
4. **What needs the adapter?**
   - Interactive trade rescoring (any proposed trade).
   - Lineup what-ifs.
   - Odds under an add or drop.
   - Live `values3`.
   - Re-running the waiver board.
   - The draft assistant.
   - Health checks as data (`i3_health` returns structured data; `status.R` only prints).
5. **What do current models not support?**
   - FAAB or bid guidance (the league has no budget).
   - Keepers.
   - Trade acceptance prediction.
   - Validated P(title) or playoff odds; these are SHADOW only.
   - ESPN's own playoff odds (absent from the league response).
   - Player-level K and D/ST values.
   - Late-window lineup swaps and streaming as recommendations (both informational only).
   - The league trade-fairness monitor (needs transactions; scheduled for January 2027).
   - Any 2026 accuracy or calibration view (2026 outcomes are sealed).
6. **Effort.**
   - Phase 0: 0.5 day.
   - Phase 1: 2–3 days.
   - Phase 2: 2 days.
   - Phase 3: 3–4 days.
   - Phase 4: 1.5 days.
   - Phase 5: 1.5 days.
   - Total: about 11–13 focused days. The MVP (Phases 0–1) is about 3 days.
7. **Dependencies.**
   - A project-local Python venv created with `uv`, which is present **[V]**. It holds streamlit, pandas,
     pyarrow, altair and pytest; pytest is not installed today **[V]**.
   - No R package changes, and `renv.lock` stays untouched.
   - The venv itself needs owner approval because it is an install.
8. **Most serious integrity risks.**
   - The UI calls CLI paths that append to committed manifests or the ledger. That pollutes the sealed 2026
     decision record and dirties the tree before a slate window.
   - Showing any 2026 outcome-joined metric.
   - New `.R` files placed under `R/`. Every production script sources all of `R/**`, so the dispatcher would
     load them, and an uncommitted file there blocks scheduled runs.
   - Streamlit's default usage telemetry, which is on unless disabled.
   - Accidental ESPN requests through `league_refresh.R` or `valuation_run.R --capture`.
9. **Can implementation run autonomously?** Yes, inside the boundaries in [implementation_roadmap §1](implementation_roadmap.md).
   Stop only at the approval points below.
10. **Owner approval needed for:**
    - **A1:** create the Python venv and install packages.
    - **A2:** where the UI lives (`ui/`), and the adapter living outside `R/`.
    - **A3:** UI what-ifs are *exploratory and never ledgered*. Recording a decision stays with the CLI and
      briefing.
    - **A4:** any button that triggers an ESPN request. Recommended: none; league refresh stays a terminal step.
    - **A5:** any change to an existing R function. Recommended: none; the adapter only composes existing
      functions.
    - **A6:** adding a `.gitignore` rule for `data/draft/`, which is currently not covered.
11. **MVP and deferrals.**
    - **MVP:** a read-only command center (briefing, status, freshness), a valuation explorer over the latest
      run, the league outlook from the latest odds record, and a research and model registry page.
    - **Then:** the trade lab and lineup lab through the adapter.
    - **Deferred:** the draft assistant (until August 2027), a historical odds timeline (only one week of
      records so far **[V]**), and anything that needs F3-full or R1.
12. **Ready to start immediately?** Yes, once A1–A3 are answered. No code blockers were found. One caution: do
    the first commits outside slate windows (Thu/Sun/Mon) and keep `R/` and `scripts/` untouched.

## Exact next step

The owner answers A1–A3, which can be done in one message. Then start Phase 0 from
[implementation_roadmap.md](implementation_roadmap.md): create `ui/` and the venv, add `.streamlit/config.toml`
with localhost binding and telemetry off, then the adapter skeleton and its tests.
