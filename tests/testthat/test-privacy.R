# Privacy (master plan F3-lite): no private league value may appear in any file Git tracks.
# Reads the private values locally (league id, cookies, team names, owner ids) and reports only the
# names of offending files, never the values. Skipped where no local league configuration exists.

test_that("no league id, cookie, team name or owner id appears in a tracked file", {
  withr::local_dir(project_root)
  cred <- tryCatch(lg_credentials(), error = function(e) NULL)
  skip_if(is.null(cred) || is.na(cred$league_id), "no local league configuration")
  needles <- c(cred$league_id, cred$espn_s2, cred$swid, gsub("[{}]", "", cred$swid %||% ""))
  lg <- tryCatch(lg_latest_snapshot(nfl_season()), error = function(e) NULL)
  if (!is.null(lg)) {
    owners <- unlist(strsplit(lg$teams$owners, ",", fixed = TRUE))
    needles <- c(needles, lg$teams$team_name, owners, gsub("[{}]", "", owners))
  }
  needles <- unique(needles[!is.na(needles) & nchar(needles) >= 4])
  files <- system2("git", "ls-files", stdout = TRUE)
  files <- files[file.exists(files) & !grepl("[.](parquet|rds|png|jpg|jpeg|gz|pdf|ico)$", files, ignore.case = TRUE)]
  hit <- vapply(files, function(f) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    any(vapply(needles, function(n) grepl(n, txt, fixed = TRUE), logical(1)))
  }, logical(1))
  expect_equal(unname(files[hit]), character())   # file names only
})
