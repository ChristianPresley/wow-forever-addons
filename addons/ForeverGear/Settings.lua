local _, ns = ...

-- The "Forever Gear" page in the Options window of the game. Every option of the addon is here.

local page

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

local function build()
  page = ns.NewSettingsPage("Forever Gear", "Gear lists for your class and role, loot of dungeons, and upgrade lines in tooltips. Type /fgear help for commands.")

  page:Header("Gear list")
  local values = {}
  for _, role in ipairs(ns.RolesOf(ns.PlayerClass())) do
    values[#values + 1] = { role, ns.ROLES[role] }
  end
  page:Choice({
    label = "Role of this class",
    hint = "The gear list that the window shows and that the tooltip compares with. The button of the window changes this too.",
    values = values,
    get = function()
      return ns.GetRole()
    end,
    set = function(value)
      ns.SetRole(value)
    end,
  })
  check("showSource", "Show where items come from", "In the window: the dungeon, boss, profession or quest of each item.")
  check("lock", "Lock the window", "A locked window does not move when you drag it.")

  page:Header("Item tooltips")
  check("tooltipList", "Gear list lines", "In the tooltip of an item: its place on the gear list of your role, and whether it is on your own list.")
  check("tooltipOtherRoles", "Other roles of the class", "Also name the other roles of your class whose list has the item.")
  check("tooltipUpgrade", "Upgrade line", "In the tooltip of an item: whether it ranks higher on your list than what you wear in its slot.")

  page:Header("Your own list")
  page:Info(function()
    local count = #ns.PersonalList()
    return string.format("%d %s on your own list. Click an item in the window to add it.", count, count == 1 and "item" or "items")
  end)
  page:Buttons({
    {
      label = "Open the window",
      hint = "Opens the gear window. /fgear does the same.",
      click = function()
        ns.ShowWindow()
      end,
    },
    {
      label = "Reset position",
      hint = "Puts the window back at its first place.",
      click = function()
        ns.ResetPositions()
      end,
    },
    {
      label = "Clear your list",
      hint = "Takes every item off your own list.",
      confirm = "Take every item off your own gear list?",
      click = function()
        ns.ClearPersonal()
      end,
    },
  })
end

function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the options page cannot open now. Type /fgear help for the commands.")
  end
end

ns.OnLogin(function()
  if pcall(build) and page:Register() then
    ns.OnOptionChanged(function()
      page:Refresh()
    end)
  else
    page = nil
  end
end)
