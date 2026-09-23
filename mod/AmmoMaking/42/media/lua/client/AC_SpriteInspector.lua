-- Ammo Making - Temporary Sprite Inspector
-- Project Zomboid Build 42.20
--
-- Temporary development helper.
-- Right click any world tile and choose:
--
-- AmmoMaking Debug: Inspect Tile Sprites
--
-- Object information will be printed to console.txt.

local function safeCall(
    object,
    methodName
)

    if not object then
        return nil
    end

    local method =
        object[methodName]

    if not method then
        return nil
    end

    local success,
          result =
        pcall(
            method,
            object
        )

    if success then
        return result
    end

    return nil
end


local function getSpriteName(
    object
)

    if not object then
        return nil
    end

    ------------------------------------------------
    -- Try direct texture name first.
    ------------------------------------------------

    local textureName =
        safeCall(
            object,
            "getTextureName"
        )

    if textureName
        and textureName ~= ""
    then

        return textureName
    end


    ------------------------------------------------
    -- Then inspect object's sprite.
    ------------------------------------------------

    local sprite =
        safeCall(
            object,
            "getSprite"
        )

    if sprite then

        local spriteName =
            safeCall(
                sprite,
                "getName"
            )

        if spriteName
            and spriteName ~= ""
        then

            return spriteName
        end
    end


    return nil
end


local function printObject(
    label,
    object,
    index
)

    if not object then
        return
    end


    local objectName =
        safeCall(
            object,
            "getObjectName"
        )


    local customName =
        safeCall(
            object,
            "getName"
        )


    local spriteName =
        getSpriteName(
            object
        )


    print(
        "[AmmoMaking][SpriteInspector] "
        .. tostring(label)
        .. " #"
        .. tostring(index)
        .. " | object="
        .. tostring(object)
        .. " | objectName="
        .. tostring(objectName)
        .. " | name="
        .. tostring(customName)
        .. " | sprite="
        .. tostring(spriteName)
    )
end


local function inspectSquare(
    square
)

    if not square then

        print(
            "[AmmoMaking][SpriteInspector] No square"
        )

        return
    end


    print(
        "============================================================"
    )


    print(
        "[AmmoMaking][SpriteInspector] Inspecting square "
        .. tostring(square:getX())
        .. ", "
        .. tostring(square:getY())
        .. ", "
        .. tostring(square:getZ())
    )


    ------------------------------------------------
    -- NORMAL OBJECTS
    ------------------------------------------------

    local objects =
        square:getObjects()


    if objects then

        print(
            "[AmmoMaking][SpriteInspector] Objects: "
            .. tostring(
                objects:size()
            )
        )


        for index = 0,
            objects:size() - 1
        do

            printObject(
                "Object",
                objects:get(index),
                index
            )
        end
    end


    ------------------------------------------------
    -- SPECIAL OBJECTS
    ------------------------------------------------

    local specialObjects =
        square:getSpecialObjects()


    if specialObjects then

        print(
            "[AmmoMaking][SpriteInspector] SpecialObjects: "
            .. tostring(
                specialObjects:size()
            )
        )


        for index = 0,
            specialObjects:size() - 1
        do

            printObject(
                "SpecialObject",
                specialObjects:get(index),
                index
            )
        end
    end


    ------------------------------------------------
    -- WORLD INVENTORY OBJECTS
    ------------------------------------------------

    local worldObjects =
        square:getWorldObjects()


    if worldObjects then

        print(
            "[AmmoMaking][SpriteInspector] WorldObjects: "
            .. tostring(
                worldObjects:size()
            )
        )


        for index = 0,
            worldObjects:size() - 1
        do

            printObject(
                "WorldObject",
                worldObjects:get(index),
                index
            )
        end
    end


    print(
        "============================================================"
    )
end


local function inspectClickedTile(
    player,
    square
)

    inspectSquare(
        square
    )


    if player then

        HaloTextHelper.addText(
            player,
            "Tile sprites written to console"
        )
    end
end


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


    if not square then
        return
    end


    context:addOption(
        "AmmoMaking Debug: Inspect Tile Sprites",
        player,
        inspectClickedTile,
        square
    )
end


Events.OnFillWorldObjectContextMenu.Add(
    onFillWorldObjectContextMenu
)


print(
    "[AmmoMaking] Sprite inspector loaded"
)