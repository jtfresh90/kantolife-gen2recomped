-- tests/npc_lifecycle_test.lua
-- Standalone: lua tests/npc_lifecycle_test.lua
-- Verifies the AmbientCore spawn/remove lifecycle against a stub mod:
--   * spawnNpc payload shape (x/y numbers, sprite string, per-gen movement
--     fields, kantoLifeAmbient flag)
--   * removeNpc called with every spawned id on map.exited
--   * talk-state save round-trip through mod.save
-- Skips with exit 0 when lib/AmbientCore.lua is absent.
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
  if cond then print("PASS: " .. msg)
  else failures = failures + 1; print("FAIL: " .. msg) end
end

-- ---- stub mod ------------------------------------------------------------
local handlers = {}
local spawned = {}   -- { {mapId, def, npcId} }
local removed = {}
local saveBucket = {}
local npcSeq = 0

local fakeMap = {
  id = "TEST_MAP",
  def = {},
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
}
local fakeOw = {
  map = fakeMap,
  npcs = {},
  player = { cellX = 10, cellY = 10, facing = "down" },
}

local stubMod = {
  generation = 3,
  gameVersion = "firered",
  path = HERE .. "..",
  read = function(self, rel)
    local f = io.open(HERE .. "../" .. rel, "r")
    if not f then return nil, "not found" end
    local s = f:read("*a"); f:close()
    return s
  end,
  world = {
    spawnNpc = function(_, mapId, def)
      npcSeq = npcSeq + 1
      local id = mapId .. "_obj_" .. npcSeq
      spawned[#spawned + 1] = { mapId = mapId, def = def, npcId = id }
      return id
    end,
    removeNpc = function(_, npcId)
      removed[#removed + 1] = npcId
      return true
    end,
    overworld = function() return fakeOw end,
  },
  events = {
    on = function(_, name, cb) handlers[name] = cb end,
  },
  save = {
    get = function(_, k, d) local v = saveBucket[k]; return v == nil and d or v end,
    set = function(_, k, v) saveBucket[k] = v end,
  },
  options = {
    define = function() end,
    get = function(_, k)
      if k == "ambient_humans" then return 2 end
      if k == "ambient_pokemon" then return 1 end
      return nil
    end,
  },
  log = { info = function() end, warn = function() end, error = function() end },
  engineRequire = function(name)
    if name == "src.world.Collision" then
      return {
        canMove = function() return true end,
        target = function(cx, cy, dir)
          if dir == "up" then return cx, cy - 1 end
          if dir == "down" then return cx, cy + 1 end
          if dir == "left" then return cx - 1, cy end
          if dir == "right" then return cx + 1, cy end
          return cx, cy
        end,
      }
    end
    error("no engine in test: " .. tostring(name))
  end,
  content = { sprites = { register = function() end } },
  game = {
    data = {
      sprites = { SPRITE_H3_001 = true, SPRITE_H3_002 = true,
                  KL_klT_PIKACHU = true },
      pokemon = { PIKACHU = { name = "PIKACHU" } },
      items = { POTION = { name = "POTION" } },
    },
  },
}

local adapterStub = {
  id = "klT", gen = 3, label = "Test",
  humanSprites = { { "SPRITE_H3_001", "m" }, { "SPRITE_H3_002", "f" } },
  pokemonSpecies = { "PIKACHU" },
  giftItems = { "POTION" },
  giftTMs = {},
  flySpecies = {},
  psychicSpecies = {},
  isOutdoor = function() return true end,
}

local chunk = assert(loadfile(corePath))
local v = chunk()
local core = (type(v) == "table") and v or nil
check(core ~= nil and type(core.install) == "function", "AmbientCore exposes install")

local handle
local ok, err = pcall(function() handle = core.install(stubMod, adapterStub) end)
check(ok, "install succeeds with stub mod (" .. tostring(err) .. ")")
if not ok then os.exit(1) end
check(type(handlers["map.entered"]) == "function", "map.entered wired")
check(type(handlers["map.exited"]) == "function", "map.exited wired")
check(type(handlers["world.tick"]) == "function", "world.tick wired")
check(type(handlers["world.interacted"]) == "function", "world.interacted wired")

-- ---- map.entered -> spawns ----------------------------------------------
handlers["map.entered"]({ mapId = "TEST_MAP" })
check(#spawned == 3, "2 humans + 1 pokemon spawned (got " .. #spawned .. ")")

local seenHuman, seenPoke = 0, 0
for _, s in ipairs(spawned) do
  local def = s.def
  check(s.mapId == "TEST_MAP", "spawn mapId correct for " .. s.npcId)
  check(type(def.x) == "number" and type(def.y) == "number", "def has numeric x/y")
  check(type(def.sprite) == "string", "def has string sprite")
  check(def.kantoLifeAmbient == true, "def flagged kantoLifeAmbient")
  check(type(def.kantoLifeSlot) == "string", "def has slot uid")
  local moveOk = (type(def.movementType) == "number")
    or (def.movement == "WALK" or def.movement == "STAY")
  check(moveOk, "def has gen-appropriate movement fields")
  if def.kantoLifeIsPoke then seenPoke = seenPoke + 1
  else seenHuman = seenHuman + 1 end
end
check(seenHuman == 2 and seenPoke == 1, "human/pokemon split correct")

-- ---- save round-trip (talk-state persistence contract) -------------------
local key = "klT_talk:TEST_MAP#1"
local st = stubMod.save:get(key, { count = 0 })
local newSt, fifth = core.talkCount(st)
stubMod.save:set(key, newSt)
local back = stubMod.save:get(key)
check(type(back) == "table" and back.count == 1 and fifth == false,
  "talk state round-trips through mod.save (count=1)")
-- drive to the 5th through the persisted state
for _ = 1, 4 do
  local cur = stubMod.save:get(key)
  local ns, f = core.talkCount(cur)
  stubMod.save:set(key, ns)
  fifth = f
end
local final = stubMod.save:get(key)
check(fifth == true and final.count == 0, "5th interaction via persisted state resets count")

-- ---- map.exited -> despawn ----------------------------------------------
local ids = {}
for _, s in ipairs(spawned) do ids[s.npcId] = true end
handlers["map.exited"]({ mapId = "TEST_MAP" })
check(#removed == 3, "all 3 NPCs removed on map exit (got " .. #removed .. ")")
local allRemoved = true
for _, id in ipairs(removed) do if not ids[id] then allRemoved = false end end
check(allRemoved, "removed ids match spawned ids")

if type(handle) == "table" and type(handle.shutdown) == "function" then
  local okS = pcall(handle.shutdown)
  check(okS, "shutdown runs clean")
end

if failures > 0 then print(failures .. " FAILURES"); os.exit(1) end
print("ALL NPC_LIFECYCLE TESTS PASSED")
