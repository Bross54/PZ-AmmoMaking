-- Ammo Making - Die sets and a little reloading stock as rare loot
-- Project Zomboid Build 42.20
--
-- A die set can be forged (AC_Calibres) or, rarely, found.
-- This file adds each calibre's die set to a few vanilla
-- procedural loot lists, and (COMPONENTS, below) a small
-- amount of reloading stock: a jar of gunpowder, a loose
-- primer, brass scrap, a small brass sheet. Never a case,
-- a projectile or a round: those are what the player
-- manufactures, and validate() refuses them.
--
-- How vanilla loot works, as read in the installed 42.20.4
-- files (docs/AMMUNITION_ROADMAP.md, section 2):
--
--   ProceduralDistributions.list.<Name> = { rolls = N,
--       items = { "Item", weight, "Item", weight, ... } }
--   Distributions.lua names those lists per room and
--       container (procList = { { name = "<Name>", ... } }).
--   IsoWorld fires OnPreDistributionMerge,
--       OnDistributionMerge and OnPostDistributionMerge and
--       then calls ItemPickerJava.Parse(), which reads the
--       Lua tables once.
--   ItemPickerJava: for every roll and every entry,
--       Rand.Next(10000) < (weight * 100 * lootModifier
--       + zombieDensity) * lootMultiplier. A weight is the
--       percent chance per roll at default settings.
--
-- So the entries are inserted in an OnPreDistributionMerge
-- handler: every Lua file is loaded by then, whatever the
-- load order, and the parse has not happened yet.
--
-- A die set is DisplayCategory = Tool, so the engine files
-- it under the "Tool" loot type and the sandbox's tool loot
-- setting scales it (Item.isToolLoot, ItemPickerJava
-- .getLootType).
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the handler
-- runs before the parse on a real world load, and how often
-- a die set is actually met. The weights are deliberately
-- small.

require "AC_Calibres"

AC_Loot = AC_Loot or {}


------------------------------------------------
-- CONFIG
------------------------------------------------
--
-- Every loot number of the mod is in this file: the tier
-- weights here and each list's scale in TARGETS. Which
-- tier a calibre's die set belongs to is part of the
-- calibre (calibre.lootTier in AC_Calibres), so that no
-- calibre is named here and a new one needs no edit. An
-- entry's weight is
--
--   tierWeight[calibre.lootTier] * scale of the list
--
-- The limits are what validate() enforces, so a typo that
-- makes die sets common is refused and named.
------------------------------------------------

AC_Loot.CONFIG = {

    enabled = true,

    -- Percent chance per roll, before the list's scale.
    -- For comparison, in vanilla's own lists a reloading
    -- skill book is 1 to 0.2 and a punch set 2 to 8.
    tierWeight = {

        common = 1.0,

        uncommon = 0.6,

        rare = 0.3,
    },

    -- No single entry may weigh more than this.
    maxWeight = 1.0,

    -- All die sets of one list together may not weigh more
    -- than this: with four rolls, about an 18 % chance
    -- that a container filled from the list holds one.
    maxListWeight = 5.0,

    -- A calibre's die set may be in at most this many lists.
    maxListsPerCalibre = 4,

    -- COMPONENTS: no single entry may weigh more than
    -- this, and all components of one list together not
    -- more than that.
    maxComponentWeight = 2.0,

    maxComponentListWeight = 6.0,
}


------------------------------------------------
-- TARGETS
------------------------------------------------
--
-- list      a ProceduralDistributions.list name. Each one
--           was checked in the installed 42.20.4
--           Distributions.lua: it is named by at least one
--           container (tests/vanilla_snapshot.lua pins
--           that). Vanilla also carries lists nothing
--           uses - GunStoreCounter, GunStoreDisplayCase,
--           GunStoreShelf, PoliceStorageAmmunition,
--           MetalWorkerTools and about 180 more - and an
--           entry there would never spawn.
-- scale     multiplies the tier weight.
-- classes   the calibre classes (AC_Calibres.CLASSES)
--           whose die sets the list gets; left out, every
--           class.
-- where     which containers vanilla fills from the list
--           (Distributions.lua, 42.20.4), for the
--           documentation. Not read by any logic.
--
-- Handgun dies turn up in a garage gun locker, long-gun
-- dies among a hunter's things, and all of them, a little
-- more often, in a gun store.
------------------------------------------------

