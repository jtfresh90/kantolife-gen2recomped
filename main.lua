-- Kanto Life for Gen2Recomped — unified entry.
-- Generation dispatch only: each generation keeps its own implementation.
--
--   Gen 1 (Red/Blue/Yellow)          -> lib/KantoMain.lua   (legacy module,
--   Gen 2 (Gold/Silver/Crystal)      -> lib/JohtoMain.lua    run through the
--                                                           G2RCompat facade)
--   Gen 3 (FireRed/LeafGreen/Emerald)-> lib/FireRedMain.lua (AmbientCore)
--   Gen 4 (Platinum, experimental)   -> lib/SinnohMain.lua  (AmbientCore)
return function(mod)
  local function loadLocal(rel)
    local source, err = mod:read(rel)
    if type(source) ~= "string" then
      error("Kanto Life: missing bundled module " .. rel .. ": " .. tostring(err), 0)
    end
    local compile = loadstring or load
    local chunk, compileErr = compile(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      error("Kanto Life: cannot compile " .. rel .. ": " .. tostring(compileErr), 0)
    end
    local ok, value = pcall(chunk)
    if not ok then error("Kanto Life: cannot load " .. rel .. ": " .. tostring(value), 0) end
    if type(value) ~= "function" then error("Kanto Life: " .. rel .. " must return an installer function", 0) end
    return value
  end

  -- Install hygiene: clear the mod's persisted data (mod.save bucket) on
  -- fresh install, update, or reinstall-after-removal, before any generation
  -- code reads it. Fail-open: hygiene must never break mod load.
  pcall(function()
    local hygiene = loadLocal("lib/InstallHygiene.lua")
    hygiene(mod)
    if mod.events and type(mod.events.on) == "function" then
      mod.events:on("save.loaded", function() pcall(hygiene, mod) end)
      mod.events:on("save.created", function() pcall(hygiene, mod) end)
    end
  end)

  -- Generation detection. Gen2Recomped exposes mod.generation (1..5) and
  -- mod.host.generation; fall back to the engine's GameVersion module.
  local gen = tonumber(mod.generation)
  if gen == nil and type(mod.host) == "table" then
    gen = tonumber(mod.host.generation)
  end
  if gen == nil and mod.engineRequire then
    local okGV, GV = pcall(mod.engineRequire, "src.core.GameVersion")
    if okGV and GV then
      if type(GV.generation) == "function" then
        local okGen, value = pcall(GV.generation)
        if okGen and value ~= nil then gen = tonumber(value) end
      elseif type(GV.isGen4) == "function" then
        local ok4, is4 = pcall(GV.isGen4)
        if ok4 and is4 then gen = 4 end
      end
    end
  end
  if gen == nil and mod.game and mod.game.generation ~= nil then
    gen = tonumber(mod.game.generation)
  end
  if gen == nil then error("Kanto Life: could not determine the active game generation", 0) end

  local rel, useCompat
  if gen == 1 then
    rel, useCompat = "lib/KantoMain.lua", true
  elseif gen == 2 then
    rel, useCompat = "lib/JohtoMain.lua", true
  elseif gen == 3 then
    rel, useCompat = "lib/FireRedMain.lua", false
  elseif gen == 4 then
    rel, useCompat = "lib/SinnohMain.lua", false
  else
    error("Kanto Life: unsupported game generation " .. tostring(gen), 0)
  end

  -- Gens 1/2 reuse the proven gen1recomp-era modules through the G2RCompat
  -- facade, which remaps the few event names Gen2Recomped does not have
  -- ("update" -> "world.tick", "map.ready" -> "map.entered").
  -- Gens 3/4 run the new AmbientCore engine directly on the Gen2Recomped
  -- world API with per-generation movement adapters.
  local target = mod
  if useCompat then
    local compat = loadLocal("lib/G2RCompat.lua")
    target = compat(mod)
  end

  -- Fail-open install: a generation installer error must not leave the game
  -- with a half-wrapped Overworld / missing NPCs. Log and continue so the
  -- base game stays playable.
  local installer = loadLocal(rel)
  local okRun, err = pcall(installer, target)
  if not okRun then
    pcall(function()
      if mod.log and type(mod.log.error) == "function" then
        mod.log:error("Kanto Life installer failed for gen %s (%s): %s",
          tostring(gen), tostring(rel), tostring(err))
      end
    end)
  else
    pcall(function()
      if mod.log and type(mod.log.info) == "function" then
        mod.log:info("Kanto Life installed for generation %s (%s)", tostring(gen), tostring(rel))
      end
    end)
  end
end
