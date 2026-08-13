-- Ammo Making - Geological sampling context menus
-- Project Zomboid Build 42.20

require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTimedActionQueue"
require "luautils"


------------------------------------------------
-- GET INVENTORY ITEM
------------------------------------------------

local function getActualItem(
    entry
)

    if not entry then
        return nil
    end


    if entry.getFullType then
        return entry
    end


    if entry.items
        and entry.items[1]
    then

        return entry.items[1]
    end


    return nil
end


------------------------------------------------
-- GET CLICKED SQUARE
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
-- VALID SAMPLING LOCATION
------------------------------------------------

local function isValidSamplingSquare(
    square
)

    if not square then
        return false
    end


    ------------------------------------------------
    -- Never allow soil sampling inside a mapped
    -- room/building, regardless of the underlying
    -- floor sprite.
    ------------------------------------------------

    if square:getRoom() ~= nil then

        return false
    end


    return
        AC_Geology.isSurveyableSquare(
            square
        )
end


------------------------------------------------
-- FIND LAB ANALYZER
------------------------------------------------

local function getAnalyzerWorldObject(
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

        if AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
            object
        ) then

            return object
        end
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

                local worldItems =
                    square:getWorldObjects()


                if worldItems then

                    for index = 0,
                        worldItems:size() - 1
                    do

                        local worldItem =
                            worldItems:get(
                                index
                            )


                        if AC_LaboratoryAnalyzer.isAnalyzerWorldObject(
                            worldItem
                        ) then

                            return worldItem
                        end
                    end
                end
            end
        end
    end


    return nil
end


------------------------------------------------
-- DIG SAMPLE
------------------------------------------------

local function digSample(
    player,
    square
)

    if not player
        or not square
    then

        return
    end


    if not isValidSamplingSquare(
        square
    ) then

        HaloTextHelper.addText(
            player,
            "Requires outdoor natural ground"
        )


        return
    end


    local shovel =
        AC_GeologySampling.getEquippedShovel(
            player
        )


    if not shovel then

        HaloTextHelper.addText(
            player,
            "Equip a shovel first"
        )


        return
    end


    if not luautils.walkAdj(
        player,
        square
    ) then

        HaloTextHelper.addText(
            player,
            "Cannot reach sampling location"
        )


        return
    end


    ISTimedActionQueue.add(
        AC_DigGeologicalSampleAction:new(
            player,
            square,
            shovel
        )
    )
end


------------------------------------------------
-- VIEW SAMPLE RESULT
------------------------------------------------

local function viewAssay(
    player,
    sample
)

    if not player
        or not sample
    then

        return
    end


    AC_GeologySampling.updateLaboratoryAssay(
        sample
    )


    AC_GeologyAssayUI.open(
        player,
        sample
    )
end


------------------------------------------------
-- PORTABLE ASSAY
------------------------------------------------

local function analyzeSample(
    player,
    sample,
    kit
)

    if not player
        or not sample
        or not kit
    then

        return
    end


    local success,
          errorCode =
        AC_GeologySampling.analyzeSample(
            sample,
            kit
        )


    if not success then

        if errorCode == "kit_empty" then

            HaloTextHelper.addText(
                player,
                "Assay kit is empty"
            )

        elseif errorCode
            == "already_analyzed"
        then

            HaloTextHelper.addText(
                player,
                "Sample already has an equal or better assay"
            )

        elseif errorCode
            == "lab_processing"
        then

            HaloTextHelper.addText(
                player,
                "Sample is currently being analyzed"
            )

        else

            HaloTextHelper.addText(
                player,
                "Analysis failed"
            )
        end


        return
    end


    HaloTextHelper.addText(
        player,
        "Sample analyzed"
    )


    AC_GeologyAssayUI.open(
        player,
        sample
    )
end


------------------------------------------------
-- SHOW LAB STATUS
------------------------------------------------

