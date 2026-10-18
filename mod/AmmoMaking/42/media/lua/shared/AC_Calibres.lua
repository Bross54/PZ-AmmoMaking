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
--                   the same steps at the reloading press,
--                   only with its add-on active (PRESS)
--   buildUnits()    what each component contains, for the
--                   material-conservation checks
--   getItems()      the item ids the compatibility check
--                   probes
--
-- Cast lead bullets (AC_Casting) read two things from
-- here and nothing else: which classes have a bullet mould
-- (CLASSES[class].mould) and each such calibre's cast
-- bullet item (calibre.castBullet); a rifle's also needs a
-- gas check (CLASSES.rifle.gasCheck).
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

require "AC_Features"

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
-- castBullet
--          the cast lead bullet (AC_Casting), only for a
--          class with a mould; when left out it is
--          AmmoMaking.CastBullet<suffix>. Same lead per
--          bullet as copper per copper bullet
--          (bulletsPerScrap).
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
-- material and powder, not a quality penalty. The press
-- takes the same die sets.
------------------------------------------------

------------------------------------------------
-- RELOADING PRESS (feature "reloadingPress": an add-on)
------------------------------------------------
--
-- The press is a placed station that exists only with the
-- add-on mod AmmoMakingPress (docs/RELOADING_PRESS_DESIGN.md
-- 10). Its recipes are described here and generated like
-- every other recipe: the same calibre's case, bullet and assembly
-- steps, the SAME die set kept, exactly the same
-- material, less time, and no hammer (the press does the
-- pressing).
--
-- enabled: whether the press exists in this game. It is
-- the feature "reloadingPress" (AC_Features): true only
-- when the add-on mod that carries the station entity,
-- its tile sheet and the press recipe script is active.
-- Without it buildRecipes() adds nothing, so the recipe
-- list, the callbacks and the compatibility check do not
-- know a press exists, and no recipe is left that nothing
-- can craft.
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

    enabled = AC_Features.isEnabled("reloadingPress"),

    benchTag = "AmmoMakingReloadingPress",

    timedAction = "UseHandPress",

    timePercent = 60,

    -- The range timePercent may be tuned in.
    minimumPercent = 50,

    maximumPercent = 90,


    minimumTime = 20,

    -- The hand steps that have a press version. The die
    -- set is forged, not pressed. assembleCast is the
    -- assembly on a cast bullet (AC_Casting), for the
    -- calibres that cast.
    steps = { "case", "bullet", "assemble", "assembleCast" },

    idSuffix = "AtPress",

    -- What a press recipe is called: its hand recipe's
    -- name with this added. The names are generated into
    -- the add-on's Recipes.json.
    nameSuffix = " (Press)",

    -- What the station is built from: a mirror of the
    -- build recipe in the add-on's entity script (the
    -- tests compare the two), for the debug kit. The
    -- engine reads the script, not this.
    buildKit = {
        { "Base.Hammer", 1 },
        { "Base.SteelBarHalf", 2 },
        { "Base.Plank", 4 },
        { "Base.Nails", 8 },
    },
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


------------------------------------------------
-- DIE SET WEAR
------------------------------------------------
--
-- A die set wears out like vanilla's small punch set
-- (Base.SmallPunchSet, items/normal.txt: a base:normal
-- tool with ConditionMax, ConditionLowerChanceOneIn and
-- base:showcondition, kept with flags[MayDegradeLight]).
-- Without it one die set, found or forged, served a
-- calibre for the rest of the game.
--
-- The engine does the wearing; no Lua runs for it. What
-- the jar (42.20.4) does with a kept input when a craft
-- completes (processKeepInputItem of the class
-- CraftRecipeData):
--
--   skill  = the recipe's highest relevant skill level
--            (Ammo Making, attached at boot) + the
--            character's Maintenance level
--   damageCheck(skill, multiplier): one chance in
--            (ConditionLowerChanceOneIn * multiplier
--             + skill) of losing one point of condition
--
-- with the multiplier 6 for MayDegradeVeryLight, 3 for
-- MayDegradeLight, 2 for MayDegrade, 1 for
-- MayDegradeHeavy. At condition 0 the item is broken,
-- and InputScript.passesBrokenTest refuses a broken
-- item unless the line says AllowDestroyedItem: a worn
-- out die set stops its recipes, and a new one is forged
-- or found.
--
-- conditionMax is the engine's default (Item: 10), so a
-- die set saved before this change is a full one.
--
-- The item script (AC_Items.txt) carries the two
-- numbers; the tests hold it to this table. The press
-- and the spent-case resizing copy the hand recipe's
-- kept lines, so they wear the die set as hand work does.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the
-- condition shows on the die set, falls while crafting
-- and that a broken die set is refused.
------------------------------------------------

AC_Calibres.DIE_WEAR = {

    flag = "MayDegradeVeryLight",

    -- The jar's multiplier for that flag.
    flagMultiplier = 6,

    conditionMax = 10,

    conditionLowerChanceOneIn = 15,
}


