-- Ammo Making - Lead: recovered from vanilla junk, cast into bullets
-- Project Zomboid Build 42.20
--
-- A second projectile metal, cheaper than copper, for every
-- calibre; a rifle's cast bullet takes a copper gas check
-- (docs/METALLURGY_DESIGN.md
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
-- castBullet. Nothing here names a calibre. A rifle's cast
-- round takes a gas check (the reason is beside CLASSES).
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
-- MOULD MATERIALS (tunable)
------------------------------------------------
--
-- What a bullet mould is made of decides how good its
-- bullets are and how long it lasts. The forged iron
-- mould is the reference; the other three need no forge
-- and give worse bullets:
--
--   iron   forged at a Forge; kept, wears very
--          slowly like a die set (MayDegradeVeryLight,
--          some 900 casts)                           +0
--   stone  carved from a vanilla stone block with a
--          hammer and a chisel (the lines of vanilla's
--          Make_Stone_Block_from_Stone); kept, wears
--          like a tool (MayDegradeLight)             -5
--   clay   shaped from dug clay with a knife, fired in
--          a kiln (the lines of vanilla's
--          FireClayIngotMold); kept, but tagged
--          base:breakonsmithing like vanilla's clay
--          ingot mould, so one cast breaks it        -10
--   sand   rammed from one use of a sandbag with clay as
--          the binder; consumed by its one cast      -20
--
-- qualityBonus is added to the cast bullet's quality
-- roll (AC_CaseQuality.roll, the case's roll), and a
-- round assembled from a cast bullet averages it with its
-- case (AC_CaseQuality.CONFIG.projectileShare). XP, level,
-- time and metal of a cast are the same in every mould:
-- the material changes quality and durability only.
--
-- The one-cast break: processKeepInputItem of the class
-- CraftRecipeData sets condition 0 on a kept item tagged
-- base:breakonsmithing when CraftRecipe.isSmithing() is
-- true, which is category Blacksmithing (javap, 42.20.4);
-- the casts are Blacksmithing.
--
-- prefix makes the item ids: prefix .. the iron mould's
-- name ("AmmoMaking.StoneBulletMouldPistol"); a fired clay
-- mould has an "Unfired" twin.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: the kiln firing,
-- the clay mould breaking after one cast, the stone
-- mould's wear.
------------------------------------------------

AC_Casting.MOULD_MATERIALS = {

    {
        id = "iron",
        qualityBonus = 0,
        keep = true,
        flags = { "MayDegradeVeryLight" },
        -- 10 x (15 x 6 + level + Maintenance): some 900
        -- casts, the die set's numbers (AC_Calibres.DIE_WEAR).
        conditionMax = 10,
        conditionLowerChanceOneIn = 15,
    },

    {
        id = "stone",
        prefix = "Stone",
        qualityBonus = -5,
        keep = true,
        flags = { "MayDegradeLight" },
        -- The item script's two wear numbers (the tests
        -- compare): 10 x (10 x 3 + level + Maintenance),
        -- some 300 casts.
        conditionMax = 10,
        conditionLowerChanceOneIn = 10,
    },

    { id = "clay", prefix = "Clay", qualityBonus = -10, keep = true, unfired = true },

    { id = "sand", prefix = "Sand", qualityBonus = -20, keep = false },
}


------------------------------------------------
-- GAS CHECKS (tunable)
------------------------------------------------
--
-- A rifle's cast bullet (a class with gasCheck) takes a
-- gas check at assembly: a copper cup punched from scrap
-- cold on a surface, the cup-punching lines of the brass
-- case cups (punch and hammer kept). perScrap of them
-- from one copper scrap; each holds scrapUnits /
-- perScrap of copper, which the cast round's contents
-- carry. No XP: it is a part of the rifle's cast round,
-- whose assembly pays.
------------------------------------------------

AC_Casting.GAS_CHECK = {

    item = "AmmoMaking.GasCheck",

    scrapItem = "Base.CopperScrap",

    perScrap = 10,

    time = 80,

    timedAction = "MakingHammer_Surface",

    benchTag = "AnySurfaceCraft",

    category = "Metalworking",

    id = "AmmoMaking_PunchGasChecks",

    callback = "onPunchGasChecks",
}


-- The copper in one gas check.
function AC_Casting.gasCheckUnits()

    return
        AC_Casting.CONFIG.scrapUnits
        / AC_Casting.GAS_CHECK.perScrap
end


-- Does any castable calibre need a gas check?
function AC_Casting.needsGasChecks()

    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        if (AC_Calibres.CLASSES[calibre.class] or {}).gasCheck then
            return true
        end
    end


    return false
end


-- The gas check recipe, at the level of the first
-- calibre that needs one; nil when none does.
function AC_Casting.buildGasCheckRecipe()

    local gas =
        AC_Casting.GAS_CHECK


    local level = nil


    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        if (AC_Calibres.CLASSES[calibre.class] or {}).gasCheck then

            level =
                math.min(
                    level or 10,
                    calibre.levels.bullet
                )
        end
    end


    if not level then
        return nil
    end


    return {
        id = gas.id,
        step = "gasCheck",
        time = gas.time,
        timedAction = gas.timedAction,
        benchTag = gas.benchTag,
        category = gas.category,
        callback = gas.callback,
        xp = 0,
        requiredLevel = level,
        inputs = {
            { count = 1, items = { gas.scrapItem } },
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
            { count = gas.perScrap, item = gas.item },
        },
    }
end


------------------------------------------------
-- BULLET LUBE (tunable)
------------------------------------------------
--
-- A cast lead bullet is sized and lubed before it is
-- loaded: wax in its grooves keeps the lead from smearing
-- in the bore. Here: a few cast bullets and some uses of
-- a vanilla candle (Base.Candle, items/normal.txt: a
-- drainable of 333 uses, UseDelta 0.003; vanilla's
-- LightCandle takes it by id) give the same bullets back,
-- each qualityBonus better, once: a lubed bullet is
-- marked and lubing it again changes nothing. No XP
-- (nothing new is made), the calibre's bullet level.
------------------------------------------------

AC_Casting.LUBE = {

    item = "Base.Candle",

    uses = 10,

    bullets = 5,

    qualityBonus = 5,

    time = 60,

    timedAction = "Making",

    benchTag = "AnySurfaceCraft",

    category = "Weaponry",
}


-- The material entry by id, or nil.
function AC_Casting.getMouldMaterial(
    materialId
)

    for _,
        material
    in ipairs(
        AC_Casting.MOULD_MATERIALS
    )
    do

        if material.id == materialId then
            return material
        end
    end


    return nil
end


-- The items of one class's mould in one material:
-- { item, unfired }. iron is the class's own mould.
function AC_Casting.getMouldItems(
    className,
    materialId
)

    local class =
        AC_Calibres.CLASSES[className] or {}


    local material =
        AC_Casting.getMouldMaterial(materialId)


    if not class.mould
        or not material
    then
        return nil
    end


    if not material.prefix then
        return { item = class.mould }
    end


    local module,
          name =
        string.match(
            class.mould,
            "^(.-)%.([^%.]+)$"
        )


    local item =
        module .. "." .. material.prefix .. name


    return {
        item = item,
        unfired = material.unfired and (item .. "Unfired") or nil,
    }
end


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


    -- A rifle's cast round keeps a little copper: its
    -- gas check.
    if (AC_Calibres.CLASSES[calibre.class] or {}).gasCheck then

        contents.copper =
            AC_Casting.gasCheckUnits()
    end


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


    for _,
        mould
    in ipairs(
        AC_Casting.getMoulds()
    )
    do

        for _,
            recipe
        in ipairs(
            AC_Casting.buildMaterialMouldRecipes(mould)
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


-- The stone, clay and sand moulds of one class, in the
-- order of MOULD_MATERIALS. Vanilla lines throughout:
--
--   stone  Make_Stone_Block_from_Stone
--          (recipes_stonemasonry_i.txt): HammerStoneStanding,
--          AnySurfaceCraft, the hammer and chisel lines
--   clay   PressClayBrickManually (recipes_pottery.txt):
--          Making, AnySurfaceCraft, Base.Clay in; the
--          knife line of the leather recipes
--          (recipes_leather_prep.txt); then
--          FireClayIngotMold (craftrecipe_kiln.txt):
--          Making_With_Kiln, KilnSmall;KilnLarge, a fire
--          starter and a log or charcoal
--   sand   MeltSand (recipes_blacksmith_furnace_ii.txt):
--          one use of Base.Sandbag, with a clay binder
--
-- Like the forged mould, a mould pays nothing when made.
function AC_Casting.buildMaterialMouldRecipes(
    mould
)

    local config =
        AC_Casting.CONFIG


    local recipes = {}


    local function knife()

        return {
            count = 1,
            tags = { "base:sharpknife" },
            keep = true,
            flags = { "IsNotDull", "MayDegradeLight" },
        }
    end


    local function add(
        recipe
    )

        recipe.class = mould.class

        recipe.xp = config.mouldXp

        recipe.requiredLevel = mould.level

        recipe.tool = true

        table.insert(
            recipes,
            recipe
        )
    end


    local stone =
        AC_Casting.getMouldItems(mould.class, "stone")


    local stoneName =
        shortName(stone.item)


    add({
        id = config.idPrefix .. "Carve" .. stoneName,
        step = "mould",
        material = "stone",
        time = 300,
        timedAction = "HammerStoneStanding",
        benchTag = "AnySurfaceCraft",
        category = "Masonry",
        callback = "onCarve" .. stoneName,
        inputs = {
            {
                count = 1,
                tags = { "base:hammer", "base:clubhammer" },
                keep = true,
                flags = { "MayDegradeLight", "Prop1" },
            },
            {
                count = 1,
                tags = { "base:crudechisel", "base:masonschisel" },
                keep = true,
                flags = { "MayDegradeLight", "Prop2" },
            },
            { count = 1, items = { "Base.StoneBlock" } },
        },
        outputs = {
            { count = 1, item = stone.item },
        },
    })


    local clay =
        AC_Casting.getMouldItems(mould.class, "clay")


    local clayName =
        shortName(clay.item)


    add({
        id = config.idPrefix .. "Shape" .. clayName,
        step = "mould",
        material = "clay",
        time = 120,
        timedAction = "Making",
        benchTag = "AnySurfaceCraft",
        category = "Pottery",
        callback = "onShape" .. clayName,
        inputs = {
            { count = 2, items = { "Base.Clay" } },
            knife(),
        },
        outputs = {
            { count = 1, item = clay.unfired },
        },
    })


    add({
        id = config.idPrefix .. "Fire" .. clayName,
        step = "mould",
        material = "clay",
        time = 20,
        timedAction = "Making_With_Kiln",
        benchTag = "KilnSmall;KilnLarge",
        category = "Pottery",
        callback = "onFire" .. clayName,
        inputs = {
            { count = 1, items = { clay.unfired } },
            { count = 1, tags = { "base:startfire" } },
            { count = 1, tags = { "base:log", "base:charcoal" } },
        },
        outputs = {
            { count = 1, item = clay.item },
        },
    })


    local sand =
        AC_Casting.getMouldItems(mould.class, "sand")


    local sandName =
        shortName(sand.item)


    add({
        id = config.idPrefix .. "Ram" .. sandName,
        step = "mould",
        material = "sand",
        time = 60,
        timedAction = "Making",
        benchTag = "AnySurfaceCraft",
        category = "Pottery",
        callback = "onRam" .. sandName,
        inputs = {
            { count = 1, items = { "Base.Sandbag" } },
            { count = 1, items = { "Base.Clay" } },
            knife(),
        },
        outputs = {
            { count = 1, item = sand.item },
        },
    })


    return recipes
end


-- The recipes of one castable calibre: a cast per mould
-- material, then the assembly.
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


    -- One cast per mould material. The iron cast keeps the
    -- id it always had; the others name their mould. Only
    -- the mould line, the id and the quality differ.
    local casts = {}


    for _,
        material
    in ipairs(
        AC_Casting.MOULD_MATERIALS
    )
    do

        local mouldItems =
            AC_Casting.getMouldItems(calibre.class, material.id)


        local tail =
            material.prefix
            and ("In" .. material.prefix .. "Mould")
            or ""


        table.insert(
            casts,
            {

                id = config.idPrefix .. "CastBullets" .. suffix .. tail,

                calibre = calibre.id,

                step = "cast",

                material = material.id,

                qualityBonus = material.qualityBonus + (class.castQualityBonus or 0),

                effect = "castBulletQuality",

                time = calibre.time.bullet,

                benchTag = config.benchTag,

                category = config.category,

                callback = "onCastBullets" .. suffix .. tail,

                xp = calibre.xp.bullet,

                requiredLevel = calibre.levels.bullet,

                inputs = {
                    crucible(),
                    tongs(),
                    charcoal(config.castCharcoal),
                    { count = 1, items = { config.scrapItem } },
                    {
                        count = 1,
                        items = { mouldItems.item },
                        keep = material.keep or nil,
                        flags = material.flags,
                    },
                },

                outputs = {
                    { count = calibre.bulletsPerScrap, item = calibre.castBullet },
                },
            }
        )
    end


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


    if class.gasCheck then

        table.insert(
            inputs,
            { count = 1, items = { AC_Casting.GAS_CHECK.item } }
        )
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


    table.insert(
        casts,
        assemble
    )


    return casts
end


-- One lube recipe per castable calibre.
function AC_Casting.buildLubeRecipes()

    local config =
        AC_Casting.CONFIG


    local lube =
        AC_Casting.LUBE


    local recipes = {}


    for _,
        calibre
    in ipairs(
        AC_Casting.getCastable()
    )
    do

        table.insert(
            recipes,
            {
                id = config.idPrefix .. "LubeCastBullets" .. calibre.suffix,
                calibre = calibre.id,
                step = "lube",
                -- A treatment: the same item back, better, for
                -- no XP; not a step of the chain.
                treatment = true,
                effect = "lubeCastBullets",
                time = lube.time,
                timedAction = lube.timedAction,
                benchTag = lube.benchTag,
                category = lube.category,
                callback = "onLubeCastBullets" .. calibre.suffix,
                xp = 0,
                requiredLevel = calibre.levels.bullet,
                inputs = {
                    { count = lube.bullets, items = { calibre.castBullet } },
                    { count = lube.uses, items = { lube.item } },
                },
                outputs = {
                    { count = lube.bullets, item = calibre.castBullet },
                },
            }
        )
    end


    return recipes
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


    local gasCheck =
        AC_Casting.buildGasCheckRecipe()


    if gasCheck then

        table.insert(
            recipes,
            gasCheck
        )
    end


    for _,
        recipe
    in ipairs(
        AC_Casting.buildLubeRecipes()
    )
    do

        table.insert(
            recipes,
            recipe
        )
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


    if AC_Casting.needsGasChecks() then

        units[AC_Casting.GAS_CHECK.item] = {
            metal = "copper",
            units = AC_Casting.gasCheckUnits(),
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
