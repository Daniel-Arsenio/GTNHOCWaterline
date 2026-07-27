local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
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

local function first(address)
  if type(address) == "table" then return address[1] end
  return address
end

local rows, unset = {}, {}

for _, t in ipairs(TARGETS) do
  local field, address, method = t[1], first(t[2]), t[3]

  if address == nil or address == "" then
    unset[#unset + 1] = field
  else
    local resolved, ctype, result = address, "-", nil

    if #address < 36 then
      local ok, full = pcall(component.get, address)
      if ok and type(full) == "string" then resolved = full else resolved = nil end
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
        elseif type(value) == "table" then
          result = string.format("ok  %s=%d", method, #value)
        else
          result = string.format("ok  %s=%s", method, tostring(value))
        end
      else
        result = "ok  " .. method
      end
    end

    rows[#rows + 1] = { field, address:sub(1, 8), ctype, result }
  end
end

if cfg.__issues and #cfg.__issues > 0 then
  print("config.lua has " .. #cfg.__issues .. " unrecognised key(s):")
  print("  " .. table.concat(cfg.__issues, " "))
  print("")
end

print(string.format("%-19s %-9s %-16s %s", "field", "prefix", "type", "result"))
for _, r in ipairs(rows) do
  print(string.format("%-19s %-9s %-16s %s", r[1], r[2], r[3], r[4]))
end

if #unset > 0 then
  print("")
  print("unset: " .. table.concat(unset, " "))
end
