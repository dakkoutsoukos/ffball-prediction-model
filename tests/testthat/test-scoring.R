rules <- read_scoring_rules("espn_ppr", dir = file.path(project_root, "config", "scoring"))

blank_line <- function(...) {
  x <- as.list(setNames(rep(0, length(rules$weights)), names(rules$weights)))
  tibble::as_tibble(utils::modifyList(x, list(...)))
}

test_that("ESPN PPR scores a typical WR line", {
  # 7 rec, 112 yds, 1 TD -> 7 + 11.2 + 6
  expect_equal(score_fantasy_points(blank_line(receptions = 7, receiving_yards = 112, receiving_tds = 1), rules), 24.2)
})

test_that("yardage is fractional and negative yards subtract", {
  expect_equal(score_fantasy_points(blank_line(receiving_yards = 7), rules), 0.7)
  expect_equal(score_fantasy_points(blank_line(rushing_yards = -4), rules), -0.4)
  expect_equal(score_fantasy_points(blank_line(passing_yards = 251), rules), 10.04)
})

test_that("fumbles lost, 2pt conversions, and return TDs are scored", {
  line <- blank_line(receptions = 3, receiving_yards = 30, fumbles_lost_total = 1,
                     receiving_2pt_conversions = 1, special_teams_tds = 1)
  expect_equal(score_fantasy_points(line, rules), 3 + 3 - 2 + 2 + 6)
  # ESPN penalises every fumble lost, including on kick/punt returns.
  expect_equal(score_fantasy_points(blank_line(fumbles_lost_total = 2), rules), -4)
  expect_false(any(c("sack_fumbles_lost", "rushing_fumbles_lost", "receiving_fumbles_lost") %in%
                     names(rules$weights)))   # never double-count fumble components
})

test_that("QB passing line uses 4-point passing TDs and -2 interceptions", {
  line <- blank_line(passing_yards = 300, passing_tds = 2, passing_interceptions = 1, rushing_yards = 20)
  expect_equal(score_fantasy_points(line, rules), 12 + 8 - 2 + 2)
})

test_that("NA stats count as zero but missing columns fail loudly", {
  line <- blank_line(receptions = 2)
  line$receiving_yards <- NA_real_
  expect_equal(score_fantasy_points(line, rules), 2)
  expect_error(score_fantasy_points(dplyr::select(line, -receptions), rules), "missing scoring column")
})

test_that("scoring is vectorised and configurable", {
  lines <- dplyr::bind_rows(blank_line(receptions = 5), blank_line(receptions = 1, receiving_tds = 1))
  expect_equal(score_fantasy_points(lines, rules), c(5, 7))
  half <- rules
  half$weights[["receptions"]] <- 0.5
  expect_equal(score_fantasy_points(lines, half), c(2.5, 6.5))
})

test_that("unknown scoring system errors", {
  expect_error(read_scoring_rules("nope", dir = file.path(project_root, "config", "scoring")), "not found")
})
