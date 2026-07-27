local sides = require("sides")
local computer = require("computer")

local t3 = {}
t3.__index = t3

function t3.new(cfg, gt, clock)
  local self = setmetatable({}, t3)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t3

  self.unit = gt.machineFor(self.c.unitAddress, gt.MACHINE.t3, "flocculation unit")
  if self.unit == nil then
    error("flocculation unit not found", 0)
  end

  self.trans = gt.proxy(self.c.transposerAddress, "t3 flocculant transposer")
  self.sink = sides[self.c.sinkSide] or sides.up

  local side, tank, amount
  if self.c.sourceSide then
    side = sides[self.c.sourceSide]
    tank = self.c.sourceTank or 1
    local fluid = gt.call(self.trans, "getFluidInTank", nil, side, tank)
    amount = type(fluid) == "table" and (fluid.amount or 0) or 0
  else
    side, tank, amount = gt.findFluid(self.trans, self.c.fluidName, { [self.sink] = true })
  end

  if side == nil then
    error("no " .. self.c.fluidName .. " on the t3 transposer, sink is " ..
      tostring(gt.SIDE_NAME[self.sink]) .. ", fill the buffer and check t3.sinkSide", 0)
  end
  if side == self.sink then
    error("t3 source and sink are both " .. tostring(gt.SIDE_NAME[side]) ..
      ", set t3.sinkSide to the hatch face", 0)
  end

  self.source, self.tank = side, tank
  print(string.format("t3  %s tank %d (%s) -> %s",
    gt.SIDE_NAME[side], tank, gt.num(amount or 0), gt.SIDE_NAME[self.sink]))

  self.pushed = 0
  self.nextTry = 0
  self.bufferWarned = false
  self.halted = false
  self.stats = { cycles = 0, full = 0, partial = 0, empty = 0 }
  return self
end

function t3:consumed()
  local gt = self.gt
  local info = gt.sensor(self.unit)
  local value, line = gt.prefixNumber(info, self.c.consumedPrefix, nil)

  if value == nil then
    if not self.warnedLine then
      self.warnedLine = true
      gt.warn("t3 no sensor line matching %q, falling back to line %d",
        self.c.consumedPrefix, self.c.consumedLine)
      gt.dumpSensor(info, "flocculation unit")
    end
    return gt.lineNumber(info, self.c.consumedLine, self.c.consumedPrefix)
  end

  if self.foundLine ~= line then
    self.foundLine = line
    gt.info(self.cfg.log.verbose, "t3 reading consumption from sensor line %d", line)
  end
  return value
end

function t3:buffer()
  local fluid = self.gt.call(self.trans, "getFluidInTank", nil, self.source, self.tank)
  return type(fluid) == "table" and (fluid.amount or 0) or 0
end

function t3:send(want)
  local c, gt = self.c, self.gt
  local moved, why = gt.pushFluid(self.trans, self.source, self.sink, want, self.tank)

  if moved == 0 and want > c.stepVolume then
    gt.warn("t3 one shot of %s failed (%s), retrying in %s chunks",
      gt.num(want), tostring(why), gt.num(c.stepVolume))
    local total = 0
    while total < want do
      local chunk = math.min(c.stepVolume, want - total)
      local got = gt.pushFluid(self.trans, self.source, self.sink, chunk, self.tank)
      if got == 0 then break end
      total = total + got
    end
    moved = total
  end

  if moved == 0 then
    gt.warn("t3 nothing moved (%s), check the pump tier and that %s is the hatch",
      tostring(why), gt.SIDE_NAME[self.sink])
  end
  return moved
end

function t3:startCycle()
  local c, gt = self.c, self.gt
  self.stats.cycles = self.stats.cycles + 1

  if self.pushed >= c.targetVolume then
    self.stats.full = self.stats.full + 1
  elseif self.pushed > 0 then
    self.stats.partial = self.stats.partial + 1
  elseif self.stats.cycles > 1 then
    self.stats.empty = self.stats.empty + 1
  end

  self.pushed = 0
  self.nextTry = 0

  local have = self:buffer()
  local threshold = (c.bufferWarnCycles or 0) * c.targetVolume

  if threshold > 0 and have < threshold and not self.bufferWarned then
    self.bufferWarned = true
    gt.warn("t3 buffer %s, %.1f charges, the recycler is behind",
      gt.num(have), have / c.targetVolume)
  elseif have >= threshold and self.bufferWarned then
    self.bufferWarned = false
    gt.info(self.cfg.log.verbose, "t3 buffer recovered to %s", gt.num(have))
  end

  if c.haltWhenShort then
    local want = have < c.stepVolume
    if want and not self.halted then
      self.halted = true
      gt.warn("t3 buffer under %s, pausing the unit until it refills", gt.num(c.stepVolume))
      gt.call(self.unit, "setWorkAllowed", nil, false)
    elseif not want and self.halted then
      self.halted = false
      gt.warn("t3 buffer refilled, resuming the unit")
      gt.call(self.unit, "setWorkAllowed", nil, true)
    end
  end
end

function t3:tick(started)
  local c, gt = self.c, self.gt

  if started then self:startCycle() end
  if self.pushed >= c.targetVolume then return end
  if not self.clock:working() then return end

  local now = computer.uptime()
  if now < self.nextTry then return end
  self.nextTry = now + (c.retryInterval or 2)

  local already = self:consumed()
  if already ~= nil and already + self.pushed >= c.targetVolume then
    self.pushed = c.targetVolume
    return
  end

  local fraction = self.clock:fraction()
  if self.pushed > 0 and fraction ~= nil and fraction > (c.topUpUntil or 0.6) then
    return
  end

  local have = self:buffer()
  local whole = have - (have % c.stepVolume)
  local want = math.min(c.targetVolume - self.pushed, whole)
  if want < c.stepVolume then return end

  local moved = self:send(want)
  if moved <= 0 then return end
  self.pushed = self.pushed + moved

  if self.pushed >= c.targetVolume then
    gt.info(self.cfg.log.verbose, "t3 c%d charged %s", self.clock.count, gt.num(self.pushed))
  else
    gt.info(self.cfg.log.verbose, "t3 c%d topped up to %s of %s, waiting on the recycler",
      self.clock.count, gt.num(self.pushed), gt.num(c.targetVolume))
  end
end

function t3:status()
  local info = self.gt.sensor(self.unit)
  local consumed = self.gt.prefixNumber(info, self.c.consumedPrefix, self.c.consumedLine)
  local chance = self.gt.prefixNumber(info, "Success chance:", 2)
  return string.format("t3 cycles=%d full=%d partial=%d empty=%d consumed=%s success=%s%%",
    self.stats.cycles, self.stats.full, self.stats.partial, self.stats.empty,
    self.gt.num(consumed or 0), tostring(chance))
end

return t3
