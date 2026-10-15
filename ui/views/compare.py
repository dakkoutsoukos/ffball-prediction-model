"""Compare 2–4 players side by side, all from one valuation run and one distribution archive."""
import altair as alt
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import playerdata as P
from ffui import state as S

C.page_header("Compare players", "Side by side on the same valuation run, scoring and horizon.")

runs = S.valuation_runs()
if not runs:
    C.empty_state("No valuation run", "Run `Rscript scripts/valuation_run.R --league`.")
    st.stop()
run = runs[-1]
table, issues = P.player_table(run)
if table is None:
    st.error("The values table is missing required columns: " + ", ".join(issues))
    st.stop()

table["label"] = table["espn_name"].fillna(table["player_id"]) + " (" + table["position"] + ", " + table["team"].fillna("FA") + ")"
lab_to_id = dict(zip(table["label"], table["player_id"]))
pick = st.multiselect("Players (2–4)", list(lab_to_id), max_selections=4, placeholder="Type a name")
if len(pick) < 2:
    st.caption(f"Pick at least two players. All numbers come from valuation run {run.run_id} ({run.as_of_utc}).")
    st.stop()
ids = [lab_to_id[x] for x in pick]
sub = table[table["player_id"].isin(ids)].copy()

if sub["position"].nunique() > 1:
    st.info("Mixed positions: compare VOR (value over each position's replacement level), not raw points.",
            icon=":material/info:")

keep = ["position", "team", "league_team", "injury_status", "ros_points", "vor", "vor_regular", "vor_playoffs",
        "trade_value", "overall_rank", "position_rank", "current_week_points", "wins_added"]
wide = sub.set_index("label")[[c for c in keep if c in sub.columns]].T
st.dataframe(wide.astype(str), width="stretch")
st.caption("V1 values (adopted). Wins added appears only for players in a cached values3 run (shadow engine).")

c1, c2 = st.columns(2, gap="large")
with c1:
    st.markdown("**Weekly projections**")
    w = S.val_table(run, "weekly")
    if w is not None:
        pw = w[w["player_id"].isin(ids)].merge(sub[["player_id", "label"]], on="player_id", validate="many_to_one")
        st.altair_chart(alt.Chart(pw).mark_line(point=True).encode(
            x=alt.X("week:O", title="Week"), y=alt.Y("proj:Q", title="Projected points"),
            color=alt.Color("label:N", title=None, legend=alt.Legend(orient="bottom", columns=1)),
            tooltip=["label", "week", alt.Tooltip("proj:Q", format=".1f"), "opponent"]), width="stretch")
with c2:
    st.markdown("**This week's outcome ranges** (P0)")
    pods, prov = S.pods(run.run_id)
    if pods is None:
        C.empty_state("No distribution archive", "Written by the dispatcher after each capture.")
    else:
        pr = pods[pods["espn_id"].astype(str).isin(sub["espn_id"].astype(str))].merge(
            sub[["espn_id", "label"]].astype({"espn_id": str}), on="espn_id", validate="many_to_one")
        if pr.empty:
            st.caption("No distribution rows for these players this week.")
        else:
            base = alt.Chart(pr).encode(y=alt.Y("label:N", title=None))
            st.altair_chart((base.mark_rule(strokeWidth=2, color="#6baed6").encode(x=alt.X("q10:Q", title="Points (10–90% and median)"), x2="q90:Q")
                             + base.mark_bar(height=14, color="#2171b5").encode(x="q25:Q", x2="q75:Q")
                             + base.mark_tick(color="#08306b", thickness=3, size=18).encode(x="q50:Q",
                                tooltip=["label", alt.Tooltip("q50:Q", format=".1f"), alt.Tooltip("p_active:Q", format=".2f")]))
                            .properties(height=60 + 40 * len(pr)), width="stretch")
            st.caption("Thin line 10–90%, box 25–75%, tick median. pod_baseline_v0.")
            for n in prov.notes:
                st.warning(n)
C.provenance(None, {"Valuation run": run.run_id, "As of (UTC)": run.as_of_utc,
                    "Distribution source": prov.source if pods is not None and prov else "–"})
