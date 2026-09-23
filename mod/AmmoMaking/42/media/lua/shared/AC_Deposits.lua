-- Ammo Making - Ore deposit reserves and depletion
-- Project Zomboid Build 42.20
--
-- Initial reserves are derived deterministically from
-- AC_Geology, so nothing is stored for untouched ground.
--
-- Only tiles that have actually been worked are stored,
-- as an extracted count per metal, in global ModData:
--
--     remaining = initial reserve (from geology)
--               - extracted       (from save data)
--
-- Storing the extracted count instead of the remaining
-- count keeps old saves valid if reserve balancing
-- changes later.

AC_Deposits = AC_Deposits or {}


------------------------------------------------
-- CONFIGURATION
------------------------------------------------

AC_Deposits.CONFIG = {

    ------------------------------------------------
    -- Global ModData key for depletion records.
    ------------------------------------------------

    modDataKey = "AmmoMakingDeposits",


    ------------------------------------------------
    -- ORE UNITS PER TILE BY GEOLOGICAL GRADE
    ------------------------------------------------
    --
    -- One unit = one ore item.
    --
    -- Vanilla Base.CopperOre is a heavy 40-weight
    -- chunk, so reserves are intentionally small.
    -- Trace concentrations are not workable.
    ------------------------------------------------

    reserveByGrade = {

        ["None"] = 0,

        ["Trace"] = 0,

        ["Poor"] = 1,

        ["Moderate"] = 1,

        ["Good"] = 2,

        ["Rich"] = 3,

        ["Very Rich"] = 4,
    },
}


------------------------------------------------
-- METALS
------------------------------------------------

AC_Deposits.METALS = {
    "copper",
    "zinc",
}


AC_Deposits.METAL_NAMES = {

    copper = "Copper",

    zinc = "Zinc",
}


function AC_Deposits.isMetal(
    metal
)

    return
        AC_Deposits.METAL_NAMES[metal]
        ~= nil
end


function AC_Deposits.getMetalName(
    metal
)

    return
        AC_Deposits.METAL_NAMES[metal]
        or tostring(metal)
end


------------------------------------------------
-- TILE KEY
------------------------------------------------

local function tileKey(
    x,
    y
)

    return
        tostring(math.floor(x))
        .. ","
        .. tostring(math.floor(y))
end


------------------------------------------------
-- SAVE DATA
------------------------------------------------
--
-- Global ModData is saved with the world.
--
-- Structure:
--
-- {
--     version = 1,
--     tiles = {
--         ["x,y"] = { copper = extracted, zinc = extracted },
--     },
-- }
--
-- A metal entry that exists with value 0 means the
-- tile was worked but held no workable ore.
------------------------------------------------

local function getStore()

    local store =
        ModData.getOrCreate(
            AC_Deposits.CONFIG.modDataKey
        )


    if not store.version then
        store.version = 1
    end


    if not store.tiles then
        store.tiles = {}
    end


    return store
end


local function getRecord(
    x,
    y,
    create
)

    local store =
        getStore()


    local key =
        tileKey(
            x,
            y
        )


    local record =
        store.tiles[key]


    if not record
        and create
    then

        record = {}

        store.tiles[key] =
            record
    end


    return record
end


------------------------------------------------
-- GEOLOGY
------------------------------------------------

function AC_Deposits.getConcentration(
    x,
    y,
    metal
)

    x =
        math.floor(x)

    y =
        math.floor(y)


    if metal == "copper" then

        return
            AC_Geology.getCopperConcentration(
                x,
                y
            )
    end


    if metal == "zinc" then

        return
            AC_Geology.getZincConcentration(
                x,
                y
            )
    end


    return 0
end


------------------------------------------------
-- INITIAL RESERVE
------------------------------------------------

function AC_Deposits.getReserveForConcentration(
    concentration
)

    local grade =
        AC_Geology.getGrade(
            tonumber(concentration)
            or 0
        )


    return
        AC_Deposits.CONFIG.reserveByGrade[grade]
        or 0
