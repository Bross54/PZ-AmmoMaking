-- Ammo Making - Geological sampling and assay system
-- Project Zomboid Build 42.20

AC_GeologySampling = AC_GeologySampling or {}


------------------------------------------------
-- CONFIGURATION
------------------------------------------------

AC_GeologySampling.CONFIG = {

    ------------------------------------------------
    -- KIT USES
    ------------------------------------------------

    fieldKitUses = 20,

    advancedFieldKitUses = 10,


    ------------------------------------------------
    -- FIELD ASSAY
    ------------------------------------------------
    --
    -- Field assay only returns a broad geological
    -- grade, so it intentionally has relatively
    -- high internal uncertainty.
    ------------------------------------------------

    fieldMeasurementError = 15,


    ------------------------------------------------
    -- ADVANCED FIELD ASSAY
    ------------------------------------------------
    --
    -- Maximum measurement error:
    --
    -- +/-10 percentage points.
    --
    -- Example:
    -- true concentration = 50%
    -- measured center can be 40-60%.
    --
    -- The displayed result is also shown as a
    -- +/-10 point estimated range.
    ------------------------------------------------

    advancedMeasurementError = 10,

    advancedRangeHalfWidth = 10,


    ------------------------------------------------
    -- LABORATORY ASSAY
    ------------------------------------------------
    --
    -- Maximum instrument error:
    --
    -- +/-2 percentage points.
    ------------------------------------------------

    laboratoryMeasurementError = 2,


    ------------------------------------------------
    -- LAB PROCESSING TIME
    ------------------------------------------------

    laboratoryHours = 24,


    ------------------------------------------------
    -- DIGGING
    ------------------------------------------------

    digActionTime = 180,

    shovelWearChance = 10,

    digSound = "DigFurrowWithShovel",
}


------------------------------------------------
-- ITEMS
------------------------------------------------

AC_GeologySampling.ITEMS = {

    Sample =
        "AmmoMaking.GeologicalSample",

    FieldKit =
        "AmmoMaking.FieldAssayKit",

    AdvancedFieldKit =
        "AmmoMaking.AdvancedFieldAssayKit",

    LaboratoryAnalyzer =
        "AmmoMaking.LaboratoryAssayAnalyzer",
}


------------------------------------------------
-- SHOVELS
------------------------------------------------

