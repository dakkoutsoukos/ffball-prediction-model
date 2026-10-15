"""Read-only access to artifacts the pipeline already writes. Nothing here writes, fetches or runs R.

Discovery goes through the committed manifests first (they carry run ids and hashes), then the folders.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq

from .paths import Repo

STAMP = "%Y%m%dT%H%M%SZ"


def parse_stamp(s: str | None) -> datetime | None:
    if not s or not isinstance(s, str):
        return None
    for fmt in (STAMP, "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def age_hours(when: datetime | None, now: datetime | None = None) -> float | None:
    if when is None:
        return None
    now = now or datetime.now(timezone.utc)
    return (now - when).total_seconds() / 3600


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_parquet(path: Path) -> pd.DataFrame:
    # memory_map off: the archive is read by R and the dispatcher too (the R side uses mmap = FALSE)
    return pq.read_table(path, memory_map=False).to_pandas()


def read_manifest(repo: Repo, name: str) -> pd.DataFrame:
    p = repo.manifests / f"{name}.csv"
    if not p.exists():
        return pd.DataFrame()
    return pd.read_csv(p, dtype=str, keep_default_na=False, na_values=["NA", ""])


@dataclass
class Provenance:
    source: str
    run_id: str | None = None
    as_of_utc: str | None = None
    sha256: str | None = None
    hash_ok: bool | None = None
    model_versions: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)


# ---------------------------------------------------------------- valuation runs
@dataclass
class ValuationRun:
    run_id: str
    season: int
    week: int
    as_of_utc: str
    methodology_version: str
    dir: Path
    values_sha256: str | None
    provenance: Provenance


def valuation_runs(repo: Repo) -> list[ValuationRun]:
    man = read_manifest(repo, "valuation_manifest")
    out = []
    for _, r in man.iterrows():
        d = repo.valuation / f"season={int(r['season'])}" / f"week={int(r['week']):02d}" / f"run={r['run_id']}"
        if not d.exists():
            continue
        prov = Provenance(source=str(d.relative_to(repo.root)), run_id=r["run_id"], as_of_utc=r.get("as_of_utc"),
                          sha256=r.get("values_sha256"), model_versions={"methodology": r.get("methodology_version")})
        out.append(ValuationRun(r["run_id"], int(r["season"]), int(r["week"]), r.get("as_of_utc", ""),
                                r.get("methodology_version", ""), d, r.get("values_sha256"), prov))
    return sorted(out, key=lambda v: v.run_id)


def latest_valuation(repo: Repo, run_id: str | None = None) -> ValuationRun | None:
    runs = valuation_runs(repo)
    if run_id:
        runs = [r for r in runs if r.run_id == run_id]
    return runs[-1] if runs else None


def valuation_table(run: ValuationRun, name: str, verify: bool = False) -> pd.DataFrame | None:
    p = run.dir / f"{name}.parquet"
    if not p.exists():
        return None
    if verify and name == "values" and run.values_sha256:
        run.provenance.hash_ok = sha256_file(p) == run.values_sha256
    return read_parquet(p)


def run_meta(run: ValuationRun) -> dict:
    p = run.dir / "run_meta.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def value_history(repo: Repo) -> pd.DataFrame:
    """VOR and ROS points per player across all valuation runs (accrues over the season)."""
    frames = []
    for run in valuation_runs(repo):
        v = valuation_table(run, "values")
        if v is None:
            continue
        cols = [c for c in ["player_id", "espn_id", "position", "ros_points", "vor", "trade_value", "overall_rank"] if c in v]
        v = v[cols].copy()
        v["run_id"], v["week"], v["as_of_utc"] = run.run_id, run.week, run.as_of_utc
        frames.append(v)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


# ---------------------------------------------------------------- distributions (P0)
def latest_pods(repo: Repo, valuation_run_id: str | None = None) -> tuple[pd.DataFrame | None, Provenance | None]:
    man = read_manifest(repo, "distribution_manifest")
    if man.empty:
        return None, None
    if valuation_run_id is not None:
        same = man[man["valuation_run_id"] == valuation_run_id]
        man = same if not same.empty else man
    r = man.sort_values("created_at_utc").iloc[-1]
    root = repo.distributions / f"season={int(r['season'])}" / f"week={int(r['week']):02d}"
    cands = sorted(root.glob("run=*/pods.parquet")) if root.exists() else []
    if not cands:
        return None, None
    p = cands[-1]
    prov = Provenance(source=str(p.relative_to(repo.root)), run_id=r["valuation_run_id"], as_of_utc=r["created_at_utc"],
                      sha256=r.get("pods_sha256"), model_versions={"pod": r.get("pod_version")})
    if valuation_run_id and r["valuation_run_id"] != valuation_run_id:
        prov.notes.append("Distributions were built from a different valuation run than the values shown.")
    return read_parquet(p), prov


# ---------------------------------------------------------------- league snapshot
@dataclass
class LeagueSnapshot:
    alias: str
    season: int
    captured_at_utc: str
    raw_sha256: str
    roster_path: Path | None
    raw_path: Path | None
    scoring_period: int | None

    @property
    def captured(self) -> datetime | None:
        return parse_stamp(self.captured_at_utc)


def latest_league_snapshot(repo: Repo) -> LeagueSnapshot | None:
    man = read_manifest(repo, "league_snapshot_manifest")
    if man.empty:
        return None
    r = man.sort_values("captured_at_utc").iloc[-1]
    d = repo.league_snapshots / r["league_alias"] / f"season={int(r['season'])}"
    stem = f"captured_at={r['captured_at_utc']}"
    roster = d / f"{stem}_roster.parquet"
    raw = d / f"{stem}.json.gz"
    sp = r.get("scoring_period")
    return LeagueSnapshot(r["league_alias"], int(r["season"]), r["captured_at_utc"], r["raw_sha256"],
                          roster if roster.exists() else None, raw if raw.exists() else None,
                          int(sp) if sp not in (None, "") and str(sp).isdigit() else None)


def league_roster(snap: LeagueSnapshot) -> pd.DataFrame | None:
    return read_parquet(snap.roster_path) if snap and snap.roster_path else None


def league_teams(snap: LeagueSnapshot) -> pd.DataFrame | None:
    r = league_roster(snap)
    if r is None:
        return None
    return r[["team_id", "team_abbrev", "team_name"]].drop_duplicates("team_id").sort_values("team_id").reset_index(drop=True)


# ---------------------------------------------------------------- league analysis (V2 snapshot command)
def latest_league_analysis(repo: Repo, alias: str | None) -> tuple[dict[str, pd.DataFrame], Provenance | None]:
    if not alias:
        return {}, None
    root = repo.league_analysis / alias
    runs = sorted(root.glob("season=*/run=*")) if root.exists() else []
    runs = [r for r in runs if r.is_dir()]
    if not runs:
        return {}, None
    d = runs[-1]
    out = {p.stem: read_parquet(p) for p in d.glob("*.parquet")}
    meta = d / "analysis_meta.json"
    m = json.loads(meta.read_text(encoding="utf-8")) if meta.exists() else {}
    prov = Provenance(source=str(d.relative_to(repo.root)), run_id=d.name.removeprefix("run="),
                      as_of_utc=m.get("captured_league_at_utc") or m.get("created_at_utc"),
                      model_versions={"methodology": m.get("methodology_version")})
    return out, prov


# ---------------------------------------------------------------- decision ledger (read-only; recommendations only)
def decision_records(repo: Repo, alias: str | None = None, types: tuple[str, ...] | None = None) -> list[dict]:
    """Ledgered recommendations with their manifest hash check. Outcomes are sealed and never read here."""
    man = read_manifest(repo, "decision_manifest")
    if man.empty:
        return []
    if alias:
        man = man[man["league_alias"] == alias]
    if types:
        man = man[man["type"].isin(types)]
    out = []
    for _, r in man.iterrows():
        p = (repo.decisions / r["league_alias"] / f"season={int(r['season'])}" / f"week={int(r['week']):02d}"
             / f"{r['decision_id']}.json")
        if not p.exists():
            continue
        rec = json.loads(p.read_text(encoding="utf-8"))
        rec["_hash_ok"] = sha256_file(p) == r["record_sha256"]
        rec["_path"] = str(p.relative_to(repo.root))
        out.append(rec)
    return sorted(out, key=lambda d: d.get("as_of_utc", ""))


def latest_decision(repo: Repo, dtype: str, alias: str | None = None) -> dict | None:
    recs = decision_records(repo, alias, (dtype,))
    return recs[-1] if recs else None


# ---------------------------------------------------------------- briefings (D5 / I2)
def briefings(repo: Repo) -> list[Path]:
    return sorted(repo.briefings.glob("season=*/week=*/briefing_*.html"), key=lambda p: p.name)


def briefing_time(p: Path) -> datetime | None:
    m = re.search(r"briefing_(\d{8}T\d{6}Z)", p.name)
    return parse_stamp(m.group(1)) if m else None


# ---------------------------------------------------------------- operations
def ops_status(repo: Repo) -> dict:
    p = repo.ops / "status.txt"
    if not p.exists():
        return {"available": False}
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    out: dict = {"available": True, "lines": lines, "modified_utc": datetime.fromtimestamp(p.stat().st_mtime, timezone.utc)}
    for ln in lines:
        k, _, v = ln.partition(":")
        key = k.strip().lower()
        if key in ("decision", "target", "next window opens", "upcoming games", "all-position captures per week"):
            out[key] = v.strip()
        if ln.startswith("PUSH NEEDED"):
            m = re.search(r"(\d+) local commit", ln)
            out["commits_not_pushed"] = int(m.group(1)) if m else None
        if ln.startswith(("ALERT", "WARNING", "COMMIT NEEDED")):
            out.setdefault("alerts", []).append(ln)
    return out


def dispatch_log(repo: Repo, n: int = 200) -> pd.DataFrame:
    p = repo.ops / "dispatch_log.csv"
    if not p.exists():
        return pd.DataFrame()
    return pd.read_csv(p, dtype=str, keep_default_na=False).tail(n)


def manifest_folder_audit(repo: Repo) -> pd.DataFrame:
    """Manifest rows whose folder/file is missing (and runs on disk that no manifest lists)."""
    rows = []
    man = read_manifest(repo, "valuation_manifest")
    listed = set()
    for _, r in man.iterrows():
        d = repo.valuation / f"season={int(r['season'])}" / f"week={int(r['week']):02d}" / f"run={r['run_id']}"
        listed.add(d.resolve())
        rows.append({"manifest": "valuation", "id": r["run_id"], "on_disk": d.exists()})
    for d in repo.valuation.glob("season=*/week=*/run=*"):
        if d.resolve() not in listed:
            rows.append({"manifest": "valuation", "id": d.name.removeprefix("run="), "on_disk": True, "unlisted": True})
    pm = read_manifest(repo, "prediction_manifest")
    for _, r in pm.iterrows():
        d = repo.predictions / f"season={int(r['season'])}" / f"week={int(r['week']):02d}" / f"run={r['run_id']}"
        rows.append({"manifest": "prediction", "id": r["run_id"], "on_disk": d.exists()})
    dm = read_manifest(repo, "decision_manifest")
    for _, r in dm.iterrows():
        p = (repo.decisions / r["league_alias"] / f"season={int(r['season'])}" / f"week={int(r['week']):02d}"
             / f"{r['decision_id']}.json")
        rows.append({"manifest": "decision", "id": r["decision_id"], "on_disk": p.exists()})
    df = pd.DataFrame(rows)
    if not df.empty and "unlisted" not in df:
        df["unlisted"] = False
    return df.fillna({"unlisted": False}) if not df.empty else df


def manifest_summary(repo: Repo) -> pd.DataFrame:
    rows = []
    for p in sorted(repo.manifests.glob("*.csv")):
        df = pd.read_csv(p, dtype=str, keep_default_na=False)
        tcols = [c for c in df.columns if c.endswith("_utc") or c in ("run_id", "query_id", "created_at_utc")]
        last = df[tcols[0]].iloc[-1] if len(df) and tcols else ""
        rows.append({"manifest": p.stem, "rows": len(df), "latest": last})
    return pd.DataFrame(rows)


def horizon_study(repo: Repo) -> tuple[dict | None, str | None]:
    files = sorted(repo.horizon.glob("season=*/run=*.json"))
    if not files:
        return None, None
    return json.loads(files[-1].read_text(encoding="utf-8")), str(files[-1].relative_to(repo.root))


def read_gz_json(path: Path) -> dict:
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return json.load(f)
