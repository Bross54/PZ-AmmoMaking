-- Ammo Making - Materials and station recipes
-- Project Zomboid Build 42.20
--
-- Metallurgy (ore to brass), case stock (brass to case
-- cups) and the ammunition components of AC_Calibres extend
-- the vanilla stations; they are not systems of their own. The recipes are ordinary craftRecipe blocks
-- in media/scripts/AC_Recipes.txt, attached to the vanilla
-- furnace and forge bench tags or to any surface. The
-- engine does the timing, consumes the inputs, keeps the
-- tools and creates the outputs. This module holds only
-- what the script file cannot express:
--
--   RECIPES   a Lua mirror of AC_Recipes.txt, so tests can
--             prove the material-conservation invariants
--             and that the two never drift apart
--   UNITS     how much metal each item contains
--   on<Name>  the recipes' OnCreate callbacks: Ammo Making
--             XP, once per completed craft
--   applySkillRequirements
--             attaches the Ammo Making perk to the recipe
--             scripts after Lua has loaded
--
-- Why the last two are Lua and not script fields: the engine
-- resolves SkillRequired / xpAward names while it parses the
-- scripts, before any mod Lua runs. The Ammo Making perk is
-- registered from Lua, so it is unknown at that moment and
-- the engine drops the entry with a warning (42.20.4 jar:
-- CraftRecipe.Load, GameWindow.initShared). See
-- docs/VANILLA_METALLURGY_RESEARCH.md section 6.
--
-- Nothing here persists anything, and there is no custom
-- station, fuel, heat or timer.

-- The component recipes and their units are built from the
-- calibre definitions, which must be loaded first.
require "AC_Calibres"

AC_Materials = AC_Materials or {}


------------------------------------------------
-- CONFIG
------------------------------------------------
--
-- Not balanced yet. XP is per completed craft: the brass
-- recipe is one craft for ten ingots, sheet forging one
-- craft per ingot, cup punching one craft per sheet.
------------------------------------------------

AC_Materials.CONFIG = {

    -- Metal accounting unit. One ingot is 100 units, a scrap
    -- 10 and a case cup 5, so nothing needs fractions.
    unitsPerIngot = 100,

    xpSmeltZincOre = 3,

    xpCastIngot = 5,

    xpCastBrass = 25,

    xpForgeBrassSheets = 5,

    xpPunchCaseCups = 1,

    -- Ammo Making level of a recipe that names none of its
    -- own (metallurgy and case stock). 0 gates nothing; it
    -- makes Ammo Making the recipe's relevant skill, which
    -- is what the engine's own time scaling reads (5% faster
    -- per level above the requirement). The component
    -- recipes carry their own levels (AC_Calibres).
    requiredLevel = 0,

    xpLogSource = "Crafting",
}


------------------------------------------------
-- ITEM IDS
------------------------------------------------
--
-- Copper and brass are vanilla items. Only zinc is ours.
------------------------------------------------

AC_Materials.ITEMS = {

    CopperOre = "Base.CopperOre",

    CopperScrap = "Base.CopperScrap",

    CopperIngot = "Base.CopperIngot",

    ZincOre = "AmmoMaking.ZincOre",

    ZincScrap = "AmmoMaking.ZincScrap",

    ZincIngot = "AmmoMaking.ZincIngot",

    BrassIngot = "Base.BrassIngot",

    BrassScrap = "Base.BrassScrap",

    SmallBrassSheet = "AmmoMaking.SmallBrassSheet",

    BrassCaseCup = "AmmoMaking.BrassCaseCup",

    Crucible = "Base.CeramicCrucible",

    ClayIngotMold = "Base.ClayIngotMold",

    IronIngotMold = "Base.IronIngotMold",

    SteelIngotMold = "Base.SteelIngotMold",

    Tongs = "Base.Tongs",

    Charcoal = "Base.Charcoal",

    -- Tools of the case-stock recipes, for the debug kit. The
    -- recipes themselves ask for tags, not for these ids.
    BallPeenHammer = "Base.BallPeenHammer",

    MetalworkingPunch = "Base.MetalworkingPunch",
}


