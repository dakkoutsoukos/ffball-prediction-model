"""Draft (deferred): the D4 draft assistant exists as a terminal tool; the UI page is planned for the 2027 pre-draft window."""
import streamlit as st

from ffui import components as C

C.page_header("Draft (2027)", "Deferred until the 2027 pre-draft window.")
st.info("""The draft assistant (D4, VL10) is built and tested as a terminal tool:

```
Rscript scripts/draft_assistant.R --picks data/draft/picks.csv [--rollouts 100] [--odds]
```

It takes about 19 s per pick (plus about a minute with `--odds`). Its mock-draft gain is an upper bound because simulated
opponents follow the model's own assumptions. Keepers and FAAB are gated off in this league.

An in-app draft board is deferred: it is only useful during a draft, and building it now would mean designing against a
2027 draft that has not happened. `data/draft/` is git-ignored, so a pick log there stays private.""", icon=":material/event:")
