# Feasibility report

*Labels: [V] verified · [I] inferred · [P] proposed · [B] blocked. Paths are relative to the repository root.*

## 1. Executive summary

The system is an R pipeline (R 4.5.1, renv-pinned) with:
- frozen projection lineages (M1–M4);
- valuation V1 (ROS values) and V2 (league trade analyzer);
- shadow simulators (S0, S1, S2, S3, D1–D5);
- a scheduled dispatcher (F0);
- a monitor (I3).

All user-facing tools are CLI scripts that print to the console. Every one of them prints team and player names, so
a UI has to work from their **structured side outputs**, not their stdout. Those side outputs exist and are rich:
parquet runs, query JSONs, ledger JSONs and briefing HTML. A useful read-only UI can be built with no R changes.
Interactive what-ifs need a new adapter, because the existing commands write committed manifests and ledger
records on every call [V].

## 2. Current capabilities (what actually works)

| Capability | State | Evidence |
|---|---|---|
| Weekly projections (frozen lineages, ESPN provider) | Working, scheduled | `scripts/weekly_run.R`; `archive/prediction_manifest.csv` (7 runs) [V] |
| ROS valuation V1 (VOR, ROS points, trade value) | Working, captured by the dispatcher | `scripts/valuation_run.R`; `data/archive/valuation/.../values.parquet` (34 cols) [V] |
| League analyzer V2 (rankings, needs, MTV, trade search, waivers) | Working; needs a fresh league snapshot (< 24 h unless `--allow-stale`) | `scripts/trade_analyzer.R`; `R/valuation/league_analysis.R` [V] |
| S0 odds (playoffs, title), shadow | Working, 11–15 s for 10k simulations | `sim_league_odds` `R/simulation/season_sim.R:275`; VL3, valuation_log L567/L1647 [V] |
| D2 trade re-score v3 (ΔP, frontier, Nash, explanations), shadow | Working, 0.56 min | `sim_trade_rescore` `R/simulation/trade_rescore.R:54`; `R/simulation/trade_v3.R` [V] |
| D3 waiver board, shadow | Working, 0.8 min | `sim_fa_rescore` `R/simulation/fa_board.R:103` [V] |
| S3 `values3` (wins added = primary display) | Working, 1.3 min for 15 players | `v3_live_values` `R/simulation/values_v3.R:54`; VL7, VL11 X10b supported [V] |
| D0/D1 lineup advice (EV slotting, game-time plan) | Working | `lg_lineup_advice` `R/valuation/lineup_helpers.R:151` [V] |
| D4 draft assistant | Working (development); for 2027 drafts | `scripts/draft_assistant.R`, `R/valuation/v3_draft.R` [V] |
| D5 briefing + I2 HTML | Working, 12.2 min | `scripts/briefing.R`; `data/archive/briefings/.../*.html` [V] |
| I3 health and status | Working; console only | `scripts/status.R`, `i3_health` `R/live/monitor.R:148` [V] |
| F0 dispatcher | Running hourly; last result 0 | `schtasks` query, `data/ops/status.txt` [V] |

## 3. Feature feasibility matrix

Legend:
- **E**: existing artifact, read directly.
- **A**: needs an adapter (computational).
- **N**: needs new modeling or data, out of scope.
- **X**: must not be shown.

### A. Fantasy command center
| Feature | Class | Notes |
|---|---|---|
| Weekly briefing | E | Embed the latest `briefings/.../briefing_<TS>.html` (self-contained) [V] |
| Roster overview | E | League snapshot `_roster.parquet` joined with `values.parquet` on `espn_id` [V/I] |
| Team strength and positional weakness | E | `league_analysis/.../power_rankings.parquet`, `team_needs.parquet`, written only by the `snapshot` command [V]; freshness depends on when it was last run |
| Upcoming matchup, P(win) | E (latest odds/lineup ledger JSON) / A (fresh) | S1-sim is adopted (X23); it is shown through the S0 shadow label |
| Playoff odds | E / A | S0 shadow; must show the sensitivity bands and the "unvalidated, too sharp" label (VL3 L525) |
| Championship probability | E / A, SHADOW only | P(title) from S0; no validated source |
| Waiver recommendations | E (ledger `waivers` record) / A | Streaming informational only; no FAAB (X-003) |
| Recommended actions | E | Briefing sections and fragility flags |
| Valuation summary | E | `values.parquet` + latest `values3` result if one exists, else A |
| Data freshness and health | E (status.txt, manifests, dispatch_log) / A (`i3_health` as data) | |

### B. Player valuation explorer
| Feature | Class | Notes |
|---|---|---|
| Search, filter by position/team, rankings | E | `values.parquet` cols `espn_name, position, team, overall_rank, position_rank` [V] |
| ROS projections, VOR, regular/playoff split | E | `ros_points, vor, vor_regular, vor_playoffs, ros_points_playoffs` [V] |
| Weekly projections | E | `weekly.parquet` (valuation run); `predictions.parquet` (frozen-lineage run) |
| Roster utility | E | `mru`, `trade_value`, MTV matrix (`league_analysis/.../mtv.parquet`) |
| Wins added (primary per VL11) | A (or E if a recent `values3` query JSON exists) | `values3` is not query-archived; it needs the adapter [V: values3 returns via console and query JSON] |
| Uncertainty and distributions | E | `distributions/.../pods.parquet` (P0, frozen `pod_baseline_v0`) |
| Historical value movement | E, thin | Only 3 valuation runs in the manifest [V]; the chart fills over the season |
| Provenance | E | `run_meta.json`, `methodology_version`, manifest sha256s |
| K/D-ST player values | N | v0 has position-level draws only (L1626) |

