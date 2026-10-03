-- Ammo Making - feature switches
-- Project Zomboid Build 42.20
--
-- ONE place decides whether a runtime-sensitive system of
-- the mod exists in a game. Every other file asks
-- AC_Features.isEnabled(id) and never reads a switch of
-- its own: a system that is off registers no event, wraps
-- no vanilla function, adds no recipe and no menu entry.
--
-- A feature is one of:
--
--   stable        always on. Not listed here at all: the
--                 geology, mining, metallurgy and
--                 ammunition stages have no switch.
--   experimental  written and tested offline, NOT yet seen
--                 working in the game. Off unless its
--                 switch is on.
--   disabled      written, and locked: no switch turns it
--                 on. Changing the word below is the
--                 deliberate step.
--
-- Two kinds of switch, because the game loads two kinds
-- of thing:
--
--   mod = "<id>"      Scripts (items, recipes, entities,
--                     tile sheets) are read by the engine
--                     before any Lua runs and cannot be
--                     hidden afterwards. A feature that
--                     needs them ships them in an ADD-ON
--                     MOD of its own, beside the main mod.
--                     Ticking the add-on in the mod list
--                     is the switch; without it none of
--                     its scripts exist.
--   sandbox = "<opt>" A feature that is Lua only is a
--                     sandbox option of the save
--                     (media/sandbox-options.txt,
--                     SandboxVars.AmmoMaking.<opt>),
--                     false by default.
--
-- singlePlayerOnly: the feature changes items from Lua and
-- has no server authority yet, so it is off for a
-- multiplayer client and on a server, whatever its switch
-- says (docs/MULTIPLAYER_DESIGN.md).
--
-- conflicts: ids of other mods that already do the same
-- thing to the same vanilla functions. With one of them
-- active the feature stands down, so nothing is done
-- twice (docs/REFERENCE_IMPLEMENTATIONS.md).
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that
-- getActivatedMods() lists an add-on's id as written here
-- (both spellings Build 42 uses are accepted), and that a
-- custom sandbox option arrives in SandboxVars.

AC_Features = AC_Features or {}


AC_Features.STABLE = "stable"

AC_Features.EXPERIMENTAL = "experimental"

AC_Features.DISABLED = "disabled"


-- The table sandbox options of the mod arrive in:
-- SandboxVars.AmmoMaking.<option>.
AC_Features.SANDBOX_TABLE = "AmmoMaking"


AC_Features.DEFINITIONS = {

    {
        id = "reloadingPress",

        name = "Reloading Press",

        stability = AC_Features.EXPERIMENTAL,

        -- A station entity, a tile sheet and 27 recipes.
        mod = "AmmoMakingPress",

        singlePlayerOnly = false,

        what = "a placed crafting station that runs the case, projectile and assembly steps in 60 % of the hand time",
    },

    {
        id = "spentCases",

        name = "Spent Cases",

        stability = AC_Features.EXPERIMENTAL,

        -- Nine items and their scrapping recipes.
        mod = "AmmoMakingSpentCases",

        singlePlayerOnly = true,

        -- Hot Brass (Workshop 3610677934) spawns a casing
        -- item of its own for every shot, from the same
        -- event and the same two eject functions. Both at
        -- once would leave two cases per round.
        conflicts = { "HBVCEFb42" },

        what = "fired rounds leave spent brass that can only be scrapped, at a loss",
    },

    {
        id = "qualityTracking",

        name = "Ammunition Quality Tracking",

        stability = AC_Features.EXPERIMENTAL,

        sandbox = "QualityTracking",

        singlePlayerOnly = true,

        what = "the casing quality of handloaded rounds is followed through magazines and firearms and comes back when they are unloaded",
    },

    {
        id = "qualityEffects",

        name = "Ammunition Quality Firing Effects",

        -- Locked. The code path exists and is tested; no
        -- effect on firing may be switched on before the
        -- tracking under it has been seen to stay in step
        -- in the game.
        stability = AC_Features.DISABLED,

        sandbox = "QualityEffects",

        requires = "qualityTracking",

        singlePlayerOnly = true,

        what = "poor handloads raise vanilla's own jam chance",
    },
}


