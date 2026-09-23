-- Ammo Making - Runtime compatibility self-check
-- Project Zomboid Build 42.20
--
-- Several assumptions about vanilla Build 42 (item ids,
-- engine functions, square methods) cannot be verified
-- outside the game. This module checks them once when a
-- game starts and prints one concise line per check:
--
--     [AmmoMaking] OK: Base.CopperOre
--     [AmmoMaking] WARNING: Base.PickAxeForged not found
--     [AmmoMaking] UNVERIFIED: world item spawn (no square)
--
-- OK          the assumption holds on this build
-- WARNING     the assumption is wrong; the affected
--             feature will not work as intended
-- UNVERIFIED  the check could not be performed safely
--             here (needs an in-game test instead)
--
-- It never changes game state and never raises: every
-- probe is pcall-guarded. It runs once per game start;
-- the debug menu can run it again on demand.

AC_Compat = AC_Compat or {}


AC_Compat.hasRun =
    AC_Compat.hasRun or false


AC_Compat.lastResults =
    AC_Compat.lastResults or nil


------------------------------------------------
-- ITEM IDS THE MOD DEPENDS ON
------------------------------------------------

AC_Compat.REQUIRED_ITEMS = {

    "Base.CopperOre",

    "Base.PickAxe",

    "Base.PickAxeForged",

    "AmmoMaking.ZincOre",

    "AmmoMaking.GeologicalSample",

    "AmmoMaking.FieldAssayKit",

    "AmmoMaking.AdvancedFieldAssayKit",

    "AmmoMaking.LaboratoryAssayAnalyzer",
}


------------------------------------------------
-- HELPERS
------------------------------------------------

local function safe(
    fn,
    ...
)

    local ok,
          result =
        pcall(
            fn,
            ...
        )


    if not ok then
        return nil, result
    end


    return result, nil
end


------------------------------------------------
-- Does a Java object expose a method of this name?
--
-- Kahlua returns the method object for obj.name, so
-- a nil means the method does not exist on this build.
-- Any error is reported as "unknown" rather than as a
-- missing method.
------------------------------------------------

local function hasMethod(
    object,
    name
)

    if object == nil then
        return nil
    end


    local ok,
          result =
        pcall(
            function()

                return
                    object[name] ~= nil
            end
        )


    if not ok then
        return nil
    end


    return result
end


local function addResult(
    results,
    status,
    label,
    detail
)

    table.insert(
        results,
        {
            status = status,

            label = label,

            detail = detail,
        }
    )
end


------------------------------------------------
-- INDIVIDUAL CHECKS
------------------------------------------------

local function checkScriptItems(
    results
)

    local manager =
        safe(
            function()

                return
                    getScriptManager()
            end
        )


    if not manager then

        for _,
            itemType
        in ipairs(
            AC_Compat.REQUIRED_ITEMS
        )
        do

            addResult(
                results,
                "UNVERIFIED",
                itemType,
                "no script manager"
            )
        end


        return
    end


    for _,
        itemType
    in ipairs(
        AC_Compat.REQUIRED_ITEMS
    )
    do

        local script,
              err =
            safe(
                function()

                    return
                        manager:FindItem(
                            itemType
                        )
                end
            )


        if err then

            addResult(
                results,
                "UNVERIFIED",
                itemType,
                tostring(err)
            )

        elseif script then

            addResult(
                results,
                "OK",
                itemType
            )

        else

            addResult(
                results,
                "WARNING",
                itemType .. " not found",
                "item script missing on this build"
            )
        end
    end
end


local function checkItemFactory(
    results
)

    if type(instanceItem) == "function" then

        addResult(
            results,
            "OK",
            "item factory (instanceItem)"
        )


        return
    end


    if InventoryItemFactory
        and InventoryItemFactory.CreateItem
    then

        addResult(
            results,
            "OK",
            "item factory (InventoryItemFactory.CreateItem)"
        )


        return
    end


    addResult(
        results,
        "WARNING",
        "item factory missing",
        "neither instanceItem nor InventoryItemFactory.CreateItem exists"
    )
end


local function checkModData(
    results
)

    if ModData
        and ModData.getOrCreate
    then

        local store,
              err =
            safe(
                function()

                    return
                        ModData.getOrCreate(
                            AC_Deposits.CONFIG.modDataKey
                        )
                end
            )


        if type(store) == "table" then

            addResult(
                results,
                "OK",
                "global ModData (" .. AC_Deposits.CONFIG.modDataKey .. ")"
            )

        else

            addResult(
                results,
                "WARNING",
                "global ModData unusable",
                tostring(err)
            )
        end


        return
    end


    addResult(
        results,
        "WARNING",
        "ModData.getOrCreate missing",
        "depletion cannot be persisted"
    )
end


