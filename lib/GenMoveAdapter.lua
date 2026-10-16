-- GenMoveAdapter.lua — per-generation movement template fields for spawned NPCs.
--
-- Gen2Recomped's NPC constructor (src/world/NPC.lua) derives wander/facing
-- behavior from the spawn template:
--
--   Gen 1/2: `movement` / `range` STRINGS.
--             movement="WALK" -> self.wanders = true;
--             range in {"ANY_DIR","UP_DOWN","LEFT_RIGHT","DOWN",...} -> roamDirs.
--             movement="STAY" -> stands still, keeps facing.
--   Gen 3:   `movementType` NUMBER, resolved through
--             data.constants.gen3MovementTypes (ROM-extracted). When the type
--             is absent or past the end of the table, the Gen 2 string reads
--             still apply (NPC.lua: the object "stands still facing south"
--             only when NEITHER spelling is given).
--   Gen 4:   `direction` (0=up,1=down,2=left,3=right, the FaceDirection enum)
--             sets the spawn facing; the wander box is `movementRangeX` /
--             `movementRangeZ` on the template (RomExtractorGen4 normalizes
--             Z->Y on import). The shared NPC.update wander branch still keys
--             off movement="WALK", so Gen 4 wanderers carry BOTH spellings.
--
-- For NPCs the mod drives itself (routines, sleep, travel), spawn with the
-- STAY-equivalent, set frozen=true, and drive facing/targetX/targetY/moving/
-- progress manually -- but NEVER set movement state without a valid walkable
-- target (check Collision.canMove first).
--
-- Usage:
--   local GenMoveAdapter = loadLocal("lib/GenMoveAdapter.lua")
--   local move = GenMoveAdapter.forGen(4)
--   local def = move.wander("down", 3)   -- objDef movement fields
--   local def2 = move.stay("left")
--
--   -- Gen 3 native wander type, resolved at runtime from the ROM-extracted
--   -- table (fail-open: falls back to the string spelling):
--   local mt = GenMoveAdapter.gen3WanderType(gameData)
local GenMoveAdapter = {}

local FACINGS = { up = true, down = true, left = true, right = true }
local GEN4_DIR = { up = 0, down = 1, left = 2, right = 3 }

local function facingOf(facing)
  facing = tostring(facing or "down"):lower()
  if FACINGS[facing] then return facing end
  return "down"
end

-- Gen 1 / Gen 2 adapter: string movement/range.
local function gen12()
  return {
    gen = 1,
    wander = function(facing, rangeCells)
      return { movement = "WALK", range = "ANY_DIR" }
    end,
    stay = function(facing)
      return { movement = "STAY", range = facingOf(facing):upper() }
    end,
    spin = function()
      return { movement = "SPIN", range = "SPIN_SLOW" }
    end,
    -- post-spawn tuning hook (engine fields); Gen 1/2 needs none.
    tune = function(npc, opts) end,
  }
end

-- Gen 3 adapter: prefer a native wander movementType resolved at runtime
-- from data.constants.gen3MovementTypes; fail open to the string spelling
-- (which NPC.new honors when no movementType is given).
function GenMoveAdapter.gen3WanderType(gameData)
  local constants = gameData and gameData.constants
  local types = constants and constants.gen3MovementTypes
  if type(types) ~= "table" then return nil end
  for id, t in pairs(types) do
    if type(t) == "table" and t.wanders == true and not t.hides
       and t.axis == nil and type(id) == "number" then
      return id
    end
  end
  return nil
end

local function gen3()
  return {
    gen = 3,
    wander = function(facing, rangeCells, gameData)
      local mt = GenMoveAdapter.gen3WanderType(gameData)
      if mt ~= nil then
        return { movementType = mt }
      end
      return { movement = "WALK", range = "ANY_DIR" }
    end,
    stay = function(facing)
      return { movement = "STAY", range = facingOf(facing):upper() }
    end,
    spin = function()
      return { movement = "SPIN", range = "SPIN_SLOW" }
    end,
    tune = function(npc, opts) end,
  }
end

-- Gen 4 adapter: native direction + movementRangeX/movementRangeZ box, plus
-- the shared movement="WALK" spelling so NPC.update's wander branch walks
-- the NPC (the constructor only enforces the roam box for Gen 3 templates,
-- so tune() also seeds the engine's roam fields post-spawn).
local function gen4()
  return {
    gen = 4,
    wander = function(facing, rangeCells)
      local f = facingOf(facing)
      local r = tonumber(rangeCells) or 3
      if r < 0 then r = 0 end
      return {
        movement = "WALK",
        range = "ANY_DIR",
        direction = GEN4_DIR[f],
        movementRangeX = r,
        movementRangeZ = r,
        movementRangeY = r, -- extractor normalizes Z->Y; carry both
      }
    end,
    stay = function(facing)
      local f = facingOf(facing)
      return {
        movement = "STAY",
        range = f:upper(),
        direction = GEN4_DIR[f],
        movementRangeX = 0,
        movementRangeZ = 0,
        movementRangeY = 0,
      }
    end,
    spin = function()
      return { movement = "SPIN", range = "SPIN_SLOW", direction = 1 }
    end,
    tune = function(npc, opts)
      -- Enforce the Gen 4 wander box through the engine's own roam fields
      -- (NPC.update checks roamOriginX/roamRangeX per axis; nil = unbounded).
      if npc and opts and opts.wanderBox then
        npc.roamOriginX, npc.roamOriginY = npc.cellX, npc.cellY
        local r = tonumber(opts.wanderBox) or 0
        npc.roamRangeX = r > 0 and r or nil
        npc.roamRangeY = r > 0 and r or nil
      end
    end,
  }
end

-- forGen(gen): 1 and 2 share the string protocol; 3 and 4 have adapters.
function GenMoveAdapter.forGen(gen)
  gen = tonumber(gen)
  if gen == 3 then return gen3() end
  if gen == 4 then return gen4() end
  local a = gen12()
  a.gen = (gen == 2) and 2 or 1
  return a
end

-- Facing helpers shared by custom movement drivers.
function GenMoveAdapter.facingDelta(facing)
  if facing == "up" then return 0, -1 end
  if facing == "down" then return 0, 1 end
  if facing == "left" then return -1, 0 end
  if facing == "right" then return 1, 0 end
  return 0, 1
end

function GenMoveAdapter.normalizeFacing(facing)
  return facingOf(facing)
end

function GenMoveAdapter.gen4DirNumber(facing)
  return GEN4_DIR[facingOf(facing)]
end

return GenMoveAdapter
