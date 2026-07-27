local computer = require("computer")

local power = {}
power.__index = power

local VOLTAGE = {
  LV = 32, MV = 128, HV = 512, EV = 2048, IV = 8192,
  LuV = 32768, ZPM = 131072, UV = 524288, UHV = 2097152,
  UEV = 8388608, UIV = 33554432,
}

local AMP_FRACTION = 15 / 16
local SETTERS = { "setMaxParallel", "setParallel", "setParallelism", "setBatchSize" }
local PARALLEL_PATTERN = "parallel[^%d]*(%d+)"

function power.new(cfg, gt, clock)
  local self = setmetatable({}, power)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.power
  self.units = {}

  for _, name in ipairs({ "t1", "t2", "t3", "t4" }) do
    local spec = self.c.units[name]
    local unitCfg = cfg[name]
    if spec and unitCfg and unitCfg.enabled and unitCfg.unitAddress ~= "" then
      local ok, proxy = pcall(gt.proxy, unitCfg.unitAddress, name)
      if ok then
        self.units[#self.units + 1] = {
          name = name,
          tier = spec.tier,
          proxy = proxy,
          draw = (VOLTAGE[spec.tier] or 0) * AMP_FRACTION,
        }
      end
    end
  end

  self.recommended = 1
  self.nextCheck = 0
  self.applied = {}
  self:recompute(true)
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

function power:recompute(announce)
  local budget = self:budget()
  local per = self:perParallel()
  if per <= 0 then return end

  self.recommended = math.max(1, math.floor(budget / per))
  if self.c.parallelCap and self.recommended > self.c.parallelCap then
    self.recommended = self.c.parallelCap
  end

  if not announce then return end
  print(string.format("power: %d EU/t usable after reserve, %d EU/t per parallel over %d units",
    math.floor(budget), math.floor(per), #self.units))
  print(string.format("power: set every unit to %d parallels, total draw %d EU/t, headroom %d EU/t",
    self.recommended, math.floor(self.recommended * per), math.floor(budget - self.recommended * per)))
  for _, u in ipairs(self.units) do
    print(string.format("  %s %-3s %d EU/t", u.name, u.tier, math.floor(u.draw * self.recommended)))
  end
end

function power:readParallel(u)
  return self.gt.matchNumber(self.gt.sensor(u.proxy), PARALLEL_PATTERN)
end

function power:apply(u, n)
  for _, name in ipairs(SETTERS) do
    if type(u.proxy[name]) == "function" then
      local ok = pcall(u.proxy[name], n)
      if ok then return name end
    end
  end
  return nil
end

function power:tick(started)
  local now = computer.uptime()
  if now < self.nextCheck then return end
  self.nextCheck = now + (self.c.checkInterval or 60)

  local gt = self.gt
  for _, u in ipairs(self.units) do
    local actual = self:readParallel(u)

    if actual == nil then
      if not self.applied[u.name .. ":unread"] then
        self.applied[u.name .. ":unread"] = true
        gt.log(true, "power: cannot read a parallel count from %s, adjust PARALLEL_PATTERN", u.name)
      end
    elseif actual ~= self.recommended then
      local method = self.c.autoApply and self:apply(u, self.recommended) or nil
      if method then
        gt.log(true, "power: %s parallels %d to %d via %s", u.name, actual, self.recommended, method)
      elseif actual > self.recommended then
        gt.log(true, "power: %s set to %d parallels, budget supports %d, expect a powerfail",
          u.name, actual, self.recommended)
      else
        gt.log(true, "power: %s set to %d parallels, budget supports %d, catalysts are being wasted",
          u.name, actual, self.recommended)
      end
    end
  end
end

function power:status()
  return string.format("power budget=%d perParallel=%d recommended=%d units=%d",
    math.floor(self:budget()), math.floor(self:perParallel()), self.recommended, #self.units)
end

return power
