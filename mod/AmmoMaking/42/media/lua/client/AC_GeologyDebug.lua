-- Ammo Making - Debug tools
-- Project Zomboid Build 42.20
--
-- One "Ammo Making Debug" submenu on the world context
-- menu, available only when the game runs with -debug
-- (isDebugEnabled() == true).
--
-- These tools reveal exact geology and reserves and can
-- spawn items, so nothing here may be reachable outside
-- debug mode. Labels are intentionally plain English;
-- they are not player-facing.

AC_GeologyDebug =
    AC_GeologyDebug or {}


------------------------------------------------
-- HELPERS
------------------------------------------------

local function round(value)

    return
        math.floor(
            value + 0.5
        )
end


local function log(text)

    print(
        "[AmmoMaking] "
        .. tostring(text)
    )
end


local function halo(
    player,
    text
)

    HaloTextHelper.addText(
        player,
        tostring(text)
    )
end


local function playerTile(
    player
)

    return
        math.floor(
            player:getX()
        ),
        math.floor(
            player:getY()
        )
end


------------------------------------------------
-- Spawns one item into the player's inventory and
-- reports whether the item script exists. Returns
-- the item or nil.
------------------------------------------------

local function spawnItem(
    player,
    itemType
)

    local item =
        player:getInventory():AddItem(
            itemType
        )


    if item then

        log(
            "Debug spawn OK: "
            .. tostring(itemType)
        )

    else

        log(
            "WARNING: debug spawn FAILED: "
            .. tostring(itemType)
            .. " (item script not found on this build?)"
        )
    end


    return item
end


local function spawnItems(
    player,
    itemTypes,
    label
)

    if not player then
        return
    end


    local okCount = 0


    for _,
        itemType
    in ipairs(
        itemTypes
    )
    do

        if spawnItem(
            player,
            itemType
        ) then

            okCount =
                okCount + 1
        end
    end


    halo(
        player,
        label
        .. ": "
        .. okCount
        .. "/"
        .. #itemTypes
        .. " items spawned"
    )
end


------------------------------------------------
-- INSPECT CURRENT TILE
------------------------------------------------
--
-- True geology and reserve state of the tile the
-- player stands on. Works on any square; the terrain
-- verdict is reported instead of enforced so invalid
-- ground can be diagnosed too.
------------------------------------------------

local function inspectTile(
    player
)

    if not player then
        return
    end


    local square =
        player:getSquare()


    local x,
          y =
        playerTile(
            player
        )


    log("GEOLOGY TILE " .. x .. ", " .. y)


    log(
        "Floor sprite: "
        .. tostring(
            AC_Geology.getFloorSpriteName(
                square
            )
        )
        .. " | z = "
        .. tostring(
            square and square:getZ()
        )
        .. " | room = "
        .. tostring(
            square and square:getRoom() ~= nil
        )
        .. " | water = "
        .. tostring(
            AC_Geology.isWaterSquare(
                square
            )
        )
        .. " | mineable = "
        .. tostring(
            AC_Mining.isMineableSquare(
                square
            )
        )
    )


    local info =
        AC_Deposits.getTileInfo(
            x,
            y
        )


    local haloParts = {}


    for _,
        metal
    in ipairs(
        AC_Deposits.METALS
    )
    do

        local m =
            info[metal]


        log(
            AC_Deposits.METAL_NAMES[metal]
            .. ": "
            .. string.format("%.1f", m.concentration)
            .. "% ("
            .. m.grade
            .. ") reserve "
            .. m.remaining
            .. "/"
            .. m.initial
            .. ", extracted "
            .. m.extracted
            .. ", worked "
            .. tostring(m.worked)
        )


        table.insert(
            haloParts,
            AC_Deposits.METAL_NAMES[metal]:sub(1, 2)
            .. " "
            .. round(m.concentration)
            .. "% "
            .. m.remaining
            .. "/"
            .. m.initial
        )
    end


    halo(
        player,
        "Tile "
        .. x
        .. ","
        .. y
        .. ": "
        .. table.concat(
            haloParts,
            " | "
        )
    )
