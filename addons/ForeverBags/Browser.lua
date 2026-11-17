local _, ns = ...

-- The list of the items of all characters: bags, bank and equipment, with a search box, a filter
-- for one character and the gold of each character. It reads the store only, so it also works
-- far from a bank and for characters that are not logged in.

local FRAME_NAME = "ForeverBagsBrowser"
local WIDTH, HEIGHT = 520, 470
local ROWS = 17
local ROW_HEIGHT = 20
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame
local filter = ""
local onlyCharacter -- a character key, or nil for all characters
local items = {} -- { id, total, name }
local offset = 0
local requested = {} -- [itemID] = true after the client was asked to load the item

local function itemName(itemID)
  local name = C_Item.GetItemNameByID(itemID)
  if type(name) == "string" and name ~= "" then
    return name
  end
  -- The client loads the item, and a later look has the name.
  if not requested[itemID] then
    requested[itemID] = true
    pcall(C_Item.RequestLoadItemDataByID, itemID)
  end
  return nil
end

local function itemIcon(itemID)
  return C_Item.GetItemIconByID(itemID) or UNKNOWN_ICON
end

-- Adds the counts of one table to the totals.
local function add(totals, counts)
  if type(counts) ~= "table" then
    return
  end
  for itemID, count in pairs(counts) do
    if type(itemID) == "number" and type(count) == "number" then
      totals[itemID] = (totals[itemID] or 0) + count
    end
  end
end

