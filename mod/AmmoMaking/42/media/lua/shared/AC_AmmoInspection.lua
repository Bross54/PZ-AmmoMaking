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


local function text(key, fallback, ...)
    return AC_Text.get(key, fallback, ...)
end


local function getPowderLabel(powderLoad)
    if powderLoad < 0.85 then
        return text("IGUI_AmmoMaking_Powder_VeryLow", "Very Low")
    elseif powderLoad < 0.95 then
        return text("IGUI_AmmoMaking_Powder_Low", "Low")
    elseif powderLoad <= 1.05 then
        return text("IGUI_AmmoMaking_Powder_Standard", "Standard")
    elseif powderLoad <= 1.15 then
        return text("IGUI_AmmoMaking_Powder_Hot", "Hot")
    else
        return text("IGUI_AmmoMaking_Powder_DangerouslyHot", "Dangerously Hot")
    end
end


local function getConditionLabel(value)
    if value >= 70 then
        return text("IGUI_AmmoMaking_Condition_Good", "Looks Good")
    elseif value >= 50 then
        return text("IGUI_AmmoMaking_Condition_Average", "Looks Average")
    else
        return text("IGUI_AmmoMaking_Condition_Poor", "Looks Poor")
    end
end


local function getReliabilityLabel(failureChance)
    if failureChance < 1 then
        return text("IGUI_AmmoMaking_Reliability_VeryHigh", "Very High")
    elseif failureChance < 3 then
        return text("IGUI_AmmoMaking_Reliability_High", "High")
    elseif failureChance < 8 then
        return text("IGUI_AmmoMaking_Reliability_Moderate", "Moderate")
    elseif failureChance < 15 then
        return text("IGUI_AmmoMaking_Reliability_Low", "Low")
    else
        return text("IGUI_AmmoMaking_Reliability_VeryLow", "Very Low")
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

    ------------------------------------------------
    -- result.title is drawn by the UI itself; lines
    -- hold only the body so no filtering is needed.
    ------------------------------------------------

    local result = {
        level = level,
        title = text("IGUI_AmmoMaking_Insp_Title", "Ammo Inspection"),
        lines = {}
    }


    ------------------------------------------------
    -- LEVEL 0
    ------------------------------------------------

    if level <= 0 then

        table.insert(
            result.lines,
            text(
                "IGUI_AmmoMaking_Insp_NoKnowledge",
                "You do not know enough about ammunition to judge this cartridge."
            )
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
            text("IGUI_AmmoMaking_Insp_OverallQualityPct", "Overall Quality: %1%",
                round(data.overallQuality))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_CasingQualityPct", "Casing Quality: %1%",
                round(data.casingQuality))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_PrimerQualityPct", "Primer Quality: %1%",
                round(data.primerQuality))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_ProjectileQualityPct", "Projectile Quality: %1%",
                round(data.projectileQuality))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_AssemblyQualityPct", "Assembly Quality: %1%",
                round(data.assemblyQuality))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_ReloadCount", "Casing Reload Count: %1",
                tostring(data.reloadCount))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_PowderLoadExact", "Powder Load: %1x",
                string.format("%.2f", data.powderLoad))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_FailureChance", "Failure Chance: %1%",
                string.format("%.2f", data.failureChance))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_CatastrophicChance", "Catastrophic Failure Chance: %1%",
                string.format("%.2f", data.catastrophicFailureChance))
        )

        return result
    end


    ------------------------------------------------
    -- LEVEL 1+
    ------------------------------------------------

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_OverallQuality", "Overall Quality: %1",
            AmmoQuality.getQualityLabel(item))
    )


    if level == 1 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 2+
    ------------------------------------------------

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_Casing", "Casing: %1",
            getConditionLabel(data.casingQuality))
    )


    if level == 2 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 3+
    ------------------------------------------------

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_Projectile", "Projectile: %1",
            getConditionLabel(data.projectileQuality))
    )


    if level == 3 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 4+
    ------------------------------------------------

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_PowderLoad", "Powder Load: %1",
            getPowderLabel(data.powderLoad))
    )


    if level == 4 then
        return result
    end


    ------------------------------------------------
    -- LEVEL 5+
    ------------------------------------------------

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_Primer", "Primer: %1",
            getConditionLabel(data.primerQuality))
    )

    table.insert(
        result.lines,
        text("IGUI_AmmoMaking_Insp_Reliability", "Estimated Reliability: %1",
            getReliabilityLabel(data.failureChance))
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
            text("IGUI_AmmoMaking_Insp_EstimatedQuality", "Estimated Quality: %1-%2%",
                minQuality, maxQuality)
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
            text("IGUI_AmmoMaking_Insp_CasingRange", "Casing Quality: %1-%2%",
                minCasing, maxCasing)
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_ProjectileRange", "Projectile Quality: %1-%2%",
                minProjectile, maxProjectile)
        )
    end


    if data.catastrophicFailureChance > 0.5 then

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_Warning",
                "WARNING: Possible catastrophic ammunition failure.")
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
            text("IGUI_AmmoMaking_Insp_PrimerRange", "Primer Quality: %1-%2%",
                minPrimer, maxPrimer)
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_AssemblyRange", "Assembly Quality: %1-%2%",
                minAssembly, maxAssembly)
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
            text("IGUI_AmmoMaking_Insp_FailureRange", "Estimated Failure Chance: %1-%2%",
                string.format("%.1f", minFailure),
                string.format("%.1f", maxFailure))
        )

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_ReloadCount", "Casing Reload Count: %1",
                tostring(data.reloadCount))
        )
    end


    return result
