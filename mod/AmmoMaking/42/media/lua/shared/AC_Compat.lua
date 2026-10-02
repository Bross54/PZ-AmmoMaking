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
-- OK lines are printed only in -debug mode (or when the
-- caller asks for them). A normal game start prints what
-- needs attention, WARNING and UNVERIFIED, and a short
-- summary:
--
--     [AmmoMaking] Pistol calibres: 5/5 complete
--     [AmmoMaking] Rifle calibres: 3/3 complete
--     [AmmoMaking] Shotgun shells: 1/1 complete
--     [AmmoMaking] Compatibility check: 171 ok, 0 warnings, 0 unverified
--
-- It never changes game state and never raises: every
-- probe is pcall-guarded. It runs once per game start;
-- the debug menu can run it again on demand.

require "AC_Calibres"
require "AC_Loot"
require "AC_Recycling"

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

    -- Metallurgy: the vanilla items the furnace recipes
    -- consume, keep and produce, and the mod's zinc chain.
    "AmmoMaking.ZincScrap",

    "AmmoMaking.ZincIngot",

    "Base.CopperScrap",

    "Base.CopperIngot",

    "Base.BrassIngot",

    "Base.BrassScrap",

    "Base.CeramicCrucible",

    "Base.ClayIngotMold",

    "Base.IronIngotMold",

    "Base.SteelIngotMold",

    "Base.Tongs",

    "Base.Charcoal",

    -- Case stock: brass sheets and cups, and the vanilla
    -- hand tools the debug kit hands out.
    "AmmoMaking.SmallBrassSheet",

    "AmmoMaking.BrassCaseCup",

    "Base.BallPeenHammer",

    "Base.MetalworkingPunch",
}


------------------------------------------------
-- Ammunition components: every item the component
-- recipes name by id, taken from the calibre model so a
-- new calibre is probed without editing this file, and
-- the vanilla tools the debug kits hand out.
------------------------------------------------

for _,
    itemType
in ipairs(
    AC_Calibres.getItems()
)
do

    local known = false


    for _,
        existing
    in ipairs(
        AC_Compat.REQUIRED_ITEMS
    )
    do

        if existing == itemType then
            known = true
        end
    end


    if not known then

        table.insert(
            AC_Compat.REQUIRED_ITEMS,
            itemType
        )
    end
end


for _,
    itemType
in ipairs(
    { "Base.MortarPestle", "Base.Hammer" }
)
do

    table.insert(
        AC_Compat.REQUIRED_ITEMS,
        itemType
    )
