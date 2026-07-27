local BASE = "/home/waterline/"

local function isArray(t)
  return type(t) == "table" and #t > 0
end

local function merge(base, over)
  for key, value in pairs(over) do
    if type(value) == "table" and type(base[key]) == "table"
       and not isArray(value) and not isArray(base[key]) then
      merge(base[key], value)
    else
      base[key] = value
    end
  end
  return base
end

local cfg = dofile(BASE .. "defaults.lua")

local ok, user = pcall(dofile, BASE .. "config.lua")
if ok and type(user) == "table" then
  merge(cfg, user)
else
  print("settings: config.lua missing or invalid, running on defaults")
end

return cfg