end


------------------------------------------------
-- SURVEY 3x3 AREA
------------------------------------------------

local function surveyArea(
    player
)

    if not player then
        return
    end


    local x,
          y =
        playerTile(
            player
        )


    local survey =
        AC_Geology.surveyArea(
            x,
            y
        )


    log("GEOLOGICAL SURVEY " .. x .. ", " .. y .. " (3x3)")


    log(
        "Copper average "
        .. round(survey.copperAverage)
        .. "% ("
        .. AC_Geology.getGrade(survey.copperAverage)
        .. "), peak "
        .. round(survey.copperPeak)
        .. "%"
    )


    log(
        "Zinc average "
        .. round(survey.zincAverage)
        .. "% ("
        .. AC_Geology.getGrade(survey.zincAverage)
        .. "), peak "
        .. round(survey.zincPeak)
        .. "%"
    )


    ------------------------------------------------
    -- Per-tile reserves of the area, so a tester can
    -- pick a tile with known ore before mining.
    ------------------------------------------------

    local radius =
        AC_Geology.CONFIG.surveyRadius


    for offsetY = -radius, radius do

        local row = {}


        for offsetX = -radius, radius do

            local tx =
                x + offsetX

            local ty =
                y + offsetY


            table.insert(
                row,
                tx
                .. ","
                .. ty
                .. " Cu"
                .. AC_Deposits.getRemaining(tx, ty, "copper")
                .. "/"
                .. AC_Deposits.getInitialReserve(tx, ty, "copper")
                .. " Zn"
                .. AC_Deposits.getRemaining(tx, ty, "zinc")
                .. "/"
                .. AC_Deposits.getInitialReserve(tx, ty, "zinc")
            )
        end


        log(
            table.concat(
                row,
                "   "
            )
        )
    end


    halo(
        player,
        "Survey: Cu "
        .. round(survey.copperAverage)
        .. "% | Zn "
        .. round(survey.zincAverage)
        .. "%"
    )
end


------------------------------------------------
-- GEOLOGY SEED
------------------------------------------------

local function showSeed(
    player
)

    if not player then
        return
    end


    local seeds =
        AC_Geology.getSeedInfo()


    if not seeds then

        log("WARNING: no save identity; geology seed unavailable")

        halo(
            player,
            "Geology seed unavailable"
        )


        return
    end


    log(
        "Save identity: "
        .. tostring(seeds.identity)
        .. " | geology seed "
        .. tostring(seeds.geology)
        .. " | copper "
        .. tostring(seeds.copper)
        .. " | zinc "
        .. tostring(seeds.zinc)
    )


    halo(
        player,
        "Geology seed: "
        .. tostring(seeds.geology)
    )
end


------------------------------------------------
-- RESET DEPLETION
------------------------------------------------

local function resetTile(
    player
)

    if not player then
        return
    end


    local x,
          y =
        playerTile(
            player
        )


    AC_Deposits.resetTile(
        x,
        y
    )


    log(
        "Depletion reset at "
        .. x
        .. ", "
        .. y
        .. "; worked tiles in save: "
        .. AC_Deposits.getWorkedTileCount()
    )


    halo(
        player,
        "Depletion reset (tile)"
    )
end


local function resetArea(
    player
)

    if not player then
        return
    end


    local x,
          y =
        playerTile(
            player
        )


    local radius =
        AC_Geology.CONFIG.surveyRadius


    for offsetX = -radius, radius do

        for offsetY = -radius, radius do

            AC_Deposits.resetTile(
                x + offsetX,
                y + offsetY
            )
        end
    end


    log(
        "Depletion reset around "
        .. x
        .. ", "
        .. y
        .. " (3x3); worked tiles in save: "
        .. AC_Deposits.getWorkedTileCount()
    )


    halo(
        player,
        "Depletion reset (3x3)"
    )
