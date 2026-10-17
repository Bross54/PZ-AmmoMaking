-- Ammo Making - temporary visuals, in one place
-- Project Zomboid Build 42.20
--
-- PLACEHOLDER_VISUAL
--
-- The mod draws its own inventory icons (ICONS below).
-- Everything else a player sees is either a vanilla asset
-- borrowed for the time being or programmer art, and
-- every such choice that Lua makes is in the table below. Gameplay code never names a sprite,
-- icon or model: it asks AC_Visuals.get(key).
--
-- Replacing a visual later is:
--
--     change "value" here  ->  run the tests  ->  done
--
-- What is NOT here, because the engine reads it from
-- scripts before any Lua runs:
--
--   an item's Icon and WorldStaticModel   AC_Items.txt
--   the press's sprites and window icon   the add-on's
--                                         entity script
--                                         and tile sheet
--
-- Those are listed, with these, in the generated table of
-- docs/PLACEHOLDER_ASSETS.md (tests/write_recipes.lua
-- reads the scripts), and the entries below marked
-- "mirror" repeat a script's value so that Lua can probe
-- it: the tests fail if a mirror and its script disagree.
--
-- An entry:
--
--   key      what gameplay code asks for
--   value    the asset's name
--   kind     "world sprite", "window icon"
--   feature  what the player sees it on
--   source   where the placeholder comes from
--   final    the asset that should replace it
--   usedBy   where the value takes effect
--   mirror   the script file whose value this repeats, if
--            it is one

AC_Visuals = AC_Visuals or {}


AC_Visuals.MARK = "PLACEHOLDER_VISUAL"


AC_Visuals.LIST = {

    {
        key = "analyzerWorldSprite",

        value = "industry_03_61",

        kind = "world sprite",

        feature = "Laboratory Assay Analyzer, placed",

        source = "vanilla tile of the industry_03 sheet, found with the tile inspector; claimed by no vanilla entity and not a vanilla moveable",

        final = "a one-tile laboratory instrument on a stand, one or two faces",

        usedBy = "AC_LaboratoryAnalyzer.CONFIG.worldSprite",
    },

    {
        key = "pressSpriteSouth",

        value = "ammomaking_press_01_0",

        kind = "world sprite",

        feature = "Reloading Press, facing south (add-on AmmoMakingPress)",

        source = "the add-on's own tile sheet: programmer art drawn by art/reloading_press/make_art.py",

        final = "a single-stage bench press on a short wooden stand, facing south, 128 x 256",

        usedBy = "the entity's SpriteConfig; probed by AC_Compat when the press is on",

        mirror = "mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress.txt",
    },

    {
        key = "pressSpriteEast",

        value = "ammomaking_press_01_1",

        kind = "world sprite",

        feature = "Reloading Press, facing east (add-on AmmoMakingPress)",

        source = "the add-on's own tile sheet: programmer art drawn by art/reloading_press/make_art.py",

        final = "the same press facing east, 128 x 256",

        usedBy = "the entity's SpriteConfig; probed by AC_Compat when the press is on",

        mirror = "mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress.txt",
    },

    {
        key = "pressWindowIcon",

        value = "Build_AmmoMakingReloadingPress",

        kind = "window icon",

        feature = "Reloading Press, crafting window and build menu (add-on AmmoMakingPress)",

        source = "the add-on's own icon, 48 x 48, drawn by art/icons/make_icons.py",

        final = "none needed: original art; redraw it when the press's sprites get final art",

        usedBy = "the entity's window skin",

        mirror = "mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress_xuiSkin.txt",
    },
}


------------------------------------------------
-- THE MOD'S OWN ICONS
------------------------------------------------
--
-- Original pixel art, drawn by art/icons/make_icons.py
-- and shipped as loose files:
--
--   <mod>/42/media/textures/<prefix><name>.png
--
-- An item script's "Icon = <name>" makes the engine look
-- for the texture "Item_<name>" (Item.DoParam in the
-- 42.20.4 jar), first in the texture packs and then as
-- media/textures/Item_<name>.png; a window skin's Icon
-- is the file name itself. Every name starts with
-- "AmmoMaking", so no vanilla icon is ever replaced.
--
-- An icon belongs to the mod whose scripts name it: an
-- add-on's items and windows can only use what the
-- add-on itself ships.
--
-- The tests check that every entry has its file at the
-- stated size, that every icon an item names is either
-- one of these or one a vanilla item uses, and that no
-- entry is unused.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: how each icon
-- reads in the inventory.
------------------------------------------------

