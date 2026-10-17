-- Ammo Making custom skill
-- Project Zomboid Build 42.20

AmmoMakingSkill = AmmoMakingSkill or {}

-- Create custom perk
AmmoMakingSkill.perk = PerkFactory.Perk.new(
    "AmmoMaking",
    Perks.Crafting
)

AmmoMakingSkill.perk:setCustom()

-- Register perk
PerkFactory.AddPerk(
    AmmoMakingSkill.perk,
    "AmmoMaking",
    Perks.Crafting,
    75,
    150,
    300,
    750,
    1500,
    3000,
    4500,
    6000,
    7500,
    9000
)

-- Refresh translations
PerkFactory.initTranslations()

-- Debug output
--
-- The perk name key has no space ("IGUI_perks_AmmoMaking"). The level
-- description keys in IG_UI.json are written with a space
-- ("IGUI_perks_Ammo Making_Description1") because the vanilla skill
-- panel builds them from the translated perk name. Which spelling the
-- engine actually resolves is reported by AC_Compat at startup rather
-- than assumed here; getTextOrNull never prints a raw key.
print("[AmmoMaking] Ammo Making skill registered")
print("[AmmoMaking] Perk name = " .. tostring(AmmoMakingSkill.perk:getName()))
print(
    "[AmmoMaking] Perk name translation = "
    .. tostring(getTextOrNull("IGUI_perks_AmmoMaking"))
)

-- Add Ammo Making XP
function AmmoMakingSkill.addXP(player, amount)
    if not player then
        return
    end

    if not amount or amount <= 0 then
        return
    end

    player:getXp():AddXP(
        AmmoMakingSkill.perk,
        amount
    )
end

-- Current Ammo Making XP total, or nil when it cannot be read.
-- getXp():getXP(perk) is how vanilla ISPlayerStatsUI reads a perk's XP.
function AmmoMakingSkill.getXP(player)
    if not player then
        return nil
    end

    local xp = player:getXp()

    if not xp or not xp.getXP then
        return nil
    end

    return xp:getXP(AmmoMakingSkill.perk)
end

-- "5" for whole numbers, "2.50" otherwise
function AmmoMakingSkill.formatXP(amount)
    amount = tonumber(amount)

    if not amount then
        return "?"
    end

    if amount == math.floor(amount) then
        return string.format("%d", amount)
    end

    return string.format("%.2f", amount)
end

-- Add Ammo Making XP once and log it, with the perk's XP total before
-- and after so the console shows what the engine actually applied (it
-- may scale the amount; that is not assumed here). Returns the amount
-- requested, or 0 when nothing was added.
function AmmoMakingSkill.awardXP(player, amount, source)
    if not player or not amount or amount <= 0 then
        return 0
    end

    local before = AmmoMakingSkill.getXP(player)

    AmmoMakingSkill.addXP(player, amount)

    local after = AmmoMakingSkill.getXP(player)

    print(
        "[AmmoMaking] "
        .. tostring(source or "XP")
        .. ": +"
        .. AmmoMakingSkill.formatXP(amount)
        .. " Ammo Making XP (total "
        .. AmmoMakingSkill.formatXP(before)
        .. " -> "
        .. AmmoMakingSkill.formatXP(after)
        .. ")"
    )

    return amount
end

-- Get current Ammo Making level
function AmmoMakingSkill.getLevel(player)
    if not player then
        return 0
    end

    return player:getPerkLevel(
        AmmoMakingSkill.perk
    )
end

-- Check if player has required Ammo Making level
function AmmoMakingSkill.hasLevel(player, requiredLevel)
    if not player then
        return false
    end

    return AmmoMakingSkill.getLevel(player) >= requiredLevel
end