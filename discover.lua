local BASE = "/home/waterline/"
local gt = dofile(BASE .. "gtutil.lua")
local component = require("component")

local function isRelevant(ctype)
  return ctype == "gt_machine" or ctype == "transposer"
    or ctype:sub(1, 3) == "me_" or ctype:find("interface", 1, true) ~= nil
end

local function describe(address, ctype)
  local ok, dev = pcall(component.proxy, address)
  if not ok then return "unreadable" end

  if ctype == "gt_machine" then
    local okName, name = pcall(dev.getName)
    if okName and type(name) == "string" and #name > 0 then return name end
    local info = gt.sensor(dev)
    return info[1] or ctype
  end

  if ctype:sub(1, 3) == "me_" or ctype:find("interface", 1, true) then
    local function count(method)
      local okC, r = pcall(dev[method])
      return (okC and type(r) == "table") and #r or "-"
    end
    return string.format("craft=%s fluids=%s cpus=%s",
      count("getCraftables"), count("getFluidsInNetwork"), count("getCpus"))
  end

  if ctype == "transposer" then
    local bits = {}
    for side = 0, 5 do
      local okC, tanks = pcall(dev.getTankCount, side)
      for tank = 1, (okC and tanks or 0) do
        local okT, f = pcall(dev.getFluidInTank, side, tank)
        if okT and type(f) == "table" and (f.capacity or 0) > 0 then
          bits[#bits + 1] = string.format("%s(%d) %s %s/%s", gt.SIDE_NAME[side], side,
            gt.short(f.name or "empty", 22), gt.num(f.amount or 0), gt.num(f.capacity))
        end
      end
      local okS, stacks = pcall(dev.getAllStacks, side)
      if okS and stacks ~= nil then
        bits[#bits + 1] = string.format("%s(%d) inv", gt.SIDE_NAME[side], side)
      end
    end
    return #bits > 0 and table.concat(bits, "  ") or "nothing attached"
  end

  return ctype
end

local rows, others = {}, {}

for address, ctype in component.list() do
  if isRelevant(ctype) then
    rows[#rows + 1] = { a = address, t = ctype, d = describe(address, ctype) }
  else
    others[ctype] = (others[ctype] or 0) + 1
  end
end

table.sort(rows, function(a, b)
  if a.t ~= b.t then return a.t < b.t end
  return a.d < b.d
end)

print(string.format("%-9s %-16s %s", "prefix", "type", "identity"))
for _, r in ipairs(rows) do
  print(string.format("%-9s %-16s %s", r.a:sub(1, 8), r.t, r.d))
end

local list = {}
for ctype, n in pairs(others) do
  list[#list + 1] = ctype .. (n > 1 and ("x" .. n) or "")
end
table.sort(list)

print("")
print("other: " .. table.concat(list, " "))
print("paste any prefix into config.lua, full addresses are not needed")
