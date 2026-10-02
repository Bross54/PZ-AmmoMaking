-- Ammo Making - What the mod keeps in a save
-- Project Zomboid Build 42.20
--
-- Two things, neither of which stores anything itself:
--
--   number(), whole(), isFinite()
--       how a number is read back from ModData. A save can
--       be damaged or edited by hand, and Lua's tonumber()
--       is not enough: "nan" and "inf" are numbers to it,
--       and 900 is a perfectly good number that is not a
--       quality. The modules that read persisted numbers
--       use these, so a damaged value becomes the nearest
--       valid one, or the field's default, and never
--       reaches arithmetic or the screen.
--
--   SCHEMA, check()
--       every key the mod persists: who owns it, what type
--       and range it has, its default, what happens to a
--       damaged value, and whether a schema version would
--       matter. The tests walk this table: every key is
--       fuzzed, and a ModData key that appears in the code
--       but not here fails the suite. check() reports what
--       is wrong with a given table and changes nothing.
--
-- docs/DEVELOPMENT.md ("Persisted data") is the prose for
-- this table. The engine's part - that ModData survives a
-- save, a reload and a chunk unload - is not something
-- this file can prove.

-- The test cartridge's fields are AmmoQuality.DEFAULTS.
require "AC_AmmoQuality"

AC_SaveData = AC_SaveData or {}


------------------------------------------------
-- READING NUMBERS
------------------------------------------------

-- A real, usable number: not NaN, not an infinity.
function AC_SaveData.isFinite(
    value
)

    return
        type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end


------------------------------------------------
-- value as a number within minimum..maximum. A value
-- that is not a finite number (nil, a table, a word,
-- NaN, an infinity) gives default; a finite one outside
-- the range is clamped to it. A numeric string counts,
-- as it does for tonumber(). minimum and maximum may be
-- left out.
------------------------------------------------

function AC_SaveData.number(
    value,
    default,
    minimum,
    maximum
)

    local number =
        tonumber(value)


    if not AC_SaveData.isFinite(number) then
        return default
    end


    if minimum ~= nil
        and number < minimum
    then
        return minimum
    end


    if maximum ~= nil
        and number > maximum
    then
        return maximum
    end


    return number
end


-- The same, rounded down to a whole number.
function AC_SaveData.whole(
    value,
    default,
    minimum,
    maximum
)

    local number =
        AC_SaveData.number(
            value,
            nil,
            minimum,
            maximum
        )


    if number == nil then
        return default
    end


    return
        math.floor(number)
end


------------------------------------------------
-- VERSIONS
------------------------------------------------
--
-- A persisted structure that has a layout carries a
-- whole-number "version". versionStatus() says how a
-- stored version relates to the one this release writes:
--
--   "missing"  no version stored
--   "current"  this release's layout
--   "older"    an earlier layout: upgrade() can bring it
--              forward
--   "newer"    written by a LATER release. Not ours to
--              repair, reset or stamp: an owner reads
--              what it understands, and writes only in
--              the form it understands, or not at all
--   "damaged"  not a whole number from 1 to MAX_VERSION.
--              A version of 1e300 is not a later
--              release; it is a broken number
--
-- What "missing" and "damaged" mean is the owner's
-- business (the deposits store was written without a
-- version by nobody: it stamps 1).
------------------------------------------------

-- No structure of the mod will see a million layouts.
AC_SaveData.MAX_VERSION = 1000000


function AC_SaveData.versionStatus(
    value,
    current
)

    if value == nil then
        return "missing"
    end


    if not AC_SaveData.isFinite(value)
        or value ~= math.floor(value)
        or value < 1
        or value > AC_SaveData.MAX_VERSION
    then
        return "damaged"
    end


    if value == current then
        return "current"
    end


    if value > current then
        return "newer"
    end


    return "older"
end


