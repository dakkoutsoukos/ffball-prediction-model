# 02 — Research Landscape

*What the evidence says about fantasy-football analytics and the methods around it, as of 2026-10-13.
Every source cited here is listed with its URL, type and verification level in [10_sources.md](10_sources.md).
Citations use author–year keys, for example [Gneiting 2011].*

**How to read the evidence labels.**

| Label | Meaning |
|---|---|
| **Strong** | Peer-reviewed theory or results, or several independent, consistent analyses with disclosed methods |
| **Moderate** | Credible practitioner analyses with disclosed methods, a single peer-reviewed study, or consistent indirect evidence |
| **Weak** | A single practitioner or vendor analysis, a small or old study, or student work |
| **Speculative** | Plausible, but no evidence was found |
| **(arith.)** | Our own illustrative arithmetic, not a sourced result |

---

## 0. Method and limits of this review

**Research passes**

| Pass | What was done |
|---|---|
| 0. Repository | Full read of FFball's docs, logs, configuration, registries and the relevant code. See [03](03_current_system_assessment.md). |
| 1. Broad external | Eight parallel investigations: projection methods, advanced metrics, valuation/trades/simulation, lineup/waiver/draft optimisation, forecast evaluation, data and tooling, the platform landscape, and methods from other fields. Together they made 593 tool calls (web searches, page fetches, source-code reads and CRAN index queries). Every source was tagged as fetched-and-read (F), seen only as a search snippet (S), or unverified (U). |
| 2. Verification | Direct fetches of primary sources for the facts the roadmap depends on: the ESPN league API views, the anchor papers and the R package contracts. Results are recorded in [10_sources.md](10_sources.md) §V. |
| 3. Critical review | An adversarial review of the draft plan. Its outcomes are recorded in [07](07_master_roadmap.md) §10. |

**Limits**
- **Search budget.** The shared web-search budget ran out during pass 1. After that, research continued by fetching known primary URLs only. Topics that are thinner as a result:
  - aging curves;
  - waiver-priority option value;
  - keeper and auction literature;
  - Sleeper's in-app features;
  - academic work on the efficiency of player-prop markets.
- **Paywalls.** These sources are cited at snippet level at most: Fantasy Points (HTTP 402), RotoViz (403), PFF articles, the Haugh & Singal full text (403), and the FantasyPros support pages (403).
- **No new outcome data was examined.** No data analysis was run on FFball's historical outcomes for any *new* question family. This keeps those seasons clean for the pre-registered experiments in [09](09_experiment_backlog.md).

---

## 1. The ten findings that shape the plan

| # | Finding | Strength | Key sources |
|---|---|---|---|
| 1 | **Consensus and market mean forecasts are hard to beat.** The evidence comes from several directions: <br>• FFball's own M1–M4 results; <br>• crowd averages beat every single projection source in every season of 2012–2016; <br>• betting markets beat models and experts on NFL games; <br>• bettors rarely beat bookmakers; <br>• student ML papers lose to ESPN; <br>• ESPN's own AI system feeds ESPN projections *into* its ensemble rather than replacing them. | Strong (direction) | [Petersen 2017], [Boulier & Stekler 2003], [Levitt 2004], [Jayanti 2026], [Baughman et al. 2021a], FFball E2–E5 |
| 2 | **The only well-supported routes to better weekly means:** <br>• calibrating the base (level bias); <br>• timely availability and injury information; <br>• averaging several independent sources. <br>For the third, the quantitative evidence is season-long and blog-level; the weekly evidence is a qualitative textbook statement. | Moderate | FFball E4/E5/E10/E14, [Petersen 2017; Petersen 2026] |
| 3 | **Calibrated predictive distributions are the largest gap, both in FFball and across the industry.** No platform publishes calibration evidence (coverage, PIT, CRPS, Brier) for floors, ceilings, boom/bust labels or win probabilities. | Moderate (absence of evidence) | Platform review §12, [Baughman et al. 2021a] |
| 4 | **Weather-forecast post-processing transfers directly.** Proper scoring rules, EMOS/distributional regression, isotonic distributional regression and conformal prediction come from weather and statistics. CRPS reduces to MAE for point forecasts, so it continues FFball's MAE lineage. | Strong (theory); untested in fantasy | [Gneiting & Raftery 2007], [Gneiting et al. 2005], [Henzi et al. 2021], [Gibbs & Candès 2021] |
| 5 | **Using MAE to grade mean forecasts is inconsistent.** Absolute error is consistent for the median and squared error for the mean. Valuation and lineup sums need means. | Strong (theory) | [Gneiting 2011], [Ehm et al. 2016] |
| 6 | **Win-probability lineup optimisation changes few pre-kickoff decisions in season-long head-to-head (H2H) leagues.** It matters more in late lock windows and in DFS. Better means and better calibration matter more than variance-seeking. | Weak–moderate | [Haugh & Singal 2021], [alhart2015 2026], [Hunter et al. 2016], (arith.) |
| 7 | **Player outcomes are correlated in ways that change team-score variance.** Same-team QB–WR1 correlation is about +0.3 in full-PPR weekly data; QB–TE about +0.27; WR–WR about 0. These figures depend heavily on how roles are defined. | Moderate (sign); weak (size) | [Huntington 2026], [Winks 2022], [Subvertadown 2022a] |
| 8 | **The right valuation unit is wins or championship equity in a specific league, not points.** Practitioner "fantasy WAR" uses normal approximations with known flaws. Expected VBD shows that expected-value VOR understates bench upside, which is consistent with FFball's VE3 hoarding pathology. | Moderate | [Stuart 2013], [Henderson 2019], [Fantasy Footballers 2022] |
| 9 | **There is open R prior art for simulation, and it can be improved on.** <br>• ffsimulator: season-level shock, rank-bucket bootstrap, common-random-number "wins added", but hindsight lineups × an "efficiency" factor. <br>• nflseedR: a pluggable weekly results function, tiebreakers, chunked reproducible simulation. | Strong (code read) | [Ho n.d.], [Carl & Sharpe n.d.] |
| 10 | **Power, not cleverness, is the binding constraint on proving improvements.** <br>• The unit of inference is the week. <br>• With 8–17 prospective weeks, the minimum detectable effect is 0.7–1.15 week-level SDs. <br>• Anytime-valid e-values allow optional stopping and valid combination across seasons, but **they do not add power; only more weeks do**. <br>• Decision quality has to be measured directly; it does not follow from accuracy. | Strong (theory) | [Choe & Ramdas 2024], [Grünwald et al. 2024], [Murphy 1993], [Cameron et al. 2008] |

