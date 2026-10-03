"""Ammo Making - mutation run for the offline suite.

    python tests/run_mutants.py            run every mutant
    python tests/run_mutants.py check      only check that every mutant still applies
    python tests/run_mutants.py 12 40      run mutants 12 and 40

Each mutant is one deliberate fault in a mod file: a balance number, a
missing guard, a wrong item. The suite must fail for every one of them. A
mutant that the suite passes ("survived") is a gap in the tests, or a change
that does not matter and should be removed from this list.

The fault is written into the real file, the suite is run in a fresh Lua
5.1 state (lupa), and the file is restored, also when the run is
interrupted. Do not run this while anything else reads the repository.

Needs Python with `lupa` (the suite itself is plain Lua 5.1; lupa is how it
is run on a machine without a `lua` binary). It proves the same thing the
suite does: the Lua logic and the data, not the game.
"""

import io
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
LUA = "mod/AmmoMaking/42/media/lua/"
SHARED = LUA + "shared/"
CLIENT = LUA + "client/"

# (file, text to find exactly once, replacement, what the fault is)
MUTANTS = [
    # ---- brass recycling
    (SHARED + "AC_Recycling.lua", "    scrapPerBatch = 1,", "    scrapPerBatch = 2,", "recycling gives all of the brass back"),
    (SHARED + "AC_Recycling.lua", "    scrapPerBatch = 1,", "    scrapPerBatch = 3,", "recycling returns more brass than it takes"),
    (SHARED + "AC_Recycling.lua", "    batchUnits = 20,", "    batchUnits = 10,", "a recycling batch no bigger than its scrap"),
    (SHARED + "AC_Recycling.lua", "    xp = 0,", "    xp = 1,", "recycling grants XP"),
    (SHARED + "AC_Recycling.lua", "    scrapPerIngot = 10,", "    scrapPerIngot = 5,", "an ingot from five brass scrap"),
    (SHARED + "AC_Recycling.lua", "        loss = true,\n", "", "the scrapping recipes are not marked as lossy"),
    (SHARED + "AC_Recycling.lua", "            recycling = true,\n\n            inputs = {\n                {\n                    count = 1,\n                    items = { \"Base.CeramicCrucible\" },", "            inputs = {\n                {\n                    count = 1,\n                    items = { \"Base.CeramicCrucible\" },", "the recast is not marked as recycling"),
    (SHARED + "AC_Recycling.lua", "                scrap = count * value / config.batchUnits * config.scrapPerBatch,", "                scrap = count * value / config.batchUnits * config.scrapPerBatch * 2,", "a scrapping recipe hands back twice its yield"),
    (SHARED + "AC_Recycling.lua", "            config.cupUnits * calibre.cupsPerCase\n", "            config.cupUnits\n", "every case is scrapped as if it were one cup"),
    (SHARED + "AC_Recycling.lua", "        if units[calibre.case] == nil then\n\n            table.insert(\n                order,\n                calibre.case\n            )\n        end\n\n\n        units[calibre.case] =", "        if units[calibre.round] == nil then\n\n            table.insert(\n                order,\n                calibre.round\n            )\n        end\n\n\n        units[calibre.round] =", "finished rounds can be scrapped instead of cases"),
    (SHARED + "AC_Recycling.lua", "    castId = \"AmmoMaking_CastBrassIngotFromScrap\",", "    castId = \"AmmoMaking_CastBrassIngots\",", "a duplicate recipe id"),
    (SHARED + "AC_Recycling.lua", "        if previous ~= nil\n            and recovery > previous\n        then\n            problem(\"source \" .. label .. \" returns more brass than a cleaner source\")\n        end\n", "", "a dirtier source of brass may return more than a cleaner one"),
    (SHARED + "AC_Recycling.lua", "            if units[itemType] ~= nil then\n                problem(tostring(itemType) .. \" belongs to two sources\")\n            end\n", "", "one component may be scrapped through two sources"),
    (SHARED + "AC_Recycling.lua", "        if source.scrapPerBatch * scrapUnits >= source.batchUnits then", "        if false then", "a source that loses no brass passes validation"),
    (SHARED + "AC_Recycling.lua", "            { count = group.scrap, item = config.scrapItem },", "            { count = group.scrap, item = \"Base.CopperScrap\" },", "brass is scrapped into copper"),
    (SHARED + "AC_Materials.lua", "        if recipe.loss\n            and units >= available\n        then", "        if recipe.loss\n            and units > available + 1e9\n        then", "the conservation check no longer requires a loss"),
    (SHARED + "AC_AmmoMakingSkill.lua", "    if not player or not amount or amount <= 0 then", "    if not player or not amount then", "an award of 0 XP still touches the XP"),

    # ---- die set loot
    (SHARED + "AC_Loot.lua", "        common = 1.0,", "        common = 10.0,", "common die sets ten times as likely"),
    (SHARED + "AC_Loot.lua", "        rare = 0.3,", "        rare = 0.9,", "rare die sets three times as likely"),
    (SHARED + "AC_Loot.lua", "        uncommon = 0.6,", "        uncommon = 0.2,", "uncommon die sets rarer than rare ones"),
    (SHARED + "AC_Loot.lua", "        list = \"GunStoreMagsAmmo\",", "        list = \"GunStoreDisplayCase\",", "die sets in a deprecated, unused list"),
    (SHARED + "AC_Loot.lua", "        list = \"GunStoreMagsAmmo\",", "        list = \"GunStoreAccessories\",", "die sets in the list an army surplus store fills most of its display cases from"),
    (SHARED + "AC_Loot.lua", "        list = \"GarageFirearms\",", "        list = \"PoliceStorageAmmunition\",", "die sets in a list no container names"),
    (SHARED + "AC_Loot.lua", "        list = \"Hunter\",\n\n        scale = 0.5,", "        list = \"Hunter\",\n\n        scale = 1,", "the hunter list twice as generous"),
    (SHARED + "AC_Loot.lua", "                        item = calibre.dieSet,", "                        item = calibre.case,", "the loot is a case, not a die set"),
    (SHARED + "AC_Loot.lua", "            if hasItem(list.items, entry.item) then", "            if false then", "the loot is added again on every world load"),
    (SHARED + "AC_Loot.lua", "    enabled = true,", "    enabled = false,", "die set loot switched off"),
    (SHARED + "AC_Loot.lua", "    maxWeight = 1.0,", "    maxWeight = 100.0,", "the per-entry weight limit is gone"),
    (SHARED + "AC_Loot.lua", "    maxListWeight = 5.0,", "    maxListWeight = 500.0,", "the per-list weight limit is gone"),
    (SHARED + "AC_Loot.lua", "        classes = { \"pistol\" },", "        classes = { \"rifle\" },", "rifle dies in the garage gun locker"),
    (SHARED + "AC_Loot.lua", "            note(\"missing\", entry.list)\n", "            procedural[entry.list] = { rolls = 1, items = {} }\n", "a missing loot list is created"),
    (SHARED + "AC_Loot.lua", "        (1 - (1 - weight / 100) ^ rolls) * 100", "        weight * rolls", "the documented chance is not the engine's"),
    (SHARED + "AC_Calibres.lua", "    lootTier = \"common\",\n\n    assembleLevel = 3,", "    lootTier = \"rare\",\n\n    assembleLevel = 3,", "the common dies are rare"),
    (SHARED + "AC_Compat.lua", "    checkLoot(results)\n", "", "the game-start check no longer looks at loot"),

    # ---- press
    (SHARED + "AC_Calibres.lua", "    timePercent = 60,", "    timePercent = 30,", "a press more than three times as fast"),
    (SHARED + "AC_Calibres.lua", "    timePercent = 60,", "    timePercent = 80,", "a different press speed"),
    (SHARED + "AC_Calibres.lua", "                math.floor(hand.time * press.timePercent / 100)", "                hand.time", "the press is no faster than the hand"),
    (SHARED + "AC_Calibres.lua", "    enabled = AC_Features.isEnabled(\"reloadingPress\"),", "    enabled = true,", "the press recipes are live without a station"),
    (SHARED + "AC_Calibres.lua", "                local isHammer =\n                    input.keep\n                    and input.tags\n                    and input.tags[1] == \"base:hammer\"", "                local isHammer =\n                    input.keep", "the press needs no die set"),
    (SHARED + "AC_Calibres.lua", "                local isHammer =\n                    input.keep\n                    and input.tags\n                    and input.tags[1] == \"base:hammer\"", "                local isHammer =\n                    not input.keep and input.items and input.items[1] == \"AmmoMaking.BrassCaseCup\"", "the press forms a case from nothing"),

    # ---- ammo boxes
    (SHARED + "AC_Calibres.lua", "        box = \"Base.Bullets9mmBox\",", "        box = \"Base.Bullets9mmCarton\",", "the 9mm box is a carton"),
    (SHARED + "AC_Calibres.lua", "        box = \"Base.556Box\",", "        box = \"Base.308Box\",", "two calibres share a box"),
    (SHARED + "AC_Calibres.lua", "        round = \"Base.Bullets9mm\",\n\n        box = \"Base.Bullets9mmBox\",\n\n        roundsPerBox = 50,", "        round = \"Base.Bullets9mm\",\n\n        box = \"Base.Bullets9mmBox\",\n\n        roundsPerBox = 20,", "a 9mm box of twenty"),
    (SHARED + "AC_Compat.lua", "AC_Compat.BOX_RECIPE = \"place_ammo_in_box\"", "AC_Compat.BOX_RECIPE = \"PlaceAmmoInBox\"", "the probed box recipe id is not vanilla's"),

    # ---- save data
    (SHARED + "AC_SaveData.lua", "    if value > current then\n        return \"newer\"\n    end\n", "", "a later release's layout is taken for an older one"),
    (SHARED + "AC_SaveData.lua", "        layout =\n            layout + 1\n", "        layout =\n            current\n", "an upgrade stamps the newest layout after its first step"),
    (SHARED + "AC_SaveData.lua", "        if not ok then\n", "        if false then\n", "a failed upgrade step still advances the layout"),
    (SHARED + "AC_SaveData.lua", "        if not ok then\n\n            data.version = layout\n", "        if not ok then\n", "a step that stamps and then fails is not run again"),
    (SHARED + "AC_SaveData.lua", "        or value > AC_SaveData.MAX_VERSION\n", "", "a broken number counts as a later release"),
    (SHARED + "AC_Deposits.lua", "        if not readable then\n\n            return {\n                version = store.version,\n                tiles = {},\n                unreadable = true,\n            }\n        end\n\n\n        return store\n    end\n", "    end\n", "a later release's depletion store is reset like a damaged one"),
    (SHARED + "AC_Deposits.lua", "    if getStore().unreadable then\n        return 0\n    end\n", "", "ore can be mined from a save whose depletion cannot be recorded"),
    (SHARED + "AC_SaveData.lua", "        and value == value\n", "", "NaN counts as a finite number"),
    (SHARED + "AC_SaveData.lua", "        and value ~= math.huge\n", "", "infinity counts as a finite number"),
    (SHARED + "AC_SaveData.lua", "    if maximum ~= nil\n        and number > maximum\n    then\n        return maximum\n    end\n", "", "a stored number is not clamped at its maximum"),
    (SHARED + "AC_SaveData.lua", "    if minimum ~= nil\n        and number < minimum\n    then\n        return minimum\n    end\n", "", "a stored number is not clamped at its minimum"),
    (SHARED + "AC_SaveData.lua", "    { key = \"assayRank\", type = \"number\", whole = true, min = 0, max = 3, default = 0, repair = \"read with tonumber; anything else is rank 0 (untested)\" },\n", "", "a persisted key is missing from the schema"),
    (SHARED + "AC_CaseQuality.lua", "    -- Clamped like a case's own quality, so damaged data\n    -- never reads as \"900\".\n    return\n        clamp(\n            quality,\n            AC_CaseQuality.CONFIG.minQuality,\n            AC_CaseQuality.CONFIG.maxQuality\n        )", "    return quality", "a round's quality is trusted as stored (900 shows as 900)"),
    (SHARED + "AC_GeologySampling.lua", "    local uses =\n        AC_SaveData.whole(\n            data.assayUsesRemaining,\n            0,\n            0,\n            maximum\n        )", "    local uses =\n        AC_SaveData.whole(\n            data.assayUsesRemaining,\n            0,\n            0\n        )", "a damaged kit can have any number of uses"),
    (SHARED + "AC_GeologySampling.lua", "    local uses =\n        AC_SaveData.whole(\n            data.assayUsesRemaining,\n            0,\n            0,\n            maximum\n        )", "    local uses =\n        AC_SaveData.whole(\n            data.assayUsesRemaining,\n            maximum,\n            0,\n            maximum\n        )", "a damaged kit is refilled"),
    (SHARED + "AC_GeologySampling.lua", "        repairKit(\n            data,\n            kitType\n        )\n", "", "an initialised kit is never repaired"),
    (SHARED + "AC_GeologySampling.lua", "    trueValue =\n        AC_SaveData.number(\n            trueValue,\n            0,\n            0,\n            100\n        )", "    trueValue =\n        tonumber(trueValue) or 0", "a damaged true grade reaches the field measurement"),
    (SHARED + "AC_GeologySampling.lua", "    local data =\n        displayData(\n            sample:getModData()\n        )", "    local data =\n        sample:getModData()", "the result panel prints stored values raw"),
    (SHARED + "AC_LaboratoryAnalyzer.lua", "    data.labRemainingHours =\n        AC_SaveData.number(\n            data.labRemainingHours,\n            AC_LaboratoryAnalyzer.CONFIG.processingHours,\n            0,\n            AC_LaboratoryAnalyzer.CONFIG.processingHours\n        )", "    data.labRemainingHours =\n        tonumber(data.labRemainingHours) or AC_LaboratoryAnalyzer.CONFIG.processingHours", "an analyzer timer is trusted as stored"),
    (SHARED + "AC_LaboratoryAnalyzer.lua", "        and number >= 0\n        and number <= 100\nend", "        and number >= 0\nend", "a laboratory result above 100 is accepted"),
    (SHARED + "AC_LaboratoryAnalyzer.lua", "    trueValue =\n        AC_SaveData.number(\n            trueValue,\n            0,\n            0,\n            100\n        )", "    trueValue =\n        tonumber(trueValue) or 0", "a damaged true grade reaches the laboratory measurement"),
    (SHARED + "AC_AmmoQuality.lua", "            if not AC_SaveData.isFinite(data[key]) then", "            if type(data[key]) ~= \"number\" then", "a NaN field on the test cartridge is kept"),
    (SHARED + "AC_Deposits.lua", "        AC_SaveData.whole(\n            record[metal],\n            0,\n            0\n        )", "        (tonumber(record[metal]) or 0)", "a negative or broken depletion count is trusted"),

    # ---- quality tally (pure arithmetic)
    (SHARED + "AC_QualityTally.lua", "    local handloaded =\n        math.floor(tally.handloaded * actual / tally.count)", "    local handloaded =\n        math.ceil(tally.handloaded * actual / tally.count)", "rounds lost unseen are assumed to have been factory rounds"),
    (SHARED + "AC_QualityTally.lua", "    if #AC_QualityTally.check(value) == 0 then", "    if type(value.count) == \"number\" and type(value.handloaded) == \"number\" and type(value.qualitySum) == \"number\" then", "a tally that contradicts itself is trusted"),
    (SHARED + "AC_QualityTally.lua", "    if not AC_SaveData.isFinite(quality) then\n\n        return\n            make(\n                tally.count + 1,\n                tally.handloaded,\n                tally.qualitySum,\n                tally.phase\n            )\n    end\n", "", "a round of unknown quality is loaded as a handloaded one"),
    (SHARED + "AC_QualityTally.lua", "            and (phase >= 1 - 1e-9 or handloaded == count)\n", "            and handloaded * 2 > count\n", "the majority kind of round leaves first (the fault a review found)"),
    (SHARED + "AC_QualityTally.lua", "            and (phase >= 1 - 1e-9 or handloaded == count)\n", "\n", "handloaded rounds always leave first"),
    (SHARED + "AC_QualityTally.lua", "            qualitySum =\n                qualitySum - quality\n", "", "the quality of a round that leaves also stays behind"),
    (SHARED + "AC_QualityTally.lua", "            local quality =\n                math.floor(qualitySum / handloaded)", "            local quality =\n                math.ceil(qualitySum / handloaded) + 1", "a round that leaves takes more than its share of quality"),
    (SHARED + "AC_QualityTally.lua", "    if isNewer(value) then\n        return AC_QualityTally.empty(0), value\n    end\n", "", "a split turns a later release's tally into one of this layout"),
    (SHARED + "AC_QualityTally.lua", "    if (from ~= nil and rawequal(from, to))\n        or isNewer(from)", "    if isNewer(from)", "a record transferred into itself gains rounds"),
    (SHARED + "AC_QualityTally.lua", "    if isNewer(value) then\n        return AC_QualityTally.empty(0), AC_QualityTally.NEWER\n    end\n", "", "a later release's tally is treated as damage and overwritten"),
    (SHARED + "AC_QualityTally.lua", "    if a.count + b.count > AC_QualityTally.CONFIG.maxRounds then\n        return a, false\n    end\n", "", "a merge may exceed the round limit"),
    (SHARED + "AC_QualityTally.lua", "    if actual > tally.count\n        or tally.handloaded == 0\n    then\n", "    if tally.handloaded == 0 then\n", "rounds that arrive unseen are counted as handloaded in proportion"),
    (SHARED + "AC_QualityTally.lua", "    local whole =\n        AC_SaveData.whole(\n            quality,\n            minimum,\n            minimum,\n            maximum\n        )", "    local whole =\n        quality", "a loaded round's quality is taken as given (900 stays 900)"),
    (SHARED + "AC_QualityTally.lua", "        if index <= extra then\n            list[index] = base + 1\n        else\n            list[index] = base\n        end", "        list[index] = base + 1", "unloaded rounds are each rounded up, creating quality"),

    # ---- calls the engine would refuse (the mock checks them against tests/engine_snapshot.lua)
    (SHARED + "AC_Mining.lua", "                        ZombRandFloat(0.2, 0.8),\n                        ZombRandFloat(0.2, 0.8),\n                        0\n", "                        ZombRandFloat(0.2, 0.8),\n                        ZombRandFloat(0.2, 0.8)\n", "the ore is dropped with an overload the engine does not have"),
    (SHARED + "AC_AmmoMakingSkill.lua", "    player:getXp():AddXP(\n", "    player:getXp():AddXP(\n        true,\n", "XP is granted with an argument too many"),
    ("tests/engine_snapshot.lua", "                hasWater = { \"\" },\n                haveElectricity", "                hasWater = { \"boolean\" },\n                haveElectricity", "the recorded build's hasWater takes an argument the mod does not pass"),

    # ---- the calibre model and the chain (the faults earlier passes guarded against)
    (SHARED + "AC_Calibres.lua", "    cupUnits = 5,", "    cupUnits = 4,", "a case cup holds less brass than the sheet gives"),
    (SHARED + "AC_Calibres.lua", "    usesPerJar = 10,", "    usesPerJar = 12,", "a jar of powder holds twelve uses"),
    (SHARED + "AC_Calibres.lua", "    fertilizerUses = 2,", "    fertilizerUses = 0,", "gunpowder needs no fertilizer"),
    (SHARED + "AC_Calibres.lua", "    powderUses = 1,\n\n    -- Pieces of wadding", "    powderUses = 2,\n\n    -- Pieces of wadding", "the standard charge is doubled"),
    (SHARED + "AC_Calibres.lua", "        cupsPerCase = 3,\n\n        powderUses = 5,", "        cupsPerCase = 3,\n\n        powderUses = 4,", "the .308 takes a charge less"),
    (SHARED + "AC_Calibres.lua", "        brassUnits = 1,\n\n        -- Priming compound in one primer.\n        compoundUnits = 2,", "        brassUnits = 1,\n\n        -- Priming compound in one primer.\n        compoundUnits = 1,", "a small pistol primer holds half its compound"),
    (SHARED + "AC_Calibres.lua", "        primerFamily = \"LargePistol\",\n\n        bulletsPerScrap = 1,\n\n        lootTier = \"uncommon\",\n\n        assembleLevel = 4,", "        primerFamily = \"SmallPistol\",\n\n        bulletsPerScrap = 1,\n\n        lootTier = \"uncommon\",\n\n        assembleLevel = 4,", "the .45 takes the wrong primer family"),
    (SHARED + "AC_Calibres.lua", "                { count = calibre.powderUses, items = { AC_Calibres.POWDER.item } },", "                { count = 1, items = { AC_Calibres.POWDER.item } },", "every round takes one charge whatever its calibre"),
    (SHARED + "AC_Calibres.lua", "                { count = 1, item = calibre.round },", "                { count = 2, item = calibre.round },", "two rounds from one set of components"),
    (SHARED + "AC_Calibres.lua", "                { count = calibre.bulletsPerScrap, item = calibre.bullet },", "                { count = calibre.bulletsPerScrap + 1, item = calibre.bullet },", "an extra bullet from every scrap"),
    (SHARED + "AC_Calibres.lua", "                { count = calibre.cupsPerCase, items = { \"AmmoMaking.BrassCaseCup\" } },", "                { count = 1, items = { \"AmmoMaking.BrassCaseCup\" } },", "every case is drawn from one cup"),
    (SHARED + "AC_Calibres.lua", "    return {\n        count = 1,\n        items = { calibre.dieSet },\n        keep = true,\n    }", "    return {\n        count = 1,\n        items = { calibre.dieSet },\n    }", "the die set is consumed"),
    (SHARED + "AC_Calibres.lua", "                destroy = true,\n", "", "the wad hands back a dirty rag"),
    (SHARED + "AC_Calibres.lua", "            assembleLevel - 2\n", "            assembleLevel - 4\n", "die sets and cases unlock four levels early"),
    (SHARED + "AC_Calibres.lua", "        wads = 1,\n\n        lootTier = \"rare\",", "        wads = 0,\n\n        lootTier = \"rare\",", "a shell without a wad"),
    (SHARED + "AC_Calibres.lua", "            requiredLevel = calibre.levels.assemble,", "            requiredLevel = 0,", "assembly is open at level 0"),
    (SHARED + "AC_Calibres.lua", "            xp = calibre.xp.assemble,", "            xp = calibre.xp.assemble * 10,", "assembly pays ten times the XP"),
    (SHARED + "AC_Calibres.lua", "    requiredLevel = 3,\n\n    xp = 5,", "    requiredLevel = 3,\n\n    xp = 50,", "mixing gunpowder pays ten times the XP"),
    (SHARED + "AC_Materials.lua", "    unitsPerIngot = 100,", "    unitsPerIngot = 90,", "an ingot is ninety units"),
    (SHARED + "AC_Materials.lua", "    xpCastBrass = 25,", "    xpCastBrass = 250,", "a brass batch pays ten times the XP"),
    (SHARED + "AC_Materials.lua", "            { count = 7, items = { \"Base.CopperIngot\" } },", "            { count = 6, items = { \"Base.CopperIngot\" } },", "brass from six copper ingots"),
    (SHARED + "AC_Materials.lua", "            { count = 10, item = \"Base.BrassIngot\" },", "            { count = 11, item = \"Base.BrassIngot\" },", "eleven brass ingots from ten of metal"),
    (SHARED + "AC_Materials.lua", "            { count = 2, item = \"AmmoMaking.BrassCaseCup\" },", "            { count = 3, item = \"AmmoMaking.BrassCaseCup\" },", "three cups from a sheet"),
    (SHARED + "AC_Materials.lua", "                { count = 1, item = AC_Calibres.POWDER.item, oneUse = true },", "                { count = 1, item = AC_Calibres.POWDER.item },", "taking a round apart gives a full jar"),
    (SHARED + "AC_Materials.lua", "                AC_Materials.getRecipeXP(recipe),\n                AC_Materials.CONFIG.xpLogSource", "                AC_Materials.getRecipeXP(recipe) * 2,\n                AC_Materials.CONFIG.xpLogSource", "every craft pays double"),
    (SHARED + "AC_Materials.lua", "                AC_Materials.getRequiredLevel(recipe)\n            )\n\n\n            summary.attached =", "                0\n            )\n\n\n            summary.attached =", "no recipe is gated by level"),
    (SHARED + "AC_Mining.lua", "    xpPerOre = 5,", "    xpPerOre = 50,", "mining pays ten times the XP"),
    (SHARED + "AC_CaseQuality.lua", "    data[config.qualityKey] =\n        clamp(\n            math.floor(quality + 0.5),\n            config.minQuality,\n            config.maxQuality\n        )", "    data[config.qualityKey] =\n        math.floor(quality + 0.5)", "a case quality is stored unclamped"),

    # ---- inspection
    (SHARED + "AC_AmmoInspection.lua", "    if type(isDebugEnabled) == \"function\"\n        and isDebugEnabled()\n    then\n\n        local config = AC_CaseQuality.CONFIG", "    if true then\n\n        local config = AC_CaseQuality.CONFIG", "the debug lines of an inspection show in a normal game"),
    (SHARED + "AC_AmmoInspection.lua", "    elseif level < 5 then\n", "    elseif level < 1 then\n", "the exact case quality is shown below level 5"),

    # ---- probes that must be able to fail
    (SHARED + "AC_Compat.lua", "        elseif id == AC_Compat.DEFAULT_SPRITE_ID then", "        elseif false then", "the analyzer sprite probe accepts a sprite the engine made up on the spot"),

    # ---- per-interaction cost and housekeeping
    (SHARED + "AC_Compat.lua", "function AC_Compat.runAmmunition(\n    verbose\n)\n\n    local results = {}\n", "function AC_Compat.runAmmunition(\n    verbose\n)\n\n    AC_Compat.hasRun = true\n\n    local results = {}\n", "the ammunition-only check counts as the once-per-start check"),
    (SHARED + "AC_CaseQuality.lua", "    if item.hasModData\n        and not item:hasModData()\n    then\n        return nil\n    end\n", "", "right-clicking a factory round creates ModData on it"),
    (SHARED + "AC_Compat.lua", "function AC_Compat.resetForNewWorld()\n\n    AC_Compat.hasRun = false", "function AC_Compat.resetForNewWorld()\n\n    AC_Compat.hasRun = true", "a second save in the same session gets no compatibility check"),
    (CLIENT + "AC_MiningContextMenu.lua", "            metal,\n            samples\n        )", "            metal\n        )", "the mining menu scans the inventory once per metal"),
    (CLIENT + "AC_AmmoInspectionUI.lua", "    self.titleText =\n        self.titleText\n        or AC_Text.get(", "    self.titleText =\n        AC_Text.get(", "the inspection panel translates its title every frame"),
    (SHARED + "AC_Mining.lua", "    if samples == nil then\n", "    if not samples then\n", "an explicit 'no samples' makes findProspect scan again"),

    # ---- release metadata
    ("mod/AmmoMaking/42/mod.info", "modversion=0.9.0", "modversion=1.0.0", "the mod calls itself 1.0 with no changelog entry"),
    ("mod/AmmoMaking/42/mod.info", "versionMin=42.20.0", "versionMin=41.78.0", "the mod claims to run on Build 41"),

    # ---- data files
    ("mod/AmmoMaking/common/media/lua/shared/Translate/EN/Recipes.json", "    \"AmmoMaking_ScrapBrass10\": \"Scrap Small Brass Sheets and Medium Cases\",\n", "", "a recipe has no name"),
    ("mod/AmmoMaking/common/media/lua/shared/Translate/EN/IG_UI.json", "This record stays with the loose round; loading or boxing it keeps only a count.", "This record stays with the round.", "the inspection text no longer states the limit"),
    ("mod/AmmoMaking/42/media/scripts/AC_Recipes.txt", "            item 1 Base.BrassScrap,\n        }\n    }\n\n    craftRecipe AmmoMaking_ScrapBrass10", "            item 2 Base.BrassScrap,\n        }\n    }\n\n    craftRecipe AmmoMaking_ScrapBrass10", "the script was edited by hand to return all the brass"),
    ("mod/AmmoMaking/42/media/scripts/AC_Items.txt", "    item DieSet9mm", "    item DieSet38Special", "a duplicate item id"),
    ("tests/vanilla_snapshot.lua", "            GunStoreMagsAmmo = { rolls = 4, entries = 34, weight = 360.5, references = 1 },", "            GunStoreMagsAmmo = { rolls = 4, entries = 0, weight = 0, references = 0 },", "the gun store list has become unused in vanilla"),
    ("tests/vanilla_snapshot.lua", "            [\"Base.Bullets9mm\"] = { box = \"Base.Bullets9mmBox\", perBox = 50,", "            [\"Base.Bullets9mm\"] = { box = \"Base.Bullets9mmBox\", perBox = 30,", "vanilla's 9mm box holds thirty"),
    ("mod/AmmoMaking/42/media/scripts/AC_Items.txt", "        DisplayName = Empty 9mm Case,\n        DisplayCategory = Ammo,\n        ItemType = base:normal,\n        Weight = 0.005,", "        DisplayName = Empty 9mm Case,\n        DisplayCategory = Ammo,\n        ItemType = base:normal,\n        Weight = 0.05,", "a 9mm case heavier than the round it goes into"),
    # ---- geology equipment (the kits and the analyzer)
    (SHARED + "AC_Materials.lua", "        callback = \"onAssembleFieldAssayKit\",\n\n        xp = 0,", "        callback = \"onAssembleFieldAssayKit\",\n\n        xp = 5,", "putting a field kit together pays XP"),
    (SHARED + "AC_Materials.lua", "        callback = \"onAssembleFieldAssayKit\",\n\n        xp = 0,\n\n        requiredLevel = 0,", "        callback = \"onAssembleFieldAssayKit\",\n\n        xp = 0,\n\n        requiredLevel = 3,", "the first kit needs a skill level nobody has yet"),
    (SHARED + "AC_Materials.lua", "        callback = \"onAssembleAdvancedFieldAssayKit\",\n\n        xp = 0,\n\n        requiredLevel = 1,", "        callback = \"onAssembleAdvancedFieldAssayKit\",\n\n        xp = 0,\n\n        requiredLevel = 0,", "the advanced kit needs no more skill than the field kit"),
    (SHARED + "AC_Materials.lua", "            { count = 1, items = { \"Base.Calculator\" } },", "            { count = 1, items = { \"AmmoMaking.FieldAssayKit\" } },", "a used-up field kit becomes a fresh advanced kit"),
    (SHARED + "AC_Materials.lua", "            { count = 4, items = { \"Base.SheetMetal\" } },", "            { count = 1, items = { \"Base.SheetMetal\" } },", "a 12 kg analyzer from 6 kg of parts"),
    (SHARED + "AC_Materials.lua", "    { count = 5, items = { \"Base.SheetPaper2\" } },", "    { count = 5, items = { \"Base.GunPowder\" } },", "a kit takes uses of a drainable"),
    (SHARED + "AC_Materials.lua", "    AC_Materials.EQUIPMENT_RECIPES\n)\ndo\n\n    table.insert(\n        AC_Materials.RECIPES,\n        recipe\n    )\nend\n", "    {}\n)\ndo\n\n    table.insert(\n        AC_Materials.RECIPES,\n        recipe\n    )\nend\n", "the equipment recipes never join the recipe list"),
    (SHARED + "AC_Compat.lua", "    \"Base.CarBatteryCharger\",\n", "", "an ingredient of the analyzer is not probed at game start"),

    (SHARED + "AC_Materials.lua", "    { count = 1, items = { \"Base.Tweezers\", \"Base.Tweezers_Forged\" } },", "    { count = 1, items = { \"AmmoMaking.LaboratoryAssayAnalyzer\" } },", "every kit needs an analyzer, and nothing makes the first instrument cheaply"),

    (CLIENT + "AC_GeologyDebug.lua", "                entry[2] =\n                    entry[2] + input.count\n", "                entry[2] =\n                    entry[2] + 1\n", "the debug parts kit holds one of each part, not what the recipes take"),

    (SHARED + "AC_Materials.lua", "            { count = 1, items = { \"Base.Amplifier\" }, flags = { \"NoBrokenItems\" } },", "            { count = 1, items = { \"Base.HomeAlarm\" } },", "the analyzer takes a part that is not probed and whose availability nobody recorded"),
    (SHARED + "AC_Materials.lua", "            { count = 1, items = { \"Base.LightBulb\" }, flags = { \"NoBrokenItems\" } },", "            { count = 1, items = { \"Base.LightBulb\" } },", "a burnt-out bulb builds an analyzer"),

    # ---- feature switches
    (SHARED + "AC_Features.lua", "    return options[option] == true\n", "    return options[option] ~= nil\n", "any sandbox value switches a feature on"),
    (SHARED + "AC_Features.lua", "    return\n        mods:contains(modId) == true\n        or mods:contains(\"\\\\\" .. modId) == true\n", "    return true\n", "every add-on counts as active"),
    (SHARED + "AC_Features.lua", "    if definition.stability ~= AC_Features.EXPERIMENTAL then\n        return false, \"locked\"\n    end\n", "", "a locked feature can be switched on"),
    (SHARED + "AC_Features.lua", "    if definition.singlePlayerOnly\n        and AC_Features.isMultiplayer()\n    then\n        return false, \"multiplayer\"\n    end\n", "", "a single-player feature runs on a multiplayer client"),
    (SHARED + "AC_Features.lua", "        if AC_Features.isModActive(other) then\n            return false, \"conflict with \" .. other\n        end\n", "", "spent cases run beside a mod that already leaves casings"),
    (SHARED + "AC_Features.lua", "        stability = AC_Features.DISABLED,", "        stability = AC_Features.EXPERIMENTAL,", "firing effects are unlocked"),
    (SHARED + "AC_Features.lua", "    if definition.requires\n        and not AC_Features.isEnabled(definition.requires)\n    then\n        return false, \"needs \" .. definition.requires\n    end\n", "", "a feature runs without the one it needs"),

    # ---- the press add-on
    ("mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress.txt", "            Recipes = AmmoMakingReloadingPress,", "            Recipes = HandPress,", "the press station offers vanilla's hand press recipes instead of its own"),
    ("mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress.txt", "                    row = ammomaking_press_01_1,", "                    row = crafted_01_73,", "the press claims a sprite of vanilla's hand press"),
    ("mod/AmmoMakingPress/42/mod.info", "require=\\AmmoMaking\n", "", "the press add-on can be enabled without the main mod"),
    ("mod/AmmoMakingPress/42/mod.info", "tiledef=ammomaking_press 6142\n", "", "the press add-on does not declare its tile sheet"),
    ("art/reloading_press/tiles.json", "\"output\": \"../../mod/AmmoMakingPress/42/media\",", "\"output\": \"../../mod/AmmoMaking/42/media\",", "the press tile sheet is built into the main mod"),
    (SHARED + "AC_Visuals.lua", "        value = \"ammomaking_press_01_1\",", "        value = \"ammomaking_press_01_0\",", "the game-start check probes the south sprite twice and never the east one"),
    (SHARED + "AC_Compat.lua", "    checkLoot(results)\n\n    checkFeatures(results)\n", "    checkLoot(results)\n", "the game-start check never looks at the features"),

    # ---- the test harness itself
    ("tests/mock_pz.lua", "    return (state * 48271) % 2147483647", "    return (state * 1103515245 + 12345) % 2147483648", "the test generator loses bits in Lua's doubles and loops"),
]


