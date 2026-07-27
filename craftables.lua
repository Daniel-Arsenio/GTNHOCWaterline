local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui

local args = { ... }
local raw = args[1] or ""
local needle = raw:lower()
local target = args[2] or cfg.stock.interfaceAddress
local limit = tonumber(args[3]) or 400

local me = gt.network(target, "getCraftables", "craftables target")

local LW = math.max(20, math.floor((tui.width() - 26) * 0.45))
local NW = math.max(18, math.floor((tui.width() - 26) * 0.40))

local function probe(name, detail, hits, good)
  tui.write(tui.c.key, tui.pad(name, 10))
  tui.write(tui.c.dim, tui.pad(detail, 26))
  tui.write(good and tui.c.ok or tui.c.warn, hits)
  tui.reset()
  io.write("\n")
end

local function describe(entry)
  if type(entry) ~= "table" then return nil, "not a table" end

  if entry.label or entry.name then
    return { label = entry.label, name = entry.name, damage = entry.damage }
  end

  local accessor = entry.getStack or entry.getItemStack
  if accessor == nil then
    return nil, "no getStack, no getItemStack, no direct fields"
  end

  local ok, stack = pcall(accessor)
  if not ok then return nil, tostring(stack) end
  if type(stack) ~= "table" then return nil, "accessor returned " .. type(stack) end
  return { label = stack.label, name = stack.name, damage = stack.damage }
end

local function show(info, extra)
  tui.write(tui.c.dim, "  ")
  tui.write(tui.c.bright, tui.pad(tostring(info.label), LW))
  tui.write(tui.c.text, tui.pad(tostring(info.name), NW))
  tui.write(tui.c.dim, tostring(extra or info.damage or ""))
  tui.reset()
  io.write("\n")
end

tui.header("craftables", "target " .. tostring(target):sub(1, 8)
  .. "   query " .. (raw ~= "" and raw or "(all)"))

if raw ~= "" then
  local byLabel = gt.call(me, "getCraftables", nil, { label = raw })
  probe("filter", "getCraftables{label}",
    type(byLabel) == "table" and (#byLabel .. " hit") or "unavailable",
    type(byLabel) == "table" and #byLabel > 0)
  if type(byLabel) == "table" then
    for _, c in ipairs(byLabel) do
      local info = describe(c)
      if info then show(info) end
    end
  end
end

if raw ~= "" then
  local items = gt.call(me, "getItemsInNetwork", nil, { label = raw })
  probe("network", "getItemsInNetwork{label}",
    type(items) == "table" and (#items .. " hit") or "unavailable",
    type(items) == "table" and #items > 0)
  if type(items) == "table" then
    for _, it in ipairs(items) do
      show(it, gt.num(it.size or 0) .. "  craftable=" .. tostring(it.isCraftable))
    end
  end
end

local fluids = gt.call(me, "getFluidsInNetwork", nil)
local fluidHits = {}
if type(fluids) == "table" then
  for _, f in ipairs(fluids) do
    local label = (f.label or f.name or ""):lower()
    local name = (f.name or ""):lower()
    if needle == "" or label:find(needle, 1, true) or name:find(needle, 1, true) then
      fluidHits[#fluidHits + 1] = f
    end
  end
  probe("fluids", "label or internal name", #fluidHits .. " of " .. #fluids, #fluidHits > 0)
  for _, f in ipairs(fluidHits) do
    show(f, gt.num(f.amount or 0))
  end
else
  probe("fluids", "getFluidsInNetwork", "unavailable", false)
end

local craftables = gt.call(me, "getCraftables", nil)
if type(craftables) ~= "table" then
  print("getCraftables unavailable")
  return
end

local scanned = math.min(limit, #craftables)
local shown, failed, firstError = 0, 0, nil
local hits = {}

for i = 1, math.min(limit, #craftables) do
  local info, err = describe(craftables[i])
  if info == nil then
    failed = failed + 1
    firstError = firstError or err
  else
    local label = (info.label or ""):lower()
    local name = (info.name or ""):lower()
    if needle == "" or label:find(needle, 1, true) or name:find(needle, 1, true) then
      hits[#hits + 1] = info
      shown = shown + 1
    end
  end
end

probe("scan", scanned .. " of " .. #craftables .. " craftables",
  shown .. " hit, " .. failed .. " unreadable", shown > 0 and failed == 0)
for _, info in ipairs(hits) do show(info) end
if firstError then
  tui.line(tui.c.bad, "  read error: " .. firstError)
end

if shown == 0 and #craftables > 0 then
  io.write("\n")
  tui.line(tui.c.warn, "structure of craftables[1], since nothing matched")
  local first = craftables[1]
  tui.line(tui.c.dim, "  type: " .. type(first))
  if type(first) == "table" then
    local keys = {}
    for key, value in pairs(first) do
      keys[#keys + 1] = tostring(key) .. "=" .. type(value)
    end
    table.sort(keys)
    if #keys == 0 then
      tui.line(tui.c.dim, "  members resolve through __index")
      for _, member in ipairs({ "label", "name", "getStack", "getItemStack", "request" }) do
        tui.line(tui.c.dim, "  " .. tui.pad(member, 15) .. type(first[member]))
      end
    else
      tui.columns(keys, tui.c.dim)
    end
  end
end
if #craftables > limit then
  tui.line(tui.c.dim, string.format("  %d not scanned, rerun: craftables %s %s %d",
    #craftables - limit, raw ~= "" and raw or "''", tostring(target):sub(1, 8), #craftables))
end

local cpus = gt.call(me, "getCpus", nil)
if type(cpus) == "table" then
  local free = 0
  for _, c in ipairs(cpus) do if c.busy == false then free = free + 1 end end
  probe("cpus", #cpus .. " total", free .. " free", free > 0)
end