AC_Loot.TARGETS = {

    -- GunStoreMagsAmmo, not GunStoreAccessories. Both are
    -- offered to a gun store's display cases with the
    -- same weight and at most once per store, so for a
    -- gun store the two are the same bet. But an army
    -- surplus store fills nearly every display case
    -- after its third from GunStoreAccessories (max =
    -- 99, and its other lists are used up): eight cases
    -- there would hold a whole die set on average,
    -- twelve times a gun store's share
    -- (docs/LOOT_AND_RECYCLING.md, 1.2).
    {
        list = "GunStoreMagsAmmo",

        scale = 1,

        where = "at most one display case of a gun store",
    },

    {
        list = "GarageFirearms",

        scale = 0.5,

        where = "the gun locker of a garage storage room; military lockers",

        classes = { "pistol" },
    },

    {
        list = "Hunter",

        scale = 0.5,

        where = "a hunter's things in an attic, closet, hall, living room, storage unit or garage",

        classes = { "rifle", "shotgun" },
    },

    {
        list = "HuntingLockers",

        scale = 0.5,

        where = "the lockers of a hunting store's changing room and of a hunter's storage",

        classes = { "rifle", "shotgun" },
    },
}


------------------------------------------------
-- COMPONENTS (tunable)
------------------------------------------------
--
-- A little reloading stock where it would believably be.
-- Every loot number of the mod besides the die sets is in
-- this table.
--
--   item     what is found. One item per find: the engine
--            creates one for each successful roll.
--   list     a live ProceduralDistributions.list (named by
--            a container; tests/vanilla_snapshot.lua).
--   weight   percent chance per roll, at most
--            CONFIG.maxComponentWeight.
--   what     for the documentation.
--
-- What it is worth, so that it cannot replace the
-- crafting loop (docs/LOOT_AND_RECYCLING.md, 4):
--
--   a jar of gunpowder   ten uses: two to ten rounds'
--                        powder. Vanilla's own item; it
--                        has no loot list of its own.
--   a loose primer       one round's primer. A find is a
--                        curiosity, not a supply.
--   brass scrap          ten units of brass, a tenth of an
--                        ingot (vanilla's item).
--   a small brass sheet  ten units: two case cups.
--
-- None of them is a case, a projectile, a round or a
-- die set, and nothing here can be assembled without the
-- rest of the chain.
------------------------------------------------

-- The kinds AC_Calibres.identify() knows that may never be
-- in COMPONENTS.
AC_Loot.NEVER_COMPONENT_LOOT = {

    case = true,

    bullet = true,

    round = true,

    dieSet = true,
}


AC_Loot.COMPONENTS = {

    { item = "Base.GunPowder", list = "GunStoreMagsAmmo", weight = 1.0, what = "a jar of gunpowder among a gun store's ammunition" },

    { item = "Base.GunPowder", list = "Hunter", weight = 0.5, what = "a jar of gunpowder among a hunter's things" },

    { item = "Base.BrassScrap", list = "CrateMetalwork", weight = 2.0, what = "brass scrap in a metalwork crate" },

    { item = "Base.BrassScrap", list = "CrateBlacksmithing", weight = 2.0, what = "brass scrap in a blacksmith's crate" },

    { item = "AmmoMaking.SmallBrassSheet", list = "CrateMetalwork", weight = 1.0, what = "a small brass sheet in a metalwork crate" },
}


-- A loose primer of each family in a gun store, from the
-- calibre model, so that no primer family is named here.
AC_Loot.PRIMER_LOOT = { list = "GunStoreMagsAmmo", weight = 1.0 }


for _,
    primer
in ipairs(
    AC_Calibres.PRIMERS
)
do

    table.insert(
        AC_Loot.COMPONENTS,
        {
            item = primer.item,
            list = AC_Loot.PRIMER_LOOT.list,
            weight = AC_Loot.PRIMER_LOOT.weight,
            what = "a loose primer among a gun store's ammunition",
        }
    )
end


-- The flat list of component entries:
-- { list, item, weight, component = true }.
function AC_Loot.buildComponentEntries(
    components
)

    local entries = {}


    for _,
        component
    in ipairs(
        components or AC_Loot.COMPONENTS
    )
    do

        if type(component.item) == "string"
            and type(component.list) == "string"
            and type(component.weight) == "number"
        then

            table.insert(
                entries,
                {
                    list = component.list,
                    item = component.item,
                    weight = component.weight,
                    component = true,
                }
            )
        end
    end


    return entries
end


-- Problems of the component table, in the form of
-- validate(): empty when it is sound.
function AC_Loot.validateComponents(
    components
)

    components =
        components or AC_Loot.COMPONENTS


    local config =
        AC_Loot.CONFIG


    local problems = {}

    local seen = {}

    local listWeight = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "loot: " .. text
        )
    end


    for index,
        component
    in ipairs(
        components
    )
    do

        local label =
            tostring(component.item or index)


        if type(component.item) ~= "string"
            or component.item == ""
            or type(component.list) ~= "string"
            or component.list == ""
        then

            problem("component " .. label .. " needs an item and a list")

        else

            -- The calibre-specific products are never loot
            -- here: a case, a projectile or a round would
            -- skip the forming steps, and die sets have
            -- their own, rarer table. A loose primer is
            -- allowed: it fits every calibre of its family
            -- and makes nothing by itself.
            local kind =
                AC_Calibres.identify(component.item)


            if AC_Loot.NEVER_COMPONENT_LOOT[tostring(kind)] then
                problem(label .. " is a " .. tostring(kind) .. ": what the player forms and assembles is never component loot")
            end


            local pair =
                component.list .. "|" .. component.item


            if seen[pair] then
                problem(label .. " is in " .. component.list .. " more than once")
            end


            seen[pair] = true
        end


        if type(component.weight) ~= "number"
            or component.weight <= 0
            or component.weight > config.maxComponentWeight
        then

            problem(label .. " must weigh more than 0 and at most " .. config.maxComponentWeight)

        elseif type(component.list) == "string" then

            listWeight[component.list] =
                (listWeight[component.list] or 0) + component.weight
        end
    end


    for list,
        total
    in pairs(
        listWeight
    )
    do

        if total > config.maxComponentListWeight then
            problem("components weigh " .. total .. " in " .. list .. ", above " .. config.maxComponentListWeight)
        end
    end


    return problems
