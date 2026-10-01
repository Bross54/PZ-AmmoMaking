-- Ammo Making - Calibre definitions and ammunition component recipes
-- Project Zomboid Build 42.20
--
-- One table describes a calibre: its vanilla round, its
-- case, bullet and die set items, its primer family, how
-- much powder it takes and which Ammo Making level each
-- step needs. Everything else is derived from that table:
--
--   buildRecipes()  the Lua mirror of the craftRecipe
--                   blocks (AC_Materials appends it to
--                   AC_Materials.RECIPES)
--   buildUnits()    what each component contains, for the
--                   material-conservation checks
--   getItems()      the item ids to probe and to spawn
--
-- Adding a calibre is a new entry in AC_Calibres.LIST, its
-- three items in AC_Items.txt, their names, and a
-- regenerated AC_Recipes.txt (tests/write_recipes.lua
-- renders the blocks from this file). No calibre name
-- appears in any other Lua logic.
--
-- The recipes produce the VANILLA round item, so vanilla
-- firearms and magazines need no change.
--
-- Vanilla evidence for every item id, tool tag and recipe
-- pattern used here: docs/VANILLA_AMMUNITION_RESEARCH.md.

AC_Calibres = AC_Calibres or {}


------------------------------------------------
-- SHARED VALUES
------------------------------------------------
--
-- Not balanced yet. Metal amounts are in the units of
-- AC_Materials (100 per ingot, 10 per scrap or small
-- sheet, 5 per case cup).
------------------------------------------------

AC_Calibres.CONFIG = {

    -- Brass in one case cup; a case is drawn from one cup.
    cupUnits = 5,

    -- Units in one vanilla copper scrap / one small brass
    -- sheet.
    scrapUnits = 10,

    sheetUnits = 10,
}


------------------------------------------------
-- PROPELLANT
------------------------------------------------
--
-- Vanilla Base.GunPowder, a 10-use jar. Vanilla's only
-- source is taking rounds apart (one use per round), so
-- the mod adds a recipe from raw materials: charcoal and
-- fertilizer ground in a mortar. Vanilla has no sulfur or
-- nitrate item; fertilizer is the nitrate stand-in, the
-- way vanilla uses a cold pack in its smoke bomb.
------------------------------------------------

AC_Calibres.POWDER = {

    item = "Base.GunPowder",

    usesPerJar = 10,

    charcoal = 2,

    fertilizerItem = "Base.Fertilizer",

    fertilizerUses = 2,

    requiredLevel = 3,

    xp = 5,

    time = 150,
}


------------------------------------------------
-- PRIMING COMPOUND SOURCES
------------------------------------------------
--
-- Loot items that carry an impact- or friction-sensitive
-- charge. units = compound per item, or per use for a
-- drainable (a recipe line counts uses for those).
------------------------------------------------

AC_Calibres.COMPOUND_SOURCES = {

    {
        id = "Caps",

        items = { "Base.CapGunCap" },

        units = 2,
    },

    {
        id = "Matches",

        items = { "Base.Matches", "Base.Matchbox" },

        units = 1,

        uses = { ["Base.Matches"] = 10, ["Base.Matchbox"] = 50 },
    },
}


------------------------------------------------
-- PRIMER FAMILIES
------------------------------------------------
--
-- A primer belongs to a family, not to a calibre: 9mm
-- and .38 Special both take small pistol primers.
------------------------------------------------

AC_Calibres.PRIMERS = {

    {
        id = "SmallPistol",

        item = "AmmoMaking.SmallPistolPrimer",

        -- Brass in one primer cup and anvil.
        brassUnits = 1,

        -- Priming compound in one primer.
        compoundUnits = 2,

        -- Primers punched from one small brass sheet.
        perSheet = 10,

        requiredLevel = 2,

        xp = 2,

        time = 120,
    },
}


------------------------------------------------
-- CALIBRES
------------------------------------------------
--
-- id       shown in debug labels and logs
-- suffix   used in item and recipe ids (letters and
--          digits only)
-- round    the vanilla cartridge item the assembly makes
-- ammoType the vanilla weapon AmmoType, for reference
-- case, bullet, dieSet
--          the calibre's three mod items; when left out
--          they are AmmoMaking.Case<suffix>,
--          AmmoMaking.Bullet<suffix>, AmmoMaking.DieSet<suffix>
-- primer   a PRIMERS id
-- bulletsPerScrap
--          copper bullets swaged from one Base.CopperScrap
-- powderUses
--          uses of Base.GunPowder per round. Never below
--          1: vanilla returns one use when a round is
--          taken apart, so less would create powder.
-- levels   Ammo Making level required per step
-- xp, time per step
--
-- Anything a definition leaves out comes from DEFAULTS,
-- so a new calibre states only what makes it different.
------------------------------------------------

