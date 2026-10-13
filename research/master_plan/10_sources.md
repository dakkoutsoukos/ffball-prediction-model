# 10 — Sources and Evidence

*A traceable bibliography for the master plan. All sources were accessed on 2026-10-13 unless a date is
given. Keys match the citations used in documents 01–09.*

**Source type**

| Code | Meaning |
|---|---|
| **PR** | Peer-reviewed journal or conference |
| **PP** | Preprint |
| **TH** | Thesis or student paper |
| **TXT** | Open textbook |
| **DOC** | Documentation, code or data repository |
| **PRAC** | Practitioner analysis with a method described |
| **VEND** | Vendor analysis |
| **MKT** | Marketing or press release |
| **SEC** | Secondary source (e.g., an encyclopedia summary of a primary work) |

**Verification level**

| Code | Meaning |
|---|---|
| **F** | Fetched and read in this research (*F-abs* = abstract only) |
| **S** | Seen only in search results or a secondary listing |
| **U** | Not verified (cited only) |
| **V2** | Re-verified in the pass-2 direct-fetch check (§V) |

**Quality**

| Rating | Meaning |
|---|---|
| **High** | Strong methods, primary, peer-reviewed or code-verified |
| **Medium** | A credible method with limitations |
| **Low** | Weak method, vendor claim or tiny sample |

**Unsupported claims** are marked as such in the Quality column. No claim in this plan rests on a U-level source alone.

---

## A. Fantasy projections: accuracy, methods and published models

| Key | Source (author, date, title, venue) | URL | Finding used | Type · Verif. | Quality / limitations |
|---|---|---|---|---|---|
| Petersen 2017 | I. T. Petersen (Fantasy Football Analytics), 2017-03-19, "Who Has the Best Fantasy Football Projections? 2017 Update" | https://www.r-bloggers.com/2017/03/who-has-the-best-fantasy-football-projections-2017-update/ | Simple average beat every single source each year, 2012–2016 (5-yr R² .625, MASE .569 vs ESPN .564/.647). Accuracy weights ≈ simple mean. Over-projection of about 4–10 pts per season. | PRAC · F | Medium. Season-long; no significance tests; author runs a compared source |
| Petersen 2016a | Petersen, 2016-04-04, "Which are More Accurate: Rankings or Projections?" | https://fantasyfootballanalytics.net/2016/04/accuracy-of-rankings-vs-projections.html | Pooled R²: projections .53 vs ECR .27 vs ADP .23; the gap mostly vanishes within position | PRAC · F | Medium. 2015 only |
| Petersen 2016b | Petersen, 2016-03-12, "Who Has the Best Projections? 2016 Update" | http://www.r-bloggers.com/?p=117620 | Crowd beat each source, 2012–2015 | PRAC · F | Medium |
| Petersen 2026 | Petersen, v0.0.1 2026-10-08, *Fantasy Football Analytics: Statistics, Prediction, and Empiricism Using R* (CC BY 4.0; "a book in progress") | https://isaactpetersen.github.io/Fantasy-Football-Analytics-Textbook/ | Ch. 17: crowd-averaged projections are more accurate than individual sources "for both seasonal and weekly projections" (R² and MAE). Rarely above about two-thirds of variance explained. Over-prediction at high projections. Weekly stat-level R² example (yards .24–.42, TDs .00–.10). Chapters on simulation, MPT, decision-making. | TXT · F (partial), V2 | Medium. Weekly claim qualitative; book in progress |
| FFA 2019 | Fantasy Football Analytics, 2019, "2019 Projections Now Live!" | https://fantasyfootballanalytics.net/2019/07/2019-projections-now-live.html | Floors and ceilings are percentiles across sources; non-normal | PRAC · F | Medium. Disagreement is not outcome uncertainty |
| ffanalytics | FantasyFootballAnalytics, `ffanalytics` README and `calc_projections.R` | https://github.com/FantasyFootballAnalytics/ffanalytics | Scraper list; average, robust and weighted aggregation; `add_uncertainty`; hard-coded VOR baselines QB13/RB35/WR36/TE13/K8/DST3; "scraping historical periods will not be successful" | DOC · F | High (code) |
| FantasyPros n.d.-a | FantasyPros, "In-Season Accuracy Methodology" (undated, cites 2024) | https://fantasypros.com/about/faq/football-inseason-accuracy-methodology | Rank-slot → average-points scoring; half-PPR; union pool (top-N ECR ∪ top-N actual); weekly z-scores; worst week dropped from W8 | DOC · F | High as a description. **Grades ranks, not projections** |
| FantasyPros n.d.-b | FantasyPros, "Rest of Season Accuracy Methodology" | https://fantasypros.com/about/faq/football-rest-of-season-accuracy-methodology | Tuesday snapshots W2–16; 3-yr slot averages; weeks weighted by weeks remaining | DOC · F | High as a description |
| FantasyPros n.d.-c | FantasyPros support, "What is ECR and how do you calculate it?" | https://support.fantasypros.com/hc/en-us/articles/115001219327 | "Rank Points" aggregation; about 50 experts | DOC · S | Medium (403 on fetch) |
| 4for4 n.d. | 4for4, "Fantasy Football Accuracy" | https://www.4for4.com/fantasy-football/4for4-fantasy-football-accuracy | Accuracy marketing via FantasyPros awards; ranker no longer participates | MKT · F | Low (marketing) |
| Clay 2020 | M. Clay (ESPN), "50 things I learned doing 2020 projections" | https://africa.espn.com/ffl/story/_/id/28978349/ | Top-down process, team by team, "not automated"; league target split about RB 21 / TE 21 / WR 58 | PRAC · F | Medium (self-description) |
| Clay 2026 | M. Clay (ESPN), 2026-01-07, "xFP: 2025 leaderboard for QBs" | https://africa.espn.com/fantasy/football/story/_/id/46168860/2025-fantasy-football-expected-fantasy-points-xfp-qb | xFP method (opportunity only). Bio: "His projections power the ESPN Fantasy Football game" | PRAC · F | Medium |
| ESPN Press 2023 | ESPN Press Room, 2023-08-10, "ESPN Fantasy Football … new features for 2023" | http://espnpressroom.com/press-release/espn-fantasy-football-introducing-new-features-more-content-more-fun-for-2023/ | FantasyCast matchup win probability; IBM Trade Analyzer and Waiver Grades; custom dollar generator | MKT · F | Low (no method) |
| IBM 2025 | IBM Newsroom, 2025-09-24, "New IBM watsonx AI-powered insights … ESPN Fantasy Football 2025" | https://newsroom.ibm.com/2025-09-24-new-ibm-watsonx-ai-powered-insights-help-elevate-espn-fantasy-football-for-2025-fantasy-football-season | Waiver and Trade Grades, boom/bust probabilities; no accuracy reported | MKT · F | Low |
| Baughman et al. 2021a | A. Baughman et al., arXiv 2111.02874, 2021-11-04, "Deep AI for Fantasy Football Language Understanding" | https://arxiv.org/abs/2111.02874 | News NLP → boom/bust/injury classifiers (72%); regression ensemble *including ESPN projections* (RMSE 6.78, test 2017). No ESPN-only baseline; no calibration. | PP · F-abs | Medium. No baseline comparison |
| Jayanti 2026 | V. D. Jayanti, 2026, "Beyond the Expert: An Algorithmic Approach to Correcting Expert Bias in Fantasy Football Projections" | https://wsb.wharton.upenn.edu/wp-content/uploads/2026/05/Beyond-the-Expert_-An-Algorithmic-Approach-to-Correcting-Expert-Bias-in-Fantasy-Football-Projections_Jayanti.pdf | ESPN 2025 preseason projections beat a 1,933-feature component XGBoost on rank-MAE | TH · F | Low (student work; one season; rank metrics) |
| Cosico 2026 | E. Cosico, U. Oregon undergraduate thesis, "Fantasy Football Predictive Modeling" | https://scholarsbank.uoregon.edu/server/api/core/bitstreams/e2a8e28c-3788-4643-aea8-0b59ed1460ca/content | Sample filtered on a same-game snap threshold; ADP's negative correlation misread | TH · F | Low. Used as a **leakage example** |
| Williams 2026 | J. Williams Jr., Princeton ORFE thesis, 2026-04-09, "Inside the Huddle: Reproducing ESPN Player Projections Using Public Data" | https://theses-dissertations.princeton.edu/entities/publication/d6981488-f30c-47ce-8f06-b6c3e98f2578 | Claims to beat *raw* ESPN in 2025 (MAE 2.909 vs 3.074), crediting "will-they-play" and Vegas features | TH · F-abs | Low. FFball's code review of the associated public repo (`docs/prior_work.md`) found a target leak |
| Groos 2025 | D. Groos, arXiv 2508.09992, "OpenFPL" | https://arxiv.org/abs/2508.09992 | A public-data Fantasy Premier League model only *matched* a commercial service prospectively | PP · F-abs | Medium (other sport) |
| Lutz 2015 | R. Lutz, arXiv 1505.06918, "Fantasy Football Prediction" | https://arxiv.org/abs/1505.06918 | QB SVR/NN class project; MAE > 6; no benchmark | PP · F/S | Low |
| GWTTKB 2026 | GWTTKB, 2026-08-02, "What Actually Predicts Fantasy Football" | https://gwttkb.com/research/what-actually-predicts-fantasy-football.html | Line-implied PPR MAE 4.96 vs 5.54 (trailing 5-game); opponent PPR allowed +0.38 (WR); preseason 80% bands covered 87.9%; rookie ridge no better than naive | VEND · F | Low. Vendor; partly in-sample |
| Baldwin 2021 | B. Baldwin, Open Source Football, 2021-02-05, "nflfastR EP, WP, CP, xYAC and xPass models" | https://www.opensourcefootball.com/posts/2020-09-28-nflfastr-ep-wp-and-cp-models/ | Models fit and validated on 2006–2019, so in-sample through 2019; xPass calibration error 0.008 | DOC · F | High. Leakage tag source |
| Sydlowski & Ho n.d. | J. Sydlowski & T. Ho, `ffopportunity` | https://ffopportunity.ffverse.com ; https://github.com/ffverse/ffopportunity | xgboost xFP trained on 2006–2020; CC BY-SA; "experimental"; update cron | DOC · F | High (code). No validation published |
| mgcv docs | S. Wood, mgcv `family.mgcv` | https://stat.ethz.ch/R-manual/R-devel/library/mgcv/html/family.mgcv.html | Families: nb, ziP, ziplss, tw, twlss, gaulss, gammals, shash | DOC · F | High |
| Footballguys DFS | Footballguys, "Expectation and Variance" (DFS) | https://www.footballguys.com/article/DFS_expectationvariance | Floor near 0, right skew, spread grows with the projection | PRAC · S | Low–medium |
| Kuzmits & Adams 2008 | F. Kuzmits & A. Adams, *J Strength Cond Res* 2008, "The NFL combine: does it predict performance?" | https://pubmed.ncbi.nlm.nih.gov/18841077/ | Combine metrics predict weakly | PR · S | Medium |
| Teramoto et al. 2016 | M. Teramoto et al., *JSCR* 2016, combine predictive value for RB/WR | https://doi.org/10.1519/JSC.0000000000001202 | Weak prediction | PR · S | Medium |
| Lichtman 2009 | M. Lichtman, Hardball Times, 2009-12-21, "How do baseball players age? (Part 1)" | https://tht.fangraphs.com/how-do-baseball-players-age-part-1/ | Delta method and survivor bias | PRAC · F | Medium |
| Zimmerman 2021 | RotoWire (upd. 2021), "At What Age do Players Decline?" | https://www.rotowire.com/football/article/the-stats-room-at-what-age-do-players-decline-29538 | RB and WR efficiency peak around 25 | PRAC · F | Low (delta method; efficiency only) |
| Schuckers et al. 2023 | M. Schuckers, M. Lopez & B. Macdonald, *Annals of OR* 325:681–699 (arXiv 2110.14017) | https://arxiv.org/abs/2110.14017 | Imputing unobserved seasons reduces survivor bias (simulation, NHL) | PR · F/S | High (method); other sport |
| BtBS 2016 | Beyond the Box Score, 2016-01-14, projection-system review | https://www.beyondtheboxscore.com/2016/1/14/10733872/steamer-zips-pecota-marcel-projections-review | PECOTA not consistently better than Marcel | PRAC · S | Low–medium (baseball) |
| Duan et al. 2020 | T. Duan et al., ICML 2020, "NGBoost" | https://arxiv.org/abs/1910.03225 | Natural-gradient boosting for distributions | PR · F | High (method) |
| Meinshausen 2006 | N. Meinshausen, *JMLR* 7, "Quantile Regression Forests" | https://jmlr.org/papers/v7/meinshausen06a.html | Conditional quantiles from forests | PR · F | High (method) |
| Wang et al. 2023 | X. Wang, R. Hyndman, F. Li & Y. Kang, "Forecast combinations: an over 50-year review" (arXiv 2205.04216; IJF) | https://arxiv.org/abs/2205.04216 | Simple combinations are a strong default | PR/PP · F-abs | High |
| 4for4 defenses | 4for4, "Do Defenses Repeat Fantasy Football Performances?" (2025, 2026 editions) | https://www.4for4.com/2026/preseason/do-defenses-repeat-fantasy-football-performances | Year-over-year persistence of points allowed by position r ≈ .16 (TE) to .27 (QB) | PRAC · S | Low–medium |
| FantasyLabs Vegas | FantasyLabs, "Model Building with Ian: Vegas Score" | https://www.fantasylabs.com/articles/model-building-with-ian-vegas-score/ | WR Vegas effects mostly noise | PRAC · S | Low |
| PLOS 2025 | PLOS ONE 2025, "Goal-line oracles" (crowd forecasts, EPL) | https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0312487 | Crowds beat individuals | PR · S | Medium (other sport) |
| EJOR 2021 | *EJOR* 2021, expert performance and crowd wisdom (EPL) | https://www.sciencedirect.com/science/article/pii/S037722172030480X | Former professionals beat laypeople | PR · S | Medium (other sport) |

