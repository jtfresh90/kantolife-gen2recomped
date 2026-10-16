-- tests/g2r_compat_test.lua
-- Standalone: lua tests/g2r_compat_test.lua
-- Verifies lib/G2RCompat.lua event rerouting and mod-field passthrough.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local newCompat = dofile(HERE .. "../lib/G2RCompat.lua")

local failures = 0
local function check(cond, msg)
  if cond then
    print("PASS: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

-- Stub "real" mod ------------------------------------------------------------
local realOn = {}   -- { name=..., cb=..., prio=... }
local realOnce = {}
local modStub = {
  id = "kantolife_gen2recomped",
  path = "/fake/path",
  version = "1.0.0",
  events = {
    on = function(self, name, cb, prio)
      realOn[#realOn + 1] = { name = name, cb = cb, prio = prio }
      return #realOn
    end,
    once = function(self, name, cb, prio)
      realOnce[#realOnce + 1] = { name = name, cb = cb, prio = prio }
      return #realOnce
    end,
    emit = function(self, name, payload)
      return "emitted:" .. tostring(name)
    end,
  },
  hooks = {
    wrap = function(self, name, cb, prio)
      return "wrapped:" .. tostring(name)
    end,
  },
  save = { get = function(self, k) return "saveval:" .. k end },
  log = { info = function() end },
}
function modStub:read(path)      -- colon-call method on the real mod
  return "FILE:" .. path
end

local facade = newCompat(modStub)
check(type(facade) == "table", "G2RCompat returns a facade table")

-- events:on("update") reroutes to "world.tick", callback receives dt --------
local gotDt = nil
facade.events:on("update", function(dt) gotDt = dt end)
check(#realOn == 1, "one real subscription registered")
check(realOn[1].name == "world.tick", 'on("update") reroutes to "world.tick"')
realOn[1].cb({ dt = 0.033 })
check(gotDt == 0.033, 'rerouted "update" callback receives dt (0.033)')
gotDt = nil
realOn[1].cb({})
check(gotDt == 0.016, 'rerouted "update" callback defaults dt to 0.016 when absent')

-- events:on("map.ready") reroutes to "map.entered" ---------------------------
local mapReadyHit = false
facade.events:on("map.ready", function() mapReadyHit = true end)
check(realOn[#realOn].name == "map.entered", 'on("map.ready") reroutes to "map.entered"')
realOn[#realOn].cb()
check(mapReadyHit, 'rerouted "map.ready" callback fires')

-- other events pass through with the same name --------------------------------
facade.events:on("dialogue.start", function() end, 5)
check(realOn[#realOn].name == "dialogue.start", 'other events pass through unchanged')
check(realOn[#realOn].prio == 5, "priority argument is preserved")

-- :once rerouting -------------------------------------------------------------
facade.events:once("update", function(dt) end)
check(realOnce[#realOnce].name == "world.tick", 'once("update") reroutes to "world.tick"')
facade.events:once("save.loaded", function() end)
check(realOnce[#realOnce].name == "save.loaded", 'once("save.loaded") passes through')

-- :emit passes through ---------------------------------------------------------
check(facade.events:emit("custom.evt", {}) == "emitted:custom.evt", "events:emit passes through")

-- hooks:wrap passes through ----------------------------------------------------
local wrapResult = facade.hooks:wrap("npc.spawn", function() end)
check(wrapResult == "wrapped:npc.spawn", "hooks:wrap passes through name and returns handle")

-- mod:read via colon call works (facade __index -> real) -----------------------
check(facade:read("lib/Foo.lua") == "FILE:lib/Foo.lua", "facade:read resolves via colon call")
check(facade.id == "kantolife_gen2recomped", "facade.id passthrough")
check(facade.path == "/fake/path", "facade.path passthrough")
check(facade.version == "1.0.0", "facade.version passthrough")
check(type(facade.save) == "table" and facade.save:get("k") == "saveval:k", "facade.save passthrough")
check(type(facade.log) == "table", "facade.log passthrough")

-- __newindex writes through to the real mod ------------------------------------
facade.customField = 42
check(modStub.customField == 42, "__newindex writes through to real mod")

if failures > 0 then
  print(failures .. " FAILURES")
  os.exit(1)
end
print("ALL G2R_COMPAT TESTS PASSED")
