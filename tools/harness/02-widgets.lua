
---------------------------------------------------------------------------------------------------
-- Part 2: frames and other widgets
--
-- Blizzard's documentation has the methods of the widgets in "script objects" (SimpleFrameAPI,
-- SimpleFontStringAPI and so on). It does not say which kind of widget has which script
-- objects: LAYERS below does, from the element types of Blizzard_SharedXML/UI.xsd.
-- A widget of a kind has the methods of its layers and nothing else.
--
-- A hand-written method is registered for one layer with `define`. The layer must document
-- the name. `undocumented` is for a method that the documentation lacks: it needs the file of
-- the game's own UI code that uses it.

local function join(...)
  local out = {}
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    if realType(part) == "table" then
      for _, name in ipairs(part) do
        out[#out + 1] = name
      end
    else
      out[#out + 1] = part
    end
  end
  return out
end

local OBJECT = { "SimpleFrameScriptObjectAPI", "SimpleObjectAPI" }
local SCRIPT_REGION = join(OBJECT, "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleAnimatableObjectAPI")
local REGION = join(SCRIPT_REGION, "SimpleRegionAPI")
local TEXTURE_BASE = join(REGION, "SimpleTextureBaseAPI")
local FRAME = join(SCRIPT_REGION, "SimpleFrameAPI")
local BUTTON = join(FRAME, "SimpleButtonAPI")
local MODEL = join(FRAME, "SimpleModelAPI")
local ANIMATION = join(OBJECT, "SimpleAnimAPI")

local LAYERS = {
  -- Regions
  Texture = join(TEXTURE_BASE, "SimpleTextureAPI"),
  MaskTexture = TEXTURE_BASE,
  Line = join(TEXTURE_BASE, "SimpleLineAPI"),
  FontString = join(REGION, "SimpleFontStringAPI"),
  -- Frames
  Frame = FRAME,
  EventFrame = FRAME,
  Button = BUTTON,
  ItemButton = BUTTON,
  DropdownButton = BUTTON,
  EventButton = BUTTON,
  CheckButton = join(BUTTON, "SimpleCheckboxAPI"),
  EditBox = join(FRAME, "SimpleEditBoxAPI"),
  EventEditBox = join(FRAME, "SimpleEditBoxAPI"),
  Slider = join(FRAME, "SimpleSliderAPI"),
  StatusBar = join(FRAME, "SimpleStatusBarAPI"),
  ScrollFrame = join(FRAME, "SimpleScrollFrameAPI"),
  EventScrollFrame = join(FRAME, "SimpleScrollFrameAPI"),
  MessageFrame = join(FRAME, "SimpleMessageFrameAPI"),
  ScrollingMessageFrame = join(FRAME, "SimpleMessageFrameAPI"),
  SimpleHTML = join(FRAME, "SimpleHTMLAPI"),
  ColorSelect = join(FRAME, "SimpleColorSelectAPI"),
  GameTooltip = join(FRAME, "FrameAPITooltip"),
  Cooldown = join(FRAME, "FrameAPICooldown"),
  Model = MODEL,
  PlayerModel = join(MODEL, "FrameAPICharacterModelBase"),
  DressUpModel = join(MODEL, "FrameAPICharacterModelBase", "FrameAPIDressUpModel"),
  TabardModel = join(MODEL, "FrameAPICharacterModelBase", "FrameAPITabardModelBase", "FrameAPITabardModel"),
  CinematicModel = join(MODEL, "FrameAPICharacterModelBase", "FrameAPICinematicModel"),
  ModelFFX = join(MODEL, "SimpleModelFFXAPI"),
  MapScene = join(MODEL, "SimpleMapSceneAPI"),
  ModelScene = join(FRAME, "FrameAPIModelSceneFrame"),
  Minimap = join(FRAME, "MinimapFrameAPI"),
  MovieFrame = join(FRAME, "SimpleMovieAPI"),
  Browser = join(FRAME, "SimpleBrowserAPI"),
  Checkout = join(FRAME, "FrameAPISimpleCheckout"),
  OffScreenFrame = join(FRAME, "SimpleOffScreenFrameAPI"),
  -- Frames of the game's map. The three with a blob have the methods of FrameAPIBlob: the
  -- game's code calls DrawNone and SetFillTexture on a quest blob frame
  -- (Blizzard_SharedMapDataProviders/QuestBlobDataProvider.lua).
  UnitPositionFrame = join(FRAME, "FrameAPIUnitPositionFrame"),
  FogOfWarFrame = join(FRAME, "FrameAPIFogOfWarFrame"),
  QuestPOIFrame = join(FRAME, "FrameAPIBlob", "FrameAPIQuestPOI"),
  ScenarioPOIFrame = join(FRAME, "FrameAPIBlob", "FrameAPIScenarioPOI"),
  ArchaeologyDigSiteFrame = join(FRAME, "FrameAPIBlob", "FrameAPIArchaeologyDigSiteFrame"),
  -- Animations
  AnimationGroup = join(OBJECT, "SimpleAnimGroupAPI"),
  Animation = ANIMATION,
  Alpha = join(ANIMATION, "SimpleAnimAlphaAPI"),
  Rotation = join(ANIMATION, "SimpleAnimRotationAPI"),
  Scale = join(ANIMATION, "SimpleAnimScaleAPI"),
  LineScale = join(ANIMATION, "SimpleAnimScaleAPI", "SimpleAnimScaleLineAPI"),
  Translation = join(ANIMATION, "SimpleAnimTranslationAPI"),
  LineTranslation = join(ANIMATION, "SimpleAnimTranslationAPI", "SimpleAnimTranslationLineAPI"),
  Path = join(ANIMATION, "SimpleAnimPathAPI"),
  FlipBook = join(ANIMATION, "SimpleAnimFlipBookAPI"),
  VertexColor = join(ANIMATION, "SimpleAnimVertexColorAPI"),
  TextureCoordTranslation = join(ANIMATION, "SimpleAnimTextureCoordTranslationAPI"),
  RadialProgress = join(ANIMATION, "SimpleAnimRadialProgressAPI"),
  -- Fonts
  Font = join(OBJECT, "SimpleFontAPI"),
}

-- What the game's UI files say and the documentation does not (tools/api/forever-ui.json, built
-- by `cargo dev ui-names`): fonts, undocumented events, frame types, animation types, and the
-- scripts that the XML files put on each kind.
local UI_NAMES = snapshot.ui or {}

-- The kinds that CreateFrame makes: all but the regions, the animations and the font.
local NOT_A_FRAME = {
  Texture = true, MaskTexture = true, Line = true, FontString = true, AnimationGroup = true, Animation = true,
  Alpha = true, Rotation = true, Scale = true, LineScale = true, Translation = true, LineTranslation = true,
  Path = true, FlipBook = true, VertexColor = true, TextureCoordTranslation = true, RadialProgress = true,
  Font = true,
}

-- A frame type of the game that is not written above is made from another frame type, and has
-- the methods of that one: an ItemButton and a ContainedAlertFrame are buttons
-- (Blizzard_SharedXML/UI.xsd, and the intrinsic frames of the XML files).
do
  local function layersOf(name, depth)
    if LAYERS[name] then
      return LAYERS[name]
    end
    local base = UI_NAMES.frameTypes and UI_NAMES.frameTypes[name]
    if base and base ~= "" and depth < 8 then
      return layersOf(base, depth + 1)
    end
  end
  local names = {}
  for name in pairs(UI_NAMES.frameTypes or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    if not LAYERS[name] and not NOT_A_FRAME[name] then
      LAYERS[name] = layersOf(name, 0)
    end
  end
end
local FRAME_KIND = {} -- lower case name -> name
for kind in pairs(LAYERS) do
  if not NOT_A_FRAME[kind] then
    FRAME_KIND[kind:lower()] = kind
  end
end

-- What IsObjectType answers yes to, besides the kind itself.
local ANCESTORS = {
  SimpleScriptRegionAPI = "ScriptRegion", SimpleRegionAPI = "Region", SimpleFrameAPI = "Frame",
  SimpleButtonAPI = "Button", SimpleTextureBaseAPI = "TextureBase", SimpleAnimAPI = "Animation",
  SimpleModelAPI = "Model", SimpleObjectAPI = "Object",
  -- For the kinds that the game derives from these: an EventEditBox is an EditBox.
  SimpleEditBoxAPI = "EditBox", SimpleScrollFrameAPI = "ScrollFrame", SimpleMessageFrameAPI = "MessageFrame",
  SimpleCheckboxAPI = "CheckButton", SimpleSliderAPI = "Slider", SimpleStatusBarAPI = "StatusBar",
}

-- The scripts of each layer (Blizzard_SharedXML/UI.xsd). SetScript with another name fails.
local LAYER_SCRIPTS = {
  SimpleScriptRegionAPI = { "OnShow", "OnHide", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnLoad" },
  SimpleFrameAPI = {
    "OnUpdate", "OnEvent", "OnSizeChanged", "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnKeyDown", "OnKeyUp",
    "OnChar", "OnAttributeChanged", "OnEnable", "OnDisable", "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave",
    "OnGamePadButtonDown", "OnGamePadButtonUp", "OnGamePadStick",
  },
  SimpleButtonAPI = { "OnClick", "PreClick", "PostClick", "OnDoubleClick" },
  SimpleEditBoxAPI = {
    "OnTextChanged", "OnEnterPressed", "OnEscapePressed", "OnTabPressed", "OnSpacePressed", "OnEditFocusGained",
    "OnEditFocusLost", "OnCursorChanged", "OnTextSet", "OnInputLanguageChanged", "OnArrowPressed", "OnCharComposition",
  },
  SimpleSliderAPI = { "OnValueChanged", "OnMinMaxChanged" },
  SimpleStatusBarAPI = { "OnValueChanged", "OnMinMaxChanged" },
  SimpleScrollFrameAPI = { "OnVerticalScroll", "OnHorizontalScroll", "OnScrollRangeChanged" },
  -- OnTooltipSetFramestack: Blizzard_DebugTools/Blizzard_DebugTools.xml. The scripts
  -- OnTooltipSetItem, OnTooltipSetSpell and OnTooltipSetUnit are in UI.xsd, and no file of this
  -- client uses them: TooltipDataProcessor took their place.
  FrameAPITooltip = { "OnTooltipCleared", "OnTooltipSetDefaultAnchor", "OnTooltipAddMoney", "OnTooltipSetFramestack" },
  FrameAPICooldown = { "OnCooldownDone" },
  SimpleMessageFrameAPI = { "OnMessageScrollChanged" },
  SimpleColorSelectAPI = { "OnColorSelect" },
  -- OnAnimStarted: Blizzard_RecruitAFriend/RecruitAFriendFrame.xml.
  SimpleModelAPI = { "OnAnimFinished", "OnAnimStarted", "OnModelLoaded", "OnModelCleared", "OnUpdateModel" },
  -- Blizzard_UIPanels_Game/Mainline/DressUpFrames.xml
  FrameAPIModelSceneFrame = { "OnDressModel" },
  FrameAPIDressUpModel = { "OnDressModel" },
  -- Blizzard_HelpFrame/HelpFrame.xml
  SimpleBrowserAPI = { "OnExternalLink", "OnButtonUpdate", "OnError", "OnEscapePressed" },
  -- Blizzard_SimpleCheckout/Blizzard_SimpleCheckout.xml
  FrameAPISimpleCheckout = { "OnExternalLink", "OnRequestNewSize" },
  -- Blizzard_UIPanels_Game/Mainline/FogOfWarFrameTemplates.xml
  FrameAPIFogOfWarFrame = { "OnUiMapChanged" },
  SimpleAnimGroupAPI = { "OnPlay", "OnFinished", "OnLoop", "OnStop", "OnPause", "OnUpdate", "OnLoad" },
  SimpleAnimAPI = { "OnPlay", "OnFinished", "OnStop", "OnPause", "OnUpdate", "OnLoad" },
  SimpleMovieAPI = { "OnMovieFinished", "OnMovieShowSubtitle", "OnMovieHideSubtitle" },
}

local implementations = {} -- [layer][name] = function

local function define(layer, name, fn)
  local object = snapshot.widgets[layer]
  if not object or not object.methods[name] then
    error("the stand-in defines " .. layer .. ":" .. name .. ", which the API snapshot does not have")
  end
  implementations[layer] = implementations[layer] or {}
  implementations[layer][name] = { fn = fn, spec = object.methods[name] }
end

-- `where`: the file of the game's own UI code that uses the method.
local function undocumented(layer, name, where, fn)
  local object = snapshot.widgets[layer]
  if object and object.methods[name] then
    error("the stand-in calls " .. layer .. ":" .. name .. " undocumented, and the API snapshot has it")
  end
  if realType(where) ~= "string" then
    error("an undocumented method needs the file of the game's code that uses it")
  end
  implementations[layer] = implementations[layer] or {}
  implementations[layer][name] = { fn = fn }
end

local function defineAll(layers, name, fn)
  for _, layer in ipairs(layers) do
    define(layer, name, fn)
  end
end

---------------------------------------------------------------------------------------------------
-- Objects

local function state(object)
  return rawget(object, "__state")
end
H.state = state

local function run(object, script, ...)
  local handler = state(object).scripts[script]
  if handler then
    return handler(object, ...)
  end
end
H.run = run

local kinds = {} -- [kind] = { methods = {}, scripts = {}, isA = {} }, made at the first use
H.made = 0 -- the number of widgets made so far: each widget keeps its number

local function kindOf(name)
  local kind = kinds[name]
  if kind then
    return kind
  end
  local layers = LAYERS[name]
  kind = { methods = {}, scripts = {}, isA = { [name:lower()] = true } }
  for _, layer in ipairs(layers) do
    local object = snapshot.widgets[layer]
    if not object then
      error("the stand-in names the layer " .. layer .. ", which the API snapshot does not have")
    end
    for method, spec in pairs(object.methods) do
      kind.methods[method] = H.methodStub(name .. ":" .. method, spec)
    end
    if ANCESTORS[layer] then
      kind.isA[ANCESTORS[layer]:lower()] = true
    end
    for _, script in ipairs(LAYER_SCRIPTS[layer] or {}) do
      kind.scripts[script] = true
    end
  end
  -- Hand-written methods, the later layer over the earlier one.
  for _, layer in ipairs(layers) do
    for method, entry in pairs(implementations[layer] or {}) do
      if entry.spec then
        local spec = H.parseSpec(entry.spec)
        local fn = entry.fn
        local label = name .. ":" .. method
        kind.methods[method] = function(self, ...)
          H.checkArguments(label, spec, false, ...)
          local n, out = H.pack(fn(self, ...))
          H.checkResults(label, spec, n, out)
          return unpack(out, 1, n)
        end
      else
        kind.methods[method] = entry.fn
      end
    end
  end
  kind.meta = {
    -- A method of the kind, or a method that a template of the game gives the object (the
    -- methods of the mixins of the template: see mixinMethods).
    __index = function(object, key)
      local method = kind.methods[key]
      if method ~= nil then
        return method
      end
      local extras = rawget(object, "__state").extras
      if extras then
        for index = 1, #extras do
          method = extras[index][key]
          if method ~= nil then
            return method
          end
        end
      end
    end,
  }
  kinds[name] = kind
  return kind
end

local function newObject(kindName, parent, name)
  local kind = kindOf(kindName)
  local object = setmetatable({}, kind.meta)
  -- The state of the stand-in is in one table, so the other fields of the object are the addon's own.
  rawset(object, "__state", {
    kind = kindName, class = kind, parent = parent, name = name, shown = true, scripts = {}, events = {}, points = {},
    width = 0, height = 0, value = 0, min = 0, max = 1, id = 0, alpha = 1, scale = 1, level = 1,
    attributes = {}, children = {}, regions = {}, groups = {}, lines = 0, made = H.made,
  })
  H.made = H.made + 1
  return object
end
H.newObject = newObject

local function isWidget(value)
  return realType(value) == "table" and rawget(value, "__state") ~= nil
end
H.isWidget = isWidget

-- A text that is a number counts as the number: the same rule as for a documented number
-- argument (checkArguments in 01-api.lua).
local function number(value, what)
  if realType(value) == "string" and tonumber(value) then
    return tonumber(value)
  end
  if realType(value) ~= "number" then
    fail(what .. ": a number is needed, got " .. realType(value))
  end
  return value
end

---------------------------------------------------------------------------------------------------
-- Every object

define("SimpleFrameScriptObjectAPI", "GetName", function(self)
  return state(self).name
end)
define("SimpleObjectAPI", "GetParent", function(self)
  return state(self).parent
end)
define("SimpleObjectAPI", "GetDebugName", function(self)
  return state(self).name or state(self).kind
end)
-- An intrinsic frame of the game (ItemButton, EventFrame, DropdownButton) says that it is of
-- the frame type that it is made from: "GetObjectType returns the intrinsic's type, not the
-- intrinsic's name" (https://warcraft.wiki.gg/wiki/Intrinsic_frame). The game's code agrees:
-- Blizzard_Menu/Menu.lua compares the type of a dropdown button with "Button".
local function objectType(kindName)
  local intrinsics = UI_NAMES.intrinsics or {}
  for _ = 1, 8 do
    local base = intrinsics[kindName]
    if not base then
      break
    end
    kindName = base
  end
  return kindName
end
define("SimpleFrameScriptObjectAPI", "GetObjectType", function(self)
  return objectType(state(self).kind)
end)
-- A button is also a "Frame"; the name is not case sensitive (Blizzard_Dispatcher.lua).
define("SimpleFrameScriptObjectAPI", "IsObjectType", function(self, name)
  local s = state(self)
  name = realTostring(name):lower()
  -- The name of an intrinsic frame type is not a widget type.
  if name == s.kind:lower() and objectType(s.kind) ~= s.kind then
    return false
  end
  return s.class.isA[name] == true
end)

---------------------------------------------------------------------------------------------------
-- Scripts

local function checkScript(self, script, what)
  if realType(script) ~= "string" then
    fail(what .. ": the script name is not a text")
  end
  if not state(self).class.scripts[script] then
    fail(what .. ": " .. state(self).kind .. " doesn't have a \"" .. script .. "\" script")
  end
end

local function setScript(self, script, handler)
  checkScript(self, script, "SetScript")
  if handler ~= nil and realType(handler) ~= "function" then
    fail("SetScript: the handler of " .. script .. " is not a function")
  end
  state(self).scripts[script] = handler
end
local function getScript(self, script)
  checkScript(self, script, "GetScript")
  return state(self).scripts[script]
end
local function hasScript(self, script)
  return state(self).class.scripts[script] == true
end
local function hookScript(self, script, handler)
  checkScript(self, script, "HookScript")
  if realType(handler) ~= "function" then
    fail("HookScript: the handler of " .. script .. " is not a function")
  end
  local scripts = state(self).scripts
  local previous = scripts[script]
  scripts[script] = previous and function(...)
    previous(...)
    handler(...)
  end or handler
  return true
end
for _, layer in ipairs({ "SimpleScriptRegionAPI", "SimpleAnimAPI", "SimpleAnimGroupAPI" }) do
  define(layer, "SetScript", setScript)
  define(layer, "GetScript", getScript)
  define(layer, "HasScript", hasScript)
  define(layer, "HookScript", hookScript)
end

---------------------------------------------------------------------------------------------------
-- Shown and hidden

local function isVisible(self)
  local object = self
  while object do
    local s = state(object)
    if not s or not s.shown then
      return false
    end
    object = s.parent
  end
  return true
end

-- The widgets under one that are shown themselves: they become visible or hidden with it.
-- Regions and child frames together, in the order in which they were made.
local function eachShownChild(self, fn)
  local s = state(self)
  local shown = {}
  for _, list in ipairs({ s.regions, s.children }) do
    for _, child in ipairs(list) do
      if state(child).shown then
        shown[#shown + 1] = child
      end
    end
  end
  table.sort(shown, function(a, b)
    return state(a).made < state(b).made
  end)
  for _, child in ipairs(shown) do
    fn(child)
  end
end

-- OnShow runs for the widgets under a frame first, then for the frame, and each handler sees
-- every one of them as visible already. The tests "visible updated on kids before calling any
-- OnShow" and "OnShow order between frame children and regions" of the wowless project run in
-- the game client: https://github.com/wowless/wowless (addon/Wowless/test.lua).
local function fireShown(self)
  eachShownChild(self, fireShown)
  run(self, "OnShow")
end
local function fireHidden(self)
  eachShownChild(self, fireHidden)
  run(self, "OnHide")
end

local function show(self)
  local s = state(self)
  if not s.shown then
    s.shown = true
    if isVisible(self) then
      fireShown(self)
    end
  end
end
local function hide(self)
  local s = state(self)
  if s.shown then
    local wasVisible = isVisible(self)
    s.shown = false
    if wasVisible then
      -- The children were visible until now.
      eachShownChild(self, fireHidden)
      run(self, "OnHide")
    end
  end
end

define("SimpleScriptRegionAPI", "IsShown", function(self)
  return state(self).shown
end)
define("SimpleScriptRegionAPI", "IsVisible", isVisible)
define("SimpleScriptRegionAPI", "Show", show)
define("SimpleScriptRegionAPI", "Hide", hide)
define("SimpleScriptRegionAPI", "SetShown", function(self, shown)
  if shown then
    show(self)
  else
    hide(self)
  end
end)
define("SimpleScriptRegionAPI", "SetParent", function(self, parent)
  if parent ~= nil and not isWidget(parent) then
    fail("SetParent: the parent is not a frame")
  end
  local s = state(self)
  local old = s.parent
  local wasVisible = isVisible(self)
  if old then
    for _, list in ipairs({ state(old).children, state(old).regions }) do
      for index = #list, 1, -1 do
        if list[index] == self then
          table.remove(list, index)
        end
      end
    end
  end
  s.parent = parent
  if parent then
    table.insert(LAYERS[s.kind] and NOT_A_FRAME[s.kind] and state(parent).regions or state(parent).children, self)
  end
  -- Under a hidden parent the widget is not on the screen any more, and the other way round.
  local nowVisible = isVisible(self)
  if wasVisible and not nowVisible then
    fireHidden(self)
  elseif nowVisible and not wasVisible then
    fireShown(self)
  end
end)

---------------------------------------------------------------------------------------------------
-- Size and place

local function sizeChanged(self)
  local s = state(self)
  if s.class.scripts.OnSizeChanged then
    run(self, "OnSizeChanged", s.width, s.height)
  end
end
define("SimpleScriptRegionResizingAPI", "SetSize", function(self, width, height)
  local s = state(self)
  s.width, s.height = number(width, "SetSize"), number(height, "SetSize")
  sizeChanged(self)
end)
define("SimpleScriptRegionResizingAPI", "SetWidth", function(self, width)
  state(self).width = number(width, "SetWidth")
  sizeChanged(self)
end)
define("SimpleScriptRegionResizingAPI", "SetHeight", function(self, height)
  state(self).height = number(height, "SetHeight")
  sizeChanged(self)
end)
define("SimpleScriptRegionAPI", "GetWidth", function(self)
  return state(self).width
end)
define("SimpleScriptRegionAPI", "GetHeight", function(self)
  return state(self).height
end)
define("SimpleScriptRegionAPI", "GetSize", function(self)
  local s = state(self)
  return s.width, s.height
end)

local POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
-- The texts of the game's errors: "Invalid region point nonsense" for the point and "Unknown
-- region point nonsense" for the relative point (wowless, Region > SetPoint > badpoint).
local function pointName(value, what)
  local name = realType(value) == "string" and value:upper()
  if not name or not POINTS[name] then
    fail("SetPoint: " .. (what == "point" and "Invalid" or "Unknown") .. " region point " .. realTostring(value))
  end
  return name
end
-- GetPoint gives the anchors in this order, not in the order of the calls (wowless, Region > GetPoint).
local POINT_ORDER = { TOPLEFT = 1, TOP = 2, TOPRIGHT = 3, LEFT = 4, CENTER = 5, RIGHT = 6, BOTTOMLEFT = 7, BOTTOM = 8, BOTTOMRIGHT = 9 }

-- The forms of the game: (point), (point, x, y), (point, relativeTo), (point, relativeTo, x, y),
-- (point, relativeTo, relativePoint), (point, relativeTo, relativePoint, x, y).
-- relativeTo is a region or the name of one. The second form of four is in the game's own
-- code: Blizzard_AdventureMap/AM_QuestDialog.lua.
-- True if the place of `region` hangs on `target`: through its anchors, one after another.
local function dependsOn(region, target, depth)
  if region == target then
    return true
  end
  if not isWidget(region) or depth > 50 then
    return false
  end
  for _, anchor in ipairs(state(region).points) do
    if anchor[2] ~= nil and dependsOn(anchor[2], target, depth + 1) then
      return true
    end
  end
  return false
end
-- The game refuses an anchor to a region whose own place hangs on this one, with this text
-- (a report of it: https://www.wowace.com/projects/skada/issues/605).
local function checkAnchor(self, relativeTo, what)
  if relativeTo == self then
    fail("Action[" .. what .. "] failed because[Cannot anchor to itself]: attempted from: " .. (state(self).name or "<unnamed>") .. ":" .. what .. ".")
  end
  if relativeTo ~= nil and dependsOn(relativeTo, self, 0) then
    fail("Action[" .. what .. "] failed because[Cannot anchor to a region dependent on it]: attempted from: " .. (state(self).name or "<unnamed>") .. ":" .. what .. ".")
  end
end

define("SimpleScriptRegionResizingAPI", "SetPoint", function(self, point, a, b, c, d)
  point = pointName(point, "point")
  local relativeTo, relativePoint, x, y
  -- Without a region the anchor is to the parent; with nil in the place of the region it is
  -- to the screen, as for SetAllPoints.
  local toParent = true
  if realType(a) == "number" then
    x, y = a, b
  elseif a == nil and b == nil then
    x, y = 0, 0
  else
    toParent = false
    relativeTo = a
    if realType(b) == "number" then
      x, y = b, c
    else
      relativePoint, x, y = b, c, d
    end
  end
  if realType(relativeTo) == "string" then
    local named = _G[relativeTo]
    if not isWidget(named) then
      fail("SetPoint: there is no region with the name " .. relativeTo)
    end
    relativeTo = named
  elseif relativeTo ~= nil and not isWidget(relativeTo) then
    fail("SetPoint: the region to anchor to is not a region")
  end
  if toParent then
    relativeTo = state(self).parent
  end
  checkAnchor(self, relativeTo, "SetPoint")
  relativePoint = relativePoint ~= nil and pointName(relativePoint, "relative point") or point
  x, y = x or 0, y or 0
  if realType(x) ~= "number" or realType(y) ~= "number" then
    fail("SetPoint: an offset is not a number")
  end
  local points = state(self).points
  local entry = { point, relativeTo, relativePoint, x, y }
  for index, existing in ipairs(points) do
    if existing[1] == point then
      points[index] = entry -- the same point again replaces the first
      return
    end
  end
  points[#points + 1] = entry
  table.sort(points, function(a, b)
    return POINT_ORDER[a[1]] < POINT_ORDER[b[1]]
  end)
end)
define("SimpleScriptRegionResizingAPI", "GetPointByName", function(self, point)
  point = pointName(point, "point")
  for _, anchor in ipairs(state(self).points) do
    if anchor[1] == point then
      return unpack(anchor, 1, 5)
    end
  end
end)
define("SimpleScriptRegionResizingAPI", "ClearAllPoints", function(self)
  state(self).points = {}
end)
define("SimpleScriptRegionResizingAPI", "ClearPoint", function(self, point)
  point = pointName(point, "point")
  local points = state(self).points
  for index = #points, 1, -1 do
    if points[index][1] == point then
      table.remove(points, index)
    end
  end
end)
-- The region to fill is a region or the name of one. Without the argument it is the parent;
-- with an explicit nil it is the screen (the game's code has SetAllPoints(nil); the rule is on
-- https://warcraft.wiki.gg/wiki/API_ScriptRegionResizing_SetAllPoints).
define("SimpleScriptRegionResizingAPI", "SetAllPoints", function(self, ...)
  local relativeTo = ...
  if realType(relativeTo) == "string" then
    local named = rawget(_G, relativeTo)
    if not isWidget(named) then
      fail("SetAllPoints: there is no region with the name " .. relativeTo)
    end
    relativeTo = named
  elseif relativeTo ~= nil and not isWidget(relativeTo) then
    fail("SetAllPoints: the region to anchor to is not a region")
  end
  local target = relativeTo
  if select("#", ...) == 0 then
    target = state(self).parent
  end
  checkAnchor(self, target, "SetAllPoints")
  state(self).points = { { "TOPLEFT", target, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0 } }
end)
define("SimpleScriptRegionResizingAPI", "GetPoint", function(self, index)
  local point = state(self).points[index or 1]
  if point then
    return unpack(point, 1, 5)
  end
end)
define("SimpleScriptRegionResizingAPI", "GetNumPoints", function(self)
  return #state(self).points
end)

-- A region with no anchor has no rectangle: the game answers nil.
local function placed(self)
  return #state(self).points > 0
end
define("SimpleScriptRegionAPI", "GetCenter", function(self)
  if placed(self) then
    return 500, 400
  end
end)
for name, value in pairs({ GetLeft = 100, GetRight = 300, GetTop = 500, GetBottom = 300 }) do
  define("SimpleScriptRegionAPI", name, function(self)
    if placed(self) then
      return value
    end
  end)
end

for _, layer in ipairs({ "SimpleFrameAPI", "SimpleRegionAPI" }) do
  define(layer, "GetScale", function(self)
    return state(self).scale
  end)
  define(layer, "SetScale", function(self, scale)
    state(self).scale = number(scale, "SetScale")
  end)
  define(layer, "GetEffectiveScale", function(self)
    local scale, object = 1, self
    while object do
      scale = scale * state(object).scale
      object = state(object).parent
    end
    return scale
  end)
  define(layer, "GetAlpha", function(self)
    return state(self).alpha
  end)
  -- A value outside 0 to 1 is brought into that range, without an error, since patch 12.0.0
  -- (https://warcraft.wiki.gg/wiki/API_Region_SetAlpha). The game's own code still clamps
  -- first: Blizzard_FrameXML/LossOfControlFrame.lua has SetAlpha(Saturate(...)).
  define(layer, "SetAlpha", function(self, alpha)
    if secrets[alpha] == nil then
      alpha = math.max(0, math.min(1, number(alpha, "SetAlpha")))
    end
    state(self).alpha = alpha
  end)
end

---------------------------------------------------------------------------------------------------
-- Frames

local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }

-- The fonts that a font string can inherit, and the events that the game's own code registers
-- and the documentation does not list. Both come from the game's UI files, not from a list
-- written by hand: tools/api/forever-ui.json, built by `cargo dev ui-names`.
local FONTS = UI_NAMES.fonts or {}
local undocumentedEvent = {}
for _, name in ipairs(UI_NAMES.undocumentedEvents or {}) do
  undocumentedEvent[name] = true
end
H.undocumentedEvents = undocumentedEvent
local knownFont = {}

-- The kind of region that a template of the game's XML files is for, or nil.
function H.regionTemplate(name)
  local record = realType(name) == "string" and uiFiles.template and uiFiles.template(name)
  return record and record.kind or nil
end

local function newRegion(kindName, layerArgument)
  return function(self, name, layer, template)
    if name ~= nil and realType(name) ~= "string" then
      fail("Create" .. kindName .. ": the name is not a text")
    end
    if layerArgument and layer ~= nil and not DRAW_LAYERS[realTostring(layer):upper()] then
      fail("Create" .. kindName .. ": unknown draw layer " .. realTostring(layer))
    end
    if kindName == "FontString" and template ~= nil and not knownFont[template] then
      fail("CreateFontString: Couldn't find inherited node \"" .. realTostring(template) .. "\"")
    end
    -- A template of a texture is a virtual texture of the game's XML files
    -- (Blizzard_PetBattleUI: CreateTexture(nil, "ARTWORK", "SharedPetBattleStrengthPetTypeTemplate")).
    if kindName ~= "FontString" and template ~= nil and uiFiles.template and H.regionTemplate(template) ~= kindName then
      fail("Create" .. kindName .. ": Couldn't find inherited node \"" .. realTostring(template) .. "\"")
    end
    local region = newObject(kindName, self, name)
    table.insert(state(self).regions, region)
    if name then
      _G[name] = region
    end
    return region
  end
end
define("SimpleFrameAPI", "CreateTexture", newRegion("Texture", true))
define("SimpleFrameAPI", "CreateFontString", newRegion("FontString", true))
define("SimpleFrameAPI", "CreateMaskTexture", newRegion("MaskTexture", true))
define("SimpleFrameAPI", "CreateLine", newRegion("Line", true))

-- Animations belong to a region, and an animation group is not a region of its parent.
define("SimpleAnimatableObjectAPI", "CreateAnimationGroup", function(self, name)
  local group = newObject("AnimationGroup", self, realType(name) == "string" and name or nil)
  table.insert(state(self).groups, group)
  return group
end)
define("SimpleAnimGroupAPI", "CreateAnimation", function(self, animationType, name)
  local kindName = animationType or "Animation"
  if animationType ~= nil and realType(animationType) ~= "string" then
    fail("CreateAnimation: the animation type is not a text")
  end
  -- A type that the game does not make from Lua gives a plain animation, without an error:
  -- CreateAnimation("TextureCoordTranslation") is of the type "Animation" in the game client
  -- (wowless, TextureCoordTranslation > objecttype: "The XML name doesn't work from Lua").
  local isAnimation = false
  for _, known in ipairs(UI_NAMES.animationTypes or { "Animation", "Alpha", "Rotation", "Scale", "Translation", "Path" }) do
    isAnimation = isAnimation or known == kindName
  end
  if not isAnimation or not LAYERS[kindName] or kindName == "TextureCoordTranslation" then
    kindName = "Animation"
  end
  return newObject(kindName, self, realType(name) == "string" and name or nil)
end)
-- An animation group that plays: Play starts it and runs OnPlay. The stand-in has no clock
-- for animations; the driver ends each playing group with H.finishAnimation, which runs
-- OnLoop for a group that repeats, then OnFinished, as the game does at the end.
define("SimpleAnimGroupAPI", "Play", function(self)
  local s = state(self)
  if not s.playing then
    s.playing = true
    H.playing = H.playing or {}
    H.playing[#H.playing + 1] = self
    run(self, "OnPlay")
  end
end)
define("SimpleAnimGroupAPI", "Stop", function(self)
  local s = state(self)
  if s.playing then
    s.playing = false
    run(self, "OnStop", true)
  end
end)
define("SimpleAnimGroupAPI", "IsPlaying", function(self)
  return state(self).playing == true
end)
define("SimpleAnimGroupAPI", "SetLooping", function(self, looping)
  state(self).looping = looping
end)
define("SimpleAnimGroupAPI", "GetLooping", function(self)
  return state(self).looping or "NONE"
end)
function H.finishAnimation(group)
  local s = state(group)
  if not s.playing then
    return
  end
  if s.looping and s.looping ~= "NONE" then
    run(group, "OnLoop", "FORWARD")
    return
  end
  s.playing = false
  run(group, "OnFinished", false)
end

define("SimpleFrameAPI", "GetChildren", function(self)
  return unpack(state(self).children)
end)
define("SimpleFrameAPI", "GetRegions", function(self)
  return unpack(state(self).regions)
end)
define("SimpleFrameAPI", "GetNumChildren", function(self)
  return #state(self).children
end)
define("SimpleFrameAPI", "GetNumRegions", function(self)
  return #state(self).regions
end)

define("SimpleFrameAPI", "RegisterEvent", function(self, event)
  if not H.knownEvents[event] and not undocumentedEvent[event] then
    fail("Frame:RegisterEvent(): attempt to register unknown event \"" .. realTostring(event) .. "\"")
  end
  state(self).events[event] = true
  return true
end)
define("SimpleFrameAPI", "RegisterUnitEvent", function(self, event, unit)
  if not H.knownEvents[event] and not undocumentedEvent[event] then
    fail("Frame:RegisterUnitEvent(): attempt to register unknown event \"" .. realTostring(event) .. "\"")
  end
  if realType(unit) ~= "string" then
    fail("Frame:RegisterUnitEvent(): a unit is needed")
  end
  state(self).events[event] = true
  return true
end)
define("SimpleFrameAPI", "UnregisterEvent", function(self, event)
  if not H.knownEvents[event] and not undocumentedEvent[event] then
    fail("Frame:UnregisterEvent(): unknown event \"" .. realTostring(event) .. "\"")
  end
  state(self).events[event] = nil
  return true
end)
define("SimpleFrameAPI", "UnregisterAllEvents", function(self)
  state(self).events = {}
end)
define("SimpleFrameAPI", "IsEventRegistered", function(self, event)
  return state(self).events[event] == true
end)

define("SimpleFrameAPI", "GetID", function(self)
  return state(self).id
end)
define("SimpleFrameAPI", "SetID", function(self, id)
  state(self).id = number(plain(id), "SetID")
end)
define("SimpleFrameAPI", "GetFrameLevel", function(self)
  return state(self).level
end)
define("SimpleFrameAPI", "SetFrameLevel", function(self, level)
  state(self).level = number(level, "SetFrameLevel")
end)
-- The list FRAMESTRATA of UI.xsd. WORLD is the strata of the world frame and cannot be given
-- to a frame (https://warcraft.wiki.gg/wiki/Frame_Strata); no file of the game gives PARENT.
local STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true,
  FULLSCREEN_DIALOG = true, TOOLTIP = true, BLIZZARD = true,
}
define("SimpleFrameAPI", "SetFrameStrata", function(self, strata)
  if realType(strata) ~= "string" or not STRATA[strata:upper()] then
    fail("SetFrameStrata: unknown strata " .. realTostring(strata))
  end
  state(self).strata = strata:upper()
end)
define("SimpleFrameAPI", "GetFrameStrata", function(self)
  return state(self).strata or "MEDIUM"
end)
define("SimpleFrameAPI", "SetMovable", function(self, movable)
  state(self).movable = movable and true or false
end)
define("SimpleFrameAPI", "IsMovable", function(self)
  return state(self).movable or false
end)
define("SimpleFrameAPI", "SetAttribute", function(self, name, value)
  state(self).attributes[name] = value
  run(self, "OnAttributeChanged", name, value)
end)
define("SimpleFrameAPI", "GetAttribute", function(self, name)
  return state(self).attributes[name]
end)
define("SimpleScriptRegionAPI", "IsMouseOver", function()
  return false
end)
define("SimpleScriptRegionAPI", "EnableMouse", function(self, enable)
  state(self).mouse = enable and true or false
end)
define("SimpleScriptRegionAPI", "IsMouseEnabled", function(self)
  return state(self).mouse or false
end)

local CLICKS = {
  AnyUp = true, AnyDown = true, LeftButtonUp = true, LeftButtonDown = true, RightButtonUp = true,
  RightButtonDown = true, MiddleButtonUp = true, MiddleButtonDown = true, Button4Up = true, Button4Down = true,
  Button5Up = true, Button5Down = true,
}
local DRAGS = { LeftButton = true, RightButton = true, MiddleButton = true, Button4 = true, Button5 = true }
define("SimpleButtonAPI", "RegisterForClicks", function(_, ...)
  for i = 1, select("#", ...) do
    if not CLICKS[(select(i, ...))] then
      fail("RegisterForClicks: unknown click type " .. realTostring((select(i, ...))))
    end
  end
end)
define("SimpleFrameAPI", "RegisterForDrag", function(_, ...)
  for i = 1, select("#", ...) do
    if not DRAGS[(select(i, ...))] then
      fail("RegisterForDrag: unknown button " .. realTostring((select(i, ...))))
    end
  end
end)

---------------------------------------------------------------------------------------------------
-- Text. A secret value can be shown where the documentation opens the method to addon code.

local function checkText(text, what)
  local kind = realType(plain(text))
  if text ~= nil and kind ~= "string" and kind ~= "number" then
    fail(what .. ": a text is needed, got " .. kind)
  end
end
local function setText(self, text)
  checkText(text, "SetText")
  state(self).text = text
end
local function setFormattedText(self, pattern, ...)
  local ok, text = pcall(string.format, pattern, ...)
  if not ok then
    fail("SetFormattedText: " .. realTostring(text):gsub("^.-:%d+: ", ""))
  end
  state(self).text = text
end
local function getText(self)
  return state(self).text
end
for _, layer in ipairs({ "SimpleFontStringAPI", "SimpleButtonAPI", "SimpleEditBoxAPI" }) do
  define(layer, "SetText", setText)
  define(layer, "GetText", getText)
end
define("SimpleFontStringAPI", "SetFormattedText", setFormattedText)
define("SimpleButtonAPI", "SetFormattedText", setFormattedText)
define("FrameAPITooltip", "SetText", function(self, text)
  checkText(text, "SetText")
  local s = state(self)
  s.text, s.lines = text, 1
end)
-- The text of a button is the text of its font string.
-- A button has no font string until it gets a text: GetFontString and GetText give nil
-- before, and SetText makes the font string (wowless, "button text", a test that runs in the
-- game client: https://github.com/wowless/wowless, addon/Wowless/test.lua).
define("SimpleButtonAPI", "SetText", function(self, text)
  checkText(text, "SetText")
  local s = state(self)
  s.text = text
  if not s.fontString and text ~= nil then
    s.fontString = newObject("FontString", self)
  end
  if s.fontString then
    state(s.fontString).text = text
  end
end)
define("SimpleButtonAPI", "GetFontString", function(self)
  return state(self).fontString
end)
define("SimpleButtonAPI", "SetFontString", function(self, fontString)
  if not (isWidget(fontString) and state(fontString).kind == "FontString") then
    fail("SetFontString: a font string is needed")
  end
  state(self).fontString = fontString
  state(self).text = state(fontString).text
end)
define("SimpleEditBoxAPI", "SetText", function(self, text)
  checkText(text, "SetText")
  state(self).text = text == nil and "" or text
  run(self, "OnTextChanged", false)
end)
define("SimpleEditBoxAPI", "GetText", function(self)
  return state(self).text or ""
end)
define("SimpleEditBoxAPI", "SetFocus", function(self)
  if not state(self).focus then
    state(self).focus = true
    run(self, "OnEditFocusGained")
  end
end)
define("SimpleEditBoxAPI", "ClearFocus", function(self)
  if state(self).focus then
    state(self).focus = false
    run(self, "OnEditFocusLost")
  end
end)
define("SimpleEditBoxAPI", "HasFocus", function(self)
  return state(self).focus or false
end)
define("SimpleFontStringAPI", "GetStringWidth", function(self)
  local text = plain(state(self).text)
  return text and #realTostring(text) * 6 or 0
end)
define("SimpleFontStringAPI", "GetUnboundedStringWidth", function(self)
  local text = plain(state(self).text)
  return text and #realTostring(text) * 6 or 0
end)
define("SimpleFontStringAPI", "GetStringHeight", function()
  return 12
end)
define("SimpleFontStringAPI", "GetTextScale", function()
  return 1
end)
local JUSTIFY_H = { LEFT = true, CENTER = true, RIGHT = true }
local JUSTIFY_V = { TOP = true, MIDDLE = true, BOTTOM = true }
define("SimpleFontStringAPI", "SetJustifyH", function(self, value)
  if realType(value) ~= "string" or not JUSTIFY_H[value:upper()] then
    fail("SetJustifyH: unknown value " .. realTostring(value))
  end
  state(self).justifyH = value:upper()
end)
define("SimpleFontStringAPI", "GetJustifyH", function(self)
  return state(self).justifyH or "CENTER"
end)
define("SimpleFontStringAPI", "SetJustifyV", function(self, value)
  if realType(value) ~= "string" or not JUSTIFY_V[value:upper()] then
    fail("SetJustifyV: unknown value " .. realTostring(value))
  end
  state(self).justifyV = value:upper()
end)
define("SimpleFontStringAPI", "GetJustifyV", function(self)
  return state(self).justifyV or "MIDDLE"
end)

for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
  define("SimpleButtonAPI", getter, function(self)
    local s = state(self)
    s[getter] = s[getter] or newObject("Texture", self)
    return s[getter]
  end)
end
define("SimpleStatusBarAPI", "GetStatusBarTexture", function(self)
  local s = state(self)
  s.barTexture = s.barTexture or newObject("Texture", self)
  return s.barTexture
end)
-- A slider has no thumb texture until SetThumbTexture, which takes a texture or a picture; a
-- picture goes into the thumb texture that is there (wowless, Slider, a test that runs in the
-- game client).
define("SimpleSliderAPI", "GetThumbTexture", function(self)
  return state(self).thumb
end)
define("SimpleSliderAPI", "SetThumbTexture", function(self, asset)
  local s = state(self)
  if isWidget(asset) then
    s.thumb = asset
  elseif asset ~= nil then
    s.thumb = s.thumb or newObject("Texture", self)
    s.thumb:SetTexture(asset)
  end
end)

---------------------------------------------------------------------------------------------------
-- Buttons, check boxes, sliders and status bars

define("SimpleCheckboxAPI", "SetChecked", function(self, checked)
  state(self).checked = checked and true or false
end)
define("SimpleCheckboxAPI", "GetChecked", function(self)
  return state(self).checked or false
end)
local function setEnabled(self, enabled)
  local s = state(self)
  local was = not s.disabled
  s.disabled = not enabled
  if was ~= (enabled and true or false) then
    run(self, enabled and "OnEnable" or "OnDisable")
  end
end
define("SimpleButtonAPI", "SetEnabled", setEnabled)
define("SimpleButtonAPI", "Enable", function(self)
  setEnabled(self, true)
end)
define("SimpleButtonAPI", "Disable", function(self)
  setEnabled(self, false)
end)
define("SimpleButtonAPI", "IsEnabled", function(self)
  return not state(self).disabled
end)
-- A click as the game does it: nothing on a disabled button, a check box changes first.
local function click(self, button, isDown)
  local s = state(self)
  if s.disabled then
    return
  end
  button = button or "LeftButton"
  if s.class.methods.SetChecked then
    s.checked = not s.checked
  end
  run(self, "PreClick", button, isDown or false)
  run(self, "OnClick", button, isDown or false)
  run(self, "PostClick", button, isDown or false)
end
define("SimpleButtonAPI", "Click", click)
H.click = click

local function setMinMax(self, low, high)
  local s = state(self)
  if secrets[low] == nil and secrets[high] == nil then
    number(low, "SetMinMaxValues")
    number(high, "SetMinMaxValues")
  end
  s.min, s.max = low, high
  run(self, "OnMinMaxChanged", low, high)
end
define("SimpleSliderAPI", "SetMinMaxValues", setMinMax)
define("SimpleStatusBarAPI", "SetMinMaxValues", setMinMax)
local function getMinMax(self)
  local s = state(self)
  return s.min, s.max
end
define("SimpleSliderAPI", "GetMinMaxValues", getMinMax)
define("SimpleStatusBarAPI", "GetMinMaxValues", getMinMax)
define("SimpleSliderAPI", "SetValueStep", function(self, step)
  state(self).step = number(step, "SetValueStep")
end)
define("SimpleSliderAPI", "GetValueStep", function(self)
  return state(self).step or 0
end)
define("SimpleSliderAPI", "SetObeyStepOnDrag", function(self, obey)
  state(self).obeyStep = obey and true or false
end)
-- The value stays in the range of the slider.
local function setSliderValue(self, value, userInput)
  local s = state(self)
  value = number(value, "SetValue")
  -- A drag by the player goes in steps when the slider obeys its step on a drag
  -- (SetObeyStepOnDrag); SetValue from code does not.
  if userInput and s.obeyStep and s.step and s.step > 0 then
    value = s.min + math.floor((value - s.min) / s.step + 0.5) * s.step
  end
  value = math.max(s.min, math.min(s.max, value))
  if s.value ~= value then
    s.value = value
    run(self, "OnValueChanged", value, userInput or false)
  end
end
define("SimpleSliderAPI", "SetValue", function(self, value)
  setSliderValue(self, value, false)
end)
H.setSliderValue = setSliderValue
define("SimpleSliderAPI", "GetValue", function(self)
  return state(self).value
end)
define("SimpleStatusBarAPI", "SetValue", function(self, value)
  local s = state(self)
  if secrets[value] == nil then
    number(value, "SetValue")
  end
  local changed = secrets[value] ~= nil or secrets[s.value] ~= nil or s.value ~= value
  s.value = value
  if changed then
    run(self, "OnValueChanged", value)
  end
end)
define("SimpleStatusBarAPI", "GetValue", function(self)
  return state(self).value
end)

---------------------------------------------------------------------------------------------------
-- Tooltips
--
-- The documentation of the tooltip has only its newest methods. The older ones below are in the
-- game's own UI code of this client, on a tooltip.

local GAME_TOOLTIP = "Blizzard_GameTooltip/Mainline/GameTooltip.lua"
-- The anchors on https://warcraft.wiki.gg/wiki/API_GameTooltip_SetOwner. Each one is also in
-- the game's own Lua code.
local ANCHORS = {
  ANCHOR_TOP = true, ANCHOR_RIGHT = true, ANCHOR_BOTTOM = true, ANCHOR_LEFT = true, ANCHOR_TOPRIGHT = true,
  ANCHOR_BOTTOMRIGHT = true, ANCHOR_TOPLEFT = true, ANCHOR_BOTTOMLEFT = true, ANCHOR_CURSOR = true,
  ANCHOR_CURSOR_RIGHT = true, ANCHOR_PRESERVE = true, ANCHOR_NONE = true,
}
-- And each anchor that the game's own Lua code names (ANCHOR_CENTER is one).
for _, anchor in ipairs(UI_NAMES.tooltipAnchors or {}) do
  ANCHORS[anchor] = true
end
undocumented("FrameAPITooltip", "SetOwner", GAME_TOOLTIP, function(self, owner, anchor)
  if not isWidget(owner) then
    fail("SetOwner: the owner is not a region")
  end
  -- Without an anchor, and with a text that is not an anchor, the game takes ANCHOR_LEFT and
  -- gives no error: the tests GameTooltip > SetOwner > OneArg and InvalidAnchorType of the
  -- wowless project run in the game client (https://github.com/wowless/wowless,
  -- addon/Wowless/uiobjects.lua).
  local s = state(self)
  s.anchor = ANCHORS[anchor] and anchor or "ANCHOR_LEFT"
  s.owner, s.lines, s.text = owner, 0, nil
  -- SetOwner clears and hides the tooltip. It shows again when it gets an item or a spell, or
  -- with Show() after AddLine: an addon that adds lines and forgets Show() has no tooltip.
  hide(self)
end)
undocumented("FrameAPITooltip", "GetOwner", "Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua", function(self)
  return state(self).owner
end)
undocumented("FrameAPITooltip", "GetAnchorType", "Blizzard_SharedXMLGame/Tooltip/TooltipComparisonManager.lua", function(self)
  return state(self).anchor or "ANCHOR_LEFT"
end)
undocumented("FrameAPITooltip", "IsOwned", "Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua", function(self, owner)
  return state(self).owner == owner
end)
local function addLine(self, text, what)
  local kind = realType(plain(text))
  if text ~= nil and kind ~= "string" and kind ~= "number" then
    fail(what .. ": a text is needed, got " .. kind)
  end
  state(self).lines = state(self).lines + 1
end
undocumented("FrameAPITooltip", "AddLine", GAME_TOOLTIP, function(self, text)
  addLine(self, text, "AddLine")
end)
undocumented("FrameAPITooltip", "AddDoubleLine", "Blizzard_SharedXML/SharedTooltipTemplates.lua", function(self, left, right)
  addLine(self, left, "AddDoubleLine")
  local kind = realType(plain(right))
  if right ~= nil and kind ~= "string" and kind ~= "number" then
    fail("AddDoubleLine: a text is needed, got " .. kind)
  end
end)
undocumented("FrameAPITooltip", "NumLines", "Blizzard_SharedXML/SharedTooltipTemplates.lua", function(self)
  return state(self).lines
end)
undocumented("FrameAPITooltip", "ClearLines", "Blizzard_SharedXML/PropertyBindingMixin.lua", function(self)
  state(self).lines = 0
end)
-- The item that a tooltip shows: H.world.tooltipItem, set by the driver.
local function showItem(self, itemID)
  state(self).lines = 1
  state(self).itemID = itemID
  show(self)
end
undocumented("FrameAPITooltip", "SetHyperlink", GAME_TOOLTIP, function(self, link)
  if realType(link) ~= "string" then
    fail("SetHyperlink: a text is needed")
  end
  showItem(self, tonumber(link:match("item:(%d+)")))
end)
undocumented("FrameAPITooltip", "SetItemByID", GAME_TOOLTIP, function(self, itemID)
  showItem(self, number(itemID, "SetItemByID"))
end)
undocumented("FrameAPITooltip", "SetBagItem", "Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua", function(self, bag, slot)
  number(bag, "SetBagItem")
  number(slot, "SetBagItem")
  showItem(self, nil)
end)
undocumented("FrameAPITooltip", "SetSpellByID", "Blizzard_DamageMeter/DamageMeterEntry.lua", function(self, spellID)
  number(spellID, "SetSpellByID")
  state(self).lines = 1
  show(self)
end)
-- More of the older methods that fill a tooltip. Each shows the tooltip with its content.
local function filled(self)
  state(self).lines = 1
  state(self).itemID = nil
  show(self)
  return true
end
undocumented("FrameAPITooltip", "SetInventoryItem", "Blizzard_AzeriteRespecUI/Blizzard_AzeriteRespecUI.lua", function(self, unit, slot)
  if realType(unit) ~= "string" then
    fail("SetInventoryItem: a unit is needed")
  end
  number(slot, "SetInventoryItem")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetUnit", "Blizzard_UnitFrame/Mainline/UnitFrame.lua", function(self, unit)
  if realType(unit) ~= "string" then
    fail("SetUnit: a unit is needed")
  end
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetCurrencyByID", "Blizzard_CovenantSanctum/Blizzard_CovenantSanctumUpgrades.lua", function(self, currencyID)
  number(currencyID, "SetCurrencyByID")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetAction", "Blizzard_ActionBar/Shared/ActionButton.lua", function(self, action)
  number(action, "SetAction")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetMerchantItem", "Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua", function(self, index)
  number(index, "SetMerchantItem")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetQuestItem", "Blizzard_UIPanels_Game/Mainline/QuestInfo.lua", function(self, kind, index)
  if realType(kind) ~= "string" then
    fail("SetQuestItem: the kind of reward is needed")
  end
  number(index, "SetQuestItem")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetLootItem", "Blizzard_UIPanels_Game/Mainline/LootFrame.lua", function(self, slot)
  number(slot, "SetLootItem")
  return filled(self)
end)
undocumented("FrameAPITooltip", "SetUnitAura", "Blizzard_BuffFrame/BuffFrame.lua", function(self, unit, index)
  if realType(unit) ~= "string" then
    fail("SetUnitAura: a unit is needed")
  end
  number(index, "SetUnitAura")
  return filled(self)
end)
-- A picture beside the last line.
undocumented("FrameAPITooltip", "AddTexture", "Blizzard_CooldownViewer/CooldownViewerItemData.lua", function(_, texture)
  local kind = realType(texture)
  if kind ~= "string" and kind ~= "number" then
    fail("AddTexture: a file name or the number of a file is needed, got " .. kind)
  end
end)

-- The atlas of a texture: a named part of a picture file. SetTexture takes it away.
define("SimpleTextureBaseAPI", "SetAtlas", function(self, atlas)
  state(self).atlas = atlas
end)
define("SimpleTextureBaseAPI", "GetAtlas", function(self)
  return state(self).atlas or ""
end)

-- A font string without a text gives nil, although the documentation has a text.
H.allowNil("FontString:GetText", "The game gives nil for a font string without a text: Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua reads self.description:GetText() or \"\".")

-- The same for every kind of widget that has the method through one layer.
local function allowNilFor(layer, method, reason)
  for kindName, layers in pairs(LAYERS) do
    for _, name in ipairs(layers) do
      if name == layer then
        H.allowNil(kindName .. ":" .. method, reason)
      end
    end
  end
end
allowNilFor("SimpleFrameScriptObjectAPI", "GetName", "A widget made without a name has none: Blizzard_GarrisonUI/Mainline/Blizzard_AdventuresCombatLog.lua has `return frame and frame:GetName() or \"\"`.")
allowNilFor("SimpleObjectAPI", "GetParent", "A frame at the top has no parent: Blizzard_DebugTools/Blizzard_DebugTools.lua has `self:GetParent() or UIParent`.")
for _, layer in ipairs({ "SimpleScriptRegionAPI", "SimpleAnimAPI", "SimpleAnimGroupAPI" }) do
  allowNilFor(layer, "GetScript", "A script that nobody set is nil: Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua has `searchBox:GetScript(\"OnUpdate\") == nil`.")
end
allowNilFor("SimpleScriptRegionResizingAPI", "GetPoint", "An anchor to the screen has no region: Blizzard_EditMode/Shared/EditModeManager.lua has `if not relativeTo then` after GetPoint(1).")
allowNilFor("SimpleButtonAPI", "GetText", "The text of a button is the text of its font string, which is nil without a text (FontString:GetText above).")
allowNilFor("SimpleScriptRegionResizingAPI", "GetPointByName", "An anchor to the screen has no region, as for GetPoint; a point that is not set gives nothing (wowless, Region > GetPointByName, a test that runs in the game client).")
allowNilFor("SimpleButtonAPI", "GetFontString", "A button without a text has no font string (wowless, button text, a test that runs in the game client: addon/Wowless/test.lua).")
allowNilFor("SimpleSliderAPI", "GetThumbTexture", "A slider has no thumb texture until SetThumbTexture (wowless, Slider, a test that runs in the game client: addon/Wowless/uiobjects.lua).")

-- The part of the picture that a texture shows. SetTexCoord takes (left, right, top, bottom) or
-- the four corners; GetTexCoord gives the four corners: upper left, lower left, upper right,
-- lower right, x and y of each (Blizzard_SharedXMLBase/TextureUtil.lua and
-- Blizzard_UnitFrame/Mainline/UnitPowerBarAlt.lua read them in this order).
define("SimpleTextureBaseAPI", "SetTexCoord", function(self, a, b, c, d, e, f, g, h)
  local corners
  if e ~= nil then
    corners = { a, b, c, d, e, f, g, h }
  else
    corners = { a, c, a, d, b, c, b, d }
  end
  for index = 1, 8 do
    corners[index] = number(corners[index], "SetTexCoord")
  end
  state(self).texCoord = corners
end)
define("SimpleTextureBaseAPI", "GetTexCoord", function(self)
  return unpack(state(self).texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }, 1, 8)
end)

-- The draw layer of a region, one of the layers of UI.xsd, and its place in that layer.
define("SimpleRegionAPI", "SetDrawLayer", function(self, layer, sublevel)
  if realType(layer) ~= "string" or not DRAW_LAYERS[layer:upper()] then
    fail("SetDrawLayer: unknown draw layer " .. realTostring(layer))
  end
  local s = state(self)
  s.drawLayer, s.sublevel = layer:upper(), sublevel ~= nil and number(sublevel, "SetDrawLayer") or 0
end)
define("SimpleRegionAPI", "GetDrawLayer", function(self)
  local s = state(self)
  return s.drawLayer or "ARTWORK", s.sublevel or 0
end)

-- The colour of a region. Its alpha part is the alpha of the region: after
-- SetVertexColor(0.2, 0.4, 0.6, 0.8), GetAlpha gives 0.8 (wowless, Texture > color texture,
-- vertex color, and gradient).
define("SimpleRegionAPI", "SetVertexColor", function(self, r, g, b, a)
  local s = state(self)
  s.vertexColor = { number(r, "SetVertexColor"), number(g, "SetVertexColor"), number(b, "SetVertexColor") }
  if a ~= nil then
    s.alpha = math.max(0, math.min(1, number(a, "SetVertexColor")))
  end
end)
define("SimpleRegionAPI", "GetVertexColor", function(self)
  local s = state(self)
  local color = s.vertexColor or { 1, 1, 1 }
  return color[1], color[2], color[3], plain(s.alpha)
end)

-- The state of a button: NORMAL, PUSHED, or DISABLED for a disabled button. Another text
-- fails (wowless, "button states").
define("SimpleButtonAPI", "SetButtonState", function(self, buttonState)
  if buttonState ~= "NORMAL" and buttonState ~= "PUSHED" and buttonState ~= "DISABLED" then
    fail("SetButtonState: unknown state " .. realTostring(buttonState))
  end
  state(self).buttonState = buttonState
end)
define("SimpleButtonAPI", "GetButtonState", function(self)
  local s = state(self)
  if s.disabled then
    return "DISABLED"
  end
  return s.buttonState == "PUSHED" and "PUSHED" or "NORMAL"
end)

-- A status bar without a bar texture has the colour 1, 1, 1, 1: the colour belongs to the
-- texture (wowless, StatusBar).
define("SimpleStatusBarAPI", "SetStatusBarColor", function(self, r, g, b, a)
  local s = state(self)
  if s.barTexture then
    s.barColor = { number(r, "SetStatusBarColor"), number(g, "SetStatusBarColor"), number(b, "SetStatusBarColor"), a ~= nil and number(a, "SetStatusBarColor") or 1 }
  end
end)
define("SimpleStatusBarAPI", "SetStatusBarTexture", function(self, asset)
  local s = state(self)
  s.barColor = nil
  if asset == nil then
    s.barTexture = nil
  elseif isWidget(asset) then
    s.barTexture = asset
  else
    s.barTexture = s.barTexture or newObject("Texture", self)
    s.barTexture:SetTexture(asset)
  end
  return true
end)
define("SimpleStatusBarAPI", "GetStatusBarColor", function(self)
  local color = state(self).barColor or { 1, 1, 1, 1 }
  return color[1], color[2], color[3], color[4]
end)

-- A value that must be one of a list of UI.xsd: the blend mode of a texture (ALPHAMODE), the
-- direction of a slider or a status bar (ORIENTATION). The value is kept for the getter.
local function listed(layer, setter, getter, enumeration, default)
  local allowed = {}
  for _, value in ipairs((UI_NAMES.enumerations or {})[enumeration] or {}) do
    allowed[value] = true
  end
  define(layer, setter, function(self, value)
    if next(allowed) and not (realType(value) == "string" and allowed[value:upper()]) then
      fail(setter .. ": unknown value " .. realTostring(value))
    end
    state(self)["listed:" .. setter] = realType(value) == "string" and value:upper() or value
  end)
  define(layer, getter, function(self)
    return state(self)["listed:" .. setter] or default
  end)
end
listed("SimpleTextureBaseAPI", "SetBlendMode", "GetBlendMode", "ALPHAMODE", "BLEND")
listed("SimpleSliderAPI", "SetOrientation", "GetOrientation", "ORIENTATION", "VERTICAL")
listed("SimpleStatusBarAPI", "SetOrientation", "GetOrientation", "ORIENTATION", "HORIZONTAL")

-- The offset of one corner of a texture, by the number of the corner.
define("SimpleTextureBaseAPI", "SetVertexOffset", function(self, index, x, y)
  local s = state(self)
  s.vertexOffsets = s.vertexOffsets or {}
  s.vertexOffsets[number(index, "SetVertexOffset")] = { number(x, "SetVertexOffset"), number(y, "SetVertexOffset") }
end)
define("SimpleTextureBaseAPI", "GetVertexOffset", function(self, index)
  local kept = (state(self).vertexOffsets or {})[number(index, "GetVertexOffset")]
  if kept then
    return kept[1], kept[2]
  end
  return 0, 0
end)

-- A font by its name or as an object: the game's code gives a name
-- (Blizzard_GuildControlUI/Localization.lua: SetFontObject("AchievementDescriptionFont")).
-- The getter gives the font object.
local function fontObject(value, what)
  if realType(value) == "string" then
    local font = rawget(_G, value)
    if not (isWidget(font) and state(font).kind == "Font") then
      fail(what .. ": there is no font with the name " .. value)
    end
    return font
  end
  return value
end
local function fontPair(layer, setter, getter)
  local spec = H.parseSpec(snapshot.widgets[layer].methods[getter])
  define(layer, setter, function(self, font)
    -- Without a font the game refuses (wowless, EditBox > fontobject: SetFontObject(nil) fails).
    if font == nil then
      fail(setter .. ": a font is needed")
    end
    state(self)["font:" .. setter] = fontObject(font, setter)
  end)
  define(layer, getter, function(self)
    local font = state(self)["font:" .. setter]
    if font == nil then
      return H.defaultOf(spec.returns[1], 0)
    end
    return font
  end)
end
for _, layer in ipairs({ "SimpleFontStringAPI", "SimpleEditBoxAPI", "SimpleMessageFrameAPI" }) do
  fontPair(layer, "SetFontObject", "GetFontObject")
end
for _, which in ipairs({ "Normal", "Highlight", "Disabled" }) do
  fontPair("SimpleButtonAPI", "Set" .. which .. "FontObject", "Get" .. which .. "FontObject")
end

-- The number of an edit box is its text: SetNumber changes the text, and the box tells its
-- OnTextChanged script (NumericInputBoxMixin in Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.lua
-- answers OnTextChanged with GetNumber after its own SetNumber).
define("SimpleEditBoxAPI", "SetNumber", function(self, value)
  state(self).text = realTostring(number(value, "SetNumber"))
  run(self, "OnTextChanged", false)
end)
define("SimpleEditBoxAPI", "GetNumber", function(self)
  return tonumber(plain(state(self).text)) or 0
end)
define("SimpleEditBoxAPI", "Insert", function(self, text)
  checkText(text, "Insert")
  state(self).text = realTostring(plain(state(self).text) or "") .. realTostring(plain(text))
  run(self, "OnTextChanged", false)
end)

---------------------------------------------------------------------------------------------------
-- Pairs of a setter and a getter that keep the value
--
-- For a documented pair SetX and GetX that no hand-written method covers, the getter answers
-- what the setter got. Only for a pair of the same shape: the getter takes no argument, and
-- each of its results has the kind of the setter's argument at the same place. So
-- SetCheckedTexture(asset) and GetCheckedTexture(), which gives a texture object, are not a
-- pair, and GetVertexOffset(index) is not the answer to SetVertexOffset(index, x, y).

local function sameShape(setSpec, getSpec)
  if #getSpec.arguments > 0 or #getSpec.returns == 0 then
    return false
  end
  for index, result in ipairs(getSpec.returns) do
    local argument = setSpec.arguments[index]
    if not argument or argument.kind ~= result.kind then
      return false
    end
  end
  return true
end

for layerName, object in pairs(snapshot.widgets) do
  for method in pairs(object.methods) do
    local property = method:match("^Set(%u%w*)$")
    local getter = property and ("Get" .. property)
    local written = implementations[layerName] or {}
    local free = getter and object.methods[getter] and not written[method] and not written[getter]
    local getSpec = free and H.parseSpec(object.methods[getter])
    local setSpec = free and H.parseSpec(object.methods[method])
    if free and not sameShape(setSpec, getSpec) then
      -- A getter for a texture of the widget gives a texture object, whatever the setter got.
      if #getSpec.arguments == 0 and #getSpec.returns == 1 and getSpec.returns[1].kind == "o" and property:find("Texture$") then
        local key = "texture:" .. property
        define(layerName, getter, function(self)
          local s = state(self)
          if not s[key] then
            s[key] = newObject("Texture", self)
          end
          return s[key]
        end)
      end
    elseif free then
      local key = "kept:" .. property
      define(layerName, method, function(self, ...)
        state(self)[key] = H.pack(...)
        state(self)[key .. ":values"] = { ... }
        -- What the setter itself returns: for most of them a flag that it worked.
        local out, n = {}, 0
        for _, entry in ipairs(setSpec.returns) do
          n = n + 1
          out[n] = entry.kind == "b" and true or H.defaultOf(entry, 0)
        end
        return unpack(out, 1, n)
      end)
      define(layerName, getter, function(self)
        local s = state(self)
        if s[key] then
          -- A result that the setter did not get has its default: 1 for a part of a colour
          -- (the alpha of SetTextColor(r, g, b)), else the default of the kind.
          local values, n = s[key .. ":values"], math.max(s[key], #getSpec.returns)
          local out = {}
          for index = 1, n do
            out[index] = values[index]
            if out[index] == nil and getSpec.returns[index] and not getSpec.returns[index].optional then
              out[index] = property:find("Color$") and 1 or H.defaultOf(getSpec.returns[index], 0)
            end
          end
          return unpack(out, 1, n)
        end
        local out, n = {}, 0
        for _, entry in ipairs(getSpec.returns) do
          n = n + 1
          out[n] = H.defaultOf(entry, 0)
        end
        return unpack(out, 1, n)
      end)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Templates
--
-- What a template of the game gives a frame: child keys, methods, key values and scripts. A
-- template that the game's XML files do not have fails, the same as in the game.

-- The record of a template of the game, from the game's XML files (tools/api/forever-ui.json):
-- { kind, inherits = { name }, mixin = { name }, children = { { kind, key, array, name, part,
-- inherits, mixin, children, values } }, values = { key = { type, value } }, scripts = { name } }.
local templateRecords, mixinRecords = {}, {}
local function gameTemplate(name)
  local record = templateRecords[name]
  if record == nil then
    record = uiFiles.template and realType(name) == "string" and uiFiles.template(name) or false
    templateRecords[name] = record
  end
  return record or nil
end
local function gameMixin(name)
  local record = mixinRecords[name]
  if record == nil then
    record = uiFiles.mixin and uiFiles.mixin(name) or false
    mixinRecords[name] = record
  end
  return record or nil
end

-- A method that a mixin of the game gives a frame, and that nobody wrote for the stand-in. The
-- name is there, as in the game; a call fails, because a method that does nothing would let
-- the addon run on with a wrong result.
local function unwritten(template, mixin, method)
  return function()
    fail("the stand-in for the game does not have the method " .. method .. " of " .. mixin .. " yet (template " .. template .. "): write it in tools/harness/02-widgets.lua")
  end
end
-- The methods that a mixin of the game gives, with those of the mixins that it is made from:
-- one table for each mixin, made once and shared by every frame with that mixin. The frame
-- finds them through its method lookup (kindOf), after the methods of its own kind: a mixin
-- method with the name of a method of the widget (SetEnabled, SetText) stands on top of that
-- one in the game and calls it, so the stand-in keeps the method of the widget.
local mixinTables = {}
local function mixinMethods(mixinName, templateName)
  local methods = mixinTables[mixinName]
  if methods == nil then
    methods = {}
    mixinTables[mixinName] = methods
    local mixin = gameMixin(mixinName)
    if mixin then
      for _, parent in ipairs(mixin.from or {}) do
        for method, stub in pairs(mixinMethods(parent, templateName)) do
          methods[method] = stub
        end
      end
      for _, method in ipairs(mixin.methods or {}) do
        methods[method] = unwritten(templateName, mixinName, method)
      end
    end
  end
  return methods
end

local function mixInto(object, mixinName, templateName)
  local methods = mixinMethods(mixinName, templateName)
  if next(methods) then
    local s = state(object)
    s.extras = s.extras or {}
    s.extras[#s.extras + 1] = methods
  end
end
-- A key value of a template: <KeyValue key="fitTextWidthPadding" value="40" type="number"/>.
local function setValues(object, values)
  for key, entry in pairs(values or {}) do
    local kind, value = entry[1], entry[2]
    if kind == "number" then
      rawset(object, key, tonumber(value))
    elseif kind == "boolean" then
      rawset(object, key, value == "true")
    elseif kind == "string" then
      rawset(object, key, value)
    elseif kind == "global" then
      rawset(object, key, rawget(_G, value))
    end
  end
end

-- A part of a frame that the XML file makes with its own element (<ButtonText>, <NormalTexture>)
-- is what the getter of the frame gives: the key in the state of the frame.
local PART = {
  ButtonText = "fontString", NormalTexture = "GetNormalTexture", PushedTexture = "GetPushedTexture",
  HighlightTexture = "GetHighlightTexture", DisabledTexture = "GetDisabledTexture", ThumbTexture = "thumb",
  BarTexture = "barTexture", CheckedTexture = "texture:CheckedTexture",
  DisabledCheckedTexture = "texture:DisabledCheckedTexture",
}

local function noop() end

-- What the stand-in adds to a template of the game by hand: behaviour. The kind, the child
-- keys, the names of the mixin methods and the key values of a template come from the game's
-- XML files. `fields`: a field that the Lua code of the game sets and no XML file shows, with
-- the file of the game that sets it.
local TEMPLATES = {
  -- Blizzard_SharedXML/SecureUIPanelTemplates.xml, UIButtonFitToTextBehaviorMixin in
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua.
  UIPanelButtonNoTooltipTemplate = { setup = function(frame)
    frame.SetTextToFit = function(self, value)
      self:SetText(value)
    end
    frame.FitToText = noop
  end },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: UIPanelCloseButton_OnClick hides the parent.
  UIPanelCloseButton = { setup = function(frame)
    state(frame).scripts.OnClick = function(self)
      local parent = self:GetParent()
      if parent then
        parent:Hide()
      end
    end
  end },
  -- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml: the font string .Text is also
  -- .text (UICheckButtonFontString_SetParentKeyAlias in Mainline/SharedUIPanelTemplates.lua).
  UICheckButtonTemplate = {
    fields = { text = "Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua" },
    setup = function(frame)
      frame.text = frame.Text
    end,
  },
  -- Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml: Escape takes the focus away (EditBox_ClearFocus).
  InputBoxScriptTemplate = { setup = function(frame)
    state(frame).scripts.OnEscapePressed = function(self)
      self:ClearFocus()
    end
  end },
  -- Blizzard_SharedXML/Backdrop.xml and Backdrop.lua
  BackdropTemplate = {
    fields = { backdropInfo = "Blizzard_SharedXML/Backdrop.lua" },
    setup = function(frame)
      function frame:SetBackdrop(info)
        if info ~= nil and realType(info) ~= "table" then
          fail("SetBackdrop: a table is needed")
        end
        self.backdropInfo = info
      end
      function frame:GetBackdrop()
        return self.backdropInfo
      end
      frame.ClearBackdrop = function(self)
        self.backdropInfo = nil
      end
      frame.ApplyBackdrop = noop
      frame.OnBackdropLoaded = noop
      frame.OnBackdropSizeChanged = noop
      function frame:HasBackdropInfo(info)
        return self.backdropInfo ~= nil and (info == nil or info == self.backdropInfo)
      end
      -- Blizzard_SharedXML/Backdrop.lua: the colour goes to SetVertexColor of the pieces.
      local function color(key, what)
        frame["Set" .. key] = function(self, r, g, b, a)
          number(r, what)
          number(g, what)
          number(b, what)
          state(self)["backdrop:" .. key] = { r, g, b, a or 1 }
        end
        frame["Get" .. key] = function(self)
          local kept = state(self)["backdrop:" .. key]
          if kept then
            return kept[1], kept[2], kept[3], kept[4]
          end
        end
      end
      color("BackdropColor", "SetBackdropColor")
      color("BackdropBorderColor", "SetBackdropBorderColor")
    end,
  },
  -- Blizzard_GameTooltip/Mainline/GameTooltip.xml: GameTooltipDataMixin gives GetItem.
  GameTooltipTemplate = { setup = function(frame)
    function frame:GetItem()
      local itemID = state(self).itemID
      local item = itemID and H.items and H.items[itemID]
      if item then
        return item.name, "|cffffffff|Hitem:" .. itemID .. "|h[" .. item.name .. "]|h|r", itemID
      end
    end
  end },
  -- Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml and ContainerFrame.lua
  ContainerFrameItemButtonTemplate = {
    fields = { bagID = "Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua" },
    setup = function(frame)
      for _, method in ipairs({
        "SetHasItem", "SyncAppearanceWithHasItem", "UpdateExtended", "UpdateQuestItem", "UpdateNewItem",
        "UpdateJunkItem", "UpdateCooldown", "SetReadable",
      }) do
        frame[method] = noop
      end
      function frame:GetBagID()
        return self.bagID or self:GetParent():GetID()
      end
      -- ContainerFrameItemButtonMixin:OnAttributeChanged keeps the number of the bag.
      function frame:SetBagID(id)
        self:SetAttribute("bagid", id)
        self.bagID = id
      end
      function frame:GetSlotAndBagID()
        return self:GetID(), self:GetBagID()
      end
    end,
  },
  -- The intrinsic frame ItemButton: Blizzard_ItemButton/Shared/ItemButtonTemplate.xml,
  -- ItemButtonMixin in Blizzard_ItemButton/Shared and Mainline/ItemButtonTemplate.lua.
  ItemButton = { setup = function(frame)
    frame.SetItemButtonTexture = noop
    frame.SetMatchesSearch = noop
  end },
}
H.templates = TEMPLATES

local applyTemplate

local function addChildren(parent, children, templateName)
  for _, child in ipairs(children or {}) do
    if LAYERS[child.kind] then
      local parentName = state(parent).name
      local name = child.name and parentName and (parentName .. child.name) or nil
      local object = newObject(child.kind, parent, name)
      local s = state(parent)
      if child.kind == "AnimationGroup" then
        table.insert(s.groups, object)
      elseif not NOT_A_FRAME[child.kind] then
        table.insert(s.children, object)
      elseif s.regions and state(object).class.methods.SetPoint then
        table.insert(s.regions, object)
      end
      if child.key then
        rawset(parent, child.key, object)
      end
      if child.array then
        local list = rawget(parent, child.array)
        if realType(list) ~= "table" then
          list = {}
          rawset(parent, child.array, list)
        end
        list[#list + 1] = object
      end
      if name then
        _G[name] = object
      end
      if child.part and PART[child.part] then
        s[PART[child.part]] = object
      end
      for _, inherited in ipairs(child.inherits or {}) do
        -- A font string inherits a font, which is not a template with parts.
        if gameTemplate(inherited) or TEMPLATES[inherited] then
          applyTemplate(object, inherited, 1)
        end
      end
      for _, mixin in ipairs(child.mixin or {}) do
        mixInto(object, mixin, templateName)
      end
      addChildren(object, child.children, templateName)
      setValues(object, child.values)
    end
  end
end

-- The kind of frame that a template is for, or nil for a template that the game does not have.
local function templateKind(name)
  local record = gameTemplate(name)
  return record and record.kind or (TEMPLATES[name] and TEMPLATES[name].kind)
end
H.templateKind = templateKind

applyTemplate = function(frame, name, depth)
  local record, hand = gameTemplate(name), TEMPLATES[name]
  if not record and not hand then
    fail("CreateFrame: Couldn't find inherited node \"" .. realTostring(name) .. "\"")
  end
  local kindName = state(frame).kind
  local wanted = templateKind(name)
  if wanted and wanted ~= kindName and not kindOf(kindName).isA[wanted:lower()] then
    fail("CreateFrame: the template \"" .. name .. "\" is for a " .. wanted .. ", not for a " .. kindName)
  end
  if record and depth <= 20 then
    for _, inherited in ipairs(record.inherits or {}) do
      if gameTemplate(inherited) or TEMPLATES[inherited] then
        applyTemplate(frame, inherited, depth + 1)
      end
    end
    for _, mixin in ipairs(record.mixin or {}) do
      mixInto(frame, mixin, name)
    end
    addChildren(frame, record.children, name)
    setValues(frame, record.values)
  end
  if hand and hand.setup then
    hand.setup(frame)
  end
end

function CreateFrame(kindName, name, parent, template, id)
  local kind = realType(kindName) == "string" and FRAME_KIND[kindName:lower()]
  if not kind then
    fail("CreateFrame: unknown frame type '" .. realTostring(kindName) .. "'")
  end
  -- The name: a number becomes its text, and a frame in the place of the name is no name
  -- (wowless, Frame > creation with number name, creation with frame in name position).
  if realType(name) == "number" then
    name = realTostring(name)
  elseif isWidget(name) then
    name = nil
  elseif name ~= nil and realType(name) ~= "string" then
    fail("CreateFrame: the name is not a text")
  end
  if parent ~= nil and not (isWidget(parent) and not NOT_A_FRAME[state(parent).kind]) then
    fail("CreateFrame: the parent is not a frame")
  end
  -- "$parent" at the start of the name is the name of the parent, or "Top" without a named
  -- parent (wowless, Frame > support $parent in frame names).
  if name and name:sub(1, 7):lower() == "$parent" then
    name = ((parent and state(parent).name) or "Top") .. name:sub(8)
  end
  local frame = newObject(kind, parent, name)
  if id ~= nil then
    state(frame).id = number(id, "CreateFrame")
  end
  -- An intrinsic frame type of the game (ItemButton, DropdownButton) is made from its own
  -- XML definition, which has the name of the type.
  if kind ~= "Frame" and (gameTemplate(kind) or TEMPLATES[kind]) then
    applyTemplate(frame, kind, 1)
  end
  if template ~= nil then
    for part in realTostring(template):gmatch("[^,%s]+") do
      applyTemplate(frame, part, 1)
    end
  end
  if parent then
    table.insert(state(parent).children, frame)
  end
  if name then
    _G[name] = frame
  end
  H.frames[#H.frames + 1] = frame
  return frame
end

-- The font objects of the game.
if not snapshot.ui then
  -- A run without the names file (a test of the stand-in alone) has the most common fonts.
  FONTS = { "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "NumberFontNormal", "ChatFontNormal", "GameTooltipText" }
end
for _, name in ipairs(FONTS) do
  knownFont[name] = true
  _G[name] = newObject("Font", nil, name)
end

---------------------------------------------------------------------------------------------------
-- Self-check of this file against the snapshot
--
-- Every script object of Blizzard's documentation must be a layer of some widget kind above, or
-- be here with the reason why no widget of the stand-in has it. So a script object that a patch
-- of the game adds cannot go unseen: the check fails until someone decides where it belongs.

local NOT_A_LAYER = {
  -- Objects that a function of the game returns. They are not frames or regions.
  AbbreviateConfigAPI = "an object from CreateAbbreviateConfig",
  AbbreviatedNumberFormatterAPI = "an object from a number formatter function",
  DurationTextBindingObjectAPI = "an object for the text of a duration",
  HousingCatalogSearcherAPI = "an object of the housing catalogue",
  LuaColorCurveObjectAPI = "a curve object",
  LuaCurveObjectAPI = "a curve object",
  LuaCurveObjectBaseAPI = "a curve object",
  LuaDurationClockObjectAPI = "a duration object",
  LuaDurationManualClockAPI = "a duration object",
  LuaDurationObjectAPI = "a duration object",
  LuaLocaleContextAPI = "a locale object",
  NumericFormatterAPI = "a number formatter object",
  NumericRuleFormatterAPI = "a number formatter object",
  SecondsFormatterAPI = "a time formatter object",
  TimedSignalMapAPI = "a signal map object",
  UnitHealPredictionCalculatorAPI = "a heal prediction object",
  -- Frames and parts of frames that only the game's own windows make. CreateFrame of the
  -- stand-in does not know these frame types, so an addon that asks for one fails.
  -- Objects that only the game's own code makes: no frame type of UI.xsd has them.
  FrameAPIModelSceneFrameActor = "an actor of a model scene: ModelScene:CreateActor makes it, CreateFrame does not",
  FrameAPIModelSceneFrameActorBase = "an actor of a model scene: ModelScene:CreateActor makes it, CreateFrame does not",
  FrameAPINamePlate = "a name plate: the game makes it for a unit, and UI.xsd has no such frame type",
  HousingFixturePointFrameAPI = "a frame of the housing editor: UI.xsd has no such frame type",
  HousingLayoutPinFrameAPI = "a frame of the housing editor: UI.xsd has no such frame type",
  PingPinFrameAPI = "the ping frame of the game: UI.xsd has no such frame type",
  SimpleControlPointAPI = "a control point of a path animation: Path:CreateControlPoint makes it",
  SimpleMaskTextureAPI = "a mask texture has no methods of its own in the documentation",
  SimpleVectorGraphicsAPI = "a vector graphics region: no method of a frame makes one, only an XML file",
}

-- Returns the problems, one text for each.
function H.selfCheck()
  local problems = {}
  local used = {}
  local kindNames = {}
  for name in pairs(LAYERS) do
    kindNames[#kindNames + 1] = name
  end
  table.sort(kindNames)
  for _, name in ipairs(kindNames) do
    for _, layer in ipairs(LAYERS[name]) do
      used[layer] = true
      if not snapshot.widgets[layer] then
        problems[#problems + 1] = "the widget kind " .. name .. " names the layer " .. layer .. ", which the API snapshot does not have"
      end
    end
    -- Makes the method table of the kind: a hand-written method for a name that the
    -- documentation lacks fails here.
    local ok, err = pcall(kindOf, name)
    if not ok then
      problems[#problems + 1] = "the widget kind " .. name .. ": " .. realTostring(err)
    end
  end
  local objects = {}
  for name in pairs(snapshot.widgets) do
    objects[#objects + 1] = name
  end
  table.sort(objects)
  for _, name in ipairs(objects) do
    if not used[name] and not NOT_A_LAYER[name] then
      problems[#problems + 1] = "the script object " .. name .. " of the documentation is not a layer of a widget kind and is not listed as left out (02-widgets.lua)"
    elseif used[name] and NOT_A_LAYER[name] then
      problems[#problems + 1] = "the script object " .. name .. " is a layer of a widget kind and is also listed as left out"
    end
  end
  for name in pairs(NOT_A_LAYER) do
    if not snapshot.widgets[name] then
      problems[#problems + 1] = "the script object " .. name .. " is listed as left out, and the documentation does not have it any more"
    end
  end
  -- A layer with scripts, or with a name for IsObjectType, must be a layer of some kind.
  for layer in pairs(LAYER_SCRIPTS) do
    if not used[layer] then
      problems[#problems + 1] = "the script list names the layer " .. layer .. ", which no widget kind has"
    end
  end
  for layer in pairs(ANCESTORS) do
    if not used[layer] then
      problems[#problems + 1] = "the list for IsObjectType names the layer " .. layer .. ", which no widget kind has"
    end
  end
  -- The names from the game's UI files: without them every font but a few would be refused.
  if snapshot.ui and (not knownFont.GameFontNormal or not knownFont.GameFontHighlightSmall) then
    problems[#problems + 1] = "tools/api/forever-ui.json has no fonts: build it with cargo dev ui-names"
  end
  table.sort(problems)
  return problems
end

---------------------------------------------------------------------------------------------------
-- Check of this file against the game's UI files
--
-- tools/api/forever-ui.json has what the game's own XML and Lua files say: the frame types,
-- the scripts that each kind of widget gets, the templates, and each call of a widget method
-- with its arguments written out. H.uiCheck compares the stand-in with all of it and returns
-- the differences. `cargo test` and `cargo dev conformance` run it.

-- Calls in the game's Lua code that are not calls of a widget: a Lua object of the game with
-- a method of the same name. Each needs the file of the game with the call.
local NOT_A_WIDGET_CALL = {
  ["SetValue(true)"] = "Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua: a setting object of the game, not a slider",
  ["SetValue(false)"] = "Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua: a setting object of the game, not a slider",
  ["SetSize(0)"] = "Blizzard_SharedXML/IndexRangeDataProvider.lua: a data provider, not a region",
  ["SetRotation(\"left\")"] = "Blizzard_SharedXML/ModelSceneControlFrame.lua: a button of the model controls with its own SetRotation",
  ["SetRotation(\"right\")"] = "Blizzard_SharedXML/ModelSceneControlFrame.lua: a button of the model controls with its own SetRotation",
  ["SetGlow(true)"] = "Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua: a button of the talent window with its own SetGlow",
  ["SetGlow(false)"] = "Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua: a button of the talent window with its own SetGlow",
}

-- One widget of each kind, each under its own parent.
local function oneOfEach()
  local list = {}
  local names = {}
  for name in pairs(LAYERS) do
    names[#names + 1] = name
  end
  table.sort(names)
  local host = CreateFrame("Frame", nil, UIParent)
  local group = host:CreateAnimationGroup()
  for _, name in ipairs(names) do
    local object
    if not NOT_A_FRAME[name] then
      object = CreateFrame(name, nil, host)
    elseif name == "AnimationGroup" then
      object = host:CreateAnimationGroup()
    elseif name == "Font" then
      object = newObject("Font", nil, nil)
    elseif LAYERS[name][#OBJECT + 1] == "SimpleAnimAPI" then
      object = group:CreateAnimation(name)
    else
      object = newObject(name, host)
      table.insert(state(host).regions, object)
    end
    list[#list + 1] = { name, object }
  end
  return list
end

-- The fields that a template of the game gives a frame: child keys, lists, key values and the
-- methods of its mixins, with those of the templates that it inherits.
local function templateFields(name, into, depth)
  local record = gameTemplate(name)
  if not record or depth > 20 then
    return into
  end
  for _, inherited in ipairs(record.inherits or {}) do
    templateFields(inherited, into, depth + 1)
  end
  for _, child in ipairs(record.children or {}) do
    if child.key then
      into[child.key] = true
    end
    if child.array then
      into[child.array] = true
    end
  end
  for key in pairs(record.values or {}) do
    into[key] = true
  end
  local seen = {}
  local function methodsOf(mixinName)
    local mixin = gameMixin(mixinName)
    if mixin and not seen[mixinName] then
      seen[mixinName] = true
      for _, parent in ipairs(mixin.from or {}) do
        methodsOf(parent)
      end
      for _, method in ipairs(mixin.methods or {}) do
        into[method] = true
      end
    end
  end
  for _, mixin in ipairs(record.mixin or {}) do
    methodsOf(mixin)
  end
  if TEMPLATES[name] then
    for field in pairs(TEMPLATES[name].fields or {}) do
      into[field] = true
    end
  end
  return into
end

function H.uiCheck()
  local problems = {}
  local function problem(text)
    problems[#problems + 1] = text
  end
  if not UI_NAMES.frameTypes or not uiFiles.template then
    return { "tools/api/forever-ui.json has no frame types and templates: build it with cargo dev ui-names" }
  end

  -- 1. Frame types and animation types: each one of the game is a kind, and each frame kind
  --    of this file is a frame type of the game.
  for name in pairs(UI_NAMES.frameTypes) do
    if not LAYERS[name] or NOT_A_FRAME[name] then
      problem("the frame type " .. name .. " of the game is not a widget kind (LAYERS)")
    end
  end
  for name in pairs(LAYERS) do
    if not NOT_A_FRAME[name] and not UI_NAMES.frameTypes[name] then
      problem("the widget kind " .. name .. " is not a frame type of the game (UI.xsd and the intrinsic frames)")
    end
  end
  for _, name in ipairs(UI_NAMES.animationTypes or {}) do
    if not (LAYERS[name] and NOT_A_FRAME[name]) then
      problem("the animation type " .. name .. " of the game is not a widget kind (LAYERS)")
    end
  end

  -- The lists of allowed texts of UI.xsd: each value is one that the hand-written list takes.
  for enumeration, list in pairs({ DRAWLAYER = DRAW_LAYERS, FRAMESTRATA = STRATA, JUSTIFYHTYPE = JUSTIFY_H, JUSTIFYVTYPE = JUSTIFY_V, FRAMEPOINT = POINTS }) do
    local values = (UI_NAMES.enumerations or {})[enumeration]
    if not values then
      problem("UI.xsd does not have the list " .. enumeration .. " any more")
    end
    for _, value in ipairs(values or {}) do
      if not list[value] then
        problem("UI.xsd has the value " .. value .. " in " .. enumeration .. ", and the stand-in refuses it")
      end
    end
  end

  -- 2. Scripts: a script that an XML file of the game puts on a kind is a script of that kind.
  for element, scripts in pairs(UI_NAMES.scripts or {}) do
    if LAYERS[element] then
      local known = kindOf(element).scripts
      for _, script in ipairs(scripts) do
        if not known[script] then
          problem("the game's XML files put the script " .. script .. " on a " .. element .. ", and the stand-in does not have it for that kind (LAYER_SCRIPTS)")
        end
      end
    elseif element ~= "Actor" then
      problem("the game's XML files put scripts on a " .. element .. ", which is not a widget kind")
    end
  end

  -- 3. Templates: each hand-written entry is a template of the game, and gives no field that
  --    the game's template does not have.
  local templateNames = {}
  for name in pairs(TEMPLATES) do
    templateNames[#templateNames + 1] = name
  end
  table.sort(templateNames)
  for _, name in ipairs(templateNames) do
    local record = gameTemplate(name)
    if not record then
      problem("the template " .. name .. " is written by hand, and the game's XML files do not have it")
    else
      local ok, frame = pcall(CreateFrame, record.kind, nil, UIParent, name)
      if not ok then
        problem("the template " .. name .. " cannot be made: " .. realTostring(frame))
      else
        local fields = templateFields(name, {}, 0)
        -- The intrinsic frame type of the template brings its own fields.
        templateFields(record.kind, fields, 0)
        for key, value in pairs(frame) do
          if key ~= "__state" and realType(key) == "string" and not fields[key] then
            problem("the template " .. name .. " gives the field " .. key .. ", which the game's template does not have (a child key, a key value or a mixin method)")
          end
        end
      end
    end
  end

  -- 4. Calls of the game's own code: each must be accepted by one kind that has the method.
  local calls = uiFiles.calls and uiFiles.calls() or {}
  local objects
  local used = {}
  for index, call in ipairs(calls) do
    if index % 200 == 1 then
      objects = oneOfEach()
    end
    local method = call:match("^([%w_]+)%(")
    local chunk = loadstring("return function(o) return o:" .. call .. " end")
    if method and chunk then
      local fn = chunk()
      local has, accepted, firstError, firstKind = false, false, nil, nil
      for _, entry in ipairs(objects) do
        local object = entry[2]
        if object[method] ~= nil then
          has = true
          local ok, err = pcall(fn, object)
          if ok then
            accepted = true
            break
          elseif not firstError then
            firstError, firstKind = realTostring(err), entry[1]
          end
        end
      end
      if has and not accepted then
        if NOT_A_WIDGET_CALL[call] then
          used[call] = true
        elseif firstError:find("there is no region with the name", 1, true) then
          -- An anchor to a frame of the game by its name: the stand-in does not have that frame.
        else
          problem("the game's code calls " .. call .. ", and the stand-in refuses it: " .. firstKind .. ": " .. firstError)
        end
      end
    end
  end
  for call in pairs(NOT_A_WIDGET_CALL) do
    if #calls > 0 and not used[call] then
      problem("NOT_A_WIDGET_CALL lists " .. call .. ", which the stand-in accepts or the game's code does not have any more")
    end
  end
  table.sort(problems)
  return problems
end

-- The names of the methods that a widget can have: those of every kind. `cargo dev ui-names`
-- collects the calls of these in the game's own Lua code.
function H.widgetMethodNames()
  local seen, names = {}, {}
  for kindName in pairs(LAYERS) do
    for method in pairs(kindOf(kindName).methods) do
      if not seen[method] then
        seen[method] = true
        names[#names + 1] = method
      end
    end
  end
  table.sort(names)
  return names
end