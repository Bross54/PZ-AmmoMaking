-- Ammo Making - offline tests: lead and cast bullets (AC_Casting,
-- AC_Loot.MOULDS).
--
-- Loaded by tests/run_tests.lua. Pure logic: the casting model against the
-- calibre model and the installed game's item weights
-- (tests/engine_snapshot.lua), material and XP accounting, and the mould loot
-- judged per room (tests/vanilla_snapshot.lua). Mocked engine: the cast
-- assembly's OnCreate on mocked items, the loot registration on mocked
-- tables and the game-start report. That the recipes appear at the furnace
-- and forge, take a broken lead pipe and keep the mould, and how often a
-- mould is found, are REQUIRES FUTURE IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK, VANILLA, ENGINE = T.check, T.eq, T.section, T.MOCK, T.VANILLA, T.ENGINE
    local readFile, ROOT = T.readFile, T.ROOT

    local function recipesOf(step)
        local found = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.step == step then table.insert(found, recipe) end
        end
        return found
    end

    local function castRecipe(calibre, step)
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.calibre == calibre.id and recipe.step == step then return recipe end
        end
        return nil
    end

    section("Lead: which calibres cast, and why rifles do not (pure)")
    do
        local C = AC_Casting.CONFIG
        eq(#AC_Casting.validate(), 0, "the casting model is sound: " .. table.concat(AC_Casting.validate(), "; "))
        eq(#AC_Calibres.validate(), 0, "the calibre model with its cast bullets is sound: " .. table.concat(AC_Calibres.validate(), "; "))
        eq(C.metal, "lead", "the metal is lead")
        eq(C.scrapUnits, AC_Calibres.CONFIG.scrapUnits, "a lead scrap holds what a copper scrap holds")

        local castable = {}
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local class = AC_Calibres.CLASSES[calibre.class]
            eq(calibre.castBullet ~= nil, calibre.class ~= "rifle", calibre.id .. (calibre.class == "rifle" and ": a rifle keeps its copper bullet" or ": casts a lead bullet"))
            eq(calibre.castBullet ~= nil, class.mould ~= nil, calibre.id .. ": cast exactly when its class has a mould")
            if calibre.castBullet then
                castable[#castable + 1] = calibre.id
                eq(string.sub(calibre.castBullet, 1, 11), "AmmoMaking.", calibre.id .. ": the cast bullet is the mod's item")
                check(T.declaredItems[calibre.castBullet] ~= nil, calibre.id .. ": " .. calibre.castBullet .. " is in AC_Items.txt")
                eq(AC_Calibres.identify(calibre.castBullet), "castBullet", calibre.id .. ": identify() knows the cast bullet")
                local copper, lead = AC_Materials.UNITS[calibre.bullet], AC_Materials.UNITS[calibre.castBullet]
                eq(lead.metal, "lead", calibre.id .. ": the cast bullet is lead")
                eq(lead.units, copper.units, calibre.id .. ": as much lead as the swaged bullet has copper")
                -- A cast bullet weighs what the copper bullet of its calibre does.
                local castItem, copperItem = T.declaredItems[calibre.castBullet], T.declaredItems[calibre.bullet]
                eq(castItem and castItem.fields.Weight, copperItem and copperItem.fields.Weight, calibre.id .. ": the same weight as its copper bullet")
            end
        end
        eq(table.concat(castable, ", "), "9mm, .38 Special, .45 ACP, .357 Magnum, .44 Magnum, 12 Gauge", "the five pistol calibres and the shell cast; the three rifles do not")
        eq(AC_Calibres.CLASSES.rifle.mould, nil, "the rifle class has no mould")
        eq(AC_Calibres.get("12 Gauge").castBullet, "AmmoMaking.LeadShotCharge12Gauge", "the shell's cast projectile is a charge of lead shot")

        -- The validators refuse what they are there to refuse.
        local function calibreProblems(change)
            local list = {}
            for index, calibre in ipairs(AC_Calibres.LIST) do
                local copy = {}
                for key, value in pairs(calibre) do copy[key] = value end
                list[index] = copy
            end
            change(list)
            return table.concat(AC_Calibres.validate(list), "; ")
        end
        local rifle, nine, shell = 6, 1, 9
        eq(AC_Calibres.LIST[rifle].class, "rifle", "the sixth definition is a rifle")
        check(string.find(calibreProblems(function(l) l[rifle].castBullet = "AmmoMaking.CastBulletX" end), "has no cast bullet: its class has no mould", 1, true) ~= nil, "a rifle with a cast bullet is refused")
        check(string.find(calibreProblems(function(l) l[nine].castBullet = nil end), "has a mould but it has no cast bullet", 1, true) ~= nil, "a pistol without one is refused")
        check(string.find(calibreProblems(function(l) l[shell].castBullet = l[nine].castBullet end), "is already used by", 1, true) ~= nil, "two calibres sharing a cast bullet are refused")
        check(string.find(calibreProblems(function(l) l[nine].castBullet = l[nine].bullet end), "is already used by", 1, true) ~= nil, "a cast bullet that is the copper bullet is refused")
        check(string.find(calibreProblems(function(l) l[nine].castBullet = AC_Calibres.CLASSES.pistol.mould end), "is already used by class pistol mould", 1, true) ~= nil, "a cast bullet that is a mould is refused")
        local saved = AC_Calibres.CLASSES.shotgun.mould
        AC_Calibres.CLASSES.shotgun.mould = AC_Calibres.CLASSES.pistol.mould
        check(string.find(table.concat(AC_Calibres.validate(), "; "), "mould item", 1, true) ~= nil, "two classes sharing a mould are refused")
        AC_Calibres.CLASSES.shotgun.mould = "Base.Pliers"
        check(string.find(table.concat(AC_Calibres.validate(), "; "), "the mould must be an item of the mod", 1, true) ~= nil, "a vanilla item as a mould is refused")
        AC_Calibres.CLASSES.shotgun.mould = saved

        local function castingProblems(change)
            local savedConfig, savedSources = {}, AC_Casting.SOURCES
            for key, value in pairs(C) do savedConfig[key] = value end
            local sources = {}
            for index, source in ipairs(savedSources) do
                sources[index] = { id = source.id, items = source.items, count = source.count, scrap = source.scrap }
            end
            AC_Casting.SOURCES = sources
            change(C, sources)
            local found = table.concat(AC_Casting.validate(), "; ")
            for key, value in pairs(savedConfig) do C[key] = value end
            AC_Casting.SOURCES = savedSources
            return found
        end
        check(string.find(castingProblems(function(c) c.recoverXp = 1 end), "melting junk must teach nothing", 1, true) ~= nil, "melting that pays XP is refused")
        check(string.find(castingProblems(function(c) c.scrapUnits = 20 end), "must hold what a copper scrap holds", 1, true) ~= nil, "a lead scrap worth two copper scraps is refused")
        check(string.find(castingProblems(function(c) c.mouldXp = 11 end), "no more XP than a die set", 1, true) ~= nil, "a mould that pays more than a die set is refused")
        check(string.find(castingProblems(function(c) c.castCharcoal = 0 end), "castCharcoal", 1, true) ~= nil, "a cast without heat is refused")
        check(string.find(castingProblems(function(_, s) s[1].items = { AC_Calibres.get("9mm").castBullet } end), "is not a vanilla item", 1, true) ~= nil, "melting the mod's own bullets is refused")
        check(string.find(castingProblems(function(_, s) s[1].items = { "Base.Bullets9mm" } end), "is a component of the mod", 1, true) ~= nil, "melting finished rounds is refused")
        check(string.find(castingProblems(function(_, s) s[2].id = s[1].id end), "named twice", 1, true) ~= nil, "two sources with one id are refused")
        check(string.find(castingProblems(function(_, s) s[1].scrap = 0.5 end), "whole and at least 1", 1, true) ~= nil, "half a scrap is refused")
    end

    section("Lead: melting vanilla junk, casting, assembling (pure)")
    do
        local C = AC_Casting.CONFIG

        -- Melting: a declared source of lead, from vanilla items only, no XP,
        -- never more lead scrap by weight than the junk weighs.
        local melts = recipesOf("leadSource")
        eq(#melts, #AC_Casting.SOURCES, "one melt per source")
        eq(#melts, 2, "two sources: the lead pipe and jig lures")
        local scrapWeight = tonumber(T.declaredItems[C.scrapItem].fields.Weight)
        eq(scrapWeight, 0.5, "a lead scrap weighs what a copper scrap weighs")
        eq(T.declaredItems[C.scrapItem].fields.Weight, "0.5", "(as written in the script)")
        for _, melt in ipairs(melts) do
            eq(melt.source, "lead", melt.id .. " is a declared source of lead")
            eq(AC_Materials.getRecipeXP(melt), 0, melt.id .. " teaches nothing")
            eq(AC_Materials.getRequiredLevel(melt), 0, melt.id .. " needs no level")
            eq(melt.benchTag, "PrimitiveFurnace", melt.id .. " at any furnace")
            eq(melt.category, "Blacksmithing", melt.id .. " is smithing, so clay moulds and crude tongs break as in vanilla")
            check(AC_Materials.checkConservation(melt), melt.id .. " passes the conservation check as a source")
            local junk = melt.inputs[4]
            local facts = ENGINE.items[junk.items[1]]
            check(facts ~= nil, junk.items[1] .. " is recorded from the installed game")
            if facts then
                check(melt.outputs[1].count * scrapWeight <= junk.count * facts.weight, melt.id .. ": no more lead by weight than the junk weighs (" .. melt.outputs[1].count * scrapWeight .. " of " .. junk.count * facts.weight .. ")")
            end
            -- Without its junk, the same recipe creates lead from nothing.
            check(not AC_Materials.checkConservation({ id = "nothing", source = "lead", inputs = { melt.inputs[1], melt.inputs[2] }, outputs = melt.outputs }), melt.id .. ": lead from the kept tools alone is refused")
            check(not AC_Materials.checkConservation({ id = "undeclared", inputs = melt.inputs, outputs = melt.outputs }), melt.id .. ": an undeclared source is refused")
        end
        local pipe = AC_Materials.getRecipe("AmmoMaking_MeltLeadFromLeadPipe")
        eq(pipe.inputs[4].count .. " -> " .. pipe.outputs[1].count, "1 -> 2", "a lead pipe melts to two scrap")
        eq(pipe.inputs[4].destroy, true, "and is destroyed, broken or whole, as vanilla melts its junk")
        eq(table.concat(pipe.inputs[4].flags, ";"), "AllowDestroyedItem", "with vanilla's flag for a broken item")
        local jigs = AC_Materials.getRecipe("AmmoMaking_MeltLeadFromJigLures")
        eq(jigs.inputs[4].count .. " -> " .. jigs.outputs[1].count, "5 -> 1", "five jig lures melt to one scrap")
        eq(ENGINE.items["Base.LeadPipe"].type, "base:weapon", "the lead pipe is vanilla's weapon")
        eq(ENGINE.items["Base.JigLure"].type, "base:normal", "the jig lure is a plain item, not a drainable")

        -- Nothing but a melt makes lead; nothing turns lead into anything
        -- but a cast bullet, and a cast bullet into anything but a round.
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            for _, output in ipairs(recipe.outputs) do
                if output.item == C.scrapItem then eq(recipe.step, "leadSource", recipe.id .. " makes lead scrap: only a melt may") end
                local kind = AC_Calibres.identify(output.item)
                if kind == "castBullet" then eq(recipe.step, "cast", recipe.id .. " makes cast bullets: only a cast may") end
            end
            for _, input in ipairs(recipe.inputs) do
                for _, id in ipairs(input.items or {}) do
                    if id == C.scrapItem and not input.keep then eq(recipe.step, "cast", recipe.id .. " consumes lead scrap: only a cast may") end
                    local kind, calibre = AC_Calibres.identify(id)
                    if kind == "castBullet" then
                        eq(recipe.step, "assembleCast", recipe.id .. " consumes a cast bullet: only its assembly may")
                        eq(recipe.calibre, calibre.id, recipe.id .. " consumes its own calibre's cast bullet")
                    end
                    check(kind ~= "round", recipe.id .. " consumes no finished round")
                end
            end
        end

        for _, calibre in ipairs(AC_Casting.getCastable()) do
            local name = calibre.id
            local cast = castRecipe(calibre, "cast")
            local assemble = castRecipe(calibre, "assembleCast")
            local swage = castRecipe(calibre, "bullet")
            local hand = castRecipe(calibre, "assemble")
            check(cast ~= nil and assemble ~= nil, name .. ": a cast and an assembly")
            -- Casting pays what swaging pays: level, XP, time.
            eq(AC_Materials.getRequiredLevel(cast), AC_Materials.getRequiredLevel(swage), name .. ": casting opens with swaging")
            eq(AC_Materials.getRecipeXP(cast), AC_Materials.getRecipeXP(swage), name .. ": a cast pays what a swage pays")
            eq(cast.time, swage.time, name .. ": and takes as long")
            eq(cast.outputs[1].count, swage.outputs[1].count, name .. ": as many bullets from a lead scrap as from a copper one")
            eq(cast.benchTag, "PrimitiveFurnace", name .. ": cast at any furnace")
            eq(cast.timedAction, nil, name .. ": no timed action, like vanilla furnace recipes")
            local mould = AC_Calibres.CLASSES[calibre.class].mould
            local keptMould, crucible = false, false
            for _, input in ipairs(cast.inputs) do
                if input.items and input.items[1] == mould then keptMould = input.keep == true and #input.items == 1 and input.flags == nil end
                if input.items and input.items[1] == "Base.CeramicCrucible" then crucible = input.keep == true end
            end
            check(keptMould, name .. ": keeps its class's mould, by item type alone")
            check(crucible, name .. ": keeps the empty crucible")
            check(AC_Materials.checkConservation(cast), name .. ": casting conserves lead")
            check(not AC_Materials.checkConservation({ id = "x", inputs = cast.inputs, outputs = { { count = cast.outputs[1].count + 1, item = calibre.castBullet } } }), name .. ": one bullet more is refused")
            check(not AC_Materials.checkConservation({ id = "x", inputs = cast.inputs, outputs = { { count = 1, item = calibre.bullet } } }), name .. ": lead cannot become a copper bullet")

            -- The assembly is the copper one with its bullet line swapped.
            eq(#assemble.inputs, #hand.inputs, name .. ": the assembly has the copper assembly's lines")
            for index, input in ipairs(hand.inputs) do
                local mine = assemble.inputs[index]
                if input.items and input.items[1] == calibre.bullet then
                    eq(mine.items[1], calibre.castBullet, name .. ": the bullet line takes the cast bullet")
                    eq(mine.count, input.count, name .. ": one of it")
                else
                    eq(T.RENDER.renderInput(mine), T.RENDER.renderInput(input), name .. ": line " .. index .. " is the copper assembly's")
                end
            end
            eq(assemble.outputs[1].item, calibre.round, name .. ": the same vanilla round")
            eq(assemble.outputs[1].count, 1, name .. ": one round per craft")
            for _, key in ipairs({ "requiredLevel", "xp", "time", "timedAction", "benchTag", "category", "effect" }) do
                eq(assemble[key], hand[key], name .. ": assembly " .. key .. " is the copper assembly's")
            end
            -- What the round holds: lead where the copper round has copper.
            local inCast, outCast = AC_Materials.getRecipeUnits(assemble)
            local inHand, outHand = AC_Materials.getRecipeUnits(hand)
            eq(outCast.copper, nil, name .. ": a cast round holds no copper")
            eq(outCast.lead, outHand.copper, name .. ": its lead is the copper round's copper, unit for unit")
            eq(inCast.brass, inHand.brass, name .. ": the same brass, so the same zinc from the mine")
            eq(outCast.brass, outHand.brass, name .. ": and the same brass in the round")
            eq(outCast.powder, outHand.powder, name .. ": the same charge")
            check(AC_Materials.checkConservation(assemble), name .. ": the cast assembly conserves every material")
            local copperRound = { id = "x", inputs = assemble.inputs, outputs = { { count = 1, item = calibre.round } } }
            check(not AC_Materials.checkConservation(copperRound), name .. ": a round counted as copper from a lead bullet is refused")
            check(not AC_Materials.checkConservation({ id = "x", inputs = assemble.inputs, outputs = { { count = 2, item = calibre.round, contents = assemble.outputs[1].contents } } }), name .. ": two rounds from one set is refused")
            eq(AC_Casting.STEP_OF.cast, "bullet", "a cast takes the bullet step's values")
            eq(AC_Casting.STEP_OF.assembleCast, "assemble", "a cast assembly the assembly's")
        end

        -- Moulds: one per class that casts; forged like a die set, from iron,
        -- for nothing, and met when the first bullet it casts opens.
        local moulds = recipesOf("mould")
        eq(#moulds, 2, "two moulds: pistol and buckshot")
        for _, recipe in ipairs(moulds) do
            local mould = AC_Casting.getMould(recipe.class)
            eq(recipe.outputs[1].item, mould.item, recipe.id .. " makes its class's mould")
            eq(AC_Materials.getRecipeXP(recipe), 0, recipe.id .. ": a mould pays per cast, not when it is forged")
            eq(recipe.tool, true, recipe.id .. " makes a tool")
            eq(recipe.benchTag, "Forge", recipe.id .. ": forged where a die set is")
            local lowest = 10
            for _, calibre in ipairs(AC_Casting.getCastable()) do
                if calibre.class == recipe.class then lowest = math.min(lowest, calibre.levels.bullet) end
            end
            eq(AC_Materials.getRequiredLevel(recipe), lowest, recipe.id .. ": opens with the first bullet it casts")
            local parts = recipe.inputs[2].count * ENGINE.items[recipe.inputs[2].items[1]].weight
            check(parts >= tonumber(T.declaredItems[mould.item].fields.Weight), recipe.id .. ": the iron weighs at least what the mould does")
            eq(T.declaredItems[mould.item].fields.DisplayCategory, "Tool", recipe.id .. ": the mould is a Tool, filed under the engine's tool loot")
        end
        eq(AC_Casting.getMould("pistol").level, 2, "the pistol mould at level 2, with 9mm bullets")
        eq(AC_Casting.getMould("shotgun").level, 3, "the buckshot mould at level 3, with shot charges")
        eq(AC_Casting.getMould("rifle"), nil, "no rifle mould")
    end

    section("Lead: the mine stays the way to rounds, and no loop pays (pure)")
    do
        -- Per 100 rounds of each castable calibre: the brass, and therefore
        -- the zinc that only an assayed deposit gives, is exactly the copper
        -- round's. Lead replaces the bullet's copper only.
        for _, calibre in ipairs(AC_Casting.getCastable()) do
            local primer = AC_Calibres.getPrimer(calibre.primerFamily)
            local brass = calibre.cupsPerCase * AC_Calibres.CONFIG.cupUnits + primer.brassUnits
            local castIn = AC_Materials.getRecipeUnits(castRecipe(calibre, "assembleCast"))
            eq(castIn.brass, brass, calibre.id .. ": a cast round takes all of its brass")
            eq(castIn.copper, nil, calibre.id .. ": and no copper at all")
            eq(castIn.lead, AC_Calibres.CONFIG.scrapUnits / calibre.bulletsPerScrap, calibre.id .. ": lead in place of the bullet's copper, and nothing else")
        end
        -- XP per round is the copper round's, whichever bullet: lead opens no
        -- faster climb.
        for _, calibre in ipairs(AC_Casting.getCastable()) do
            local copperXP = AC_Materials.getRecipeXP(castRecipe(calibre, "bullet")) / calibre.bulletsPerScrap + AC_Materials.getRecipeXP(castRecipe(calibre, "assemble"))
            local leadXP = AC_Materials.getRecipeXP(castRecipe(calibre, "cast")) / calibre.bulletsPerScrap + AC_Materials.getRecipeXP(castRecipe(calibre, "assembleCast"))
            eq(leadXP, copperXP, calibre.id .. ": a round earns the same XP with either bullet")
        end
        -- Every lead recipe at its level appears in the progression; nothing
        -- opens above level 5.
        for _, step in ipairs({ "leadSource", "mould", "cast", "assembleCast" }) do
            for _, recipe in ipairs(recipesOf(step)) do
                check(AC_Materials.getRequiredLevel(recipe) <= 5, recipe.id .. " opens at level 5 or below")
            end
        end
        -- A round from either recipe can only be taken apart for powder, so
        -- lead in a round is lead gone: melting a pipe, casting and assembling
        -- end with less lead than the pipe gave.
        local inv = { ["Base.LeadPipe"] = 1, ["Base.CeramicCrucible"] = 1, ["base:crudetongs"] = 1, ["base:charcoal"] = 10 }
        local nine = AC_Calibres.get("9mm")
        inv[AC_Calibres.CLASSES.pistol.mould] = 1
        check(T.mirrorCraft(inv, AC_Materials.getRecipe("AmmoMaking_MeltLeadFromLeadPipe")), "a lead pipe melts on the mirror inventory")
        eq(inv[AC_Casting.CONFIG.scrapItem], 2, "into two scrap")
        check(T.mirrorCraft(inv, castRecipe(nine, "cast")) and T.mirrorCraft(inv, castRecipe(nine, "cast")), "cast twice")
        eq(inv[nine.castBullet], 4, "four 9mm bullets from one pipe")
        eq(inv[AC_Casting.CONFIG.scrapItem], 0, "no lead scrap left")
        eq(inv["Base.LeadPipe"], 0, "the pipe is gone")
        eq(inv[AC_Calibres.CLASSES.pistol.mould], 1, "the mould is kept")
    end

    section("Bullet mould loot: beside the die sets, judged per room (pure)")
    do
        local L = AC_Loot
        local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
        eq(#L.validateMoulds(), 0, "the mould loot table is sound: " .. table.concat(L.validateMoulds(), "; "))
        eq(L.MOULDS.weight, 0.5, "a mould weighs 0.5 before the list's scale")
        local entries = L.buildMouldEntries()
        eq(#entries, 4, "both moulds in a gun store, the pistol mould in a garage gun locker, the buckshot mould among a hunter's things")
        local perList, seen = {}, {}
        for _, entry in ipairs(entries) do
            local facts = VANILLA.loot.lists[entry.list]
            local what = entry.item .. " in " .. entry.list
            check(facts ~= nil and facts.references >= 1 and facts.entries > 0, what .. ": the list is used by a container and holds items")
            check(entry.weight > 0 and entry.weight <= L.CONFIG.maxWeight, what .. ": within a die set's limit")
            check(AC_Calibres.identify(entry.item) == nil, what .. " is no calibre component")
            perList[entry.list] = (perList[entry.list] or 0) + entry.weight
            seen[entry.list .. "|" .. entry.item] = true
        end
        eq(perList.GunStoreMagsAmmo, 1, "a gun store's ammunition case: both moulds, 1 in all")
        eq(perList.GarageFirearms, 0.25, "a garage gun locker: the pistol mould, 0.25")
        eq(perList.Hunter, 0.25, "a hunter's things: the buckshot mould, 0.25")
        check(seen["GarageFirearms|" .. AC_Calibres.CLASSES.pistol.mould] and not seen["GarageFirearms|" .. AC_Calibres.CLASSES.shotgun.mould], "the handgun locker holds the pistol mould only")
        check(seen["Hunter|" .. AC_Calibres.CLASSES.shotgun.mould] and not seen["Hunter|" .. AC_Calibres.CLASSES.pistol.mould], "the hunter holds the buckshot mould only")

        -- Per ROOM, at the default and at the die-set multiplier's maximum:
        -- twelve containers filled from a list hold under one mould.
        local die = AC_Balance.getOption("dieSetLoot")
        local most, mostWhere = 0, ""
        for _, target in ipairs(L.MOULDS.lists) do
            local users = VANILLA.loot.users[target.list]
            check(users ~= nil and #users >= 1, target.list .. " has its users in the snapshot")
            local each = VANILLA.loot.lists[target.list].rolls * perList[target.list] / 100
            for _, user in ipairs(users or {}) do
                local previous = 0
                for _, size in ipairs(BALANCE.LOOT_ROOM_SIZES) do
                    local moulds = BALANCE.expectedUses(user.lists, target.list, size) * each
                    check(moulds >= previous, target.list .. " in " .. user.container .. ": more containers never mean fewer moulds")
                    previous = moulds
                end
                check(previous <= 1, target.list .. " in " .. user.container .. ": twelve such containers hold at most one mould on average (" .. string.format("%.3f", previous) .. ")")
                check(previous * die.max <= 1, target.list .. " in " .. user.container .. ": and at the multiplier's maximum x" .. die.max .. " (" .. string.format("%.3f", previous * die.max) .. ")")
                if previous > most then most, mostWhere = previous, user.container end
            end
        end
        local gunStore
        for _, user in ipairs(VANILLA.loot.users.GunStoreMagsAmmo) do
            if user.container == "gunstore.displaycase" then gunStore = user.lists end
        end
        local store = BALANCE.expectedUses(gunStore, "GunStoreMagsAmmo", 8) * VANILLA.loot.lists.GunStoreMagsAmmo.rolls * perList.GunStoreMagsAmmo / 100
        check(store > 0.01 and store < 0.03, "a gun store of eight display cases holds a mould about one time in sixty (" .. string.format("%.3f", store) .. ")")
        check(most > 0.1 and most < 0.15, "the fullest room of twelve is a row of military lockers at about 0.12 (" .. string.format("%.3f", most) .. ")")
        eq(L.NEVER_COMPONENT_LOOT.castBullet, true, "a cast bullet is never component loot")
        print(string.format("  Loot: the fullest room of twelve containers holds %.3f bullet moulds on average (%s); a gun store of 8 display cases %.3f", most, mostWhere, store))

        -- The die-set multiplier scales them; components and books keep theirs.
        local lists, distribution = T.mockProceduralLists(), T.mockDistribution()
        local summary = L.registerMoulds(lists, distribution)
        eq(summary.added, #entries, "every mould entry is added")
        eq(#summary.missing + #summary.empty + #summary.unreferenced, 0, "to lists that exist, hold items and are used")
        eq(L.registerMoulds(lists, distribution).added, 0, "a second world load adds nothing")
        for _, owned in ipairs(L.owned) do
            if AC_Casting.getMould("pistol").item == owned.item or AC_Casting.getMould("shotgun").item == owned.item then
                eq(owned.option, "dieSetLoot", owned.item .. " in " .. owned.list .. " takes the die-set multiplier")
            end
        end
        local savedVars = SandboxVars
        SandboxVars = { AmmoMaking = { DieSetLootMultiplier = 0 } }
        L.applyMultipliers(lists)
        SandboxVars = savedVars
        for _, entry in ipairs(entries) do
            local found = nil
            for index = 1, #lists[entry.list].items, 2 do
                if lists[entry.list].items[index] == entry.item then found = true end
            end
            eq(found, nil, entry.item .. " in " .. entry.list .. " is taken out at x0")
        end
        L.applyMultipliers(lists)
        L.CONFIG.enabled = false
        eq(L.registerMoulds(T.mockProceduralLists(), distribution).added, 0, "loot switched off: no mould is added")
        L.CONFIG.enabled = true
        local short = T.mockProceduralLists()
        short.Hunter = nil
        eq(table.concat(L.registerMoulds(short, distribution).missing, ","), "Hunter", "a list this build does not have is named")
        eq(short.Hunter, nil, "and never created")

        -- validateMoulds() refuses what would flood a room.
        local function refused(what, change, needle)
            local copy = { weight = L.MOULDS.weight, lists = {} }
            for index, target in ipairs(L.MOULDS.lists) do copy.lists[index] = { list = target.list, scale = target.scale, classes = target.classes } end
            change(copy)
            local found = table.concat(L.validateMoulds(copy), "; ")
            check(string.find(found, needle, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
        end
        refused("a heavy mould", function(c) c.weight = 1.5 end, "at most 1")
        refused("a list over the cap", function(c) c.weight = 0.8 end, "above 1")
        refused("a scale above 1", function(c) c.lists[1].scale = 2 end, "at most 1")
        refused("the same list twice", function(c) c.lists[3].list = c.lists[2].list end, "named twice")
        refused("a rifle mould", function(c) c.lists[3].classes = { "rifle" } end, "a class without a mould")
        refused("a mould in no list", function(c) table.remove(c.lists, 3) table.remove(c.lists, 1) end, "is in no list")

        -- The loot document names every list.
        local document = readFile(ROOT .. "/docs/LOOT_AND_RECYCLING.md")
        for _, target in ipairs(L.MOULDS.lists) do
            check(string.find(document, "`" .. target.list .. "`", 1, true) ~= nil, "docs/LOOT_AND_RECYCLING.md names " .. target.list)
        end
        check(string.find(document, "Bullet moulds", 1, true) ~= nil, "and has the mould section")
    end

    section("Lead: the cast round's record and the game-start report (mocked engine)")
    do
        -- The cast assembly runs the copper assembly's effect: the round
        -- takes its case's quality, and nothing for the bullet.
        local nine = AC_Calibres.get("9mm")
        local assemble = castRecipe(nine, "assembleCast")
        local round, case = MOCK.newItem(nine.round), MOCK.newItem(nine.case)
        AC_CaseQuality.set(case, 64)
        local data = {
            getAllCreatedItems = function() return MOCK.arrayList({ round }) end,
            getAllConsumedItems = function() return MOCK.arrayList({ case, MOCK.newItem(nine.castBullet) }) end,
        }
        local player = MOCK.newPlayer()
        MOCK.capturePrint(true)
        local granted = AC_Materials[assemble.callback](data, player)
        MOCK.capturePrint(false)
        eq(granted, AC_Materials.getRecipeXP(castRecipe(nine, "assemble")), "the cast assembly pays the copper assembly's XP")
        eq(AC_CaseQuality.getRoundQuality(round), 64, "the round keeps its case's quality, no penalty for lead")

        local cast = castRecipe(nine, "cast")
        local bulletsData = setmetatable({}, { __index = function(_, key) error("craftRecipeData." .. tostring(key) .. " was read") end })
        MOCK.capturePrint(true)
        eq(AC_Materials[cast.callback](bulletsData, MOCK.newPlayer()), AC_Materials.getRecipeXP(cast), "a cast pays once, reading nothing of the craft")
        eq(AC_Materials[AC_Materials.getRecipe("AmmoMaking_MeltLeadFromLeadPipe").callback](bulletsData, player), 0, "a melt pays nothing")
        MOCK.capturePrint(false)

        -- Game start: the model and the mould loot are reported.
        local ids = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
        MOCK.resetCraftRecipes(ids)
        AC_Materials.applySkillRequirements()
        AC_Loot.lastMouldSummary = AC_Loot.registerMoulds(T.mockProceduralLists(), T.mockDistribution())
        local function labels()
            MOCK.capturePrint(true)
            local results = AC_Compat.run(false)
            MOCK.capturePrint(false)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            return found
        end
        local found = labels()
        local castLine = "lead casting (" .. #AC_Casting.getCastable() .. " castable calibres, " .. #AC_Casting.getMoulds() .. " moulds, no XP for melting)"
        eq(found[castLine], "OK", "the game-start check reports the casting model")
        eq(found["bullet mould loot (4 entries)"], "OK", "and the registered moulds")
        for _, id in ipairs(AC_Casting.getItems()) do
            eq(found[id], "OK", id .. " is probed at game start")
        end
        local saved = AC_Loot.lastMouldSummary
        AC_Loot.lastMouldSummary = nil
        eq(labels()["bullet mould loot was not registered"], "WARNING", "moulds that never registered are a WARNING")
        AC_Loot.lastMouldSummary = saved
        AC_Casting.CONFIG.recoverXp = 2
        eq(labels()["casting: melting junk must teach nothing"], "WARNING", "a broken casting model is a WARNING by name")
        AC_Casting.CONFIG.recoverXp = 0

        -- The documents quote what the code says.
        local checklist = string.gsub(readFile(ROOT .. "/docs/INGAME_VALIDATION.md"), "\n%s*", " ")
        for _, line in ipairs({
            "[AmmoMaking] Bullet mould loot: 4 entries added",
            "OK: " .. castLine,
            "OK: bullet mould loot (4 entries)",
        }) do
            check(string.find(checklist, line, 1, true) ~= nil, "docs/INGAME_VALIDATION.md quotes: " .. line)
        end
        local metallurgy = readFile(ROOT .. "/docs/METALLURGY_DESIGN.md")
        check(string.find(metallurgy, "## 12. Lead and cast bullets", 1, true) ~= nil, "the metallurgy document has the section the code cites")
        local ammunition = readFile(ROOT .. "/docs/AMMUNITION_DESIGN.md")
        check(string.find(ammunition, "### 6.1 Cast lead bullets", 1, true) ~= nil, "and the ammunition document its section")
        local names = readFile(T.TRANSLATE .. "Recipes.json")
        for _, recipe in ipairs(AC_Casting.buildRecipes()) do
            check(string.find(names, '"' .. recipe.id .. '"', 1, true) ~= nil, recipe.id .. " has a name")
        end
    end
end
