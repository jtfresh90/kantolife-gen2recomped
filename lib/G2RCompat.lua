-- G2RCompat.lua — Gen2Recomped compatibility facade for the Gen 1 / Gen 2
-- Kanto Life modules, which were written against the gen1recomp mod API.
--
-- Gen2Recomped's mod API is a close relative of gen1recomp's, but a few
-- event/hook names the legacy modules use do not exist here:
--
--   events "update"     -> "world.tick"  (payload {dt, mapId, overworld, scripted})
--   events "map.ready"   -> "map.entered" (legacy handlers also subscribe to
--                          map.entered/map.reloaded and are idempotent, so
--                          routing through map.entered is safe)
--   hook   "world.talk" -> does not exist in Gen2Recomped; the Gen 1/2
--                          modules do not use it (only the old Gen 3 module
--                          did), so no shim is provided.
--   hook   "input.key" / "input.gamepad" -> do not exist in Gen2Recomped;
--                          only the old Gen 3 module used them.
--
-- Everything else passes through untouched. The facade preserves colon-call
-- semantics: `facade:read(path)` resolves through to the real mod's fields
-- via __index, so self-references (self.path, self.id, ...) keep working.
--
-- Usage (from main.lua):
--   local compat = loadLocal("lib/G2RCompat.lua")
--   local installer = loadLocal("lib/KantoMain.lua")
--   installer(compat(mod))
return function(mod)
  local real = mod

  local function tickDt(ev)
    if type(ev) == "table" and tonumber(ev.dt) then return ev.dt end
    return 0.016
  end

  local eventsFacade = {}
  function eventsFacade:on(name, cb, prio)
    if name == "update" then
      return real.events:on("world.tick", function(ev)
        local ok, err = pcall(cb, tickDt(ev))
        if not ok and real.log and type(real.log.warn) == "function" then
          pcall(real.log.warn, real.log, "Kanto Life: update shim error: %s", tostring(err))
        end
      end, prio)
    end
    if name == "map.ready" then
      return real.events:on("map.entered", cb, prio)
    end
    return real.events:on(name, cb, prio)
  end
  function eventsFacade:once(name, cb, prio)
    if name == "update" then
      return real.events:once("world.tick", function(ev)
        pcall(cb, tickDt(ev))
      end, prio)
    end
    if name == "map.ready" then
      return real.events:once("map.entered", cb, prio)
    end
    return real.events:once(name, cb, prio)
  end
  function eventsFacade:emit(name, payload)
    return real.events:emit(name, payload)
  end

  local hooksFacade = {}
  function hooksFacade:wrap(name, cb, prio)
    return real.hooks:wrap(name, cb, prio)
  end

  local facade = {}
  setmetatable(facade, {
    __index = function(_, k)
      if k == "events" then return eventsFacade end
      if k == "hooks" then return hooksFacade end
      return real[k]
    end,
    __newindex = function(_, k, v)
      real[k] = v
    end,
  })
  return facade
end
