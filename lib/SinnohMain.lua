-- lib/SinnohMain.lua — Gen 4 (Platinum) installer for the Kanto Life
-- ambient-NPC engine.
--
-- Gen 4 (Platinum) is experimental in Gen2Recomped; NPC features here are
-- implemented against the same world API but have not been verified in-game.
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

  -- ------------------------------------------------------------------
  -- Human sprites: runtime discovery ONLY. Gen 4 object defs carry
  -- def.spriteName (e.g. "youngster", "pikachu"; set by RomExtractorGen4).
  -- A name matching a species id classifies the def as a Pokemon sprite,
  -- anything else as human. There is no static fallback: without the
  -- ROM's object table, member ids cannot be known, so on a map with no
  -- vanilla NPCs nothing spawns (fail-open) rather than guessing ids.
  -- ------------------------------------------------------------------
  local A = {
    id = "kl4",
    gen = 4,
    label = "Sinnoh",
    humanSprites = {},
  }

  local discovered = {}

  function A.refreshHumans()
    local ok, err = pcall(function()
      local game = getGame()
      local ow = mod.world:overworld()
      if not (ow and ow.npcs) then return end
      -- species set for classification
      local speciesSet = {}
      if game and game.data and game.data.pokemon then
        for k in pairs(game.data.pokemon) do
          speciesSet[tostring(k):upper()] = true
        end
      end
      for _, n in ipairs(ow.npcs) do
        local def = n.def
        if def and not def.kantoLifeAmbient then
          local sid = def.sprite
          local sname = def.spriteName
          if type(sid) == "string" and not discovered[sid] then
            local isPoke = type(sname) == "string"
              and speciesSet[sname:upper()] == true
            discovered[sid] = true
            if not isPoke then
              A.humanSprites[#A.humanSprites + 1] = { sid, nil }
            end
          end
        end
      end
    end)
    if not ok then logWarn("SinnohMain: refreshHumans failed: %s",
      tostring(err)) end
  end

  -- ------------------------------------------------------------------
  -- Species pools (filtered against Game.data.pokemon at install time).
  -- Sinnoh dex 387-493 plus the earlier generations (Platinum carries
  -- the national dex in data; unknown ids are dropped by the filter).
  -- ------------------------------------------------------------------
  local SINNOH_DEX = {
    "TURTWIG","GROTLE","TORTERRA","CHIMCHAR","MONFERNO","INFERNAPE",
    "PIPLUP","PRINPLUP","EMPOLEON","STARLY","STARAVIA","STARAPTOR",
    "BIDOOF","BIBAREL","KRICKETOT","KRICKETUNE","SHINX","LUXIO","LUXRAY",
    "BUDEW","ROSERADE","CRANIDOS","RAMPARDOS","SHIELDON","BASTIODON",
    "BURMY","WORMADAM","MOTHIM","COMBEE","VESPIQUEN","PACHIRISU","BUIZEL",
    "FLOATZEL","CHERUBI","CHERRIM","SHELLOS","GASTRODON","AMBIPOM",
    "DRIFLOON","DRIFBLIM","BUNEARY","LOPUNNY","MISMAGIUS","HONCHKROW",
    "GLAMEOW","PURUGLY","CHINGLING","STUNKY","SKUNTANK","BRONZOR","BRONZONG",
    "BONSLY","MIME_JR","HAPPINY","CHATOT","SPIRITOMB","GIBLE","GABITE",
    "GARCHOMP","MUNCHLAX","RIOLU","LUCARIO","HIPPOPOTAS","HIPPOWDON",
    "SKORUPI","DRAPION","CROAGUNK","TOXICROAK","CARNIVINE","FINNEON",
    "LUMINEON","MANTYKE","SNOVER","ABOMASNOW","WEAVILE","MAGNEZONE",
    "LICKILICKY","RHYPERIOR","TANGROWTH","ELECTIVIRE","MAGMORTAR",
    "TOGEKISS","YANMEGA","LEAFEON","GLACEON","GLISCOR","MAMOSWINE",
    "PORYGON_Z","GALLADE","PROBOPASS","DUSKNOIR","FROSLASS","ROTOM",
    "UXIE","MESPRIT","AZELF","DIALGA","PALKIA","HEATRAN","REGIGIGAS",
    "GIRATINA","CRESSELIA","PHIONE","MANAPHY","DARKRAI","SHAYMIN","ARCEUS",
  }
  -- Earlier generations for trade/battle variety.
  local EARLIER_DEX = {
    "BULBASAUR","IVYSAUR","VENUSAUR","CHARMANDER","CHARMELEON","CHARIZARD",
    "SQUIRTLE","WARTORTLE","BLASTOISE","PIDGEY","PIDGEOT","RATTATA",
    "SPEAROW","FEAROW","PIKACHU","RAICHU","SANDSHREW","NIDORAN_F",
    "NIDORAN_M","CLEFAIRY","VULPIX","JIGGLYPUFF","ZUBAT","ODDISH","PARAS",
    "VENONAT","DIGLETT","MEOWTH","PSYDUCK","MANKEY","GROWLITHE","POLIWAG",
    "ABRA","KADABRA","ALAKAZAM","MACHOP","BELLSPROUT","TENTACOOL","GEODUDE",
    "PONYTA","SLOWPOKE","MAGNEMITE","FARFETCH_D","DODUO","DODRIO","SEEL",
    "GRIMER","SHELLDER","GASTLY","ONIX","DROWZEE","HYPNO","KRABBY","VOLTORB",
    "EXEGGCUTE","CUBONE","KOFFING","RHYHORN","CHANSEY","TANGELA","HORSEA",
    "GOLDEEN","STARYU","MR_MIME","SCYTHER","JYNX","ELECTABUZZ","MAGMAR",
    "PINSIR","TAUROS","MAGIKARP","GYARADOS","LAPRAS","DITTO","EEVEE",
    "PORYGON","OMANYTE","KABUTO","AERODACTYL","SNORLAX","ARTICUNO","ZAPDOS",
    "MOLTRES","DRATINI","DRAGONITE","MEWTWO","MEW",
    "CHIKORITA","CYNDAQUIL","TOTODILE","SENTRET","HOOTHOOT","LEDYBA",
    "SPINARAK","CHINCHOU","PICHU","CLEFFA","TOGEPI","NATU","MAREEP","MARILL",
    "HOPPIP","AIPOM","SUNKERN","YANMA","WOOPER","MURKROW","MISDREAVUS",
    "GIRAFARIG","DUNSPARCE","GLIGAR","SNUBBULL","QWILFISH","SHUCKLE",
    "HERACROSS","SNEASEL","TEDDIURSA","SWINUB","CORSOLA","REMORAID",
    "DELIBIRD","SKARMORY","HOUNDOUR","PHANPY","STANTLER","SMEARGLE",
    "MILTANK","LARVITAR","RAIKOU","ENTEI","SUICUNE","LUGIA","HO_OH","CELEBI",
    "TREECKO","TORCHIC","MUDKIP","POOCHYENA","ZIGZAGOON","WURMPLE","LOTAD",
    "SEEDOT","TAILLOW","SWELLOW","WINGULL","PELIPPER","RALTS","GARDEVOIR",
    "SHROOMISH","SLAKOTH","WHISMUR","MAKUHITA","AZURILL","SKITTY","SABLEYE",
    "MAWILE","ARON","MEDITITE","ELECTRIKE","PLUSLE","MINUN","VOLBEAT",
    "ROSELIA","GULPIN","CARVANHA","WAILMER","NUMEL","TORKOAL","SPOINK",
    "SPINDA","TRAPINCH","CACNEA","SWABLU","ALTARIA","ZANGOOSE","SEVIPER",
    "LUNATONE","SOLROCK","BARBOACH","CORPHISH","BALTOY","LILEEP","ANORITH",
    "FEEBAS","MILOTIC","CASTFORM","KECLEON","SHUPPET","DUSKULL","TROPIUS",
    "ABSOL","SNORUNT","SPHEAL","CLAMPERL","RELICANTH","LUVDISC","BAGON",
    "BELDUM","REGIROCK","REGICE","REGISTEEL","LATIAS","LATIOS","KYOGRE",
    "GROUDON","RAYQUAZA","JIRACHI",
  }

  local function filterSpecies(list)
    local game = getGame()
    local data = game and game.data and game.data.pokemon
    if not data then return {} end
    local out = {}
    for _, s in ipairs(list) do
      if data[s] ~= nil then out[#out + 1] = s end
    end
    return out
  end

  local dexPool = {}
  for _, s in ipairs(SINNOH_DEX) do dexPool[#dexPool + 1] = s end
  for _, s in ipairs(EARLIER_DEX) do dexPool[#dexPool + 1] = s end
  A.pokemonSpecies = filterSpecies(dexPool)
  if #A.pokemonSpecies == 0 then
    A.pokemonSpecies = dexPool -- spawn-time filtering drops unknown ids
  end

  A.flySpecies = filterSpecies({
    "STARAPTOR","PELIPPER","DRIFBLIM","TOGEKISS","HONCHKROW","CHATOT",
    "CROBAT","SKARMORY","PIDGEOT","FEAROW","NOCTOWL","XATU",
  })
  A.psychicSpecies = filterSpecies({
    "BRONZOR","BRONZONG","CHINGLING","MISMAGIUS","UXIE","MESPRIT","AZELF",
    "GALLADE","MR_MIME","ESPEON","KADABRA","ALAKAZAM",
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
    "WATER_STONE","THUNDER_STONE","LEAF_STONE","SUN_STONE","SHINY_STONE",
    "DUSK_STONE","DAWN_STONE","OVAL_STONE","PROTEIN","IRON","CALCIUM",
    "ZINC","CARBOS","HP_UP","PP_UP","PP_MAX",
  }
  local GIFT_TMS = {}
  for i = 1, 92 do
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
  if #A.giftItems == 0 then A.giftItems = GIFT_ITEMS end
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
    logWarn("SinnohMain: AmbientCore failed to load: %s", tostring(err))
    return { shutdown = function() end }
  end
  return AmbientCore.install(mod, A)
end