local function showLaboratoryStatus(
    player,
    analyzerWorldObject
)

    if not player
        or not analyzerWorldObject
    then

        return
    end


    local info =
        AC_LaboratoryAnalyzer.getStatusInfo(
            analyzerWorldObject
        )


    if not info then

        HaloTextHelper.addText(
            player,
            "Invalid laboratory analyzer"
        )


        return
    end


    if info.state == "idle" then

        if info.powered then

            HaloTextHelper.addText(
                player,
                "Laboratory analyzer ready"
            )

        else

            HaloTextHelper.addText(
                player,
                "Laboratory analyzer has no power"
            )
        end


        return
    end


    if info.state == "processing" then

        local prefix =
            "Processing"


        if not info.powered then

            prefix =
                "Processing paused - no power"
        end


        local text =
            string.format(
                "%s - %.1f hours remaining",
                prefix,
                tonumber(
                    info.hoursRemaining
                )
                or 0
            )


        HaloTextHelper.addText(
            player,
            text
        )


        return
    end


    if info.state == "ready" then

        HaloTextHelper.addText(
            player,
            "Laboratory assay complete - result ready"
        )
    end
end


------------------------------------------------
-- START LAB ASSAY
------------------------------------------------

local function startLaboratoryAssay(
    player,
    analyzerWorldObject,
    sample
)

    if not player
        or not analyzerWorldObject
        or not sample
    then

        return
    end


    local success,
          errorCode =
        AC_LaboratoryAnalyzer.startAssay(
            player,
            analyzerWorldObject,
            sample
        )


    if not success then

        if errorCode == "no_power" then

            HaloTextHelper.addText(
                player,
                "Laboratory analyzer requires electricity"
            )

        elseif errorCode == "busy" then

            HaloTextHelper.addText(
                player,
                "Laboratory analyzer is already occupied"
            )

        elseif errorCode
            == "invalid_sample"
        then

            HaloTextHelper.addText(
                player,
                "This sample cannot be analyzed"
            )

        else

            HaloTextHelper.addText(
                player,
                "Could not start laboratory assay"
            )
        end


        return
    end


    HaloTextHelper.addText(
        player,
        "Laboratory assay started - 24 hours"
    )
end


------------------------------------------------
-- COLLECT LAB SAMPLE
------------------------------------------------

local function collectLaboratorySample(
    player,
    analyzerWorldObject
)

    if not player
        or not analyzerWorldObject
    then

        return
    end


    local sample,
          errorCode =
        AC_LaboratoryAnalyzer.collectSample(
            player,
            analyzerWorldObject
        )


    if not sample then

        if errorCode == "not_ready" then

            HaloTextHelper.addText(
                player,
                "Laboratory assay is still processing"
            )

        elseif errorCode == "empty" then

            HaloTextHelper.addText(
                player,
                "Laboratory analyzer is empty"
            )

        else

            HaloTextHelper.addText(
                player,
                "Could not collect laboratory sample"
            )
        end


        return
    end


    HaloTextHelper.addText(
        player,
        "Laboratory tested sample collected"
    )


    AC_GeologyAssayUI.open(
        player,
        sample
    )
end


------------------------------------------------
-- ADD ANALYZER OPTIONS
------------------------------------------------