---

## 2. Player projection systems (category A)

### 2.1 How accurate projection sources are, and the case for averaging

- **Season-long evidence (the best available).** Fantasy Football Analytics (FFA) compared projection sources for QB/RB/WR/TE over 2012–2016 [Petersen 2017; Petersen 2016b].
  - The **simple average beat every single source in every year**.
    - Five-year R²: 0.625 for the average vs 0.564 for ESPN.
    - Five-year MASE: 0.569 vs 0.647.
  - Weighting sources by past accuracy did about as well as the simple mean.
  - A robust (outlier-resistant) average was slightly worse.
  - Rankings of individual sources were unstable from year to year.
  - All sources over-projected, by roughly 4–10 points per season.
  - **Strength:** Moderate. It is season-long, comes from blogs, has no significance tests, and its author runs one of the sources compared.
  - **Weekly evidence: qualitative only.** Petersen's open textbook (ch. 17, "Accuracy of Fantasy Projections") states that "for both seasonal and weekly projections, crowd-averaged projections showed greater accuracy than individual projection sources", in both R² and MAE [Petersen 2026, F]. It also says that:
    - projections rarely explain "more than about two-thirds of the variance";
    - weekly accuracy is lower than seasonal;
    - projections tend to "overpredict performance at higher levels of projected points".

    That last point is consistent with FFball's calibration slopes below 1. No weekly numbers are published in the narrative.
- **Rankings vs projections.** FFA's 2016 comparison reports projections R² 0.53 vs expert consensus rankings (ECR) 0.27 [Petersen 2016a]. That gap is mostly an artefact of pooling positions. Within a position it nearly disappears (WR 0.48 vs 0.44; for RBs, rankings did better).
- **Accuracy contests grade ranks, not projections** [FantasyPros n.d.-a]. The FantasyPros accuracy methodology:
  - maps each expert's rank slot to the historical average points for that slot;
  - scores in half-PPR only;
  - uses a player pool that includes players who turned out to finish in the top N;
  - z-scores each week and drops each expert's worst week.

  It cannot measure calibration, uncertainty or decision value. 4for4's marketing notes that its most decorated ranker withdrew from the contest [4for4 n.d.].
- **The forecast-combination literature agrees** [Clemen 1989; Claeskens et al. 2016; Wang et al. 2023]:
  - Equal weights are a strong default.
  - Estimated weights add estimation error.
  - In the M4 competition, 12 of the 17 most accurate methods were combinations [Makridakis et al. 2020].
- **What this means for FFball.**
  - Averaging is the only mean-improvement route with outside evidence behind it.
  - It cannot be backtested, because there is no point-in-time archive of other free sources, so it can only be tested prospectively.
  - Each source's terms must be checked first. FantasyPros terms allow personal single-copy use only [FantasyPros ToU]; the ESPN terms are documented in `docs/espn_projections.md`.

### 2.2 Weekly prediction by machine learning: what the evidence shows

- **No source shows a public-data feature model beating a major site's weekly projections out of sample.**
  - A 2026 student paper: ESPN's preseason projections beat a per-position XGBoost model with 1,933 component features on rank-MAE [Jayanti 2026].
  - ESPN/IBM's deployed system used ESPN projections *inside* a regression ensemble (RMSE 6.78 on 2017) and reported no ESPN-only comparison [Baughman et al. 2021a].
  - An open Fantasy Premier League model only *matched* a commercial service prospectively [Groos 2025].
- **The only "beats ESPN" result found is leaky.** A 2026 Princeton undergraduate thesis credits its edge mostly to "will-they-play" prediction and Vegas features [Williams 2026]. FFball's own code review of that thesis's repository found a severe target leak (`docs/prior_work.md`): `implied_team_total == 0` exactly on non-playing rows. That leak explains the dominance of the "Vegas" features.
- **Common leakage patterns in published fantasy ML** [Cosico 2026; Kapoor & Narayanan 2023; FFball prior_work]:
  1. Samples filtered on outcomes, such as same-game snap share.
  2. Benchmarks with the wrong sign (ADP is a rank, so its expected correlation with points is negative).
  3. Cross-validation that mixes seasons.
  4. Features produced by models trained on the evaluation seasons:
     - nflfastR's CP/xYAC/xPass models were fit on 2006–2019 [Baldwin 2021];
     - ffopportunity's xFP models were fit on 2006–2020 [Sydlowski & Ho n.d.].
  5. Closing lines or final injury statuses that did not exist when the forecast was made.
  6. Scoring only the players who played.
- **FFball's M2 result agrees.** XGBoost never beat linear models, and no feature family beat calibrated ESPN on the holdout (E4, E5).
- **Strength:** Moderate. Every study is weak on its own, but they point the same way.

### 2.3 Direct points vs stat components ("top-down")

- **ESPN's projections are already built top-down.** Mike Clay's process goes team by team, then dropback, carry and target shares, with subjective inputs, and is "not automated" [Clay 2020]. His ESPN bio says his projections "power the ESPN Fantasy Football game" [ESPN Press 2023; Clay 2026].
- **No evidence that component models give better means** [Jayanti 2026]. Their value lies elsewhere:
  1. **Exact rescoring.** For linear scoring, E[points] equals the scoring weights times E[stats].
  2. **Structured uncertainty.** Points decompose into volume × share × efficiency + TDs.
  3. **Coherent correlations.** Teammates are negatively related through shares and positively related through team scoring.
- **Count-model chain** (implementable with mgcv/gamlss families [mgcv docs]):
  - targets: negative binomial;
  - receptions given targets: binomial;
  - yards: skewed continuous;
  - TDs: Poisson.

  No NFL player-level evaluation of such a chain was found.
- **Signal varies sharply by component.** In Petersen's worked example, weekly TD projections explain about 0–10% of variance, against 24–42% for yardage [Petersen 2026]. Component modelling therefore matters more for distributions and rescoring than for means.

