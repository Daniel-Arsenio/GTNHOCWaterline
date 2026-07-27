local sides = require("sides")

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
    error("no " .. self.c.fluidName .. " on the t3 transposer, sink is side " ..
      tostring(self.sink) .. " (" .. tostring(gt.SIDE_NAME[self.sink]) ..
      "), fill the buffer tank and check t3.sinkSide", 0)
  end
  if side == self.sink then
    error("t3 source and sink are both side " .. tostring(side) ..
      ", set t3.sinkSide to the face the hatch is on", 0)
  end

  self.source, self.tank = side, tank
  print(string.format("t3  %s tank %d (%s) -> %s",
    gt.SIDE_NAME[side] or side, tank, gt.num(amount or 0),
    gt.SIDE_NAME[self.sink] or self.sink))

  self.charged = false
  self.stats = { cycles = 0, charged = 0, short = 0 }
  return self
end

function t3:consumed()
  local gt = self.gt
  local info = gt.sensor(self.unit)
  local value, line = gt.prefixNumber(info, self.c.consumedPrefix, nil)

  if value == nil then
    if not self.warnedLine then
      self.warnedLine = true
      gt.warn("t3: no line matching %q, falling back to line %d",
        self.c.consumedPrefix, self.c.consumedLine)
      gt.dumpSensor(info, "flocculation unit")
    end
    return gt.lineNumber(info, self.c.consumedLine, self.c.consumedPrefix)
  end

  if self.foundLine ~= line then
    self.foundLine = line
    gt.warn("t3: reading consumption from sensor line %d", line)
  end
  return value
end

function t3:tick(started)
  local c, gt = self.c, self.gt

  if started then
    self.stats.cycles = self.stats.cycles + 1
    self.charged = false

    local warn = (c.bufferWarnCycles or 0) * c.targetVolume
    if warn > 0 then
      local fluid = gt.call(self.trans, "getFluidInTank", nil, self.source, self.tank)
      local have = type(fluid) == "table" and (fluid.amount or 0) or 0
      if have < warn and not self.bufferWarned then
        self.bufferWarned = true
        gt.warn("t3 buffer %s, %.1f charges left, check the export bus",
          gt.num(have), have / c.targetVolume)
      elseif have >= warn and self.bufferWarned then
        self.bufferWarned = false
        gt.info(self.cfg.log.verbose, "t3 buffer recovered to %s", gt.num(have))
      end
    end
  end

  if self.charged then return end

  if not self.clock:working() then
    if self.reason ~= "idle" then
      self.reason = "idle"
      gt.warn("t3: waiting, the plant reports no work")
    end
    return
  end

  local already = self:consumed()
  if already ~= nil and already >= c.targetVolume then
    self.charged = true
    if self.reason ~= "done" then
      self.reason = "done"
      gt.warn("t3: sensor already reports %d L consumed, skipping the charge", already)
    end
    return
  end
  self.reason = nil

  local available = gt.call(self.trans, "getFluidInTank", nil, self.source, self.tank)
  local stocked = type(available) == "table" and (available.amount or 0) or 0
  local want = c.targetVolume

  if stocked < c.targetVolume then
    want = stocked - (stocked % c.stepVolume)
    self.stats.short = self.stats.short + 1
    gt.warn("t3 cycle %d: only %d L flocculant buffered, charging %d L",
      self.clock.count, stocked, want)
    if c.haltWhenShort then
      gt.call(self.unit, "setWorkAllowed", nil, false)
    end
  end

  if want <= 0 then
    self.charged = true
    return
  end

  gt.warn("t3 cycle %d: moving %d L from %s tank %d to %s",
    self.clock.count, want, gt.SIDE_NAME[self.source] or self.source, self.tank,
    gt.SIDE_NAME[self.sink] or self.sink)

  local moved, why = gt.pushFluid(self.trans, self.source, self.sink, want, self.tank)

  if moved == 0 and c.stepVolume > 0 and want > c.stepVolume then
    gt.warn("t3: one shot of %s failed (%s), retrying in %s chunks",
      gt.num(want), tostring(why), gt.num(c.stepVolume))

    local total = 0
    while total < want do
      local chunk = math.min(c.stepVolume, want - total)
      local got, err = gt.pushFluid(self.trans, self.source, self.sink, chunk, self.tank)
      if got == 0 then
        gt.warn("t3: chunk of %s also failed (%s)", gt.num(chunk), tostring(err))
        break
      end
      total = total + got
    end
    moved = total
  end

  self.charged = true

  if moved == 0 then
    gt.warn("t3: nothing moved (%s). check the transposer pump tier and that %s is the hatch",
      tostring(why), gt.SIDE_NAME[self.sink] or self.sink)
  elseif moved ~= want then
    gt.warn("t3 c%d asked %s moved %s, raise the transposer pump tier",
      self.clock.count, gt.num(want), gt.num(moved))
  else
    self.stats.charged = self.stats.charged + 1
    gt.info(self.cfg.log.verbose, "t3 c%d charged %s", self.clock.count, gt.num(moved))
  end
end

function t3:status()
  local consumed = self:consumed()
  local chance = self.gt.lineNumber(self.gt.sensor(self.unit), 2, "Success chance:")
  return string.format("t3 cycles=%d charged=%d short=%d consumed=%s success=%s%%",
    self.stats.cycles, self.stats.charged, self.stats.short,
    tostring(consumed), tostring(chance))
end

return t3