------------------------------------------------
-- METAL UNITS
------------------------------------------------
--
-- item -> { metal, units }. One ore chunk holds exactly
-- one ingot of metal: the vanilla "Smelt Copper Ore"
-- turns 1 ore into 10 scrap, and casting takes 10 scrap
-- per ingot.
--
-- Base.BrassScrap is listed for the later recycling
-- stage; no recipe touches it yet.
------------------------------------------------

AC_Materials.UNITS = {

    ["Base.CopperOre"] = { metal = "copper", units = 100 },

    ["Base.CopperScrap"] = { metal = "copper", units = 10 },

    ["Base.CopperIngot"] = { metal = "copper", units = 100 },

    ["AmmoMaking.ZincOre"] = { metal = "zinc", units = 100 },

    ["AmmoMaking.ZincScrap"] = { metal = "zinc", units = 10 },

    ["AmmoMaking.ZincIngot"] = { metal = "zinc", units = 100 },

    ["Base.BrassIngot"] = { metal = "brass", units = 100 },

    ["Base.BrassScrap"] = { metal = "brass", units = 10 },

    -- Case stock: ten small sheets per ingot, two cups per
    -- sheet. One cup becomes one cartridge case later.
    ["AmmoMaking.SmallBrassSheet"] = { metal = "brass", units = 10 },

    ["AmmoMaking.BrassCaseCup"] = { metal = "brass", units = 5 },
}


-- Ammunition components: cases, bullets, primers, powder,
-- priming compound and the vanilla rounds they become.
for itemType,
    entry
in pairs(
    AC_Calibres.buildUnits()
)
do

    AC_Materials.UNITS[itemType] = entry
end


------------------------------------------------
-- Which metals an alloy is made of. Used only by
-- the conservation check: brass counts as the sum
-- of the copper and zinc that went in.
------------------------------------------------

AC_Materials.ALLOYS = {

    brass = { "copper", "zinc" },
}


------------------------------------------------
-- RECIPES (mirror of media/scripts/AC_Recipes.txt)
------------------------------------------------
--
-- An input is { count, items = {...} } or
-- { count, tags = {...} }, plus keep = true for a tool
-- that is not consumed and flags = {...} as written in
-- the script. timedAction is set only where the vanilla
-- template has one (furnace recipes have none). tests/run_tests.lua parses the script
-- file and compares it with this table field by field.
--
-- The vanilla smelting recipe for copper ore
-- (Base.SmeltCopperOre) is listed under VANILLA_RECIPES
-- below: it is part of the chain but not ours.
------------------------------------------------

local TONGS = {
    count = 1,
    tags = { "base:crudetongs", "base:tongs" },
    keep = true,
    flags = { "MayDegradeLight" },
}

local CRUCIBLE = {
    count = 1,
    items = { "Base.CeramicCrucible" },
    keep = true,
    flags = { "IsEmpty" },
}

local INGOT_MOLD = {
    count = 1,
    items = { "Base.ClayIngotMold", "Base.IronIngotMold", "Base.SteelIngotMold" },
    keep = true,
}

local function charcoal(count)

    return {
        count = count,
        tags = { "base:charcoal" },
    }
end