## B. Player metrics and stability

| Key | Source | URL | Finding used | Type · Verif. | Quality / limitations |
|---|---|---|---|---|---|
| Hoopes 2024a | S. Hoopes (4for4), 2024-07-08, "The Most Predictable WR Stats" | https://www.4for4.com/2024/preseason/most-predictable-wide-receiver-stats | WR targets/g YoY .70 (next PPG .62); EPA/target .18; TD rate .19; TPRR .64; YPRR .56 (next .59); aDOT .65 (next .07) | PRAC · F | Medium. Survivor filter (≥ 30 targets in both seasons); season-level |
| Hoopes 2024b | Hoopes, 2024-07-03, "The Most Predictable RB Stats" | https://www.4for4.com/2024/preseason/most-predictable-running-back-stats | Receptions/g .70; routes/g .64; rush att/g .61; RYOE/att .33 (next .18); TD rate .05 | PRAC · F | Medium |
| Hoopes 2024c | Hoopes, 2024-07-01, "The Most Predictable QB Stats" | https://www.4for4.com/2024/preseason/most-predictable-quarterback-stats | Rush att/g .89 (next .47); CPOE .42 (next .13); EPA/dropback .50 (next .33) | PRAC · F | Medium |
| Hernandez 2023 | 4for4, 2023-07-20, "Most Predictable WR Stats" | https://www.4for4.com/2023/preseason/most-predictable-wide-receiver-stats | Targets/g .66; target share .55; Y/T .22; TD rate .12 | PRAC · F | Medium |
| Stuart 2014 | C. Stuart, Football Perspective, 2014-07-21, "YPRR, Yards per Target, and TPRR" | https://www.footballperspective.com/yards-per-route-run-yards-per-target-and-targets-per-route-run/ | TPRR R² .41; YPRR .21; Y/T .08 (2007–12, n = 344) | PRAC · F | Medium (PFF data; survivorship acknowledged) |
| Tuccitto 2017 | D. Tuccitto, Footballguys, 2017-08-24, "True Fantasy Points: WR" | https://footballguys.com/article/tuccittotfp0wr2017 | Stabilisation: receptions/route ≈ 188 routes; YPRR ≈ 351; TD/route ≈ 882 | PRAC · F | Medium (method not fully stated) |
| Burke 2022 | B. Burke (ESPN), 2022-09-28, "Receiver tracking metrics" | https://africa.espn.com/nfl/story/_/id/34649390/ | Open .61, Catch .38, YAC .35 year over year; described as descriptive | VEND · F | Medium |
| Vabishchevich 2024 | P. Vabishchevich (SumerSports), 2024-06-04, "Cutting Through Noise to Increase CPOE Stability" | https://sumersports.com/the-zone/cutting-through-noise-to-increase-cpoe-stability/ | CPOE r .46 → .51 after filtering | PRAC · F | Medium (small sample) |
| Fantasy Points 2023 | Fantasy Points newsletter, 2023-07-30, first-read target share | https://newsletter.fantasypoints.com/p/finding-stud-wrs-first-read-target-share | YoY .78; next FPG .79 | VEND · F | Low (proprietary; short sample) |
| Irby 2025 | M. Irby (Legendary Upside), 2025-07-10, "Overlooked Stats" | https://www.legendaryupside.com/overlooked-stats-being-prioritized-in-an-offense-as-it-turns-out-may-be-meaningful/ | First-read share r .694 with next PPR | PRAC · F (partial) | Low |
| Gretch 2019 | B. Gretch (CBS), 2019-08-05, air yards research process (secondary on Hermsmeyer) | https://www.cbssports.com/fantasy/football/news/2019-fantasy-football-draft-prep-how-should-i-use-air-yards-in-my-research-process/ | Targets plus air yards beat targets alone; YAC not predictive once depth is controlled | PRAC (SEC) · F | Medium |
| Winks 2020 | H. Winks (NBC/Rotoworld), 2020-12-30, "Fantasy Usage Model 2020 recap" | https://www.nbcsports.com/fantasy/football/news/article-fantasy-usage-model-expected-ppr-points-2020-recap | Expected PPR predicts future points better than actual PPR | PRAC · F (partial) | Low–medium (self-assessment) |
| Franks et al. 2016 | A. Franks, A. D'Amour, D. Cervone, L. Bornn, "Meta-Analytics" (JQAS) | https://arxiv.org/abs/1609.09830 | Stability, discrimination and independence of metrics | PR · S | High (method) |
| FP xTD 2023 | Fantasy Points, 2023, "XTD touchdown regression candidates" | https://fantasypoints.com/nfl/articles/2023/xtd-touchdown-regression-candidates | xTD stickier (r² .382 vs .276) but next-year TDs .283 vs .275 | VEND · S | Low (paywalled) |
| FFers xFP 2024 | The Fantasy Footballers, "Expected Fantasy Points: 2024 regression candidates" | https://www.thefantasyfootballers.com/analysis/expected-fantasy-points-2024-wr-regression-candidates-fantasy-football/ | Fantasy points over expectation regresses for 67–74% of players | PRAC · S | Low |
| nflreadr docs | nflverse, nflreadr reference and the data-schedule article | https://nflreadr.nflverse.com/articles/nflverse_data_schedule.html ; https://nflreadr.nflverse.com/reference/index.html | Update timing; FTN (≤ 48 h; `read_thrown` 2023+); participation after the postseason; NGS thresholds and week-0 overwrite; PFR advanced 2018+ | DOC · F | High |

