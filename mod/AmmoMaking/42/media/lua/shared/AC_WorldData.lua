-- Ammo Making - World-specific deterministic data
-- Project Zomboid Build 42.20

AC_WorldData = AC_WorldData or {}


------------------------------------------------
-- LOCAL CACHE
------------------------------------------------

AC_WorldData.cachedSaveIdentity =
    AC_WorldData.cachedSaveIdentity or nil

AC_WorldData.cachedGeologySeed =
    AC_WorldData.cachedGeologySeed or nil

AC_WorldData.cachedCopperSeed =
    AC_WorldData.cachedCopperSeed or nil

AC_WorldData.cachedZincSeed =
    AC_WorldData.cachedZincSeed or nil


------------------------------------------------
-- STRING HASH
------------------------------------------------
--
-- Converts any string into a deterministic integer.
--
-- Same input:
--     always same result
--
-- Different save identity:
--     different result
------------------------------------------------

local function hashString(text)

    if not text then
        return nil
    end


    local hash = 5381


    for i = 1, string.len(text) do

        local byte =
            string.byte(
                text,
                i
            )


        ------------------------------------------------
        -- DJB-style deterministic hash
        --
        -- Modulo keeps the value safely inside the
        -- integer range Lua/PZ handles reliably.
        ------------------------------------------------

        hash =
            (
                (hash * 33)
                + byte
            )
            % 2147483647
    end


    return hash
end


------------------------------------------------
-- CONVERT HASH TO SIX-DIGIT SEED
------------------------------------------------

local function makeSixDigitSeed(
    hash
)

    if not hash then
        return nil
    end


    ------------------------------------------------
    -- Output range:
    --
    -- 100000 - 999999
    ------------------------------------------------

    return
        100000
        + (hash % 900000)
end


------------------------------------------------
-- GET SAVE IDENTITY
------------------------------------------------
--
-- We intentionally derive the geology seed from
-- the save/world identity instead of storing a
-- separately generated random value.
--
-- This means:
--
-- SAME SAVE
--     -> same identity
--     -> same geology seed
--
-- DIFFERENT SAVE
--     -> different identity
--     -> different geology seed
--
-- RESTART
--     -> no change
------------------------------------------------

function AC_WorldData.getSaveIdentity()

    ------------------------------------------------
    -- Cached value
    ------------------------------------------------

    if AC_WorldData.cachedSaveIdentity then

        return
            AC_WorldData.cachedSaveIdentity
    end


    ------------------------------------------------
    -- Current IsoWorld
    ------------------------------------------------

    local world =
        getWorld()


    if not world then

        print(
            "[AmmoMaking] ERROR: Cannot get current IsoWorld"
        )

        return nil
    end


    ------------------------------------------------
    -- Current world/save identifier
    ------------------------------------------------

    local worldName =
        world:getWorld()


    if not worldName
        or worldName == ""
    then

        print(
            "[AmmoMaking] ERROR: Current world has no save identity"
        )

        return nil
    end


    ------------------------------------------------
    -- Store in runtime cache
    ------------------------------------------------

    AC_WorldData.cachedSaveIdentity =
        tostring(
            worldName
        )


    return
        AC_WorldData.cachedSaveIdentity
end


------------------------------------------------
-- GEOLOGY SEED
------------------------------------------------

function AC_WorldData.getGeologySeed()

    if AC_WorldData.cachedGeologySeed then

        return
            AC_WorldData.cachedGeologySeed
    end


    local identity =
        AC_WorldData.getSaveIdentity()


    if not identity then
        return nil
    end


    ------------------------------------------------
    -- Namespace prevents unrelated hashes from
    -- accidentally producing the same subsystem
    -- value.
    ------------------------------------------------

    local source =
        "AmmoMaking|Geology|"
        .. identity


    local hash =
        hashString(
            source
        )


    local seed =
        makeSixDigitSeed(
            hash
        )


    AC_WorldData.cachedGeologySeed =
        seed


    print(
        "[AmmoMaking] Save identity: "
        .. tostring(identity)
    )


    print(
        "[AmmoMaking] Geology seed: "
        .. tostring(seed)
    )


    return seed
end


------------------------------------------------
-- COPPER SEED
------------------------------------------------

function AC_WorldData.getCopperSeed()

    if AC_WorldData.cachedCopperSeed then

        return
            AC_WorldData.cachedCopperSeed
    end


    local identity =
        AC_WorldData.getSaveIdentity()


    if not identity then
        return nil
    end


    local source =
        "AmmoMaking|Copper|"
        .. identity


    local hash =
        hashString(
            source
        )


    local seed =
        makeSixDigitSeed(
            hash
        )


    AC_WorldData.cachedCopperSeed =
        seed


    return seed
end


------------------------------------------------
-- ZINC SEED
------------------------------------------------

function AC_WorldData.getZincSeed()

    if AC_WorldData.cachedZincSeed then

        return
            AC_WorldData.cachedZincSeed
    end


    local identity =
        AC_WorldData.getSaveIdentity()


    if not identity then
        return nil
    end


    local source =
        "AmmoMaking|Zinc|"
        .. identity


    local hash =
        hashString(
            source
        )


    local seed =
        makeSixDigitSeed(
            hash
        )


    AC_WorldData.cachedZincSeed =
        seed


    return seed
end


------------------------------------------------
-- DEBUG SEED INFORMATION
------------------------------------------------

function AC_WorldData.getSeedInfo()

    local identity =
        AC_WorldData.getSaveIdentity()


    if not identity then
        return nil
    end


    return {

        identity =
            identity,

        geology =
            AC_WorldData.getGeologySeed(),

        copper =
            AC_WorldData.getCopperSeed(),

        zinc =
            AC_WorldData.getZincSeed()
    }
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] World data system loaded"
)