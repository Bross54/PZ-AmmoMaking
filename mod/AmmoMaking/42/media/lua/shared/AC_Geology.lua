-- Ammo Making - Geological deposit system
-- Project Zomboid Build 42.20

AC_Geology = AC_Geology or {}


------------------------------------------------
-- CONFIGURATION
------------------------------------------------

AC_Geology.CONFIG = {

    ------------------------------------------------
    -- VEIN SIZE
    ------------------------------------------------

    -- Larger value = broader geological veins.
    baseScale = 55,

    -- Medium-scale variation.
    detailScale = 18,


    ------------------------------------------------
    -- ORE RARITY
    ------------------------------------------------
    --
    -- LOWER = ore appears more frequently.
    -- HIGHER = ore appears less frequently.
    --
    -- Rough guide:
    --
    -- 0.40 = very common
    -- 0.45 = common
    -- 0.50 = moderate
    -- 0.55 = uncommon
    -- 0.60 = rare
    ------------------------------------------------

    copperThreshold = 0.50,

    zincThreshold = 0.52,


    ------------------------------------------------
    -- SURVEY AREA
    ------------------------------------------------
    --
    -- A geological sample represents the square area
    -- within this many tiles of its centre (1 = 3x3).
    -- Mining coverage and the debug 3x3 tools read
    -- the same value so they can never drift apart.
    ------------------------------------------------

    surveyRadius = 1,
}


------------------------------------------------
-- ITEM TYPES
------------------------------------------------

AC_Geology.ITEMS = {

    ------------------------------------------------
    -- VANILLA BUILD 42 COPPER
    ------------------------------------------------

    CopperOre =
        "Base.CopperOre",

    CopperIngot =
        "Base.CopperIngot",


    ------------------------------------------------
    -- AMMO MAKING ZINC
    ------------------------------------------------

    ZincOre =
        "AmmoMaking.ZincOre",

    ZincIngot =
        "AmmoMaking.ZincIngot",
}


------------------------------------------------
-- BASIC MATH HELPERS
------------------------------------------------

local function clamp(
    value,
    minValue,
    maxValue
)

    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end


local function lerp(
    a,
    b,
    t
)

    return
        a
        + ((b - a) * t)
end


local function smoothstep(t)

    return
        t
        * t
        * (3 - (2 * t))
end


------------------------------------------------
-- WORLD SEEDS
------------------------------------------------

local function getCopperSeed()

    if not AC_WorldData then

        error(
            "[AmmoMaking] AC_WorldData is not loaded"
        )
    end


    return
        AC_WorldData.getCopperSeed()
end


local function getZincSeed()

    if not AC_WorldData then

        error(
            "[AmmoMaking] AC_WorldData is not loaded"
        )
    end


    return
        AC_WorldData.getZincSeed()
end


------------------------------------------------
-- DETERMINISTIC 2D HASH
------------------------------------------------

local function hash2D(
    x,
    y,
    seed
)

    local value =
        math.sin(
            (x * 127.1)
            + (y * 311.7)
            + (seed * 74.7)
        )
        * 43758.5453123


    return
        value
        - math.floor(value)
end


------------------------------------------------
-- VALUE NOISE
------------------------------------------------

local function valueNoise(
    x,
    y,
    scale,
    seed
)

    local scaledX =
        x / scale

    local scaledY =
        y / scale


    local x0 =
        math.floor(scaledX)

    local y0 =
        math.floor(scaledY)


    local x1 =
        x0 + 1

    local y1 =
        y0 + 1


    local tx =
        scaledX - x0

    local ty =
        scaledY - y0


    tx =
        smoothstep(tx)

    ty =
        smoothstep(ty)


    local v00 =
        hash2D(
            x0,
            y0,
            seed
        )


    local v10 =
        hash2D(
            x1,
            y0,
            seed
        )


    local v01 =
        hash2D(
            x0,
            y1,
            seed
        )


    local v11 =
        hash2D(
            x1,
            y1,
            seed
        )


    local top =
        lerp(
            v00,
            v10,
            tx
        )


    local bottom =
        lerp(
            v01,
            v11,
            tx
        )


    return
        lerp(
            top,
            bottom,
            ty
        )
end


------------------------------------------------
-- MULTI-LAYER GEOLOGICAL NOISE
------------------------------------------------

