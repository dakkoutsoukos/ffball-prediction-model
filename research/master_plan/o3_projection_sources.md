# O3 / R4: Candidate additional projection sources (desk research)

**Status: research only. Nothing has been implemented, captured or downloaded. All ingestion waits on owner approval (O3, and O4 for the FantasyPros ECR archive).**
Date: 2026-10-14. Framing comes from `07_master_roadmap.md` (R4: capture-only in 2026–27, then a pre-registered prospective MSE test), `09_experiment_backlog.md` X19, and `06_data_infrastructure.md` rows 8–9. Paid sources stay excluded under the owner's standing rule (06 §"Explicitly excluded").

Evidence grades: **V** = verified this session from a primary page; **P** = carried over from the existing master-plan sources (`10_sources.md`); **U** = unverified (background knowledge, needs checking before any decision).

## 1. Recommendation

1. **Sleeper weekly projections (prospective capture), the first candidate for X19.** Sleeper is free, has its own JSON, and works at the same request scale as the ESPN capture (about one call per week). It is plausibly a different model from ESPN's. Its terms and provenance are the open questions, because the endpoint is undocumented (U).
2. **ffanalytics-style weekly scrape of 2–3 terms-permitting free sites** (candidates: NFL.com, CBS, FFToday; each site's terms still to be checked). Prospective only. The package README itself says "scraping historical periods will not be successful" (V).
3. **FantasyPros weekly ECR archive via `nflreadr::load_ff_rankings(type = "all")` (O4).** This is the only candidate with a point-in-time **historical** archive (V that the archive exists; start year and snapshot timing are U, and 06 says "about 2019, not verified"). It has **ranks, not points**, so it cannot go into an MSE average directly. It can be tested as a *rank-to-points residual feature* on ESPN, and that test can run now on dev seasons. Terms allow a personal single copy only (P).

Not recommended: anything paid (PFF, 4for4, ETR, RotoWire, prop histories), Yahoo (projections are partner-sourced and need login/OAuth, U), and nflverse `ff_opportunity`. `ff_opportunity`'s expected points are computed from the *realized* play-by-play of the same game, so it is a leakage hazard as a forecast and is usable only lagged (P/U). Vegas implied team totals (closing spread and total in nflverse schedules) are free and historical (U, columns to confirm). They are better treated as a *feature* (X22 / R-track) than as a "projection source".

### Leakage-safe test design (pre-register before any capture is used)
- **X19 (prospective):** freeze the combination rule now. Use an equal-weight mean of calibrated ESPN plus the k captured sources, with **no fitted weights**, because the forecast-combination literature favours equal weights when samples are small (the "forecast combination puzzle"; U for a specific citation in this repo). Capture is timestamped and hashed before kickoff (same protocol as the ESPN capture). Run 2027 as dev (coverage ≥ 90%, the join is debugged, and only the stopping/inclusion rules may be adjusted). Run 2028 as a sealed single check. Metric: weekly MSE by position, paired by player-week, with a block bootstrap over weeks. A source missing for a player-week falls back to ESPN-only for that row (pre-declared).
- **ECR residual test (historical, O4):** map weekly ECR rank to points with a per-position monotone map fitted on dev seasons only. Test whether `ESPN + β·(ECR-implied − ESPN)` lowers MSE. Use the dev seasons in the existing split. 2024 is the check year if it remains unspent; **2025 is spent** (progress log). Check snapshot timestamps first, because if ECR snapshots are taken after Tuesday they may still predate late-week news differently than ESPN does.

## 2. Comparison table

| Source | Historical PIT weekly? | Independence from ESPN | Terms | Cost | Accuracy evidence | Access | Volume |
|---|---|---|---|---|---|---|---|
| Sleeper projections | Uncertain. The endpoint accepts past season/week, but whether values are frozen pre-kickoff is unknown (U) | Probably its own/partner model (U) | Undocumented endpoint; public API docs cover league data only (U) | Free | None found | JSON `api.sleeper.app/projections/nfl/{season}/{week}` (U) | ~1 call/week |
| FantasyPros ECR (archive) | **Yes**, weekly archive via DynastyProcess (V); start year about 2019 (U) | Consensus of about 50 experts (P); ESPN analysts may be among them, so partly correlated | Personal single copy (P) | Free (archive) | Vendor contest grades ranks, not projections (P) | `nflreadr::load_ff_rankings` | 1 file |
| FantasyPros consensus projections | No (prospective) | Averages several sites, likely including ESPN (U), so it is correlated by construction | Personal single copy (P) | Free page; some features paid | Vendor-produced | HTML scrape (ffanalytics) | ~5 pages/week |
| NFL.com / NFL Fantasy | No | Separate model (U) | Check ToS (U) | Free | None found | ffanalytics scraper (V) | low |
| CBS | No | Separate (U) | Check ToS (U) | Free | None | ffanalytics (V) | low |
| FFToday | No | Separate (U) | Check ToS (U) | Free | None | ffanalytics (V) | low |
| numberFire / FanDuel Research | No | Separate (U) | Check ToS; the site has been restructured (U) | Free/partial | None | ffanalytics (V); breakage risk | low |
| FantasySharks, FFNerd, FleaFlicker, RTSports | No | Varies | Check each (U) | Free / API key | None | ffanalytics (V) | low |
| Yahoo | No | Partner-sourced (U) | Login/OAuth | Free | None | API + OAuth | — |
| PFF, 4for4, ETR, RotoWire | No (paid archives) | Separate | Paid | Paid (excluded) | Marketing only (P) | — | — |
| Props / Underdog / PrizePicks | Paid history only | Market-based, very independent | Paid / ToS restrictive | Excluded | Markets generally efficient (U) | — | — |
| Vegas team totals (nflverse schedules) | **Yes**, closing lines (U on columns/years) | Market-based | nflverse CC-BY (U) | Free | Strong as a matchup signal (U) | `nflreadr::load_schedules` | 1 file |
| nflverse `ff_opportunity` | Yes, but **post-hoc** | n/a | CC-BY (U) | Free | n/a, not a forecast | `nflreadr` | 1 file |

## 3. Per-source notes
- **ffanalytics** (https://github.com/FantasyFootballAnalytics/ffanalytics). Weekly scrapers: CBS, ESPN, FantasyPros, FantasySharks, FFToday, FleaFlicker, NumberFire, FantasyFootballNerd, NFL (V). No historical scraping (V). FFA's floors and ceilings measure *source disagreement*, not outcome uncertainty (P). Scrapers break as sites change, which is a maintenance cost.
- **FantasyPros ECR** (https://nflreadr.nflverse.com/reference/load_ff_rankings.html; https://github.com/dynastyprocess/data). Types are `draft`, `week` and `all` (V). The terms come from https://www.fantasypros.com/about/legal/ (P). The accuracy methodology grades rank slots, not projections (P: fantasypros.com/about/faq/football-inseason-accuracy-methodology).
- **Sleeper.** The public docs (https://docs.sleeper.com) cover users, leagues and players. The projections endpoint is community-documented only (U). Use in O5 is separate.
- **Incremental-value evidence.** 05_modeling_strategy cites season-long quantitative evidence for averaging and only qualitative weekly evidence [Petersen 2026] (P). No independent weekly study was found in this session. Vendor accuracy rankings are not evidence of MSE gains. The prior is a modest gain, which shrinks as sources share inputs (injury news, Vegas lines).

## 4. Open risks
- Terms: every non-FantasyPros site's ToS is unread. Personal-use restrictions must be honoured (no redistribution; keep data out of the repo if needed).
- Correlation: consensus feeds that include ESPN dilute the gain, so the test must name each source's inputs where they are known.
- Timing: snapshot times differ from the ESPN capture, so an inactive/news-timing advantage could masquerade as skill. Align on a common cutoff.
- Power: one prospective season (~17 weeks) may be too small to detect a small MSE gain. Pre-register the minimum detectable effect.
- Fragility: scrapers and undocumented endpoints can disappear mid-season, which would break the ≥ 90% coverage criterion.
- Budget: only 2 WebFetch calls were used in this session, and many cells are U. Verify them before any owner decision.
