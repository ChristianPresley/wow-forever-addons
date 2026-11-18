local _, ns = ...

-- The page "Forever Gather" in the Options window of the game.

local page

local function build()
  page = ns.NewSettingsPage("Forever Gather", "Nodes learned from your own gathering. Type /fgather for commands.")
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
  local function slider(key, label, hint, step, format)
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
      format = format,
    })
  end

  page:Header("Kinds")
  check("herb", "Herbs", "Places where you picked an herb.")
  check("ore", "Ore", "Veins and deposits that you mined.")
  check("fish", "Fish", "Places where you caught a fish. Casts along one shore merge into one place.")
  check("treasure", "Treasure", "Chests and other things that you opened.")

  page:Header("Where")
  check("worldMap", "Show on the world map", "A pin for each node on the map of its zone.")
  check("minimap", "Show on the minimap", "A pin for each node near you.")
  slider("size", "Size of the pins", "The size of a pin on the minimap. Pins on the world map are a little larger.", 1, function(value)
    return value .. " pixels"
  end)

  page:Header("Skill")
  check("hideTrivial", "Hide nodes that give no more skill", "Hides a node when your skill is 100 or more over the skill you first gathered it at.")
  slider("minSkill", "Hide nodes learned below skill", "Hides nodes that you first gathered at a lower skill than this. At 0 every node shows.", 5, function(value)
    return value == 0 and "show all" or tostring(value)
  end)

  page:Header("Data")
  page:Info(function()
    return ns.CountNodes() .. " nodes learned, for all your characters."
  end)
  page:Buttons({
    {
      label = "Forget all nodes",
      hint = "Deletes every learned node.",
      confirm = "Delete all learned nodes? This is for all your characters.",
      click = function()
        ns.Forget()
      end,
    },
  })
end

function ns.OpenSettings()
  if not (page and page:Open()) then
    ns.Print("the settings page cannot open now. Open the game's Options window and choose AddOns, Forever Gather.")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  build()
  if not page:Register() then
    page = nil
    return
  end
  ns.OnChange(function()
    page:Refresh()
  end)
end)
