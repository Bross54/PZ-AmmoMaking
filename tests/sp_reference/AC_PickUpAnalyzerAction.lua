-- Ammo Making - Pick up a placed laboratory analyzer
-- Project Zomboid Build 42.20
--
-- Queued after walking next to a placed analyzer.
-- Follows the vanilla Build 42 pick-up actions
-- (ISRemoveTrapAction, ISAddTakeDispenserBottle): the
-- item is added first, then the world object is
-- removed with transmitRemoveItemFromSquare followed by
-- RemoveTileObject.
--
-- The analyzer has to stay idle and empty for the
-- whole action (checked read-only in isValid) and is
-- checked once more in perform() before anything
-- changes, so an assay started in the meantime blocks
-- the pickup.

require "TimedActions/ISBaseTimedAction"


AC_PickUpAnalyzerAction =
    ISBaseTimedAction:derive(
        "AC_PickUpAnalyzerAction"
    )


------------------------------------------------
-- HELPERS
------------------------------------------------

local function isStillPlaced(
    analyzer
)

    return
        analyzer ~= nil
        and analyzer:getSquare() ~= nil
        and analyzer:getObjectIndex() ~= -1
end


------------------------------------------------
-- REFUSAL TEXT
------------------------------------------------
--
-- Player-facing reason for a refused pickup; also
-- used as the tooltip of the disabled menu option.
------------------------------------------------

function AC_PickUpAnalyzerAction.getRefusalText(
    reason
)

    if reason == "processing" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_PickUpBusy",
                "Cancel the laboratory assay before moving the analyzer"
            )
    end


    if reason == "ready" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_PickUpReady",
                "Collect the laboratory sample before moving the analyzer"
            )
    end


    return
        AC_Text.get(
            "IGUI_AmmoMaking_Lab_PickUpFailed",
            "Could not pick up the laboratory analyzer"
        )
end


------------------------------------------------
-- PICK UP
------------------------------------------------
--
-- Returns the new item, or nil and a reason:
--   gone                  already removed
--   invalid_analyzer,
--   processing, ready     see canPickUp()
--   item_creation_failed  the analyzer stays placed
------------------------------------------------

function AC_PickUpAnalyzerAction.pickUp(
    character,
    analyzer
)

    if not isStillPlaced(
        analyzer
    ) then

        return nil,
            "gone"
    end


    local allowed,
          reason =
        AC_LaboratoryAnalyzer.canPickUp(
            analyzer
        )


    if not allowed then

        return nil,
            reason
    end


    local square =
        analyzer:getSquare()


    local inventory =
        character:getInventory()


    local item =
        inventory:AddItem(
            AC_LaboratoryAnalyzer.ITEMS.Analyzer
        )


    if not item then

        return nil,
            "item_creation_failed"
    end


    square:transmitRemoveItemFromSquare(
        analyzer
    )


    square:RemoveTileObject(
        analyzer
    )


    square:RecalcAllWithNeighbours(
        true
    )


    inventory:setDrawDirty(
        true
    )


    print(
        "[AmmoMaking] Laboratory Assay Analyzer picked up at "
        .. tostring(
            square:getX()
        )
        .. ", "
        .. tostring(
            square:getY()
        )
    )


    return item, nil
end


------------------------------------------------
-- VALID
------------------------------------------------

function AC_PickUpAnalyzerAction:isValid()

    return
        isStillPlaced(
            self.analyzer
        )
        and AC_LaboratoryAnalyzer.isIdleAndEmpty(
            self.analyzer
        )
end


------------------------------------------------
-- WAIT TO START
------------------------------------------------

function AC_PickUpAnalyzerAction:waitToStart()

    self.character:faceLocation(
        self.square:getX() + 0.5,
        self.square:getY() + 0.5
    )


    return
        self.character:isTurning()
        or self.character:shouldBeTurning()
end


------------------------------------------------
-- UPDATE
------------------------------------------------

function AC_PickUpAnalyzerAction:update()

    self.character:faceLocation(
        self.square:getX() + 0.5,
        self.square:getY() + 0.5
    )


    self.character:setMetabolicTarget(
        Metabolics.HeavyDomestic
    )
end


------------------------------------------------
-- START
------------------------------------------------

function AC_PickUpAnalyzerAction:start()

    ------------------------------------------------
    -- Same animation as vanilla trap pickup.
    ------------------------------------------------

    self:setActionAnim(
        "Loot"
    )


    self.character:SetVariable(
        "LootPosition",
        "Low"
    )


    self:setOverrideHandModels(
        nil,
        nil
    )
end


------------------------------------------------
-- STOP
------------------------------------------------

function AC_PickUpAnalyzerAction:stop()

    ISBaseTimedAction.stop(
        self
    )
end


------------------------------------------------
-- PERFORM
------------------------------------------------

function AC_PickUpAnalyzerAction:perform()

    local item,
          errorCode =
        AC_PickUpAnalyzerAction.pickUp(
            self.character,
            self.analyzer
        )


    if item then

        HaloTextHelper.addText(
            self.character,
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_PickedUp",
                "Laboratory Assay Analyzer picked up"
            )
        )

    else

        HaloTextHelper.addText(
            self.character,
            AC_PickUpAnalyzerAction.getRefusalText(
                errorCode
            )
        )


        print(
            "[AmmoMaking] Analyzer pickup refused: "
            .. tostring(
                errorCode
            )
        )
    end


    ISBaseTimedAction.perform(
        self
    )
end


------------------------------------------------
-- DURATION
------------------------------------------------

function AC_PickUpAnalyzerAction:getDuration()

    if self.character:isTimedActionInstant() then

        return 1
    end


    return
        AC_LaboratoryAnalyzer.CONFIG.pickUpActionTime
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_PickUpAnalyzerAction:new(
    character,
    analyzer
)

    local o =
        ISBaseTimedAction.new(
            self,
            character
        )


    o.character =
        character


    o.analyzer =
        analyzer


    o.square =
        analyzer:getSquare()


    o.stopOnWalk =
        true


    o.stopOnRun =
        true


    o.maxTime =
        o:getDuration()


    return o
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Analyzer pickup action loaded"
)
