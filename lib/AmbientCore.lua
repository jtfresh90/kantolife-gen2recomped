-- lib/AmbientCore.lua — Shared ambient-NPC engine for the Kanto Life
-- Gen2Recomped port (generations 3 and 4).
--
-- The chunk returns the `core` module table, which is a callable
-- installer (via __call) so installers may use either form:
--   AmbientCore(mod, A)          -- or
--   AmbientCore.install(mod, A)
-- Both return a handle { shutdown, talkCount, cooldownOk, enemyLevelFor }.
-- Pure, engine-free helpers are fields on the module itself so tests can
-- call them with no game running:
--   core.talkCount(st)       -> newSt, isFifth
--   core.cooldownOk(st, now) -> bool
--   core.enemyLevelFor(pmax)-> level
--
-- A (adapter table, built by the per-generation installer):
--   { id="kl3"|"kl4", gen=3|4, label="FireRed"|"Sinnoh",
--     humanSprites=array of {spriteId, gender} (installer provides),
--     pokemonSpecies=array of species id strings,
--     giftItems=array of item id strings, giftTMs=array of TM id strings,
--     flySpecies=array, psychicSpecies=array,
--     isOutdoor=function(mapDef) -> bool end,
--     refreshHumans=function() end  -- optional: refill humanSprites
--   }
--
-- Design notes:
-- * Everything engine-touching is wrapped in pcall and fails open: a
--   failed subsystem logs once and disables itself; the game is never
--   broken by this mod.
-- * Custom movement NEVER writes npc.targetX/targetY/moving/progress
--   without a walkable target: all stepping goes through tryStep(),
--   which gates on Collision.canMove first.
-- * NPCs never sleep within 5 cells of a door cell.

-- ============================================================================
-- Pure helpers (no engine calls; safe for unit tests)
-- ============================================================================

-- Talk counting. st = {count=0..4, ...} | nil.
-- Returns newSt, isFifth. On the 5th talk the count resets to 0 and
-- isFifth is true; all other fields are preserved.
local function talkCount(st)
  st = (type(st) == "table") and st or {}
  local count = (tonumber(st.count) or 0) + 1
  local isFifth = count >= 5
  local newSt = {
    count = isFifth and 0 or count,
    lastEvent = st.lastEvent,
    lastEventAt = st.lastEventAt,
    lastDetail = st.lastDetail,
  }
  return newSt, isFifth
end

-- Trade/item cooldown: 3600s from lastEventAt when lastEvent is
-- "item" or "trade". True = no cooldown active (gift/trade allowed).
local function cooldownOk(st, nowSecs)
  if type(st) ~= "table" then return true end
  local ev = st.lastEvent
  if ev ~= "item" and ev ~= "trade" then return true end
  local at = tonumber(st.lastEventAt)
  if not at then return true end
  nowSecs = tonumber(nowSecs) or os.time()
  return (nowSecs - at) >= 3600
end

-- Enemy level rules for 5th-interaction battles:
-- never above 40; below playerMax 40 -> max(2, playerMax-10).
local function enemyLevelFor(playerMax)
  playerMax = tonumber(playerMax) or 1
  local lvl = playerMax - 10
  if lvl < 2 then lvl = 2 end
  if lvl > 40 then lvl = 40 end
  return lvl
end

-- ============================================================================
-- Installer
-- ============================================================================