local function geologicalNoise(
    x,
    y,
    seed
)

    ------------------------------------------------
    -- Broad geological formation
    ------------------------------------------------

    local broad =
        valueNoise(
            x,
            y,
            AC_Geology.CONFIG.baseScale,
            seed
        )


    ------------------------------------------------
    -- Medium variation
    ------------------------------------------------

    local detail =
        valueNoise(
            x,
            y,
            AC_Geology.CONFIG.detailScale,
            seed + 1337
        )


    ------------------------------------------------
    -- Fine local variation
    ------------------------------------------------

    local fine =
        valueNoise(
            x,
            y,
            8,
            seed + 9187
        )


    return
        (broad * 0.65)
        + (detail * 0.25)
        + (fine * 0.10)
end


------------------------------------------------
-- RAW NOISE -> ORE CONCENTRATION
------------------------------------------------

local function calculateDepositConcentration(
    rawValue,
    threshold
)

    ------------------------------------------------
    -- No deposit
    ------------------------------------------------

    if rawValue <= threshold then
        return 0
    end


    ------------------------------------------------
    -- Normalize into 0-1
    ------------------------------------------------

    local normalized =
        (rawValue - threshold)
        / (1 - threshold)


    ------------------------------------------------
    -- Richness curve
    --
    -- sqrt() gives useful deposit concentrations
    -- instead of almost everything being 1-10%.
    ------------------------------------------------

    normalized =
        math.sqrt(
            normalized
        )


    return
        clamp(
            normalized * 100,
            0,
            100
        )
end


------------------------------------------------
-- COPPER CONCENTRATION
------------------------------------------------

function AC_Geology.getCopperConcentration(
    x,
    y
)

    local raw =
        geologicalNoise(
            x,
            y,
            getCopperSeed()
        )


    return
        calculateDepositConcentration(
            raw,
            AC_Geology.CONFIG.copperThreshold
        )
end


------------------------------------------------
-- ZINC CONCENTRATION
------------------------------------------------

function AC_Geology.getZincConcentration(
    x,
    y
)

    ------------------------------------------------
    -- Coordinate offset provides additional
    -- separation between zinc and copper.
    ------------------------------------------------

    local raw =
        geologicalNoise(
            x + 840,
            y - 1260,
            getZincSeed()
        )


    return
        calculateDepositConcentration(
            raw,
            AC_Geology.CONFIG.zincThreshold
        )
end


------------------------------------------------
-- TILE GEOLOGY
------------------------------------------------

function AC_Geology.getTileGeology(
    x,
    y
)

    x =
        math.floor(x)

    y =
        math.floor(y)


    return {

        x = x,

        y = y,

        copper =
            AC_Geology.getCopperConcentration(
                x,
                y
            ),

        zinc =
            AC_Geology.getZincConcentration(
                x,
                y
            )
    }
end


------------------------------------------------
-- 3x3 AREA SURVEY
------------------------------------------------

function AC_Geology.surveyArea(
    centerX,
    centerY
)

    centerX =
        math.floor(centerX)

    centerY =
        math.floor(centerY)


    local copperTotal = 0
    local zincTotal = 0

    local copperPeak = 0
    local zincPeak = 0

    local tiles = 0


    local radius =
        AC_Geology.CONFIG.surveyRadius


    for offsetX = -radius, radius do

        for offsetY = -radius, radius do

            local geology =
                AC_Geology.getTileGeology(
                    centerX + offsetX,
                    centerY + offsetY
                )


            copperTotal =
                copperTotal
                + geology.copper


            zincTotal =
                zincTotal
                + geology.zinc


            if geology.copper
                > copperPeak
            then

                copperPeak =
                    geology.copper
            end


            if geology.zinc
                > zincPeak
            then

                zincPeak =
                    geology.zinc
            end


            tiles =
                tiles + 1
        end
    end


    return {

        x =
            centerX,

        y =
            centerY,


        copperAverage =
            copperTotal / tiles,

        zincAverage =
            zincTotal / tiles,


        copperPeak =
            copperPeak,

        zincPeak =
            zincPeak
    }
end


------------------------------------------------
-- ORE GRADE
------------------------------------------------

function AC_Geology.getGrade(
    concentration
)

    if concentration <= 0 then

        return "None"


    elseif concentration < 15 then

        return "Trace"


    elseif concentration < 30 then

        return "Poor"


    elseif concentration < 50 then

        return "Moderate"


    elseif concentration < 70 then

        return "Good"


    elseif concentration < 85 then

        return "Rich"


    else

        return "Very Rich"
    end
end


------------------------------------------------
-- GRADE DISPLAY NAME
------------------------------------------------
--
-- Grades are stored and compared as the English
-- identifiers returned by getGrade(). Only the
-- display goes through the translation system.
------------------------------------------------

