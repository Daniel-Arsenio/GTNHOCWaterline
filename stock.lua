local computer = require("computer")

local function filterText(filter)
  if type(filter) ~= "table" then return tostring(filter) end
  local parts = {}
  for key, value in pairs(filter) do
    parts[#parts + 1] = key .. "=" .. tostring(value)
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

local stock = {}
stock.__index = stock

function stock.new(cfg, gt, clock)
  local self = setmetatable({}, stock)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.stock
  self.me, self.address = gt.network(self.c.interfaceAddress, "getItemsInNetwork", "stock.interfaceAddress")
  self.jobs = {}
  self.alarmed = {}
  self.lastLevel = {}
  self.jobSeen = {}
  self.trend = {}
  self.noPatternSeen = {}

  local overrides = self.c.overrides or {}
  for _, entry in ipairs(self.c.entries) do
    local patch = overrides[entry.key]
    if type(patch) == "table" then
      for key, value in pairs(patch) do entry[key] = value end
      gt.info(cfg.log.verbose, "stock: %s overridden", entry.key)
    end
  end
  self.nextCheck = 0
  self.stats = { requested = 0, done = 0, failed = 0, noPattern = 0 }
  return self
end

function stock:amount(entry)
  local gt = self.gt
  if entry.kind == "fluid" then
    local list = gt.call(self.me, "getFluidsInNetwork", nil)
    if type(list) ~= "table" then return nil end
    for _, f in ipairs(list) do
      if f.label == entry.label or f.name == entry.label then return f.amount or 0 end
    end
    return 0
  end

  local list = gt.call(self.me, "getItemsInNetwork", nil, entry.filter)
  if type(list) ~= "table" then return nil end
  local total = 0
  for _, s in ipairs(list) do total = total + (s.size or 0) end
  return total
end

function stock:cpuAvailable()
  local cpus = self.gt.call(self.me, "getCpus", nil)
  if type(cpus) ~= "table" then return true end
  local free = 0
  for _, c in ipairs(cpus) do
    if c.busy == false then free = free + 1 end
  end
  return free > (self.c.reserveCpus or 0)
end

function stock:request(entry, count)
  local gt = self.gt
  local list = gt.call(self.me, "getCraftables", nil, entry.craftFilter or entry.filter)
  if type(list) ~= "table" or #list == 0 then
    self.stats.noPattern = self.stats.noPattern + 1
    gt.warn("stock: no craftable pattern matches %s, run craftables.lua", entry.key)
    return nil
  end
  local ok, job = pcall(list[1].request, count)
  if not ok or job == nil then
    gt.warn("stock: request for %s rejected: %s", entry.key, tostring(job))
    return nil
  end
  self.stats.requested = self.stats.requested + 1
  gt.info(self.cfg.log.verbose, "stock: requested %d %s", count, entry.key)
  return job
end

function stock:settled(key, job)
  local gt = self.gt
  local ok, done = pcall(job.isDone)
  if ok and done then
    self.stats.done = self.stats.done + 1
    return true
  end
  local okc, cancelled = pcall(job.isCanceled)
  if okc and cancelled then
    self.stats.failed = self.stats.failed + 1
    gt.warn("stock: craft of %s was cancelled, check patterns and ingredients", key)
    return true
  end
  return false
end

function stock:trendReport(entry, have)
  local t = self.trend[entry.key]

  if t == nil or self.jobSeen[entry.key] then
    self.trend[entry.key] = { first = have, cycles = 0 }
    return
  end

  t.cycles = t.cycles + 1

  local every = entry.trendEvery or 10
  if t.cycles < every then return end

  local net = have - t.first
  local rate = net / t.cycles

  if math.abs(rate) < (entry.trendDeadband or 1) then
    self.gt.info(self.cfg.log.verbose, "stock: %s stable over %d cycles, loop is closed",
      entry.key, t.cycles)
  elseif rate < 0 then
    self.gt.warn("stock: %s losing %d per cycle over %d cycles, something is voiding",
      entry.key, math.floor(-rate), t.cycles)
  else
    self.gt.info(self.cfg.log.verbose, "stock: %s gaining %d per cycle", entry.key, math.floor(rate))
  end

  self.trend[entry.key] = { first = have, cycles = 0 }
end

function stock:audit()
  for _, entry in ipairs(self.c.entries) do
    if entry.trackTrend then
      local have = self:amount(entry)
      if have ~= nil then self:trendReport(entry, have) end
    end

    if entry.expectedPerCycle then
      local have = self:amount(entry)
      local last = self.lastLevel[entry.key]
      if have and last and not self.jobSeen[entry.key] then
        local used = last - have
        if used < entry.expectedPerCycle * (self.c.consumptionTolerance or 0.5) then
          self.gt.warn("stock: %s drew %d last cycle, expected about %d, the hatch may not be consuming it",
            entry.key, used, entry.expectedPerCycle)
        end
      end
      self.lastLevel[entry.key] = have
    end
  end
  self.jobSeen = {}
end

function stock:tick(started)
  local now = computer.uptime()

  for key, job in pairs(self.jobs) do
    self.jobSeen[key] = true
    if self:settled(key, job) then self.jobs[key] = nil end
  end

  if started then self:audit() end

  if now < self.nextCheck then return end
  self.nextCheck = now + self.c.checkInterval

  for _, entry in ipairs(self.c.entries) do
    if self.jobs[entry.key] == nil then
      local have = self:amount(entry)
      if have == nil then
        self.gt.warn("stock: cannot read network level for %s", entry.key)
      elseif have < entry.target then
        if entry.alarmOnly then
          if not self.alarmed[entry.key] then
            self.alarmed[entry.key] = true
            self.gt.warn("stock: %s down to %d of %d, the recycling loop is losing ground",
              entry.key, have, entry.target)
          end
        elseif self:cpuAvailable() then
          local want = math.min(entry.batch, entry.target - have)
          self.gt.info(self.cfg.log.verbose, "stock: %s at %s of %s using %s",
            entry.key, self.gt.num(have), self.gt.num(entry.target), filterText(entry.filter))
          local job = self:request(entry, want)
          if job then self.jobs[entry.key] = job end
        end
      else
        self.alarmed[entry.key] = nil
      end
    end
  end
end

function stock:status()
  local pending = 0
  for _ in pairs(self.jobs) do pending = pending + 1 end
  return string.format("stock requested=%d done=%d cancelled=%d noPattern=%d pending=%d",
    self.stats.requested, self.stats.done, self.stats.failed, self.stats.noPattern, pending)
end

return stock
