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
-- spread and a tool bonus that is 0 for the hand die set.
-- The press as designed gives no quality bonus (its one
-- advantage is time). The one bonus that is not 0 is a
-- malus: a case resized from a spent one (spent-cases
-- add-on, AC_SpentCases.RESIZE) rolls resizedBonus lower
-- than a case formed new at the same level.
--
-- Quality never changes what a recipe consumes or produces.
--
-- Storage: the case item's ModData. When rounds are
-- assembled, the round takes the average quality of the
-- cases consumed, under the field name the AmmoQuality
-- prototype already uses (casingQuality).
--
-- One code path for every calibre: nothing here names
-- one. A case or round is recognised through
-- AC_Calibres.identify().
--
-- LIMIT, established from the vanilla Lua: loading a
-- firearm or magazine turns round items into a count
-- (ISReloadWeaponAction), so the quality on a loose
-- round does not survive loading. It is information on
-- the loose round only; no combat effect may be built
-- on it without a different carrier.
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

    -- Added to the roll of a case resized from a spent
    -- one: worked brass that has been fired is harder
    -- and thinner at the neck. One label band (10)
    -- below a new case. Must stay below 0
    -- (AC_SpentCases.validateResize).
    resizedBonus = -10,

    -- Added back, in proportion, when the spent cases
    -- resized were cleaned with steel wool first
    -- (AC_SpentCases.CLEAN). resizedBonus + cleanedBonus
    -- must stay below 0 (AC_SpentCases.validateResize).
    cleanedBonus = 5,

    -- ModData key on a cleaned spent case.
    spentCleanedKey = "spentCaseCleaned",

    -- ModData keys on a case.
    flagKey = "AmmoMakingCase",

    qualityKey = "caseQuality",

    -- ModData keys on a cast lead bullet. Its quality is
    -- rolled like a case's, with the mould material's
    -- bonus (AC_Casting.MOULD_MATERIALS).
    bulletFlagKey = "AmmoMakingCastBullet",

    bulletQualityKey = "bulletQuality",

    -- Set on a cast bullet once it has been lubed: a
    -- second lubing adds nothing.
    bulletLubedKey = "bulletLubed",

    -- A round assembled with a cast bullet: its quality is
    -- the cases' average and the bullets' average, the
    -- bullets weighing this much. A swaged copper bullet
    -- carries no quality; its round is the case's.
    projectileShare = 0.5,

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


    -- Not a number, or NaN or an infinity: no quality.
    if not AC_SaveData.isFinite(quality) then
        return nil
    end


    return
        clamp(
            quality,
            config.minQuality,
            config.maxQuality
        )
end


-- A cast bullet's quality, or nil (a debug-spawned or
-- malformed bullet, or anything else).
function AC_CaseQuality.getBulletQuality(
    item
)

    -- As for a round: never create ModData by asking.
    if not item
        or (item.hasModData and not item:hasModData())
    then
        return nil
    end


    local data =
        item:getModData()


    local quality =
        data and data[AC_CaseQuality.CONFIG.bulletQualityKey]


    if not AC_SaveData.isFinite(quality) then
        return nil
    end


    return
        clamp(
            quality,
            AC_CaseQuality.CONFIG.minQuality,
            AC_CaseQuality.CONFIG.maxQuality
        )
end


-- The quality an assembled round inherited, or nil.
function AC_CaseQuality.getRoundQuality(
    item
)

    if not item then
        return nil
    end


    -- A factory round has no ModData at all, and
    -- getModData() would create an empty table on it (the
    -- engine makes one on first access). This runs for
    -- every round a player right-clicks, so ask first.
    if item.hasModData
        and not item:hasModData()
    then
        return nil
    end


    local data =
        item:getModData()


    local quality =
        data and data[AC_CaseQuality.CONFIG.roundQualityKey]




    -- Not a number, or NaN or an infinity: no quality.
    if not AC_SaveData.isFinite(quality) then
        return nil
    end


    -- Clamped like a case's own quality, so damaged data
    -- never reads as "900".
    return
        clamp(
            quality,
            AC_CaseQuality.CONFIG.minQuality,
            AC_CaseQuality.CONFIG.maxQuality
        )
end


