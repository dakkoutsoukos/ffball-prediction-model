# Verified private backup of the prospective evidence.
#
# Usage (from the project root):   Rscript scripts/backup_archives.R "<private folder>"
#   e.g. an external drive (E:/ffball_backup) or a private folder that you choose.
#
# Copies data/archive, data/snapshots, data/raw/nflverse_live and the 2026 ESPN
# pulls, then re-hashes every copied file (SHA-256). Never deletes anything at
# the destination. These files contain ESPN-derived data: keep the destination
# PRIVATE (not a public repo or a shared link).
#
# Restore: copy the same directories back into the project, then run
#   Rscript scripts/status.R      # verifies every file against the committed manifests

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop('Usage: Rscript scripts/backup_archives.R "<private folder>"')
rows <- backup_archives(args[[1]])
cli::cli_alert_success("Backed up and verified {nrow(rows)} files to {.file {args[[1]]}}")