------------------------------------------------
-- REGRINDING A WORN DIE SET
------------------------------------------------
--
-- A worn or broken die set is filed true again instead
-- of forged anew, at the price of metal: each regrind
-- leaves the die a little more open, so the condition it
-- can be brought back to falls by lossPerRegrind every
-- time (10, 8, 6, 4, 2). After the last one nothing is
-- gained and a new die set is forged or found.
--
-- The recipe consumes the die set (AllowDestroyedItem,
-- vanilla's flag for a broken item in a recipe line) and
-- makes the same die set; OnCreate sets the new one's
-- condition (InventoryItem.setCondition) and carries the
-- count in its ModData (regrindKey). A treatment: no XP,
-- the die set's level, a file or whetstone kept.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that a broken die
-- set is offered to the recipe and the made one takes the
-- condition set in OnCreate.
------------------------------------------------

AC_Calibres.REGRIND = {

    lossPerRegrind = 2,

    time = 150,

    timedAction = "Making",

    benchTag = "AnySurfaceCraft",

    category = "Tools",

    idPrefix = "AmmoMaking_RegrindDieSet",

    callbackPrefix = "onRegrindDieSet",

    -- ModData key on a die set: how often it was reground.
    regrindKey = "dieSetRegrinds",
}


-- The condition a die set reground for the n-th time
-- (n >= 1) is brought back to, from the condition it had:
-- never lower than before, never above what n regrinds
-- leave.
function AC_Calibres.regroundCondition(
    condition,
    regrinds
)

    local wear =
        AC_Calibres.DIE_WEAR


    local scale =
        AC_Balance
        and AC_Balance.get
        and AC_Balance.get("regrindLoss")
        or 1


    -- At least one point a regrind, whatever the option.
    local loss =
        math.max(
            1,
            math.floor(AC_Calibres.REGRIND.lossPerRegrind * scale + 0.5)
        )


    local cap =
        wear.conditionMax
        - loss * (tonumber(regrinds) or 1)


    condition =
        math.max(0, math.floor(tonumber(condition) or 0))


    return
        math.min(
            wear.conditionMax,
            math.max(condition, cap)
        )
end


-- One regrinding recipe per calibre.
function AC_Calibres.buildRegrindRecipes(
    list
)

    local regrind =
        AC_Calibres.REGRIND


    local recipes = {}


    for _,
        calibre
    in ipairs(
        list or AC_Calibres.ALL
    )
    do

        table.insert(
            recipes,
            {
                id = regrind.idPrefix .. calibre.suffix,
                calibre = calibre.id,
                step = "regrind",
                treatment = true,
                tool = true,
                effect = "regrindDieSet",
                time = regrind.time,
                timedAction = regrind.timedAction,
                benchTag = regrind.benchTag,
                category = regrind.category,
                callback = regrind.callbackPrefix .. calibre.suffix,
                xp = 0,
                requiredLevel = calibre.levels.dieSet,
                inputs = {
                    { count = 1, items = { calibre.dieSet }, flags = { "AllowDestroyedItem" } },
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
            }
        )
    end


    return recipes
end


-- OnCreate of a regrind: the made die set takes the
-- consumed one's count plus one and the condition that
-- allows. Returns the condition set, or nil.
function AC_Calibres.onDieSetReground(
    craftRecipeData
)

    if not craftRecipeData
        or not craftRecipeData.getAllConsumedItems
        or not craftRecipeData.getAllCreatedItems
    then
        return nil
    end


    local key =
        AC_Calibres.REGRIND.regrindKey


    local consumed =
        craftRecipeData:getAllConsumedItems()


    local created =
        craftRecipeData:getAllCreatedItems()


    local old = nil


    for index = 0, (consumed and consumed:size() or 0) - 1 do

        local item = consumed:get(index)

        if AC_Calibres.identify(item:getFullType()) == "dieSet" then
            old = item
        end
    end


    if not old then
        return nil
    end


    local regrinds = 0


    if not old.hasModData
        or old:hasModData()
    then

        regrinds =
            AC_SaveData.whole(
                old:getModData()[key],
                0
            ) or 0
    end


    regrinds = regrinds + 1


    local condition =
        AC_Calibres.regroundCondition(
            old:getCondition(),
            regrinds
        )


    for index = 0, (created and created:size() or 0) - 1 do

        local item = created:get(index)

        if AC_Calibres.identify(item:getFullType()) == "dieSet" then

            item:setCondition(condition)

            item:getModData()[key] = regrinds

            return condition
        end
    end


    return nil
end


------------------------------------------------
-- ANNEALING CASES
------------------------------------------------
--
-- Brass work-hardens when a case is formed; a short heat
-- at the neck softens it again and the case lasts and
-- seals better. Here: a few cases and some uses of a
-- vanilla blowtorch (Base.BlowTorch, items/drainable.txt:
-- ten uses, UseDelta 0.1; vanilla's CutIngotIntoBlocks
-- takes it as "item 2 [Base.BlowTorch] flags[Prop1]" with
-- timedAction Welding) give the same cases back, each
-- qualityBonus better, once: an annealed case is marked
-- (annealedKey) and annealing it again adds nothing. A
-- treatment: no XP, the forming level.
------------------------------------------------

AC_Calibres.ANNEAL = {

    item = "Base.BlowTorch",

    uses = 1,

    cases = 5,

    qualityBonus = 3,

    time = 60,

    timedAction = "Welding",

    benchTag = "AnySurfaceCraft",

    category = "Metalworking",

    idPrefix = "AmmoMaking_AnnealCases",

    callbackPrefix = "onAnnealCases",

    -- ModData key on a case.
    annealedKey = "caseAnnealed",
}


-- One annealing recipe per calibre.
function AC_Calibres.buildAnnealRecipes(
    list
)

    local anneal =
        AC_Calibres.ANNEAL


    local recipes = {}


    for _,
        calibre
    in ipairs(
        list or AC_Calibres.ALL
    )
    do

        table.insert(
            recipes,
            {
                id = anneal.idPrefix .. calibre.suffix,
                calibre = calibre.id,
                step = "anneal",
                treatment = true,
                effect = "annealCases",
                time = anneal.time,
                timedAction = anneal.timedAction,
                benchTag = anneal.benchTag,
                category = anneal.category,
                callback = anneal.callbackPrefix .. calibre.suffix,
                xp = 0,
                requiredLevel = calibre.levels.case,
                inputs = {
                    { count = anneal.cases, items = { calibre.case } },
                    { count = anneal.uses, items = { anneal.item }, flags = { "Prop1" } },
                },
                outputs = {
                    { count = anneal.cases, item = calibre.case },
                },
            }
        )
    end


    return recipes
end


-- Every recipe of one calibre: its four steps, the
-- regrinding and annealing, its casts, cast assembly and
-- lubing. For an extension's add-on script
-- (tests/render_addons.lua); the game builds the same
-- recipes through the lists above.
-- What an extension's add-on carries beyond its hand
-- recipes:
--   its press recipes: the engine shows them only where
--     the press add-on's station exists (REQUIRES FUTURE
--     IN-GAME VERIFICATION: a recipe whose bench tag no
--     station has is simply never offered);
--   its spent cases (items of the add-on too): resized
--     two for one, cleaned and scrapped like the vanilla
--     calibres' in the spent cases add-on. They are only
--     ever left by a shot where that add-on is on
--     (AC_SpentCases.getSpentCaseForRound reads ALL).
function AC_Calibres.buildExtensionExtras(
    calibre
)

    local recipes = {}


    local function add(
        list
    )

        for _,
            recipe
        in ipairs(
            list
        )
        do

            table.insert(
                recipes,
                recipe
            )
        end
    end


    add(AC_Calibres.buildPressRecipes(calibre))


    if AC_SpentCases then

        add(AC_SpentCases.buildResizeRecipes({ calibre }))

        add(AC_SpentCases.buildCleanRecipes({ calibre }))
    end


    if AC_Recycling then

        for _,
            recipe
        in ipairs(
            AC_Recycling.buildRecipes({ AC_Recycling.getSpentSource(calibre) })
        )
        do

            -- buildRecipes() ends with the recast, which the
            -- main mod ships.
            if recipe.recyclingSource then

                table.insert(
                    recipes,
                    recipe
                )
            end
        end
    end


    return recipes
end


function AC_Calibres.buildAllRecipesOf(
    calibre
)

    local recipes = {}


    local function add(
        list
    )

        for _,
            recipe
        in ipairs(
            list
        )
        do

            table.insert(
                recipes,
                recipe
            )
        end
    end


    add(AC_Calibres.buildCalibreRecipes(calibre))

    if calibre.extension then

        add(AC_Calibres.buildExtensionExtras(calibre))
    end

    add(AC_Calibres.buildRegrindRecipes({ calibre }))

    add(AC_Calibres.buildAnnealRecipes({ calibre }))


    if AC_Casting then

        add(AC_Casting.buildCalibreRecipes(calibre))

        add(AC_Casting.buildLubeRecipes({ calibre }))
    end


    return recipes
end


-- Crafts a die set is expected to last: condition points
-- times the mean number of crafts per point.
function AC_Calibres.dieSetExpectedUses(
    skillLevel,
    maintenanceLevel
)

    local wear =
        AC_Calibres.DIE_WEAR

    local oneIn =
        wear.conditionLowerChanceOneIn * wear.flagMultiplier
        + (skillLevel or 0)
        + (maintenanceLevel or 0)

    return wear.conditionMax * oneIn
end


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

        -- The bullet mould of the class (AC_Casting): one
        -- kept tool casts the lead bullets of every pistol
        -- calibre, as a die set is kept for copper ones.
        mould = "AmmoMaking.BulletMouldPistol",
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

        -- Buckshot is cast too: a mould of round cavities.
        mould = "AmmoMaking.BulletMouldShotgun",
    },

    ------------------------------------------------
    -- Rifles cast too, but only with a gas check: a
    -- plain lead bullet strips in the rifling and leads
    -- the bore at the 2,200 to 3,000 ft/s of the three
    -- rifle rounds. A small copper cup crimped on its base
    -- (AC_Casting.GAS_CHECK) is what made cast rifle loads
    -- work; even so they shoot worse than jacketed ones
    -- (castQualityBonus), and the copper still comes from
    -- the mine, a tenth of a jacketed bullet's
    -- (docs/METALLURGY_DESIGN.md 12.9).
    ------------------------------------------------

    rifle = {

        label = "Rifle calibres",

        primerFamily = "LargeRifle",

        cupsPerCase = 2,

        bulletsPerScrap = 1,

        powderUses = 4,

        lootTier = "rare",

        assembleLevel = 5,

        -- The rifle bullet mould; its cast bullets need a
        -- gas check at assembly, and roll this much lower.
        mould = "AmmoMaking.BulletMouldRifle",

        gasCheck = true,

        castQualityBonus = -10,

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


    -- Only a class with a bullet mould casts lead. A
    -- definition that names a cast bullet anyway is
    -- reported by validate().
    if class.mould then

        calibre.castBullet =
            calibre.castBullet or ("AmmoMaking.CastBullet" .. calibre.suffix)
    end


    -- What a fired round leaves behind: the case's own
    -- item name with "Spent" in front. The item exists
    -- only in the spent-cases add-on (AC_SpentCases); it
    -- is not a case and cannot be loaded as it is: it is
    -- scrapped, or resized two for one back into this
    -- calibre's case (AC_SpentCases.RESIZE).
    calibre.spentCase =
        calibre.spentCase
        or (
            "AmmoMaking.Spent"
            .. (string.match(calibre.case, "([^%.]+)$") or calibre.suffix)
        )


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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.9x19_Casing",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.9x19_Casing",

        box = "Base.Bullets9mmBox",

        roundsPerBox = 50,

        ammoType = "base:bullets_9mm",
    }),

    AC_Calibres.define({

        id = ".38 Special",

        suffix = "38Special",

        round = "Base.Bullets38",

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.38_Casing",

        -- No mfsCasing: Modern Firearms System makes this
        -- round a 6.8mm and ejects a .30-06 casing for it.

        box = "Base.Bullets38Box",

        roundsPerBox = 50,

        ammoType = "base:bullets_38",
    }),

    AC_Calibres.define({

        id = ".45 ACP",

        suffix = "45ACP",

        round = "Base.Bullets45",

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.45_Casing",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.45_Casing",

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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.357_Casing",

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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.44_Casing",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.44_Casing",

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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.556x45_Casing",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.556x45_Casing",

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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.3030_Casing",

        box = "Base.3030Box",

        roundsPerBox = 20,

        ammoType = "base:bullets_3030",
    }),

    AC_Calibres.define({

        id = ".308",

        class = "rifle",

        suffix = "308Win",

        round = "Base.308Bullets",

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.762x51_Casing",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.762x51_Casing",

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

        -- What Hot Brass ejects for it (its Init.lua).
        hotBrassCasing = "HBVCEF.12Gauge_Hull_Red",

        -- What Modern Firearms System ejects for it
        -- (MFSEject/Init.lua, AMMO_TO_CASING).
        mfsCasing = "MFSEject.12Gauge_Hull_Red",

        box = "Base.ShotgunShellsBox",

        roundsPerBox = 25,

        ammoType = "base:shotgun_shells",

        case = "AmmoMaking.Hull12Gauge",

        bullet = "AmmoMaking.ShotCharge12Gauge",

        castBullet = "AmmoMaking.LeadShotCharge12Gauge",
    }),
}


