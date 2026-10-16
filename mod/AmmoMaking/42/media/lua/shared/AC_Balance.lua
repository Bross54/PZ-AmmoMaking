-- Ammo Making - Balance options of the save
-- Project Zomboid Build 42.20
--
-- The few balance numbers a server owner may want to
-- change without editing Lua, offered as sandbox options
-- (media/sandbox-options.txt, page "Ammo Making"). Every
-- one of them is a multiplier whose default is 1, so a
-- save that never touches them plays exactly as before.
--
-- ONE place reads them. Every other file asks
-- AC_Balance.get(id) and never reads SandboxVars itself,
-- and every value is checked here: a number outside the
-- option's range is clamped into it, anything that is not
-- a finite number (a word, nil, NaN, infinity, a broken
-- table) is no setting and gives the default.
--
-- What is offered, and what is deliberately not
-- (docs/BALANCE_OPTIONS.md):
--
--   depositReserve  ore per tile        AC_Deposits
--   dieSetLoot      die sets as loot    AC_Loot
--   componentLoot   reloading stock as  AC_Loot
--                   loot
--   xp              Ammo Making XP      the ENGINE
--
-- The XP multiplier is not applied by the mod. Vanilla's
-- IsoGameCharacter$XP.AddXP multiplies a skill's XP by
-- the sandbox option "MultiplierConfig.<perk id>" when
-- the global XP multiplier toggle is off, and by the
-- global multiplier when it is on (JAR, 42.20.4). Vanilla
-- declares that option for its own skills only; the mod
-- declares MultiplierConfig.AmmoMaking, so Ammo Making is
-- scaled like every other skill. Its value is read here
-- only to be reported.
--
-- Recycling yield is NOT an option: it is the inputs and
-- outputs of generated recipe scripts, which the engine
-- reads before any Lua runs, and the only XP-safe
-- direction (less) would need crafted outputs destroyed
-- after the fact.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the options
-- arrive in SandboxVars as declared (custom options, like
-- the feature switches), and that the engine finds
-- MultiplierConfig.AmmoMaking by that name.

AC_Balance = AC_Balance or {}


------------------------------------------------
-- OPTIONS
------------------------------------------------
--
-- id         what the code asks for
-- table      the SandboxVars table the option arrives in
-- option     its name in that table; the sandbox file
--            declares it as <table>.<option>
-- min, max   the range of the sandbox file, and the
--            clamp of get()
-- default    1: today's balance
-- appliedBy  "lua" (the mod multiplies) or "engine"
--            (vanilla does, the mod only reads it)
-- what       for the documentation
------------------------------------------------

AC_Balance.OPTIONS = {

    {
        id = "depositReserve",

        table = "AmmoMaking",

        option = "DepositReserveMultiplier",

        min = 0.5,

        max = 3.0,

        default = 1.0,

        appliedBy = "lua",

        what = "ore units per worked tile; a workable grade keeps at least one",
    },

    {
        id = "dieSetLoot",

        table = "AmmoMaking",

        option = "DieSetLootMultiplier",

        min = 0.0,

        max = 2.0,

        default = 1.0,

        appliedBy = "lua",

        what = "the loot weight of every die set; 0 removes them from loot",
    },

    {
        id = "componentLoot",

        table = "AmmoMaking",

        option = "ComponentLootMultiplier",

        min = 0.0,

        max = 2.0,

        default = 1.0,

        appliedBy = "lua",

        what = "the loot weight of gunpowder, loose primers, brass scrap and small brass sheets the mod adds; 0 removes them",
    },

    {
        id = "xp",

        table = "MultiplierConfig",

        option = "AmmoMaking",

        min = 0.0,

        max = 1000.0,

        default = 1.0,

        appliedBy = "engine",

        what = "Ammo Making XP, applied by vanilla when its global XP multiplier is switched off",
    },
}


function AC_Balance.getOption(
    id
)

    for _,
        option
    in ipairs(
        AC_Balance.OPTIONS
    )
    do

        if option.id == id then
            return option
        end
    end


    return nil
end


------------------------------------------------
-- READING (pure but for SandboxVars)
------------------------------------------------

-- A value clamped into the option's range; the default
-- when it is not a finite number.
function AC_Balance.clamp(
    option,
    value
)

    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
    then
        return option.default
    end


    if value < option.min then
        return option.min
    end


    if value > option.max then
        return option.max
    end


    return value
end


-- The raw value the save holds, or nil.
function AC_Balance.getRaw(
    option
)

    if type(SandboxVars) ~= "table" then
        return nil
    end


    local options =
        SandboxVars[option.table]


    if type(options) ~= "table" then
        return nil
    end


    return options[option.option]
end


-- The value in force: the save's, checked, or the
-- default. An unknown id is an error in the mod, and
-- gives 1 (no change) rather than breaking a craft.
function AC_Balance.get(
    id
)

    local option =
        AC_Balance.getOption(
            id
        )


    if not option then
        return 1
    end


    return
        AC_Balance.clamp(
            option,
            AC_Balance.getRaw(
                option
            )
        )
end


function AC_Balance.isDefault(
    id
)

    local option =
        AC_Balance.getOption(
            id
        )


    return
        option ~= nil
        and AC_Balance.get(id) == option.default
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- The option table itself: ranges that hold their
-- default, a default of 1, unique ids and names.
------------------------------------------------

function AC_Balance.validate()

    local problems = {}

    local seenId = {}

    local seenName = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "balance: " .. text
        )
    end


    for index,
        option
    in ipairs(
        AC_Balance.OPTIONS
    )
    do

        local label =
            tostring(option.id or index)


        if type(option.id) ~= "string"
            or option.id == ""
        then
            problem("option " .. index .. " has no id")
        elseif seenId[option.id] then
            problem(label .. " is declared twice")
        end


        seenId[tostring(option.id)] = true


        local name =
            tostring(option.table) .. "." .. tostring(option.option)


        if type(option.table) ~= "string"
            or type(option.option) ~= "string"
        then
            problem(label .. " needs a table and an option name")
        elseif seenName[name] then
            problem(name .. " is used twice")
        end


        seenName[name] = true


        if type(option.min) ~= "number"
            or type(option.max) ~= "number"
            or option.min < 0
            or option.min > option.max
        then

            problem(label .. " needs a range from 0 or more")

        elseif option.default ~= 1
            or option.default < option.min
            or option.default > option.max
        then

            problem(label .. " must default to 1, inside its range: the save plays as before unless it is changed")
        end


        if option.appliedBy ~= "lua"
            and option.appliedBy ~= "engine"
        then
            problem(label .. " must say who applies it")
        end
    end


    return problems
end


------------------------------------------------
-- REPORT
------------------------------------------------

-- One line naming every option that is not at its
-- default, or nil when all are.
function AC_Balance.describeChanges()

    local parts = {}


    for _,
        option
    in ipairs(
        AC_Balance.OPTIONS
    )
    do

        local value =
            AC_Balance.get(
                option.id
            )


        if value ~= option.default then

            table.insert(
                parts,
                option.table
                .. "."
                .. option.option
                .. " = "
                .. tostring(value)
            )
        end
    end


    if #parts == 0 then
        return nil
    end


    return table.concat(parts, ", ")
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Balance options loaded"
)
