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
print("[AmmoMaking] Ammo Making skill registered")
print("[AmmoMaking] Translation test = " .. getText("IGUI_perks_AmmoMaking"))
print("[AmmoMaking] Perk name = " .. tostring(AmmoMakingSkill.perk:getName()))
print("[AmmoMaking] Description translation = " .. getText("IGUI_perks_AmmoMaking_Description"))

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