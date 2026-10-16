-- tests/ambient_core_test.lua
-- Standalone: lua tests/ambient_core_test.lua
-- Verifies lib/AmbientCore.lua (Gen 3/4 ambient NPC engine) against a stub
-- mod + stub generation adapter. Skips with exit 0 when AmbientCore.lua is
-- absent (it may not have been written yet by the concurrent authoring agent).
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local corePath = HERE .. "../lib/AmbientCore.lua"
local probe = io.open(corePath, "r")
if not probe then
  print("SKIP: lib/AmbientCore.lua not present")
  os.exit(0)
end
probe:close()

local failures = 0
local function check(cond, msg)
  if cond then
    print("PASS: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local stubMod = {
  world = {
    spawnNpc = function() return "x_obj_1" end,
    removeNpc = function() return true end,
    overworld = function() return nil end,
  },
  events = { on = function() end },
  save = { get = function() return nil end, set = function() end },
  options = { define = function() end, get = function() return nil end },
  log = { info = function() end, warn = function() end, error = function() end },
  engineRequire = function() error("no engine") end,
  content = { sprites = { register = function() end } },
}
local adapterStub = {
  id = "klT", gen = 3, label = "Test",
  humanSprites = { "SPRITE_X" },
  pokemonSpecies = { "PIKACHU" },
  giftItems = { "POTION" },
  giftTMs = {},
  flySpecies = {},
  psychicSpecies = {},
  isOutdoor = function() return true end,
}

local chunk = assert(loadfile(corePath))
local installer = chunk
local handle
local ok, err = pcall(function()
  -- Chunk may return the installer directly, or the core table itself.
  local v = installer()
  if type(v) == "function" then
    handle = v(stubMod, adapterStub)
  else
    handle = v
  end
end)
check(ok, "AmbientCore chunk loads and installs with stub mod (" .. tostring(err) .. ")")
if not ok then os.exit(1) end

-- The "core" surface: the installer returns a handle table whose fields (or
-- an embedded .core) carry the logic helpers.
local core = handle
if type(handle) == "table" and type(handle.core) == "table" then
  core = handle.core
end
check(type(core) == "table", "core handle is a table")
check(type(handle.shutdown) == "function", "handle has shutdown function")

check(type(core.talkCount) == "function", "core.talkCount exists")
local r1, isFifth1 = core.talkCount(nil)
check(type(r1) == "table" and r1.count == 1, "talkCount(nil) -> {count=1}")
check(isFifth1 == false, "talkCount(nil) -> isFifth=false")

-- 5 sequential calls: 5th is the fifth interaction, count resets to 0 ------
-- (talkCount is pure/stateless: chain the returned state through the calls)
local last, fifth = nil, false
for i = 1, 5 do
  last, fifth = core.talkCount(last)
end
check(fifth == true, "5th sequential talkCount -> isFifth true")
check(last.count == 0, "count resets to 0 after 5th interaction")
-- 6th talk starts a fresh cycle
local r6, fifth6 = core.talkCount(last)
check(fifth6 == false and r6.count == 1, "6th talk starts new cycle at count 1")

-- cooldownOk ----------------------------------------------------------------
check(type(core.cooldownOk) == "function", "core.cooldownOk exists")
local now = os.time()
check(core.cooldownOk({ lastEvent = "item", lastEventAt = now }, now) == false,
  "cooldownOk: event just happened -> false")
check(core.cooldownOk({ lastEvent = "item", lastEventAt = now - 4000 }, now) == true,
  "cooldownOk: event 4000s ago -> true")

-- enemyLevelFor ---------------------------------------------------------------
check(type(core.enemyLevelFor) == "function", "core.enemyLevelFor exists")
check(core.enemyLevelFor(50) == 40, "enemyLevelFor(50) == 40 (cap)")
check(core.enemyLevelFor(30) == 20, "enemyLevelFor(30) == 20 (player-10)")
check(core.enemyLevelFor(5) == 2, "enemyLevelFor(5) == 2 (floor)")

if failures > 0 then
  print(failures .. " FAILURES")
  os.exit(1)
end
print("ALL AMBIENT_CORE TESTS PASSED")
