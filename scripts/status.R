# Prospective-record status dashboard (read-only; no ESPN requests, no git writes).
#
# Usage (from the project root):   Rscript scripts/status.R [season]
#
# Shows the next week to predict, next kickoff, which upcoming games already have
# an archived pre-kickoff run, archive hash integrity, whether manifests are
# committed and pushed, and when the evidence was last backed up. The "Scheduled
# operations" section adds the dispatcher's view (F0): which upcoming games have a run
# made after both teams' final injury reports, alerts for games within 3 h of kickoff
# without one, and the all-position capture cadence.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1) as.integer(args[[1]]) else nfl_season()
invisible(print_status(season))
invisible(print_ops_status(season))