-- Reads the store. Returns true if a name is still missing.
local function collect()
  local totals = {}
  for _, character in ipairs(ns.Characters()) do
    if not onlyCharacter or character.key == onlyCharacter then
      add(totals, character.record.bags)
      add(totals, character.record.bank)
      add(totals, character.record.equipped)
    end
  end
  if not onlyCharacter then
    add(totals, ForeverBagsDB.accountBank)
  end
  items = {}
  local missing = false
  for itemID, total in pairs(totals) do
    local name = itemName(itemID)
    missing = missing or name == nil
    if filter == "" or (name and name:lower():find(filter, 1, true)) then
      items[#items + 1] = { id = itemID, total = total, name = name }
    end
  end
  table.sort(items, function(a, b)
    if (a.name == nil) ~= (b.name == nil) then
      return a.name ~= nil -- items without a name yet go to the end
    end
    if a.name ~= b.name then
      return (a.name or "") < (b.name or "")
    end
    return a.id < b.id
  end)
  return missing
end

-- "Name: 12 (bags 8, bank 4)" for each owner of an item.
function ns.OwnerLines(itemID)
  local owners, shared, total = ns.Owners(itemID)
  local lines = {}
  for _, owner in ipairs(owners) do
    local parts = {}
    if owner.bags > 0 then
      parts[#parts + 1] = "bags " .. owner.bags
    end
    if owner.bank > 0 then
      parts[#parts + 1] = "bank " .. owner.bank
    end
    if owner.equipped > 0 then
      parts[#parts + 1] = "equipped " .. owner.equipped
    end
    lines[#lines + 1] = {
      name = owner.record.name or owner.key,
      class = owner.record.class,
      isMe = owner.isMe,
      total = owner.total,
      text = owner.total .. (#parts > 1 and (" (" .. table.concat(parts, ", ") .. ")") or (" (" .. (parts[1] or "") .. ")")),
    }
  end
  return lines, shared, total
end

local function render()
  if not frame then
    return
  end
  offset = math.max(0, math.min(offset, #items - ROWS))
  for index, row in ipairs(frame.rows) do
    local item = items[offset + index]
    row.item = item
    row:SetShown(item ~= nil)
    if item then
      row.icon:SetTexture(itemIcon(item.id))
      row.name:SetText(item.name or ("Item " .. item.id))
      row.count:SetText(item.total)
    end
  end
  frame.empty:SetShown(#items == 0)
end

local function goldLine()
  local total, parts = 0, {}
  for _, character in ipairs(ns.Characters()) do
    local money = character.record.money
    if type(money) == "number" then
      total = total + money
      if not onlyCharacter or character.key == onlyCharacter then
        parts[#parts + 1] = (character.record.name or character.key) .. " " .. ns.Money(money)
      end
    end
  end
  if onlyCharacter then
    return table.concat(parts, "   ")
  end
  return "Gold of all characters: " .. ns.Money(total)
end

local function rebuild()
  if not (frame and frame:IsShown()) then
    return
  end
  frame.missing = collect()
  local who = "All characters"
  for _, character in ipairs(ns.Characters()) do
    if character.key == onlyCharacter then
      who = character.record.name or character.key
    end
  end
  frame.who:SetText(who)
  frame.gold:SetText(goldLine())
  frame.count:SetText(#items .. " kinds of items")
  render()
end

local function chooseCharacter(owner)
  local characters = ns.Characters()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateRadio("All characters", function()
      return onlyCharacter == nil
    end, function()
      onlyCharacter = nil
      offset = 0
      rebuild()
    end)
    for _, character in ipairs(characters) do
      local label = (character.record.name or character.key) .. " - " .. (character.record.realm or "")
      root:CreateRadio(label, function()
        return onlyCharacter == character.key
      end, function()
        onlyCharacter = character.key
        offset = 0
        rebuild()
      end)
    end
  end)
end

local function showRowTooltip(row)
  local item = row.item
  if not item then
    return
  end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  -- The tooltip of the item. Tooltip.lua adds the owners to it.
  if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.id) then
    GameTooltip:SetText(item.name or ("Item " .. item.id), 1, 1, 1)
  end
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
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("browser", self)
  end)
  frame:Hide()
  tinsert(UISpecialFrames, FRAME_NAME) -- Escape closes the window

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.04, 0.05, 0.94)
  local headerBack = frame:CreateTexture(nil, "BORDER")
  headerBack:SetPoint("TOPLEFT")
  headerBack:SetPoint("TOPRIGHT")
  headerBack:SetHeight(26)
  headerBack:SetColorTexture(0.2, 0.35, 0.5, 0.9)

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -7)
  title:SetText("Forever Bags: items of all characters")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local ok, box = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
  if not ok then
    box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  end
  box:SetSize(200, 20)
  box:SetPoint("TOPLEFT", 16, -36)
  box:SetAutoFocus(false)
  box:HookScript("OnTextChanged", function(self)
    local text = ((self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if text ~= filter then
      filter = text
      offset = 0
      rebuild()
    end
  end)
  box:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  local whoButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  whoButton:SetSize(200, 22)
  whoButton:SetPoint("LEFT", box, "RIGHT", 14, 0)
  whoButton:SetScript("OnClick", chooseCharacter)
  frame.who = whoButton

  frame.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, -66 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    if index % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.count:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:EnableMouse(true)
    row:SetScript("OnEnter", showRowTooltip)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    frame.rows[index] = row
  end

  frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  frame.empty:SetPoint("TOP", 0, -140)
  frame.empty:SetWidth(WIDTH - 80)
  frame.empty:SetText("No items. The bank of a character is in the list after you open it at a banker with that character.")

  frame.gold = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.gold:SetPoint("BOTTOMLEFT", 12, 30)
  frame.gold:SetPoint("RIGHT", -12, 0)
  frame.gold:SetJustifyH("LEFT")
  frame.gold:SetWordWrap(false)
  frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  frame.count:SetPoint("BOTTOMLEFT", 12, 10)

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    render()
  end)
  frame:SetScript("OnShow", function()
    offset = 0
    rebuild()
  end)
  -- Names arrive after the client loads the items: the list reads them again while one is missing.
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

  ns.RestorePosition("browser", frame, "CENTER", 0, 20)
end

function ns.ShowBrowser()
  if not frame then
    local ok, problem = pcall(create)
    if not ok then
      frame = nil
      ns.Print("the list could not be made: " .. tostring(problem))
      return
    end
  end
  frame:Show()
  if frame.Raise then
    frame:Raise()
  end
end

function ns.ToggleBrowser()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    ns.ShowBrowser()
  end
end

ns.OnStoreChanged(rebuild)

ns.OnResetPositions(function()
  if frame then
    ns.RestorePosition("browser", frame, "CENTER", 0, 20)
  end
end)
