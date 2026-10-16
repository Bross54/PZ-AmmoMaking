-- Ammo Making - offline tests: the balance options of the save (AC_Balance).
--
-- Loaded by tests/run_tests.lua. Pure logic: the option table, the clamp,
-- what each multiplier does to the mod's own numbers, and that the XP and
-- material rules of the mod hold at every allowed extreme. Mocked engine:
-- that the options arrive in SandboxVars, that the engine reads the loot
-- tables again when ItemPickerJava.Parse() is called, and that it applies
-- MultiplierConfig.AmmoMaking to Ammo Making XP are REQUIRES FUTURE IN-GAME
-- VERIFICATION.

return function(T)
    local check, eq, section, MOCK, VANILLA = T.check, T.eq, T.section, T.MOCK, T.VANILLA
    local readFile = T.readFile

    local function with(values, action)
        local saved = SandboxVars
        SandboxVars = values
        local ok, err = pcall(action)
        SandboxVars = saved
        if not ok then error(err, 0) end
    end

    section("Balance options: four multipliers, default 1, checked in one place")
    do
        local B = AC_Balance
        eq(#B.validate(), 0, "the option table is sound: " .. table.concat(B.validate(), "; "))

        -- Pinned: what a server owner can change, and how far. A change
        -- here is a balance decision (docs/BALANCE_OPTIONS.md).
        local expected = {
            { "depositReserve", "AmmoMaking", "DepositReserveMultiplier", 0.5, 3.0, "lua" },
            { "dieSetLoot", "AmmoMaking", "DieSetLootMultiplier", 0.0, 2.0, "lua" },
            { "componentLoot", "AmmoMaking", "ComponentLootMultiplier", 0.0, 2.0, "lua" },
            { "xp", "MultiplierConfig", "AmmoMaking", 0.0, 1000.0, "engine" },
        }
        eq(#B.OPTIONS, #expected, "four balance options")
        for index, want in ipairs(expected) do
            local option = B.OPTIONS[index]
            eq(option.id, want[1], "option " .. index .. " is " .. want[1])
            eq(option.table .. "." .. option.option, want[2] .. "." .. want[3], want[1] .. " arrives as SandboxVars." .. want[2] .. "." .. want[3])
            eq(option.min, want[4], want[1] .. " from " .. want[4])
            eq(option.max, want[5], want[1] .. " to " .. want[5])
            eq(option.default, 1, want[1] .. " defaults to 1: today's balance")
            eq(option.appliedBy, want[6], want[1] .. " is applied by the " .. want[6])
            eq(B.getOption(want[1]), option, want[1] .. " is found by id")
        end
        eq(B.getOption("recycling"), nil, "recycling yield is not an option")

        -- No setting: every multiplier is 1, and nothing is reported.
        with({}, function()
            for _, option in ipairs(B.OPTIONS) do
                eq(B.get(option.id), 1, option.id .. ": 1 without a sandbox table")
                eq(B.isDefault(option.id), true, option.id .. " is at its default")
            end
            eq(B.describeChanges(), nil, "nothing to report")
        end)
        with(nil, function() eq(B.get("dieSetLoot"), 1, "no SandboxVars at all: 1") end)
        with({ AmmoMaking = "broken", MultiplierConfig = 7 }, function()
            for _, option in ipairs(B.OPTIONS) do eq(B.get(option.id), 1, option.id .. ": a broken table is no setting") end
        end)
        eq(B.get("nope"), 1, "an unknown id changes nothing")
        eq(B.isDefault("nope"), false, "and is not an option")

        -- The clamp, for every option: inside the range a value is used as
        -- it is, outside it is pulled to the nearest end, and what is not a
        -- finite number is no setting.
        for _, option in ipairs(B.OPTIONS) do
            local function set(value)
                local tables = { AmmoMaking = {}, MultiplierConfig = {} }
                tables[option.table][option.option] = value
                return tables
            end
            local middle = (option.min + option.max) / 2
            with(set(middle), function() eq(B.get(option.id), middle, option.id .. ": " .. middle .. " is used") end)
            with(set(option.min), function() eq(B.get(option.id), option.min, option.id .. ": the minimum is allowed") end)
            with(set(option.max), function() eq(B.get(option.id), option.max, option.id .. ": the maximum is allowed") end)
            with(set(option.max + 1), function() eq(B.get(option.id), option.max, option.id .. ": above the range is clamped to the maximum") end)
            with(set(option.max * 1000 + 5), function() eq(B.get(option.id), option.max, option.id .. ": far above too") end)
            with(set(option.min - 1), function() eq(B.get(option.id), option.min, option.id .. ": below the range is clamped to the minimum") end)
            for _, value in ipairs({ "2", true, {}, 0 / 0, math.huge, -math.huge }) do
                with(set(value), function() eq(B.get(option.id), 1, option.id .. ": " .. tostring(value) .. " is no setting") end)
            end
        end
        with({ AmmoMaking = { DieSetLootMultiplier = 0.5 } }, function()
            eq(B.describeChanges(), "AmmoMaking.DieSetLootMultiplier = 0.5", "a changed option is reported by its sandbox name")
            eq(B.isDefault("dieSetLoot"), false, "and is not at its default")
        end)

        -- The validator refuses what would change a save that never set
        -- an option, and a range that cannot hold its default.
        local function refuses(what, change, text)
            local saved = {}
            for index, option in ipairs(B.OPTIONS) do
                saved[index] = {}
                for key, value in pairs(option) do saved[index][key] = value end
            end
            change(B.OPTIONS)
            local found = table.concat(B.validate(), "; ")
            for index, copy in ipairs(saved) do
                for key in pairs(B.OPTIONS[index]) do B.OPTIONS[index][key] = nil end
                for key, value in pairs(copy) do B.OPTIONS[index][key] = value end
            end
            check(string.find(found, text, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
        end
        refuses("a default other than 1", function(o) o[1].default = 1.5 end, "must default to 1")
        refuses("a range that excludes 1", function(o) o[2].max = 0.5 end, "must default to 1")
        refuses("a negative minimum", function(o) o[3].min = -1 end, "needs a range from 0 or more")
        refuses("an upside-down range", function(o) o[1].min = 4 end, "needs a range")
        refuses("a doubled id", function(o) o[2].id = o[1].id end, "is declared twice")
        refuses("a doubled sandbox name", function(o) o[2].option = o[1].option end, "is used twice")
        refuses("an option nobody applies", function(o) o[4].appliedBy = "nobody" end, "must say who applies it")
        eq(#B.validate(), 0, "and the table is sound again")

        -- The sandbox file declares exactly these options, with the same
        -- range and default, each with a label and a tooltip.
        local options = readFile(T.ROOT .. "/mod/AmmoMaking/42/media/sandbox-options.txt")
        local texts = {}
        for key, value in string.gmatch(readFile(T.TRANSLATE .. "Sandbox.json"), '"([^"]+)"%s*:%s*"([^"]*)"') do texts[key] = value end
        for _, option in ipairs(B.OPTIONS) do
            local name = option.table .. "." .. option.option
            local body = string.match(options, "option%s+" .. string.gsub(name, "%.", "%%.") .. "%s*(%b{})")
            check(body ~= nil, name .. " is declared in the sandbox file")
            body = body or ""
            eq(string.match(body, "type%s*=%s*(%a+)"), "double", name .. " is a decimal number")
            eq(tonumber(string.match(body, "min%s*=%s*([%d%.]+)")), option.min, name .. ": the file's minimum is the clamp's")
            eq(tonumber(string.match(body, "max%s*=%s*([%d%.]+)")), option.max, name .. ": the file's maximum is the clamp's")
            eq(tonumber(string.match(body, "default%s*=%s*([%d%.]+)")), option.default, name .. ": the file's default is 1")
            eq(string.match(body, "page%s*=%s*([%w_]+)"), "AmmoMaking", name .. " is on the mod's page")
            local translation = string.match(body, "translation%s*=%s*([%w_]+)")
            check(texts["Sandbox_" .. tostring(translation)] ~= nil, name .. " has a label")
            check(texts["Sandbox_" .. tostring(translation) .. "_tooltip"] ~= nil, name .. " has a tooltip")
        end
        check(string.find(texts.Sandbox_AmmoMaking_XPMultiplier_tooltip or "", "global XP multiplier is switched off", 1, true) ~= nil, "the XP tooltip says when the engine uses it")

        -- One place reads them: no other mod file names an option, and no
        -- mod Lua multiplies XP (the engine does).
        for _, name in ipairs(MOCK.MOD_FILES) do
            if name ~= "shared/AC_Balance" then
                local source = readFile(T.LUA .. name .. ".lua")
                for _, option in ipairs(B.OPTIONS) do
                    if option.table == "AmmoMaking" then
                        check(string.find(source, option.option, 1, true) == nil, name .. " does not read " .. option.option .. " itself")
                    end
                end
                check(string.find(source, "MultiplierConfig", 1, true) == nil, name .. " does not touch the XP multiplier")
            end
        end
        with({ MultiplierConfig = { AmmoMaking = 1000, Global = 5, GlobalToggle = false } }, function()
            local player = MOCK.newPlayer()
            AmmoMakingSkill.awardXP(player, 7, "test")
            eq(player.xpLog[#player.xpLog], 7, "the mod hands the engine the XP unscaled, whatever the multiplier: it is never applied twice")
        end)
    end

    section("Balance options: ore per deposit tile")
    do
        local D = AC_Deposits
        local grades = { { 0, "None", 0 }, { 10, "Trace", 0 }, { 20, "Poor", 1 }, { 40, "Moderate", 1 }, { 60, "Good", 2 }, { 75, "Rich", 3 }, { 90, "Very Rich", 4 } }
        -- At the default the reserves are the table's, exactly.
        with({}, function()
            for _, grade in ipairs(grades) do
                eq(D.getReserveForConcentration(grade[1]), D.CONFIG.reserveByGrade[grade[2]], grade[2] .. ": the table's reserve at the default")
                eq(D.getReserveForConcentration(grade[1]), grade[3], grade[2] .. " holds " .. grade[3])
            end
        end)
        -- Scaled and rounded; a workable grade keeps one unit, an
        -- unworkable one none, at every allowed value.
        local scaled = {
            [0.5] = { 0, 0, 1, 1, 1, 2, 2 },
            [1.5] = { 0, 0, 2, 2, 3, 5, 6 },
            [3.0] = { 0, 0, 3, 3, 6, 9, 12 },
        }
        for multiplier, want in pairs(scaled) do
            with({ AmmoMaking = { DepositReserveMultiplier = multiplier } }, function()
                for index, grade in ipairs(grades) do
                    eq(D.getReserveForConcentration(grade[1]), want[index], grade[2] .. " at x" .. multiplier .. " holds " .. want[index])
                end
            end)
        end
        for _, multiplier in ipairs({ 0.5, 0.51, 0.75, 1, 1.25, 2, 2.99, 3 }) do
            for name, base in pairs(D.CONFIG.reserveByGrade) do
                local value = D.scaleReserve(base, multiplier)
                eq(value == math.floor(value), true, name .. " at x" .. multiplier .. " is whole ore")
                eq(value > 0, base > 0, name .. " at x" .. multiplier .. ": workable stays workable, unworkable stays empty")
                check(value <= math.max(1, base * multiplier + 0.5), name .. " at x" .. multiplier .. ": never more than the multiplier gives")
            end
        end
        -- The floor of one holds for any factor, not only for the
        -- option's range (a later range, or a caller of its own).
        eq(D.scaleReserve(1, 0.1), 1, "a workable grade keeps one unit even at x0.1")
        eq(D.scaleReserve(4, 0.01), 1, "and at x0.01")
        eq(D.scaleReserve(-3, 2), 0, "a negative reserve is none")
        eq(D.scaleReserve("x", 2), 0, "a reserve that is not a number is none")
        eq(D.scaleReserve(2, "x"), 2, "a multiplier that is not a number changes nothing")
        with({ AmmoMaking = { DepositReserveMultiplier = 50 } }, function()
            eq(D.getReserveForConcentration(90), 12, "a value above the range is clamped: at most x3")
        end)
        with({ AmmoMaking = { DepositReserveMultiplier = 0 } }, function()
            eq(D.getReserveForConcentration(20), 1, "a value below the range is clamped: a poor tile still holds one")
        end)

        -- A worked tile keeps its extracted count; what is left follows the
        -- reserve of the moment, never below nothing.
        MOCK.clearModData()
        local x, y
        with({}, function()
            for tx = 0, 4000 do
                for ty = 0, 80 do
                    if D.getInitialReserve(tx, ty, "copper") == 2 then x, y = tx, ty break end
                end
                if x then break end
            end
        end)
        check(x ~= nil, "a good copper tile is found")
        if x then
            with({}, function()
                D.recordExtraction(x, y, "copper", 2)
                eq(D.getRemaining(x, y, "copper"), 0, "a good tile is worked out at x1")
            end)
            with({ AmmoMaking = { DepositReserveMultiplier = 3 } }, function()
                eq(D.getExtracted(x, y, "copper"), 2, "the extracted count is the save's, whatever the option")
                eq(D.getRemaining(x, y, "copper"), 4, "at x3 four are left")
            end)
            with({ AmmoMaking = { DepositReserveMultiplier = 0.5 } }, function()
                eq(D.getRemaining(x, y, "copper"), 0, "at x0.5 nothing, and never less")
            end)
            -- Mining pays per ore, so a richer save pays per action exactly
            -- as before: the option changes walking, not the rate of XP.
            eq(AC_Mining.CONFIG.xpPerOre, 5, "an ore is worth the same XP at any multiplier")
        end
        MOCK.clearModData()
    end

    section("Balance options: loot multipliers reach the tables only once the save's options are loaded")
    do
        T.reloadMod()
        local L = AC_Loot
        local lists = T.mockProceduralLists()
        -- An item that was in a list before the mod is never the mod's to
        -- scale: vanilla's (or another mod's) weight stays.
        table.insert(lists.Hunter.items, "Base.GunPowder")
        table.insert(lists.Hunter.items, 7)
        local distribution = T.mockDistribution()
        L.registerComponents(lists, distribution)
        L.register(lists, distribution)
        local entries, components = L.buildEntries(), L.buildComponentEntries()
        eq(#L.owned, #entries + #components - 1, "every inserted entry is owned, the one already there is not")

        local function weightOf(list, item)
            local items = lists[list].items
            for index = 1, #items, 2 do
                if items[index] == item then return items[index + 1] end
            end
            return nil
        end
        local function expectWeights(dieSets, parts, what)
            for _, entry in ipairs(entries) do
                eq(weightOf(entry.list, entry.item), dieSets > 0 and entry.weight * dieSets or nil, what .. ": " .. entry.item .. " in " .. entry.list)
            end
            for _, entry in ipairs(components) do
                local want = parts > 0 and entry.weight * parts or nil
                if entry.list == "Hunter" and entry.item == "Base.GunPowder" then want = 7 end
                eq(weightOf(entry.list, entry.item), want, what .. ": " .. entry.item .. " in " .. entry.list)
            end
        end

        with({}, function()
            local summary = L.applyMultipliers(lists)
            eq(summary.changed, 0, "at the defaults nothing changes")
            expectWeights(1, 1, "default")
        end)
        with({ AmmoMaking = { DieSetLootMultiplier = 2 } }, function()
            local summary = L.applyMultipliers(lists)
            eq(summary.scaled, #entries, "x2: every die set is rescaled")
            expectWeights(2, 1, "die sets x2")
            eq(L.applyMultipliers(lists).changed, 0, "and a second pass finds nothing to do")
        end)
        with({ AmmoMaking = { DieSetLootMultiplier = 0, ComponentLootMultiplier = 0.5 } }, function()
            local summary = L.applyMultipliers(lists)
            eq(summary.removed, #entries, "x0: every die set is taken out of loot")
            eq(summary.scaled, #components - 1, "and the components are halved")
            expectWeights(0, 0.5, "die sets x0, components x0.5")
        end)
        with({ AmmoMaking = { ComponentLootMultiplier = 0 } }, function()
            local summary = L.applyMultipliers(lists)
            eq(summary.restored, #entries, "back to x1: the die sets are put back")
            expectWeights(1, 0, "components x0")
        end)
        with({ AmmoMaking = { ComponentLootMultiplier = 99, DieSetLootMultiplier = -4 } }, function()
            L.applyMultipliers(lists)
            expectWeights(0, 2, "out of range: clamped to x0 and x2")
        end)
        with({}, function()
            L.applyMultipliers(lists)
            expectWeights(1, 1, "default again")
            -- A second world load in the same Lua state: the entries are
            -- present and owned, nothing is added twice.
            local again = L.register(lists, distribution)
            eq(again.added, 0, "nothing is added twice")
            eq(#L.owned, #entries + #components - 1, "and nothing is owned twice")
        end)
        eq(L.applyMultipliers("no tables").changed, 0, "without loot tables nothing happens")

        -- The world-load order, through the real handlers: the entries go
        -- in at the pre-merge event, the multipliers at OnLoadedMapZones,
        -- and the engine reads the tables again only if a weight changed.
        local function load(values)
            T.reloadMod()
            local savedProcedural, savedDistributions = ProceduralDistributions, Distributions
            ProceduralDistributions, Distributions = { list = T.mockProceduralLists() }, { T.mockDistribution() }
            MOCK.itemPickerParses = 0
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            local result = {}
            with(values, function()
                Events.OnPreDistributionMerge.fire()
                result.afterMerge = ProceduralDistributions.list.GunStoreMagsAmmo.items[#ProceduralDistributions.list.GunStoreMagsAmmo.items]
                Events.OnLoadedMapZones.fire()
            end)
            MOCK.capturePrint(false)
            result.printed = table.concat(MOCK.printLog, "\n")
            result.parses = MOCK.itemPickerParses
            result.lists = ProceduralDistributions.list
            ProceduralDistributions, Distributions = savedProcedural, savedDistributions
            return result
        end
        local plain = load({})
        eq(plain.parses, 0, "default save: the loot tables are not read again")
        eq(AC_Loot.lastMultiplierSummary.changed, 0, "nothing was changed")
        local doubled = load({ AmmoMaking = { DieSetLootMultiplier = 2 } })
        eq(doubled.parses, 1, "a changed multiplier: the engine reads the tables again, once")
        local nine = AC_Calibres.get("9mm")
        local ninePlain, nineDoubled
        for index = 1, #plain.lists.GunStoreMagsAmmo.items, 2 do
            if plain.lists.GunStoreMagsAmmo.items[index] == nine.dieSet then ninePlain = plain.lists.GunStoreMagsAmmo.items[index + 1] end
            if doubled.lists.GunStoreMagsAmmo.items[index] == nine.dieSet then nineDoubled = doubled.lists.GunStoreMagsAmmo.items[index + 1] end
        end
        eq(nineDoubled, 2 * ninePlain, "and the 9mm die set weighs twice as much in a gun store")
        local printed = doubled.printed
        check(string.find(printed, "[AmmoMaking] Loot multipliers: die sets x2", 1, true) ~= nil, "the console says so")
        check(string.find(printed, "Balance options of this save: AmmoMaking.DieSetLootMultiplier = 2", 1, true) ~= nil, "and names the changed option")
        -- Without the engine's parser nothing raises; the weights are set.
        T.reloadMod()
        local savedPicker = ItemPickerJava
        ItemPickerJava = nil
        local ok = pcall(Events.OnLoadedMapZones.fire)
        ItemPickerJava = savedPicker
        check(ok, "the handler does not raise without ItemPickerJava")
        T.reloadMod()
    end

    section("Balance options: at every allowed extreme the loot stays rare and per room bounded")
    do
        local BALANCE = dofile(T.ROOT .. "/tests/render_balance.lua")
        local die, part = AC_Balance.getOption("dieSetLoot"), AC_Balance.getOption("componentLoot")
        local function fullest(multiplier)
            local tiers = AC_Loot.CONFIG.tierWeight
            local saved = {}
            for tier, weight in pairs(tiers) do saved[tier] = weight tiers[tier] = weight * multiplier end
            local most, store = 0, 0
            local ok, err = pcall(function()
                for _, row in ipairs(BALANCE.lootAvailability(VANILLA)) do
                    most = math.max(most, row.dieSets[#row.dieSets])
                end
                local gunStore
                for _, user in ipairs(VANILLA.loot.users.GunStoreAccessories) do
                    if user.container == "gunstore.displaycase" then gunStore = user.lists end
                end
                store = BALANCE.expectedUses(gunStore, "GunStoreMagsAmmo", 8) * BALANCE.dieSetsPerContainer(AC_Loot.TARGETS[1], VANILLA)
            end)
            for tier, weight in pairs(saved) do tiers[tier] = weight end
            if not ok then error(err, 0) end
            return most, store
        end
        local mostDefault, storeDefault = fullest(die.default)
        check(mostDefault <= 1, "at the default no room of twelve containers holds a die set on average (" .. string.format("%.3f", mostDefault) .. ")")
        local mostMax, storeMax = fullest(die.max)
        -- The per-room cap scales with the multiplier and no further: the
        -- maximum is chosen so that the fullest room of twelve holds at most
        -- two die sets, and a gun store about one time in six.
        check(mostMax <= 2, "at the maximum x" .. die.max .. " the fullest room of twelve holds at most two die sets (" .. string.format("%.3f", mostMax) .. ")")
        check(math.abs(mostMax - die.max * mostDefault) < 1e-9, "the per-room figure is linear in the multiplier")
        check(storeMax < 0.3, "a gun store of eight display cases holds a die set under three times in ten (" .. string.format("%.3f", storeMax) .. ")")
        eq(fullest(die.min), 0, "at x0 no room holds one")
        -- The engine's chance per roll stays linear (weight x 100 x loot
        -- setting far below Rand.Next(10000)): every effective weight is a
        -- few percent at most.
        for _, entry in ipairs(AC_Loot.buildEntries()) do
            check(entry.weight * die.max <= 2 * AC_Loot.CONFIG.maxWeight, entry.item .. " in " .. entry.list .. ": at most " .. 2 * AC_Loot.CONFIG.maxWeight .. " % per roll at the maximum")
        end
        for _, entry in ipairs(AC_Loot.buildComponentEntries()) do
            local facts = VANILLA.loot.lists[entry.list]
            local weight = entry.weight * part.max
            check(weight <= 2 * AC_Loot.CONFIG.maxComponentWeight, entry.item .. " in " .. entry.list .. ": at most " .. 2 * AC_Loot.CONFIG.maxComponentWeight .. " % per roll at the maximum")
            check(weight / facts.weight < 0.02, entry.item .. " in " .. entry.list .. ": under 2 % of the list's weight even at the maximum")
            check(AC_Loot.chancePerContainer(weight, facts.rolls) < 16, entry.item .. " in " .. entry.list .. ": under 16 % of the containers filled from the list hold one at the maximum")
        end
    end

    section("Balance options: no XP or material from nothing, at every allowed extreme")
    do
        -- The XP multiplier scales every Ammo Making award alike (the engine
        -- multiplies the amount the mod hands it), so the XP rules of the mod
        -- are comparisons that hold for any factor: checked at the ends of
        -- the range and between.
        local xp = AC_Balance.getOption("xp")
        local recovery = AC_Recycling.getRecovery()
        for _, factor in ipairs({ xp.min, 0.01, 1, 10, xp.max }) do
            for _, recipe in ipairs(AC_Materials.RECIPES) do
                if recipe.loss or recipe.recycling then
                    eq(AC_Materials.getRecipeXP(recipe) * factor, 0, recipe.id .. ": recycling teaches nothing at x" .. factor)
                end
            end
            for _, calibre in ipairs(AC_Calibres.LIST) do
                local primer = AC_Calibres.getPrimer(calibre.primerFamily)
                local brass = calibre.cupsPerCase * AC_Calibres.CONFIG.cupUnits
                local makeOnce = (brass / 100 * AC_Materials.CONFIG.xpForgeBrassSheets
                    + calibre.cupsPerCase / 2 * AC_Materials.CONFIG.xpPunchCaseCups
                    + calibre.xp.case) * factor
                local regained = makeOnce * recovery / (1 - recovery)
                local forgone = (calibre.xp.assemble
                    + primer.xp / primer.perSheet
                    + calibre.xp.bullet / calibre.bulletsPerScrap
                    + AC_Calibres.POWDER.xp * calibre.powderUses / AC_Calibres.POWDER.usesPerJar) * factor
                if factor > 0 then
                    check(regained < forgone, calibre.id .. " at x" .. factor .. ": re-forming a scrapped case never pays more XP than loading it")
                else
                    eq(regained + forgone, 0, calibre.id .. " at x0: no XP either way")
                end
            end
        end
        -- The material rules do not depend on any option: recovery is the
        -- recipe scripts', and no option reaches AC_Recycling.
        local extremes = {}
        for _, option in ipairs(AC_Balance.OPTIONS) do
            local low, high = { AmmoMaking = {}, MultiplierConfig = {} }, { AmmoMaking = {}, MultiplierConfig = {} }
            low[option.table][option.option] = option.min
            high[option.table][option.option] = option.max
            table.insert(extremes, low)
            table.insert(extremes, high)
        end
        for index, values in ipairs(extremes) do
            with(values, function()
                eq(AC_Recycling.getRecovery(), recovery, "extreme " .. index .. ": recycling still returns " .. recovery)
                eq(#AC_Recycling.validate(), 0, "extreme " .. index .. ": recycling still validates")
                eq(#AC_Loot.validate(), 0, "extreme " .. index .. ": the loot table still validates")
            end)
        end
    end
end
