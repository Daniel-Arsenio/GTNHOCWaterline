local component = require("component")

local RELEVANT = {
  gt_machine = true,
  transposer = true,
  me_interface = true,
  me_controller = true,
}

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

  if ctype == "transposer" then
    local sides = require("sides")
    local seen = {}
    for name, side in pairs(sides) do
      if type(side) == "number" and #name > 1 then
        local okT, tanks = pcall(dev.getFluidInTank, side)
        if okT and type(tanks) == "table" and tanks[1] and (tanks[1].capacity or 0) > 0 then
          seen[#seen + 1] = string.format("%s:%s", name, tanks[1].label or "empty")
        end
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
