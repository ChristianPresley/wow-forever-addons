local _, ns = ...

-- The pages in the Options window of the game: "Forever Compass" for the settings of all compasses,
-- and under it one page for each compass.

local main
local pages = {}

local function kindValues()
  local values = {}
  for _, kind in ipairs(ns.KINDS) do
    values[#values + 1] = { kind.key, kind.name }
  end
  return values
end

local function colorValues()
  local values = {}
  for _, color in ipairs(ns.COLORS) do
    values[#values + 1] = { color[1], color[2] }
  end
  return values
end

local function buildMain()
  main = ns.NewSettingsPage("Forever Compass", "Each compass has its own page under this one. Type /fcompass for commands.")

  main:Header("Compasses")
  for index = 1, ns.COUNT do
    main:Check({
      label = "Show compass " .. index,
      hint = "What it points to, and how it looks, is on its own page: Compass " .. index .. ", under Forever Compass in the list.",
      get = function()
        return ns.GetCompass(index, "enabled")
      end,
      set = function(value)
        ns.SetCompass(index, "enabled", value)
      end,
    })
  end
  main:Info(function()
    local parts = {}
    for index = 1, ns.COUNT do
      local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
      parts[#parts + 1] = index .. ": " .. (kind and kind.name or "?")
    end
    return table.concat(parts, "     ")
  end)

  main:Header("All compasses")
  main:Check({
    label = "Lock the compasses",
    hint = "Locked compasses do not move and let clicks through.",
    get = function()
      return ns.GetOption("lock")
    end,
    set = function(value)
      ns.SetOption("lock", value)
    end,
  })
  main:Check({
    label = "Hide in combat",
    hint = "Hides all compasses while you are in combat.",
    get = function()
      return ns.GetOption("hideInCombat")
    end,
    set = function(value)
      ns.SetOption("hideInCombat", value)
    end,
  })
  main:Buttons({
    {
      label = "Reset positions",
      hint = "Puts the compasses back in a row at the top of the screen.",
      click = ns.ResetPositions,
    },
  })

  main:Header("Learned places")
  main:Info(function()
    return "Vendors, repairers, trainers, bankers, auctioneers and mailboxes are learned when you visit them."
  end)
  main:Info(function()
    return ns.CountPlaces() .. " places learned, for all your characters."
  end)
  main:Buttons({
    {
      label = "Forget learned places",
      hint = "Deletes every learned vendor, repairer, trainer, banker, auctioneer and mailbox.",
      confirm = "Delete all learned places? This is for all your characters.",
      click = ns.ForgetPlaces,
    },
  })
end

local function buildCompass(index)
  local page = ns.NewSettingsPage("Compass " .. index, "Forever Compass, compass " .. index .. ".", main)
  local function get(key)
    return function()
      return ns.GetCompass(index, key)
    end
  end
  local function set(key)
    return function(value)
      ns.SetCompass(index, key, value)
    end
  end

  page:Header("What it shows")
  page:Check({ label = "Show this compass", hint = "Turns compass " .. index .. " on or off.", get = get("enabled"), set = set("enabled") })
  page:Choice({
    label = "Points to the nearest",
    hint = "The kind of thing this compass points to. It always points to the nearest one.",
    values = kindValues(),
    get = get("kind"),
    set = set("kind"),
  })
  page:Info(function()
    local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
    return kind and kind.hint or ""
  end)
  page:Slider({
    label = "Ignore targets farther than",
    hint = "A target farther away than this is not shown. At 0 there is no limit.",
    min = ns.COMPASS_LIMITS.maxYards[1],
    max = ns.COMPASS_LIMITS.maxYards[2],
    step = 50,
    get = get("maxYards"),
    set = set("maxYards"),
    format = function(value)
      return value == 0 and "no limit" or (value .. " yards")
    end,
  })
  page:Check({
    label = "Hide while there is nothing to point to",
    hint = "Without this, an empty compass stays on screen and says that nothing is near.",
    get = get("hideEmpty"),
    set = set("hideEmpty"),
  })

  page:Header("How it looks")
  page:Choice({ label = "Colour", hint = "The colour of the ring, the needle and the name.", values = colorValues(), get = get("color"), set = set("color") })
  page:Slider({
    label = "Size",
    hint = "The width of the compass.",
    min = ns.COMPASS_LIMITS.size[1],
    max = ns.COMPASS_LIMITS.size[2],
    step = 4,
    get = get("size"),
    set = set("size"),
    format = function(value)
      return value .. " pixels"
    end,
  })
  page:Slider({
    label = "Opacity",
    hint = "How solid the compass is. At 100 percent you cannot see through it.",
    min = ns.COMPASS_LIMITS.alpha[1],
    max = ns.COMPASS_LIMITS.alpha[2],
    step = 5,
    get = get("alpha"),
    set = set("alpha"),
    format = function(value)
      return value .. " percent"
    end,
  })
  page:Check({ label = "Show the name of the target", hint = "The name under the compass.", get = get("showName"), set = set("showName") })
  page:Check({ label = "Show the distance", hint = "The distance to the target, in yards.", get = get("showDistance"), set = set("showDistance") })
  return page
end

-- Opens the page of a compass, or the main page.
function ns.OpenSettings(index)
  local page = index and pages[index] or main
  if not (page and page:Open()) then
    ns.Print("the settings page cannot open now. Open the game's Options window and choose AddOns, Forever Compass.")
  end
end

ns.OnLogin(function()
  buildMain()
  if not main:Register() then
    main = nil
    return
  end
  for index = 1, ns.COUNT do
    local page = buildCompass(index)
    if page:Register() then
      pages[index] = page
    end
  end
  ns.OnChange(function()
    main:Refresh()
    for _, page in pairs(pages) do
      page:Refresh()
    end
  end)
end)
