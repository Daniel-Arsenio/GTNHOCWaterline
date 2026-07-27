local BASE = "/home/waterline/"
local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")

local args = { ... }
local needle = (args[1] or ""):lower()

local target = args[2] or cfg.stock.interfaceAddress
local me = gt.proxy(target, "ME interface")
print("using component " .. tostring(target))

print("=== craftables matching '" .. needle .. "'")
local craftables = gt.call(me, "getCraftables", nil)
if type(craftables) ~= "table" then
  print("  getCraftables unavailable, is the adapter on an ME Interface?")
else
  local shown = 0
  for _, c in ipairs(craftables) do
    local ok, itemStack = pcall(c.getItemStack)
    if ok and itemStack then
      local label = itemStack.label or "?"
      if needle == "" or label:lower():find(needle, 1, true) then
        print(string.format("  label=%q name=%q damage=%s",
          label, tostring(itemStack.name), tostring(itemStack.damage)))
        shown = shown + 1
      end
    end
  end
  print("  " .. shown .. " shown of " .. #craftables)
end

print("")
print("=== fluids in network matching '" .. needle .. "'")
local fluids = gt.call(me, "getFluidsInNetwork", nil)
if type(fluids) ~= "table" then
  print("  getFluidsInNetwork unavailable on this network")
else
  for _, f in ipairs(fluids) do
    local label = f.label or f.name or "?"
    if needle == "" or label:lower():find(needle, 1, true) then
      print(string.format("  label=%q name=%q amount=%d", label, tostring(f.name), f.amount or 0))
    end
  end
end

print("")
print("=== crafting CPUs")
local cpus = gt.call(me, "getCpus", nil)
if type(cpus) ~= "table" then
  print("  getCpus unavailable")
else
  for i, c in ipairs(cpus) do
    print(string.format("  %d name=%s busy=%s storage=%s coprocessors=%s",
      i, tostring(c.name), tostring(c.busy), tostring(c.storage), tostring(c.coprocessors)))
  end
end
