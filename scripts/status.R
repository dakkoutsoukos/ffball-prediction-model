# Prospective-record status dashboard (read-only; no ESPN requests, no git writes).
#
# Usage (from the project root):   Rscript scripts/status.R [season]
#
# Shows the next week to predict, next kickoff, which upcoming games already have
# an archived pre-kickoff run, archive hash integrity, whether manifests are
# committed and pushed, and when the evidence was last backed up.

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1) as.integer(args[[1]]) else as.integer(format(Sys.Date(), "%Y"))
invisible(print_status(season))
