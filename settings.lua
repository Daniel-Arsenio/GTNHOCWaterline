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

local function validate(defaults, user, path, problems)
  for key, value in pairs(user) do
    if type(key) ~= "number" and key ~= "__issues" then
      local here = path == "" and tostring(key) or (path .. "." .. tostring(key))
      if defaults[key] == nil then
        problems[#problems + 1] = here
      elseif type(value) == "table" and type(defaults[key]) == "table"
             and not isArray(value) and not isArray(defaults[key]) then
        validate(defaults[key], value, here, problems)
      end
    end
  end
end

local cfg = dofile(BASE .. "defaults.lua")

local ok, user = pcall(dofile, BASE .. "config.lua")
if not ok or type(user) ~= "table" then
  print("settings: config.lua missing or invalid, running on defaults")
  return cfg
end

local problems = {}
validate(cfg, user, "", problems)

table.sort(problems)

merge(cfg, user)
cfg.__issues = problems
return cfg
