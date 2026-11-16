local _, ns = ...

-- The pages in the Options window of the game: "Forever Compass" for the bar, and under it one
-- page for each tracker.

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
  main = ns.NewSettingsPage("Forever Compass", "Each tracker has its own page under this one. Type /fcompass for commands.")
  local function check(key, label, hint)
    main:Check({
      label = label,
      hint = hint,
      get = function()
        return ns.GetOption(key)
      end,
      set = function(value)
        ns.SetOption(key, value)
      end,
    })
  end
  local function slider(key, label, hint, step, unit)
    main:Slider({
      label = label,
      hint = hint,
      min = ns.OPTION_LIMITS[key][1],
      max = ns.OPTION_LIMITS[key][2],
      step = step,
      get = function()
        return ns.GetOption(key)
      end,
      set = function(value)
        ns.SetOption(key, value)
      end,
      format = function(value)
        return value .. " " .. unit
      end,
    })
  end

  main:Header("Compass bar")
  check("show", "Show the compass bar", "The bar at the top of the screen, with N, NE, E, SE, S, SW, W and NW. It scrolls as you turn.")
  slider("barAlpha", "Opacity of the bar", "How solid the bar is. Each tracker has its own opacity, on its page.", 5, "percent")
  slider("barWidth", "Width of the bar", "The width of the bar, as a part of the width of the screen.", 1, "percent of the screen")
  slider("fov", "Part of the circle on the bar", "How many of the 360 degrees the bar shows at one time. At 360 the whole circle is on the bar.", 15, "degrees")
  check("showDegrees", "Show the heading in degrees", "The direction you look in, as a number above the bar. North is 0 and east is 90.")
  check("lock", "Lock the bar", "A locked bar does not move and lets clicks through.")
  check("hideInCombat", "Hide in combat", "Hides the bar and the markers while you are in combat.")

  main:Header("Trackers")
  for index = 1, ns.COUNT do
    main:Check({
      label = "Tracker " .. index,
      hint = "Puts a marker on the bar. What it points to, and how it looks, is on its own page: Tracker " .. index .. ", under Forever Compass in the list.",
      get = function()
        return ns.GetCompass(index, "enabled")
      end,
      set = function(value)
        ns.SetCompass(index, "enabled", value)
      end,
    })
  end

  main:Header("Data")
  main:Info(function()
    return ns.CountPlaces() .. " places learned (vendors, repairers, trainers, bankers, auctioneers, mailboxes), for all your characters."
  end)
  main:Buttons({
    {
      label = "Reset the position",
      hint = "Puts the bar back at the top of the screen.",
      click = ns.ResetPositions,
    },
    {
      label = "Forget learned places",
      hint = "Deletes every learned vendor, repairer, trainer, banker, auctioneer and mailbox.",
      confirm = "Delete all learned places? This is for all your characters.",
      click = ns.ForgetPlaces,
    },
  })
end

local function buildTracker(index)
  local page = ns.NewSettingsPage("Tracker " .. index, "Forever Compass, tracker " .. index .. ": a marker on the compass bar.", main)
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
  page:Check({ label = "Show this tracker", hint = "Turns tracker " .. index .. " on or off.", get = get("enabled"), set = set("enabled") })
  page:Choice({
    label = "Points to the nearest",
    hint = "The kind of thing this tracker points to. Its marker is at the bearing of the nearest one.",
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

  page:Header("How it looks")
  page:Slider({
    label = "Opacity of the marker",
    hint = "How solid the marker and its text are. A marker at the end of the bar, for a target outside the shown part of the circle, is dimmed.",
    min = ns.COMPASS_LIMITS.alpha[1],
    max = ns.COMPASS_LIMITS.alpha[2],
    step = 5,
    get = get("alpha"),
    set = set("alpha"),
    format = function(value)
      return value .. " percent"
    end,
  })
  page:Choice({ label = "Colour", hint = "The colour of the marker and of the name.", values = colorValues(), get = get("color"), set = set("color") })
  page:Slider({
    label = "Size of the marker",
    hint = "The width of the marker on the bar.",
    min = ns.COMPASS_LIMITS.size[1],
    max = ns.COMPASS_LIMITS.size[2],
    step = 2,
    get = get("size"),
    set = set("size"),
    format = function(value)
      return value .. " pixels"
    end,
  })
  page:Check({ label = "Show the name of the target", hint = "The name under the marker.", get = get("showName"), set = set("showName") })
  page:Check({ label = "Show the distance", hint = "The distance to the target, in yards, under the marker.", get = get("showDistance"), set = set("showDistance") })
  return page
end

-- Opens the page of a tracker, or the main page.
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
    local page = buildTracker(index)
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