## C. Valuation, trades and league simulation

| Key | Source | URL | Finding used | Type · Verif. | Quality / limitations |
|---|---|---|---|---|---|
| Bryant 2016 | J. Bryant (Footballguys), 2016-05-13, "Principles of Value Based Drafting" | https://www.footballguys.com/article/bryant_vbd | VBD introduced 1996; pick-100 baseline; strict VBD abandoned after about pick 120 | PRAC · F | Medium |
| Stuart 2013 | C. Stuart (Footballguys), 2013-06-09, "Expected VBD" | https://footballguys.com/article/stuart_expected_vbd_by_adp | Value = E[max(0, X − R)]; backups' value "is not zero"; proposes championship win-probability added | PRAC · F | Medium (strong logic) |
| Bales 2013 | J. Bales (RotoWire), 2013-07-08, "VBD, Baseline Players and Draft Strategy" | https://www.rotowire.com/football/article/according-to-the-data-vbd-baseline-players-and-draft-strategy-17864 | "The baseline is a moving target" | PRAC · F | Medium |
| FantasyPros VBD | FantasyPros support, "What is value-based drafting?" | https://support.fantasypros.com/hc/en-us/articles/115005868747 | VORP / VONA / VOLS definitions | DOC · S | Medium (403) |
| Henderson 2019 | J. Henderson (FantasyPros), 2019-08-16, "Introducing Fantasy Football WAR" | https://www.fantasypros.com/2019/08/introducing-fantasy-football-wins-above-replacement-war-2019-fantasy-football/ | Normal team score, mean 108.43, SD 20.9 (12-team standard scoring, 2018) | PRAC · F | Low–medium. Treats own score as known |
| Dynasty Nerds 2020 | Dynasty Nerds, 2020-03-18, "Fantasy Football WAR: The Theory" | https://www.dynastynerds.com/analytics/fantasy-football-wins-above-replacement-the-theory/ | Mean 116.92, SD 21.66 (half-PPR 2019) from summed positional SDs | PRAC · F | Low. Summing SDs implies perfect correlation |
| Fantasy Footballers 2022 | The Fantasy Footballers, 2022-04-11, "On the WARpath" | https://www.thefantasyfootballers.com/articles/on-the-warpath-understanding-performance-above-replacement-fantasy-football/ | Diminishing returns; a normal model overvalues booms | PRAC · F | Low–medium |
| Ho n.d. | T. Ho (ffverse), `ffsimulator` (docs, manual, source) | https://ffsimulator.ffverse.com/ ; https://github.com/ffverse/ffsimulator | Season rank draw N(ECR, SD/2); rank-bucket bootstrap; hindsight lineups × efficiency N(0.775, 0.05); `ff_wins_added` (experimental) removes a player and re-simulates; archived from CRAN 2024-02-27 | DOC · F, V2 | High (code). Design flaws noted |
| Carl & Sharpe n.d. | S. Carl & L. Sharpe (nflverse), `nflseedR` 2.x | https://nflseedr.com/ ; https://nflseedr.com/articles/nflsim2.html ; https://github.com/nflverse/nflseedR | `nfl_simulations()`; `compute_results(teams, games, week_num, …)` returns updated tables; chunks; L'Ecuyer-CMRG seeds; tiebreakers; outputs by game, team and simulation | DOC · F, V2 | High |
| KTC | KeepTradeCut, FAQ and "About Player Values" | https://keeptradecut.com/frequently-asked-questions ; https://keeptradecut.com/about/player-values | Keep/Trade/Cut votes via "an adapted ELO algorithm"; tradesourced values; 1QB/SF databases; package value adjustment | DOC · F | Medium (self-described) |
| FantasyCalc API | FantasyCalc, values API | https://api.fantasycalc.com/values/current?isDynasty=false&numQbs=1&numTeams=12&ppr=1 | Fields (value, redraftValue, trend30Day, maybeMovingStandardDeviation…). The trade-derived method is **not documented** | DOC · F | Low (method unverified) |
| DynastyProcess calc | DynastyProcess, `apps-calculator` (`R/values.R`) | https://github.com/dynastyprocess/apps-calculator | value = round(10500·exp(−(f/10000)·ecr)), f = 235; future picks ×0.8 per year | DOC · F | High (code) |
| DynastyProcess data | DynastyProcess, `data` repository (GPL-3.0) | https://github.com/dynastyprocess/data | values.csv; FantasyPros ECR history (`db_fpecr`); player-ID crosswalk; weekly GitHub Actions | DOC · F | High |
| Baughman et al. 2021b | A. Baughman et al. (IBM), arXiv 2111.02859, "Large Scale Diverse Combinatorial Optimization: ESPN Fantasy Football Player Trades" | https://arxiv.org/abs/2111.02859 | Personalised values; cosine-dissimilarity team pairing; 0–1 knapsack; expert review 76.9% → 97.3% "high-quality" | PP · F-abs | Medium. Not validated by acceptance or outcomes |
| Parshall et al. 2025 | Parshall, Ali & Zimmerman, arXiv 2511.17535, "A Genetic Algorithm for Optimizing Fantasy Football Trades with Playoff Biasing" | https://arxiv.org/abs/2511.17535 | GA with playoff-week weighting; one league; both sides about +3 pts per week | PP · F-abs | Low (one league) |
| Draft Sharks KB | Draft Sharks, Trade Analyzer and Injury Predictor knowledge-base pages | https://www.draftsharks.com/kb/fantasy-football-trade-analyzer ; https://www.draftsharks.com/kb/injury-predictor | Both teams, next week + ROS; injury model with 80% CI on games missed (anecdotal validation) | DOC/MKT · F | Low–medium |
| Chandrakumaran et al. 2024 | Chandrakumaran, Larkin, McIntosh & Robertson, *PLOS ONE* 2024-03-14, "Compounding endowment effects when trading draft picks in the AFL" | https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0300546 | Endowment-like retention (log-rate 0.269; 905 draftees, 2003–2016) | PR · F | Medium (observational; other sport) |
| KKT 1990 | Kahneman, Knetsch & Thaler (1990), *JPE* 98(6):1325–1348, via an encyclopedia summary | https://en.wikipedia.org/wiki/Endowment_effect | Willingness to accept ≈ 2× willingness to pay (mugs) | SEC · F | High (primary is classic); fantasy transfer unknown |
| Massey & Thaler 2013 | C. Massey & R. Thaler, "The Loser's Curse", *Management Science* | (cited in Chandrakumaran et al. 2024) | NFL teams overvalue draft picks | PR · S (secondary) | High (primary) |
| Roth et al. 2004 | A. Roth, T. Sönmez & U. Ünver, "Kidney Exchange", *QJE* 119(2):457–488 (NBER WP 10002) | https://www.nber.org/papers/w10002 | Top trading cycles and chains | PR · F-abs | High; transfer to fantasy weak |
| Shapley & Scarf 1974 | L. Shapley & H. Scarf, *J Math Econ* 1(1):23–37 | https://jmvidal.cse.sc.edu/lib/shapley74a.html ; https://en.wikipedia.org/wiki/Top_trading_cycle | Core, strategy-proof allocation for single indivisible goods | PR · S/SEC | High (theory) |
| Nash 1950 | J. Nash, "The Bargaining Problem", *Econometrica* 18(2):155–162, via an encyclopedia summary | https://en.wikipedia.org/wiki/Cooperative_bargaining | Maximise the product of gains | SEC · F | High (theory) |
| Bergman et al. 2021 | Bergman, Cardonha, Imbrogno & Lozano, arXiv 2112.07002 | https://arxiv.org/abs/2112.07002 | Multivariate Gaussian DFS entries; NP-hard; positive returns 2018–19 | PP · F-abs | Medium |
| Getty et al. 2018 | Getty, Li, Yano, Gao & Hosoi, "Luck and the Law", *SIAM Review* 60(4):869–887 | https://dspace.mit.edu/handle/1721.1/119466 | Fantasy sports sit near professional sports on a skill–luck spectrum | PR · F (record), S (findings) | High |
| uberfastman | uberfastman, `fantasy-football-metrics-weekly-report` (GPL-3.0) | https://github.com/uberfastman/fantasy-football-metrics-weekly-report | Monte Carlo playoff probabilities across hosts; score model undocumented | DOC · F | Medium |

