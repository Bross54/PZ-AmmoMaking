-- Ammo Making - Ore extraction
-- Project Zomboid Build 42.20
--
-- Extraction is tied to the geology system:
--
--   1. A geological sample is dug (3x3 area).
--   2. The sample is assayed (field / advanced / lab).
--   3. While carrying an assayed sample that reports a
--      metal, the player can work any tile inside the
--      sampled 3x3 area with a pickaxe.
--   4. Each extraction consumes one unit of the tile's
--      deterministic reserve (AC_Deposits) and drops one
--      ore item on the mined square.
--
-- The assay only decides whether the player KNOWS
-- about a deposit. What is actually extracted always
-- comes from the true geology of the mined tile.
--
-- All world-state changes go through
-- AC_Mining.extract(), so it can later be executed on
-- the server for multiplayer.

AC_Mining = AC_Mining or {}


------------------------------------------------
-- CONFIGURATION
------------------------------------------------

AC_Mining.CONFIG = {

    ------------------------------------------------
    -- ACTION TIME
    ------------------------------------------------
    --
    -- Each Ammo Making level reduces extraction
    -- time by 4%. Level 10 = 40% faster.
    ------------------------------------------------

    baseActionTime = 400,

    skillTimeReductionPerLevel = 0.04,


    ------------------------------------------------
    -- PROSPECTING
    ------------------------------------------------
    --
    -- Samples represent a 3x3 area, so a sample
    -- covers tiles within 1 tile of its center.
    --
    -- Rank 1 = field assay or better.
    ------------------------------------------------

    prospectRadius = 1,

    minimumAssayRank = 1,


    ------------------------------------------------
    -- REWARDS / WEAR
    ------------------------------------------------

    xpPerOre = 5,

    pickaxeWearChance = 15,


    ------------------------------------------------
    -- FEEDBACK
    ------------------------------------------------
    --
    -- Show "the vein is thinning" when this many
    -- units or fewer remain after an extraction.
    ------------------------------------------------

    thinningThreshold = 1,


    ------------------------------------------------
    -- PRESENTATION (placeholders)
    ------------------------------------------------
    --
    -- No verified B42 pickaxe mining animation or
    -- sound name is used yet. The action falls back to
    -- the vanilla shovel animation and sound.
    ------------------------------------------------

    sound = "Shoveling",

    soundRadius = 20,
}


------------------------------------------------
-- PICKAXES
------------------------------------------------
--
-- Explicit list on purpose: a substring match on
-- "pickaxe" would also accept Base.PickAxeHead.
------------------------------------------------

AC_Mining.PICKAXE_TYPES = {

    ["Base.PickAxe"] = true,

    ["Base.PickAxeForged"] = true,
}


------------------------------------------------
-- ORE ITEMS
------------------------------------------------
--
-- Resolved at call time so load order between
-- shared files does not matter.
------------------------------------------------

function AC_Mining.getOreItemType(
    metal
)

    if metal == "copper" then

        return
            AC_Geology.ITEMS.CopperOre
    end


    if metal == "zinc" then

        return
            AC_Geology.ITEMS.ZincOre
    end


    return nil
end


------------------------------------------------
-- HELPERS
------------------------------------------------

local function createItem(
    fullType
)

    ------------------------------------------------
    -- Build 42 item factory, with the older factory
    -- as a fallback.
    ------------------------------------------------

    if instanceItem then

        return
            instanceItem(
                fullType
            )
    end


    return
        InventoryItemFactory.CreateItem(
            fullType
        )
end


local function applyPickaxeWear(
    pickaxe
)

    if not pickaxe then
        return
    end


    if ZombRand(100)
        >= AC_Mining.CONFIG.pickaxeWearChance
    then

        return
    end


    local condition =
        pickaxe:getCondition()


    if condition <= 0 then
        return
    end


    pickaxe:setCondition(
        math.max(
            0,
            condition - 1
        )
    )
end


------------------------------------------------
-- PICKAXE
------------------------------------------------

function AC_Mining.isPickaxe(
    item
)

    return
        item ~= nil
        and AC_Mining.PICKAXE_TYPES[
            item:getFullType()
        ] == true
end


