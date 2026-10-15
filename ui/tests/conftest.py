"""Synthetic fixture repository (hand-written; no real league data) and helpers."""
from __future__ import annotations

import gzip
import hashlib
import json
import sys
import textwrap
from pathlib import Path

import pandas as pd
import pytest

UI = Path(__file__).resolve().parents[1]
REAL_REPO = UI.parent
sys.path.insert(0, str(UI))

ALIAS = "league_test00"
RUN = "20261013T120000Z"
SNAP = "20261014T080000Z"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write_csv(p: Path, rows: list[dict]) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(p, index=False, lineterminator="\n")


def build_repo(root: Path) -> Path:
    (root / "archive").mkdir(parents=True)
    # valuation run
    vd = root / "data/archive/valuation/season=2026/week=06" / f"run={RUN}"
    vd.mkdir(parents=True)
    players = [("00-01", "1001", "Alpha QB", "QB", "AAA"), ("00-02", "1002", "Bravo RB", "RB", "BBB"),
               ("00-03", "1003", "Charlie WR", "WR", "AAA"), ("00-04", "1004", "Delta TE", "TE", "CCC"),
               ("00-05", "1005", "Echo WR", "WR", "BBB")]
    values = pd.DataFrame([{"season": 2026, "week": 6, "run_id": RUN, "methodology_version": "valuation_v1",
                            "player_id": g, "gsis_id": g, "espn_id": e, "espn_name": n, "position": pos, "team": t,
                            "ros_points": 100.0 - 10 * i, "vor": 50.0 - 10 * i, "vor_regular": 40.0 - 8 * i,
                            "vor_playoffs": 10.0 - 2 * i, "trade_value": 90 - 10 * i, "overall_rank": i + 1,
                            "position_rank": 1, "current_week_points": 15.0 - i, "injury_status": None,
                            "rostered": i < 3} for i, (g, e, n, pos, t) in enumerate(players)])
    values.to_parquet(vd / "values.parquet", index=False)
    weekly = pd.DataFrame([{"player_id": g, "espn_id": e, "player_name": n, "position": pos, "team": t, "season": 2026,
                            "week": w, "opponent": "ZZZ", "has_game": w != 9, "proj": 10.0 + i, "source": "espn",
                            "p_active": 1.0} for i, (g, e, n, pos, t) in enumerate(players) for w in range(6, 12)])
    weekly.to_parquet(vd / "weekly.parquet", index=False)
    (vd / "run_meta.json").write_text(json.dumps({"run_id": RUN, "as_of_utc": "2026-10-13T12:00:00Z", "git_commit": "abc",
                                                  "git_dirty": False, "n_players": 5, "elapsed_seconds": 1}))
    write_csv(root / "archive/valuation_manifest.csv", [{
        "run_id": RUN, "season": 2026, "week": 6, "as_of_utc": "2026-10-13T12:00:00Z", "methodology_version": "valuation_v1",
        "league_hash": "h", "n_players": 5, "values_sha256": sha(vd / "values.parquet"), "weekly_sha256": "x",
        "run_meta_sha256": "x", "espn_capture_sha256": "x", "m4_run_id": "x", "ros_params_sha256": "x", "git_commit": "abc"}])
    # distributions
    dd = root / "data/archive/distributions/season=2026/week=06/run=20261013T130000Z"
    dd.mkdir(parents=True)
    q = {f"q{k:02d}": float(k) / 5 for k in (1, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 99)}
    pd.DataFrame([{"player_id": g, "espn_id": e, "position": pos, "team": t, "week": 6, "base": 10.0, "status": "ACTIVE",
                   "p_active": 1.0, **q, "mean_active": 10.0, "mean": 10.0} for g, e, _, pos, t in players]).to_parquet(dd / "pods.parquet", index=False)
    write_csv(root / "archive/distribution_manifest.csv", [{"valuation_run_id": RUN, "season": 2026, "week": 6,
              "created_at_utc": "20261013T130000Z", "pod_version": "pod_baseline_v0", "pod_table_sha256": "x", "n_players": 5,
              "pods_sha256": sha(dd / "pods.parquet"), "git_commit": "abc"}])
    # league snapshot (roster parquet + raw json.gz)
    sd = root / "data/snapshots/espn_league" / ALIAS / "season=2026"
    sd.mkdir(parents=True)
    roster = pd.DataFrame([{"lineup_slot": "QB", "is_ir_slot": False, "is_skill": True, "captured_at_utc": SNAP,
                            "league_alias": ALIAS, "team_id": 1 if i < 2 else 2, "espn_id": e, "player_name": n,
                            "position": pos, "nfl_team": t, "injury_status": "ACTIVE", "team_abbrev": "T1" if i < 2 else "T2",
                            "team_name": "Team One" if i < 2 else "Team Two"} for i, (g, e, n, pos, t) in enumerate(players[:3])])
    roster.to_parquet(sd / f"captured_at={SNAP}_roster.parquet", index=False)
    raw = sd / f"captured_at={SNAP}.json.gz"
    with gzip.open(raw, "wt") as f:
        f.write("{}")
    write_csv(root / "archive/league_snapshot_manifest.csv", [{"league_alias": ALIAS, "season": 2026, "scoring_period": 6,
              "captured_at_utc": SNAP, "n_teams": 2, "n_rostered": 3, "n_skill": 3, "raw_sha256": sha(raw), "roster_sha256": "x"}])
    # decision ledger (recommendations only)
    dec = root / "data/archive/decisions" / ALIAS / "season=2026/week=06"
    dec.mkdir(parents=True)
    rows = []
    recs = {
        "odds": {"teams": [{"team_id": 1, "e_wins": 7.1, "p_playoffs": 0.6, "p_title": 0.2, "mean_points_for": 1500, "p_seed1": 0.3,
                            "p_seed2": 0.1, "p_seed3": 0.1, "p_seed4": 0.1, "mc_se_playoffs": 0.004},
                           {"team_id": 2, "e_wins": 6.9, "p_playoffs": 0.4, "p_title": 0.1, "mean_points_for": 1450, "p_seed1": 0.2,
                            "p_seed2": 0.1, "p_seed3": 0.05, "p_seed4": 0.05, "mc_se_playoffs": 0.004}],
                 "matchups": [{"home": 1, "away": 2, "p_home": 0.55, "margin_q10": -20, "margin_q50": 3, "margin_q90": 25}],
                 "leverage": [{"team_id": 1, "p_win_this_week": 0.55, "p_playoffs_if_win": 0.7, "p_playoffs_if_loss": 0.5, "leverage": 0.2}],
                 "bands": [{"team_id": 1, "p_playoffs": 0.55, "p_title": 0.18, "sigma_scale": 0.5, "noise_scale": 1},
                           {"team_id": 1, "p_playoffs": 0.65, "p_title": 0.22, "sigma_scale": 1.5, "noise_scale": 1}],
                 "label": "SHADOW"},
        "waivers": {"board": [{"add_row": 5, "add": "Echo WR", "position": "WR", "drop": "Bravo RB", "dU": 3.2, "d_wins": 0.1,
                               "d_playoffs": 0.01, "d_title": 0.004}],
                    "drop_advice": [{"row": 2, "player": "Bravo RB", "position": "RB", "cost": 1.0}],
                    "stream_view": [{"row": 1, "player": "Alpha QB", "position": "QB", "expected": 18.0, "gain": 0.0, "week": 6,
                                     "stream_candidate": False, "status": "informational"}]},
    }
    for i, (typ, rec) in enumerate(recs.items()):
        did = f"20261014T08000{i}Z_{typ}_aaaaaaaa"
        p = dec / f"{did}.json"
        p.write_text(json.dumps({"decision_id": did, "type": typ, "as_of_utc": f"2026-10-14T08:00:0{i}Z", "recommendation": rec,
                                 "metrics": {"fragile": False, "sims": 1000}, "inputs": {}}))
        rows.append({"decision_id": did, "league_alias": ALIAS, "season": 2026, "week": 6, "type": typ,
                     "as_of_utc": f"2026-10-14T08:00:0{i}Z", "record_sha256": sha(p), "git_commit": "abc"})
    write_csv(root / "archive/decision_manifest.csv", rows)
    write_csv(root / "archive/prediction_manifest.csv", [{"run_id": "20261013T110000Z", "season": 2026, "week": 6}])
    # ops
    (root / "data/ops").mkdir(parents=True)
    (root / "data/ops/status.txt").write_text(textwrap.dedent("""\
        FFball dispatcher status - 2026-10-15 19:05 UTC
        Decision: none - no run due
        Target: season 2026 week 6
        Next window opens: Thu 2026-10-15 17:15 ET
        PUSH NEEDED: 3 local commit(s) not on origin (git push before kickoff).
        """))
    write_csv(root / "data/ops/dispatch_log.csv", [{"logged_at_utc": "2026-10-15T19:05:00Z", "decided_for_utc": "", "action": "none",
              "kind": "", "season": 2026, "week": 6, "slate_id": "", "reason": "no run due", "result": "-"}])
    # research records
    (root / "models/registry").mkdir(parents=True)
    (root / "models/registry/m1.yml").write_text("lineage: M1\nfrozen_commit: deadbeef\nfrozen_at_utc: '2026-09-01T00:00:00Z'\n"
                                                 "selection_rationale: Test lineage. More text.\n")
    (root / "models/probabilistic").mkdir(parents=True)
    (root / "models/probabilistic/pod_baseline_v0.yml").write_text("# FROZEN test\nversion: pod_baseline_v0\npre_registration: E18\n")
    (root / "models/fingerprints").mkdir(parents=True)
    (root / "models/fingerprints/m1.csv").write_text("model_id,n,mean_pred\nm1,10,5.0\n")
    ex = root / "research/master_plan/execution"
    ex.mkdir(parents=True)
    (ex / "milestone_tracker.md").write_text("# T\n\n| id | Milestone | Status |\n|---|---|---|\n| F0 | Ops | COMPLETED |\n| R1 | Score | NOT STARTED |\n")
    (ex / "experiment_results.md").write_text("| id | Date | Classification |\n|---|---|---|\n| R-001 | 2026-10-13 | supported |\n")
    (ex / "decisions.md").write_text("# D\n\n## X-001 First\nbody\n")
    (root / "research/experiment_log.md").write_text("# Log\n\n## E1 Test\nbody one\n\n## E2 Second\nbody two\n")
    (root / "research/valuation_log.md").write_text("# VL\n\n## VL1 Test\nbody\n")
    (root / "research/contamination_register.yml").write_text(
        "version: 1\nsealed_seasons:\n  2026: sealed\nfamilies:\n  weekly_wr_points:\n    description: test\n    confirmatory: [2026]\n"
        "spent_checks:\n  - {date: 2026-10-13, family: injury_stack, season: 2019, entry: E19c}\n")
    (root / "ui/r").mkdir(parents=True)
    return root


