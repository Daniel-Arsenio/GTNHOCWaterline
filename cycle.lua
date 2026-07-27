local computer = require("computer")

local cycle = {}
cycle.__index = cycle

function cycle.new(cfg, gt)
  local self = setmetatable({}, cycle)
  self.gt = gt
  self.machine = gt.proxy(cfg.cycleAddress, "cycle source (WPP)")
  self.period = cfg.cycleSeconds or 120

  local methods = gt.methods(gt.resolve(cfg.cycleAddress, "cycle source (WPP)"))
  self.useProgress = methods.getWorkProgress ~= nil
    or self.machine.getWorkProgress ~= nil

  self.count = 0
  self.progress = nil
  self.active = nil
  self.nextEdge = computer.uptime() + self.period

  if self.useProgress then
    print("cycle: tracking getWorkProgress on the plant")
  else
    print(string.format("cycle: no progress method, free-running on a %d second timer", self.period))
    print("cycle: use 'sync' while a cycle starts, or accept the drift")
  end

  return self
end

function cycle:sync()
  self.nextEdge = computer.uptime() + self.period
  self.count = self.count + 1
  return true
end

function cycle:poll()
  if not self.useProgress then
    if computer.uptime() >= self.nextEdge then
      self.nextEdge = self.nextEdge + self.period
      self.count = self.count + 1
      return true
    end
    return false
  end

  local gt = self.gt
  local progress = gt.call(self.machine, "getWorkProgress", nil)
  local active = gt.call(self.machine, "isMachineActive", nil)
  local restarted = false

  if type(progress) == "number" and type(self.progress) == "number" and progress < self.progress then
    restarted = true
  end
  if active == true and self.active == false then
    restarted = true
  end

  self.progress, self.active = progress, active
  if restarted then self.count = self.count + 1 end
  return restarted
end

return cycle