AC_Visuals.ICONS = {

    { name = "AmmoMakingZincOre", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingZincScrap", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingZincIngot", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBrassSheet", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCaseCup", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingPrimerSmallPistol", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingPrimerLargePistol", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingPrimerSmallRifle", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingPrimerLargeRifle", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingDieSet", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCasePistol", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCaseMagnum", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCaseRifle", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingHull", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBulletPistol", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBulletRifle", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingShot", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingLeadScrap", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCastBullet", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingLeadShot", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBulletMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingShotMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingRifleMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingStoneMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingClayMouldUnfired", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingClayMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSandMould", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingGasCheck", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingCastBulletRifle", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSample", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingFieldKit", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingAdvancedKit", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingAnalyzer", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBook1", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBook2", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBook3", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBook4", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingBook5", mod = "AmmoMaking", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSpentCasePistol", mod = "AmmoMakingSpentCases", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSpentCaseMagnum", mod = "AmmoMakingSpentCases", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSpentCaseRifle", mod = "AmmoMakingSpentCases", prefix = "Item_", size = 32 },

    { name = "AmmoMakingSpentHull", mod = "AmmoMakingSpentCases", prefix = "Item_", size = 32 },

    { name = "AmmoMakingReloadingPress", mod = "AmmoMakingPress", prefix = "Build_", size = 48 },
}


-- A spent case's icon, by the icon of the case it was:
-- the same drawing, tarnished and sooted at the mouth.
AC_Visuals.SPENT_ICONS = {

    AmmoMakingCasePistol = "AmmoMakingSpentCasePistol",

    AmmoMakingCaseMagnum = "AmmoMakingSpentCaseMagnum",

    AmmoMakingCaseRifle = "AmmoMakingSpentCaseRifle",

    AmmoMakingHull = "AmmoMakingSpentHull",
}


function AC_Visuals.findIcon(
    name
)

    for _,
        entry
    in ipairs(
        AC_Visuals.ICONS
    )
    do

        if entry.name == name then
            return entry
        end
    end


    return nil
end


-- The icon of the spent form of a case; the case's own
-- icon when there is no drawing of it spent.
function AC_Visuals.getSpentIcon(
    cleanIcon
)

    return AC_Visuals.SPENT_ICONS[cleanIcon] or cleanIcon
end


------------------------------------------------
-- LOOKUP
------------------------------------------------

function AC_Visuals.find(
    key
)

    for _,
        entry
    in ipairs(
        AC_Visuals.LIST
    )
    do

        if entry.key == key then
            return entry
        end
    end


    return nil
end


-- The asset's name, or nil for a key nobody defined.
function AC_Visuals.get(
    key
)

    local entry =
        AC_Visuals.find(key)


    return entry and entry.value or nil
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- Returns a list of problems; empty when every entry is
-- complete and no key is used twice.
------------------------------------------------

function AC_Visuals.validate(
    list
)

    list =
        list or AC_Visuals.LIST


    local problems = {}

    local seen = {}


    for index,
        entry
    in ipairs(
        list
    )
    do

        local label =
            tostring(entry.key or index)


        for _,
            field
        in ipairs(
            { "key", "value", "kind", "feature", "source", "final", "usedBy" }
        )
        do

            if type(entry[field]) ~= "string"
                or entry[field] == ""
            then

                table.insert(
                    problems,
                    "visual " .. label .. " has no " .. field
                )
            end
        end


        if seen[label] then

            table.insert(
                problems,
                "visual " .. label .. " is defined twice"
            )
        end


        seen[label] = true
    end


    return problems
end
