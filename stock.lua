local computer = require("computer")

local stock = {}
stock.__index = stock

function stock.new(cfg, gt, clock)
  local self = setmetatable({}, stock)
  self.cfg, self.gt, self.clock, self.c = cfg, gt, clock, cfg.stock
  self.me = gt.proxy(self.c.interfaceAddress, "ME interface")
  self.jobs = {}
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
      if f.label == entry.label or f.name == entry.name then return f.amount or 0 end
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
  local list = gt.call(self.me, "getCraftables", nil, entry.filter)
  if type(list) ~= "table" or #list == 0 then
    self.stats.noPattern = self.stats.noPattern + 1
    gt.log(true, "stock: no craftable pattern matches %s, run craftables.lua", entry.key)
    return nil
  end
  local ok, job = pcall(list[1].request, count)
  if not ok or job == nil then
    gt.log(true, "stock: request for %s rejected: %s", entry.key, tostring(job))
    return nil
  end
  self.stats.requested = self.stats.requested + 1
  gt.log(self.cfg.log.verbose, "stock: requested %d %s", count, entry.key)
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
    gt.log(true, "stock: craft of %s was cancelled, check patterns and ingredients", key)
    return true
  end
  return false
end

function stock:tick(started)
  local now = computer.uptime()

  for key, job in pairs(self.jobs) do
    if self:settled(key, job) then self.jobs[key] = nil end
  end

  if now < self.nextCheck then return end
  self.nextCheck = now + self.c.checkInterval

  for _, entry in ipairs(self.c.entries) do
    if self.jobs[entry.key] == nil then
      local have = self:amount(entry)
      if have == nil then
        self.gt.log(true, "stock: cannot read network level for %s", entry.key)
      elseif have < entry.target then
        if self:cpuAvailable() then
          local want = math.min(entry.batch, entry.target - have)
          local job = self:request(entry, want)
          if job then self.jobs[entry.key] = job end
        end
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