------------------------------------------------
-- LOOKUP
------------------------------------------------

function AC_Features.get(
    id
)

    for _,
        definition
    in ipairs(
        AC_Features.DEFINITIONS
    )
    do

        if definition.id == id then
            return definition
        end
    end


    return nil
end


------------------------------------------------
-- IS AN ADD-ON MOD ACTIVE?
------------------------------------------------
--
-- getActivatedMods() is the engine's list of loaded mod
-- ids (jar: LuaManager.GlobalObject.getActivatedMods ->
-- ZomboidFileSystem.getModIDs, an ArrayList<String>).
-- Build 42 writes an id with a leading backslash in some
-- places; both spellings are looked for. Anything
-- unexpected means "not active".
------------------------------------------------

function AC_Features.isModActive(
    modId
)

    if type(modId) ~= "string"
        or type(getActivatedMods) ~= "function"
    then
        return false
    end


    local ok,
          mods =
        pcall(getActivatedMods)


    if not ok
        or not mods
        or not mods.contains
    then
        return false
    end


    return
        mods:contains(modId) == true
        or mods:contains("\\" .. modId) == true
end


------------------------------------------------
-- IS A SANDBOX OPTION ON?
------------------------------------------------
--
-- Only the boolean true counts. A missing table, a
-- missing option or any other value is "off".
------------------------------------------------

function AC_Features.isSandboxOn(
    option
)

    if type(option) ~= "string"
        or type(SandboxVars) ~= "table"
    then
        return false
    end


    local options =
        SandboxVars[AC_Features.SANDBOX_TABLE]


    if type(options) ~= "table" then
        return false
    end


    return options[option] == true
end


------------------------------------------------
-- MULTIPLAYER
------------------------------------------------

function AC_Features.isMultiplayer()

    if type(isClient) == "function"
        and isClient()
    then
        return true
    end


    if type(isServer) == "function"
        and isServer()
    then
        return true
    end


    return false
end


------------------------------------------------
-- STATE
------------------------------------------------
--
-- Returns enabled (boolean) and why (a short word for the
-- log): "stable", "on", "off", "locked", "multiplayer",
-- "needs <feature>", "conflict with <mod>", "unknown".
--
-- Nothing is cached: an add-on cannot change during a
-- session, and a sandbox option is only known once the
-- save is loaded, so a cache would have to know when to
-- forget. The lookups are a list search and a table read,
-- and callers ask at registration time, not per frame.
------------------------------------------------

function AC_Features.getState(
    id
)

    local definition =
        AC_Features.get(id)


    if not definition then
        return false, "unknown"
    end


    if definition.stability == AC_Features.STABLE then
        return true, "stable"
    end


    if definition.stability ~= AC_Features.EXPERIMENTAL then
        return false, "locked"
    end


    local switchedOn = false


    if definition.mod then

        switchedOn =
            AC_Features.isModActive(definition.mod)

    elseif definition.sandbox then

        switchedOn =
            AC_Features.isSandboxOn(definition.sandbox)
    end


    if not switchedOn then
        return false, "off"
    end


    if definition.singlePlayerOnly
        and AC_Features.isMultiplayer()
    then
        return false, "multiplayer"
    end


    for _,
        other
    in ipairs(
        definition.conflicts or {}
    )
    do

        if AC_Features.isModActive(other) then
            return false, "conflict with " .. other
        end
    end


    if definition.requires
        and not AC_Features.isEnabled(definition.requires)
    then
        return false, "needs " .. definition.requires
    end


    return true, "on"
end


function AC_Features.isEnabled(
    id
)

    local enabled =
        AC_Features.getState(id)


    return enabled
