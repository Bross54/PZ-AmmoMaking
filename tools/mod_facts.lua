-- Ammo Making - what the mod relies on, taken from its own model
--
-- Run by tools/pz_compat.py inside a Lua 5.1 state in which
-- tests/mock_pz.lua and every mod file have been loaded. Returns one table
-- of plain lists and maps: every vanilla item, tag, station, timed action,
-- recipe, loot list, sprite and sound the mod names. Nothing here is typed
-- by hand: a new calibre or recipe is covered because the model has it.

local facts = {
    items = {},         -- vanilla item id -> where it is used
    itemTags = {},      -- item tag -> a recipe that uses it
    benchTags = {},     -- station tag -> a recipe that uses it
    timedActions = {},  -- timed action -> a recipe that uses it
    vanillaRecipes = {},
    calibres = {},
    lootLists = {},
    sprites = {},
    sounds = {},
    modItems = {},
}

local function item(id, where)
    if type(id) ~= "string" then return end
    if string.sub(id, 1, 5) == "Base." then
        facts.items[id] = facts.items[id] or where
    else
        facts.modItems[id] = true
    end
end

local function recipeLines(recipe, where)
    for _, input in ipairs(recipe.inputs or {}) do
        for _, id in ipairs(input.items or {}) do item(id, where) end
        for _, tag in ipairs(input.tags or {}) do facts.itemTags[tag] = facts.itemTags[tag] or where end
    end
    for _, output in ipairs(recipe.outputs or {}) do item(output.item, where) end
end

for _, recipe in ipairs(AC_Materials.RECIPES) do
    local where = "recipe " .. recipe.id
    recipeLines(recipe, where)
    facts.benchTags[recipe.benchTag] = facts.benchTags[recipe.benchTag] or where
    if recipe.timedAction then
        facts.timedActions[recipe.timedAction] = facts.timedActions[recipe.timedAction] or where
    end
end

-- Vanilla recipes the conservation checks model by id.
for _, recipe in ipairs(AC_Materials.VANILLA_RECIPES) do
    -- One mirror entry per calibre stands for vanilla's single recipe.
    facts.vanillaRecipes[string.match(recipe.id, "^(GatherGunpowder)_") or recipe.id] = true
    recipeLines(recipe, "vanilla recipe " .. recipe.id)
end
facts.vanillaRecipes[AC_Compat.BOX_RECIPE] = true

for _, id in ipairs(AC_Compat.REQUIRED_ITEMS) do item(id, "AC_Compat.REQUIRED_ITEMS") end

-- What the test mock claims the game has: checked like the mod's own names,
-- so the tests cannot run against items or sprites that do not exist.
for id in pairs(MOCK.knownScriptItems) do item(id, "tests/mock_pz.lua knownScriptItems") end
for id in pairs(MOCK.useDeltas) do item(id, "tests/mock_pz.lua useDeltas") end
for sprite in pairs(MOCK.knownSprites) do facts.sprites[sprite] = facts.sprites[sprite] or "tests/mock_pz.lua knownSprites" end

for _, calibre in ipairs(AC_Calibres.LIST) do
    item(calibre.round, "calibre " .. calibre.id)
    item(calibre.box, "calibre " .. calibre.id .. " (box)")
    table.insert(facts.calibres, {
        id = calibre.id,
        round = calibre.round,
        box = calibre.box,
        roundsPerBox = calibre.roundsPerBox,
        ammoType = calibre.ammoType,
    })
end

local powder = AC_Calibres.POWDER
item(powder.item, "gunpowder")
item(powder.fertilizerItem, "gunpowder")
facts.powder = { item = powder.item, usesPerJar = powder.usesPerJar }

-- Drainables whose use count the material model assumes.
facts.uses = { [powder.item] = powder.usesPerJar }
for _, source in ipairs(AC_Calibres.COMPOUND_SOURCES) do
    for _, id in ipairs(source.items) do item(id, "priming compound") end
    for id, uses in pairs(source.uses or {}) do facts.uses[id] = uses end
end
for id, units in pairs(AC_Materials.UNITS) do
    if type(units) == "table" and units.uses and string.sub(id, 1, 5) == "Base." then
        facts.uses[id] = units.uses
    end
end
for _, id in ipairs(AC_Calibres.WAD.items) do item(id, "wadding") end

for id in pairs(AC_Mining.PICKAXE_TYPES) do item(id, "AC_Mining.PICKAXE_TYPES") end
for id in pairs(AC_GeologySampling.SHOVEL_TYPES) do item(id, "AC_GeologySampling.SHOVEL_TYPES") end
for _, metal in ipairs(AC_Deposits.METALS) do item(AC_Mining.getOreItemType(metal), "ore of " .. metal) end

for _, target in ipairs(AC_Loot.TARGETS) do facts.lootLists[target.list] = true end

facts.sprites[AC_LaboratoryAnalyzer.CONFIG.worldSprite] = "the placed laboratory analyzer"
facts.sounds[AC_Mining.CONFIG.sound] = "mining"
facts.sounds[AC_GeologySampling.CONFIG.digSound] = "digging a sample"

-- The press is described and switched off; what it names is watched, not
-- required.
facts.press = {
    enabled = AC_Calibres.PRESS.enabled,
    benchTag = AC_Calibres.PRESS.benchTag,
    timedAction = AC_Calibres.PRESS.timedAction,
}

return facts
