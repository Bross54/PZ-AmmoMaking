-- Ammo Making - Cartridge case quality
-- Project Zomboid Build 42.20
--
-- The finished cartridge case is the first component that
-- carries a quality. Ore, ingots, brass, sheets and cups
-- carry none.
--
-- Quality is one number, 1..100, on the same scale and with
-- the same labels as the AmmoQuality prototype
-- (AmmoQuality.labelFor). It is rolled once, when the case
-- is formed, from the maker's Ammo Making level, a random
-- spread and a tool bonus that is 0 for the hand die set
-- and exists so a future press can raise it.
--
-- Quality never changes what a recipe consumes or produces.
--
-- Storage: the case item's ModData. When rounds are
-- assembled, the round takes the average quality of the
-- cases consumed, under the field name the AmmoQuality
-- prototype already uses (casingQuality).
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that ModData on a
-- crafted case survives stacking, container transfers and
-- save/reload, and that the engine exposes
-- getAllCreatedItems / getAllConsumedItems to Lua (the
-- 42.20.4 jar declares both; vanilla Lua calls the second).

AC_CaseQuality = AC_CaseQuality or {}


------------------------------------------------
-- CONFIG
------------------------------------------------
--
-- Level 0 centres on 50, level 10 on 90. With the spread a
-- novice makes Very Poor to Average cases and a master
-- Good to Excellent ones; nobody makes a guaranteed
-- failure and nothing is destroyed.
------------------------------------------------

AC_CaseQuality.CONFIG = {

    baseQuality = 50,

    qualityPerLevel = 4,

    -- Half-width of the random spread.
    spread = 15,

    minQuality = 1,

    maxQuality = 100,

    maxLevel = 10,

    -- ModData keys on a case.
    flagKey = "AmmoMakingCase",

    qualityKey = "caseQuality",

    -- ModData keys on an assembled round.
    roundFlagKey = "AmmoMakingHandloaded",

    roundQualityKey = "casingQuality",
}


local function clamp(
    value,
    low,
    high
)

    if value < low then
        return low
    end


    if value > high then
        return high
    end


    return value
end


------------------------------------------------
-- ROLL (pure)
------------------------------------------------
--
-- level      Ammo Making level, clamped to 0..10
-- random01   a number in [0, 1); 0.5 is the centre
-- toolBonus  added flat; 0 for the hand die set
--
-- Returns a whole number in minQuality..maxQuality.
------------------------------------------------

function AC_CaseQuality.roll(
    level,
    random01,
    toolBonus
)

    local config =
        AC_CaseQuality.CONFIG


    level =
        clamp(
            tonumber(level) or 0,
            0,
            config.maxLevel
        )


    random01 =
        clamp(
            tonumber(random01) or 0.5,
            0,
            1
        )


    local quality =
        config.baseQuality
        + config.qualityPerLevel * level
        + (tonumber(toolBonus) or 0)
        + (random01 * 2 - 1) * config.spread


    return
        clamp(
            math.floor(quality + 0.5),
            config.minQuality,
            config.maxQuality
        )
end


------------------------------------------------
-- READ / WRITE
------------------------------------------------

function AC_CaseQuality.set(
    item,
    quality
)

    if not item
        or type(quality) ~= "number"
    then
        return false
    end


    local config =
        AC_CaseQuality.CONFIG


    local data =
        item:getModData()


    data[config.flagKey] = true

    data[config.qualityKey] =
        clamp(
            math.floor(quality + 0.5),
            config.minQuality,
            config.maxQuality
        )


    return true
end


-- The stored quality, or nil for an item that has none
-- (a case spawned by debug, or anything that is not a
-- case). Malformed data counts as none.
function AC_CaseQuality.get(
    item
)

    if not item then
        return nil
    end


    local config =
        AC_CaseQuality.CONFIG


    local data =
        item:getModData()


    local quality =
        data and data[config.qualityKey]


    if type(quality) ~= "number" then
        return nil
    end


    return
        clamp(
            quality,
            config.minQuality,
            config.maxQuality
        )
end


-- The quality an assembled round inherited, or nil.
function AC_CaseQuality.getRoundQuality(
    item
)

    if not item then
        return nil
    end


    local data =
        item:getModData()


    local quality =
        data and data[AC_CaseQuality.CONFIG.roundQualityKey]


    if type(quality) ~= "number" then
        return nil
    end


    return quality
end


function AC_CaseQuality.getLabel(
    quality
)

    return
        AmmoQuality.labelFor(
            quality
        )
end


------------------------------------------------
-- Java ArrayList -> Lua table. Returns {} when the
-- recipe data or the method is missing.
------------------------------------------------

local function listItems(
    craftRecipeData,
    methodName
)

    local items = {}


    if not craftRecipeData
        or not craftRecipeData[methodName]
    then
        return items
    end


    local list =
        craftRecipeData[methodName](
            craftRecipeData
        )


    if not list then
        return items
    end


    for index = 0, list:size() - 1 do

        table.insert(
            items,
            list:get(index)
        )
    end


    return items
end


------------------------------------------------
-- EFFECT: cases formed
------------------------------------------------
--
-- Called from the forming recipe's OnCreate. Rolls a
-- quality for each created case. Returns the list of
-- qualities written.
------------------------------------------------

function AC_CaseQuality.onCasesFormed(
    craftRecipeData,
    character,
    toolBonus
)

    local level = 0


    if character then

        level =
            AmmoMakingSkill.getLevel(
                character
            )
    end


    local written = {}


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllCreatedItems"
        )
    )
    do

        if AC_Calibres.identify(item:getFullType()) == "case" then

            local quality =
                AC_CaseQuality.roll(
                    level,
                    ZombRandFloat(0.0, 1.0),
                    toolBonus
                )


            AC_CaseQuality.set(
                item,
                quality
            )


            table.insert(
                written,
                quality
            )
        end
    end


    return written
end


------------------------------------------------
-- EFFECT: rounds assembled
------------------------------------------------
--
-- Called from the assembly recipe's OnCreate, while the
-- consumed items can still be read. The created rounds
-- take the average quality of the consumed cases. Cases
-- without a quality are ignored; with none at all the
-- rounds are left untouched.
--
-- Returns the quality written, or nil.
------------------------------------------------

function AC_CaseQuality.onRoundsAssembled(
    craftRecipeData
)

    local total = 0

    local count = 0


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllConsumedItems"
        )
    )
    do

        local quality =
            AC_CaseQuality.get(
                item
            )


        if quality
            and AC_Calibres.identify(item:getFullType()) == "case"
        then

            total =
                total + quality

            count =
                count + 1
        end
    end


    if count == 0 then
        return nil
    end


    local average =
        math.floor(total / count + 0.5)


    local config =
        AC_CaseQuality.CONFIG


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllCreatedItems"
        )
    )
    do

        if AC_Calibres.identify(item:getFullType()) == "round" then

            local data =
                item:getModData()


            data[config.roundFlagKey] = true

            data[config.roundQualityKey] = average
        end
    end


    return average
end


------------------------------------------------
-- Dispatch table for AC_Materials: recipe.effect ->
-- function(craftRecipeData, character).
------------------------------------------------

AC_CaseQuality.EFFECTS = {

    caseQuality =
        function(
            craftRecipeData,
            character
        )

            return
                AC_CaseQuality.onCasesFormed(
                    craftRecipeData,
                    character,
                    0
                )
        end,

    roundQuality =
        function(
            craftRecipeData
        )

            return
                AC_CaseQuality.onRoundsAssembled(
                    craftRecipeData
                )
        end,
}


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Case quality loaded"
)
