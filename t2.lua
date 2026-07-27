local t2 = {}
t2.__index = t2

function t2.new(cfg, gt, clock)
  local self = setmetatable({}, t2)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t2
  self.unit = gt.proxy(self.c.unitAddress, "ozonation unit")
  self.trans = gt.proxy(self.c.transposerAddress, "t2 ozone transposer")
  self.gated = nil
  self.stats = { cycles = 0, byTier = {}, pushed = 0 }
  for i = 1, #self.c.recipeTiers do self.stats.byTier[i] = 0 end
  self.stats.belowFirstTier = 0

  local _, capacity = gt.tankTotals(self.trans, self.c.hatchSide)
  if capacity < self.c.ozoneTarget then
    print(string.format("t2 warning: ozone hatch capacity %d L is below the %d L target, use a ZPM hatch",
      capacity, self.c.ozoneTarget))
  end
  return self
end

function t2:tierFor(level)
  local best = nil
  for i, tier in ipairs(self.c.recipeTiers) do
    if level >= tier.volume then best = i end
  end
  return best
end

function t2:tick(started)
  local c, gt = self.c, self.gt
  local level = gt.tankTotals(self.trans, c.hatchSide)

  if started then
    self.stats.cycles = self.stats.cycles + 1
    local tier = self:tierFor(level)
    if tier then
      self.stats.byTier[tier] = self.stats.byTier[tier] + 1
      gt.log(self.cfg.log.verbose, "t2 cycle %d: %d L ozone, recipe tier %d at %d%% base",
        self.clock.count, level, tier, c.recipeTiers[tier].chance)
    else
      self.stats.belowFirstTier = self.stats.belowFirstTier + 1
      gt.log(true, "t2 cycle %d: only %d L ozone, below the %d L minimum recipe",
        self.clock.count, level, c.recipeTiers[1].volume)
    end
  end

  if level < c.ozoneTarget then
    local moved = gt.pushFluid(self.trans, c.sourceSide, c.hatchSide, c.ozoneTarget - level)
    if moved > 0 then
      self.stats.pushed = self.stats.pushed + moved
      level = level + moved
    end
  end

  if c.gateUntilFull then
    local want = level >= c.ozoneTarget
    if self.gated ~= want then
      gt.call(self.unit, "setWorkAllowed", nil, want)
      self.gated = want
      gt.log(true, "t2 %s unit, ozone buffer at %d L", want and "enabled" or "held off", level)
    end
  end
end

function t2:status()
  local parts = {}
  for i, tier in ipairs(self.c.recipeTiers) do
    parts[#parts + 1] = string.format("%d%%=%d", tier.chance, self.stats.byTier[i])
  end
  return string.format("t2 cycles=%d starved=%d [%s]",
    self.stats.cycles, self.stats.belowFirstTier, table.concat(parts, " "))
end

return t2
