"""Trade Lab: build a trade, score it with V2's team utility and (optionally) the shadow S0 simulator, or search
for packages. Everything here is exploratory and never ledgered."""
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L
from ffui import state as S

C.page_header("Trade Lab", "Build and score trades. Model estimates of your and your partner's rosters, not acceptance predictions.")
ctx = C.need_context("trade")
if not ctx:
    st.stop()

players = S.players_frame(ctx)
names = S.team_names(ctx)
me = ctx.get("my_team")
if me is None:
    st.error("Your team could not be detected from the league snapshot.")
    st.stop()
partners = {names[t]: t for t in names if t != me}
NOISE = 0.005


def roster_options(team_id: int) -> dict[str, str]:
    r = players[players["team_id"] == team_id].sort_values("vor", ascending=False)
    return {f"{p.player_name} ({p.position}, {p.nfl_team or 'FA'}){' · IR' if p.on_ir else ''} · VOR {p.vor:.0f}": p.player_id
            for p in r.itertuples() if pd.notna(p.vor)} | {
            f"{p.player_name} ({p.position}){' · IR' if p.on_ir else ''}": p.player_id for p in r.itertuples() if pd.isna(p.vor)}


def side_table(df: pd.DataFrame) -> None:
    show = df[["team", "gives", "gets", "U_before", "U_after", "delta", "delta_regular", "delta_playoffs", "dropped", "added"]]
    st.dataframe(show, hide_index=True, width="stretch", column_config={
        "U_before": st.column_config.NumberColumn("U before", format="%.1f", help="Expected rest-of-season lineup points (V2)."),
        "U_after": st.column_config.NumberColumn("U after", format="%.1f"),
        "delta": st.column_config.NumberColumn("ΔU", format="%+.1f"),
        "delta_regular": st.column_config.NumberColumn("ΔU regular", format="%+.1f"),
        "delta_playoffs": st.column_config.NumberColumn("ΔU playoffs", format="%+.1f"),
        "dropped": "Must drop", "added": "Streams in"})


def rescore_cards(rs: pd.DataFrame, label_cols=None) -> None:
    for _, r in rs.iterrows():
        with st.container(border=True):
            if label_cols:
                st.markdown(f"**You give** {r[label_cols[0]]} · **you get** {r[label_cols[1]]}")
            c = st.columns(5)
            c[0].metric("Your ΔP(playoffs)", C.fmt_pct(r["d_playoffs_a"]), help=f"{C.fmt_pct(r['p_playoffs_a0'])} → {C.fmt_pct(r['p_playoffs_a1'])}")
            c[1].metric("Your ΔP(title)", C.fmt_pct(r["d_title_a"]), help=f"{C.fmt_pct(r['p_title_a0'])} → {C.fmt_pct(r['p_title_a1'])}")
            c[2].metric("Your Δ wins", C.fmt_num(r["d_wins_a"], 2))
            c[3].metric("Their ΔP(playoffs)", C.fmt_pct(r["d_playoffs_b"]))
            c[4].metric("Their generic view", C.fmt_num(r["partner_lens_b"]),
                        help="The partner's change in generic V1 VOR: how the trade looks to a manager using public values.")
            notes = []
            if abs(r["d_playoffs_a"]) < NOISE and abs(r["d_title_a"]) < NOISE:
                notes.append("your ΔP is within simulation noise (< 0.5 pt)")
            if "qualification" in r and pd.notna(r.get("qualification")):
                notes.append(f"title gain from qualifying {C.fmt_pct(r['qualification'])}, from playoff strength {C.fmt_pct(r.get('playoff_strength'))}")
            notes.append(f"Nash product {r['nash']:.4f} (fairness summary only)")
            st.caption(" · ".join(notes))


tab_build, tab_search, tab_saved = st.tabs(["Build a trade", "Find packages", "Saved this session"])

