-- Ammo inspection system
-- Project Zomboid Build 42.20

AmmoInspection = AmmoInspection or {}


------------------------------------------------
-- HELPERS
------------------------------------------------

local function round(value)
    return math.floor(value + 0.5)
end


local function getRange(value, margin)
    local minValue = math.max(0, round(value - margin))
    local maxValue = math.min(100, round(value + margin))

    return minValue, maxValue
end


local function getPowderLabel(powderLoad)
    if powderLoad < 0.85 then
        return "Very Low"
    elseif powderLoad < 0.95 then
        return "Low"
    elseif powderLoad <= 1.05 then
        return "Standard"
    elseif powderLoad <= 1.15 then
        return "Hot"
    else
        return "Dangerously Hot"
    end
end


local function getConditionLabel(value)
    if value >= 70 then
        return "Looks Good"
    elseif value >= 50 then
        return "Looks Average"
    else
        return "Looks Poor"
    end
end


local function getReliabilityLabel(failureChance)
    if failureChance < 1 then
        return "Very High"
    elseif failureChance < 3 then
        return "High"
    elseif failureChance < 8 then
        return "Moderate"
    elseif failureChance < 15 then
        return "Low"
    else
        return "Very Low"
    end
end


------------------------------------------------
-- MAIN INSPECTION
------------------------------------------------

function AmmoInspection.inspect(player, item)
    if not player or not item then
        return nil
    end

    AmmoQuality.initialize(item)
    AmmoQuality.calculateReliability(item)

    local level = AmmoMakingSkill.getLevel(player)
    local data = item:getModData()

    local result = {
        level = level,
        lines = {}
    }

    table.insert(
        result.lines,
        "Ammo Inspection"
    )


    ------------------------------------------------
    -- LEVEL 0
    ------------------------------------------------

    if level <= 0 then

        table.insert(
            result.lines,
            "You do not know enough about ammunition to judge this cartridge."
        )

        return result
    end


    ------------------------------------------------
    -- LEVEL 10
    -- Expert view: precise information only
    ------------------------------------------------

    if level >= 10 then

        table.insert(
            result.lines,
            "Overall Quality: "
            .. round(data.overallQuality)
            .. "%"
        )

        table.insert(
            result.lines,
            "Casing Quality: "
            .. round(data.casingQuality)
            .. "%"
        )

        table.insert(
            result.lines,
            "Primer Quality: "
            .. round(data.primerQuality)
            .. "%"
        )

        table.insert(
            result.lines,
            "Projectile Quality: "
            .. round(data.projectileQuality)
            .. "%"
        )

        table.insert(
            result.lines,
            "Assembly Quality: "
            .. round(data.assemblyQuality)
            .. "%"
        )

        table.insert(
            result.lines,
            "Casing Reload Count: "
            .. tostring(data.reloadCount)
        )

        table.insert(
            result.lines,
            string.format(
                "Powder Load: %.2fx",
                data.powderLoad
            )
        )

        table.insert(
            result.lines,
            string.format(
                "Failure Chance: %.2f%%",
                data.failureChance
            )
        )

        table.insert(
            result.lines,
            string.format(
                "Catastrophic Failure Chance: %.2f%%",
                data.catastrophicFailureChance
            )
        )

        return result
    end


    ------------------------------------------------
    -- LEVEL 1+
    ------------------------------------------------

    table.insert(
        result.lines,
        "Overall Quality: "
        .. AmmoQuality.getQualityLabel(item)
    )


    if level == 1 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 2+
    ------------------------------------------------

    table.insert(
        result.lines,
        "Casing: "
        .. getConditionLabel(data.casingQuality)
    )


    if level == 2 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 3+
    ------------------------------------------------

    table.insert(
        result.lines,
        "Projectile: "
        .. getConditionLabel(data.projectileQuality)
    )


    if level == 3 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 4+
    ------------------------------------------------

    table.insert(
        result.lines,
        "Powder Load: "
        .. getPowderLabel(data.powderLoad)
    )


    if level == 4 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 5+
    ------------------------------------------------

    table.insert(
        result.lines,
        "Primer: "
        .. getConditionLabel(data.primerQuality)
    )

    table.insert(
        result.lines,
        "Estimated Reliability: "
        .. getReliabilityLabel(data.failureChance)
    )


    if level == 5 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 6+
    ------------------------------------------------

    do
        local minQuality, maxQuality =
            getRange(data.overallQuality, 15)

        table.insert(
            result.lines,
            "Estimated Quality: "
            .. minQuality
            .. "-"
            .. maxQuality
            .. "%"
        )
    end


    if level == 6 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 7+
    ------------------------------------------------

    do
        local minCasing, maxCasing =
            getRange(data.casingQuality, 12)

        local minProjectile, maxProjectile =
            getRange(data.projectileQuality, 12)

        table.insert(
            result.lines,
            "Casing Quality: "
            .. minCasing
            .. "-"
            .. maxCasing
            .. "%"
        )

        table.insert(
            result.lines,
            "Projectile Quality: "
            .. minProjectile
            .. "-"
            .. maxProjectile
            .. "%"
        )
    end


    if data.catastrophicFailureChance > 0.5 then

        table.insert(
            result.lines,
            "WARNING: Possible catastrophic ammunition failure."
        )
    end


    if level == 7 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 8+
    ------------------------------------------------

    do
        local minPrimer, maxPrimer =
            getRange(data.primerQuality, 8)

        local minAssembly, maxAssembly =
            getRange(data.assemblyQuality, 8)

        table.insert(
            result.lines,
            "Primer Quality: "
            .. minPrimer
            .. "-"
            .. maxPrimer
            .. "%"
        )

        table.insert(
            result.lines,
            "Assembly Quality: "
            .. minAssembly
            .. "-"
            .. maxAssembly
            .. "%"
        )
    end


    if level == 8 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 9
    ------------------------------------------------

    do
        local minFailure =
            math.max(
                0,
                data.failureChance - 0.5
            )

        local maxFailure =
            math.min(
                100,
                data.failureChance + 0.5
            )

        table.insert(
            result.lines,
            string.format(
                "Estimated Failure Chance: %.1f-%.1f%%",
                minFailure,
                maxFailure
            )
        )

        table.insert(
            result.lines,
            "Casing Reload Count: "
            .. tostring(data.reloadCount)
        )
    end


    return result
end