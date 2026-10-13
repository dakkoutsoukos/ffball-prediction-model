# Task Scheduler setup for the F0 dispatcher (owner decision O1, approved 2026-10-13).
#
# Writes two git-ignored files under scripts/ops/ (they hold absolute, machine-specific paths):
#   ffball_dispatch.cmd       the wrapper the task runs (cd to the project, Rscript scripts/ops_dispatch.R)
#   ffball_dispatch_task.xml  the task definition: hourly at :05, only while you are logged on (no
#                             stored password), hidden (conhost --headless), allowed on battery,
#                             started after a missed trigger, one instance at a time, 2 h limit
# and optionally registers, triggers or removes the task "FFball_dispatch".
#
# Usage (from the project root):
#   Rscript scripts/ops_setup.R                # write the files; print the commands
#   Rscript scripts/ops_setup.R --register     # also register (or replace) the task
#   Rscript scripts/ops_setup.R --run-now      # trigger the registered task once (smoke test)
#   Rscript scripts/ops_setup.R --status       # show the task's last run time and result
#   Rscript scripts/ops_setup.R --install-push-log  # git pre-push hook logging push times (E16 late-push rule)
#   Rscript scripts/ops_setup.R --unregister   # remove the task
#
# The dispatcher only commits locally. Pushing before kickoff stays your job (docs/prospective_protocol.md).

suppressPackageStartupMessages(
  for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
)
args <- commandArgs(trailingOnly = TRUE)
task <- "FFball_dispatch"
root <- normalizePath(".", winslash = "/")
if (.Platform$OS.type != "windows") stop("Task Scheduler setup is Windows-only.")
if (!file.exists("scripts/ops_dispatch.R")) stop("Run from the project root.")

dir.create("scripts/ops", showWarnings = FALSE)
rscript <- file.path(R.home("bin"), "Rscript.exe")
cmd <- file.path(root, "scripts", "ops", "ffball_dispatch.cmd")
xml <- file.path(root, "scripts", "ops", "ffball_dispatch_task.xml")
writeLines(ops_wrapper_cmd(root, rscript), cmd)
nxt <- as.POSIXlt(Sys.time())
nxt$min <- 5
nxt$sec <- 0
start <- as.POSIXct(nxt) + if (as.POSIXlt(Sys.time())$min >= 5) 3600 else 0
user <- paste0(Sys.getenv("USERDOMAIN"), "\\", Sys.getenv("USERNAME"))
write_utf16(ops_task_xml(cmd, root, user, start), xml)
cli::cli_alert_success("Wrote {.file {cmd}} and {.file {xml}} (git-ignored).")

sch <- function(...) {
  out <- suppressWarnings(system2("schtasks", c(...), stdout = TRUE, stderr = TRUE))
  list(code = attr(out, "status") %||% 0L, out = out)
}
if ("--register" %in% args) {
  r <- sch("/Create", "/TN", task, "/XML", shQuote(win_path(xml)), "/F")
  if (r$code != 0) stop("schtasks /Create failed: ", paste(r$out, collapse = " "))
  cli::cli_alert_success("Registered task {.val {task}}: hourly at :05 from {format(start, '%Y-%m-%d %H:%M')} local time.")
}
if ("--run-now" %in% args) {
  r <- sch("/Run", "/TN", task)
  if (r$code != 0) stop("schtasks /Run failed: ", paste(r$out, collapse = " "))
  cli::cli_alert_success("Triggered {.val {task}}; check {.file data/ops/status.txt} and {.file data/ops/dispatch_log.csv} in a minute.")
}
if ("--status" %in% args) {
  r <- sch("/Query", "/TN", task, "/V", "/FO", "LIST")
  keep <- grepl("^(TaskName|Status|Next Run Time|Last Run Time|Last Result|Task To Run|Run As User|Logon Mode):", r$out)
  cat(r$out[keep], sep = "\n")
}
if ("--install-push-log" %in% args) {
  hook <- file.path(system2("git", c("rev-parse", "--git-path", "hooks"), stdout = TRUE), "pre-push")
  if (file.exists(hook) && !any(grepl("FFball", readLines(hook, warn = FALSE)))) {
    stop("A different pre-push hook already exists at ", hook, "; not overwriting it.")
  }
  con <- file(hook, "wb")   # LF line endings: the hook runs under Git's sh
  writeLines(push_log_hook(), con, sep = "\n")
  close(con)
  Sys.chmod(hook, "0755")
  cli::cli_alert_success("Installed the push-time logger {.file {hook}} (logs to data/ops/push_log.csv; never blocks a push).")
}
if ("--unregister" %in% args) {
  r <- sch("/Delete", "/TN", task, "/F")
  if (r$code != 0) stop("schtasks /Delete failed: ", paste(r$out, collapse = " "))
  cli::cli_alert_success("Removed task {.val {task}}.")
}
if (!length(intersect(args, c("--register", "--run-now", "--status", "--install-push-log", "--unregister")))) {
  cli::cli_text("Register:   Rscript scripts/ops_setup.R --register")
  cli::cli_text("Smoke test: Rscript scripts/ops_setup.R --run-now   (then read data/ops/status.txt)")
}
