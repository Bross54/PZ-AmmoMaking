-- Ammo Quality system
-- Project Zomboid Build 42.20

AmmoQuality = AmmoQuality or {}

-- Clamp helper
local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

-- The prototype's fields on a test cartridge and their starting
-- values. This is the AmmoMaking.TestCartridge prototype only: real
-- cases and rounds carry one quality, kept by AC_CaseQuality, and must
-- never be passed to initialize() (a handloaded round also has a
-- "casingQuality", which this would overwrite).
AmmoQuality.DEFAULTS = {

    -- Component quality values: 0-100
    casingQuality = 100,
    primerQuality = 100,
    projectileQuality = 100,
    assemblyQuality = 100,

    -- Powder load: 1.0 = standard load
    powderLoad = 1.0,

    -- Number of times casing has previously been reloaded
    reloadCount = 0,

    -- Final calculated quality
    overallQuality = 100,

    -- Reliability / failure values
    failureChance = 0,
    catastrophicFailureChance = 0,
}

-- Initialize quality data on an ammo item
function AmmoQuality.initialize(item)
    if not item then
        return
    end

    local data = item:getModData()

    if data.AmmoMakingQualityInitialized then

        -- Already set up. A field that is missing or is not a
        -- number (a damaged save) gets its default back, so the
        -- arithmetic below never meets a nil.
        for key, default in pairs(AmmoQuality.DEFAULTS) do
            if type(data[key]) ~= "number" then
                data[key] = default
            end
        end

        return
    end

    data.AmmoMakingQualityInitialized = true

    for key, default in pairs(AmmoQuality.DEFAULTS) do
        data[key] = default
    end
end

-- Calculate overall cartridge quality
function AmmoQuality.calculateOverall(item)
    if not item then
        return 0
    end

    AmmoQuality.initialize(item)

    local data = item:getModData()

    local quality =
        (data.casingQuality * 0.30) +
        (data.primerQuality * 0.20) +
        (data.projectileQuality * 0.20) +
        (data.assemblyQuality * 0.30)

    -- Penalize abnormal powder loads
    local powderDeviation = math.abs(data.powderLoad - 1.0)

    quality = quality - (powderDeviation * 40)

    -- Penalize reused casings
    quality = quality - (data.reloadCount * 2)

    quality = clamp(quality, 0, 100)

    data.overallQuality = quality

    return quality
end

-- Update reliability values
function AmmoQuality.calculateReliability(item)
    if not item then
        return
    end

    AmmoQuality.initialize(item)

    local data = item:getModData()

    local quality = AmmoQuality.calculateOverall(item)

    -- Temporary balancing formula
    local failureChance = 0

    if quality >= 90 then
        failureChance = 0.05
    elseif quality >= 80 then
        failureChance = 0.15
    elseif quality >= 70 then
        failureChance = 0.5
    elseif quality >= 60 then
        failureChance = 1.0
    elseif quality >= 50 then
        failureChance = 2.5
    elseif quality >= 40 then
        failureChance = 5.0
    elseif quality >= 30 then
        failureChance = 10.0
    elseif quality >= 20 then
        failureChance = 18.0
    else
        failureChance = 30.0
    end

    -- Hot loads increase failure chance
    if data.powderLoad > 1.10 then
        failureChance = failureChance + ((data.powderLoad - 1.10) * 50)
    end

    failureChance = clamp(failureChance, 0, 100)

    data.failureChance = failureChance

    -- Catastrophic failure should remain much rarer
    local catastrophic = 0

    if quality < 50 then
        catastrophic = (50 - quality) * 0.02
    end

    if data.powderLoad > 1.20 then
        catastrophic = catastrophic + ((data.powderLoad - 1.20) * 4)
    end

    data.catastrophicFailureChance = clamp(catastrophic, 0, 100)
end

-- Label for a 0-100 quality value (translated for display). Shared by
-- cartridges and by components that carry a single quality, such as
-- cartridge cases.
function AmmoQuality.labelFor(quality)
    if type(quality) ~= "number" then
        return AC_Text.get("IGUI_AmmoMaking_Quality_Unknown", "Unknown")
    end

    if quality >= 90 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_Excellent", "Excellent")
    elseif quality >= 80 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_VeryGood", "Very Good")
    elseif quality >= 70 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_Good", "Good")
    elseif quality >= 60 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_Average", "Average")
    elseif quality >= 50 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_Poor", "Poor")
    elseif quality >= 30 then
        return AC_Text.get("IGUI_AmmoMaking_Quality_VeryPoor", "Very Poor")
    else
        return AC_Text.get("IGUI_AmmoMaking_Quality_Dangerous", "Dangerous")
    end
end

-- Returns a simple quality label (translated for display)
function AmmoQuality.getQualityLabel(item)
    if not item then
        return AmmoQuality.labelFor(nil)
    end

    return AmmoQuality.labelFor(AmmoQuality.calculateOverall(item))
end