end


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


        addResult(
            results,
            "UNVERIFIED",
            "laboratory analyzer square methods",
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
    -- Water detection: hasWater() only. The old
    -- square:Is(IsoFlagType.water) fallback does not
    -- exist on 42.20.4 and is no longer used.
    ------------------------------------------------

    if hasMethod(square, "hasWater") == true then

        addResult(
            results,
            "OK",
            "water detection (hasWater)"
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


    ------------------------------------------------
    -- Placed laboratory analyzer.
    ------------------------------------------------

    for _,
        check
    in ipairs(
        {
            { "AddSpecialObject", "the laboratory analyzer cannot be placed" },

            { "getSpecialObjects", "a placed analyzer is not found by the menu" },

            { "transmitRemoveItemFromSquare", "the laboratory analyzer cannot be picked up" },

            { "RemoveTileObject", "the laboratory analyzer cannot be picked up" },

            { "hasGridPower", "analyzer grid power falls back to the world hydro flag" },
        }
    )
    do

        if hasMethod(square, check[1]) == true then

            addResult(
                results,
                "OK",
                "IsoGridSquare:" .. check[1]
            )

        else

            addResult(
                results,
                "WARNING",
                "IsoGridSquare:" .. check[1] .. " missing",
                check[2]
            )
        end
    end
end


local function checkCharacterMethods(
    results,
    player
)

    local groups = {

        {
            consequence = "used by the sampling/mining timed actions",

            names = {
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
            },
        },

        {
            consequence = "used by laboratory analyzer placement and pickup",

            names = {
                "setPrimaryHandItem",
                "setSecondaryHandItem",
                "getPlayerNum",
                "SetVariable",
            },
        },
    }


    for _,
        group
    in ipairs(
        groups
    )
    do

        for _,
            name
        in ipairs(
            group.names
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
                    group.consequence
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

        { "ISBuildingObject", function() return ISBuildingObject ~= nil and ISBuildingObject.derive ~= nil end, "the laboratory analyzer cannot be placed" },

        { "IsoThumpable.new", function() return IsoThumpable ~= nil and IsoThumpable.new ~= nil end, "the laboratory analyzer cannot be placed" },

        { "getCell", function() return type(getCell) == "function" end, "the analyzer placement cursor cannot start" },

        { "ISInventoryPaneContextMenu.transferIfNeeded", function() return ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.transferIfNeeded ~= nil end, "an analyzer in a bag is not moved to the main inventory before placing" },

        { "AC_LaboratoryAnalyzerObject loaded", function() return AC_LaboratoryAnalyzerObject ~= nil end, "server/BuildingObjects/AC_LaboratoryAnalyzerObject.lua did not load; the analyzer cannot be placed" },

        { "Metabolics.HeavyDomestic", function() return Metabolics ~= nil and Metabolics.HeavyDomestic ~= nil end, "metabolic load while picking up the analyzer" },

        { "AC_CaseQuality effects", function() return AC_CaseQuality ~= nil and AC_CaseQuality.EFFECTS ~= nil and AC_CaseQuality.EFFECTS.caseQuality ~= nil and AC_CaseQuality.EFFECTS.roundQuality ~= nil end, "formed cases get no quality" },
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
-- The placed analyzer's temporary vanilla sprite.
-- Vanilla code treats a nil getSprite(name) as "no
-- such tile", which is what this relies on.
------------------------------------------------

local function checkAnalyzerSprite(
    results
)

    local spriteName =
        AC_LaboratoryAnalyzer.CONFIG.worldSprite


    if type(getSprite) ~= "function" then

        addResult(
            results,
            "UNVERIFIED",
            "analyzer world sprite " .. tostring(spriteName),
            "getSprite unavailable"
        )


        return
    end


    local sprite,
          err =
        safe(
            function()

                return
                    getSprite(
                        spriteName
                    )
            end
        )


    if err then

        addResult(
            results,
            "UNVERIFIED",
            "analyzer world sprite " .. tostring(spriteName),
            tostring(err)
        )

    elseif sprite then

        addResult(
            results,
            "OK",
            "analyzer world sprite (" .. tostring(spriteName) .. ")"
        )

    else

        addResult(
            results,
            "WARNING",
            "analyzer world sprite " .. tostring(spriteName) .. " not found",
            "a placed analyzer would be invisible; change AC_LaboratoryAnalyzer.CONFIG.worldSprite"
        )
    end
end


------------------------------------------------
-- Station recipes (media/scripts/AC_Recipes.txt):
-- metallurgy and case stock.
--
-- Each recipe must be known to the script manager,
-- its OnCreate callback must exist, and the Ammo
-- Making requirement AC_Materials attaches at boot
-- must be there. Read-only: nothing is attached here.
------------------------------------------------

local function checkMetallurgyRecipes(
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

        addResult(
            results,
            "UNVERIFIED",
            "station recipes",
            "no script manager"
        )


        return
    end


    if hasMethod(manager, "getCraftRecipe") ~= true then

        addResult(
            results,
            "WARNING",
            "ScriptManager:getCraftRecipe missing",
            "the mod's recipes cannot be checked or given their skill requirement"
        )


        return
    end


    local skillMethodsReported = false


    for _,
        recipe
    in ipairs(
        AC_Materials.RECIPES
    )
    do

        local script,
              err =
            safe(
                function()

                    return
                        manager:getCraftRecipe(
                            recipe.id
                        )
                end
            )


        if err then

            addResult(
                results,
                "UNVERIFIED",
                "recipe " .. recipe.id,
                tostring(err)
            )

        elseif not script then

            addResult(
                results,
                "WARNING",
                "recipe " .. recipe.id .. " not found",
                "AC_Recipes.txt did not load; this recipe is unavailable"
            )

        else

            addResult(
                results,
                "OK",
                "recipe " .. recipe.id
            )


            local canAttach =
                hasMethod(script, "addRequiredSkill") == true
                and hasMethod(script, "getRequiredSkillCount") == true


            if not skillMethodsReported then

                skillMethodsReported = true


                if canAttach then

                    addResult(
                        results,
                        "OK",
                        "CraftRecipe:addRequiredSkill"
                    )

                else

                    addResult(
                        results,
                        "WARNING",
                        "CraftRecipe:addRequiredSkill missing",
                        "the mod's recipes get no Ammo Making requirement; craft time does not improve with skill"
                    )
                end
            end


            if canAttach then

                local count =
                    safe(
                        function()

                            return
                                script:getRequiredSkillCount()
                        end
                    )


                if type(count) == "number"
                    and count > 0
                then

                    addResult(
                        results,
                        "OK",
                        "Ammo Making requirement on " .. recipe.id
                    )

                else

                    addResult(
                        results,
                        "WARNING",
                        "Ammo Making requirement not attached to " .. recipe.id,
                        AC_Materials.getRequiredLevel(recipe) > 0
                            and ("the recipe is not gated at Ammo Making " .. AC_Materials.getRequiredLevel(recipe))
                            or "craft time does not improve with skill"
                    )
                end
            end
        end


        if type(AC_Materials[recipe.callback]) ~= "function" then

            addResult(
                results,
                "WARNING",
                "OnCreate callback AC_Materials." .. tostring(recipe.callback) .. " missing",
                "no Ammo Making XP for " .. recipe.id
            )
        end
    end
end


------------------------------------------------
-- Calibres (AC_Calibres).
--
-- First the model itself: a definition that shares an
-- item with another calibre, names an unknown primer
-- family or has a fractional amount is a WARNING with
-- the calibre's name.
--
-- Then one line per calibre: complete, or which of its
-- items and recipes this build does not have. A calibre
-- that is incomplete does not stop the others, and
-- nothing here stops the game.
------------------------------------------------

local function checkCalibres(
    results
)

    local problems,
          err =
        safe(
            AC_Calibres.validate
        )


    if err then

        addResult(
            results,
            "UNVERIFIED",
            "calibre model",
            tostring(err)
        )

    elseif #problems == 0 then

        addResult(
            results,
            "OK",
            "calibre model (" .. #AC_Calibres.LIST .. " calibres, " .. #AC_Calibres.PRIMERS .. " primer families)"
        )

    else

        for _,
            problem
        in ipairs(
            problems
        )
        do

            addResult(
                results,
                "WARNING",
                "calibre model: " .. problem,
                "its recipes may take the wrong component or create material"
            )
        end
    end


    -- The prepared press recipes: reported only when their
    -- description is wrong, since the press is not in the
    -- game yet.
    for _,
        problem
    in ipairs(
        safe(AC_Calibres.validatePress) or {}
    )
    do

        addResult(
            results,
            "WARNING",
            "calibre model: " .. problem,
            "the prepared press recipes would be wrong"
        )
    end


    local manager =
        safe(
            function()

                return
                    getScriptManager()
            end
        )


    if not manager then

        addResult(
            results,
            "UNVERIFIED",
            "calibres",
            "no script manager"
        )


        return
    end


    local canFindRecipes =
        hasMethod(manager, "getCraftRecipe") == true


    local classTally = {}


    results.calibreSummary = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local missing = {}


        local primer =
            AC_Calibres.getPrimer(
                calibre.primerFamily
            )


        local itemTypes = {
            calibre.round,
            calibre.case,
            calibre.bullet,
            calibre.dieSet,
            primer and primer.item or nil,
        }


        -- A shell's wadding: every alternative its recipe
        -- line names.
        if (calibre.wads or 0) > 0 then

            for _,
                itemType
            in ipairs(
                AC_Calibres.WAD.items
            )
            do

                table.insert(
                    itemTypes,
                    itemType
                )
            end
        end


        for _,
            itemType
        in pairs(
            itemTypes
        )
        do

            local script =
                safe(
                    function()

                        return
                            manager:FindItem(
                                itemType
                            )
                    end
                )


            if not script then

                table.insert(
                    missing,
                    itemType
                )
            end
        end


        if canFindRecipes then

            for _,
                recipe
            in ipairs(
                AC_Calibres.buildCalibreRecipes(calibre)
            )
            do

                local script =
                    safe(
                        function()

                            return
                                manager:getCraftRecipe(
                                    recipe.id
                                )
                        end
                    )


                if not script then

                    table.insert(
                        missing,
                        recipe.id
                    )
                end
            end
        end


        -- Tally per class, in the order the classes first
        -- appear in the list, for the summary lines.
        local tally =
            classTally[calibre.class]


        if not tally then

            local class =
                AC_Calibres.CLASSES[calibre.class] or {}


            tally = {

                class = calibre.class,

                label = class.label or (tostring(calibre.class) .. " calibres"),

                complete = 0,

                total = 0,
            }


            classTally[calibre.class] = tally


            table.insert(
                results.calibreSummary,
                tally
            )
        end


        tally.total =
            tally.total + 1


        if #missing == 0 then

            tally.complete =
                tally.complete + 1


            addResult(
                results,
                "OK",
                "calibre " .. calibre.id .. " complete"
            )

        else

            table.sort(
                missing
            )


            addResult(
                results,
                "WARNING",
                "calibre " .. calibre.id .. " incomplete",
                "missing " .. table.concat(missing, ", ") .. "; the other calibres are unaffected"
            )
        end
    end


    ------------------------------------------------
    -- Gunpowder is counted in uses. The material
    -- model assumes a jar holds POWDER.usesPerJar of
    -- them; the item script's UseDelta says how many
    -- it really holds on this build.
    ------------------------------------------------

    local powder =
        AC_Calibres.POWDER


    local script =
        safe(
            function()

                return
                    manager:FindItem(
                        powder.item
                    )
            end
        )


    if not script
        or hasMethod(script, "getUseDelta") ~= true
    then

        addResult(
            results,
            "UNVERIFIED",
            "uses per jar of " .. powder.item,
            "item script or getUseDelta unavailable"
        )


        return
    end


    local delta =
        safe(
            function()

                return
                    script:getUseDelta()
            end
        )


    local uses =
        type(delta) == "number"
        and delta > 0
        and math.floor(1 / delta + 0.5)
        or nil


    if uses == powder.usesPerJar then

        addResult(
            results,
            "OK",
            powder.item .. " holds " .. uses .. " uses"
        )

    else

        addResult(
            results,
            "WARNING",
            powder.item .. " holds " .. tostring(uses) .. " uses, the mod assumes " .. powder.usesPerJar,
            "powder accounting and the Mix Gunpowder yield are off on this build"
        )
    end
end


------------------------------------------------
-- Ammo boxes. The mod has no box recipe: vanilla's
-- place_ammo_in_box takes the nine rounds by item type,
-- and a handloaded round is that item. What can be
-- checked here is that the recipe and each round's box
-- still exist under the ids the installed 42.20.4
-- scripts use. A WARNING means boxing handloaded rounds
-- of that calibre may not be offered on this build;
-- making and firing them is unaffected.
------------------------------------------------

AC_Compat.BOX_RECIPE = "place_ammo_in_box"


local function checkBoxes(
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

        addResult(
            results,
            "UNVERIFIED",
            "ammo boxes",
            "no script manager"
        )


        return
    end


    local missing = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local script =
            safe(
                function()

                    return
                        manager:FindItem(
                            calibre.box
                        )
                end
            )


        if not script then

            table.insert(
                missing,
                tostring(calibre.box)
            )
        end
    end


    if hasMethod(manager, "getCraftRecipe") == true then

        local recipe =
            safe(
                function()

                    return
                        manager:getCraftRecipe(
                            AC_Compat.BOX_RECIPE
                        )
                end
            )


        if not recipe then

            table.insert(
                missing,
                "recipe " .. AC_Compat.BOX_RECIPE
            )
        end
    end


    if #missing == 0 then

        addResult(
            results,
            "OK",
            "vanilla ammo boxes (" .. #AC_Calibres.LIST .. " rounds, boxed by vanilla's own recipe)"
        )

    else

        addResult(
            results,
            "WARNING",
            "vanilla ammo boxes changed",
            "missing " .. table.concat(missing, ", ") .. "; handloaded rounds may not be boxable, everything else is unaffected"
        )
    end
end


------------------------------------------------
-- Brass recycling (AC_Recycling): it loses brass and
-- awards nothing. Its recipes and items are probed with
-- all the others (checkMetallurgyRecipes, REQUIRED_ITEMS);
-- this is the model's own rule.
------------------------------------------------

local function checkRecycling(
    results
)

    if type(AC_Recycling) ~= "table" then

        addResult(
            results,
            "WARNING",
            "brass recycling",
            "AC_Recycling is not loaded"
        )


        return
    end


    local problems,
          err =
        safe(
            AC_Recycling.validate
        )


    if err then

        addResult(
            results,
            "UNVERIFIED",
            "brass recycling model",
            tostring(err)
        )


        return
    end


    if #problems == 0 then

        addResult(
            results,
            "OK",
            "brass recycling (half of the brass comes back, no XP)"
        )


        return
    end


    for _,
        problem
    in ipairs(
        problems
    )
    do

        addResult(
            results,
            "WARNING",
            problem,
            "recycling may create brass or award XP"
        )
    end
end


------------------------------------------------
-- Die set loot (AC_Loot): the model is sound, and the
-- registration that ran when the world loaded found
-- every list it targets, in use.
--
-- A list that is missing, emptied or named by no
-- container means vanilla has reorganised its loot:
-- die sets are then crafted only, which still works.
------------------------------------------------

local function checkLoot(
    results
)

    if type(AC_Loot) ~= "table" then

        addResult(
            results,
            "WARNING",
            "die set loot",
            "AC_Loot is not loaded"
        )


        return
    end


    local problems,
          err =
        safe(
            AC_Loot.validate
        )


    if err then

        addResult(
            results,
            "UNVERIFIED",
            "die set loot model",
            tostring(err)
        )


        return
    end


    for _,
        problem
    in ipairs(
        problems
    )
    do

        addResult(
            results,
            "WARNING",
            problem,
            "no die set is added to any loot list"
        )
    end


    if #problems > 0 then
        return
    end


    if not AC_Loot.CONFIG.enabled then

        addResult(
            results,
            "OK",
            "die set loot is switched off"
        )


        return
    end


    local summary =
        AC_Loot.lastSummary


    if type(summary) ~= "table" then

        addResult(
            results,
            "WARNING",
            "die set loot was not registered",
            "OnPreDistributionMerge did not reach the mod; die sets can only be forged"
        )


        return
    end


    if summary.unavailable then

        addResult(
            results,
            "WARNING",
            "die set loot was not registered",
            "ProceduralDistributions.list was not there when the loot tables were merged; die sets can only be forged"
        )


        return
    end


    local clean = true


    for _,
        bucket
    in ipairs(
        {
            { "missing", "does not exist on this build" },
            { "empty", "has been emptied by vanilla" },
            { "unreferenced", "is used by no container" },
        }
    )
    do

        for _,
            name
        in ipairs(
            summary[bucket[1]] or {}
        )
        do

            clean = false


            addResult(
                results,
                "WARNING",
                "loot list " .. tostring(name) .. " " .. bucket[2],
                "die sets will not be found there; they can still be forged"
            )
        end
    end


    if clean then

        addResult(
            results,
            "OK",
            "die set loot (" .. (summary.added + summary.present) .. " entries in " .. #AC_Loot.TARGETS .. " lists)"
        )
    end
end


------------------------------------------------
-- RUN
------------------------------------------------
--
-- Returns the result list and a summary table:
--
--   { ok = n, warnings = n, unverified = n,
--     calibres = { { class, label, complete, total }, ... } }
--
-- verbose: print the OK lines too. Left out, it follows
-- -debug mode.
------------------------------------------------

------------------------------------------------
-- Prints a result list and returns its summary.
-- OK lines only when verbose; WARNING and UNVERIFIED
-- always; then one line per calibre class and the
-- totals under the given title.
------------------------------------------------

local function report(
    results,
    verbose,
    title
)

    local summary = {

        ok = 0,

        warnings = 0,

        unverified = 0,

        calibres = results.calibreSummary or {},
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


        if verbose
            or result.status ~= "OK"
        then
            print(line)
        end


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


    for _,
        tally
    in ipairs(
        summary.calibres
    )
    do

        print(
            "[AmmoMaking] "
            .. tally.label
            .. ": "
            .. tally.complete
            .. "/"
            .. tally.total
            .. " complete"
        )
    end


    print(
        "[AmmoMaking] "
        .. title
        .. ": "
        .. summary.ok
        .. " ok, "
        .. summary.warnings
        .. " warnings, "
        .. summary.unverified
        .. " unverified"
    )


    return summary
end


-- OK lines are wanted when the game runs in -debug mode.
local function defaultVerbose()

    return
        type(isDebugEnabled) == "function"
        and safe(isDebugEnabled) == true
end


------------------------------------------------
-- Only the ammunition part: the calibre model, each
-- calibre's items and recipes, the gunpowder jar. For
-- the debug menu's "Verify Ammo Dependencies".
------------------------------------------------

function AC_Compat.runAmmunition(
    verbose
)

    local results = {}


    checkCalibres(results)


    return
        results,
        report(
            results,
            verbose == true,
            "Ammunition dependencies"
        )
end


function AC_Compat.run(
    verbose
)

    if verbose == nil then
        verbose = defaultVerbose()
    end


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

    checkAnalyzerSprite(results)

    checkMetallurgyRecipes(results)

    checkCalibres(results)

    checkBoxes(results)

    checkRecycling(results)

    checkLoot(results)


    local summary =
        report(
            results,
            verbose,
            "Compatibility check"
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