AC_GeologySampling.SHOVEL_TYPES = {

    ["Base.Shovel"] = true,

    ["Base.Shovel2"] = true,

    ["Base.HandShovel"] = true,
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


local function round(value)

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
-- MEASURE VALUE WITH ERROR
------------------------------------------------

local function measuredValue(
    trueValue,
    maximumError
)

    trueValue =
        tonumber(trueValue)
        or 0

    maximumError =
        tonumber(maximumError)
        or 0


    local errorAmount = 0


    if maximumError > 0 then

        errorAmount =
            ZombRand(
                (maximumError * 2) + 1
            )
            - maximumError
    end


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
-- SAMPLE
------------------------------------------------

function AC_GeologySampling.isSample(item)

    return
        item ~= nil
        and item:getFullType()
            == AC_GeologySampling.ITEMS.Sample
end


------------------------------------------------
-- SHOVEL
------------------------------------------------

function AC_GeologySampling.isShovel(item)

    if not item then
        return false
    end


    local fullType =
        item:getFullType()


    if AC_GeologySampling.SHOVEL_TYPES[
        fullType
    ] then

        return true
    end


    if item:hasTag("Shovel") then
        return true
    end


    if item:hasTag("DigGrave") then
        return true
    end


    if item:hasTag("DigPlow") then
        return true
    end


    return false
end


function AC_GeologySampling.getEquippedShovel(
    player
)

    if not player then
        return nil
    end


    local primary =
        player:getPrimaryHandItem()


    if AC_GeologySampling.isShovel(
        primary
    ) then

        return primary
    end


    local secondary =
        player:getSecondaryHandItem()


    if AC_GeologySampling.isShovel(
        secondary
    ) then

        return secondary
    end


    return nil
end


------------------------------------------------
-- SHOVEL WEAR
------------------------------------------------

local function applyShovelWear(
    shovel
)

    if not shovel then
        return
    end


    local roll =
        ZombRand(100)


    if roll >=
        AC_GeologySampling.CONFIG.shovelWearChance
    then

        return
    end


    local condition =
        shovel:getCondition()


    if condition <= 0 then
        return
    end


    shovel:setCondition(
        math.max(
            0,
            condition - 1
        )
    )
end


------------------------------------------------
-- CREATE SAMPLE
------------------------------------------------

function AC_GeologySampling.createSample(
    player,
    square,
    shovel
)

    if not player then
        return nil, "no_player"
    end


    if not square then
        return nil, "no_square"
    end


    shovel =
        shovel
        or AC_GeologySampling.getEquippedShovel(
            player
        )


    if not shovel then
        return nil, "no_shovel"
    end


    if not AC_GeologySampling.isShovel(
        shovel
    ) then

        return nil, "no_shovel"
    end


    if not AC_Geology.isSurveyableSquare(
        square
    ) then

        return nil, "invalid_surface"
    end


    local x =
        square:getX()


    local y =
        square:getY()


    ------------------------------------------------
    -- Sample represents a 3x3 geological area
    -- centered on the selected tile.
    ------------------------------------------------

    local survey =
        AC_Geology.surveyArea(
            x,
            y
        )


    if not survey then
        return nil, "survey_failed"
    end


    local sample =
        player:getInventory():AddItem(
            AC_GeologySampling.ITEMS.Sample
        )


    if not sample then
        return nil, "item_creation_failed"
    end


    local data =
        sample:getModData()


    data.AmmoMakingGeologicalSample =
        true


    data.sampleX =
        x


    data.sampleY =
        y


    data.geologySeed =
        AC_WorldData.getGeologySeed()


    ------------------------------------------------
    -- TRUE HIDDEN GEOLOGY
    ------------------------------------------------

    data.trueCopper =
        survey.copperAverage
        or 0


    data.trueZinc =
        survey.zincAverage
        or 0


    data.trueCopperPeak =
        survey.copperPeak
        or 0


    data.trueZincPeak =
        survey.zincPeak
        or 0


    ------------------------------------------------
    -- ASSAY STATE
    ------------------------------------------------

    data.assayRank = 0

    data.assayType = nil


    data.copperGrade = nil

    data.zincGrade = nil


    data.copperMin = nil

    data.copperMax = nil


    data.zincMin = nil

    data.zincMax = nil


    ------------------------------------------------
    -- LABORATORY STATE
    ------------------------------------------------

    data.labProcessing =
        false


    data.labStartedAt =
        nil


    data.labReadyAt =
        nil


    data.labCopperResult =
        nil


    data.labZincResult =
        nil


    sample:setCustomName(
        true
    )


    sample:setName(
        "Geological Sample"
    )


    applyShovelWear(
        shovel
    )


    print(
        "[AmmoMaking] Geological sample collected at "
        .. tostring(x)
        .. ", "
        .. tostring(y)
    )


    return sample, nil
end


------------------------------------------------
-- KIT TYPE
------------------------------------------------

function AC_GeologySampling.getKitType(
    item
)

    if not item then
        return nil
    end


    local fullType =
        item:getFullType()


    if fullType
        == AC_GeologySampling.ITEMS.FieldKit
    then

        return "field"
    end


    if fullType
        == AC_GeologySampling.ITEMS.AdvancedFieldKit
    then

        return "advanced"
    end


    return nil
end


------------------------------------------------
-- KIT RANK
------------------------------------------------

function AC_GeologySampling.getKitRank(
    item
)

    local kitType =
        AC_GeologySampling.getKitType(
            item
        )


    if kitType == "field" then
        return 1
    end


    if kitType == "advanced" then
        return 2
    end


    return 0
end


------------------------------------------------
-- INITIALIZE KIT
------------------------------------------------

function AC_GeologySampling.initializeKit(
    kit
)

    if not kit then
        return nil
    end


    local kitType =
        AC_GeologySampling.getKitType(
            kit
        )


    if not kitType then
        return nil
    end


    local data =
        kit:getModData()


    if data.AmmoMakingAssayKitInitialized then
        return data
    end


    data.AmmoMakingAssayKitInitialized =
        true


    data.assayKitType =
        kitType


    if kitType == "field" then

        data.assayMaxUses =
            AC_GeologySampling.CONFIG.fieldKitUses


        data.assayUsesRemaining =
            AC_GeologySampling.CONFIG.fieldKitUses


    elseif kitType == "advanced" then

        data.assayMaxUses =
            AC_GeologySampling.CONFIG.advancedFieldKitUses


        data.assayUsesRemaining =
            AC_GeologySampling.CONFIG.advancedFieldKitUses
    end


    return data
end


------------------------------------------------
-- KIT DISPLAY NAME
------------------------------------------------

function AC_GeologySampling.updateKitName(
    kit
)

    local data =
        AC_GeologySampling.initializeKit(
            kit
        )


    if not data then
        return
    end


    local kitType =
        AC_GeologySampling.getKitType(
            kit
        )


    local uses =
        tonumber(
            data.assayUsesRemaining
        )
        or 0


    local maximum =
        tonumber(
            data.assayMaxUses
        )
        or 0


    kit:setCustomName(
        true
    )


    if kitType == "field" then

        kit:setName(
            "Field Assay Kit ("
            .. tostring(uses)
            .. "/"
            .. tostring(maximum)
            .. ")"
        )


    elseif kitType == "advanced" then

        kit:setName(
            "Advanced Field Assay Kit ("
            .. tostring(uses)
            .. "/"
            .. tostring(maximum)
            .. ")"
        )
    end
end


------------------------------------------------
-- KIT USES
------------------------------------------------

function AC_GeologySampling.getKitUses(
    kit
)

    local data =
        AC_GeologySampling.initializeKit(
            kit
        )


    if not data then
        return 0
    end


    return
        tonumber(
            data.assayUsesRemaining
        )
        or 0
end


function AC_GeologySampling.consumeKitUse(
    kit
)

    local data =
        AC_GeologySampling.initializeKit(
            kit
        )


    if not data then
        return false
    end


    local uses =
        tonumber(
            data.assayUsesRemaining
        )
        or 0


    if uses <= 0 then
        return false
    end


    data.assayUsesRemaining =
        uses - 1


    AC_GeologySampling.updateKitName(
        kit
    )


    return true
end


------------------------------------------------
-- FIELD ASSAY
------------------------------------------------

local function performFieldAssay(
    sample
)

    local data =
        sample:getModData()


    local copper =
        measuredValue(
            data.trueCopper,
            AC_GeologySampling.CONFIG.fieldMeasurementError
        )


    local zinc =
        measuredValue(
            data.trueZinc,
            AC_GeologySampling.CONFIG.fieldMeasurementError
        )


    data.copperGrade =
        AC_Geology.getGrade(
            copper
        )


    data.zincGrade =
        AC_Geology.getGrade(
            zinc
        )


    data.copperMin =
        nil


    data.copperMax =
        nil


    data.zincMin =
        nil


    data.zincMax =
        nil


    data.assayRank =
        1


    data.assayType =
        "Field"
end


------------------------------------------------
-- ADVANCED FIELD ASSAY
------------------------------------------------

local function performAdvancedFieldAssay(
    sample
)

    local data =
        sample:getModData()


    ------------------------------------------------
    -- Estimated center may deviate from the true
    -- concentration by up to +/-10 points.
    ------------------------------------------------

    local copperCenter =
        measuredValue(
            data.trueCopper,
            AC_GeologySampling.CONFIG.advancedMeasurementError
        )


    local zincCenter =
        measuredValue(
            data.trueZinc,
            AC_GeologySampling.CONFIG.advancedMeasurementError
        )


    local margin =
        AC_GeologySampling.CONFIG.advancedRangeHalfWidth


    ------------------------------------------------
    -- Display +/-10% estimate range.
    ------------------------------------------------

    data.copperMin =
        clamp(
            copperCenter - margin,
            0,
            100
        )


    data.copperMax =
        clamp(
            copperCenter + margin,
            0,
            100
        )


    data.zincMin =
        clamp(
            zincCenter - margin,
            0,
            100
        )


    data.zincMax =
        clamp(
            zincCenter + margin,
            0,
            100
        )


    data.copperGrade =
        AC_Geology.getGrade(
            copperCenter
        )


    data.zincGrade =
        AC_Geology.getGrade(
            zincCenter
        )


    data.assayRank =
        2


    data.assayType =
        "Advanced Field"
end


------------------------------------------------
-- ANALYZE WITH PORTABLE KIT
------------------------------------------------

function AC_GeologySampling.analyzeSample(
    sample,
    kit
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return false, "invalid_sample"
    end


    local data =
        sample:getModData()


    if data.labProcessing == true then

        return false, "lab_processing"
    end


    local kitRank =
        AC_GeologySampling.getKitRank(
            kit
        )


    if kitRank <= 0 then

        return false, "invalid_kit"
    end


    local currentRank =
        tonumber(
            data.assayRank
        )
        or 0


    if currentRank >= kitRank then

        return false, "already_analyzed"
    end


    if AC_GeologySampling.getKitUses(
        kit
    ) <= 0
    then

        return false, "kit_empty"
    end


    if not AC_GeologySampling.consumeKitUse(
        kit
    ) then

        return false, "kit_empty"
    end


    if kitRank == 1 then

        performFieldAssay(
            sample
        )


    elseif kitRank == 2 then

        performAdvancedFieldAssay(
            sample
        )
    end


    sample:setCustomName(
        true
    )


    sample:setName(
        "Tested Geological Sample"
    )


    print(
        "[AmmoMaking] Sample analyzed with "
        .. tostring(
            data.assayType
        )
        .. " Assay"
    )


    return true, nil
end


------------------------------------------------
-- LABORATORY ANALYZER
------------------------------------------------

function AC_GeologySampling.isLaboratoryAnalyzer(
    item
)

    return
        item ~= nil
        and item:getFullType()
            == AC_GeologySampling.ITEMS.LaboratoryAnalyzer
end


------------------------------------------------
-- START LABORATORY ASSAY
------------------------------------------------

function AC_GeologySampling.startLaboratoryAssay(
    sample,
    analyzer
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return false, "invalid_sample"
    end


    if not AC_GeologySampling.isLaboratoryAnalyzer(
        analyzer
    ) then

        return false, "invalid_analyzer"
    end


    local data =
        sample:getModData()


    if data.labProcessing == true then

        return false, "lab_processing"
    end


    local currentRank =
        tonumber(
            data.assayRank
        )
        or 0


    if currentRank >= 3 then

        return false, "already_analyzed"
    end


    ------------------------------------------------
    -- Final laboratory measurement is rolled when
    -- processing starts.
    --
    -- Reloading the save therefore cannot reroll
    -- the result.
    --
    -- Accuracy:
    -- +/-2 percentage points.
    ------------------------------------------------

    data.labCopperResult =
        measuredValue(
            data.trueCopper,
            AC_GeologySampling.CONFIG.laboratoryMeasurementError
        )


    data.labZincResult =
        measuredValue(
            data.trueZinc,
            AC_GeologySampling.CONFIG.laboratoryMeasurementError
        )


    local now =
        getWorldHours()


    data.labStartedAt =
        now


    data.labReadyAt =
        now
        + AC_GeologySampling.CONFIG.laboratoryHours


    data.labProcessing =
        true


    sample:setCustomName(
        true
    )


    sample:setName(
        "Geological Sample (Lab Processing)"
    )


    print(
        "[AmmoMaking] Laboratory assay started at world hour "
        .. tostring(now)
        .. "; ready at "
        .. tostring(data.labReadyAt)
    )


    return true, nil
end


------------------------------------------------
-- UPDATE LABORATORY ASSAY
------------------------------------------------

function AC_GeologySampling.updateLaboratoryAssay(
    sample
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return false
    end


    local data =
        sample:getModData()


    if data.labProcessing ~= true then
        return false
    end


    local readyAt =
        tonumber(
            data.labReadyAt
        )


    if not readyAt then
        return false
    end


    if getWorldHours() < readyAt then
        return false
    end


    data.labProcessing =
        false


    data.assayRank =
        3


    data.assayType =
        "Laboratory"


    data.copperGrade =
        AC_Geology.getGrade(
            tonumber(
                data.labCopperResult
            )
            or 0
        )


    data.zincGrade =
        AC_Geology.getGrade(
            tonumber(
                data.labZincResult
            )
            or 0
        )


    sample:setCustomName(
        true
    )


    sample:setName(
        "Laboratory Tested Geological Sample"
    )


    print(
        "[AmmoMaking] Laboratory assay completed for sample "
        .. tostring(
            data.sampleX
        )
        .. ", "
        .. tostring(
            data.sampleY
        )
    )


    return true
end


------------------------------------------------
-- LAB PROCESSING STATE
------------------------------------------------

function AC_GeologySampling.isLaboratoryProcessing(
    sample
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return false
    end


    AC_GeologySampling.updateLaboratoryAssay(
        sample
    )


    return
        sample:getModData().labProcessing
        == true
end


------------------------------------------------
-- LAB HOURS REMAINING
------------------------------------------------

function AC_GeologySampling.getLaboratoryHoursRemaining(
    sample
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return 0
    end


    AC_GeologySampling.updateLaboratoryAssay(
        sample
    )


    local data =
        sample:getModData()


    if data.labProcessing ~= true then
        return 0
    end


    local readyAt =
        tonumber(
            data.labReadyAt
        )
        or 0


    return math.max(
        0,
        readyAt - getWorldHours()
    )
end


------------------------------------------------
-- FIND KIT
------------------------------------------------

function AC_GeologySampling.findKit(
    player,
    fullType
)

    if not player then
        return nil
    end


    local items =
        player:getInventory():
            getItemsFromFullType(
                fullType,
                true
            )


    if not items then
        return nil
    end


    for index = 0,
        items:size() - 1
    do

        local item =
            items:get(
                index
            )


        if AC_GeologySampling.getKitUses(
            item
        ) > 0
        then

            AC_GeologySampling.updateKitName(
                item
            )


            return item
        end
    end


    return nil
end


------------------------------------------------
-- FIND LABORATORY ANALYZER
------------------------------------------------

function AC_GeologySampling.findLaboratoryAnalyzer(
    player
)

    if not player then
        return nil
    end


    local items =
        player:getInventory():
            getItemsFromFullType(
                AC_GeologySampling.ITEMS.LaboratoryAnalyzer,
                true
            )


    if not items
        or items:size() <= 0
    then

        return nil
    end


    return items:get(0)
end


------------------------------------------------
-- RESULT LINES
------------------------------------------------

function AC_GeologySampling.getResultLines(
    sample
)

    if not AC_GeologySampling.isSample(
        sample
    ) then

        return nil
    end


    AC_GeologySampling.updateLaboratoryAssay(
        sample
    )


    local data =
        sample:getModData()


    local rank =
        tonumber(
            data.assayRank
        )
        or 0


    local lines = {}


    table.insert(
        lines,
        "Sample Location: "
        .. tostring(
            data.sampleX
        )
        .. ", "
        .. tostring(
            data.sampleY
        )
    )


    ------------------------------------------------
    -- LAB PROCESSING
    ------------------------------------------------

    if data.labProcessing == true then

        local remaining =
            AC_GeologySampling.getLaboratoryHoursRemaining(
                sample
            )


        table.insert(
            lines,
            "Analysis: Laboratory Assay"
        )


        table.insert(
            lines,
            "Status: Processing"
        )


        table.insert(
            lines,
            string.format(
                "Time Remaining: %.1f hours",
                remaining
            )
        )


        return lines
    end


    ------------------------------------------------
    -- UNTESTED
    ------------------------------------------------

    if rank <= 0 then

        table.insert(
            lines,
            "Status: Untested"
        )


        return lines
    end


    ------------------------------------------------
    -- FIELD
    ------------------------------------------------

    if rank == 1 then

        table.insert(
            lines,
            "Analysis: Field Assay"
        )


        table.insert(
            lines,
            "Copper: "
            .. tostring(
                data.copperGrade
            )
        )


        table.insert(
            lines,
            "Zinc: "
            .. tostring(
                data.zincGrade
            )
        )


        return lines
    end


    ------------------------------------------------
    -- ADVANCED FIELD
    ------------------------------------------------

    if rank == 2 then

        table.insert(
            lines,
            "Analysis: Advanced Field Assay"
        )


        table.insert(
            lines,
            "Copper: "
            .. tostring(
                data.copperMin
            )
            .. "-"
            .. tostring(
                data.copperMax
            )
            .. "%"
            .. " ("
            .. tostring(
                data.copperGrade
            )
            .. ")"
        )


        table.insert(
            lines,
            "Zinc: "
            .. tostring(
                data.zincMin
            )
            .. "-"
            .. tostring(
                data.zincMax
            )
            .. "%"
            .. " ("
            .. tostring(
                data.zincGrade
            )
            .. ")"
        )


        table.insert(
            lines,
            "Estimated Accuracy: +/-10%"
        )


        return lines
    end


    ------------------------------------------------
    -- LABORATORY
    ------------------------------------------------

    table.insert(
        lines,
        "Analysis: Laboratory Assay"
    )


    table.insert(
        lines,
        "Copper: "
        .. tostring(
            data.labCopperResult
        )
        .. "%"
        .. " ("
        .. tostring(
            data.copperGrade
        )
        .. ")"
    )


    table.insert(
        lines,
        "Zinc: "
        .. tostring(
            data.labZincResult
        )
        .. "%"
        .. " ("
        .. tostring(
            data.zincGrade
        )
        .. ")"
    )


    table.insert(
        lines,
        "Instrument Tolerance: +/-2%"
    )


    return lines
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Geological sampling system loaded"
)