-- Ammo Making - Laboratory Assay Analyzer
-- Project Zomboid Build 42.20

AC_LaboratoryAnalyzer =
    AC_LaboratoryAnalyzer or {}


------------------------------------------------
-- CONFIGURATION
------------------------------------------------

AC_LaboratoryAnalyzer.CONFIG = {

    processingHours = 24,

    measurementError = 2,

    -- Ammo Making XP when a finished sample is collected.
    assayXP = 10,

    -- Temporary vanilla world sprite of the placed
    -- analyzer (found in 42.20 with the tile object
    -- inspector); a custom sprite can replace it later
    -- without touching the analyzer logic.
    worldSprite = "industry_03_61",

    -- Ticks to place the analyzer. ISBuildAction takes
    -- 50 off for the Handy trait, so this must stay
    -- above 50.
    placeActionTime = 100,

    -- Ticks to pick a placed analyzer up again.
    pickUpActionTime = 50,
}


------------------------------------------------
-- ITEM TYPES
------------------------------------------------

AC_LaboratoryAnalyzer.ITEMS = {

    Analyzer =
        "AmmoMaking.LaboratoryAssayAnalyzer",

    Sample =
        "AmmoMaking.GeologicalSample",
}


------------------------------------------------
-- WORLD OBJECT
------------------------------------------------
--
-- A placed analyzer is the IsoThumpable created by
-- AC_LaboratoryAnalyzerObject (server/BuildingObjects).
-- It is recognised by a flag in its own ModData; the
-- object name is only a fallback for an object whose
-- ModData did not survive.
------------------------------------------------

AC_LaboratoryAnalyzer.OBJECT_NAME =
    "AmmoMakingLaboratoryAnalyzer"


------------------------------------------------
-- SAMPLE DATA FIELDS
------------------------------------------------

AC_LaboratoryAnalyzer.SAMPLE_FIELDS = {

    "sampleX",
    "sampleY",

    "geologySeed",

    "trueCopper",
    "trueZinc",

    "trueCopperPeak",
    "trueZincPeak",

    "assayRank",
    "assayType",

    "copperGrade",
    "zincGrade",

    "copperMin",
    "copperMax",

    "zincMin",
    "zincMax",
}


------------------------------------------------
-- ANALYZER STATE FIELDS
------------------------------------------------
--
-- Besides these, a stored sample is kept as
-- "stored_" .. field for every SAMPLE_FIELDS entry.
------------------------------------------------

AC_LaboratoryAnalyzer.STATE_FIELDS = {

    "labAnalyzerState",

    "storedSample",

    "labStartedAt",
    "labReadyAt",
    "labRemainingHours",
    "labLastUpdateAt",

    "labCopperResult",
    "labZincResult",
}


------------------------------------------------
-- HELPERS
------------------------------------------------

local function clamp(
    value,
    minimum,
    maximum
)

    if value < minimum then
        return minimum
    end


    if value > maximum then
        return maximum
    end


    return value
end


local function round(
    value
)

    return math.floor(
        value + 0.5
    )
end


local function getWorldHours()

    local gameTime =
        getGameTime()


    if not gameTime then
        return 0
    end


    return gameTime:getWorldAgeHours()
end


------------------------------------------------
-- LABORATORY MEASUREMENT
------------------------------------------------

local function laboratoryMeasurement(
    trueValue
)

    trueValue =
        tonumber(
            trueValue
        )
        or 0


    local maximumError =
        AC_LaboratoryAnalyzer.CONFIG.measurementError


    local errorAmount =
        ZombRand(
            (maximumError * 2) + 1
        )
        - maximumError


    return clamp(
        round(
            trueValue
            + errorAmount
        ),
        0,
        100
    )
end


------------------------------------------------
-- ANALYZER ITEM CHECK
------------------------------------------------

function AC_LaboratoryAnalyzer.isAnalyzerItem(
    item
)

    return
        item ~= nil
        and item:getFullType()
            == AC_LaboratoryAnalyzer.ITEMS.Analyzer
end


------------------------------------------------
-- DROPPED ANALYZER (ITEM ON THE GROUND)
------------------------------------------------
--
-- The original analyzer: the inventory item dropped
-- on the floor, with its state in the item's ModData.
-- Still supported so analyzers, and samples stored in
-- them, from existing saves keep working.
------------------------------------------------

function AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
    worldObject
)

    if not worldObject then
        return false
    end


    if not instanceof(
        worldObject,
        "IsoWorldInventoryObject"
    ) then

        return false
    end


    return
        AC_LaboratoryAnalyzer.isAnalyzerItem(
            worldObject:getItem()
        )
end


------------------------------------------------
-- PLACED ANALYZER (WORLD OBJECT)
------------------------------------------------
--
-- hasModData() is checked before getModData() so that
-- looking at an arbitrary wall or floor does not
-- create an empty ModData table on it.
------------------------------------------------

function AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
    worldObject
)

    if not worldObject then
        return false
    end


    if instanceof(
        worldObject,
        "IsoWorldInventoryObject"
    ) then

        return false
    end


    if worldObject.hasModData
        and worldObject:hasModData()
        and worldObject:getModData().AmmoMakingLaboratoryAnalyzerWorldObject
            == true
    then

        return true
    end


    return
        worldObject.getName ~= nil
        and worldObject:getName()
            == AC_LaboratoryAnalyzer.OBJECT_NAME
end


------------------------------------------------
-- ANY ANALYZER IN THE WORLD
------------------------------------------------

function AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
    worldObject
)

    return
        AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
            worldObject
        )
        or AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            worldObject
        )
end


------------------------------------------------
-- GET ANALYZER ITEM
------------------------------------------------
--
-- Only a dropped analyzer has an item; a placed
-- analyzer returns nil.
------------------------------------------------

function AC_LaboratoryAnalyzer.getAnalyzerItem(
    worldObject
)

    if not AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
        worldObject
    ) then

        return nil
    end


    return worldObject:getItem()
end


------------------------------------------------
-- GET PERSISTENT ANALYZER DATA
------------------------------------------------
--
-- Dropped analyzer: the item's ModData.
-- Placed analyzer: the world object's ModData.
------------------------------------------------

function AC_LaboratoryAnalyzer.getAnalyzerData(
    worldObject
)

    local item =
        AC_LaboratoryAnalyzer.getAnalyzerItem(
            worldObject
        )


    if item then
        return item:getModData()
    end


    if AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
        worldObject
    ) then

        return worldObject:getModData()
    end


    return nil
end


------------------------------------------------
-- UPDATE ANALYZER NAME
------------------------------------------------
--
-- Only a dropped analyzer shows its state in its
-- item name; a placed analyzer has no item.
------------------------------------------------

local function updateAnalyzerName(
    worldObject,
    state
)

    local item =
        AC_LaboratoryAnalyzer.getAnalyzerItem(
            worldObject
        )


    if not item then
        return
    end


    item:setCustomName(
        true
    )


    if state == "processing" then

        item:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_AnalyzerProcessing",
                "Laboratory Assay Analyzer (Processing)"
            )
        )

    elseif state == "ready" then

        item:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_AnalyzerReady",
                "Laboratory Assay Analyzer (Result Ready)"
            )
        )

    else

        item:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_Analyzer",
                "Laboratory Assay Analyzer"
            )
        )
    end
end


------------------------------------------------
-- CLEAR STORED SAMPLE
------------------------------------------------

local function clearStoredSample(
    data
)

    for _,
        field
    in ipairs(
        AC_LaboratoryAnalyzer.SAMPLE_FIELDS
    )
    do

        data[
            "stored_" .. field
        ] =
            nil
    end


    data.storedSample =
        nil

    data.labStartedAt =
        nil

    data.labReadyAt =
        nil

    data.labRemainingHours =
        nil

    data.labLastUpdateAt =
        nil

    data.labCopperResult =
        nil

    data.labZincResult =
        nil
end


------------------------------------------------
-- NORMALISE STORED STATE
------------------------------------------------
--
-- Analyzer state lives in ModData that an older
-- version or a damaged save may have left
-- inconsistent. Repair it so the machine is never
-- stuck and a stored sample is never lost:
--
--   unknown state          -> processing if a sample
--                             is stored, else idle
--   idle with a sample     -> processing (it can then
--                             finish, or be cancelled)
--   processing / ready
--   without a sample       -> idle
--   sample without results -> results rolled now
--   non-numeric timers     -> dropped; updateState()
--                             rebuilds them
------------------------------------------------

local VALID_STATES = {

    idle = true,

    processing = true,

    ready = true,
}


