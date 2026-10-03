-- Ammo Making - renders the generated files of the add-on mods
--
-- A feature that needs scripts ships them in an add-on mod of its own
-- (AC_Features.lua). Those scripts are generated from the same model as the
-- main mod's, whether or not the feature is on in the Lua state that
-- renders them:
--
--   Reloading Press   mod/AmmoMakingPress
--     42/media/scripts/AC_PressRecipes.txt        every calibre's press recipes
--     common/.../Translate/EN/Recipes.json         their names
--   Spent Cases       mod/AmmoMakingSpentCases
--     42/media/scripts/AC_SpentCaseItems.txt       one spent case per calibre
--     42/media/scripts/AC_SpentCaseRecipes.txt     their scrapping recipes
--     common/.../Translate/EN/ItemName.json, Recipes.json
--
--   tests/write_recipes.lua  writes them
--   tests/run_tests.lua      asserts each file equals its rendering
--
-- Needs the mod loaded (AC_Calibres, AC_Recycling) and tests/render_recipes.
-- Returns a table of functions; it defines no globals.

local A = {}

A.PRESS = "mod/AmmoMakingPress/"
A.SPENT = "mod/AmmoMakingSpentCases/"

A.PRESS_SCRIPT = A.PRESS .. "42/media/scripts/AC_PressRecipes.txt"
A.PRESS_NAMES = A.PRESS .. "common/media/lua/shared/Translate/EN/Recipes.json"

A.SPENT_ITEMS = A.SPENT .. "42/media/scripts/AC_SpentCaseItems.txt"
A.SPENT_SCRIPT = A.SPENT .. "42/media/scripts/AC_SpentCaseRecipes.txt"
A.SPENT_ITEM_NAMES = A.SPENT .. "common/media/lua/shared/Translate/EN/ItemName.json"
A.SPENT_NAMES = A.SPENT .. "common/media/lua/shared/Translate/EN/Recipes.json"

-- "key": "value" pairs of a flat JSON object, in file order.
function A.readNames(text)
    local names, order = {}, {}
    for key, value in string.gmatch(text, '"([^"]+)"%s*:%s*"([^"]*)"') do
        names[key] = value
        table.insert(order, key)
    end
    return names, order
end