-- Marks a loose round as handloaded with this casing
-- quality: the same two keys an assembled round gets.
-- Used when a round comes back out of a magazine or gun
-- (AC_QualityCarrier). A quality that is not a finite
-- number writes nothing: the round stays a factory round.
function AC_CaseQuality.setRoundQuality(
    item,
    quality
)

    if not item
        or not AC_SaveData.isFinite(quality)
    then
        return false
    end


    local config =
        AC_CaseQuality.CONFIG


    local data =
        item:getModData()


    data[config.roundFlagKey] = true

    data[config.roundQualityKey] =
        clamp(
            math.floor(quality),
            config.minQuality,
            config.maxQuality
        )


    return true
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
-- EFFECT: bullets cast
------------------------------------------------
--
-- Called from a cast recipe's OnCreate. Rolls a quality
-- for each cast bullet created, with the mould
-- material's bonus. Returns the list written.
------------------------------------------------

function AC_CaseQuality.onBulletsCast(
    craftRecipeData,
    character,
    mouldBonus
)

    local level = 0


    if character then

        level =
            AmmoMakingSkill.getLevel(
                character
            )
    end


    local config =
        AC_CaseQuality.CONFIG


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

        if AC_Calibres.identify(item:getFullType()) == "castBullet" then

            local quality =
                AC_CaseQuality.roll(
                    level,
                    ZombRandFloat(0.0, 1.0),
                    mouldBonus
                )


            local data =
                item:getModData()


            data[config.bulletFlagKey] = true

            data[config.bulletQualityKey] = quality


            table.insert(
                written,
                quality
            )
        end
    end


    return written
end


------------------------------------------------
-- EFFECT: cast bullets lubed
------------------------------------------------
--
-- The lube recipe consumes cast bullets and makes as many
-- of the same type. Each created bullet takes one
-- consumed bullet's quality, in order, plus the bonus if
-- that bullet was not lubed yet; a bullet without a
-- quality stays without one. Returns the list written.
------------------------------------------------

function AC_CaseQuality.onBulletsLubed(
    craftRecipeData,
    bonus
)

    local config =
        AC_CaseQuality.CONFIG


    local sources = {}


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllConsumedItems"
        )
    )
    do

        if AC_Calibres.identify(item:getFullType()) == "castBullet" then

            local quality =
                AC_CaseQuality.getBulletQuality(item)


            local lubed =
                quality ~= nil
                and item:getModData()[config.bulletLubedKey] == true


            table.insert(
                sources,
                { quality = quality, lubed = lubed }
            )
        end
    end


    local written = {}

    local index = 0


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllCreatedItems"
        )
    )
    do

        if AC_Calibres.identify(item:getFullType()) == "castBullet" then

            index = index + 1


            local source =
                sources[index]


            if source
                and source.quality
            then

                local quality =
                    source.quality


                if not source.lubed then

                    quality =
                        clamp(
                            quality + (tonumber(bonus) or 0),
                            config.minQuality,
                            config.maxQuality
                        )
                end


                local data =
                    item:getModData()


                data[config.bulletFlagKey] = true

                data[config.bulletQualityKey] = quality

                data[config.bulletLubedKey] = true


                table.insert(
                    written,
                    quality
                )
            end
        end
    end


    return written
end


------------------------------------------------
-- EFFECT: spent cases cleaned, and what it is worth
------------------------------------------------

-- Is this the spent case of a calibre the mod makes?
local function isSpentCase(
    fullType
)

    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if calibre.spentCase == fullType then
            return true
        end
    end


    return false
end


-- Marks every spent case the cleaning made. Returns how
-- many.
function AC_CaseQuality.onSpentCasesCleaned(
    craftRecipeData
)

    local marked = 0


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllCreatedItems"
        )
    )
    do

        if isSpentCase(item:getFullType()) then

            item:getModData()[AC_CaseQuality.CONFIG.spentCleanedKey] = true

            marked = marked + 1
        end
    end


    return marked
end


