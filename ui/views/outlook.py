"""Season Outlook: standings, remaining schedule, shadow odds with sensitivity bands, add/drop scenarios."""
import altair as alt
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L
from ffui import state as S

C.page_header("Season Outlook", "Standings, schedule and playoff/title odds.")
st.warning("Playoff and title odds are **Shadow / Unvalidated**: " + L.SHADOW.meaning, icon=":material/science:")

ctx = C.need_context("outlook")
if not ctx:
    st.stop()
names = S.team_names(ctx)
me = ctx.get("my_team")
lab = lambda t: names.get(int(t), f"Team {t}") + (" (you)" if int(t) == me else "")  # noqa: E731

tab_odds, tab_table, tab_sched, tab_hist = st.tabs(["Odds", "Standings & strength", "Schedule", "Odds history"])

with tab_odds:
    o = st.columns([1, 1, 2, 2])
    sims = o[0].selectbox("Simulations", [5000, 10000], index=1)
    bands = o[1].toggle("Sensitivity bands", value=True, help="4 × 2,000 extra simulations (σ_L × 0.5/1.5, noise × 0.8/1.2; VL3).")
    pl = S.players_frame(ctx)
    mine = pl[pl["team_id"] == me]
    fa = pl[pl["free_agent"]].sort_values("ros_points", ascending=False).head(150)
    add = o[2].multiselect("What-if: add", list(fa["player_id"]), format_func=lambda x: fa.set_index("player_id").loc[x, "player_name"],
                           help="Free agents (top 150 by ROS points) added to your roster.")
    drop = o[3].multiselect("What-if: drop", list(mine["player_id"]), format_func=lambda x: mine.set_index("player_id").loc[x, "player_name"])
    params = {"sims": sims, "bands": bands, "add": add, "drop": drop}
    job = C.job_control("odds", "odds", params, ctx, "Simulate the season", "About 10–20 s.")
    res = job.result if job else None
    src = "exploratory"
    if not res:
        led = S.latest_decision("odds")
        if led:
            res, src = led["recommendation"], f"ledgered {led['as_of_utc']}"
    if res:
        h = st.columns([3, 1])
        h[0].markdown(f"**Season odds** · {src}")
        with h[1]:
            C.badge(L.SHADOW)
        t = pd.DataFrame(res["teams"])
        t["team"] = t["team_id"].map(lab)
        b = pd.DataFrame(res.get("bands") or [])
        if not b.empty:
            rng = b.groupby("team_id").agg(pp_lo=("p_playoffs", "min"), pp_hi=("p_playoffs", "max"),
                                           pt_lo=("p_title", "min"), pt_hi=("p_title", "max")).reset_index()
            t = t.merge(rng, on="team_id", how="left", validate="one_to_one")
        t = t.sort_values("p_title", ascending=False)
        cols = [c for c in ["team", "e_wins", "p_playoffs", "pp_lo", "pp_hi", "p_seed1", "p_title", "pt_lo", "pt_hi", "mc_se_playoffs"] if c in t]
        st.dataframe(t[cols], hide_index=True, width="stretch", column_config={
            "e_wins": st.column_config.NumberColumn("E[wins]", format="%.2f"),
            "p_playoffs": st.column_config.NumberColumn("P(playoffs)", format="percent"),
            "pp_lo": st.column_config.NumberColumn("band low", format="percent"),
            "pp_hi": st.column_config.NumberColumn("band high", format="percent"),
            "p_seed1": st.column_config.NumberColumn("P(1 seed)", format="percent"),
            "p_title": st.column_config.NumberColumn("P(title)", format="percent"),
            "pt_lo": st.column_config.NumberColumn("band low", format="percent"),
            "pt_hi": st.column_config.NumberColumn("band high", format="percent"),
            "mc_se_playoffs": st.column_config.NumberColumn("MC s.e.", format="%.4f")})
        if not b.empty:
            ch = alt.Chart(t).encode(y=alt.Y("team:N", sort="-x", title=None))
            st.altair_chart((ch.mark_rule(strokeWidth=6, color="#c6dbef").encode(x=alt.X("pp_lo:Q", title="P(playoffs) with sensitivity band", axis=alt.Axis(format="%")), x2="pp_hi:Q")
                             + ch.mark_point(filled=True, color="#08306b", size=60).encode(x="p_playoffs:Q",
                                tooltip=["team", alt.Tooltip("p_playoffs:Q", format=".1%"), alt.Tooltip("pp_lo:Q", format=".1%"), alt.Tooltip("pp_hi:Q", format=".1%")]))
                            .properties(height=40 * len(t)), width="stretch")
        m = pd.DataFrame(res.get("matchups") or [])
        if not m.empty:
            st.markdown(f"**This week's matchups** (period {res.get('current_period', '–')})")
            m["home"], m["away"] = m["home"].map(lab), m["away"].map(lab)
            st.dataframe(m, hide_index=True, width="stretch", column_config={
                "p_home": st.column_config.NumberColumn("P(home wins)", format="percent"),
                "margin_q10": st.column_config.NumberColumn("margin 10%", format="%.1f"),
                "margin_q50": st.column_config.NumberColumn("median margin", format="%.1f"),
                "margin_q90": st.column_config.NumberColumn("margin 90%", format="%.1f")})
        lev = (res.get("leverage") or [None])[0]
        if lev:
            st.caption(f"Your leverage: P(playoffs) {C.fmt_pct(lev['p_playoffs_if_win'])} with a win this week vs "
                       f"{C.fmt_pct(lev['p_playoffs_if_loss'])} with a loss.")
        wi = pd.DataFrame(res.get("what_if") or [])
        if not wi.empty:
            r = wi[wi["team_id"] == me]
            if len(r):
                st.success(f"What-if (common random numbers): your P(playoffs) changes by {C.fmt_pct(r['d_playoffs'].iloc[0])}, "
                           f"P(title) by {C.fmt_pct(r['d_title'].iloc[0])}.")
        st.caption("ESPN's own playoff odds are not provided for this league (X-004).")
        if job:
            C.provenance(job.meta)

