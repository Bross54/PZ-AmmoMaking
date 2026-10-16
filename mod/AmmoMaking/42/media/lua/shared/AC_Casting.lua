-- Ammo Making - Lead: recovered from vanilla junk, cast into bullets
-- Project Zomboid Build 42.20
--
-- A second projectile metal, cheaper than copper, for the
-- pistol calibres and buckshot (docs/METALLURGY_DESIGN.md
-- 12, docs/AMMUNITION_DESIGN.md 6.1):
--
--   Base.LeadPipe, Base.JigLure
--        |  Melt Lead from ...        Primitive Furnace,
--        |  (kept crucible, tongs)    1 charcoal, 0 XP
--        v
--   AmmoMaking.LeadScrap (10 units of lead)
--        |  Cast <calibre> Lead Bullets
--        |  Primitive Furnace, 1 charcoal, kept crucible,
--        |  tongs and the class's bullet mould
--        v
--   AmmoMaking.CastBullet<suffix> (or the lead shot charge)
--        |  Assemble <calibre> Round (Cast Bullet)
--        v
--   the same vanilla round as the copper recipe makes
--
-- What vanilla 42.20.4 has, read in the installed files
-- (FILE, media/scripts/generated/items/):
--
--   Base.LeadPipe  "Lead Pipe", weapon.txt: a base:weapon,
--                  Weight 1.5, Tags base:hasmetal;
--                  base:nomaintenancexp;base:killanimal.
--                  No vanilla recipe consumes it.
--   Base.JigLure   "Jig Lure", normal.txt: a base:normal
--                  fishing lure, Weight 0.1. No vanilla
--                  recipe consumes it.
--
-- and what it does NOT have: no lead ingot, scrap or ore,
-- no sinker or wheel weight, no bullet mould, no lead tag
-- (grep of items/, recipes/, entities/ and registries).
-- Car batteries hold lead but are drainables (UseDelta
-- 0.00001: a recipe line would count one use of charge,
-- not the battery) and a scarce vehicle part; they are not
-- a source.
--
-- The furnace lines are vanilla's own: the kept empty
-- crucible and tongs of ExtractIronFromSmallItem
-- (recipes_blacksmith_furnaces_i.txt, Tags =
-- PrimitiveFurnace), whose junk line is also
-- "mode:destroy flags[...AllowDestroyedItem]"; the mould
-- forging copies the die set's (Forge_Small_Metalworking
-- _Punch_Set).
--
-- Every calibre fact comes from AC_Calibres: which classes
-- have a mould (CLASSES[class].mould) and each calibre's
-- castBullet. Nothing here names a calibre. Rifles have no
-- mould and keep copper (the reason is beside CLASSES).
--
-- The balance rules, enforced by validate() and the tests:
--
--   RECOVERY TEACHES NOTHING. Melting junk awards 0 XP.
--   CASTING PAYS WHAT SWAGING PAYS. A cast bullet has the
--     swaged bullet's level, XP and time; its round the
--     copper round's. Lead changes where the metal comes
--     from, never what a level opens or what a craft
--     earns.
--   SAME METAL PER BULLET. One lead scrap makes as many
--     bullets as one copper scrap (bulletsPerScrap).
--   NO WAY BACK. No recipe turns a cast bullet, or a round,
--     into lead again (vanilla's Gather Gunpowder returns
--     powder only).
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the recipes
-- appear at a Primitive Furnace and a Forge, take what
-- they say (a broken lead pipe included) and keep the
-- crucible, tongs and mould.

require "AC_Calibres"

AC_Casting = AC_Casting or {}


------------------------------------------------
-- CONFIG (tunable)
------------------------------------------------
--
-- scrapUnits must equal a copper scrap's
-- (AC_Calibres.CONFIG.scrapUnits): a cast bullet holds the
-- lead a swaged bullet holds in copper.
--
-- Charcoal: one per melt and one per cast, the amount of
-- vanilla's own small-item melt. Time: 200 for a melt
-- (every vanilla furnace recipe); a cast takes the
-- calibre's bullet time.
------------------------------------------------

AC_Casting.CONFIG = {

    metal = "lead",

    scrapItem = "AmmoMaking.LeadScrap",

    scrapUnits = 10,

    benchTag = "PrimitiveFurnace",

    category = "Blacksmithing",

    recoverTime = 200,

    recoverCharcoal = 1,

    -- Melting junk teaches nothing. validate() refuses any
    -- other value.
    recoverXp = 0,

    recoverLevel = 0,

    castCharcoal = 1,

    -- The moulds: forged like a die set, from iron instead
    -- of steel (a mould only holds molten lead; a die is
    -- struck). A mould pays per cast, as a kit pays per
    -- assay, so forging one awards nothing.
    mouldBenchTag = "Forge",

    mouldTimedAction = "HammerMetalStanding",

    mouldCategory = "Tools",

    mouldTime = 300,

    mouldBarItem = "Base.IronBarQuarter",

    mouldBars = 2,

    mouldCharcoal = 2,

    mouldXp = 0,

    idPrefix = "AmmoMaking_",
}