end


------------------------------------------------
-- ENTRIES (pure)
------------------------------------------------
--
-- The flat list of what is inserted:
-- { list, item, weight, calibre }, in TARGETS order and,
-- inside a target, in AC_Calibres.LIST order.
--
-- A calibre whose tier has no weight, and a target
-- without a list name or a scale, yield no entry;
-- validate() reports them.
------------------------------------------------

function AC_Loot.buildEntries(
    targets,
    calibres
)

    targets =
        targets or AC_Loot.TARGETS

    calibres =
        calibres or AC_Calibres.LIST


    local entries = {}


    for _,
        target
    in ipairs(
        targets
    )
    do

        local wanted = nil


        if type(target.classes) == "table" then

            wanted = {}


            for _,
                class
            in ipairs(
                target.classes
            )
            do

                wanted[class] = true
            end
        end


        for _,
            calibre
        in ipairs(
            calibres
        )
        do

            local tierWeight =
                AC_Loot.CONFIG.tierWeight[calibre.lootTier]


            if (not wanted or wanted[calibre.class])
                and type(target.list) == "string"
                and type(tierWeight) == "number"
                and type(target.scale) == "number"
            then

                table.insert(
                    entries,
                    {
                        list = target.list,

                        item = calibre.dieSet,

                        weight = tierWeight * target.scale,

                        calibre = calibre.id,
                    }
                )
            end
        end
    end


    return entries
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- Returns a list of problems, empty when the loot model is
-- sound. Run by the tests and by the compatibility check.
------------------------------------------------

