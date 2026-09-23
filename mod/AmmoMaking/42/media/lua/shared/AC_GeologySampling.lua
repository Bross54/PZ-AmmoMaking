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
    -- DIGGING
    ------------------------------------------------
    --
    -- digActionTime: timed action length, same base
    -- as vanilla grave digging.
    --
    -- digSound: emitter sound played while digging.
    -- "Shoveling" is the vanilla ISBuildAction sound
    -- and is the one that has been heard in-game.
    ------------------------------------------------

    digActionTime = 150,

    shovelWearChance = 10,

    digSound = "Shoveling",

    digSoundRadius = 15,


    ------------------------------------------------
    -- AMMO MAKING XP
    ------------------------------------------------
    --
    -- Granted per successful portable assay. Kit uses
    -- are limited, so this cannot be farmed.
    -- Digging samples gives no XP for that reason.
    ------------------------------------------------

    fieldAssayXP = 3,

    advancedAssayXP = 6,
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
    --
    -- Filled in by AC_LaboratoryAnalyzer.collectSample
    -- when a laboratory result is returned. Kept here
    -- so every sample carries the same field set.
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
        AC_Text.get(
            "IGUI_AmmoMaking_Item_Sample",
            "Geological Sample"
        )
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
-- KIT XP
------------------------------------------------

function AC_GeologySampling.getAssayXP(
    kit
)

    local kitRank =
        AC_GeologySampling.getKitRank(
            kit
        )


    if kitRank == 1 then

        return
            AC_GeologySampling.CONFIG.fieldAssayXP
    end


    if kitRank == 2 then

        return
            AC_GeologySampling.CONFIG.advancedAssayXP
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
            AC_Text.get(
                "IGUI_AmmoMaking_Item_FieldKit",
                "Field Assay Kit (%1/%2)",
                uses,
                maximum
            )
        )


    elseif kitType == "advanced" then

        kit:setName(
            AC_Text.get(
                "IGUI_AmmoMaking_Item_AdvancedKit",
                "Advanced Field Assay Kit (%1/%2)",
                uses,
                maximum
            )
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
        AC_Text.get(
            "IGUI_AmmoMaking_Item_SampleTested",
            "Tested Geological Sample"
        )
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


    local data =
        sample:getModData()


    local rank =
        tonumber(
            data.assayRank
        )
        or 0


    local lines = {}


    local copperName =
        AC_Deposits.getMetalName(
            "copper"
        )

    local zincName =
        AC_Deposits.getMetalName(
            "zinc"
        )


    table.insert(
        lines,
        AC_Text.get(
            "IGUI_AmmoMaking_Result_Location",
            "Sample Location: %1, %2",
            data.sampleX,
            data.sampleY
        )
    )


    ------------------------------------------------
    -- UNTESTED
    ------------------------------------------------

    if rank <= 0 then

        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Untested",
                "Status: Untested"
            )
        )


        return lines
    end


    ------------------------------------------------
    -- FIELD
    ------------------------------------------------

    if rank == 1 then

        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_FieldAssay",
                "Analysis: Field Assay"
            )
        )


        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Grade",
                "%1: %2",
                copperName,
                AC_Geology.getGradeName(
                    data.copperGrade
                )
            )
        )


        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Grade",
                "%1: %2",
                zincName,
                AC_Geology.getGradeName(
                    data.zincGrade
                )
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
            AC_Text.get(
                "IGUI_AmmoMaking_Result_AdvancedAssay",
                "Analysis: Advanced Field Assay"
            )
        )


        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Range",
                "%1: %2-%3% (%4)",
                copperName,
                data.copperMin,
                data.copperMax,
                AC_Geology.getGradeName(
                    data.copperGrade
                )
            )
        )


        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Range",
                "%1: %2-%3% (%4)",
                zincName,
                data.zincMin,
                data.zincMax,
                AC_Geology.getGradeName(
                    data.zincGrade
                )
            )
        )


        table.insert(
            lines,
            AC_Text.get(
                "IGUI_AmmoMaking_Result_Accuracy",
                "Estimated Accuracy: +/-%1%",
                AC_GeologySampling.CONFIG.advancedRangeHalfWidth
            )
        )


        return lines
    end


    ------------------------------------------------
    -- LABORATORY
    ------------------------------------------------

    table.insert(
        lines,
        AC_Text.get(
            "IGUI_AmmoMaking_Result_LabAssay",
            "Analysis: Laboratory Assay"
        )
    )


    table.insert(
        lines,
        AC_Text.get(
            "IGUI_AmmoMaking_Result_Exact",
            "%1: %2% (%3)",
            copperName,
            data.labCopperResult,
            AC_Geology.getGradeName(
                data.copperGrade
            )
        )
    )


    table.insert(
        lines,
        AC_Text.get(
            "IGUI_AmmoMaking_Result_Exact",
            "%1: %2% (%3)",
            zincName,
            data.labZincResult,
            AC_Geology.getGradeName(
                data.zincGrade
            )
        )
    )


    table.insert(
        lines,
        AC_Text.get(
            "IGUI_AmmoMaking_Result_Tolerance",
            "Instrument Tolerance: +/-%1%",
            AC_LaboratoryAnalyzer.CONFIG.measurementError
        )
    )


    return lines
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Geological sampling system loaded"
)