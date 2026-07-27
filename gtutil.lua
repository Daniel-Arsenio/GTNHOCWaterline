local component = require("component")
local computer = require("computer")

local tui = dofile("/home/waterline/tui.lua")

local gt = {}
gt.tui = tui

function gt.resolve(address, label)
  label = label or "component"
  if type(address) ~= "string" or #address < 3 then
    error(label .. ": address not set in config.lua", 0)
  end
  if #address >= 36 then return address end

  local ok, full, reason = pcall(component.get, address)
  if not ok then
    error(string.format("%s: resolving %q raised %s", label, address, tostring(full)), 0)
  end
  if type(full) ~= "string" then
    error(string.format("%s: no unique component matches %q (%s)",
      label, address, tostring(reason)), 0)
  end
  return full
end

function gt.methods(address)
  local ok, list = pcall(component.methods, address)
  if ok and type(list) == "table" then return list end
  return {}
end

function gt.has(proxy, name)
  return proxy ~= nil and proxy[name] ~= nil
end

function gt.proxy(address, label)
  label = label or "component"
  local resolved = gt.resolve(address, label)

  local ctype = "unknown"
  local okType, t = pcall(component.type, resolved)
  if okType and type(t) == "string" then ctype = t end

  local ok, dev, reason = pcall(component.proxy, resolved)
  if not ok then
    error(string.format("%s: the %s driver at %s threw: %s",
      label, ctype, resolved:sub(1, 8), tostring(dev)), 0)
  end
  if dev == nil then
    error(string.format("%s: %s is a %s and could not be proxied: %s",
      label, resolved:sub(1, 8), ctype, tostring(reason)), 0)
  end
  return dev
end

function gt.machines()
  local out = {}
  for address, ctype in component.list("gt_machine") do
    local ok, dev = pcall(component.proxy, address)
    if ok and dev then
      local okName, name = pcall(dev.getName)
      out[#out + 1] = {
        address = address,
        proxy = dev,
        name = (okName and type(name) == "string") and name or "",
      }
    end
  end
  return out
end

function gt.findMachine(name)
  if type(name) ~= "string" or name == "" then return nil end
  local exact, fuzzy = nil, nil
  for _, m in ipairs(gt.machines()) do
    if m.name == name then
      exact = m
      break
    elseif fuzzy == nil and m.name:lower():find(name:lower(), 1, true) then
      fuzzy = m
    end
  end
  local hit = exact or fuzzy
  if hit then return hit.proxy, hit.address, hit.name end
  return nil
end

function gt.machineFor(address, expected, label)
  if type(address) == "string" and #address >= 3 then
    local ok, proxy = pcall(gt.proxy, address, label)
    if ok and proxy then
      local actual = gt.call(proxy, "getName", nil)
      if expected == nil or actual == nil or actual == expected
         or (type(actual) == "string" and actual:lower():find(expected:lower(), 1, true)) then
        return proxy, address
      end
      print(string.format("%s: %s is %s, not %s, ignoring the configured address",
        label, address:sub(1, 8), tostring(actual), expected))
    else
      print(string.format("%s: %s unusable, falling back to name search", label, address:sub(1, 8)))
    end
  end

  local proxy, found, name = gt.findMachine(expected)
  if proxy then
    print(string.format("%s: matched %s by name (%s)", label, found:sub(1, 8), name))
    return proxy, found
  end
  return nil
end

