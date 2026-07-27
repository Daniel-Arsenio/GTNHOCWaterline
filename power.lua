local power = {}
power.__index = power

local VOLTAGE = {
  LV = 32, MV = 128, HV = 512, EV = 2048, IV = 8192,
  LuV = 32768, ZPM = 131072, UV = 524288, UHV = 2097152,
  UEV = 8388608, UIV = 33554432,
}

local AMP_FRACTION = 15 / 16

function power.new(cfg, gt, clock)
  local self = setmetatable({}, power)
  self.cfg, self.gt, self.c = cfg, gt, cfg.power

  self.units = {}
  for _, name in ipairs({ "t1", "t2", "t3", "t4" }) do
    local spec = self.c.units[name]
    if spec and cfg[name] and cfg[name].enabled then
      self.units[#self.units + 1] = {
        name = name,
        tier = spec.tier,
        draw = (VOLTAGE[spec.tier] or 0) * AMP_FRACTION,
      }
    end
  end

  self:report()
  return self
end

function power:budget()
  local total = 0
  for _, h in ipairs(self.c.hatches) do
    total = total + (h.amps or 0) * (VOLTAGE[h.tier] or 0)
  end
  return total * (1 - (self.c.reserveFraction or 0))
end

function power:perParallel()
  local total = 0
  for _, u in ipairs(self.units) do total = total + u.draw end
  return total
end

function power:parallels()
  local per = self:perParallel()
  if per <= 0 then return 0 end
  local n = math.max(1, math.floor(self:budget() / per))
  if self.c.parallelCap and n > self.c.parallelCap then n = self.c.parallelCap end
  return n
end

function power:report()
  local per = self:perParallel()
  if per <= 0 then
    print("power: no units enabled")
    return
  end

  local budget, n = self:budget(), self:parallels()
  print(string.format("power: %d EU/t usable after reserve", math.floor(budget)))
  print(string.format("power: %d EU/t per parallel across %d unit(s)", math.floor(per), #self.units))
  print(string.format("power: set every unit to %d parallels", n))
  print(string.format("power: draw %d EU/t, headroom %d EU/t",
    math.floor(n * per), math.floor(budget - n * per)))
  for _, u in ipairs(self.units) do
    print(string.format("  %s %-3s %d EU/t", u.name, u.tier, math.floor(u.draw * n)))
  end
end

function power:tick(started)
end

function power:status()
  return string.format("power budget=%d perParallel=%d parallels=%d",
    math.floor(self:budget()), math.floor(self:perParallel()), self:parallels())
end

return power