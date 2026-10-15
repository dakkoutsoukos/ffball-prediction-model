import json

import pandas as pd
import pytest

from ffui import artifacts as A
from ffui import contracts as K
from ffui import playerdata as P
from ffui import research as R


def test_valuation_discovery_and_hash(repo):
    runs = A.valuation_runs(repo)
    assert [r.run_id for r in runs] == ["20261013T120000Z"]
    v = A.valuation_table(runs[0], "values", verify=True)
    assert runs[0].provenance.hash_ok is True
    assert K.check("values", v).ok


def test_valuation_hash_mismatch_detected(repo):
    run = A.latest_valuation(repo)
    p = run.dir / "values.parquet"
    df = pd.read_parquet(p)
    df.loc[0, "vor"] = 999.0
    df.to_parquet(p, index=False)
    A.valuation_table(run, "values", verify=True)
    assert run.provenance.hash_ok is False


def test_manifest_row_without_folder_is_skipped(repo):
    m = repo.manifests / "valuation_manifest.csv"
    df = pd.read_csv(m, dtype=str)
    extra = df.iloc[[0]].assign(run_id="20261014T000000Z")
    pd.concat([df, extra]).to_csv(m, index=False)
    assert [r.run_id for r in A.valuation_runs(repo)] == ["20261013T120000Z"]
    aud = A.manifest_folder_audit(repo)
    assert ((aud["id"] == "20261014T000000Z") & (~aud["on_disk"])).any()


def test_missing_archive_is_graceful(tmp_path):
    from ffui.paths import Repo
    r = Repo(tmp_path)
    assert A.valuation_runs(r) == []
    assert A.latest_league_snapshot(r) is None
    assert A.decision_records(r) == []
    assert A.ops_status(r) == {"available": False}
    assert A.latest_pods(r) == (None, None)


def test_pods_and_snapshot(repo):
    pods, prov = A.latest_pods(repo, "20261013T120000Z")
    assert K.check("pods", pods).ok and prov.model_versions["pod"] == "pod_baseline_v0" and not prov.notes
    pods, prov = A.latest_pods(repo, "OTHER_RUN")
    assert prov.notes, "a different valuation run must be flagged"
    s = A.latest_league_snapshot(repo)
    assert s.alias == "league_test00" and s.roster_path.exists() and s.captured is not None
    assert K.check("roster", A.league_roster(s)).ok


def test_decisions_hash_check_and_tamper(repo):
    recs = A.decision_records(repo)
    assert {r["type"] for r in recs} == {"odds", "waivers"} and all(r["_hash_ok"] for r in recs)
    p = repo.root / recs[0]["_path"]
    d = json.loads(p.read_text())
    d["recommendation"]["label"] = "tampered"
    p.write_text(json.dumps(d))
    assert A.decision_records(repo)[0]["_hash_ok"] is False


def test_ops_status_parse(repo):
    o = A.ops_status(repo)
    assert o["available"] and o["decision"].startswith("none") and o["commits_not_pushed"] == 3
    assert o["next window opens"].startswith("Thu")


def test_contracts_and_safe_join():
    assert K.check("values", pd.DataFrame({"player_id": []})).missing
    left = pd.DataFrame({"espn_id": ["1", "2"]})
    right = pd.DataFrame({"espn_id": ["1", "1"], "x": [1, 2]})
    with pytest.raises(Exception):
        K.safe_join(left, right, ["espn_id"])
    assert len(K.unique_key(right, ["espn_id"])) == 2


def test_league_teams_by_id_not_name(repo):
    values = A.valuation_table(A.latest_valuation(repo), "values")
    roster = A.league_roster(A.latest_league_snapshot(repo))
    roster.loc[0, "player_name"] = "Somebody Else"  # names never drive the join
    t, issues = P.attach_league_teams(values, roster)
    assert t.set_index("espn_id").loc["1001", "league_team"] == "Team One"
    assert t.set_index("espn_id").loc["1005", "league_team"] == "Free agent"
    assert not issues


def test_duplicate_roster_ids_are_reported(repo):
    values = A.valuation_table(A.latest_valuation(repo), "values")
    roster = A.league_roster(A.latest_league_snapshot(repo))
    roster = pd.concat([roster, roster.iloc[[0]].assign(team_id=2, team_name="Team Two")])
    t, issues = P.attach_league_teams(values, roster)
    assert len(t) == len(values) and issues
    assert pd.isna(t.set_index("espn_id").loc["1001", "league_team_id"])


def test_filter_players(repo):
    values = A.valuation_table(A.latest_valuation(repo), "values")
    t, _ = P.attach_league_teams(values, A.league_roster(A.latest_league_snapshot(repo)))
    assert len(P.filter_players(t, q="charlie")) == 1
    assert len(P.filter_players(t, q="1004")) == 1
    assert set(P.filter_players(t, pos=["WR"])["espn_name"]) == {"Charlie WR", "Echo WR"}
    assert set(P.filter_players(t, own=["Free agents"])["espn_id"]) == {"1004", "1005"}
    assert set(P.filter_players(t, own=["My team"], my_team_name="Team One")["espn_id"]) == {"1001", "1002"}


def test_research_parsers(repo):
    assert list(R.milestones(repo)["id"]) == ["F0", "R1"]
    assert R.experiment_results(repo).iloc[0]["Classification"] == "supported"
    reg = R.registries(repo)
    assert reg.iloc[0]["lineage"] == "M1" and reg.iloc[0]["frozen_commit"] == "deadbeef"
    assert R.frozen_params(repo).iloc[0]["pre_registration"] == "E18"
    assert [h for h, _ in R.log_sections(repo.research / "experiment_log.md")] == ["E1 Test", "E2 Second"]
    assert 2026 in R.contamination(repo)["sealed_seasons"]


def test_md_tables_ragged_rows():
    t = R.md_tables("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |\n")[0]
    assert t.shape == (2, 2)
