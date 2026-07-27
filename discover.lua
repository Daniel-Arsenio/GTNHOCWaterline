local component = require("component")

local RELEVANT = setmetatable({
  gt_machine = true,
  transposer = true,
}, {
  __index = function(_, key)
    if type(key) ~= "string" then return false end
    return key:sub(1, 3) == "me_" or key:find("interface", 1, true) ~= nil
  end,
})

local function describe(address, ctype)
  local ok, dev = pcall(component.proxy, address)
  if not ok then return "?" end

  if ctype == "gt_machine" then
    local okName, name = pcall(dev.getName)
    if okName and type(name) == "string" and #name > 0 then return name end
    local okInfo, info = pcall(dev.getSensorInformation)
    if okInfo and type(info) == "table" and info[1] then
      return (info[1]:gsub("\194\167.", ""):gsub("\167.", ""))
    end
  end

  if ctype:sub(1, 3) == "me_" or ctype:find("interface", 1, true) then
    local bits = {}
    local function try(method)
      local ok, result = pcall(dev[method])
      if ok and type(result) == "table" then return tostring(#result) end
      return "no"
    end
    bits[#bits + 1] = "craftables=" .. try("getCraftables")
    bits[#bits + 1] = "fluids=" .. try("getFluidsInNetwork")
    bits[#bits + 1] = "cpus=" .. try("getCpus")
    return table.concat(bits, " ")
  end

  if ctype == "transposer" then
    local names = { [0] = "bottom", "top", "north", "south", "west", "east" }
    local seen = {}
    for side = 0, 5 do
      local bits = {}
      local tanks = 0
      local okCount, count = pcall(dev.getTankCount, side)
      if okCount and type(count) == "number" then tanks = count end
      for tank = 1, tanks do
        local okT, fluid = pcall(dev.getFluidInTank, side, tank)
        if okT and type(fluid) == "table" and (fluid.capacity or 0) > 0 then
          bits[#bits + 1] = string.format("%s %d/%d",
            fluid.name or "empty", fluid.amount or 0, fluid.capacity or 0)
        end
      end
      local okS, stacks = pcall(dev.getAllStacks, side)
      if okS and stacks ~= nil then bits[#bits + 1] = "inventory" end
      if #bits > 0 then
        seen[#seen + 1] = names[side] .. "(" .. side .. ")=" .. table.concat(bits, ",")
      end
    end
    if #seen > 0 then return table.concat(seen, " ") end
  end

  return ctype
end

local rows = {}
for address, ctype in component.list() do
  rows[#rows + 1] = {
    address = address,
    ctype = ctype,
    info = RELEVANT[ctype] and describe(address, ctype) or "",
    mark = RELEVANT[ctype] and "*" or " ",
  }
end

table.sort(rows, function(a, b)
  if a.ctype ~= b.ctype then return a.ctype < b.ctype end
  return a.address < b.address
end)

print(string.format("  %-8s %-14s %s", "prefix", "type", "identity"))
for _, r in ipairs(rows) do
  print(string.format("%s %-8s %-14s %s", r.mark, r.address:sub(1, 8), r.ctype, r.info))
end
print("")
print(#rows .. " components, * marks ones this program can use")
print("paste the prefix into config.lua, it does not need the full address")
print("a missing me_interface usually means an MFU is sitting in that adapter")
