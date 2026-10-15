"""Reusable Streamlit pieces: context bar, status badges, provenance, job control, empty states."""
from __future__ import annotations

import json
import time

import pandas as pd
import streamlit as st

from . import labels as L
from . import state as S
from .jobs import ERROR_CODES, OPS, Job


def badge(status: L.Status, help_inline: bool = False) -> None:
    st.badge(status.label, color=status.color, help=status.meaning)
    if help_inline:
        st.caption(status.meaning)


def metric_badge(key: str) -> None:
    status, text = L.METRIC_STATUS[key]
    st.badge(status.label, color=status.color, help=f"{text}. {status.meaning}")


def page_header(title: str, subtitle: str = "") -> None:
    if S.demo_mode():
        st.error("DEMONSTRATION DATA: the app is running on synthetic fixtures (FFUI_DEMO=1), not your league.")
    st.title(title)
    if subtitle:
        st.caption(subtitle)
    context_bar()


def _age_color(h: float | None) -> str:
    if h is None:
        return "red"
    return "green" if h < 24 else "orange" if h < 72 else "red"


def context_bar() -> None:
    f = S.freshness()
    cols = st.columns([1.3, 1.3, 1, 1.4])
    with cols[0]:
        if f.snapshot_age_h is None:
            st.badge("No league snapshot", color="red")
        else:
            st.badge(f"League snapshot {f.snapshot_age_h:.0f} h old", color=_age_color(f.snapshot_age_h),
                     help=f"Captured {f.snapshot_at} (UTC). Rosters and availability are as of this capture.")
    with cols[1]:
        st.badge(f"Valuation run {f.valuation_run or 'none'}", color="blue" if f.valuation_run else "red",
                 help=f"As of {f.valuation_as_of}. Projections and values come from this run.")
    with cols[2]:
        st.badge(f"Code {f.head}", color="gray", help="Git commit of the repository (cached results are keyed on it).")
    with cols[3]:
        o = S.ops_status()
        nxt = o.get("next window opens")
        if nxt:
            st.badge(f"Next slate window {nxt}", color="gray", help="From data/ops/status.txt (dispatcher).")
        with st.popover("How to refresh"):
            st.markdown(L.REFRESH_HELP)
    if f.snapshot_age_h is not None and f.snapshot_age_h > 24:
        st.warning(f"The league snapshot is {f.snapshot_age_h:.0f} hours old: rosters, free agents and injury "
                   "statuses may have changed. Refresh it in a terminal (see *How to refresh*).", icon=":material/schedule:")


def provenance(meta: dict | None, extra: dict | None = None, label: str = "Provenance") -> None:
    with st.expander(label, icon=":material/info:"):
        if not meta and not extra:
            st.caption("No provenance recorded.")
            return
        rows = {}
        if meta:
            i = meta.get("inputs") or {}
            rows.update({
                "Computed": meta.get("started_at_utc"), "Elapsed (s)": meta.get("elapsed_seconds"),
                "League snapshot (UTC)": i.get("league_captured_at_utc"),
                "League snapshot sha256": (i.get("league_raw_sha256") or "")[:16],
                "Valuation run": i.get("valuation_run_id"), "Policy": i.get("policy"),
                "Adapter": meta.get("adapter_version"), "Git commit": (meta.get("git_commit") or "")[:10],
                "Exploratory (not ledgered)": meta.get("exploratory"),
            })
            for k, v in (meta.get("model_versions") or {}).items():
                rows[f"Model · {k}"] = v if isinstance(v, str) else json.dumps(v)
        if extra:
            rows.update(extra)
        st.dataframe(pd.DataFrame({"field": list(rows), "value": [("" if v is None else str(v)) for v in rows.values()]}),
                     hide_index=True, width="stretch")


def empty_state(what: str, how: str) -> None:
    st.info(f"**{what}**\n\n{how}", icon=":material/inventory_2:")


def need_context(page_key: str) -> dict | None:
    """Return the league context, loading it only from an explicit click (about 4 s, cached per snapshot)."""
    ctx = S.league_context(load=False)
    if ctx:
        return ctx
    if not S.snapshot():
        empty_state("No league snapshot", "Run `Rscript scripts/league_refresh.R` in a terminal first.")
        return None
    st.info("This page needs the league model's view of the current snapshot (rosters, ids, standings). "
            "Loading it takes about 4 seconds and is cached until the snapshot or valuation run changes.",
            icon=":material/database:")
    if st.button("Load league context", key=f"load_ctx_{page_key}", type="primary"):
        with st.spinner("Loading the league context..."):
            ctx = S.league_context(load=True)
        if ctx:
            st.rerun()
        st.error(f"Could not load the league context: {st.session_state.get('context_error', 'unknown error')}")
    return None


def job_control(page_key: str, op: str, params: dict, ctx: dict, button: str, help_text: str = "") -> Job | None:
    """A compute button with cache lookup, progress, cancel and errors. Returns a finished Job (done/cached) or None.

    Nothing runs until the button is pressed; a cached result for the same inputs is shown immediately."""
    r = S.runner()
    opctx = S.op_context(ctx)
    key = r.key_for(op, params, opctx)
    skey = f"job_{page_key}_{op}"
    hit = r.cached(op, key)
    typical = OPS[op][1]
    c1, c2 = st.columns([3, 2])
    with c1:
        pressed = st.button(button, key=f"btn_{skey}", type="primary", disabled=hit is not None,
                            help=help_text or f"Typically about {typical} s on this machine.")
    with c2:
        if hit:
            st.caption(f"Showing the cached result for these inputs ({hit.meta.get('started_at_utc', '')} UTC).")
        else:
            st.caption(f"Typically about {typical} s. Runs in the background; results are cached.")
    if hit:
        st.session_state.pop(skey, None)
        return hit
    if pressed:
        job = r.start(op, params, opctx)
        if job.state == "busy":
            st.warning(job.message)
            return None
        if job.state in ("cached", "done"):
            return job
        if job.state == "failed":
            st.error(job.message)
            return None
        st.session_state[skey] = {"key": job.key, "op": op}
    active = st.session_state.get(skey)
    if active and active["key"] == key:
        _job_progress(skey, op, key)
    elif active:
        st.session_state.pop(skey, None)
    return None


@st.fragment(run_every=1.0)
def _job_progress(skey: str, op: str, key: str) -> None:
    r = S.runner()
    job = r.poll(op, key)
    if job.state == "running":
        frac = min(job.elapsed / max(job.expected * 1.5, 1), 0.95)
        st.progress(frac, text=f"Running {op.replace('_', ' ')}: {job.elapsed:.0f} s (typically about {job.expected} s)")
        if st.button("Cancel", key=f"cancel_{skey}"):
            r.cancel(op, key)
            st.session_state.pop(skey, None)
            st.rerun()
        return
    st.session_state.pop(skey, None)
    if job.state in ("done", "cached"):
        st.rerun()
    elif job.state == "cancelled":
        st.info("Cancelled.")
    else:
        if job.code == 3:
            st.warning(f"{job.message}. Reload the page context (Operations ▸ clear the context, or refresh the browser).")
        else:
            st.error(f"{job.state.title()}: {job.message}")


def fmt_pct(x, digits: int = 1) -> str:
    return "–" if x is None or pd.isna(x) else f"{100 * float(x):.{digits}f}%"


def fmt_num(x, digits: int = 1) -> str:
    return "–" if x is None or pd.isna(x) else f"{float(x):,.{digits}f}"


def code_error_help(code: int | None) -> str:
    return ERROR_CODES.get(code or 0, "")


def wait_note(seconds: float) -> None:
    time.sleep(seconds)
