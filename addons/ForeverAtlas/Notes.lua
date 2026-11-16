local _, ns = ...

-- Map notes: ForeverAtlasDB.notes[mapID] = { { x = n, y = n, text = s, icon = n, t = n }, ... } with x, y from 0 to 100.
-- Alt-left-click on the world map adds one. Plain clicks stay with the map (zoom), Ctrl-click with
-- the game's own map pin and Shift-click with other addons.

local MAX_LETTERS = 80
local CLICK_PRIORITY = 1100
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local ICON_COUNT = 8

local editor

local function clean(text)
  return ((text or ""):gsub("|", ""):match("^%s*(.-)%s*$"))
end

local function iconOf(note)
  local icon = ns.Usable(note.icon) and note.icon >= 1 and note.icon <= ICON_COUNT and note.icon or 1
  return ICON_PATH .. icon
end

local function remove(mapID, note)
  local list = ForeverAtlasDB.notes[mapID]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i] == note then
      table.remove(list, i)
    end
  end
  if #list == 0 then
    ForeverAtlasDB.notes[mapID] = nil
  end
  ns.RefreshPins()
end

function ns.AddNote(mapID, x, y, text, icon)
  local notes = ForeverAtlasDB.notes
  if type(notes[mapID]) ~= "table" then
    notes[mapID] = {}
  end
  local note = { x = x, y = y, text = text, icon = icon or 1, t = time() }
  table.insert(notes[mapID], note)
  ns.RefreshPins()
  return note
end

local function selectIcon(index)
  editor.icon = index
  for i, button in ipairs(editor.icons) do
    button.ring:SetShown(i == index)
  end
end

local function close()
  editor.box:ClearFocus()
  editor:Hide()
end

local function save()
  local text = clean(editor.box:GetText())
  if text == "" then
    text = "Note"
  end
  if editor.note then
    editor.note.text, editor.note.icon = text, editor.icon
    ns.RefreshPins()
  else
    ns.AddNote(editor.mapID, editor.x, editor.y, text, editor.icon)
  end
  close()
end

local function button(parent, label, width, onClick)
  local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  frame:SetSize(width, 22)
  frame:SetText(label)
  frame:SetScript("OnClick", onClick)
  return frame
end

local function buildEditor()
  editor = CreateFrame("Frame", "ForeverAtlasNoteEditor", UIParent)
  editor:SetSize(300, 132)
  editor:SetPoint("CENTER")
  editor:SetFrameStrata("DIALOG")
  editor:EnableMouse(true)
  editor:SetClampedToScreen(true)
  editor:Hide()
  table.insert(UISpecialFrames, "ForeverAtlasNoteEditor")

  local background = editor:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.05, 0.05, 0.05, 0.92)

  editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  editor.title:SetPoint("TOPLEFT", 12, -10)

  editor.box = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  editor.box:SetSize(270, 22)
  editor.box:SetPoint("TOPLEFT", 18, -30)
  editor.box:SetAutoFocus(false)
  editor.box:SetMaxLetters(MAX_LETTERS)
  editor.box:SetScript("OnEnterPressed", save)
  editor.box:SetScript("OnEscapePressed", close)

  editor.icons = {}
  for i = 1, ICON_COUNT do
    local choice = CreateFrame("Button", nil, editor)
    choice:SetSize(24, 24)
    choice:SetPoint("TOPLEFT", 14 + (i - 1) * 34, -62)
    local texture = choice:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(ICON_PATH .. i)
    choice.ring = choice:CreateTexture(nil, "BACKGROUND")
    choice.ring:SetPoint("TOPLEFT", -4, 4)
    choice.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    choice.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    choice.ring:SetBlendMode("ADD")
    choice:SetScript("OnClick", function()
      selectIcon(i)
    end)
    editor.icons[i] = choice
  end

  editor.save = button(editor, "Save", 80, save)
  editor.save:SetPoint("BOTTOMLEFT", 12, 10)
  editor.delete = button(editor, "Delete", 80, function()
    if editor.note then
      remove(editor.mapID, editor.note)
    end
    close()
  end)
  editor.delete:SetPoint("LEFT", editor.save, "RIGHT", 8, 0)
  editor.cancel = button(editor, "Cancel", 80, close)
  editor.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
end