local function getProbeSquare()

    local player =
        safe(
            function()

                return
                    getPlayer()
            end
        )


    if not player then
        return nil, nil
    end


    local square =
        safe(
            function()

                return
                    player:getSquare()
            end
        )


    return square, player
end


local function checkSquareMethods(
    results,
    square
)

    if not square then

        addResult(
            results,
            "UNVERIFIED",
            "world item spawn (AddWorldInventoryItem)",
            "no player square available"
        )


        addResult(
            results,
            "UNVERIFIED",
            "water detection",
            "no player square available"
        )


        return
    end


    local spawn =
        hasMethod(
            square,
            "AddWorldInventoryItem"
        )


    if spawn == true then

        addResult(
            results,
            "OK",
            "world item spawn (AddWorldInventoryItem)"
        )

    elseif spawn == false then

        addResult(
            results,
            "WARNING",
            "IsoGridSquare:AddWorldInventoryItem missing",
            "mined ore cannot be dropped on the ground"
        )

    else

        addResult(
            results,
            "UNVERIFIED",
            "world item spawn (AddWorldInventoryItem)",
            "method lookup failed"
        )
    end


    ------------------------------------------------
    -- Water detection: either API is enough.
    ------------------------------------------------

    if hasMethod(square, "hasWater") == true then

        addResult(
            results,
            "OK",
            "water detection (hasWater)"
        )

    elseif IsoFlagType
        and IsoFlagType.water
        and hasMethod(square, "Is") == true
    then

        addResult(
            results,
            "OK",
            "water detection (Is(IsoFlagType.water))"
        )

    else

        addResult(
            results,
            "WARNING",
            "water detection unavailable",
            "water tiles will pass the terrain check"
        )
    end


    for _,
        name
    in ipairs(
        { "getFloor", "getRoom", "getZ" }
    )
    do

        if hasMethod(square, name) == true then

            addResult(
                results,
                "OK",
                "IsoGridSquare:" .. name
            )

        else

            addResult(
                results,
                "WARNING",
                "IsoGridSquare:" .. name .. " missing",
                "terrain validation depends on it"
            )
        end
    end
end


local function checkCharacterMethods(
    results,
    player
)

    local names = {
        "getPrimaryHandItem",
        "getSecondaryHandItem",
        "getInventory",
        "getXp",
        "getPerkLevel",
        "faceLocation",
        "setMetabolicTarget",
        "addCombatMuscleStrain",
        "getEmitter",
        "isTimedActionInstant",
    }


    for _,
        name
    in ipairs(
        names
    )
    do

        local present =
            hasMethod(
                player,
                name
            )


        if present == true then

            addResult(
                results,
                "OK",
                "IsoPlayer:" .. name
            )

        elseif present == false then

            addResult(
                results,
                "WARNING",
                "IsoPlayer:" .. name .. " missing",
                "used by the sampling/mining timed actions"
            )

        else

            addResult(
                results,
                "UNVERIFIED",
                "IsoPlayer:" .. name,
                "no player available"
            )
        end
    end
end


local function checkGlobals(
    results
)

    local checks = {

        { "getTextOrNull", function() return type(getTextOrNull) == "function" end, "translation lookups fall back to English" },

        { "isDebugEnabled", function() return type(isDebugEnabled) == "function" end, "debug menus stay hidden" },

        { "ZombRand / ZombRandFloat", function() return type(ZombRand) == "function" and type(ZombRandFloat) == "function" end, "randomness for wear and item placement" },

        { "HaloTextHelper.addText", function() return HaloTextHelper ~= nil and HaloTextHelper.addText ~= nil end, "on-screen feedback" },

        { "luautils.walkAdj", function() return luautils ~= nil and luautils.walkAdj ~= nil end, "walking to the sampling/mining tile" },

        { "ISTimedActionQueue.add", function() return ISTimedActionQueue ~= nil and ISTimedActionQueue.add ~= nil end, "timed actions" },

        { "ISBaseTimedAction", function() return ISBaseTimedAction ~= nil end, "timed actions" },

        { "ISWorldObjectContextMenu.addToolTip", function() return ISWorldObjectContextMenu ~= nil and ISWorldObjectContextMenu.addToolTip ~= nil end, "tooltips on disabled options" },

        { "BuildingHelper.getShovelAnim", function() return BuildingHelper ~= nil and BuildingHelper.getShovelAnim ~= nil end, "placeholder digging animation (falls back to DigShovel)" },

        { "Metabolics.DiggingSpade", function() return Metabolics ~= nil and Metabolics.DiggingSpade ~= nil end, "metabolic load while digging/mining" },

        { "Perks.Strength", function() return Perks ~= nil and Perks.Strength ~= nil end, "muscle strain scaling" },

        { "Ammo Making perk registered", function() return AmmoMakingSkill ~= nil and AmmoMakingSkill.perk ~= nil end, "XP cannot be granted" },
    }


    for _,
        check
    in ipairs(
        checks
    )
    do

        local label,
              probe,
              consequence =
            check[1],
            check[2],
            check[3]


        local present,
              err =
            safe(
                probe
            )


        if err then

            addResult(
                results,
                "UNVERIFIED",
                label,
                tostring(err)
            )

        elseif present then

            addResult(
                results,
                "OK",
                label
            )

        else

            addResult(
                results,
                "WARNING",
                label .. " missing",
                consequence
            )
        end
    end