------------------------------------------------
-- UPGRADE
------------------------------------------------
--
-- Brings data (a table with a "version" field) from an
-- older layout to current, one step at a time.
-- steps[v] is a function(data) that turns layout v into
-- layout v + 1.
--
-- Returns a status and the number of steps applied:
--
--   "current"   nothing to do (the usual case: one
--               comparison, no step looked at)
--   "upgraded"  every step ran; data.version is current
--   "missing", "newer", "damaged"
--               as versionStatus(); nothing was touched
--   "stuck"     there is no step from the stored layout;
--               nothing further was touched
--   "failed"    a step raised an error. The version is
--               left at that step's layout, so the step
--               runs again at the next load
--
-- Rules for a step, because of that last case: it may
-- run more than once on the same data, so it must
-- tolerate its own partial result; it converts and never
-- resets; and it creates nothing a player can hold.
--
-- The version is this function's to set, not the step's:
-- whatever a step does to data.version is overwritten
-- (one layout up when it returns, back to where it was
-- when it raises), so a step cannot skip a layout, run
-- twice or make the loop run for ever. data that is not
-- a table, or a current that is not a number, is
-- "damaged" and nothing is touched.
--
-- No structure of the mod has a second layout yet, so no
-- step exists. This is here so that the first one is a
-- function in a table and not a design.
------------------------------------------------

function AC_SaveData.upgrade(
    data,
    current,
    steps
)

    if type(data) ~= "table"
        or type(current) ~= "number"
    then
        return "damaged", 0
    end


    local status =
        AC_SaveData.versionStatus(
            data.version,
            current
        )


    if status ~= "older" then
        return status, 0
    end


    local applied = 0

    local layout =
        data.version


    while layout < current do

        local step =
            type(steps) == "table" and steps[layout]


        if type(step) ~= "function" then
            return "stuck", applied
        end


        local ok,
              problem =
            pcall(
                step,
                data
            )


        if not ok then

            data.version = layout


            print(
                "[AmmoMaking] WARNING: save data upgrade from layout "
                .. tostring(layout)
                .. " failed: "
                .. tostring(problem)
            )


            return "failed", applied
        end


        layout =
            layout + 1

        data.version = layout

        applied =
            applied + 1
    end


    return "upgraded", applied
end