end

------------------------------------------------
-- COMPONENT INSPECTION
------------------------------------------------
--
-- For the real components: an empty case (or hull) and a
-- loose handloaded round. Unlike inspect() above, which
-- belongs to the test-cartridge prototype and fills in
-- its item's data, this only READS, and shows only what
-- the mod stores reliably:
--
--   the calibre           from the item's type
--   the case quality      rolled when the case was formed
--   the casing quality    a round inherited at assembly
--
-- Nothing else exists to show: primers, bullets and
-- powder carry no quality. A round's record lives on the
-- loose item only; vanilla loading turns rounds into a
-- count (AC_CaseQuality), so nothing here describes what
-- is in a firearm or magazine.
--
-- Level 0 sees the calibre only, levels 1-4 the label,
-- level 5 and above the number as well.
------------------------------------------------

-- kind ("case" or "round") and the calibre definition
-- for an item this inspection covers, or nil. A round
-- counts only when it carries a handloading record:
-- factory rounds have nothing to inspect.
function AmmoInspection.getComponent(item)
    if not item or not item.getFullType then
        return nil, nil
    end

    local kind, calibre = AC_Calibres.identify(item:getFullType())

    if kind == "case" then
        return kind, calibre
    end

    if kind == "round" and AC_CaseQuality.getRoundQuality(item) then
        return kind, calibre
    end

    return nil, nil
end


function AmmoInspection.inspectComponent(player, item)
    if not player then
        return nil
    end

    local kind, calibre = AmmoInspection.getComponent(item)

    if not kind then
        return nil
    end

    local level = AmmoMakingSkill.getLevel(player)

    local result = {
        level = level,
        kind = kind,
        calibre = calibre.id,
        title = text("IGUI_AmmoMaking_Insp_Title", "Ammo Inspection"),
        lines = {}
    }

    table.insert(
        result.lines,
        kind == "case"
            and text("IGUI_AmmoMaking_Insp_EmptyCase", "Empty case: %1", calibre.id)
            or text("IGUI_AmmoMaking_Insp_HandloadedRound", "Handloaded round: %1", calibre.id)
    )

    local quality =
        kind == "case"
        and AC_CaseQuality.get(item)
        or AC_CaseQuality.getRoundQuality(item)

    if level <= 0 then

        table.insert(
            result.lines,
            text(
                "IGUI_AmmoMaking_Insp_NoKnowledgeComponent",
                "You do not know enough about ammunition to judge it."
            )
        )

    elseif not quality then

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_NoRecord", "Case quality: not recorded")
        )

    elseif level < 5 then

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_CaseQuality", "Case quality: %1",
                AmmoQuality.labelFor(quality))
        )

    else

        table.insert(
            result.lines,
            text("IGUI_AmmoMaking_Insp_CaseQualityExact", "Case quality: %1 (%2)",
                AmmoQuality.labelFor(quality),
                round(quality))
        )
    end

    if kind == "round" then

        table.insert(
            result.lines,
            text(
                "IGUI_AmmoMaking_Insp_LooseOnly",
                "This record stays with the loose round; loading or boxing it keeps only a count."
            )
        )
    end

    return result
end
