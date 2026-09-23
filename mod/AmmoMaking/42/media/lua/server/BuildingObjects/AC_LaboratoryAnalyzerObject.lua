-- Ammo Making - Placeable Laboratory Assay Analyzer
-- Project Zomboid Build 42.20

require "BuildingObjects/ISBuildingObject"


AC_LaboratoryAnalyzerObject =
    ISBuildingObject:derive(
        "AC_LaboratoryAnalyzerObject"
    )


------------------------------------------------
-- CONSTANTS
------------------------------------------------

AC_LaboratoryAnalyzerObject.ITEM_TYPE =
    "AmmoMaking.LaboratoryAssayAnalyzer"


AC_LaboratoryAnalyzerObject.OBJECT_NAME =
    "AmmoMakingLaboratoryAnalyzer"


------------------------------------------------
-- TEMPORARY VANILLA WORLD SPRITE
------------------------------------------------
--
-- Coffee machine found in B42.20 using
-- AC_SpriteInspector.
--
-- This can later be replaced by a custom
-- Ammo Making sprite without touching the
-- analyzer backend.
------------------------------------------------

AC_LaboratoryAnalyzerObject.SPRITE =
    "industry_03_61"


------------------------------------------------
-- VALIDATE SOURCE ITEM
------------------------------------------------

function AC_LaboratoryAnalyzerObject:hasSourceItem()

    if not self.sourceItem then
        return false
    end


    if self.sourceItem:getFullType()
        ~= AC_LaboratoryAnalyzerObject.ITEM_TYPE
    then

        return false
    end


    local container =
        self.sourceItem:getContainer()


    if not container then
        return false
    end


    return true
end


------------------------------------------------
-- VALID PLACEMENT
------------------------------------------------

function AC_LaboratoryAnalyzerObject:isValid(
    square
)

    if not square then
        return false
    end


    ------------------------------------------------
    -- Source analyzer must still exist while the
    -- placement cursor is active.
    ------------------------------------------------

    if not self:hasSourceItem() then
        return false
    end


    ------------------------------------------------
    -- Vanilla B42 placement validation.
    ------------------------------------------------

    if not ISBuildingObject.isValid(
        self,
        square
    ) then

        return false
    end


    return true
end


------------------------------------------------
-- CREATE WORLD OBJECT
------------------------------------------------

function AC_LaboratoryAnalyzerObject:create(
    x,
    y,
    z,
    north,
    sprite
)

    print(
        "[AmmoMaking] Creating Laboratory Assay Analyzer at "
        .. tostring(x)
        .. ", "
        .. tostring(y)
        .. ", "
        .. tostring(z)
    )


    ------------------------------------------------
    -- Make sure the inventory item still exists.
    ------------------------------------------------

    if not self:hasSourceItem() then

        print(
            "[AmmoMaking] Analyzer placement aborted: source item missing"
        )


        return
    end


    local container =
        self.sourceItem:getContainer()


    ------------------------------------------------
    -- Target square.
    ------------------------------------------------

    local cell =
        getWorld():getCell()


    local square =
        cell:getGridSquare(
            x,
            y,
            z
        )


    if not square then

        print(
            "[AmmoMaking] Analyzer placement aborted: target square missing"
        )


        return
    end


    ------------------------------------------------
    -- Create persistent world object.
    ------------------------------------------------

    local analyzer =
        IsoThumpable.new(
            cell,
            square,
            sprite,
            north,
            self
        )


    if not analyzer then

        print(
            "[AmmoMaking] Analyzer placement aborted: IsoThumpable creation failed"
        )


        return
    end


    ------------------------------------------------
    -- Configure world object.
    ------------------------------------------------

    analyzer:setName(
        AC_LaboratoryAnalyzerObject.OBJECT_NAME
    )


    analyzer:setCanBarricade(
        false
    )


    analyzer:setIsThumpable(
        false
    )


    ------------------------------------------------
    -- Persistent analyzer data.
    ------------------------------------------------

    local data =
        analyzer:getModData()


    data.AmmoMakingLaboratoryAnalyzer =
        true


    data.AmmoMakingLaboratoryAnalyzerWorldObject =
        true


    data.labAnalyzerState =
        "idle"


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


    ------------------------------------------------
    -- Add object to world.
    ------------------------------------------------

    square:AddSpecialObject(
        analyzer
    )


    square:RecalcAllWithNeighbours(
        true
    )


    analyzer:transmitCompleteItemToClients()


    ------------------------------------------------
    -- Consume inventory analyzer only after the
    -- world object was successfully created.
    ------------------------------------------------

    container:Remove(
        self.sourceItem
    )


    container:setDrawDirty(
        true
    )


    self.javaObject =
        analyzer


    print(
        "[AmmoMaking] Laboratory Assay Analyzer placed successfully"
    )
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_LaboratoryAnalyzerObject:new(
    sourceItem
)

    local o =
        ISBuildingObject.new(
            self
        )


    o:init()


    ------------------------------------------------
    -- Same sprite for every direction for now.
    ------------------------------------------------

    o:setSprite(
        AC_LaboratoryAnalyzerObject.SPRITE
    )


    o:setNorthSprite(
        AC_LaboratoryAnalyzerObject.SPRITE
    )


    o:setEastSprite(
        AC_LaboratoryAnalyzerObject.SPRITE
    )


    o:setSouthSprite(
        AC_LaboratoryAnalyzerObject.SPRITE
    )


    ------------------------------------------------
    -- Placement settings.
    ------------------------------------------------

    o.sourceItem =
        sourceItem


    o.noNeedHammer =
        true


    o.dragNilAfterPlace =
        true


    o.maxTime =
        50


    o.ignoreNorth =
        true


    o.canBeAlwaysPlaced =
        false


    return o
end


------------------------------------------------
-- LOAD
------------------------------------------------

print(
    "[AmmoMaking] Laboratory analyzer building object loaded"
)