# Capture a timestamped snapshot of ESPN's live WR projections.
#
# Usage (from the project root):
#   Rscript scripts/snapshot_espn.R        # ESPN's current scoring period
#   Rscript scripts/snapshot_espn.R 5      # a specific (e.g. upcoming) week
#
# Disabled unless ESPN is enabled (config/local.yml: espn: {enabled: true}).
# Read docs/espn_projections.md (terms of use) first. Snapshots are written to
# data/snapshots/espn/ and must never be committed to this repository.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
cfg <- read_project_config()
args <- commandArgs(trailingOnly = TRUE)
path <- snapshot_espn_projections(
  position = "WR",
  league_defaults_id = cfg$espn$league_defaults_id,
  week = if (length(args) > 0) as.integer(args[[1]]) else NULL,
  enabled = isTRUE(cfg$espn$enabled)
)
cli::cli_alert_success("Saved {.file {path}}")
