-- Ammo Making - offline tests: the documents that describe what is left.
--
-- Loaded by tests/run_tests.lua. Three documents exist for whoever takes
-- the mod from "code complete" to "released": the placeholder list (a
-- generated table), the art brief and the in-game checklist. A document
-- cannot be tested for being right about the game; it can be tested for
-- not drifting from the code: every menu entry, console line, feature name
-- and config key it quotes has to exist.

return function(T)
    local check, eq, section = T.check, T.eq, T.section
    local readFile, ROOT, LUA = T.readFile, T.ROOT, T.LUA
    local ADDONS = dofile(ROOT .. "/tests/render_addons.lua")

    section("docs/PLACEHOLDER_ASSETS.md: the table equals its rendering")
    do
        local document = readFile(ROOT .. "/" .. ADDONS.ASSETS_DOCUMENT)
        local mainItems = readFile(ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt")
        local spentItems = readFile(ROOT .. "/" .. ADDONS.SPENT_ITEMS)
        check(string.find(document, ADDONS.renderPlaceholderBlock(mainItems, spentItems), 1, true) ~= nil,
            "the placeholder table is what tests/write_recipes.lua renders")
        eq(ADDONS.replacePlaceholders(document, mainItems, spentItems), document, "rendering it again changes nothing")
        eq(ADDONS.replacePlaceholders("no markers", mainItems, spentItems), nil, "a document without the markers is refused")

        -- One row per visual and per item; the brief's five columns.
        local rendered = ADDONS.renderPlaceholders(mainItems, spentItems)
        for _, visual in ipairs(AC_Visuals.LIST) do
            check(string.find(rendered, "key `" .. visual.key .. "`", 1, true) ~= nil, visual.key .. " has a row")
            check(string.find(rendered, "`" .. visual.value .. "`", 1, true) ~= nil, visual.key .. ": its value is in the row")
        end
        local main, spent = ADDONS.readItemsInOrder(mainItems), ADDONS.readItemsInOrder(spentItems)
        check(#main > 0, "the main mod's items are read")
        eq(#spent, #AC_Calibres.LIST, "one spent item per calibre")
        for _, list in ipairs({ main, spent }) do
            for _, item in ipairs(list) do
                check(string.find(rendered, "(`" .. item.fullType .. "`)", 1, true) ~= nil, item.fullType .. " has a row")
                check(item.fields.Icon ~= nil, item.fullType .. " has an icon to list")
            end
        end
        check(string.find(rendered, (#AC_Visuals.LIST + #main + #spent) .. " placeholders in all", 1, true) ~= nil, "the total is the sum of the rows")
        for _, column in ipairs({ "Feature", "Current placeholder", "Vanilla source", "Where configured", "Final asset needed later" }) do
            check(string.find(rendered, column, 1, true) ~= nil, "column: " .. column)
        end
        check(string.find(document, AC_Visuals.MARK, 1, true) ~= nil, "the document names the marker " .. AC_Visuals.MARK)
    end

    section("docs/ART_HANDOFF.md: every placeholder it names is a real one")
    do
        local document = readFile(ROOT .. "/docs/ART_HANDOFF.md")
        for _, visual in ipairs(AC_Visuals.LIST) do
            check(string.find(document, "`" .. visual.key .. "`", 1, true) ~= nil, "the brief covers the visual " .. visual.key)
            check(string.find(document, visual.value, 1, true) ~= nil, visual.key .. ": and names what it replaces (" .. visual.value .. ")")
        end
        -- Every "Icon = X" the brief says it replaces is an icon an item of
        -- the mod uses today.
        local used = {}
        for _, item in ipairs(ADDONS.readItemsInOrder(readFile(ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Items.txt"))) do
            used[item.fields.Icon] = true
        end
        used[AC_Visuals.get("pressWindowIcon")] = true
        local named = 0
        for icon in string.gmatch(document, "`Icon = ([%w_]+)") do
            named = named + 1
            eq(used[icon], true, "the brief's icon " .. icon .. " is in use")
        end
        check(named >= 8, "the brief names the icons it replaces (" .. named .. ")")
        for _, heading in ipairs({ "Inventory icon", "World model", "Tile sprite", "Priority 1", "Naming and delivery", "What not to draw" }) do
            check(string.find(document, heading, 1, true) ~= nil, "section: " .. heading)
        end
    end

    section("docs/INGAME_VALIDATION.md: 22 sections in order, quoting only what exists")
    do
        local document = readFile(ROOT .. "/docs/INGAME_VALIDATION.md")
        local titles = {
            "Startup", "Compatibility report", "Debug menu", "Geology", "Field assay", "Advanced assay", "Analyzer",
            "Mining", "Save and reload: depletion", "Metallurgy", "Brass", "9mm", "Rifle", "12 gauge", "Recycling",
            "Loot", "Ammo boxes", "Press", "Spent cases", "Quality tally", "Save and reload", "Error log check",
        }
        local last, starts = 0, {}
        for index, title in ipairs(titles) do
            local at = string.find(document, "\n## " .. index .. ". " .. title, 1, true)
            check(at ~= nil, "section " .. index .. ": " .. title)
            check(at ~= nil and at > last, "section " .. index .. " follows section " .. (index - 1))
            last = at or last
            starts[index] = at or last
        end
        starts[#titles + 1] = string.find(document, "\n## After the session", 1, true)
        check(starts[#titles + 1] ~= nil and starts[#titles + 1] > last, "the closing section follows them")
        for index, title in ipairs(titles) do
            local body = string.sub(document, starts[index], (starts[index + 1] or #document) - 1)
            check(string.find(body, "\nSteps\n", 1, true) ~= nil, title .. ": steps")
            check(string.find(body, "\nExpected", 1, true) ~= nil, title .. ": expected result")
            check(string.find(body, "\nResult: ____", 1, true) ~= nil, title .. ": a pass/fail field")
        end
        local _, fields = string.gsub(document, "\nResult: ____", "")
        eq(fields, #titles, "one pass/fail field per section")

        -- Debug menu entries are quoted as **Group > Entry**: the group is
        -- a submenu of the debug tree and the entry starts one of its
        -- option labels.
        local debug = readFile(LUA .. "client/AC_GeologyDebug.lua")
        local quoted = 0
        for group, entry in string.gmatch((string.gsub(document, "\n%s*", " ")), "%*%*(%a+) > ([^%*]+)%*%*") do
            quoted = quoted + 1
            check(string.find(debug, '"' .. group .. '"', 1, true) ~= nil, "debug submenu " .. group .. " exists")
            for part in string.gmatch(entry .. " / ", "(.-) / ") do
                local label = string.gsub(part, " > .*$", "")
                check(string.find(debug, '"' .. label, 1, true) ~= nil, "debug entry '" .. label .. "' exists")
            end
        end
        check(quoted >= 20, "the checklist gives debug shortcuts (" .. quoted .. ")")
        for _, group in ipairs({ "Geology", "Analyzer", "Metallurgy", "Ammunition", "Stations", "Diagnostics" }) do
            check(string.find(debug, '"' .. group .. '"', 1, true) ~= nil, "the debug tree has " .. group)
        end

        -- Feature lines as AC_Compat prints them.
        local flat = string.gsub(document, "\n%s*", " ")
        for _, definition in ipairs(AC_Features.DEFINITIONS) do
            check(string.find(flat, "feature " .. definition.name .. ": off", 1, true) ~= nil, "the off line of " .. definition.name)
        end
        check(string.find(flat, "feature " .. AC_Features.get("qualityEffects").name .. ": off (locked)", 1, true) ~= nil, "quality effects are expected locked")
        check(string.find(flat, "conflict with " .. AC_Features.get("spentCases").conflicts[1], 1, true) ~= nil, "the conflict line names the conflicting mod")

        -- Add-on names as their mod.info gives them, options as translated.
        for _, folder in ipairs({ "AmmoMakingPress", "AmmoMakingSpentCases" }) do
            local name = string.match(readFile(ROOT .. "/mod/" .. folder .. "/42/mod.info"), "name=([^\r\n]+)")
            check(string.find(flat, name, 1, true) ~= nil, "the add-on is named as the mod list shows it: " .. name)
        end
        check(string.find(flat, #AC_QualityCarrier.WRAPS .. " of " .. #AC_QualityCarrier.WRAPS .. " reload functions", 1, true) ~= nil, "the tracking install line has the real count")
        check(string.find(flat, AC_SpentCases.CONFIG.recoveryPercent .. " % found, placed on the " .. AC_SpentCases.CONFIG.placement, 1, true) ~= nil, "the spent-case install line has the real defaults")
        check(string.find(flat, "Calibre definitions loaded (" .. #AC_Calibres.LIST .. ")", 1, true) ~= nil, "the calibre count")
        check(string.find(flat, AC_Visuals.get("analyzerWorldSprite"), 1, true) ~= nil, "the analyzer's placeholder sprite is named")

        -- Recipe names in italics are names of the three Recipes.json.
        local names = {}
        for _, path in ipairs({
            T.TRANSLATE .. "Recipes.json",
            ROOT .. "/" .. ADDONS.PRESS_NAMES,
            ROOT .. "/mod/AmmoMakingSpentCases/common/media/lua/shared/Translate/EN/Recipes.json",
        }) do
            for _, value in string.gmatch(readFile(path), '"([^"]+)"%s*:%s*"([^"]*)"') do names[value] = true end
        end
        local function known(text)
            if names[text] then return true end
            for name in pairs(names) do
                if string.sub(name, 1, #text) == text then return true end
            end
            return false
        end
        local recipes = 0
        for text in string.gmatch(flat, "%*(%u[^%*]-)%*") do
            if string.find(text, "^Smelt ") or string.find(text, "^Cast ") or string.find(text, "^Forge ") or string.find(text, "^Form ")
                or string.find(text, "^Swage ") or string.find(text, "^Assemble ") or string.find(text, "^Make ") or string.find(text, "^Punch ")
                or string.find(text, "^Scrap ") or string.find(text, "^Build ")
            then
                recipes = recipes + 1
                local stem = string.gsub(text, " %.%.%.$", "")
                check(known(stem), "the recipe '" .. text .. "' exists")
            end
        end
        check(recipes >= 20, "the checklist names the recipes to craft (" .. recipes .. ")")

        -- It never asks for what the mod refuses.
        check(string.find(document, "Use a **new** sandbox world for the session, single player", 1, true) ~= nil, "single player is stated")
        check(string.find(document, "untick", 1, true) ~= nil, "it says what to do when a world does not load")
    end

    section("docs/REFERENCE_IMPLEMENTATIONS.md: references, not dependencies")
    do
        local document = readFile(ROOT .. "/docs/REFERENCE_IMPLEMENTATIONS.md")
        check(string.find(document, "Nothing was copied", 1, true) ~= nil, "it says nothing was copied")
        check(string.find(document, "No dependency", 1, true) ~= nil, "and that there is no dependency")
        for _, folder in ipairs({ "AmmoMaking", "AmmoMakingPress", "AmmoMakingSpentCases" }) do
            local info = readFile(ROOT .. "/mod/" .. folder .. "/42/mod.info")
            local required = string.match(info, "require=([^\r\n]+)")
            check(required == nil or required == "\\AmmoMaking", folder .. " requires nothing but the main mod")
        end
        for _, conflict in ipairs(AC_Features.get("spentCases").conflicts) do
            check(string.find(document, conflict, 1, true) ~= nil, "the conflicting mod " .. conflict .. " is explained")
        end
    end
end