local function install(mod, A)
  local function logInfo(fmt, ...)
    local args = { ... }
    pcall(function() mod.log:info(fmt, unpack(args)) end)
  end
  local function logWarn(fmt, ...)
    local args = { ... }
    pcall(function() mod.log:warn(fmt, unpack(args)) end)
  end

  local function degraded(reason)
    pcall(function()
      mod.log:warn("AmbientCore[%s]: %s; running degraded",
        tostring(A and A.id), tostring(reason))
    end)
    return {
      shutdown = function() end,
      talkCount = talkCount,
      cooldownOk = cooldownOk,
      enemyLevelFor = enemyLevelFor,
    }
  end

  -- Defensive: without the mod API surfaces we need, do nothing.
  if type(mod) ~= "table" or type(mod.world) ~= "table"
      or type(mod.events) ~= "table" then
    return degraded("mod API missing")
  end
  if type(A) ~= "table" or type(A.id) ~= "string" then
    return degraded("bad adapter")
  end

  local function loadBundled(rel)
    local okR, src = pcall(function() return mod:read(rel) end)
    if not okR or type(src) ~= "string" then return nil, src end
    local chunk, ce = (loadstring or load)(src,
      "@" .. tostring(mod.path or "?") .. "/" .. rel)
    if not chunk then return nil, ce end
    local ok, value = pcall(chunk)
    if not ok then return nil, value end
    return value
  end

  -- ---- optional modules -------------------------------------------------
  local GenMoveAdapter = loadBundled("lib/GenMoveAdapter.lua")
  local move = nil
  if type(GenMoveAdapter) == "table" and GenMoveAdapter.forGen then
    local okM, m = pcall(GenMoveAdapter.forGen, A.gen)
    if okM and type(m) == "table" then move = m end
  end
  if not move then
    return degraded("GenMoveAdapter unavailable")
  end

  local DialogueGen = loadBundled("lib/DialogueGen.lua")
  if type(DialogueGen) ~= "table" or type(DialogueGen.generate) ~= "function" then
    DialogueGen = nil -- dialogue falls back to short built-in lines
    logWarn("AmbientCore[%s]: DialogueGen unavailable, using fallback lines", A.id)
  end

  local Collision = nil
  do
    local okC, c = pcall(function() return mod.engineRequire("src.world.Collision") end)
    if okC and type(c) == "table" and c.canMove and c.target then
      Collision = c
    else
      return degraded("Collision module unavailable")
    end
  end

  local MapModule = nil
  do
    local okM, m = pcall(function() return mod.engineRequire("src.world.Map") end)
    if okM and type(m) == "table" and m.isOutdoor then MapModule = m end
  end

  local SpriteRenderer = nil
  do
    local okS, s = pcall(mod.engineRequire, "src.render.SpriteRenderer")
    if okS and type(s) == "table" and s.new then SpriteRenderer = s end
  end

  -- ---- options ----------------------------------------------------------
  local function opt(key, default)
    if type(mod.options) ~= "table" then return default end
    local ok, v = pcall(function() return mod.options:get(key) end)
    if not ok or v == nil then return default end
    return v
  end

  pcall(function()
    mod.options:define({
      { key = "ambient_humans",  label = "Ambient humans",  type = "number", default = 6, min = 0, max = 12 },
      { key = "ambient_pokemon", label = "Ambient Pokemon", type = "number", default = 4, min = 0, max = 8 },
      { key = "npc_routines", label = "NPC routines", type = "toggle", default = true },
      { key = "npc_agenda",   label = "NPC agendas",  type = "toggle", default = true },
      { key = "npc_sleep",    label = "NPC sleep",    type = "toggle", default = true },
      { key = "exp_greetings",  label = "Lifelike: greetings",      type = "toggle", default = true },
      { key = "exp_chatter",    label = "Lifelike: NPC chatter",    type = "toggle", default = true },
      { key = "exp_moods",      label = "Lifelike: moods",          type = "toggle", default = true },
      { key = "exp_idle",       label = "Lifelike: idle behaviors", type = "toggle", default = true },
      { key = "exp_timeaware",  label = "Lifelike: time comments",  type = "toggle", default = true },
      { key = "exp_player",     label = "Lifelike: notice player",  type = "toggle", default = true },
      { key = "exp_companions", label = "Lifelike: companions",     type = "toggle", default = true },
      { key = "exp_ambience",   label = "Lifelike: ambience",       type = "toggle", default = true },
      { key = "fly_teleport_freq", label = "Fly/teleport frequency", type = "choice",
        default = "medium",
        choices = {
          { label = "Frequent", value = "frequent" },
          { label = "Medium",   value = "medium" },
          { label = "Low",      value = "low" },
        } },
      { key = "fifth_interactions", label = "5th interactions", type = "toggle", default = true },
    })
  end)

  -- ---- save helpers -----------------------------------------------------
  local function saveGet(key, default)
    if type(mod.save) ~= "table" then return default end
    local ok, v = pcall(function() return mod.save:get(key, default) end)
    if not ok then return default end
    return (v == nil) and default or v
  end
  local function saveSet(key, value)
    if type(mod.save) ~= "table" then return end
    pcall(function() mod.save:set(key, value) end)
  end

  -- ---- game / overworld access ------------------------------------------
  local function getGame()
    local ok, g = pcall(function() return mod.game end)
    if ok and g then return g end
    local ow = nil
    pcall(function() ow = mod.world:overworld() end)
    if ow then
      if ow.game then return ow.game end
      -- OverworldState holds a game reference on most builds; probe gently.
      local ok2, g2 = pcall(function() return ow._game or ow.Game end)
      if ok2 and g2 then return g2 end
    end
    return nil
  end

  local function safeOverworld()
    local ow = nil
    pcall(function() ow = mod.world:overworld() end)
    return ow
  end

  local function isOutdoor(def)
    if type(A.isOutdoor) == "function" then
      local ok, v = pcall(A.isOutdoor, def)
      if ok and v ~= nil then return v and true or false end
    end
    if MapModule then
      local ok, v = pcall(MapModule.isOutdoor, def)
      if ok and v ~= nil then return v and true or false end
    end
    return false
  end

  -- ---- state ------------------------------------------------------------
  local alive = true
  local booted = false
  local tickCount = 0
  -- maps[mapId] = { list={entry...}, byUid={uid=entry}, slots=n,
  --                 doors={ {x,y}... }|nil, respawn={ {at, kind} } }
  local maps = {}
  local bubbles = {} -- { npcId, text, until }
  local currentTod = "DAY"
  local wasNight = false
  local sleepSaveKey = A.id .. "_sleep"
  local flyTpSaveKey = A.id .. "_flytp"
  local pendingSleep = nil -- roster restored from save, applied on balance

  -- forward declarations (defined in the sleep section below, but used by
  -- balance() above their definition point)
  local isNightTod, setSleeping

  local MALE_NAMES = {
    "Aaron","Ben","Carlos","Dan","Eli","Frank","Gus","Hank","Ivan","Jack",
    "Kyle","Liam","Milo","Nate","Owen","Pete","Quinn","Ray","Sam","Theo",
  }
  local FEMALE_NAMES = {
    "Ada","Beth","Cora","Dana","Elsa","Faye","Gina","Hana","Iris","June",
    "Kara","Lena","Mia","Nina","Opal","Paula","Rosa","Sara","Tina","Uma",
  }
  local FALLBACK_LINES = {
    "Nice to meet you! Enjoying the sights?",
    "The weather has been strange lately, don't you think?",
    "I heard something interesting down the road.",
    "Just passing through. You?",
    "Have you seen my friend? We got separated.",
    "This place always feels alive, doesn't it?",
  }

  local function mapState(mapId)
    local ms = maps[mapId]
    if not ms then
      ms = { list = {}, byUid = {}, slots = 0, doors = nil, respawn = {} }
      maps[mapId] = ms
    end
    return ms
  end

  -- ---- door cells -------------------------------------------------------
  local function mapDoors(mapId)
    local ms = maps[mapId]
    if ms.doors then return ms.doors end
    local doors = {}
    local ow = safeOverworld()
    local def = ow and ow.map and ow.map.def
    if def and type(def.warps) == "table" then
      for _, w in ipairs(def.warps) do
        if type(w) == "table" and type(w.x) == "number"
            and type(w.y) == "number" then
          doors[#doors + 1] = { x = w.x, y = w.y }
        end
      end
    end
    ms.doors = doors
    return doors
  end

  local function nearDoor(x, y, doors, dist)
    for _, d in ipairs(doors or {}) do
      if math.abs(x - d.x) + math.abs(y - d.y) <= dist then return true end
    end
    return false
  end

  -- ---- movement ---------------------------------------------------------
  -- tryStep: the ONLY place that writes movement fields. Never call the
  -- field writes directly elsewhere (grep audit: targetX/targetY/moving/
  -- progress assignments live here alone).
  local function tryStep(npc, dir)
    if not npc or npc.moving then return false end
    if type(npc.cellX) ~= "number" or type(npc.cellY) ~= "number" then
      return false
    end
    local ow = safeOverworld()
    local map = ow and ow.map
    if not map then return false end
    local entities = ow.npcs
    local ok, can = pcall(Collision.canMove, map, entities, npc, dir)
    if not (ok and can) then return false end
    local okT, tx, ty = pcall(Collision.target, npc.cellX, npc.cellY, dir)
    if not (okT and type(tx) == "number" and type(ty) == "number") then
      return false
    end
    npc.targetX = tx
    npc.targetY = ty
    npc.facing = dir
    npc.moving = true
    npc.progress = 0
    return true
  end

  local DIRS4 = { "up", "down", "left", "right" }
  local function stepToward(npc, tx, ty)
    if not npc or npc.moving then return false end
    local dx = tx - npc.cellX
    local dy = ty - npc.cellY
    local pref = {}
    if math.abs(dx) >= math.abs(dy) then
      pref[1] = dx > 0 and "right" or "left"
      pref[2] = dy > 0 and "down" or "up"
    else
      pref[1] = dy > 0 and "down" or "up"
      pref[2] = dx > 0 and "right" or "left"
    end
    for _, d in ipairs(DIRS4) do
      local seen = false
      for _, p in ipairs(pref) do if p == d then seen = true break end end
      if not seen then pref[#pref + 1] = d end
    end
    for _, d in ipairs(pref) do
      if tryStep(npc, d) then return true end
    end
    return false
  end

  local function manhattan(ax, ay, bx, by)
    return math.abs(ax - bx) + math.abs(ay - by)
  end

  -- ---- bubbles (render.hud text bubbles) --------------------------------
  local function addBubble(entry, text, ttl)
    if not entry or not entry.npcId or type(text) ~= "string" then return end
    bubbles[#bubbles + 1] = {
      npcId = entry.npcId, text = text,
      untilT = os.clock() + (tonumber(ttl) or 2.5),
    }
    if #bubbles > 40 then table.remove(bubbles, 1) end
  end

  local hudFont = nil
  local unwrapHud = nil
  local function drawBubbles(game, viewport)
    if #bubbles == 0 then return end
    local now = os.clock()
    -- prune expired
    for i = #bubbles, 1, -1 do
      if bubbles[i].untilT < now then table.remove(bubbles, i) end
    end
    if #bubbles == 0 then return end
    local cam = game and game.camera
    if not (cam and type(cam.x) == "number" and type(cam.y) == "number") then
      return
    end
    local R = require("src.render.Renderer")
    local wc = R and R.worldCanvas
    if not (wc and wc.getWidth) then return end
    local wvw, wvh = wc:getWidth(), wc:getHeight()
    if not (wvw > 0 and wvh > 0) then return end
    local ww, wh = love.graphics.getDimensions()
    local pw, ph = ww, wh
    if love.graphics.getPixelDimensions then
      pw, ph = love.graphics.getPixelDimensions()
    end
    local dpiX, dpiY = 1, 1
    if ww > 0 then dpiX = pw / ww end
    if wh > 0 then dpiY = ph / wh end
    if dpiX < 1e-6 then dpiX = 1 end
    if dpiY < 1e-6 then dpiY = 1 end
    -- Replicate Renderer:endFrame's world-pass blit geometry so bubbles
    -- land exactly over their NPCs (fail-open: any failure skips drawing).
    local sp = R:fitScale()
    local okZ, Zoom = pcall(mod.engineRequire, "src.render.Zoom")
    if okZ and Zoom and Zoom.scale then sp = Zoom.scale(sp) end
    sp = R:worldPresentationScale(sp, pw, ph, wvw, wvh)
    local sx, sy = sp / dpiX, sp / dpiY
    local wox = math.floor((pw - wvw * sp) / 2) / dpiX
    local woy = math.floor((ph - wvh * sp) / 2) / dpiY
    if not hudFont then hudFont = love.graphics.newFont(12) end
    local ow = safeOverworld()
    local npcs = ow and ow.npcs
    if not npcs then return end
    love.graphics.push()
    love.graphics.setFont(hudFont)
    for _, b in ipairs(bubbles) do
      local npc = nil
      for _, n in ipairs(npcs) do
        if n.id == b.npcId then npc = n break end
      end
      if npc and type(npc.px) == "number" and type(npc.py) == "number" then
        local x = wox + (npc.px + 8 - cam.x) * sx
        local y = woy + (npc.py - 10 - cam.y) * sy
        if x > -40 and y > -20 and x < ww + 40 and y < wh + 20 then
          local tw = hudFont:getWidth(b.text)
          local bx, by = x - tw / 2 - 3, y - 2
          love.graphics.setColor(0, 0, 0, 0.72)
          love.graphics.rectangle("fill", bx, by, tw + 6, 16)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.print(b.text, bx + 3, by + 1)
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
  end

  pcall(function()
    unwrapHud = mod.hooks:wrap("render.hud", function(next, game, viewport)
      local ok, err = pcall(drawBubbles, game, viewport)
      if not ok then
        -- Fail-open: a drawing bug must never break the frame.
        bubbles = {}
      end
      return next()
    end)
  end)

  -- ---- sprite helpers ---------------------------------------------------
  local validSpriteCache = {}
  local function spriteValid(id)
    if type(id) ~= "string" then return false end
    if validSpriteCache[id] ~= nil then return validSpriteCache[id] end
    local ok = false
    local game = getGame()
    pcall(function()
      ok = game and game.data and game.data.sprites
        and game.data.sprites[id] ~= nil or false
    end)
    validSpriteCache[id] = ok
    return ok
  end

  local function speciesName(species)
    local game = getGame()
    local name = nil
    pcall(function()
      local def = game and game.data and game.data.pokemon
        and game.data.pokemon[species]
      if def and def.name then name = tostring(def.name) end
    end)
    return name or tostring(species)
  end

  -- Swap an NPC's overworld sprite to a species' art for fly/teleport
  -- departures. Best-effort: registered KL sprite first, then a vanilla
  -- pokemon sprite from the current map, else keep the current sprite.
  local spriteSwapFailed = false
  local function spriteForSpecies(species)
    if type(species) ~= "string" then return nil end
    local regId = "KL_" .. A.id .. "_" .. species
    if spriteValid(regId) then return regId end
    -- Try to register from the species' art. The pokemon data schema
    -- carries spriteFront/spriteBack paths (battle art); per the design,
    -- a registered 1-frame sprite from that art is the fallback when no
    -- overworld species art is discoverable. All speculative: fail-open.
    if not spriteSwapFailed then
      local ok, path = pcall(function()
        local game = getGame()
        local def = game and game.data and game.data.pokemon
          and game.data.pokemon[species]
        if type(def) ~= "table" then return nil end
        for _, k in ipairs({ "spriteFront", "spriteBack", "icon",
                             "front", "sprite", "image", "iconImage" }) do
          if type(def[k]) == "string" then return def[k] end
        end
        return nil
      end)
      if ok and type(path) == "string" and path ~= "" then
        local okF, exists = pcall(function()
          return love.filesystem.getInfo(path) ~= nil
        end)
        if okF and exists then
          local okR = pcall(function()
            mod.content.sprites:register(regId, { image = path, frames = 1 })
          end)
          if okR then
            validSpriteCache[regId] = nil -- drop the pre-register miss
            if spriteValid(regId) then return regId end
          end
        end
      end
    end
    return nil
  end

  local function swapNpcSprite(entry, species)
    if not entry or not entry.npc or not SpriteRenderer then return end
    local sid = spriteForSpecies(species)
    if not sid then return end
    pcall(function()
      local game = getGame()
      local def = game and game.data and game.data.sprites
        and game.data.sprites[sid]
      if def then
        entry.npc.sprite = SpriteRenderer.new(def, entry.npc.id)
      end
    end)
  end

  -- ---- fly/teleport cooldown --------------------------------------------
  local function flyTpCooldownSecs()
    local f = opt("fly_teleport_freq", "medium")
    if f == "frequent" then return 0 end
    if f == "low" then return 10 end
    return 5 -- medium
  end

  local function flyTpReady()
    local cd = flyTpCooldownSecs()
    if cd <= 0 then return true end
    local last = tonumber(saveGet(flyTpSaveKey, 0)) or 0
    return (os.time() - last) >= cd
  end

  local function flyTpConsume()
    saveSet(flyTpSaveKey, os.time())
  end

  -- ---- spawning ---------------------------------------------------------
  local function pickSpawnCell(ow, nearX, nearY)
    local map = ow and ow.map
    if not map then return nil end
    for _ = 1, 12 do
      local x = nearX + math.random(-7, 7)
      local y = nearY + math.random(-7, 7)
      if manhattan(x, y, nearX, nearY) >= 2 then
        local okW, walk = pcall(function() return map:isWalkableCell(x, y) end)
        local okH2O, water = pcall(function() return map:isWaterCell(x, y) end)
        if okW and walk and not (okH2O and water) then
          return x, y
        end
      end
    end
    return nil
  end

  local function findNpc(npcId)
    local ow = safeOverworld()
    if not (ow and ow.npcs) then return nil end
    for _, n in ipairs(ow.npcs) do
      if n.id == npcId then return n end
    end
    return nil
  end

  local function spawnOne(mapId, kind, atX, atY)
    local ow = safeOverworld()
    if not ow then return nil end
    local ms = mapState(mapId)
    ms.slots = ms.slots + 1
    local uid = mapId .. "#" .. ms.slots
    local isPoke = kind == "poke"
    local spriteId, displayName, species, gender = nil, nil, nil, nil

    if isPoke then
      local pool = A.pokemonSpecies or {}
      if #pool == 0 then return nil end
      species = pool[math.random(#pool)]
      displayName = speciesName(species)
      -- Pokemon NPCs reuse a validated species sprite registration when
      -- available, else a validated human-pool sprite is never used for
      -- them: fall back to any validated vanilla map sprite.
      spriteId = spriteForSpecies(species)
      if not spriteId then
        for _, n in ipairs(ow.npcs or {}) do
          local s = n.def and n.def.sprite
          if type(s) == "string" and spriteValid(s)
              and not (n.def.kantoLifeAmbient) then
            spriteId = s
            break
          end
        end
      end
      if not spriteId then return nil end -- fail-open: no sprite, no spawn
    else
      if type(A.refreshHumans) == "function" then
        pcall(A.refreshHumans)
      end
      local pool = A.humanSprites or {}
      if #pool == 0 then return nil end
      local pick = pool[math.random(#pool)]
      if type(pick) == "table" then
        spriteId, gender = pick[1], pick[2]
      else
        spriteId = pick
      end
      if not spriteValid(spriteId) then return nil end
      gender = (gender == "m" or gender == "f") and gender
        or (math.random() < 0.5 and "m" or "f")
      local names = (gender == "m") and MALE_NAMES or FEMALE_NAMES
      displayName = names[math.random(#names)]
    end

    local px, py = atX, atY
    if not (px and py) then
      local pl = ow.player
      local nx, ny = pl and pl.cellX or 10, pl and pl.cellY or 10
      px, py = pickSpawnCell(ow, nx, ny)
      if not (px and py) then return nil end
    end

    local facing = DIRS4[math.random(#DIRS4)]
    local game = getGame()
    local okW, wdef = pcall(move.wander, facing, 3,
      game and game.data or nil)
    local def = {}
    if okW and type(wdef) == "table" then
      for k, v in pairs(wdef) do def[k] = v end
    end
    def.x = px
    def.y = py
    def.sprite = spriteId
    def.name = displayName
    def.kantoLifeAmbient = true
    def.kantoLifeSlot = uid
    def.kantoLifeIsPoke = isPoke and true or nil
    def.kantoLifeSpecies = species
    def.kantoLifeDisplayName = displayName
    -- def.text intentionally left nil: the engine talk path only
    -- faces/unfreezes text-less NPCs, and our interacted handler runs
    -- the talk pipeline.

    local npcId, err = mod.world:spawnNpc(mapId, def)
    if not npcId then
      logWarn("AmbientCore[%s]: spawnNpc failed: %s", A.id, tostring(err))
      return nil
    end
    local npc = findNpc(npcId)
    if npc then pcall(move.tune, npc, { wanderBox = 3 }) end

    local entry = {
      uid = uid, npcId = npcId, npc = npc,
      mapId = mapId, isPoke = isPoke, species = species,
      displayName = displayName, gender = gender,
      state = "wander", stateT = math.random(20, 60),
      mood = ({ "happy", "calm", "grumpy" })[math.random(3)],
      nextMoodT = os.clock() + math.random(45, 120),
      nextGreetT = os.clock() + math.random(10, 40),
      nextIdleT = os.clock() + math.random(20, 60),
      nextAmbT = os.clock() + math.random(30, 90),
      recent = {}, sleeping = false, pauseT = 0,
      agenda = "wander",
    }
    ms.list[#ms.list + 1] = entry
    ms.byUid[uid] = entry
    return entry
  end

  local function despawnEntry(entry)
    if not entry then return end
    pcall(function() mod.world:removeNpc(entry.npcId) end)
    local ms = maps[entry.mapId]
    if ms then
      ms.byUid[entry.uid] = nil
      for i, e in ipairs(ms.list) do
        if e == entry then table.remove(ms.list, i) break end
      end
    end
  end

  local function despawnMap(mapId)
    local ms = maps[mapId]
    if not ms then return end
    for i = #ms.list, 1, -1 do
      local e = ms.list[i]
      pcall(function() mod.world:removeNpc(e.npcId) end)
    end
    maps[mapId] = nil
  end

  local function countKind(ms, kind)
    local n = 0
    for _, e in ipairs(ms.list) do
      if (kind == "poke") == (e.isPoke and true or false) then n = n + 1 end
    end
    return n
  end

  local function balance(mapId)
    local ow = safeOverworld()
    if not ow or not ow.map then return end
    if ow.map.id ~= mapId then mapId = ow.map.id end
    local def = ow.map.def or {}
    local outdoor = isOutdoor(def)
    local wantH = opt("ambient_humans", 6)
    local wantP = opt("ambient_pokemon", 4)
    if not outdoor then
      wantH = math.ceil(wantH / 3)
      wantP = math.ceil(wantP / 3)
    end
    local ms = mapState(mapId)
    -- trim extras (option lowered)
    for i = #ms.list, 1, -1 do
      local e = ms.list[i]
      local over = (e.isPoke and countKind(ms, "poke") > wantP)
        or ((not e.isPoke) and countKind(ms, "human") > wantH)
      if over then despawnEntry(e) end
    end
    -- spawn missing
    local needH = wantH - countKind(ms, "human")
    local needP = wantP - countKind(ms, "poke")
    for _ = 1, math.max(0, needH) do spawnOne(mapId, "human") end
    for _ = 1, math.max(0, needP) do spawnOne(mapId, "poke") end
    -- companions: bond a pair of humans (follower + leader)
    if opt("exp_companions", true) then
      local humans = {}
      for _, e in ipairs(ms.list) do
        if not e.isPoke and not e.followUid and e.state == "wander" then
          humans[#humans + 1] = e
        end
      end
      if #humans >= 2 and math.random() < 0.5 then
        local a = humans[math.random(#humans)]
        local b = humans[math.random(#humans)]
        if a ~= b then
          b.followUid = a.uid
          b.state = "follow"
          b.agenda = "follow"
          addBubble(b, "^^", 2)
        end
      end
    end
    -- re-apply persisted sleep roster on night loads
    if pendingSleep and pendingSleep.map == mapId and isNightTod() then
      for uid in pairs(pendingSleep.uids or {}) do
        local e = ms.byUid[uid]
        if e and not e.sleeping then setSleeping(e, true) end
      end
      pendingSleep = nil
    end
  end

  -- ---- sleep ------------------------------------------------------------
  isNightTod = function()
    return currentTod == "NIGHT" or currentTod == "NITE"
  end

  setSleeping = function(entry, asleep)
    local npc = entry and entry.npc
    if not npc then return end
    if asleep then
      entry.sleeping = true
      npc.frozen = true
      npc.facing = "down"
      npc.moving = false
      addBubble(entry, "Z", 5)
    else
      entry.sleeping = false
      npc.frozen = false
    end
  end

  local function pollTod()
    local ow = safeOverworld()
    if ow then
      local t = ow.tod or ow.objectTod
      if type(t) == "string" and t ~= "" then currentTod = t end
    end
  end

  local function applyNightTransition()
    local night = isNightTod()
    if night == wasNight then return end
    wasNight = night
    if not opt("npc_sleep", true) then return end
    for mapId, ms in pairs(maps) do
      local doors = mapDoors(mapId)
      if night then
        local roster = {}
        for _, e in ipairs(ms.list) do
          -- ~35% sleep; never within 5 cells of a door cell.
          if not e.sleeping and math.random() < 0.35 then
            local npc = e.npc
            if npc and not nearDoor(npc.cellX, npc.cellY, doors, 5) then
              setSleeping(e, true)
              roster[e.uid] = true
            end
          elseif e.sleeping then
            roster[e.uid] = true
          end
        end
        saveSet(sleepSaveKey, { map = mapId, uids = roster })
      else
        for _, e in ipairs(ms.list) do
          if e.sleeping then setSleeping(e, false) end
        end
        saveSet(sleepSaveKey, nil)
      end
    end
  end

  -- ---- travel / departures ----------------------------------------------
  local function waterNear(npc, radius)
    local ow = safeOverworld()
    local map = ow and ow.map
    if not (map and npc) then return nil end
    for r = 1, radius do
      for dx = -r, r do
        for _, dy in ipairs({ -r, r }) do
          local okW, water = pcall(function()
            return map:isWaterCell(npc.cellX + dx, npc.cellY + dy)
          end)
          if okW and water then
            return npc.cellX + dx, npc.cellY + dy
          end
        end
        for dy = -r + 1, r - 1 do
          for _, dx2 in ipairs({ -r, r }) do
            local okW, water = pcall(function()
              return map:isWaterCell(npc.cellX + dx2, npc.cellY + dy)
            end)
            if okW and water then
              return npc.cellX + dx2, npc.cellY + dy
            end
          end
        end
      end
    end
    return nil
  end

  local function walkableCell(x, y)
    local ow = safeOverworld()
    local map = ow and ow.map
    if not map then return false end
    local ok, v = pcall(function() return map:isWalkableCell(x, y) end)
    return ok and v or false
  end

  local function adjacentWalkable(x, y, doors)
    for _, d in ipairs(DIRS4) do
      local dx, dy = 0, 0
      if d == "up" then dy = -1
      elseif d == "down" then dy = 1
      elseif d == "left" then dx = -1
      else dx = 1 end
      local cx, cy = x + dx, y + dy
      if walkableCell(cx, cy) and not nearDoor(cx, cy, doors, 0) then
        return cx, cy
      end
    end
    return nil
  end

  local function startTravel(entry)
    local npc = entry.npc
    if not npc then return end
    local doors = mapDoors(entry.mapId)
    -- choose departure method
    local method = "door"
    local r = math.random()
    if flyTpReady() and r < 0.35 then
      method = (math.random() < 0.5) and "fly" or "teleport"
    else
      local wx, wy = waterNear(npc, 4)
      if wx then method = "surf" end
    end
    local tx, ty = nil, nil
    if method == "surf" then
      local wx, wy = waterNear(npc, 4)
      if wx then
        -- walk to a walkable cell beside the water, despawn at the edge
        for _, d in ipairs(DIRS4) do
          local dx, dy = 0, 0
          if d == "up" then dy = -1 elseif d == "down" then dy = 1
          elseif d == "left" then dx = -1 else dx = 1 end
          if walkableCell(wx + dx, wy + dy) then
            tx, ty = wx + dx, wy + dy
            break
          end
        end
      end
      if not tx then method = "door" end
    end
    if method ~= "surf" then
      if #doors > 0 then
        local door = doors[math.random(#doors)]
        tx, ty = adjacentWalkable(door.x, door.y, doors)
      end
      if not tx then
        -- no doors: wander off to a random reachable cell instead
        tx = npc.cellX + math.random(-8, 8)
        ty = npc.cellY + math.random(-8, 8)
      end
    end
    entry.state = "travel"
    entry.agenda = "travel"
    entry.travelTX, entry.travelTY = tx, ty
    entry.departMethod = method
    entry.stuckT = 0
    npc.wanders = false
    npc.frozen = false
  end

  local function departNow(entry)
    local npc = entry.npc
    local method = entry.departMethod or "door"
    if method == "fly" or method == "teleport" then
      flyTpConsume()
      addBubble(entry, method == "fly" and "^^" or "**", 2)
      local pool = (method == "fly") and A.flySpecies or A.psychicSpecies
      if type(pool) == "table" and #pool > 0 and npc then
        swapNpcSprite(entry, pool[math.random(#pool)])
      end
      entry.state = "depart"
      entry.departKind = method
      entry.departT = (method == "fly") and 1.0 or 0.7
      if npc then npc.frozen = true end
    elseif method == "surf" then
      addBubble(entry, "~", 2)
      -- schedule a respawn at another door later
      local ms = maps[entry.mapId]
      if ms then
        ms.respawn[#ms.respawn + 1] = {
          at = os.clock() + math.random(20, 40),
          kind = entry.isPoke and "poke" or "human",
        }
      end
      despawnEntry(entry)
    else
      local ms = maps[entry.mapId]
      if ms then
        ms.respawn[#ms.respawn + 1] = {
          at = os.clock() + math.random(20, 40),
          kind = entry.isPoke and "poke" or "human",
        }
      end
      despawnEntry(entry)
    end
  end

  local function driveTravel(entry, dt)
    local npc = entry.npc
    if not npc then despawnEntry(entry) return end
    if npc.moving then return end -- engine is advancing the step
    entry.stuckT = (entry.stuckT or 0) + dt
    if entry.stuckT > 8 then
      -- stuck: give up quietly (fail-open)
      despawnEntry(entry)
      return
    end
    local tx, ty = entry.travelTX, entry.travelTY
    if not (tx and ty) then despawnEntry(entry) return end
    if manhattan(npc.cellX, npc.cellY, tx, ty) <= 1 then
      departNow(entry)
      return
    end
    if stepToward(npc, tx, ty) then entry.stuckT = 0 end
  end

  local function driveDepart(entry, dt)
    local npc = entry.npc
    entry.departT = (entry.departT or 0.5) - dt
    if entry.departKind == "fly" and npc then
      npc.py = npc.py - 48 * dt -- rise, then despawn
    end
    if entry.departT <= 0 then
      local ms = maps[entry.mapId]
      if ms then
        ms.respawn[#ms.respawn + 1] = {
          at = os.clock() + math.random(20, 40),
          kind = entry.isPoke and "poke" or "human",
        }
      end
      despawnEntry(entry)
    end
  end

  -- ---- meetups (chatter) -------------------------------------------------
  local function faceEachOther(a, b)
    local na, nb = a.npc, b.npc
    if not (na and nb) then return end
    local dx, dy = nb.cellX - na.cellX, nb.cellY - na.cellY
    if math.abs(dx) >= math.abs(dy) then
      na.facing = dx > 0 and "right" or "left"
      nb.facing = dx > 0 and "left" or "right"
    else
      na.facing = dy > 0 and "down" or "up"
      nb.facing = dy > 0 and "up" or "down"
    end
  end

  local CHAT_LINES = {
    "Did you hear?",
    "No way!",
    "Really?",
    "Ha!",
    "Tell me more.",
    "Hmm...",
  }

  local function startMeetup(a, b)
    for _, e in ipairs({ a, b }) do
      e.state = "meetup"
      e.agenda = "chat"
      e.meetupT = 10
      e.meetPartner = (e == a) and b.uid or a.uid
      if e.npc then
        e.npc.wanders = false
        e.npc.frozen = true
        e.npc.moving = false
      end
    end
    faceEachOther(a, b)
    local now = os.clock()
    a.meetupBubbles = {
      { at = now + 0.5, text = CHAT_LINES[math.random(#CHAT_LINES)] },
      { at = now + 5.5, text = CHAT_LINES[math.random(#CHAT_LINES)] },
    }
    b.meetupBubbles = {
      { at = now + 3.0, text = CHAT_LINES[math.random(#CHAT_LINES)] },
      { at = now + 8.0, text = CHAT_LINES[math.random(#CHAT_LINES)] },
    }
  end

  local function endMeetup(entry)
    entry.state = "wander"
    entry.agenda = "wander"
    entry.stateT = math.random(20, 60)
    entry.meetPartner = nil
    entry.meetupBubbles = nil
    local npc = entry.npc
    if npc then
      npc.frozen = false
      npc.wanders = true
    end
  end

  -- ---- lifelike tick helpers ---------------------------------------------
  local GREETINGS = {
    happy = { "Hi there!", "Hey!", "Lovely day!" },
    calm = { "Hello.", "Hi.", "Good day." },
    grumpy = { "Hmph.", "What?", "Oh. Hi." },
  }

  local function playerCell()
    local ow = safeOverworld()
    local p = ow and ow.player
    if p and type(p.cellX) == "number" then return p.cellX, p.cellY end
    return nil
  end

  local function lifelikeTick(entry, now)
    local npc = entry.npc
    if not npc or entry.sleeping then return end
    local px, py = playerCell()
    local distP = (px and manhattan(npc.cellX, npc.cellY, px, py)) or 99

    -- greetings
    if opt("exp_greetings", true) and entry.state == "wander"
        and now >= (entry.nextGreetT or 0) then
      entry.nextGreetT = now + math.random(25, 70)
      if distP <= 4 and math.random() < 0.6 then
        local g = GREETINGS[entry.mood] or GREETINGS.calm
        addBubble(entry, g[math.random(#g)], 2.5)
      end
    end
    -- moods shift slowly
    if opt("exp_moods", true) and now >= (entry.nextMoodT or 0) then
      entry.nextMoodT = now + math.random(45, 120)
      entry.mood = ({ "happy", "calm", "grumpy" })[math.random(3)]
    end
    -- idle: spin-in-place or brief pause
    if opt("exp_idle", true) and entry.state == "wander"
        and now >= (entry.nextIdleT or 0) then
      entry.nextIdleT = now + math.random(30, 90)
      local r = math.random()
      if r < 0.35 then
        npc.facing = DIRS4[math.random(#DIRS4)]
      elseif r < 0.5 then
        entry.pauseT = 2
      end
    end
    -- ambience: yawns, sneezes, curiosity
    if opt("exp_ambience", true) and now >= (entry.nextAmbT or 0) then
      entry.nextAmbT = now + math.random(40, 120)
      local r = math.random()
      if r < 0.4 then addBubble(entry, "*yawn*", 2.5)
      elseif r < 0.7 then addBubble(entry, "*achoo!*", 2)
      else addBubble(entry, "?", 2) end
    end
  end

  local function driveFollow(entry)
    local npc = entry.npc
    if not npc or npc.moving then return end
    local ms = maps[entry.mapId]
    local leader = ms and ms.byUid[entry.followUid]
    if not (leader and leader.npc and not leader.sleeping) then
      entry.followUid = nil
      entry.state = "wander"
      entry.agenda = "wander"
      if npc then npc.wanders = true end
      return
    end
    local ln = leader.npc
    local d = manhattan(npc.cellX, npc.cellY, ln.cellX, ln.cellY)
    if d > 1 then
      npc.wanders = false
      stepToward(npc, ln.cellX, ln.cellY) -- canMove blocks the occupied cell
    elseif d == 0 then
      stepToward(npc, npc.cellX + 1, npc.cellY) -- shouldn't happen; nudge
    end
  end

  -- ---- per-entry AI -------------------------------------------------------
  local function aiStep(entry, dt, now)
    local npc = entry.npc
    if not npc then return end
    if entry.sleeping then return end -- frozen; skip everything

    -- brief idle pause
    if entry.pauseT > 0 then
      entry.pauseT = entry.pauseT - dt
      npc.frozen = true
      if entry.pauseT <= 0 then npc.frozen = false end
      return
    end

    if entry.state == "travel" then
      driveTravel(entry, dt)
      return
    elseif entry.state == "depart" then
      driveDepart(entry, dt)
      return
    elseif entry.state == "meetup" then
      entry.meetupT = (entry.meetupT or 0) - dt
      for _, b in ipairs(entry.meetupBubbles or {}) do
        if not b.done and now >= b.at then
          b.done = true
          addBubble(entry, b.text, 2.5)
        end
      end
      if entry.meetupT <= 0 then endMeetup(entry) end
      return
    elseif entry.state == "follow" then
      driveFollow(entry)
      lifelikeTick(entry, now)
      return
    end

    -- wander: agenda state machine
    if opt("npc_agenda", true) then
      entry.stateT = (entry.stateT or 30) - dt
      if entry.stateT <= 0 then
        local r = math.random()
        if opt("npc_routines", true) and r < 0.55 then
          startTravel(entry)
          return
        elseif r < 0.8 then
          entry.state = "rest"
          entry.agenda = "rest"
          entry.stateT = math.random(15, 40)
          npc.frozen = true
          return
        else
          entry.stateT = math.random(20, 60)
        end
      end
    end
    if entry.state == "rest" then
      entry.stateT = (entry.stateT or 20) - dt
      if entry.stateT <= 0 then
        entry.state = "wander"
        entry.agenda = "wander"
        entry.stateT = math.random(20, 60)
        npc.frozen = false
      end
      return
    end
    lifelikeTick(entry, now)
  end

  -- ---- 5th interactions ---------------------------------------------------
  local function playerMaxLevel(game)
    local ok, lvl = pcall(function()
      local m = 0
      for _, mon in ipairs(game.save.party or {}) do
        if type(mon) == "table" and type(mon.level) == "number"
            and mon.level > m then
          m = mon.level
        end
      end
      return m
    end)
    if ok and lvl and lvl > 0 then return lvl end
    return 5
  end

  local function itemName(id)
    local game = getGame()
    local name = nil
    pcall(function()
      local def = game and game.data and game.data.items
        and game.data.items[id]
      if def and def.name then name = tostring(def.name) end
    end)
    return name or tostring(id)
  end

  local function itemValid(id)
    local game = getGame()
    local ok = false
    pcall(function()
      ok = game and game.data and game.data.items
        and game.data.items[id] ~= nil or false
    end)
    return ok
  end

  local function pickGift(pool)
    for _ = 1, 10 do
      local id = pool[math.random(#pool)]
      if itemValid(id) then return id end
    end
    return nil
  end

  local function queueRows(rows)
    pcall(function() mod.world:queueScript(rows) end)
  end

  local function talkLine(entry, mapId)
    local line = FALLBACK_LINES[math.random(#FALLBACK_LINES)]
    if DialogueGen then
      local ok, gen, recent = pcall(DialogueGen.generate, {
        npcName = entry.displayName,
        gender = entry.gender,
        agenda = entry.agenda,
        pokemon = entry.isPoke and speciesName(entry.species) or nil,
        location = tostring(mapId or ""),
        timeOfDay = currentTod,
        recentLines = entry.recent,
        dex = A.pokemonSpecies,
      })
      if ok and type(gen) == "string" and gen ~= "" then
        line = gen
        entry.recent = recent or entry.recent
      end
    end
    return line
  end

  -- Lua side of the {"kl_trade_swap", species} script verb: swap the
  -- player's first party mon for a generated one of the offered species.
  -- Returns true on success; any failure -> false (script falls back to
  -- an item gift). Never throws.
  local function tradeSwap(ctx, species)
    local game = ctx and ctx.game
    if not (game and game.save) then return false end
    local party = game.save.party
    if type(party) ~= "table" or #party == 0 then return false end
    local old = party[1]
    if type(old) ~= "table" or old.isEgg then return false end
    if type(species) ~= "string" then return false end
    local okP, Pokemon = pcall(mod.engineRequire, "src.pokemon.Pokemon")
    if not (okP and Pokemon and Pokemon.new) then return false end
    local ok, newMon = pcall(Pokemon.new, game.data, species,
      tonumber(old.level) or 5)
    if not (ok and type(newMon) == "table") then return false end
    party[1] = newMon
    return true
  end

  local unwrapCmd = nil
  pcall(function()
    unwrapCmd = mod.hooks:wrap("script.command", function(next, ctx, name, args)
      if name == "kl_trade_swap" then
        local ok, res = pcall(tradeSwap, ctx, args and args[1])
        if ctx then ctx.lastCheck = (ok and res) and true or false end
        return nil -- handled; continue to the next row
      end
      return next()
    end)
  end)

  local function fifthHuman(entry, npc, st, key, mapId)
    local game = getGame()
    local roll = math.random()
    local kind = roll < 0.4 and "item" or (roll < 0.7 and "trade" or "battle")
    if kind ~= "battle" and not cooldownOk(st, os.time()) then
      -- cooldown active: reference the earlier gift/trade instead
      local detail = st.lastDetail and itemName(st.lastDetail)
        or "that gift"
      queueRows({ { "show_text",
        "Still enjoying " .. detail .. "? I gave it to you not long ago." } })
      st.count, st.lastEvent = 0, st.lastEvent
      saveSet(key, st)
      return
    end
    if kind == "item" then
      local pool = ((A.giftTMs and #A.giftTMs > 0 and math.random() < 0.35)
        and A.giftTMs) or A.giftItems or {}
      if #pool == 0 then kind = "battle" else
        local id = pickGift(pool)
        if not id then kind = "battle" end
        if kind == "item" then
          queueRows({
            { "show_text",
              "You've been great company. Here, take this "
              .. itemName(id) .. "!" },
            { "give_item", id, 1 },
          })
          st.count, st.lastEvent, st.lastEventAt, st.lastDetail =
            0, "item", os.time(), id
          saveSet(key, st)
          return
        end
      end
    end
    if kind == "trade" then
      local pool = A.pokemonSpecies or {}
      if #pool == 0 or not game then
        kind = "battle"
      else
        local species = pool[math.random(#pool)]
        local oldName = "your lead Pokemon"
        pcall(function()
          local old = game.save.party and game.save.party[1]
          if old then
            oldName = old.nickname
              or speciesName(old.species or "?")
          end
        end)
        local fallback = pickGift(A.giftItems or {})
        local rows = {
          { "show_text",
            "Say... would you trade " .. oldName .. " for my "
            .. speciesName(species) .. "?" },
          { "choice", { "YES", "NO" } },
          { "jump_if_false", "kl_td_no" },
          { "kl_trade_swap", species },
          { "jump_if_false", "kl_td_fail" },
          { "show_text",
            "Pleasure doing business! Take good care of "
            .. speciesName(species) .. "." },
          { "jump", "kl_td_done" },
          { "label", "kl_td_fail" },
          { "show_text",
            "Hmm, the trade didn't go through. Here, take this instead." },
        }
        if fallback then
          rows[#rows + 1] = { "give_item", fallback, 1 }
        end
        rows[#rows + 1] = { "jump", "kl_td_done" }
        rows[#rows + 1] = { "label", "kl_td_no" }
        rows[#rows + 1] = { "show_text", "No worries! Maybe another time." }
        rows[#rows + 1] = { "label", "kl_td_done" }
        queueRows(rows)
        st.count, st.lastEvent, st.lastEventAt, st.lastDetail =
          0, "trade", os.time(), species
        saveSet(key, st)
        return
      end
    end
    -- battle (also the fallback for failed item/trade setup)
    if not game then
      queueRows({ { "show_text", talkLine(entry, mapId) } })
      st.count = 0
      saveSet(key, st)
      return
    end
    local okB, BattleState = pcall(mod.engineRequire, "src.battle.BattleState")
    if not (okB and BattleState and BattleState.newEditorTrainer) then
      queueRows({ { "show_text", talkLine(entry, mapId) } })
      st.count = 0
      saveSet(key, st)
      return
    end
    local lvl = enemyLevelFor(playerMaxLevel(game))
    local pool = A.pokemonSpecies or {}
    local partyRows = {}
    local n = math.random(1, 3)
    for _ = 1, n do
      if #pool > 0 then
        partyRows[#partyRows + 1] = {
          species = pool[math.random(#pool)], level = lvl,
        }
      end
    end
    if #partyRows == 0 then
      queueRows({ { "show_text", talkLine(entry, mapId) } })
      st.count = 0
      saveSet(key, st)
      return
    end
    local look = nil
    pcall(function()
      local tc = npc.def and npc.def.trainerClass
      if type(tc) == "string" and game.data.trainers
          and game.data.trainers[tc] then
        look = tc
      end
    end)
    local okT, battle = pcall(BattleState.newEditorTrainer, game,
      partyRows, look, entry.displayName)
    if not (okT and battle) then
      queueRows({ { "show_text", talkLine(entry, mapId) } })
      st.count = 0
      saveSet(key, st)
      return
    end
    -- newEditorTrainer registered trainers[EDITOR_TRAINER_CLASS]; the
    -- engine's start_battle "trainer" path builds the battle from it,
    -- so the intro text plays before the transition.
    local classKey = BattleState.EDITOR_TRAINER_CLASS or "OPP_EDITOR_TRAINER"
    queueRows({
      { "show_text",
        entry.displayName .. ": You've got spirit! Let's battle!" },
      { "start_battle", "trainer", classKey, 1 },
    })
    st.count, st.lastEvent, st.lastEventAt, st.lastDetail =
      0, "battle", os.time(), entry.displayName
    saveSet(key, st)
  end

  local function fifthPokemon(entry, npc, st, key, mapId)
    local game = getGame()
    if math.random() < 0.5 and cooldownOk(st, os.time()) then
      -- item gift
      local pool = A.giftItems or {}
      local id = (#pool > 0) and pickGift(pool) or nil
      if id then
        queueRows({
          { "play_cry", entry.species },
          { "show_text",
            speciesName(entry.species) .. " found a " .. itemName(id)
            .. " and gives it to you!" },
          { "give_item", id, 1 },
        })
        st.count, st.lastEvent, st.lastEventAt, st.lastDetail =
          0, "item", os.time(), id
        saveSet(key, st)
        return
      end
    elseif not cooldownOk(st, os.time()) then
      queueRows({
        { "play_cry", entry.species },
        { "show_text",
          speciesName(entry.species) .. " nuzzles you happily." },
      })
      st.count = 0
      saveSet(key, st)
      return
    end
    -- wild encounter with them
    if not game then
      st.count = 0
      saveSet(key, st)
      return
    end
    local lvl = enemyLevelFor(playerMaxLevel(game))
    queueRows({
      { "play_cry", entry.species },
      { "show_text", "Wild " .. speciesName(entry.species) .. " appeared!" },
      { "start_battle", "wild", entry.species, lvl },
    })
    st.count, st.lastEvent, st.lastEventAt, st.lastDetail =
      0, "wild", os.time(), entry.species
    saveSet(key, st)
  end

  local function handleTalk(entry, npc, mapId)
    if entry.sleeping then
      -- sleeping NPCs skip routines and talk counting
      npc.frozen = true
      npc.facing = "down"
      queueRows({ { "show_text", "...Zzz..." } })
      return
    end
    local key = A.id .. "_talk:" .. entry.uid
    local st = saveGet(key, nil)
    local newSt, isFifth = talkCount(st)
    if not isFifth or not opt("fifth_interactions", true) then
      local rows = {}
      if entry.isPoke and entry.species then
        rows[#rows + 1] = { "play_cry", entry.species }
      end
      rows[#rows + 1] = { "show_text", talkLine(entry, mapId) }
      queueRows(rows)
      saveSet(key, newSt)
      return
    end
    if entry.isPoke then
      fifthPokemon(entry, npc, newSt, key, mapId)
    else
      fifthHuman(entry, npc, newSt, key, mapId)
    end
  end

  -- ---- events -----------------------------------------------------------
  pcall(function()
    mod.events:on("world.interacted", function(ev)
      if not alive then return end
      if not ev or ev.kind ~= "npc" then return end
      local npc = ev.target
      if not (npc and npc.def and npc.def.kantoLifeAmbient) then return end
      local uid = npc.def.kantoLifeSlot
      if type(uid) ~= "string" then return end
      local ms = maps[ev.mapId]
      local entry = ms and ms.byUid[uid]
      if not entry then return end
      entry.npc = npc -- refresh the object reference
      local ok, err = pcall(handleTalk, entry, npc, ev.mapId)
      if not ok then logWarn("AmbientCore[%s]: talk failed: %s", A.id,
        tostring(err)) end
    end)
  end)

  pcall(function()
    mod.events:on("map.entered", function(ev)
      if not alive then return end
      local mapId = ev and ev.mapId
      if type(mapId) ~= "string" then return end
      -- sweep entries from any other map (belt-and-braces)
      local stale = {}
      for id in pairs(maps) do
        if id ~= mapId then stale[#stale + 1] = id end
      end
      for _, id in ipairs(stale) do despawnMap(id) end
      local ok, err = pcall(balance, mapId)
      if not ok then logWarn("AmbientCore[%s]: balance failed: %s", A.id,
        tostring(err)) end
      -- player-notice: nearby NPCs react to the player's arrival
      if opt("exp_player", true) then
        local ms = maps[mapId]
        local px, py = playerCell()
        if ms and px then
          for _, e in ipairs(ms.list) do
            local npc = e.npc
            if npc and not e.sleeping
                and manhattan(npc.cellX, npc.cellY, px, py) <= 5
                and math.random() < 0.5 then
              addBubble(e, math.random() < 0.5 and "!" or "Oh!", 2)
            end
          end
        end
      end
    end)
  end)

  pcall(function()
    mod.events:on("map.exited", function(ev)
      if not alive then return end
      local mapId = ev and (ev.mapId or ev.fromMapId)
      if type(mapId) == "string" then despawnMap(mapId) end
    end)
  end)

  pcall(function()
    mod.events:on("world.tod_changed", function(ev)
      if not alive then return end
      if ev then
        local t = ev.tod or ev.newTod or ev.timeOfDay
        if type(t) == "string" and t ~= "" then currentTod = t end
      end
      applyNightTransition()
      -- time-aware comments from nearby NPCs
      if opt("exp_timeaware", true) then
        local px, py = playerCell()
        if px then
          local comment = nil
          if currentTod == "MORNING" then comment = "Morning!"
          elseif currentTod == "NIGHT" or currentTod == "NITE" then
            comment = "*yawn*"
          elseif currentTod == "DAY" then comment = "Nice day." end
          if comment then
            for _, ms in pairs(maps) do
              for _, e in ipairs(ms.list) do
                local npc = e.npc
                if npc and not e.sleeping
                    and manhattan(npc.cellX, npc.cellY, px, py) <= 6
                    and math.random() < 0.4 then
                  addBubble(e, comment, 3)
                end
              end
            end
          end
        end
      end
    end)
  end)

  pcall(function()
    mod.events:on("save.loaded", function()
      if not alive then return end
      local roster = saveGet(sleepSaveKey, nil)
      if type(roster) == "table" then pendingSleep = roster end
      pollTod()
      applyNightTransition()
    end)
  end)

  pcall(function()
    mod.events:on("save.created", function()
      if not alive then return end
      saveSet(sleepSaveKey, nil)
      saveSet(flyTpSaveKey, 0)
    end)
  end)

  -- ---- main tick --------------------------------------------------------
  local function tick(ev)
    if not alive then return end
    if ev and ev.scripted then return end
    tickCount = tickCount + 1
    local ow = safeOverworld()
    if not ow or not ow.map then return end
    local mapId = ow.map.id
    if not booted then
      booted = true
      pollTod()
      local ok, err = pcall(balance, mapId)
      if not ok then logWarn("AmbientCore[%s]: boot balance failed: %s",
        A.id, tostring(err)) end
      applyNightTransition()
    end
    -- poll tod cheaply (event may not fire on all builds)
    if tickCount % 90 == 0 then
      pollTod()
      applyNightTransition()
    end
    local ms = maps[mapId]
    if not ms then return end
    -- respawn queue: travelers return at another door later
    local now = os.clock()
    for i = #ms.respawn, 1, -1 do
      local r = ms.respawn[i]
      if r.at <= now then
        table.remove(ms.respawn, i)
        local doors = mapDoors(mapId)
        if #doors > 0 then
          local door = doors[math.random(#doors)]
          local cx, cy = adjacentWalkable(door.x, door.y, doors)
          if cx then
            local ok, err = pcall(spawnOne, mapId, r.kind, cx, cy)
            if not ok then logWarn("AmbientCore[%s]: respawn failed: %s",
              A.id, tostring(err)) end
          end
        end
      end
    end
    -- meetup pairing scan (staggered)
    if tickCount % 120 == 0 and opt("exp_chatter", true)
        and opt("npc_routines", true) then
      local idle = {}
      for _, e in ipairs(ms.list) do
        if e.state == "wander" and not e.sleeping and e.npc
            and not e.followUid then
          idle[#idle + 1] = e
        end
      end
      local meetups = 0
      for i = 1, #idle do
        if meetups >= 2 then break end
        local a = idle[i]
        if a.state == "wander" then
          for j = i + 1, #idle do
            local b = idle[j]
            if b.state == "wander" and a.npc and b.npc
                and manhattan(a.npc.cellX, a.npc.cellY,
                              b.npc.cellX, b.npc.cellY) <= 3 then
              -- walk adjacent first via tryStep, then hold the conversation
              local ok, err = pcall(startMeetup, a, b)
              if ok then meetups = meetups + 1 end
              break
            end
          end
        end
      end
    end
    -- per-NPC AI, each isolated so one bad NPC can't break the loop
    local dt = (ev and tonumber(ev.dt)) or (1 / 60)
    if dt > 0.25 then dt = 0.25 end
    for i = #ms.list, 1, -1 do
      local e = ms.list[i]
      local ok, err = pcall(aiStep, e, dt, now)
      if not ok then
        logWarn("AmbientCore[%s]: AI failed for %s: %s", A.id,
          tostring(e.uid), tostring(err))
        -- keep the NPC wandering rather than killing it
        if e.npc then
          pcall(function()
            e.npc.frozen = false
            e.npc.wanders = true
          end)
        end
        e.state = "wander"
      end
    end
  end

  pcall(function()
    mod.events:on("world.tick", tick)
  end)

  logInfo("AmbientCore[%s]: installed (%s)", A.id, A.label or "?")

  local handle = {}
  function handle.shutdown()
    alive = false
    pcall(function() if unwrapHud then unwrapHud() end end)
    pcall(function() if unwrapCmd then unwrapCmd() end end)
    local ids = {}
    for id in pairs(maps) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
      pcall(despawnMap, id)
    end
    bubbles = {}
  end
  -- pure helpers also reachable off the handle (test/stub surface)
  handle.talkCount = talkCount
  handle.cooldownOk = cooldownOk
  handle.enemyLevelFor = enemyLevelFor
  return handle
end

-- The chunk returns the `core` table: a callable installer module.
--   core(mod, A) / core.install(mod, A) -> handle { shutdown = fn,
--       talkCount = fn, cooldownOk = fn, enemyLevelFor = fn }
--   core.talkCount / core.cooldownOk / core.enemyLevelFor — pure,
--   engine-free helpers (the test surface).
-- (Plain Lua functions cannot carry fields, so the module is a table
-- with a __call metamethod rather than a bare function.)
local core = {
  talkCount = talkCount,
  cooldownOk = cooldownOk,
  enemyLevelFor = enemyLevelFor,
}
core.install = install
-- No installed state lives on the module table itself; real handles
-- come from install(). This no-op keeps the module handle-shaped for
-- consumers that treat it as one.
core.shutdown = function() end
setmetatable(core, {
  __call = function(_, mod, A) return install(mod, A) end,
})
return core
