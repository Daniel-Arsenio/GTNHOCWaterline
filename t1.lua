local t1 = {}
t1.__index = t1

function t1.new(cfg, gt, clock)
  local self = setmetatable({}, t1)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t1
  self.unit = gt.proxy(self.c.unitAddress, "clarifier")
  self.trans = gt.proxy(self.c.transposerAddress, "t1 filter transposer")
  self.lastCount = nil
  self.starved = false
  self.stats = { cycles = 0, consumed = 0, restocked = 0, starvedCycles = 0 }
  return self
end

function t1:tick(started)
  local c, gt = self.c, self.gt
  local have = gt.countItems(self.trans, c.busSide, c.filterLabel)

  if started then
    self.stats.cycles = self.stats.cycles + 1
    if self.lastCount and have < self.lastCount then
      self.stats.consumed = self.stats.consumed + (self.lastCount - have)
    end
    if have == 0 then
      self.stats.starvedCycles = self.stats.starvedCycles + 1
      gt.log(true, "t1 cycle %d: no filter in the bus, clarifier is idle", self.clock.count)
    end
  end

  if have < c.filterStock then
    local moved = gt.pushItems(self.trans, c.sourceSide, c.busSide, c.filterStock - have, c.sourceSlot)
    if moved > 0 then
      self.stats.restocked = self.stats.restocked + moved
      self.starved = false
      gt.log(self.cfg.log.verbose, "t1 restocked %d filters, bus now %d", moved, have + moved)
      have = have + moved
    elseif not self.starved then
      self.starved = true
      gt.log(true, "t1: ME interface has no Activated Carbon Filter to pull")
    end
  end

  self.lastCount = have
end

function t1:status()
  return string.format("t1 cycles=%d filtersUsed=%d restocked=%d idleCycles=%d",
    self.stats.cycles, self.stats.consumed, self.stats.restocked, self.stats.starvedCycles)
end

return t1
