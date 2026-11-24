local _, ns = ...

-- Export and import of the learned nodes as text, to pass them to another player or account.
--
-- The text: the line "FG1", then one line for each node:
--   <map>;<kind>;<x>;<y>;<name>
-- x and y are whole numbers from 0 to 10000 (ten-thousandths of the map). The name is the rest
-- of the line. An import adds the nodes that are not known yet; it changes and deletes nothing.
-- An imported node has the count 0 until the player gathers it.

local HEADER = "FG1"
local SCALE = 10000
local MAX_LINES = 20000
local MAX_NAME = 80

-- Returns the text and the number of nodes in it.
function ns.ExportNodes()
  local maps = {}
  for mapID in pairs(ForeverGatherDB.nodes) do
    maps[#maps + 1] = mapID
  end
  table.sort(maps)
  local lines, count = { HEADER }, 0
  for _, mapID in ipairs(maps) do
    for _, node in ipairs(ForeverGatherDB.nodes[mapID]) do
      lines[#lines + 1] = string.format("%d;%s;%d;%d;%s", mapID, node.kind,
        math.floor(node.x * SCALE + 0.5), math.floor(node.y * SCALE + 0.5), (node.name:gsub("[\r\n]", " ")))
      count = count + 1
    end
  end
  return table.concat(lines, "\n"), count
end

-- Adds the nodes of an export. Returns the number of nodes read and the number added, or nil
-- and the reason.
function ns.ImportNodes(text)
  if type(text) ~= "string" then
    return nil, "there is no text to import."
  end
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      lines[#lines + 1] = line
      if #lines > MAX_LINES then
        return nil, "the text has more than " .. MAX_LINES .. " lines."
      end
    end
  end
  if lines[1] ~= HEADER then
    return nil, "this is not an export of Forever Gather: the first line is not " .. HEADER .. "."
  end
  -- Read everything first: a text with a wrong line changes nothing.
  local read = {}
  for index = 2, #lines do
    local map, kind, x, y, name = lines[index]:match("^(%d+);(%a+);(%d+);(%d+);(.+)$")
    local mapID, nx, ny = tonumber(map), tonumber(x), tonumber(y)
    if not mapID or not ns.KIND[kind] or nx > SCALE or ny > SCALE or #name > MAX_NAME then
      return nil, string.format("line %d is not a node: %s", index, lines[index]:sub(1, 60))
    end
    if not ns.MapTooLarge(mapID) then
      read[#read + 1] = { mapID = mapID, kind = kind, x = nx / SCALE, y = ny / SCALE, name = name }
    end
  end
  local added = 0
  local nodes = ForeverGatherDB.nodes
  for _, entry in ipairs(read) do
    nodes[entry.mapID] = nodes[entry.mapID] or {}
    local list = nodes[entry.mapID]
    if not ns.FindNode(list, entry.kind, entry.name, entry.x, entry.y) then
      list[#list + 1] = { kind = entry.kind, name = entry.name, x = entry.x, y = entry.y, count = 0, imported = true }
      if type(ForeverGatherDB.names[entry.name]) ~= "table" then
        ForeverGatherDB.names[entry.name] = { kind = entry.kind }
      end
      added = added + 1
    end
  end
  if added > 0 then
    ns.Changed()
  end
  return #read, added
end

---------------------------------------------------------------------------------------------------
-- The window: one text box, filled for an export, empty for an import.

local FRAME_NAME = "ForeverGatherShare"
local frame

local function createWindow()
  frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  frame:Hide()
  frame:SetSize(520, 320)
  frame:SetPoint("CENTER")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, FRAME_NAME)

  frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.help:SetPoint("TOPLEFT", 16, -32)
  frame.help:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
  frame.help:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -64)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontSmall")
  box:SetWidth(460)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  scroll:SetScrollChild(box)
  frame.box = box

  frame.action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.action:SetSize(140, 22)
  frame.action:SetPoint("BOTTOMRIGHT", -16, 14)
  frame.action:SetScript("OnClick", function()
    if frame.mode == "import" then
      local read, added = ns.ImportNodes(box:GetText())
      if read then
        ns.Print(string.format("%d |4node:nodes; read, %d of them new.", read, added))
        box:SetText("")
        frame:Hide()
      else
        ns.Print("Nothing imported: " .. added)
      end
    else
      box:SetFocus()
      box:HighlightText()
    end
  end)
end

local function open(mode)
  if not frame then
    createWindow()
  end
  frame.mode = mode
  if mode == "import" then
    frame.TitleText:SetText("Forever Gather: import nodes")
    frame.help:SetText("Paste the text of an export below (Ctrl+V) and click Import. Nodes that you do not know yet are added; nothing is changed or deleted.")
    frame.box:SetText("")
    frame.action:SetText("Import")
  else
    local text, count = ns.ExportNodes()
    frame.TitleText:SetText("Forever Gather: export nodes")
    frame.help:SetText(string.format("%d |4node:nodes;. Copy the text below (Ctrl+C); another player imports it with /fgather import.", count))
    frame.box:SetText(text)
    frame.action:SetText("Select all")
  end
  frame:Show()
  frame.box:SetFocus()
  if mode == "export" then
    frame.box:HighlightText()
  end
end

function ns.ShowExport()
  open("export")
end

function ns.ShowImport()
  open("import")
end
