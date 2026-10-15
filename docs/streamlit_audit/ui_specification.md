# UI specification

*All [P]. Difficulty: S (< 0.5 day), M (0.5–1.5 days), L (> 1.5 days).*

## 1. Global shell

- **Navigation.** `st.navigation` with five groups:
  - **Command Center**
  - **Players** (Explorer, Compare)
  - **Decisions** (Trade Lab, Lineup Lab, Waivers)
  - **Season** (Outlook)
  - **System** (Research, Operations)
- **Context bar (every page).** Shows:
  - league snapshot age, colored green < 24 h, amber < 72 h, red beyond that;
  - the valuation run id and as-of time;
  - the distribution run;
  - git HEAD, with a dirty flag;
  - "next slate window" from `status.txt`.
  It also has a "context mismatch" warning. A "How to refresh" popover gives the terminal commands; there is no
  refresh button (A4).
- **Status badges** (`labels.py`), with fixed wording:
  - `SHADOW · unvalidated`: S0, S2 and ΔP outputs. Wording from VL3: inputs early-week, odds too sharp until R3,
    rosters frozen, players independent.
  - `INFORMATIONAL`: late window, streaming, Nash.
  - `ADOPTED`: V1 VOR, V2 ΔU, wins added, S1-sim P(win).
  - `FRAGILE`: per the VL13 rule.
  - `EXPLORATORY · not ledgered`: every UI-run what-if.
- **Provenance expander** under each panel: source file, run id, sha256 (short), `model_versions`, seed, simulation
  count, elapsed time.
- **States.** Loading uses `st.status` while a job runs, with elapsed time against the expected time and a cancel
  button. When data is missing, the page says what produced it and the command to run.
- **Layout and accessibility.** Wide layout. Tables use `st.dataframe` with column config (formats, help text).
  Charts use Altair with a colour-blind-safe palette and direct labels. Probabilities use one decimal place, and
  bands are always shown next to point estimates. Nothing relies on colour alone: badges carry text.
- **Phone-width use is not a goal.** The app is local to the PC.

## 2. Pages

| # | Page | Purpose | Components and interactions | Data | Diff. |
|---|---|---|---|---|---|
| 1 | Command Center | One-glance weekly state | Metric tiles: P(win) this week, P(playoffs) ± band, P(title) (SHADOW), roster risk. "Latest briefing" embed (HTML), with a picker for older briefings. Action list from the latest ledger records (lineup, waivers, trades), each with time and fragility. Health strip | latest briefing, ledger JSONs, `status.txt` | M |
| 2 | Player Explorer | Find and rank players | Filters: position, NFL team, rostered/FA, league team. Search box (name and id). Sortable table: ROS pts, VOR (regular/playoffs), rank, wins added (if a `values3` cache exists, else a button), injury. Row selection opens the detail drawer | `values.parquet`, `rosters.parquet`, ui_cache values3 | M |
| 2a | Player detail | One player | Weekly projections (weekly.parquet). Score distribution (pods: quantile fan). Value over valuation runs (thin, labelled "accruing"). Provenance | weekly, pods, manifests | M |
| 3 | Compare | 2–4 players side by side | Multiselect, aligned metrics table, overlaid distribution chart | same | S |
| 4 | Trade Lab | Build and score trades | Partner team select. Two multiselects (give/get), validated against rosters. "Quick evaluate" (V2 ΔU and fairness, seconds). "Simulate" (ΔP playoffs/title, decomposition, explanations; about 0.5 min, ≤ 5k simulations). "Find packages" (search plus `d2_trade_valid`, top-k). Result cards show ΔU both sides, ΔP with band, Nash summary (INFORMATIONAL), FRAGILE flag, invariant exclusions count. Saved trades are a session-state list for comparison | adapter `trade_eval`/`trade_search` | L |
| 5 | Lineup Lab | Weekly lineup | Recommended lineup with slots, EV and kickoff time. Game-time plan. What-if: toggle a player's availability (manual override) and the fixed prior vs P1 provider, then re-run (seconds). Bench vs starter delta table. The late-window box is INFORMATIONAL only | adapter `lineup` | M |
| 6 | Waivers | FA decisions | Last board (ledger) or a fresh run (0.8 min): screen table (ΔU), re-scored top 8 (ΔP), drop advice, streaming view (INFORMATIONAL). Waiver-priority note; no bids (no FAAB) | ledger `waivers`, adapter `fa_board`, `waiver_curves` | M |
| 7 | Season Outlook | Standings and odds | Standings table. Odds table: playoffs and title with σ_L/noise bands, SHADOW badge. Remaining schedule. Scenario: add/drop, then re-run odds (≈15 s). Odds history from the ledger (accruing) | adapter `standings`, `odds`; ledger | M |
| 8 | Research | Methods and evidence, sealed-safe | Lineage registry (frozen commits, fingerprints). Milestone tracker table. Experiment results table (id, family, pre-registration, result, classification). Contamination register with spent checks and the sealed season. Source-of-truth table per metric. Links to logs. **No 2026 accuracy panels**; a fixed notice explains the seal | md/yml/csv; optional `research_target` allow-list | M |
| 9 | Operations | Health and freshness | status.txt, dispatch log (last 50), next window, push-needed count, manifest-vs-folder audit, `health` op results, scheduler state (read-only query), UI job history, cache size with a clear-cache button (ui_cache only) | ops files, manifests, adapter `health` | M |
| 10 | Draft (2027, deferred) | Live draft help | Pick log editor (git-ignored file), recommendation list, optional odds | adapter `draft` | L |

## 3. Interaction rules

- No page starts a job on load. Every compute button shows its expected cost and offers a cached result first.
- Session state holds the selected context (snapshot sha, valuation run). If newer artifacts appear, a banner
  offers to switch; the app never switches silently.
- What-if results always carry `EXPLORATORY · not ledgered`. To record a decision, the page shows the matching
  terminal command (`trade_analyzer.R rescore …`, `ledger-action …`) for the owner to run (A3).