AC_Materials.RECIPES = {

    {
        id = "AmmoMaking_SmeltZincOre",

        time = 200,

        benchTag = "PrimitiveFurnace",

        category = "Blacksmithing",

        callback = "onSmeltZincOre",

        xpKey = "xpSmeltZincOre",

        inputs = {
            charcoal(4),
            { count = 1, items = { "AmmoMaking.ZincOre" } },
        },

        outputs = {
            { count = 10, item = "AmmoMaking.ZincScrap" },
        },
    },

    {
        id = "AmmoMaking_CastCopperIngot",

        time = 200,

        benchTag = "Furnace",

        category = "Blacksmithing",

        callback = "onCastCopperIngot",

        xpKey = "xpCastIngot",

        inputs = {
            CRUCIBLE,
            TONGS,
            charcoal(4),
            { count = 10, items = { "Base.CopperScrap" } },
            INGOT_MOLD,
        },

        outputs = {
            { count = 1, item = "Base.CopperIngot" },
        },
    },

    {
        id = "AmmoMaking_CastZincIngot",

        time = 200,

        benchTag = "Furnace",

        category = "Blacksmithing",

        callback = "onCastZincIngot",

        xpKey = "xpCastIngot",

        inputs = {
            CRUCIBLE,
            TONGS,
            charcoal(4),
            { count = 10, items = { "AmmoMaking.ZincScrap" } },
            INGOT_MOLD,
        },

        outputs = {
            { count = 1, item = "AmmoMaking.ZincIngot" },
        },
    },

    {
        id = "AmmoMaking_CastBrassIngots",

        time = 200,

        benchTag = "Furnace",

        category = "Blacksmithing",

        callback = "onCastBrassIngots",

        xpKey = "xpCastBrass",

        -- The alloy: units out must equal units in.
        alloy = "brass",

        inputs = {
            CRUCIBLE,
            TONGS,
            charcoal(10),
            { count = 7, items = { "Base.CopperIngot" } },
            { count = 3, items = { "AmmoMaking.ZincIngot" } },
            INGOT_MOLD,
        },

        outputs = {
            { count = 10, item = "Base.BrassIngot" },
        },
    },

    ------------------------------------------------
    -- Case stock (docs/AMMUNITION_DESIGN.md, C1)
    ------------------------------------------------

    {
        id = "AmmoMaking_ForgeSmallBrassSheets",

        time = 200,

        timedAction = "HammerMetalStanding",

        benchTag = "PrimitiveForge",

        category = "Blacksmithing",

        callback = "onForgeSmallBrassSheets",

        xpKey = "xpForgeBrassSheets",

        inputs = {
            charcoal(1),
            { count = 1, items = { "Base.BrassIngot" } },
            {
                count = 1,
                tags = { "base:hammer", "base:clubhammer" },
                keep = true,
                flags = { "Prop1", "MayDegradeLight" },
            },
            {
                count = 1,
                tags = { "base:tongs", "base:metalworkingpliers" },
                keep = true,
                flags = { "Prop2", "MayDegradeLight" },
            },
        },

        outputs = {
            { count = 10, item = "AmmoMaking.SmallBrassSheet" },
        },
    },

    {
        id = "AmmoMaking_PunchBrassCaseCups",

        time = 100,

        timedAction = "MakingHammer_Surface",

        benchTag = "AnySurfaceCraft",

        category = "Metalworking",

        callback = "onPunchBrassCaseCups",

        xpKey = "xpPunchCaseCups",

        inputs = {
            { count = 1, items = { "AmmoMaking.SmallBrassSheet" } },
            {
                count = 1,
                tags = { "base:metalworkingpunch", "base:smallpunch" },
                keep = true,
                flags = { "MayDegradeLight" },
            },
            {
                count = 1,
                tags = { "base:hammer" },
                keep = true,
                flags = { "MayDegradeVeryLight" },
            },
        },

        outputs = {
            { count = 2, item = "AmmoMaking.BrassCaseCup" },
        },
    },
}


-- Ammunition components (docs/AMMUNITION_DESIGN.md):
-- gunpowder, primers, and per calibre the die set, case,
-- bullets and assembly.
for _,
    recipe
in ipairs(
    AC_Calibres.buildRecipes()
)
do

    table.insert(
        AC_Materials.RECIPES,
        recipe
    )
end


------------------------------------------------
-- Vanilla recipes that touch the same metals,
-- recorded from the installed 42.20.4 scripts so
-- the loop check in the tests covers the whole
-- graph and not only our half of it. These are
-- not defined by the mod and are never modified.
------------------------------------------------

AC_Materials.VANILLA_RECIPES = {

    {
        id = "SmeltCopperOre",

        inputs = {
            charcoal(4),
            { count = 1, items = { "Base.CopperOre" } },
        },

        outputs = {
            { count = 10, item = "Base.CopperScrap" },
        },
    },

    -- Copper sheets leave the metal chain: nothing turns
    -- a sheet back into scrap or an ingot.
    {
        id = "Forge_Small_Copper_Sheet",

        inputs = {
            charcoal(1),
            { count = 1, items = { "Base.CopperScrap" } },
        },

        outputs = {
            { count = 1, item = "Base.SmallCopperSheet" },
        },
    },

    {
        id = "Forge_Copper_Sheet",

        inputs = {
            charcoal(1),
            { count = 4, items = { "Base.CopperScrap" } },
        },

        outputs = {
            { count = 1, item = "Base.CopperSheet" },
        },
    },
}


