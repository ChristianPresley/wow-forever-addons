local _, ns = ...

-- The "Forever Bags" page in the Options window of the game. Every option of the addon is here.

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

local function slider(key, label, hint, step, format)
  page:Slider({
    label = label,
    hint = hint,
    min = ns.LIMITS[key][1],
    max = ns.LIMITS[key][2],
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

local function percent(value)
  return value .. "%"
end

local function build()
  page = ns.NewSettingsPage("Forever Bags", "One bag window, and the items of all your characters. Type /fbags help for commands.")

  page:Header("Bag window")
  check("replaceBags", "Use this bag window in place of the game's", "The bag key and the bag buttons open the Forever Bags window. Off: the bag window of the game comes back, and /fbags still opens this one.")
  page:Choice({
    label = "Order of the items",
    hint = "By category: new items, equipment, consumables, trade goods, quest items, other and junk, each under its name. The View button of the window changes this too.",
    values = ns.GROUPINGS,
    get = function()
      return ns.GetOption("groupBy")
    end,
    set = function(value)
      ns.SetOption("groupBy", value)
    end,
  })
  slider("columns", "Items in a row", nil, 1, function(value)
    return value .. " items"
  end)
  slider("scale", "Size of the items", nil, 5, percent)
  slider("alpha", "Opacity of the background", nil, 5, percent)
  check("lock", "Lock the window", "A locked window does not move when you drag it.")
  check("itemLevel", "Item level on weapons and armor", "The item level at the top left of the button. An item your level is too low for is red either way.")

  page:Header("Item tooltips")
  check("tooltipCounts", "How many this character owns", "In the tooltip of an item: the number in the bags, in the bank and equipped.")
  check("tooltipAlts", "How many your other characters own", "In the tooltip of an item: a line for each other character with the item, and the shared bank.")

  page:Header("Stored items")
  page:Info(function()
    local characters = ns.Characters()
    local withBank = 0
    for _, character in ipairs(characters) do
      if character.record.bankSeen then
        withBank = withBank + 1
      end
    end
    return string.format("%d %s stored, %d with a bank. A bank is stored when you open it at a banker.",
      #characters, #characters == 1 and "character" or "characters", withBank)
  end)
  page:Buttons({
    {
      label = "Items of all characters",
      hint = "Opens the list of the items of all your characters. /fbags all does the same.",
      click = function()
        ns.ShowBrowser()
      end,
    },
    {
      label = "Reset positions",
      hint = "Puts the bag window and the list back at their first places.",
      click = function()
        ns.ResetPositions()
      end,
    },
    {
      label = "Forget other characters",
      hint = "Deletes the stored items and gold of every character but this one. A character is stored again when you log in with it.",
      confirm = "Delete the stored items of all your other characters?",
      click = function()
        ns.ForgetOthers()
      end,
    },
  })
end

-- /fbags options
function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the options page cannot open now. Type /fbags help for the commands.")
  end
end

ns.OnLogin(function()
  if pcall(build) and page:Register() then
    ns.OnChange(function()
      page:Refresh()
    end)
  else
    page = nil
  end
end)
