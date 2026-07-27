local cycle = {}
cycle.__index = cycle

function cycle.new(cfg, gt)
  local self = setmetatable({}, cycle)
  self.gt = gt
  self.machine = gt.proxy(cfg.cycleAddress, "cycle source (WPP)")
  self.count = 0
  self.progress = nil
  self.active = nil
  return self
end

function cycle:poll()
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