function gt.network(addresses, method, label)
  if type(addresses) == "string" then addresses = { addresses } end
  if type(addresses) ~= "table" or #addresses == 0 then
    error(label .. ": no address configured", 0)
  end

  local notes = {}
  for _, address in ipairs(addresses) do
    if type(address) == "string" and #address >= 3 then
      local ok, dev = pcall(gt.proxy, address, label)
      if not ok then
        notes[#notes + 1] = address:sub(1, 8) .. " " .. tostring(dev)
      elseif gt.has(dev, method) then
        return dev, address
      else
        notes[#notes + 1] = address:sub(1, 8) .. " has no " .. method
      end
    end
  end

  error(label .. ": no candidate answers " .. method .. " (" .. table.concat(notes, "; ") .. ")", 0)
end

local function escapePattern(text)
  return (text:gsub("([%().%%%+%-%*%?%[%^%$%]])", "%%%1"))
end

gt.MACHINE = {
  plant = "multimachine.purificationplant",
  t1 = "multimachine.purificationunitclarifier",
  t2 = "multimachine.purificationunitozonation",
  t3 = "multimachine.purificationunitflocculator",
  t4 = "multimachine.purificationunitphadjustment",
  t5 = "multimachine.purificationunitplasmaheater",
  t6 = "multimachine.purificationunituvtreatment",
  t7 = "multimachine.purificationunitdegasifier",
  t8 = "multimachine.purificationunitextractor",
}

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

function gt.lineNumber(info, line, prefix)
  local data = info[line]
  if type(data) ~= "string" then return nil end
  if prefix then data = data:gsub(escapePattern(prefix), "") end
  data = gt.clean(data):gsub(",", "")
  return tonumber(data:match("([%d%.]+)"))
end

function gt.prefixNumber(info, prefix, fallbackLine)
  if type(prefix) == "string" and prefix ~= "" then
    for i = 1, #info do
      if type(info[i]) == "string" and info[i]:find(prefix, 1, true) then
        return gt.lineNumber(info, i, prefix), i
      end
    end
  end
  if fallbackLine then
    return gt.lineNumber(info, fallbackLine, prefix), fallbackLine
  end
  return nil
end

function gt.dumpSensor(info, label)
  print("--- " .. label .. " sensor lines")
  for i = 1, #info do
    print(string.format("  [%2d] %s", i, info[i]))
  end
end

function gt.lineString(info, line, prefix)
  local data = info[line]
  if type(data) ~= "string" then return nil end
  if prefix then data = data:gsub(escapePattern(prefix), "") end
  return gt.clean(data)
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
  if fn == nil then return default end
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

gt.SIDE_NAME = { [0] = "bottom", "top", "north", "south", "west", "east" }

function gt.findFluid(transposer, fluidName, ignore)
  ignore = ignore or {}
  local bestSide, bestTank, bestAmount = nil, nil, -1

  for side = 0, 5 do
    if not ignore[side] then
      local tanks = gt.call(transposer, "getTankCount", 0, side) or 0
      for tank = 1, tanks do
        local fluid = gt.call(transposer, "getFluidInTank", nil, side, tank)
        if type(fluid) == "table" and type(fluid.name) == "string"
           and fluid.name:find(fluidName, 1, true) then
          local amount = fluid.amount or 0
          if amount > bestAmount then
            bestSide, bestTank, bestAmount = side, tank, amount
          end
        end
      end
    end
  end

  if bestSide == nil then return nil end
  return bestSide, bestTank, bestAmount
end

function gt.findItem(transposer, label, ignore)
  ignore = ignore or {}
  for side = 0, 5 do
    if not ignore[side] then
      local stacks = gt.call(transposer, "getAllStacks", nil, side)
      if stacks ~= nil then
        local ok, all = pcall(stacks.getAll)
        if ok and type(all) == "table" then
          for index, slot in pairs(all) do
            if type(slot) == "table" and type(slot.label) == "string"
               and slot.label:find(label, 1, true) then
              return side, index + 1
            end
          end
        end
      end
    end
  end
  return nil
end

function gt.pushFluid(transposer, source, sink, want, tank)
  if want <= 0 then return 0, "nothing requested" end

  local called, a, b = pcall(transposer.transferFluid, source, sink, want, tank)
  if not called then
    return 0, "transferFluid threw: " .. tostring(a)
  end

  if type(a) == "number" then return a, nil end
  if a ~= true then
    return 0, "returned " .. tostring(a) .. ", " .. tostring(b)
  end
  if type(b) ~= "number" then return want, nil end
  return b, nil
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

function gt.num(n)
  if type(n) ~= "number" then return tostring(n) end
  local abs = math.abs(n)
  if abs >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if abs >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if abs >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n))
end

function gt.short(text, width)
  text = tostring(text)
  if #text <= width then return text end
  return text:sub(1, width - 1) .. "~"
end

local function stamped(colour, fmt, ...)
  tui.write(tui.c.dim, string.format("%5ds ", math.floor(computer.uptime())))
  tui.write(colour, string.format(fmt, ...))
  tui.reset()
  io.write("\n")
end

function gt.warn(fmt, ...)
  stamped(tui.c.warn, fmt, ...)
end

function gt.bad(fmt, ...)
  stamped(tui.c.bad, fmt, ...)
end

function gt.info(enabled, fmt, ...)
  if not enabled then return end
  stamped(tui.c.text, fmt, ...)
end

function gt.log(enabled, fmt, ...)
  if not enabled then return end
  stamped(enabled == true and tui.c.warn or tui.c.text, fmt, ...)
end

return gt
