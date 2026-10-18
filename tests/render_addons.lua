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
--     42/media/scripts/AC_SpentCaseRecipes.txt     their scrapping and resizing recipes
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
-- The station itself: vanilla names an entity's build recipe in
-- Recipes.json under the entity's name ("Hand_Press"), the bench tag its
-- recipes ask for in IG_UI.json ("IGUI_CraftingWindow_HandPress", read by
-- ISWidgetTitleHeader for "Requires a ..."), and the placed object in
-- Moveables.json under its tile's GroupName_CustomName.
A.PRESS_ENTITY = "AmmoMaking_ReloadingPress"
A.PRESS_DISPLAY_NAME = "Reloading Press"
A.PRESS_UI = A.PRESS .. "common/media/lua/shared/Translate/EN/IG_UI.json"
A.PRESS_MOVEABLES = A.PRESS .. "common/media/lua/shared/Translate/EN/Moveables.json"

function A.pressUiNames()
    return A.renderNames({ { "IGUI_CraftingWindow_" .. AC_Calibres.PRESS.benchTag, A.PRESS_DISPLAY_NAME } })
end

function A.pressMoveableNames()
    return A.renderNames({ { "Reloading_Press", A.PRESS_DISPLAY_NAME } })
end

function A.pressNames(handNames)
    local list = { { A.PRESS_ENTITY, A.PRESS_DISPLAY_NAME } }
    for _, recipe in ipairs(A.pressRecipes()) do
        local hand = handNames[recipe.handRecipe]
        assert(hand and hand ~= "", "no name for " .. tostring(recipe.handRecipe))
        table.insert(list, { recipe.id, AC_Calibres.pressName(hand) })
    end
    return A.renderNames(list)
end

