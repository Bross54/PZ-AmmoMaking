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
-- In multiplayer Build 42 runs create() on the server:
-- ISBuildAction:start() sends the building object
-- (createBuildAction), the server rebuilds it with
-- AC_LaboratoryAnalyzerObject.new(...) from its fields
-- named like new()'s parameters (JAR BuildAction.write
-- / parse) and calls create() (FILE
-- shared/ActionManager.lua, Actions.build). That is why
-- new()'s first parameter is called character: the
-- field of that name holds the IsoPlayer, while the
-- field "player" holds the player NUMBER the cursor
-- needs, which the server could not call a method on.
-- The menu offers placement on a multiplayer client only
-- with server authority on (AC_Authority), and create()
-- on a server checks it again (AC_Authority.mayPlace).
-- REQUIRES FUTURE IN-GAME VERIFICATION (dedicated
-- server).
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


    ------------------------------------------------
    -- Multiplayer server: only with server authority
    -- on, and only next to the player. Never reached
    -- in single player (isServer() is false there).
    ------------------------------------------------

    if isServer() then

        local allowed,
              refusal =
            AC_Authority.mayPlace(
                self.character,
                square
            )


        if not allowed then

            print(
                "[AmmoMaking] Analyzer placement refused by the server: "
                .. tostring(refusal)
            )


            return
        end
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
    -- Vanilla hands dismantable thumpables to its own
    -- dismantle / move handling (ISMoveableSpriteProps,
    -- ISDestroyCursor), which would bypass the pick-up
    -- rule. Vanilla traps set this explicitly too.
    ------------------------------------------------

    analyzer:setIsDismantable(
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
    -- Same as vanilla TrapBO; reached on a
    -- multiplayer server.
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
    character,
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
    -- One face per direction. ISBuildingObject's
    -- plain sprite is its west face (getSprite(),
    -- nSprite 1); with a single sprite for all four
    -- the cursor rotated but always looked the same.
    ------------------------------------------------

    local faces =
        AC_LaboratoryAnalyzer.CONFIG.facingSprites


    o:setSprite(
        faces.west
    )

    o:setNorthSprite(
        faces.north
    )

    o:setEastSprite(
        faces.east
    )

    o:setSouthSprite(
        faces.south
    )


    o.character =
        character


    o.player =
        character:getPlayerNum()


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
