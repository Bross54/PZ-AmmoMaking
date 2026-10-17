-- Ammo Making - offline tests: calibres of other mods (AC_Calibres.EXTENSIONS)
-- and their add-ons (mod/AmmoMakingCalibre762x39).
--
-- Loaded by tests/run_tests.lua. The add-on's scripts are generated
-- (tests/render_addons.lua); here they are held to the model, the
-- calibre is checked with its add-on in the game and out of it, and the
-- vanilla calibres are shown to be untouched either way. That the round
-- Base.762Bullets and its AmmoType are what Vanilla Weapons Plus -
-- Gunworks Edition ships was read from its installed files (Workshop
-- 3773834525); that the add-on loads beside it is REQUIRES FUTURE
-- IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK
    local readFile, ROOT, parseScript = T.readFile, T.ROOT, T.parseScript

    local ADDONS = dofile(ROOT .. "/tests/render_addons.lua")
    local RENDER = T.RENDER

    local function strip(text) return (string.gsub(text or "", "\r", "")) end

    section("Calibres of other mods: absent unless their add-on is in the game (pure)")
    do
        eq(#AC_Calibres.EXTENSIONS, 1, "one extension calibre: 7.62x39")
        local ext = AC_Calibres.EXTENSIONS[1]
        eq(ext.id, "7.62x39", "its id")
        eq(ext.round, "Base.762Bullets", "the round of Vanilla Weapons Plus")
        eq(ext.ammoType, "mvgi:bullets_762", "and its AmmoType")
        eq(ext.class, "rifle", "a rifle round")
        eq(AC_Features.get(ext.extension).mod, "AmmoMakingCalibre762x39", "switched by its add-on")
        eq(#AC_Calibres.validate(AC_Calibres.EXTENSIONS), 0, "the definition is sound: " .. table.concat(AC_Calibres.validate(AC_Calibres.EXTENSIONS), "; "))
        eq(#AC_Calibres.ALL, #AC_Calibres.LIST, "without the add-on: only the vanilla calibres")
        eq(AC_Calibres.identify(ext.round), nil, "and its round is nothing to the mod")
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            check(recipe.calibre ~= ext.id, recipe.id .. " is not of the extension")
        end
        local seen = {}
        for _, calibre in ipairs(AC_Calibres.LIST) do
            seen[calibre.round] = true
            seen[calibre.suffix] = true
        end
        check(not seen[ext.round] and not seen[ext.suffix], "it shares no round or suffix with a vanilla calibre")
    end

    section("Calibres of other mods: the add-on's files are the model's rendering")
    do
        local mainItems = assert(readFile(ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
        local handNames = ADDONS.readNames(assert(readFile(ROOT .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        for _, calibre in ipairs(AC_Calibres.EXTENSIONS) do
            local paths = ADDONS.extensionPaths(calibre)
            local items = strip(readFile(ROOT .. "/" .. paths.items))
            local _, itemsBody = RENDER.splitHeader(items)
            eq(itemsBody, ADDONS.extensionItemsBody(calibre, mainItems), paths.items .. " equals the rendering (run tests/write_recipes.lua)")
            local script = strip(readFile(ROOT .. "/" .. paths.script))
            local _, scriptBody = RENDER.splitHeader(script)
            eq(scriptBody, ADDONS.extensionScriptBody(calibre, RENDER), paths.script .. " equals the rendering")
            eq(strip(readFile(ROOT .. "/" .. paths.itemNames)), ADDONS.extensionItemNames(calibre, mainItems), paths.itemNames .. " equals the rendering")
            eq(strip(readFile(ROOT .. "/" .. paths.names)), ADDONS.extensionNames(calibre, handNames), paths.names .. " equals the rendering")
            -- The add-on's mod.info: the main mod and the gun mod are required.
            local root = ADDONS.EXTENSION_MODS[calibre.extension]
            local info = strip(readFile(ROOT .. "/" .. root .. "42/mod.info"))
            check(string.find(info, "id=" .. AC_Features.get(calibre.extension).mod .. "\n", 1, true) ~= nil, "its mod.info has the feature's mod id")
            check(string.find(info, "require=\\AmmoMaking,\\MarzVanillaGuns", 1, true) ~= nil, "and requires Ammo Making and Vanilla Weapons Plus")
            local version = string.match(strip(readFile(ROOT .. "/mod/AmmoMaking/42/mod.info")), "modversion=([^\n]+)")
            check(string.find(info, "modversion=" .. version, 1, true) ~= nil, "the same version as the main mod")
            check(string.find(info, "pack=", 1, true) == nil and string.find(info, "tiledef=", 1, true) == nil, "no tile sheet")
            -- Recipes count: four steps, regrind, anneal, four casts, the cast assembly, the lube.
            local parsed = parseScript(ROOT .. "/" .. paths.script)
            eq(#parsed.blocks, 12, "twelve recipes in the add-on's script")
        end
    end

    section("Calibres of other mods: with the add-on in the game (mocked engine)")
    do
        local saved = MOCK.activeMods
        MOCK.activeMods = { "AmmoMaking", "AmmoMakingCalibre762x39", "MarzVanillaGuns" }
        T.reloadMod()
        local ext = AC_Calibres.get("7.62x39")
        check(ext ~= nil, "the calibre is in the game")
        eq(AC_Features.hasContent("calibre762x39"), true, "the add-on's content is in")
        eq(#AC_Calibres.ALL, #AC_Calibres.LIST + 1, "ALL holds it")
        eq(#AC_Calibres.LIST, 9, "LIST stays the nine vanilla calibres: press, spent cases, loot and recycling are untouched")
        eq(AC_Calibres.identify("Base.762Bullets"), "round", "its round is a round")
        eq(AC_Calibres.identify(ext.case), "case", "its case a case")
        eq(AC_Calibres.identify(ext.castBullet), "castBullet", "its cast bullet a cast bullet")
        -- Every recipe of the add-on's script is listed, with its callback.
        local listed = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do listed[recipe.id] = recipe end
        local paths = ADDONS.extensionPaths(ext)
        for _, block in ipairs(parseScript(ROOT .. "/" .. paths.script).blocks) do
            local recipe = listed[block.name]
            check(recipe ~= nil, block.name .. " is listed by AC_Materials")
            if recipe then
                check(type(AC_Materials[recipe.callback]) == "function", block.name .. ": its OnCreate callback exists")
                check(AC_Materials.checkConservation(recipe), block.name .. " conserves material")
            end
        end
        -- Units: its items are tracked like the vanilla rifles'.
        check(AC_Materials.UNITS[ext.case] ~= nil and AC_Materials.UNITS[ext.bullet] ~= nil and AC_Materials.UNITS[ext.castBullet] ~= nil, "its case and bullets carry material units")
        check(AC_Materials.UNITS[ext.round] ~= nil, "and its round")
        -- The press and the spent cases know nothing of it.
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.calibre == ext.id then
                check(recipe.step ~= "resize" and recipe.step ~= "clean" and not string.find(recipe.id, AC_Calibres.PRESS.idSuffix, 1, true), recipe.id .. " is no press or spent-case recipe")
            end
        end
        -- Its cast round takes a gas check, like the vanilla rifles.
        local assemble = listed["AmmoMaking_AssembleCastRound" .. ext.suffix]
        eq(assemble.inputs[#assemble.inputs].items[1], AC_Casting.GAS_CHECK.item, "its cast round takes a gas check")
        eq(#AC_Calibres.validate(AC_Calibres.ALL), 0, "ALL is sound: " .. table.concat(AC_Calibres.validate(AC_Calibres.ALL), "; "))
        MOCK.activeMods = saved
        T.reloadMod()
        eq(#AC_Calibres.ALL, #AC_Calibres.LIST, "(and back without the add-on)")
    end
end
