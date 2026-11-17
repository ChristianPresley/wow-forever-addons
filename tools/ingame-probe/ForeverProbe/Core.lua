-- Forever Probe: asks the game client what it does in the cases that neither Blizzard's
-- documentation, the game's own UI code nor the public reference settles.
--
-- Use: copy this folder to Interface/AddOns, log in, type /foreverprobe. Each line is one
-- case with what the game answered. The same lines are saved in ForeverProbeDB.lines
-- (WTF/Account/<account>/SavedVariables/ForeverProbe.lua after /reload or logout).
-- docs/addon-development.md, "Where the sources say nothing", says how the answers are used:
-- tools/ingame-probe/answers.txt has them, and a test compares the stand-in with them.

local lines = {}

local function show(value)
  if type(value) == "table" and value.GetObjectType then
    return "<" .. value:GetObjectType() .. ">"
  end
  return tostring(value)
end

-- Runs one case. The line says "ok" with the results, or "error" with the text of the game.
local function case(name, fn)
  local results = { pcall(fn) }
  local parts = {}
  for index = 2, #results do
    parts[#parts + 1] = show(results[index])
  end
  lines[#lines + 1] = name .. " = " .. (results[1] and "ok" or "error") .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
end

local function run()
  wipe(lines)
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetSize(100, 100)
  host:SetPoint("CENTER")

  -- A name in another letter case.
  case("SetPoint with a lower-case point", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("topleft")
    return f:GetPoint(1)
  end)
  case("CreateAnimation with a lower-case type", function()
    return host:CreateAnimationGroup():CreateAnimation("alpha"):GetObjectType()
  end)
  case("SetOwner with a lower-case anchor", function()
    GameTooltip:SetOwner(host, "anchor_right")
    GameTooltip:Hide()
  end)
  case("SetFrameStrata with a lower-case strata", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetFrameStrata("dialog")
    return f:GetFrameStrata()
  end)
  case("CreateTexture with a lower-case draw layer", function()
    return host:CreateTexture(nil, "artwork"):GetDrawLayer()
  end)
  case("SetJustifyH with a lower-case value", function()
    local text = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetJustifyH("right")
    return text:GetJustifyH()
  end)

  -- A value outside the range.
  case("StatusBar:SetValue above the range, then GetValue", function()
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetMinMaxValues(0, 10)
    bar:SetValue(50)
    return bar:GetValue()
  end)
  case("StatusBar: the range made smaller than the value, then GetValue", function()
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(80)
    bar:SetMinMaxValues(0, 10)
    return bar:GetValue()
  end)
  case("Slider: the range made smaller than the value: GetValue, calls of OnValueChanged", function()
    local slider = CreateFrame("Slider", nil, host)
    slider:SetMinMaxValues(0, 100)
    slider:SetValue(80)
    local calls = 0
    slider:SetScript("OnValueChanged", function() calls = calls + 1 end)
    slider:SetMinMaxValues(0, 10)
    return slider:GetValue(), calls
  end)
  case("Slider:SetValue above the range, then GetValue", function()
    local slider = CreateFrame("Slider", nil, host)
    slider:SetMinMaxValues(0, 10)
    slider:SetValue(50)
    return slider:GetValue()
  end)
  case("Slider:SetValue between two steps, then GetValue", function()
    local slider = CreateFrame("Slider", nil, host)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(7)
    return slider:GetValue()
  end)

  -- Cases that the stand-in takes from a reference outside the game's files. A different
  -- answer here means that the stand-in is wrong for this client.
  case("GetObjectType of an ItemButton, an EventFrame, a DropdownButton", function()
    return CreateFrame("ItemButton", nil, host):GetObjectType(), CreateFrame("EventFrame", nil, host):GetObjectType(), CreateFrame("DropdownButton", nil, host):GetObjectType()
  end)
  case("IsObjectType('ItemButton') and ('Button') of an ItemButton", function()
    local button = CreateFrame("ItemButton", nil, host)
    return button:IsObjectType("ItemButton"), button:IsObjectType("Button")
  end)
  case("SetAlpha(2), then GetAlpha", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetAlpha(2)
    return f:GetAlpha()
  end)
  case("SetAllPoints with the name of a frame", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints("UIParent")
    return f:GetNumPoints(), select(2, f:GetPoint(1))
  end)
  case("SetAllPoints(true)", function()
    CreateFrame("Frame", nil, host):SetAllPoints(true)
  end)
  case("SetParent with the name of a frame", function()
    CreateFrame("Frame", nil, host):SetParent("UIParent")
  end)
  case("Two frames anchored to each other", function()
    local a, b = CreateFrame("Frame", nil, host), CreateFrame("Frame", nil, host)
    a:SetPoint("LEFT", b, "RIGHT")
    b:SetPoint("LEFT", a, "RIGHT")
  end)
  case("A frame anchored to itself", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("CENTER", f, "CENTER")
  end)
  case("SetFrameStrata('WORLD')", function()
    CreateFrame("Frame", nil, host):SetFrameStrata("WORLD")
  end)
  case("SetOwner with ANCHOR_CURSOR_LEFT", function()
    GameTooltip:SetOwner(host, "ANCHOR_CURSOR_LEFT")
    GameTooltip:Hide()
  end)
  case("SetScript with a script that the frame does not have", function()
    CreateFrame("Frame", nil, host):SetScript("OnClick", function() end)
  end)
  case("HookScript of OnTooltipSetItem on a tooltip", function()
    GameTooltip:HookScript("OnTooltipSetItem", function() end)
  end)
  case("A hidden parent and its child: the scripts in order", function()
    local order = ""
    local parent = CreateFrame("Frame", nil, host)
    local child = CreateFrame("Frame", nil, parent)
    parent:SetScript("OnHide", function() order = order .. "parent hides, " end)
    child:SetScript("OnHide", function() order = order .. "child hides, " end)
    parent:SetScript("OnShow", function() order = order .. "parent shows, " end)
    child:SetScript("OnShow", function() order = order .. "child shows, " end)
    parent:Hide()
    parent:Show()
    return order
  end)
  case("The same point set twice: GetNumPoints", function()
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("CENTER")
    f:SetPoint("CENTER", 5, 5)
    return f:GetNumPoints()
  end)
  case("GetText of a font string and of a button without a text", function()
    return host:CreateFontString(nil, "ARTWORK", "GameFontNormal"):GetText(), CreateFrame("Button", nil, host):GetText()
  end)
  case("A tooltip after SetOwner and AddLine: IsShown", function()
    GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
    GameTooltip:AddLine("A line")
    local shown = GameTooltip:IsShown()
    GameTooltip:Hide()
    return shown
  end)
  case("Click of a disabled button: calls of OnClick", function()
    local calls = 0
    local button = CreateFrame("Button", nil, host)
    button:SetScript("OnClick", function() calls = calls + 1 end)
    button:Disable()
    button:Click()
    return calls
  end)
  host:Hide()

  ForeverProbeDB = { client = (select(4, GetBuildInfo())), build = (select(2, GetBuildInfo())), lines = lines }
  for _, line in ipairs(lines) do
    print("|cff66ccffForever Probe|r " .. line)
  end
  print("|cff66ccffForever Probe|r " .. #lines .. " cases. They are saved after /reload.")
end

SLASH_FOREVERPROBE1 = "/foreverprobe"
SlashCmdList["FOREVERPROBE"] = run
