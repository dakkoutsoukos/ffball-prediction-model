# Lineup helpers (master plan D0): kickoff slotting, locks, game-time plans. Toy data only.

lh_league <- function() {
  val_league(list(name = "toy", teams = 8, slots = list(
    list(name = "QB", eligible = "QB", count = 1), list(name = "RB", eligible = "RB", count = 2),
    list(name = "WR", eligible = "WR", count = 2), list(name = "TE", eligible = "TE", count = 1),
    list(name = "FLEX", eligible = c("RB", "WR", "TE"), count = 2)),
    bench = 7, regular_season_weeks = c(1, 14), playoff_weeks = c(15, 17)))
}

lh_prior <- function() read_availability_prior(file.path(project_root, "config", "availability_prior.yml"))

lh_et <- function(x) { t <- as.POSIXct(x, tz = "America/New_York"); attr(t, "tzone") <- "UTC"; t }

#' A 12-player roster for week 6 (Thu 10-15 .. Mon 10-19).
lh_team <- function() {
  tibble::tibble(
    player_name = c("QB1", "RB1", "RB2", "RB3", "RB4", "WR1", "WR2", "WR3", "WR4", "TE1", "TE2", "RB5"),
    position = c("QB", "RB", "RB", "RB", "RB", "WR", "WR", "WR", "WR", "TE", "TE", "RB"),
    proj = c(22, 18, 15, 12, 6, 17, 14, 13, 5, 9, 4, 11),
    kickoff_utc = lh_et(c("2026-10-18 13:00", "2026-10-15 20:15", "2026-10-18 20:20", "2026-10-18 13:00",
                          "2026-10-18 13:00", "2026-10-18 16:25", "2026-10-18 13:00", "2026-10-19 20:15",
                          "2026-10-18 13:00", "2026-10-18 16:25", "2026-10-18 13:00", "2026-10-18 13:00")),
    status = "NORMAL", is_ir = c(rep(FALSE, 11), TRUE))
}

test_that("existing slot assignment and allocation are unchanged (V1/V2 bit-identity guard)", {
  d <- lh_team()
  hall <- val_hall_table(val_one_team(lh_league()))
  st <- val_allocate(ifelse(d$is_ir, 0, d$proj), d$position, hall)
  expect_equal(which(st), c(1L, 2L, 3L, 4L, 6L, 7L, 8L, 10L))
  expect_equal(val_assign_slots(d$proj, d$position, st, val_one_team(lh_league()))[st],
               c("QB", "RB", "RB", "FLEX", "WR", "WR", "FLEX", "TE"))
})

test_that("kickoff slotting puts the latest starters in FLEX and never changes expected points", {
  d <- lh_team()
  league <- lh_league()
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, league)
  s <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, league)
  flex <- d$player_name[which(s == "FLEX")]
  expect_setequal(flex, c("RB2", "WR3"))                 # Sunday-night RB and Monday-night WR
  expect_equal(sum(d$proj[!is.na(s)]), sum(d$proj[st]))   # same starters, same expected points
  expect_equal(sort(table(s[!is.na(s)])), sort(table(rep(c("QB", "RB", "WR", "TE", "FLEX"), c(1, 2, 2, 1, 2)))))
  # every starter is eligible for his slot
  el <- lapply(league$slots, `[[`, "eligible")
  expect_true(all(mapply(function(p, sl) p %in% el[[sl]], d$position[!is.na(s)], s[!is.na(s)])))
  # the value-ordered assignment would have put the early RB3 in FLEX instead
  v1 <- val_assign_slots(d$proj, d$position, st, val_one_team(league))
  expect_true("RB3" %in% d$player_name[which(v1 == "FLEX")])
})

test_that("ties in kickoff keep the higher-valued player in the specific slot", {
  d <- lh_team()
  d$kickoff_utc[d$position == "RB"] <- lh_et("2026-10-18 13:00")
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, lh_league())
  s <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, lh_league())
  expect_equal(d$player_name[s %in% "FLEX" & d$position == "RB"], "RB3")
})

test_that("locked players keep their slots; locked bench players cannot start", {
  d <- lh_team()
  d$proj[d$player_name == "RB4"] <- 30                   # a big projection, but his Thursday game started on the bench
  d$kickoff_utc[d$player_name == "RB4"] <- lh_et("2026-10-15 20:15")
  locked <- d$kickoff_utc <= lh_et("2026-10-16 09:00")
  fixed <- ifelse(locked & d$player_name == "RB1", "FLEX", NA_character_)   # RB1 was set in FLEX on Thursday
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, lh_league(), locked | d$is_ir, fixed)
  expect_false(st[d$player_name == "RB4"])
  expect_true(st[d$player_name == "RB1"])
  s <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, lh_league(), fixed)
  expect_equal(s[d$player_name == "RB1"], "FLEX")
  expect_equal(sum(s %in% "FLEX"), 2L)
  expect_equal(sum(s %in% "RB"), 2L)
})