-- Opens the editor for an existing note, or for a new one at x, y on mapID.
local function edit(mapID, x, y, note)
  if not editor then
    buildEditor()
  end
  editor.mapID, editor.x, editor.y, editor.note = mapID, x, y, note
  editor.title:SetText(string.format("%s - %s %.1f, %.1f", note and "Edit note" or "New note", ns.MapName(mapID), x, y))
  editor.box:SetText(note and note.text or "")
  editor.delete:SetShown(note ~= nil)
  selectIcon(note and ns.Usable(note.icon) and note.icon >= 1 and note.icon <= ICON_COUNT and note.icon or 1)
  editor:Show()
  editor.box:SetFocus()
end

ns.AddPinProvider(function(mapID, add)
  if not ns.GetOption("notes") then
    return
  end
  local list = ForeverAtlasDB.notes[mapID]
  if type(list) ~= "table" then
    return
  end
  for _, note in ipairs(list) do
    if type(note) == "table" and type(note.text) == "string" then
      add(note.x, note.y, {
        look = { texture = iconOf(note) },
        size = 18,
        tooltip = function(tooltip)
          tooltip:AddLine(note.text, 1, 1, 1, true)
          if ns.Usable(note.t) then
            tooltip:AddLine(date("%Y-%m-%d", note.t), 0.6, 0.6, 0.6)
          end
          tooltip:AddLine("Click to edit or delete", 0.6, 0.6, 0.6)
        end,
        click = function()
          edit(mapID, note.x, note.y, note)
        end,
      })
    end
  end
end)

-- /fatlas note <text>: a note where the player stands.
function ns.NoteCommand(text)
  text = clean(text)
  if text == "" then
    ns.Print("usage: /fatlas note <text>. On the world map, Alt-click adds a note at the cursor.")
    return
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  local x, y = ns.PlayerPosition(mapID)
  if not x then
    ns.Print("the game does not give your position here.")
    return
  end
  ns.AddNote(mapID, x, y, text:sub(1, MAX_LETTERS))
  if not ns.GetOption("notes") then
    ns.SetOption("notes", true)
  end
  ns.Print(string.format("note added at %s %.1f, %.1f.", ns.MapName(mapID), x, y))
end

-- Opens the editor for a new note at a place of a map (x, y from 0 to 100). For the Forever
-- Atlas map. Returns true if the editor opened.
function ns.EditNote(mapID, x, y)
  if not ns.GetOption("notes") then
    return false
  end
  local ok, err = pcall(edit, mapID, x, y)
  if not ok then
    geterrorhandler()(err)
  end
  return ok
end

local function onCanvasClick(_, mouseButton, cursorX, cursorY)
  if mouseButton ~= "LeftButton" or not IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown() then
    return false
  end
  if not ns.GetOption("notes") then
    return false
  end
  local mapID = WorldMapFrame:GetMapID()
  if not ns.Usable(cursorX) or not ns.Usable(cursorY) then
    if not WorldMapFrame.GetNormalizedCursorPosition then
      return false
    end
    cursorX, cursorY = WorldMapFrame:GetNormalizedCursorPosition()
  end
  if not mapID or not ns.Usable(cursorX) or not ns.Usable(cursorY) or cursorX < 0 or cursorX > 1 or cursorY < 0 or cursorY > 1 then
    return false
  end
  local ok, err = pcall(edit, mapID, cursorX * 100, cursorY * 100)
  if not ok then
    geterrorhandler()(err)
  end
  return true
end

ns.OnOption(function(key)
  if key == "notes" then
    ns.RefreshPins()
  end
end)

ns.OnLogin(function()
  -- Numeric keys can come back as strings from an edited file.
  local notes = ForeverAtlasDB.notes
  local odd = {}
  for key in pairs(notes) do
    if type(key) ~= "number" then
      odd[#odd + 1] = key
    end
  end
  for _, key in ipairs(odd) do
    local list = notes[key]
    notes[key] = nil
    if tonumber(key) and type(list) == "table" and notes[tonumber(key)] == nil then
      notes[tonumber(key)] = list
    end
  end
  ns.WhenMapReady(function()
    if WorldMapFrame.AddCanvasClickHandler then
      WorldMapFrame:AddCanvasClickHandler(onCanvasClick, CLICK_PRIORITY)
    end
  end)
end)
