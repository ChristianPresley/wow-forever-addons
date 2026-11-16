
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
  ModelScene = join(FRAME, "FrameAPIModelSceneFrame"),
  Minimap = join(FRAME, "MinimapFrameAPI"),
  MovieFrame = join(FRAME, "SimpleMovieAPI"),
  Browser = join(FRAME, "SimpleBrowserAPI"),
  OffScreenFrame = join(FRAME, "SimpleOffScreenFrameAPI"),
  -- Animations
  AnimationGroup = join(OBJECT, "SimpleAnimGroupAPI"),
  Animation = ANIMATION,
  Alpha = join(ANIMATION, "SimpleAnimAlphaAPI"),
  Rotation = join(ANIMATION, "SimpleAnimRotationAPI"),
  Scale = join(ANIMATION, "SimpleAnimScaleAPI"),
  Translation = join(ANIMATION, "SimpleAnimTranslationAPI"),
  Path = join(ANIMATION, "SimpleAnimPathAPI"),
  FlipBook = join(ANIMATION, "SimpleAnimFlipBookAPI"),
  VertexColor = join(ANIMATION, "SimpleAnimVertexColorAPI"),
  TextureCoordTranslation = join(ANIMATION, "SimpleAnimTextureCoordTranslationAPI"),
  -- Fonts
  Font = join(OBJECT, "SimpleFontAPI"),
}

