"""Repository paths used by the UI. Everything is resolved from a repository root, never from the CWD.

Tests build a `Repo` over a temporary fixture tree; the app uses `default_repo()`.
"""
from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path

UI_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Repo:
    root: Path

    @property
    def manifests(self) -> Path: return self.root / "archive"
    @property
    def data_archive(self) -> Path: return self.root / "data" / "archive"
    @property
    def valuation(self) -> Path: return self.data_archive / "valuation"
    @property
    def distributions(self) -> Path: return self.data_archive / "distributions"
    @property
    def predictions(self) -> Path: return self.data_archive / "predictions"
    @property
    def decisions(self) -> Path: return self.data_archive / "decisions"
    @property
    def briefings(self) -> Path: return self.data_archive / "briefings"
    @property
    def league_analysis(self) -> Path: return self.data_archive / "league_analysis"
    @property
    def horizon(self) -> Path: return self.data_archive / "horizon_study"
    @property
    def league_snapshots(self) -> Path: return self.root / "data" / "snapshots" / "espn_league"
    @property
    def ops(self) -> Path: return self.root / "data" / "ops"
    @property
    def models(self) -> Path: return self.root / "models"
    @property
    def research(self) -> Path: return self.root / "research"
    @property
    def execution(self) -> Path: return self.research / "master_plan" / "execution"
    @property
    def ui_cache(self) -> Path:
        """The only place the UI writes (data/archive/* is git-ignored)."""
        return self.data_archive / "ui_cache"
    @property
    def adapter(self) -> Path: return self.root / "ui" / "r" / "ui_adapter.R"


def default_repo() -> Repo:
    return Repo(Path(os.environ.get("FFUI_REPO", UI_ROOT.parent)).resolve())


def find_rscript() -> str | None:
    for c in (os.environ.get("FFUI_RSCRIPT", ""), r"C:\Program Files\R\R-4.5.1\bin\Rscript.exe"):
        if c and Path(c).exists():
            return c
    return shutil.which("Rscript")


def is_inside(path: Path, parent: Path) -> bool:
    try:
        Path(path).resolve().relative_to(Path(parent).resolve())
        return True
    except ValueError:
        return False