function AC_Loot.validate(
    targets,
    calibres
)

    targets =
        targets or AC_Loot.TARGETS

    calibres =
        calibres or AC_Calibres.LIST


    local config =
        AC_Loot.CONFIG


    local problems = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "loot: " .. text
        )
    end


    for tier,
        weight
    in pairs(
        config.tierWeight
    )
    do

        if type(weight) ~= "number"
            or weight <= 0
            or weight > config.maxWeight
        then
            problem("tier " .. tostring(tier) .. " must weigh more than 0 and at most " .. config.maxWeight)
        end
    end


    for _,
        calibre
    in ipairs(
        calibres
    )
    do

        if calibre.lootTier == nil then
            problem(tostring(calibre.id) .. " has no loot tier")
        elseif config.tierWeight[calibre.lootTier] == nil then
            problem(tostring(calibre.id) .. " has an unknown loot tier " .. tostring(calibre.lootTier))
        end
    end


    local seenList = {}


    for _,
        target
    in ipairs(
        targets
    )
    do

        local name =
            tostring(target.list)


        if type(target.list) ~= "string"
            or target.list == ""
        then
            problem("a target has no list name")
        elseif seenList[target.list] then
            problem("list " .. name .. " is targeted twice")
        end


        seenList[name] = true


        if type(target.scale) ~= "number"
            or target.scale <= 0
            or target.scale > 1
        then
            problem("list " .. name .. " must have a scale above 0 and at most 1")
        end


        if target.classes ~= nil then

            if type(target.classes) ~= "table"
                or #target.classes == 0
            then

                problem("list " .. name .. " names no classes")

            else

                local seen = {}


                for _,
                    class
                in ipairs(
                    target.classes
                )
                do

                    if not AC_Calibres.CLASSES[class] then
                        problem("list " .. name .. " names an unknown class " .. tostring(class))
                    elseif seen[class] then
                        problem("list " .. name .. " names " .. tostring(class) .. " twice")
                    end


                    seen[class] = true
                end
            end
        end
    end


    ------------------------------------------------
    -- The entries themselves: rare, and each die set once
    -- per list.
    ------------------------------------------------

    local listWeight = {}

    local listsOfItem = {}

    local seenPair = {}


    for _,
        entry
    in ipairs(
        AC_Loot.buildEntries(targets, calibres)
    )
    do

        local pair =
            entry.list .. "|" .. entry.item


        if seenPair[pair] then
            problem(entry.item .. " is in " .. entry.list .. " more than once")
        end


        seenPair[pair] = true


        if entry.weight <= 0
            or entry.weight > config.maxWeight
        then
            problem(entry.item .. " weighs " .. entry.weight .. " in " .. entry.list .. ", outside 0 to " .. config.maxWeight)
        end


        listWeight[entry.list] =
            (listWeight[entry.list] or 0) + entry.weight

        listsOfItem[entry.item] =
            (listsOfItem[entry.item] or 0) + 1
    end


    for _,
        target
    in ipairs(
        targets
    )
    do

        local total =
            listWeight[tostring(target.list)] or 0


        if total > config.maxListWeight then
            problem("die sets weigh " .. total .. " in " .. tostring(target.list) .. ", above " .. config.maxListWeight)
        end
    end


    for _,
        calibre
    in ipairs(
        calibres
    )
    do

        local count =
            listsOfItem[calibre.dieSet] or 0


        if count == 0
            and config.tierWeight[calibre.lootTier] ~= nil
        then
            problem(tostring(calibre.id) .. " die set is in no list")
        elseif count > config.maxListsPerCalibre then
            problem(tostring(calibre.id) .. " die set is in " .. count .. " lists, above " .. config.maxListsPerCalibre)
        end
    end


    return problems
end


------------------------------------------------
-- Chance, in percent, that a container filled from a list
-- of the given rolls holds at least one item of the given
-- weight, at default sandbox settings and no zombie
-- density bonus. For the documentation and the tests; the
-- engine does the rolling.
------------------------------------------------