with tab_build:
    pname = st.selectbox("Trade partner", list(partners))
    tb = partners[pname]
    a, b = st.columns(2, gap="large")
    mine_opts, theirs_opts = roster_options(me), roster_options(tb)
    give = a.multiselect(f"You give ({names[me]})", list(mine_opts))
    get = b.multiselect(f"You get ({pname})", list(theirs_opts))
    o = st.columns([1.2, 1, 1.4])
    horizon = o[0].segmented_control("Horizon", ["full", "regular", "playoffs"], default="full",
                                     help="Which weeks count in the utility (V2).")
    sims = o[1].selectbox("Simulations", [2000, 5000], index=1, help="S0 simulations (CLI default 5,000).")
    simulate = o[2].toggle("Simulate playoff and title effects", value=True,
                           help="Shadow S0 re-score with common random numbers (≈10 s). Off: utility only (≈5 s).")
    if not give and not get:
        st.caption("Pick at least one player on either side.")
    else:
        params = {"team_a": me, "give_a": [mine_opts[x] for x in give], "team_b": tb, "give_b": [theirs_opts[x] for x in get],
                  "horizon": horizon or "full", "simulate": simulate, "sims": sims}
        job = C.job_control("trade", "trade_eval", params, ctx, "Evaluate trade")
        if job and job.result:
            res = job.result
            C.badge(L.EXPLORATORY)
            teams = pd.DataFrame(res["teams"])
            met = (res.get("metrics") or [{}])[0]
            st.markdown(f"**Utility (V2)** · classification **{met.get('classification', '–')}** · surplus "
                        f"{C.fmt_num(met.get('surplus'))} · balance {C.fmt_num(met.get('balance'))}")
            side_table(teams)
            with st.expander("Why (model explanations)"):
                for e in res.get("explanations") or []:
                    st.markdown(f"- {e}")
            if res.get("rescore"):
                st.markdown("**Season effects (S0)**")
                C.badge(L.SHADOW)
                rescore_cards(pd.DataFrame(res["rescore"]))
                if res.get("sim_explanations"):
                    st.caption(res["sim_explanations"] if isinstance(res["sim_explanations"], str) else " ".join(res["sim_explanations"]))
            if st.button("Save to this session's comparison", key="save_trade"):
                mine_row = teams[teams["team_id"] == me].iloc[0]
                rs = (res.get("rescore") or [{}])[0]
                st.session_state.setdefault("saved_trades", []).append({
                    "partner": pname, "you give": mine_row["gives"], "you get": mine_row["gets"],
                    "your ΔU": mine_row["delta"], "their ΔU": teams[teams["team_id"] == tb]["delta"].iloc[0],
                    "your ΔP(playoffs)": rs.get("d_playoffs_a"), "your ΔP(title)": rs.get("d_title_a"),
                    "classification": met.get("classification"), "horizon": horizon})
                st.toast("Saved")
            C.provenance(job.meta)

