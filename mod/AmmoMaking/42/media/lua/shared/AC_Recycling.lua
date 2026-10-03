-- Ammo Making - Brass recycling
-- Project Zomboid Build 42.20
--
-- Brass components nobody needs any more - case cups,
-- small sheets, empty cases and hulls of a calibre the
-- player has stopped loading - can be hammered into
-- vanilla brass scrap, and brass scrap can be cast back
-- into a brass ingot.
--
-- Two rules, both enforced by validate() and the tests:
--
--   IT LOSES MATERIAL. Scrapping hands back half of the
--   brass. Making something, scrapping it and making it
--   again always ends with less brass than it started
--   with.
--
--   IT TEACHES NOTHING. Every recycling recipe awards 0
--   Ammo Making XP, so scrapping and re-forming is not a
--   way to grind the skill for free: each round trip costs
--   half of the brass, a furnace, charcoal and time, and
--   a case that is scrapped and formed again can never
--   return the XP its assembly would have given
--   (docs/LOOT_AND_RECYCLING.md, section 2.4).
--
-- What is NOT recycled, deliberately:
--
--   finished rounds   vanilla already takes a round apart
--                     for one use of gunpowder
--                     (GatherGunpowder, tags[base:ammo]); a
--                     second way out of a round would be a
--                     duplication loop
--   primers           scrapping one would destroy priming
--                     compound for a unit or two of brass
--   bullets and shot  they are copper, and two bullets are
--                     exactly one scrap: nothing to lose
--
-- Base.BrassScrap is the vanilla item. No recipe of
-- vanilla 42.20.4 consumes it and almost none of it is
-- loot (docs/LOOT_AND_RECYCLING.md), so this is what gives
-- it a use.
--
-- The recipes are ordinary craftRecipe blocks, generated
-- like every other one (AC_Materials appends them to its
-- RECIPES; tests/write_recipes.lua renders the script).
-- Nothing here persists anything.

require "AC_Features"
require "AC_Calibres"

AC_Recycling = AC_Recycling or {}


------------------------------------------------
-- CONFIG
------------------------------------------------
--
-- Tunable. Brass is counted in the units of AC_Materials:
-- 100 per ingot, 10 per scrap or small sheet, 5 per case
-- cup.
--
-- A scrapping recipe takes a batch of components worth a
-- whole number of batchUnits and hands back scrapPerBatch
-- brass scrap for each. With 20 and 1 that is 10 units out
-- of 20: half recovered, half lost. 50 and 3 would be
-- three fifths; anything that loses nothing is refused by
-- validate().
--
-- Half is not arbitrary. Above about 58 % a 12 gauge hull
-- that is scrapped and formed over and over would earn
-- more XP than loading it into a shell, and recycling
-- would be the better way to train (the tests pin this).
------------------------------------------------

AC_Recycling.CONFIG = {

    scrapItem = "Base.BrassScrap",

    ingotItem = "Base.BrassIngot",

    batchUnits = 20,

    scrapPerBatch = 1,

    -- Brass scrap melted into one ingot, with nothing lost:
    -- the same ten-to-one as copper and zinc scrap.
    scrapPerIngot = 10,

    -- Brass in one ingot (AC_Materials.CONFIG.unitsPerIngot;
    -- that file loads after this one).
    ingotUnits = 100,

    -- Recycling teaches nothing. validate() refuses any
    -- other value.
    xp = 0,

    requiredLevel = 0,

    scrapTime = 100,

    castTime = 200,

    castCharcoal = 4,

    idPrefix = "AmmoMaking_ScrapBrass",

    castId = "AmmoMaking_CastBrassIngotFromScrap",
}


local function gcd(
    a,
    b
)

    while b ~= 0 do
        a, b = b, a % b
    end


    return a
end


------------------------------------------------
-- WHAT CAN BE SCRAPPED
------------------------------------------------
--
-- item -> brass units, for everything that is nothing but
-- brass: the case cup, the small sheet, and every
-- calibre's case or hull. Taken from the calibre model, so
-- a new calibre's case is recyclable without an edit here.
------------------------------------------------

function AC_Recycling.getScrappable()

    local config =
        AC_Calibres.CONFIG


    local units = {

        ["AmmoMaking.BrassCaseCup"] = config.cupUnits,

        ["AmmoMaking.SmallBrassSheet"] = config.sheetUnits,
    }


    local order = {
        "AmmoMaking.BrassCaseCup",
        "AmmoMaking.SmallBrassSheet",
    }


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if units[calibre.case] == nil then

            table.insert(
                order,
                calibre.case
            )
        end


        units[calibre.case] =
            config.cupUnits * calibre.cupsPerCase
    end


    return units, order
