local computer = require("computer")

local t3 = {}
t3.__index = t3

function t3.new(cfg, gt, clock)
  local self = setmetatable({}, t3)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t3
  self.unit = gt.proxy(self.c.unitAddress, "flocculation unit")
  self.trans = gt.proxy(self.c.transposerAddress, "t3 flocculant transposer")
  self.filling = false
  self.charge = 0
  self.pushed = 0
  self.deadline = 0
  self.stats = { cycles = 0, clean = 0, short = 0, carried = 0 }

  local _, capacity = gt.tankTotals(self.trans, self.c.hatchSide)
  if capacity < self.c.targetVolume then
    print(string.format("t3 warning: hatch capacity %d L cannot hold a %d L charge",
      capacity, self.c.targetVolume))
  end
  return self
end

function t3:tick(started)
  local c, gt = self.c, self.gt
  local now = computer.uptime()

  if started then
    self.stats.cycles = self.stats.cycles + 1
    local residual = gt.tankTotals(self.trans, c.hatchSide)

    if residual > 0 then
      self.stats.carried = self.stats.carried + 1
      gt.log(true, "t3 cycle %d: %d L carried over, so last cycle consumed %d L and not %d L",
        self.clock.count, residual, c.targetVolume - residual, c.targetVolume)
    end

    self.charge = c.targetVolume - residual
    self.pushed = 0
    self.deadline = now + c.fillWindow
    self.filling = self.charge > 0
  end

  if not self.filling then return end

  local want = self.charge - self.pushed
  if want > 0 then
    self.pushed = self.pushed + gt.pushFluid(self.trans, c.sourceSide, c.hatchSide, want)
    want = self.charge - self.pushed
  end

  if want <= 0 then
    self.filling = false
    self.stats.clean = self.stats.clean + 1
    gt.log(self.cfg.log.verbose, "t3 cycle %d: charged %d L", self.clock.count, self.pushed)
  elseif now > self.deadline then
    self.filling = false
    self.stats.short = self.stats.short + 1
    gt.log(true, "t3 cycle %d: only moved %d L of %d L, success chance is not on a 100 kL step",
      self.clock.count, self.pushed, self.charge)
  end
end

function t3:status()
  return string.format("t3 cycles=%d charged=%d short=%d carriedOver=%d",
    self.stats.cycles, self.stats.clean, self.stats.short, self.stats.carried)
end

return t3