## D. Decisions: lineups, waivers/FAAB, drafts

| Key | Source | URL | Finding used | Type · Verif. | Quality / limitations |
|---|---|---|---|---|---|
| Haugh & Singal 2021 | M. Haugh & R. Singal, "How to Play Fantasy Sports Strategically (and Win)", *Management Science* 67(1):72–92, DOI 10.1287/mnsc.2019.3528 (SSRN 10.2139/ssrn.3393127) | https://pubsonline.informs.org/doi/10.1287/mnsc.2019.3528 ; slides: https://cfe.columbia.edu/sites/default/files/content/slides/How%20to%20Play%20Fantasy%20Sports%20Strategically%20(and%20Win).pdf | Double-up and top-heavy payoffs; mean–variance formulation; binary QPs; Dirichlet regression of opponents; 2017 NFL DFS. **Slides:** >350% ROI over 17 weeks. The ~50% benchmark figure is snippet-only. | PR · V2 (Crossref abstract), slides F | High. Full text 403; no arXiv version; DFS, not season-long |
| Hunter et al. 2016 | D. Hunter, J. P. Vielma & T. Zaman, arXiv 1604.01455 (v3 2019), "Picking Winners in Daily Fantasy Sports Using Integer Programming" | https://arxiv.org/abs/1604.01455 | Maximise mean subject to a variance lower bound and an overlap cap; 38 hockey DFS contests | PP · F | Medium. DFS hockey |
| Becker & Sun 2016 | A. Becker & X. A. Sun, *JQAS* 12(1):17–30, "An analytical approach for fantasy football draft and lineup management" | https://ideas.repec.org/a/bpj/jqsprt/v12y2016i1p17-30n1.html ; https://www.amstat.org/asa/files/pdfs/pressreleases/press_release_JQAS_fantasy_football.pdf | MIP for draft plus lineups; trained 2004–06, simulated 2007–08; claims an edge | PR · F-abs | Medium. Effect size unverified |
| Fry et al. 2007 | M. Fry, A. Lundberg & J. Ohlmann, *JQAS* 3(2), DOI 10.2202/1559-0410.1050, "A Player Selection Heuristic for a Sports League Draft" | https://emunix.emich.edu/~aross15/math319/player-selection-heuristic-sports-league-draft.pdf | Deterministic DP anticipating opponents via ADP; better on average and more robust in simulation | PR · F (full) | Medium (2005 data) |
| Lee & Liu 2022 | Lee & Liu, *Judgment and Decision Making* 17(4):691–719, "Drafting strategies in fantasy football …" | https://dlab.sauder.ubc.ca/sjdm/journal/22/220318/jdm220318.html | 1,350 Sleeper leagues (2017), 12,590 teams. ADP vs points r −.56 (RB), −.55 (WR). QB/K/DEF herding. Handcuffs 51.04% vs 50.56% (BF 4.2 for no difference). Following a QB pick: no effect (BF 4.7). | PR · F, V2 | High (one season, one platform) |
| Mlčoch & Hubáček 2023 | Mlčoch & Hubáček, *ITOR*, "Competing in daily fantasy sports using generative models" | https://doi.org/10.1111/itor.13344 | 34% ROI over 8 weeks (DFS) | PR · F-abs | Medium (DFS) |
| Rosenof 2023 / 2024 | Z. Rosenof, arXiv 2307.02188 and 2409.09884 (fantasy basketball) | https://arxiv.org/abs/2307.02188 ; https://arxiv.org/abs/2409.09884 | Dynamic, draft-state-aware valuation beats static lists in simulation | PP · F-abs | Low–medium (other game) |
| Maniezzo & Aspee Encina 2022 | *Operations Research Forum*, "Predictive Analytics for Real-time Auction Bidding Support: a Case on Fantasy Football" | https://doi.org/10.1007/s43069-022-00160-w | Auction bidding support; simulated validation | PR · F-abs | Low. Sport unverified |
| Braun n.d. | N. Braun, "Fantasy Math" | https://nathanbraun.com/fantasymath/ | Correlated-simulation tool author calls the lineup edge "small"; decisions driven by the scale parameter | PRAC/MKT · F | Low |
| Kartes 2024 | J. Kartes (FFA), 2024-09-22, "Fantasy Football Projections and Uncertainty" | https://fantasyfootballanalytics.net/2024/09/fantasy-football-projections-and-uncertainty.html | Low-uncertainty starters for favourites, high for underdogs (uncertainty = source disagreement) | PRAC · F | Low (unvalidated) |
| alhart2015 2026 | alhart2015, GitHub issue #188, 2026-09-15/16 | https://github.com/alhart2015/FantasyFootball/issues/188 | **0 of 208 team-weeks** where the win-probability lineup differed from the EV lineup (16 teams, top-half bonus, 60k sims, common random numbers, paired SE ≈ 0.003); closed by a pre-registered < 5% disagreement rule | DOC (hobbyist) · F, V2 | Medium (one league; careful design) |
| Huntington 2026 | T. Huntington (RotoWire), 2026-09-03, "Does Stacking Work in Fantasy Football?" | https://www.rotowire.com/football/article/does-stacking-work-in-fantasy-football-what-four-years-of-data-say-about-drafting-correlated-players-2026-131409 | Full-PPR weekly correlations, 2022–25: QB–top WR +.31; QB–TE +.27; QB–RB +.07; WR–WR −.02; stack about 14% more boom-or-bust | PRAC · F | Medium (unconditional; post-hoc roles) |
| Winks 2022 | H. Winks (Underdog), 2022-07-10, "Correlation At Ceiling Outcomes" | https://underdognetwork.com/football/best-ball-research/correlation-at-ceiling-outcomes-between-teammates-and-their-opponents | Conditional correlations (WR1–WR2 +.16, RB1–WR2 −.11) | PRAC · F | Low–medium (conditioning on high scores) |
| Beimfohr 2025 | E. Beimfohr (Spike Week), 2025-09-21, "Visualizing Single Game Correlation" | https://spikeweek.com/visualizing-single-game-correlation/ | Single-game correlations (inflated) | PRAC · F | Low |
| Subvertadown 2022a | Subvertadown, "Pairing/Stacking Analysis" | https://subvertadown.com/article/pairing-stacking-analysis-correlations-between-the-different-fantasy-positions | Signs: QB–WR strongest, QB–TE next, RB–WR negative, K–D/ST positive | PRAC · F | Medium |
| Subvertadown 2022b | Subvertadown, "Is QB Really More Predictable Than D/ST?" | https://subvertadown.com/article/is-qb-really-more-predictable-than-d-st- | QB RMS 8.0 → 7.5 after projections; correlation ≈ .35 (QB, D/ST); D/ST tracks the opponent offence | PRAC · F | Medium (self-reported) |
| Subvertadown 2022c | Subvertadown, "Fantasy Score Distributions: point vs error distributions" | https://subvertadown.com/article/fantasy-score-distributions-point-distributions-vs-error-distributions | Distribution shapes | PRAC · F | Medium |
| Subvertadown 2026 | Subvertadown, "Final Accuracy Report 2025" (2026-01-07) and "Accuracy Report #1: Weeks 1–4, 2026" | https://subvertadown.com/article/final-accuracy-report-2025 ; https://subvertadown.com/article/accuracy-report-1-weeks-1---4-2026 | The most transparent commercial self-evaluation found; K correlation ≈ .10 | PRAC · F | Medium (self-reported) |
| Solow 2026 | B. Solow (Pitcher List), 2026-02-23, "Auction Theory for Fantasy Baseball" | https://pitcherlist.com/auction-theory-for-fantasy-baseball/ | "Bidding your value in an SBFP auction guarantees you cannot get any positive return"; winner's curse | PRAC · F | Medium (theory applied) |
| FF Beacon 2026 | FF Beacon, "FAAB Calculator / FAAB Bid Data" (upd. 2026-10-08) | https://ffbeacon.com/tools/faab | 60,421 winning bids from 1,003 Sleeper leagues (2023–26); 72% single bidder; medians by number of bidders, week and position | VEND · F | Low–medium (selection undisclosed; dynasty-heavy) |
| STACKED 2026 | STACKED, 2026-08-12, "How Far Do Players Actually Fall Past ADP?" | https://www.stackedfantasy.com/blog/how-far-players-fall-past-adp | σ ≈ 2.25 + 0.11·pick, skewed; QB/TE wider (21,893 Sleeper 12-team drafts) | VEND · F | Medium (one platform and season) |
| Winks 2025 | H. Winks (Underdog), 2025-06-28, Zero RB analysis | https://underdognetwork.com/football/best-ball-research/dont-be-dumb-when-you-draft-a-zero-rb-team-in-2025 | Best-ball construction results; crowding | PRAC · F | Low (does not transfer to H2H) |
| Strachan 2024 | T. Strachan (FantasyPros), 2024-02-16, Hero RB strategy | https://www.fantasypros.com/2024/02/hero-rb-best-ball-draft-strategy-2024-fantasy-football/ | Advance rates vary by year | PRAC · F | Low |
| Footballers flex | The Fantasy Footballers, "How to Flex" | https://www.thefantasyfootballers.com/articles/fantasy-football-flex-strategies/ | Put the latest-kickoff player in FLEX | PRAC · S | Medium (logic) |
| CRAN TV Optimization | F. Schwendinger & H. Borchers, CRAN Task View: Optimization, 2026-09-23 | https://cran.r-project.org/web/views/Optimization.html | HiGHS "currently among the best open source" MILP solvers; QP without integers only | DOC · F | High |
| highs / ompr | CRAN pages for `highs` (1.14.0-2) and `ompr` (1.0.4) | https://cran.r-project.org/package=highs ; https://cran.r-project.org/package=ompr | Solver interfaces | DOC · F | High |
| ffscrapr | T. Ho, `ffscrapr` docs (incl. `ff_transactions`, ESPN basics) | https://ffscrapr.ffverse.com/ | Multi-host league access; ESPN private-league support | DOC · F, V2 | High (CRAN copy dated 2023) |

