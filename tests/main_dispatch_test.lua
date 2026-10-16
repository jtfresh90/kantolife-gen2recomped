-- tests/main_dispatch_test.lua
-- Standalone: lua tests/main_dispatch_test.lua
-- Static analysis of main.lua: generation dispatch wiring.
-- main.lua is NOT executed (it requires a live mod object).
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local f = assert(io.open(HERE .. "../main.lua", "r"))
local src = f:read("*a")
f:close()

local failures = 0
local function check(cond, msg)
  if cond then
    print("PASS: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

for _, lib in ipairs({ "KantoMain", "JohtoMain", "FireRedMain", "SinnohMain" }) do
  check(src:find("lib/" .. lib .. ".lua", 1, true) ~= nil,
    "main.lua references lib/" .. lib .. ".lua")
end
check(src:find("gen%s*==%s*4", 1) ~= nil, "main.lua has a gen==4 branch (SinnohMain)")
check(src:find("gen%s*==%s*3", 1) ~= nil, "main.lua has a gen==3 branch (FireRedMain)")
check(src:find("gen%s*==%s*2", 1) ~= nil, "main.lua has a gen==2 branch (JohtoMain)")
check(src:find("gen%s*==%s*1", 1) ~= nil, "main.lua has a gen==1 branch (KantoMain)")
check(src:find("loadstring", 1, true) ~= nil, "loadstring-based loadLocal present")
check(src:find("G2RCompat", 1, true) ~= nil, "main.lua wires G2RCompat for gens 1/2")
check(src:find("InstallHygiene", 1, true) ~= nil, "main.lua runs InstallHygiene")

if failures > 0 then
  print(failures .. " FAILURES")
  os.exit(1)
end
print("ALL MAIN_DISPATCH TESTS PASSED")
