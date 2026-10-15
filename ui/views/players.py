"""Player Explorer: the latest valuation run (V1 values), league ownership from the snapshot, P0 distributions."""
import altair as alt
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import contracts as K
from ffui import playerdata as P
from ffui import state as S

C.page_header("Player Explorer", "Search, filter and rank every player in the latest valuation run.")

runs = S.valuation_runs()
if not runs:
    C.empty_state("No valuation run", "Run `Rscript scripts/valuation_run.R --league` (the dispatcher also captures runs).")
    st.stop()

labels = {f"{r.run_id} · week {r.week} · {r.methodology_version}": r for r in reversed(runs)}
with st.sidebar:
    run = labels[st.selectbox("Valuation run", list(labels), help="Latest first. Values are never mixed across runs.")]

table, issues = P.player_table(run)
if table is None:
    st.error("The values table of this run is missing or lacks required columns: " + ", ".join(issues))
    st.stop()
for msg in issues:
    st.warning(msg)

# ---------------------------------------------------------------- filters
f = st.columns([2, 1.2, 1.2, 1.4])
q = f[0].text_input("Search", placeholder="Player name or ESPN id", label_visibility="collapsed")
pos = f[1].multiselect("Position", sorted(table["position"].dropna().unique()), placeholder="All positions")
nfl = f[2].multiselect("NFL team", sorted(table["team"].dropna().unique()), placeholder="All NFL teams")
owners = ["Free agents", "My team"] + sorted(t for t in table["league_team"].dropna().unique() if t != "Free agent")
own = f[3].multiselect("League team", owners, placeholder="Anyone")

view = P.filter_players(table, q, pos, nfl, own, my_team_name=P.my_team_name())
st.caption(f"{len(view)} of {len(table)} players · run {run.run_id} as of {run.as_of_utc} · "
           f"values hash {'verified' if S.values_hash_ok(run) else 'NOT verified' if S.values_hash_ok(run) is False else 'n/a'}")

cols = ["espn_name", "position", "team", "league_team", "injury_status", "ros_points", "vor", "vor_regular",
        "vor_playoffs", "trade_value", "overall_rank", "position_rank", "current_week_points", "wins_added"]
cols = [c for c in cols if c in view.columns]
event = st.dataframe(
    view[cols], hide_index=True, width="stretch", height=460, on_select="rerun", selection_mode="single-row",
    column_config={
        "espn_name": "Player", "team": "NFL", "league_team": "League team", "injury_status": "Status",
        "ros_points": st.column_config.NumberColumn("ROS pts", format="%.1f", help="V1 rest-of-season points (adopted)."),
        "vor": st.column_config.NumberColumn("VOR", format="%.1f", help="V1 value over replacement, rest of season (adopted)."),
        "vor_regular": st.column_config.NumberColumn("VOR reg.", format="%.1f"),
        "vor_playoffs": st.column_config.NumberColumn("VOR playoffs", format="%.1f"),
        "trade_value": st.column_config.ProgressColumn("Trade value", min_value=0, max_value=100, format="%.0f"),
        "overall_rank": "Rank", "position_rank": "Pos. rank",
        "current_week_points": st.column_config.NumberColumn("This week", format="%.1f"),
        "wins_added": st.column_config.NumberColumn("Wins added", format="%.2f",
                                                    help="S3 (adopted metric, shadow engine); only for players in a cached values3 run (Lineup Lab ▸ values)."),
    })

sel = event.selection.rows if event and event.selection else []
if not sel:
    st.caption("Select a row for the player's weekly projections, outcome distribution and value history.")
    st.stop()
player = view.iloc[sel[0]]

# ---------------------------------------------------------------- player detail
st.divider()
st.subheader(f"{player['espn_name']} · {player['position']} · {player['team']}")
m = st.columns(5)
m[0].metric("ROS points", C.fmt_num(player.get("ros_points")))
m[1].metric("VOR", C.fmt_num(player.get("vor")))
m[2].metric("Overall rank", f"{int(player['overall_rank'])}" if pd.notna(player.get("overall_rank")) else "–")
m[3].metric("League team", player.get("league_team") or "–")
m[4].metric("Status", player.get("injury_status") or "Active")
st.caption("Values are V1 (adopted): ESPN posted future weeks through the VE1 transform; replacement level in this league's format.")

a, b = st.columns(2, gap="large")
with a:
    st.markdown("**Weekly projections** (this run)")
    w = S.val_table(run, "weekly")
    if w is None or not K.check("weekly", w).ok:
        C.empty_state("No weekly table", "This run has no usable weekly.parquet.")
    else:
        pw = w[w["player_id"] == player["player_id"]].sort_values("week")
        if pw.empty:
            st.caption("No weekly rows for this player in this run.")
        else:
            ch = alt.Chart(pw).mark_bar().encode(
                x=alt.X("week:O", title="Week"), y=alt.Y("proj:Q", title="Projected points"),
                color=alt.condition("datum.has_game", alt.value("#1f5f99"), alt.value("#bbbbbb")),
                tooltip=["week", alt.Tooltip("proj:Q", format=".1f"), "opponent", "source", alt.Tooltip("p_active:Q", format=".2f")])
            st.altair_chart(ch, width="stretch")
            st.caption("Grey: no game (bye). Projection source per week in the tooltip; P(active) from the frozen P1 provider.")
with b:
    st.markdown("**This week's outcome distribution** (P0)")
    pods, prov = S.pods(run.run_id)
    if pods is None:
        C.empty_state("No distribution archive", "The dispatcher writes P0 distributions after each capture.")
    else:
        pr = pods[pods["espn_id"].astype(str) == str(player["espn_id"])]
        if pr.empty:
            st.caption("No distribution row for this player (no game this week, or outside the captured pool).")
        else:
            st.altair_chart(P.fan_chart(pr.iloc[0]), width="stretch")
            r0 = pr.iloc[0]
            st.caption(f"Week {int(r0['week'])}: median {r0['q50']:.1f}, 10–90% range {r0['q10']:.1f}–{r0['q90']:.1f}, "
                       f"mean {r0['mean']:.1f}; P(active) {r0['p_active']:.2f}. pod_baseline_v0 (frozen; P2 failed, so P0 stays).")
            for n in prov.notes:
                st.warning(n)

st.markdown("**Value across valuation runs**")
h = S.value_history()
hp = h[h["player_id"] == player["player_id"]] if not h.empty else h
if hp.empty or hp["run_id"].nunique() < 2:
    st.caption("History is accruing: fewer than two valuation runs contain this player so far.")
else:
    st.altair_chart(alt.Chart(hp).mark_line(point=True).encode(
        x=alt.X("as_of_utc:N", title="Valuation run (UTC)"), y=alt.Y("vor:Q", title="VOR"),
        tooltip=["run_id", "week", alt.Tooltip("vor:Q", format=".1f"), alt.Tooltip("ros_points:Q", format=".1f")]),
        width="stretch")
C.provenance(None, {"Valuation run": run.run_id, "As of (UTC)": run.as_of_utc, "Methodology": run.methodology_version,
                    "Source": run.provenance.source, "Distribution source": prov.source if pods is not None and prov else "–",
                    "Player id (gsis)": player.get("gsis_id"), "ESPN id": player.get("espn_id")})
