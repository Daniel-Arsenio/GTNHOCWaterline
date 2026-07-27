local BASE = "/home/waterline/"
local event = require("event")
local computer = require("computer")

local cfg = dofile(BASE .. "config.lua")
local gt = dofile(BASE .. "gtutil.lua")
local clock = dofile(BASE .. "cycle.lua").new(cfg, gt)

local modules = {}
for _, name in ipairs({ "power", "stock", "t1", "t2", "t3", "t4" }) do
  if cfg[name] and cfg[name].enabled then
    local ok, mod = pcall(dofile, BASE .. name .. ".lua")
    if not ok then
      print(name .. " failed to load: " .. tostring(mod))
    else
      local built, instance = pcall(mod.new, cfg, gt, clock)
      if built then
        modules[#modules + 1] = instance
        print(name .. " loaded")
      else
        print(name .. " disabled: " .. tostring(instance))
      end
    end
  end
end

if #modules == 0 then
  print("no modules enabled, check config.lua")
  return
end

local nextStatus = computer.uptime() + 300

while true do
  local started = clock:poll()

  for _, m in ipairs(modules) do
    local ok, err = pcall(m.tick, m, started)
    if not ok then print("tick error: " .. tostring(err)) end
  end

  if computer.uptime() > nextStatus then
    print(string.format("--- cycle %d ---", clock.count))
    for _, m in ipairs(modules) do print("  " .. m:status()) end
    nextStatus = computer.uptime() + 300
  end

  if event.pull(cfg.pollInterval, "interrupted") then break end
end

print(string.format("stopped after %d cycles", clock.count))
for _, m in ipairs(modules) do print("  " .. m:status()) end
