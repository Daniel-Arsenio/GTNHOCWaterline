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
  local list = gt.call(me, "getCraftables", nil, entry.craftFilter or entry.filter)
  if type(list) ~= "table" then return "err" end
  if #list == 0 then return "NONE" end
  return "yes"
end

print("stock " .. (cfg.stock.enabled and "ENABLED" or "disabled"))
print(string.format("%-22s %9s %9s %-5s %-6s %s",
  "entry", "network", "target", "craft", "mode", ""))

for _, entry in ipairs(cfg.stock.entries) do
  local have = amountOf(entry)
  print(string.format("%-22s %9s %9s %-5s %-6s %s",
    gt.short(entry.key, 22),
    have == nil and "?" or gt.num(have),
    gt.num(entry.target),
    craftable(entry),
    entry.alarmOnly and "alarm" or "craft",
    (have ~= nil and have < entry.target) and "LOW" or ""))
end

print("")
print("NONE means it can never be requested, fix filter with craftables.lua")