local function dropIfNotNumber(
    data,
    field
)

    if data[field] ~= nil
        and tonumber(data[field]) == nil
    then

        data[field] =
            nil

        return true
    end


    return false
end


local function normalizeState(
    data
)

    local original =
        data.labAnalyzerState


    local hasSample =
        data.storedSample == true


    local state =
        original


    if not VALID_STATES[state]
        or (state == "idle" and hasSample)
    then

        if hasSample then
            state = "processing"
        else
            state = "idle"
        end
    end


    if state ~= "idle"
        and not hasSample
    then

        state = "idle"
    end


    local repaired =
        original ~= nil
        and state ~= original


    if state == "idle" then

        clearStoredSample(
            data
        )

    else

        for _,
            field
        in ipairs(
            { "labRemainingHours", "labReadyAt", "labLastUpdateAt" }
        )
        do

            if dropIfNotNumber(
                data,
                field
            ) then

                repaired = true
            end
        end


        if tonumber(data.labCopperResult) == nil
            or tonumber(data.labZincResult) == nil
        then

            data.labCopperResult =
                laboratoryMeasurement(
                    data.stored_trueCopper
                )

            data.labZincResult =
                laboratoryMeasurement(
                    data.stored_trueZinc
                )

            repaired = true
        end
    end


    data.labAnalyzerState =
        state


    if repaired then

        print(
            "[AmmoMaking] WARNING: laboratory analyzer state repaired ("
            .. tostring(original)
            .. " -> "
            .. state
            .. ")"
        )
    end
end


------------------------------------------------
-- INITIALIZE ANALYZER
------------------------------------------------

function AC_LaboratoryAnalyzer.initialize(
    worldObject
)

    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            worldObject
        )


    if not data then
        return nil
    end


    data.AmmoMakingLaboratoryAnalyzer =
        true


    normalizeState(
        data
    )


    updateAnalyzerName(
        worldObject,
        data.labAnalyzerState
    )


    return data
end


------------------------------------------------
-- ELECTRICITY
------------------------------------------------

function AC_LaboratoryAnalyzer.hasPower(
    worldObject
)

    if not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
        worldObject
    ) then

        return false
    end


    local square =
        worldObject:getSquare()


    if not square then
        return false
    end


    ------------------------------------------------
    -- Generator / square-level electricity.
    ------------------------------------------------

    if square:haveElectricity() then

        return true
    end


    ------------------------------------------------
    -- Utility grid / hydro power.
    --
    -- Hydro power should only count for an analyzer
    -- placed inside a mapped room/building.
    ------------------------------------------------

    local world =
        getWorld()


    if world
        and world:isHydroPowerOn()
        and square:getRoom() ~= nil
    then

        return true
    end


    return false
end


------------------------------------------------
-- UPDATE PROCESSING STATE
------------------------------------------------

function AC_LaboratoryAnalyzer.updateState(
    worldObject
)

    local data =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not data then
        return nil
    end


    if data.labAnalyzerState
        ~= "processing"
    then

        return data.labAnalyzerState
    end


    local now =
        getWorldHours()


    ------------------------------------------------
    -- MIGRATION FROM OLD READY-AT TIMER
    ------------------------------------------------

    if data.labRemainingHours == nil then

        if data.labReadyAt then

            data.labRemainingHours =
                math.max(
                    0,
                    tonumber(
                        data.labReadyAt
                    )
                    - now
                )

        else

            data.labRemainingHours =
                AC_LaboratoryAnalyzer.CONFIG.processingHours
        end


        data.labLastUpdateAt =
            now
    end


    ------------------------------------------------
    -- Calculate elapsed in-game time since the
    -- analyzer was last checked.
    ------------------------------------------------

    local lastUpdate =
        tonumber(
            data.labLastUpdateAt
        )
        or now


    local elapsed =
        math.max(
            0,
            now - lastUpdate
        )


    ------------------------------------------------
    -- Only consume processing time while powered.
    ------------------------------------------------

    if AC_LaboratoryAnalyzer.hasPower(
        worldObject
    ) then

        data.labRemainingHours =
            math.max(
                0,
                tonumber(
                    data.labRemainingHours
                )
                - elapsed
            )
    end


    data.labLastUpdateAt =
        now


    ------------------------------------------------
    -- Keep readyAt for debug/display compatibility.
    ------------------------------------------------

    data.labReadyAt =
        now
        + (
            tonumber(
                data.labRemainingHours
            )
            or 0
        )


    ------------------------------------------------
    -- COMPLETE
    ------------------------------------------------

    if tonumber(
        data.labRemainingHours
    ) <= 0 then

        data.labAnalyzerState =
            "ready"


        data.labRemainingHours =
            0


        updateAnalyzerName(
            worldObject,
            "ready"
        )


        print(
            "[AmmoMaking] Laboratory analyzer completed sample "
            .. tostring(
                data.stored_sampleX
            )
            .. ", "
            .. tostring(
                data.stored_sampleY
            )
        )
    end


    return data.labAnalyzerState
