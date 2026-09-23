-- Ammo Making - Geology debug tools
-- Project Zomboid Build 42.20

AC_GeologyDebug =
    AC_GeologyDebug or {}


------------------------------------------------
-- ROUND
------------------------------------------------

local function round(value)

    return
        math.floor(
            value + 0.5
        )
end


------------------------------------------------
-- CHECK SURVEY SURFACE
------------------------------------------------

local function checkSurveySurface(
    player,
    actionName
)

    if not player then
        return nil
    end


    local square =
        player:getSquare()


    if not square then

        print(
            "[AmmoMaking] "
            .. tostring(actionName)
            .. " failed: player square not found"
        )

        return nil
    end


    local spriteName =
        AC_Geology.getFloorSpriteName(
            square
        )


    print(
        "[AmmoMaking] "
        .. tostring(actionName)
        .. " floor sprite: "
        .. tostring(spriteName)
    )


    if not AC_Geology.isSurveyableSquare(
        square
    ) then

        print(
            "[AmmoMaking] "
            .. tostring(actionName)
            .. " rejected: invalid ground surface"
        )


        HaloTextHelper.addText(
            player,
            "Requires natural ground"
        )


        return nil
    end


    return square
end


------------------------------------------------
-- PRINT GEOLOGY SEED
------------------------------------------------

local function printGeologySeed(
    player
)

    if not player then
        return
    end


    local seeds =
        AC_Geology.getSeedInfo()


    print(
        "[AmmoMaking] GEOLOGY SEEDS"
    )


    print(
        "[AmmoMaking] World Geology Seed: "
        .. tostring(
            seeds.geology
        )
    )


    print(
        "[AmmoMaking] Copper Seed: "
        .. tostring(
            seeds.copper
        )
    )


    print(
        "[AmmoMaking] Zinc Seed: "
        .. tostring(
            seeds.zinc
        )
    )


    HaloTextHelper.addText(
        player,
        "Geology Seed: "
        .. tostring(
            seeds.geology
        )
    )
end


------------------------------------------------
-- INSPECT CURRENT TILE
------------------------------------------------

local function printTileGeology(
    player
)

    if not player then
        return
    end


    local square =
        checkSurveySurface(
            player,
            "Tile inspection"
        )


    if not square then
        return
    end


    local x =
        math.floor(
            player:getX()
        )

    local y =
        math.floor(
            player:getY()
        )


    local geology =
        AC_Geology.getTileGeology(
            x,
            y
        )


    local copper =
        round(
            geology.copper
        )


    local zinc =
        round(
            geology.zinc
        )


    local copperGrade =
        AC_Geology.getGrade(
            geology.copper
        )


    local zincGrade =
        AC_Geology.getGrade(
            geology.zinc
        )


    print(
        "[AmmoMaking] GEOLOGY TILE"
    )


    print(
        "[AmmoMaking] Position: "
        .. tostring(x)
        .. ", "
        .. tostring(y)
    )


    print(
        "[AmmoMaking] Copper: "
        .. tostring(copper)
        .. "% ("
        .. tostring(copperGrade)
        .. ")"
    )


    print(
        "[AmmoMaking] Zinc: "
        .. tostring(zinc)
        .. "% ("
        .. tostring(zincGrade)
        .. ")"
    )


    ------------------------------------------------
    -- Mining reserves
    ------------------------------------------------

    local reserves =
        AC_Deposits.getTileInfo(
            x,
            y
        )


    for _,
        metal
    in ipairs(
        AC_Deposits.METALS
    )
    do

        local info =
            reserves[metal]


        print(
            "[AmmoMaking] "
            .. AC_Deposits.getMetalName(metal)
            .. " reserve: "
            .. tostring(info.remaining)
            .. "/"
            .. tostring(info.initial)
            .. " (extracted "
            .. tostring(info.extracted)
            .. ", worked "
            .. tostring(info.worked)
            .. ")"
        )
    end


    HaloTextHelper.addText(
        player,
        "Tile: Cu "
        .. tostring(copper)
        .. "% ("
        .. tostring(reserves.copper.remaining)
        .. "/"
        .. tostring(reserves.copper.initial)
        .. ") | Zn "
        .. tostring(zinc)
        .. "% ("
        .. tostring(reserves.zinc.remaining)
        .. "/"
        .. tostring(reserves.zinc.initial)
        .. ")"
    )
end


------------------------------------------------
-- RESET MINING DEPLETION (3x3)
------------------------------------------------

local function resetAreaDepletion(
    player
)

    if not player then
        return
    end


    local x =
        math.floor(
            player:getX()
        )

    local y =
        math.floor(
            player:getY()
        )


    for offsetX = -1, 1 do

        for offsetY = -1, 1 do

            AC_Deposits.resetTile(
                x + offsetX,
                y + offsetY
            )
        end
    end


    print(
        "[AmmoMaking] Mining depletion reset around "
        .. tostring(x)
        .. ", "
        .. tostring(y)
        .. "; worked tiles in save: "
        .. tostring(
            AC_Deposits.getWorkedTileCount()
        )
    )


    HaloTextHelper.addText(
        player,
        "Mining depletion reset (3x3)"
    )
