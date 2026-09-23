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
-- INVENTORY ANALYZER ITEM
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
-- LEGACY DROPPED ANALYZER
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


    local item =
        worldObject:getItem()


    return
        AC_LaboratoryAnalyzer.isAnalyzerItem(
            item
        )
end


------------------------------------------------
-- NEW PLACED ANALYZER
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


    local data =
        worldObject:getModData()


    if data
        and data.AmmoMakingLaboratoryAnalyzerWorldObject
            == true
    then

        return true
    end


    if worldObject.getName
        and worldObject:getName()
            == AC_LaboratoryAnalyzer.OBJECT_NAME
    then

        return true
    end


    return false
end


------------------------------------------------
-- ANY ANALYZER WORLD OBJECT
------------------------------------------------

function AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
    worldObject
)

    return
        AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
            worldObject
        )
        or
        AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            worldObject
        )
end


------------------------------------------------
-- LEGACY ANALYZER ITEM
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

function AC_LaboratoryAnalyzer.getAnalyzerData(
    worldObject
)

    if AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
        worldObject
    ) then

        local item =
            worldObject:getItem()


        if not item then
            return nil
        end


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
-- UPDATE LEGACY DROPPED ITEM NAME
------------------------------------------------

local function updateLegacyAnalyzerName(
    worldObject,
    state
)

    if not AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(
        worldObject
    ) then

        return
    end


    local item =
        worldObject:getItem()


    if not item then
        return
    end


    item:setCustomName(
        true
    )


    if state == "processing" then

        item:setName(
            "Laboratory Assay Analyzer (Processing)"
        )


    elseif state == "ready" then

        item:setName(
            "Laboratory Assay Analyzer (Result Ready)"
        )


    else

        item:setName(
            "Laboratory Assay Analyzer"
        )
    end
end


------------------------------------------------
-- INITIALIZE
------------------------------------------------

function AC_LaboratoryAnalyzer.initialize(
    worldObject
)

    if not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
        worldObject
    ) then

        return nil
    end


    local data =
        AC_LaboratoryAnalyzer.getAnalyzerData(
            worldObject
        )


    if not data then
        return nil
    end


    data.AmmoMakingLaboratoryAnalyzer =
        true


    if not data.labAnalyzerState then

        data.labAnalyzerState =
            "idle"
    end


    updateLegacyAnalyzerName(
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
    -- Generator / local electrical power.
    ------------------------------------------------

    if square:haveElectricity() then

        return true
    end


    ------------------------------------------------
    -- Utility grid power.
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
-- UPDATE PROCESSING
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
    -- MIGRATE OLD READY-AT TIMER
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
    -- Only process while powered.
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


        updateLegacyAnalyzerName(
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
-- SAMPLE ELIGIBILITY
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
-- STORE SAMPLE
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
-- CLEAR SAMPLE
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
-- START ASSAY
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


    local data =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not data then

        return false,
            "invalid_analyzer"
    end


    AC_LaboratoryAnalyzer.updateState(
        worldObject
    )


    if data.labAnalyzerState
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
    -- COPY SAMPLE DATA
    ------------------------------------------------

    storeSampleData(
        data,
        sample
    )


    ------------------------------------------------
    -- Roll result immediately.
    ------------------------------------------------

    local sampleData =
        sample:getModData()


    data.labCopperResult =
        laboratoryMeasurement(
            sampleData.trueCopper
        )


    data.labZincResult =
        laboratoryMeasurement(
            sampleData.trueZinc
        )


    ------------------------------------------------
    -- START TIMER
    ------------------------------------------------

    local now =
        getWorldHours()


    data.labStartedAt =
        now


    data.labRemainingHours =
        AC_LaboratoryAnalyzer.CONFIG.processingHours


    data.labLastUpdateAt =
        now


    data.labReadyAt =
        now
        + AC_LaboratoryAnalyzer.CONFIG.processingHours


    data.labAnalyzerState =
        "processing"


    ------------------------------------------------
    -- REMOVE PHYSICAL SAMPLE
    ------------------------------------------------

    container:Remove(
        sample
    )


    container:setDrawDirty(
        true
    )


    updateLegacyAnalyzerName(
        worldObject,
        "processing"
    )


    print(
        "[AmmoMaking] Laboratory assay started for sample "
        .. tostring(
            data.stored_sampleX
        )
        .. ", "
        .. tostring(
            data.stored_sampleY
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
-- COLLECT SAMPLE
------------------------------------------------

function AC_LaboratoryAnalyzer.collectSample(
    player,
    worldObject
)

    if not player then

        return nil,
            "no_player"
    end


    local data =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not data then

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


    if data.storedSample
        ~= true
    then

        return nil,
            "missing_sample"
    end


    ------------------------------------------------
    -- Recreate sample.
    ------------------------------------------------

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
    -- Restore original geology.
    ------------------------------------------------

    for _,
        field
    in ipairs(
        AC_LaboratoryAnalyzer.SAMPLE_FIELDS
    )
    do

        sampleData[field] =
            data[
                "stored_" .. field
            ]
    end


    sampleData.AmmoMakingGeologicalSample =
        true


    ------------------------------------------------
    -- FINAL LAB RESULT
    ------------------------------------------------

    sampleData.assayRank =
        3


    sampleData.assayType =
        "Laboratory"


    sampleData.labProcessing =
        false


    sampleData.labStartedAt =
        data.labStartedAt


    sampleData.labReadyAt =
        getWorldHours()


    sampleData.labCopperResult =
        tonumber(
            data.labCopperResult
        )
        or 0


    sampleData.labZincResult =
        tonumber(
            data.labZincResult
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
        "Laboratory Tested Geological Sample"
    )


    ------------------------------------------------
    -- RESET ANALYZER
    ------------------------------------------------

    clearStoredSample(
        data
    )


    data.labAnalyzerState =
        "idle"


    updateLegacyAnalyzerName(
        worldObject,
        "idle"
    )


    print(
        "[AmmoMaking] Laboratory tested sample collected"
    )


    return sample, nil
end


------------------------------------------------
-- STATUS
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
-- LOAD
------------------------------------------------

print(
    "[AmmoMaking] Laboratory analyzer system loaded"
)