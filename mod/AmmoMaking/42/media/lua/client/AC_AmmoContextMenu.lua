-- Ammo Making inventory context menu
-- Project Zomboid Build 42.20

require "ISUI/ISInventoryPaneContextMenu"


------------------------------------------------
-- HELPERS
------------------------------------------------

local function getActualItem(entry)
    if not entry then
        return nil
    end

    -- Normal InventoryItem
    if entry.getFullType then
        return entry
    end

    -- Inventory stack / context-menu wrapper
    if entry.items and entry.items[1] then
        return entry.items[1]
    end

    return nil
end


------------------------------------------------
-- AMMO INSPECTION
------------------------------------------------

local function showInspection(player, item)
    if not player or not item then
        return
    end

    local inspection = AmmoInspection.inspect(player, item)

    if not inspection or not inspection.lines then
        return
    end

    print("[AmmoMaking] Inspection:")
    print(table.concat(inspection.lines, "\n"))

    AC_AmmoInspectionUI.open(
        player,
        inspection
    )
end


local function onInspectAmmo(player, item)
    showInspection(player, item)
end


------------------------------------------------
-- DEBUG AMMO QUALITY PRESETS
------------------------------------------------

local function applyPreset(player, item, presetName)
    if not player or not item then
        return
    end

    AmmoQuality.initialize(item)

    local data = item:getModData()

    if presetName == "Perfect" then

        data.casingQuality = 100
        data.primerQuality = 100
        data.projectileQuality = 100
        data.assemblyQuality = 100

        data.powderLoad = 1.00
        data.reloadCount = 0


    elseif presetName == "Good" then

        data.casingQuality = 85
        data.primerQuality = 80
        data.projectileQuality = 88
        data.assemblyQuality = 82

        data.powderLoad = 1.02
        data.reloadCount = 1


    elseif presetName == "Poor" then

        data.casingQuality = 55
        data.primerQuality = 48
        data.projectileQuality = 65
        data.assemblyQuality = 45

        data.powderLoad = 0.92
        data.reloadCount = 3


    elseif presetName == "Dangerous" then

        data.casingQuality = 35
        data.primerQuality = 42
        data.projectileQuality = 65
        data.assemblyQuality = 30

        data.powderLoad = 1.22
        data.reloadCount = 5


    elseif presetName == "Overloaded" then

        data.casingQuality = 75
        data.primerQuality = 70
        data.projectileQuality = 80
        data.assemblyQuality = 65

        data.powderLoad = 1.35
        data.reloadCount = 1


    else

        print(
            "[AmmoMaking] Unknown ammo quality preset: "
            .. tostring(presetName)
        )

        return
    end


    -- Recalculate derived data
    AmmoQuality.calculateReliability(item)

    print(
        "[AmmoMaking] Applied preset: "
        .. tostring(presetName)
    )

    print(
        "[AmmoMaking] Overall quality: "
        .. tostring(data.overallQuality)
    )

    print(
        "[AmmoMaking] Failure chance: "
        .. tostring(data.failureChance)
    )

    print(
        "[AmmoMaking] Catastrophic chance: "
        .. tostring(data.catastrophicFailureChance)
    )


    HaloTextHelper.addText(
        player,
        "Preset: " .. tostring(presetName)
    )
end


------------------------------------------------
-- DEBUG AMMO MAKING LEVEL
------------------------------------------------

local function setAmmoMakingLevel(player, targetLevel)
    if not player then
        return
    end

    targetLevel = tonumber(targetLevel)

    if not targetLevel then
        return
    end


    -- Clamp to valid range
    if targetLevel < 0 then
        targetLevel = 0
    elseif targetLevel > 10 then
        targetLevel = 10
    end


    ------------------------------------------------
    -- Direct debug level setter
    ------------------------------------------------

    player:setPerkLevelDebug(
        AmmoMakingSkill.perk,
        targetLevel
    )


    ------------------------------------------------
    -- Synchronize XP with selected level
    ------------------------------------------------

    player:getXp():setXPToLevel(
        AmmoMakingSkill.perk,
        targetLevel
    )


    ------------------------------------------------
    -- Verify actual level
    ------------------------------------------------

    local actualLevel =
        AmmoMakingSkill.getLevel(player)


    print(
        "[AmmoMaking] Debug skill level set. Target="
        .. tostring(targetLevel)
        .. " Actual="
        .. tostring(actualLevel)
    )


    HaloTextHelper.addText(
        player,
        "Ammo Making Level "
        .. tostring(actualLevel)
    )
end


------------------------------------------------
-- DEBUG QUALITY SUBMENU
------------------------------------------------

local function addQualityDebugMenu(
    context,
    player,
    item
)

    local debugOption =
        context:addOption(
            "Debug Ammo Quality"
        )


    local debugMenu =
        ISContextMenu:getNew(context)


    context:addSubMenu(
        debugOption,
        debugMenu
    )


    debugMenu:addOption(
        "Perfect",
        player,
        applyPreset,
        item,
        "Perfect"
    )


    debugMenu:addOption(
        "Good",
        player,
        applyPreset,
        item,
        "Good"
    )


    debugMenu:addOption(
        "Poor",
        player,
        applyPreset,
        item,
        "Poor"
    )


    debugMenu:addOption(
        "Dangerous",
        player,
        applyPreset,
        item,
        "Dangerous"
    )


    debugMenu:addOption(
        "Overloaded",
        player,
        applyPreset,
        item,
        "Overloaded"
    )
end


------------------------------------------------
-- DEBUG SKILL LEVEL SUBMENU
------------------------------------------------

local function addSkillDebugMenu(
    context,
    player
)

    local levelOption =
        context:addOption(
            "Debug Ammo Making Level"
        )


    local levelMenu =
        ISContextMenu:getNew(context)


    context:addSubMenu(
        levelOption,
        levelMenu
    )


    ------------------------------------------------
    -- Level 0 - 10
    ------------------------------------------------

    for level = 0, 10 do

        levelMenu:addOption(
            "Level " .. tostring(level),
            player,
            setAmmoMakingLevel,
            level
        )

    end
end


------------------------------------------------
-- INVENTORY CONTEXT MENU
------------------------------------------------

local function onFillInventoryContextMenu(
    playerIndex,
    context,
    items
)

    local player =
        getSpecificPlayer(playerIndex)


    if not player then
        return
    end


    for _, entry in ipairs(items) do

        local item =
            getActualItem(entry)


        if item
            and item:getFullType()
                == "AmmoMaking.TestCartridge"
        then


            ------------------------------------------------
            -- INSPECT AMMUNITION
            ------------------------------------------------

            context:addOption(
                "Inspect Ammunition",
                player,
                onInspectAmmo,
                item
            )


            ------------------------------------------------
            -- DEBUG QUALITY
            ------------------------------------------------

            addQualityDebugMenu(
                context,
                player,
                item
            )


            ------------------------------------------------
            -- DEBUG SKILL LEVEL
            ------------------------------------------------

            addSkillDebugMenu(
                context,
                player
            )


            -- We found the relevant item,
            -- no reason to continue iterating.
            return
        end
    end
end


------------------------------------------------
-- EVENT REGISTRATION
------------------------------------------------

Events.OnFillInventoryObjectContextMenu.Add(
    onFillInventoryContextMenu
)


print(
    "[AmmoMaking] Ammo context menu loaded"
)