local _, ns = ...

-- The pages of Forever Gather in the Options window of the game: the main page, and under it
-- the page "Alerts and sharing".

local page, more

-- A checkbox and a slider for an option, on the given page.
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

local function said(node, reason)
  ns.Print(node and ("Forgot " .. node.name .. ".") or ("Nothing forgotten: " .. reason .. "."))
end

local function build()
  page = ns.NewSettingsPage("Forever Gather", "Nodes learned from your own gathering. Type /fgather for commands.")

  page:Header("Kinds")
  check(page, "herb", "Herbs", "Places where you picked an herb.")
  check(page, "ore", "Ore", "Veins and deposits that you mined.")
  check(page, "fish", "Fish", "Places where you caught a fish. Casts along one shore merge into one place.")
  check(page, "treasure", "Treasure", "Chests that you opened: things whose loot has no quest item.")
  check(page, "quest", "Quest objects", "Things that you opened and that gave a quest item.")

  page:Header("Where")
  check(page, "worldMap", "Show on the world map", "A pin for each node on the map of its zone.")
  check(page, "minimap", "Show on the minimap", "A pin for each node near you, also for a node of the next zone.")
  slider(page, "size", "Size of the pins", "The size of a pin on the minimap. Pins on the world map are a little larger.", 1, function(value)
    return value .. " pixels"
  end)

  page:Header("Skill")
  check(page, "hideTrivial", "Hide nodes that give no more skill", "Hides a node when your skill is 100 or more over the skill you first gathered it at.")
  slider(page, "minSkill", "Hide nodes learned below skill", "Hides nodes that you first gathered at a lower skill than this. At 0 every node shows.", 5, function(value)
    return value == 0 and "show all" or tostring(value)
  end)

  page:Header("Data")
  page:Info(function()
    return ns.CountNodes() .. " nodes learned, for all your characters."
  end)
  page:Buttons({
    {
      label = "Forget the node here",
      hint = "Deletes the learned node nearest to you, within 20 yards.",
      confirm = "Delete the learned node nearest to you?",
      click = function()
        said(ns.ForgetHere())
      end,
    },
    {
      label = "Forget all nodes",
      hint = "Deletes every learned node.",
      confirm = "Delete all learned nodes? This is for all your characters.",
      click = function()
        ns.Forget()
      end,
    },
  })

  more = ns.NewSettingsPage("Alerts and sharing", "The alert for a node that is near, the look of the pins, and the nodes as text.", page)

  more:Header("Alert")
  check(more, "alert", "Say when a learned node is near", "A line in the chat when you come near a node that you know. Each node is said once for a visit.")
  check(more, "alertSound", "With a sound", "A sound with the line.")
  slider(more, "alertYards", "Near is within", "The distance at which a node is said.", 5, function(value)
    return value .. " yards"
  end)

  more:Header("Pins")
  check(more, "skillColours", "Dot in the colour of the difficulty", "A dot on the pin: orange, yellow, green or grey for your skill, red when the node needs more skill. It comes from the skill that you first gathered the node at.")
  slider(more, "dimMinutes", "Dim a pin after its gather", "A node that you gathered is dim for this long, and its alert is silent. At 0 no pin is dim.", 1, function(value)
    return value == 0 and "never" or (value .. " minutes")
  end)

  check(more, "route", "Route through the nodes of the zone", "A line on the world map through the nodes that show, in an order that is short to ride.")

  more:Header("Share and clean up")
  more:Info(function()
    return "An export is text to copy. An import adds the nodes that you do not know yet."
  end)
  more:Buttons({
    {
      label = "Export nodes",
      hint = "Opens a window with all learned nodes as text.",
      click = function()
        ns.ShowExport()
      end,
    },
    {
      label = "Import nodes",
      hint = "Opens a window to paste the text of an export.",
      click = function()
        ns.ShowImport()
      end,
    },
    {
      label = "Merge duplicates",
      hint = "Merges the nodes of the same name that are within 15 yards of each other (fish: 45 yards) into one.",
      click = function()
        ns.Print(string.format("%d |4node:nodes; merged into another.", ns.CleanNodes()))
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
  local hasMore = more:Register()
  ns.OnChange(function()
    page:Refresh()
    if hasMore then
      more:Refresh()
    end
  end)
end)
