"""Player tables for the explorer and comparison pages (pure functions on DataFrames; tested without Streamlit)."""
from __future__ import annotations

import altair as alt
import pandas as pd

from . import contracts as K

QUANTS = ["q05", "q10", "q25", "q50", "q75", "q90", "q95"]


def attach_league_teams(values: pd.DataFrame, roster: pd.DataFrame | None) -> tuple[pd.DataFrame, list[str]]:
    """League ownership by ESPN id (never by name). Duplicate ESPN ids in the roster are reported, not fanned out."""
    issues: list[str] = []
    v = values.copy()
    if roster is None or roster.empty:
        v["league_team"] = pd.NA
        v["league_team_id"] = pd.NA
        issues.append("No league snapshot: league ownership is not shown.")
        return v, issues
    r = roster[["espn_id", "team_id", "team_name"]].copy()
    r["espn_id"] = r["espn_id"].astype(str)
    dup = K.unique_key(r, ["espn_id"])
    if not dup.empty:
        issues.append(f"{dup['espn_id'].nunique()} ESPN id(s) appear on more than one roster in the snapshot; "
                      "their league team is left blank.")
        r = r[~r["espn_id"].isin(dup["espn_id"])]
    v["espn_id"] = v["espn_id"].astype(str)
    v = v.merge(r.rename(columns={"team_id": "league_team_id", "team_name": "league_team"}), on="espn_id",
                how="left", validate="many_to_one")
    v["league_team"] = v["league_team"].fillna("Free agent")
    return v, issues


def player_table(run, roster: pd.DataFrame | None = None, wins: pd.DataFrame | None = None):
    from . import state as S  # local import: keeps this module importable without a Streamlit session
    values = S.val_table(run, "values")
    res = K.check("values", values)
    if values is None or not res.ok:
        return None, res.missing
    issues: list[str] = []
    dup = K.unique_key(values, ["player_id"])
    if not dup.empty:
        issues.append(f"{dup['player_id'].nunique()} player id(s) are duplicated in the values table; the first row is used.")
        values = values.drop_duplicates("player_id")
    roster = S.league_roster() if roster is None else roster
    t, more = attach_league_teams(values, roster)
    issues += more
    wins = wins if wins is not None else cached_wins_added()
    if wins is not None and not wins.empty:
        t = t.merge(wins[["player_id", "wins_added"]].drop_duplicates("player_id"), on="player_id", how="left", validate="many_to_one")
    return t.sort_values("overall_rank").reset_index(drop=True), issues


def cached_wins_added() -> pd.DataFrame | None:
    """Wins added from the newest cached values3 result for the current context (UI cache only)."""
    from . import state as S
    import json
    root = S.repo().ui_cache / "values3"
    ctx = S.league_context(load=False)
    if not root.exists() or not ctx:
        return None
    want = ctx.get("inputs", {}).get("league_raw_sha256")
    best = None
    for meta_p in root.glob("*/meta.json"):
        meta = json.loads(meta_p.read_text(encoding="utf-8"))
        if (meta.get("inputs") or {}).get("league_raw_sha256") != want:
            continue
        if best is None or meta.get("started_at_utc", "") > best[0]:
            best = (meta.get("started_at_utc", ""), meta_p.parent / "result.json")
    if not best:
        return None
    res = json.loads(best[1].read_text(encoding="utf-8"))
    return pd.DataFrame(res.get("values") or [])


def my_team_name() -> str | None:
    from . import state as S
    ctx = S.league_context(load=False)
    if ctx:
        return S.team_names(ctx).get(ctx.get("my_team"))
    d = S.latest_decision("odds")
    roster = S.league_roster()
    if d and roster is not None and d["recommendation"].get("leverage"):
        tid = d["recommendation"]["leverage"][0]["team_id"]
        hit = roster[roster["team_id"] == tid]
        return hit["team_name"].iloc[0] if len(hit) else None
    return None


def filter_players(t: pd.DataFrame, q: str = "", pos=(), nfl=(), own=(), my_team_name: str | None = None) -> pd.DataFrame:
    v = t
    if q:
        ql = q.strip().lower()
        v = v[v["espn_name"].fillna("").str.lower().str.contains(ql, regex=False) | (v["espn_id"].astype(str) == ql)]
    if pos:
        v = v[v["position"].isin(pos)]
    if nfl:
        v = v[v["team"].isin(nfl)]
    if own:
        keep = set(own) - {"Free agents", "My team"}
        mask = v["league_team"].isin(keep)
        if "Free agents" in own:
            mask |= v["league_team"] == "Free agent"
        if "My team" in own and my_team_name:
            mask |= v["league_team"] == my_team_name
        v = v[mask]
    return v


def fan_chart(row: pd.Series) -> alt.Chart:
    q = {k: float(row[k]) for k in QUANTS if k in row and pd.notna(row[k])}
    bands = pd.DataFrame([
        {"band": "5–95%", "lo": q.get("q05"), "hi": q.get("q95"), "order": 1},
        {"band": "10–90%", "lo": q.get("q10"), "hi": q.get("q90"), "order": 2},
        {"band": "25–75%", "lo": q.get("q25"), "hi": q.get("q75"), "order": 3},
    ]).dropna()
    base = alt.Chart(bands).mark_bar(height=26).encode(
        x=alt.X("lo:Q", title="Fantasy points this week"), x2="hi:Q",
        y=alt.Y("band:N", sort=alt.SortField("order"), title=None),
        color=alt.Color("order:O", scale=alt.Scale(range=["#c6dbef", "#6baed6", "#2171b5"]), legend=None),
        tooltip=["band", alt.Tooltip("lo:Q", format=".1f"), alt.Tooltip("hi:Q", format=".1f")])
    med = alt.Chart(pd.DataFrame({"q50": [q.get("q50")]})).mark_rule(color="#08306b", strokeWidth=2).encode(x="q50:Q")
    return (base + med).properties(height=130)


def compare_frame(t: pd.DataFrame, ids: list[str]) -> pd.DataFrame:
    keep = ["espn_name", "position", "team", "league_team", "ros_points", "vor", "vor_regular", "vor_playoffs",
            "trade_value", "overall_rank", "position_rank", "current_week_points", "injury_status", "wins_added"]
    sub = t[t["player_id"].isin(ids)]
    return sub[[c for c in keep if c in sub.columns]].set_index("espn_name").T
