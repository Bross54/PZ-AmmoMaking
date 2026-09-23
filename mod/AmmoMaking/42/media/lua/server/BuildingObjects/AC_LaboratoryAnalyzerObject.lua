-- Ammo Making - Placeable Laboratory Assay Analyzer
-- Project Zomboid Build 42.20
--
-- Placement cursor that turns the Laboratory Assay
-- Analyzer item into a world object. It follows the
-- vanilla Build 42 pattern for an inventory item that
-- becomes an IsoThumpable (TrapBO, ISSimpleFurniture):
--
--   getCell():setDrag(AC_LaboratoryAnalyzerObject:new(...))
--   -> ISBuildingObject:tryBuild() walks to the square
--      and queues an ISBuildAction
--   -> ISBuildAction:perform() calls create() when the
--      action completes (single-player / split-screen)
--
-- In multiplayer Build 42 runs create() on the server.
-- That path is not supported yet, so the menu never
-- starts placement on a multiplayer client
-- (AC_LaboratoryAnalyzer.isPlacementAvailable).
--
-- Every rule about the analyzer's state lives in
-- AC_LaboratoryAnalyzer; this file only creates the
-- object.

require "BuildingObjects/ISBuildingObject"


AC_LaboratoryAnalyzerObject =
    ISBuildingObject:derive(
        "AC_LaboratoryAnalyzerObject"
    )


------------------------------------------------
-- SOURCE ITEM
------------------------------------------------
--
-- The analyzer item has to stay in the placing
-- character's main inventory, both while the cursor
-- is shown and when the build action completes.
------------------------------------------------

function AC_LaboratoryAnalyzerObject:hasSourceItem()

    if not self.sourceItem
        or not self.character
    then

        return false
    end


    if not AC_LaboratoryAnalyzer.isAnalyzerItem(
        self.sourceItem
    ) then

        return false
    end


    return
        self.character:getInventory():contains(
            self.sourceItem
        )
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


    if not self:hasSourceItem() then
        return false
    end


    ------------------------------------------------
    -- Vanilla checks: vehicles, safehouses, blocking
    -- objects and, with ignoreNorth, at most one
    -- thumpable (so one analyzer) per tile.
    ------------------------------------------------

    return
        ISBuildingObject.isValid(
            self,
            square
        )
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

    ------------------------------------------------
    -- The item may have been dropped or moved while
    -- the build action ran: never create an analyzer
    -- without consuming one.
    ------------------------------------------------

    if not self:hasSourceItem() then

        print(
            "[AmmoMaking] Analyzer placement aborted: analyzer item no longer in the inventory"
        )


        return
    end


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


    analyzer:setName(
        AC_LaboratoryAnalyzer.OBJECT_NAME
    )


    analyzer:setCanBarricade(
        false
    )


    ------------------------------------------------
    -- Zombies cannot thump it down, so a stored
    -- sample is not lost to an attack.
    ------------------------------------------------

    analyzer:setIsThumpable(
        false
    )


    ------------------------------------------------
    -- Fresh state, or the state of an item that still
    -- holds a sample (see initializePlacedData).
    ------------------------------------------------

    AC_LaboratoryAnalyzer.initializePlacedData(
        analyzer:getModData(),
        self.sourceItem:getModData()
    )


    square:AddSpecialObject(
        analyzer
    )


    square:RecalcAllWithNeighbours(
        true
    )


    analyzer:transmitCompleteItemToClients()


    ------------------------------------------------
    -- Consume the item only after the object exists.
    ------------------------------------------------

    local character =
        self.character


    if self.sourceItem
        == character:getPrimaryHandItem()
    then

        character:setPrimaryHandItem(
            nil
        )
    end


    if self.sourceItem
        == character:getSecondaryHandItem()
    then

        character:setSecondaryHandItem(
            nil
        )
    end


    local inventory =
        character:getInventory()


    inventory:Remove(
        self.sourceItem
    )


    ------------------------------------------------
    -- Same as vanilla TrapBO; only reached if the
    -- multiplayer path is enabled one day.
    ------------------------------------------------

    if isServer() then

        sendRemoveItemFromContainer(
            inventory,
            self.sourceItem
        )
    end


    inventory:setDrawDirty(
        true
    )


    self.javaObject =
        analyzer


    print(
        "[AmmoMaking] Laboratory Assay Analyzer placed at "
        .. tostring(x)
        .. ", "
        .. tostring(y)
        .. ", "
        .. tostring(z)
    )
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_LaboratoryAnalyzerObject:new(
    player,
    sourceItem
)

    local o = {}

    setmetatable(
        o,
        self
    )

    self.__index =
        self


    o:init()


    ------------------------------------------------
    -- One sprite for every direction for now.
    ------------------------------------------------

    local sprite =
        AC_LaboratoryAnalyzer.CONFIG.worldSprite


    o:setSprite(
        sprite
    )

    o:setNorthSprite(
        sprite
    )

    o:setEastSprite(
        sprite
    )

    o:setSouthSprite(
        sprite
    )


    o.character =
        player


    o.player =
        player:getPlayerNum()


    o.sourceItem =
        sourceItem


    o.noNeedHammer =
        true


    o.dragNilAfterPlace =
        true


    o.ignoreNorth =
        true


    o.maxTime =
        AC_LaboratoryAnalyzer.CONFIG.placeActionTime


    return o
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Laboratory analyzer building object loaded"
)
