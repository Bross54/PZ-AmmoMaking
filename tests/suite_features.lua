-- Ammo Making - offline tests: the feature switches (AC_Features).
--
-- Loaded by tests/run_tests.lua, which hands over its helpers. Mocked
-- engine: that the game reports an add-on's id through getActivatedMods()
-- and a sandbox option through SandboxVars is not proved here.

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK

    section("Feature switches: one table decides what exists, and everything is off by default")
    do
        local F = AC_Features
        eq(#F.validate(), 0, "the feature table is sound: " .. table.concat(F.validate(), "; "))

        -- Pinned: which runtime-sensitive systems there are, how sure the
        -- mod is of each, and what switches it. Changing one of these is a
        -- decision, and this is where it shows.
        local expected = {
            { "reloadingPress", F.EXPERIMENTAL, "mod", "AmmoMakingPress", false },
            { "spentCases", F.EXPERIMENTAL, "mod", "AmmoMakingSpentCases", true },
            { "qualityTracking", F.EXPERIMENTAL, "sandbox", "QualityTracking", true },
            { "qualityEffects", F.DISABLED, "sandbox", "QualityEffects", true },
        }
        eq(#F.DEFINITIONS, #expected, "four switched features")
        for index, want in ipairs(expected) do
            local definition = F.DEFINITIONS[index]
            eq(definition.id, want[1], "feature " .. index .. " is " .. want[1])
            eq(definition.stability, want[2], want[1] .. " stability")
            eq(definition[want[3]], want[4], want[1] .. " is switched by its " .. want[3])
            eq(definition.singlePlayerOnly, want[5], want[1] .. " single player only")
            eq(F.get(want[1]), definition, want[1] .. " is found by id")
        end
        eq(F.get("qualityEffects").requires, "qualityTracking", "effects need the tracking under them")
        eq(F.get("nope"), nil, "an unknown feature is not found")

        -- Nothing switched on: everything is off, and says why.
        MOCK.activeMods, MOCK.client, MOCK.server = {}, false, false
        SandboxVars = {}
        for _, want in ipairs(expected) do
            local enabled, why = F.getState(want[1])
            eq(enabled, false, want[1] .. " is off by default")
            eq(why, want[2] == F.DISABLED and "locked" or "off", want[1] .. " says why")
            eq(F.isEnabled(want[1]), false, want[1] .. ": isEnabled agrees")
        end
        local unknown, whyUnknown = F.getState("nope")
        eq(unknown, false, "an unknown feature is off")
        eq(whyUnknown, "unknown", "and says so")

        -- An add-on mod is the switch for anything that ships scripts.
        -- Both spellings of an id that Build 42 uses are accepted; nothing
        -- else is.
        for _, spelling in ipairs({ "AmmoMakingPress", "\\AmmoMakingPress" }) do
            MOCK.activeMods = { "\\AmmoMaking", spelling }
            eq(F.isEnabled("reloadingPress"), true, "the press is on when the add-on is listed as " .. spelling)
            eq(F.isEnabled("spentCases"), false, "and nothing else comes on with it")
        end
        for _, spelling in ipairs({ "AmmoMakingPressX", "ammomakingpress", "AmmoMaking", "/AmmoMakingPress", "" }) do
            MOCK.activeMods = { spelling }
            eq(F.isEnabled("reloadingPress"), false, "the press stays off for the id '" .. spelling .. "'")
        end
        MOCK.activeMods = { "AmmoMakingSpentCases" }
        eq(F.isEnabled("spentCases"), true, "spent cases are on with their add-on")
        eq(F.isEnabled("reloadingPress"), false, "and the press is not")

        -- A list the engine does not hand out, or one that throws, is "off".
        local realList = getActivatedMods
        getActivatedMods = function() error("no mod list") end
        eq(F.isModActive("AmmoMakingPress"), false, "a failing mod list switches nothing on")
        getActivatedMods = function() return nil end
        eq(F.isModActive("AmmoMakingPress"), false, "nor does a missing one")
        getActivatedMods = function() return {} end
        eq(F.isModActive("AmmoMakingPress"), false, "nor one without contains()")
        getActivatedMods = nil
        eq(F.isModActive("AmmoMakingPress"), false, "nor a build without the function")
        getActivatedMods = realList
        eq(F.isModActive(nil), false, "no id, not active")
        MOCK.activeMods = {}

        -- A sandbox option is the switch for a Lua-only feature. Only the
        -- boolean true counts.
        for _, value in ipairs({ "true", 1, "on", {}, false }) do
            SandboxVars = { AmmoMaking = { QualityTracking = value } }
            eq(F.isEnabled("qualityTracking"), false, "tracking stays off for the value " .. tostring(value))
        end
        SandboxVars = { AmmoMaking = "broken" }
        eq(F.isEnabled("qualityTracking"), false, "a broken option table switches nothing on")
        SandboxVars = nil
        eq(F.isEnabled("qualityTracking"), false, "nor do missing sandbox options")
        SandboxVars = { OtherMod = { QualityTracking = true } }
        eq(F.isEnabled("qualityTracking"), false, "nor another mod's option of the same name")
        SandboxVars = { AmmoMaking = { QualityTracking = true } }
        eq(F.isEnabled("qualityTracking"), true, "the boolean true switches tracking on")

        -- A locked feature has no switch: its option and everything it
        -- needs can be on, and it stays off.
        SandboxVars = { AmmoMaking = { QualityTracking = true, QualityEffects = true } }
        local effects, whyEffects = F.getState("qualityEffects")
        eq(effects, false, "firing effects stay off with their option on")
        eq(whyEffects, "locked", "because they are locked")

        -- Unlocked (as a later version would), it still needs the tracking.
        local definition = F.get("qualityEffects")
        definition.stability = F.EXPERIMENTAL
        eq(F.isEnabled("qualityEffects"), true, "(unlocked, with tracking on, the effects would be on)")
        SandboxVars = { AmmoMaking = { QualityEffects = true } }
        local alone, whyAlone = F.getState("qualityEffects")
        eq(alone, false, "(and off without the tracking)")
        eq(whyAlone, "needs qualityTracking", "saying what they need")
        definition.stability = F.DISABLED

        -- Multiplayer: a feature that changes items from Lua has no server
        -- authority yet and is off on a client and on a server. The press
        -- is the engine's own station and is not affected.
        SandboxVars = { AmmoMaking = { QualityTracking = true } }
        MOCK.activeMods = { "AmmoMakingPress", "AmmoMakingSpentCases" }
        for _, side in ipairs({ "client", "server" }) do
            MOCK[side] = true
            for _, id in ipairs({ "spentCases", "qualityTracking" }) do
                local enabled, why = F.getState(id)
                eq(enabled, false, id .. " is off on a multiplayer " .. side)
                eq(why, "multiplayer", id .. " says why")
            end
            eq(F.isEnabled("reloadingPress"), true, "the press is not switched off on a " .. side)
            MOCK[side] = false
        end
        eq(F.isEnabled("spentCases"), true, "(single player again: on)")

        -- A mod that already leaves a casing for every shot: spent cases
        -- stand down rather than leave a second one.
        eq(table.concat(F.get("spentCases").conflicts, ","), "HBVCEFb42", "spent cases know the one installed mod that does the same")
        for _, spelling in ipairs({ "HBVCEFb42", "\HBVCEFb42" }) do
            MOCK.activeMods = { "AmmoMakingSpentCases", spelling }
            local enabled, why = F.getState("spentCases")
            eq(enabled, false, "spent cases stand down beside " .. spelling)
            eq(why, "conflict with HBVCEFb42", "and say why")
        end
        MOCK.activeMods = { "AmmoMakingPress", "AmmoMakingSpentCases" }

        -- describe(): one line per feature, for the log and the debug menu.
        local lines = F.describe()
        eq(#lines, #F.DEFINITIONS, "one line per feature")
        check(string.find(lines[1], "Reloading Press [experimental]: ON (on; add-on mod AmmoMakingPress)", 1, true) ~= nil, "the press line: " .. lines[1])
        check(string.find(lines[4], "[disabled]: off (locked; sandbox option AmmoMaking.QualityEffects)", 1, true) ~= nil, "the locked line: " .. lines[4])

        MOCK.activeMods = {}
        SandboxVars = {}

        -- validate() refuses a table that could switch something on by
        -- accident.
        local function problems(change)
            local copy = {}
            for index, original in ipairs(F.DEFINITIONS) do
                local entry = {}
                for key, value in pairs(original) do entry[key] = value end
                copy[index] = entry
            end
            change(copy)
            return table.concat(F.validate(copy), "; ")
        end
        local function refused(what, change, text)
            local found = problems(change)
            check(string.find(found, text, 1, true) ~= nil, what .. " is refused: " .. found)
        end
        refused("a second feature with the same id", function(d) d[2].id = d[1].id end, "is defined twice")
        refused("a feature without an id", function(d) d[1].id = nil end, "has no id")
        refused("an unknown stability", function(d) d[1].stability = "beta" end, "has no known stability")
        refused("a feature with two switches", function(d) d[1].sandbox = "Press" end, "needs exactly one switch")
        refused("a feature with no switch", function(d) d[1].mod = nil end, "needs exactly one switch")
        refused("two features on one add-on", function(d) d[2].mod = d[1].mod end, "shares its switch")
        refused("two features on one option", function(d) d[4].sandbox = d[3].sandbox end, "shares its switch")
        refused("a requirement that is no feature", function(d) d[4].requires = "tracking" end, "which is not a feature")
        refused("a feature that requires itself", function(d) d[4].requires = d[4].id end, "which is not a feature")
        refused("a feature that does not say whether it is single player only", function(d) d[1].singlePlayerOnly = nil end, "single player only")
        refused("a feature without a name", function(d) d[1].name = "" end, "has no name")
        refused("a feature in conflict with its own add-on", function(d) d[2].conflicts = { d[2].mod } end, "not another mod's id")
        refused("conflicts that are not a list", function(d) d[2].conflicts = "HBVCEFb42" end, "other than a list")
        eq(problems(function() end), "", "(the unchanged table passes)")
    end
end
