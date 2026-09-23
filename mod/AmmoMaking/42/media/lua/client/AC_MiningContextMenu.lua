-- Ammo Making - Ore extraction context menu
-- Project Zomboid Build 42.20
--
-- Mining options only appear on natural outdoor ground
-- that is covered by an assayed geological sample the
-- player is carrying. Having a pickaxe alone is never
-- enough.

require "TimedActions/ISTimedActionQueue"
require "luautils"


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
-- DISABLED OPTION WITH TOOLTIP
------------------------------------------------

local function addUnavailableOption(
    context,
    name,
    description
)

    local option =
        context:addOption(
            name
        )


    option.notAvailable =
        true


    if description
        and ISWorldObjectContextMenu
        and ISWorldObjectContextMenu.addToolTip
    then

        local tooltip =
            ISWorldObjectContextMenu.addToolTip()


        tooltip.description =
            description


        option.toolTip =
            tooltip
    end


    return option
end


------------------------------------------------
-- MINE ORE
------------------------------------------------

local function mineOre(
    player,
    square,
    metal,
    pickaxe
)

    if not player
        or not square
        or not metal
    then

        return
    end


    if not AC_Mining.isUsablePickaxe(
        pickaxe
    ) then

        HaloTextHelper.addText(
            player,
            "Equip a usable pickaxe first"
        )


        return
    end


    if not luautils.walkAdj(
        player,
        square
    ) then

        HaloTextHelper.addText(
            player,
            "Cannot reach mining location"
        )


        return
    end


    ISTimedActionQueue.add(
        AC_MineOreAction:new(
            player,
            square,
            metal,
            pickaxe
        )
    )
end


------------------------------------------------
-- ADD OPTION FOR ONE METAL
------------------------------------------------

local function addMetalOption(
    player,
    context,
    square,
    metal,
    pickaxe
)

    local sample,
          reportedGrade =
        AC_Mining.findProspect(
            player,
            square,
            metal
        )


    ------------------------------------------------
    -- No assay knowledge for this metal here:
    -- the player does not know about a deposit.
    ------------------------------------------------

    if not sample then
        return
    end


    local metalName =
        AC_Deposits.getMetalName(
            metal
        )


    local optionName =
        "Mine "
        .. metalName
        .. " Ore (Assay: "
        .. tostring(reportedGrade)
        .. ")"


    ------------------------------------------------
    -- Exhaustion is only shown after the tile was
    -- worked, so the menu never leaks true geology.
    ------------------------------------------------

    if AC_Deposits.isKnownExhausted(
        square:getX(),
        square:getY(),
        metal
    ) then

        addUnavailableOption(
            context,
            "Mine "
            .. metalName
            .. " Ore (Exhausted)",
            "No workable "
            .. string.lower(metalName)
            .. " ore is left on this spot."
        )


        return
    end


    if not pickaxe then

        addUnavailableOption(
            context,
            optionName,
            "Requires an equipped pickaxe."
        )


        return
    end


    if not AC_Mining.isUsablePickaxe(
        pickaxe
    ) then

        addUnavailableOption(
            context,
            optionName,
            "Your pickaxe is broken."
        )


        return
    end


    context:addOption(
        optionName,
        player,
        mineOre,
        square,
        metal,
        pickaxe
    )
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


    local square =
        getClickedSquare(
            worldObjects
        )


    if not AC_Mining.isMineableSquare(
        square
    ) then

        return
    end


    ------------------------------------------------
    -- Multiplayer clients get a clear message instead
    -- of a client-side extraction that would neither
    -- persist nor be shared with other players.
    ------------------------------------------------

    if not AC_Mining.isAvailable() then

        addUnavailableOption(
            context,
            "Mine Ore",
            "Ore extraction is not available in multiplayer yet."
        )


        return
    end


    local pickaxe =
        AC_Mining.getEquippedPickaxe(
            player
        )


    for _,
        metal
    in ipairs(
        AC_Deposits.METALS
    )
    do

        addMetalOption(
            player,
            context,
            square,
            metal,
            pickaxe
        )
    end
end


------------------------------------------------
-- EVENTS
------------------------------------------------

Events.OnFillWorldObjectContextMenu.Add(
    onFillWorldObjectContextMenu
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Mining context menu loaded"
)