function AC_Loot.chancePerContainer(
    weight,
    rolls
)

    return
        (1 - (1 - weight / 100) ^ rolls) * 100
end


------------------------------------------------
-- VANILLA LISTS (read only)
------------------------------------------------
--
-- Whether a list is named by any container of a
-- distribution table (Distributions[1]). Walks the table
-- once, at world load, for the handful of names asked for.
------------------------------------------------

function AC_Loot.findReferencedLists(
    distribution,
    names
)

    local wanted = {}

    local found = {}


    for _,
        name
    in ipairs(
        names
    )
    do

        wanted[name] = true
    end


    local visited = {}


    local function walk(
        node
    )

        if visited[node] then
            return
        end


        visited[node] = true


        for key,
            value
        in pairs(
            node
        )
        do

            if type(value) == "table" then

                if key == "procList" then

                    for _,
                        entry
                    in ipairs(
                        value
                    )
                    do

                        if type(entry) == "table"
                            and wanted[entry.name]
                        then
                            found[entry.name] = true
                        end
                    end

                elseif key ~= "items"
                    and key ~= "junk"
                then

                    walk(value)
                end
            end
        end
    end


    if type(distribution) == "table" then
        walk(distribution)
    end


    return found
end


------------------------------------------------
-- REGISTRATION
------------------------------------------------
--
-- Appends the entries to the procedural lists. An entry
-- already there is left alone, so a second world load in
-- the same Lua state adds nothing. A list that does not
-- exist is never created: the entry is skipped and counted.
--
-- procedural defaults to ProceduralDistributions.list,
-- distribution to Distributions[1].
--
-- Returns { added, present, missing = { list names },
-- empty = { ... }, unreferenced = { ... } }, with
-- unavailable = true when there was no loot table at all.
------------------------------------------------

local function hasItem(
    items,
    itemType
)

    for index = 1, #items, 2 do

        if items[index] == itemType then
            return true
        end
    end


    return false
end


-- entries: what to insert; names: the lists to look for
-- among the containers; referenced: which lists a
-- container names, when the caller has already walked
-- the distribution table (it is walked once per world
-- load, for the die sets and the components together).
-- Shared by the die sets and the components.
local function registerEntries(
    entries,
    names,
    procedural,
    distribution,
    referenced
)

    local summary = {

        added = 0,

        present = 0,

        missing = {},

        empty = {},

        unreferenced = {},
    }


    if procedural == nil
        and type(ProceduralDistributions) == "table"
    then
        procedural = ProceduralDistributions.list
    end


    if distribution == nil
        and type(Distributions) == "table"
    then
        distribution = Distributions[1]
    end


    if type(procedural) ~= "table" then

        -- The loot tables are not there to add to.
        summary.unavailable = true


        return summary
    end


    local noted = {}


    local function note(
        bucket,
        name
    )

        if not noted[bucket .. name] then

            noted[bucket .. name] = true


            table.insert(
                summary[bucket],
                name
            )
        end
    end


    if referenced == nil then

        referenced =
            distribution
            and AC_Loot.findReferencedLists(distribution, names)
    end


    for _,
        entry
    in ipairs(
        entries
    )
    do

        local list =
            procedural[entry.list]


        if type(list) ~= "table"
            or type(list.items) ~= "table"
        then

            note("missing", entry.list)

        else

            -- A list vanilla has emptied is one it no longer
            -- uses ("-- DEPRECATED").
            if #list.items == 0 then
                note("empty", entry.list)
            end


            if referenced
                and not referenced[entry.list]
            then
                note("unreferenced", entry.list)
            end


            if hasItem(list.items, entry.item) then

                summary.present =
                    summary.present + 1

            else

                table.insert(
                    list.items,
                    entry.item
                )

                table.insert(
                    list.items,
                    entry.weight
                )


                summary.added =
                    summary.added + 1
            end
        end
    end


    return summary
end


local function emptySummary()

    return {

        added = 0,

        present = 0,

        missing = {},

        empty = {},

        unreferenced = {},
    }
end


