local internet = require("internet")
local filesystem = require("filesystem")
local computer = require("computer")

local REPO = "https://raw.githubusercontent.com/Daniel-Arsenio/GTNHOCWaterline/main/"
local DEST = "/home/waterline/"

local FILES = {
  "gtutil.lua", "cycle.lua", "defaults.lua", "settings.lua", "ui.lua",
  "power.lua", "stock.lua",
  "watch.lua", "t2.lua", "t3.lua", "t4.lua",
  "run.lua", "probe.lua", "craftables.lua", "discover.lua", "check.lua", "levels.lua", "install.lua",
}

local ONCE = { "config.lua" }

local function fetch(name)
  local url = REPO .. name .. "?nocache=" .. tostring(math.floor(computer.uptime() * 1000))
  local chunks = {}
  local ok, err = pcall(function()
    for chunk in internet.request(url) do chunks[#chunks + 1] = chunk end
  end)
  if not ok then return nil, tostring(err) end
  local body = table.concat(chunks)
  if #body == 0 then return nil, "empty response" end
  if body:sub(1, 3) == "404" then return nil, "not found in repo" end
  local loaded, syntax = load(body, "=" .. name)
  if not loaded then return nil, "downloaded file is not valid Lua: " .. tostring(syntax) end
  return body
end

local function write(name, body)
  local file, err = io.open(DEST .. name, "w")
  if not file then return false, tostring(err) end
  file:write(body)
  file:close()
  return true
end

if not filesystem.exists(DEST) then filesystem.makeDirectory(DEST) end

local failed = 0

for _, name in ipairs(FILES) do
  local body, err = fetch(name)
  if body then
    local ok, werr = write(name, body)
    print((ok and "  updated " or "  FAILED  ") .. name .. (ok and "" or " " .. werr))
    if not ok then failed = failed + 1 end
  else
    print("  FAILED  " .. name .. " " .. err)
    failed = failed + 1
  end
end

for _, name in ipairs(ONCE) do
  if filesystem.exists(DEST .. name) then
    print("  kept    " .. name)
  else
    local body, err = fetch(name)
    if body and write(name, body) then
      print("  created " .. name .. ", fill in the addresses before running")
    else
      print("  FAILED  " .. name .. " " .. tostring(err))
      failed = failed + 1
    end
  end
end

if failed == 0 then
  print("done, run " .. DEST .. "probe.lua")
else
  print(failed .. " file(s) failed, nothing was partially written")
end