end


function AC_Deposits.getInitialReserve(
    x,
    y,
    metal
)

    if not AC_Deposits.isMetal(
        metal
    ) then

        return 0
    end


    return
        AC_Deposits.getReserveForConcentration(
            AC_Deposits.getConcentration(
                x,
                y,
                metal
            )
        )
end


------------------------------------------------
-- DEPLETION
------------------------------------------------

function AC_Deposits.getExtracted(
    x,
    y,
    metal
)

    local record =
        getRecord(
            x,
            y,
            false
        )


    if not record then
        return 0
    end


    return
        tonumber(
            record[metal]
        )
        or 0
end


function AC_Deposits.getRemaining(
    x,
    y,
    metal
)

    return
        math.max(
            0,
            AC_Deposits.getInitialReserve(
                x,
                y,
                metal
            )
            - AC_Deposits.getExtracted(
                x,
                y,
                metal
            )
        )
end


------------------------------------------------
-- WORKED / EXHAUSTED
------------------------------------------------
--
-- "Worked" means somebody has already tried to
-- extract this metal here. Only then does the game
-- tell the player that the tile is exhausted, so the
-- context menu does not reveal hidden geology.
------------------------------------------------

function AC_Deposits.hasBeenWorked(
    x,
    y,
    metal
)

    local record =
        getRecord(
            x,
            y,
            false
        )


    return
        record ~= nil
        and record[metal] ~= nil
end


function AC_Deposits.isKnownExhausted(
    x,
    y,
    metal
)

    return
        AC_Deposits.hasBeenWorked(
            x,
            y,
            metal
        )
        and AC_Deposits.getRemaining(
            x,
            y,
            metal
        ) <= 0
end


function AC_Deposits.markWorked(
    x,
    y,
    metal
)

    if not AC_Deposits.isMetal(
        metal
    ) then

        return
    end


    local record =
        getRecord(
            x,
            y,
            true
        )


    if record[metal] == nil then

        record[metal] =
            0
    end
end


function AC_Deposits.recordExtraction(
    x,
    y,
    metal,
    amount
)

    if not AC_Deposits.isMetal(
        metal
    ) then

        return 0
    end


    amount =
        tonumber(amount)
        or 1


    local record =
        getRecord(
            x,
            y,
            true
        )


    record[metal] =
        (
            tonumber(
                record[metal]
            )
            or 0
        )
        + amount


    return
        AC_Deposits.getRemaining(
            x,
            y,
            metal
        )
end


------------------------------------------------
-- DEBUG HELPERS
------------------------------------------------

function AC_Deposits.getTileInfo(
    x,
    y
)

    local info = {}


    for _,
        metal
    in ipairs(
        AC_Deposits.METALS
    )
    do

        local concentration =
            AC_Deposits.getConcentration(
                x,
                y,
                metal
            )


        info[metal] = {

            concentration =
                concentration,

            grade =
                AC_Geology.getGrade(
                    concentration
                ),

            initial =
                AC_Deposits.getInitialReserve(
                    x,
                    y,
                    metal
                ),

            extracted =
                AC_Deposits.getExtracted(
                    x,
                    y,
                    metal
                ),

            remaining =
                AC_Deposits.getRemaining(
                    x,
                    y,
                    metal
                ),

            worked =
                AC_Deposits.hasBeenWorked(
                    x,
                    y,
                    metal
                ),
        }
    end


    return info
end


function AC_Deposits.resetTile(
    x,
    y
)

    local store =
        getStore()


    store.tiles[
        tileKey(
            x,
            y
        )
    ] =
        nil
end


function AC_Deposits.getWorkedTileCount()

    local count = 0


    for _ in pairs(
        getStore().tiles
    ) do

        count =
            count + 1
    end


    return count
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Deposit system loaded"
)