end


------------------------------------------------
-- VALIDATION
------------------------------------------------
--
-- Returns a list of problems; empty when the table is
-- sound. Run by the tests and by the compatibility check.
------------------------------------------------

function AC_Features.validate(
    definitions
)

    definitions =
        definitions or AC_Features.DEFINITIONS


    local problems = {}

    local seen = {}

    local switches = {}


    local function problem(text)

        table.insert(
            problems,
            text
        )
    end


    for index,
        definition
    in ipairs(
        definitions
    )
    do

        local label =
            tostring(definition.id or index)


        if type(definition.id) ~= "string"
            or definition.id == ""
        then

            problem("feature " .. label .. " has no id")

        elseif seen[definition.id] then

            problem("feature " .. label .. " is defined twice")
        end


        seen[definition.id or index] = true


        if definition.stability ~= AC_Features.STABLE
            and definition.stability ~= AC_Features.EXPERIMENTAL
            and definition.stability ~= AC_Features.DISABLED
        then

            problem("feature " .. label .. " has no known stability")
        end


        if type(definition.name) ~= "string"
            or definition.name == ""
        then

            problem("feature " .. label .. " has no name")
        end


        local hasMod =
            type(definition.mod) == "string"
            and definition.mod ~= ""

        local hasSandbox =
            type(definition.sandbox) == "string"
            and definition.sandbox ~= ""


        if definition.stability ~= AC_Features.STABLE
            and hasMod == hasSandbox
        then

            problem("feature " .. label .. " needs exactly one switch: an add-on mod or a sandbox option")
        end


        local switch =
            (hasMod and ("mod " .. definition.mod))
            or (hasSandbox and ("sandbox " .. definition.sandbox))


        if switch then

            if switches[switch] then
                problem("feature " .. label .. " shares its switch with " .. switches[switch])
            end

            switches[switch] = label
        end


        if type(definition.singlePlayerOnly) ~= "boolean" then

            problem("feature " .. label .. " does not say whether it is single player only")
        end


        if definition.conflicts ~= nil then

            if type(definition.conflicts) ~= "table" then

                problem("feature " .. label .. " names its conflicts as something other than a list")

            else

                for _,
                    other
                in ipairs(
                    definition.conflicts
                )
                do

                    if type(other) ~= "string"
                        or other == ""
                        or other == definition.mod
                    then
                        problem("feature " .. label .. " has a conflict that is not another mod's id")
                    end
                end
            end
        end
    end


    for _,
        definition
    in ipairs(
        definitions
    )
    do

        if definition.requires ~= nil then

            local found = false

            for _,
                other
            in ipairs(
                definitions
            )
            do

                if other.id == definition.requires
                    and other ~= definition
                then
                    found = true
                end
            end


            if not found then

                problem(
                    "feature "
                    .. tostring(definition.id)
                    .. " requires "
                    .. tostring(definition.requires)
                    .. ", which is not a feature"
                )
            end
        end
    end


    return problems
end


------------------------------------------------
-- DESCRIBE (log and debug menu)
------------------------------------------------
--
-- One line per feature: name, stability, state and what
-- switches it.
------------------------------------------------

function AC_Features.describe()

    local lines = {}


    for _,
        definition
    in ipairs(
        AC_Features.DEFINITIONS
    )
    do

        local enabled,
              why =
            AC_Features.getState(definition.id)


        local switch = "no switch"


        if definition.mod then

            switch =
                "add-on mod " .. definition.mod

        elseif definition.sandbox then

            switch =
                "sandbox option "
                .. AC_Features.SANDBOX_TABLE
                .. "."
                .. definition.sandbox
        end


        table.insert(
            lines,
            string.format(
                "%s [%s]: %s (%s; %s)",
                definition.name,
                definition.stability,
                enabled and "ON" or "off",
                why,
                switch
            )
        )
    end


    return lines
end