## E. Forecast evaluation and statistical methodology

| Key | Source | URL | Finding used | Type · Verif. | Quality |
|---|---|---|---|---|---|
| Gneiting & Raftery 2007 | T. Gneiting & A. Raftery, *JASA* 102(477):359–378, "Strictly proper scoring rules, prediction, and estimation" | https://sites.stat.washington.edu/raftery/Research/PDF/Gneiting2007jasa.pdf | CRPS is proper and generalises absolute error; interval score | PR · F | High |
| Gneiting, Balabdaoui & Raftery 2007 | *JRSS-B* 69(2):243–268, "Probabilistic forecasts, calibration and sharpness" | https://sites.stat.washington.edu/people/raftery/Research/PDF/Gneiting2007jrssb.pdf | "Maximise sharpness subject to calibration"; PIT | PR · S | High |
| Gneiting 2011 | T. Gneiting, *JASA* 106:746–762, "Making and evaluating point forecasts" (arXiv 0912.0902) | https://arxiv.org/abs/0912.0902 | Consistent for the mean iff Bregman; for a quantile iff generalised piecewise linear; mismatch "can lead to grossly misguided inferences" | PR · F, V2 | High |
| Ehm et al. 2016 | Ehm, Gneiting, Jordan & Krüger, *JRSS-B* 78:1–29, "Of quantiles and expectiles" (Murphy diagrams) | https://arxiv.org/abs/1503.08195 | Consistent scores are mixtures of elementary scores | PR · S | High |
| Czado et al. 2009 | Czado, Gneiting & Held, *Biometrics* 65(4):1254–1261 | https://doi.org/10.1111/j.1541-0420.2009.01191.x | PIT for count data (randomised PIT) | PR · S | High |
| Dimitriadis et al. 2021 | Dimitriadis, Gneiting & Jordan, *PNAS* 118:e2016191118, "Stable reliability diagrams for probabilistic classifiers" | https://arxiv.org/abs/2008.03033 | CORP reliability diagrams (isotonic, PAV) and decomposition | PR · F | High |
| Arnold et al. 2024 | Arnold, Walz, Ziegel & Gneiting, *EJS* 18(2):4992–5044, "Decompositions of the mean CRPS" | https://doi.org/10.1214/24-EJS2316 | Isotonic MCB/DSC/UNC decomposition | PR · S | High |
| Scheuerer & Hamill 2015 | *MWR* 143(4):1321–1334, "Variogram-based proper scoring rules" | https://repository.library.noaa.gov/view/noaa/22327 | Energy score weak on dependence; variogram score better | PR · S | High |
| Alexander et al. 2021 | Alexander, Coulon, Han & Meng, arXiv 2101.12693 | https://arxiv.org/abs/2101.12693 | Variogram (p = 0.5) beat energy score in simulations | PP · F | Medium |
| Ziel & Berk 2019 | F. Ziel & K. Berk, arXiv 1910.07325 | https://arxiv.org/abs/1910.07325 | Energy score "performs comparably well … also regarding dependencies" (contrary view) | PP · F | Medium |
| Jordan et al. 2019 | Jordan, Krüger & Lerch, *JSS* 90(12), `scoringRules` | https://doi.org/10.18637/jss.v090.i12 | R implementation | PR · S | High |
| Allen (JSS 110(8)) | S. Allen, "Weighted scoringRules", *JSS* 110(8) | https://doi.org/10.18637/jss.v110.i08 | Threshold-weighted scores in R | PR · S | High |
| Diebold 2015 | F. Diebold, *JBES* 33(1), "Comparing predictive accuracy, twenty years later" | https://www.nber.org/papers/w18391 | DM test compares forecasts, not models; pseudo-out-of-sample is not an overfitting guard | PR · S | High |
| Harvey et al. 1997 | Harvey, Leybourne & Newbold, *IJF* 13(2):281–291 | https://iaorifors.com/paper/20644 | Small-sample DM correction | PR · S | High |
| Coroneo & Iacone 2020 | *J Applied Econometrics* 35(4) | https://eprints.whiterose.ac.uk/155897 | Fixed-smoothing asymptotics for short samples | PR · S | High |
| Giacomini & White 2006 | *Econometrica* 74(6):1545–1578, "Tests of conditional predictive ability" | https://econometricsociety.org/publications/econometrica/2006/11/01/tests-conditional-predictive-ability | Assumes rolling windows (FFball uses expanding windows) | PR · S | High |
| Hansen et al. 2011 | Hansen, Lunde & Nason, *Econometrica* 79(2):453–497, "The model confidence set" | https://search.r-project.org/CRAN/refmans/MCS/html/MCS-package.html | MCS instead of pairwise winners | PR · S | High |
| Cameron et al. 2008 | Cameron, Gelbach & Miller, *REStat* 90(3):414–427 | https://www.nber.org/papers/t0344 | Cluster-robust tests over-reject with 5–30 clusters; bootstrap-t | PR · S | High |
| Choe & Ramdas 2024 | Y. J. Choe & A. Ramdas, "Comparing Sequential Forecasters", *Operations Research* (DOI 10.1287/opre.2021.0792) | https://arxiv.org/abs/2110.00115 | Anytime-valid confidence sequences and e-processes for forecast comparison; bounded scores | PR · F, V2 | High |
| Henzi & Ziegel 2022 | *Biometrika* 109(3):647–663 | https://arxiv.org/abs/2103.08402 | E-values for comparing probability forecasts | PR · S | High |
| Arnold, Henzi & Ziegel 2023 | *AoAS* 17(3):1909–1935 | https://doi.org/10.1214/22-AOAS1697 | Sequentially valid calibration tests | PR · S | High |
| Arnold et al. (SMCS) | Arnold, Gavrilopoulos, Schulz & Ziegel, "Sequential model confidence sets" | https://arxiv.org/abs/2404.18678 | Sequential MCS | PP/PR · S | High |
| Ramdas et al. 2023 | Ramdas, Grünwald, Vovk & Shafer, *Stat Sci* 38(4) | https://doi.org/10.1214/23-STS894 | Game-theoretic statistics; safe anytime-valid inference | PR · S | High |
| Grünwald et al. 2024 | Grünwald, de Heide & Koolen, *JRSS-B* 86(5):1091–1128, "Safe testing" | https://research.vu.nl/en/publications/safe-testing-2/ | E-values multiply across studies and seasons | PR · S | High |
| Benavoli et al. 2017 | *JMLR* 18(77), "Time for a change" | https://www.jmlr.org/papers/v18/16-305.html | Bayesian comparison; ROPE | PR · S | High |
| Tashman 2000 | *IJF* 16(4):437–450 | https://ideas.repec.org/a/eee/intfor/v16y2000i4p437-450.html | Rolling-origin evaluation | PR · S | High |
| Bergmeir & Benítez 2012 | "On the use of cross-validation for time series predictor evaluation" | https://research.monash.edu/en/publications/on-the-use-of-cross-validation-for-time-series-predictor-evaluati/ | Blocked CV | PR · S | High |
| Bergmeir et al. 2018 | Bergmeir, Hyndman & Koo, *CSDA* 120:70–83 | https://ideas.repec.org/a/eee/csdana/v120y2018icp70-83.html | K-fold valid only for pure AR | PR · S | High |
| Kapoor & Narayanan 2023 | *Patterns* 4(9):100804, "Leakage and the reproducibility crisis in ML-based science" | https://pmc.ncbi.nlm.nih.gov/articles/PMC10499856 | 8-type leakage taxonomy; 294 papers affected | PR · F | High |
| Dwork et al. 2015 | Dwork, Feldman, Hardt, Pitassi, Reingold & Roth, *Science* 349(6248):636, "The reusable holdout" | https://cis.upenn.edu/~aaroth/reusable.html | Adaptive reuse can manufacture accuracy; Thresholdout | PR · F | High |
| Roelofs et al. 2019 | *NeurIPS* 32, meta-analysis of overfitting | https://papers.nips.cc/paper/9117-a-meta-analysis-of-overfitting-in-machine-learning | Little adaptive overfitting on Kaggle | PR · S | High |
| Clemen 1989 | *IJF* 5(4):559–583, "Combining forecasts" | https://people.duke.edu/~clemen/bio/Published%20Papers/13.CombiningReview-Clemen-IJOF-89.pdf | Simple combinations are robust | PR · S | High |
| Claeskens et al. 2016 | *IJF* 32(3):754–762, "The forecast combination puzzle" | https://research.vu.nl/en/publications/the-forecast-combination-puzzle-a-simple-theoretical-explanation-2/ | Estimated weights add variance | PR · S | High |
| Yao et al. 2018 | Yao, Vehtari, Simpson & Gelman, *Bayesian Analysis* 13(3) | https://arxiv.org/abs/1704.02030 | Stacking of predictive distributions | PR · S | High |
| Gneiting et al. 2005 | Gneiting, Raftery, Westveld & Goldman, *MWR* 133:1098–1118 (EMOS) | https://sites.stat.washington.edu/raftery/Research/PDF/gneiting2005.pdf | Minimum-CRPS calibration of ensemble forecasts | PR · S | High (weather) |
| Raftery et al. 2005 | Raftery, Gneiting, Balabdaoui & Polakowski, *MWR* 133:1155–1174 (BMA) | https://heibib.ub.uni-heidelberg.de/search/Record/1428576878 | BMA calibration | PR · S | High (weather) |
| Henzi et al. 2021 | Henzi, Ziegel & Gneiting, *JRSS-B*, "Isotonic distributional regression" | https://doi.org/10.1111/rssb.12450 | Nonparametric calibrated benchmark | PR · S | High |
| Gibbs & Candès 2021 | *NeurIPS*, "Adaptive conformal inference under distribution shift" | https://arxiv.org/abs/2106.00170 | Long-run coverage under shift | PR · F | High |
| Barber et al. 2023 | Barber, Candès, Ramdas & Tibshirani, *Ann Stat* 51(2) | https://arxiv.org/abs/2202.13415 | Conformal beyond exchangeability | PR · S | High |
| Romano et al. 2019 | Romano, Patterson & Candès, *NeurIPS* 32, CQR | https://arxiv.org/abs/1905.03222 | Conformalised quantile regression | PR · F | High |
| Wang & Hyndman 2024 | arXiv 2410.13115 (`conformalForecast`) | https://arxiv.org/abs/2410.13115 | Conformal multistep forecasting in R | PP · S | Medium |
| Hyndman et al. 2011 | *CSDA*, optimal combination for hierarchical series | https://doi.org/10.1016/j.csda.2011.03.006 | Reconciliation | PR · S | High |
| Wickramasuriya et al. 2019 | *JASA* 114(526):804–819 (MinT) | https://doi.org/10.1080/01621459.2018.1448825 | MinT reconciliation | PR · S | High |
| Panagiotelis et al. 2023 | *EJOR* 306(2):693–706 | https://econpapers.repec.org/paper/mshebswps/2020-23.htm | Probabilistic reconciliation | PR · S | High |
| Makridakis et al. 2020 | *IJF* 36(1), M4 competition | https://pure.unic.ac.cy/en/publications/the-m4-competition-100000-time-series-and-61-forecasting-methods/ | Combinations dominate | PR · S | High |
| Makridakis et al. 2022a/b | *IJF* 38(4):1346–1364 (M5 accuracy); 1365–1385 (M5 uncertainty) | https://ideas.repec.org/a/eee/intfor/v38y2022i4p1346-1364.html | LightGBM led; few beat simple benchmarks; uncertainty worse at granular levels | PR · S | High |
| Makridakis et al. 2022c | *IJF* 38(4):1279–1282, M5 special-issue editorial | https://pmc.ncbi.nlm.nih.gov/articles/PMC9232271 | As above | PR · F | High |
| Murphy 1993 | A. Murphy, *Weather & Forecasting* 8(2):281–293, "What is a good forecast?" | https://stafforini.com/works/murphy-1993-what-good-forecast/ | Consistency, quality and value are distinct | PR · S | High |
| Elmachtoub & Grigas 2022 | *Management Science* 68(1):9–26, "Smart 'Predict, then Optimize'" | https://arxiv.org/abs/1710.08005 | Decision-focused (SPO+) loss | PR · S | High |
| Hu, Kallus & Mao 2022 | *Management Science*, "Fast rates for contextual linear optimization" | https://arxiv.org/abs/2011.03030 | Plug-in can match integrated approaches | PR · S | High |
| Gama et al. 2014 | *ACM CSUR* 46(4):44, concept drift survey | https://doi.org/10.1145/2523813 | Drift detection | PR · S | High |

