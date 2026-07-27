local computer = require("computer")

local cycle = {}
cycle.__index = cycle

function cycle.new(cfg, gt)
  local self = setmetatable({}, cycle)
  self.gt = gt
  self.c = cfg.cycle
  self.count = 0
  self.lastProgress = 0
  self.period = self.c.seconds or 120
  self.nextEdge = computer.uptime() + self.period

  self.machine = gt.machineFor(cfg.cycleAddress, gt.MACHINE.plant, "water purification plant")
  if self.machine == nil then
    error("water purification plant not found, is it linked and adapter connected", 0)
  end

  self.useProgress = gt.has(self.machine, "getWorkProgress")
    and gt.has(self.machine, "hasWork")

  if self.useProgress then
    local max = gt.call(self.machine, "getWorkMaxProgress", nil)
    print(string.format("cycle: tracking plant progress, %s tick cycle", tostring(max)))
  else
    print("cycle: plant exposes no progress, free running on a timer")
  end

  return self
end

function cycle:edge()
  self.count = self.count + 1
  self.nextEdge = computer.uptime() + self.period
  return true
end

function cycle:poll()
  if not self.useProgress then
    if computer.uptime() >= self.nextEdge then return self:edge() end
    return false
  end

  local gt = self.gt
  local progress = gt.call(self.machine, "getWorkProgress", 0) or 0
  local working = gt.call(self.machine, "hasWork", nil)
  local ended = false

  if self.lastProgress > progress or (working == false and self.lastProgress ~= 0) then
    ended = true
    self.lastProgress = 0
  end

  if working then self.lastProgress = progress end

  if ended then return self:edge() end
  return false
end

function cycle:working()
  return self.gt.call(self.machine, "hasWork", false) == true
end

function cycle:seconds()
  local p = self.gt.call(self.machine, "getWorkProgress", nil)
  if type(p) ~= "number" then return nil end
  return math.ceil(p / 20)
end

return cycle
