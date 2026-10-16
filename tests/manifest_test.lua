-- tests/manifest_test.lua
-- Standalone: lua tests/manifest_test.lua
-- Verifies manifest.json identity/version/profile fields via a tiny
-- self-contained JSON parser (no external deps).
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local f = assert(io.open(HERE .. "../manifest.json", "r"))
local src = f:read("*a")
f:close()

-- Minimal JSON -> Lua parser (objects, arrays, strings, numbers, true/false/null).
local pos = 1
local function skipWs()
  pos = src:match("^%s*()", pos)
end
local parseValue
local function parseString()
  assert(src:sub(pos, pos) == '"', "expected string at " .. pos)
  pos = pos + 1
  local out = {}
  while true do
    local c = src:sub(pos, pos)
    if c == '"' then pos = pos + 1; return table.concat(out) end
    if c == "\\" then
      local e = src:sub(pos + 1, pos + 1)
      local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if map[e] then out[#out + 1] = map[e]; pos = pos + 2
      else out[#out + 1] = e; pos = pos + 2 end
    else
      out[#out + 1] = c; pos = pos + 1
    end
  end
end
local function parseArray()
  local t = {}
  pos = pos + 1; skipWs()
  if src:sub(pos, pos) == "]" then pos = pos + 1; return t end
  while true do
    t[#t + 1] = parseValue(); skipWs()
    local c = src:sub(pos, pos)
    pos = pos + 1
    if c == "]" then return t end
    assert(c == ",", "expected , or ] at " .. pos)
    skipWs()
  end
end
local function parseObject()
  local t = {}
  pos = pos + 1; skipWs()
  if src:sub(pos, pos) == "}" then pos = pos + 1; return t end
  while true do
    local k = parseString(); skipWs()
    assert(src:sub(pos, pos) == ":", "expected : at " .. pos)
    pos = pos + 1; skipWs()
    t[k] = parseValue(); skipWs()
    local c = src:sub(pos, pos)
    pos = pos + 1
    if c == "}" then return t end
    assert(c == ",", "expected , or } at " .. pos)
    skipWs()
  end
end
parseValue = function()
  skipWs()
  local c = src:sub(pos, pos)
  if c == "{" then return parseObject() end
  if c == "[" then return parseArray() end
  if c == '"' then return parseString() end
  if src:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
  if src:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
  if src:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
  local num = src:match("^(-?%d+%.?%d*)", pos)
  assert(num, "unexpected token at " .. pos)
  pos = pos + #num
  return tonumber(num)
end
local manifest = parseValue()
skipWs()
assert(pos > #src, "trailing garbage in manifest.json")

local failures = 0
local function check(cond, msg)
  if cond then
    print("PASS: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

check(manifest.id == "kantolife_gen2recomped", 'id == "kantolife_gen2recomped"')
check(manifest.api == 2, "api == 2")
check(manifest.version == "1.0.0", 'version == "1.0.0"')

local gens = manifest.generations
local gensOk = type(gens) == "table" and #gens == 4
if gensOk then
  for i, g in ipairs({ 1, 2, 3, 4 }) do
    if gens[i] ~= g then gensOk = false end
  end
end
check(gensOk, "generations == {1,2,3,4}")

local perms = manifest.permissions or {}
local hasEng = false
for _, p in ipairs(perms) do
  if p == "engine_internals" then hasEng = true end
end
check(hasEng, 'permissions contains "engine_internals"')
check(manifest.github == "jtfresh90/kantolife-gen2recomped",
  'github == "jtfresh90/kantolife-gen2recomped"')
check(manifest.profile == "content", 'profile == "content"')
check(manifest.category == "CONTENT", 'category == "CONTENT"')
check(manifest.entry == "main.lua", 'entry == "main.lua"')

if failures > 0 then
  print(failures .. " FAILURES")
  os.exit(1)
end
print("ALL MANIFEST TESTS PASSED")
