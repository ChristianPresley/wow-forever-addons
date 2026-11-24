local _, ns = ...

-- The Forever Gear window: the gear list of a role, the player's own list, or the loot of an
-- instance. Click an item to put it on your own list or take it off.

local FRAME_NAME = "ForeverGearWindow"
local WIDTH, HEIGHT = 440, 470
local ROWS, ROW_HEIGHT = 18, 20

ns.VIEWS = {
  { "list", "Gear list" },
  { "mine", "My list" },
  { "loot", "Loot" },
}

local frame
local view = "list"
local instance = ns.INSTANCES[1].key
local entries = {}
local offset = 0

local function itemText(itemID)
  local name, link = C_Item.GetItemInfo(itemID)
  if link then
    return link, true
  end
  return name or ("Item " .. itemID), false
end

local function textOf(values, key)
  for _, entry in ipairs(values) do
    if entry[1] == key then
      return entry[2]
    end
  end
  return tostring(key)
end

-- The rows: { header = text } or { id = itemID, left = text, right = text }.
function ns.WindowEntries()
  local list = {}
  local missing = false
  local function add(itemID, right)
    local text, known = itemText(itemID)
    missing = missing or not known
    if ns.IsPersonal(itemID) then
      text = "|cff80c0ff*|r " .. text
    end
    if ns.IsEquipped(itemID) then
      right = "|cff40c040worn|r" .. (right ~= "" and ", " .. right or "")
    end
    list[#list + 1] = { id = itemID, left = text, right = right }
  end
  local showSource = ns.GetOption("showSource")
  local function sourceOf(item)
    if not showSource then
      return ""
    end
    local where = ns.INSTANCE_BY_KEY[item.from].name
    return item.source and (where .. ": " .. item.source) or where
  end
  local lastHeader
  local function header(text)
    if text ~= lastHeader then
      list[#list + 1] = { header = text }
      lastHeader = text
    end
  end
  if view == "list" then
    local current = ns.GetRole()
    for _, entry in ipairs(ns.ListOf(current, ns.PlayerClass())) do
      header(ns.SLOT_BY_KEY[entry.item.slot].name)
      add(entry.item.id, "#" .. entry.rank .. (showSource and "  " .. sourceOf(entry.item) or ""))
    end
  elseif view == "mine" then
    for _, entry in ipairs(ns.PersonalList()) do
      header(entry.slot and ns.SLOT_BY_KEY[entry.slot].name or "Other")
      local item = ns.Item(entry.id)
      add(entry.id, item and sourceOf(item) or "")
    end
  else
    for _, item in ipairs(ns.LootOf(instance)) do
      header(item.source or "Several sources")
      add(item.id, ns.SLOT_BY_KEY[item.slot].name)
    end
  end
  return list, missing
end

local function render()
  if not frame then
    return
  end
  offset = math.max(0, math.min(offset, #entries - ROWS))
  for index, row in ipairs(frame.rows) do
    local entry = entries[index + offset]
    row.entry = entry
    if entry then
      row:Show()
      if entry.header then
        row.left:SetText("|cffffd100" .. entry.header .. "|r")
        row.right:SetText("")
        row.icon:Hide()
      else
        row.left:SetText(entry.left)
        row.right:SetText(entry.right)
        row.icon:SetTexture(C_Item.GetItemIconByID(entry.id) or 134400)
        row.icon:Show()
      end
    else
      row:Hide()
    end
  end
  frame.empty:SetShown(#entries == 0)
end

local function rebuild()
  if not frame then
    return
  end
  local class = ns.PlayerClass()
  frame.view:SetText(textOf(ns.VIEWS, view))
  if view == "list" then
    frame.choice:SetText(ns.ROLES[ns.GetRole(class)])
    frame.choice:Show()
  elseif view == "loot" then
    frame.choice:SetText(ns.INSTANCE_BY_KEY[instance].name)
    frame.choice:Show()
  else
    frame.choice:Hide()
  end
  local missing
  entries, missing = ns.WindowEntries()
  frame.missing = missing
  render()
end
ns.RebuildWindow = rebuild

-- Moves the view, the role or the instance one step.
function ns.SetView(key)
  for _, entry in ipairs(ns.VIEWS) do
    if entry[1] == key then
      view = key
      offset = 0
      rebuild()
      return true
    end
  end
  return false
end

function ns.SetInstance(key)
  if ns.INSTANCE_BY_KEY[key] then
    instance = key
    view = "loot"
    offset = 0
    rebuild()
    return true
  end
  return false
end

local function nextOf(values, current)
  for index, value in ipairs(values) do
    if value == current then
      return values[index % #values + 1]
    end
  end
  return values[1]
end

local function cycleView()
  local keys = {}
  for _, entry in ipairs(ns.VIEWS) do
    keys[#keys + 1] = entry[1]
  end
  ns.SetView(nextOf(keys, view))
end

local function cycleChoice()
  if view == "list" then
    -- The role of the window follows the options: a click changes the role of the class.
    ns.SetRole(nextOf(ns.RolesOf(ns.PlayerClass()), ns.GetRole()))
  elseif view == "loot" then
    local keys = {}
    for _, entry in ipairs(ns.INSTANCES) do
      keys[#keys + 1] = entry.key
    end
    ns.SetInstance(nextOf(keys, instance))
  end
end

local function showRowTooltip(row)
  local entry = row.entry
  if not entry or entry.header then
    return
  end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. entry.id) then
    GameTooltip:SetText(entry.left, 1, 1, 1)
  end
  GameTooltip:AddLine("Click: put on your own list or take off.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function create()
  frame = CreateFrame("Frame", FRAME_NAME, UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("window", self)
  end)
  frame:Hide()
  tinsert(UISpecialFrames, FRAME_NAME)

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.05, 0.04, 0.03, 0.94)
  local headerBack = frame:CreateTexture(nil, "BORDER")
  headerBack:SetPoint("TOPLEFT")
  headerBack:SetPoint("TOPRIGHT")
  headerBack:SetHeight(26)
  headerBack:SetColorTexture(0.45, 0.32, 0.12, 0.9)

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -7)
  title:SetText("Forever Gear")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame.view = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.view:SetSize(130, 22)
  frame.view:SetPoint("TOPLEFT", 10, -34)
  frame.view:SetScript("OnClick", cycleView)

  frame.choice = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.choice:SetSize(200, 22)
  frame.choice:SetPoint("LEFT", frame.view, "RIGHT", 10, 0)
  frame.choice:SetScript("OnClick", cycleChoice)

  frame.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, -64 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    if index % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)
    row:SetScript("OnEnter", showRowTooltip)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
      local entry = self.entry
      if entry and entry.id then
        ns.TogglePersonal(entry.id)
      end
    end)
    frame.rows[index] = row
  end

  frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  frame.empty:SetPoint("TOP", 0, -140)
  frame.empty:SetWidth(WIDTH - 80)
  frame.empty:SetText("Nothing here yet. Click an item in the gear list or the loot to put it on your own list.")

  local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 10)
  hint:SetText("* on your own list. Click an item to add or remove it.")

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    render()
  end)
  frame:SetScript("OnShow", function()
    offset = 0
    rebuild()
  end)
  -- Names arrive after the client loads the items: the window reads them again while one is missing.
  local elapsed = 0
  frame:SetScript("OnUpdate", function(self, seconds)
    elapsed = elapsed + seconds
    if elapsed >= 1 then
      elapsed = 0
      if self.missing then
        rebuild()
      end
    end
  end)

  ns.RestorePosition("window", frame, "CENTER", 0, 20)
end

function ns.ShowWindow()
  if not frame then
    local ok, problem = pcall(create)
    if not ok then
      frame = nil
      ns.Print("the window could not be made: " .. tostring(problem))
      return false
    end
  end
  frame:Show()
  rebuild()
  return true
end

function ns.ToggleWindow()
  if frame and frame:IsShown() then
    frame:Hide()
    return true
  end
  return ns.ShowWindow()
end

ns.OnOptionChanged(function()
  if frame and frame:IsShown() then
    rebuild()
  end
end)

ns.OnResetPositions(function()
  if frame then
    ns.RestorePosition("window", frame, "CENTER", 0, 20)
  end
end)

-- The equipped items change: the "worn" marks follow.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function()
  if frame and frame:IsShown() then
    rebuild()
  end
end)