AC_Calibres.DEFAULTS = {

    primer = "SmallPistol",

    bulletsPerScrap = 2,

    powderUses = 1,

    levels = {
        dieSet = 1,
        case = 1,
        bullet = 2,
        assemble = 3,
    },

    xp = {
        dieSet = 10,
        case = 1,
        bullet = 1,
        assemble = 2,
    },

    time = {
        dieSet = 300,
        case = 80,
        bullet = 80,
        assemble = 40,
    },
}


local function copyTable(
    source
)

    local copy = {}


    for key,
        value
    in pairs(
        source
    )
    do

        copy[key] = value
    end


    return copy
end


------------------------------------------------
-- Completes a definition from DEFAULTS. Step tables
-- (levels, xp, time) are merged key by key, so a
-- calibre may override a single step.
------------------------------------------------

function AC_Calibres.define(
    definition
)

    local defaults =
        AC_Calibres.DEFAULTS


    local calibre =
        copyTable(
            definition
        )


    calibre.case =
        calibre.case or ("AmmoMaking.Case" .. calibre.suffix)

    calibre.bullet =
        calibre.bullet or ("AmmoMaking.Bullet" .. calibre.suffix)

    calibre.dieSet =
        calibre.dieSet or ("AmmoMaking.DieSet" .. calibre.suffix)


    for _,
        key
    in ipairs(
        { "primer", "bulletsPerScrap", "powderUses" }
    )
    do

        if calibre[key] == nil then
            calibre[key] = defaults[key]
        end
    end


    for _,
        key
    in ipairs(
        { "levels", "xp", "time" }
    )
    do

        local merged =
            copyTable(
                defaults[key]
            )


        for step,
            value
        in pairs(
            definition[key] or {}
        )
        do

            merged[step] = value
        end


        calibre[key] = merged
    end


    return calibre
end


AC_Calibres.LIST = {

    AC_Calibres.define({

        id = "9mm",

        suffix = "9mm",

        round = "Base.Bullets9mm",

        ammoType = "base:bullets_9mm",
    }),

    -- The second calibre, added to prove the model: one
    -- definition, three items, their names and a
    -- regenerated script. It shares the small pistol
    -- primer with 9mm.
    AC_Calibres.define({

        id = ".38 Special",

        suffix = "38Special",

        round = "Base.Bullets38",

        ammoType = "base:bullets_38",
    }),
}


------------------------------------------------
-- LOOKUP
------------------------------------------------

function AC_Calibres.get(
    id
)

    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if calibre.id == id then
            return calibre
        end
    end


    return nil
end


function AC_Calibres.getPrimer(
    id
)

    for _,
        primer
    in ipairs(
        AC_Calibres.PRIMERS
    )
    do

        if primer.id == id then
            return primer
        end
    end


    return nil
end


------------------------------------------------
-- Finds what an item is in the calibre model.
-- Returns kind ("case", "bullet", "dieSet", "round",
-- "primer") and the calibre or primer definition, or
-- nil for anything else.
------------------------------------------------

function AC_Calibres.identify(
    fullType
)

    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        for _,
            kind
        in ipairs(
            { "case", "bullet", "dieSet", "round" }
        )
        do

            if calibre[kind] == fullType then
                return kind, calibre
            end
        end
    end


    for _,
        primer
    in ipairs(
        AC_Calibres.PRIMERS
    )
    do

        if primer.item == fullType then
            return "primer", primer
        end
    end


    return nil, nil
end


------------------------------------------------
-- RECIPE PARTS (vanilla tool lines, verbatim)
------------------------------------------------

local function hammer()

    return {
        count = 1,
        tags = { "base:hammer" },
        keep = true,
        flags = { "MayDegradeVeryLight" },
    }
end


local function punch()

    return {
        count = 1,
        tags = { "base:metalworkingpunch", "base:smallpunch" },
        keep = true,
        flags = { "MayDegradeLight" },
    }
end


-- A calibre's die set. Kept, never consumed. It has no
-- wear flag: the item defines no condition.
local function dieSet(calibre)

    return {
        count = 1,
        items = { calibre.dieSet },
        keep = true,
    }
end


------------------------------------------------
-- RECIPES OF ONE CALIBRE
------------------------------------------------
--
-- Four recipes, in the order a player meets them.
-- "effect" names what AC_Materials runs after the XP:
-- the case gets its quality when it is formed, the round
-- inherits it when it is assembled.
------------------------------------------------

