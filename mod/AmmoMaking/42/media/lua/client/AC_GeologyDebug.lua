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


    HaloTextHelper.addText(
        player,
        "Tile: Cu "
        .. tostring(copper)
        .. "% | Zn "
        .. tostring(zinc)
        .. "%"
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