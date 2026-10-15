"""Fixed status wording. The text follows the research records (VL3, VL7, VL9, VL11, VL12, VL13, X-012, X11)."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Status:
    label: str
    color: str  # streamlit badge colours: blue, green, orange, red, violet, gray
    meaning: str


ADOPTED = Status("Adopted", "green", "Passed its pre-registered check; the system's production method for this number.")
SHADOW = Status("Shadow / Unvalidated", "orange",
                "Shadow output of the S0 simulator (VL3). Inputs are early-week, so odds are too sharp until R3; rosters "
                "are frozen; players are independent. Not a calibrated forecast: 2026 outcomes stay sealed until 2027.")
INFORMATIONAL = Status("Informational", "gray", "Shown for context only; its check did not support using it as a recommendation.")
EXPLORATORY = Status("Exploratory · not ledgered", "violet",
                     "Computed by the UI for a what-if. Not written to the decision ledger or any manifest. "
                     "Record official decisions with the terminal commands.")
FRAGILE = Status("Fragile", "red", "The ranking changes under the sensitivity settings or sits within simulation noise (VL13).")
LEDGERED = Status("Ledgered", "blue", "An official recommendation recorded by the terminal tools or the briefing (F5).")
STALE = Status("Stale", "red", "The league snapshot is older than 24 hours; rosters may have changed.")

METRIC_STATUS: dict[str, tuple[Status, str]] = {
    "ros_points": (ADOPTED, "V1 rest-of-season points (ESPN posted weeks through VE1, ros_params_v1)"),
    "vor": (ADOPTED, "V1 value over replacement (rest of season)"),
    "trade_value": (ADOPTED, "V1 0-100 display value"),
    "weekly_proj": (ADOPTED, "Weekly projection: ESPN for QB/RB/TE, frozen M4 for WR; P(active) from the frozen P1 provider"),
    "distribution": (ADOPTED, "P0 outcome distribution (pod_baseline_v0; P2 failed, so P0 stays)"),
    "dU": (ADOPTED, "V2 change in expected rest-of-season lineup points (team utility); not an acceptance prediction"),
    "wins_added": (ADOPTED, "S3 wins added (VL7; X10b supported on 2025) computed on the shadow S0 engine"),
    "p_win": (ADOPTED, "S1 simulation P(win) (X23 supported) shown through the shadow S0 engine"),
    "odds": (SHADOW, "S0 playoff and title odds"),
    "dP": (SHADOW, "Change in P(playoffs)/P(title) on S0; at these simulation counts it does not rank close candidates (X11)"),
    "nash": (INFORMATIONAL, "Nash product: a fairness summary, not an acceptance model (VL12)"),
    "streaming": (INFORMATIONAL, "Streaming view (X16 null; VL11)"),
    "late_window": (INFORMATIONAL, "Late-window swaps (X8/X9 not supported; VL11)"),
    "lineup": (ADOPTED, "D0 expected-points lineup: FLEX holds the latest kickoffs; never changes expected points (X-012)"),
}

UNSUPPORTED = [
    ("FAAB bid guidance", "The league has no acquisition budget; claims go by waiver priority."),
    ("Keepers", "keeperCount is 0 in this league."),
    ("Trade acceptance predictions", "Not modelled (V2 methodology §7). Utility and fairness are model estimates only."),
    ("ESPN's own playoff odds", "Absent from this league's ESPN response (X-004)."),
    ("Player-level K and D/ST values", "K/D-ST enter only as v0 position-level draws (kdst_v0)."),
    ("2026 accuracy or calibration", "2026 outcomes are sealed until the 2027 decision pre-registrations."),
    ("League trade-fairness monitor", "Needs league transactions (scheduled with F3-full, January 2027)."),
    ("Draft assistant", "Deferred to the 2027 pre-draft window; the R tool exists (scripts/draft_assistant.R)."),
]

REFRESH_HELP = """Refreshing data stays a terminal step (the UI never contacts ESPN). In PowerShell, from the project folder
(Rscript is not on PATH, so the alias line comes first):

```
Set-Alias Rscript "C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe"
Rscript scripts/league_refresh.R          # league snapshot (one ESPN request)
Rscript scripts/valuation_run.R --league  # optional: valuation run in this league's format (~4 min)
Rscript scripts/briefing.R                # optional: weekly briefing (~12 min; records ledger entries)
```
The scheduled dispatcher captures projections automatically before each slate."""
