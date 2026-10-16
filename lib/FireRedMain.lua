-- lib/FireRedMain.lua — Gen 3 (FireRed / LeafGreen / Emerald) installer
-- for the Kanto Life ambient-NPC engine.
--
-- Builds the generation adapter A and hands it to AmbientCore. Defines
-- nothing itself beyond that call.
--
-- Entry: main.lua calls this chunk as installer(mod).

return function(mod)
  local function loadBundled(rel)
    local src, err = mod:read(rel)
    if type(src) ~= "string" then return nil, err end
    local chunk, ce = (loadstring or load)(src, "@" .. mod.path .. "/" .. rel)
    if not chunk then return nil, ce end
    local ok, value = pcall(chunk)
    if not ok then return nil, value end
    return value
  end

  local function logWarn(fmt, ...)
    local args = { ... }
    pcall(function() mod.log:warn(fmt, unpack(args)) end)
  end

  local function getGame()
    local ok, g = pcall(function() return mod.game end)
    if ok and g then return g end
    return nil
  end

  local function gameVersion()
    local v = nil
    pcall(function() v = mod.gameVersion end)
    if type(v) ~= "string" then
      local ok, GV = pcall(function()
        return mod.engineRequire("src.core.GameVersion")
      end)
      if ok and GV and GV.get then
        local ok2, vv = pcall(GV.get)
        if ok2 and type(vv) == "string" then v = vv end
      end
    end
    return (type(v) == "string") and v:lower() or ""
  end

  local isEmerald = gameVersion():find("emerald") ~= nil

  -- ------------------------------------------------------------------
  -- Human sprites.
  --
  -- Gen 3 object events carry a numeric graphics id; the importer maps it
  -- to "SPRITE_G3_%03d" (RomExtractorGen3). The ROM's object-graphics
  -- table is dominated by human townsfolk/trainer sprites, but the exact
  -- slot contents were NOT verified against the ROM table in this
  -- environment: the id ranges below are a best-effort curation (early
  -- player-variant slots skipped) and every id is validated against
  -- Game.data.sprites at spawn time. Runtime discovery (refreshHumans)
  -- supplements the static list with sprites from vanilla NPCs that look
  -- human (trainer class set, or wandering non-ambient NPCs).
  -- ------------------------------------------------------------------
  local HUMAN_DEFS = {}
  do
    -- Slots 16..64: presumed human townsfolk/trainer graphics.
    -- (Uncertainty documented above; runtime discovery is the backstop.)
    local genders = { "m", "f" }
    for id = 16, 64 do
      -- Skip a few slots that commonly hold non-human props in Gen 3
      -- object tables (best-effort guess, documented as such).
      if id ~= 29 and id ~= 30 and id ~= 47 then
        HUMAN_DEFS[#HUMAN_DEFS + 1] = {
          ("SPRITE_G3_%03d"):format(id),
          genders[(id % 2) + 1],
        }
      end
    end
  end

  local A = {
    id = "kl3",
    gen = 3,
    label = "FireRed",
    humanSprites = HUMAN_DEFS,
  }

  -- Runtime discovery: harvest human-looking sprites from vanilla NPCs
  -- on the current map. Called by the core before each balance pass.
  local discovered = {}
  function A.refreshHumans()
    local ok, err = pcall(function()
      local ow = mod.world:overworld()
      if not (ow and ow.npcs) then return end
      for _, n in ipairs(ow.npcs) do
        local def = n.def
        if def and not def.kantoLifeAmbient then
          local s = def.sprite
          if type(s) == "string" and not discovered[s] then
            local humanish = def.trainerClass ~= nil
              or def.movement == "WALK"
            -- Exclude obvious props: static NPCs with no text and no
            -- trainer class are usually signs/boulders/item balls.
            if humanish then
              discovered[s] = true
              A.humanSprites[#A.humanSprites + 1] = { s, nil }
            end
          end
        end
      end
    end)
    if not ok then logWarn("FireRedMain: refreshHumans failed: %s",
      tostring(err)) end
  end

  -- ------------------------------------------------------------------
  -- Species pools (filtered against Game.data.pokemon at install time).
  -- ------------------------------------------------------------------
  local KANTO_DEX = {
    "BULBASAUR","IVYSAUR","VENUSAUR","CHARMANDER","CHARMELEON","CHARIZARD",
    "SQUIRTLE","WARTORTLE","BLASTOISE","CATERPIE","METAPOD","BUTTERFREE",
    "WEEDLE","KAKUNA","BEEDRILL","PIDGEY","PIDGEOTTO","PIDGEOT","RATTATA",
    "RATICATE","SPEAROW","FEAROW","EKANS","ARBOK","PIKACHU","RAICHU",
    "SANDSHREW","SANDSLASH","NIDORAN_F","NIDORINA","NIDOQUEEN","NIDORAN_M",
    "NIDORINO","NIDOKING","CLEFAIRY","CLEFABLE","VULPIX","NINETALES",
    "JIGGLYPUFF","WIGGLYTUFF","ZUBAT","GOLBAT","ODDISH","GLOOM","VILEPLUME",
    "PARAS","PARASECT","VENONAT","VENOMOTH","DIGLETT","DUGTRIO","MEOWTH",
    "PERSIAN","PSYDUCK","GOLDUCK","MANKEY","PRIMEAPE","GROWLITHE","ARCANINE",
    "POLIWAG","POLIWHIRL","POLIWRATH","ABRA","KADABRA","ALAKAZAM","MACHOP",
    "MACHOKE","MACHAMP","BELLSPROUT","WEEPINBELL","VICTREEBEL","TENTACOOL",
    "TENTACRUEL","GEODUDE","GRAVELER","GOLEM","PONYTA","RAPIDASH","SLOWPOKE",
    "SLOWBRO","MAGNEMITE","MAGNETON","FARFETCH_D","DODUO","DODRIO","SEEL",
    "DEWGONG","GRIMER","MUK","SHELLDER","CLOYSTER","GASTLY","HAUNTER","GENGAR",
    "ONIX","DROWZEE","HYPNO","KRABBY","KINGLER","VOLTORB","ELECTRODE",
    "EXEGGCUTE","EXEGGUTOR","CUBONE","MAROWAK","HITMONLEE","HITMONCHAN",
    "LICKITUNG","KOFFING","WEEZING","RHYHORN","RHYDON","CHANSEY","TANGELA",
    "KANGASKHAN","HORSEA","SEADRA","GOLDEEN","SEAKING","STARYU","STARMIE",
    "MR_MIME","SCYTHER","JYNX","ELECTABUZZ","MAGMAR","PINSIR","TAUROS",
    "MAGIKARP","GYARADOS","LAPRAS","DITTO","EEVEE","VAPOREON","JOLTEON",
    "FLAREON","PORYGON","OMANYTE","OMASTAR","KABUTO","KABUTOPS","AERODACTYL",
    "SNORLAX","ARTICUNO","ZAPDOS","MOLTRES","DRATINI","DRAGONAIR","DRAGONITE",
    "MEWTWO","MEW",
  }
  local HOENN_DEX = {
    "TREECKO","GROVYLE","SCEPTILE","TORCHIC","COMBUSKEN","BLAZIKEN",
    "MUDKIP","MARSHTOMP","SWAMPERT","POOCHYENA","MIGHTYENA","ZIGZAGOON",
    "LINOONE","WURMPLE","SILCOON","BEAUTIFLY","CASCOON","DUSTOX","LOTAD",
    "LOMBRE","LUDICOLO","SEEDOT","NUZLEAF","SHIFTRY","TAILLOW","SWELLOW",
    "WINGULL","PELIPPER","RALTS","KIRLIA","GARDEVOIR","SURSKIT","MASQUERAIN",
    "SHROOMISH","BRELOOM","SLAKOTH","VIGOROTH","SLAKING","NINCADA","NINJASK",
    "SHEDINJA","WHISMUR","LOUDRED","EXPLOUD","MAKUHITA","HARIYAMA","AZURILL",
    "NOSEPASS","SKITTY","DELCATTY","SABLEYE","MAWILE","ARON","LAIRON",
    "AGGRON","MEDITITE","MEDICHAM","ELECTRIKE","MANECTRIC","PLUSLE","MINUN",
    "VOLBEAT","ILLUMISE","ROSELIA","GULPIN","SWALOT","CARVANHA","SHARPEDO",
    "WAILMER","WAILORD","NUMEL","CAMERUPT","TORKOAL","SPOINK","GRUMPIG",
    "SPINDA","TRAPINCH","VIBRAVA","FLYGON","CACNEA","CACTURNE","SWABLU",
    "ALTARIA","ZANGOOSE","SEVIPER","LUNATONE","SOLROCK","BARBOACH","WHISCASH",
    "CORPHISH","CRAWDAUNT","BALTOY","CLAYDOL","LILEEP","CRADILY","ANORITH",
    "ARMALDO","FEEBAS","MILOTIC","CASTFORM","KECLEON","SHUPPET","BANETTE",
    "DUSKULL","DUSCLOPS","TROPIUS","CHIMECHO","ABSOL","WYNAUT","SNORUNT",
    "GLALIE","SPHEAL","SEALEO","WALREIN","CLAMPERL","HUNTAIL","GOREBYSS",
    "RELICANTH","LUVDISC","BAGON","SHELGON","SALAMENCE","BELDUM","METANG",
    "METAGROSS","REGIROCK","REGICE","REGISTEEL","LATIAS","LATIOS","KYOGRE",
    "GROUDON","RAYQUAZA","JIRACHI","DEOXYS",
  }

  local function filterSpecies(list)
    local game = getGame()
    local data = game and game.data and game.data.pokemon
    if not data then return {} end -- filtered later at spawn; keep raw
    local out = {}
    for _, s in ipairs(list) do
      if data[s] ~= nil then out[#out + 1] = s end
    end
    return out
  end

  local dexPool = {}
  for _, s in ipairs(KANTO_DEX) do dexPool[#dexPool + 1] = s end
  if isEmerald then
    for _, s in ipairs(HOENN_DEX) do dexPool[#dexPool + 1] = s end
  end
  A.pokemonSpecies = filterSpecies(dexPool)
  if #A.pokemonSpecies == 0 then
    -- game data not ready at install time; keep the raw pool and let
    -- spawn-time filtering drop unknown ids.
    A.pokemonSpecies = dexPool
  end

  A.flySpecies = filterSpecies({
    "PIDGEOT","FEAROW","DODRIO","AERODACTYL","CHARIZARD","MOLTRES",
    "ZAPDOS","ARTICUNO","DRAGONITE","NOCTOWL","SKARMORY","PELIPPER",
    "SWELLOW","XATU",
  })
  A.psychicSpecies = filterSpecies({
    "KADABRA","ALAKAZAM","HYPNO","MR_MIME","ESPEON","XATU","MEWTWO",
    "NATU","ABRA","DROWZEE",
  })

  -- ------------------------------------------------------------------
  -- Gift items / TMs (filtered against Game.data.items at install time).
  -- ------------------------------------------------------------------
  local GIFT_ITEMS = {
    "POTION","SUPER_POTION","HYPER_POTION","MAX_POTION","FULL_RESTORE",
    "FULL_HEAL","REVIVE","MAX_REVIVE","ANTIDOTE","AWAKENING","BURN_HEAL",
    "ICE_HEAL","PARLYZ_HEAL","POKE_BALL","GREAT_BALL","ULTRA_BALL",
    "REPEL","SUPER_REPEL","MAX_REPEL","ESCAPE_ROPE","RARE_CANDY","NUGGET",
    "BIG_PEARL","STARDUST","HEART_SCALE","MOON_STONE","FIRE_STONE",
    "WATER_STONE","THUNDER_STONE","LEAF_STONE","SUN_STONE","PROTEIN",
    "IRON","CALCIUM","ZINC","CARBOS","HP_UP","PP_UP","PP_MAX",
  }
  local GIFT_TMS = {}
  for i = 1, 50 do
    GIFT_TMS[#GIFT_TMS + 1] = ("TM%02d"):format(i)
  end

  local function filterItems(list)
    local game = getGame()
    local data = game and game.data and game.data.items
    if not data then return {} end
    local out = {}
    for _, id in ipairs(list) do
      if data[id] ~= nil then out[#out + 1] = id end
    end
    return out
  end

  A.giftItems = filterItems(GIFT_ITEMS)
  A.giftTMs = filterItems(GIFT_TMS)
  if #A.giftItems == 0 then A.giftItems = GIFT_ITEMS end -- spawn-time filter
  if #A.giftTMs == 0 then A.giftTMs = GIFT_TMS end

  -- ------------------------------------------------------------------
  function A.isOutdoor(mapDef)
    local ok, Map = pcall(function()
      return mod.engineRequire("src.world.Map")
    end)
    if ok and Map and Map.isOutdoor then
      local ok2, v = pcall(Map.isOutdoor, mapDef)
      if ok2 and v ~= nil then return v and true or false end
    end
    return false
  end

  local AmbientCore, err = loadBundled("lib/AmbientCore.lua")
  if type(AmbientCore) ~= "table" or type(AmbientCore.install) ~= "function" then
    logWarn("FireRedMain: AmbientCore failed to load: %s", tostring(err))
    return { shutdown = function() end }
  end
  return AmbientCore.install(mod, A)
end
