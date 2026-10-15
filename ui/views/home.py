"""Command Center: this week's state from files already on disk (no R job runs on this page)."""
import pandas as pd
import streamlit as st

from ffui import artifacts as A
from ffui import components as C
from ffui import labels as L
from ffui import state as S

C.page_header("Command Center", "This week at a glance, from the latest ledgered recommendations, valuation run and briefing.")

odds = S.latest_decision("odds")
lineup = S.latest_decision("lineup")
waivers = S.latest_decision("waivers")
trades = S.latest_decision("trade_rescore")
ctx = S.league_context(load=False)

me = None
if odds and odds["recommendation"].get("leverage"):
    me = odds["recommendation"]["leverage"][0]["team_id"]
elif ctx:
    me = ctx.get("my_team")
names = S.team_names(ctx) if ctx else {}
roster_all = S.league_roster()
if not names and roster_all is not None:
    names = dict(roster_all.drop_duplicates("team_id")[["team_id", "team_name"]].itertuples(index=False))

# ---------------------------------------------------------------- headline tiles
st.subheader("Season and this week")
if odds:
    rec = odds["recommendation"]
    t = pd.DataFrame(rec["teams"])
    mine = t[t["team_id"] == me].iloc[0] if me is not None and (t["team_id"] == me).any() else None
    lev = rec["leverage"][0] if rec.get("leverage") else {}
    bands = pd.DataFrame(rec.get("bands") or [])
    bm = bands[bands["team_id"] == me] if not bands.empty and me is not None else pd.DataFrame()
    c = st.columns(4)
    c[0].metric("P(win) this week", C.fmt_pct(lev.get("p_win_this_week")),
                help="S1 simulation win probability (method adopted, X23) shown through the shadow S0 engine.")
    if mine is not None:
        rng = f"band {C.fmt_pct(bm['p_playoffs'].min(), 0)}–{C.fmt_pct(bm['p_playoffs'].max(), 0)}" if not bm.empty else ""
        c[1].metric("P(playoffs)", C.fmt_pct(mine["p_playoffs"]), rng, delta_color="off",
                    help="Shadow S0 odds; the band is σ_L × 0.5–1.5 and noise × 0.8–1.2 (VL3).")
        rng = f"band {C.fmt_pct(bm['p_title'].min(), 0)}–{C.fmt_pct(bm['p_title'].max(), 0)}" if not bm.empty else ""
        c[2].metric("P(title)", C.fmt_pct(mine["p_title"]), rng, delta_color="off", help="Shadow S0 odds.")
        c[3].metric("Expected wins", C.fmt_num(mine["e_wins"], 2), help="Shadow S0: expected regular-season wins.")
    cap = st.columns([1, 4])
    with cap[0]:
        C.badge(L.SHADOW)
    with cap[1]:
        st.caption(f"From the ledgered odds of {odds['as_of_utc']} ({odds['metrics'].get('sims')} simulations). "
                   f"Leverage this week: P(playoffs) {C.fmt_pct(lev.get('p_playoffs_if_win'))} with a win vs "
                   f"{C.fmt_pct(lev.get('p_playoffs_if_loss'))} with a loss. Fresh odds: Season Outlook.")
else:
    C.empty_state("No ledgered odds yet", "Run `Rscript scripts/trade_analyzer.R odds` or the briefing in a terminal, "
                  "or compute exploratory odds on the Season Outlook page.")

left, right = st.columns([3, 2], gap="large")