------------------------------------------------
-- SOURCES (tunable)
------------------------------------------------
--
-- Vanilla items that are mostly lead. A melt takes count
-- of them and gives scrap lead scrap; never more lead
-- scrap weight (0.5 each) than the items weigh, which the
-- tests check against the installed game's weights:
--
--   Lead Pipe   1.5   ->  2 scrap (1.0): the fittings and
--                         the dross are lost
--   Jig Lure    5 x 0.1 -> 1 scrap (0.5): a jig is a lead
--                         head on a hook
--
-- destroy and flags follow vanilla's junk-melting line, so
-- a broken pipe melts as well as a whole one.
------------------------------------------------

AC_Casting.SOURCES = {

    {
        id = "LeadPipe",

        items = { "Base.LeadPipe" },

        count = 1,

        scrap = 2,

        destroy = true,

        flags = { "AllowDestroyedItem" },
    },

    {
        id = "JigLures",

        items = { "Base.JigLure" },

        count = 5,

        scrap = 1,
    },
}


------------------------------------------------
-- The copper step whose level, XP and time each cast
-- step of a calibre takes (the rule "casting pays what
-- swaging pays").
------------------------------------------------

AC_Casting.STEP_OF = {

    cast = "bullet",

    assembleCast = "assemble",
}


------------------------------------------------
-- RECIPE PARTS (vanilla lines, verbatim)
------------------------------------------------

local function crucible()

    return {
        count = 1,
        items = { "Base.CeramicCrucible" },
        keep = true,
        flags = { "IsEmpty" },
    }
end


local function tongs()

    return {
        count = 1,
        tags = { "base:crudetongs", "base:tongs" },
        keep = true,
        flags = { "MayDegradeLight" },
    }
end


local function charcoal(
    count
)

    return {
        count = count,
        tags = { "base:charcoal" },
    }
end


-- "AmmoMaking.BulletMouldPistol" -> "BulletMouldPistol"
local function shortName(
    itemType
)

    return
        string.match(
            tostring(itemType),
            "([^%.]+)$"
        )
end


------------------------------------------------
-- MOULDS
------------------------------------------------
--
-- One per class that has one, in the order the classes
-- first appear in AC_Calibres.LIST: { class, item, level,
-- calibres }. level is the lowest bullet level of the
-- class's castable calibres: a mould is met when the
-- first bullet it casts opens.
------------------------------------------------

function AC_Casting.getMoulds()

    local moulds = {}

    local byClass = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local class =
            AC_Calibres.CLASSES[calibre.class] or {}


        if class.mould
            and calibre.castBullet
        then

            local mould =
                byClass[calibre.class]


            if not mould then

                mould = {
                    class = calibre.class,
                    item = class.mould,
                    level = calibre.levels.bullet,
                    calibres = {},
                }


                byClass[calibre.class] = mould


                table.insert(
                    moulds,
                    mould
                )
            end


            mould.level =
                math.min(
                    mould.level,
                    calibre.levels.bullet
                )


            table.insert(
                mould.calibres,
                calibre.id
            )
        end
    end


    return moulds
end


function AC_Casting.getMould(
    className
)

    for _,
        mould
    in ipairs(
        AC_Casting.getMoulds()
    )
    do

        if mould.class == className then
            return mould
        end
    end


    return nil
end


-- The calibres that can be cast, in LIST order.
function AC_Casting.getCastable()

    local castable = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if calibre.castBullet then

            table.insert(
                castable,
                calibre
            )
        end
    end


    return castable
end


------------------------------------------------
-- WHAT A ROUND HOLDS when its bullet is lead: the copper
-- round's contents with the projectile's copper turned to
-- lead, unit for unit. The vanilla round item is the same
-- either way, so the assembly recipe states what it made
-- (output.contents, read by AC_Materials.getRecipeUnits).
------------------------------------------------

function AC_Casting.castRoundContents(
    calibre
)

    local entry =
        AC_Calibres.buildUnits()[calibre.round]


    local contents = {}


    for material,
        units
    in pairs(
        entry and entry.contents or {}
    )
    do

        contents[material] = units
    end


    contents[AC_Casting.CONFIG.metal] =
        contents.copper


    contents.copper = nil


    return contents
end


------------------------------------------------
-- RECIPES
------------------------------------------------
--
-- In order: one melt per source, one mould per class,
-- then per castable calibre its cast and its assembly.
-- step is "leadSource", "mould", "cast" or
-- "assembleCast"; the tests and the recipe audit group
-- by it.
------------------------------------------------

function AC_Casting.buildSourceRecipes()

    local config =
        AC_Casting.CONFIG


    local recipes = {}


    for _,
        source
    in ipairs(
        AC_Casting.SOURCES
    )
    do

        table.insert(
            recipes,
            {
                id = config.idPrefix .. "MeltLeadFrom" .. source.id,

                step = "leadSource",

                time = config.recoverTime,

                benchTag = config.benchTag,

                category = config.category,

                callback = "onMeltLeadFrom" .. source.id,

                xp = config.recoverXp,

                requiredLevel = config.recoverLevel,

                -- The one recipe kind that brings lead into the
                -- accounting, from untracked vanilla junk.
                source = config.metal,

                inputs = {
                    crucible(),
                    tongs(),
                    charcoal(config.recoverCharcoal),
                    {
                        count = source.count,
                        items = source.items,
                        destroy = source.destroy,
                        flags = source.flags,
                    },
                },

                outputs = {
                    { count = source.scrap, item = config.scrapItem },
                },
            }
        )
    end


    return recipes
end


function AC_Casting.buildMouldRecipes()

    local config =
        AC_Casting.CONFIG


    local recipes = {}


    for _,
        mould
    in ipairs(
        AC_Casting.getMoulds()
    )
    do

        local name =
            shortName(mould.item)


        table.insert(
            recipes,
            {
                id = config.idPrefix .. "Forge" .. name,

                step = "mould",

                class = mould.class,

                time = config.mouldTime,

                timedAction = config.mouldTimedAction,

                benchTag = config.mouldBenchTag,

                category = config.mouldCategory,

                callback = "onForge" .. name,

                xp = config.mouldXp,

                requiredLevel = mould.level,

                -- A tool, not a metal product the accounting
                -- follows.
                tool = true,

                inputs = {
                    charcoal(config.mouldCharcoal),
                    { count = config.mouldBars, items = { config.mouldBarItem } },
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
                    { count = 1, item = mould.item },
                },
            }
        )
    end


    return recipes
end


-- The two recipes of one castable calibre.
function AC_Casting.buildCalibreRecipes(
    calibre
)

    local config =
        AC_Casting.CONFIG


    local class =
        AC_Calibres.CLASSES[calibre.class] or {}


    if not calibre.castBullet
        or not class.mould
    then
        return {}
    end


    local suffix =
        calibre.suffix


    local cast = {

        id = config.idPrefix .. "CastBullets" .. suffix,

        calibre = calibre.id,

        step = "cast",

        time = calibre.time.bullet,

        benchTag = config.benchTag,

        category = config.category,

        callback = "onCastBullets" .. suffix,

        xp = calibre.xp.bullet,

        requiredLevel = calibre.levels.bullet,

        inputs = {
            crucible(),
            tongs(),
            charcoal(config.castCharcoal),
            { count = 1, items = { config.scrapItem } },
            { count = 1, items = { class.mould }, keep = true },
        },

        outputs = {
            { count = calibre.bulletsPerScrap, item = calibre.castBullet },
        },
    }


    -- The copper assembly with its bullet line swapped:
    -- every other line, the level, XP, time and the
    -- round-quality effect are the copper recipe's own.
    local hand = nil


    for _,
        recipe
    in ipairs(
        AC_Calibres.buildCalibreRecipes(calibre)
    )
    do

        if recipe.step == "assemble" then
            hand = recipe
        end
    end


    local inputs = {}


    for _,
        input
    in ipairs(
        hand.inputs
    )
    do

        if input.items
            and input.items[1] == calibre.bullet
        then

            table.insert(
                inputs,
                { count = input.count, items = { calibre.castBullet } }
            )

        else

            table.insert(
                inputs,
                input
            )
        end
    end


    local assemble = {

        id = config.idPrefix .. "AssembleCastRound" .. suffix,

        calibre = calibre.id,

        step = "assembleCast",

        handRecipe = hand.id,

        time = hand.time,

        timedAction = hand.timedAction,

        benchTag = hand.benchTag,

        category = hand.category,

        callback = "onAssembleCastRound" .. suffix,

        xp = hand.xp,

        requiredLevel = hand.requiredLevel,

        effect = hand.effect,

        inputs = inputs,

        outputs = {
            {
                count = 1,
                item = calibre.round,
                contents = AC_Casting.castRoundContents(calibre),
            },
        },
    }


    return { cast, assemble }
end


function AC_Casting.buildRecipes()

    local recipes =
        AC_Casting.buildSourceRecipes()


    for _,
        recipe
    in ipairs(
        AC_Casting.buildMouldRecipes()
    )
    do

        table.insert(
            recipes,
            recipe
        )
    end


    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        for _,
            recipe
        in ipairs(
            AC_Casting.buildCalibreRecipes(calibre)
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
-- item -> entry for AC_Materials.UNITS: the lead scrap
-- and every cast bullet. The round is not here: it is the
-- vanilla item and keeps its copper entry; the cast
-- assembly says what it made (castRoundContents).
------------------------------------------------

function AC_Casting.buildUnits()

    local config =
        AC_Casting.CONFIG


    local units = {

        [config.scrapItem] = {
            metal = config.metal,
            units = config.scrapUnits,
        },
    }


    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        units[calibre.castBullet] = {
            metal = config.metal,
            units = config.scrapUnits / calibre.bulletsPerScrap,
        }
    end


    return units
end


------------------------------------------------
-- ITEM IDS: every item the recipes name by id, mod and
-- vanilla, once. For the compatibility check.
------------------------------------------------

function AC_Casting.getItems()

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
        AC_Casting.buildRecipes()
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
-- VALIDATION (pure)
------------------------------------------------
--
-- Returns a list of problems, each "casting: text", empty
-- when the model is sound. Run by the tests and by the
-- compatibility check at game start.
------------------------------------------------

local function isWhole(
    value,
    minimum
)

    return
        type(value) == "number"
        and value == math.floor(value)
        and value >= minimum
end


function AC_Casting.validate()

    local config =
        AC_Casting.CONFIG


    local problems = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "casting: " .. text
        )
    end


    if config.scrapUnits ~= AC_Calibres.CONFIG.scrapUnits then
        problem("a lead scrap must hold what a copper scrap holds (" .. tostring(AC_Calibres.CONFIG.scrapUnits) .. ")")
    end


    if config.recoverXp ~= 0 then
        problem("melting junk must teach nothing")
    end


    if not isWhole(config.mouldXp, 0)
        or config.mouldXp > AC_Calibres.DEFAULTS.xp.dieSet
    then
        problem("a mould may pay no more XP than a die set")
    end


    for _,
        key
    in ipairs(
        { "recoverCharcoal", "castCharcoal", "mouldBars", "mouldCharcoal" }
    )
    do

        if not isWhole(config[key], 1) then
            problem(key .. " must be a whole number of at least 1")
        end
    end


    local ids = {}


    for index,
        source
    in ipairs(
        AC_Casting.SOURCES
    )
    do

        local label =
            "source " .. tostring(source.id or index)


        if type(source.id) ~= "string"
            or source.id == ""
            or string.find(source.id, "[^%w]")
        then

            problem(label .. ": the id must be letters and digits")

        elseif ids[source.id] then

            problem(label .. ": named twice")
        end


        ids[tostring(source.id)] = true


        if type(source.items) ~= "table"
            or #source.items == 0
        then

            problem(label .. ": names no item")

        else

            for _,
                itemType
            in ipairs(
                source.items
            )
            do

                if string.sub(tostring(itemType), 1, 5) ~= "Base." then
                    problem(label .. ": " .. tostring(itemType) .. " is not a vanilla item")
                end


                -- Never something the mod makes: lead may not
                -- come back out of the chain.
                if AC_Calibres.identify(itemType) ~= nil then
                    problem(label .. ": " .. tostring(itemType) .. " is a component of the mod")
                end
            end
        end


        if not isWhole(source.count, 1)
            or not isWhole(source.scrap, 1)
        then
            problem(label .. ": count and scrap must be whole and at least 1")
        end
    end


    -- Every mould casts something.
    for className,
        class
    in pairs(
        AC_Calibres.CLASSES
    )
    do

        -- That a mould belongs to one class is
        -- AC_Calibres.validate()'s rule.
        if class.mould then

            if not AC_Casting.getMould(className) then
                problem("class " .. className .. " has a mould and no calibre to cast")
            end
        end
    end


    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        if not isWhole(config.scrapUnits / calibre.bulletsPerScrap, 1) then
            problem(tostring(calibre.id) .. ": its bullets do not divide a lead scrap into whole units")
        end
    end


    return problems
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Lead casting loaded ("
    .. #AC_Casting.getCastable()
    .. " castable calibres)"
)
