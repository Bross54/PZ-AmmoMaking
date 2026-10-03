-- Ammo Making - temporary visuals, in one place
-- Project Zomboid Build 42.20
--
-- PLACEHOLDER_VISUAL
--
-- The mod has no final art. Everything a player sees is
-- either a vanilla asset borrowed for the time being or
-- programmer art, and every such choice that Lua makes is
-- in the table below. Gameplay code never names a sprite,
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

        value = "Build_Handpress",

        kind = "window icon",

        feature = "Reloading Press, crafting window and build menu (add-on AmmoMakingPress)",

        source = "vanilla's Hand Operated Press icon (scripts/xui/defaultskin/x_entity_hand_press.txt)",

        final = "a 32 x 32 icon of the reloading press",

        usedBy = "the entity's window skin",

        mirror = "mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress_xuiSkin.txt",
    },
}


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