### C. Trade analyzer
| Feature | Class | Notes |
|---|---|---|
| Pick send/receive players, multi-player | A | `lg_trade` (ΔU, fairness) is fast [I]; `sim_trade_rescore` gives ΔP |
| Before/after roster strength, positional effect | A | V2 `lg_trade` outputs + v3 decomposition |
| Playoff/title implications | A, SHADOW | ΔP at 2,000–5,000 simulations does not rank close candidates (X11); show the fragile flag |
| Fairness, team-specific utility | A | Nash product is a "fairness summary, not an acceptance model" (L1206) |
| Alternative packages | A | `lg_trade_search` + `d2_trade_valid` (V2 search can return invariant-failing candidates, X-021) |
| Acceptance prediction | N | Explicitly unsupported (V2 methodology §7) |

### D. Lineup lab
| Feature | Class | Notes |
|---|---|---|
| Optimal lineup, FLEX, game-time plan | A (E from the last ledger `lineup` record) | `lg_lineup_advice`; EV only, never changes expected points (X-012) |
| Start/sit compare, what-if availability | A | Swap the P1 provider input (`--fixed-prior` exists [V]); manual availability override = new adapter parameter [P] |
| Projected lineup distribution | A | P0 distributions plus independence (P3 gate null) |
| Late-window swaps | N/informational | X8/X9 not supported (VL11) |

### E. Waiver explorer
| Feature | Class | Notes |
|---|---|---|
| Available-player rankings, roster improvement | E (`waiver_curves`, `waiver_levels` parquet) / A (`faboard`) | |
| Add/drop compare, short vs ROS | A | `d3_drop_advice`, `d3_stream_view` |
| Waiver priority | E | League has waiver priority, no FAAB |
| Bid guidance | N | No budget in the league |
| Live availability | [B] | Only as fresh as the last manual `league_refresh.R` (an ESPN request; stays an owner step) |

### F. Season outlook
| Feature | Class | Notes |
|---|---|---|
| Standings | E | League snapshot raw JSON (`captured_at=<TS>.json.gz`) via adapter parse [I]; the adapter is simpler than re-parsing ESPN JSON in Python |
| Playoff/title odds + bands | E / A | as above |
| Remaining schedule strength | A | `lg_state_from_snapshot` (mMatchup schedule) |
| Odds under scenarios (add/drop) | A | `sim_league_odds` with `--add/--drop` |
| Odds history | E, thin | One week of odds ledger records so far [V] |

### G. Research dashboard
| Feature | Class | Notes |
|---|---|---|
| Lineage/version explorer | E | `models/registry/*.yml`, frozen YAMLs, fingerprints CSVs [V] |
| Milestones, experiment status | E | `milestone_tracker.md`, `experiment_results.md` tables (Markdown parse) [V] |
| Backtest/development metrics | E (Markdown) / A (targets objects) | Metrics are mostly prose in logs; targets objects (e.g. `vl11_result`, `m4_dev_eval`) need R to read (`targets::tar_read`, read-only) [I] |
| Contamination register, spent checks | E | `research/contamination_register.yml` |
| 2026 accuracy/calibration, ledger outcomes | **X** | Sealed (`sealed_seasons: 2026`; `LEDGER_UNSEAL_ENTRIES`, `lg_ledger_report()` aborts) [V] |

### H. Operations
| Feature | Class | Notes |
|---|---|---|
| Last run, next window, coverage, push needed | E | `data/ops/status.txt` (name-free, 7 lines) [V], `dispatch_log.csv` |
| Archived outputs, manifests | E | `archive/*.csv` (11 manifests) [V] |
| Health checks | A | `i3_health()` returns data; `status.R` only prints |
| Scheduler state | E/A | `schtasks /Query` (read-only) |
| Manual execution of jobs | Restricted | Only the read-only `status` is safe. `weekly_run`, `valuation_run --capture`, `league_refresh` and `ops_setup --run-now` make network calls, commits or task changes: not UI-triggerable without approval |

## 4. Key blockers and recommendations

1. **CLI side effects (blocking for interactivity).** Each analyzer command writes a query JSON and appends
   `archive/league_query_manifest.csv`. Odds, lineup, waivers, rescore and the trade commands also write ledger
   records and `archive/decision_manifest.csv` (`scripts/trade_analyzer.R:358-370`, `R/valuation/ledger.R:22`) [V].
   There is no dry-run flag. → Build `ui/r/ui_adapter.R`, which calls the *core* functions directly and writes only to
   `data/archive/ui_cache/` [P]. No existing R code changes.
2. **Data freshness is manual.** Live league state depends on the owner running `league_refresh.R` (an ESPN request,
   X-022). The UI shows the snapshot age prominently and never refreshes on its own.
3. **Stdout prints names.** The UI must never scrape stdout. The adapter writes structured files; stdout and stderr
   are kept only for error diagnostics in the local UI.
4. **Sealed outcomes.** The research pages show methodology, registered results and development metrics only. No 2026
   realized-points joins.
5. **Thin history.** Odds and value timelines will look empty early. Label them as accruing.