end


local function checkTranslations(
    results
)

    if type(getTextOrNull) ~= "function" then
        return
    end


    local perkName =
        safe(
            function()

                return
                    getTextOrNull(
                        "IGUI_perks_AmmoMaking"
                    )
            end
        )


    if type(perkName) == "string" then

        addResult(
            results,
            "OK",
            "translation file loaded (IGUI_perks_AmmoMaking = " .. perkName .. ")"
        )

    else

        addResult(
            results,
            "WARNING",
            "translation file not loaded",
            "English fallbacks are used for all mod text"
        )
    end


    ------------------------------------------------
    -- The skill panel builds level description keys
    -- from the perk name. Report which spelling the
    -- engine resolves so the JSON can be corrected
    -- after an in-game check.
    ------------------------------------------------

    local spaced =
        safe(
            function()

                return
                    getTextOrNull(
                        "IGUI_perks_Ammo Making_Description1"
                    )
            end
        )


    local joined =
        safe(
            function()

                return
                    getTextOrNull(
                        "IGUI_perks_AmmoMaking_Description1"
                    )
            end
        )


    if type(spaced) == "string"
        or type(joined) == "string"
    then

        addResult(
            results,
            "OK",
            "perk level descriptions resolve ("
            .. (type(spaced) == "string" and "spaced key" or "joined key")
            .. ")"
        )

    else

        addResult(
            results,
            "UNVERIFIED",
            "perk level descriptions",
            "neither IGUI_perks_Ammo Making_Description1 nor IGUI_perks_AmmoMaking_Description1 resolves; check the skill panel in game"
        )
    end
end


local function checkGeologySeed(
    results
)

    local seed,
          err =
        safe(
            function()

                return
                    AC_WorldData.getGeologySeed()
            end
        )


    if type(seed) == "number" then

        addResult(
            results,
            "OK",
            "geology seed derived from save identity (" .. tostring(seed) .. ")"
        )

    else

        addResult(
            results,
            "WARNING",
            "geology seed unavailable",
            tostring(err or "save identity missing")
        )
    end
end


------------------------------------------------
-- RUN
------------------------------------------------
--
-- Returns the result list and a summary table:
--
--   { ok = n, warnings = n, unverified = n }
------------------------------------------------

function AC_Compat.run()

    local results = {}


    checkScriptItems(results)

    checkItemFactory(results)

    checkModData(results)


    local square,
          player =
        getProbeSquare()


    checkSquareMethods(
        results,
        square
    )


    checkCharacterMethods(
        results,
        player
    )


    checkGlobals(results)

    checkTranslations(results)

    checkGeologySeed(results)


    local summary = {

        ok = 0,

        warnings = 0,

        unverified = 0,
    }


    for _,
        result
    in ipairs(
        results
    )
    do

        local line =
            "[AmmoMaking] "
            .. result.status
            .. ": "
            .. result.label


        if result.detail
            and result.status ~= "OK"
        then

            line =
                line
                .. " ("
                .. tostring(result.detail)
                .. ")"
        end


        print(line)


        if result.status == "OK" then

            summary.ok =
                summary.ok + 1

        elseif result.status == "WARNING" then

            summary.warnings =
                summary.warnings + 1

        else

            summary.unverified =
                summary.unverified + 1
        end
    end


    print(
        "[AmmoMaking] Compatibility check: "
        .. summary.ok
        .. " ok, "
        .. summary.warnings
        .. " warnings, "
        .. summary.unverified
        .. " unverified"
    )


    AC_Compat.hasRun =
        true


    AC_Compat.lastResults =
        results


    return results, summary
end


------------------------------------------------
-- Run once per game start. The whole run is
-- pcall-guarded: a bug in the diagnostics must never
-- break the game.
------------------------------------------------

function AC_Compat.runOnce()

    if AC_Compat.hasRun then
        return
    end


    local ok,
          err =
        pcall(
            AC_Compat.run
        )


    if not ok then

        print(
            "[AmmoMaking] WARNING: compatibility check failed: "
            .. tostring(err)
        )


        AC_Compat.hasRun =
            true
    end
end


Events.OnGameStart.Add(
    AC_Compat.runOnce
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Compatibility check loaded"
)
