"""Shared, cached data context for all pages. File reads are cached on (path, mtime, size); R results on their
deterministic job key. Nothing here starts an R job except `league_context(load=True)`, which pages call only
from an explicit button (or when the result is already cached)."""
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import streamlit as st

from . import artifacts as A
from .jobs import JobRunner, git_head
from .paths import Repo, default_repo


@st.cache_resource
def repo() -> Repo:
    return default_repo()


@st.cache_resource
def runner() -> JobRunner:
    r = JobRunner(repo())
    r.recover()
    return r


def stamp(p: Path) -> tuple:
    try:
        s = p.stat()
        return (str(p), s.st_mtime_ns, s.st_size)
    except OSError:
        return (str(p), 0, 0)


def manifests_stamp() -> tuple:
    rp = repo()
    return tuple(stamp(p) for p in sorted(rp.manifests.glob("*.csv")))


@st.cache_data(show_spinner=False)
def _snapshot(_stamp: tuple) -> A.LeagueSnapshot | None:
    return A.latest_league_snapshot(repo())


def snapshot() -> A.LeagueSnapshot | None:
    return _snapshot(manifests_stamp())


@st.cache_data(show_spinner=False)
def _valuation_runs(_stamp: tuple) -> list[A.ValuationRun]:
    return A.valuation_runs(repo())


def valuation_runs() -> list[A.ValuationRun]:
    return _valuation_runs(manifests_stamp())


@st.cache_data(show_spinner=False)
def _val_table(run_dir: str, name: str, _stamp: tuple) -> pd.DataFrame | None:
    p = Path(run_dir) / f"{name}.parquet"
    return A.read_parquet(p) if p.exists() else None


def val_table(run: A.ValuationRun, name: str) -> pd.DataFrame | None:
    return _val_table(str(run.dir), name, stamp(run.dir / f"{name}.parquet"))


@st.cache_data(show_spinner=False)
def _values_hash_ok(path: str, expected: str | None, _stamp: tuple) -> bool | None:
    return None if not expected else A.sha256_file(Path(path)) == expected


def values_hash_ok(run: A.ValuationRun) -> bool | None:
    p = run.dir / "values.parquet"
    return _values_hash_ok(str(p), run.values_sha256, stamp(p))


@st.cache_data(show_spinner=False)
def _pods(valuation_run_id: str | None, _stamp: tuple):
    return A.latest_pods(repo(), valuation_run_id)


def pods(valuation_run_id: str | None = None):
    return _pods(valuation_run_id, manifests_stamp())


@st.cache_data(show_spinner=False)
def _history(_stamp: tuple) -> pd.DataFrame:
    return A.value_history(repo())


def value_history() -> pd.DataFrame:
    return _history(manifests_stamp())


@st.cache_data(show_spinner=False)
def _roster(path: str, _stamp: tuple) -> pd.DataFrame:
    return A.read_parquet(Path(path))


def league_roster() -> pd.DataFrame | None:
    s = snapshot()
    if not s or not s.roster_path:
        return None
    return _roster(str(s.roster_path), stamp(s.roster_path))


@st.cache_data(show_spinner=False)
def _decisions(alias: str | None, _stamp: tuple) -> list[dict]:
    return A.decision_records(repo(), alias)


def decisions(alias: str | None = None) -> list[dict]:
    return _decisions(alias, manifests_stamp())


def latest_decision(dtype: str) -> dict | None:
    s = snapshot()
    recs = [d for d in decisions(s.alias if s else None) if d.get("type") == dtype]
    return recs[-1] if recs else None


@st.cache_data(show_spinner=False)
def _analysis(alias: str | None, _stamp: tuple):
    return A.latest_league_analysis(repo(), alias)


def league_analysis():
    s = snapshot()
    root = repo().league_analysis
    return _analysis(s.alias if s else None, tuple(stamp(p) for p in sorted(root.glob("*/season=*/run=*"))) if root.exists() else ())


def ops_status() -> dict:
    return A.ops_status(repo())


# ---------------------------------------------------------------- league context (R, cheap, cached by snapshot)
def context_request() -> tuple[dict, dict]:
    s = snapshot()
    runs = valuation_runs()
    ctx = {"league_raw_sha256": s.raw_sha256 if s else None,
           "valuation_manifest": f"{len(runs)}:{runs[-1].run_id if runs else ''}"}
    return {}, ctx


def league_context(load: bool = False) -> dict | None:
    """The league model's view (players with ids, rosters, standings, schedule). Returns the cached result if one
    exists for the current snapshot and valuation runs; runs the ~4 s `context` op only when load=True."""
    params, ctx = context_request()
    if not ctx["league_raw_sha256"]:
        return None
    r = runner()
    key = r.key_for("context", params, ctx)
    hit = r.cached("context", key)
    if hit:
        return {**hit.result, "_meta": hit.meta}
    if not load:
        return None
    job = r.wait("context", params, ctx)
    if job.result:
        return {**job.result, "_meta": job.meta}
    st.session_state["context_error"] = job.message
    return None


def op_context(ctx: dict) -> dict:
    """The context every computational op checks (exit 3 if the league snapshot or valuation run changed)."""
    i = ctx.get("inputs", {})
    return {"league_raw_sha256": i.get("league_raw_sha256"), "valuation_run_id": i.get("valuation_run_id")}


def players_frame(ctx: dict) -> pd.DataFrame:
    p = pd.DataFrame(ctx.get("players", []))
    teams = pd.DataFrame(ctx.get("teams", []))
    if not p.empty and not teams.empty:
        p = p.merge(teams[["team_id", "team_name"]], on="team_id", how="left", validate="many_to_one")
        p["team_name"] = p["team_name"].fillna("Free agent")
    return p


def team_names(ctx: dict) -> dict[int, str]:
    return {int(t["team_id"]): t.get("team_name") or f"Team {t['team_id']}" for t in ctx.get("teams", [])}


@dataclass
class Freshness:
    snapshot_age_h: float | None
    snapshot_at: str | None
    valuation_run: str | None
    valuation_as_of: str | None
    head: str


def freshness() -> Freshness:
    s = snapshot()
    runs = valuation_runs()
    return Freshness(A.age_hours(s.captured) if s else None, s.captured_at_utc if s else None,
                     runs[-1].run_id if runs else None, runs[-1].as_of_utc if runs else None, git_head(repo())[:7])


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def demo_mode() -> bool:
    return os.environ.get("FFUI_DEMO") == "1"