### 2.4 Probabilistic and distributional forecasting

- **Shape of weekly fantasy points.**
  - Practitioners describe a floor near zero, right skew, and spread that grows with the projection [Footballguys DFS; FFA 2019].
  - FFball's own WR numbers give MAE/SD ≈ 0.68–0.75. For a normal distribution the ratio is 0.80, so the residuals have heavy tails or skew (inference from E2/E5 numbers).
  - QB weekly RMS deviation drops only from 8.0 to 7.5 points once projections are subtracted [Subvertadown 2022b].
- **Fantasy distributions are not calibrated anywhere.**
  - FFA's floors and ceilings are percentiles of *disagreement across sources*, not outcome uncertainty [FFA 2019; ffanalytics].
  - IBM reports a 72% boom/bust classification accuracy but no calibration [Baughman et al. 2021a].
  - One vendor reports that its preseason 80% bands covered 87.9% of outcomes, meaning they were too wide [GWTTKB 2026].
- **Candidate methods, roughly in order of fit for FFball** (details in [05](05_modeling_strategy.md)):

  | Method | What it does | Source |
  |---|---|---|
  | Empirical residual quantiles by position × projection band × status | Assumption-light baseline | — |
  | Isotonic distributional regression (IDR) on the base projection | Nonparametric benchmark | [Henzi et al. 2021] |
  | EMOS-style location–scale(–shape) regression fit by minimum CRPS | Hurdle for availability plus a skewed continuous part | [Gneiting et al. 2005]; mgcv `shash`/`gaulss`/`twlss`; gamlss; crch |
  | Linear quantile regression | With monotone rearrangement so quantiles don't cross | — |
  | Conformal wrappers | Calibration under drift | CQR [Romano et al. 2019]; ACI [Gibbs & Candès 2021] |
  | Quantile regression forests / NGBoost | Only with many covariates, which have not paid off for FFball | [Meinshausen 2006], [Duan et al. 2020] |
- **Mixture and compound structure.** Yardage (continuous), TDs (discrete) and receptions combine into skewed, sometimes multimodal outcomes, which gives boom/bust probabilities without extreme-value theory. Agent H rated this a high-priority test, but no fantasy literature on it was found (Speculative). After the critical review, the plan keeps it as a *future* idea for non-PPR rescoring and bonuses, not as a P2 candidate.

### 2.5 Rookies, aging, breakouts and stability

- **Stability.** Volume is far more stable than efficiency [Hoopes 2024a–c; Hernandez 2023; Stuart 2014].
  - WR targets per game, year over year: r ≈ 0.66–0.70.
  - WR target share: 0.55.
  - Yards per target: 0.22.
  - TD rate: 0.12–0.19.
  - QB rush attempts per game: 0.89.
- **Stabilisation points** (reliability ≈ 0.5) for per-route WR rates [Tuccitto 2017]:
  - receptions per route: about 188 routes;
  - yards per route run (YPRR): about 351;
  - TDs per route: about 882.

  Both are *season-level* and survivor-filtered. Nobody has published week-level reliability, so FFball must estimate it.
- **Rookies.** Combine metrics predict weakly [Kuzmits & Adams 2008; Teramoto et al. 2016]. A vendor reports a "cliff" in draft capital and that its ridge model did not beat a naive baseline [GWTTKB 2026] (Weak).
- **Aging.** The delta method has survivor bias [Lichtman 2009]. Imputing unobserved seasons fixes it in simulation and in the NHL [Schuckers et al. 2023]. NFL evidence is practitioner-only: RB efficiency declines from about 25, WR efficiency peaks around 25 [Zimmerman 2021]. Relevant only to multi-season (keeper or dynasty) value.
- **Similarity / nearest-neighbour systems** (PECOTA, RotoViz, KUBIAK): no out-of-sample evaluation exists for the NFL. In baseball, PECOTA does not consistently beat Marcel [Beyond the Box Score 2016] (Weak). **Park.**

### 2.6 Context: matchup, weather, betting lines, team-level forecasts

- **Defence vs position.**
  - Year-over-year persistence is weak, r ≈ 0.16 (TE) to 0.27 (QB) [4for4 2026 defenses; 4for4 2025 defenses].
  - A sweep of 24,924 player-weeks kept only opponent PPR allowed, worth about +0.38 points for WRs [GWTTKB 2026].
  - FFball's own VE1 opponent term moved weekly MAE by under 0.04%.
  - **Verdict:** heavy shrinkage or skip.