-- The kinds that CreateFrame makes: all but the regions, the animations and the font.
local NOT_A_FRAME = {
  Texture = true, MaskTexture = true, Line = true, FontString = true, AnimationGroup = true, Animation = true,
  Alpha = true, Rotation = true, Scale = true, Translation = true, Path = true, FlipBook = true,
  VertexColor = true, TextureCoordTranslation = true, Font = true,
}
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
    "OnEditFocusLost", "OnCursorChanged", "OnTextSet", "OnInputLanguageChanged", "OnArrowPressed",
  },
  SimpleSliderAPI = { "OnValueChanged", "OnMinMaxChanged" },
  SimpleStatusBarAPI = { "OnValueChanged", "OnMinMaxChanged" },
  SimpleScrollFrameAPI = { "OnVerticalScroll", "OnHorizontalScroll", "OnScrollRangeChanged" },
  FrameAPITooltip = { "OnTooltipCleared", "OnTooltipSetDefaultAnchor", "OnTooltipAddMoney" },
  FrameAPICooldown = { "OnCooldownDone" },
  SimpleMessageFrameAPI = { "OnMessageScrollChanged" },
  SimpleColorSelectAPI = { "OnColorSelect" },
  SimpleModelAPI = { "OnAnimFinished", "OnModelLoaded", "OnUpdateModel" },
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
    __index = function(_, key)
      return kind.methods[key]
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
    attributes = {}, children = {}, regions = {}, groups = {}, lines = 0,
  })
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
define("SimpleFrameScriptObjectAPI", "GetObjectType", function(self)
  return state(self).kind
end)
-- A button is also a "Frame"; the name is not case sensitive (Blizzard_Dispatcher.lua).
define("SimpleFrameScriptObjectAPI", "IsObjectType", function(self, name)
  return state(self).class.isA[realTostring(name):lower()] == true
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
local function eachShownChild(self, fn)
  local s = state(self)
  for _, list in ipairs({ s.regions, s.children }) do
    for _, child in ipairs(list) do
      if state(child).shown then
        fn(child)
      end
    end
  end
end

local function fireShown(self)
  run(self, "OnShow")
  eachShownChild(self, fireShown)
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
local function pointName(value, what)
  local name = realType(value) == "string" and value:upper()
  if not name or not POINTS[name] then
    fail("SetPoint: unknown " .. what .. " " .. realTostring(value))
  end
  return name
end

-- The forms of the game: (point), (point, x, y), (point, relativeTo), (point, relativeTo, x, y),
-- (point, relativeTo, relativePoint), (point, relativeTo, relativePoint, x, y).
-- relativeTo is a region or the name of one. The second form of four is in the game's own
-- code: Blizzard_AdventureMap/AM_QuestDialog.lua.
define("SimpleScriptRegionResizingAPI", "SetPoint", function(self, point, a, b, c, d)
  point = pointName(point, "point")
  local relativeTo, relativePoint, x, y
  if realType(a) == "number" then
    x, y = a, b
  elseif a == nil and b == nil then
    x, y = 0, 0
  else
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
  if relativeTo == self then
    fail("SetPoint: a region cannot be anchored to itself")
  end
  relativePoint = relativePoint ~= nil and pointName(relativePoint, "relative point") or point
  x, y = x or 0, y or 0
  if realType(x) ~= "number" or realType(y) ~= "number" then
    fail("SetPoint: an offset is not a number")
  end
  local points = state(self).points
  local entry = { point, relativeTo or state(self).parent, relativePoint, x, y }
  for index, existing in ipairs(points) do
    if existing[1] == point then
      points[index] = entry -- the same point again replaces the first
      return
    end
  end
  points[#points + 1] = entry
end)
define("SimpleScriptRegionResizingAPI", "ClearAllPoints", function(self)
  state(self).points = {}
end)
define("SimpleScriptRegionResizingAPI", "SetAllPoints", function(self, relativeTo)
  if relativeTo ~= nil and not isWidget(relativeTo) then
    fail("SetAllPoints: the region to anchor to is not a region")
  end
  local target = relativeTo or state(self).parent
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
  define(layer, "SetAlpha", function(self, alpha)
    if secrets[alpha] == nil then
      number(alpha, "SetAlpha")
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
local UI_NAMES = snapshot.ui or {}
local FONTS = UI_NAMES.fonts or {}
local undocumentedEvent = {}
for _, name in ipairs(UI_NAMES.undocumentedEvents or {}) do
  undocumentedEvent[name] = true
end
H.undocumentedEvents = undocumentedEvent
local knownFont = {}

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
  if realType(kindName) ~= "string" or not (LAYERS[kindName] and NOT_A_FRAME[kindName]) or kindName == "AnimationGroup" then
    fail("CreateAnimation: unknown animation type " .. realTostring(animationType))
  end
  return newObject(kindName, self, realType(name) == "string" and name or nil)
end)
define("SimpleAnimGroupAPI", "IsPlaying", function()
  return false
end)

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
local STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true,
  FULLSCREEN_DIALOG = true, TOOLTIP = true, PARENT = true, WORLD = true,
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
define("SimpleButtonAPI", "SetText", function(self, text)
  checkText(text, "SetText")
  state(self).text = text
  local fontString = state(self).fontString
  if fontString then
    state(fontString).text = text
  end
end)
define("SimpleButtonAPI", "GetFontString", function(self)
  local s = state(self)
  if not s.fontString then
    s.fontString = newObject("FontString", self)
    state(s.fontString).text = s.text
  end
  return s.fontString
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
define("SimpleFontStringAPI", "SetJustifyH", function(_, value)
  if realType(value) ~= "string" or not JUSTIFY_H[value:upper()] then
    fail("SetJustifyH: unknown value " .. realTostring(value))
  end
end)
define("SimpleFontStringAPI", "SetJustifyV", function(_, value)
  if realType(value) ~= "string" or not JUSTIFY_V[value:upper()] then
    fail("SetJustifyV: unknown value " .. realTostring(value))
  end
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
define("SimpleSliderAPI", "GetThumbTexture", function(self)
  local s = state(self)
  s.thumb = s.thumb or newObject("Texture", self)
  return s.thumb
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
  number(value, "SetValue")
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
local ANCHORS = {
  ANCHOR_TOP = true, ANCHOR_RIGHT = true, ANCHOR_BOTTOM = true, ANCHOR_LEFT = true, ANCHOR_TOPRIGHT = true,
  ANCHOR_BOTTOMRIGHT = true, ANCHOR_TOPLEFT = true, ANCHOR_BOTTOMLEFT = true, ANCHOR_CURSOR = true,
  ANCHOR_CURSOR_RIGHT = true, ANCHOR_CURSOR_LEFT = true, ANCHOR_PRESERVE = true, ANCHOR_NONE = true,
}
undocumented("FrameAPITooltip", "SetOwner", GAME_TOOLTIP, function(self, owner, anchor)
  if not isWidget(owner) then
    fail("SetOwner: the owner is not a region")
  end
  if anchor ~= nil and not ANCHORS[anchor] then
    fail("SetOwner: unknown anchor " .. realTostring(anchor))
  end
  local s = state(self)
  s.owner, s.lines, s.text = owner, 0, nil
  -- SetOwner clears and hides the tooltip. It shows again when it gets an item or a spell, or
  -- with Show() after AddLine: an addon that adds lines and forgets Show() has no tooltip.
  hide(self)
end)
undocumented("FrameAPITooltip", "GetOwner", "Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua", function(self)
  return state(self).owner
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

-- A font string without a text gives nil, although the documentation has a text.
H.allowNil("FontString:GetText", "The game gives nil for a font string without a text: Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua reads self.description:GetText() or \"\".")

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
-- What a template of the game gives a frame: child keys, methods and scripts. Each entry names
-- the frame kind of the template and the game file. A template that is not here fails, the
-- same as an unknown template in the game.

local function child(kindName, key, alias)
  return function(frame)
    local kindIsRegion = NOT_A_FRAME[kindName]
    local name = state(frame).name
    local object = newObject(kindName, frame, name and realType(alias) == "string" and (name .. alias) or nil)
    table.insert(kindIsRegion and state(frame).regions or state(frame).children, object)
    frame[key] = object
    if state(object).name then
      _G[state(object).name] = object
    end
    return object
  end
end

local function all(...)
  local steps = { ... }
  return function(frame)
    for _, step in ipairs(steps) do
      step(frame)
    end
  end
end

local function threePart(frame)
  child("Texture", "Left")(frame)
  child("Texture", "Right")(frame)
  child("Texture", "Middle")(frame)
end

local function noop() end

local TEMPLATES = {
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
  UIPanelButtonTemplate = { kind = "Button", setup = function(frame)
    threePart(frame)
    -- The text of the button, "$parentText" in the game.
    local text = child("FontString", "Text", "Text")(frame)
    state(frame).fontString = text
    frame.SetTextToFit = function(self, value)
      self:SetText(value)
    end
    frame.FitToText = noop
  end },
  UIPanelCloseButton = { kind = "Button", setup = function(frame)
    -- UIPanelCloseButton_OnClick hides the parent.
    state(frame).scripts.OnClick = function(self)
      local parent = self:GetParent()
      if parent then
        parent:Hide()
      end
    end
  end },
  UISliderTemplate = { kind = "Slider", setup = all(child("Frame", "NineSlice"), child("Texture", "Thumb")) },
  -- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml: .Text, and .text as an alias.
  UICheckButtonTemplate = { kind = "CheckButton", setup = function(frame)
    local text = child("FontString", "Text", "Text")(frame)
    frame.text = text
  end },
  -- Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml
  InputBoxTemplate = { kind = "EditBox", setup = function(frame)
    threePart(frame)
    state(frame).scripts.OnEscapePressed = function(self)
      self:ClearFocus()
    end
  end },
  SearchBoxTemplate = { kind = "EditBox", setup = function(frame)
    threePart(frame)
    child("FontString", "Instructions")(frame)
    child("Texture", "searchIcon")(frame)
    local clear = child("Button", "clearButton")(frame)
    child("Texture", "Icon")(clear)
    state(frame).scripts.OnEscapePressed = function(self)
      self:ClearFocus()
    end
  end },
  -- Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml. It has no .Inset.
  BasicFrameTemplateWithInset = { kind = "Frame", setup = function(frame)
    child("FontString", "TitleText")(frame)
    local close = child("Button", "CloseButton")(frame)
    state(close).scripts.OnClick = function(self)
      self:GetParent():Hide()
    end
    for _, key in ipairs({ "Bg", "TitleBg", "TopTileStreaks", "InsetBg" }) do
      child("Texture", key)(frame)
    end
  end },
  -- Blizzard_SharedXML/Backdrop.xml and Backdrop.lua
  BackdropTemplate = { setup = function(frame)
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
    function frame:SetBackdropColor(r, g, b)
      number(r, "SetBackdropColor")
      number(g, "SetBackdropColor")
      number(b, "SetBackdropColor")
    end
    function frame:SetBackdropBorderColor(r, g, b)
      number(r, "SetBackdropBorderColor")
      number(g, "SetBackdropBorderColor")
      number(b, "SetBackdropBorderColor")
    end
  end },
  -- Blizzard_GameTooltip/Mainline/GameTooltip.xml: GameTooltipDataMixin gives GetItem.
  GameTooltipTemplate = { kind = "GameTooltip", setup = function(frame)
    function frame:GetItem()
      local itemID = state(self).itemID
      local item = itemID and H.items and H.items[itemID]
      if item then
        return item.name, "|cffffffff|Hitem:" .. itemID .. "|h[" .. item.name .. "]|h|r", itemID
      end
    end
  end },
  -- Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml and ContainerFrame.lua
  ContainerFrameItemButtonTemplate = { kind = "ItemButton", setup = function(frame)
    for _, method in ipairs({
      "SetHasItem", "SetItemButtonTexture", "SyncAppearanceWithHasItem", "UpdateExtended", "UpdateQuestItem",
      "UpdateNewItem", "UpdateJunkItem", "UpdateCooldown", "SetReadable", "SetMatchesSearch",
    }) do
      frame[method] = noop
    end
    function frame:GetBagID()
      return self.bagID or self:GetParent():GetID()
    end
    function frame:SetBagID(id)
      self:SetAttribute("bagid", id)
    end
    child("Texture", "icon")(frame)
    child("FontString", "Count")(frame)
    child("Texture", "IconBorder")(frame)
  end },
}
H.templates = TEMPLATES

-- Templates of the game that the stand-in does not have yet: the message says so, and does not
-- say that the game lacks them.
local GAME_TEMPLATES = {
  BasicFrameTemplate = true, ButtonFrameTemplate = true, PortraitFrameTemplate = true, DefaultPanelTemplate = true,
  UIPanelScrollFrameTemplate = true, ScrollFrameTemplate = true, CooldownFrameTemplate = true,
  SecureActionButtonTemplate = true, UIDropDownMenuTemplate = true, UISliderTemplateWithLabels = true,
  UIPanelCloseButtonDefaultAnchors = true, InsetFrameTemplate = true, SharedTooltipTemplate = true,
  SecureHandlerStateTemplate = true, SecureUnitButtonTemplate = true, OptionsSliderTemplate = true,
}

function CreateFrame(kindName, name, parent, template, id)
  local kind = realType(kindName) == "string" and FRAME_KIND[kindName:lower()]
  if not kind then
    fail("CreateFrame: unknown frame type '" .. realTostring(kindName) .. "'")
  end
  if name ~= nil and realType(name) ~= "string" then
    fail("CreateFrame: the name is not a text")
  end
  if parent ~= nil and not (isWidget(parent) and not NOT_A_FRAME[state(parent).kind]) then
    fail("CreateFrame: the parent is not a frame")
  end
  local frame = newObject(kind, parent, name)
  if id ~= nil then
    state(frame).id = number(id, "CreateFrame")
  end
  if template ~= nil then
    for part in realTostring(template):gmatch("[^,%s]+") do
      local entry = TEMPLATES[part]
      if not entry then
        if GAME_TEMPLATES[part] then
          fail("CreateFrame: the stand-in for the game does not have the template \"" .. part .. "\" yet (tools/harness/02-widgets.lua)")
        end
        fail("CreateFrame: Couldn't find inherited node \"" .. part .. "\"")
      end
      if entry.kind and entry.kind ~= kind and not kindOf(kind).isA[entry.kind:lower()] then
        fail("CreateFrame: the template \"" .. part .. "\" is for a " .. entry.kind .. ", not for a " .. kind)
      end
      entry.setup(frame)
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
  FrameAPIArchaeologyDigSiteFrame = "the dig site frame of the game's map",
  FrameAPIBlob = "a quest blob frame of the game's map",
  FrameAPIFogOfWarFrame = "the fog of war frame of the game's map",
  FrameAPIModelSceneFrameActor = "an actor of a model scene",
  FrameAPIModelSceneFrameActorBase = "an actor of a model scene",
  FrameAPINamePlate = "a name plate of the game",
  FrameAPIQuestPOI = "the quest marker frame of the game's map",
  FrameAPIScenarioPOI = "the scenario marker frame of the game's map",
  FrameAPISimpleCheckout = "the checkout frame of the shop",
  FrameAPIUnitPositionFrame = "the unit position frame of the game's map",
  HousingFixturePointFrameAPI = "a frame of the housing editor",
  HousingLayoutPinFrameAPI = "a frame of the housing editor",
  PingPinFrameAPI = "the ping frame of the game",
  SimpleAnimRadialProgressAPI = "an animation type that the stand-in does not make",
  SimpleAnimScaleLineAPI = "an animation type that the stand-in does not make",
  SimpleAnimTranslationLineAPI = "an animation type that the stand-in does not make",
  SimpleControlPointAPI = "a control point of a path animation",
  SimpleMapSceneAPI = "the map scene frame of the game",
  SimpleMaskTextureAPI = "a mask texture has no methods of its own in the documentation",
  SimpleModelFFXAPI = "a model frame type that the stand-in does not make",
  SimpleVectorGraphicsAPI = "a vector graphics region that the stand-in does not make",
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