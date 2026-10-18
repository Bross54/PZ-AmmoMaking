-- Ammo Making - offline tests: calibres of other mods (AC_Calibres.EXTENSIONS)
-- and their add-ons, one per gun mod (tests/render_addons.lua,
-- EXTENSION_PACKS).
--
-- Loaded by tests/run_tests.lua. The add-ons' scripts are generated; here
-- they are held to the model, every pack is checked with its add-on in the
-- game and out of it, and the vanilla calibres are shown to be untouched
-- either way. The round ids and AmmoType keys were read from the gun mods'
-- installed files (Workshop 3773834525, 3761077099, 3773858287, 3616176188,
-- 3238830225, 3633421539); that each add-on loads beside its gun mod is
-- REQUIRES FUTURE IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK
    local readFile, ROOT, parseScript = T.readFile, T.ROOT, T.parseScript

    local ADDONS = dofile(ROOT .. "/tests/render_addons.lua")
    local RENDER = T.RENDER

    local function strip(text) return (string.gsub(text or "", "\r", "")) end

    section("Calibres of other mods: the model, absent unless an add-on is in the game (pure)")
    do
        local E = AC_Calibres.EXTENSIONS
        eq(#E, 58, "58 calibres of eight gun mods")
        eq(#ADDONS.EXTENSION_PACKS, 9, "nine add-ons")
        eq(#AC_Calibres.ALL, #AC_Calibres.LIST, "without an add-on: only the vanilla calibres")
        local vanillaRound, ids, suffixes = {}, {}, {}
        for _, calibre in ipairs(AC_Calibres.LIST) do
            vanillaRound[calibre.round] = true
            ids[calibre.id], suffixes[calibre.suffix] = "vanilla", "vanilla"
        end
        for _, calibre in ipairs(E) do
            check(ids[calibre.id] == nil, calibre.id .. ": an id of its own")
            check(suffixes[calibre.suffix] == nil, calibre.id .. ": a suffix of its own (" .. calibre.suffix .. ")")
            ids[calibre.id], suffixes[calibre.suffix] = true, true
            check(not vanillaRound[calibre.round], calibre.id .. ": not a vanilla round")
            eq(AC_Calibres.identify(calibre.round), nil, calibre.id .. ": nothing to the mod without its add-on")
            check(#AC_Calibres.extensionFeatures(calibre) >= 1, calibre.id .. " comes with an add-on")
            for _, feature in ipairs(AC_Calibres.extensionFeatures(calibre)) do
                check(ADDONS.getPack(feature) ~= nil, calibre.id .. ": its add-on " .. feature .. " is a pack")
            end
            check(string.find(calibre.round, "Bullets22", 1, true) == nil and calibre.round ~= "Base.22Bullets", calibre.id .. ": no rimfire round")
        end
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            check(not AC_Calibres.get(recipe.calibre or "") or AC_Calibres.get(recipe.calibre).extension == nil, recipe.id .. " is not of an extension")
        end
        -- The packs that may be loaded together never give one round two calibres.
        for _, pack in ipairs(ADDONS.EXTENSION_PACKS) do
            local list = ADDONS.packCalibres(pack)
            check(#list >= 1, pack.feature .. " has calibres")
            eq(#AC_Calibres.validate(list), 0, pack.feature .. ": its calibres are sound: " .. table.concat(AC_Calibres.validate(list), "; "))
            local mod = AC_Features.get(pack.feature).mod
            for _, other in ipairs(ADDONS.EXTENSION_PACKS) do
                if other ~= pack then
                    local blocked = false
                    for _, id in ipairs(pack.incompatible) do
                        if id == AC_Features.get(other.feature).mod then blocked = true end
                    end
                    local reverse = false
                    for _, id in ipairs(other.incompatible) do
                        if id == mod then reverse = true end
                    end
                    eq(blocked, reverse, pack.feature .. " and " .. other.feature .. ": incompatibility is declared on both sides")
                    if not blocked then
                        local rounds = {}
                        for _, calibre in ipairs(list) do rounds[calibre.round] = calibre.id end
                        for _, calibre in ipairs(ADDONS.packCalibres(other)) do
                            local mine = rounds[calibre.round]
                            check(mine == nil or mine == calibre.id, pack.feature .. " and " .. other.feature .. " may load together: " .. calibre.round .. " is one calibre in both")
                        end
                    end
                end
            end
        end
        -- Base.762Bullets: 7.62x39 for Vanilla Weapons Plus and VFE, 7.62x51 for Rain's.
        local seen = {}
        for _, calibre in ipairs(E) do
            if calibre.round == "Base.762Bullets" then table.insert(seen, calibre.id) end
        end
        eq(table.concat(seen, ","), "7.62x39,7.62x51", "Base.762Bullets is two calibres, kept apart by incompatible=")
    end

    section("Calibres of other mods: every add-on's files are the model's rendering")
    do
        local mainItems = assert(readFile(ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))
        local handNames = ADDONS.readNames(assert(readFile(ROOT .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        local version = string.match(strip(readFile(ROOT .. "/mod/AmmoMaking/42/mod.info")), "modversion=([^\n]+)")
        for _, pack in ipairs(ADDONS.EXTENSION_PACKS) do
            local calibres = ADDONS.packCalibres(pack)
            local paths = ADDONS.packPaths(pack)
            local _, itemsBody = RENDER.splitHeader(strip(readFile(ROOT .. "/" .. paths.items)))
            eq(itemsBody, ADDONS.extensionItemsBody(calibres, mainItems), paths.items .. " equals the rendering (run tests/write_recipes.lua)")
            local _, scriptBody = RENDER.splitHeader(strip(readFile(ROOT .. "/" .. paths.script)))
            eq(scriptBody, ADDONS.extensionScriptBody(calibres, RENDER, pack), paths.script .. " equals the rendering")
            eq(strip(readFile(ROOT .. "/" .. paths.itemNames)), ADDONS.extensionItemNames(calibres, mainItems), paths.itemNames .. " equals the rendering")
            eq(strip(readFile(ROOT .. "/" .. paths.names)), ADDONS.extensionNames(calibres, handNames, pack), paths.names .. " equals the rendering")
            local info = strip(readFile(ROOT .. "/" .. paths.info))
            eq(info, ADDONS.packInfo(pack, version), paths.info .. " equals the rendering")
            check(string.find(info, "require=\\AmmoMaking,\\" .. pack.requires .. "\n", 1, true) ~= nil, pack.feature .. ": requires Ammo Making and its gun mod")
            check(string.find(info, "pack=", 1, true) == nil and string.find(info, "tiledef=", 1, true) == nil, pack.feature .. ": no tile sheet")
            check(readFile(ROOT .. "/" .. pack.root .. "42/poster.png") ~= nil, pack.feature .. " has a poster")
            local bridged = pack.casingBridge and #AC_SpentCases.buildCasingBridgeRecipes(pack.casingBridge) or 0
            local extras, pressed = 0, 0
            for _, calibre in ipairs(calibres) do
                extras = extras + #AC_Calibres.buildExtensionExtras(calibre)
                pressed = pressed + #AC_Calibres.buildPressRecipes(calibre)
            end
            eq(pressed, 4 * #calibres, pack.feature .. ": every calibre has its four press recipes (case, bullet, assembly, cast assembly)")
            eq(extras, 7 * #calibres, pack.feature .. ": and three for its spent cases (resize, clean, scrap)")
            eq(#parseScript(ROOT .. "/" .. paths.script).blocks, 12 * #calibres + extras + bridged, pack.feature .. ": twelve recipes per calibre, its press and spent-case recipes, and its gun mod's casings resized")
        end
    end

    section("Calibres of other mods: what each pack expects is in its gun mod, as installed (recorded)")
    do
        -- tools/pz_compat.py reads the installed gun mods into
        -- tests/engine_snapshot.lua (gunMods): no mock. A round two gun mods
        -- share is the same item under each mod's own AmmoType
        -- (AC_Calibres.ammoTypeOf).
        local recorded = T.ENGINE.gunMods or {}
        local judged = 0
        for _, pack in ipairs(ADDONS.EXTENSION_PACKS) do
            local mod = recorded[pack.requires]
            check(mod ~= nil, pack.feature .. ": its gun mod " .. pack.requires .. " is in the snapshot")
            if mod and mod.installed then
                judged = judged + 1
                for _, calibre in ipairs(ADDONS.packCalibres(pack)) do
                    eq(mod.rounds[calibre.round], true, pack.feature .. ": " .. pack.requires .. " defines " .. calibre.round .. " (" .. calibre.id .. ")")
                    local key = AC_Calibres.ammoTypeOf(calibre, pack.feature)
                    check((mod.ammoTypes[key] or 0) > 0, pack.feature .. ": a firearm of " .. pack.requires .. " fires " .. calibre.id .. " as " .. key)
                end
                if pack.casingBridge then
                    for _, recipe in ipairs(AC_SpentCases.buildCasingBridgeRecipes(pack.casingBridge)) do
                        local casing = recipe.inputs[1].items[1]
                        eq(mod.casings[casing], true, pack.feature .. ": " .. pack.requires .. " defines the casing " .. casing)
                    end
                end
            end
        end
        check(judged >= 1, "at least one gun mod was installed when the snapshot was recorded (" .. judged .. ")")
        -- The shared rounds this was found on (2026-10-18).
        local function byId(id) for _, c in ipairs(AC_Calibres.EXTENSIONS) do if c.id == id then return c end end end
        eq(AC_Calibres.ammoTypeOf(byId("7.62x39"), "packVFE"), "vfe:bullets_762", "VFE's 7.62x39 key is VFE's own")
        eq(AC_Calibres.ammoTypeOf(byId("7.62x39"), "calibre762x39"), "mvgi:bullets_762", "Vanilla Weapons Plus keeps its own")
        eq(AC_Calibres.ammoTypeOf(byId(".223"), "packRains"), "firearms:bullets_223", "Rain's .223 key is Rain's own")
        eq(AC_Calibres.ammoTypeOf(byId("7.62x39 M43"), "packGaelGunStore"), "ggs:762x39_bullets", "GaelGunStore's 7.62x39 key is its own")
        eq(AC_Calibres.ammoTypeOf(byId(".50 BMG"), "packMFS"), "efk:cat_bullets50", "MFS's .50 key is its own")
    end

    section("Calibres of other mods: each add-on in the game (mocked engine)")
    do
        local saved = MOCK.activeMods
        for _, pack in ipairs(ADDONS.EXTENSION_PACKS) do
            MOCK.activeMods = { "AmmoMaking", AC_Features.get(pack.feature).mod, pack.requires }
            T.reloadMod()
            local calibres = ADDONS.packCalibres(pack)
            eq(#AC_Calibres.ALL, #AC_Calibres.LIST + #calibres, pack.feature .. ": ALL holds its calibres")
            eq(#AC_Calibres.LIST, 9, pack.feature .. ": LIST stays the nine vanilla calibres")
            eq(#AC_Calibres.validate(AC_Calibres.ALL), 0, pack.feature .. ": ALL is sound: " .. table.concat(AC_Calibres.validate(AC_Calibres.ALL), "; "))
            local listed = {}
            for _, recipe in ipairs(AC_Materials.RECIPES) do listed[recipe.id] = recipe end
            for _, block in ipairs(parseScript(ROOT .. "/" .. ADDONS.packPaths(pack).script).blocks) do
                local recipe = listed[block.name]
                check(recipe ~= nil, block.name .. " is listed by AC_Materials")
                if recipe then
                    check(type(AC_Materials[recipe.callback]) == "function", block.name .. ": its OnCreate callback exists")
                    check(AC_Materials.checkConservation(recipe), block.name .. " conserves material")
                end
            end
            for _, calibre in ipairs(calibres) do
                eq(AC_SpentCases.getSpentCaseForRound(calibre.round), calibre.spentCase, calibre.id .. ": a shot of its round leaves its spent case (with the spent cases add-on on)")
                check(AC_Materials.UNITS[calibre.spentCase] ~= nil, calibre.id .. ": its spent case carries units")
                eq(AC_Calibres.identify(calibre.round), "round", calibre.id .. ": its round is a round")
                check(AC_Materials.UNITS[calibre.case] ~= nil and AC_Materials.UNITS[calibre.castBullet] ~= nil, calibre.id .. ": its case and cast bullet carry units")
                local gas = AC_Calibres.CLASSES[calibre.class].gasCheck == true
                local assemble = listed["AmmoMaking_AssembleCastRound" .. calibre.suffix]
                eq(assemble and assemble.inputs[#assemble.inputs].items[1] == AC_Casting.GAS_CHECK.item, gas, calibre.id .. ": a gas check exactly when a rifle")
            end
            for _, recipe in ipairs(AC_Materials.RECIPES) do
                if recipe.calibre and AC_Calibres.get(recipe.calibre).extension then
                    if recipe.step == "resize" or recipe.step == "clean" then
                        eq(AC_Calibres.get(recipe.calibre).spentCase, recipe.inputs[1].items[1], recipe.id .. ": takes the pack calibre's own spent case")
                    end
                    if string.find(recipe.id, AC_Calibres.PRESS.idSuffix, 1, true) then
                        check(recipe.press and recipe.benchTag == AC_Calibres.PRESS.benchTag, recipe.id .. ": a press recipe of the pack, at the press's station")
                    end
                end
            end
        end
        -- Modern Firearms System's Base.Bullets38 is a 6.8mm: a WARNING, nothing changed.
        MOCK.activeMods = { "AmmoMaking", "ModernFirearmsSystem" }
        T.reloadMod()
        local results = {}
        AC_Compat.checkRoundOverrides(results)
        eq(#results, 1, "beside MFS: one warning")
        eq(results[1] and results[1].status, "WARNING", "a WARNING")
        check(results[1] and string.find(results[1].label, "6.8mm", 1, true) ~= nil, "naming the 6.8mm")
        MOCK.activeMods = saved
        T.reloadMod()
        local none = {}
        AC_Compat.checkRoundOverrides(none)
        eq(#none, 0, "without MFS: none")
        eq(#AC_Calibres.ALL, #AC_Calibres.LIST, "(and back without the add-ons)")

        -- Other ammunition-making mods: one WARNING each, nothing changed.
        local seenIds = {}
        for _, other in ipairs(AC_Compat.OVERLAPPING_MODS) do
            check(type(other.mod) == "string" and other.mod ~= "" and not seenIds[other.mod], "an overlapping mod has an id of its own: " .. tostring(other.mod))
            seenIds[other.mod] = true
            check(string.match(other.workshop or "", "^%d+$") ~= nil, other.name .. ": its Workshop item is named")
        end
        check(seenIds.ammomaker and seenIds.ammocraft and seenIds.AmmoCraft, "Ammo Maker, Ammocraft and Ammo Craft are told apart (ids differ in case)")
        MOCK.activeMods = { "AmmoMaking", "ammomaker", "LoadIt" }
        local overlap = {}
        AC_Compat.checkOverlappingMods(overlap)
        eq(#overlap, 2, "beside Ammo Maker and Load It!: two warnings")
        eq(overlap[1] and overlap[1].status, "WARNING", "a WARNING")
        check(overlap[1] and string.find(overlap[1].label, "Ammo Maker is active", 1, true) ~= nil, "naming the mod")
        MOCK.activeMods = { "AmmoMaking", "AmmoCraft" }
        overlap = {}
        AC_Compat.checkOverlappingMods(overlap)
        check(#overlap == 1 and string.find(overlap[1].label, "Ammo Craft is active", 1, true) ~= nil, "AmmoCraft is Ammo Craft, not Ammocraft")
        MOCK.activeMods = saved
        overlap = {}
        AC_Compat.checkOverlappingMods(overlap)
        eq(#overlap, 0, "alone: none")
    end

    section("Calibres of other mods: their die sets as loot, on a budget of their own (pure)")
    do
        local L, VANILLA = AC_Loot, T.VANILLA
        local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
        eq(#L.buildExtensionEntries(), 0, "no pack in the game: no extension die set in any list")
        -- The worst case: every extension calibre at once, though some packs
        -- cannot be loaded together.
        local entries = L.buildExtensionEntries(nil, AC_Calibres.EXTENSIONS)
        check(#entries > #AC_Calibres.EXTENSIONS, "every extension die set goes into at least one list (" .. #entries .. ")")
        local perList, vanillaPerList = {}, {}
        for _, entry in ipairs(entries) do
            eq(entry.extension, true, entry.item .. " is marked an extension entry")
            check(entry.weight > 0 and entry.weight <= L.CONFIG.maxWeight, entry.item .. " in " .. entry.list .. ": within a die set's limit")
            perList[entry.list] = (perList[entry.list] or 0) + entry.weight
        end
        for _, entry in ipairs(L.buildEntries()) do vanillaPerList[entry.list] = (vanillaPerList[entry.list] or 0) + entry.weight end
        local scaleOf = {}
        for _, target in ipairs(L.TARGETS) do scaleOf[target.list] = target.scale end
        for list, weight in pairs(perList) do
            local cap = L.CONFIG.extensionListWeight * scaleOf[list]
            check(weight <= cap + 1e-9, list .. ": all extension die sets together at most " .. cap .. " (" .. string.format("%.3f", weight) .. ")")
        end
        -- Per ROOM, the vanilla die sets and the extension ones together, at
        -- the default and the die-set multiplier's maximum: twelve containers
        -- filled from a list hold at most one die set on average.
        local die = AC_Balance.getOption("dieSetLoot")
        for _, target in ipairs(L.TARGETS) do
            local each = VANILLA.loot.lists[target.list].rolls * ((vanillaPerList[target.list] or 0) + (perList[target.list] or 0)) / 100
            for _, user in ipairs(VANILLA.loot.users[target.list] or {}) do
                local most = 0
                for _, size in ipairs(BALANCE.LOOT_ROOM_SIZES) do
                    most = math.max(most, BALANCE.expectedUses(user.lists, target.list, size) * each)
                end
                check(most <= 1, target.list .. " in " .. user.container .. ": with every pack, twelve containers hold at most one die set (" .. string.format("%.3f", most) .. ")")
                check(most * die.max <= 2, target.list .. " in " .. user.container .. ": and at the multiplier's maximum x" .. die.max .. " at most two, the vanilla die sets' bound (" .. string.format("%.3f", most * die.max) .. ")")
            end
        end
        -- In the game: a pack's die sets are registered beside the vanilla ones.
        local saved = MOCK.activeMods
        local pack = ADDONS.getPack("packRealFirearms")
        MOCK.activeMods = { "AmmoMaking", AC_Features.get(pack.feature).mod, pack.requires }
        T.reloadMod()
        local active = L.buildExtensionEntries()
        check(#active > 0, "with the Real Firearms pack: its die sets are loot")
        local lists, distribution = T.mockProceduralLists(), T.mockDistribution()
        local summary = L.register(lists, distribution)
        eq(summary.added, #L.buildEntries() + #active, "registered with the vanilla die sets")
        MOCK.activeMods = saved
        T.reloadMod()
    end

    section("Hot Brass bridge: its casings resized at the die set like spent cases")
    do
        local handNames = ADDONS.readNames(assert(readFile(ROOT .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json")))
        local version = string.match(strip(readFile(ROOT .. "/mod/AmmoMaking/42/mod.info")), "modversion=([^\n]+)")
        local _, body = RENDER.splitHeader(strip(readFile(ROOT .. "/" .. ADDONS.HOT_BRASS_SCRIPT)))
        eq(body, ADDONS.hotBrassScriptBody(RENDER), "AC_HotBrassRecipes.txt equals the rendering")
        eq(strip(readFile(ROOT .. "/" .. ADDONS.HOT_BRASS_NAMES)), ADDONS.hotBrassNames(handNames), "its names equal the rendering")
        eq(strip(readFile(ROOT .. "/" .. ADDONS.HOT_BRASS_INFO)), ADDONS.hotBrassInfo(version), "its mod.info equals the rendering")
        local recipes = AC_SpentCases.buildHotBrassRecipes()
        eq(#recipes, #AC_Calibres.LIST, "one resizing per vanilla calibre")
        for _, recipe in ipairs(recipes) do
            local calibre = AC_Calibres.get(recipe.calibre)
            eq(recipe.inputs[1].items[1], calibre.hotBrassCasing, recipe.id .. " takes the Hot Brass casing")
            eq(string.sub(calibre.hotBrassCasing, 1, 7), "HBVCEF.", recipe.id .. ": a Hot Brass item")
            eq(recipe.inputs[1].count, AC_SpentCases.RESIZE.spentPerCase, recipe.id .. ": two for one, like a spent case")
            eq(recipe.effect, "resizedCaseQuality", recipe.id .. ": the resized malus")
            eq(recipe.xp, 0, recipe.id .. ": no XP")
        end
        local saved = MOCK.activeMods
        MOCK.activeMods = { "AmmoMaking", "AmmoMakingHotBrass", "HBVCEFb42" }
        T.reloadMod()
        local listed = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do listed[recipe.id] = recipe end
        for _, recipe in ipairs(AC_SpentCases.buildHotBrassRecipes()) do
            local mine = listed[recipe.id]
            check(mine ~= nil and type(AC_Materials[mine.callback]) == "function", recipe.id .. " is listed with its callback")
            check(mine and AC_Materials.checkConservation(mine), recipe.id .. " loses brass, never makes it")
            check(AC_Materials.UNITS[recipe.inputs[1].items[1]] ~= nil, recipe.id .. ": its casing carries brass units")
        end
        MOCK.activeMods = saved
        T.reloadMod()
    end
end
