local sides = require("sides")

local t4 = {}
t4.__index = t4

function t4.new(cfg, gt, clock)
  local self = setmetatable({}, t4)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t4

  self.unit = gt.machineFor(self.c.unitAddress, gt.MACHINE.t4, "pH neutralisation unit")
  if self.unit == nil then
    error("pH neutralisation unit not found", 0)
  end

  self.acidT = gt.proxy(self.c.acid.transposerAddress, "t4 acid transposer")
  self.baseT = gt.proxy(self.c.base.transposerAddress, "t4 base transposer")
  self.acidSink = sides[self.c.acid.sinkSide] or sides.bottom
  self.baseSink = sides[self.c.base.sinkSide] or sides.bottom

  local aSide, aTank
  if self.c.acid.sourceSide then
    aSide, aTank = sides[self.c.acid.sourceSide], self.c.acid.sourceTank or 1
  else
    aSide, aTank = gt.findFluid(self.acidT, self.c.acid.fluidName, { [self.acidSink] = true })
  end
  if aSide == nil then
    error("no " .. self.c.acid.fluidName .. " found on the t4 acid transposer", 0)
  end
  self.acidSide, self.acidTank = aSide, aTank

  local bSide = gt.findItem(self.baseT, self.c.base.itemLabel, { [self.baseSink] = true })
  if bSide == nil then
    error("no " .. self.c.base.itemLabel .. " found on the t4 base transposer", 0)
  end
  self.baseSide = bSide

  print(string.format("t4  acid %s->%s tank %d   dust %s->%s",
    gt.SIDE_NAME[aSide] or aSide, gt.SIDE_NAME[self.acidSink] or self.acidSink, aTank,
    gt.SIDE_NAME[bSide] or bSide, gt.SIDE_NAME[self.baseSink] or self.baseSink))

  self.dosed = false
  self.stats = { cycles = 0, dosed = 0, shortfalls = 0 }
  return self
end

function t4:ph()
  local gt = self.gt
  local info = gt.sensor(self.unit)
  local value, line = gt.prefixNumber(info, self.c.phPrefix, nil)

  if value == nil then
    if not self.warnedLine then
      self.warnedLine = true
      gt.warn("t4: no line matching %q, falling back to line %d",
        self.c.phPrefix, self.c.phLine)
      gt.dumpSensor(info, "pH unit")
    end
    return gt.lineNumber(info, self.c.phLine, self.c.phPrefix)
  end

  if self.foundLine ~= line then
    self.foundLine = line
    gt.warn("t4: reading pH from sensor line %d", line)
  end
  return value
end

function t4:putDust(count)
  local moved = 0
  for i = 1, math.ceil(count / 64) do
    local batch = math.min(64, count - moved)
    local n = self.baseT.transferItem(self.baseSide, self.baseSink, batch)
    if type(n) ~= "number" or n ~= batch then
      moved = moved + (type(n) == "number" and n or 0)
      return moved, false
    end
    moved = moved + n
  end
  return moved, true
end

function t4:putAcid(litres)
  local _, moved = self.acidT.transferFluid(self.acidSide, self.acidSink, litres, self.acidTank)
  moved = type(moved) == "number" and moved or 0
  return moved, moved == litres
end

function t4:tick(started)
  local c, gt = self.c, self.gt

  if started then
    self.stats.cycles = self.stats.cycles + 1
    self.dosed = false

    if c.acid.bufferWarn and c.acid.bufferWarn > 0 then
      local fluid = gt.call(self.acidT, "getFluidInTank", nil, self.acidSide, self.acidTank)
      local have = type(fluid) == "table" and (fluid.amount or 0) or 0
      if have < c.acid.bufferWarn then
        gt.warn("t4: acid buffer down to %d L", have)
      end
    end

    if c.base.bufferWarn and c.base.bufferWarn > 0 then
      local have = gt.countItems(self.baseT, self.baseSide, c.base.itemLabel)
      if have < c.base.bufferWarn then
        gt.warn("t4: sodium hydroxide down to %d", have)
      end
    end
  end

  if self.dosed then return end
  if not self.clock:working() then return end

  local ph = self:ph()
  if ph == nil then return end

  local diff = c.targetPh - ph
  local count = math.floor(math.abs(diff / 0.01))

  if count == 0 then
    self.dosed = true
    return
  end

  local ok
  if diff > 0 then
    local moved
    moved, ok = self:putDust(count)
    gt.info(self.cfg.log.verbose, "t4 c%d pH %.2f +%d dust", self.clock.count, ph, moved)
  else
    local litres = count * c.litresPerStep
    local moved
    moved, ok = self:putAcid(litres)
    gt.info(self.cfg.log.verbose, "t4 c%d pH %.2f -%s acid", self.clock.count, ph, gt.num(moved))
  end

  if not ok then
    self.stats.shortfalls = self.stats.shortfalls + 1
    gt.warn("t4 cycle %d: ran out of reagent mid dose", self.clock.count)
    if c.haltWhenShort then
      gt.call(self.unit, "setWorkAllowed", nil, false)
    end
  else
    self.stats.dosed = self.stats.dosed + 1
  end

  self.dosed = true
end

function t4:status()
  local info = self.gt.sensor(self.unit)
  local ph = self.gt.lineNumber(info, self.c.phLine, self.c.phPrefix)
  local chance = self.gt.lineNumber(info, 2, "Success chance:")
  return string.format("t4 cycles=%d dosed=%d short=%d pH=%s success=%s%%",
    self.stats.cycles, self.stats.dosed, self.stats.shortfalls,
    tostring(ph), tostring(chance))
end

return t4