------------------------------------------------
-- SCHEMA
------------------------------------------------
--
-- One entry per persisted structure:
--
--   id       name used by check() and the tests
--   owner    the module that reads and writes it
--   carrier  where it lives in the save
--   version  whether the structure carries a version, and
--            what a change of layout would need
--   keys     { key, type, ... } per field:
--
--     type     "number", "string", "boolean", "table",
--              or "flag" (true, or absent)
--     min, max range of a number; a function is called
--              when the limit comes from another module's
--              CONFIG
--     whole    the number is an integer
--     values   the allowed strings
--     default  what a missing or unusable value is read as
--              ("none" where the reader returns nothing)
--     read     false for a key that is written and never
--              read by logic (a record, a marker)
--     repair   what the owner does with a damaged value
--
-- A key ending in "*" stands for a family (the analyzer's
-- stored_<field> copies of a sample's fields).
------------------------------------------------

local function percent(key, extra)

    local entry = {
        key = key,
        type = "number",
        min = 0,
        max = 100,
    }


    for name,
        value
    in pairs(
        extra or {}
    )
    do

        entry[name] = value
    end


    return entry
end


local function grades()

    local names = {}


    for name in pairs(
        AC_Geology.GRADE_KEYS
    )
    do

        table.insert(
            names,
            name
        )
    end


    table.sort(
        names
    )


    return names
end


-- The fields of a geological sample. The analyzer keeps a
-- copy of each as stored_<field>.
local SAMPLE_KEYS = {

    { key = "AmmoMakingGeologicalSample", type = "flag", read = false, repair = "a marker; the item type decides what is a sample" },

    { key = "sampleX", type = "number", default = "none", repair = "a sample without usable coordinates covers no square and is shown as '?'" },

    { key = "sampleY", type = "number", default = "none", repair = "as sampleX" },

    { key = "geologySeed", type = "number", read = false, repair = "a record; geology is recomputed from the save's identity" },

    percent("trueCopper", { default = 0, repair = "read as 0..100; anything else as 0" }),

    percent("trueZinc", { default = 0, repair = "read as 0..100; anything else as 0" }),

    percent("trueCopperPeak", { read = false, repair = "a record" }),

    percent("trueZincPeak", { read = false, repair = "a record" }),

    { key = "assayRank", type = "number", whole = true, min = 0, max = 3, default = 0, repair = "read with tonumber; anything else is rank 0 (untested)" },

    { key = "assayType", type = "string", read = false, repair = "a record" },

    { key = "copperGrade", type = "string", values = grades, default = "none", repair = "an unknown grade is shown as unknown; geology, not the sample, decides what a tile yields" },

    { key = "zincGrade", type = "string", values = grades, default = "none", repair = "as copperGrade" },

    percent("copperMin", { default = "none", repair = "shown as '?' when not 0..100" }),

    percent("copperMax", { default = "none", repair = "shown as '?' when not 0..100" }),

    percent("zincMin", { default = "none", repair = "shown as '?' when not 0..100" }),

    percent("zincMax", { default = "none", repair = "shown as '?' when not 0..100" }),

    percent("labCopperResult", { default = "none", repair = "shown as '?' when not 0..100" }),

    percent("labZincResult", { default = "none", repair = "shown as '?' when not 0..100" }),

    { key = "labStartedAt", type = "number", read = false, repair = "a record" },

    { key = "labReadyAt", type = "number", read = false, repair = "a record on a sample" },

    { key = "labProcessing", type = "boolean", default = false, repair = "only ever written false; the three places that test it for true are dead, kept for a save that might carry true" },
}


AC_SaveData.SCHEMA = {

    {
        id = "deposits",

        owner = "AC_Deposits",

        carrier = "global ModData \"AmmoMakingDeposits\"",

        version = "version = 1, AC_Deposits.CONFIG.version. Stamped when missing; brought forward by AC_SaveData.upgrade and AC_Deposits.MIGRATIONS (no step exists: there has been one layout); a store written by a later release is read and never reset or stamped.",

        keys = {

            { key = "version", type = "number", default = 1, repair = "restored to 1 when missing; a higher one marks a later release's store, which is left as it is" },

            { key = "tiles", type = "table", default = "empty", repair = "a non-table is replaced by an empty table with a warning; the records are lost" },
        },
    },

    {
        id = "depositsTile",

        owner = "AC_Deposits",

        carrier = "tiles[\"x,y\"] of the deposits store; a non-table record reads as an unworked tile and is replaced by the next write",

        version = "none: reserves come from geology, the record is only what was taken, so a rebalance needs no migration",

        keys = {

            { key = "copper", type = "number", whole = true, min = 0, default = 0, repair = "read as a count of 0 or more; anything else as 0 (unworked)" },

            { key = "zinc", type = "number", whole = true, min = 0, default = 0, repair = "as copper" },
        },
    },

    {
        id = "sample",

        owner = "AC_GeologySampling",

        carrier = "item ModData of AmmoMaking.GeologicalSample",

        version = "none: fields have only been added",

        keys = SAMPLE_KEYS,
    },

    {
        id = "kit",

        owner = "AC_GeologySampling",

        carrier = "item ModData of AmmoMaking.FieldAssayKit and AmmoMaking.AdvancedFieldAssayKit",

        version = "none",

        keys = {

            { key = "AmmoMakingAssayKitInitialized", type = "flag", repair = "a kit without it is set up as new the first time it is looked at" },

            { key = "assayKitType", type = "string", values = { "field", "advanced" }, read = false, repair = "a record; the item type decides" },

            {
                key = "assayMaxUses",
                type = "number",
                whole = true,
                min = 1,
                max = function()
                    return math.max(
                        AC_GeologySampling.CONFIG.fieldKitUses,
                        AC_GeologySampling.CONFIG.advancedFieldKitUses
                    )
                end,
                repair = "rewritten to the kit type's full count when it is not a whole number between 1 and that count",
            },

            {
                key = "assayUsesRemaining",
                type = "number",
                whole = true,
                min = 0,
                max = function()
                    return math.max(
                        AC_GeologySampling.CONFIG.fieldKitUses,
                        AC_GeologySampling.CONFIG.advancedFieldKitUses
                    )
                end,
                default = 0,
                repair = "rewritten into 0..assayMaxUses; a value that is not a number becomes 0 (an empty kit, never a free refill)",
            },
        },
    },

    {
        id = "analyzer",

        owner = "AC_LaboratoryAnalyzer",

        carrier = "ModData of the placed IsoThumpable, or of the dropped item (the first version's carrier)",

        version = "none; the one migration is by shape: labReadyAt without labRemainingHours is an analyzer saved by the first version",

        keys = {

            { key = "AmmoMakingLaboratoryAnalyzerWorldObject", type = "flag", repair = "falls back to the object's name" },

            { key = "AmmoMakingLaboratoryAnalyzer", type = "flag", read = false, repair = "a marker" },

            { key = "labAnalyzerState", type = "string", values = { "idle", "processing", "ready" }, default = "idle", repair = "an unknown state becomes processing when a sample is stored, else idle; logged" },

            { key = "storedSample", type = "boolean", default = false, repair = "only exactly true counts as a stored sample" },

            {
                key = "labRemainingHours",
                type = "number",
                min = 0,
                max = function()
                    return AC_LaboratoryAnalyzer.CONFIG.processingHours
                end,
                repair = "dropped and rebuilt when it is not a finite number or is longer than a full run",
            },

            { key = "labLastUpdateAt", type = "number", min = 0, repair = "dropped and rebuilt when it is not a finite number" },

            { key = "labReadyAt", type = "number", min = 0, repair = "read only by the first-version migration; dropped when not a finite number" },

            { key = "labStartedAt", type = "number", read = false, repair = "a record" },

            percent("labCopperResult", { repair = "rolled again from the stored sample when it is not 0..100" }),

            percent("labZincResult", { repair = "rolled again from the stored sample when it is not 0..100" }),

            { key = "stored_*", type = "any", family = SAMPLE_KEYS, repair = "copied back onto the sample as they are; the sample's own readers then apply" },
        },
    },

    {
        id = "case",

        owner = "AC_CaseQuality",

        carrier = "item ModData of a calibre's case or hull",

        version = "none",

        keys = {

            { key = "AmmoMakingCase", type = "flag", read = false, repair = "a marker" },

            { key = "caseQuality", type = "number", min = 1, max = 100, default = "none", repair = "read as 1..100; not a finite number reads as no quality" },
        },
    },

    {
        id = "round",

        owner = "AC_CaseQuality",

        carrier = "item ModData of a loose handloaded round; gone once the round is loaded or boxed",

        version = "none",

        keys = {

            { key = "AmmoMakingHandloaded", type = "flag", read = false, repair = "a marker" },

            { key = "casingQuality", type = "number", min = 1, max = 100, default = "none", repair = "read as 1..100; not a finite number reads as no record" },
        },
    },

    {
        id = "testCartridge",

        owner = "AmmoQuality",

        carrier = "item ModData of AmmoMaking.TestCartridge (prototype)",

        version = "none",

        -- The numeric fields are AmmoQuality.DEFAULTS; they
        -- are added below so the two cannot drift apart.
        keys = {

            { key = "AmmoMakingQualityInitialized", type = "flag", repair = "a cartridge without it gets every default" },
        },
    },
}


-- AmmoQuality loads before this file. Its DEFAULTS are the
-- test cartridge's numeric fields.
if type(AmmoQuality) == "table"
    and type(AmmoQuality.DEFAULTS) == "table"
then

    local names = {}


    for name in pairs(
        AmmoQuality.DEFAULTS
    )
    do

        table.insert(
            names,
            name
        )
    end


    table.sort(
        names
    )


    for _,
        structure
    in ipairs(
        AC_SaveData.SCHEMA
    )
    do

        if structure.id == "testCartridge" then

            for _,
                name
            in ipairs(
                names
            )
            do

                table.insert(
                    structure.keys,
                    {
                        key = name,

                        type = "number",

                        default = AmmoQuality.DEFAULTS[name],

                        repair = "restored to its default on the next inspection when it is not a finite number",
                    }
                )
            end
        end
    end
end


function AC_SaveData.getStructure(
    id
)

    for _,
        structure
    in ipairs(
        AC_SaveData.SCHEMA
    )
    do

        if structure.id == id then
            return structure
        end
    end


    return nil
end


local function limit(
    value
)

    if type(value) == "function" then
        return value()
    end


    return value
end


------------------------------------------------
-- Problems of one field against its entry, appended to
-- problems. A missing value is never a problem: every key
-- may be absent.
------------------------------------------------

local function checkField(
    problems,
    entry,
    key,
    value
)

    if value == nil
        or entry.type == "any"
    then
        return
    end


    local function problem(
        text
    )

        table.insert(
            problems,
            key .. ": " .. text
        )
    end


    if entry.type == "flag" then

        if value ~= true then
            problem("a flag must be true or absent")
        end

    elseif entry.type == "number" then

        if not AC_SaveData.isFinite(value) then

            problem("not a finite number")

        else

            local minimum =
                limit(entry.min)

            local maximum =
                limit(entry.max)


            if (minimum ~= nil and value < minimum)
                or (maximum ~= nil and value > maximum)
            then
                problem("outside " .. tostring(minimum) .. ".." .. tostring(maximum))
            end


            if entry.whole
                and value ~= math.floor(value)
            then
                problem("not a whole number")
            end
        end

    elseif type(value) ~= entry.type then

        problem("not a " .. entry.type)

    elseif entry.values then

        local known = false


        for _,
            allowed
        in ipairs(
            limit(entry.values)
        )
        do

            if allowed == value then
                known = true
            end
        end


        if not known then
            problem("unknown value " .. tostring(value))
        end
    end
end


------------------------------------------------
-- CHECK (read only)
------------------------------------------------
--
-- What is wrong with a table of the given structure: a
-- list of "<key>: <problem>", empty when every present
-- field is of its type and in its range and no field is
-- unknown. Changes nothing.
------------------------------------------------

function AC_SaveData.check(
    id,
    data
)

    local structure =
        AC_SaveData.getStructure(id)


    if not structure then
        return { "unknown structure " .. tostring(id) }
    end


    if type(data) ~= "table" then
        return { tostring(id) .. ": not a table" }
    end


    local problems = {}

    local known = {}

    local families = {}


    for _,
        entry
    in ipairs(
        structure.keys
    )
    do

        if entry.family then

            table.insert(
                families,
                entry
            )

        else

            known[entry.key] = entry
        end
    end


    for key,
        value
    in pairs(
        data
    )
    do

        local entry =
            known[key]


        if not entry
            and type(key) == "string"
        then

            -- A family member: stored_<field> is checked as
            -- <field>.
            for _,
                family
            in ipairs(
                families
            )
            do

                local prefix =
                    string.sub(family.key, 1, -2)


                if string.sub(key, 1, #prefix) == prefix then

                    for _,
                        member
                    in ipairs(
                        family.family
                    )
                    do

                        if member.key == string.sub(key, #prefix + 1) then
                            entry = member
                        end
                    end
                end
            end
        end


        if entry then

            checkField(
                problems,
                entry,
                tostring(key),
                value
            )

        else

            table.insert(
                problems,
                tostring(key) .. ": not a key of " .. id
            )
        end
    end


    table.sort(
        problems
    )


    return problems
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Save data schema loaded"
)