end


------------------------------------------------
-- GET STATE
------------------------------------------------

function AC_LaboratoryAnalyzer.getState(
    worldObject
)

    return
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )
end


------------------------------------------------
-- HOURS REMAINING
------------------------------------------------

function AC_LaboratoryAnalyzer.getHoursRemaining(
    worldObject
)

    local state =
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )


    if state ~= "processing" then
        return 0
    end


    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            worldObject
        )


    if not data then
        return 0
    end


    return
        tonumber(
            data.labRemainingHours
        )
        or 0
end


------------------------------------------------
-- CHECK SAMPLE ELIGIBILITY
------------------------------------------------

function AC_LaboratoryAnalyzer.canAnalyzeSample(
    sample
)

    if not sample then
        return false
    end


    if sample:getFullType()
        ~= AC_LaboratoryAnalyzer.ITEMS.Sample
    then

        return false
    end


    local data =
        sample:getModData()


    local rank =
        tonumber(
            data.assayRank
        )
        or 0


    if rank >= 3 then
        return false
    end


    if data.labProcessing
        == true
    then

        return false
    end


    return true
end


------------------------------------------------
-- STORE SAMPLE DATA
------------------------------------------------

local function storeSampleData(
    analyzerData,
    sample
)

    local sampleData =
        sample:getModData()


    for _,
        field
    in ipairs(
        AC_LaboratoryAnalyzer.SAMPLE_FIELDS
    )
    do

        analyzerData[
            "stored_" .. field
        ] =
            sampleData[field]
    end


    analyzerData.storedSample =
        true
end


------------------------------------------------
-- START LABORATORY ASSAY
------------------------------------------------

function AC_LaboratoryAnalyzer.startAssay(
    player,
    worldObject,
    sample
)

    if not player then

        return false,
            "no_player"
    end


    if not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
        worldObject
    ) then

        return false,
            "invalid_analyzer"
    end


    if not AC_LaboratoryAnalyzer.hasPower(
        worldObject
    ) then

        return false,
            "no_power"
    end


    local analyzerData =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not analyzerData then

        return false,
            "invalid_analyzer"
    end


    AC_LaboratoryAnalyzer.updateState(
        worldObject
    )


    if analyzerData.labAnalyzerState
        ~= "idle"
    then

        return false,
            "busy"
    end


    if not AC_LaboratoryAnalyzer.canAnalyzeSample(
        sample
    ) then

        return false,
            "invalid_sample"
    end


    local container =
        sample:getContainer()


    if not container then

        return false,
            "sample_not_in_container"
    end


    ------------------------------------------------
    -- SAVE SAMPLE DATA
    ------------------------------------------------

    storeSampleData(
        analyzerData,
        sample
    )


    ------------------------------------------------
    -- Roll final laboratory result immediately so
    -- saving/reloading cannot reroll the assay.
    ------------------------------------------------

    local sampleData =
        sample:getModData()


    analyzerData.labCopperResult =
        laboratoryMeasurement(
            sampleData.trueCopper
        )


    analyzerData.labZincResult =
        laboratoryMeasurement(
            sampleData.trueZinc
        )


    ------------------------------------------------
    -- START PROCESSING
    ------------------------------------------------

    local now =
        getWorldHours()


    analyzerData.labStartedAt =
        now


    analyzerData.labRemainingHours =
        AC_LaboratoryAnalyzer.CONFIG.processingHours


    analyzerData.labLastUpdateAt =
        now


    analyzerData.labReadyAt =
        now
        + AC_LaboratoryAnalyzer.CONFIG.processingHours


    analyzerData.labAnalyzerState =
        "processing"


    ------------------------------------------------
    -- REMOVE SAMPLE FROM INVENTORY
    ------------------------------------------------

    container:Remove(
        sample
    )


    container:setDrawDirty(
        true
    )


    updateAnalyzerName(
        worldObject,
        "processing"
    )


    print(
        "[AmmoMaking] Laboratory assay started for sample "
        .. tostring(
            analyzerData.stored_sampleX
        )
        .. ", "
        .. tostring(
            analyzerData.stored_sampleY
        )
        .. "; processing time = "
        .. tostring(
            AC_LaboratoryAnalyzer.CONFIG.processingHours
        )
        .. " hours"
    )


    return true, nil
