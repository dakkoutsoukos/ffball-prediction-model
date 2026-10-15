"""Waivers: the D3 free-agent board (utility screen, S0 re-score, drop advice, streaming view)."""
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L
from ffui import state as S

C.page_header("Waivers", "Free agents that improve your roster, what to drop, and this week's streaming view.")

snap = S.snapshot()
if snap:
    st.caption(f"Free agents are as of the league snapshot captured {snap.captured_at_utc} UTC; someone may have claimed "
               "them since. This league has no FAAB budget: claims go by waiver priority.")

ctx = S.league_context(load=False)
board_cfg = st.columns(3)
k = board_cfg[0].number_input("Re-score top", 1, 12, 8, help="Adds re-scored on S0 (CLI default 8).")
per = board_cfg[1].number_input("Candidates per position", 2, 10, 6)
sims = board_cfg[2].selectbox("Simulations", [2000, 5000], index=1)

fresh = None
if ctx is None:
    C.need_context("waivers")
else:
    job = C.job_control("waivers", "fa_board", {"k": int(k), "per_pos": int(per), "sims": sims}, ctx, "Build the free-agent board")
    fresh = job.result if job else None
    meta = job.meta if job else None

led = S.latest_decision("waivers")
if fresh:
    src, rec = "exploratory", fresh
else:
    src, rec = ("ledgered", led["recommendation"]) if led else (None, None)

if not rec:
    C.empty_state("No board yet", "Build one above, or run the briefing in a terminal.")
    st.stop()

h = st.columns([3, 1])
h[0].markdown(f"**Free-agent board** · {'computed now' if src == 'exploratory' else 'ledgered ' + led['as_of_utc']}")
with h[1]:
    C.badge(L.EXPLORATORY if src == "exploratory" else (L.FRAGILE if (led.get("metrics") or {}).get("fragile") else L.LEDGERED))
if src == "exploratory" and rec.get("waiver_rank") is not None:
    st.caption(f"Your waiver priority: {rec['waiver_rank']}.")

board = pd.DataFrame(rec.get("board") or [])
if board.empty:
    st.info("No free agent improves your expected rest-of-season lineup.")
else:
    st.dataframe(board[["add", "position", "drop", "dU", "d_wins", "d_playoffs", "d_title"]], hide_index=True,
                 width="stretch", column_config={
                     "add": "Add", "drop": "Drop",
                     "dU": st.column_config.NumberColumn("ΔU (ROS pts)", format="%+.1f", help="V2 utility change (adopted)."),
                     "d_wins": st.column_config.NumberColumn("Δ wins", format="%+.2f"),
                     "d_playoffs": st.column_config.NumberColumn("ΔP(playoffs)", format="percent"),
                     "d_title": st.column_config.NumberColumn("ΔP(title)", format="percent")})
    C.badge(L.SHADOW)
    st.caption("ΔP and Δ wins are shadow S0 numbers; deltas below about 0.005 are within simulation noise.")

c1, c2 = st.columns(2, gap="large")
with c1:
    st.markdown("**Drop advice** (cheapest players to release)")
    d = pd.DataFrame(rec.get("drop_advice") or [])
    if not d.empty:
        st.dataframe(d[["player", "position", "cost"]], hide_index=True, width="stretch",
                     column_config={"cost": st.column_config.NumberColumn("Cost (ΔU)", format="%.1f")})
        if (d["cost"] < 0).any():
            st.caption("A negative cost means streaming free agents in that slot is worth more than keeping the player.")
with c2:
    st.markdown("**Streaming view, this week**")
    C.badge(L.INFORMATIONAL)
    sv = pd.DataFrame(rec.get("stream_view") or [])
    if not sv.empty:
        st.dataframe(sv[["position", "player", "expected", "gain", "stream_candidate"]], hide_index=True,
                     width="stretch", column_config={
                         "expected": st.column_config.NumberColumn("Expected", format="%.1f"),
                         "gain": st.column_config.NumberColumn("Gain this week", format="%+.1f")})
    st.caption("Streaming is informational: the QB streaming check was null (X16, VL11).")

if src == "exploratory":
    with st.expander("Full utility screen"):
        st.dataframe(pd.DataFrame(rec.get("screen") or []), hide_index=True, width="stretch")
    C.provenance(meta)

an, prov = S.league_analysis()
if "waiver_levels" in an:
    with st.expander("League free-agent level by position (last analysis snapshot)"):
        st.dataframe(an["waiver_levels"], hide_index=True, width="stretch")
        st.caption(f"From {prov.source} ({prov.run_id}).")