## F. Methods from other fields

| Key | Source | URL | Finding used | Type · Verif. | Quality |
|---|---|---|---|---|---|
| Glickman & Stern 1998 | *JASA* 93:25–35, "A State-Space Model for National Football League Scores" | https://www.glicko.net/research.html | Time-varying team strength (week and season variance) | PR · F (citation), S (content) | High |
| Glickman 1999 | *Applied Statistics* 48:377–394 (Glicko) | https://www.glicko.net/research.html | Dynamic paired comparisons | PR · F (citation) | High |
| Lopez et al. 2018 | Lopez, Matthews & Baumer, "How often does the best team win?" (arXiv 1701.05976; AoAS) | https://arxiv.org/abs/1701.05976 | Bayesian state-space models on betting markets | PR · F | High |
| Efron & Morris 1975 | *JASA* 70(350):311–319 | https://www.medicine.mcgill.ca/epidemiology/hanley/bios602/MultilevelData/EfronMorrisJASA1975.pdf | Stein shrinkage roughly halves MSE in examples | PR · S | High |
| Muth 1960 | *JASA* 55:299–306 (via a QuantEcon lecture) | https://python-advanced.quantecon.org/muth_kalman.html | EWMA is optimal for random walk plus noise | PR · S | High |
| Egidi & Gabry 2018 | *JQAS* 14(3):143–157 | https://arts.units.it/handle/11368/2929586 | Hierarchical fantasy-soccer ratings | PR · F | Medium |
| Yurko et al. 2019 | Yurko, Ventura & Horowitz, "nflWAR", *JQAS* | https://arxiv.org/abs/1802.00998 | Multilevel player effects | PR · S | High |
| Hutchison 2025 | Footballguys, "Chance to Play: Questionable vs. Doubtful" | https://www.footballguys.com/article/2025-chance-to-play-questionable-vs-doubtful | Questionable 70.7% and Doubtful 6.9% played (2017–24) | PRAC · F | Medium |
| Raybon 2018 | C. Raybon (4for4), "How Injury Affects Weekly NFL Player Performance" | https://www.4for4.com/fantasy-football/how-injury-affects-nfl-fantasy | Output when playing while Q/D (2008–15): RB −11.9%, WR −14.9%, TE −5.8%, QB +1.5% | PRAC · F | Medium (old designation regime; self-baseline) |
| Hägglund et al. 2006 | *BJSM* 40:767–772 | https://bjsm.bmj.com/content/40/9/767 | Prior injury hazard ratio 2.7 (soccer) | PR · S | High (other sport) |
| Ullah et al. 2014 | *BJSM* 48(17):1287–1293 | https://bjsm.bmj.com/content/48/17/1287 | Frailty and Andersen–Gill models for recurrent injuries | PR · S | High (other sport) |
| van Ours & van Tuijl 2016 | *Economic Inquiry* 54(1):591–604 | https://pure.eur.nl/en/publications/in-season-head-coach-dismissals-and-the-performance-of-profession/ | Post-dismissal gains are regression to the mean | PR · S | High |
| Nishihata 2025 | "The Value of a Chance", arXiv 2511.07218 | https://arxiv.org/abs/2511.07218 | Absences redistribute playing time, not efficiency (MLB) | PP · F | Medium |
| Uhrín et al. 2021 | *IMA J Management Math* (arXiv 2107.08827) | https://arxiv.org/abs/2107.08827 | Fractional or adaptive Kelly | PR · F | High (betting) |
| McHale & Scarf 2011 | *Statistical Modelling* 11:219–236 | https://statmod.org/smij/Vol11/Iss3/McHale/Abstract.html | Copula dependence in goals | PR · F | High (soccer) |
| Matthews et al. 2012 | Matthews, Ramchurn & Chalkiadakis, *AAAI* 26(1):1394–1400 | https://ojs.aaai.org/index.php/AAAI/article/view/8259 | Bayesian RL for fantasy soccer | PR · F | High (other game) |
| Levitt 2004 | S. Levitt, *Economic Journal* 114(495):223–246 | https://ideas.repec.org/a/ecj/econjl/v114y2004i495p223-246.html | Bookmakers out-predict bettors | PR · F | High |
| Boulier & Stekler 2003 | *IJF* 19(2):257–270 | https://ideas.repec.org/a/eee/intfor/v19y2003i2p257-270.html | Betting market the best NFL predictor (1994–2000) | PR · F (citation), S | High |
| Paul & Weinbach | Totals-market efficiency | https://works.bepress.com/rodney_paul/12 | Efficient overall, with some subsets | PR · S | Medium |
| Kelly & Chen | NFL totals (AABRI) | https://jid.aabri.com/manuscripts/203263.pdf | High-total unders anomaly faded after 2010 | PR (minor) · S | Low–medium |
| Goldner 2012 | *JQAS* 8(1), drive Markov chain | https://ideas.repec.org/a/bpj/jqsprt/v8y2012i1n9.html | Expected points per drive | PR · S | High |
| NFLSimulatoR | Williams, Palmquist & Elmore, arXiv 2102.01846 | https://arxiv.org/abs/2102.01846 | Play resampling for strategy questions | PP · F | Medium |
| nfelo | nfelo, About | https://nfeloapp.com/about | Elo with QB, rest and weather adjustments | DOC · F | Medium |
| 4for4 DFS corr | 4for4, DFS correlation tool | https://www.4for4.com/2021/preseason/using-4for4-nfl-dfs-player-correlation-tool | QB–WR1 ≈ .46 (unconditional) | PRAC · S | Low |
| RotoGrinders late swap | RotoGrinders, "DraftKings Tips: Late Swap" | https://rotogrinders.com/articles/draftkings-tips-late-swap-404801 | Late-swap option value | PRAC · S | Low |

