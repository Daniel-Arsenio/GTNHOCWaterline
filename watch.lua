local watch = {}
watch.__index = watch

function watch.new(cfg, gt, clock)
  local self = setmetatable({}, watch)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.watch
  self.stats = { cycles = 0, alerts = 0 }

  if self.c.mode == "units" then
    self.units = {}
    for _, name in ipairs({ "t1", "t2", "t3", "t4" }) do
      local unitCfg = cfg[name]
      if unitCfg and unitCfg.enabled then
        local ok, proxy = pcall(gt.machineFor, unitCfg.unitAddress, gt.MACHINE[name], name)
        if ok and proxy then
          self.units[#self.units + 1] = { name = name, proxy = proxy, idle = 0 }
        end
      end
    end
    if #self.units == 0 then
      error("mode is 'units' but no unit adapters are reachable", 0)
    end
    print("watch: monitoring " .. #self.units .. " unit controller(s)")
    return self
  end

  self.me = gt.network(self.c.interfaceAddress, "getFluidsInNetwork", "watch.interfaceAddress")
  self.tracked = {}
  for _, f in ipairs(self.c.fluids) do
    self.tracked[#self.tracked + 1] = { key = f.key, label = f.label, last = nil, stale = 0 }
  end
  print("watch: monitoring " .. #self.tracked .. " water grade(s) through the network")
  return self
end

function watch:tickUnits()
  local gt = self.gt
  for _, u in ipairs(self.units) do
    local active = gt.call(u.proxy, "hasWork", nil)
    if active == false then
      u.idle = u.idle + 1
      if u.idle == 1 or u.idle % (self.c.repeatEvery or 5) == 0 then
        self.stats.alerts = self.stats.alerts + 1
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

function watch:tickNetwork()
  local gt = self.gt
  local list = gt.call(self.me, "getFluidsInNetwork", nil)
  if type(list) ~= "table" then return end

  local level = {}
  for _, f in ipairs(list) do
    if f.label then level[f.label] = f.amount or 0 end
    if f.name then level[f.name] = f.amount or 0 end
  end

  for _, t in ipairs(self.tracked) do
    local now = level[t.label] or 0
    if t.last ~= nil and now == t.last then
      t.stale = t.stale + 1
      local threshold = self.c.staleCycles or 3
      if t.stale == threshold or (t.stale > threshold and t.stale % (self.c.repeatEvery or 5) == 0) then
        self.stats.alerts = self.stats.alerts + 1
        gt.log(true, "watch: %s flat at %d L for %d cycles, that stage has stalled",
          t.key, now, t.stale)
      end
    else
      if t.stale >= (self.c.staleCycles or 3) then
        gt.log(true, "watch: %s moving again after %d flat cycles", t.key, t.stale)
      end
      t.stale = 0
    end
    t.last = now
  end
end

function watch:tick(started)
  if not started then return end
  self.stats.cycles = self.stats.cycles + 1
  if self.units then self:tickUnits() else self:tickNetwork() end
end

function watch:status()
  local parts = {}
  if self.units then
    for _, u in ipairs(self.units) do
      parts[#parts + 1] = string.format("%s=%s", u.name, u.idle == 0 and "ok" or ("idle" .. u.idle))
    end
  else
    for _, t in ipairs(self.tracked) do
      parts[#parts + 1] = string.format("%s=%s", t.key, t.stale == 0 and "ok" or ("flat" .. t.stale))
    end
  end
  return string.format("watch cycles=%d alerts=%d [%s]",
    self.stats.cycles, self.stats.alerts, table.concat(parts, " "))
end

return watch
