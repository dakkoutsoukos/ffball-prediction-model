"""Read-only parsing of the research records (Markdown tables, YAML registries). Sealed outcomes are never read."""
from __future__ import annotations

import re
from pathlib import Path

import pandas as pd
import yaml

from .paths import Repo


def md_tables(text: str) -> list[pd.DataFrame]:
    """All pipe tables in a Markdown document."""
    tables, cur = [], []
    for ln in text.splitlines() + [""]:
        s = ln.strip()
        if s.startswith("|") and s.endswith("|"):
            cur.append(s)
            continue
        if len(cur) >= 2 and re.match(r"^\|[\s:\-|]+\|$", cur[1]):
            head = [c.strip() for c in cur[0].strip("|").split("|")]
            rows = [[c.strip() for c in r.strip("|").split("|")] for r in cur[2:]]
            rows = [r + [""] * (len(head) - len(r)) if len(r) < len(head) else r[:len(head)] for r in rows]
            tables.append(pd.DataFrame(rows, columns=head))
        cur = []
    return tables


def first_table_with(path: Path, column: str) -> pd.DataFrame | None:
    if not path.exists():
        return None
    for t in md_tables(path.read_text(encoding="utf-8")):
        if column in t.columns:
            return t
    return None


def milestones(repo: Repo) -> pd.DataFrame | None:
    return first_table_with(repo.execution / "milestone_tracker.md", "Milestone")


def experiment_results(repo: Repo) -> pd.DataFrame | None:
    return first_table_with(repo.execution / "experiment_results.md", "Classification")


def registries(repo: Repo) -> pd.DataFrame:
    rows = []
    for p in sorted((repo.models / "registry").glob("*.yml")):
        y = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        models = y.get("models") or []
        ids = [str(m.get("model_id", m.get("id", ""))) for m in models if isinstance(m, dict)] if isinstance(models, list) \
            else [str(k) for k in models] if isinstance(models, dict) else []
        rationale = str(y.get("selection_rationale") or "").split(".")[0]
        rows.append({"registry": p.stem, "lineage": y.get("lineage", p.stem.upper()), "model_ids": ", ".join(ids),
                     "frozen_commit": (y.get("frozen_commit") or y.get("frozen_parent_commit") or "")[:10],
                     "summary": rationale,
                     "frozen_at_utc": y.get("frozen_at_utc"), "file": str(p.relative_to(repo.root))})
    return pd.DataFrame(rows)


def frozen_params(repo: Repo) -> pd.DataFrame:
    rows = []
    for p in sorted(repo.models.glob("*/*.yml")):
        if p.parent.name == "registry":
            continue
        y = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        meta = y if isinstance(y, dict) else {}
        meta = meta.get("meta", meta) if isinstance(meta.get("meta"), dict) else meta
        head = p.read_text(encoding="utf-8").splitlines()[0].lstrip("# ").strip()
        rows.append({"file": str(p.relative_to(repo.root)), "version": str(meta.get("version") or p.stem),
                     "pre_registration": str(meta.get("pre_registration") or meta.get("entry") or ""),
                     "header": head[:140],
                     "bytes": p.stat().st_size})
    return pd.DataFrame(rows)


def fingerprints(repo: Repo) -> pd.DataFrame:
    frames = []
    for p in sorted((repo.models / "fingerprints").glob("*.csv")):
        d = pd.read_csv(p, dtype=str)
        d.insert(0, "fingerprint", p.stem)
        frames.append(d)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def contamination(repo: Repo) -> dict:
    p = repo.research / "contamination_register.yml"
    return yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else {}


def log_sections(path: Path) -> list[tuple[str, str]]:
    """(heading, body) for each level-2 section of a research log, newest last as written."""
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    parts = re.split(r"(?m)^## ", text)
    out = []
    for part in parts[1:]:
        head, _, body = part.partition("\n")
        out.append((head.strip(), body))
    return out
