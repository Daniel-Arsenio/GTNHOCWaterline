local BASE = "/home/waterline/"
local event = require("event")
local computer = require("computer")

local cfg = dofile(BASE .. "settings.lua")
local gt = dofile(BASE .. "gtutil.lua")
local tui = gt.tui

if cfg.ui and cfg.ui.maximise then tui.maximise() end
tui.header("waterline", "grades 1 to 4")
local clock = dofile(BASE .. "cycle.lua").new(cfg, gt)

local REBIND_AFTER = 5

local function build(name)
  local ok, mod = pcall(dofile, BASE .. name .. ".lua")
  if not ok then return nil, tostring(mod) end
  local built, instance = pcall(mod.new, cfg, gt, clock)
  if not built then return nil, tostring(instance) end
  return instance
end

if cfg.__issues and #cfg.__issues > 0 then
  tui.line(tui.c.warn, #cfg.__issues .. " unrecognised key(s) in config.lua, ignored")
  tui.columns(cfg.__issues, tui.c.dim)
end

local modules = {}
for _, name in ipairs({ "power", "stock", "watch", "t2", "t3", "t4", "ui" }) do
  if cfg[name] and cfg[name].enabled then
    local instance, err = build(name)
    if instance then
      modules[#modules + 1] = { name = name, impl = instance, errors = 0 }
      tui.line(tui.c.ok, tui.pad(name, 8), tui.c.dim, "loaded")
    else
      tui.line(tui.c.bad, tui.pad(name, 8), tui.c.dim, "disabled  " .. err)
    end
  end
end

if #modules == 0 then
  tui.line(tui.c.bad, "no modules enabled, check config.lua")
  return
end

local nextStatus = computer.uptime() + 300

while true do
  local started = clock:poll()

  for _, m in ipairs(modules) do
    local ok, err = pcall(m.impl.tick, m.impl, started)
    if ok then
      m.errors = 0
    else
      m.errors = m.errors + 1
      print(m.name .. " tick error: " .. tostring(err))
      if m.errors >= REBIND_AFTER then
        local rebuilt, rerr = build(m.name)
        if rebuilt then
          m.impl, m.errors = rebuilt, 0
          print(m.name .. " rebound to its components")
        else
          m.errors = 0
          print(m.name .. " could not rebind: " .. rerr)
        end
      end
    end
  end

  if computer.uptime() > nextStatus then
    tui.rule()
    tui.line(tui.c.head, "cycle " .. clock.count)
    for _, m in ipairs(modules) do tui.line(tui.c.text, "  " .. m.impl:status()) end
    tui.rule()
    nextStatus = computer.uptime() + 300
  end

  if event.pull(cfg.pollInterval, "interrupted") then break end
end

print(string.format("stopped after %d cycles", clock.count))
for _, m in ipairs(modules) do print("  " .. m.impl:status()) end