------------------------------------------------
-- CALIBRES OF OTHER MODS (EXTENSIONS)
------------------------------------------------
--
-- A round another mod adds is handloaded through an
-- add-on of this mod: the add-on ships the calibre's
-- items and recipe scripts (generated, like the press's),
-- the calibre is defined here, because Lua lives only in
-- the main mod. extension names its feature
-- (AC_Features), which is on when the add-on is ticked.
--
-- LIST stays the vanilla calibres: the press, the spent
-- cases, loot and brass recycling are scripts of their
-- own and know nothing of an add-on's items. ALL is LIST
-- and the extensions whose add-on is in the game; it is
-- what identify(), get(), the recipe list, the material
-- units and casting read.
------------------------------------------------

AC_Calibres.EXTENSIONS = {

    ------------------------------------------------
    -- 7.62x39 of Vanilla Weapons Plus - Gunworks Edition
    -- (Workshop 3773834525, mod MarzVanillaGuns): item
    -- Base.762Bullets, AmmoType mvgi:bullets_762, the
    -- AK-47's, a box of 20 (its own OpenBoxOfBullets20
    -- recipe). A rifle round loaded like the 5.56: small
    -- rifle primer, two cups, one bullet per copper scrap,
    -- three charges.
    ------------------------------------------------
    AC_Calibres.define({
        id = "7.62x39",
        class = "rifle",
        suffix = "762x39",
        -- Vanilla Firearms Expansion uses the same item.
        extension = { "calibre762x39", "packVFE" },
        -- The vanilla calibre whose item look and names the
        -- add-on's are made from (tests/render_addons.lua).
        template = ".308",
        round = "Base.762Bullets",
        box = "Base.762Box",
        roundsPerBox = 20,
        ammoType = "mvgi:bullets_762",
        -- VFE's firearms name the same item vfe:bullets_762.
        ammoTypes = { packVFE = "vfe:bullets_762" },
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
    }),

    ------------------------------------------------
    -- Shared by Vanilla Firearms Expansion and Rain's
    -- Firearms (both define Base.223Bullets).
    ------------------------------------------------
    AC_Calibres.define({
        id = ".223",
        class = "rifle",
        suffix = "223Rem",
        extension = { "packVFE", "packRains", "packRainsExpanded" },
        template = ".308",
        round = "Base.223Bullets",
        box = "Base.223Box",
        roundsPerBox = 20,
        ammoType = "vfe:bullets_223",
        -- Rain's firearms name it firearms:bullets_223.
        ammoTypes = { packRains = "firearms:bullets_223", packRainsExpanded = "firearms:bullets_223" },
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),

    ------------------------------------------------
    -- Rain's Firearms: its 7.62x51 is Base.762Bullets,
    -- the item Vanilla Firearms Expansion and Vanilla
    -- Weapons Plus use for 7.62x39. The add-ons cannot be
    -- loaded together (incompatible= in their mod.info).
    ------------------------------------------------
    AC_Calibres.define({
        id = "7.62x51",
        class = "rifle",
        suffix = "762x51",
        extension = { "packRains", "packRainsExpanded" },
        template = ".308",
        round = "Base.762Bullets",
        box = "Base.762Box",
        roundsPerBox = 50,
        ammoType = "firearms:bullets_762x51",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),

    ------------------------------------------------
    -- Base.762x39Bullets: Rain's Firearms and
    -- GaelGunStore.
    ------------------------------------------------
    AC_Calibres.define({
        id = "7.62x39 M43",
        class = "rifle",
        suffix = "762x39M43",
        extension = { "packRains", "packRainsExpanded", "packGaelGunStore" },
        template = ".308",
        round = "Base.762x39Bullets",
        box = "Base.762x39Box",
        roundsPerBox = 30,
        ammoType = "firearms:bullets_762x39",
        -- GaelGunStore's firearms name it ggs:762x39_bullets.
        ammoTypes = { packGaelGunStore = "ggs:762x39_bullets" },
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
    }),

    ------------------------------------------------
    -- Rain's Firearms Expanded.
    ------------------------------------------------
    AC_Calibres.define({
        id = ".45-70",
        class = "rifle",
        suffix = "4570Gov",
        extension = { "packRainsExpanded" },
        template = ".308",
        round = "Base.4570Bullets",
        box = "Base.4570Box",
        roundsPerBox = 50,
        ammoType = "hiraeth:bullets_4570",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 4,
    }),
    AC_Calibres.define({
        id = ".45 Colt",
        class = "pistol",
        suffix = "45Colt",
        extension = { "packRainsExpanded" },
        template = ".357 Magnum",
        round = "Base.45ColtBullets",
        box = "Base.45ColtBulletsBox",
        roundsPerBox = 50,
        ammoType = "hiraeth:bullets_45colt",
        primerFamily = "LargePistol",
        cupsPerCase = 1,
        bulletsPerScrap = 1,
        powderUses = 2,
        assembleLevel = 4,
    }),
    AC_Calibres.define({
        id = "7.63x25",
        class = "pistol",
        suffix = "763x25",
        extension = { "packRainsExpanded" },
        template = ".357 Magnum",
        round = "Base.763x25Bullets",
        box = "Base.Bullets76325Box",
        roundsPerBox = 50,
        ammoType = "hiraeth:bullets_76325",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),

    ------------------------------------------------
    -- GaelGunStore (its .22 LR is rimfire: the priming
    -- is in the rim, it is not reloaded).
    ------------------------------------------------
    AC_Calibres.define({
        id = ".32 ACP",
        class = "pistol",
        suffix = "32ACP",
        extension = { "packGaelGunStore" },
        template = ".357 Magnum",
        round = "Base.Bullets32",
        box = "Base.Bullets32Box",
        roundsPerBox = 50,
        ammoType = "ggs:bullets_32",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),
    AC_Calibres.define({
        id = "9x39",
        class = "rifle",
        suffix = "9x39",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.9x39Bullets",
        box = "Base.9x39Box",
        roundsPerBox = 30,
        ammoType = "ggs:9x39_bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 2,
    }),
    AC_Calibres.define({
        id = "5.45x39",
        class = "rifle",
        suffix = "545x39",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.545x39Bullets",
        box = "Base.545x39Box",
        roundsPerBox = 30,
        ammoType = "ggs:545x39_bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "7.62x54R",
        class = "rifle",
        suffix = "762x54R",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.762x54rBullets",
        box = "Base.762x54rBox",
        roundsPerBox = 20,
        ammoType = "ggs:762x54r_bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = "7.92x57",
        class = "rifle",
        suffix = "792x57",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.792x57Bullets",
        box = "Base.792x57Box",
        roundsPerBox = 20,
        ammoType = "ggs:792x57_bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = ".30-06",
        class = "rifle",
        suffix = "3006Spr",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.30_06Bullets",
        box = "Base.30_06Box",
        roundsPerBox = 20,
        ammoType = "ggs:30_06_bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = ".303 British",
        class = "rifle",
        suffix = "303Brit",
        extension = { "packGaelGunStore" },
        template = ".308",
        round = "Base.303Bullets",
        box = "Base.303Box",
        roundsPerBox = 20,
        ammoType = "ggs:303_bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = ".50 AE",
        class = "pistol",
        suffix = "50AE",
        extension = { "packGaelGunStore" },
        template = ".357 Magnum",
        round = "Base.Bullets50Magnum",
        box = "Base.Bullets50MagnumBox",
        roundsPerBox = 30,
        ammoType = "ggs:bullets_50magnum",
        primerFamily = "LargePistol",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
        assembleLevel = 5,
    }),

    ------------------------------------------------
    -- Base.Bullets50: GaelGunStore and Modern Firearms
    -- System. A heavy round, at level 6.
    ------------------------------------------------
    AC_Calibres.define({
        id = ".50 BMG",
        class = "rifle",
        suffix = "50BMG",
        extension = { "packGaelGunStore", "packMFS" },
        template = ".308",
        round = "Base.Bullets50",
        box = "Base.Bullets50Box",
        roundsPerBox = 20,
        ammoType = "ggs:bullets_50",
        -- Modern Firearms System's name it efk:cat_bullets50.
        ammoTypes = { packMFS = "efk:cat_bullets50" },
        primerFamily = "LargeRifle",
        cupsPerCase = 6,
        bulletsPerScrap = 1,
        powderUses = 10,
        assembleLevel = 6,
    }),

    ------------------------------------------------
    -- Real Firearms: every round is an RF_ item of its
    -- own, so the calibres the mod already knows come
    -- again, marked (RF).
    ------------------------------------------------
    AC_Calibres.define({
        id = "9x19 (RF)",
        class = "pistol",
        suffix = "RF9x19",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_9x19Bullets",
        box = "Base.RF_9x19Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_9x19Bullets",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),
    AC_Calibres.define({
        id = "9x18 (RF)",
        class = "pistol",
        suffix = "RF9x18",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_9x18Bullets",
        box = "Base.RF_9x18Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_9x18Bullets",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),
    AC_Calibres.define({
        id = ".45 ACP (RF)",
        class = "pistol",
        suffix = "RF45ACP",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_45Bullets",
        box = "Base.RF_45Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_45Bullets",
        primerFamily = "LargePistol",
        cupsPerCase = 1,
        bulletsPerScrap = 1,
        powderUses = 1,
        assembleLevel = 4,
    }),
    AC_Calibres.define({
        id = ".357 Magnum (RF)",
        class = "pistol",
        suffix = "RF357Mag",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_357Bullets",
        box = "Base.RF_357Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_357Bullets",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 2,
        assembleLevel = 4,
    }),
    AC_Calibres.define({
        id = ".380 ACP (RF)",
        class = "pistol",
        suffix = "RF380ACP",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_380Bullets",
        box = "Base.RF_380Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_380Bullets",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),
    AC_Calibres.define({
        id = ".500 Magnum (RF)",
        class = "pistol",
        suffix = "RF500Mag",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_500Bullets",
        box = "Base.RF_500Box",
        roundsPerBox = 10,
        ammoType = "RealFirearms:RF_500Bullets",
        primerFamily = "LargePistol",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 4,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "7.62x25 (RF)",
        class = "pistol",
        suffix = "RF762x25",
        extension = { "packRealFirearms" },
        template = ".357 Magnum",
        round = "Base.RF_762x25Bullets",
        box = "Base.RF_762x25Box",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_762x25Bullets",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
    }),
    AC_Calibres.define({
        id = ".30 Carbine (RF)",
        class = "rifle",
        suffix = "RF30Carb",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_30CarbineBullets",
        box = "Base.RF_30CarbineBox",
        roundsPerBox = 50,
        ammoType = "RealFirearms:RF_30CarbineBullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 2,
    }),
    AC_Calibres.define({
        id = "5.45x39 (RF)",
        class = "rifle",
        suffix = "RF545x39",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_545x39Bullets",
        box = "Base.RF_545x39Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_545x39Bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "5.56x45 (RF)",
        class = "rifle",
        suffix = "RF556x45",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_556x45Bullets",
        box = "Base.RF_556x45Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_556x45Bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "7.62x39 (RF)",
        class = "rifle",
        suffix = "RF762x39",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_762x39Bullets",
        box = "Base.RF_762x39Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_762x39Bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "7.62x51 (RF)",
        class = "rifle",
        suffix = "RF762x51",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_762x51Bullets",
        box = "Base.RF_762x51Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_762x51Bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = "7.62x54R (RF)",
        class = "rifle",
        suffix = "RF762x54R",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_762x54Bullets",
        box = "Base.RF_762x54Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_762x54Bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = "7.92x33 (RF)",
        class = "rifle",
        suffix = "RF792x33",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_792x33Bullets",
        box = "Base.RF_792x33Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_792x33Bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "7.92x57 (RF)",
        class = "rifle",
        suffix = "RF792x57",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_792x57Bullets",
        box = "Base.RF_792x57Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_792x57Bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = ".30-06 (RF)",
        class = "rifle",
        suffix = "RF3006",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_3006Bullets",
        box = "Base.RF_3006Box",
        roundsPerBox = 30,
        ammoType = "RealFirearms:RF_3006Bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
    }),
    AC_Calibres.define({
        id = "12.7x55 (RF)",
        class = "rifle",
        suffix = "RF127x55",
        extension = { "packRealFirearms" },
        template = ".308",
        round = "Base.RF_127x55Bullets",
        box = "Base.RF_127x55Box",
        roundsPerBox = 10,
        ammoType = "RealFirearms:RF_127x55Bullets",
        primerFamily = "LargeRifle",
        cupsPerCase = 4,
        bulletsPerScrap = 1,
        powderUses = 6,
        assembleLevel = 6,
    }),
    AC_Calibres.define({
        id = "12 Gauge (RF)",
        class = "shotgun",
        suffix = "RF12Ga",
        extension = { "packRealFirearms" },
        template = "12 Gauge",
        round = "Base.RF_12GaugeBullets",
        box = "Base.RF_12GaugeBox",
        roundsPerBox = 24,
        ammoType = "RealFirearms:RF_12GaugeBullets",
        primerFamily = "LargePistol",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 3,
        wads = 1,
    }),

    ------------------------------------------------
    -- Modern Firearms System (its Bullets38 is a 6.8mm,
    -- see AC_Compat; .50 BMG above).
    ------------------------------------------------
    AC_Calibres.define({
        id = "5.8x42",
        class = "rifle",
        suffix = "58x42",
        extension = { "packMFS" },
        template = ".308",
        round = "Base.A_58bullets",
        box = "Base.58Box",
        roundsPerBox = 50,
        ammoType = "efk:cat_58bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "5.45x39 (MFS)",
        class = "rifle",
        suffix = "545MFS",
        extension = { "packMFS" },
        template = ".308",
        round = "Base.545Bullets",
        box = "Base.545Box",
        roundsPerBox = 50,
        ammoType = "efk:cat_545bullets",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
    }),
    AC_Calibres.define({
        id = "8.6mm",
        class = "rifle",
        suffix = "86mm",
        extension = { "packMFS" },
        template = ".308",
        round = "Base.Bullets86",
        box = "Base.Bullets86Box",
        roundsPerBox = 50,
        ammoType = "efk:cat_bullets86",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 7,
        assembleLevel = 6,
    }),
    AC_Calibres.define({
        id = "14.5mm",
        class = "rifle",
        suffix = "145mm",
        extension = { "packMFS" },
        template = ".308",
        round = "Base.Bullets145",
        box = "Base.Bullets145Box",
        roundsPerBox = 20,
        ammoType = "efk:cat_bullets145",
        primerFamily = "LargeRifle",
        cupsPerCase = 8,
        bulletsPerScrap = 1,
        powderUses = 16,
        assembleLevel = 6,
    }),

    ------------------------------------------------
    -- Guns of 93: B42 Test Build (Workshop 3183820077,
    -- mod guns93; AmmoType keys from its registries.lua,
    -- read 2026-10-18). Its .22 is rimfire; its 5.56 and
    -- .308 belts are machine-gun links; both left out. Its
    -- slugs are an item of their own (Base.SlugBullets),
    -- unlike vanilla's one shell, so they are a calibre.
    ------------------------------------------------
    AC_Calibres.define({
        id = "10mm Auto",
        class = "pistol",
        suffix = "10mmG93",
        extension = { "packGuns93" },
        template = ".357 Magnum",
        round = "Base.10mmBullets",
        box = "Base.10mmBox",
        roundsPerBox = 50,
        ammoType = "guns93:bullets_10mm",
        primerFamily = "LargePistol",
        cupsPerCase = 1,
        bulletsPerScrap = 1,
        powderUses = 2,
        assembleLevel = 4,
    }),
    AC_Calibres.define({
        id = ".25 ACP",
        class = "pistol",
        suffix = "25ACPG93",
        extension = { "packGuns93" },
        template = ".357 Magnum",
        round = "Base.25Bullets",
        box = "Base.25Box",
        roundsPerBox = 100,
        ammoType = "guns93:bullets_25",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = ".30-06 (G93)",
        class = "rifle",
        suffix = "3006G93",
        extension = { "packGuns93" },
        template = ".308",
        round = "Base.3006Bullets",
        box = "Base.3006Box",
        roundsPerBox = 20,
        ammoType = "guns93:bullets_3006",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = ".30 Carbine",
        class = "rifle",
        suffix = "30CarbineG93",
        extension = { "packGuns93" },
        template = ".308",
        round = "Base.30CarBullets",
        box = "Base.30CarBox",
        roundsPerBox = 20,
        ammoType = "guns93:bullets_30car",
        primerFamily = "SmallRifle",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 2,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = ".380 ACP",
        class = "pistol",
        suffix = "380ACPG93",
        extension = { "packGuns93" },
        template = ".357 Magnum",
        round = "Base.380Bullets",
        box = "Base.380Box",
        roundsPerBox = 50,
        ammoType = "guns93:bullets_380",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = ".40 S&W",
        class = "pistol",
        suffix = "40SWG93",
        extension = { "packGuns93" },
        template = ".357 Magnum",
        round = "Base.40Bullets",
        box = "Base.40Box",
        roundsPerBox = 50,
        ammoType = "guns93:bullets_40",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = ".45 Colt (G93)",
        class = "pistol",
        suffix = "45ColtG93",
        extension = { "packGuns93" },
        template = ".357 Magnum",
        round = "Base.45LCBullets",
        box = "Base.45LCBox",
        roundsPerBox = 50,
        ammoType = "guns93:bullets_45lc",
        primerFamily = "LargePistol",
        cupsPerCase = 1,
        bulletsPerScrap = 1,
        powderUses = 2,
        assembleLevel = 4,
    }),
    AC_Calibres.define({
        id = "7.62x39 (G93)",
        class = "rifle",
        suffix = "762x39G93",
        extension = { "packGuns93" },
        template = ".308",
        round = "Base.76239Bullets",
        box = "Base.76239Box",
        roundsPerBox = 20,
        ammoType = "guns93:bullets_76239",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "7.92x57 (G93)",
        class = "rifle",
        suffix = "792x57G93",
        extension = { "packGuns93" },
        template = ".308",
        round = "Base.792Bullets",
        box = "Base.792Box",
        roundsPerBox = 20,
        ammoType = "guns93:bullets_792",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "12 Gauge Slug",
        class = "shotgun",
        suffix = "12GaSlugG93",
        extension = { "packGuns93" },
        template = "12 Gauge",
        round = "Base.SlugBullets",
        box = "Base.SlugBulletBox",
        roundsPerBox = 25,
        ammoType = "guns93:bullets_slug",
        primerFamily = "LargePistol",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 3,
        wads = 1,
        assembleLevel = 4,
    }),

    ------------------------------------------------
    -- Post Soviet Armory B42 (Workshop 3722136144, mod
    -- PostSovietArmoryB42; keys
    -- Post_Soviet_Armory_B42:<item, lower case>). Its
    -- .22 LR is rimfire; its 7.65x21 has no firearm.
    -- 23x75 is the KS-23's 4-gauge shell: twice the 12
    -- gauge's brass and powder, two wads.
    ------------------------------------------------
    AC_Calibres.define({
        id = "9x18",
        class = "pistol",
        suffix = "9x18PSA",
        extension = { "packPSA" },
        template = ".357 Magnum",
        round = "Base.Bullets9x18mm",
        box = "Base.Bullets9x18mm_Box",
        roundsPerBox = 16,
        ammoType = "Post_Soviet_Armory_B42:bullets9x18mm",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = "9x19",
        class = "pistol",
        suffix = "9x19PSA",
        extension = { "packPSA" },
        template = ".357 Magnum",
        round = "Base.Bullets9x19mm",
        box = "Base.Bullets9x19mm_Box",
        roundsPerBox = 30,
        ammoType = "Post_Soviet_Armory_B42:bullets9x19mm",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = "9x39 (PSA)",
        class = "rifle",
        suffix = "9x39PSA",
        extension = { "packPSA" },
        template = ".308",
        round = "Base.Bullets9x39mm",
        box = "Base.Bullets9x39mm_Box",
        roundsPerBox = 10,
        ammoType = "Post_Soviet_Armory_B42:bullets9x39mm",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 2,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "5.45x39 (PSA)",
        class = "rifle",
        suffix = "545x39PSA",
        extension = { "packPSA" },
        template = ".308",
        round = "Base.Bullets545x39",
        box = "Base.Bullets545x39_Box",
        roundsPerBox = 30,
        ammoType = "Post_Soviet_Armory_B42:bullets545x39",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 2,
        powderUses = 3,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "7.62x25",
        class = "pistol",
        suffix = "762x25PSA",
        extension = { "packPSA" },
        template = ".357 Magnum",
        round = "Base.Bullets762x25",
        box = "Base.Bullets762x25_Box",
        roundsPerBox = 40,
        ammoType = "Post_Soviet_Armory_B42:bullets762x25",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = "7.62x38R",
        class = "pistol",
        suffix = "762x38RPSA",
        extension = { "packPSA" },
        template = ".357 Magnum",
        round = "Base.Bullets762x38R",
        box = "Base.Bullets762x38R_Box",
        roundsPerBox = 14,
        ammoType = "Post_Soviet_Armory_B42:bullets762x38r",
        primerFamily = "SmallPistol",
        cupsPerCase = 1,
        bulletsPerScrap = 2,
        powderUses = 1,
        assembleLevel = 3,
    }),
    AC_Calibres.define({
        id = "7.62x39 (PSA)",
        class = "rifle",
        suffix = "762x39PSA",
        extension = { "packPSA" },
        template = ".308",
        round = "Base.Bullets762x39",
        box = "Base.Bullets762x39_Box",
        roundsPerBox = 30,
        ammoType = "Post_Soviet_Armory_B42:bullets762x39",
        primerFamily = "SmallRifle",
        cupsPerCase = 2,
        bulletsPerScrap = 1,
        powderUses = 3,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "7.62x54R (PSA)",
        class = "rifle",
        suffix = "762x54RPSA",
        extension = { "packPSA" },
        template = ".308",
        round = "Base.Bullets762x54R",
        box = "Base.Bullets762x54R_Box",
        roundsPerBox = 20,
        ammoType = "Post_Soviet_Armory_B42:bullets762x54r",
        primerFamily = "LargeRifle",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 5,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "23x75",
        class = "shotgun",
        suffix = "23x75PSA",
        extension = { "packPSA" },
        template = "12 Gauge",
        round = "Base.23x75ShotgunShells",
        box = "Base.23x75ShotgunShells_Box",
        roundsPerBox = 8,
        ammoType = "Post_Soviet_Armory_B42:23x75shotgunshells",
        primerFamily = "LargePistol",
        cupsPerCase = 6,
        bulletsPerScrap = 1,
        powderUses = 6,
        wads = 2,
        assembleLevel = 5,
    }),
    AC_Calibres.define({
        id = "12x70",
        class = "shotgun",
        suffix = "12x70PSA",
        extension = { "packPSA" },
        template = "12 Gauge",
        round = "Base.12x70ShotgunShells",
        box = "Base.12x70ShotgunShells_Box",
        roundsPerBox = 10,
        ammoType = "Post_Soviet_Armory_B42:12x70shotgunshells",
        primerFamily = "LargePistol",
        cupsPerCase = 3,
        bulletsPerScrap = 1,
        powderUses = 3,
        wads = 1,
        assembleLevel = 4,
    }),
}


-- The features (add-ons) an extension calibre comes with:
-- extension is one feature id or a list of them.
function AC_Calibres.extensionFeatures(
    calibre
)

    local extension =
        calibre and calibre.extension


    if type(extension) == "table" then
        return extension
    end


    if type(extension) == "string" then
        return { extension }
    end


    return {}
end


-- The AmmoType a pack's gun mod gives the calibre's
-- round. A round several gun mods share is the same item
-- under a key of each mod's own (ammoTypes, by feature);
-- ammoType is the first pack's. Read from the installed
-- gun mods; tests/engine_snapshot.lua records what their
-- firearms name (gunMods).
function AC_Calibres.ammoTypeOf(
    calibre,
    feature
)

    local byPack =
        calibre.ammoTypes


    return
        byPack
        and byPack[feature]
        or calibre.ammoType
end


-- Is the extension calibre in the game: any of its
-- add-ons ticked.
function AC_Calibres.isExtensionActive(
    calibre
)

    for _,
        feature
    in ipairs(
        AC_Calibres.extensionFeatures(calibre)
    )
    do

        if AC_Features.hasContent(feature) then
            return true
        end
    end


    return false
end


-- The extensions whose add-on is in the game.
function AC_Calibres.getActiveExtensions()

    local active = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.EXTENSIONS
    )
    do

        if AC_Calibres.isExtensionActive(calibre) then

            table.insert(
                active,
                calibre
            )
        end
    end


    return active
end


AC_Calibres.ALL = {}


for _,
    calibre
in ipairs(
    AC_Calibres.LIST
)
do

    table.insert(
        AC_Calibres.ALL,
        calibre
    )
end


for _,
    calibre
in ipairs(
    AC_Calibres.getActiveExtensions()
)
do

    table.insert(
        AC_Calibres.ALL,
        calibre
    )
end


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


        -- A bullet mould is the mod's own item and belongs
        -- to one class.
        if class.mould ~= nil then

            if type(class.mould) ~= "string"
                or string.sub(class.mould, 1, 11) ~= "AmmoMaking."
            then

                problem("class " .. className, "the mould must be an item of the mod")

            elseif itemOwner[class.mould] then

                problem("class " .. className, "mould item " .. class.mould .. " is already used by " .. itemOwner[class.mould])

            else

                itemOwner[class.mould] = "class " .. className .. " mould"
            end
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


        -- The cast bullet: only where the class has a
        -- mould, and like every component it belongs to one
        -- calibre.
        local mould =
            (AC_Calibres.CLASSES[calibre.class] or {}).mould


        if calibre.castBullet ~= nil then

            if not mould then

                problem(name, "a " .. tostring(calibre.class) .. " calibre has no cast bullet: its class has no mould")

            elseif type(calibre.castBullet) ~= "string"
                or calibre.castBullet == ""
            then

                problem(name, "no castBullet item")

            elseif itemOwner[calibre.castBullet] then

                problem(name, "castBullet item " .. calibre.castBullet .. " is already used by " .. itemOwner[calibre.castBullet])

            else

                itemOwner[calibre.castBullet] = name .. " castBullet"
            end

        elseif mould then

            problem(name, "its class has a mould but it has no cast bullet")
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
        AC_Calibres.ALL
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
-- Returns kind ("case", "bullet", "castBullet", "dieSet",
-- "round", "primer") and the calibre or primer definition, or
-- nil for anything else.
------------------------------------------------

-- The item roles of a calibre, in the order identify()
-- tries them. One table, not one per call: identify()
-- runs for every item of an inventory right-click. A
-- calibre without a cast bullet simply never matches it.
local ITEM_KINDS = { "case", "bullet", "castBullet", "dieSet", "round" }


function AC_Calibres.identify(
    fullType
)

    for _,
        calibre
    in ipairs(
        AC_Calibres.ALL
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


-- A calibre's die set. Kept, never consumed; it wears
-- (DIE_WEAR).
local function dieSet(calibre)

    return {
        count = 1,
        items = { calibre.dieSet },
        keep = true,
        flags = { AC_Calibres.DIE_WEAR.flag },
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

-- What a press recipe is called, from its hand recipe's
-- name: " (Press)" added, or ", Press" inside a name that
-- already ends in a bracket ("... (Cast Bullet, Press)").
function AC_Calibres.pressName(
    handName
)

    handName =
        tostring(handName or "")


    if string.sub(handName, -1) == ")" then

        return
            string.sub(handName, 1, -2)
            .. ", "
            .. string.match(AC_Calibres.PRESS.nameSuffix, "%(([^)]*)%)")
            .. ")"
    end


    return handName .. AC_Calibres.PRESS.nameSuffix
end


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


    -- The calibre's own steps, then its cast assembly.
    local hands =
        AC_Calibres.buildCalibreRecipes(calibre)


    if AC_Casting then

        for _,
            cast
        in ipairs(
            AC_Casting.buildCalibreRecipes(calibre)
        )
        do

            table.insert(
                hands,
                cast
            )
        end
    end


    for _,
        hand
    in ipairs(
        hands
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
    local known = { case = true, bullet = true, assemble = true, assembleCast = true }


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
        AC_Calibres.ALL
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


        -- An extension's add-on carries its press and
        -- spent-case recipes, so they are there whenever
        -- its content is.
        if calibre.extension then

            for _,
                recipe
            in ipairs(
                AC_Calibres.buildExtensionExtras(calibre)
            )
            do

                table.insert(
                    recipes,
                    recipe
                )
            end

        -- Off until the press station exists.
        elseif AC_Calibres.PRESS.enabled then

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

-- The same for the spent cases: a fired case holds the
-- brass of the case it was, and never more (the primer
-- cup goes with the primer). Kept apart from
-- buildUnits(): the items exist only with the spent-cases
-- add-on, and AC_Materials takes these in only when that
-- feature is on.
-- Another mod's ejected casings (field: hotBrassCasing
-- for the Hot Brass bridge, mfsCasing for the Modern
-- Firearms System pack): the brass of the case they
-- were, like a spent case of the mod.
function AC_Calibres.buildCasingUnits(
    field
)

    local units = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if calibre[field] then

            units[calibre[field]] = {
                metal = "brass",
                units = AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase,
            }
        end
    end


    return units
end


function AC_Calibres.buildHotBrassUnits()

    return
        AC_Calibres.buildCasingUnits(
            "hotBrassCasing"
        )
end


function AC_Calibres.buildSpentUnits(
    list
)

    local units = {}


    for _,
        calibre
    in ipairs(
        list or AC_Calibres.LIST
    )
    do

        units[calibre.spentCase] = {
            metal = "brass",
            units = AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase,
        }
    end


    return units
end


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
        AC_Calibres.ALL
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


    -- The vanilla blowtorch the annealing takes.
    add(AC_Calibres.ANNEAL.item)


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
