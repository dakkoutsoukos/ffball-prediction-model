"""End-to-end checks on the REAL local archives and the REAL R adapter (opt-in: set FFUI_REAL=1).

Gate B (decision-record isolation): every exploratory op runs, and the committed manifests, the decision ledger,
the query archive and `git status` must be byte-identical afterwards. Assertions are on counts, states and hashes
only, so no league-private value is printed on failure.
"""
import hashlib
import os
import subprocess
import time
from pathlib import Path

import pytest

from conftest import REAL_REPO

pytestmark = pytest.mark.skipif(os.environ.get("FFUI_REAL") != "1", reason="set FFUI_REAL=1 to run on real archives")


def tree_hash(*roots: Path) -> str:
    h = hashlib.sha256()
    for root in roots:
        for p in sorted(root.rglob("*")) if root.exists() else []:
            if p.is_file():
                h.update(str(p.relative_to(REAL_REPO)).encode())
                h.update(p.read_bytes())
    return h.hexdigest()


def protected_state() -> dict:
    git = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all", "--", "archive", "R", "scripts", "models",
                          "research", "config", "renv.lock"], cwd=REAL_REPO, capture_output=True, text=True).stdout
    return {"manifests": tree_hash(REAL_REPO / "archive"), "ledger": tree_hash(REAL_REPO / "data/archive/decisions"),
            "league_analysis": tree_hash(REAL_REPO / "data/archive/league_analysis"),
            "models": tree_hash(REAL_REPO / "models"), "git": git}


@pytest.fixture(scope="module")
def runner(tmp_path_factory):
    from ffui.jobs import JobRunner
    from ffui.paths import Repo
    return JobRunner(Repo(REAL_REPO))


@pytest.fixture(scope="module")
def ctx(runner):
    from ffui import artifacts as A
    snap = A.latest_league_snapshot(runner.repo)
    job = runner.wait("context", {}, {"league_raw_sha256": snap.raw_sha256, "valuation_manifest": "e2e"})
    assert job.state in ("done", "cached"), job.message
    return job.result


def run(runner, op, params, ctx):
    from ffui.state import op_context
    t = time.time()
    job = runner.wait(op, params, op_context(ctx))
    return job, time.time() - t


def test_gate_b_exploratory_ops_leave_records_untouched(runner, ctx):
    before = protected_state()
    me = ctx["my_team"]
    pl = [p for p in ctx["players"] if p["team_id"] == me and not p["on_ir"]]
    other = next(t["team_id"] for t in ctx["teams"] if t["team_id"] != me)
    theirs = [p for p in ctx["players"] if p["team_id"] == other and not p["on_ir"]]
    pl.sort(key=lambda p: -(p["vor"] or 0))
    theirs.sort(key=lambda p: -(p["vor"] or 0))
    fa = sorted([p for p in ctx["players"] if p["free_agent"]], key=lambda p: -(p["ros_points"] or 0))
    cases = [
        ("health", {}),
        ("lineup", {"team": me, "overrides": [{"player_id": pl[0]["player_id"], "p_active": 0.0}]}),
        ("odds", {"sims": 2000, "bands": False, "add": [fa[0]["player_id"]], "drop": [pl[-1]["player_id"]]}),
        ("trade_eval", {"team_a": me, "give_a": [pl[2]["player_id"]], "team_b": other, "give_b": [theirs[2]["player_id"]],
                        "sims": 2000, "simulate": True, "horizon": "full"}),
        ("trade_search", {"team_b": other, "k": 2, "sims": 2000, "simulate": True}),
        ("trade_search", {"team_b": other, "k": 2, "sims": 2000, "simulate": False, "my_gain_only": True,
                          "sell_player": pl[1]["player_id"], "boost_pct": 20}),
        ("fa_board", {"k": 3, "per_pos": 4, "sims": 2000}),
        ("values3", {"sims": 2000}),
    ]
    times = {}
    for op, params in cases:
        job, dt = run(runner, op, params, ctx)
        assert job.state in ("done", "cached"), f"{op}: {job.state} {job.code}"
        assert job.meta["exploratory"] is True and job.meta["ledgered"] is False
        if params.get("sell_player"):
            c = job.result.get("candidates") or []
            assert all(params["sell_player"] in x["a_ids"].split(";") and x["delta_a"] > 0 for x in c)
        times[op] = round(dt, 1)
    after = protected_state()
    for k in before:
        assert before[k] == after[k], f"{k} changed"
    print("timings (s):", times)