------------------------------------------------
-- Calibres of other mods (AC_Calibres.EXTENSIONS)
------------------------------------------------
--
-- One add-on per gun mod (a "pack"): the items of each of its calibres,
-- made from the calibre's template (the same look and weight, the
-- calibre's name in place of the template's), their recipes
-- (AC_Calibres.buildAllRecipesOf), their English names, made from the
-- template's recipe names, and the add-on's mod.info. A calibre two gun
-- mods share (the same round item) is in both packs, identically.
--
-- requires: the gun mod's id. incompatible: the packs whose calibres
-- name the same round item as a different calibre (Base.762Bullets is
-- 7.62x39 in Vanilla Weapons Plus and VFE, 7.62x51 in Rain's).

A.EXTENSION_PACKS = {
    { feature = "calibre762x39", root = "mod/AmmoMakingCalibre762x39/", prefix = "762x39",
      title = "Ammo Making: 7.62x39 (experimental)", poster = "7.62X39",
      gunMod = "Vanilla Weapons Plus - Gunworks Edition", requires = "MarzVanillaGuns",
      incompatible = { "AmmoMakingRains", "AmmoMakingRainsExpanded" } },
    { feature = "packVFE", root = "mod/AmmoMakingVFE/", prefix = "VFE",
      title = "Ammo Making: Vanilla Firearms Expansion (experimental)", poster = "VFE",
      gunMod = "Vanilla Firearms Expansion", requires = "VFExpansion1",
      incompatible = { "AmmoMakingRains", "AmmoMakingRainsExpanded" } },
    { feature = "packRains", root = "mod/AmmoMakingRains/", prefix = "Rains",
      title = "Ammo Making: Rain's Firearms (experimental)", poster = "RAIN'S",
      gunMod = "B42 Rain's Firearms & Gun Parts", requires = "B42RainsFirearmsAndGunParts4220",
      incompatible = { "AmmoMakingCalibre762x39", "AmmoMakingVFE", "AmmoMakingRainsExpanded" } },
    { feature = "packRainsExpanded", root = "mod/AmmoMakingRainsExpanded/", prefix = "RainsExpanded",
      title = "Ammo Making: Rain's Firearms Expanded (experimental)", poster = "RAIN'S EXP",
      gunMod = "B42 Rain's Firearms & Gun Parts Expanded", requires = "B42RainsFirearmsAndGunPartsExpanded4220",
      incompatible = { "AmmoMakingCalibre762x39", "AmmoMakingVFE", "AmmoMakingRains" } },
    { feature = "packGaelGunStore", root = "mod/AmmoMakingGaelGunStore/", prefix = "GaelGunStore",
      title = "Ammo Making: GaelGunStore (experimental)", poster = "GAELGUNSTORE",
      gunMod = "GaelGunStore", requires = "GaelGunStore_B42", incompatible = {} },
    { feature = "packRealFirearms", root = "mod/AmmoMakingRealFirearms/", prefix = "RealFirearms",
      title = "Ammo Making: Real Firearms (experimental)", poster = "REAL FIREARMS",
      gunMod = "Real Firearms", requires = "RealFirearms", incompatible = {} },
    { feature = "packMFS", root = "mod/AmmoMakingMFS/", prefix = "MFS",
      title = "Ammo Making: Modern Firearms System (experimental)", poster = "MFS",
      gunMod = "Modern Firearms System", requires = "ModernFirearmsSystem", incompatible = {},
      -- MFS ejects casings of its own for the vanilla rounds: their
      -- resizing travels with this pack (AC_SpentCases.CASING_BRIDGES.mfs).
      casingBridge = "mfs" },
    { feature = "packGuns93", root = "mod/AmmoMakingGuns93/", prefix = "Guns93",
      title = "Ammo Making: Guns of 93 (experimental)", poster = "GUNS OF 93",
      gunMod = "Guns of 93", requires = "guns93", incompatible = {} },
    { feature = "packPSA", root = "mod/AmmoMakingPSA/", prefix = "PSA",
      title = "Ammo Making: Post Soviet Armory (experimental)", poster = "PSA",
      gunMod = "Post Soviet Armory", requires = "PostSovietArmoryB42", incompatible = {} },
}

function A.getPack(feature)
    for _, pack in ipairs(A.EXTENSION_PACKS) do
        if pack.feature == feature then return pack end
    end
    return nil
end

-- The extension calibres of a pack, in AC_Calibres.EXTENSIONS order.
function A.packCalibres(pack)
    local list = {}
    for _, calibre in ipairs(AC_Calibres.EXTENSIONS) do
        for _, feature in ipairs(AC_Calibres.extensionFeatures(calibre)) do
            if feature == pack.feature then table.insert(list, calibre) end
        end
    end
    return list
end

function A.packPaths(pack)
    local root = pack.root
    return {
        items = root .. "42/media/scripts/AC_" .. pack.prefix .. "Items.txt",
        script = root .. "42/media/scripts/AC_" .. pack.prefix .. "Recipes.txt",
        itemNames = root .. "common/media/lua/shared/Translate/EN/ItemName.json",
        names = root .. "common/media/lua/shared/Translate/EN/Recipes.json",
        info = root .. "42/mod.info",
    }
end

-- Replaces every plain occurrence of from in text.
local function swap(text, from, to)
    local out, start = {}, 1
    while true do
        local i, j = string.find(text, from, start, true)
        if not i then break end
        table.insert(out, string.sub(text, start, i - 1))
        table.insert(out, to)
        start = j + 1
    end
    table.insert(out, string.sub(text, start))
    return table.concat(out)
end
A.swap = swap

-- The extension's items in the order of ITEM_ROLES, each a copy of its
-- template's item: { name, fullType, fields = { {key, value}, ... } }.
local ITEM_ROLES = { "dieSet", "case", "bullet", "castBullet" }

function A.extensionItems(calibre, mainItems)
    local template = assert(AC_Calibres.get(calibre.template) or (function()
        for _, c in ipairs(AC_Calibres.LIST) do if c.id == calibre.template then return c end end
    end)(), "no template calibre " .. tostring(calibre.template))
    local source = string.gsub(mainItems, "\r", "")
    local items = {}
    for _, role in ipairs(ITEM_ROLES) do
        local fullType, templateType = calibre[role], template[role]
        if fullType and templateType then
            local templateName = string.match(templateType, "%.([%w_]+)$")
            local body = assert(string.match(source, "item%s+" .. templateName .. "%s*(%b{})"), "no template item " .. templateType)
            local fields = {}
            for key, value in string.gmatch(body, "([%w_]+)%s*=%s*([^,\n]+),") do
                if key == "DisplayName" then value = swap(value, template.id, calibre.id) end
                table.insert(fields, { key, value })
            end
            table.insert(items, { name = string.match(fullType, "%.([%w_]+)$"), fullType = fullType, fields = fields })
        end
    end
    -- Its spent case, made from its case as the spent cases add-on makes
    -- the vanilla calibres' (AC_SpentCases.buildItems).
    local caseFields = {}
    for _, item in ipairs(items) do
        if item.fullType == calibre.case then
            for _, field in ipairs(item.fields) do caseFields[field[1]] = field[2] end
        end
    end
    for _, spent in ipairs(AC_SpentCases.buildItems(function(fullType) return fullType == calibre.case and caseFields or nil end, { calibre })) do
        table.insert(items, spent)
    end
    return items, template
end

function A.extensionItemsBody(calibres, mainItems)
    local blocks = {}
    local items = {}
    for _, calibre in ipairs(calibres) do
        for _, item in ipairs((A.extensionItems(calibre, mainItems))) do table.insert(items, item) end
    end
    for _, item in ipairs(items) do
        local lines = { "    item " .. item.name, "    {" }
        for _, field in ipairs(item.fields) do
            table.insert(lines, "        " .. field[1] .. " = " .. field[2] .. ",")
        end
        table.insert(lines, "    }")
        table.insert(blocks, table.concat(lines, "\n"))
    end
    return "module AmmoMaking\n{\n" .. table.concat(blocks, "\n\n") .. "\n}\n"
end

function A.extensionItemNames(calibres, mainItems)
    local list = {}
    for _, calibre in ipairs(calibres) do
        for _, item in ipairs((A.extensionItems(calibre, mainItems))) do
            for _, field in ipairs(item.fields) do
                if field[1] == "DisplayName" then table.insert(list, { item.fullType, tostring(field[2]) }) end
            end
        end
    end
    return A.renderNames(list)
end

-- pack (optional): a pack with a casingBridge adds the resizing of its
-- gun mod's casings after its calibres' recipes.
function A.extensionRecipes(calibres, pack)
    local recipes = {}
    for _, calibre in ipairs(calibres) do
        for _, recipe in ipairs(AC_Calibres.buildAllRecipesOf(calibre)) do table.insert(recipes, recipe) end
    end
    if pack and pack.casingBridge then
        for _, recipe in ipairs(AC_SpentCases.buildCasingBridgeRecipes(pack.casingBridge)) do table.insert(recipes, recipe) end
    end
    return recipes
end

function A.extensionScriptBody(calibres, RENDER, pack)
    return RENDER.renderModule(A.extensionRecipes(calibres, pack))
end

-- The pack's mod.info. version: the main mod's modversion.
function A.packInfo(pack, version)
    local incompatible = {}
    for _, id in ipairs(pack.incompatible) do table.insert(incompatible, "\\" .. id) end
    local calibres = {}
    for _, calibre in ipairs(A.packCalibres(pack)) do table.insert(calibres, calibre.id) end
    local lines = {
        "name=" .. pack.title,
        "id=" .. AC_Features.get(pack.feature).mod,
        "require=\\AmmoMaking,\\" .. pack.requires,
    }
    if #incompatible > 0 then table.insert(lines, "incompatible=" .. table.concat(incompatible, ",")) end
    table.insert(lines, "modversion=" .. version)
    table.insert(lines, "versionMin=" .. A.mainVersionMin())
    table.insert(lines, "poster=poster.png")
    table.insert(lines, "description=EXPERIMENTAL add-on for Ammo Making and " .. pack.gunMod .. ": handload its "
        .. table.concat(calibres, ", ") .. " like the vanilla rounds, with die sets, cases, copper or cast lead bullets and the same tools. Not yet verified in game.")
    return table.concat(lines, "\n") .. "\n"
end

-- The names of a casing bridge's resizings: the spent cases' resizing of
-- the calibre, with the bridge's suffix.
function A.casingBridgeNames(key, handNames)
    local list = {}
    for _, recipe in ipairs(AC_SpentCases.buildCasingBridgeRecipes(key)) do
        local form = handNames[recipe.formRecipe]
        assert(form and form ~= "", "no name for " .. tostring(recipe.formRecipe))
        table.insert(list, { recipe.id, AC_SpentCases.getResizeName(form) .. AC_SpentCases.CASING_BRIDGES[key].nameSuffix })
    end
    return list
end

-- handNames: the main mod's recipe names. Each recipe is named after the
-- template's recipe of the same id, the calibre's name in place of the
-- template's. pack (optional): its casing bridge's names follow.
function A.extensionNames(calibres, handNames, pack)
    local list = {}
    for _, calibre in ipairs(calibres) do
        local template = nil
        for _, c in ipairs(AC_Calibres.LIST) do if c.id == calibre.template then template = c end end
        assert(template, "no template calibre " .. tostring(calibre.template))
        local function nameOf(id)
            local templateId = swap(id, calibre.suffix, template.suffix)
            local name = handNames[templateId]
            assert(name and name ~= "", "no name for " .. templateId)
            return swap(name, template.id, calibre.id)
        end
        for _, recipe in ipairs(AC_Calibres.buildAllRecipesOf(calibre)) do
            local name
            if recipe.press then
                -- Named after its hand recipe, as the press add-on names the
                -- vanilla calibres' ("... (Press)").
                name = AC_Calibres.pressName(nameOf(recipe.handRecipe))
            elseif recipe.resize then
                name = AC_SpentCases.getResizeName(nameOf(recipe.formRecipe))
            elseif recipe.clean then
                name = AC_SpentCases.getCleanName(nameOf(recipe.formRecipe))
            elseif recipe.recyclingSource then
                local units = tonumber(string.match(recipe.id, "(%d+)$"))
                name = AC_Recycling.getSpentSizeName(units) .. " - " .. calibre.id
            else
                name = nameOf(recipe.id)
            end
            table.insert(list, { recipe.id, name })
        end
    end
    if pack and pack.casingBridge then
        for _, entry in ipairs(A.casingBridgeNames(pack.casingBridge, handNames)) do table.insert(list, entry) end
    end
    return A.renderNames(list)
end

-- The main mod's versionMin: every add-on asks for the same build.
function A.mainVersionMin()
    local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$")) or "."
    local handle = assert(io.open(root .. "/mod/AmmoMaking/42/mod.info", "r"))
    local text = handle:read("*a")
    handle:close()
    return assert(string.match(text, "versionMin=([^\r\n]+)"), "no versionMin")
end

------------------------------------------------
-- Hot Brass bridge
------------------------------------------------

A.HOT_BRASS = "mod/AmmoMakingHotBrass/"
A.HOT_BRASS_SCRIPT = A.HOT_BRASS .. "42/media/scripts/AC_HotBrassRecipes.txt"
A.HOT_BRASS_NAMES = A.HOT_BRASS .. "common/media/lua/shared/Translate/EN/Recipes.json"
A.HOT_BRASS_INFO = A.HOT_BRASS .. "42/mod.info"

function A.hotBrassScriptBody(RENDER)
    return RENDER.renderModule(AC_SpentCases.buildHotBrassRecipes())
end

function A.hotBrassNames(handNames)
    return A.renderNames(A.casingBridgeNames("hotBrass", handNames))
end

function A.hotBrassInfo(version)
    return table.concat({
        "name=Ammo Making: Hot Brass Casings (experimental)",
        "id=" .. AC_Features.get("hotBrass").mod,
        "require=\\AmmoMaking,\\HBVCEFb42",
        "modversion=" .. version,
        "versionMin=" .. A.mainVersionMin(),
        "poster=poster.png",
        "description=EXPERIMENTAL add-on for Ammo Making and Hot Brass: the casings Hot Brass ejects are resized at the calibre's die set like Ammo Making's spent cases, two into one usable case of a lower quality, for no XP. Not yet verified in game.",
    }, "\n") .. "\n"
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
-- The brass catcher (AC_SpentCases.CATCHER), after the spent cases.
function A.catcherItem()
    local c = AC_SpentCases.CATCHER
    return {
        name = string.match(c.item, "%.([%w_]+)$"), fullType = c.item, displayName = c.displayName,
        fields = { { "DisplayName", c.displayName }, { "DisplayCategory", c.category }, { "ItemType", "base:normal" },
                   { "Icon", c.icon }, { "Weight", c.weight }, { "WorldStaticModel", "AmmoMaking.AmmoMakingBrassCatcher" } },
    }
end

-- The case tumbler (AC_SpentCases.TUMBLER), after the catcher.
function A.tumblerItem()
    local t = AC_SpentCases.TUMBLER
    return {
        name = string.match(t.item, "%.([%w_]+)$"), fullType = t.item, displayName = t.displayName,
        fields = { { "DisplayName", t.displayName }, { "DisplayCategory", t.category }, { "ItemType", "base:normal" },
                   { "Icon", t.icon }, { "Weight", t.weight }, { "WorldStaticModel", "AmmoMaking.AmmoMakingCaseTumbler" } },
    }
end

function A.spentItemsBody(mainItems)
    local blocks = {}
    local items = A.spentItems(mainItems)
    table.insert(items, A.catcherItem())
    table.insert(items, A.tumblerItem())
    for _, item in ipairs(items) do
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
    table.insert(list, { AC_SpentCases.CATCHER.item, AC_SpentCases.CATCHER.displayName })
    table.insert(list, { AC_SpentCases.TUMBLER.item, AC_SpentCases.TUMBLER.displayName })
    return A.renderNames(list)
end

-- The scrapping recipes of the spent source.
function A.spentScrapRecipes()
    local recipes = {}
    for _, recipe in ipairs(AC_Recycling.buildRecipes({ AC_Recycling.getSpentSource() })) do
        -- buildRecipes() ends with the recast, which the main mod ships.
        if recipe.recyclingSource then table.insert(recipes, recipe) end
    end
    return recipes
end

-- Everything the add-on's recipe script holds: the scrapping recipes, then
-- one resizing recipe per calibre.
function A.spentRecipes()
    local recipes = A.spentScrapRecipes()
    for _, recipe in ipairs(AC_SpentCases.buildResizeRecipes()) do table.insert(recipes, recipe) end
    for _, recipe in ipairs(AC_SpentCases.buildCleanRecipes()) do table.insert(recipes, recipe) end
    table.insert(recipes, AC_SpentCases.buildCatcherRecipe())
    table.insert(recipes, AC_SpentCases.buildTumblerRecipe())
    for _, recipe in ipairs(AC_SpentCases.buildTumbleRecipes()) do table.insert(recipes, recipe) end
    return recipes
end

function A.spentScriptBody(RENDER)
    return RENDER.renderModule(A.spentRecipes())
end

-- handNames: the main mod's recipe names (id -> name); a resizing recipe is
-- named after its forming recipe.
function A.spentNames(handNames)
    local list = {}
    for _, recipe in ipairs(A.spentRecipes()) do
        if recipe.resize then
            local form = handNames[recipe.formRecipe]
            assert(form and form ~= "", "no name for " .. tostring(recipe.formRecipe))
            table.insert(list, { recipe.id, AC_SpentCases.getResizeName(form) })
        elseif recipe.tumble then
            local form = handNames[recipe.formRecipe]
            assert(form and form ~= "", "no name for " .. tostring(recipe.formRecipe))
            table.insert(list, { recipe.id, AC_SpentCases.getTumbleName(form) })
        elseif recipe.clean then
            local form = handNames[recipe.formRecipe]
            assert(form and form ~= "", "no name for " .. tostring(recipe.formRecipe))
            table.insert(list, { recipe.id, AC_SpentCases.getCleanName(form) })
        elseif recipe.tumbler then
            table.insert(list, { recipe.id, AC_SpentCases.TUMBLER.recipeName })
        elseif recipe.catcher then
            table.insert(list, { recipe.id, AC_SpentCases.CATCHER.recipeName })
        else
            table.insert(list, { recipe.id, AC_Recycling.getSpentRecipeName(recipe) })
        end
    end
    return A.renderNames(list)
end

------------------------------------------------
-- docs/PLACEHOLDER_ASSETS.md: every temporary visual, in one table
------------------------------------------------
--
-- Two kinds of rows, from two sources:
--
--   AC_Visuals.LIST            what Lua names (sprites, a window icon)
--   the item scripts           each item's Icon and world model, which the
--                              engine reads from the script: the main
--                              mod's AC_Items.txt and the spent-cases
--                              add-on's generated AC_SpentCaseItems.txt
--
-- An inventory icon is the mod's own where AC_Visuals.ICONS lists it;
-- everything else is a vanilla asset or programmer art standing in for
-- art the mod does not have.

A.ASSETS_START = "<!-- PLACEHOLDER ASSET TABLE: generated by tests/write_recipes.lua from AC_Visuals.lua and the item scripts. Do not edit. -->"
A.ASSETS_FINISH = "<!-- END PLACEHOLDER ASSET TABLE -->"

-- Items of an item script in file order: { fullType, fields }.
function A.readItemsInOrder(text)
    text = string.gsub(text, "/%*.-%*/", "")
    local module = string.match(text, "module%s+([%w_]+)")
    local items = {}
    for name, body in string.gmatch(text, "item%s+([%w_]+)%s*(%b{})") do
        local fields = {}
        for key, value in string.gmatch(body, "([%w_]+)%s*=%s*([^,\n]+),") do
            fields[key] = (string.gsub(value, "%s+$", ""))
        end
        table.insert(items, { fullType = module .. "." .. name, fields = fields })
    end
    return items
end

-- mainItems, spentItems: the texts of the two item scripts.
function A.renderPlaceholders(mainItems, spentItems)
    local lines = {
        "### Sprites and window icons (configured in Lua: `AC_Visuals.lua`)",
        "",
        "| Feature | Current placeholder | Vanilla source / reference | Where configured | Final asset needed later |",
        "|---|---|---|---|---|",
    }
    for _, visual in ipairs(AC_Visuals.LIST) do
        local where = "`AC_Visuals.LIST`, key `" .. visual.key .. "`"
        if visual.mirror then
            where = where .. " (mirrors `" .. visual.mirror .. "`, which the engine reads)"
        end
        table.insert(lines, "| " .. table.concat({
            visual.feature, "`" .. visual.value .. "` (" .. visual.kind .. ")", visual.source, where, visual.final,
        }, " | ") .. " |")
    end

    local function itemRows(title, script, text)
        table.insert(lines, "")
        table.insert(lines, "### " .. title)
        table.insert(lines, "")
        table.insert(lines, "| Item | Icon (inventory) | World model | Where configured | Final asset needed later |")
        table.insert(lines, "|---|---|---|---|---|")
        local count = 0
        for _, item in ipairs(A.readItemsInOrder(text)) do
            local fields = item.fields
            local own = AC_Visuals.findIcon(fields.Icon) ~= nil
            count = count + 1
            table.insert(lines, "| " .. table.concat({
                (fields.DisplayName or item.fullType) .. " (`" .. item.fullType .. "`)",
                "`" .. tostring(fields.Icon) .. "`, " .. (own and "the mod's own" or "vanilla"),
                fields.WorldStaticModel and ("`" .. fields.WorldStaticModel .. "`, " .. (string.find(fields.WorldStaticModel, "AmmoMaking.", 1, true) == 1 and "the mod's own (art/models/make_models.py)" or "vanilla")) or "none (the engine's default for an item without one)",
                "`" .. script .. "`, item `" .. string.match(item.fullType, "([^%.]+)$") .. "`: `Icon`, `WorldStaticModel`",
                own and (fields.WorldStaticModel and "a world model" or "none; a world model is optional")
                    or ("a 32 x 32 icon" .. (fields.WorldStaticModel and " and a world model" or "; a world model is optional")),
            }, " | ") .. " |")
        end
        return count
    end
    local main = itemRows("Items of the main mod (configured in the item script)", "mod/AmmoMaking/42/media/scripts/AC_Items.txt", mainItems)
    local spent = itemRows("Items of the spent-cases add-on (generated: each copies its unused case)", "mod/AmmoMakingSpentCases/42/media/scripts/AC_SpentCaseItems.txt", spentItems)
    table.insert(lines, "")
    table.insert(lines, #AC_Visuals.LIST .. " visuals named in Lua, " .. main .. " items of the main mod, " .. spent .. " of the spent-cases add-on: " .. (#AC_Visuals.LIST + main + spent) .. " placeholders in all. An item with an icon of the mod's own is still listed while its world model is borrowed.")
    return table.concat(lines, "\n")
end

function A.renderPlaceholderBlock(mainItems, spentItems)
    return A.ASSETS_START .. "\n\n" .. A.renderPlaceholders(mainItems, spentItems) .. "\n\n" .. A.ASSETS_FINISH
end

function A.replacePlaceholders(text, mainItems, spentItems)
    local from = string.find(text, A.ASSETS_START, 1, true)
    local _, to = string.find(text, A.ASSETS_FINISH, 1, true)
    if not from or not to or to < from then return nil end
    return string.sub(text, 1, from - 1) .. A.renderPlaceholderBlock(mainItems, spentItems) .. string.sub(text, to + 1)
end

A.ASSETS_DOCUMENT = "docs/PLACEHOLDER_ASSETS.md"

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
local function writeScript(path, body, RENDER, defaultHeader)
    local existing = read(path)
    local header = existing and RENDER.splitHeader(existing) or assert(defaultHeader, "cannot open " .. path)
    write(path, header .. body)
end

-- The leading comment of a pack's generated scripts.
local function packHeader(pack, what)
    return "/* " .. pack.title .. " - " .. what .. ".\n\n"
        .. "   EXPERIMENTAL, NOT YET SEEN IN GAME. Needs " .. pack.gunMod .. " (" .. pack.requires .. ").\n\n"
        .. "   THE BODY OF THIS FILE IS GENERATED by tests/write_recipes.lua from\n"
        .. "   AC_Calibres.EXTENSIONS of the main mod (tests/render_addons.lua). The\n"
        .. "   OnCreate callbacks are the main mod's. Do not edit the body. */\n\n"
end

-- which: "press", "spent" or nil for both. Returns the paths written.
function A.writeAll(root, RENDER, which)
    local written = {}
    if which == nil or which == "press" then
        writeScript(root .. "/" .. A.PRESS_SCRIPT, A.pressScriptBody(RENDER), RENDER)
        local handNames = A.readNames(assert(read(root .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        write(root .. "/" .. A.PRESS_NAMES, A.pressNames(handNames))
        write(root .. "/" .. A.PRESS_UI, A.pressUiNames())
        write(root .. "/" .. A.PRESS_MOVEABLES, A.pressMoveableNames())
        table.insert(written, A.PRESS_SCRIPT)
        table.insert(written, A.PRESS_NAMES)
    end
    if (which == nil or which == "spent") and AC_SpentCases then
        local mainItems = assert(read(root .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
        writeScript(root .. "/" .. A.SPENT_ITEMS, A.spentItemsBody(mainItems), RENDER)
        writeScript(root .. "/" .. A.SPENT_SCRIPT, A.spentScriptBody(RENDER), RENDER)
        write(root .. "/" .. A.SPENT_ITEM_NAMES, A.spentItemNames(mainItems))
        local handNames = A.readNames(assert(read(root .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        write(root .. "/" .. A.SPENT_NAMES, A.spentNames(handNames))
        for _, path in ipairs({ A.SPENT_ITEMS, A.SPENT_SCRIPT, A.SPENT_ITEM_NAMES, A.SPENT_NAMES }) do
            table.insert(written, path)
        end
    end
    if which == nil or which == "hotbrass" then
        local handNames = A.readNames(assert(read(root .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        local version = string.match(assert(read(root .. "/mod/AmmoMaking/42/mod.info")), "modversion=([^\n]+)")
        writeScript(root .. "/" .. A.HOT_BRASS_SCRIPT, A.hotBrassScriptBody(RENDER), RENDER,
            "/* Ammo Making: Hot Brass Casings (add-on) - resizing Hot Brass's casings.\n\n"
            .. "   EXPERIMENTAL, NOT YET SEEN IN GAME. Needs Hot Brass (HBVCEFb42).\n\n"
            .. "   THE BODY OF THIS FILE IS GENERATED by tests/write_recipes.lua from\n"
            .. "   AC_SpentCases.buildHotBrassRecipes of the main mod: the spent cases'\n"
            .. "   resizing with Hot Brass's casing in place of the spent case. The OnCreate\n"
            .. "   callbacks are the main mod's. Do not edit the body. */\n\n")
        write(root .. "/" .. A.HOT_BRASS_NAMES, A.hotBrassNames(handNames))
        write(root .. "/" .. A.HOT_BRASS_INFO, A.hotBrassInfo(version))
        for _, path in ipairs({ A.HOT_BRASS_SCRIPT, A.HOT_BRASS_NAMES, A.HOT_BRASS_INFO }) do table.insert(written, path) end
    end
    if which == nil or which == "extensions" then
        local mainItems = assert(read(root .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
        local handNames = A.readNames(assert(read(root .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        local version = string.match(assert(read(root .. "/mod/AmmoMaking/42/mod.info")), "modversion=([^\n]+)")
        for _, pack in ipairs(A.EXTENSION_PACKS) do
            local calibres = A.packCalibres(pack)
            local paths = A.packPaths(pack)
            writeScript(root .. "/" .. paths.items, A.extensionItemsBody(calibres, mainItems), RENDER, packHeader(pack, "the items of its calibres"))
            writeScript(root .. "/" .. paths.script, A.extensionScriptBody(calibres, RENDER, pack), RENDER, packHeader(pack, "the recipes of its calibres"))
            write(root .. "/" .. paths.itemNames, A.extensionItemNames(calibres, mainItems))
            write(root .. "/" .. paths.names, A.extensionNames(calibres, handNames, pack))
            write(root .. "/" .. paths.info, A.packInfo(pack, version))
            for _, path in ipairs({ paths.items, paths.script, paths.itemNames, paths.names, paths.info }) do
                table.insert(written, path)
            end
        end
    end
    if which == nil then
        local path = root .. "/" .. A.ASSETS_DOCUMENT
        local document = read(path)
        if document then
            local mainItems = assert(read(root .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
            local spentItems = assert(read(root .. "/" .. A.SPENT_ITEMS))
            write(path, assert(A.replacePlaceholders(document, mainItems, spentItems), "placeholder table markers not found"))
            table.insert(written, A.ASSETS_DOCUMENT)
        end
    end
    return written
end

return A
