"""Research: frozen lineages, registered results and data-use rules. Read-only; never reruns research and never
shows 2026 outcomes (sealed)."""
import pandas as pd
import streamlit as st

from ffui import components as C
from ffui import labels as L
from ffui import research as R
from ffui import state as S

C.page_header("Research", "Model lineages, registered results and the rules that protect them.")
st.info("2026 outcomes are **sealed** (contamination register: `sealed_seasons: 2026`). This page shows registered "
        "results, development metrics and methodology only: no 2026 accuracy or calibration, and nothing here reruns "
        "an experiment.", icon=":material/lock:")
rp = S.repo()

t_models, t_truth, t_miles, t_exp, t_data, t_logs, t_targets = st.tabs(
    ["Models", "Source of truth", "Milestones", "Experiments", "Data use", "Logs", "Stored results"])

with t_models:
    st.markdown("**Frozen projection lineages** (`models/registry/`)")
    st.dataframe(R.registries(rp), hide_index=True, width="stretch")
    st.markdown("**Frozen parameter files**")
    st.dataframe(R.frozen_params(rp), hide_index=True, width="stretch")
    st.markdown("**Prediction fingerprints** (verified by the pipeline's `*_fingerprint_check` targets)")
    st.dataframe(R.fingerprints(rp), hide_index=True, width="stretch")
    st.caption("Read-only. Frozen files are never edited; a change is a new version with its own pre-registration.")

with t_truth:
    st.markdown("Which model produces each number shown in this app, and its status.")
    rows = [{"metric": k, "status": s.label, "source": text} for k, (s, text) in L.METRIC_STATUS.items()]
    st.dataframe(pd.DataFrame(rows), hide_index=True, width="stretch")
    for s in (L.ADOPTED, L.SHADOW, L.INFORMATIONAL, L.EXPLORATORY, L.FRAGILE, L.LEDGERED):
        st.markdown(f"- **{s.label}**: {s.meaning}")

with t_miles:
    m = R.milestones(rp)
    if m is None:
        C.empty_state("No milestone tracker", "research/master_plan/execution/milestone_tracker.md")
    else:
        stat = st.multiselect("Status contains", ["COMPLETED", "FAILED", "IN PROGRESS", "NOT STARTED", "DEFERRED", "RESEARCHED"])
        v = m[m["Status"].str.contains("|".join(stat))] if stat else m
        st.dataframe(v, hide_index=True, width="stretch", height=520)
        st.caption("From the execution tracker (Markdown). A milestone is completed only when its acceptance criteria pass.")

with t_exp:
    e = R.experiment_results(rp)
    if e is None:
        C.empty_state("No results table", "research/master_plan/execution/experiment_results.md")
    else:
        q = st.text_input("Filter", placeholder="id, family or text")
        v = e[e.apply(lambda r: q.lower() in " ".join(map(str, r.values)).lower(), axis=1)] if q else e
        st.dataframe(v, hide_index=True, width="stretch", height=520)
        st.caption("Registered results with their classification. Development results are labelled as such; "
                   "confirmatory checks are run once (spent checks are listed under Data use).")

with t_data:
    c = R.contamination(rp)
    if not c:
        C.empty_state("No contamination register", "research/contamination_register.yml")
    else:
        st.markdown(f"**Sealed seasons**: {', '.join(map(str, (c.get('sealed_seasons') or {}).keys()))}")
        for k, v in (c.get("sealed_seasons") or {}).items():
            st.caption(f"{k}: {v}")
        fam = []
        for name, f in (c.get("families") or {}).items():
            row = {"family": name, "description": f.get("description", "")}
            for role in ("development", "training", "check", "confirmatory", "contaminated", "outcome_free", "descriptive"):
                if role in f:
                    row[role] = ", ".join(map(str, f[role]))
            fam.append(row)
        st.markdown("**Question families and the seasons each may use**")
        st.dataframe(pd.DataFrame(fam), hide_index=True, width="stretch")
        st.markdown("**Spent checks** (run once; never re-run)")
        st.dataframe(pd.DataFrame(c.get("spent_checks") or []), hide_index=True, width="stretch")

with t_logs:
    which = st.radio("Log", ["Experiment log (E-entries)", "Valuation log (VL-entries)", "Decisions"], horizontal=True)
    path = {"Experiment log (E-entries)": rp.research / "experiment_log.md",
            "Valuation log (VL-entries)": rp.research / "valuation_log.md",
            "Decisions": rp.execution / "decisions.md"}[which]
    secs = R.log_sections(path)
    if not secs:
        C.empty_state("Empty log", str(path))
    else:
        heads = [h for h, _ in secs]
        pick = st.selectbox("Entry", list(reversed(heads)))
        body = dict(secs)[pick]
        st.markdown(f"### {pick}")
        st.markdown(body)
        st.caption(f"Read-only view of {path.relative_to(rp.root)}.")

with t_targets:
    st.caption("Stored result objects from the pipeline (read with `targets::tar_read`; never rebuilt). Only an "
               "allow-list of pre-2026 result objects is available, and the adapter refuses any table with 2026 rows.")
    ctx_stub = {"inputs": {}}
    name = st.selectbox("Result object", ["vl11_result", "x22_result", "p3_gate_result", "s2_summary", "f1_mde",
                                          "e19_check", "m4_dev_eval", "m2_holdout_tables"])
    job = C.job_control(f"target_{name}", "research_target", {"name": name}, ctx_stub, "Load stored result")
    if job and job.result:
        content = job.result.get("content") or {}
        if not content:
            st.caption("The object has no table-shaped content to display.")
        for k, v in content.items():
            st.markdown(f"**{k}**")
            if isinstance(v, list) and v and isinstance(v[0], dict):
                st.dataframe(pd.DataFrame(v), hide_index=True, width="stretch")
            else:
                st.write(v)
        C.provenance(job.meta)