def read(path):
    with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
        return handle.read()


def write(path, text):
    with io.open(os.path.join(ROOT, path), "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def apply(text, old, new):
    """The mutated text, or None when old is not found exactly once.

    Files may use either line ending; the mutant is written with LF.
    """
    crlf = "\r\n" in text
    plain = text.replace("\r\n", "\n")
    if plain.count(old) != 1:
        return None
    mutated = plain.replace(old, new)
    return mutated.replace("\n", "\r\n") if crlf else mutated


# A healthy run takes a few seconds. A mutant can turn a bounded loop into
# an endless one; that is a fault the suite noticed, not a run to wait for.
TIMEOUT = 120


def run_suite():
    """Runs the suite in a process of its own. Returns (passed, failed, error).

    A process, so that a suite which never ends can be stopped: the file is
    then restored by the caller as for any other mutant.
    """
    try:
        result = subprocess.run([sys.executable, os.path.abspath(__file__), "--suite"], capture_output=True, text=True, errors="replace", timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, None, "the suite did not finish in %d seconds" % TIMEOUT
    # The last line is "passed<TAB>failed<TAB>error"; the error may be empty,
    # so the line must not be stripped of its trailing tab.
    lines = [line for line in result.stdout.split("\n") if line.strip()]
    line = lines[-1].rstrip("\r") if lines else ""
    parts = line.split("\t")
    if len(parts) != 3:
        return None, None, "the suite process ended without a result: %s" % (result.stderr.strip().splitlines() or [line])[-1][:200]
    passed = int(parts[0]) if parts[0] != "None" else None
    failed = int(parts[1]) if parts[1] != "None" else None
    return passed, failed, (parts[2] or None)


def run_suite_here():
    """Runs tests/run_tests.lua in a fresh Lua state. Returns (passed, failed, error)."""
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('arg = { [0] = "%s/tests/run_tests.lua" }' % ROOT)
    lua.execute('''
        __summary = nil
        print = function(...)
            local first = tostring((select(1, ...)))
            if string.find(first, "^Passed: ") then __summary = first end
        end
        os.exit = function() error("__exit__", 0) end
    ''')
    error = None
    try:
        lua.execute("dofile(arg[0])")
    except Exception as raised:  # a Lua error, or the suite's own exit
        if "__exit__" not in str(raised):
            error = str(raised).splitlines()[0][:200]
    summary = lua.globals()["__summary"]
    passed = failed = None
    if summary:
        parts = summary.replace("Passed:", "").replace("Failed:", "").split()
        passed, failed = int(parts[0]), int(parts[1])
    return passed, failed, error


def main():
    arguments = sys.argv[1:]
    if arguments == ["--suite"]:
        passed, failed, error = run_suite_here()
        print("%s\t%s\t%s" % (passed, failed, (error or "").replace("\t", " ").replace("\n", " ")))
        return 0
    invalid = []
    for index, (path, old, new, what) in enumerate(MUTANTS, 1):
        if apply(read(path), old, new) is None:
            invalid.append((index, path, what))
    for index, path, what in invalid:
        print("DOES NOT APPLY %3d  %s  (%s)" % (index, what, path))
    if arguments and arguments[0] == "check":
        print("%d mutants, %d do not apply" % (len(MUTANTS), len(invalid)))
        return 1 if invalid else 0
    if invalid:
        return 1

    passed, failed, error = run_suite()
    if error or failed != 0:
        print("The suite is not green before any mutation: %s failed, %s" % (failed, error))
        return 1
    print("Baseline: %d passed, 0 failed" % passed, flush=True)

    chosen = [int(a) for a in arguments] or range(1, len(MUTANTS) + 1)
    survived = []
    for index in chosen:
        path, old, new, what = MUTANTS[index - 1]
        original = read(path)
        try:
            write(path, apply(original, old, new))
            passed, failed, error = run_suite()
        finally:
            write(path, original)
        killed = bool(error) or failed is None or failed > 0
        how = ("error: " + error) if error else ("%s checks failed" % failed)
        print("%-8s %3d  %s  [%s]" % ("killed" if killed else "SURVIVED", index, what, how), flush=True)
        if not killed:
            survived.append((index, what))

    print("")
    print("%d mutants run, %d killed, %d survived" % (len(chosen), len(chosen) - len(survived), len(survived)))
    for index, what in survived:
        print("  survived: %3d  %s" % (index, what))
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
