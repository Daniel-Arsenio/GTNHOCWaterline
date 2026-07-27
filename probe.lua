local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local sides = require("sides")

local function dumpMachine(label, address)
  if address == nil or address == "" then return end
  print("=== machine " .. label .. " " .. address)
  local ok, machine = pcall(gt.proxy, address, label)
  if not ok then print("  " .. tostring(machine)) return end
  print(string.format("  work=%s progress=%s/%s allowed=%s",
    tostring(gt.call(machine, "hasWork", "n/a")),
    tostring(gt.call(machine, "getWorkProgress", "n/a")),
    tostring(gt.call(machine, "getWorkMaxProgress", "n/a")),
    tostring(gt.call(machine, "isWorkAllowed", "n/a"))))
  local info = gt.sensor(machine)
  for i = 1, #info do print(string.format("  [%2d] %s", i, info[i])) end
  local ph = gt.matchNumber(info, "ph[^%d%-]*(%d+%.?%d*)")
  if ph then print(string.format("  parsed pH = %.2f", ph)) end
  local par = gt.matchNumber(info, "parallel[^%d]*(%d+)")
  if par then print(string.format("  parsed parallels = %d", par)) end
  local names = {}
  for name in pairs(gt.methods(gt.resolve(address, label))) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    print("  methods: none reported")
  else
    local line = "  methods:"
    for _, name in ipairs(names) do
      if #line + #name + 1 > 78 then
        print(line)
        line = "   "
      end
      line = line .. " " .. name
    end
    print(line)
  end
  print("")
end

local function dumpTransposer(label, address)
  if address == nil or address == "" then return end
  print("=== transposer " .. label .. " " .. address)
  local ok, t = pcall(gt.proxy, address, label)
  if not ok then print("  " .. tostring(t)) return end
  for name, side in pairs(sides) do
    if type(side) == "number" and #name > 1 then
      local amount, capacity = gt.tankTotals(t, side)
      local slots = gt.call(t, "getInventorySize", nil, side)
      if capacity > 0 or (type(slots) == "number" and slots > 0) then
        print(string.format("  %-9s side=%d fluid=%d/%d slots=%s items=%d",
          name, side, amount, capacity, tostring(slots), gt.countItems(t, side, nil)))
      end
    end
  end
  print("")
end

dumpMachine("wpp", cfg.cycleAddress)
dumpMachine("t1 clarifier", cfg.t1.unitAddress)
dumpMachine("t2 ozonation", cfg.t2.unitAddress)
dumpMachine("t3 flocculation", cfg.t3.unitAddress)
dumpMachine("t4 ph", cfg.t4.unitAddress)

dumpTransposer("t3 flocculant", cfg.t3.transposerAddress)
dumpTransposer("t4 acid", cfg.t4.acid.transposerAddress)
dumpTransposer("t4 base", cfg.t4.base.transposerAddress)
