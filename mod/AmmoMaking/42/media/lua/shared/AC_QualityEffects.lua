-- Ammo Making - What ammunition quality does at the shot
-- Project Zomboid Build 42.20
--
-- LOCKED. Feature "qualityEffects" (AC_Features) is
-- "disabled": no switch turns it on, and with it off
-- afterShot() returns before it looks at anything. A
-- handloaded round fires exactly like a factory round.
--
-- The code path is complete so that the day the quality
-- tracking under it (AC_QualityCarrier) has been seen to
-- stay in step in the game, switching an effect on is a
-- one-word change in AC_Features and a number here, not
-- a new system.
--
-- WHAT AN EFFECT MAY BE (docs/AMMO_QUALITY_RUNTIME_DESIGN.md 7.1)
--
-- The tally hands rounds out at the MEAN quality of the
-- load: two rounds of 90 and 10, loaded and unloaded,
-- come back as two of 50. That is harmless only for an
-- effect that is LINEAR in quality. A threshold ("a
-- misfire below 30") could be dodged by loading a bad
-- round among good ones.
--
-- So every effect here is a linear function of the
-- load's quality sum. Mixing and unmixing rounds changes
-- nothing in total; a factory round contributes nothing.
--
-- THE ONE EFFECT: a jam
--
-- Vanilla already has a jam (HandWeapon.checkJam, the
-- script's JamGunChance, cleared by racking). A poor
-- handload adds a small chance of the same jam after the
-- shot:
--
--   extra % = maximumExtraJamPercent
--             * (handloaded * 100 - qualitySum)
--             / (99 * rounds in the load)
--
-- A load of nothing but quality-100 handloads, or of
-- factory rounds: 0. A load of nothing but quality-1
-- handloads: the maximum. It never applies to a firearm
-- vanilla says cannot jam (JamGunChance 0), and it is
-- vanilla's own jam state that is set: no new mechanic.
--
-- No damage, range, accuracy or penetration is touched,
-- and none is planned.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION, before unlocking:
-- that HandWeapon:setJammed(true) after a shot behaves
-- like vanilla's own jam (the sound, the rack that
-- clears it), and that the tracking it reads is right.

require "AC_Features"

AC_QualityEffects = AC_QualityEffects or {}


AC_QualityEffects.CONFIG = {

    -- Percentage points of extra jam chance per shot for a
    -- load that is entirely quality-1 handloads. Tunable,
    -- 0 to 100.
    maximumExtraJamPercent = 4,

    -- The quality scale's ends (AC_CaseQuality: 1..100).
    worstQuality = 1,

    bestQuality = 100,

    -- ZombRand resolution: chances are compared in
    -- hundredths of a percent.
    rollSides = 10000,
}


------------------------------------------------
-- PURE: the extra jam chance of a load, in percent
------------------------------------------------
--
-- load is a tally record (or anything with count,
-- handloaded, qualitySum). Linear in qualitySum. Returns
-- 0 for anything that is not a sane load: doubt resolves
-- toward "no effect".
------------------------------------------------

function AC_QualityEffects.getExtraJamPercent(
    load
)

    local config =
        AC_QualityEffects.CONFIG


    if type(load) ~= "table" then
        return 0
    end


    local count = tonumber(load.count)

    local handloaded = tonumber(load.handloaded)

    local qualitySum = tonumber(load.qualitySum)


    if not count
        or not handloaded
        or not qualitySum
        or count ~= count
        or handloaded ~= handloaded
        or qualitySum ~= qualitySum
        or count < 1
        or handloaded < 1
        or handloaded > count
        or qualitySum < handloaded * config.worstQuality
        or qualitySum > handloaded * config.bestQuality
    then
        return 0
    end


    local span =
        config.bestQuality - config.worstQuality


    local missing =
        handloaded * config.bestQuality - qualitySum


    local percent =
        config.maximumExtraJamPercent * missing / (span * count)


    if percent < 0 then
        return 0
    end


    if percent > config.maximumExtraJamPercent then
        return config.maximumExtraJamPercent
    end


    return percent
end


------------------------------------------------
-- EFFECTS
------------------------------------------------
--
-- A list, so a second effect is a second entry. Each:
--
--   id
--   describe(load)   a short text for the debug printout
--   apply(character, weapon, fired)
--                    fired is what AC_QualityCarrier.onShot
--                    returns: { rounds, handloaded,
--                    qualitySum, before = the load's
--                    record before the shot }. Returns
--                    true when it did something.
------------------------------------------------

AC_QualityEffects.EFFECTS = {

    {
        id = "jam",

        describe = function(load)

            return string.format(
                "extra jam chance %.2f %% per shot",
                AC_QualityEffects.getExtraJamPercent(load)
            )
        end,

        apply = function(character, weapon, fired)

            if not weapon
                or not weapon.getJamGunChance
                or not weapon.setJammed
            then
                return false
            end


            -- A firearm vanilla says cannot jam does not
            -- jam; one that is jammed stays as it is.
            if (tonumber(weapon:getJamGunChance()) or 0) <= 0
                or weapon:isJammed()
            then
                return false
            end


            local percent =
                AC_QualityEffects.getExtraJamPercent(fired.before)


            if percent <= 0 then
                return false
            end


            local config =
                AC_QualityEffects.CONFIG


            if ZombRand(config.rollSides) >= percent * config.rollSides / 100 then
                return false
            end


            weapon:setJammed(true)


            return true
        end,
    },
}


------------------------------------------------
-- AFTER A SHOT
------------------------------------------------
--
-- Called by AC_QualityCarrier with what was fired.
-- Returns the ids of the effects that did something, or
-- nil while the feature is off (which is always, today).
------------------------------------------------

function AC_QualityEffects.afterShot(
    character,
    weapon,
    fired
)

    if not AC_Features.isEnabled("qualityEffects") then
        return nil
    end


    if type(fired) ~= "table"
        or type(fired.before) ~= "table"
    then
        return {}
    end


    local applied = {}


    for _,
        effect
    in ipairs(
        AC_QualityEffects.EFFECTS
    )
    do

        if effect.apply(character, weapon, fired) then

            table.insert(
                applied,
                effect.id
            )
        end
    end


    return applied
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------

function AC_QualityEffects.validate()

    local config =
        AC_QualityEffects.CONFIG


    local problems = {}


    local maximum =
        config.maximumExtraJamPercent


    if type(maximum) ~= "number"
        or maximum ~= maximum
        or maximum < 0
        or maximum > 100
    then

        table.insert(
            problems,
            "quality effects: maximumExtraJamPercent must be a number from 0 to 100"
        )
    end


    if type(config.worstQuality) ~= "number"
        or type(config.bestQuality) ~= "number"
        or config.bestQuality <= config.worstQuality
    then

        table.insert(
            problems,
            "quality effects: the quality scale must have two different ends"
        )
    end


    local seen = {}


    for index,
        effect
    in ipairs(
        AC_QualityEffects.EFFECTS
    )
    do

        if type(effect.id) ~= "string"
            or seen[effect.id]
            or type(effect.apply) ~= "function"
            or type(effect.describe) ~= "function"
        then

            table.insert(
                problems,
                "quality effects: effect " .. tostring(effect.id or index) .. " is incomplete or defined twice"
            )
        end


        seen[effect.id or index] = true
    end


    return problems
end
