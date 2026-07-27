local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")

local args = { ... }
local raw = args[1] or ""
local needle = raw:lower()
local target = args[2] or cfg.stock.interfaceAddress
local limit = tonumber(args[3]) or 400

local me = gt.network(target, "getCraftables", "craftables target")

local function describe(entry)
  if type(entry) ~= "table" then return nil, "not a table" end

  if entry.label or entry.name then
    return { label = entry.label, name = entry.name, damage = entry.damage }
  end

  if entry.getItemStack == nil then
    return nil, "no getItemStack and no direct fields"
  end

  local ok, stack = pcall(entry.getItemStack)
  if not ok then return nil, tostring(stack) end
  if type(stack) ~= "table" then return nil, "getItemStack returned " .. type(stack) end
  return { label = stack.label, name = stack.name, damage = stack.damage }
end

local function show(info)
  print(string.format("  %-34s %-30s %s",
    gt.short(tostring(info.label), 34), gt.short(tostring(info.name), 30),
    tostring(info.damage)))
end

print("craftables  target " .. tostring(target):sub(1, 8) .. "  query " .. (raw ~= "" and raw or "(all)"))
print("")

if raw ~= "" then
  local byLabel = gt.call(me, "getCraftables", nil, { label = raw })
  print(string.format("filter   getCraftables{label}     %s",
    type(byLabel) == "table" and (#byLabel .. " hit(s)") or "unavailable"))
  if type(byLabel) == "table" then
    for _, c in ipairs(byLabel) do
      local info = describe(c)
      if info then show(info) end
    end
  end
end

if raw ~= "" then
  local items = gt.call(me, "getItemsInNetwork", nil, { label = raw })
  print(string.format("network  getItemsInNetwork{label} %s",
    type(items) == "table" and (#items .. " hit(s)") or "unavailable"))
  if type(items) == "table" then
    for _, it in ipairs(items) do
      print(string.format("  %-34s %-30s %s craftable=%s",
        gt.short(tostring(it.label), 34), gt.short(tostring(it.name), 30),
        gt.num(it.size or 0), tostring(it.isCraftable)))
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
  print(string.format("fluids   name or label match     %d of %d", #fluidHits, #fluids))
  for _, f in ipairs(fluidHits) do
    print(string.format("  %-34s %-30s %s",
      gt.short(tostring(f.label), 34), gt.short(tostring(f.name), 30), gt.num(f.amount or 0)))
  end
else
  print("fluids   getFluidsInNetwork       unavailable")
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

print(string.format("scan     %d of %d craftables      %d hit(s), %d unreadable",
  scanned, #craftables, shown, failed))
for _, info in ipairs(hits) do show(info) end
if firstError then
  print("  read error: " .. gt.short(firstError, 70))
end

if shown == 0 and #craftables > 0 then
  print("")
  print("=== structure of craftables[1], since nothing matched")
  local first = craftables[1]
  print("  type: " .. type(first))
  if type(first) == "table" then
    local keys = {}
    for key, value in pairs(first) do
      keys[#keys + 1] = tostring(key) .. "=" .. type(value)
    end
    table.sort(keys)
    if #keys == 0 then
      print("  no keys via pairs, members resolve through __index")
      for _, probe in ipairs({ "label", "name", "damage", "size", "getItemStack", "request" }) do
        print(string.format("  %-13s %s", probe, type(first[probe])))
      end
    else
      print("  " .. table.concat(keys, "  "))
    end
  end
  print("  send this block if the scan still finds nothing")
end
if #craftables > limit then
  print(string.format("  %d not scanned, rerun: craftables %s %s %d",
    #craftables - limit, raw ~= "" and raw or "''", tostring(target):sub(1, 8), #craftables))
end

local cpus = gt.call(me, "getCpus", nil)
if type(cpus) == "table" then
  local free = 0
  for _, c in ipairs(cpus) do if c.busy == false then free = free + 1 end end
  print(string.format("cpus     %d total                  %d free", #cpus, free))
end