## G. Data, licensing and tooling

| Key | Source | URL | Finding used | Type · Verif. | Quality |
|---|---|---|---|---|---|
| nflverse-data | nflverse, data repository | https://github.com/nflverse/nflverse-data | Releases and automation | DOC · F | High |
| nflreadpy README | nflverse | https://github.com/nflverse/nflreadpy | "majority … CC-BY 4.0 … FTN data is CC-BY-SA 4.0" | DOC · F | High |
| nflreadr reference | nflverse, `load_*` pages | https://nflreadr.nflverse.com/reference/index.html | Coverage, timing, licences per dataset | DOC · F | High |
| nfldata | nflverse/nfldata | https://github.com/nflverse/nfldata | Games file history (no licence file) | DOC · F | High |
| Disney ToU 2024 | Disney Terms of Use (2024-05-24) | https://disneytermsofuse.com/english/ | Prohibits automated extraction | DOC · F | High |
| Sports Reference | "Data use policy" | https://www.sports-reference.com/data_use.html | Some datasets may not be redistributed; no AI training; "free to reuse facts" | DOC · F | High |
| FantasyPros ToU | FantasyPros Terms (2010-07-01) | https://www.fantasypros.com/about/legal/ | Personal single copy only | DOC · F | High |
| Sleeper API | docs.sleeper.com | https://docs.sleeper.com/ | Read-only, no auth, non-commercial, < 1,000 calls/min | DOC · F | High |
| MFL API | MyFantasyLeague API info | https://api.myfantasyleague.com/2025/api_info | "free … in almost any way"; no harvesting; 1 s spacing | DOC · F | High |
| Yahoo API | Yahoo Fantasy Sports API terms and docs | https://legal.yahoo.com/us/en/yahoo/terms/product-atos/fantasysportsapi/index.html | OAuth 2.0; usage agreement | DOC · S | Medium |
| Open-Meteo HF | Historical Forecast API | https://open-meteo.com/en/docs/historical-forecast-api | Stitched first hours of each run (near-nowcast) | DOC · F | High |
| Open-Meteo PR | Previous Runs API | https://open-meteo.com/en/docs/previous-runs-api | Fixed 1–7-day leads; most models from 2024, GFS from 2021 | DOC · F | High |
| Open-Meteo terms | Terms | https://open-meteo.com/en/terms | CC BY 4.0; non-commercial < 10,000 calls/day | DOC · F | High |
| Meteostat | Terms and licence | https://dev.meteostat.net/terms.html | CC BY 4.0 observations | DOC · F | High |
| NOAA NDFD | NCEI product page | https://www.ncei.noaa.gov/products/weather-climate-models/national-digital-forecast-database | Forecast archive from 2004 | DOC · F | High |
| The Odds API | Historical odds and pricing | https://the-odds-api.com/historical-odds-data/ | History on paid plans only (excluded) | DOC · F | High |
| Big Data Bowl | NFL Football Ops repository | https://github.com/nfl-football-ops/Big-Data-Bowl | Tracking subsets; no licence file | DOC · F | Medium |
| CmdStanR / CmdStan | Stan docs | https://mc-stan.org/cmdstanr/articles/cmdstanr.html ; https://mc-stan.org/docs/cmdstan-guide/installation.html | Needs RTools on Windows | DOC · F | High |
| R-INLA | Download page | https://www.r-inla.org/download/ | Binary repository; version pinning | DOC · F | High |
| XGBoost params | XGBoost docs | https://xgboost.readthedocs.io/en/stable/parameter.html | `reg:quantileerror`; expectile needs ≥ 3.3.0 | DOC · F | High |
| targets/crew | rOpenSci targets manual | https://books.ropensci.org/targets/crew.html | Local parallel workers | DOC · F | High |
| probably | tidymodels | https://probably.tidymodels.org/reference/index.html | Calibration and conformal intervals | DOC · F | High |
| Quarto dashboards | Posit | https://quarto.org/docs/dashboards/ | Static or Shiny dashboards | DOC · F | High |
| taskscheduleR | bnosac | https://github.com/bnosac/taskscheduleR | Windows scheduling from R | DOC · F | High |
| CRAN indexes | CRAN PACKAGES (source and Windows R 4.5/4.6), queried 2026-10-13 | https://cloud.r-project.org/src/contrib/PACKAGES.gz | Versions and binaries for every package recommended in 05/06; R 4.6 current | DOC · F | High |
| seqcomp | CRAN `seqcomp` 0.3.0 (2026-09-27) | https://cran.r-project.org/package=seqcomp | Anytime-valid comparison (Choe & Ramdas), quantile scores, sequential MCS, Winkler | DOC · F, V2 | High (young package) |
| ESPN client code | ffverse/ffscrapr `R/espn_*.R`; cwendt94/espn-api `espn_api/` | https://github.com/ffverse/ffscrapr ; https://github.com/cwendt94/espn-api | ESPN views and fields (§V) | DOC · V2 | High (code); ESPN itself is undocumented |