local function addLaboratoryAnalyzerOptions(
    player,
    context,
    analyzerWorldObject
)

    if not player
        or not context
        or not analyzerWorldObject
    then

        return
    end


    local info =
        AC_LaboratoryAnalyzer.getStatusInfo(
            analyzerWorldObject
        )


    if not info then
        return
    end


    ------------------------------------------------
    -- IDLE
    ------------------------------------------------

    if info.state == "idle" then

        context:addOption(
            "Check Laboratory Analyzer",
            player,
            showLaboratoryStatus,
            analyzerWorldObject
        )


        if not info.powered then

            local option =
                context:addOption(
                    "Laboratory Analyzer - Requires Electricity"
                )


            option.notAvailable =
                true


            return
        end


        local samples =
            player:getInventory():
                getItemsFromFullType(
                    AC_LaboratoryAnalyzer.ITEMS.Sample,
                    true
                )


        local foundSample =
            false


        if samples then

            for index = 0,
                samples:size() - 1
            do

                local sample =
                    samples:get(
                        index
                    )


                if AC_LaboratoryAnalyzer.canAnalyzeSample(
                    sample
                ) then

                    foundSample =
                        true


                    local data =
                        sample:getModData()


                    local optionName =
                        "Start Lab Assay: Sample "
                        .. tostring(
                            data.sampleX
                        )
                        .. ", "
                        .. tostring(
                            data.sampleY
                        )


                    context:addOption(
                        optionName,
                        player,
                        startLaboratoryAssay,
                        analyzerWorldObject,
                        sample
                    )
                end
            end
        end


        if not foundSample then

            local option =
                context:addOption(
                    "No Geological Samples Available"
                )


            option.notAvailable =
                true
        end


        return
    end


    ------------------------------------------------
    -- PROCESSING
    --
    -- Only ONE status option now.
    ------------------------------------------------

    if info.state == "processing" then

        context:addOption(
            "Check Laboratory Progress",
            player,
            showLaboratoryStatus,
            analyzerWorldObject
        )


        return
    end


    ------------------------------------------------
    -- READY
    ------------------------------------------------

    if info.state == "ready" then

        context:addOption(
            "Collect Laboratory Sample",
            player,
            collectLaboratorySample,
            analyzerWorldObject
        )
    end
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


    local player =
        getSpecificPlayer(
            playerIndex
        )


    if not player then
        return
    end


    ------------------------------------------------
    -- LAB ANALYZER
    ------------------------------------------------

    local analyzerWorldObject =
        getAnalyzerWorldObject(
            worldObjects
        )


    if analyzerWorldObject then

        addLaboratoryAnalyzerOptions(
            player,
            context,
            analyzerWorldObject
        )
    end


    ------------------------------------------------
    -- GEOLOGICAL SAMPLING
    ------------------------------------------------

    local shovel =
        AC_GeologySampling.getEquippedShovel(
            player
        )


    if not shovel then
        return
    end


    local square =
        getClickedSquare(
            worldObjects
        )


    if not isValidSamplingSquare(
        square
    ) then

        return
    end


    context:addOption(
        "Dig Geological Sample",
        player,
        digSample,
        square
    )
end


------------------------------------------------
-- INVENTORY CONTEXT MENU
------------------------------------------------

local function onFillInventoryContextMenu(
    playerIndex,
    context,
    items
)

    local player =
        getSpecificPlayer(
            playerIndex
        )


    if not player then
        return
    end


    for _,
        entry
    in ipairs(
        items
    )
    do

        local item =
            getActualItem(
                entry
            )


        if AC_GeologySampling.isSample(
            item
        ) then

            AC_GeologySampling.updateLaboratoryAssay(
                item
            )


            local data =
                item:getModData()


            local assayRank =
                tonumber(
                    data.assayRank
                )
                or 0


            if assayRank > 0 then

                context:addOption(
                    "View Assay Result",
                    player,
                    viewAssay,
                    item
                )
            end


            if assayRank < 1 then

                local fieldKit =
                    AC_GeologySampling.findKit(
                        player,
                        AC_GeologySampling.ITEMS.FieldKit
                    )


                if fieldKit then

                    context:addOption(
                        "Analyze with Field Assay Kit",
                        player,
                        analyzeSample,
                        item,
                        fieldKit
                    )
                end
            end


            if assayRank < 2 then

                local advancedKit =
                    AC_GeologySampling.findKit(
                        player,
                        AC_GeologySampling.ITEMS.AdvancedFieldKit
                    )


                if advancedKit then

                    local optionName =
                        "Analyze with Advanced Field Assay Kit"


                    if assayRank == 1 then

                        optionName =
                            "Re-analyze with Advanced Field Assay Kit"
                    end


                    context:addOption(
                        optionName,
                        player,
                        analyzeSample,
                        item,
                        advancedKit
                    )
                end
            end


            return
        end
    end
end


------------------------------------------------
-- EVENTS
------------------------------------------------

Events.OnFillWorldObjectContextMenu.Add(
    onFillWorldObjectContextMenu
)


Events.OnFillInventoryObjectContextMenu.Add(
    onFillInventoryContextMenu
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Geological sampling context menus loaded"
)