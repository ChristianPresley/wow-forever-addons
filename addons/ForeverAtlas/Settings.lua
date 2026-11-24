local _, ns = ...

-- The "Forever Atlas" page in the Options window of the game. Every option of the addon is here.

local page

local function count(list)
  local n = 0
  for _ in pairs(list or {}) do
    n = n + 1
  end
  return n
end

local function build()
  page = ns.NewSettingsPage("Forever Atlas", "Type /fatlas for commands and /way 45.2 61.8 for a waypoint.")
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

  page:Header("Forever Atlas map")
  check("mapKey", "Open the Forever Atlas map with the map key", "The key of the world map (M) opens the Forever Atlas map: zoom with the mouse wheel, drag to move. Off: the key opens the map of the game, and /fatlas map opens this one.")

  page:Header("Forever Atlas map: what it shows")
  for _, kind in ipairs(ns.MAP_KINDS) do
    check(ns.MapKindOption(kind.key), kind.name, "Shows these on the Forever Atlas map. The button \"Show\" of the map changes this too.")
  end
  check("zoneNames", "Names of the zones", "On the map of a continent: the name of each zone, in its middle.")
  check("zoneHighlight", "Light up the zone under the pointer", "The zone under the pointer lights up, as on the map of the game.")
  check("terrainDetail", "Terrain when zoomed in", "Zoomed in on a zone, the map shows the terrain itself, as the minimap does, and zooms in much further.")

  check("questAreas", "Quest areas", "The area of each quest objective is shaded on the map, under the pins.")
  check("revealAll", "Land you have not explored", "The map shows all the land of a zone, also where you have not been. Off: only the land you have explored, as on the map of the game.")
  check("revealBright", "That land as bright as the rest", "The land where you have not been is as bright as the land where you have been. Off: it is a little darker.")

  page:Header("Forever Atlas map: the window")
  local function percent(key, label, hint)
    page:Slider({
      label = label,
      hint = hint,
      min = ns.limits[key][1],
      max = ns.limits[key][2],
      step = 5,
      get = function()
        return ns.GetOption(key)
      end,
      set = function(value)
        ns.SetOption(key, value)
      end,
      format = function(value)
        return value .. "%"
      end,
    })
  end
  percent("mapOpacity", "Opacity of the map window", "Lower: the game shows through the map. You can move your character while the map is open.")
  percent("mapScale", "Size of the map window", "The scale of the whole window. Drag its bottom right corner to change its shape; the map keeps its place and size.")

  page:Header("Minimap")
  local owner = ns.MinimapOwner and ns.MinimapOwner()
  local because = owner and (" " .. owner .. " shapes the minimap, so this does nothing now.") or ""
  check("minimapSquare", "Square minimap", "A square minimap, which shows more of the land in its corners." .. because)
  percent("minimapScale", "Size of the minimap", "Makes the minimap and the buttons around it larger." .. because)
  check("minimapCoords", "Coordinates under the minimap", "Your coordinates under the minimap." .. because)

  page:Header("World map of the game")
  check("coords", "Coordinates on the world map", "Player and cursor coordinates in the corner of the world map.")
  check("notes", "Map notes", "Shows your notes on the world map. Alt-click the map to add one.")
  check("announce", "First-visit chat messages", "A chat message when you enter an area for the first time.")

  page:Header("On screen")
  check("hud", "Coordinates on screen", "A small read-out of your coordinates, shown without the map. Drag it to move it.")
  check("hudArea", "Area name in the read-out", "Shows the name of the area under the coordinates.")
  check("hudLock", "Lock the read-out and the waypoint arrow", "Locked frames do not move and let clicks through.")

  page:Header("Waypoints")
  check("arrow", "Direction arrow", "An arrow on screen that points to your newest waypoint, with the distance.")
  page:Slider({
    label = "Remove a waypoint when you are this near",
    hint = "A waypoint counts as reached, and is removed, within this distance.",
    min = ns.limits.arrivalYards[1],
    max = ns.limits.arrivalYards[2],
    step = 1,
    get = function()
      return ns.GetOption("arrivalYards")
    end,
    set = function(value)
      ns.SetOption("arrivalYards", value)
    end,
    format = function(value)
      return value .. " yards"
    end,
  })

  page:Header("Data")
  page:Info(function()
    local areas = 0
    for _, zone in pairs(ForeverAtlasCharDB.zones) do
      areas = areas + count(zone)
    end
    local notes = 0
    for _, list in pairs(ForeverAtlasDB.notes) do
      notes = notes + count(list)
    end
    return string.format(
      "This character: %d visited areas, %d waypoints.   All characters: %d map notes, %d remembered NPCs.",
      areas, #ForeverAtlasCharDB.waypoints, notes, ns.CountNpcs and ns.CountNpcs() or 0
    )
  end)
  page:Buttons({
    {
      label = "Reset frame positions",
      hint = "Puts the coordinate read-out, the waypoint arrow and the map window back where they were at first.",
      click = function()
        ns.ResetFrames()
        if ns.ResetMapWindow then
          ns.ResetMapWindow()
        end
      end,
    },
    {
      label = "Remove all waypoints",
      hint = "Removes every waypoint of this character.",
      confirm = "Remove all waypoints of this character?",
      click = ns.ClearWaypoints,
    },
  })
  page:Buttons({
    {
      label = "Delete all map notes",
      hint = "Deletes every map note. Notes are shared by all your characters.",
      confirm = "Delete all your map notes? This is for all your characters.",
      click = function()
        wipe(ForeverAtlasDB.notes)
        ns.RefreshPins()
      end,
    },
    {
      label = "Forget visited areas",
      hint = "Deletes the record of the areas this character has visited (the /fatlas list and zone counts).",
      confirm = "Delete the record of the areas this character has visited?",
      click = function()
        wipe(ForeverAtlasCharDB.zones)
        ns.RefreshPins()
      end,
    },
  })
  page:Buttons({
    {
      label = "Forget remembered NPCs",
      hint = "Deletes the vendors, trainers and other NPCs the addon remembers, and their pins. They are shared by all your characters.",
      confirm = "Delete all remembered vendors, trainers and other NPCs? This is for all your characters.",
      click = function()
        ns.ForgetNpcs()
      end,
    },
  })
end

function ns.OpenSettings()
  if not (page and page:Open()) then
    ns.Print("the settings page cannot open now. Open the game's Options window and choose AddOns, Forever Atlas.")
  end
end

ns.OnLogin(function()
  build()
  if page:Register() then
    ns.OnOption(function()
      page:Refresh()
    end)
  else
    page = nil
  end
end)
