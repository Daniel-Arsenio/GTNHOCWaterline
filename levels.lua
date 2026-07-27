local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")

local me = gt.network(cfg.stock.interfaceAddress, "getItemsInNetwork", "stock.interfaceAddress")

local function amountOf(entry)
  if entry.kind == "fluid" then
    local list = gt.call(me, "getFluidsInNetwork", nil)
    if type(list) ~= "table" then return nil end
    for _, f in ipairs(list) do
      if f.label == entry.label or f.name == entry.label then return f.amount or 0 end
    end
    return 0
  end

  local list = gt.call(me, "getItemsInNetwork", nil, entry.filter)
  if type(list) ~= "table" then return nil end
  local total = 0
  for _, s in ipairs(list) do total = total + (s.size or 0) end
  return total
end

local function craftable(entry)
  local list = gt.call(me, "getCraftables", nil, entry.filter)
  if type(list) ~= "table" then return "error" end
  if #list == 0 then return "NO PATTERN" end
  return "yes (" .. #list .. ")"
end

print("stock.enabled = " .. tostring(cfg.stock.enabled))
print("")
print(string.format("%-24s %-6s %12s %12s %-12s %s",
  "entry", "kind", "in network", "target", "craftable", "mode"))

for _, entry in ipairs(cfg.stock.entries) do
  local have = amountOf(entry)
  local mode = entry.alarmOnly and "alarm only" or "auto craft"
  local state = ""

  if have == nil then
    state = "UNREADABLE"
  elseif have < entry.target then
    state = "BELOW TARGET"
  end

  print(string.format("%-24s %-6s %12s %12s %-12s %s %s",
    entry.key, entry.kind, tostring(have), tostring(entry.target),
    craftable(entry), mode, state))
end

print("")
print("a NO PATTERN entry can never be requested, check the filter with craftables.lua")
print("network levels only, buffer tanks and interfaces are checked by t3 and t4")
