local component = require("component")
local computer = require("computer")
local tui = dofile("/home/waterline/tui.lua")

local ui = {}
ui.__index = ui

local FILLED = "\226\150\136"
local EMPTY = "\226\150\145"

function ui.new(cfg, gt, clock)
  local self = setmetatable({}, ui)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.ui
  self.gpu = component.isAvailable("gpu") and component.gpu or nil
  self.lastText = nil
  self.nextDraw = 0

  if self.c.mode == "pinned" and self.gpu == nil then
    print("ui: no gpu, falling back to printed lines")
    self.c.mode = "line"
  end
  return self
end

function ui:bar(fraction, width)
  return tui.bar(fraction, width, FILLED, EMPTY)
end

function ui:text()
  local fraction = self.clock:fraction()
  local width = (self.c.barWidth and self.c.barWidth > 0) and self.c.barWidth
    or math.max(20, math.floor(tui.width() / 3))

  if fraction == nil then
    return string.format("cycle %d  no progress source", self.clock.count)
  end

  local seconds = math.floor(self.clock.progress / 20)
  local total = math.floor((self.clock.max or 0) / 20)
  local state = self.clock.busy and "running" or "idle"

  return string.format("[%s] %3d%%  %ds/%ds  cycle %d  %s",
    self:bar(fraction, width), math.floor(fraction * 100),
    seconds, total, self.clock.count, state)
end

function ui:tick(started)
  if self.c.mode == "off" then return end

  local now = computer.uptime()
  if now < self.nextDraw then return end
  self.nextDraw = now + (self.c.minInterval or 0.5)

  local text = self:text()
  if text == self.lastText then return end
  self.lastText = text

  if self.c.mode == "pinned" and self.gpu then
    local w, h = self.gpu.getResolution()
    local previous = self.gpu.setForeground(
      self.clock.busy and tui.c.ok or tui.c.dim)
    self.gpu.set(1, h, text .. string.rep(" ", math.max(0, w - #text)))
    self.gpu.setForeground(previous)
  else
    tui.line(self.clock.busy and tui.c.ok or tui.c.dim, text)
  end
end

function ui:status()
  return "ui " .. self.c.mode
end

return ui
