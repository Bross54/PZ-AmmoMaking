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
-- WORLD ANALYZER CHECK
------------------------------------------------

function AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
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
-- GET ANALYZER ITEM
------------------------------------------------

function AC_LaboratoryAnalyzer.getAnalyzerItem(
    worldObject
)

    if not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
        worldObject
    ) then

        return nil
    end


    return worldObject:getItem()
end


------------------------------------------------
-- UPDATE ANALYZER NAME
------------------------------------------------

local function updateAnalyzerName(
    item,
    state
)

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
-- INITIALIZE ANALYZER
------------------------------------------------

function AC_LaboratoryAnalyzer.initialize(
    worldObject
)

    local item =
        AC_LaboratoryAnalyzer.getAnalyzerItem(
            worldObject
        )


    if not item then
        return nil, nil
    end


    local data =
        item:getModData()


    data.AmmoMakingLaboratoryAnalyzer =
        true


    if not data.labAnalyzerState then

        data.labAnalyzerState =
            "idle"
    end


    updateAnalyzerName(
        item,
        data.labAnalyzerState
    )


    return item, data
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

    local item,
          data =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not item
        or not data
    then

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
            item,
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


    local item =
        AC_LaboratoryAnalyzer.getAnalyzerItem(
            worldObject
        )


    if not item then
        return 0
    end


    local data =
        item:getModData()


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


    local item,
          analyzerData =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not item
        or not analyzerData
    then

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
        item,
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


    local item,
          analyzerData =
        AC_LaboratoryAnalyzer.initialize(
            worldObject
        )


    if not item
        or not analyzerData
    then

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
        "Laboratory Tested Geological Sample"
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
        item,
        "idle"
    )


    print(
        "[AmmoMaking] Laboratory tested sample collected"
    )


    return sample, nil
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


    local item =
        AC_LaboratoryAnalyzer.getAnalyzerItem(
            worldObject
        )


    if not item then
        return nil
    end


    local data =
        item:getModData()


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