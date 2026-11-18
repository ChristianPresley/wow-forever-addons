local _, ns = ...

-- Crafting cost and profit. When the player selects a learned recipe in the profession window, the
-- addon notes its reagents, for all characters of the account. The cost of a craft is the
-- sum of the stored auction prices of its reagents; the profit is what the item sells for at the
-- auction house, minus the cut of the house (5%), minus that cost.
--
-- Only basic reagents count. Optional and finishing reagents are left out. For a reagent with
-- several qualities the cheapest stored one counts.

local CUT = 0.05
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1

local function recipes()
  local db = ForeverAuctionsDB
  if type(db.recipes) ~= "table" then
    db.recipes = {} -- [output itemID] = { makes = average items per craft, slots = { { qty, ids = { itemID, ... } } } }
  end
  return db.recipes
end

-- Reads one recipe. Returns true if it was stored.
local function learnRecipe(recipeID)
  local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
  if type(info) ~= "table" or not info.learned then
    return false
  end
  local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
  local output = type(schematic) == "table" and schematic.outputItemID
  if type(output) ~= "number" or type(schematic.reagentSlotSchematics) ~= "table" then
    return false
  end
  local slots = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics) do
    if slot.reagentType == BASIC and slot.required ~= false and type(slot.quantityRequired) == "number" and slot.quantityRequired > 0 then
      local ids = {}
      for _, reagent in ipairs(type(slot.reagents) == "table" and slot.reagents or {}) do
        if type(reagent.itemID) == "number" then
          ids[#ids + 1] = reagent.itemID
        end
      end
      if #ids > 0 then
        slots[#slots + 1] = { qty = slot.quantityRequired, ids = ids }
      end
    end
  end
  if #slots == 0 then
    return false
  end
  local low = type(schematic.quantityMin) == "number" and schematic.quantityMin or 1
  local high = type(schematic.quantityMax) == "number" and schematic.quantityMax or low
  recipes()[output] = { makes = math.max(1, (low + high) / 2), slots = slots }
  return true
end

-- This client has no list of all recipes for addons. The profession window says which recipe the
-- player selects (ProfessionsRecipeListMixin.Event.OnRecipeSelected), and that one is read.
function ns.LearnRecipe(recipeID)
  if not (ForeverAuctionsDB and type(recipeID) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
    and C_TradeSkillUI.GetRecipeSchematic) then
    return false
  end
  local ok, stored = pcall(learnRecipe, recipeID)
  return ok and stored or false
end

-- The cost of the reagents of one crafted item, and whether every reagent has a stored price.
-- Nil if no known recipe makes the item.
function ns.CraftCost(itemID)
  local recipe = ForeverAuctionsDB and type(ForeverAuctionsDB.recipes) == "table" and ForeverAuctionsDB.recipes[itemID]
  if type(recipe) ~= "table" or type(recipe.slots) ~= "table" then
    return nil
  end
  local total, complete = 0, true
  for _, slot in ipairs(recipe.slots) do
    local cheapest
    for _, id in ipairs(slot.ids or {}) do
      local entry = ns.Lookup(id)
      if entry and (not cheapest or entry.price < cheapest) then
        cheapest = entry.price
      end
    end
    if cheapest then
      total = total + cheapest * (slot.qty or 1)
    else
      complete = false
    end
  end
  return math.floor(total / (recipe.makes or 1) + 0.5), complete
end

-- What one crafted item earns at the auction house after the cut, minus the cost of its reagents.
-- Nil unless the item and every reagent have a stored price.
function ns.CraftProfit(itemID)
  local cost, complete = ns.CraftCost(itemID)
  local entry = ns.Lookup(itemID)
  if not (cost and complete and entry) then
    return nil
  end
  return math.floor(entry.price * (1 - CUT) + 0.5) - cost, cost
end

local owner = {}
if EventRegistry and EventRegistry.RegisterCallback then
  pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
    if type(recipeInfo) == "table" then
      ns.LearnRecipe(recipeInfo.recipeID)
    end
  end, owner)
end