AC_Geology.GRADE_KEYS = {

    ["None"] = "IGUI_AmmoMaking_Grade_None",

    ["Trace"] = "IGUI_AmmoMaking_Grade_Trace",

    ["Poor"] = "IGUI_AmmoMaking_Grade_Poor",

    ["Moderate"] = "IGUI_AmmoMaking_Grade_Moderate",

    ["Good"] = "IGUI_AmmoMaking_Grade_Good",

    ["Rich"] = "IGUI_AmmoMaking_Grade_Rich",

    ["Very Rich"] = "IGUI_AmmoMaking_Grade_VeryRich",
}


function AC_Geology.getGradeName(
    grade
)

    local key =
        AC_Geology.GRADE_KEYS[grade]


    if not key then
        return tostring(grade)
    end


    return
        AC_Text.get(
            key,
            grade
        )
end


------------------------------------------------
-- FLOOR SPRITE NAME
------------------------------------------------

function AC_Geology.getFloorSpriteName(
    square
)

    if not square then
        return nil
    end


    local floor =
        square:getFloor()


    if not floor then
        return nil
    end


    local sprite =
        floor:getSprite()


    if not sprite then
        return nil
    end


    return
        sprite:getName()
end


------------------------------------------------
-- STRING HELPER
------------------------------------------------

local function contains(
    text,
    value
)

    return
        string.find(
            text,
            value,
            1,
            true
        )
        ~= nil
end


------------------------------------------------
-- WATER
------------------------------------------------
--
-- Build 42 exposes IsoGridSquare:hasWater(); older
-- builds use the "water" flag on the square. Both
-- calls are guarded so a missing method can never
-- raise a runtime error in a context menu.
------------------------------------------------

function AC_Geology.isWaterSquare(
    square
)

    if not square then
        return false
    end


    local ok,
          result =
        pcall(
            function()

                return
                    square:hasWater()
            end
        )


    if ok
        and result == true
    then

        return true
    end


    if IsoFlagType
        and IsoFlagType.water
    then

        ok,
        result =
            pcall(
                function()

                    return
                        square:Is(
                            IsoFlagType.water
                        )
                end
            )


        if ok
            and result == true
        then

            return true
        end
    end


    return false
end


------------------------------------------------
-- SURVEYABLE SURFACE
------------------------------------------------

function AC_Geology.isSurveyableSquare(
    square
)

    if not square then
        return false
    end


    ------------------------------------------------
    -- Ground level only
    ------------------------------------------------

    if square:getZ() ~= 0 then
        return false
    end


    ------------------------------------------------
    -- Never inside a mapped room/building,
    -- regardless of the underlying floor sprite.
    --
    -- Sampling, extraction and debug tools all rely
    -- on this function, so the rule lives here.
    ------------------------------------------------

    if square:getRoom() ~= nil then
        return false
    end


    ------------------------------------------------
    -- Never on water. Vanilla water tiles live on
    -- natural blend sheets, so the sprite-name rules
    -- below would otherwise accept a lake or river.
    ------------------------------------------------

    if AC_Geology.isWaterSquare(
        square
    ) then

        return false
    end


    ------------------------------------------------
    -- Floor sprite
    ------------------------------------------------

    local spriteName =
        AC_Geology.getFloorSpriteName(
            square
        )


    if not spriteName then
        return false
    end


    local name =
        string.lower(
            spriteName
        )


    ------------------------------------------------
    -- NATURAL TERRAIN
    ------------------------------------------------

    if contains(
        name,
        "blends_natural_"
    ) then

        return true
    end


    ------------------------------------------------
    -- PLOWED / FARM LAND
    ------------------------------------------------

    if contains(
        name,
        "plowed"
    ) then

        return true
    end


    if contains(
        name,
        "farm"
    ) then

        return true
    end


    ------------------------------------------------
    -- SAND
    ------------------------------------------------

    if contains(
        name,
        "sand"
    ) then

        return true
    end


    ------------------------------------------------
    -- GRAVEL
    ------------------------------------------------

    if contains(
        name,
        "gravel"
    ) then

        return true
    end


    ------------------------------------------------
    -- STREET / ASPHALT
    ------------------------------------------------

    if contains(
        name,
        "blends_street_"
    ) then

        return false
    end


    ------------------------------------------------
    -- Everything else blocked
    ------------------------------------------------

    return false
end


------------------------------------------------
-- SEED INFORMATION
------------------------------------------------

function AC_Geology.getSeedInfo()

    return
        AC_WorldData.getSeedInfo()
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Geology system loaded"
)