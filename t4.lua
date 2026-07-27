local computer = require("computer")

local t4 = {}
t4.__index = t4

local PH_PATTERN = "ph[^%d%-]*(%d+%.?%d*)"

function t4.new(cfg, gt, clock)
  local self = setmetatable({}, t4)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.t4
  self.unit = gt.proxy(self.c.unitAddress, "pH neutralisation unit")
  self.acidT = gt.proxy(self.c.acid.transposerAddress, "t4 acid transposer")
  self.baseT = gt.proxy(self.c.base.transposerAddress, "t4 base transposer")
  self.nextDose = 0
  self.startPh = nil
  self.stats = { cycles = 0, inBand = 0, outOfBand = 0, doses = 0, noRead = 0 }
  return self
end

function t4:readPh()
  return self.gt.matchNumber(self.gt.sensor(self.unit), PH_PATTERN)
end

function t4:inputsClear()
  local c, gt = self.c, self.gt
  if gt.tankTotals(self.acidT, c.acid.hatchSide) > 0 then return false end
  if gt.countItems(self.baseT, c.base.busSide, nil) > 0 then return false end
  return true
end

function t4:tick(started)
  local c, gt = self.c, self.gt
  local now = computer.uptime()
  local ph = self:readPh()

  if started then
    if self.startPh then
      if math.abs(self.startPh - c.targetPh) <= 0.05 then
        self.stats.inBand = self.stats.inBand + 1
      else
        self.stats.outOfBand = self.stats.outOfBand + 1
        gt.log(true, "t4 cycle %d finished at pH %.2f, outside the 6.95 to 7.05 band",
          self.clock.count - 1, self.startPh)
      end
    end
    self.stats.cycles = self.stats.cycles + 1
    self.startPh = nil
    if ph then
      gt.log(self.cfg.log.verbose, "t4 cycle %d: starting pH %.2f", self.clock.count, ph)
    end
  end

  if ph == nil then
    self.stats.noRead = self.stats.noRead + 1
    return
  end
  self.startPh = ph

  if ph < c.minSanePh or ph > c.maxSanePh then
    gt.log(true, "t4 pH %.2f outside the sane range, not dosing", ph)
    return
  end
  if gt.call(self.unit, "isMachineActive", nil) == false then return end
  if now < self.nextDose then return end
  if not self:inputsClear() then return end

  local err = c.targetPh - ph
  if math.abs(err) <= c.deadband then return end

  local steps = math.floor(math.abs(err) * 100 + 0.5)
  if steps == 0 then return end

  if err > 0 then
    local moved = gt.pushItems(self.baseT, c.base.sourceSide, c.base.busSide, steps, c.base.sourceSlot)
    gt.log(self.cfg.log.verbose, "t4 pH %.2f, sodium hydroxide %d of %d", ph, moved, steps)
    if moved < steps then
      gt.log(true, "t4: short %d dust, check the ME interface stock", steps - moved)
    end
  else
    local litres = steps * c.litresPerStep
    local moved = gt.pushFluid(self.acidT, c.acid.sourceSide, c.acid.hatchSide, litres)
    gt.log(self.cfg.log.verbose, "t4 pH %.2f, hydrochloric acid %d L of %d L", ph, moved, litres)
    if moved < litres then
      gt.log(true, "t4: short %d L acid, check the buffer tank", litres - moved)
    end
  end

  self.stats.doses = self.stats.doses + 1
  self.nextDose = now + c.doseInterval
end

function t4:status()
  return string.format("t4 cycles=%d inBand=%d missed=%d doses=%d noRead=%d",
    self.stats.cycles, self.stats.inBand, self.stats.outOfBand, self.stats.doses, self.stats.noRead)
end

return t4
