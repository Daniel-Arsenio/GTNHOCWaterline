local sides = require("sides")

return {
  pollInterval = 0.2,
  log = { verbose = true },

  cycleAddress = "",

  power = {
    enabled = true,
    autoApply = false,
    checkInterval = 60,
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
    interfaceAddress = "",
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
    repeatEvery = 5,
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
    sourceSide = sides.down,
    hatchSide = sides.up,
    targetVolume = 900000,
    fillWindow = 4.0,
  },

  t4 = {
    enabled = true,
    unitAddress = "",
    targetPh = 7.0,
    deadband = 0.005,
    litresPerStep = 10,
    minSanePh = 0.5,
    maxSanePh = 13.5,
    doseInterval = 1.1,
    acid = {
      transposerAddress = "",
      sourceSide = sides.down,
      hatchSide = sides.up,
    },
    base = {
      transposerAddress = "",
      sourceSide = sides.down,
      busSide = sides.up,
      sourceSlot = 1,
    },
  },
}
