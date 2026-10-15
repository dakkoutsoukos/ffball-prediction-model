"""Help & limits: what the app does, what it never does, and what the models do not support."""
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L

C.page_header("Help & limits")

st.markdown("""
**What this app is.** A local window onto the FFball pipeline. Read-only pages show files the pipeline already wrote
(valuation runs, distributions, ledgered recommendations, the briefing, dispatcher status). Decision pages run
*exploratory* what-ifs through `ui/r/ui_adapter.R`, which calls the same R functions as the terminal tools.

**What it never does.**
- Contact ESPN or any other service (league refresh stays a terminal step).
- Write the decision ledger, the committed manifests, models or research files. App results live in the git-ignored
  `data/archive/ui_cache/`.
- Run research, backtests or any spent or holdout check.
- Leave this machine: Streamlit is bound to 127.0.0.1 with usage statistics off.
""")
st.markdown(L.REFRESH_HELP)

st.subheader("Status labels")
for s in (L.ADOPTED, L.SHADOW, L.INFORMATIONAL, L.EXPLORATORY, L.FRAGILE, L.LEDGERED, L.STALE):
    c = st.columns([1, 5])
    with c[0]:
        C.badge(s)
    c[1].write(s.meaning)

st.subheader("Not supported by the current models")
st.dataframe(pd.DataFrame(L.UNSUPPORTED, columns=["feature", "why"]), hide_index=True, width="stretch")

st.subheader("Typical run times on this machine")
st.dataframe(pd.DataFrame([
    ("League context", "≈4 s", "once per snapshot/valuation run"), ("Lineup", "≈3 s", ""),
    ("Season odds (10,000 sims + bands)", "≈15–20 s", ""), ("Trade evaluation with S0", "≈10 s", ""),
    ("Package search + re-score", "≈30–60 s", ""), ("Free-agent board", "≈20–30 s", ""),
    ("Roster values (wins added)", "≈30–60 s", ""),
], columns=["calculation", "time", "note"]), hide_index=True, width="stretch")
st.caption("Results are cached per input set, league snapshot, valuation run and code version. Only one calculation runs at a time.")
