local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui
local sides = require("sides")

local function dumpMachine(label, address)
  if address == nil or address == "" then return end
  tui.header(label, address)
  local ok, machine = pcall(gt.proxy, address, label)
  if not ok then tui.line(tui.c.bad, "  " .. tostring(machine)) return end
  tui.line(tui.c.key, "  work ", tui.c.val, tostring(gt.call(machine, "hasWork", "n/a")),
    tui.c.key, "   progress ", tui.c.val,
    tostring(gt.call(machine, "getWorkProgress", "n/a")) .. "/" ..
    tostring(gt.call(machine, "getWorkMaxProgress", "n/a")),
    tui.c.key, "   allowed ", tui.c.val, tostring(gt.call(machine, "isWorkAllowed", "n/a")))
  local info = gt.sensor(machine)
  for i = 1, #info do
    tui.write(tui.c.dim, string.format("  %2d  ", i))
    tui.write(tui.c.val, info[i])
    tui.reset()
    io.write("\n")
  end
  local ph = gt.matchNumber(info, "ph[^%d%-]*(%d+%.?%d*)")
  if ph then tui.line(tui.c.ok, string.format("  parsed pH = %.2f", ph)) end
  local names = {}
  for name in pairs(gt.methods(gt.resolve(address, label))) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    tui.line(tui.c.dim, "  methods: none reported")
  else
    tui.line(tui.c.dim, "  methods")
    tui.columns(names, tui.c.dim)
  end
  print("")
end

local function dumpTransposer(label, address)
  if address == nil or address == "" then return end
  tui.header("transposer " .. label, address)
  local ok, t = pcall(gt.proxy, address, label)
  if not ok then tui.line(tui.c.bad, "  " .. tostring(t)) return end
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
