local _, ns = ...

-- The page in the Options window of the game.

local page

local function build()
  page = ns.NewSettingsPage("Forever Trace", "A record of errors and events for a developer. Type /ftrace for commands.")
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
  local function slider(key, label, hint, step, unit)
    page:Slider({
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

  page:Header("Recording")
  check("enabled", "Record errors and events", "Lua errors, blocked actions, warnings of the game, and what happened around them. The game writes the record to the disk at /reload and at logout.")
  check("announce", "Say a new error in the chat", "One line for each new error. A repeat of the same error is counted, not said again.")
  slider("ring", "Events to keep", "Logins, zone changes, fights and what the Forever addons log. The oldest go first. Your markers are kept apart from them.", 50, "events")
  slider("errors", "Different errors to keep", "A repeat of an error raises its count. When the list is full, the error that was seen longest ago goes.", 10, "errors")

  page:Header("Screenshots")
  check("screenshots", "Take a screenshot for a new error", "Also for /ftrace mark, at once. For an error half a second later, so that the error window of the game is in the picture. Off until you have tried the test button: the screenshot is in the Screenshots folder of the game at once, without a /reload.")
  slider("shotGap", "Time between two screenshots", "No screenshot for an error that comes sooner than this after the last screenshot.", 5, "seconds")

  page:Info(function()
    return (ns.StatusLines()[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end)
  page:Info(function()
    return (ns.StatusLines()[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end)
  page:Buttons({
    { label = "Test error", hint = "Raises one harmless Lua error and says if the record caught it. The game may show its error window.", click = ns.Test },
    { label = "Test screenshot", hint = "Takes one screenshot now, to see if the game lets an addon take one.", click = ns.TestShot },
    {
      label = "Drop a marker",
      hint = "A marker in the trace at this moment. /ftrace mark with a text says what you saw.",
      click = function()
        ns.Mark("marker from the settings page")
      end,
    },
    { label = "Delete the trace", hint = "Deletes the stored errors, events and markers.", confirm = "Delete all stored errors, events and markers of Forever Trace?", click = ns.Clear },
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
