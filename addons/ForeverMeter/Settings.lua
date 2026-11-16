local _, ns = ...

-- The "Forever Meter" pages in the Options window of the game. Every option of the addon is here.

local page, groups, barsPage

local function check(target, key, label, hint)
  target:Check({
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

local function slider(target, key, label, hint, step, format)
  target:Slider({
    label = label,
    hint = hint,
    min = ns.LIMITS[key][1],
    max = ns.LIMITS[key][2],
    step = step or 1,
    get = function()
      return ns.GetOption(key)
    end,
    set = function(value)
      ns.SetOption(key, value)
    end,
    format = format,
  })
end

local function pixels(value)
  return value .. " pixels"
end

local function percent(value)
  return value .. "%"
end

local function bars(value)
  return value == 1 and "1 bar" or (value .. " bars")
end

local function build()
  page = ns.NewSettingsPage("Forever Meter", "A damage and healing meter. Type /fmeter help for commands. Click the title of the meter for its menu.")

  page:Header("Meter window")
  check(page, "show", "Show the meter window", "The window with a bar for each player. /fmeter does the same.")
  check(page, "lock", "Lock the window", "A locked window does not move when you drag it.")
  check(page, "hideOutOfCombat", "Hide the window out of combat", "The window shows when a fight starts and hides when it ends.")
  slider(page, "width", "Width of the window", nil, 5, pixels)
  slider(page, "rowHeight", "Height of a bar", nil, 1, pixels)
  slider(page, "alpha", "Opacity of the background", "0% leaves only the bars.", 5, percent)

  page:Header("Your own read-out")
  check(page, "personal", "Show my own DPS on screen", "One line with your damage per second in the current fight, and your place in the group. Drag it to move it.")
  check(page, "personalHealing", "Show my HPS in place of my DPS", "For healers: the read-out shows your healing per second.")
  check(page, "personalLock", "Lock the read-out", "A locked read-out does not move when you drag it.")

  page:Header("Data")
  check(page, "autoReset", "Delete earlier fights when I enter a dungeon or a raid", "The whole session then starts again in each instance.")
  page:Info(function()
    local available, reason = ns.Available()
    if not available then
      return reason
    end
    local enabled = ns.GameMeterEnabled()
    local fights = #ns.Sessions()
    if enabled == false then
      return "The damage meter of the game is off. If the bars stay empty in a fight, turn it on with the button below."
    end
    return string.format("The game has the data of %d %s.", fights, fights == 1 and "fight" or "fights")
  end)
  page:Buttons({
    {
      label = "Delete all fights",
      hint = "Deletes the damage data of all fights. The game's own damage meter loses it too.",
      confirm = "Delete the damage data of all fights?",
      click = function()
        ns.ResetData()
      end,
    },
    {
      label = "Reset positions",
      hint = "Puts the meter window, the read-out and the spell window back at their first places.",
      click = function()
        ns.ResetPositions()
      end,
    },
    {
      label = "Turn on game damage data",
      hint = "Turns on the damage meter of the game, which collects the numbers. You can hide its own window in the Edit Mode of the game.",
      click = function()
        if ns.EnableGameMeter() then
          ns.Print("the damage meter of the game is on.")
        else
          ns.Print("the setting could not be changed on this game client.")
        end
      end,
    },
  })
end

-- The second page: what the window shows for each kind of group, and the bars.
local function buildGroups()
  groups = ns.NewSettingsPage("Groups and bars", "The meter works alone, in a party and in a raid. Each has its own settings.", page)

  local modes = {}
  for _, mode in ipairs(ns.MODES) do
    modes[#modes + 1] = { mode.key, mode.label }
  end
  groups:Header("What to show")
  groups:Choice({
    label = "The meter shows",
    hint = "The same choice is in the menu of the meter window.",
    values = modes,
    get = function()
      return ns.GetOption("mode")
    end,
    set = function(value)
      ns.SetOption("mode", value)
    end,
  })

  groups:Header("Alone, party and raid")
  check(groups, "showSolo", "Show the window when I am alone", nil)
  slider(groups, "rowsSolo", "Bars when I am alone", "You, your pet and the enemies you fight can each have a bar.", 1, bars)
  check(groups, "showParty", "Show the window in a party", nil)
  slider(groups, "rowsParty", "Bars in a party", "A party has up to five players.", 1, bars)
  check(groups, "showRaid", "Show the window in a raid", nil)
  slider(groups, "rowsRaid", "Bars in a raid", "The mouse wheel moves through a longer list.", 1, bars)
end

-- The third page: how a bar looks, and the report.
local function buildBars()
  barsPage = ns.NewSettingsPage("Bars and reports", "How each bar looks, how often the meter updates, and the report to chat.", page)

  barsPage:Header("Bars")
  check(barsPage, "pinSelf", "Keep my own bar in view", "When you are farther down the list than the window shows, the last bar is yours.")
  check(barsPage, "classColors", "Class colours", "Each bar has the colour of the player's class. Off: all bars are grey.")
  check(barsPage, "showRank", "Place in the list before the name", nil)
  check(barsPage, "showPercent", "Share of the group total", "The game hides the numbers from addons during a fight, so the percentage comes when the fight ends.")
  slider(barsPage, "updateTenths", "Time between two updates", "A shorter time shows changes sooner and costs more.", 1, function(value)
    return string.format("%.1f seconds", value / 10)
  end)

  barsPage:Header("Report")
  slider(barsPage, "reportLines", "Players in a report to chat", "The report is in the menu of the meter window, and under /fmeter report party.", 1, function(value)
    return value == 1 and "1 player" or (value .. " players")
  end)
end

-- /fmeter options
function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the options page cannot open now. Type /fmeter help for the commands.")
  end
end

ns.OnLogin(function()
  if pcall(build) and page:Register() then
    ns.OnChange(function()
      page:Refresh()
      if groups then
        groups:Refresh()
      end
      if barsPage then
        barsPage:Refresh()
      end
    end)
    -- A page under the main page is registered after it.
    if not (pcall(buildGroups) and groups:Register()) then
      groups = nil
    end
    if not (pcall(buildBars) and barsPage:Register()) then
      barsPage = nil
    end
  else
    page = nil
  end
end)