with tab_search:
    pname2 = st.selectbox("Partner", list(partners), key="search_partner")
    o = st.columns(4)
    k = o[0].number_input("Re-score top", 1, 8, 5, help="Candidates re-scored by S0 (CLI default 5).")
    sims2 = o[1].selectbox("Simulations", [2000, 5000], index=1, key="search_sims")
    sim2 = o[3].toggle("Re-score with S0", value=True)
    mine_g = o[2].toggle("Only trades where I gain", value=True,
                         help="Keep every trade that raises your utility, ranked by your gain. The partner may lose on our "
                              "model; the search still requires the two sides to look fair on PUBLIC trade value.")
    ww = False if mine_g else st.toggle("Only win-win", value=False, help="Keep trades that raise both teams' utility.")
    my_roster = players[players["team_id"] == me].sort_values("trade_value", ascending=False)
    sell_opts = {"": "None"} | {p.player_id: f"{p.player_name} ({p.position}) · public value {p.trade_value:.0f}"
                                for p in my_roster.itertuples() if pd.notna(p.trade_value)}
    s1, s2 = st.columns([2, 1])
    sell = s1.selectbox("Sell high (optional)", list(sell_opts), format_func=lambda x: sell_opts[x],
                        help="A player you think the public overrates. Only packages that include him are shown, and his "
                             "public value is inflated so the search asks for a bigger return.")
    boost = s2.slider("Public value boost", 0, 50, 15, step=5, format="+%d%%", disabled=not sell,
                      help="How much more the other manager values him than the public trade value says.")
    params = {"team_b": partners[pname2], "k": int(k), "sims": sims2, "win_win": ww, "simulate": sim2,
              "my_gain_only": mine_g}
    if sell:
        params |= {"sell_player": sell, "boost_pct": boost}
    job = C.job_control("trade_search", "trade_search", params, ctx, "Search packages",
                        "V2's utility search, invariant filter (X-021), then the top candidates re-scored (≈1–2 min "
                        "with 'I gain' or sell-high, which evaluate more candidates).")
    if job and job.result:
        res = job.result
        C.badge(L.EXPLORATORY)
        sh = res.get("sell_high")
        if sh:
            st.info(f"Selling high on **{sell_opts.get(sh['player_id'], sh['player_id']).split(' · ')[0]}** with his public value "
                    f"inflated by {sh['boost_pct']:.0f}%. That only changes which packages count as fair to the other "
                    "manager; *Your ΔU* and *Their ΔU* are still the model's projections.", icon=":material/trending_up:")
        st.caption(f"{res.get('n_evaluated', 0)} trades shown after filters; {res.get('excluded_invariants', 0)} candidate(s) failed V2's "
                   "trade invariants and were left out of the re-score (X-021).")
        cand = pd.DataFrame(res.get("candidates") or [])
        if cand.empty:
            st.info("No package passed the filters. Try a larger boost, another partner, or turn off 'Only trades where I gain'.")
        else:
            cols = ["a_gives", "b_gives", "delta_a", "delta_b", "tv_a_gives", "tv_a_gives_perceived", "tv_b_gives", "classification"]
            st.dataframe(cand[[c for c in cols if c in cand]], hide_index=True, width="stretch", column_config={
                "a_gives": "You give", "b_gives": "You get",
                "delta_a": st.column_config.NumberColumn("Your ΔU", format="%+.1f", help="Model: change in your expected ROS lineup points."),
                "delta_b": st.column_config.NumberColumn("Their ΔU", format="%+.1f", help="Model: may be negative; they judge the deal by public value."),
                "tv_a_gives": st.column_config.NumberColumn("Public value you give", format="%.0f"),
                "tv_a_gives_perceived": st.column_config.NumberColumn("…as perceived", format="%.0f",
                                                                      help="With the sell-high boost applied."),
                "tv_b_gives": st.column_config.NumberColumn("Public value you get", format="%.0f")})
            if (cand["delta_b"] < -20).any():
                st.caption("Trades where the partner loses more than 20 points on our model are lopsided enough that an "
                           "attentive manager may notice; acceptance is not modelled.")
        if res.get("rescore"):
            st.markdown("**Top candidates re-scored (S0)**")
            C.badge(L.SHADOW)
            st.caption("At these simulation counts ΔP does not reliably rank close candidates (X11); prefer the utility "
                       f"ranking unless differences are large. Frontier trades: {', '.join(map(str, res.get('frontier_trades') or [])) or '–'}.")
            rescore_cards(pd.DataFrame(res["rescore"]), ["a_gives", "b_gives"])
        C.provenance(job.meta)

with tab_saved:
    saved = st.session_state.get("saved_trades", [])
    if not saved:
        st.caption("Evaluate a trade and press *Save* to compare several here (kept for this browser session only).")
    else:
        st.dataframe(pd.DataFrame(saved), hide_index=True, width="stretch", column_config={
            "your ΔP(playoffs)": st.column_config.NumberColumn(format="percent"),
            "your ΔP(title)": st.column_config.NumberColumn(format="percent"),
            "your ΔU": st.column_config.NumberColumn(format="%+.1f"), "their ΔU": st.column_config.NumberColumn(format="%+.1f")})
        if st.button("Clear"):
            st.session_state["saved_trades"] = []
            st.rerun()

st.caption("To record an official decision, run the terminal tools (e.g. `Rscript scripts/trade_analyzer.R rescore --b \"Team\"`, "
           "then `ledger-action`). The app never writes the ledger.")
