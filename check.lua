local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local component = require("component")

local TARGETS = {
  { "cycleAddress", cfg.cycleAddress, "getWorkProgress" },
  { "stock.interfaceAddress", cfg.stock.interfaceAddress, "getCraftables" },
  { "t2.interfaceAddress", cfg.t2.interfaceAddress, "getFluidsInNetwork" },
  { "t1.unitAddress", cfg.t1.unitAddress, "isMachineActive" },
  { "t2.unitAddress", cfg.t2.unitAddress, "isMachineActive" },
  { "t4.unitAddress", cfg.t4.unitAddress, "getSensorInformation" },
  { "t3.transposerAddress", cfg.t3.transposerAddress, "transferFluid" },
  { "t4.acid.transposerAddress", cfg.t4.acid.transposerAddress, "transferFluid" },
  { "t4.base.transposerAddress", cfg.t4.base.transposerAddress, "transferItem" },
}

local SAFE_CALL = {
  getWorkProgress = true,
  getCraftables = true,
  getFluidsInNetwork = true,
  isMachineActive = true,
  getSensorInformation = true,
}

local function report(field, address, method)
  if address == nil or address == "" then
    print(string.format("%-28s not set", field))
    return
  end

  local resolved = address
  if #address < 36 then
    local ok, full, reason = pcall(component.get, address)
    if not ok or type(full) ~= "string" then
      print(string.format("%-28s %-10s UNRESOLVED %s", field, address, tostring(full or reason)))
      return
    end
    resolved = full
  end

  local ctype = "unknown"
  local okType, t = pcall(component.type, resolved)
  if okType and type(t) == "string" then ctype = t end

  local ok, dev, reason = pcall(component.proxy, resolved)
  if not ok then
    print(string.format("%-28s %-10s %-14s DRIVER THREW %s",
      field, resolved:sub(1, 8), ctype, tostring(dev)))
    return
  end
  if dev == nil then
    print(string.format("%-28s %-10s %-14s NO PROXY %s",
      field, resolved:sub(1, 8), ctype, tostring(reason)))
    return
  end

  local methods = gt.methods(resolved)
  if dev[method] == nil and methods[method] == nil then
    local names = {}
    for name in pairs(methods) do names[#names + 1] = name end
    table.sort(names)
    print(string.format("%-28s %-10s %-14s MISSING %s, has: %s",
      field, resolved:sub(1, 8), ctype, method, table.concat(names, " ")))
    return
  end

  if SAFE_CALL[method] then
    local called, result = pcall(dev[method])
    if not called then
      print(string.format("%-28s %-10s %-14s %s THREW %s",
        field, resolved:sub(1, 8), ctype, method, tostring(result)))
      return
    end
    local shown
    if type(result) == "table" then
      shown = #result .. " entries"
    else
      shown = tostring(result)
    end
    print(string.format("%-28s %-10s %-14s ok, %s = %s",
      field, resolved:sub(1, 8), ctype, method, shown))
    return
  end

  print(string.format("%-28s %-10s %-14s ok, %s present",
    field, resolved:sub(1, 8), ctype, method))
end

print(string.format("%-28s %-10s %-14s %s", "field", "prefix", "type", "result"))
for _, t in ipairs(TARGETS) do
  report(t[1], t[2], t[3])
end
