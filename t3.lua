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
  print(string.format("t3: flocculant from %s tank %d (%d L), into %s",
    gt.SIDE_NAME[side] or side, tank, amount or 0, gt.SIDE_NAME[self.sink] or self.sink))

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
      gt.log(true, "t3: no line matching %q, falling back to line %d",
        self.c.consumedPrefix, self.c.consumedLine)
      gt.dumpSensor(info, "flocculation unit")
    end
    return gt.lineNumber(info, self.c.consumedLine, self.c.consumedPrefix)
  end

  if self.foundLine ~= line then
    self.foundLine = line
    gt.log(true, "t3: reading consumption from sensor line %d", line)
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
      if have < warn then
        gt.log(true, "t3: buffer down to %d L, %.1f cycles left, check the export bus",
          have, have / c.targetVolume)
      end
    end
  end

  if self.charged then return end

  if not self.clock:working() then
    if self.reason ~= "idle" then
      self.reason = "idle"
      gt.log(true, "t3: waiting, the plant reports no work")
    end
    return
  end

  local already = self:consumed()
  if already ~= nil and already >= c.targetVolume then
    self.charged = true
    if self.reason ~= "done" then
      self.reason = "done"
      gt.log(true, "t3: sensor already reports %d L consumed, skipping the charge", already)
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
    gt.log(true, "t3 cycle %d: only %d L flocculant buffered, charging %d L",
      self.clock.count, stocked, want)
    if c.haltWhenShort then
      gt.call(self.unit, "setWorkAllowed", nil, false)
    end
  end

  if want <= 0 then
    self.charged = true
    return
  end

  gt.log(true, "t3 cycle %d: moving %d L from %s tank %d to %s",
    self.clock.count, want, gt.SIDE_NAME[self.source] or self.source, self.tank,
    gt.SIDE_NAME[self.sink] or self.sink)

  local moved = gt.pushFluid(self.trans, self.source, self.sink, want, self.tank)
  self.charged = true

  if moved == 0 then
    gt.log(true, "t3: nothing moved. the sink side is probably wrong, %s must be the face " ..
      "the flocculant hatch is on. set t3.sinkSide.", gt.SIDE_NAME[self.sink] or self.sink)
  elseif moved ~= want then
    gt.log(true, "t3 cycle %d: asked for %d L, moved %d L, check the transposer pump tier",
      self.clock.count, want, moved)
  else
    self.stats.charged = self.stats.charged + 1
    gt.log(self.cfg.log.verbose, "t3 cycle %d: charged %d L", self.clock.count, moved)
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
