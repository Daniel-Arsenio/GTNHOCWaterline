local component = require("component")
local computer = require("computer")
local term = require("term")
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

  if self.c.mode == "pinned" then
    if self.gpu == nil then
      self.c.mode = "line"
    else
      local w, h = self.gpu.getResolution()
      self.width, self.height = w, h
      local ok = pcall(term.setViewport, w, h - 2, 0, 0)
      if ok then
        self.reserved = true
      else
        self.c.mode = "line"
      end
    end
  end
  return self
end

function ui:bar(fraction, width)
  return tui.bar(fraction, width, FILLED, EMPTY)
end

function ui:parts()
  local fraction = self.clock:fraction()
  local width = (self.c.barWidth and self.c.barWidth > 0) and self.c.barWidth
    or math.max(20, math.floor(tui.width() / 3))

  if fraction == nil then
    return nil, width, string.format("cycle %d   no progress source", self.clock.count)
  end

  local seconds = math.floor(self.clock.progress / 20)
  local total = math.floor((self.clock.max or 0) / 20)

  return fraction, width, string.format("%3d%%   %ds of %ds   cycle %d   %s",
    math.floor(fraction * 100), seconds, total, self.clock.count,
    self.clock.busy and "running" or "idle")
end

function ui:text()
  local fraction, width, info = self:parts()
  if fraction == nil then return info end
  return "[" .. self:bar(fraction, width) .. "] " .. info
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
    self:draw()
  else
    tui.line(self.clock.busy and tui.c.ok or tui.c.dim, text)
  end
end

function ui:draw()
  local gpu = self.gpu
  local fraction, width, info = self:parts()
  local w, h = self.width, self.height
  local previous = gpu.setForeground(tui.c.text)

  local column = 1
  if fraction ~= nil then
    local filled = math.floor(fraction * width + 0.5)
    gpu.setForeground(self.clock.busy and tui.c.ok or tui.c.dim)
    if filled > 0 then gpu.set(column, h, FILLED:rep(filled)) end
    gpu.setForeground(tui.c.rule)
    if width - filled > 0 then gpu.set(column + filled, h, EMPTY:rep(width - filled)) end
    column = column + width + 2
  end

  gpu.setForeground(self.clock.busy and tui.c.val or tui.c.dim)
  gpu.set(column, h, info .. string.rep(" ", math.max(0, w - column - #info + 1)))
  gpu.setForeground(previous)
end

function ui:shutdown()
  if self.reserved and self.gpu then
    pcall(term.setViewport, self.width, self.height, 0, 0)
    self.gpu.set(1, self.height, string.rep(" ", self.width))
    self.reserved = false
  end
end

function ui:status()
  return "ui " .. self.c.mode
end

return ui