-- A flat JSON object, one pair per line, in the given order.
function A.renderNames(pairsInOrder)
    local lines = {}
    for index, pair in ipairs(pairsInOrder) do
        local key = string.gsub(pair[1], '["\\]', "\\%0")
        local value = string.gsub(pair[2], '["\\]', "\\%0")
        table.insert(lines, '    "' .. key .. '": "' .. value .. '"' .. (index < #pairsInOrder and "," or ""))
    end
    return "{\n" .. table.concat(lines, "\n") .. "\n}\n"
end

------------------------------------------------
-- Reloading press
------------------------------------------------

-- Every calibre's press recipes, in calibre order.
function A.pressRecipes()
    local recipes = {}
    for _, calibre in ipairs(AC_Calibres.LIST) do
        for _, recipe in ipairs(AC_Calibres.buildPressRecipes(calibre)) do
            table.insert(recipes, recipe)
        end
    end
    return recipes
end

function A.pressScriptBody(RENDER)
    return RENDER.renderModule(A.pressRecipes())
end

-- handNames: the main mod's recipe names (id -> name).
function A.pressNames(handNames)
    local list = {}
    for _, recipe in ipairs(A.pressRecipes()) do
        local hand = handNames[recipe.handRecipe]
        assert(hand and hand ~= "", "no name for " .. tostring(recipe.handRecipe))
        table.insert(list, { recipe.id, hand .. AC_Calibres.PRESS.nameSuffix })
    end
    return A.renderNames(list)
end

------------------------------------------------
-- Spent cases
------------------------------------------------

-- The script fields of every item in an item script: full type -> { key = value }.
function A.readItemFields(text)
    text = string.gsub(text, "/%*.-%*/", "")
    local module = string.match(text, "module%s+([%w_]+)")
    local items = {}
    for name, body in string.gmatch(text, "item%s+([%w_]+)%s*(%b{})") do
        local fields = {}
        for key, value in string.gmatch(body, "([%w_]+)%s*=%s*([^,\n]+),") do
            fields[key] = (string.gsub(value, "%s+$", ""))
        end
        items[module .. "." .. name] = fields
    end
    return items
end

-- The spent-case items, each with the look and weight of its clean case.
-- mainItems: the text of the main mod's AC_Items.txt.
function A.spentItems(mainItems)
    local clean = A.readItemFields(mainItems)
    return AC_SpentCases.buildItems(function(fullType) return clean[fullType] end)
end

-- One item block per calibre.
function A.spentItemsBody(mainItems)
    local blocks = {}
    for _, item in ipairs(A.spentItems(mainItems)) do
        local lines = { "    item " .. item.name, "    {" }
        for _, field in ipairs(item.fields) do
            table.insert(lines, "        " .. field[1] .. " = " .. tostring(field[2]) .. ",")
        end
        table.insert(lines, "    }")
        table.insert(blocks, table.concat(lines, "\n"))
    end
    return "module AmmoMaking\n{\n" .. table.concat(blocks, "\n\n") .. "\n}\n"
end

function A.spentItemNames(mainItems)
    local list = {}
    for _, item in ipairs(A.spentItems(mainItems)) do
        table.insert(list, { item.fullType, item.displayName })
    end
    return A.renderNames(list)
end

function A.spentRecipes()
    local recipes = {}
    for _, recipe in ipairs(AC_Recycling.buildRecipes({ AC_Recycling.getSpentSource() })) do
        -- buildRecipes() ends with the recast, which the main mod ships.
        if recipe.recyclingSource then table.insert(recipes, recipe) end
    end
    return recipes
end

function A.spentScriptBody(RENDER)
    return RENDER.renderModule(A.spentRecipes())
end

function A.spentNames()
    local list = {}
    for _, recipe in ipairs(A.spentRecipes()) do
        table.insert(list, { recipe.id, AC_Recycling.getSpentRecipeName(recipe) })
    end
    return A.renderNames(list)
end

------------------------------------------------
-- Writing
------------------------------------------------

local function read(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = string.gsub(handle:read("*a"), "\r", "")
    handle:close()
    return text
end

local function write(path, text)
    local handle = assert(io.open(path, "w"), "cannot write " .. path)
    handle:write(text)
    handle:close()
end

-- Rewrites a script's body, keeping its leading comment.
local function writeScript(path, body, RENDER)
    local header = RENDER.splitHeader(assert(read(path), "cannot open " .. path))
    write(path, header .. body)
end

-- which: "press", "spent" or nil for both. Returns the paths written.
function A.writeAll(root, RENDER, which)
    local written = {}
    if which == nil or which == "press" then
        writeScript(root .. "/" .. A.PRESS_SCRIPT, A.pressScriptBody(RENDER), RENDER)
        local handNames = A.readNames(assert(read(root .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        write(root .. "/" .. A.PRESS_NAMES, A.pressNames(handNames))
        table.insert(written, A.PRESS_SCRIPT)
        table.insert(written, A.PRESS_NAMES)
    end
    if (which == nil or which == "spent") and AC_SpentCases then
        local mainItems = assert(read(root .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
        writeScript(root .. "/" .. A.SPENT_ITEMS, A.spentItemsBody(mainItems), RENDER)
        writeScript(root .. "/" .. A.SPENT_SCRIPT, A.spentScriptBody(RENDER), RENDER)
        write(root .. "/" .. A.SPENT_ITEM_NAMES, A.spentItemNames(mainItems))
        write(root .. "/" .. A.SPENT_NAMES, A.spentNames())
        for _, path in ipairs({ A.SPENT_ITEMS, A.SPENT_SCRIPT, A.SPENT_ITEM_NAMES, A.SPENT_NAMES }) do
            table.insert(written, path)
        end
    end
    return written
end

return A