# ---------------------------------------------------------------- recommended actions
with left:
    st.subheader("Latest recommendations")
    if not any([lineup, waivers, trades]):
        C.empty_state("No ledgered recommendations", "They are written by the briefing (`Rscript scripts/briefing.R`).")
    if lineup:
        with st.container(border=True):
            m = lineup.get("metrics", {})
            h = st.columns([3, 1])
            h[0].markdown(f"**Lineup** · ledgered {lineup['as_of_utc']}")
            with h[1]:
                C.badge(L.FRAGILE if m.get("fragile") else L.LEDGERED)
            r = pd.DataFrame(lineup["recommendation"]["roster"])
            changes = r[r["recommended_starter"] != r["current_starter"]] if not r.empty else r
            st.write(f"Expected points: recommended **{C.fmt_num(m.get('ev_recommended'))}** vs current ESPN lineup "
                     f"**{C.fmt_num(m.get('ev_current'))}**. {len(changes)} start/sit change(s).")
            if len(changes):
                st.dataframe(changes[["player", "position", "slot_current", "slot_recommended", "proj", "status"]],
                             hide_index=True, width="stretch")
    if waivers:
        with st.container(border=True):
            m = waivers.get("metrics", {})
            h = st.columns([3, 1])
            h[0].markdown(f"**Waiver board** · ledgered {waivers['as_of_utc']}")
            with h[1]:
                C.badge(L.FRAGILE if m.get("fragile") else L.LEDGERED)
            b = pd.DataFrame(waivers["recommendation"].get("board") or [])
            if not b.empty:
                st.dataframe(b[["add", "position", "drop", "dU", "d_wins", "d_playoffs"]].head(5), hide_index=True,
                             width="stretch", column_config={
                                 "dU": st.column_config.NumberColumn("ΔU (pts)", format="%.1f"),
                                 "d_wins": st.column_config.NumberColumn("Δ wins", format="%.2f"),
                                 "d_playoffs": st.column_config.NumberColumn("ΔP(playoffs)", format="percent")})
            st.caption("No FAAB in this league: claims go by waiver priority. ΔP is shadow; deltas under ~0.005 are noise.")
    if trades:
        with st.container(border=True):
            m = trades.get("metrics", {})
            h = st.columns([3, 1])
            h[0].markdown(f"**Trade re-score** · ledgered {trades['as_of_utc']}")
            with h[1]:
                C.badge(L.FRAGILE if m.get("fragile") else L.LEDGERED)
            tp = pd.DataFrame(trades["recommendation"].get("top") or [])
            if not tp.empty:
                st.dataframe(tp[["a_gives", "b_gives", "d_playoffs_a", "d_title_a", "v2_delta_a", "v2_delta_b"]],
                             hide_index=True, width="stretch", column_config={
                                 "a_gives": "You give", "b_gives": "You get",
                                 "d_playoffs_a": st.column_config.NumberColumn("Your ΔP(playoffs)", format="percent"),
                                 "d_title_a": st.column_config.NumberColumn("Your ΔP(title)", format="percent"),
                                 "v2_delta_a": st.column_config.NumberColumn("Your ΔU", format="%.1f"),
                                 "v2_delta_b": st.column_config.NumberColumn("Their ΔU", format="%.1f")})
            st.caption(f"{m.get('invalid_candidates', 0)} candidate(s) failed V2's invariants and were left out. "
                       "Model estimates, not acceptance predictions.")

# ---------------------------------------------------------------- roster and health
with right:
    st.subheader("Your roster")
    runs = S.valuation_runs()
    if roster_all is not None and me is not None:
        mine = roster_all[roster_all["team_id"] == me]
        if runs:
            v = S.val_table(runs[-1], "values")
            if v is not None:
                v = v.drop_duplicates("espn_id")[["espn_id", "ros_points", "vor", "position_rank"]]
                mine = mine.merge(v, on="espn_id", how="left", validate="many_to_one")
        cols = [c for c in ["player_name", "position", "nfl_team", "lineup_slot", "injury_status", "ros_points", "vor", "position_rank"] if c in mine]
        st.dataframe(mine[cols].sort_values("vor", ascending=False) if "vor" in mine else mine[cols], hide_index=True,
                     width="stretch", column_config={
                         "player_name": "Player", "nfl_team": "NFL", "lineup_slot": "Slot", "injury_status": "Status",
                         "ros_points": st.column_config.NumberColumn("ROS pts", format="%.1f"),
                         "vor": st.column_config.NumberColumn("VOR", format="%.1f")})
        st.caption(f"Roster from the league snapshot of {S.snapshot().captured_at_utc}; values from run "
                   f"{runs[-1].run_id if runs else '–'} (joined on ESPN id).")
    else:
        C.empty_state("Roster unavailable", "Needs a league snapshot and a ledgered odds record or the league context.")

    st.subheader("System health")
    o = S.ops_status()
    if o.get("available"):
        st.write(f"Dispatcher: **{o.get('decision', '–')}** · target {o.get('target', '–')}")
        st.caption(f"Status written {o['modified_utc']:%Y-%m-%d %H:%M} UTC · next window {o.get('next window opens', '–')}")
        for a in o.get("alerts", []):
            st.warning(a)
        if o.get("commits_not_pushed"):
            st.info(f"{o['commits_not_pushed']} local commit(s) not on GitHub: push before kickoff (the app never pushes).")
    else:
        st.caption("No dispatcher status file (data/ops/status.txt).")

# ---------------------------------------------------------------- briefing
st.subheader("Weekly briefing")
bl = S.repo() and A.briefings(S.repo())
if bl:
    opts = {f"{A.briefing_time(p):%Y-%m-%d %H:%M} UTC · {p.parent.name}": p for p in reversed(bl)}
    pick = st.selectbox("Briefing", list(opts), index=0, label_visibility="collapsed")
    p = opts[pick]
    st.caption("The D5 briefing as written by `scripts/briefing.R` (self-contained local HTML; recommendations in it are ledgered).")
    st.iframe(p.read_text(encoding="utf-8"), height=900)  # our own self-contained briefing (trusted)
else:
    C.empty_state("No briefing yet", "Run `Rscript scripts/briefing.R` in a terminal (about 12 minutes; it records ledger entries).")
