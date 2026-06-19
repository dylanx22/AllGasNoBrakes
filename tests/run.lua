-- Run from repo root: lua tests/run.lua
dofile("tests/wow_stubs.lua")
local T = dofile("tests/harness.lua")
_G.T = T

-- Load addon modules (order matters: dependencies first).
-- Core.lua must load first: it defines ns.OnInit, which the glue modules
-- (Tracking/Sync/Config/UI) call at load time. Its load-time CreateFrame is stubbed.
local MODULES = {
  "AllGasNoBrakes/Core.lua",
  "AllGasNoBrakes/Debug.lua",
  "AllGasNoBrakes/Hash.lua",
  "AllGasNoBrakes/Book.lua",
  "AllGasNoBrakes/BookSettle.lua",
  "AllGasNoBrakes/BookGuard.lua",
  "AllGasNoBrakes/Database.lua",
  "AllGasNoBrakes/Phases.lua",
  "AllGasNoBrakes/Insights.lua",
  "AllGasNoBrakes/Classify.lua",
  "AllGasNoBrakes/Snark.lua",
  "AllGasNoBrakes/Report.lua",
  "AllGasNoBrakes/Ledger.lua",
  "AllGasNoBrakes/History.lua",
  "AllGasNoBrakes/Export.lua",
  "AllGasNoBrakes/Achievements.lua",
  "AllGasNoBrakes/Killcam.lua",
  "AllGasNoBrakes/Milestones.lua",
  "AllGasNoBrakes/Tracking.lua",
  "AllGasNoBrakes/PhaseTracker.lua",
  "AllGasNoBrakes/Sync.lua",
  "AllGasNoBrakes/AntiPrize.lua",
  "AllGasNoBrakes/Announce.lua",
  "AllGasNoBrakes/Config.lua",
  "AllGasNoBrakes/Help.lua",
  "AllGasNoBrakes/Welcome.lua",
  "AllGasNoBrakes/UI.lua",
  "AllGasNoBrakes/Brand.lua",
  "AllGasNoBrakes/Streak.lua",
  "AllGasNoBrakes/Banner.lua",
  "AllGasNoBrakes/Summary.lua",
  "AllGasNoBrakes/Demo.lua",
  "AllGasNoBrakes/BookSync.lua",
  "AllGasNoBrakes/Settlement.lua",
  "AllGasNoBrakes/BookUI.lua",
  "AllGasNoBrakes/Tour.lua",
}
-- Work in both layouts: the addon files live under AllGasNoBrakes/ in the dev
-- repo, but at the repo root in the published (CurseForge-packaged) repo.
local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end end
local ROOTED = not exists("AllGasNoBrakes/Core.lua")
for _, m in ipairs(MODULES) do
  local path = ROOTED and (m:gsub("^AllGasNoBrakes/", "")) or m
  if exists(path) then dofile(path) end   -- skip modules not yet created
end

-- Load and run every test file.
local TESTS = {
  "tests/test_smoke.lua",
  "tests/test_hash.lua",
  "tests/test_book.lua",
  "tests/test_book_settle.lua",
  "tests/test_book_guard.lua",
  "tests/test_database.lua",
  "tests/test_phases.lua",
  "tests/test_insights.lua",
  "tests/test_killcam.lua",
  "tests/test_history.lua",
  "tests/test_export.lua",
  "tests/test_classify.lua",
  "tests/test_snark.lua",
  "tests/test_report.lua",
  "tests/test_ledger.lua",
  "tests/test_achievements.lua",
  "tests/test_tracking.lua",
  "tests/test_sync.lua",
  "tests/test_announce.lua",
  "tests/test_milestones.lua",
  "tests/test_config.lua",
  "tests/test_config_tabs.lua",
  "tests/test_help.lua",
  "tests/test_welcome.lua",
  "tests/test_tour.lua",
  "tests/test_book_admin.lua",
  "tests/test_brand.lua",
  "tests/test_streak.lua",
  "tests/test_banner.lua",
  "tests/test_summary.lua",
  "tests/test_demo.lua",
  "tests/test_debug.lua",
  "tests/test_antiprize.lua",
}
for _, t in ipairs(TESTS) do
  local f = io.open(t, "r")
  if f then f:close(); dofile(t) end
end

os.exit(T.summary() and 0 or 1)