end


------------------------------------------------
-- SPAWN TEST ITEMS
------------------------------------------------

local function spawnSamplingKit(
    player
)

    spawnItems(
        player,
        {
            "Base.Shovel",
            AC_GeologySampling.ITEMS.FieldKit,
            AC_GeologySampling.ITEMS.AdvancedFieldKit,
        },
        "Sampling kit"
    )
end


local function spawnMiningKit(
    player
)

    local itemTypes = {}


    for itemType in pairs(
        AC_Mining.PICKAXE_TYPES
    ) do

        table.insert(
            itemTypes,
            itemType
        )
    end


    table.sort(
        itemTypes
    )


    spawnItems(
        player,
        itemTypes,
        "Mining kit"
    )
end


local function spawnLaboratoryAnalyzer(
    player
)

    spawnItems(
        player,
        {
            AC_LaboratoryAnalyzer.ITEMS.Analyzer,
        },
        "Laboratory analyzer"
    )
end


------------------------------------------------
-- SPAWN ASSAYED SAMPLE
------------------------------------------------
--
-- Creates a sample of the 3x3 area around the player
-- and applies an advanced field assay without using a
-- kit, so the mining loop can be tested in seconds.
-- The assay still carries measurement error, exactly
-- like a real kit.
------------------------------------------------

local function spawnAssayedSample(
    player
)

    if not player then
        return
    end


    local x,
          y =
        playerTile(
            player
        )


    local sample,
          errorCode =
        AC_GeologySampling.buildSample(
            player,
            x,
            y
        )


    if not sample then

        log(
            "WARNING: debug sample failed: "
            .. tostring(errorCode)
        )


        halo(
            player,
            "Sample creation failed"
        )


        return
    end


    AC_GeologySampling.applyAssay(
        sample,
        2
    )


    local data =
        sample:getModData()


    log(
        "Debug assayed sample at "
        .. x
        .. ", "
        .. y
        .. ": copper "
        .. tostring(data.copperGrade)
        .. ", zinc "
        .. tostring(data.zincGrade)
    )


    halo(
        player,
        "Assayed sample: Cu "
        .. tostring(data.copperGrade)
        .. " | Zn "
        .. tostring(data.zincGrade)
    )
end


------------------------------------------------
-- INSPECT CLICKED TILE OBJECTS
------------------------------------------------
--
-- Lists every object, special object and world item
-- on the clicked square with its sprite name, to pick
-- vanilla sprites (the analyzer's world sprite was
-- found this way) and to check placed analyzers: an
-- analyzer also prints its stored state, read without
-- updating it. Recovered from the standalone
-- AC_SpriteInspector of the local branch.
------------------------------------------------

local function safeCall(
    object,
    methodName
)

    if not object
        or not object[methodName]
    then

        return nil
    end


    local ok,
          result =
        pcall(
            object[methodName],
            object
        )


    if ok then
        return result
    end


    return nil
end


local function getSpriteName(
    object
)

    local textureName =
        safeCall(
            object,
            "getTextureName"
        )


    if textureName
        and textureName ~= ""
    then

        return textureName
    end


    return
        safeCall(
            safeCall(
                object,
                "getSprite"
            ),
            "getName"
        )
end


local function describeAnalyzer(
    object
)

    if not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
        object
    ) then

        return ""
    end


    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            object
        )
        or {}


    local kind =
        AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            object
        )
        and "placed"
        or "dropped"


    return
        " | analyzer (" .. kind .. ")"
        .. " state=" .. tostring(data.labAnalyzerState)
        .. " remaining=" .. tostring(data.labRemainingHours)
        .. " lastUpdate=" .. tostring(data.labLastUpdateAt)
        .. " sample=" .. tostring(data.storedSample == true)
        .. " at " .. tostring(data.stored_sampleX)
        .. "," .. tostring(data.stored_sampleY)
