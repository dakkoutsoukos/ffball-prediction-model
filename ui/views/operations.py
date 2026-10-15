"""Operations: dispatcher status, data freshness, archives, health checks and the UI's own jobs. Read-only for the
pipeline: nothing here runs a capture, a refresh, a commit or changes the scheduled task."""
import subprocess
import sys

import pandas as pd
import streamlit as st

from ffui import artifacts as A
from ffui import components as C
from ffui import jobs as J
from ffui import state as S

C.page_header("Operations", "Pipeline status, data freshness, archives and the app's own background jobs.")
rp = S.repo()
r = S.runner()

t_status, t_data, t_health, t_jobs = st.tabs(["Dispatcher", "Archives & freshness", "Health checks", "App jobs & cache"])

with t_status:
    o = S.ops_status()
    if not o.get("available"):
        C.empty_state("No dispatcher status", "data/ops/status.txt is written hourly by the scheduled task.")
    else:
        c = st.columns(3)
        c[0].metric("Last decision", o.get("decision", "–"))
        c[1].metric("Target", o.get("target", "–"))
        c[2].metric("Local commits not pushed", o.get("commits_not_pushed", 0) or 0)
        st.caption(f"status.txt written {o['modified_utc']:%Y-%m-%d %H:%M} UTC "
                   f"({A.age_hours(o['modified_utc']):.1f} h ago; the task runs hourly at :05).")
        for a in o.get("alerts", []):
            st.warning(a)
        st.code("\n".join(o["lines"]), language=None)
    st.markdown("**Dispatch log** (latest first)")
    log = A.dispatch_log(rp, 300)
    if not log.empty:
        acts = st.multiselect("Action", sorted(log["action"].unique()), placeholder="All actions")
        v = log[log["action"].isin(acts)] if acts else log
        st.dataframe(v.iloc[::-1], hide_index=True, width="stretch", height=320)
    st.markdown("**Scheduled task** (read-only query)")
    if sys.platform == "win32" and st.button("Query the FFball_dispatch task"):
        out = subprocess.run(["schtasks", "/Query", "/TN", "FFball_dispatch", "/V", "/FO", "LIST"], capture_output=True,
                             text=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=30)
        keep = ("Status", "Last Run Time", "Last Result", "Next Run Time", "Scheduled Task State", "Logon Mode", "Repeat: Every")
        lines = [ln for ln in out.stdout.splitlines() if ln.split(":")[0].strip() in keep]
        st.code("\n".join(lines) or out.stderr or "No output", language=None)

with t_data:
    f = S.freshness()
    c = st.columns(3)
    c[0].metric("League snapshot age", f"{f.snapshot_age_h:.1f} h" if f.snapshot_age_h is not None else "–")
    c[1].metric("Latest valuation run", f.valuation_run or "–")
    c[2].metric("Valuation runs on disk", len(S.valuation_runs()))
    st.markdown("**Manifests** (committed, append-only)")
    st.dataframe(A.manifest_summary(rp), hide_index=True, width="stretch")
    st.markdown("**Manifest ↔ archive audit**")
    aud = A.manifest_folder_audit(rp)
    if aud.empty:
        st.caption("No manifest rows.")
    else:
        bad = aud[(~aud["on_disk"]) | (aud["unlisted"])]
        if bad.empty:
            st.success(f"All {len(aud)} manifest rows have their files on disk, and no run folder is unlisted.")
        else:
            st.warning(f"{len(bad)} mismatch(es): rows without files, or run folders no manifest lists.")
            st.dataframe(bad, hide_index=True, width="stretch")
    runs = S.valuation_runs()
    if runs:
        st.markdown("**Latest valuation run**")
        meta = A.run_meta(runs[-1])
        ok = S.values_hash_ok(runs[-1])
        st.write(f"`{runs[-1].run_id}` · week {runs[-1].week} · {runs[-1].methodology_version} · values hash "
                 f"{'verified against the manifest' if ok else 'MISMATCH' if ok is False else 'not recorded'}")
        if meta:
            st.dataframe(pd.DataFrame({"field": ["as_of_utc", "git_commit", "git_dirty", "n_players", "elapsed_seconds"],
                                       "value": [str(meta.get(k)) for k in ["as_of_utc", "git_commit", "git_dirty", "n_players", "elapsed_seconds"]]}),
                         hide_index=True, width="stretch")
    hs, hpath = A.horizon_study(rp)
    if hs:
        st.markdown("**R3 horizon study** (outcome-free; adoption per cell about early November)")
        st.caption(f"{hpath}: {hs.get('rows')} rows, {hs.get('active_rows')} active, target weeks {hs.get('target_weeks')}; "
                   f"adopted cells: {len(hs.get('adoption') or []) if isinstance(hs.get('adoption'), list) else hs.get('adoption')}")

with t_health:
    st.caption("I3 checks (freshness, dispatcher, run coverage, ESPN 401, Monte Carlo SE) computed by `i3_health()` "
               "through the adapter. Read-only.")
    job = C.job_control("health", "health", {"stamp": S.ops_status().get("modified_utc", "").__str__()}, {"inputs": {}}, "Run health checks")
    if job and job.result:
        h = pd.DataFrame(job.result.get("health") or [])
        icon = {"OK": "✅", "WARN": "⚠️", "ALERT": "🛑"}
        if not h.empty:
            h.insert(0, "", h["level"].map(lambda x: icon.get(str(x).upper(), "•")))
            st.dataframe(h, hide_index=True, width="stretch")
        C.provenance(job.meta)

with t_jobs:
    holder = r.lock_holder()
    if holder:
        st.info(f"A calculation is running (job {holder['key'][:8]}, PID {holder['pid']}).")
    hist = r.history(50)
    if not hist:
        st.caption("No app jobs yet.")
    else:
        df = pd.DataFrame([{"started": J.fmt_time(h.get("started")), "op": h.get("op"), "state": h.get("state"),
                            "message": h.get("message", ""), "key": h.get("key")} for h in hist])
        st.dataframe(df, hide_index=True, width="stretch")
        running = [h for h in hist if h.get("state") == "running"]
        for h in running:
            if st.button(f"Cancel {h['op']} ({h['key'][:8]})", key=f"cx_{h['key']}"):
                r.cancel(h["op"], h["key"])
                st.rerun()
        with st.expander("Job log (local diagnostics)"):
            key = st.selectbox("Job", [h["key"] for h in hist], format_func=lambda k: next(f"{x['op']} · {J.fmt_time(x.get('started'))}" for x in hist if x["key"] == k))
            p = r.jobs_dir / key / "stderr.log"
            txt = p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
            txt = "\n".join(ln for ln in txt.splitlines() if "have' not found" not in ln)
            st.code(txt[-4000:] or "(empty)", language=None)
            st.caption("Shown only here, on this machine. The log may contain player or team names; it lives under the git-ignored data/archive/ui_cache/.")
    n, size = r.cache_size()
    st.markdown(f"**Cache**: {n} files, {size / 1e6:.1f} MB in `data/archive/ui_cache/` (git-ignored).")
    if st.button("Clear the app cache", disabled=bool(holder)):
        r.clear_cache()
        st.cache_data.clear()
        st.success("Cleared. Results will be recomputed on request.")
