-- tests/gen_move_adapter_test.lua
-- Standalone: lua tests/gen_move_adapter_test.lua
-- Verifies lib/GenMoveAdapter.lua per-generation movement template contracts.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local GenMoveAdapter = dofile(HERE .. "../lib/GenMoveAdapter.lua")

local failures = 0
local function check(cond, msg)
  if cond then
    print("PASS: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

-- forGen returns tables with wander/stay/spin/tune functions ---------------
for _, g in ipairs({ 1, 2, 3, 4 }) do
  local a = GenMoveAdapter.forGen(g)
  check(type(a) == "table", "forGen(" .. g .. ") returns a table")
  check(type(a.wander) == "function", "forGen(" .. g .. ") has wander fn")
  check(type(a.stay) == "function", "forGen(" .. g .. ") has stay fn")
  check(type(a.spin) == "function", "forGen(" .. g .. ") has spin fn")
  check(type(a.tune) == "function", "forGen(" .. g .. ") has tune fn")
end

-- Gen 1 / Gen 2: string protocol -------------------------------------------
for _, g in ipairs({ 1, 2 }) do
  local a = GenMoveAdapter.forGen(g)
  local w = a.wander("down", 3)
  check(w.movement == "WALK", "gen " .. g .. " wander movement=WALK (string)")
  check(type(w.movement) == "string", "gen " .. g .. " wander movement is a string")
  local s = a.stay("left")
  check(s.movement == "STAY", "gen " .. g .. " stay movement=STAY")
  check(s.range == "LEFT", "gen " .. g .. " stay range=LEFT")
  local sp = a.spin()
  check(sp.movement == "SPIN", "gen " .. g .. " spin movement=SPIN")
end

-- Gen 3: movementType number when gameData has gen3MovementTypes ------------
local a3 = GenMoveAdapter.forGen(3)
local fakeData = {
  constants = {
    gen3MovementTypes = {
      [3] = { wanders = true },
      [7] = { wanders = true, hides = true },
      [9] = { wanders = true, axis = "x" },
    },
  },
}
local w3 = a3.wander("up", 2, fakeData)
check(type(w3.movementType) == "number", "gen 3 wander returns numeric movementType with gameData")
check(w3.movementType == 3, "gen 3 wander picks the plain wanders type (id 3)")

local w3fallback = a3.wander("up", 2, nil)
check(w3fallback.movement == "WALK", "gen 3 wander falls back to movement=WALK without gameData")
local w3empty = a3.wander("up", 2, { constants = {} })
check(w3empty.movement == "WALK", "gen 3 wander falls back when gen3MovementTypes missing")

local s3 = a3.stay("right")
check(s3.movement == "STAY" and s3.range == "RIGHT", "gen 3 stay = STAY/RIGHT")

-- Gen 4: direction 0-3 + movementRangeX/Z numbers ---------------------------
local a4 = GenMoveAdapter.forGen(4)
local w4 = a4.wander("down", 3)
check(type(w4.direction) == "number" and w4.direction >= 0 and w4.direction <= 3,
  "gen 4 wander direction is 0-3")
check(type(w4.movementRangeX) == "number" and w4.movementRangeX == 3,
  "gen 4 wander movementRangeX == rangeCells")
check(type(w4.movementRangeZ) == "number" and w4.movementRangeZ == 3,
  "gen 4 wander movementRangeZ == rangeCells")
check(w4.movement == "WALK", "gen 4 wander also carries movement=WALK")

-- Gen 4 stay() facings map up->0, down->1, left->2, right->3 ----------------
local expect = { up = 0, down = 1, left = 2, right = 3 }
for facing, num in pairs(expect) do
  local s4 = a4.stay(facing)
  check(s4.direction == num, "gen 4 stay(" .. facing .. ") direction=" .. num)
end

-- gen4DirNumber helper agrees with stay() -----------------------------------
for facing, num in pairs(expect) do
  check(GenMoveAdapter.gen4DirNumber(facing) == num,
    "gen4DirNumber(" .. facing .. ")=" .. num)
end

-- facingDelta / normalizeFacing ---------------------------------------------
local dx, dy = GenMoveAdapter.facingDelta("up")
check(dx == 0 and dy == -1, "facingDelta(up) = 0,-1")
dx, dy = GenMoveAdapter.facingDelta("down")
check(dx == 0 and dy == 1, "facingDelta(down) = 0,1")
dx, dy = GenMoveAdapter.facingDelta("left")
check(dx == -1 and dy == 0, "facingDelta(left) = -1,0")
dx, dy = GenMoveAdapter.facingDelta("right")
check(dx == 1 and dy == 0, "facingDelta(right) = 1,0")
dx, dy = GenMoveAdapter.facingDelta("bogus")
check(dx == 0 and dy == 1, "facingDelta(bogus) defaults to down")
check(GenMoveAdapter.normalizeFacing("UP") == "up", "normalizeFacing(UP)=up")
check(GenMoveAdapter.normalizeFacing(nil) == "down", "normalizeFacing(nil)=down")
check(GenMoveAdapter.normalizeFacing("north") == "down", "normalizeFacing(north)=down")

-- tune() is fail-open for every generation ----------------------------------
for _, g in ipairs({ 1, 2, 3, 4 }) do
  local ok = pcall(GenMoveAdapter.forGen(g).tune, nil, nil)
  check(ok, "forGen(" .. g .. ").tune(nil,nil) does not error")
end
local npc4 = { cellX = 5, cellY = 6 }
GenMoveAdapter.forGen(4).tune(npc4, { wanderBox = 2 })
check(npc4.roamRangeX == 2 and npc4.roamRangeY == 2, "gen 4 tune seeds roam box")

if failures > 0 then
  print(failures .. " FAILURES")
  os.exit(1)
end
print("ALL GEN_MOVE_ADAPTER TESTS PASSED")