end


local function logObjectList(
    label,
    list
)

    if not list then
        return
    end


    log(
        label
        .. ": "
        .. list:size()
    )


    for index = 0,
        list:size() - 1
    do

        local object =
            list:get(
                index
            )


        log(
            label
            .. " #"
            .. index
            .. " | objectName="
            .. tostring(
                safeCall(
                    object,
                    "getObjectName"
                )
            )
            .. " | name="
            .. tostring(
                safeCall(
                    object,
                    "getName"
                )
            )
            .. " | sprite="
            .. tostring(
                getSpriteName(
                    object
                )
            )
            .. describeAnalyzer(
                object
            )
        )
    end
end


local function inspectTileObjects(
    player,
    square
)

    if not player then
        return
    end


    if not square then

        halo(
            player,
            "No tile to inspect"
        )


        return
    end


    log(
        "TILE OBJECTS "
        .. tostring(square:getX())
        .. ", "
        .. tostring(square:getY())
        .. ", "
        .. tostring(square:getZ())
    )


    logObjectList(
        "Object",
        safeCall(
            square,
            "getObjects"
        )
    )


    logObjectList(
        "SpecialObject",
        safeCall(
            square,
            "getSpecialObjects"
        )
    )


    logObjectList(
        "WorldObject",
        safeCall(
            square,
            "getWorldObjects"
        )
    )


    halo(
        player,
        "Tile objects written to console"
    )
end


------------------------------------------------
-- LABORATORY ANALYZER
------------------------------------------------
--
-- Offered only for an analyzer on the clicked
-- square. Inspect is read-only; it does not credit
-- the pending hours. Complete skips the remaining
-- processing time but grants no XP: the sample is
-- still collected through the normal menu.
------------------------------------------------

local function formatHours(
    value
)

    value =
        tonumber(
            value
        )


    if not value then
        return "nil"
    end


    return
        string.format(
            "%.2f",
            value
        )
end


local function inspectAnalyzer(
    player,
    analyzer
)

    if not player then
        return
    end


    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            analyzer
        )


    if not data then

        halo(
            player,
            "Not an Ammo Making analyzer"
        )


        return
    end


    local square =
        analyzer:getSquare()


    local now =
        getGameTime():getWorldAgeHours()


    local lastUpdate =
        tonumber(
            data.labLastUpdateAt
        )


    local kind =
        AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            analyzer
        )
        and "placed"
        or "dropped"


    log(
        "ANALYZER (" .. kind .. ") at "
        .. tostring(square and square:getX())
        .. ", "
        .. tostring(square and square:getY())
        .. ", "
        .. tostring(square and square:getZ())
    )


    log(
        "  state=" .. tostring(data.labAnalyzerState)
        .. " storedSample=" .. tostring(data.storedSample == true)
        .. " sample at " .. tostring(data.stored_sampleX)
        .. ", " .. tostring(data.stored_sampleY)
        .. " assayRank=" .. tostring(data.stored_assayRank)
    )


    log(
        "  remaining=" .. formatHours(data.labRemainingHours) .. " h"
        .. " lastUpdate=" .. formatHours(lastUpdate)
        .. " now=" .. formatHours(now)
        .. " pending=" .. formatHours(lastUpdate and math.max(0, now - lastUpdate))
        .. " h (credited at the next check if powered then)"
    )


    local gridPower =
        square
        and square.hasGridPower
        and square:hasGridPower()


    log(
        "  powered=" .. tostring(AC_LaboratoryAnalyzer.hasPower(analyzer))
        .. " (haveElectricity=" .. tostring(square and square:haveElectricity())
        .. " hasGridPower=" .. tostring(gridPower)
        .. " room=" .. tostring(square ~= nil and square:getRoom() ~= nil)
        .. ")"
    )


    log(
        "  rolled lab result copper=" .. tostring(data.labCopperResult)
        .. " zinc=" .. tostring(data.labZincResult)
        .. " (hidden until collection)"
    )


    log(
        "  idle and empty (pick-up allowed)="
        .. tostring(AC_LaboratoryAnalyzer.isIdleAndEmpty(analyzer))
    )


    halo(
        player,
        "Analyzer "
        .. tostring(data.labAnalyzerState)
        .. ", "
        .. formatHours(data.labRemainingHours)
        .. " h left (see console)"
    )
