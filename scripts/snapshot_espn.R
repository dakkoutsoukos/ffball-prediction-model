# Capture a timestamped snapshot of ESPN's current-week WR projections.
#
# Usage (from the project root):  Rscript scripts/snapshot_espn.R
#
# Disabled unless config/project.yml sets espn.enabled: true. Read
# docs/espn_projections.md (terms of use) first. Snapshots are written to
# data/snapshots/espn/ and must never be committed to this repository.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
cfg <- read_project_config()
path <- snapshot_espn_projections(
  position = "WR",
  league_defaults_id = cfg$espn$league_defaults_id,
  enabled = isTRUE(cfg$espn$enabled)
)
cli::cli_alert_success("Saved {.file {path}}")