function AC_Mining.isUsablePickaxe(
    item
)

    if not AC_Mining.isPickaxe(
        item
    ) then

        return false
    end


    if item:isBroken() then
        return false
    end


    return
        item:getCondition() > 0
end


function AC_Mining.getEquippedPickaxe(
    player
)

    if not player then
        return nil
    end


    local primary =
        player:getPrimaryHandItem()


    if AC_Mining.isPickaxe(
        primary
    ) then

        return primary
    end


    local secondary =
        player:getSecondaryHandItem()


    if AC_Mining.isPickaxe(
        secondary
    ) then

        return secondary
    end


    return nil
end


------------------------------------------------
-- MINEABLE GROUND
------------------------------------------------
--
-- Same terrain rules as geological sampling:
-- outdoor natural ground on level 0 only.
------------------------------------------------

function AC_Mining.isMineableSquare(
    square
)

    return
        AC_Geology.isSurveyableSquare(
            square
        )
end


------------------------------------------------
-- ASSAY KNOWLEDGE
------------------------------------------------

function AC_Mining.getReportedGrade(
    sample,
    metal
)

    if not sample then
        return nil
    end


    local data =
        sample:getModData()


    if metal == "copper" then
        return data.copperGrade
    end


    if metal == "zinc" then
        return data.zincGrade
    end


    return nil
end


function AC_Mining.sampleCoversSquare(
    sample,
    square
)

    if not sample
        or not square
    then

        return false
    end


    local data =
        sample:getModData()


    local sampleX =
        tonumber(data.sampleX)

    local sampleY =
        tonumber(data.sampleY)


    if not sampleX
        or not sampleY
    then

        return false
    end


    local radius =
        AC_Mining.CONFIG.prospectRadius


    return
        math.abs(square:getX() - sampleX) <= radius
        and math.abs(square:getY() - sampleY) <= radius
end


------------------------------------------------
-- FIND PROSPECT
------------------------------------------------
--
-- Returns the best assayed sample in the player's
-- inventory (including bags) that covers this square
-- and reports the metal at any grade above None.
--
-- Returns: sample, reportedGrade   or   nil
------------------------------------------------

function AC_Mining.findProspect(
    player,
    square,
    metal
)

    if not player
        or not square
        or not AC_Deposits.isMetal(metal)
    then

        return nil
    end


    local samples =
        player:getInventory():
            getItemsFromFullType(
                AC_GeologySampling.ITEMS.Sample,
                true
            )


    if not samples then
        return nil
    end


    local bestSample = nil
    local bestGrade = nil
    local bestRank = 0


    for index = 0,
        samples:size() - 1
    do

        local sample =
            samples:get(
                index
            )


        local data =
            sample:getModData()


        local rank =
            tonumber(
                data.assayRank
            )
            or 0


        local grade =
            AC_Mining.getReportedGrade(
                sample,
                metal
            )


        if rank >= AC_Mining.CONFIG.minimumAssayRank
            and rank > bestRank
            and data.labProcessing ~= true
            and grade ~= nil
            and grade ~= "None"
            and AC_Mining.sampleCoversSquare(
                sample,
                square
            )
        then

            bestSample =
                sample

            bestGrade =
                grade

            bestRank =
                rank
        end
    end


    return
        bestSample,
        bestGrade
end


------------------------------------------------
-- ACTION TIME
------------------------------------------------

function AC_Mining.getActionTime(
    player
)

    local level =
        AmmoMakingSkill.getLevel(
            player
        )


    local multiplier =
        1
        - (
            level
            * AC_Mining.CONFIG.skillTimeReductionPerLevel
        )


    return
        math.max(
            1,
            math.floor(
                AC_Mining.CONFIG.baseActionTime
                * multiplier
            )
        )
end


------------------------------------------------
-- EXTRACT ORE
------------------------------------------------
--
-- Performs one extraction on a tile.
--
-- Success returns a result table:
--
-- {
--     item = ore item dropped on the square,
--     metal = "copper" / "zinc",
--     remaining = units left on this tile,
-- }
--
-- Failure returns nil, errorCode:
--
--     no_player, no_square, invalid_metal,
--     invalid_surface, no_pickaxe, no_prospect,
--     no_ore, item_creation_failed
------------------------------------------------

