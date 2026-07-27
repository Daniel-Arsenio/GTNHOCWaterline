local component = require("component")
local computer = require("computer")

local gt = {}

function gt.proxy(address, label)
  label = label or "component"
  if type(address) ~= "string" or #address < 3 then
    error(label .. ": address not configured in config.lua", 0)
  end

  local resolved = address
  if #address < 36 then
    local ok, full = pcall(component.get, address)
    if not ok or type(full) ~= "string" then
      error(label .. ': no unique component matches "' .. address .. '"', 0)
    end
    resolved = full
  end

  local ok, dev = pcall(component.proxy, resolved)
  if not ok or not dev then
    error(label .. ": cannot proxy " .. resolved, 0)
  end
  return dev
end

function gt.clean(text)
  if type(text) ~= "string" then return "" end
  return (text:gsub("\194\167.", ""):gsub("\167.", ""))
end

function gt.sensor(machine)
  local ok, info = pcall(machine.getSensorInformation)
  if not ok or type(info) ~= "table" then return {} end
  local out = {}
  for i = 1, #info do out[i] = gt.clean(info[i]) end
  return out
end

function gt.matchNumber(info, pattern)
  for i = 1, #info do
    local value = info[i]:lower():match(pattern)
    if value then
      local n = tonumber((value:gsub(",", "")))
      if n then return n, i end
    end
  end
  return nil
end

function gt.call(machine, method, default, ...)
  local fn = machine[method]
  if type(fn) ~= "function" then return default end
  local ok, value = pcall(fn, ...)
  if not ok then return default end
  return value
end

function gt.tankTotals(transposer, side)
  local ok, tanks = pcall(transposer.getFluidInTank, side)
  local amount, capacity = 0, 0
  if ok and type(tanks) == "table" then
    for _, t in ipairs(tanks) do
      amount = amount + (t.amount or 0)
      capacity = capacity + (t.capacity or 0)
    end
  end
  return amount, capacity
end

function gt.pushFluid(transposer, source, sink, want)
  if want <= 0 then return 0 end
  local ok, moved = transposer.transferFluid(source, sink, want)
  if ok ~= true then return 0 end
  if type(moved) ~= "number" then return want end
  return moved
end

function gt.countItems(transposer, side, label)
  local size = gt.call(transposer, "getInventorySize", 0, side) or 0
  local total = 0
  for slot = 1, size do
    local stack = gt.call(transposer, "getStackInSlot", nil, side, slot)
    if stack and (label == nil or stack.label == label or stack.name == label) then
      total = total + (stack.size or 0)
    end
  end
  return total
end

function gt.pushItems(transposer, source, sink, count, sourceSlot)
  local moved, guard = 0, 0
  while moved < count and guard < 32 do
    local n = transposer.transferItem(source, sink, math.min(64, count - moved), sourceSlot)
    if type(n) ~= "number" or n == 0 then break end
    moved = moved + n
    guard = guard + 1
  end
  return moved
end

function gt.log(enabled, fmt, ...)
  if not enabled then return end
  print(string.format("[%8.1f] " .. fmt, computer.uptime(), ...))
end

return gt