-- The share (0 to 1) of the spent cases a resizing
-- consumed that had been cleaned. Asks before reading, so
-- no ModData is made on a case that has none.
function AC_CaseQuality.cleanedShare(
    craftRecipeData
)

    local spent = 0

    local cleaned = 0


    for _,
        item
    in ipairs(
        listItems(
            craftRecipeData,
            "getAllConsumedItems"
        )
    )
    do

        if isSpentCase(item:getFullType()) then

            spent = spent + 1


            local hasData =
                not item.hasModData
                or item:hasModData()


            if hasData
                and item:getModData()[AC_CaseQuality.CONFIG.spentCleanedKey] == true
            then
                cleaned = cleaned + 1
            end
        end
    end


    if spent == 0 then
        return 0
    end


    return cleaned / spent
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

    local created =
        listItems(
            craftRecipeData,
            "getAllCreatedItems"
        )


    local consumed =
        listItems(
            craftRecipeData,
            "getAllConsumedItems"
        )


    local config =
        AC_CaseQuality.CONFIG


    local written = nil


    for _,
        round
    in ipairs(
        created
    )
    do

        local kind,
              calibre =
            AC_Calibres.identify(
                round:getFullType()
            )


        if kind == "round" then

            -- Only cases of the round's own calibre count. The
            -- recipe cannot take any other, so this only guards
            -- against a future recipe that mixes inputs.
            local total = 0

            local count = 0

            local bulletTotal = 0

            local bullets = 0


            for _,
                item
            in ipairs(
                consumed
            )
            do

                local itemKind,
                      itemCalibre =
                    AC_Calibres.identify(
                        item:getFullType()
                    )


                local quality =
                    AC_CaseQuality.get(
                        item
                    )


                if quality
                    and itemKind == "case"
                    and itemCalibre == calibre
                then

                    total =
                        total + quality

                    count =
                        count + 1
                end


                local bulletQuality =
                    itemKind == "castBullet"
                    and itemCalibre == calibre
                    and AC_CaseQuality.getBulletQuality(item)


                if bulletQuality then

                    bulletTotal =
                        bulletTotal + bulletQuality

                    bullets =
                        bullets + 1
                end
            end


            -- The cases' average, the cast bullets' average,
            -- or both weighted by projectileShare.
            local average = nil


            if count > 0
                and bullets > 0
            then

                local share =
                    config.projectileShare

                average =
                    (total / count) * (1 - share)
                    + (bulletTotal / bullets) * share

            elseif count > 0 then

                average =
                    total / count

            elseif bullets > 0 then

                average =
                    bulletTotal / bullets
            end


            if average then

                average =
                    math.floor(average + 0.5)


                local data =
                    round:getModData()


                data[config.roundFlagKey] = true

                data[config.roundQualityKey] = average


                written = average
            end
        end
    end


    return written
end


------------------------------------------------
-- Dispatch table for AC_Materials: recipe.effect ->
-- function(craftRecipeData, character, recipe).
------------------------------------------------

AC_CaseQuality.EFFECTS = {

    -- A worn die set filed true again
    -- (AC_Calibres.REGRIND).
    regrindDieSet =
        function(
            craftRecipeData
        )

            return
                AC_Calibres.onDieSetReground(
                    craftRecipeData
                )
        end,

    -- Lubing cast bullets with candle wax
    -- (AC_Casting.LUBE).
    lubeCastBullets =
        function(
            craftRecipeData
        )

            return
                AC_CaseQuality.onBulletsLubed(
                    craftRecipeData,
                    AC_Casting
                    and AC_Casting.LUBE
                    and AC_Casting.LUBE.qualityBonus
                    or 0
                )
        end,

    -- A cast: the bullets take the mould's bonus
    -- (recipe.qualityBonus, AC_Casting.MOULD_MATERIALS).
    castBulletQuality =
        function(
            craftRecipeData,
            character,
            recipe
        )

            return
                AC_CaseQuality.onBulletsCast(
                    craftRecipeData,
                    character,
                    recipe and recipe.qualityBonus or 0
                )
        end,

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

    -- A case resized from a spent one (the spent-cases
    -- add-on's resizing recipes); cleaned spent cases
    -- give part of the malus back.
    resizedCaseQuality =
        function(
            craftRecipeData,
            character
        )

            local config =
                AC_CaseQuality.CONFIG


            return
                AC_CaseQuality.onCasesFormed(
                    craftRecipeData,
                    character,
                    config.resizedBonus
                    + config.cleanedBonus
                    * AC_CaseQuality.cleanedShare(craftRecipeData)
                )
        end,

    -- Steel wool on spent cases: the same cases back,
    -- marked clean.
    cleanSpentCases =
        function(
            craftRecipeData
        )

            return
                AC_CaseQuality.onSpentCasesCleaned(
                    craftRecipeData
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