test_that("a Sunday-night Questionable starter has a pivot only if he sits in FLEX", {
  d <- dplyr::bind_rows(lh_team(), tibble::tibble(player_name = "WR5", position = "WR", proj = 7,
                                                   kickoff_utc = lh_et("2026-10-19 20:15"), status = "NORMAL", is_ir = FALSE))
  d$status[d$player_name == "RB2"] <- "QUESTIONABLE"
  league <- lh_league()
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, league)
  now <- lh_et("2026-10-18 09:00")
  d$starter <- st
  d$slot <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, league)
  p <- val_gametime_plan(d, league, lh_prior(), now = now)
  expect_equal(p$player, "RB2")
  expect_equal(p$p_active, 0.71)
  expect_equal(p$decision_utc, lh_et("2026-10-18 18:50"))
  expect_true(p$has_pivot)
  expect_equal(p$pivot, "WR5")                      # Monday night: still unlocked at 18:50 Sunday
  expect_equal(p$plan_ev, 0.71 * 15 + 0.29 * 7)
  expect_match(p$advice, "swap in WR5")
  # with the value-ordered slotting RB2 sits in an RB slot: only an RB could replace him -> no pivot
  d$slot <- val_assign_slots(d$proj, d$position, st, val_one_team(league))
  p1 <- val_gametime_plan(d, league, lh_prior(), now = now)
  expect_false(p1$has_pivot)
  expect_equal(p1$plan_ev, 0.71 * 15)
  expect_match(p1$advice, "no pivot")
})

test_that("an early Questionable starter can pivot to any later bench player; Doubtful and Out are handled", {
  d <- lh_team()
  d$status[d$player_name == "WR2"] <- "QUESTIONABLE"     # 13:00 kickoff, decision 11:30
  league <- lh_league()
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, league)
  d$starter <- st
  d$slot <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, league)
  p <- val_gametime_plan(d, league, lh_prior(), now = lh_et("2026-10-18 09:00"))
  # 13:00 bench players are still unlocked at 11:30. The best is RB4 (6.0 > WR4's 5.0): the
  # Monday-night WR3 moves from FLEX into WR2's slot and RB4 takes FLEX (all still unlocked).
  expect_equal(p$pivot, "RB4")
  expect_equal(p$pivot_E, 6)
  expect_equal(p$plan_ev, 0.71 * 14 + 0.29 * 6)
  # the seating rule behind pivots: a WR slot needs a WR unless an unlocked FLEX WR can slide over
  expect_true(val_seatable_in(c("WR", "RB", "RB"), c("WR", "FLEX", "FLEX"), league))
  expect_false(val_seatable_in(c("RB", "RB", "RB"), c("WR", "FLEX", "FLEX"), league))
  expect_false(val_seatable_in("QB", "FLEX", league))
  expect_false(val_seatable_in(c("RB", "RB"), "FLEX", league))
  d$status[d$player_name == "WR2"] <- "DOUBTFUL"
  p2 <- val_gametime_plan(d, league, lh_prior(), now = lh_et("2026-10-18 09:00"))
  expect_equal(p2$p_active, 0.07)
  d$status[d$player_name == "WR2"] <- "OUT"
  p3 <- val_gametime_plan(d, league, lh_prior(), now = lh_et("2026-10-18 09:00"))
  expect_match(p3$advice, "ruled out")
  expect_equal(p3$start_ev, 0)
})

test_that("two designated starters needing the same pivot are flagged", {
  d <- dplyr::bind_rows(lh_team(), tibble::tibble(player_name = "WR5", position = "WR", proj = 7,
                                                   kickoff_utc = lh_et("2026-10-19 20:15"), status = "NORMAL", is_ir = FALSE))
  d$status[d$player_name %in% c("RB2", "WR3")] <- "QUESTIONABLE"   # both in FLEX, both late
  league <- lh_league()
  st <- val_lineup_locked(ifelse(d$is_ir, 0, d$proj), d$position, league)
  d$starter <- st
  d$slot <- val_flex_slotting(d$proj, d$position, st, d$kickoff_utc, league)
  p <- val_gametime_plan(d, league, lh_prior(), now = lh_et("2026-10-18 09:00"))
  expect_equal(nrow(p), 2L)
  expect_true(all(p$pivot == "WR5"))
  expect_true(all(grepl("shared", p$advice)))
})

test_that("the designation prior comes from the committed YAML", {
  pr <- read_availability_prior(file.path(project_root, "config", "availability_prior.yml"))
  expect_equal(val_designation_prior(c("QUESTIONABLE", "DOUBTFUL", "OUT", "NORMAL", "ACTIVE", "day_to_day"), pr),
               c(0.71, 0.07, 0, 1, 1, 0.71))
  expect_equal(pr$decision_lead_minutes, 90)
})

test_that("lineup advice joins roster, projections and kickoffs and respects ESPN slots", {
  d <- lh_team()
  roster <- tibble::tibble(team_id = 1L, is_skill = TRUE, espn_id = as.character(seq_len(nrow(d))),
                           player_name = d$player_name, position = d$position, nfl_team = paste0("T", seq_len(nrow(d))),
                           lineup_slot_id = c(0L, 2L, 2L, 23L, 20L, 4L, 4L, 23L, 20L, 6L, 20L, 21L),
                           injury_status = d$status, is_ir_slot = d$is_ir)
  weekly <- tibble::tibble(espn_id = roster$espn_id, week = 6L, proj = d$proj, has_game = TRUE,
                           team = roster$nfl_team, opponent = "X")
  tg <- tibble::tibble(season = 2026L, week = 6L, team = roster$nfl_team, kickoff_utc = d$kickoff_utc)
  m <- list(current_week = 6L, season = 2026L, league = lh_league(),
            input_data = list(roster = roster, weekly = weekly))
  a <- lg_lineup_advice(m, 1L, tg, now = lh_et("2026-10-14 12:00"), prior = lh_prior())
  expect_equal(a$ev_recommended, 120)
  expect_equal(a$ev_current, 120)                         # same starters as currently set in ESPN
  expect_setequal(a$lineup$player[a$lineup$slot == "FLEX"], c("RB2", "WR3"))
  expect_equal(a$lineup$change[a$lineup$player == "RB3"], "move")   # ESPN has RB3 in FLEX
  expect_equal(a$lineup$slot[a$lineup$player == "RB5"], "IR")
  expect_equal(nrow(a$plan), 0L)
})