-- Vanilla "Gather Gunpowder" takes any round apart for
-- one use of gunpowder (tags[base:ammo] in the script).
-- Recorded once per calibre the mod can assemble, so the
-- tests can prove that taking a round apart and making a
-- new one never gains anything.
for _,
    calibre
in ipairs(
    AC_Calibres.LIST
)
do

    table.insert(
        AC_Materials.VANILLA_RECIPES,
        {
            id = "GatherGunpowder_" .. calibre.suffix,

            inputs = {
                { count = 1, items = { calibre.round } },
            },

            outputs = {
                { count = 1, item = AC_Calibres.POWDER.item, oneUse = true },
            },
        }
    )
end


------------------------------------------------
-- LOOKUP
------------------------------------------------

function AC_Materials.getRecipe(
    id
)

    for _,
        recipe
    in ipairs(
        AC_Materials.RECIPES
    )
    do

        if recipe.id == id then
            return recipe
        end
    end


    return nil
end


function AC_Materials.getRecipeXP(
    recipe
)

    if not recipe then
        return 0
    end


    return
        tonumber(recipe.xp)
        or tonumber(AC_Materials.CONFIG[recipe.xpKey])
        or 0
end


-- Ammo Making level a recipe requires.
function AC_Materials.getRequiredLevel(
    recipe
)

    return
        tonumber(recipe and recipe.requiredLevel)
        or AC_Materials.CONFIG.requiredLevel
end


------------------------------------------------
-- MATERIAL UNITS OF A RECIPE
------------------------------------------------
--
-- Returns two tables material -> units: what the recipe
-- consumes and what it creates. Kept tools and items
-- without a UNITS entry (charcoal, crucible, mold, steel)
-- contain nothing that is tracked.
--
-- A UNITS entry is { metal, units } or, for a component
-- of several materials, { contents = { material = n } }.
-- For a drainable ("uses" set) the units are per use: an
-- input line counts uses, as the engine does, and an
-- output line is a full item unless it is marked oneUse.
--
-- An input that accepts several items counts the
-- alternative with the FEWEST units: the invariant
-- must hold for the cheapest way to pay.
------------------------------------------------

local function addUnits(
    totals,
    metal,
    units
)

    totals[metal] =
        (totals[metal] or 0) + units
end


local function contentsOf(
    entry
)

    if entry.contents then
        return entry.contents
    end


    return { [entry.metal] = entry.units }
end


local function totalOf(
    contents
)

    local total = 0


    for _,
        units
    in pairs(
        contents
    )
    do

        total =
            total + units
    end


    return total
end


function AC_Materials.getRecipeUnits(
    recipe
)

    local consumed = {}

    local created = {}


    for _,
        input
    in ipairs(
        recipe.inputs or {}
    )
    do

        if not input.keep
            and input.items
        then

            local cheapest = nil


            for _,
                itemType
            in ipairs(
                input.items
            )
            do

                local entry =
                    AC_Materials.UNITS[itemType]


                if entry then

                    local contents =
                        contentsOf(entry)


                    if not cheapest
                        or totalOf(contents) < totalOf(cheapest)
                    then

                        cheapest = contents
                    end
                end
            end


            for material,
                units
            in pairs(
                cheapest or {}
            )
            do

                addUnits(
                    consumed,
                    material,
                    units * input.count
                )
            end
        end
    end


    for _,
        output
    in ipairs(
        recipe.outputs or {}
    )
    do

        local entry =
            AC_Materials.UNITS[output.item]


        if entry then

            local perItem = 1


            if entry.uses
                and not output.oneUse
            then

                perItem = entry.uses
            end


            for material,
                units
            in pairs(
                contentsOf(entry)
            )
            do

                addUnits(
                    created,
                    material,
                    units * perItem * output.count
                )
            end
        end
    end


    return consumed, created
end


