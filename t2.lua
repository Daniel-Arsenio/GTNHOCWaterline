local t2 = {}
t2.__index = t2

function t2.new(cfg, gt, clock)
  local self = setmetatable({}, t2)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t2
  local address = self.c.interfaceAddress
  if address == nil or address == "" then address = cfg.stock.interfaceAddress end
  self.me = gt.network(address, "getFluidsInNetwork", "t2.interfaceAddress")
  self.unit = nil
  if self.c.gateUntilFull then
    self.unit = gt.machineFor(self.c.unitAddress, gt.MACHINE.t2, "ozonation unit")
  end
  self.gated = nil
  self.warned = false
  self.stats = { cycles = 0, byTier = {}, starved = 0 }
  for i = 1, #self.c.recipeTiers do self.stats.byTier[i] = 0 end
  return self
end

function t2:networkOzone()
  local list = self.gt.call(self.me, "getFluidsInNetwork", nil)
  if type(list) ~= "table" then return nil end
  for _, f in ipairs(list) do
    if f.label == self.c.ozoneLabel or f.name == self.c.ozoneLabel then return f.amount or 0 end
  end
  return 0
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
  local level = self:networkOzone()

  if level == nil then
    if not self.warned then
      self.warned = true
      gt.warn("t2: cannot read Ozone in the network, check the label in config.lua")
    end
    return
  end
  self.warned = false

  if started then
    self.stats.cycles = self.stats.cycles + 1
    local tier = self:tierFor(level)
    local buffer = level / c.recipeTiers[#c.recipeTiers].volume

    if tier then
      self.stats.byTier[tier] = self.stats.byTier[tier] + 1
    else
      self.stats.starved = self.stats.starved + 1
      gt.warn("t2 c%d only %s ozone, below the smallest recipe", self.clock.count, gt.num(level))
    end

    if buffer < (c.minBufferCycles or 2) then
      if not self.bufferWarned then
        self.bufferWarned = true
        gt.warn("t2 c%d ozone %s, %.1f charges, engravers are behind",
          self.clock.count, gt.num(level), buffer)
      end
    else
      self.bufferWarned = false
      gt.info(self.cfg.log.verbose, "t2 c%d ozone %s, %.1f charges",
        self.clock.count, gt.num(level), buffer)
    end
  end

  if c.gateUntilFull and self.unit then
    local want = level >= c.recipeTiers[#c.recipeTiers].volume
    if self.gated ~= want then
      gt.call(self.unit, "setWorkAllowed", nil, want)
      self.gated = want
      gt.warn("t2 %s unit, network Ozone at %d L", want and "enabled" or "held off", level)
    end
  end
end

function t2:status()
  local parts = {}
  for i, tier in ipairs(self.c.recipeTiers) do
    parts[#parts + 1] = string.format("%d%%=%d", tier.chance, self.stats.byTier[i])
  end
  return string.format("t2 cycles=%d starved=%d [%s]",
    self.stats.cycles, self.stats.starved, table.concat(parts, " "))
end

return t2
