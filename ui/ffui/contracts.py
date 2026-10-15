"""Column contracts for the artifacts the UI reads. A missing required column hides only the panel that needs it."""
from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

REQUIRED: dict[str, list[str]] = {
    "values": ["run_id", "player_id", "gsis_id", "espn_id", "espn_name", "position", "team", "ros_points", "vor",
               "overall_rank", "position_rank"],
    "weekly": ["player_id", "espn_id", "week", "proj", "has_game", "p_active", "source"],
    "pods": ["player_id", "espn_id", "week", "mean", "q10", "q50", "q90"],
    "roster": ["team_id", "espn_id", "position", "lineup_slot", "team_name"],
    "power_rankings": ["rank", "team_id", "U"],
    "team_needs": ["team_id", "weakest_slot", "strongest_slot"],
    "dispatch_log": ["logged_at_utc", "action", "kind", "season", "week", "reason", "result"],
    "valuation_manifest": ["run_id", "season", "week", "as_of_utc", "methodology_version", "values_sha256"],
    "decision_manifest": ["decision_id", "league_alias", "season", "week", "type", "as_of_utc", "record_sha256"],
    "league_snapshot_manifest": ["league_alias", "season", "scoring_period", "captured_at_utc", "raw_sha256"],
    "distribution_manifest": ["valuation_run_id", "season", "week", "created_at_utc", "pod_version", "pods_sha256"],
    "context_players": ["row", "player_id", "espn_id", "player_name", "position", "team_id", "free_agent", "ros_points"],
}


@dataclass
class ContractResult:
    name: str
    missing: list[str] = field(default_factory=list)
    extra: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.missing


def check(name: str, df: pd.DataFrame | None) -> ContractResult:
    req = REQUIRED[name]
    if df is None:
        return ContractResult(name, missing=list(req))
    cols = list(df.columns)
    return ContractResult(name, missing=[c for c in req if c not in cols], extra=[c for c in cols if c not in req])


def unique_key(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    """Rows whose key is duplicated (to be surfaced, never silently fanned out in a join)."""
    if df is None or df.empty:
        return pd.DataFrame(columns=cols)
    return df[df.duplicated(cols, keep=False)]


def safe_join(left: pd.DataFrame, right: pd.DataFrame, on: list[str], how: str = "left",
              validate: str = "many_to_one") -> pd.DataFrame:
    """Join on identifiers only; pandas raises if the right side has duplicate keys (validate=many_to_one)."""
    for c in on:
        if c not in left.columns or c not in right.columns:
            raise KeyError(f"join key {c!r} missing")
    return left.merge(right, on=on, how=how, validate=validate)
