"""Static safety checks: local-only config, git hygiene, the adapter's side-effect boundary, no network code in the UI."""
import re
import subprocess
import tomllib
from pathlib import Path

import pytest

UI = Path(__file__).resolve().parents[1]
REPO = UI.parent
ADAPTER = (UI / "r" / "ui_adapter.R").read_text(encoding="utf-8")


def test_streamlit_config_is_local_only():
    raw = (UI / ".streamlit" / "config.toml").read_bytes()
    assert not raw.startswith(bytes([0xEF, 0xBB, 0xBF])), "a BOM makes Streamlit ignore the whole config"
    import toml  # the parser Streamlit itself uses
    toml.loads(raw.decode("utf-8"))
    cfg = tomllib.loads(raw.decode("utf-8"))
    assert cfg["server"]["address"] == "127.0.0.1"
    assert cfg["browser"]["gatherUsageStats"] is False
    assert cfg["client"]["showErrorDetails"] == "none"
    run = (UI / "run.ps1").read_text(encoding="utf-8")
    assert "--server.address 127.0.0.1" in run and "--browser.gatherUsageStats false" in run


@pytest.mark.parametrize("path", ["data/archive/ui_cache/odds/x/result.json", "data/archive/ui_cache/jobs/k/stderr.log",
                                  "ui/.venv/Lib/x.py", "data/draft/picks.csv", "ui/ffui/__pycache__/a.pyc",
                                  "ui/.streamlit/secrets.toml"])
def test_private_and_generated_paths_are_ignored(path):
    r = subprocess.run(["git", "check-ignore", "-q", path], cwd=REPO)
    assert r.returncode == 0, f"{path} is not git-ignored"


def test_ui_code_never_reads_credentials_or_opens_network():
    pat = re.compile(r"config/local\.yml|import (requests|httpx|urllib3|socket)|from urllib|urlopen|http\.client|"
                     r"lg_credentials|espn_s2|SWID", re.I)
    hits = [str(p.relative_to(UI)) for p in UI.rglob("*.py") if ".venv" not in p.parts and "tests" not in p.parts
            and pat.search(p.read_text(encoding="utf-8"))]
    assert hits == []


def test_ui_never_shells_out_with_a_shell():
    for p in UI.rglob("*.py"):
        if ".venv" in p.parts or "tests" in p.parts:
            continue
        assert "shell=True" not in p.read_text(encoding="utf-8"), p


def test_ui_python_writes_only_to_the_cache():
    """Every write path in the job runner is derived from repo.ui_cache."""
    src = (UI / "ffui" / "jobs.py").read_text(encoding="utf-8")
    assert "self.cache = repo.ui_cache" in src and "assert is_inside(out, self.cache)" in src
    for p in (UI / "ffui").glob("*.py"):
        s = p.read_text(encoding="utf-8")
        if p.name != "jobs.py":
            assert not re.search(r"\.write_text\(|open\([^)]*['\"]w", s), f"{p.name} writes files"


PERSISTENCE = ["append_manifest", "lg_archive_query", "lg_archive_analysis", "lg_ledger_record", "lg_ledger_action",
               "lg_snapshot_league", "lg_fetch_league", "fetch_live_nflverse", "refresh_live_data", "write_once"]


def test_adapter_tripwires_cover_persistence_and_network():
    block = re.search(r'for \(fn in c\((.*?)\)\) \{', ADAPTER, re.S).group(1)
    for fn in PERSISTENCE:
        assert f'"{fn}"' in block, fn
    assert 'block_ns("httr2"' in ADAPTER and "req_perform" in ADAPTER
    assert '"commit"' in ADAPTER and '"push"' in ADAPTER


def test_adapter_never_calls_persistence_directly():
    body = ADAPTER.split("# ---- ops ----", 1)[1]
    for fn in PERSISTENCE + ["tar_make", "lg_ledger_lineup_payload"]:
        assert not re.search(rf"\b{fn}\s*\(", body), fn


def test_adapter_output_confined_to_ui_cache():
    assert 'startsWith(out_dir, paste0(cache_root, "/"))' in ADAPTER
    assert "file.rename(tmp, out_dir)" in ADAPTER


def test_tripwired_functions_exist_in_R():
    """If a persistence function is renamed in R/, its trip-wire would silently stop protecting: fail instead."""
    src = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in (REPO / "R").rglob("*.R"))
    for fn in PERSISTENCE:
        assert re.search(rf"^{fn} <- function", src, re.M), fn


def test_research_allow_list_matches_page():
    page = (UI / "views" / "research.py").read_text(encoding="utf-8")
    allow = re.search(r"RESEARCH_TARGETS <- c\((.*?)\)", ADAPTER, re.S).group(1)
    for name in re.findall(r'"(\w+)"', allow):
        assert f'"{name}"' in page
    assert "2026" in ADAPTER.split("research_target = {", 1)[1].split("},", 1)[0]