function AC_Calibres.buildCalibreRecipes(
    calibre
)

    local primer =
        AC_Calibres.getPrimer(
            calibre.primer
        )


    local suffix =
        calibre.suffix


    return {

        -- Adapted from vanilla Forge_Small_Metalworking_Punch_Set.
        {
            id = "AmmoMaking_ForgeDieSet" .. suffix,

            calibre = calibre.id,

            step = "dieSet",

            time = calibre.time.dieSet,

            timedAction = "HammerMetalStanding",

            benchTag = "Forge",

            category = "Tools",

            callback = "onForgeDieSet" .. suffix,

            xp = calibre.xp.dieSet,

            requiredLevel = calibre.levels.dieSet,

            -- A tool, not a metal product the accounting follows.
            tool = true,

            inputs = {
                { count = 2, tags = { "base:charcoal" } },
                { count = 2, items = { "Base.SteelBarQuarter" } },
                {
                    count = 1,
                    tags = { "base:ballpeenhammer" },
                    keep = true,
                    flags = { "MayDegradeLight" },
                },
                {
                    count = 1,
                    tags = { "base:metalworkingpliers", "base:tongs" },
                    keep = true,
                    flags = { "MayDegradeLight" },
                },
                {
                    count = 1,
                    tags = { "base:whetstone", "base:file" },
                    keep = true,
                    flags = { "MayDegradeLight" },
                },
            },

            outputs = {
                { count = 1, item = calibre.dieSet },
            },
        },

        {
            id = "AmmoMaking_FormCase" .. suffix,

            calibre = calibre.id,

            step = "case",

            time = calibre.time.case,

            timedAction = "MakingHammer_Surface",

            benchTag = "AnySurfaceCraft",

            category = "Metalworking",

            callback = "onFormCase" .. suffix,

            xp = calibre.xp.case,

            requiredLevel = calibre.levels.case,

            effect = "caseQuality",

            inputs = {
                { count = 1, items = { "AmmoMaking.BrassCaseCup" } },
                dieSet(calibre),
                hammer(),
            },

            outputs = {
                { count = 1, item = calibre.case },
            },
        },

        {
            id = "AmmoMaking_SwageBullets" .. suffix,

            calibre = calibre.id,

            step = "bullet",

            time = calibre.time.bullet,

            timedAction = "MakingHammer_Surface",

            benchTag = "AnySurfaceCraft",

            category = "Metalworking",

            callback = "onSwageBullets" .. suffix,

            xp = calibre.xp.bullet,

            requiredLevel = calibre.levels.bullet,

            inputs = {
                { count = 1, items = { "Base.CopperScrap" } },
                dieSet(calibre),
                hammer(),
            },

            outputs = {
                { count = calibre.bulletsPerScrap, item = calibre.bullet },
            },
        },

        {
            id = "AmmoMaking_AssembleRound" .. suffix,

            calibre = calibre.id,

            step = "assemble",

            time = calibre.time.assemble,

            timedAction = "Making",

            benchTag = "AnySurfaceCraft",

            category = "Weaponry",

            callback = "onAssembleRound" .. suffix,

            xp = calibre.xp.assemble,

            requiredLevel = calibre.levels.assemble,

            effect = "roundQuality",

            inputs = {
                { count = 1, items = { calibre.case } },
                { count = 1, items = { primer.item } },
                { count = 1, items = { calibre.bullet } },
                { count = calibre.powderUses, items = { AC_Calibres.POWDER.item } },
                dieSet(calibre),
            },

            outputs = {
                { count = 1, item = calibre.round },
            },
        },
    }
end


------------------------------------------------
-- RECIPES SHARED BY ALL CALIBRES
------------------------------------------------
--
-- Gunpowder, and one primer recipe per primer family and
-- compound source.
------------------------------------------------