end


------------------------------------------------
-- COLLECT COMPLETED SAMPLE
------------------------------------------------

function AC_LaboratoryAnalyzer.collectSample(
    player,
    worldObject
)

    if not player then

        return nil,
            "no_player"
    end


    local analyzerData =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not analyzerData then

        return nil,
            "invalid_analyzer"
    end


    local state =
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )


    if state == "processing" then

        return nil,
            "not_ready"
    end


    if state ~= "ready" then

        return nil,
            "empty"
    end


    if analyzerData.storedSample
        ~= true
    then

        return nil,
            "missing_sample"
    end


    local sample =
        player:getInventory():AddItem(
            AC_LaboratoryAnalyzer.ITEMS.Sample
        )


    if not sample then

        return nil,
            "item_creation_failed"
    end


    local sampleData =
        sample:getModData()


    ------------------------------------------------
    -- RESTORE ORIGINAL SAMPLE DATA
    ------------------------------------------------

    for _,
        field
    in ipairs(
        AC_LaboratoryAnalyzer.SAMPLE_FIELDS
    )
    do

        sampleData[field] =
            analyzerData[
                "stored_" .. field
            ]
    end


    sampleData.AmmoMakingGeologicalSample =
        true


    ------------------------------------------------
    -- LAB RESULT
    ------------------------------------------------

    sampleData.assayRank =
        3


    sampleData.assayType =
        "Laboratory"


    sampleData.labProcessing =
        false


    sampleData.labStartedAt =
        analyzerData.labStartedAt


    sampleData.labReadyAt =
        getWorldHours()


    sampleData.labCopperResult =
        tonumber(
            analyzerData.labCopperResult
        )
        or 0


    sampleData.labZincResult =
        tonumber(
            analyzerData.labZincResult
        )
        or 0


    sampleData.copperGrade =
        AC_Geology.getGrade(
            sampleData.labCopperResult
        )


    sampleData.zincGrade =
        AC_Geology.getGrade(
            sampleData.labZincResult
        )


    sample:setCustomName(
        true
    )


    sample:setName(
        AC_Text.get(
            "IGUI_AmmoMaking_Item_SampleLab",
            "Laboratory Tested Geological Sample"
        )
    )


    ------------------------------------------------
    -- RESET ANALYZER
    ------------------------------------------------

    clearStoredSample(
        analyzerData
    )


    analyzerData.labAnalyzerState =
        "idle"


    updateAnalyzerName(
        worldObject,
        "idle"
    )


    print(
        "[AmmoMaking] Laboratory tested sample collected"
    )


    return sample, nil
end


------------------------------------------------
-- CANCEL A RUNNING ASSAY
------------------------------------------------
--
-- Returns the stored sample exactly as it went in
-- (same assay, no laboratory result, no XP) and
-- leaves the analyzer idle. The rolled laboratory
-- result is discarded; it was never shown, so
-- cancelling cannot be used to re-roll a known
-- result. A finished assay is collected, not
-- cancelled.
------------------------------------------------

function AC_LaboratoryAnalyzer.cancelAssay(
    player,
    worldObject
)

    if not player then

        return nil,
            "no_player"
    end


    local analyzerData =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not analyzerData then

        return nil,
            "invalid_analyzer"
    end


    local state =
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )


    if state ~= "processing" then

        return nil,
            "not_processing"
    end


    local sample =
        player:getInventory():AddItem(
            AC_LaboratoryAnalyzer.ITEMS.Sample
        )


    if not sample then

        return nil,
            "item_creation_failed"
    end


    local sampleData =
        sample:getModData()


    for _,
        field
    in ipairs(
        AC_LaboratoryAnalyzer.SAMPLE_FIELDS
    )
    do

        sampleData[field] =
            analyzerData[
                "stored_" .. field
            ]
    end


    sampleData.AmmoMakingGeologicalSample =
        true


    sampleData.labProcessing =
        false


    sample:setCustomName(
        true
    )


    if (tonumber(sampleData.assayRank) or 0) > 0 then

        sample:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_SampleTested",
                "Tested Geological Sample"
            )
        )

    else

        sample:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_Sample",
                "Geological Sample"
            )
        )
    end


    clearStoredSample(
        analyzerData
    )


    analyzerData.labAnalyzerState =
        "idle"


    updateAnalyzerName(
        worldObject,
        "idle"
    )


    print(
        "[AmmoMaking] Laboratory assay cancelled; sample "
        .. tostring(
            sampleData.sampleX
        )
        .. ", "
        .. tostring(
            sampleData.sampleY
        )
        .. " returned"
    )


    return sample, nil
