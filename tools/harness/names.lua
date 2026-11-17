-- For `cargo dev conformance`: the names that the stand-in for the game has.
--
-- Returns { globals = { name, ... }, methods = { name, ... } }.
--   globals: every global name: the documented functions and namespaces, and what the stand-in
--            adds by hand (each of those cites the game's own UI code).
--   methods: every name that can follow a colon: the documented methods of every widget kind,
--            and the methods of the objects that the game's Lua code hands out (a timer, a menu
--            entry, a scroll view, a colour, a template).

local H = ...
local realType = H.realType

local methods = {}
for _, object in pairs(H.snapshot.widgets) do
  for name in pairs(object.methods) do
    methods[name] = true
  end
end

-- Function fields of a table, and of the tables in it.
local seen = {}
local function collect(value, depth)
  if realType(value) ~= "table" or seen[value] or depth > 3 then
    return
  end
  seen[value] = true
  if H.isWidget(value) then
    for name in pairs(H.state(value).class.methods) do
      methods[name] = true
    end
    -- The methods that the templates of the frame give it (the mixins of the game).
    for _, extra in ipairs(H.state(value).extras or {}) do
      for name in pairs(extra) do
        methods[name] = true
      end
    end
  end
  for key, field in pairs(value) do
    if realType(key) == "string" and key ~= "__state" then
      if realType(field) == "function" then
        methods[key] = true
      else
        collect(field, depth + 1)
      end
    end
  end
end

-- Objects that the game's Lua code makes on request.
H.call = function(_, fn, ...)
  return pcall(fn, ...)
end
H.openAuctionHouse()
QuestLogQuests_Update()
local samples = {
  C_Timer.NewTimer(1, function() end),
  CreateScrollBoxListLinearView(),
  CreateDataProvider({}),
  CreateColor(1, 1, 1),
  CreateVector2D(0, 0),
  ItemLocation:CreateFromBagAndSlot(0, 1),
  Settings.RegisterCanvasLayoutCategory(CreateFrame("Frame"), "sample"),
  QuestScrollFrame.titleFramePool,
  WorldMapFrame:GetPinFrameLevelsManager(),
}
-- The icons of the quests in the quest log (Blizzard_POIButton): the frames of their pool.
for icon in QuestScrollFrame.Contents.buttonPool:EnumerateActive() do
  samples[#samples + 1] = icon
end
MenuUtil.CreateContextMenu(UIParent, function(_, root)
  samples[#samples + 1] = root
end)
-- One frame of each template, for the methods and keys that the template gives.
for name in pairs(H.templates) do
  local ok, frame = pcall(CreateFrame, H.templateKind(name) or "Frame", nil, UIParent, name)
  if ok then
    samples[#samples + 1] = frame
  end
end
for _, sample in ipairs(samples) do
  collect(sample, 0)
end

local globals = {}
for name, value in pairs(_G) do
  if realType(name) == "string" then
    globals[#globals + 1] = name
    collect(value, 0)
  end
end
-- The methods of a text: text:lower(), text:format(...).
for name in pairs(string) do
  methods[name] = true
end

local methodList = {}
for name in pairs(methods) do
  methodList[#methodList + 1] = name
end
table.sort(globals)
table.sort(methodList)
return { globals = globals, methods = methodList }