------------------------------------------------
-- CONSERVATION
------------------------------------------------
--
-- A recipe conserves material when, for every material
-- it creates, it consumed at least as many units of that
-- material - or, for an alloy, of the alloy's parts in
-- total. An alloy recipe must come out exactly even.
--
-- recipe.source names the one material a recipe may bring
-- into existence from untracked raw inputs (gunpowder from
-- charcoal and fertilizer). Such a recipe must still
-- consume something.
--
-- Returns ok and a reason string for a failure.
------------------------------------------------

function AC_Materials.checkConservation(
    recipe
)

    local consumed,
          created =
        AC_Materials.getRecipeUnits(
            recipe
        )


    for metal,
        units
    in pairs(
        created
    )
    do

        local available =
            consumed[metal] or 0


        if recipe.source == metal then

            -- Never short, whatever is created.
            available = units
        end


        -- The parts of an alloy pay for it only in the recipe
        -- that makes the alloy. Anywhere else brass must come
        -- from brass: the copper of a bullet is not a case.
        local parts =
            recipe.alloy == metal
            and AC_Materials.ALLOYS[metal]


        if parts then

            for _,
                part
            in ipairs(
                parts
            )
            do

                available =
                    available + (consumed[part] or 0)
            end
        end


        if units > available then

            return
                false,
                recipe.id
                .. " creates "
                .. units
                .. " units of "
                .. metal
                .. " from "
                .. available
        end


        if recipe.alloy == metal
            and units ~= available
        then

            return
                false,
                recipe.id
                .. " alloy is not exact: "
                .. available
                .. " in, "
                .. units
                .. " out"
        end
    end


    if recipe.source then

        local consumesSomething = false


        for _,
            input
        in ipairs(
            recipe.inputs or {}
        )
        do

            if not input.keep
                and input.count > 0
            then

                consumesSomething = true
            end
        end


        if not consumesSomething then

            return
                false,
                recipe.id
                .. " creates "
                .. recipe.source
                .. " from nothing"
        end
    end


    return true, nil
end


------------------------------------------------
-- EXPECTED CRAFT TIME (display / tests only)
------------------------------------------------
--
-- Mirrors the engine's own rule, which is what really
-- applies in game (42.20.4 jar, CraftRecipe.getTime):
--
--   time - (level - requiredLevel) * (time / 20)
--
-- with integer division, and no change at or below the
-- required level. The mod does not implement the timing;
-- this only predicts it for the debug printout.
------------------------------------------------

function AC_Materials.getExpectedTime(
    recipe,
    level
)

    local required =
        AC_Materials.getRequiredLevel(
            recipe
        )


    level =
        tonumber(level) or 0


    if level <= required then
        return recipe.time
    end


    return
        recipe.time
        - (level - required)
        * math.floor(recipe.time / 20)
end


