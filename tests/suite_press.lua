-- Ammo Making - offline tests: the Reloading Press add-on.
--
-- Loaded by tests/run_tests.lua. What is checked here is text and Lua:
-- that the add-on's files say what the calibre model says, name only what
-- vanilla 42.20.4 has, and that the main mod without the add-on contains
-- nothing of the press. That the game loads the tile sheet and the entity,
-- places the station and lists the recipes is REQUIRES FUTURE IN-GAME
-- VERIFICATION.

return function(T)
    local check, eq, section, MOCK, ENGINE = T.check, T.eq, T.section, T.MOCK, T.ENGINE
    local readFile, ROOT = T.readFile, T.ROOT

    local ADDON = ROOT .. "/mod/AmmoMakingPress/"
    local ART = ROOT .. "/art/reloading_press/"
    local ADDONS = dofile(ROOT .. "/tests/render_addons.lua")

    local function stripComments(text)
        return (string.gsub(text, "/%*.-%*/", ""))
    end

    section("Reloading press add-on: the station, its tile sheet and its recipes, in a mod of their own")
    do
        local P = AC_Calibres.PRESS
        local sheet = readFile(ART .. "tiles.json")
        local entityText = readFile(ADDON .. "42/media/scripts/AC_ReloadingPress.txt")
        local entity = stripComments(entityText)
        local skin = stripComments(readFile(ADDON .. "42/media/scripts/AC_ReloadingPress_xuiSkin.txt"))
        local readme = readFile(ART .. "README.md")

        -- Without the add-on the press does not exist: the feature is off,
        -- the main mod's mod.info names no sheet, none of its scripts
        -- defines an entity or a press recipe, and no Lua file of it names
        -- a press sprite outside the central table of placeholders.
        MOCK.activeMods = {}
        eq(AC_Features.isEnabled("reloadingPress"), false, "the press feature is off without its add-on")
        eq(P.enabled, false, "so the calibre model's press switch is off")
        local mainInfo = readFile(ROOT .. "/mod/AmmoMaking/42/mod.info")
        check(string.find(mainInfo, "pack=", 1, true) == nil and string.find(mainInfo, "tiledef=", 1, true) == nil, "the main mod's mod.info names no texture pack and no tile definition")
        for _, name in ipairs({ "AC_Items.txt", "AC_Recipes.txt" }) do
            local script = readFile(T.SCRIPTS .. name)
            check(string.find(script, "%f[%a]entity%s") == nil, name .. " defines no entity")
            check(string.find(script, "ammomaking_press", 1, true) == nil, name .. " names no press sprite")
            check(string.find(script, P.benchTag, 1, true) == nil, name .. " names no press bench tag")
        end
        for _, name in ipairs(MOCK.MOD_FILES) do
            if name ~= "shared/AC_Visuals" then
                check(string.find(readFile(T.LUA .. name .. ".lua"), "ammomaking_press", 1, true) == nil, name .. ".lua names no press sprite: only AC_Visuals does")
            end
        end

        -- The add-on's mod.info: an id of its own, the main mod required,
        -- the same version and game build, and the sheet's two lines.
        local info = {}
        for key, value in string.gmatch(readFile(ADDON .. "42/mod.info"), "([%w_]+)=([^\r\n]*)") do info[key] = value end
        local main = {}
        for key, value in string.gmatch(mainInfo, "([%w_]+)=([^\r\n]*)") do main[key] = value end
        eq(info.id, AC_Features.get("reloadingPress").mod, "the add-on's id is the one the feature switch looks for")
        -- The engine strips a backslash from this line and splits on commas
        -- (jar: ChooseGameInfo.readModInfo), so "\AmmoMaking" names the mod
        -- whose id is AmmoMaking.
        eq(info.require, "\\" .. main.id, "it requires the main mod")
        eq(info.modversion, main.modversion, "it carries the main mod's version")
        eq(info.versionMin, main.versionMin, "and its minimum game build")
        check(string.find(info.name or "", "experimental", 1, true) ~= nil, "its name says it is experimental")
        check(string.find(info.description or "", "Not yet verified in game", 1, true) ~= nil, "and its description that it has not been seen in game")

        -- The sheet: one tileset of eight columns, two tiles, a file number
        -- in the engine's range, the names the design fixes, written into
        -- the add-on.
        local pack = string.match(sheet, '"pack"%s*:%s*"([%w_]+)"')
        local tiledef = string.match(sheet, '"tiledef"%s*:%s*"([%w_]+)"')
        local fileNumber = tonumber(string.match(sheet, '"fileNumber"%s*:%s*(%d+)'))
        local tileset = string.match(sheet, '"name"%s*:%s*"([%w_]+)"')
        eq(pack, "AmmoMakingPress", "the texture pack's name")
        eq(tiledef, "ammomaking_press", "the tile definition's name")
        check(fileNumber ~= nil and fileNumber >= 100 and fileNumber <= 8189, "the tile-definition number is in the engine's range, 100 to 8189 (" .. tostring(fileNumber) .. ")")
        eq(tileset, "ammomaking_press_01", "the tileset's name")
        eq(string.match(sheet, '"output"%s*:%s*"([^"]+)"'), "../../mod/AmmoMakingPress/42/media", "the sheet is built into the add-on, not into the main mod")
        eq(info.pack, pack, "the add-on's mod.info names the pack")
        eq(info.tiledef, tiledef .. " " .. tostring(fileNumber), "and the tile definition with its number")
        eq(tonumber(string.match(sheet, '"columns"%s*:%s*(%d+)')), 8, "eight columns, as every vanilla sheet")
        local indices, facings = {}, {}
        for index in string.gmatch(sheet, '"index"%s*:%s*(%d+)') do table.insert(indices, tonumber(index)) end
        for facing in string.gmatch(sheet, '"Facing"%s*:%s*"(%a)"') do table.insert(facings, facing) end
        eq(table.concat(indices, ","), "0,1", "two tiles")
        eq(table.concat(facings, ","), "S,E", "facing south and east, as vanilla's hand press")
        -- Each tile has the tile properties of vanilla's Hand Press, as the
        -- snapshot recorded them from the installed tile definitions. Those
        -- include IsMoveAble and a pick-up weight: picking the station up
        -- and putting it down again is the engine's own moveable handling.
        local reference = ENGINE.pressDraft.handPressTileProperties
        check(#reference >= 6, "the snapshot records the hand press's tile properties (" .. #reference .. ")")
        for _, key in ipairs(reference) do
            local _, count = string.gsub(sheet, '"' .. key .. '"%s*:', "")
            eq(count, 2, "both tiles set " .. key .. ", as vanilla's hand press does")
        end
        eq(tonumber(string.match(sheet, '"PickUpWeight"%s*:%s*(%d+)')), 400, "it weighs what the hand press weighs")
        -- The built files are there, and are the two binary formats.
        local function head(path)
            local handle = io.open(path, "rb")
            if not handle then return nil end
            local magic = handle:read(4)
            handle:close()
            return magic
        end
        eq(head(ADDON .. "42/media/" .. tiledef .. ".tiles"), "tdef", "the add-on ships the tile definitions")
        eq(head(ADDON .. "42/media/texturepacks/" .. pack .. ".pack"), "PZPK", "and the texture pack")

        -- The entity: the press's own tag, the sheet's sprites in order,
        -- and nothing vanilla does not have.
        eq(string.match(entity, "entity%s+([%w_]+)"), AC_Compat.PRESS_ENTITY, "the entity's name is the one the game-start check looks for")
        eq(string.match(entity, "Recipes%s*=%s*([%w_]+)"), P.benchTag, "its CraftBench tag is the calibre model's")
        local rows = {}
        for row in string.gmatch(entity, "row%s*=%s*([%w_]+)") do table.insert(rows, row) end
        eq(table.concat(rows, ","), tileset .. "_0," .. tileset .. "_1", "its faces are the sheet's two sprites")
        check(string.find(entity, "face S", 1, true) ~= nil and string.find(entity, "face E", 1, true) ~= nil, "south and east")
        check(string.find(entity, "AmmoMaking:", 1, true) == nil, "the build recipe does not name the Ammo Making perk (the engine would drop it)")
        check(string.find(entity, "xuiSkin%s+default") == nil, "the entity file holds no window skin: that is a file of its own, as vanilla's is")
        local style = string.match(entity, "entityStyle%s*=%s*([%w_]+)")
        check(style ~= nil and string.find(skin, "entity%s+" .. style) ~= nil, "the skin file defines the style the entity names (" .. tostring(style) .. ")")
        local D = ENGINE.pressDraft
        eq(D.timedAction, true, "its build timed action exists in vanilla")
        eq(D.entityNameFree, true, "no vanilla entity has its name")
        eq(D.tilesetNamesFree, true, "no vanilla tileset has the sheet's name")
        eq(D.spritesUnclaimed, true, "no vanilla entity claims its sprites")
        local named = 0
        for item, present in pairs(D.items) do
            named = named + 1
            eq(present, true, "its build input " .. item .. " exists in vanilla")
            check(string.find(entity, "[" .. item .. "]", 1, true) ~= nil, "(" .. item .. " is in the entity)")
        end
        check(named >= 3, "the build recipe's inputs were checked (" .. named .. ")")
        for tag, present in pairs(D.tags) do eq(present, true, "its tool tag " .. tag .. " exists in vanilla") end
        -- The build recipe's tooltip has a text.
        local tooltip = string.match(entity, "Tooltip%s*=%s*([%w_]+)")
        local tooltips = ADDONS.readNames(readFile(ADDON .. "common/media/lua/shared/Translate/EN/Tooltip.json"))
        check(tooltip ~= nil and tooltips[tooltip] ~= nil and tooltips[tooltip] ~= "", "the build recipe's tooltip key has a text (" .. tostring(tooltip) .. ")")

        -- Placeholders: what Lua knows of the press's visuals is what the
        -- scripts say.
        eq(#AC_Visuals.validate(), 0, "the placeholder table is sound: " .. table.concat(AC_Visuals.validate(), "; "))
        eq(AC_Visuals.get("pressSpriteSouth"), rows[1], "AC_Visuals mirrors the south sprite")
        eq(AC_Visuals.get("pressSpriteEast"), rows[2], "and the east sprite")
        local icons = {}
        for icon in string.gmatch(skin, "Icon%s*=%s*([%w_]+)") do icons[icon] = true end
        check(icons[AC_Visuals.get("pressWindowIcon")] and next(icons, next(icons)) == nil, "and the one window icon the skin uses")
        for _, visual in ipairs(AC_Visuals.LIST) do
            if visual.mirror then
                check(string.find(readFile(ROOT .. "/" .. visual.mirror), visual.value, 1, true) ~= nil, visual.key .. ": the script it mirrors names " .. visual.value)
            end
        end
        eq(AC_Visuals.get("nope"), nil, "an unknown visual is nil, not a guess")
        eq(AC_LaboratoryAnalyzer.CONFIG.worldSprite, AC_Visuals.get("analyzerWorldSprite"), "the analyzer takes its sprite from the same table")
        eq(AC_LaboratoryAnalyzer.CONFIG.worldSprite, "industry_03_61", "which is still the tile that was seen in game")

        -- The art folder says where things went and what the game still has
        -- to show.
        check(string.find(readme, "mod/AmmoMakingPress", 1, true) ~= nil, "the art folder says the sheet is built into the add-on")
        check(string.find(readme, "REQUIRES FUTURE IN-GAME VERIFICATION", 1, true) ~= nil, "and what has to be seen in game")
        check(string.find(readme, "pack=" .. pack, 1, true) ~= nil, "the README's pack line is the sheet's")
        check(string.find(readme, "tiledef=" .. tiledef .. " " .. fileNumber, 1, true) ~= nil, "and its tiledef line")
    end

    section("Reloading press add-on: its recipe script and names are generated from the calibre model")
    do
        local P = AC_Calibres.PRESS
        local header, body = T.RENDER.splitHeader(readFile(ROOT .. "/" .. ADDONS.PRESS_SCRIPT))
        check(header ~= "" and string.find(header, "GENERATED", 1, true) ~= nil, "the script header says the body is generated")
        eq(body, ADDONS.pressScriptBody(T.RENDER), "AC_PressRecipes.txt equals the rendered model (run tests/write_recipes.lua)")
        local handNames = ADDONS.readNames(readFile(T.TRANSLATE .. "Recipes.json"))
        eq(readFile(ROOT .. "/" .. ADDONS.PRESS_NAMES), ADDONS.pressNames(handNames), "the add-on's Recipes.json equals the rendered names")

        local recipes = ADDONS.pressRecipes()
        eq(#recipes, #P.steps * #AC_Calibres.LIST, "three press recipes per calibre")
        local script = T.parseScript(ROOT .. "/" .. ADDONS.PRESS_SCRIPT)
        eq(#script.blocks, #recipes, "one block each")
        local names, order = ADDONS.readNames(readFile(ROOT .. "/" .. ADDONS.PRESS_NAMES))
        eq(#order, #recipes + 1, "one name each, and the station's own")
        eq(names[ADDONS.PRESS_ENTITY], ADDONS.PRESS_DISPLAY_NAME, "the station's build recipe has a name")
        eq(ADDONS.PRESS_ENTITY, AC_Compat.PRESS_ENTITY, "under the entity's name, as the game-start check probes it")
        check(string.find(readFile(ROOT .. "/mod/AmmoMakingPress/42/media/scripts/AC_ReloadingPress.txt"), "entity " .. ADDONS.PRESS_ENTITY, 1, true) ~= nil, "which is the entity the script defines")
        -- "Requires a <bench>": the recipe window looks the bench tag up as
        -- IGUI_CraftingWindow_<tag> (ISWidgetTitleHeader.lua) and would show
        -- the raw key without it.
        eq(readFile(ROOT .. "/" .. ADDONS.PRESS_UI), ADDONS.pressUiNames(), "the add-on's IG_UI.json equals the rendering")
        eq(ADDONS.readNames(readFile(ROOT .. "/" .. ADDONS.PRESS_UI))["IGUI_CraftingWindow_" .. P.benchTag], ADDONS.PRESS_DISPLAY_NAME, "the bench tag has a display name")
        eq(readFile(ROOT .. "/" .. ADDONS.PRESS_MOVEABLES), ADDONS.pressMoveableNames(), "the add-on's Moveables.json equals the rendering")
        do
            -- The moveable's key is the tile's GroupName_CustomName.
            local sheet = readFile(ROOT .. "/art/reloading_press/tiles.json")
            local group = string.match(sheet, '"GroupName"%s*:%s*"([^"]+)"')
            local custom = string.match(sheet, '"CustomName"%s*:%s*"([^"]+)"')
            eq(ADDONS.readNames(readFile(ROOT .. "/" .. ADDONS.PRESS_MOVEABLES))[group .. "_" .. custom], ADDONS.PRESS_DISPLAY_NAME, "the placed object's name is keyed by its tile's group and custom name")
        end
        local seenNames = {}
        for _, value in pairs(handNames) do seenNames[value] = true end
        local mainIds = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do mainIds[recipe.id] = true end
        for _, recipe in ipairs(recipes) do
            local what = recipe.id
            check(not mainIds[recipe.id], what .. " is not a recipe of the main mod")
            eq(recipe.benchTag, P.benchTag, what .. " can only be made at the press")
            eq(recipe.timedAction, P.timedAction, what .. " uses vanilla's press action")
            check(recipe.benchTag ~= "AnySurfaceCraft", what .. " is not offered in the hand-craft window")
            -- Named after its hand recipe; no two recipes share a name.
            eq(names[recipe.id], handNames[recipe.handRecipe] .. P.nameSuffix, what .. " is named after its hand recipe")
            check(not seenNames[names[recipe.id]], what .. " has a name nothing else has")
            seenNames[names[recipe.id]] = true
            -- Broken tools: the die set is the only kept line, and it is the
            -- hand recipe's own line, flags and all.
            local hand = AC_Materials.getRecipe(recipe.handRecipe)
            local kept = 0
            for _, input in ipairs(recipe.inputs) do
                if input.keep then
                    kept = kept + 1
                    local same = false
                    for _, handInput in ipairs(hand.inputs) do
                        same = same or (handInput.keep == true and handInput.count == input.count
                            and T.sameList(handInput.items, input.items) and T.sameList(handInput.tags, input.tags)
                            and T.sameList(handInput.flags, input.flags))
                    end
                    check(same, what .. ": its kept line is the hand recipe's own, flags and all")
                end
            end
            eq(kept, 1, what .. " keeps exactly one tool: the die set")
        end
        eq(ENGINE.timedActions[P.timedAction], true, "the press's timed action exists in vanilla")

        -- With the add-on active the main mod's Lua takes the press in:
        -- the recipes join the list, each gets its OnCreate callback (the
        -- script names it) and its skill requirement, and the game-start
        -- check probes the station. Without it, none of that.
        local before = #AC_Materials.RECIPES
        for key in pairs(AC_Materials) do
            check(type(key) ~= "string" or string.sub(key, -#P.idSuffix) ~= P.idSuffix, "off: no press callback is defined (" .. tostring(key) .. ")")
        end
        MOCK.activeMods = { "\\AmmoMaking", "AmmoMakingPress" }
        T.reloadMod()
        local pressOn = AC_Calibres.PRESS
        eq(pressOn.enabled, true, "add-on active: the press is on")
        eq(#AC_Materials.RECIPES, before + #recipes, "its recipes join the list")
        local callbacks = 0
        for _, block in ipairs(script.blocks) do
            local onCreate = string.match(block.fields.OnCreate or "", "^AC_Materials%.([%w_]+)$")
            check(onCreate ~= nil and type(AC_Materials[onCreate]) == "function", block.name .. ": the OnCreate function its script names exists")
            callbacks = callbacks + 1
            local recipe = AC_Materials.getRecipe(block.name)
            check(recipe ~= nil and recipe.press == true, block.name .. " is in the recipe list as a press recipe")
            if recipe then
                eq(AC_Materials.getRequiredLevel(recipe), AC_Materials.getRequiredLevel(AC_Materials.getRecipe(recipe.handRecipe)), block.name .. " needs the level its hand recipe needs")
                eq(AC_Materials.getRecipeXP(recipe), AC_Materials.getRecipeXP(AC_Materials.getRecipe(recipe.handRecipe)), block.name .. " pays the XP its hand recipe pays")
                local ok, reason = AC_Materials.checkConservation(recipe)
                check(ok, block.name .. " conserves material: " .. tostring(reason))
            end
        end
        eq(callbacks, #recipes, "every press recipe has its callback")
        -- A craft at the press grants its XP once, like any other.
        local sample = AC_Materials.getRecipe(recipes[1].id)
        local player = MOCK.newPlayer()
        MOCK.capturePrint(true)
        local granted = AC_Materials[sample.callback]({
            getAllCreatedItems = function() return MOCK.arrayList({}) end,
            getAllConsumedItems = function() return MOCK.arrayList({}) end,
        }, player)
        MOCK.capturePrint(false)
        eq(granted, AC_Materials.getRecipeXP(sample), "a press craft grants its hand recipe's XP")
        eq(#player.xpLog, 1, "once")

        -- The debug tree gets a Stations group, with the kit the station
        -- is built from: exactly the consumed and kept items of the
        -- entity's build recipe.
        MOCK.debug = true
        local debugPlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, T.GRASS) })
        local tree = T.fillWorldMenu(debugPlayer, debugPlayer.square):find("Ammo Making Debug")
        local stations = tree.submenu:find("Stations")
        check(stations ~= nil and stations.submenu ~= nil, "add-on active: the debug tree has a Stations group")
        eq(table.concat(stations.submenu:names(), " | "), "Spawn Press Build Kit (hammer, steel bars, planks, nails)", "with the press build kit")
        local entityText = (string.gsub(readFile(ADDON .. "42/media/scripts/AC_ReloadingPress.txt"), "/%*.-%*/", ""))
        local wanted = {}
        for count, item in string.gmatch(entityText, "item%s+(%d+)%s+%[(Base%.[%w_]+)%]") do wanted[item] = tonumber(count) end
        local kit, addedToMock = {}, {}
        for _, entry in ipairs(pressOn.buildKit) do
            kit[entry[1]] = entry[2]
            if not MOCK.knownScriptItems[entry[1]] then
                MOCK.knownScriptItems[entry[1]] = true
                addedToMock[entry[1]] = true
            end
        end
        for item, count in pairs(wanted) do eq(kit[item], count, "the build kit holds the " .. count .. " " .. item .. " the build recipe takes") end
        eq(kit["Base.Hammer"], 1, "and a hammer for its kept tool line")
        local kitSize = 0
        for _ in pairs(kit) do kitSize = kitSize + 1 end
        local wantedSize = 1
        for _ in pairs(wanted) do wantedSize = wantedSize + 1 end
        eq(kitSize, wantedSize, "and nothing else")
        MOCK.capturePrint(true)
        AC_GeologyDebug.spawnPressBuildKit(debugPlayer)
        MOCK.capturePrint(false)
        for item, count in pairs(kit) do eq(debugPlayer.inventory:count(item), count, "the debug kit hands out " .. count .. " " .. item) end
        -- What the mock did not know before, it forgets again; that these
        -- items exist in the installed game is the snapshot's statement
        -- (ENGINE.pressDraft.items), checked above.
        for item in pairs(addedToMock) do MOCK.knownScriptItems[item] = nil end
        MOCK.debug = false

        -- The game-start check: the feature line, the entity, both sprites.
        local function labels(results)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            return found
        end
        local ids = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
        MOCK.resetCraftRecipes(ids)
        AC_Materials.applySkillRequirements()
        MOCK.entityScripts = { [AC_Compat.PRESS_ENTITY] = {} }
        MOCK.knownSprites[AC_Visuals.get("pressSpriteSouth")] = true
        MOCK.knownSprites[AC_Visuals.get("pressSpriteEast")] = true
        MOCK.capturePrint(true)
        local found = labels((AC_Compat.run(false)))
        eq(found["feature Reloading Press: ON (on)"], "OK", "the check reports the press as on")
        eq(found["reloading press station entity (" .. AC_Compat.PRESS_ENTITY .. ")"], "OK", "finds its entity")
        eq(found["reloading press sprite (" .. AC_Visuals.get("pressSpriteSouth") .. ")"], "OK", "and its south sprite")
        eq(found["reloading press sprite (" .. AC_Visuals.get("pressSpriteEast") .. ")"], "OK", "and its east sprite")
        -- The add-on ticked but its scripts not loaded: said plainly.
        MOCK.entityScripts = {}
        MOCK.knownSprites[AC_Visuals.get("pressSpriteEast")] = nil
        found = labels((AC_Compat.run(false)))
        eq(found["reloading press station entity " .. AC_Compat.PRESS_ENTITY .. " not found"], "WARNING", "a missing entity is a WARNING")
        eq(found["reloading press sprite " .. AC_Visuals.get("pressSpriteEast") .. " not found"], "WARNING", "a sprite the tile sheet did not bring is a WARNING")
        MOCK.entityLookup = false
        found = labels((AC_Compat.run(false)))
        eq(found["reloading press station entity"], "UNVERIFIED", "a build without the entity lookup is UNVERIFIED, not a failure")
        MOCK.entityLookup = true
        MOCK.capturePrint(false)
        MOCK.knownSprites[AC_Visuals.get("pressSpriteSouth")] = nil

        -- Off again: the list is what it was, and the check probes nothing
        -- of the press.
        MOCK.activeMods = {}
        T.reloadMod()
        eq(AC_Calibres.PRESS.enabled, false, "add-on gone: the press is off")
        eq(#AC_Materials.RECIPES, before, "and the recipe list is what it was")
        ids = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
        MOCK.resetCraftRecipes(ids)
        AC_Materials.applySkillRequirements()
        MOCK.capturePrint(true)
        found = labels((AC_Compat.run(false)))
        MOCK.capturePrint(false)
        eq(found["feature Reloading Press: off (off)"], "OK", "the check reports the press as off")
        MOCK.debug = true
        local offPlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, T.GRASS) })
        eq(T.fillWorldMenu(offPlayer, offPlayer.square):find("Ammo Making Debug").submenu:find("Stations"), nil, "off: the debug tree has no Stations group")
        MOCK.debug = false
        for label in pairs(found) do
            check(string.find(label, "reloading press", 1, true) == nil, "off: nothing of the press is probed (" .. label .. ")")
        end
    end
end