## H. Platforms (documentation and marketing)

| Key | Source | URL | Finding used | Type · Verif. | Quality |
|---|---|---|---|---|---|
| FantasyPros tools 2026 | FantasyPros, 2026-08-01, "Best Fantasy Football Tools (2026)" | https://www.fantasypros.com/2026/07/best-fantasy-football-tools/ | Tool list; no win or playoff odds | MKT · F | Medium (features) |
| Yahoo Help | Yahoo Help SLN37135 (projections), SLN35629 (Plus), SLN37119 (Assistant GM) | https://help.yahoo.com/kb/SLN37135.html | Partner projections; min/max; weekly win probability (method undescribed) | DOC · F | Medium |
| PFF 2019 | PFF, 2019-07-15, "The logic behind PFF's fantasy projections" | https://www.pff.com/news/fantasy-the-logic-behind-pffs-fantasy-projections | Volume from game projections; efficiency from grades | PRAC · F | Medium |
| PFF WAR | Eager & Chahrouri, Sloan, "PFF WAR" | https://www.sloansportsconference.com/research-papers/pff-war-modeling-player-value-in-american-football | NFL player WAR | PR (conference) · S | Medium |
| ETR about | Establish The Run, About | https://establishtherun.com/about/ | Algorithmic projections; correlated simulations (described, not validated) | MKT · F | Low |
| RotoViz | RotoViz projection and range-of-outcome articles (2020) | https://www.rotoviz.com/2020/08/a-different-kind-of-projection-using-historical-data-to-create-low-mid-and-high-projections/ | Mode-based projections; historical ranges | PRAC · S | Low (403) |
| FanDuel Research | "Welcome to FanDuel Research" | https://fanduel.com/research/welcome-to-fanduel-research | numberFire content migration | MKT · F | — |
| PlayerProfiler | Terms glossary | https://www.playerprofiler.com/terms-glossary/ | Definitions only; no validation | DOC · F | Low |
| Subvertadown home | subvertadown.com | https://subvertadown.com/ | Streaming tools; self-evaluation | PRAC · F | Medium |
| Stokastic 2026 | Stokastic vs SaberSim vs RotoGrinders (2026-08-18) | https://www.stokastic.com/articles/nfl-dfs/stokastic-sims-vs-sabersim-vs-rotogrinders-nfl-2026 | Contest simulation (self-promotional) | MKT · F | Low |
| SaberSim | Homepage | https://www.sabersim.com/ | Testimonials | MKT · F | Low |
| FFA home | Fantasy Football Analytics homepage (Oct 2026) | https://fantasyfootballanalytics.net/ | Active tools (optimisers, risk) | PRAC · F | Medium |
| numberFire | Wikipedia | https://en.wikipedia.org/wiki/NumberFire | History | SEC · F | Low |

---

## §V. Pass-2 verification log (direct fetches, 2026-10-13)

| Item | Status | Verified facts | Evidence |
|---|---|---|---|
| ESPN schedule and scores | Verified (client code) | `view=mMatchup` (ffscrapr) / `mMatchupScore` (espn-api) → `schedule[]`: `matchupPeriodId`, `home/away.teamId`, `totalPoints`, `winner` (UNDECIDED/TIE/HOME/AWAY), `playoffTierType`. Box scores: `mMatchupScore`+`mScoreboard` with an `x-fantasy-filter`. `mSchedule` is used by neither library. | ffscrapr `R/espn_schedule.R`, `espn_starters.R`; espn-api `football/league.py`, `matchup.py`, `team.py` |
| ESPN standings | Verified | `mTeam` → `record.overall.*`, `playoffSeed`, `rankCalculatedFinal`/`rankFinal`, `divisionId`, **`currentSimulationResults.playoffPct`**; tie rules TOTAL_POINTS_SCORED / H2H_RECORD / INTRA_DIVISION_RECORD | ffscrapr `espn_standings.R`; espn-api `team.py`, `league.py`, `helper.py` |
| ESPN settings | Verified | `scheduleSettings.{matchupPeriodCount, matchupPeriods, playoffTeamCount, playoffSeedingRule, playoffMatchupPeriodLength, divisions}`; `scoringSettings.{matchupTieRule, playoffMatchupTieRule, scoringEnhancementType (WIN_BONUS_TOP_HALF)}`; `tradeSettings.deadlineDate`; `draftSettings.keeperCount` | espn-api `base_settings.py` |
| ESPN FAAB | Verified | `acquisitionSettings.{isUsingAcquisitionBudget, acquisitionBudget, minimumBid, waiverProcessDays, waiverProcessHour, …}`; team `waiverRank`, `transactionCounter.acquisitionBudgetSpent` | espn-api `base_settings.py`, `team.py` |
| ESPN transactions and bids | Verified | Route A: `communication/?view=kona_league_communication` (bid = `from` on message type 180; seasons 2019+). Route B: `view=mTransactions2` (`bidAmount`; others' trade items often empty) | ffscrapr `espn_transactions.R`; espn-api `activity.py`, `transaction.py` |
| ESPN past seasons | Verified | < 2018: `leagueHistory/{id}?seasonId=`; ≥ 2018: `seasons/{S}/segments/0/leagues/{id}` | ffscrapr `espn_api.R`; espn-api `espn_requests.py` |
| Haugh & Singal | Partially verified | Crossref: *Management Science* 67(1):72–92, DOI 10.1287/mnsc.2019.3528; abstract confirms double-up/top-heavy, mean–variance, binary QPs, Dirichlet regressions, 2017 NFL DFS. **No arXiv version** (arXiv 1702.01780 is unrelated). | Crossref API; arXiv API |
| Choe & Ramdas | Verified | *Operations Research*; anytime-valid CS and e-processes; bounded scores | arXiv 2110.00115 |
| seqcomp | Verified | 0.3.0 (2026-09-27); Choe & Ramdas CS/e-processes; quantile scores; sequential MCS; Winkler | CRAN |
| Issue #188 | Verified | 0/208 team-weeks; 16 teams; top-half bonus; 60k sims; common random numbers; SE ≈ 0.003; closed on a < 5% rule | GitHub |
| nflseedR | Verified | `compute_results(teams, games, week_num, …)` → updated tables; chunks; L'Ecuyer-CMRG; outputs | nflseedr.com |
| ffsimulator | Verified | `ff_wins_added` experimental, remove-and-resimulate; efficiency N(0.775, 0.05) | ffsimulator.ffverse.com |
| Petersen textbook | Partially verified | Weekly and seasonal crowd > individual (qualitative); chapter list | Textbook site and `.qmd` source |
| Lee & Liu 2022 | Verified | As in §D | JDM page |
| Gneiting 2011 | Verified (wording caveat) | Bregman ↔ mean; generalised piecewise linear ↔ quantile; the abstract gives absolute and squared error only as examples | arXiv 0912.0902 |

## §U. Items cited only (not verified in this research; do not rely on them without checking)

Diebold & Mariano (1995); Smith & Wallis (2009, venue); Hersbach (2000); Bracher et al. (weighted interval score); Berger (1982, intersection–union tests); Morton et al. (2003, stochastic benchmark); Summers et al. (2005, hockey pools); Nemhauser et al. (1978, submodularity); Kelly (1956); Markowitz (1952); Rockafellar & Uryasev (2000); Kalman (1960); Rubinstein (1982); Rigby & Stasinopoulos (2005, GAMLSS); Kaggle "NFL scores and betting data" (licence); KeepTradeCut and FantasyCalc terms pages; Sleeper projections endpoint; Big Data Bowl competition rules.