end


local function completeAnalyzerJob(
    player,
    analyzer
)

    if not player then
        return
    end


    local ok,
          reason =
        AC_LaboratoryAnalyzer.debugFinishProcessing(
            analyzer
        )


    if ok then

        halo(
            player,
            "Analyzer job complete - collect the sample normally"
        )


        return
    end


    log(
        "DEBUG: Complete Analyzer Job refused: "
        .. tostring(reason)
    )


    halo(
        player,
        "Analyzer is not processing ("
        .. tostring(reason)
        .. ")"
    )
end


------------------------------------------------
-- SKILL LEVEL
------------------------------------------------

function AC_GeologyDebug.setSkillLevel(
    player,
    targetLevel
)

    if not player then
        return
    end


    targetLevel =
        tonumber(
            targetLevel
        )


    if not targetLevel then
        return
    end


    if targetLevel < 0 then
        targetLevel = 0
    elseif targetLevel > 10 then
        targetLevel = 10
    end


    player:setPerkLevelDebug(
        AmmoMakingSkill.perk,
        targetLevel
    )


    player:getXp():setXPToLevel(
        AmmoMakingSkill.perk,
        targetLevel
    )


    local actualLevel =
        AmmoMakingSkill.getLevel(
            player
        )


    log(
        "Debug skill level set. Target="
        .. targetLevel
        .. " Actual="
        .. actualLevel
    )


    halo(
        player,
        "Ammo Making level "
        .. actualLevel
    )
end


------------------------------------------------
-- Adds a "Set Ammo Making Level" submenu to any
-- context menu. Shared with the inventory debug
-- menu in AC_AmmoContextMenu. Callers must already
-- have checked isDebugEnabled().
------------------------------------------------

function AC_GeologyDebug.addSkillLevelMenu(
    context,
    player
)

    local option =
        context:addOption(
            "Set Ammo Making Level"
        )


    local submenu =
        ISContextMenu:getNew(
            context
        )


    context:addSubMenu(
        option,
        submenu
    )


    for level = 0, 10 do

        submenu:addOption(
            "Level " .. level,
            player,
            AC_GeologyDebug.setSkillLevel,
            level
        )
    end
end


------------------------------------------------
-- COMPATIBILITY CHECK
------------------------------------------------

local function runCompatibilityCheck(
    player
)

    if not player then
        return
    end


    local ok,
          results,
          summary =
        pcall(
            AC_Compat.run
        )


    if not ok then

        log(
            "WARNING: compatibility check failed: "
            .. tostring(results)
        )


        halo(
            player,
            "Compatibility check failed (see console)"
        )


        return
    end


    halo(
        player,
        "Compat: "
        .. summary.ok
        .. " ok, "
        .. summary.warnings
        .. " warnings, "
        .. summary.unverified
        .. " unverified (see console)"
    )
end


------------------------------------------------
-- PUBLIC ENTRY POINTS
------------------------------------------------
--
-- Also usable from the Lua debug console, e.g.
-- AC_GeologyDebug.tile(getPlayer()).
------------------------------------------------

AC_GeologyDebug.tile =
    inspectTile

AC_GeologyDebug.survey =
    surveyArea

AC_GeologyDebug.seed =
    showSeed

AC_GeologyDebug.resetTile =
    resetTile

AC_GeologyDebug.resetArea =
    resetArea

