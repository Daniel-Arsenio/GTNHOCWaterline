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

  local side, tank = gt.findFluid(self.trans, self.c.fluidName, { [self.sink] = true })
  if side == nil then
    error("no " .. self.c.fluidName .. " found on any side of the t3 transposer", 0)
  end
  self.source, self.tank = side, tank
  print(string.format("t3: flocculant on side %d tank %d", side, tank))

  self.charged = false
  self.stats = { cycles = 0, charged = 0, short = 0 }
  return self
end

function t3:consumed()
  local info = self.gt.sensor(self.unit)
  return self.gt.lineNumber(info, self.c.consumedLine, self.c.consumedPrefix)
end

function t3:tick(started)
  local c, gt = self.c, self.gt

  if started then
    self.stats.cycles = self.stats.cycles + 1
    self.charged = false
  end

  if self.charged then return end
  if not self.clock:working() then return end

  local already = self:consumed()
  if already ~= nil and already >= c.targetVolume then
    self.charged = true
    return
  end

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

  local moved = gt.pushFluid(self.trans, self.source, self.sink, want, self.tank)
  self.charged = true

  if moved ~= want then
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