-- The die sets.
function AC_Loot.register(
    procedural,
    distribution,
    referenced
)

    if not AC_Loot.CONFIG.enabled
        or #AC_Loot.validate() > 0
    then
        return emptySummary()
    end


    local names = {}


    for _,
        target
    in ipairs(
        AC_Loot.TARGETS
    )
    do

        table.insert(
            names,
            target.list
        )
    end


    return
        registerEntries(
            AC_Loot.buildEntries(),
            names,
            procedural,
            distribution,
            referenced
        )
end


-- The reloading stock of COMPONENTS. Switched off with
-- the die sets (CONFIG.enabled), and by a component table
-- that does not validate.
function AC_Loot.registerComponents(
    procedural,
    distribution,
    referenced
)

    if not AC_Loot.CONFIG.enabled
        or #AC_Loot.validateComponents() > 0
    then
        return emptySummary()
    end


    local entries =
        AC_Loot.buildComponentEntries()


    local names = {}

    local seen = {}


    for _,
        entry
    in ipairs(
        entries
    )
    do

        if not seen[entry.list] then

            seen[entry.list] = true


            table.insert(
                names,
                entry.list
            )
        end
    end


    return
        registerEntries(
            entries,
            names,
            procedural,
            distribution,
            referenced
        )
end


-- Every list either table goes into, each once.
function AC_Loot.getListNames()

    local names = {}

    local seen = {}


    local function add(
        name
    )

        if type(name) == "string"
            and not seen[name]
        then

            seen[name] = true


            table.insert(
                names,
                name
            )
        end
    end


    for _,
        target
    in ipairs(
        AC_Loot.TARGETS
    )
    do
        add(target.list)
    end


    for _,
        component
    in ipairs(
        AC_Loot.COMPONENTS
    )
    do
        add(component.list)
    end


    return names
end


-- Which of the mod's lists a container names: ONE walk of
-- the distribution table per world load, shared by both
-- registrations. nil when there is no table to walk.
local function referencedOnce()

    if type(Distributions) ~= "table"
        or type(Distributions[1]) ~= "table"
    then
        return nil
    end


    return
        AC_Loot.findReferencedLists(
            Distributions[1],
            AC_Loot.getListNames()
        )
end


local function registerComponentsLogged(
    referenced
)

    local ok,
          summary =
        pcall(
            AC_Loot.registerComponents,
            nil,
            nil,
            referenced
        )


    if not ok then

        print(
            "[AmmoMaking] WARNING: component loot not registered: "
            .. tostring(summary)
        )


        return
    end


    AC_Loot.lastComponentSummary = summary


    if summary.added > 0
        or summary.unavailable
        or #summary.missing > 0
        or #summary.empty > 0
        or #summary.unreferenced > 0
    then

        print(
            "[AmmoMaking] Component loot: "
            .. summary.added
            .. " entries added, "
            .. summary.present
            .. " already present; lists missing: "
            .. #summary.missing
            .. ", empty: "
            .. #summary.empty
            .. ", used by no container: "
            .. #summary.unreferenced
        )
    end
end


local function registerLogged()

    local walked,
          referenced =
        pcall(referencedOnce)


    if not walked then
        referenced = nil
    end


    registerComponentsLogged(referenced)


    local ok,
          summary =
        pcall(
            AC_Loot.register,
            nil,
            nil,
            referenced
        )


    if not ok then

        print(
            "[AmmoMaking] WARNING: die set loot not registered: "
            .. tostring(summary)
        )


        return
    end


    AC_Loot.lastSummary = summary


    if summary.added > 0
        or summary.unavailable
        or #summary.missing > 0
        or #summary.empty > 0
        or #summary.unreferenced > 0
    then

        print(
            "[AmmoMaking] Die set loot: "
            .. summary.added
            .. " entries added, "
            .. summary.present
            .. " already present; lists missing: "
            .. #summary.missing
            .. ", empty: "
            .. #summary.empty
            .. ", used by no container: "
            .. #summary.unreferenced
        )
    end
end


-- Fired by the engine just before it parses the loot
-- tables (see the header).
Events.OnPreDistributionMerge.Add(
    registerLogged
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Die set loot loaded"
)
