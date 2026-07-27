local sides = require("sides")

return {
  pollInterval = 0.2,
  log = { verbose = true },

  cycleAddress = "",

  cycle = {
    seconds = 120,
  },

  power = {
    enabled = true,
    reserveFraction = 0.05,
    parallelCap = nil,
    hatches = {
      { amps = 64, tier = "LuV" },
    },
    units = {
      t1 = { tier = "LuV" },
      t2 = { tier = "LuV" },
      t3 = { tier = "ZPM" },
      t4 = { tier = "ZPM" },
    },
  },

  stock = {
    enabled = false,
    interfaceAddress = { "" },
    checkInterval = 10,
    reserveCpus = 1,
    consumptionTolerance = 0.5,
    entries = {
      {
        key = "carbon filter",
        kind = "item",
        filter = { label = "Activated Carbon Filter" },
        target = 64,
        batch = 32,
      },
      {
        key = "ozone",
        kind = "fluid",
        label = "Ozone",
        filter = { label = "Ozone" },
        target = 8000000,
        batch = 4000000,
        expectedPerCycle = 1024000,
      },
      {
        key = "sodium hydroxide",
        kind = "item",
        filter = { label = "Sodium Hydroxide Dust" },
        target = 4096,
        batch = 2048,
      },
      {
        key = "hydrochloric acid",
        kind = "fluid",
        label = "Hydrochloric Acid",
        filter = { label = "Hydrochloric Acid" },
        target = 512000,
        batch = 256000,
      },
      {
        key = "polyaluminium chloride",
        kind = "fluid",
        label = "Polyaluminium Chloride",
        filter = { label = "Polyaluminium Chloride" },
        target = 3600000,
        batch = 900000,
        alarmOnly = true,
      },
    },
  },

  watch = {
    enabled = true,
    mode = "network",
    repeatEvery = 5,
    staleCycles = 3,
    interfaceAddress = { "" },
    fluids = {
      { key = "grade 1", label = "Grade 1 Purified Water" },
      { key = "grade 2", label = "Grade 2 Purified Water" },
      { key = "grade 3", label = "Grade 3 Purified Water" },
      { key = "grade 4", label = "Grade 4 Purified Water" },
    },
  },

  t1 = {
    enabled = true,
    unitAddress = "",
  },

  t2 = {
    enabled = true,
    unitAddress = "",
    interfaceAddress = "",
    ozoneLabel = "Ozone",
    minBufferCycles = 3,
    gateUntilFull = false,
    recipeTiers = {
      { volume = 128000, chance = 20 },
      { volume = 256000, chance = 40 },
      { volume = 512000, chance = 60 },
      { volume = 1024000, chance = 80 },
    },
  },

  t3 = {
    enabled = true,
    unitAddress = "",
    transposerAddress = "",
    sinkSide = "up",
    fluidName = "polyaluminiumchloride",
    targetVolume = 900000,
    stepVolume = 100000,
    consumedLine = 4,
    consumedPrefix = "Polyaluminium Chloride consumed this cycle:",
    haltWhenShort = true,
  },

  t4 = {
    enabled = true,
    unitAddress = "",
    targetPh = 7.0,
    litresPerStep = 10,
    phLine = 4,
    phPrefix = "Current pH Value:",
    haltWhenShort = true,
    acid = {
      transposerAddress = "",
      sinkSide = "bottom",
      fluidName = "hydrochloricacid_gt5u",
    },
    base = {
      transposerAddress = "",
      sinkSide = "bottom",
      itemLabel = "Sodium Hydroxide Dust",
    },
  },
}
