local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui

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
  if type(list) ~= "table" then return "err", tui.c.bad end
  if #list == 0 then return "NONE", tui.c.bad end
  return "yes", tui.c.ok
end

tui.header("supply levels", cfg.stock.enabled and "stock enabled" or "stock disabled")

tui.write(tui.c.dim, tui.pad("entry", 24) .. tui.pad("network", 11, true)
  .. tui.pad("target", 11, true) .. "  " .. tui.pad("craft", 7) .. tui.pad("mode", 7) .. "state")
tui.reset()
io.write("\n")

for _, entry in ipairs(cfg.stock.entries) do
  local have = amountOf(entry)
  local craft, craftColour = craftable(entry)
  local low = have ~= nil and have < entry.target

  tui.write(tui.c.val, tui.pad(entry.key, 24))
  tui.write(low and tui.c.warn or tui.c.ok,
    tui.pad(have == nil and "?" or gt.num(have), 11, true))
  tui.write(tui.c.dim, tui.pad(gt.num(entry.target), 11, true) .. "  ")
  tui.write(craftColour, tui.pad(craft, 7))
  tui.write(entry.alarmOnly and tui.c.accent or tui.c.dim, tui.pad(entry.alarmOnly and "alarm" or "craft", 7))
  tui.write(low and tui.c.warn or tui.c.ok, low and "LOW" or "ok")
  tui.reset()
  io.write("\n")
end

io.write("\n")
tui.line(tui.c.dim, "NONE means it can never be requested, fix the filter with craftables.lua")
