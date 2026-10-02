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
--   buildPressRecipes()
--                   the same steps at the future reloading
--                   press; prepared, switched off (PRESS)
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
-- Tunable. Metal amounts are in the units of
-- AC_Materials (100 per ingot, 10 per scrap or small
-- sheet, 5 per case cup).
--
-- Every balance number of the ammunition stage lives in
-- this file: CONFIG, POWDER, COMPOUND_SOURCES, PRIMERS,
-- DEFAULTS, CLASSES and LIST. The recipe script and the
-- balance tables of docs/AMMUNITION_DESIGN.md are
-- generated from them, and the tests derive what they
-- expect from them.
------------------------------------------------

AC_Calibres.CONFIG = {

    -- Brass in one case cup. A case is drawn from one cup,
    -- or from more for the largest calibres (cupsPerCase).
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
-- A primer belongs to a family, not to a calibre. Each
-- calibre names its family (calibre.primerFamily); no
-- recipe code names a primer item.
--
--   SmallPistol  9mm, .38 Special, .357 Magnum
--   LargePistol  .45 ACP, .44 Magnum
--   SmallRifle   5.56
--   LargeRifle   .308, .30-30
--
-- All are made the same way: one small brass sheet and a
-- priming charge of toy caps or match heads. A large
-- primer holds twice the brass and twice the compound of
-- the small one, so the sheet yields half as many. A
-- rifle primer is the pistol primer of its size with half
-- as much compound again. No family is cheaper per unit
-- of material than another, and no recipe accepts another
-- family's primer. "class" ties a family to pistol or
-- rifle calibres: a rifle round may not name a pistol
-- primer family, nor the other way round.
--
-- A 12 gauge shell takes the LargePistol primer: an
-- all-brass hull is primed that way, and a fifth family
-- would be one more item and two more recipes that play
-- exactly like the large pistol ones. The shotgun class
-- says so itself (CLASSES.shotgun.primerClass); no other
-- class may borrow a family.
------------------------------------------------

AC_Calibres.PRIMERS = {

    {
        id = "SmallPistol",

        class = "pistol",

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

    {
        id = "LargePistol",

        class = "pistol",

        item = "AmmoMaking.LargePistolPrimer",

        brassUnits = 2,

        compoundUnits = 4,

        perSheet = 5,

        requiredLevel = 3,

        xp = 2,

        time = 120,
    },

    {
        id = "SmallRifle",

        class = "rifle",

        item = "AmmoMaking.SmallRiflePrimer",

        brassUnits = 1,

        compoundUnits = 3,

        perSheet = 10,

        requiredLevel = 4,

        xp = 3,

        time = 150,
    },

    {
        id = "LargeRifle",

        class = "rifle",

        item = "AmmoMaking.LargeRiflePrimer",

        brassUnits = 2,

        compoundUnits = 6,

        perSheet = 5,

        requiredLevel = 4,

        xp = 3,

        time = 150,
    },
}


------------------------------------------------
-- CALIBRES
------------------------------------------------
--
-- id       shown in debug labels and logs
-- class    "pistol" (default), "rifle" or "shotgun": which
--          CLASSES entry supplies the values a definition
--          leaves out. Nothing else branches on it.
-- suffix   used in item and recipe ids (letters and
--          digits only)
-- round    the vanilla cartridge item the assembly makes
-- ammoType the vanilla weapon AmmoType, for reference
-- box, roundsPerBox
--          the vanilla box item of the round and how many
--          it holds, as vanilla's own place_ammo_in_box
--          recipe has them. Reference only: the mod adds
--          no box recipe, because that recipe takes the
--          rounds by item type and a handloaded round IS
--          the vanilla item. The compatibility check
--          probes the box, so a build that renames one is
--          reported (docs/LOOT_AND_RECYCLING.md, 3).
-- case, bullet, dieSet
--          the calibre's three mod items; when left out
--          they are AmmoMaking.Case<suffix>,
--          AmmoMaking.Bullet<suffix>, AmmoMaking.DieSet<suffix>
-- primerFamily
--          a PRIMERS id
-- cupsPerCase
--          brass case cups drawn into one case
-- bulletsPerScrap
--          copper bullets swaged from one Base.CopperScrap
-- wads     pieces of wadding per round (shells only)
-- lootTier how rare the calibre's die set is as loot: a
--          key of AC_Loot.CONFIG.tierWeight ("common",
--          "uncommon", "rare"). Crafting is unaffected.
-- powderUses
--          uses of Base.GunPowder per round: the charge.
--          A whole number, never below 1: the engine has
--          no fractional uses, and vanilla returns one
--          use when a round is taken apart, so less
--          would create powder.
-- assembleLevel
--          Ammo Making level of the finished round. The
--          earlier steps are derived from it (levelsFor);
--          "levels" may still override any single step.
-- xp, time per step
--
-- Anything a definition leaves out comes from its class,
-- then from DEFAULTS, so a new calibre states only what
-- makes it different.
--
-- MATERIAL SCALE (gameplay units, not grains; tunable).
-- The standard pistol round is the baseline: one cup of
-- brass, half a scrap of copper, one charge. A heavy
-- bullet takes a whole scrap, a magnum takes more
-- powder, the largest case takes two cups:
--
--              cups  bullets/scrap  charges  primer
--   9mm          1        2            1     small
--   .38 Special  1        2            1     small
--   .45 ACP      1        1            1     large
--   .357 Magnum  1        2            2     small
--   .44 Magnum   2        1            3     large
--
-- Rifle rounds are the next tier: bottleneck cases take
-- two or three cups, and the powder scale is compressed
-- (a literal .308 charge would be nine uses, nearly a
-- jar per round):
--
--   5.56         2        2            3     small rifle
--   .30-30       2        1            4     large rifle
--   .308         3        1            5     large rifle
--
-- The shell sits between the two tiers: as much brass
-- as a .308, the charge and primer of a .44 Magnum, a
-- whole scrap of shot, and a wad:
--
--   12 Gauge     3        1            3     large pistol
--
-- Rifles are made by hand with the same kind of die set
-- as pistols; what sets them apart is level, time,
-- material and powder, not a quality penalty. A future
-- press takes the same die sets.
------------------------------------------------

------------------------------------------------
-- RELOADING PRESS (prepared, switched off)
------------------------------------------------
--
-- The press is a future placed station
-- (docs/RELOADING_PRESS_DESIGN.md). Its recipes are
-- already described here so that the day the station
-- entity exists, they are generated like every other
-- recipe: the same calibre's case, bullet and assembly
-- steps, the SAME die set kept, exactly the same
-- material, less time, and no hammer (the press does the
-- pressing).
--
-- enabled = false: buildRecipes() adds nothing, so the
-- recipe script, the callbacks and the compatibility
-- check do not know a press exists. Nothing provides the
-- bench tag yet, and a recipe nothing can craft would
-- only be dead weight in the game's recipe list.
--
-- timePercent: the press time as a percentage of the
-- hand time, rounded down. 60 means two fifths faster.
-- It is the press's ONLY advantage, besides needing no
-- hammer: same material, same die set, same output, same
-- XP. It is kept between 50 and 90: below 50 the press
-- would more than double the XP earned per hour at the
-- bench, above 90 it would not be worth building.
-- A press time below 20 is refused: the engine's 5 %
-- per level speed-up is time / 20 with integer division,
-- so a shorter recipe would never get faster with skill.

--
-- timedAction and the kept-tool line follow vanilla's
-- own press recipes (PressClayBrick: Tags = HandPress,
-- timedAction = UseHandPress, the mold mode:keep).
------------------------------------------------

AC_Calibres.PRESS = {

    enabled = false,

    benchTag = "AmmoMakingReloadingPress",

    timedAction = "UseHandPress",

    timePercent = 60,

    -- The range timePercent may be tuned in.
    minimumPercent = 50,

    maximumPercent = 90,


    minimumTime = 20,

    -- The hand steps that have a press version. The die
    -- set is forged, not pressed.
    steps = { "case", "bullet", "assemble" },

    idSuffix = "AtPress",

    -- What a press recipe is called: its hand recipe's
    -- name with this added. No name is written until the
    -- press is switched on (Recipes.json then needs one
    -- per press recipe; the tests say which).
    nameSuffix = " (Press)",
}


------------------------------------------------
-- WADDING
------------------------------------------------
--
-- What separates powder from shot in a shell: a scrap of
-- cloth or cotton. Vanilla items, not tracked as a
-- material (like charcoal). The recipe line is
-- mode:destroy, as in the vanilla recipes that consume
-- Base.RippedSheets, so the rag's ReplaceOnUse (a dirty
-- rag) is not handed back.
------------------------------------------------

AC_Calibres.WAD = {

    items = { "Base.RippedSheets", "Base.CottonBalls" },
}


AC_Calibres.DEFAULTS = {

    primerFamily = "SmallPistol",

    cupsPerCase = 1,

    bulletsPerScrap = 2,

    powderUses = 1,

    -- Pieces of wadding (WAD) in one round. Only a shell
    -- has any.
    wads = 0,

    -- The service and house-gun calibres are the common
    -- dies; a magnum or a long gun says otherwise.
    lootTier = "common",

    assembleLevel = 3,

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


------------------------------------------------
-- Per-class values that differ from DEFAULTS. A rifle
-- round unlocks at the top of the pistol ladder, takes
-- about twice as long at every step, and its larger
-- components are worth a little more XP.
------------------------------------------------

AC_Calibres.CLASSES = {

    -- label: how the compatibility summary and the debug
    -- tools name the class.
    pistol = {

        label = "Pistol calibres",
    },

    ------------------------------------------------
    -- A shotgun shell is a cartridge with one more part.
    -- Its "case" is the brass hull, its "bullet" the
    -- measured charge of copper shot, and a wad sits
    -- between powder and shot. Pistol times: the hull is
    -- a straight-walled case. primerClass names the
    -- class whose primer families it takes.
    ------------------------------------------------
    shotgun = {

        label = "Shotgun shells",

        primerClass = "pistol",

        primerFamily = "LargePistol",

        cupsPerCase = 3,

        bulletsPerScrap = 1,

        powderUses = 3,

        wads = 1,

        lootTier = "rare",

        assembleLevel = 4,

        xp = {
            case = 2,
            assemble = 3,
        },
    },

    rifle = {

        label = "Rifle calibres",

        primerFamily = "LargeRifle",

        cupsPerCase = 2,

        bulletsPerScrap = 1,

        powderUses = 4,

        lootTier = "rare",

        assembleLevel = 5,

        xp = {
            case = 2,
            assemble = 4,
        },

        time = {
            dieSet = 400,
            case = 160,
            bullet = 120,
            assemble = 80,
        },
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
-- The step ladder of a calibre whose round unlocks at
-- assembleLevel: the die set and case two levels
-- earlier, the bullet one level earlier, never below 1.
-- A player meets a calibre's tools before its rounds.
------------------------------------------------

function AC_Calibres.levelsFor(
    assembleLevel
)

    local early =
        math.max(
            1,
            assembleLevel - 2
        )


    return {

        dieSet = early,

        case = early,

        bullet =
            math.max(
                1,
                assembleLevel - 1
            ),

        assemble = assembleLevel,
    }
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


    calibre.class =
        calibre.class or "pistol"


    -- An unknown class is reported by validate(); here it
    -- simply contributes nothing.
    local class =
        AC_Calibres.CLASSES[calibre.class] or {}


    calibre.case =
        calibre.case or ("AmmoMaking.Case" .. calibre.suffix)

    calibre.bullet =
        calibre.bullet or ("AmmoMaking.Bullet" .. calibre.suffix)

    calibre.dieSet =
        calibre.dieSet or ("AmmoMaking.DieSet" .. calibre.suffix)


    for _,
        key
    in ipairs(
        { "primerFamily", "cupsPerCase", "bulletsPerScrap", "powderUses", "wads", "lootTier", "assembleLevel" }
    )
    do

        if calibre[key] == nil then
            calibre[key] = class[key]
        end


        if calibre[key] == nil then
            calibre[key] = defaults[key]
        end
    end


    local stepDefaults = {

        levels =
            AC_Calibres.levelsFor(
                calibre.assembleLevel
            ),

        xp = defaults.xp,

        time = defaults.time,
    }


    -- DEFAULTS, then the class, then the definition.
    for key,
        base
    in pairs(
        stepDefaults
    )
    do

        local merged =
            copyTable(
                base
            )


        for _,
            overrides
        in ipairs(
            { class[key] or {}, definition[key] or {} }
        )
        do

            for step,
                value
            in pairs(
                overrides
            )
            do

                merged[step] = value
            end
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

        box = "Base.Bullets9mmBox",

        roundsPerBox = 50,

        ammoType = "base:bullets_9mm",
    }),

    AC_Calibres.define({

        id = ".38 Special",

        suffix = "38Special",

        round = "Base.Bullets38",

        box = "Base.Bullets38Box",

        roundsPerBox = 50,

        ammoType = "base:bullets_38",
    }),

    AC_Calibres.define({

        id = ".45 ACP",

        suffix = "45ACP",

        round = "Base.Bullets45",

        box = "Base.Bullets45Box",

        roundsPerBox = 50,

        ammoType = "base:bullets_45",

        primerFamily = "LargePistol",

        bulletsPerScrap = 1,

        lootTier = "uncommon",

        assembleLevel = 4,

        xp = { assemble = 3 },
    }),

    AC_Calibres.define({

        id = ".357 Magnum",

        suffix = "357Magnum",

        round = "Base.Bullets357",

        box = "Base.Bullets357Box",

        roundsPerBox = 50,

        ammoType = "base:bullets_357",

        powderUses = 2,

        lootTier = "uncommon",

        assembleLevel = 4,

        xp = { assemble = 3 },
    }),

    AC_Calibres.define({

        id = ".44 Magnum",

        suffix = "44Magnum",

        round = "Base.Bullets44",

        box = "Base.Bullets44Box",

        roundsPerBox = 20,

        ammoType = "base:bullets_44",

        primerFamily = "LargePistol",

        cupsPerCase = 2,

        bulletsPerScrap = 1,

        powderUses = 3,

        lootTier = "uncommon",

        assembleLevel = 5,

        xp = { case = 2, assemble = 4 },
    }),

    ------------------------------------------------
    -- Rifle calibres (docs/RIFLE_AMMUNITION_RESEARCH.md)
    ------------------------------------------------

    AC_Calibres.define({

        id = "5.56",

        class = "rifle",

        suffix = "556NATO",

        round = "Base.556Bullets",

        box = "Base.556Box",

        roundsPerBox = 20,

        ammoType = "base:bullets_556",

        primerFamily = "SmallRifle",

        bulletsPerScrap = 2,

        powderUses = 3,
    }),

    AC_Calibres.define({

        id = ".30-30",

        class = "rifle",

        suffix = "3030Win",

        round = "Base.3030Bullets",

        box = "Base.3030Box",

        roundsPerBox = 20,

        ammoType = "base:bullets_3030",
    }),

    AC_Calibres.define({

        id = ".308",

        class = "rifle",

        suffix = "308Win",

        round = "Base.308Bullets",

        box = "Base.308Box",

        roundsPerBox = 20,

        ammoType = "base:bullets_308",

        cupsPerCase = 3,

        powderUses = 5,

        xp = { case = 3, assemble = 5 },
    }),

    ------------------------------------------------
    -- Shotgun shell (docs/SHOTGUN_AMMUNITION_RESEARCH.md).
    -- Vanilla has one shell item; the nine pellets are
    -- the gun's property, so this is "the" 12 gauge
    -- round. Every value comes from the shotgun class.
    ------------------------------------------------

    AC_Calibres.define({

        id = "12 Gauge",

        class = "shotgun",

        suffix = "12Gauge",

        round = "Base.ShotgunShells",

        box = "Base.ShotgunShellsBox",

        roundsPerBox = 25,

        ammoType = "base:shotgun_shells",

        case = "AmmoMaking.Hull12Gauge",

        bullet = "AmmoMaking.ShotCharge12Gauge",
    }),
}


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- Returns a list of problems, each "<calibre>: text",
-- empty when the model is sound. Run by the tests and by
-- the compatibility check at game start, so a bad
-- definition is named instead of silently producing a
-- recipe that takes the wrong case or creates material.
--
-- list and primers default to the live tables.
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


function AC_Calibres.validate(
    list,
    primers
)

    list =
        list or AC_Calibres.LIST

    primers =
        primers or AC_Calibres.PRIMERS


    local problems = {}


    local function problem(
        owner,
        text
    )

        table.insert(
            problems,
            tostring(owner) .. ": " .. text
        )
    end


    ------------------------------------------------
    -- Primer families
    ------------------------------------------------

    local families = {}

    local itemOwner = {}


    for _,
        primer
    in ipairs(
        primers
    )
    do

        local name =
            "primer " .. tostring(primer.id)


        if families[primer.id] then
            problem(name, "duplicate primer family id")
        end


        families[primer.id] = primer


        if type(primer.item) ~= "string" then

            problem(name, "no item")

        elseif itemOwner[primer.item] then

            problem(name, "item " .. primer.item .. " is already used by " .. itemOwner[primer.item])

        else

            itemOwner[primer.item] = name
        end


        if not isWhole(primer.brassUnits, 1)
            or not isWhole(primer.compoundUnits, 1)
            or not isWhole(primer.perSheet, 1)
        then

            problem(name, "brass, compound and count must be whole and positive")

        else

            if primer.perSheet * primer.brassUnits ~= AC_Calibres.CONFIG.sheetUnits then
                problem(name, "does not use exactly one small brass sheet")
            end


            for _,
                source
            in ipairs(
                AC_Calibres.COMPOUND_SOURCES
            )
            do

                if not isWhole(primer.perSheet * primer.compoundUnits / source.units, 1) then
                    problem(name, "takes a fractional amount of " .. source.id)
                end
            end
        end


        if not isWhole(primer.requiredLevel, 0)
            or primer.requiredLevel > 10
        then
            problem(name, "invalid level")
        end


        if not AC_Calibres.CLASSES[primer.class] then
            problem(name, "unknown class " .. tostring(primer.class))
        end
    end


    ------------------------------------------------
    -- Classes
    ------------------------------------------------

    for className,
        class
    in pairs(
        AC_Calibres.CLASSES
    )
    do

        if class.primerClass
            and not AC_Calibres.CLASSES[class.primerClass]
        then
            problem("class " .. className, "unknown primer class " .. tostring(class.primerClass))
        end
    end


    ------------------------------------------------
    -- Calibres
    ------------------------------------------------

    local ids = {}

    local suffixes = {}


    for _,
        calibre
    in ipairs(
        list
    )
    do

        local name =
            tostring(calibre.id)


        if type(calibre.id) ~= "string"
            or calibre.id == ""
        then
            problem(name, "no id")
        elseif ids[calibre.id] then
            problem(name, "duplicate calibre id")
        end


        ids[name] = true


        if not AC_Calibres.CLASSES[calibre.class] then
            problem(name, "unknown class " .. tostring(calibre.class))
        end


        if type(calibre.suffix) ~= "string"
            or calibre.suffix == ""
            or string.find(calibre.suffix, "[^%w]")
        then
            problem(name, "suffix must be letters and digits")
        elseif suffixes[calibre.suffix] then
            problem(name, "duplicate suffix " .. calibre.suffix)
        else
            suffixes[calibre.suffix] = true
        end


        -- A component belongs to exactly one calibre and
        -- one role: no case, bullet, die set or round may
        -- stand in for another.
        for _,
            kind
        in ipairs(
            { "round", "case", "bullet", "dieSet" }
        )
        do

            local itemType =
                calibre[kind]


            if type(itemType) ~= "string"
                or itemType == ""
            then

                problem(name, "no " .. kind .. " item")

            elseif itemOwner[itemType] then

                problem(name, kind .. " item " .. itemType .. " is already used by " .. itemOwner[itemType])

            else

                itemOwner[itemType] = name .. " " .. kind
            end
        end


        if type(calibre.round) == "string"
            and string.sub(calibre.round, 1, 5) ~= "Base."
        then
            problem(name, "the round must be a vanilla item")
        end


        -- The box is vanilla's, and no two rounds share one.
        if type(calibre.box) ~= "string"
            or string.sub(calibre.box, 1, 5) ~= "Base."
        then

            problem(name, "the box must be a vanilla item")

        elseif itemOwner[calibre.box] then

            problem(name, "box item " .. calibre.box .. " is already used by " .. itemOwner[calibre.box])

        else

            itemOwner[calibre.box] = name .. " box"
        end


        if not isWhole(calibre.roundsPerBox, 1) then
            problem(name, "roundsPerBox must be a whole number of at least 1")
        end


        local primer =
            families[calibre.primerFamily]


        -- A calibre takes a primer family of its own class,
        -- unless its class names another (primerClass).
        local class =
            AC_Calibres.CLASSES[calibre.class] or {}


        if not primer then
            problem(name, "unknown primer family " .. tostring(calibre.primerFamily))
        elseif primer.class ~= (class.primerClass or calibre.class) then
            problem(name, "a " .. tostring(calibre.class) .. " calibre cannot take the " .. tostring(primer.class) .. " primer family " .. tostring(primer.id))
        end


        if not isWhole(calibre.cupsPerCase, 1) then
            problem(name, "cupsPerCase must be a whole number of at least 1")
        end


        if not isWhole(calibre.bulletsPerScrap, 1)
            or not isWhole(AC_Calibres.CONFIG.scrapUnits / calibre.bulletsPerScrap, 1)
        then
            problem(name, "bulletsPerScrap must divide a scrap into whole units")
        end


        if not isWhole(calibre.powderUses, 1) then
            problem(name, "powderUses must be a whole number of at least 1")
        end


        if not isWhole(calibre.wads, 0) then
            problem(name, "wads must be a whole number")
        elseif calibre.wads < (class.wads or 0) then
            problem(name, "a " .. tostring(calibre.class) .. " round needs at least " .. class.wads .. " wad")
        end


        local levels =
            calibre.levels or {}


        local ordered = true


        for _,
            step
        in ipairs(
            { "dieSet", "case", "bullet", "assemble" }
        )
        do

            if not isWhole(levels[step], 0)
                or levels[step] > 10
            then

                problem(name, "invalid level for " .. step)

                ordered = false
            end


            if not isWhole(calibre.xp and calibre.xp[step], 1) then
                problem(name, "invalid xp for " .. step)
            end


            if not isWhole(calibre.time and calibre.time[step], 1) then
                problem(name, "invalid time for " .. step)
            end
        end


        if ordered then

            if levels.dieSet > levels.case
                or levels.case > levels.assemble
                or levels.bullet > levels.assemble
            then
                problem(name, "a component unlocks after the round it is for")
            end


            if primer
                and isWhole(primer.requiredLevel, 0)
                and primer.requiredLevel > levels.assemble
            then
                problem(name, "its primer unlocks after its round")
            end


            if AC_Calibres.POWDER.requiredLevel > levels.assemble then
                problem(name, "gunpowder unlocks after its round")
            end
        end
    end


    return problems
end


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

-- The item roles of a calibre, in the order identify()
-- tries them. One table, not one per call: identify()
-- runs for every item of an inventory right-click.
local ITEM_KINDS = { "case", "bullet", "dieSet", "round" }


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
            ITEM_KINDS
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
            calibre.primerFamily
        )


    local suffix =
        calibre.suffix


    local recipes = {

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
                { count = calibre.cupsPerCase, items = { "AmmoMaking.BrassCaseCup" } },
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


    -- A shell's wad goes in last, after the lines every
    -- round has.
    if (calibre.wads or 0) > 0 then

        table.insert(
            recipes[4].inputs,
            {
                count = calibre.wads,
                items = AC_Calibres.WAD.items,
                destroy = true,
            }
        )
    end


    return recipes
end


------------------------------------------------
-- PRESS RECIPES OF ONE CALIBRE
------------------------------------------------
--
-- The press version of each hand step in PRESS.steps:
-- the hand recipe with the press's bench tag and timed
-- action, its time divided, and its hammer line left
-- out. Inputs that carry material, the die set, the
-- outputs, the level, the XP and the effect are the hand
-- recipe's own, so a press can neither save material nor
-- skip the die set. "handRecipe" names the recipe it was
-- made from.
--
-- Built whether or not the press is enabled; only
-- buildRecipes() looks at the switch.
------------------------------------------------

function AC_Calibres.buildPressRecipes(
    calibre
)

    local press =
        AC_Calibres.PRESS


    local wanted = {}


    for _,
        step
    in ipairs(
        press.steps
    )
    do

        wanted[step] = true
    end


    local recipes = {}


    for _,
        hand
    in ipairs(
        AC_Calibres.buildCalibreRecipes(calibre)
    )
    do

        if wanted[hand.step] then

            local recipe =
                copyTable(
                    hand
                )


            recipe.id =
                hand.id .. press.idSuffix

            recipe.callback =
                hand.callback .. press.idSuffix

            recipe.handRecipe =
                hand.id

            recipe.press = true

            recipe.benchTag =
                press.benchTag

            recipe.timedAction =
                press.timedAction

            recipe.time =
                math.floor(hand.time * press.timePercent / 100)



            recipe.inputs = {}


            for _,
                input
            in ipairs(
                hand.inputs
            )
            do

                local isHammer =
                    input.keep
                    and input.tags
                    and input.tags[1] == "base:hammer"


                if not isHammer then

                    table.insert(
                        recipe.inputs,
                        input
                    )
                end
            end


            table.insert(
                recipes,
                recipe
            )
        end
    end


    return recipes
end


------------------------------------------------
-- Problems of the press description, in the form of
-- validate(): empty when it is sound. Checked whether
-- or not the press is enabled.
------------------------------------------------

function AC_Calibres.validatePress(
    list
)

    list =
        list or AC_Calibres.LIST


    local press =
        AC_Calibres.PRESS


    local problems = {}


    if type(press.benchTag) ~= "string"
        or press.benchTag == ""
        or string.find(press.benchTag, "[^%w]")
    then

        -- "-" starts a blacklist and ";" separates tags in
        -- the engine's tag query.
        table.insert(problems, "press: the bench tag must be letters and digits")
    end


    if not isWhole(press.timePercent, 1)
        or press.timePercent < press.minimumPercent
        or press.timePercent > press.maximumPercent
    then

        table.insert(
            problems,
            "press: timePercent must be a whole number from "
            .. tostring(press.minimumPercent)
            .. " to "
            .. tostring(press.maximumPercent)
        )


        return problems
    end


    if type(press.steps) ~= "table"
        or #press.steps == 0
    then

        table.insert(problems, "press: no steps")


        return problems
    end


    -- A step the press names must be one a calibre has, and
    -- never the die set: that is forged.
    local known = { case = true, bullet = true, assemble = true }


    for _,
        step
    in ipairs(
        press.steps
    )
    do

        if not known[step] then
            table.insert(problems, "press: " .. tostring(step) .. " is not a step the press can do")
        end
    end



    for _,
        calibre
    in ipairs(
        list
    )
    do

        for _,
            recipe
        in ipairs(
            AC_Calibres.buildPressRecipes(calibre)
        )
        do

            if recipe.time < press.minimumTime then

                table.insert(
                    problems,
                    tostring(calibre.id)
                    .. ": press time of "
                    .. recipe.step
                    .. " is "
                    .. recipe.time
                    .. ", below "
                    .. press.minimumTime
                )
            end
        end
    end


    return problems
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
-- then each calibre's (and its press versions, once the
-- press is enabled).
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


        -- Off until the press station exists.
        if AC_Calibres.PRESS.enabled then

            for _,
                recipe
            in ipairs(
                AC_Calibres.buildPressRecipes(calibre)
            )
            do

                table.insert(
                    recipes,
                    recipe
                )
            end
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
                calibre.primerFamily
            )


        local caseUnits =
            AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase


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