------------------------------------------------
-- XP (the recipes' OnCreate callbacks)
------------------------------------------------
--
-- The engine calls OnCreate(craftRecipeData, character)
-- once per completed craft, after the outputs exist
-- (vanilla ISHandcraftAction:performRecipe). A cancelled
-- or failed craft never reaches it.
--
-- One global function per recipe, named in the script's
-- OnCreate line, so the callback never has to ask the
-- engine which recipe ran.
--
-- Multiplayer: performRecipe runs on the server there.
-- awardXP uses the single-player XP call; a server-side
-- grant needs vanilla's addXp() and is future work
-- (docs/DEVELOPMENT.md).
------------------------------------------------

function AC_Materials.onRecipeCreated(
    recipeId,
    character,
    craftRecipeData
)

    local recipe =
        AC_Materials.getRecipe(
            recipeId
        )


    if not recipe then
        return 0
    end


    local granted = 0


    if character then

        granted =
            AmmoMakingSkill.awardXP(
                character,
                AC_Materials.getRecipeXP(recipe),
                AC_Materials.CONFIG.xpLogSource
                .. " ("
                .. recipe.id
                .. ")"
            )
    end


    ------------------------------------------------
    -- Some recipes do one more thing than XP: a formed
    -- case gets its quality, an assembled round inherits
    -- it (AC_CaseQuality.EFFECTS). A failure there must
    -- not break the craft, which has already happened.
    ------------------------------------------------

    local effect =
        recipe.effect
        and AC_CaseQuality.EFFECTS[recipe.effect]


    if effect then

        local ok,
              err =
            pcall(
                effect,
                craftRecipeData,
                character
            )


        if not ok then

            print(
                "[AmmoMaking] WARNING: "
                .. recipe.effect
                .. " failed for "
                .. recipe.id
                .. ": "
                .. tostring(err)
            )
        end
    end


    return granted
end


for _,
    recipe
in ipairs(
    AC_Materials.RECIPES
)
do

    local recipeId =
        recipe.id


    AC_Materials[recipe.callback] =
        function(
            craftRecipeData,
            character
        )

            return
                AC_Materials.onRecipeCreated(
                    recipeId,
                    character,
                    craftRecipeData
                )
        end
end


------------------------------------------------
-- SKILL REQUIREMENT ON THE RECIPE SCRIPTS
------------------------------------------------
--
-- Adds "Ammo Making: <level>" to each of our recipe
-- scripts through the engine's own
-- CraftRecipe.addRequiredSkill(Perk, int). With it the
-- crafting UI shows Ammo Making as the recipe's skill,
-- the engine refuses the craft below that level, and
-- CraftRecipe.getTime(character) shortens the craft
-- with the character's Ammo Making level.
--
-- This is the ONLY thing that gates the component
-- recipes by level: if it cannot be attached, they are
-- open to everyone and the compatibility check says so.
--
-- Safe to call any number of times: a recipe that
-- already has a required skill is left alone. Every
-- method is looked up before it is called, and only
-- with the argument types the jar declares, so a
-- build without them is reported, not crashed into.
--
-- Returns { attached, present, missing, unsupported }.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the
-- method is callable from Lua and that the requirement
-- shows in the crafting UI.
------------------------------------------------

function AC_Materials.findRecipeScript(
    recipeId
)

    if type(getScriptManager) ~= "function" then
        return nil
    end


    local manager =
        getScriptManager()


    if not manager
        or not manager.getCraftRecipe
    then
        return nil
    end


    return
        manager:getCraftRecipe(
            recipeId
        )
end


function AC_Materials.applySkillRequirements()

    local summary = {

        attached = 0,

        present = 0,

        missing = 0,

        unsupported = 0,
    }


    local perk =
        AmmoMakingSkill
        and AmmoMakingSkill.perk


    for _,
        recipe
    in ipairs(
        AC_Materials.RECIPES
    )
    do

        local script =
            AC_Materials.findRecipeScript(
                recipe.id
            )


        if not script then

            summary.missing =
                summary.missing + 1

        elseif not perk
            or not script.addRequiredSkill
            or not script.getRequiredSkillCount
        then

            summary.unsupported =
                summary.unsupported + 1

        elseif script:getRequiredSkillCount() > 0 then

            summary.present =
                summary.present + 1

        else

            script:addRequiredSkill(
                perk,
                AC_Materials.getRequiredLevel(recipe)
            )


            summary.attached =
                summary.attached + 1
        end
    end


    return summary
end


local function applySkillRequirementsLogged()

    local ok,
          summary =
        pcall(
            AC_Materials.applySkillRequirements
        )


    if not ok then

        print(
            "[AmmoMaking] WARNING: recipe skill requirements not applied: "
            .. tostring(summary)
        )


        return
    end


    if summary.attached > 0
        or summary.missing > 0
        or summary.unsupported > 0
    then

        print(
            "[AmmoMaking] Station recipes: "
            .. summary.attached
            .. " given the Ammo Making requirement, "
            .. summary.present
            .. " already had it, "
            .. summary.missing
            .. " not found, "
            .. summary.unsupported
            .. " unsupported"
        )
    end
end


-- OnGameBoot: scripts and all mod Lua are loaded. OnGameStart
-- repeats it in case the scripts were reloaded for the save;
-- the second run changes nothing when the first one held.
Events.OnGameBoot.Add(
    applySkillRequirementsLogged
)

Events.OnGameStart.Add(
    applySkillRequirementsLogged
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Materials and station recipes loaded"
)
