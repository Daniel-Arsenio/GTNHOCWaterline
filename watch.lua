local watch = {}
watch.__index = watch

function watch.new(cfg, gt, clock)
  local self = setmetatable({}, watch)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.watch
  self.units = {}

  for _, name in ipairs({ "t1", "t2", "t3", "t4" }) do
    local unitCfg = cfg[name]
    if unitCfg and unitCfg.enabled and unitCfg.unitAddress ~= "" then
      local ok, proxy = pcall(gt.proxy, unitCfg.unitAddress, name)
      if ok then
        self.units[#self.units + 1] = { name = name, proxy = proxy, idle = 0 }
      end
    end
  end

  self.stats = { cycles = 0, idleCycles = 0 }
  return self
end

function watch:tick(started)
  if not started then return end
  local gt = self.gt
  self.stats.cycles = self.stats.cycles + 1

  for _, u in ipairs(self.units) do
    local active = gt.call(u.proxy, "isMachineActive", nil)
    if active == false then
      u.idle = u.idle + 1
      self.stats.idleCycles = self.stats.idleCycles + 1
      if u.idle == 1 or u.idle % (self.c.repeatEvery or 5) == 0 then
        gt.log(true, "watch: %s idle for %d cycle(s), check its inputs", u.name, u.idle)
      end
    else
      if u.idle >= (self.c.repeatEvery or 5) then
        gt.log(true, "watch: %s running again after %d idle cycle(s)", u.name, u.idle)
      end
      u.idle = 0
    end
  end
end

function watch:status()
  local parts = {}
  for _, u in ipairs(self.units) do
    parts[#parts + 1] = string.format("%s=%s", u.name, u.idle == 0 and "ok" or ("idle" .. u.idle))
  end
  return string.format("watch cycles=%d [%s]", self.stats.cycles, table.concat(parts, " "))
end

return watch
