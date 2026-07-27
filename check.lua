local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui
local component = require("component")

local TARGETS = {
  { "cycleAddress", cfg.cycleAddress, "getWorkProgress" },
  { "stock.interface", cfg.stock.interfaceAddress, "getCraftables" },
  { "t2.interface", cfg.t2.interfaceAddress, "getFluidsInNetwork" },
  { "watch.interface", cfg.watch.interfaceAddress, "getFluidsInNetwork" },
  { "t1.unit", cfg.t1.unitAddress, "hasWork" },
  { "t2.unit", cfg.t2.unitAddress, "hasWork" },
  { "t3.unit", cfg.t3.unitAddress, "getSensorInformation" },
  { "t4.unit", cfg.t4.unitAddress, "getSensorInformation" },
  { "t3.transposer", cfg.t3.transposerAddress, "transferFluid" },
  { "t4.acid.transposer", cfg.t4.acid.transposerAddress, "transferFluid" },
  { "t4.base.transposer", cfg.t4.base.transposerAddress, "transferItem" },
}

local SAFE = {
  getWorkProgress = true, getCraftables = true,
  getFluidsInNetwork = true, hasWork = true, getSensorInformation = true,
}

local function first(a)
  if type(a) == "table" then return a[1] end
  return a
end

local rows, unset = {}, {}

for _, t in ipairs(TARGETS) do
  local field, address, method = t[1], first(t[2]), t[3]

  if address == nil or address == "" then
    unset[#unset + 1] = field
  else
    local resolved, ctype, result, colour = address, "-", nil, tui.c.bad

    if #address < 36 then
      local ok, full = pcall(component.get, address)
      resolved = (ok and type(full) == "string") and full or nil
    end

    if resolved == nil then
      result = "UNRESOLVED"
    else
      local okT, t2 = pcall(component.type, resolved)
      if okT and type(t2) == "string" then ctype = t2 end

      local ok, dev = pcall(component.proxy, resolved)
      if not ok then
        result = "DRIVER THREW"
      elseif dev == nil then
        result = "NO PROXY"
      elseif dev[method] == nil and gt.methods(resolved)[method] == nil then
        result = "MISSING " .. method
      elseif SAFE[method] then
        local called, value = pcall(dev[method])
        if not called then
          result = method .. " THREW"
        else
          colour = tui.c.ok
          result = string.format("%s = %s", method,
            type(value) == "table" and (#value .. " entries") or tostring(value))
        end
      else
        colour = tui.c.ok
        result = method .. " present"
      end
    end

    rows[#rows + 1] = { field, address:sub(1, 8), ctype, result, colour }
  end
end

tui.header("component check", #rows .. " configured, " .. #unset .. " unset")

if cfg.__issues and #cfg.__issues > 0 then
  tui.line(tui.c.warn, #cfg.__issues .. " unrecognised key(s) in config.lua, ignored")
  tui.columns(cfg.__issues, tui.c.dim)
  io.write("\n")
end

tui.write(tui.c.dim, tui.pad("field", 20) .. tui.pad("prefix", 10) .. tui.pad("type", 18) .. "result")
tui.reset()
io.write("\n")

for _, r in ipairs(rows) do
  tui.write(tui.c.val, tui.pad(r[1], 20))
  tui.write(tui.c.accent, tui.pad(r[2], 10))
  tui.write(tui.c.key, tui.pad(r[3], 18))
  tui.write(r[5], r[4])
  tui.reset()
  io.write("\n")
end

if #unset > 0 then
  io.write("\n")
  tui.line(tui.c.dim, "unset  ", tui.c.dim, table.concat(unset, "  "))
end