@pytest.fixture
def repo_root(tmp_path):
    return build_repo(tmp_path / "repo")


@pytest.fixture
def repo(repo_root):
    from ffui.paths import Repo
    return Repo(repo_root)


FAKE_ADAPTER = r'''
import json, os, sys, time
args = sys.argv[1:]
op = args[0]
req = json.load(open(args[args.index("--request") + 1]))
out = args[args.index("--out") + 1]
p = req.get("params", {})
if p.get("sleep"):
    time.sleep(float(p["sleep"]))
if p.get("fail"):
    sys.stderr.write("noise line\nUI_ADAPTER_ERROR %d: %s\n" % (int(p["fail"]), "test failure"))
    sys.exit(int(p["fail"]))
if p.get("trip"):
    sys.stderr.write("UI_ADAPTER_TRIPWIRE lg_ledger_record\n")
    sys.exit(5)
tmp = out + ".tmp" + str(os.getpid())
os.makedirs(tmp, exist_ok=True)
json.dump({"echo": p, "op": op}, open(os.path.join(tmp, "result.json"), "w"))
json.dump({"op": op, "elapsed_seconds": 0.1, "started_at_utc": "2026-10-15T00:00:00Z", "inputs": req.get("context", {}),
           "exploratory": True, "ledgered": False}, open(os.path.join(tmp, "meta.json"), "w"))
os.replace(tmp, out)
'''


@pytest.fixture
def fake_runner(repo):
    """A JobRunner whose 'Rscript' is this Python and whose adapter is a Python stand-in (same CLI contract)."""
    from ffui.jobs import JobRunner
    repo.adapter.write_text(FAKE_ADAPTER)
    return JobRunner(repo, rscript=sys.executable)
