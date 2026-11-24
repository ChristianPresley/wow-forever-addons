local _, ns = ...

-- The page in the Options window of the game.

local page

local function build()
  page = ns.NewSettingsPage("Forever Leveling", "Your experience, and the zones for your level. Type /flevel for commands.")
  local function check(key, label, hint)
    page:Check({
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
  local function slider(key, label, hint, unit)
    page:Slider({
      label = label,
      hint = hint,
      min = ns.OPTION_LIMITS[key][1],
      max = ns.OPTION_LIMITS[key][2],
      step = 1,
      get = function()
        return ns.GetOption(key)
      end,
      set = function(value)
        ns.SetOption(key, value)
      end,
      format = function(value)
        return unit == "" and tostring(value) or value .. " " .. unit
      end,
    })
  end

  page:Header("Readout")
  check("show", "Show the readout", "The window with your experience, XP an hour, time to level, kills and quests to level, and rested XP.")
  check("showBar", "Show the experience bar", "The bar in the readout. The blue part is your rested experience.")
  check("lock", "Lock the windows", "Locked windows do not move.")
  slider("scale", "Size of the windows", "The size of the readout and of the list of zones.", "percent")
  slider("samples", "Kills and quests in the averages", "How many of your last kills and quests make the average XP of one, for the counts to the next level.", "")

  page:Header("Zones")
  check("showZones", "Show the zones for your level", "A list of zones that suit your level. Click a zone to point Forever Compass at it.")
  slider("zoneSpread", "Levels around yours", "A zone is on the list if your level is no more than this many levels below or above its range.", "levels")

  page:Info(function()
    return string.format("This session: %s XP, %d kills and %d quests counted.", ns.Thousands(ns.session.gained), #ns.session.kills, #ns.session.quests)
  end)
  page:Buttons({
    { label = "Start a new session", hint = "Counts XP an hour, kills and quests again from now.", click = ns.ResetSession },
    { label = "Reset positions", hint = "Puts both windows back at the top of the screen.", click = ns.ResetPositions },
  })
  if page:Register() then
    ns.OnChange(function()
      page:Refresh()
    end)
  end
end

ns.OnLogin(build)

function ns.OpenSettings()
  if page and page:Open() then
    return
  end
  ns.Print("the settings page cannot open now.")
end
