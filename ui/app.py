"""FFball local decision app. Start with:  ui\\run.ps1  (or: cd ui; uv run streamlit run app.py)

Local only (127.0.0.1, no telemetry; see .streamlit/config.toml). The app reads the pipeline's archives and runs
exploratory what-ifs through ui/r/ui_adapter.R; it never contacts ESPN and never writes the decision ledger.
"""
import streamlit as st

st.set_page_config(page_title="FFball", page_icon=":material/sports_football:", layout="wide",
                   initial_sidebar_state="expanded")

PAGES = {
    "": [st.Page("views/home.py", title="Command Center", icon=":material/dashboard:", default=True)],
    "Players": [
        st.Page("views/players.py", title="Player Explorer", icon=":material/person_search:"),
        st.Page("views/compare.py", title="Compare", icon=":material/compare_arrows:"),
    ],
    "Decisions": [
        st.Page("views/trade.py", title="Trade Lab", icon=":material/swap_horiz:"),
        st.Page("views/lineup.py", title="Lineup Lab", icon=":material/format_list_numbered:"),
        st.Page("views/waivers.py", title="Waivers", icon=":material/person_add:"),
    ],
    "Season": [
        st.Page("views/outlook.py", title="Season Outlook", icon=":material/leaderboard:"),
        st.Page("views/draft.py", title="Draft (2027)", icon=":material/format_list_bulleted:"),
    ],
    "System": [
        st.Page("views/research.py", title="Research", icon=":material/science:"),
        st.Page("views/operations.py", title="Operations", icon=":material/monitor_heart:"),
        st.Page("views/help.py", title="Help & limits", icon=":material/help:"),
    ],
}

nav = st.navigation(PAGES)
with st.sidebar:
    st.caption("Local only · 127.0.0.1 · no telemetry. What-ifs here are exploratory and never ledgered.")
nav.run()