AC_GeologyDebug.spawnSamplingKit =
    spawnSamplingKit

AC_GeologyDebug.spawnMiningKit =
    spawnMiningKit

AC_GeologyDebug.spawnLaboratoryAnalyzer =
    spawnLaboratoryAnalyzer

AC_GeologyDebug.spawnAssayedSample =
    spawnAssayedSample

AC_GeologyDebug.compat =
    runCompatibilityCheck

AC_GeologyDebug.objects =
    inspectTileObjects

AC_GeologyDebug.inspectAnalyzer =
    inspectAnalyzer

AC_GeologyDebug.completeAnalyzerJob =
    completeAnalyzerJob


------------------------------------------------
-- CLICKED SQUARE
------------------------------------------------

local function getClickedSquare(
    worldObjects
)

    if not worldObjects then
        return nil
    end


    for _,
        object
    in ipairs(
        worldObjects
    )
    do

        if object
            and object.getSquare
        then

            local square =
                object:getSquare()


            if square then
                return square
            end
        end
    end


    return nil
end


------------------------------------------------
-- WORLD CONTEXT MENU
------------------------------------------------

local function onFillWorldObjectContextMenu(
    playerIndex,
    context,
    worldObjects,
    test
)

    if test then
        return
    end


    ------------------------------------------------
    -- Debug tools reveal exact geology and spawn
    -- items: -debug mode only, no exceptions.
    ------------------------------------------------

    if not isDebugEnabled() then
        return
    end


    local player =
        getSpecificPlayer(
            playerIndex
        )


    if not player then
        return
    end


    local rootOption =
        context:addOption(
            "Ammo Making Debug"
        )


    local menu =
        ISContextMenu:getNew(
            context
        )


    context:addSubMenu(
        rootOption,
        menu
    )


    ------------------------------------------------
    -- Inspect
    ------------------------------------------------

    menu:addOption("Inspect Current Tile", player, inspectTile)

    menu:addOption("Survey Current Area (3x3)", player, surveyArea)

    menu:addOption("Show Geology Seed", player, showSeed)


    local clickedSquare =
        getClickedSquare(
            worldObjects
        )


    if clickedSquare then

        menu:addOption("Inspect Clicked Tile Objects (sprites, analyzer state)", player, inspectTileObjects, clickedSquare)
    end


    ------------------------------------------------
    -- Laboratory analyzer (clicked analyzer only)
    ------------------------------------------------

    local analyzer =
        AC_LaboratoryAnalyzer.findInWorldObjects(
            worldObjects
        )


    if analyzer then

        menu:addOption("Inspect Analyzer State", player, inspectAnalyzer, analyzer)

        menu:addOption("Complete Analyzer Job (no XP; collect normally)", player, completeAnalyzerJob, analyzer)
    end


    ------------------------------------------------
    -- Depletion
    ------------------------------------------------

    menu:addOption("Reset Depletion: Current Tile", player, resetTile)

    menu:addOption("Reset Depletion: 3x3 Area", player, resetArea)


    ------------------------------------------------
    -- Test items
    ------------------------------------------------

    menu:addOption("Spawn Sampling Kit (shovel + assay kits)", player, spawnSamplingKit)

    menu:addOption("Spawn Mining Kit (pickaxes)", player, spawnMiningKit)

    menu:addOption("Spawn Laboratory Analyzer", player, spawnLaboratoryAnalyzer)

    menu:addOption("Spawn Assayed Sample (current 3x3)", player, spawnAssayedSample)


    ------------------------------------------------
    -- Skill / diagnostics
    ------------------------------------------------

    AC_GeologyDebug.addSkillLevelMenu(
        menu,
        player
    )


    menu:addOption("Run Compatibility Check", player, runCompatibilityCheck)
end


Events.OnFillWorldObjectContextMenu.Add(
    onFillWorldObjectContextMenu
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Debug tools loaded"
)
