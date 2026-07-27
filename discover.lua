local BASE = "/home/waterline/"
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui
local component = require("component")

local function isRelevant(ctype)
  return ctype == "gt_machine" or ctype == "transposer"
    or ctype:sub(1, 3) == "me_" or ctype:find("interface", 1, true) ~= nil
end

local function describe(address, ctype)
  local ok, dev = pcall(component.proxy, address)
  if not ok then return "unreadable", tui.c.bad end

  if ctype == "gt_machine" then
    local okName, name = pcall(dev.getName)
    if okName and type(name) == "string" and #name > 0 then
      local colour = name:find("purification", 1, true) and tui.c.ok or tui.c.dim
      return name, colour
    end
    return (gt.sensor(dev)[1] or ctype), tui.c.dim
  end

  if ctype:sub(1, 3) == "me_" or ctype:find("interface", 1, true) then
    local function count(method)
      local okC, r = pcall(dev[method])
      return (okC and type(r) == "table") and #r or "-"
    end
    return string.format("craftables %s   fluids %s   cpus %s",
      count("getCraftables"), count("getFluidsInNetwork"), count("getCpus")), tui.c.ok
  end

  if ctype == "transposer" then
    local bits = {}
    for side = 0, 5 do
      local okC, tanks = pcall(dev.getTankCount, side)
      for tank = 1, (okC and tanks or 0) do
        local okT, f = pcall(dev.getFluidInTank, side, tank)
        if okT and type(f) == "table" and (f.capacity or 0) > 0 then
          bits[#bits + 1] = string.format("%s(%d) %s %s/%s", gt.SIDE_NAME[side], side,
            f.name or "empty", gt.num(f.amount or 0), gt.num(f.capacity))
        end
      end
      local okS, stacks = pcall(dev.getAllStacks, side)
      if okS and stacks ~= nil then
        bits[#bits + 1] = string.format("%s(%d) inventory", gt.SIDE_NAME[side], side)
      end
    end
    if #bits == 0 then return "nothing attached", tui.c.bad end
    return table.concat(bits, "   "), tui.c.text
  end

  return ctype, tui.c.dim
end

local rows, others = {}, {}

for address, ctype in component.list() do
  if isRelevant(ctype) then
    local text, colour = describe(address, ctype)
    rows[#rows + 1] = { a = address, t = ctype, d = text, c = colour }
  else
    others[ctype] = (others[ctype] or 0) + 1
  end
end

table.sort(rows, function(a, b)
  if a.t ~= b.t then return a.t < b.t end
  return a.d < b.d
end)

tui.header("components", #rows .. " usable")

for _, r in ipairs(rows) do
  tui.write(tui.c.accent, tui.pad(r.a:sub(1, 8), 10))
  tui.write(tui.c.key, tui.pad(r.t, 17))
  tui.write(r.c, r.d)
  tui.reset()
  io.write("\n")
end

local list = {}
for ctype, n in pairs(others) do
  list[#list + 1] = ctype .. (n > 1 and (" x" .. n) or "")
end
table.sort(list)

io.write("\n")
tui.line(tui.c.dim, "other  ", tui.c.dim, table.concat(list, "  "))
tui.line(tui.c.dim, "prefixes are enough for config.lua, full addresses are not needed")