end


------------------------------------------------
-- SPAWN MINING TEST ITEMS
------------------------------------------------

local function spawnMiningTestItems(
    player
)

    if not player then
        return
    end


    local itemTypes = {
        "Base.Shovel",
        "Base.PickAxe",
        AC_GeologySampling.ITEMS.FieldKit,
        AC_GeologySampling.ITEMS.AdvancedFieldKit,
    }


    for _,
        itemType
    in ipairs(
        itemTypes
    )
    do

        local item =
            player:getInventory():AddItem(
                itemType
            )


        print(
            "[AmmoMaking] Debug spawn "
            .. tostring(itemType)
            .. ": "
            .. (item and "OK" or "FAILED")
        )
    end


    HaloTextHelper.addText(
        player,
        "Mining test items added"
    )
end


------------------------------------------------
-- SURVEY 3x3 AREA
------------------------------------------------

local function surveyPlayerArea(
    player
)

    if not player then
        return
    end


    local square =
        checkSurveySurface(
            player,
            "Survey"
        )


    if not square then
        return
    end


    local x =
        math.floor(
            player:getX()
        )

    local y =
        math.floor(
            player:getY()
        )


    local survey =
        AC_Geology.surveyArea(
            x,
            y
        )


    local copper =
        round(
            survey.copperAverage
        )


    local zinc =
        round(
            survey.zincAverage
        )


    local copperPeak =
        round(
            survey.copperPeak
        )


    local zincPeak =
        round(
            survey.zincPeak
        )


    local copperGrade =
        AC_Geology.getGrade(
            survey.copperAverage
        )


    local zincGrade =
        AC_Geology.getGrade(
            survey.zincAverage
        )


    print(
        "[AmmoMaking] GEOLOGICAL SURVEY"
    )


    print(
        "[AmmoMaking] Position: "
        .. tostring(x)
        .. ", "
        .. tostring(y)
    )


    print(
        "[AmmoMaking] Copper Average: "
        .. tostring(copper)
        .. "% ("
        .. tostring(copperGrade)
        .. ")"
    )


    print(
        "[AmmoMaking] Zinc Average: "
        .. tostring(zinc)
        .. "% ("
        .. tostring(zincGrade)
        .. ")"
    )


    print(
        "[AmmoMaking] Copper Peak: "
        .. tostring(copperPeak)
        .. "%"
    )


    print(
        "[AmmoMaking] Zinc Peak: "
        .. tostring(zincPeak)
        .. "%"
    )


    HaloTextHelper.addText(
        player,
        "Survey: Cu "
        .. tostring(copper)
        .. "% | Zn "
        .. tostring(zinc)
        .. "%"
    )
end


------------------------------------------------
-- PUBLIC DEBUG FUNCTIONS
------------------------------------------------

function AC_GeologyDebug.tile(
    player
)

    printTileGeology(
        player
    )
end


function AC_GeologyDebug.survey(
    player
)

    surveyPlayerArea(
        player
    )
end


function AC_GeologyDebug.seed(
    player
)

    printGeologySeed(
        player
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


    ------------------------------------------------
    -- Debug tools reveal exact geology, so they are
    -- only available when the game runs in -debug.
    ------------------------------------------------

    if not isDebugEnabled() then
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
    -- ROOT DEBUG MENU
    ------------------------------------------------

    local geologyOption =
        context:addOption(
            "Ammo Making Debug"
        )


    local geologyMenu =
        ISContextMenu:getNew(
            context
        )


    context:addSubMenu(
        geologyOption,
        geologyMenu
    )


    ------------------------------------------------
    -- SURVEY
    ------------------------------------------------

    geologyMenu:addOption(
        "Survey Current Area",
        player,
        surveyPlayerArea
    )


    ------------------------------------------------
    -- TILE
    ------------------------------------------------

    geologyMenu:addOption(
        "Inspect Current Tile",
        player,
        printTileGeology
    )


    ------------------------------------------------
    -- SEED
    ------------------------------------------------

    geologyMenu:addOption(
        "Show Geology Seed",
        player,
        printGeologySeed
    )


    ------------------------------------------------
    -- MINING
    ------------------------------------------------

    geologyMenu:addOption(
        "Reset Mining Depletion (3x3)",
        player,
        resetAreaDepletion
    )


    geologyMenu:addOption(
        "Spawn Mining Test Items",
        player,
        spawnMiningTestItems
    )
end


------------------------------------------------
-- EVENT
------------------------------------------------

Events.OnFillWorldObjectContextMenu.Add(
    onFillWorldObjectContextMenu
)


print(
    "[AmmoMaking] Geology debug tools loaded"
)