function AC_Calibres.buildSharedRecipes()

    local powder =
        AC_Calibres.POWDER


    local recipes = {

        -- Tools as in vanilla MakeAerosolBomb (mortar kept,
        -- MayDegradeLight); hand work as in GatherGunpowder.
        {
            id = "AmmoMaking_MixGunpowder",

            step = "powder",

            time = powder.time,

            timedAction = "Making",

            benchTag = "AnySurfaceCraft",

            category = "Miscellaneous",

            callback = "onMixGunpowder",

            xp = powder.xp,

            requiredLevel = powder.requiredLevel,

            -- The one recipe that brings a tracked material
            -- into existence, from charcoal and fertilizer.
            source = "powder",

            inputs = {
                { count = powder.charcoal, tags = { "base:charcoal" } },
                { count = powder.fertilizerUses, items = { powder.fertilizerItem } },
                {
                    count = 1,
                    tags = { "base:mortarpestle" },
                    keep = true,
                    flags = { "MayDegradeLight" },
                },
            },

            outputs = {
                { count = 1, item = powder.item },
            },
        },
    }


    for _,
        primer
    in ipairs(
        AC_Calibres.PRIMERS
    )
    do

        for _,
            source
        in ipairs(
            AC_Calibres.COMPOUND_SOURCES
        )
        do

            table.insert(
                recipes,
                {
                    id = "AmmoMaking_Make" .. primer.id .. "PrimersFrom" .. source.id,

                    step = "primer",

                    primer = primer.id,

                    time = primer.time,

                    timedAction = "MakingHammer_Surface",

                    benchTag = "AnySurfaceCraft",

                    category = "Metalworking",

                    callback = "onMake" .. primer.id .. "PrimersFrom" .. source.id,

                    xp = primer.xp,

                    requiredLevel = primer.requiredLevel,

                    inputs = {
                        { count = 1, items = { "AmmoMaking.SmallBrassSheet" } },
                        {
                            count = primer.perSheet * primer.compoundUnits / source.units,
                            items = source.items,
                        },
                        punch(),
                        hammer(),
                    },

                    outputs = {
                        { count = primer.perSheet, item = primer.item },
                    },
                }
            )
        end
    end


    return recipes
end


------------------------------------------------
-- All ammunition component recipes: the shared ones,
-- then each calibre's.
------------------------------------------------

function AC_Calibres.buildRecipes()

    local recipes =
        AC_Calibres.buildSharedRecipes()


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        for _,
            recipe
        in ipairs(
            AC_Calibres.buildCalibreRecipes(calibre)
        )
        do

            table.insert(
                recipes,
                recipe
            )
        end
    end


    return recipes
end


------------------------------------------------
-- MATERIAL UNITS
------------------------------------------------
--
-- item -> entry for AC_Materials.UNITS. A component of
-- one material is { metal, units }; one of several is
-- { contents = { material = units } }. For a drainable,
-- units are per use and "uses" is a full item.
--
-- A round contains exactly what goes into it, so the
-- assembly comes out even and vanilla's "gather
-- gunpowder" can only return what was put in.
------------------------------------------------

function AC_Calibres.buildUnits()

    local units = {}


    units[AC_Calibres.POWDER.item] = {
        metal = "powder",
        units = 1,
        uses = AC_Calibres.POWDER.usesPerJar,
    }


    for _,
        source
    in ipairs(
        AC_Calibres.COMPOUND_SOURCES
    )
    do

        for _,
            itemType
        in ipairs(
            source.items
        )
        do

            units[itemType] = {
                metal = "compound",
                units = source.units,
                uses = source.uses and source.uses[itemType] or nil,
            }
        end
    end


    for _,
        primer
    in ipairs(
        AC_Calibres.PRIMERS
    )
    do

        units[primer.item] = {
            contents = {
                brass = primer.brassUnits,
                compound = primer.compoundUnits,
            },
        }
    end


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local primer =
            AC_Calibres.getPrimer(
                calibre.primer
            )


        local caseUnits =
            AC_Calibres.CONFIG.cupUnits


        local bulletUnits =
            AC_Calibres.CONFIG.scrapUnits / calibre.bulletsPerScrap


        units[calibre.case] = {
            metal = "brass",
            units = caseUnits,
        }


        units[calibre.bullet] = {
            metal = "copper",
            units = bulletUnits,
        }


        units[calibre.round] = {
            contents = {
                brass = caseUnits + primer.brassUnits,
                copper = bulletUnits,
                compound = primer.compoundUnits,
                powder = calibre.powderUses,
            },
        }
    end


    return units
end


------------------------------------------------
-- ITEM IDS
------------------------------------------------
--
-- Every item the component recipes name by id (not by
-- tag), mod and vanilla, without duplicates. Used by the
-- compatibility check.
------------------------------------------------

function AC_Calibres.getItems()

    local seen = {}

    local items = {}


    local function add(
        itemType
    )

        if itemType
            and not seen[itemType]
        then

            seen[itemType] = true


            table.insert(
                items,
                itemType
            )
        end
    end


    for _,
        recipe
    in ipairs(
        AC_Calibres.buildRecipes()
    )
    do

        for _,
            input
        in ipairs(
            recipe.inputs
        )
        do

            for _,
                itemType
            in ipairs(
                input.items or {}
            )
            do

                add(itemType)
            end
        end


        for _,
            output
        in ipairs(
            recipe.outputs
        )
        do

            add(output.item)
        end
    end


    return items
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Calibre definitions loaded ("
    .. #AC_Calibres.LIST
    .. ")"
)
