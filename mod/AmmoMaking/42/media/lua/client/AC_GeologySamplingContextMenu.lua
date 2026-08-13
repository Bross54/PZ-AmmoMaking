-- Ammo Making - Geological sampling context menus
-- Project Zomboid Build 42.20

require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTimedActionQueue"
require "luautils"


------------------------------------------------
-- GET INVENTORY ITEM
------------------------------------------------

local function getActualItem(entry)

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

    if not AC_Geology.isSurveyableSquare(
        square
    ) then

        HaloTextHelper.addText(
            player,
            "Requires natural ground"
        )

        return
    end


    ------------------------------------------------
    -- Walk to a square adjacent to the clicked
    -- sampling tile before starting the action.
    ------------------------------------------------

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
-- VIEW RESULT
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

        elseif errorCode == "already_analyzed" then

            HaloTextHelper.addText(
                player,
                "Sample already has an equal or better assay"
            )

        elseif errorCode == "lab_processing" then

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
-- START LAB ASSAY
------------------------------------------------

local function startLaboratoryAssay(
    player,
    sample,
    analyzer
)

    if not player
        or not sample
        or not analyzer
    then
        return
    end

    local success,
          errorCode =
        AC_GeologySampling.startLaboratoryAssay(
            sample,
            analyzer
        )

    if not success then

        if errorCode == "lab_processing" then

            HaloTextHelper.addText(
                player,
                "Laboratory analysis already in progress"
            )

        elseif errorCode == "already_analyzed" then

            HaloTextHelper.addText(
                player,
                "Sample already has a laboratory assay"
            )

        else

            HaloTextHelper.addText(
                player,
                "Could not start laboratory analysis"
            )
        end

        return
    end

    HaloTextHelper.addText(
        player,
        "Laboratory analysis started - 24 hours"
    )

    AC_GeologyAssayUI.open(
        player,
        sample
    )
end


------------------------------------------------
-- WORLD MENU
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

    local shovel =
        AC_GeologySampling.getEquippedShovel(
            player
        )

    if not shovel then
        return
    end

    ------------------------------------------------
    -- IMPORTANT:
    --
    -- We use the clicked tile, not the tile the
    -- player is currently standing on.
    ------------------------------------------------

    local square =
        getClickedSquare(
            worldObjects
        )

    if not square then
        return
    end

    if not AC_Geology.isSurveyableSquare(
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
-- INVENTORY MENU
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

            local labProcessing =
                data.labProcessing
                == true


            ------------------------------------------------
            -- VIEW CURRENT RESULT / PROGRESS
            ------------------------------------------------

            if assayRank > 0
                or labProcessing
            then

                local optionName =
                    "View Assay Result"

                if labProcessing then

                    optionName =
                        "View Laboratory Progress"
                end

                context:addOption(
                    optionName,
                    player,
                    viewAssay,
                    item
                )
            end


            ------------------------------------------------
            -- No portable testing while sample is
            -- physically being processed.
            ------------------------------------------------

            if not labProcessing then

                ------------------------------------------------
                -- FIELD KIT
                ------------------------------------------------

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


                ------------------------------------------------
                -- ADVANCED FIELD KIT
                ------------------------------------------------

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


                ------------------------------------------------
                -- LABORATORY ANALYZER
                ------------------------------------------------

                if assayRank < 3 then

                    local analyzer =
                        AC_GeologySampling.findLaboratoryAnalyzer(
                            player
                        )

                    if analyzer then

                        context:addOption(
                            "Start Laboratory Assay (24h)",
                            player,
                            startLaboratoryAssay,
                            item,
                            analyzer
                        )
                    end
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


print(
    "[AmmoMaking] Geological sampling context menus loaded"
)