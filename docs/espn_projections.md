# ESPN historical projections: investigation and status

**Status (2026-10-05): technically available. Not fetched, pending a terms-of-use decision by the project owner.**
The pipeline has a complete, tested ESPN interface behind `espn.enabled` in
`config/project.yml`. It defaults to `false`.

## 1. Can historical pregame ESPN projections be obtained?

Yes. ESPN's public fantasy API serves past weekly projections without credentials:

```
GET https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{S}/segments/0/leaguedefaults/3
    ?scoringPeriodId={W}&view=kona_player_info
X-Fantasy-Filter: {"players":{"filterSlotIds":{"value":[4]},"limit":2000,
  "sortPercOwned":{"sortPriority":1,"sortAsc":false},
  "filterStatsForSourceIds":{"value":[0,1]},"filterStatsForSplitTypeIds":{"value":[1]},
  "filterStatsForScoringPeriodIds":{"value":[W]}}}
```

| Item | Finding (✔ verified by request, ~ inferred) |
|---|---|
| `leaguedefaults/3` | ✔ ESPN's default **PPR** league scoring. `appliedTotal` matched nflverse PPR for 117 of 117 WRs (2024 W5). `/1` is Standard. |
| Slot 4 | ✔ WR. Slot 3 is the RB/WR flex. Filter on `defaultPositionId == 3` as well. |
| Stats entries | ✔ `statSourceId` 1 = projection, 0 = actual. `statSplitTypeId` 1 = single week. Keep only `seasonId == S` and `scoringPeriodId == W`, because the live season also returns the prior season's same week. |
| Stat ids | ✔ 53 receptions, 58 targets, 42 rec yards, 43 rec TD, 23 rush att, 24 rush yds. ~ others. |
| Seasons | ✔ **2018–2025 complete**. 2026 weeks 1–4 are available, and later weeks are already posted and still changing. 2015–2017 are not available. |
| Coverage | ✔ About 360–395 WR-slot players per week. Roughly 120–130 have a projection above 0. Zero projections cover OUT/IR/free agents and deep reserves. A few players have no projection entry. |
| Volume | One request per season-week returns all WRs (50–70 KB). 2018–2025 is about 140 requests. |

The `ffanalytics` R package (FantasyFootballAnalytics) scrapes the same
endpoint but keeps no archive. Its historical projection archive needs a paid
subscription. `ffscrapr` exposes ESPN projections only for a specific league's
starters. No public dataset archiving ESPN weekly projections was found.

## 2. Are they truly pregame?

A projection pulled today for a past week is only a valid benchmark if it equals
the value ESPN showed just before that game. The Wayback Machine holds genuine
captures of ESPN's own API responses, made by ESPN's projections page at the
time. We compared those with today's API:

| Evidence | Result |
|---|---|
| 2023 W4, captured Sunday 19:17Z (during 1 pm games) vs today | **50 / 50 identical**. No change after kickoff. |
| 2026 W4, captured Sunday 13:00Z vs today | 33 / 37 identical. The other 4 differ by ≤ 0.065 pts. |
| Thursday/Wednesday captures (2023 W2, W5; 2024 W4) vs today | Only 54–72% identical. The differences are pregame injury news (for example, a player projected 18.7 midweek is 0 today after being ruled out). |
| 2019 full season captured Aug 2020 vs today | **387 / 387 (W3) and 398 / 398 (W10) identical**, actuals included. |
| Players hurt *during* a game | Keep their normal positive projection. No hindsight clean-up was found. |

**Conclusion.** The stored value is ESPN's **final pregame projection**, frozen
around kickoff. It has not been revised after the fact, and it already
incorporates the week's injury news. That makes it the right benchmark for a
kickoff-time prediction.

Not verified:
- the exact freeze rule (each game's kickoff or the first game of the week);
- 2018 and 2020–2022, for which no in-season captures exist (they are assumed to
  behave like 2019/2023);
- the timing of individual late scratches.

## 3. Terms of use: why fetching is disabled

ESPN content is governed by the Disney Terms of Use (last updated 2024-05-24):

- **§2.A** limits use to "personal, noncommercial use only". It grants no right to
  use content "in connection with any … training, testing, **benchmarking or
  validation** of any artificial intelligence or machine learning tool, model, …".
- **§2.B.x** prohibits accessing or extracting content "using a robot, spider,
  script, or other automated means … for … data mining or web scraping or
  otherwise compiling, building, creating or contributing to any collection of
  data".

Benchmarking a predictive model against ESPN projections, and archiving them with
a script, falls within that language even for private, low-volume, non-commercial
research. Open-source tools such as ffanalytics and espn-api use this endpoint
widely, but that does not change the terms.

**This is a risk decision for the project owner, so the code does not make it.**
During the investigation, about 57 exploratory requests were made to establish the
facts above. Their samples live only in a temporary scratch directory, never in
this repository.

### If the owner decides to proceed
1. Set `espn.enabled: true` in `config/project.yml`.
2. Run `targets::tar_make()`. About 130 requests are made at 1.5 s intervals, and
   raw responses are cached immutably under `data/raw/espn/`, which is git-ignored.
3. The pipeline then automatically:
   - switches the evaluation population to "ESPN projected > 0";
   - adds the ESPN benchmark, ESPN-augmented models and calibration diagnostics;
   - validates our scoring against ESPN's actual totals.
4. **Never commit ESPN data** to this public repository.

### Forward archive (designed, not running)
`snapshot_espn_projections()` (`R/data/espn.R`) and `scripts/snapshot_espn.R`
capture the live week's projections with a UTC timestamp:

```
data/snapshots/espn/season=2026/week=05/captured_at=20261008T150000Z_wr.parquet  (+ raw .json.gz)
```

Running it a few times per week (Tue, Thu before TNF, Sat, Sun 11:00 ET) builds a
genuinely point-in-time archive with known capture times. Historical retrieval
cannot guarantee that. It is subject to the same terms-of-use decision and is
disabled by the same flag.

## 4. Alternatives if ESPN is not used

| Option | Notes |
|---|---|
| FantasyPros weekly ECR (`nflreadr::load_ff_rankings("all")`) | Archived each Friday, 2020–2024. These are **rankings, not points**, so they support rank metrics only. Under FantasyPros terms. Some weeks are missing. |
| Naive / regression baselines (current) | Fully reproducible and free, but they are not the benchmark the project set out to beat. |
| Manual personal use | The §2.A benchmarking clause still applies. |