end


------------------------------------------------
-- PLACE / PICK UP AVAILABILITY
------------------------------------------------
--
-- Placing and picking up change world objects and
-- inventories on the machine that runs the code. On
-- a multiplayer client that is not authoritative:
-- Build 42 runs a build action's create() on the
-- server, and a client-side pickup would add the
-- item only locally. Both stay disabled there until
-- a server command exists, the same rule as mining.
-- Single-player and local split-screen are fine.
------------------------------------------------

function AC_LaboratoryAnalyzer.isPlacementAvailable()

    return
        not isClient()
end


------------------------------------------------
-- PICK-UP RULE
------------------------------------------------
--
-- A placed analyzer can be picked up only when it is
-- idle and empty. A running assay has to be
-- cancelled (which returns the sample) and a finished
-- one collected first, so a stored sample and its
-- progress never have to travel inside an item.
--
-- Returns true, or false and a reason:
--   invalid_analyzer  not a placed analyzer
--   processing        an assay is running
--   ready             a finished sample is waiting
------------------------------------------------

function AC_LaboratoryAnalyzer.canPickUp(
    worldObject
)

    if not AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
        worldObject
    ) then

        return false,
            "invalid_analyzer"
    end


    local state =
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )


    if state == "processing" then

        return false,
            "processing"
    end


    if state == "ready" then

        return false,
            "ready"
    end


    if state ~= "idle" then

        return false,
            "invalid_analyzer"
    end


    return true, nil
end


------------------------------------------------
-- STATE FOR A NEWLY PLACED ANALYZER
------------------------------------------------
--
-- Called by AC_LaboratoryAnalyzerObject:create() with
-- the new world object's ModData and the ModData of
-- the inventory item being placed.
--
-- An item only carries state when it was a dropped
-- analyzer picked up mid-assay (vanilla pickup of a
-- dropped item cannot be blocked). That state, with
-- its stored sample, is copied onto the placed object
-- instead of being lost. Time spent in an inventory
-- had no power, so a running assay's clock restarts
-- from now rather than counting it.
------------------------------------------------

function AC_LaboratoryAnalyzer.initializePlacedData(
    objectData,
    itemData
)

    if itemData then

        for _,
            field
        in ipairs(
            AC_LaboratoryAnalyzer.STATE_FIELDS
        )
        do

            objectData[field] =
                itemData[field]
        end


        for _,
            field
        in ipairs(
            AC_LaboratoryAnalyzer.SAMPLE_FIELDS
        )
        do

            objectData["stored_" .. field] =
                itemData["stored_" .. field]
        end
    end


    objectData.AmmoMakingLaboratoryAnalyzer =
        true


    objectData.AmmoMakingLaboratoryAnalyzerWorldObject =
        true


    if objectData.labAnalyzerState == "processing" then

        objectData.labLastUpdateAt =
            getWorldHours()
    end


    normalizeState(
        objectData
    )


    return objectData
end


------------------------------------------------
-- STATUS INFO
------------------------------------------------

function AC_LaboratoryAnalyzer.getStatusInfo(
    worldObject
)

    local state =
        AC_LaboratoryAnalyzer.updateState(
            worldObject
        )


    if not state then
        return nil
    end


    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            worldObject
        )


    if not data then
        return nil
    end


    return {

        state =
            state,

        powered =
            AC_LaboratoryAnalyzer.hasPower(
                worldObject
            ),

        hoursRemaining =
            AC_LaboratoryAnalyzer.getHoursRemaining(
                worldObject
            ),

        sampleX =
            data.stored_sampleX,

        sampleY =
            data.stored_sampleY,
    }
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Laboratory analyzer system loaded"
)