- **Weather.** Only student and practitioner evidence. Wind is the most consistent negative for passing. Recorded weather is observed at kickoff; historical *forecasts* exist only from limited archives (§11). It is probably priced into game totals. **Weak.**
- **Betting lines.**
  - Markets are near-efficient [Levitt 2004; Boulier & Stekler 2003].
  - Implied team totals are the best free team-level forecasts.
  - One vendor: line-implied PPR beats a trailing average (MAE 4.96 vs 5.54), but that is a weak baseline [GWTTKB 2026].
  - FFball's M1/M2 found closing lines added nothing *on top of* ESPN.
  - **Their likely role is in variance and correlation (game script), not the mean** (Speculative; testable on FFball's as-of-kickoff lines for 2021–2025).
- **Team-level forecasting.** Use market totals as the team forecast. Build a team-level model only to drive joint simulation [Clay 2020; Glickman & Stern 1998; nfelo n.d.].

---

## 3. Advanced player metrics: predictive or descriptive? (category H)

**Bottom line:** volume and opportunity metrics are stable and predictive; per-play efficiency and tracking metrics are mostly noise at fantasy-relevant horizons. **No public study shows any advanced metric adding value beyond ESPN or consensus weekly projections.**

| Metric family | Stability (YoY) | Next-season fantasy signal | Point-in-time in free data | Verdict |
|---|---|---|---|---|
| Targets / target share / WOPR | High (0.55–0.70) | Strong (targets/g → next PPG r ≈ 0.62) | Yes (pbp) | Use (already in) |
| Air-yards share, aDOT | aDOT 0.65 | aDOT → next PPG r ≈ 0.07; targets plus air yards beat targets alone | Yes | Role descriptor only |
| TPRR, YPRR, route participation | TPRR R² ≈ 0.41 (two eras) | YPRR r ≈ 0.59 | **No**: participation is published after the season | Skip in season; validate a snap-share proxy |
| First-read target share | Claimed 0.78 (proprietary) | Claimed 0.79 / 0.694 | Proxy via FTN `read_thrown`, 2023+ | Test (low priority) |
| Separation, YACOE, catch-over-expected, RYOE | 0.21–0.61 | Weak (RYOE → next PPG 0.18) | NGS weekly rows are thresholded; week 0 is overwritten | Skip |
| QB rushing (designed runs vs scrambles) | 0.89 | 0.47 | Yes (pbp `qb_scramble`) | Use for the QB extension |
| CPOE, EPA per dropback | 0.42–0.51 / 0.50 | 0.13 / 0.33 | Yes | Low priority |
| xFP / xTD (opportunity-expected points) | Higher than FPOE | xTD barely beats TDs for next-year TDs | ffopportunity, trained 2006–2020 (in-sample to 2020) | Use as a baseline; pin the model version |
| FPOE (points over expectation) | Regresses for 67–74% of players | Weak | Derived | Shrink heavily |
| Defence vs position | 0.16–0.27 | Weak | Yes | Shrink heavily or skip |

Sources: [Hoopes 2024a–c], [Stuart 2014], [Tuccitto 2017], [Burke 2022], [Vabishchevich 2024], [Fantasy Points 2023], [Irby 2025], [Gretch 2019], [Winks 2020], [Clay 2026], nflreadr docs. Strength: Moderate overall. Studies are season-level and survivor-filtered, and none tests whether metrics add value beyond projections.

- **Where an edge plausibly remains.** FFball's residual study (E5) showed ESPN *over*-reacts to role changes and over-projects returning players. The Questionable effect replicated (E10, E14). Together these point at **errors in availability and role transitions**, not missing metrics.
- **The "market already prices it" argument.** ESPN's projector created opportunity-adjusted TDs and publishes an xFP model [Clay 2026]. Opportunity is therefore almost certainly an input to ESPN's projections (inference).

---

## 4. Player valuation (category B)

- **VBD/VOR baselines are conventions that have never been validated.**
  - Bryant (origin, 1996) rejects worst-starter and average-starter baselines in favour of "players drafted by pick 100" [Bryant 2016].
  - ffanalytics hard-codes QB13 / RB35 / WR36 / TE13 [ffanalytics calc_projections].
  - Bales: "the baseline is a moving target" [Bales 2013].
  - **FFball is ahead of this:** its exact weekly allocation with exchange baselines (LP duals) derives the baseline from lineup economics.
- **Expected VBD (EVBD)** [Stuart 2013]: value is E[max(0, X − R)] over the outcome distribution, rather than max(0, E[X] − R).
  - The expected VBD of backups "is not zero".
  - FFball's Σₜ max(0, E − R) is the special case with no uncertainty, so it understates bench upside. That is consistent with the VE3 finding that the re-draft hoards QBs because bench value ignores level uncertainty.
  - Strength: Moderate (logic plus ADP-outcome data).
- **Wins-based value (fantasy WAR)** [Henderson 2019; Dynasty Nerds 2020; Fantasy Footballers 2022].
  - The practitioner recipe:
    1. treat the average team's weekly score as normal (mean ≈ 108–117, SD ≈ 21 in 12-team leagues, 2018–19);
    2. compute the player's P(win) against an average opponent;
    3. sum over weeks and subtract replacement.
  - Known flaws:
    - one method treats the player's own team score as known, which understates the SD of the difference;
    - summing positional SDs implies perfect correlation;
    - normality overvalues booms;
    - none of the methods is calibrated.
  - (arith.) With a team SD of about 21 and independent teams, the SD of the score difference is about 30. Near an even matchup, +1 point per week ≈ +1.3 percentage points of P(win). +10 points per week ≈ +1.8 expected wins over 14 weeks.
- **Nonlinearity of the objectives** (theory, arith.):
  - Weekly P(win) is a normal CDF of the point edge, so returns flatten for favourites.
  - P(playoffs) is S-shaped around the cutoff, so bubble teams gain most per point.
  - P(title | playoffs) is a product of round win probabilities, so it is convex; contenders value playoff-week upside more.
  - **A trade can be fair in points yet strongly favour one side in title equity.** This motivates evaluating trades in wins and title units.
- **Context-dependent value** is documented in:
  - ffsimulator's per-roster `ff_wins_added` [Ho n.d.];
  - ESPN/IBM's league- and roster-personalised valuations [Baughman et al. 2021b];
  - format-specific values (1QB, superflex, TE premium) [KeepTradeCut FAQ; DynastyProcess].

  FFball's ΔU already makes value depend on the roster. The missing piece is making it depend on the **objective**: contender, bubble team or eliminated team.
- **Dynasty and keeper.**
  - DynastyProcess values = 10500·exp(−0.0235·ECR) (verified in code). Future picks are discounted ×0.8 per year [DynastyProcess apps-calculator].
  - KeepTradeCut aggregates crowd Keep/Trade/Cut votes with an "adapted ELO algorithm" [KeepTradeCut FAQ].
  - Both rest on consensus or crowd inputs. They are relevant only if the league has keepers.
- **Auction values.** There is no primary source for the common "dollars ∝ surplus VOR" convention. Petersen optimises against average auction values (AAV) [Petersen 2026]. Relevant only for auction leagues.

---

## 5. Trade analysis and optimisation (category C)

- **Existing tools work in points, values or grades, not playoff odds:**
  - FantasyPros: "player values, team needs, expert opinions" [FantasyPros 2026 tools].
  - ESPN/IBM: Trade Grades [ESPN Press 2023; IBM 2025].
  - Draft Sharks: both teams, next week plus rest of season [Draft Sharks KB]. This is the closest to FFball.
  - KTC, FantasyCalc and DynastyProcess: market or crowd values.
  - **None documents the change in playoff or title probability for both teams in a specific league.**
- **The only documented platform trade *generator*** [Baughman et al. 2021b]:
  - ensemble player values, personalised to the league and roster;
  - teams paired by complementary needs (cosine dissimilarity);
  - a 0-1 knapsack for outgoing players;
  - six objective measures;
  - quality judged by experts (76.9% → 97.3% "high-quality"), **not** by acceptance or outcomes.
- **Academic.** A genetic algorithm with playoff-week weighting, tested in one league [Parshall et al. 2025] (Weak).
- **Bargaining theory.**
  - The Nash bargaining solution maximises the product of both sides' gains [Nash 1950, via secondary].
  - Top trading cycles is core and strategy-proof for single indivisible items [Shapley & Scarf 1974; Roth et al. 2004]. Fantasy rosters break that assumption: lineup slots make players complements, and roster limits bind.
  - **Practical rule:** rank trades by FFball's gain × the counterparty's *perceived* gain.
- **Acceptance and behaviour.**
  - No empirical study of fantasy trade acceptance was found.
  - General evidence:
    - the endowment effect (sellers ask about 2× what buyers offer) [Kahneman, Knetsch & Thaler 1990, via secondary];
    - endowment-like retention in AFL draft-pick trading [Chandrakumaran et al. 2024];
    - NFL teams overvalue their picks [Massey & Thaler 2013, secondary].
  - **Implication:** model acceptance as a sensitivity analysis through a "partner lens" (what the counterparty sees, such as raw ESPN projections), with loss aversion λ swept from 1 to about 2.2. Do not fit a model.
- **Fair vs advantageous.** These are different quantities:
  - *Fairness* is balance in the value both managers **perceive** (market or generic value).
  - *Advantage* is the gap in **context-specific** ΔP(playoffs or title).

  The best trades are perceived as fair and are advantageous in context, ideally for both sides through complementary needs. This framing comes from our synthesis of [Baughman et al. 2021b], [Stuart 2013] and bargaining theory.

---

## 6. Lineup optimisation (category D)

- **Theory (Strong).** A head-to-head week pays out on P(Y > 0), where Y = own score − opponent score. The mean–variance rule for beating a stochastic benchmark [Haugh & Singal 2021, after Morton et al. 2003]:
  - a **favourite** trades mean for *lower* variance;
  - an **underdog** trades mean for *higher* variance;
  - Var(Y) includes the covariance with the opponent's starters, so starting a player whose output moves with the opponent's starters reduces Var(Y).
- **Size of the effect in season-long H2H (Weak–moderate).**
  - The only direct measurement: a hobbyist project, 16 teams with a top-half bonus, 208 team-weeks, 60,000 simulations each, ex-ante lineups, common random numbers, paired SE ≈ 0.003. **The results-optimal lineup never differed from the points-optimal lineup (0/208).** The issue was closed under a pre-registered rule: "under ~5% disagreement means leave the objective alone" [alhart2015 2026, verified].
  - The author of a commercial correlated-simulation tool calls the edge "small" [Braun n.d.].
  - (arith.) With a team SD of about 25:
    - swapping in an equal-mean player with SD 10 instead of 6 is worth 0.003–0.006 wins per week, or about 0.3–0.8 projected points;
    - +1 point of mean every week is worth about 0.16 wins per season.
  - **Better means and calibration matter more than variance-seeking.**
- **Where it can matter:**
  - **Late lock windows.** The remaining spread is small, so variance choices can flip outcomes (arith.: +4.5 percentage points of P(win) in one illustration).
  - **Game-time decisions with P(active) < 1.**
  - **The FLEX slot.** Put the latest-kickoff eligible player in FLEX. It costs no expected points and keeps substitution options open [Fantasy Footballers flex, snippet; practitioner consensus].
- **DFS results do not transfer.**
  - Top-heavy DFS gains are large.
    - Haugh & Singal's author slides report more than 350% ROI over 17 weeks of 2017 FanDuel contests, with "very high variance". The published abstract (Management Science 67(1):72–92, verified via Crossref) gives no numbers; it describes double-up and top-heavy settings, mean–variance binary quadratic programs and Dirichlet regressions of opponents.
    - Mlčoch & Hubáček report 34% ROI over 8 weeks [Haugh & Singal 2021; Mlčoch & Hubáček 2023].
  - Those gains come from convex payouts, ownership effects and multi-entry diversification [Hunter et al. 2016], none of which exist in single-opponent H2H.
- **Correlations (Moderate for signs, Weak for magnitudes).**
  - Full-PPR weekly correlations, 2022–25: QB–top WR +0.31, QB–TE +0.27, QB–own RB +0.07, WR–WR −0.02. A QB–WR stack is "about 14% more boom-or-bust" [Huntington 2026].
  - Defining roles after the fact or using single-game samples inflates these numbers [Winks 2022; Beimfohr 2025].
  - **FFball must estimate *residual* correlations (conditional on projections), with roles defined before the game.**
- **Tooling.** Lineups are small enough to enumerate. HiGHS is "currently among the best open source" MILP solvers in R, but handles quadratic programs only without integer variables [CRAN Task View Optimization 2026].

---

## 7. Waivers, FAAB and streaming (category E)

- **FAAB is a first-price sealed-bid auction** with a large common-value component, because everyone reads similar projections. Bid shading and winner's-curse logic apply. "Bidding your value in an SBFP auction guarantees you cannot get any positive return" [Solow 2026]. **No academic fantasy FAAB study exists.**
- **Empirical bid data** [FF Beacon 2026; commercial, Sleeper only, selection undisclosed]:
  - 60,421 winning bids from 1,003 leagues, 2023–26.
  - 72% of auctions had a single bidder.
  - Median winning bids by number of bidders: 0% of budget (one), 3.2% (two), 8% (three), 18% (four or more).
  - Bids fall over the season; from week 14 the median is 0%.
- **Waiver priority** works like an option: using it drops you to the back of the order. No sources quantify its value (gap). A rule claiming only when ΔROS utility exceeds the simulated option value is our analysis.
- **Streaming** [Subvertadown 2022b; Subvertadown 2026; self-reported]:
  - Weekly projection–outcome correlation: QB ≈ 0.35, D/ST ≈ 0.35–0.40, K ≈ 0.10.
  - D/ST tracks the *opponent* offence (r ≈ 0.2 with points allowed) more than its own history (≈ 0.05).
  - Per-week edges are small but add up. In a deep 8-team free-agent pool, streaming is cheap.
- **Breakout detection.** No validated method was found. The question FFball can test is whether early usage predicts rest-of-season points *beyond* ESPN, using point-in-time snapshots.
- **Handcuffs.** No detectable win-rate benefit: 51.04% vs 50.56%, Bayes factor 4.2 for no difference [Lee & Liu 2022] (Weak–moderate). A contingent role does have real value inside a correlated availability model (§13).

---

## 8. Draft analytics (category F)

- **ADP survival.** P(a player is still available at your pick k) = P(his draft slot ≥ k). The spread widens with depth: σ ≈ 2.25 + 0.11·pick, skewed toward falling, and wider for QB/TE [STACKED 2026; 21,893 Sleeper 12-team drafts; commercial]. It needs recalibrating to ESPN 8-team drafts.
- **Optimisation.**
  - A deterministic dynamic program that anticipates opponents from ADP: better on average and more robust in simulated 10-team drafts [Fry et al. 2007].
  - A mixed-integer program (MIP) for both the draft and lineups, aiming to win the season: claims an edge over conventional strategy in simulations of 2007–08 [Becker & Sun 2016].
  - No peer-reviewed reinforcement-learning draft work for fantasy NFL was found. The best RL fantasy paper is about Fantasy Premier League [Matthews et al. 2012].
- **Human behaviour** [Lee & Liu 2022; 1,350 Sleeper leagues, 2017]:
  - ADP correlates with season points at −0.56 (RB) and −0.55 (WR), weakly for QB/TE, and not at all for DEF.
  - Drafters herd on QB/K/DEF and copy the previous pick.
  - Following an opponent's QB pick had no effect on win rate.
- **Best-ball construction results (Zero RB, Hero RB)** are unstable across years and come from 12-team, half-PPR leagues with no lineups or waivers [Winks 2025; Strachan 2024]. **They transfer weakly to H2H redraft.**
- **Recipe implied by the evidence:**
  1. A point-in-time ADP snapshot from the league's own platform.
  2. A skewed availability model.
  3. Monte Carlo opponents (ADP + noise + roster need + herding).
  4. The evaluator: the season simulator's E[wins] or P(playoffs), not VOR alone.

---

## 9. League simulation (category G)

- **ffsimulator** [Ho n.d.; source code read]. Experimental; archived from CRAN in February 2024.
  - **How it works:**
    - Each simulated season draws every player's rank once from N(ECR, SD/2), which acts as a level shock.
    - Weekly scores are resampled from historical outcomes of players at the same rank ±2.
    - Games played are Bernoulli draws; byes score 0.
    - It reports head-to-head and all-play wins.
    - `ff_wins_added()` removes a player, re-optimises that roster **on the same draws**, and reports the change in wins (common random numbers).
  - **Flaws:**
    - Lineups are hindsight-optimal, multiplied by an "efficiency" factor drawn from N(0.775, 0.05). This inflates bench value.
    - Outcomes come from rank buckets, so player-specific forecasts are thrown away.
    - No playoff stage is documented.
- **nflseedR** [Carl & Sharpe n.d.]:
  - completed games stay fixed;
  - a user-supplied `compute_results(teams, games, week_num, …)` returns `list(teams, games)` and can carry state such as Elo;
  - deep tiebreakers and playoff simulation;
  - chunked, parallel runs with reproducible random numbers.

  **This is the architectural template for FFball's season simulator.**
- **Platform win probabilities.** ESPN's FantasyCast and Yahoo's Assistant GM show win probabilities, but **no method or calibration evidence is published** [ESPN Press 2023; Yahoo Help]. Open-source playoff-odds tools exist [uberfastman], but their score models are undocumented.
  - ESPN's league API exposes a per-team `currentSimulationResults.playoffPct` field (read by the espn-api client; verified in code). FFball can log ESPN's own playoff odds as an **external comparator** for its simulator, even though ESPN's method is undocumented.
- **Overconfident playoff odds.** Level shocks correlate a team's weeks. Shortcuts that treat weeks as independent therefore make playoff odds overconfident (agent C analysis; consistent with VE1c, where the ROS residual SD is about 45–53% of the forecast).
- **Compute (arith.).** 500 players × 14 weeks × 10,000 simulations = 70M draws, run in chunks. The Monte Carlo SE of P is ≤ 0.5% at 10,000 simulations, and common random numbers shrink the SE of differences.

---

## 10. Reliability and model evaluation (category I)

- **Matching the scoring rule to the forecast** [Gneiting 2011, F]:
  - a score is consistent for the mean if and only if it is a Bregman function; squared error is one;
  - a score is consistent for a quantile if and only if it is generalised piecewise linear; absolute error is the median case;
  - otherwise the common practice "can lead to grossly misguided inferences, unless the scoring function and the forecasting task are carefully matched".

  Murphy diagrams check whether a model ranking holds across all consistent scores [Ehm et al. 2016].
- **Distributional forecasts.**
  - Primary score: CRPS. It is proper and generalises absolute error [Gneiting & Raftery 2007].
  - Calibration checks: randomised PIT for the point mass at zero [Czado et al. 2009]; interval coverage and the interval score.
  - Decomposition into miscalibration, discrimination and uncertainty (MCB/DSC/UNC) [Arnold et al. 2024].
  - Principle: maximise sharpness subject to calibration [Gneiting, Balabdaoui & Raftery 2007].
- **Binary probabilities** such as P(active) and P(win): Brier score with CORP reliability diagrams, which are stable and use isotonic regression instead of bins [Dimitriadis et al. 2021, F].
- **Correlated forecasts.** Whether the energy score is sensitive to dependence is **contested** [Scheuerer & Hamill 2015; Alexander et al. 2021 vs Ziel & Berk 2019]. Use the variogram score (p = 0.5), and above all score the **totals that decisions use**: lineup totals and matchup margins.
- **Testing.**
  - Diebold–Mariano tests need small-sample fixes [Harvey et al. 1997; Coroneo & Iacone 2020].
  - Giacomini–White assumes a rolling window, which FFball's expanding refits violate [Giacomini & White 2006].
  - The Model Confidence Set replaces pairwise "winner" claims [Hansen et al. 2011].
  - With 5–30 clusters, cluster-robust tests over-reject [Cameron et al. 2008]. A 2026 season has only 8–18 week clusters.
- **Anytime-valid inference.**
  - Confidence sequences and e-processes for score differences [Choe & Ramdas 2024].
  - Sequential calibration tests [Arnold, Henzi & Ziegel 2023].
  - Sequential model confidence sets.
  - E-values multiply across seasons [Grünwald et al. 2024; Ramdas et al. 2023].
  - Available in R as `seqcomp` (CRAN 0.3.0).
  - These methods buy validity under continuous monitoring, not power. A pre-registered, fixed-sample pooled analysis across seasons remains the most powerful confirmatory design.
- **Holdout reuse.** Reusing a holdout adaptively can manufacture accuracy from noise [Dwork et al. 2015, F]. Kaggle shows little adaptive overfitting in practice [Roelofs et al. 2019], but FFball's effects are tiny, so even a small bias matters.
- **Leakage taxonomy** [Kapoor & Narayanan 2023, F]: eight types. FFball covers temporal leakage (L3.1) and sampling bias (L3.3). It should add audits for:
  - L1.2: preprocessing fit across the train/test split;
  - L1.3: feature selection on all seasons;
  - L1.4: duplicate records;
  - L2: features that aren't legitimate for the task, such as information captured after lock.
- **Decisions.**
  - Murphy separates *quality* (accuracy) from *value* to the decision maker [Murphy 1993].
  - Decisions are argmax or threshold operations, so a ΔMAE of 0.01 rarely reorders players.
  - Measure regret against the hindsight-optimal decision, flip rates, and paired regret differences.
  - "Predict-then-optimise" plug-in approaches can match decision-focused learning [Hu, Kallus & Mao 2022; Elmachtoub & Grigas 2022].
- **Power.** MDE ≈ (t₀.₉₇₅,W−1 + t₀.₈₀,W−1)·σ_w/√W, where σ_w is the SD of week-level mean loss differences:
  - W = 8: about 1.15 σ_w;
  - W = 10: about 0.99 σ_w;
  - W = 17: about 0.72 σ_w;
  - about 150 weeks: about 0.23 σ_w.

  (Agent E's calculation; standard formula.)

---

## 11. Data and infrastructure (category J)

Summarised here; the full catalogue is in [06](06_data_infrastructure.md).

- **Licences.**
  - Most nflverse data is CC BY 4.0. The exceptions are FTN charting, participation and ffopportunity xFP (CC BY-SA 4.0) [nflreadpy README; ffopportunity].
  - The DynastyProcess data repository is GPL-3.0.
  - Upstream terms are stricter: Sports Reference forbids redistribution of some datasets and AI training [Sports Reference data use]. FantasyPros allows a personal single copy only [FantasyPros ToU].
  - The Disney terms forbid automated extraction [Disney ToU 2024]. The owner has accepted that risk for private research.
- **Timing traps.**
  - Participation data (2023+) appears only after the postseason.
  - FTN charting arrives within 48 hours.
  - NGS updates nightly and has thresholds.
  - Schedule lines are overwritten until they become closing lines, so nfldata's git history is the as-of source.
  - Depth charts carry timestamps only from 2025.
  - Weather in schedules is the observed value at the game.
- **Weather forecasts.**
  - Open-Meteo's Previous Runs API gives fixed 1–7-day lead times, mostly from January 2024 (GFS from March 2021; JMA from 2018). It is CC BY 4.0, non-commercial.
  - The Historical Forecast API stitches the first hours of successive model runs, so it is close to a nowcast. Valid only for an official run just before kickoff [Open-Meteo docs].
- **League platforms.**
  - Sleeper: free for non-commercial use, no authentication, under 1,000 calls/min.
  - MFL: "free … in almost any way".
  - Yahoo: OAuth.
  - ESPN: unofficial, cookie-based.
- **Paid sources (excluded by the owner's rule):** PFF, SIS, FTN premium, Fantasy Points Data, 4for4, ETR, RotoWire, player-prop histories.
- **R tooling.** Toolchain-free on Windows except Stan (brms, rstan model compilation and cmdstanr need RTools45). Toolchain-free alternatives exist: rstanarm, INLA, glmmTMB, mgcv, gamlss, crch, drf, ranger, lightgbm and xgboost (quantile objectives). **R 4.6 is now current, so FFball's R 4.5.1 is "oldrel"** [CRAN indexes].
- **Maintenance risk.** The ffverse is thinly maintained. ffscrapr's CRAN release dates from 2023, ffsimulator was archived from CRAN, and ffopportunity is on r-universe only. Learn from these packages; don't depend on them.

---

## 12. Platform landscape (category K, §5 of the brief)

| Capability | Commercial state of the art | Documented method? | Calibration published? |
|---|---|---|---|
| Point projections | Everywhere: ESPN (Clay), Yahoo partners, PFF, ETR, numberFire/FanDuel Research, 4for4 | One-paragraph descriptions | No error metrics on any fetched page |
| Ranges / boom-bust | Yahoo Plus min/max; Draft Sharks floor/ceiling; ESPN/IBM boom/bust; ETR and DFS simulations | Thin | **None** |
| Accuracy tracking | FantasyPros contest (ranks); Subvertadown self-reports (the most transparent found) | Contest rules documented | Ranks only |
| Trade tools | FantasyPros, ESPN/IBM grades, Draft Sharks (both teams, week + ROS), KTC/FantasyCalc/DynastyProcess values | ESPN/IBM generator only [Baughman et al. 2021b] | No outcome validation |
| Win / playoff odds | ESPN live matchup win probability; Yahoo weekly win probability; open-source playoff odds (ffsimulator, uberfastman) | Open-source only | **None** |
| Waivers / FAAB | FantasyPros Waiver Central; ESPN/IBM Waiver Grades; FF Beacon bid data | No FAAB method documented anywhere | — |
| Draft | FantasyPros Draft Wizard and simulator; ETR Solver; Draft Sharks War Room; FFA optimisers | Footballguys VBD; FFA open code | — |

**Missing across the ecosystem:**
1. Calibrated, publicly validated distributions.
2. Prospective, pre-registered accuracy tracking at both the projection *and decision* levels.
3. Trade and waiver evaluation in playoff- or title-odds units for a *specific* league.
4. A documented chain from player distributions to matchup win probability, standings and recommendations.
5. Point-in-time reproducibility.

These are exactly where FFball's existing protocol (point-in-time data, pre-registration, prospective archives) gives it an advantage.

---

## 13. Methods from other fields (category K and §3 of the brief)

| Method (field) | Transfer to FFball | Evidence | Verdict |
|---|---|---|---|
| Empirical-Bayes shrinkage (statistics) | Shrink efficiency rates, matchup effects and availability groups | [Efron & Morris 1975]; NFL reliability data | **Adopt** |
| State-space / Kalman filters (econometrics) | Weight recent games more when exposure is irregular (missed games, partial snaps); predictive variances. EWMA is the steady-state special case [Muth 1960] | NFL team strength [Glickman & Stern 1998]; markets [Lopez et al. 2018] | Test (for variance and pooling, not to beat ESPN's mean) |
| EMOS / BMA / IDR post-processing (weather) | Calibrate distributions around the base projection | [Gneiting et al. 2005; Raftery et al. 2005; Henzi et al. 2021] | **Adopt** |
| Conformal prediction (machine learning) | Coverage guarantees under drift | [Romano et al. 2019; Gibbs & Candès 2021; Barber et al. 2023] | Adopt as a wrapper |
| Forecast reconciliation (retail, hierarchical forecasting) | Make player shares coherent with team volumes; reconcile at the stat level | [Wickramasuriya et al. 2019; Panagiotelis et al. 2023] | Test (with the component model) |
| Copulas and factor models (finance) | Correlated weekly outcomes: a game-level factor anchored on market totals plus a Gaussian copula | [McHale & Scarf 2011] (soccer) | **Adopt** (simple form) |
| Survival and recurrent-event models (medicine) | Rest-of-season games missed; return to play; frailty models | [Ullah et al. 2014; Hägglund et al. 2006] (other sports) | Test |
| Causal inference (econometrics) | Redistribution of usage when a teammate is absent; avoid regression-to-the-mean traps | [van Ours & van Tuijl 2016; Nishihata 2025] | Treat as forecasting (share models) |
| Stochastic benchmark optimisation (OR, finance) | P(win) lineup objective | [Haugh & Singal 2021] | Adopt as an option, with a kill rule |
| Value of information and real options (decision analysis) | Late-kickoff FLEX, game-time decisions, handcuff option value | Practitioner consensus | **Adopt** |
| Sequential anytime-valid testing (clinical trials, statistics) | Prospective monitoring across seasons | [Choe & Ramdas 2024; Grünwald et al. 2024] | **Adopt** |
| Simulation with rollout policies (OR) | Waiver, trade and draft decisions scored by ΔP(playoffs) | [Becker & Sun 2016; Fry et al. 2007] | Adopt |
| Reinforcement learning / MDPs (AI) | Season management | None for NFL; FPL only [Matthews et al. 2012] | **Reject** (no faithful opponent simulator; validating in our own simulator is circular) |
| Bandits (AI) | Streaming | Every player's points are observed, so there is no exploration value | **Reject** |
| News NLP / LLM extraction | Injury and role news | IBM system with no ESPN-only comparison; no free timestamped archive; terms risk | **Park** |
| Play-level game simulation | Correlated outcomes | [Goldner 2012; NFLSimulatoR]; no evidence it beats factor models | **Park** |
| Similarity (PECOTA-style) systems | Distribution shapes for rookies | No NFL out-of-sample evidence | Park |
| Kelly sizing (finance) | FAAB | The budget doesn't compound | Reject |

---

## 14. Evidence map: what is supported, what is promising, what is speculative

| Tier | Items |
|---|---|
| **Strongly supported** | <ul><li>Proper scoring and calibration methods</li><li>Calibrating point forecasts to remove level bias</li><li>Volume over efficiency</li><li>TD regression</li><li>Markets and consensus beat models on means</li><li>Common random numbers for paired simulation comparisons</li><li>The risk logic of P(win) objectives</li><li>Leakage taxonomy and holdout-reuse risk</li><li>Anytime-valid inference</li></ul> |
| **Supported but needing FFball validation** | <ul><li>Distributional calibration around the base forecast (CRPS)</li><li>Injury and availability adjustments for other positions</li><li>Game-factor correlations</li><li>Wins and title-equity valuation</li><li>Expected VBD for bench value</li><li>Partner-lens perception (a frontier, not a fitted acceptance model)</li><li>Late-window decisions</li><li>A FAAB bid-shading model</li><li>A draft availability model</li></ul> |
| **Experimental** | <ul><li>Averaging several sources (prospective only)</li><li>Implied totals as variance or correlation covariates</li><li>First-read share</li><li>State-space usage filters</li><li>Component (top-down) model as an ESPN-independent fallback</li><li>Handcuff option value</li></ul> |
| **Speculative or not worth it** | <ul><li>Deep RL</li><li>Bandits</li><li>Play-level simulators</li><li>Similarity systems</li><li>LLM news extraction</li><li>Extreme-value theory for booms</li><li>Vine copulas</li><li>Weather beyond market totals</li><li>Defence-vs-position adjustments</li><li>Large feature-model searches for weekly means</li></ul> |

---

## 15. Gaps and how to continue

**Gaps.** None of the following could be found:
- A peer-reviewed study of fantasy projection accuracy.
- *Quantitative* weekly evidence that averaging sources helps. Only the textbook's qualitative statement exists.
- A calibration evaluation of any fantasy distribution or win-probability product.
- A study of fantasy trade acceptance.
- An academic study of FAAB.
- A week-level reliability study of usage metrics.
- An evaluation of NFL comparables systems.
- Survivor-corrected NFL aging curves.

**Continuation plan** (when search access resets):
- Search Google Scholar or OpenAlex for:
  - "fantasy football" combined with calibration, projection accuracy, or trade acceptance;
  - Haugh & Singal's full text (season-long applicability);
  - the Becker & Sun effect size;
  - player-prop market efficiency (peer-reviewed);
  - NFL aging curves with imputation.
- Re-check the FantasyCalc and KeepTradeCut terms.
- Check Sleeper's projection endpoint terms.
- Confirm whether ESPN's `WAIVER_ERROR` transactions carry *losing* FAAB bids.

ESPN's *winning* bid amounts are exposed: see [10_sources](10_sources.md) §V.

None of these gaps blocks the first milestones in [11](11_next_steps.md).
