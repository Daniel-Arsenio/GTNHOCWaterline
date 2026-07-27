local component = require("component")

local tui = {}

local gpu = component.isAvailable("gpu") and component.gpu or nil

-- Mediterranean palette. Body text and values sit in the foam whites, structure in the
-- blues, state in the sea greens, and only the two things you must act on break out into
-- sand and coral. Every foreground is checked for contrast against the deep navy ground.
tui.c = {
  ground = 0x011627,  -- deep water, screen background
  rule   = 0x2A6F97,  -- mediterranean blue, dividers
  head   = 0x48CAE4,  -- shallow water cyan, headers
  key    = 0x5FA8D3,  -- azure, field and column names
  text   = 0xCAE9F5,  -- sea foam, body text
  val    = 0xEAF6FB,  -- foam white, values
  bright = 0xFFFFFF,  -- surf white, emphasis
  dim    = 0x6E93A3,  -- wet slate, recessive context
  ok     = 0x2EC4B6,  -- turquoise, healthy
  cool   = 0x00B4D8,  -- azure, informational highlight
  warn   = 0xE9C46A,  -- sand, degraded but running
  bad    = 0xE76F51,  -- terracotta, failure
  accent = 0xF4A261,  -- sunset, the one thing to act on
}

function tui.width()
  if gpu == nil then return 80 end
  local w = gpu.getResolution()
  return w or 80
end

function tui.height()
  if gpu == nil then return 25 end
  local _, h = gpu.getResolution()
  return h or 25
end

function tui.maximise()
  if gpu == nil then return 80, 25 end
  local mw, mh = gpu.maxResolution()
  gpu.setResolution(mw, mh)
  return mw, mh
end

function tui.set(colour)
  if gpu then gpu.setForeground(colour) end
end

function tui.theme()
  if gpu == nil then return end
  local w, h = gpu.getResolution()
  tui.previousBackground = gpu.setBackground(tui.c.ground)
  gpu.setForeground(tui.c.text)
  gpu.fill(1, 1, w, h, " ")
end

function tui.untheme()
  if gpu == nil then return end
  local w, h = gpu.getResolution()
  gpu.setBackground(tui.previousBackground or 0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
end

function tui.reset()
  tui.set(tui.c.text)
end

function tui.write(colour, text)
  tui.set(colour)
  io.write(text)
end

function tui.line(...)
  local args = { ... }
  for i = 1, #args - 1, 2 do
    tui.write(args[i], tostring(args[i + 1]))
  end
  tui.reset()
  io.write("\n")
end

function tui.pad(text, width, right)
  text = tostring(text)
  width = tonumber(width) or #text
  if #text > width then
    if width <= 1 then return text:sub(1, width) end
    return text:sub(1, width - 1) .. "~"
  end
  local gap = string.rep(" ", width - #text)
  if right then return gap .. text end
  return text .. gap
end

function tui.rule(colour)
  tui.write(colour or tui.c.rule, string.rep("\226\148\128", tui.width() - 1))
  tui.reset()
  io.write("\n")
end

function tui.header(title, subtitle)
  tui.set(tui.c.head)
  io.write(title)
  if subtitle then
    tui.set(tui.c.dim)
    io.write("   " .. subtitle)
  end
  tui.reset()
  io.write("\n")
  tui.rule()
end

function tui.columns(items, colour, minWidth)
  if #items == 0 then return end
  local widest = minWidth or 0
  for _, item in ipairs(items) do
    if #item > widest then widest = #item end
  end
  widest = widest + 2

  local perRow = math.max(1, math.floor((tui.width() - 2) / widest))
  local row = ""
  for index, item in ipairs(items) do
    row = row .. tui.pad(item, widest)
    if index % perRow == 0 then
      tui.line(colour or tui.c.text, "  " .. row)
      row = ""
    end
  end
  if row ~= "" then tui.line(colour or tui.c.text, "  " .. row) end
end

function tui.bar(fraction, width, full, empty)
  local filled = math.floor(fraction * width + 0.5)
  return (full or "\226\150\136"):rep(filled) .. (empty or "\226\150\145"):rep(width - filled)
end

function tui.state(text)
  local lower = tostring(text):lower()
  if lower:find("ok", 1, true) or lower == "yes" or lower == "true" then return tui.c.ok end
  if lower:find("unset", 1, true) or lower == "-" or lower == "" then return tui.c.dim end
  return tui.c.bad
end

return tui