end


------------------------------------------------
-- SOURCES
------------------------------------------------
--
-- A source is one kind of brass that can be scrapped,
-- with its own recovery. Everything below (groups,
-- recipes, validation) takes a source as data, so a
-- second kind is a second entry here and no second copy
-- of the logic:
--
--   id             names the source
--   idPrefix       recipe ids are idPrefix .. brass units
--   callbackPrefix the OnCreate names, likewise
--   batchUnits, scrapPerBatch
--                  the recovery: scrapPerBatch brass scrap
--                  for every batchUnits of brass
--   components     function returning item -> units, and
--                  the items in a stable order
--
-- Listed cleanest first, and validate() refuses a later
-- source that returns more than an earlier one:
--
--   clean   unused components, at the recovery of CONFIG.
--           Always there.
--   spent   fired cases, at the lower recovery of SPENT.
--           There only when the feature "spentCases" is
--           on (AC_Features): its items and its recipe
--           scripts are in the spent-cases add-on, so
--           without the add-on no recipe is left that
--           nothing can craft.
--
-- A future "damaged brass" class is a third entry here.
------------------------------------------------

------------------------------------------------
-- SPENT BRASS (tunable)
------------------------------------------------
--
-- batchUnits 40, scrapPerBatch 1: ten units of scrap for
-- forty units of spent brass, a quarter. Half of what
-- unused components return. With the half of fired cases
-- that is never found (AC_SpentCases.CONFIG
-- .recoveryPercent), one round's brass in eight comes
-- back.
--
-- names: what each scrapping recipe is called, by the
-- brass units of the cases it takes.
------------------------------------------------

AC_Recycling.SPENT = {

    batchUnits = 40,

    scrapPerBatch = 1,

    idPrefix = "AmmoMaking_ScrapSpentBrass",

    callbackPrefix = "onScrapSpentBrass",

    names = {
        [5] = "Scrap Spent Small Cases",
        [10] = "Scrap Spent Medium Cases",
        [15] = "Scrap Spent Large Cases and Hulls",
    },

    fallbackName = "Scrap Spent Brass",
}


-- item -> brass units for every calibre's spent case: the
-- brass of the case it was. The fired primer cup is
-- thrown away with the primer.
function AC_Recycling.getSpentScrappable()

    local units = {}

    local order = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        if units[calibre.spentCase] == nil then

            table.insert(
                order,
                calibre.spentCase
            )
        end


        units[calibre.spentCase] =
            AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase
    end


    return units, order
end