def test_lineup_override_changes_availability_source(runner, ctx):
    me = ctx["my_team"]
    pid = next(p["player_id"] for p in ctx["players"] if p["team_id"] == me)
    job, _ = run(runner, "lineup", {"team": me, "overrides": [{"player_id": pid, "p_active": 0.0}], "now": "2026-10-15T20:00:00Z"}, ctx)
    assert "UI what-if overrides for 1 player" in job.result["prior_source"]
    row = [r for r in job.result["lineup"] if r["player_id"] == pid]
    assert row, "overridden player missing from the lineup table"


def test_bad_requests_are_refused(runner, ctx):
    job, _ = run(runner, "trade_eval", {"team_a": ctx["my_team"], "give_a": ["not-a-player"], "team_b": 1, "give_b": [],
                                        "simulate": False}, ctx)
    assert job.state == "failed" and job.code == 2
    job, _ = run(runner, "odds", {"sims": 999999}, ctx)
    assert job.state == "failed" and job.code == 2
    from ffui.state import op_context
    stale = {**op_context(ctx), "league_raw_sha256": "0" * 64}
    job = runner.wait("lineup", {"team": ctx["my_team"]}, stale)
    assert job.state == "failed" and job.code == 3


def test_research_target_guard(runner):
    job = runner.wait("research_target", {"name": "not_allowed"}, {})
    assert job.state == "failed" and job.code == 2
    job = runner.wait("research_target", {"name": "p3_gate_result"}, {})
    assert job.state in ("done", "cached", "failed")
    if job.state == "failed":
        assert job.code in (2, 4)  # 2 = refused by the sealed-season guard, 4 = unreadable target


def test_out_dir_outside_cache_refused():
    from ffui.paths import find_rscript
    r = subprocess.run([find_rscript(), str(REAL_REPO / "ui/r/ui_adapter.R"), "noop", "--out", str(REAL_REPO / "archive" / "x")],
                       cwd=REAL_REPO, capture_output=True, text=True, timeout=120)
    assert r.returncode == 2 and not (REAL_REPO / "archive" / "x").exists()


# ---------------------------------------------------------------- UI click-through on real data (AppTest)
def _app(page):
    import streamlit as st
    from streamlit.testing.v1 import AppTest
    from conftest import UI
    st.cache_resource.clear()
    st.cache_data.clear()
    at = AppTest.from_file(str(UI / "app.py"), default_timeout=180)
    at.run()
    at.switch_page(page)
    at.run()
    return at


def _click(at, label):
    next(b for b in at.button if b.label == label).click()
    at.run()
    return at


def _finish_job(at, op_hint=None, timeout=240):
    """Fragments do not tick inside AppTest: wait for the runner, then rerun the page so it shows the cached result."""
    from ffui import state as S
    r = S.runner()
    t = time.time()
    while r.lock_holder() and time.time() - t < timeout:
        time.sleep(0.5)
    at.run()
    return at


def test_ui_flows_trade_lineup_waivers_outlook():
    before = protected_state()
    at = _app("views/trade.py")
    if any(b.label == "Load league context" for b in at.button):
        _click(at, "Load league context")
    at.run()
    assert not at.exception
    give, get = at.multiselect[0], at.multiselect[1]
    give.select(give.options[1]); get.select(get.options[1])
    at.run()
    _click(at, "Evaluate trade")
    _finish_job(at)
    assert not at.exception, [e.message for e in at.exception]
    md = " ".join(m.value for m in at.markdown)
    assert "Utility (V2)" in md and "Season effects (S0)" in md

    at = _app("views/lineup.py")
    _click(at, "Recommend lineup")
    _finish_job(at)
    assert not at.exception and any(m.label.startswith("Expected points") for m in at.metric)

    at = _app("views/outlook.py")
    _click(at, "Simulate the season")
    _finish_job(at)
    assert not at.exception and any("Season odds" in m.value and "exploratory" in m.value for m in at.markdown)

    at = _app("views/waivers.py")
    _click(at, "Build the free-agent board")
    _finish_job(at)
    assert not at.exception and any("computed now" in m.value for m in at.markdown)

    for p in ["views/home.py", "views/players.py", "views/compare.py", "views/research.py", "views/operations.py"]:
        at = _app(p)
        assert not at.exception, p
    assert protected_state() == before