function AC_Mining.extract(
    player,
    square,
    metal,
    pickaxe
)

    if not player then
        return nil, "no_player"
    end


    if not square then
        return nil, "no_square"
    end


    if not AC_Deposits.isMetal(
        metal
    ) then

        return nil, "invalid_metal"
    end


    if not AC_Mining.isMineableSquare(
        square
    ) then

        return nil, "invalid_surface"
    end


    pickaxe =
        pickaxe
        or AC_Mining.getEquippedPickaxe(
            player
        )


    if not AC_Mining.isUsablePickaxe(
        pickaxe
    ) then

        return nil, "no_pickaxe"
    end


    if not AC_Mining.findProspect(
        player,
        square,
        metal
    ) then

        return nil, "no_prospect"
    end


    local x =
        square:getX()

    local y =
        square:getY()


    ------------------------------------------------
    -- TRUE GEOLOGY
    ------------------------------------------------

    local remaining =
        AC_Deposits.getRemaining(
            x,
            y,
            metal
        )


    if remaining <= 0 then

        ------------------------------------------------
        -- Remember that this tile was worked, so the
        -- context menu can show it as exhausted.
        ------------------------------------------------

        AC_Deposits.markWorked(
            x,
            y,
            metal
        )


        print(
            "[AmmoMaking] Mining: no workable "
            .. tostring(metal)
            .. " at "
            .. tostring(x)
            .. ", "
            .. tostring(y)
            .. " (concentration "
            .. string.format(
                "%.1f",
                AC_Deposits.getConcentration(
                    x,
                    y,
                    metal
                )
            )
            .. "%)"
        )


        return nil, "no_ore"
    end


    ------------------------------------------------
    -- ORE ITEM
    --
    -- Dropped on the mined square: vanilla
    -- Base.CopperOre is a heavy two-handed item.
    ------------------------------------------------

    local itemType =
        AC_Mining.getOreItemType(
            metal
        )


    local item =
        itemType
        and createItem(
            itemType
        )


    if not item then

        print(
            "[AmmoMaking] ERROR: Mining could not create item "
            .. tostring(itemType)
        )


        return nil, "item_creation_failed"
    end


    square:AddWorldInventoryItem(
        item,
        ZombRandFloat(0.2, 0.8),
        ZombRandFloat(0.2, 0.8),
        0
    )


    ------------------------------------------------
    -- DEPLETION / XP / WEAR
    ------------------------------------------------

    local remainingAfter =
        AC_Deposits.recordExtraction(
            x,
            y,
            metal,
            1
        )


    AmmoMakingSkill.addXP(
        player,
        AC_Mining.CONFIG.xpPerOre
    )


    applyPickaxeWear(
        pickaxe
    )


    print(
        "[AmmoMaking] Mining: extracted "
        .. tostring(itemType)
        .. " at "
        .. tostring(x)
        .. ", "
        .. tostring(y)
        .. "; remaining "
        .. tostring(remainingAfter)
        .. "/"
        .. tostring(
            AC_Deposits.getInitialReserve(
                x,
                y,
                metal
            )
        )
    )


    return {

        item =
            item,

        metal =
            metal,

        remaining =
            remainingAfter,
    }
end


------------------------------------------------
-- STARTUP ITEM CHECK
------------------------------------------------
--
-- Logs whether the ore item scripts exist, so a
-- missing vanilla item shows up clearly in
-- console.txt instead of as a silent failure.
------------------------------------------------

local function verifyOreItems()

    for _,
        metal
    in ipairs(
        AC_Deposits.METALS
    )
    do

        local itemType =
            AC_Mining.getOreItemType(
                metal
            )


        local ok,
              script =
            pcall(
                function()

                    return
                        getScriptManager():FindItem(
                            itemType
                        )
                end
            )


        if ok
            and script
        then

            print(
                "[AmmoMaking] Mining ore item OK: "
                .. tostring(itemType)
            )

        else

            print(
                "[AmmoMaking] WARNING: Mining ore item not found: "
                .. tostring(itemType)
            )
        end
    end
end


Events.OnGameStart.Add(
    verifyOreItems
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Mining system loaded"
)