-- The spent source, whether or not the feature is on (the
-- add-on's recipe script is generated from it).
function AC_Recycling.getSpentSource()

    local spent =
        AC_Recycling.SPENT


    return {
        id = "spent",

        idPrefix = spent.idPrefix,

        callbackPrefix = spent.callbackPrefix,

        batchUnits = spent.batchUnits,

        scrapPerBatch = spent.scrapPerBatch,

        components = AC_Recycling.getSpentScrappable,
    }
end


-- What a spent scrapping recipe is called.
function AC_Recycling.getSpentRecipeName(
    recipe
)

    local spent =
        AC_Recycling.SPENT


    local units =
        tonumber(
            string.match(
                tostring(recipe and recipe.id),
                "(%d+)$"
            )
        )


    return
        spent.names[units]
        or (spent.fallbackName .. " (" .. tostring(units) .. ")")
end


function AC_Recycling.getSources()

    local config =
        AC_Recycling.CONFIG


    local sources = {
        {
            id = "clean",

            idPrefix = config.idPrefix,

            callbackPrefix = "onScrapBrass",

            batchUnits = config.batchUnits,

            scrapPerBatch = config.scrapPerBatch,

            components = AC_Recycling.getScrappable,
        },
    }


    if AC_Features.hasContent("spentCases") then

        table.insert(
            sources,
            AC_Recycling.getSpentSource()
        )
    end


    return sources
end


------------------------------------------------
-- GROUPS
------------------------------------------------
--
-- Components of the same brass content share a recipe:
-- one input line that accepts any of them. A list of
--
--   { units, items = { ... }, count, scrap }
--
-- sorted by units. count is the fewest components whose
-- brass is a whole number of batches; scrap is what they
-- return.
--
--   5 units   cup, one-cup cases        4 -> 1 scrap
--   10 units  small sheet, two-cup      2 -> 1 scrap
--   15 units  three-cup cases, hull     4 -> 3 scrap
--
-- source defaults to the first of getSources().
------------------------------------------------

function AC_Recycling.buildGroups(
    source
)

    local config =
        source or AC_Recycling.getSources()[1]


    local units,
          order =
        config.components()


    local byUnits = {}

    local groups = {}


    for _,
        itemType
    in ipairs(
        order
    )
    do

        local value =
            units[itemType]


        local group =
            byUnits[value]


        if not group then

            local count =
                config.batchUnits / gcd(value, config.batchUnits)


            group = {

                units = value,

                items = {},

                count = count,

                scrap = count * value / config.batchUnits * config.scrapPerBatch,
            }


            byUnits[value] = group


            table.insert(
                groups,
                group
            )
        end


        table.insert(
            group.items,
            itemType
        )
    end


    table.sort(
        groups,
        function(a, b)

            return
                a.units < b.units
        end
    )


    return groups
end


------------------------------------------------
-- RECIPES
------------------------------------------------
--
-- One scrapping recipe per group of each source, cold,
-- on any surface, with a hammer (the line the cup and
-- case recipes use), and one furnace recipe that casts
-- ten brass scrap into an ingot (the lines of the copper
-- and zinc casting recipes).
--
-- recycling = true marks them for the checks; loss = true
-- marks the ones that must end with less brass than they
-- took; recyclingSource names the source a scrapping
-- recipe belongs to.
--
-- sources defaults to getSources().
------------------------------------------------

local function scrapRecipe(
    source,
    group
)

    local config =
        AC_Recycling.CONFIG


    return {
        id = source.idPrefix .. group.units,

        step = "scrap",

        time = config.scrapTime,

        timedAction = "MakingHammer_Surface",

        benchTag = "AnySurfaceCraft",

        category = "Metalworking",

        callback = source.callbackPrefix .. group.units,

        xp = config.xp,

        requiredLevel = config.requiredLevel,

        recycling = true,

        recyclingSource = source.id,

        loss = true,

        inputs = {
            { count = group.count, items = group.items },
            {
                count = 1,
                tags = { "base:hammer" },
                keep = true,
                flags = { "MayDegradeVeryLight" },
            },
        },

        outputs = {
            { count = group.scrap, item = config.scrapItem },
        },
    }
end


function AC_Recycling.buildRecipes(
    sources
)

    local config =
        AC_Recycling.CONFIG


    local recipes = {}


    for _,
        source
    in ipairs(
        sources or AC_Recycling.getSources()
    )
    do

        for _,
            group
        in ipairs(
            AC_Recycling.buildGroups(source)
        )
        do

            table.insert(
                recipes,
                scrapRecipe(
                    source,
                    group
                )
            )
        end
    end


    table.insert(
        recipes,
        {
            id = config.castId,

            step = "recast",

            time = config.castTime,

            benchTag = "Furnace",

            category = "Blacksmithing",

            callback = "onCastBrassIngotFromScrap",

            xp = config.xp,

            requiredLevel = config.requiredLevel,

            recycling = true,

            inputs = {
                {
                    count = 1,
                    items = { "Base.CeramicCrucible" },
                    keep = true,
                    flags = { "IsEmpty" },
                },
                {
                    count = 1,
                    tags = { "base:crudetongs", "base:tongs" },
                    keep = true,
                    flags = { "MayDegradeLight" },
                },
                { count = config.castCharcoal, tags = { "base:charcoal" } },
                { count = config.scrapPerIngot, items = { config.scrapItem } },
                {
                    count = 1,
                    items = { "Base.ClayIngotMold", "Base.IronIngotMold", "Base.SteelIngotMold" },
                    keep = true,
                },
            },

            outputs = {
                { count = 1, item = config.ingotItem },
            },
        }
    )


    return recipes
end


------------------------------------------------
-- Share of the brass a source's scrapping recipes hand
-- back, as a fraction (0.5 with the values above).
-- source defaults to the first of getSources().
------------------------------------------------

function AC_Recycling.getRecovery(
    source
)

    local config =
        source or AC_Recycling.getSources()[1]


    return
        config.scrapPerBatch * AC_Calibres.CONFIG.scrapUnits / config.batchUnits
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- Returns a list of problems, empty when recycling is
-- sound: it loses brass, it awards nothing, and every
-- amount is a whole number.
--
-- recipes defaults to buildRecipes(sources), sources to
-- getSources().
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


function AC_Recycling.validate(
    recipes,
    sources
)

    local config =
        AC_Recycling.CONFIG


    sources =
        sources or AC_Recycling.getSources()


    local scrapUnits =
        AC_Calibres.CONFIG.scrapUnits


    local problems = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "recycling: " .. text
        )
    end


    if not isWhole(config.scrapPerIngot, 1) then

        problem("batch and scrap amounts must be whole and positive")


        return problems
    end


    -- Every source loses brass, and a source listed later
    -- (dirtier) never returns more than one listed earlier.
    local previous = nil

    local sourceIds = {}


    for _,
        source
    in ipairs(
        sources
    )
    do

        local label =
            tostring(source.id)


        if sourceIds[label] then
            problem("source " .. label .. " is listed twice")
        end


        sourceIds[label] = true


        if not isWhole(source.batchUnits, 1)
            or not isWhole(source.scrapPerBatch, 1)
        then

            problem("batch and scrap amounts must be whole and positive")


            return problems
        end


        if source.scrapPerBatch * scrapUnits >= source.batchUnits then

            problem(
                "scrapping must lose brass: "
                .. source.scrapPerBatch * scrapUnits
                .. " units back for "
                .. source.batchUnits
            )
        end


        local recovery =
            AC_Recycling.getRecovery(source)


        if previous ~= nil
            and recovery > previous
        then
            problem("source " .. label .. " returns more brass than a cleaner source")
        end


        previous = recovery
    end


    if config.scrapPerIngot * scrapUnits < config.ingotUnits then

        problem(
            "an ingot of " .. config.ingotUnits .. " units cannot be cast from "
            .. config.scrapPerIngot * scrapUnits
            .. " units of scrap"
        )
    end


    if config.xp ~= 0 then
        problem("recycling must award no XP, not " .. tostring(config.xp))
    end


    -- Plain brass: every source's components, the scrap
    -- and the ingot.
    local units = {}

    local scrappable = {}


    for _,
        source
    in ipairs(
        sources
    )
    do

        for itemType,
            value
        in pairs(
            source.components()
        )
        do

            if units[itemType] ~= nil then
                problem(tostring(itemType) .. " belongs to two sources")
            end


            units[itemType] = value

            scrappable[itemType] = true
        end
    end


    units[config.scrapItem] = scrapUnits

    units[config.ingotItem] = config.ingotUnits


    recipes =
        recipes or AC_Recycling.buildRecipes(sources)


    local covered = {}


    for _,
        recipe
    in ipairs(
        recipes
    )
    do

        local name =
            tostring(recipe.id)


        if not recipe.recycling then
            problem(name .. " is not marked as recycling")
        end


        if recipe.xp ~= 0 then
            problem(name .. " awards XP")
        end


        local brassIn = 0

        local brassOut = 0


        for _,
            input
        in ipairs(
            recipe.inputs or {}
        )
        do

            if not input.keep
                and input.items
            then

                -- Every alternative of a line must hold the same
                -- brass; the smallest is what the line is worth.
                local least = nil


                for _,
                    itemType
                in ipairs(
                    input.items
                )
                do

                    local value =
                        units[itemType]


                    if value == nil then

                        problem(name .. " takes " .. tostring(itemType) .. ", which is not plain brass")

                    else

                        if least ~= nil
                            and value ~= least
                        then
                            problem(name .. " mixes components of different brass content")
                        end


                        if least == nil
                            or value < least
                        then
                            least = value
                        end


                        if recipe.loss then
                            covered[itemType] = (covered[itemType] or 0) + 1
                        end
                    end
                end


                if not isWhole(input.count, 1) then
                    problem(name .. " takes a fractional number of components")
                end


                brassIn =
                    brassIn + (least or 0) * (tonumber(input.count) or 0)
            end
        end


        for _,
            output
        in ipairs(
            recipe.outputs or {}
        )
        do

            if units[output.item] == nil then
                problem(name .. " makes " .. tostring(output.item) .. ", which is not plain brass")
            end


            if not isWhole(output.count, 1) then
                problem(name .. " makes a fractional number of items")
            end


            brassOut =
                brassOut + (units[output.item] or 0) * (tonumber(output.count) or 0)
        end


        if brassOut > brassIn then

            problem(name .. " creates brass: " .. brassOut .. " units from " .. brassIn)

        elseif recipe.loss
            and brassOut >= brassIn
        then

            problem(name .. " loses no brass: " .. brassOut .. " units from " .. brassIn)
        end
    end


    -- Each scrappable component is taken by exactly one
    -- scrapping recipe.
    for itemType in pairs(
        scrappable
    )
    do

        if (covered[itemType] or 0) ~= 1 then
            problem(tostring(itemType) .. " is taken by " .. (covered[itemType] or 0) .. " scrapping recipes")
        end
    end


    return problems
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Brass recycling loaded"
)