with tab_table:
    sd = pd.DataFrame(ctx.get("standings") or [])
    tu = pd.DataFrame(ctx.get("team_utility") or [])
    if sd.empty:
        C.empty_state("No standings in the snapshot", "The league snapshot needs view=mMatchup (scripts/league_refresh.R).")
    else:
        sd = sd.merge(tu, on="team_id", how="left", validate="one_to_one") if not tu.empty else sd
        sd["team"] = sd["team_id"].map(lab)
        sd = sd.sort_values(["wins", "points_for"], ascending=False)
        st.dataframe(sd[[c for c in ["team", "wins", "losses", "ties", "points_for", "points_against", "games_back",
                                     "playoff_seed", "waiver_rank", "U", "U_regular", "U_playoffs"] if c in sd]],
                     hide_index=True, width="stretch", column_config={
                         "U": st.column_config.NumberColumn("Roster strength U", format="%.0f",
                                                            help="V2 expected rest-of-season lineup points (adopted)."),
                         "U_regular": st.column_config.NumberColumn("U regular", format="%.0f"),
                         "U_playoffs": st.column_config.NumberColumn("U playoffs", format="%.0f"),
                         "points_for": st.column_config.NumberColumn("PF", format="%.1f"),
                         "points_against": st.column_config.NumberColumn("PA", format="%.1f")})
        st.caption("Standings from the league snapshot; roster strength is projection-based, not a standings prediction.")
    an, prov = S.league_analysis()
    if "team_needs" in an:
        with st.expander("Team needs (last analysis snapshot)"):
            st.dataframe(an["team_needs"].drop(columns=["team_id"], errors="ignore"), hide_index=True, width="stretch")
            st.caption(f"{prov.source}")

with tab_sched:
    sc = pd.DataFrame(ctx.get("schedule") or [])
    if sc.empty:
        C.empty_state("No schedule", "Refresh the league snapshot (view=mMatchup).")
    else:
        cur = (ctx.get("status") or {}).get("current_matchup_period") or 0
        only = st.toggle("Only remaining weeks", value=True)
        mine_only = st.toggle("Only your games", value=False)
        v = sc[sc["matchup_period"] >= cur] if only else sc
        if mine_only:
            v = v[(v["home_team"] == me) | (v["away_team"] == me)]
        v = v.assign(home=v["home_team"].map(lab), away=v["away_team"].map(lab))
        st.dataframe(v[["matchup_period", "home", "away", "home_points", "away_points", "winner", "playoff_tier"]],
                     hide_index=True, width="stretch")
        tu = pd.DataFrame(ctx.get("team_utility") or [])
        if not tu.empty and only:
            rem = sc[(sc["matchup_period"] >= cur) & (sc["playoff_tier"].fillna("NONE") == "NONE")]
            opp = pd.concat([rem.rename(columns={"home_team": "team_id", "away_team": "opp"})[["team_id", "opp"]],
                             rem.rename(columns={"away_team": "team_id", "home_team": "opp"})[["team_id", "opp"]]])
            opp = opp.merge(tu[["team_id", "U_regular"]].rename(columns={"team_id": "opp", "U_regular": "opp_U"}), on="opp", how="left")
            sos = opp.groupby("team_id")["opp_U"].mean().reset_index()
            sos["team"] = sos["team_id"].map(lab)
            st.markdown("**Remaining-schedule strength** (mean regular-season roster strength U of remaining opponents)")
            st.altair_chart(alt.Chart(sos).mark_bar(color="#6baed6").encode(
                x=alt.X("opp_U:Q", title="Mean opponent U (regular season)"), y=alt.Y("team:N", sort="-x", title=None),
                tooltip=["team", alt.Tooltip("opp_U:Q", format=".0f")]).properties(height=40 * len(sos)), width="stretch")
            st.caption("Descriptive: uses each opponent's current V2 roster strength, not a new model.")

with tab_hist:
    recs = [d for d in S.decisions(S.snapshot().alias if S.snapshot() else None) if d.get("type") == "odds"]
    if len(recs) < 2:
        st.caption("Odds history is accruing: fewer than two ledgered odds records so far.")
    else:
        rows = [{"as_of_utc": d["as_of_utc"], "team": lab(t["team_id"]), "p_playoffs": t["p_playoffs"], "p_title": t["p_title"]}
                for d in recs for t in d["recommendation"]["teams"]]
        h = pd.DataFrame(rows)
        st.altair_chart(alt.Chart(h).mark_line(point=True).encode(
            x=alt.X("as_of_utc:N", title="Ledgered (UTC)"), y=alt.Y("p_playoffs:Q", axis=alt.Axis(format="%"), title="P(playoffs)"),
            color=alt.Color("team:N", title=None), tooltip=["team", "as_of_utc", alt.Tooltip("p_playoffs:Q", format=".1%")]),
            width="stretch")
        C.badge(L.SHADOW)
        st.caption("From ledgered odds records (recommendations only; outcomes stay sealed).")
