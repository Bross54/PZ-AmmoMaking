-- Ammo Making - offline tests: component loot (AC_Loot.COMPONENTS).
--
-- Loaded by tests/run_tests.lua. The die sets have their own sections there.
-- Mocked ProceduralDistributions: the engine's parse and roll are not run,
-- and how often anything is found in the game is REQUIRES FUTURE IN-GAME
-- VERIFICATION.

return function(T)
    local check, eq, section, MOCK, VANILLA, ENGINE = T.check, T.eq, T.section, T.MOCK, T.VANILLA, T.ENGINE

    section("Component loot: a little reloading stock, centralised, rare, and never what the player manufactures")
    do
        local L = AC_Loot
        eq(#L.validateComponents(), 0, "the component table is sound: " .. table.concat(L.validateComponents(), "; "))

        -- Pinned: what can be found and where. A change here is a balance
        -- decision.
        local expected = {
            "Base.GunPowder @ GunStoreMagsAmmo 1", "Base.GunPowder @ Hunter 0.5",
            "Base.BrassScrap @ CrateMetalwork 2", "Base.BrassScrap @ CrateBlacksmithing 2",
            "AmmoMaking.SmallBrassSheet @ CrateMetalwork 1",
        }
        for _, primer in ipairs(AC_Calibres.PRIMERS) do table.insert(expected, primer.item .. " @ GunStoreMagsAmmo 1") end
        local entries = L.buildComponentEntries()
        eq(#entries, #expected, "nine component entries: gunpowder twice, brass scrap twice, a sheet, a primer of each family")
        for index, entry in ipairs(entries) do
            eq(entry.item .. " @ " .. entry.list .. " " .. entry.weight, expected[index], "component entry " .. index)
            eq(entry.component, true, "it is marked as a component")
        end

        -- Never a case, a projectile, a round or a die set; every item
        -- exists; every list is one a container names.
        local dieSets = {}
        for _, entry in ipairs(L.buildEntries()) do dieSets[entry.item] = true end
        local perList = {}
        for _, entry in ipairs(entries) do
            local what = entry.item .. " in " .. entry.list
            local kind = AC_Calibres.identify(entry.item)
            check(kind == nil or kind == "primer", what .. " is not a case, projectile, round or die set (" .. tostring(kind) .. ")")
            check(not dieSets[entry.item], what .. " is not a die set")
            check(T.declaredItems[entry.item] ~= nil or type(ENGINE.items[entry.item]) == "table", what .. ": the item exists")
            local facts = VANILLA.loot.lists[entry.list]
            check(facts ~= nil and facts.references >= 1 and facts.entries > 0, what .. ": the list is used by a container and holds items")
            check(entry.weight > 0 and entry.weight <= L.CONFIG.maxComponentWeight, what .. ": its weight is within the limit")
            perList[entry.list] = (perList[entry.list] or 0) + entry.weight
            if facts then
                -- Rare beside what the list already holds.
                check(entry.weight / facts.weight < 0.01, what .. " adds under 1 % to the list's weight")
                local chance = L.chancePerContainer(entry.weight, facts.rolls)
                check(chance < 8, what .. ": under 8 % of the containers filled from the list hold one (" .. string.format("%.1f", chance) .. " %)")
            end
        end
        for list, total in pairs(perList) do
            check(total <= L.CONFIG.maxComponentListWeight, "components weigh " .. total .. " in " .. list .. ", within the limit")
            check(total / VANILLA.loot.lists[list].weight < 0.03, "and together add under 3 % to " .. list)
        end

        -- What a find is worth: nothing here replaces the crafting loop.
        local U = AC_Materials.UNITS
        eq(U["Base.BrassScrap"].units * 10, AC_Materials.CONFIG.unitsPerIngot, "a brass scrap is a tenth of an ingot")
        eq(U["AmmoMaking.SmallBrassSheet"].units, 2 * U["AmmoMaking.BrassCaseCup"].units, "a small sheet is two case cups")
        eq(AC_Calibres.POWDER.usesPerJar, 10, "a jar of gunpowder is ten uses")
        local leastPowder, mostPowder = math.huge, 0
        for _, calibre in ipairs(AC_Calibres.LIST) do
            leastPowder, mostPowder = math.min(leastPowder, calibre.powderUses), math.max(mostPowder, calibre.powderUses)
        end
        check(10 / leastPowder <= 10 and 10 / mostPowder >= 2, "which is two to ten rounds' powder")
        -- No round can be assembled from loot alone: every calibre still
        -- needs a case and a projectile, and those are never loot.
        local lootable = {}
        for _, entry in ipairs(entries) do lootable[entry.item] = true end
        for _, calibre in ipairs(AC_Calibres.LIST) do
            check(not lootable[calibre.case] and not lootable[calibre.bullet] and not lootable[calibre.round], calibre.id .. ": its case, projectile and round are never loot")
        end

        -- Registration: appended once to mocked vanilla lists, nothing a
        -- second time, a missing list skipped and counted.
        local lists, distribution = T.mockProceduralLists(), T.mockDistribution()
        local before = {}
        for name, list in pairs(lists) do before[name] = #list.items end
        local summary = L.registerComponents(lists, distribution)
        eq(summary.added, #entries, "every component entry is added")
        eq(#summary.missing + #summary.empty + #summary.unreferenced, 0, "to lists that exist, hold items and are used")
        for list, total in pairs(perList) do
            local added, weight = 0, 0
            local items = lists[list].items
            for index = before[list] + 1, #items, 2 do
                added = added + 1
                weight = weight + items[index + 1]
            end
            eq(weight, total, list .. " gained exactly the components' weight")
        end
        local again = L.registerComponents(lists, distribution)
        eq(again.added, 0, "a second world load adds nothing")
        eq(again.present, #entries, "everything is already there")
        -- The die sets and the components do not disturb each other.
        local dieSummary = L.register(lists, distribution)
        eq(dieSummary.added, #L.buildEntries(), "the die sets register beside them")
        eq(L.registerComponents(lists, distribution).added, 0, "and the components are still there once")
        local short = T.mockProceduralLists()
        short.CrateMetalwork = nil
        local partial = L.registerComponents(short, distribution)
        eq(table.concat(partial.missing, ","), "CrateMetalwork", "a list this build does not have is named")
        eq(short.CrateMetalwork, nil, "and never created")
        eq(partial.added, #entries - 2, "the entries of the other lists are still added")
        eq(L.registerComponents(nil, nil).unavailable, true, "no loot tables at all: nothing is added, and the summary says so")

        -- Switched off with the die sets.
        L.CONFIG.enabled = false
        eq(L.registerComponents(T.mockProceduralLists(), distribution).added, 0, "loot switched off: no component is added")
        L.CONFIG.enabled = true

        -- validateComponents() refuses what would make loot a shortcut.
        local function refused(what, change, needle)
            local copy = {}
            for index, component in ipairs(L.COMPONENTS) do
                copy[index] = { item = component.item, list = component.list, weight = component.weight, what = component.what }
            end
            change(copy)
            local found = table.concat(L.validateComponents(copy), "; ")
            check(string.find(found, needle, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
            return copy
        end
        local nine = AC_Calibres.get("9mm")
        refused("a case as loot", function(c) c[1].item = nine.case end, "is a case")
        refused("a projectile as loot", function(c) c[1].item = nine.bullet end, "is a bullet")
        refused("a finished round as loot", function(c) c[1].item = nine.round end, "is a round")
        refused("a die set in the component table", function(c) c[1].item = nine.dieSet end, "is a dieSet")
        refused("a common component", function(c) c[1].weight = 25 end, "at most " .. L.CONFIG.maxComponentWeight)
        refused("a component with no weight", function(c) c[1].weight = 0 end, "more than 0")
        refused("the same component twice in a list", function(c) c[2].list = c[1].list end, "more than once")
        refused("a component without a list", function(c) c[1].list = "" end, "needs an item and a list")
        refused("a list flooded with components", function(c)
            for index = 1, 4 do table.insert(c, { item = "Base.Item" .. index, list = "CrateMetalwork", weight = 2 }) end
        end, "above " .. L.CONFIG.maxComponentListWeight)
        -- A component table that does not validate registers nothing.
        local saved = L.COMPONENTS[1].weight
        L.COMPONENTS[1].weight = 25
        eq(L.registerComponents(T.mockProceduralLists(), distribution).added, 0, "a component table that does not validate adds nothing")
        L.COMPONENTS[1].weight = saved

        -- The document's table is generated from the same data.
        local BALANCE = dofile(T.ROOT .. "/tests/render_balance.lua")
        local document = T.readFile(T.ROOT .. "/docs/LOOT_AND_RECYCLING.md")
        local from = string.find(document, BALANCE.COMPONENT_LOOT_START, 1, true)
        local _, to = string.find(document, BALANCE.COMPONENT_LOOT_FINISH, 1, true)
        check(from ~= nil and to ~= nil and to > from, "the loot document has the component table markers")
        eq(string.sub(document, from or 1, to or 1), BALANCE.renderComponentLootBlock(VANILLA), "the component loot table equals the rendered model (run tests/write_recipes.lua)")

        -- The game-start check reports it.
        local ids = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
        MOCK.resetCraftRecipes(ids)
        AC_Materials.applySkillRequirements()
        L.lastSummary = L.register(T.mockProceduralLists(), distribution)
        L.lastComponentSummary = L.registerComponents(T.mockProceduralLists(), distribution)
        local function labels()
            MOCK.capturePrint(true)
            local results = AC_Compat.run(false)
            MOCK.capturePrint(false)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            return found
        end
        eq(labels()["component loot (" .. #entries .. " entries)"], "OK", "the game-start check reports the registered components")
        L.lastComponentSummary = partial
        local found = labels()
        eq(found["component loot list CrateMetalwork does not exist on this build"], "WARNING", "a missing list is a WARNING")
        L.lastComponentSummary = nil
        eq(labels()["component loot was not registered"], "WARNING", "components that never registered are a WARNING")
        L.lastComponentSummary = L.registerComponents(T.mockProceduralLists(), distribution)
    end
end
