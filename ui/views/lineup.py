"""Lineup Lab: D0 expected-points lineup with game-time plans, availability what-ifs, and S3 roster values."""
from datetime import datetime, timezone

import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L
from ffui import state as S

C.page_header("Lineup Lab", "This week's lineup, start/sit what-ifs and your roster's wins added.")
ctx = C.need_context("lineup")
if not ctx:
    st.stop()
players = S.players_frame(ctx)
names = S.team_names(ctx)
me = ctx.get("my_team")

tab_lineup, tab_values = st.tabs(["Lineup", "Roster values (wins added)"])

with tab_lineup:
    o = st.columns([1.4, 1.2, 1.2])
    team = o[0].selectbox("Team", list(names), index=list(names).index(me) if me in names else 0,
                          format_func=lambda t: names[t] + (" (you)" if t == me else ""))
    fixed = o[1].toggle("Use the published prior", value=False,
                        help="Off: P(active) from the frozen P1 provider (E19c), as the CLI does. On: the fixed designation prior.")
    when = o[2].text_input("As of (UTC)", value="", placeholder="now, or 2026-10-18T14:00:00Z",
                           help="The lineup's clock: players whose game has kicked off are locked.")
    roster = players[players["team_id"] == team].sort_values("ros_points", ascending=False)
    st.markdown("**Availability what-if** (optional): set a player's chance of playing; leave blank to use the model.")
    ed = st.data_editor(pd.DataFrame({"player_id": roster["player_id"], "Player": roster["player_name"],
                                      "Pos": roster["position"], "P(active) override": [None] * len(roster)}),
                        hide_index=True, width="stretch", disabled=["player_id", "Player", "Pos"],
                        column_config={"player_id": None, "P(active) override": st.column_config.NumberColumn(
                            min_value=0.0, max_value=1.0, step=0.05, format="%.2f")}, key=f"ovr_{team}")
    ov = ed.dropna(subset=["P(active) override"])
    params = {"team": int(team), "fixed_prior": fixed,
              "overrides": [{"player_id": r["player_id"], "p_active": float(r["P(active) override"])} for r in ov.to_dict("records")]}
    if when.strip():
        try:
            datetime.strptime(when.strip(), "%Y-%m-%dT%H:%M:%SZ")
            params["now"] = when.strip()
        except ValueError:
            st.error("Use the form 2026-10-18T14:00:00Z, or leave it blank for now.")
            st.stop()
    else:
        params["now"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:00:00Z")  # hour resolution keeps the cache useful
    job = C.job_control(f"lineup_{team}", "lineup", params, ctx, "Recommend lineup")
    if job and job.result:
        res = job.result
        h = st.columns([3, 1])
        with h[1]:
            C.badge(L.EXPLORATORY)
        h[0].markdown(f"**Week {res['week']} lineup** as of {res['now']} UTC")
        c = st.columns(3)
        c[0].metric("Expected points (recommended)", C.fmt_num(res["ev_recommended"]))
        c[1].metric("Current ESPN lineup", C.fmt_num(res["ev_current"]),
                    f"{res['ev_recommended'] - res['ev_current']:+.1f} from changes" if res["ev_current"] is not None else None)
        c[2].metric("Overrides applied", len(params["overrides"]))
        lu = pd.DataFrame(res["lineup"])
        st.dataframe(lu[["slot", "player", "position", "nfl", "kickoff_utc", "proj", "status", "locked", "espn_slot", "change"]],
                     hide_index=True, width="stretch", column_config={
                         "slot": "Slot", "player": "Player", "nfl": "NFL", "kickoff_utc": "Kickoff (UTC)",
                         "proj": st.column_config.NumberColumn("Proj.", format="%.1f"), "espn_slot": "ESPN slot now",
                         "change": "Change"})
        C.metric_badge("lineup")
        st.caption(f"P(active) source: {res['prior_source']}. Flexible slots hold the latest kickoffs (no change in expected points). "
                   "Projections are this week's (pre-inactive).")
        plan = pd.DataFrame(res.get("plan") or [])
        st.markdown("**Game-time plans**")
        if plan.empty:
            st.caption("No designated starters: no game-time plan needed.")
        else:
            st.dataframe(plan, hide_index=True, width="stretch")
        with st.expander("Late-window swaps"):
            C.badge(L.INFORMATIONAL)
            st.caption("Late-window swap advice was not supported by its checks (X8/X9, VL11) and needs live box scores; "
                       "it is not offered as a recommendation.")
        C.provenance(job.meta)

with tab_values:
    st.caption("Wins added by removing each player (common random numbers; the vacated slot is streamed). Primary display "
               "metric per VL7/VL11 (X10b), computed on the shadow S0 engine. About 30–60 s.")
    team2 = st.selectbox("Team", list(names), index=list(names).index(me) if me in names else 0,
                         format_func=lambda t: names[t] + (" (you)" if t == me else ""), key="values_team")
    sims = st.selectbox("Simulations", [2000, 5000], index=1, key="values_sims")
    job = C.job_control(f"values3_{team2}", "values3", {"team": int(team2), "sims": sims}, ctx, "Compute roster values")
    if job and job.result:
        res = job.result
        C.badge(L.SHADOW)
        v = pd.DataFrame(res["values"]).sort_values("wins_added", ascending=False)
        st.dataframe(v[["player", "position", "wins_added", "playoffs_value", "title_value", "evor", "vor", "trade_value"]],
                     hide_index=True, width="stretch", column_config={
                         "wins_added": st.column_config.NumberColumn("Wins added", format="%.2f"),
                         "playoffs_value": st.column_config.NumberColumn("P(playoffs) value", format="percent"),
                         "title_value": st.column_config.NumberColumn("P(title) value", format="percent"),
                         "evor": st.column_config.NumberColumn("EVOR", format="%.1f"),
                         "vor": st.column_config.NumberColumn("V1 VOR", format="%.1f"),
                         "trade_value": st.column_config.NumberColumn("Trade value", format="%.0f")})
        risk = res.get("risk") or {}
        if risk:
            st.markdown(f"**Roster risk**: top two players supply {C.fmt_pct(risk.get('top2_share'), 0)} of expected lineup "
                        f"points; the largest single-player P(playoffs) value is {C.fmt_pct(risk.get('max_playoffs_value'))}.")
            holes = pd.DataFrame(risk.get("holes") or [])
            if not holes.empty:
                st.warning("Weeks with a starting slot and no playing roster player:")
                st.dataframe(holes, hide_index=True, width="stretch")
        C.provenance(job.meta)
