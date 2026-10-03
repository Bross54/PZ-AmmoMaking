-- Ammo Making - offline tests: spent cases (AC_SpentCases and its add-on).
--
-- Loaded by tests/run_tests.lua. The firearm side runs against
-- tests/firearm_model.lua, a model of vanilla's reload actions written from
-- the installed 42.20.4 Lua. It shows what the hooks do IF vanilla behaves
-- as it reads. That the game fires the event once per shot and calls the
-- wrapped functions is REQUIRES FUTURE IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK, ENGINE = T.check, T.eq, T.section, T.MOCK, T.ENGINE
    local readFile, ROOT = T.readFile, T.ROOT

    local ADDON = ROOT .. "/mod/AmmoMakingSpentCases/"
    local ADDONS = dofile(ROOT .. "/tests/render_addons.lua")
    local MODEL = dofile(ROOT .. "/tests/firearm_model.lua")

    local function spentItemCount(list, fullType)
        local count = 0
        for _, item in ipairs(list) do
            if fullType == nil and string.find(item.fullType, "%.Spent") or item.fullType == fullType then count = count + 1 end
        end
        return count
    end

    -- The mod reloaded with the spent-cases add-on active (or not), a fresh
    -- firearm model, and the hooks installed when the feature allows.
    local function start(active)
        MOCK.activeMods = active and { "AmmoMaking", "AmmoMakingSpentCases" } or {}
        MOCK.client, MOCK.server, MOCK.debug = false, false, false
        MOCK.randomSequence = nil
        T.reloadMod()
        MODEL.install(MOCK)
        for _, fullType in ipairs(AC_SpentCases.getItems()) do
            MOCK.knownScriptItems[fullType] = active and true or nil
        end
        MOCK.capturePrint(true)
        local installed = AC_SpentCases.installIfEnabled()
        MOCK.capturePrint(false)
        return installed
    end

    local function finish()
        if MODEL.uninstall then MODEL.uninstall() end
        for _, fullType in ipairs(AC_SpentCases.getItems()) do MOCK.knownScriptItems[fullType] = nil end
        MOCK.activeMods = {}
        MOCK.client, MOCK.server, MOCK.debug = false, false, false
        T.reloadMod()
    end

    section("Spent cases add-on: one spent case per calibre, generated, and only scrap")
    do
        MOCK.activeMods = {}
        local S = AC_SpentCases
        eq(#S.validate(), 0, "the spent-case description is sound: " .. table.concat(S.validate(), "; "))

        -- The mapping is the calibre model's: one spent item per calibre,
        -- none of them a case that could be loaded again.
        local mainItems = readFile(T.SCRIPTS .. "AC_Items.txt")
        local clean = ADDONS.readItemFields(mainItems)
        local seen = {}
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local what = calibre.id
            check(type(calibre.spentCase) == "string" and string.sub(calibre.spentCase, 1, 16) == "AmmoMaking.Spent", what .. " names its spent case")
            check(calibre.spentCase ~= calibre.case, what .. ": a spent case is not the unused case")
            check(not seen[calibre.spentCase], what .. ": its spent case is its own")
            seen[calibre.spentCase] = true
            eq(S.getSpentCaseForRound(calibre.round), calibre.spentCase, what .. ": the round maps to it")
            eq(T.declaredItems[calibre.spentCase], nil, what .. ": the main mod's item script does not define it")
        end
        eq(S.getSpentCaseForRound("Base.Nails"), nil, "something that is not a round leaves nothing")
        eq(#S.getItems(), #AC_Calibres.LIST, "one spent item per calibre")

        -- No recipe of the mod takes a spent case except the spent
        -- scrapping recipes: it cannot be formed, primed or assembled.
        local spentRecipes = ADDONS.spentRecipes()
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            for _, input in ipairs(recipe.inputs) do
                for _, id in ipairs(input.items or {}) do
                    check(not seen[id], recipe.id .. " of the main mod does not take a spent case")
                end
            end
        end
        for _, calibre in ipairs(AC_Calibres.LIST) do
            for _, recipe in ipairs(AC_Calibres.buildPressRecipes(calibre)) do
                for _, input in ipairs(recipe.inputs) do
                    for _, id in ipairs(input.items or {}) do check(not seen[id], recipe.id .. " does not take a spent case") end
                end
            end
        end

        -- The add-on's mod.info.
        local info, main = {}, {}
        for key, value in string.gmatch(readFile(ADDON .. "42/mod.info"), "([%w_]+)=([^\r\n]*)") do info[key] = value end
        for key, value in string.gmatch(readFile(ROOT .. "/mod/AmmoMaking/42/mod.info"), "([%w_]+)=([^\r\n]*)") do main[key] = value end
        eq(info.id, AC_Features.get("spentCases").mod, "the add-on's id is the one the feature switch looks for")
        eq(info.require, "\\" .. main.id, "it requires the main mod")
        eq(info.modversion, main.modversion, "it carries the main mod's version")
        eq(info.versionMin, main.versionMin, "and its minimum game build")
        eq(info.pack, nil, "it ships no texture pack")
        eq(info.tiledef, nil, "and no tile sheet")
        check(string.find(info.name or "", "experimental", 1, true) ~= nil, "its name says it is experimental")
        check(string.find(info.description or "", "Not yet verified in game", 1, true) ~= nil, "and its description that it has not been seen in game")
        check(string.find(info.description or "", "Single player only", 1, true) ~= nil, "and that it is single player only")

        -- Items: generated; each looks and weighs like the case it was.
        local header, body = T.RENDER.splitHeader(readFile(ROOT .. "/" .. ADDONS.SPENT_ITEMS))
        check(string.find(header, "GENERATED", 1, true) ~= nil and string.find(header, "PLACEHOLDER_VISUAL", 1, true) ~= nil, "the item script says it is generated and that its visuals are placeholders")
        eq(body, ADDONS.spentItemsBody(mainItems), "AC_SpentCaseItems.txt equals the rendered model (run tests/write_recipes.lua)")
        eq(readFile(ROOT .. "/" .. ADDONS.SPENT_ITEM_NAMES), ADDONS.spentItemNames(mainItems), "its ItemName.json equals the rendered names")
        local spent = ADDONS.readItemFields(readFile(ROOT .. "/" .. ADDONS.SPENT_ITEMS))
        local art = ENGINE.art
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local fields, original = spent[calibre.spentCase], clean[calibre.case]
            check(fields ~= nil, calibre.spentCase .. " is defined by the add-on")
            if fields then
                for _, key in ipairs(S.ITEM_FIELDS) do
                    eq(fields[key], original[key], calibre.spentCase .. ": " .. key .. " is its unused case's")
                end
                check(string.sub(fields.DisplayName, 1, 6) == "Spent ", calibre.spentCase .. " is called Spent ...")
                check(fields.DisplayName ~= original.DisplayName, calibre.spentCase .. " is not called what the unused case is")
                eq(art.icons[fields.Icon], true, calibre.spentCase .. ": its icon is one a vanilla item uses")
                eq(art.models[fields.WorldStaticModel], true, calibre.spentCase .. ": its world model is one vanilla defines")
                -- Lighter than, or as heavy as, the round it came from.
                local round = ENGINE.items[calibre.round]
                check(tonumber(fields.Weight) <= round.weight + 1e-9, calibre.spentCase .. " weighs no more than the round it was (" .. fields.Weight .. " against " .. round.weight .. ")")
            end
        end

        -- Recipes: generated from the "spent" source; a quarter back, no XP.
        header, body = T.RENDER.splitHeader(readFile(ROOT .. "/" .. ADDONS.SPENT_SCRIPT))
        check(string.find(header, "GENERATED", 1, true) ~= nil, "the recipe script says it is generated")
        eq(body, ADDONS.spentScriptBody(T.RENDER), "AC_SpentCaseRecipes.txt equals the rendered model (run tests/write_recipes.lua)")
        eq(readFile(ROOT .. "/" .. ADDONS.SPENT_NAMES), ADDONS.spentNames(), "its Recipes.json equals the rendered names")
        local source = AC_Recycling.getSpentSource()
        local clean = AC_Recycling.getSources()[1]
        eq(AC_Recycling.getRecovery(source), 0.25, "spent brass returns a quarter")
        eq(AC_Recycling.getRecovery(clean), 0.5, "unused components return a half")
        check(AC_Recycling.getRecovery(source) < AC_Recycling.getRecovery(clean), "spent brass recovers less than unused components")
        local both = { clean, source }
        eq(#AC_Recycling.validate(AC_Recycling.buildRecipes(both), both), 0, "clean and spent together are sound: " .. table.concat(AC_Recycling.validate(AC_Recycling.buildRecipes(both), both), "; "))
        eq(#spentRecipes, #AC_Recycling.buildGroups(source), "one spent scrapping recipe per brass size")
        local names = ADDONS.readNames(readFile(ROOT .. "/" .. ADDONS.SPENT_NAMES))
        local mainNames = ADDONS.readNames(readFile(T.TRANSLATE .. "Recipes.json"))
        local takenNames = {}
        for _, value in pairs(mainNames) do takenNames[value] = true end
        local covered = {}
        for _, recipe in ipairs(spentRecipes) do
            local what = recipe.id
            eq(recipe.recyclingSource, "spent", what .. " belongs to the spent source")
            eq(recipe.xp, 0, what .. " awards no XP")
            eq(recipe.loss, true, what .. " is marked as lossy")
            check(mainNames[recipe.id] == nil, what .. " is not a recipe of the main mod")
            check(names[recipe.id] ~= nil and string.find(names[recipe.id], "Spent", 1, true) ~= nil, what .. " has a name that says Spent")
            check(string.find(names[recipe.id], "%(%d+%)$") == nil, what .. " has a real name, not the fallback")
            check(not takenNames[names[recipe.id]], what .. " has a name no main recipe has")
            local brassIn, scrapOut = 0, 0
            for _, input in ipairs(recipe.inputs) do
                if not input.keep then
                    for _, id in ipairs(input.items) do
                        check(seen[id], what .. " takes only spent cases (" .. id .. ")")
                        covered[id] = true
                    end
                    brassIn = input.count * AC_Recycling.getSpentScrappable()[input.items[1]]
                end
            end
            for _, output in ipairs(recipe.outputs) do
                eq(output.item, "Base.BrassScrap", what .. " hands back vanilla brass scrap")
                scrapOut = scrapOut + output.count * AC_Calibres.CONFIG.scrapUnits
            end
            eq(scrapOut * 4, brassIn, what .. ": exactly a quarter of the brass comes back (" .. scrapOut .. " of " .. brassIn .. ")")
        end
        for id in pairs(seen) do check(covered[id], id .. " can be scrapped") end
        eq(AC_Recycling.getSpentRecipeName({ id = "AmmoMaking_ScrapSpentBrass99" }), "Scrap Spent Brass (99)", "a size nobody named still gets a name")

        -- Off: one source, no spent recipe in the list, nothing hooked.
        eq(AC_Features.isEnabled("spentCases"), false, "the feature is off without its add-on")
        eq(#AC_Recycling.getSources(), 1, "off: the spent source is not in the list")
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            check(recipe.recyclingSource ~= "spent", "off: " .. recipe.id .. " is not a spent recipe")
        end
        for key in pairs(AC_Materials) do
            check(type(key) ~= "string" or string.find(key, "onScrapSpentBrass", 1, true) == nil, "off: no spent callback is defined (" .. tostring(key) .. ")")
        end
    end

    section("Spent cases: nothing is hooked unless the feature is on")
    do
        local installed = start(false)
        eq(installed, nil, "off: installIfEnabled does nothing")
        eq(AC_SpentCases.installed, nil, "off: nothing is recorded as installed")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 1, "off: the only listener on the shot is vanilla's own")
        local rackEject, reloadEject = ISRackFirearm.ejectSpentRounds, ISReloadWeaponAction.ejectSpentRounds
        Events.OnGameStart.fire()
        check(ISRackFirearm.ejectSpentRounds == rackEject and ISReloadWeaponAction.ejectSpentRounds == reloadEject, "off: game start leaves vanilla's functions as they are")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 1, "off: and adds no listener")

        -- A whole magazine fired: no case anywhere.
        local square = MOCK.newSquare(10, 10, 0, T.GRASS)
        local player = MODEL.newShooter(MOCK, square)
        local gun = MODEL.newFirearm(MOCK, "revolver")
        MODEL.giveRounds(MOCK, player, MODEL.FIREARMS.revolver.ammo, 6)
        MODEL.reload(player, gun)
        for _ = 1, 6 do MODEL.fire(player, gun) end
        MODEL.rack(player, gun)
        eq(#square.worldItems + spentItemCount(player.inventory.items), 0, "off: firing leaves nothing")

        -- On a multiplayer client or server, and beside a casing mod, the
        -- add-on being ticked changes nothing.
        for _, case in ipairs({ { "client", "a multiplayer client" }, { "server", "a server" } }) do
            MOCK.activeMods = { "AmmoMaking", "AmmoMakingSpentCases" }
            T.reloadMod()
            MODEL.install(MOCK)
            MOCK[case[1]] = true
            eq(AC_SpentCases.installIfEnabled(), nil, "on " .. case[2] .. " nothing is installed")
            eq(#Events.OnWeaponSwingHitPoint.handlers, 1, "and no listener is added")
            MOCK[case[1]] = false
        end
        MOCK.activeMods = { "AmmoMaking", "AmmoMakingSpentCases", "HBVCEFb42" }
        T.reloadMod()
        MODEL.install(MOCK)
        eq(AC_SpentCases.installIfEnabled(), nil, "beside a mod that already leaves casings nothing is installed")
        finish()
    end

    section("Spent cases: each firearm family leaves its cases where vanilla says they leave (modelled vanilla actions)")
    do
        local installed = start(true)
        check(installed ~= nil and installed.shot and installed.rack and installed.reload, "on: the shot listener and both eject wrappers are installed")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 2, "one listener beside vanilla's")
        eq(AC_SpentCases.install(), installed, "installing again does nothing")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 2, "and adds no second listener")
        AC_SpentCases.CONFIG.recoveryPercent = 100

        local S = AC_SpentCases
        local function setup(family, rounds)
            local square = MOCK.newSquare(10, 10, 0, T.GRASS)
            local player = MODEL.newShooter(MOCK, square)
            local gun = MODEL.newFirearm(MOCK, family)
            local spec = MODEL.FIREARMS[family]
            MODEL.giveRounds(MOCK, player, spec.ammo, rounds)
            return square, player, gun, spec, S.getSpentCaseForRound(spec.ammo)
        end
        local function load(player, gun, spec, rounds)
            if spec.magazine then
                local magazine = MODEL.newMagazine(MOCK, spec.magazine, spec.ammo, spec.maxAmmo, 0)
                player.inventory:addItem(magazine)
                MODEL.loadMagazine(player, magazine, rounds)
                MODEL.insertMagazine(player, gun, magazine)
            else
                MODEL.reload(player, gun)
            end
        end

        -- Which family ejects when: the two script flags decide.
        local atShot = { pistol = true, assaultRifle = true, doubleBarrel = true }
        for _, family in ipairs(MODEL.FAMILIES) do
            eq(S.ejectsAtShot(MODEL.newFirearm(MOCK, family)), atShot[family] == true, family .. (atShot[family] and " throws its case clear at the shot" or " keeps its case until it is opened or racked"))
        end

        for _, family in ipairs(MODEL.FAMILIES) do
            local spec = MODEL.FIREARMS[family]
            local rounds = spec.maxAmmo
            local square, player, gun, _, spentType = setup(family, rounds)
            check(spentType ~= nil, family .. ": its calibre has a spent case")
            load(player, gun, spec, rounds)
            local loaded = MODEL.liveRounds(gun)
            check(loaded >= 1, family .. " is loaded (" .. loaded .. ")")
            eq(#square.worldItems, 0, family .. ": loading leaves no case")

            -- Fire everything. After each shot the cases on the ground are
            -- exactly the rounds whose case has left the gun.
            local fired = 0
            for _ = 1, loaded + 2 do
                if MODEL.fire(player, gun) then
                    fired = fired + 1
                    local held = S.countHeld(gun)
                    eq(spentItemCount(square.worldItems, spentType), fired - held, family .. ": after shot " .. fired .. " the ground holds the cases that have left the gun")
                end
            end
            eq(fired, loaded, family .. ": every loaded round fired, and the dry fires fired nothing")
            if family == "revolver" then
                eq(spentItemCount(square.worldItems), 0, "revolver: nothing on the ground while the cylinder is closed")
                eq(gun:getSpentRoundCount(), fired, "revolver: the cylinder holds the fired cases")
                -- Opening it to reload drops them all, once.
                MODEL.giveRounds(MOCK, player, spec.ammo, 2)
                MODEL.reload(player, gun)
                eq(spentItemCount(square.worldItems, spentType), fired, "revolver: opening the cylinder drops every case")
                MODEL.rack(player, gun)
                MODEL.reload(player, gun)
                eq(spentItemCount(square.worldItems, spentType), fired, "revolver: and not a second time")
            else
                eq(spentItemCount(square.worldItems, spentType), fired, family .. ": one case per round fired, no more")
            end
            eq(#square.worldItems, spentItemCount(square.worldItems, spentType), family .. ": nothing but its own calibre's spent case is on the ground")
            eq(spentItemCount(player.inventory.items), 0, family .. ": none went to the inventory")
            for _, calibre in ipairs(AC_Calibres.LIST) do
                if calibre.round == spec.ammo then
                    eq(spentItemCount(square.worldItems, calibre.case), 0, family .. ": what is left is not a usable case")
                end
            end
        end

        -- Racking a live round out is an unload, not a shot: no case.
        for _, family in ipairs({ "pistol", "pumpShotgun", "boltRifle" }) do
            local spec = MODEL.FIREARMS[family]
            local square, player, gun = setup(family, 3)
            load(player, gun, spec, 3)
            local before = MODEL.liveRounds(gun)
            MODEL.rack(player, gun)
            eq(MODEL.liveRounds(gun), before - 1, family .. ": racking hands a live round back")
            eq(#square.worldItems, 0, family .. ": and leaves no case")
        end
        -- Unloading a revolver that has fired nothing: no case either.
        do
            local square, player, gun, spec = setup("revolver", 6)
            load(player, gun, spec, 6)
            MODEL.unloadFirearm(player, gun)
            MODEL.rack(player, gun)
            eq(#square.worldItems, 0, "an unfired revolver unloaded leaves no case")
        end

        -- Nothing for what is not a shot of a known calibre.
        do
            local square, player, gun, spec = setup("pistol", 5)
            load(player, gun, spec, 5)
            -- Unlimited ammunition in debug: vanilla consumes nothing.
            MOCK.debug, player.unlimitedAmmo = true, true
            MODEL.fire(player, gun)
            eq(#square.worldItems, 0, "unlimited ammunition in debug leaves no case")
            MOCK.debug, player.unlimitedAmmo = false, false
            -- A melee weapon swung.
            local club = MOCK.newItem("Base.BaseballBat")
            function club:isRanged() return false end
            Events.OnWeaponSwingHitPoint.fire(player, club)
            eq(#square.worldItems, 0, "a melee swing leaves no case")
            -- A firearm of a calibre the mod does not make.
            local odd = MODEL.newFirearm(MOCK, "pistol")
            odd.ammoKey = "Base.CapGunCap"
            odd.roundChambered = true
            eq(S.getSpentCaseFor(odd), nil, "a calibre the mod does not make has no spent case")
            eq(S.onShot(player, odd), 0, "and its shot leaves nothing")
            eq(S.getSpentCaseFor(nil), nil, "no weapon, no case")
            eq(S.onShot(player, nil), 0, "no weapon, nothing left")
        end

        -- The wrapper is transparent: vanilla's function runs once, with the
        -- action it was called on, and its result is handed on.
        do
            local calls, received = 0, nil
            local wrapped = S.wrapEject(function(self, extra)
                calls = calls + 1
                received = self
                return "vanilla result", extra
            end)
            local square, player, gun = setup("pumpShotgun", 0)
            gun.spentChambered = true
            local action = { gun = gun, character = player }
            local result = wrapped(action, "argument")
            eq(calls, 1, "the wrapped function runs exactly once")
            eq(received, action, "on the action it was called for")
            eq(result, "vanilla result", "and its result is handed on")
            eq(spentItemCount(square.worldItems), 1, "the case is left after it")
            -- A failure of the mod's part never reaches vanilla.
            local bad = MOCK.newSquare(11, 11, 0, T.GRASS, { spawnError = "no room" })
            local unlucky = MODEL.newShooter(MOCK, bad)
            local second = MODEL.newFirearm(MOCK, "pumpShotgun")
            second.spentChambered = true
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            local ok = pcall(wrapped, { gun = second, character = unlucky }, "argument")
            local ok2 = pcall(wrapped, { gun = second, character = unlucky }, "argument")
            MOCK.capturePrint(false)
            check(ok and ok2, "a square that refuses the item does not break the reload")
            eq(calls, 3, "vanilla's function still ran")
            check(MOCK.printLogContains("spent cases: could not leave spent cases"), "the failure is logged")
            local warnings = 0
            for _, line in ipairs(MOCK.printLog or {}) do
                if string.find(line, "could not leave spent cases", 1, true) then warnings = warnings + 1 end
            end
            check(warnings <= 1, "once, not per case (" .. warnings .. ")")
        end

        -- Placement: the inventory instead of the ground.
        do
            S.CONFIG.placement = "inventory"
            local square, player, gun, spec, spentType = setup("pistol", 4)
            load(player, gun, spec, 4)
            for _ = 1, 4 do MODEL.fire(player, gun) end
            eq(#square.worldItems, 0, "placement inventory: nothing on the ground")
            eq(spentItemCount(player.inventory.items, spentType), 4, "placement inventory: the cases are carried")
            S.CONFIG.placement = "ground"
        end

        -- Recovery: none, all, and about half.
        do
            eq(S.roll(0), 0, "no rounds, no cases")
            eq(S.roll(-3), 0, "a negative count leaves nothing")
            eq(S.roll(0 / 0), 0, "a count that is not a number leaves nothing")
            eq(S.roll("six"), 0, "nor does a word")
            eq(S.roll(1e9), S.CONFIG.maximumPerEvent, "a damaged count is capped")
            S.CONFIG.recoveryPercent = 0
            eq(S.roll(6), 0, "at 0 % nothing is found")
            S.CONFIG.recoveryPercent = 100
            eq(S.roll(6), 6, "at 100 % everything is")
            S.CONFIG.recoveryPercent = 50
            local found = 0
            for _ = 1, 4000 do found = found + S.roll(1) end
            check(found > 1800 and found < 2200, "at 50 % about half of 4000 shots leave a case (" .. found .. ")")
            MOCK.randomSequence = { 49, 50 }
            eq(S.roll(1), 1, "a roll just under the percentage finds the case")
            eq(S.roll(1), 0, "a roll at the percentage does not")
            MOCK.randomSequence = nil

            -- The save's sandbox option overrides the default, when it is a
            -- whole percentage; anything else is not a setting.
            eq(S.getRecoveryPercent(), 50, "no sandbox option: the default")
            SandboxVars = { AmmoMaking = { SpentCaseRecovery = 100 } }
            eq(S.getRecoveryPercent(), 100, "the sandbox option is used")
            eq(S.roll(7), 7, "and decides what is found")
            SandboxVars = { AmmoMaking = { SpentCaseRecovery = 0 } }
            eq(S.roll(7), 0, "0 leaves nothing")
            for _, value in ipairs({ 250, -5, 33.3, "all", true, 0 / 0 }) do
                SandboxVars = { AmmoMaking = { SpentCaseRecovery = value } }
                eq(S.getRecoveryPercent(), 50, "the option value " .. tostring(value) .. " is ignored")
            end
            SandboxVars = { AmmoMaking = "broken" }
            eq(S.getRecoveryPercent(), 50, "a broken option table is ignored")
            SandboxVars = {}
            -- The option the add-on ships is that option, with the default
            -- of CONFIG and the whole range.
            local options = readFile(ADDON .. "42/media/sandbox-options.txt")
            check(string.find(options, "^VERSION = 1,") ~= nil and string.find(options, "/*", 1, true) == nil, "the add-on's sandbox file has the version line and no comment")
            local body = string.match(options, "option%s+AmmoMaking%." .. S.CONFIG.sandboxOption .. "%s*(%b{})")
            check(body ~= nil, "it offers " .. S.CONFIG.sandboxOption)
            eq(string.match(body or "", "type%s*=%s*(%a+)"), "integer", "as a whole number")
            eq(tonumber(string.match(body or "", "default%s*=%s*(%d+)")), S.CONFIG.recoveryPercent, "whose default is the mod's")
            eq(tonumber(string.match(body or "", "min%s*=%s*(%d+)")), 0, "from 0")
            eq(tonumber(string.match(body or "", "max%s*=%s*(%d+)")), 100, "to 100")
            local texts = ADDONS.readNames(readFile(ADDON .. "common/media/lua/shared/Translate/EN/Sandbox.json"))
            local translation = string.match(body or "", "translation%s*=%s*([%w_]+)")
            check(texts["Sandbox_" .. tostring(translation)] ~= nil and texts["Sandbox_" .. tostring(translation) .. "_tooltip"] ~= nil, "with a label and a tooltip")
            check(string.find(readFile(ROOT .. "/mod/AmmoMaking/42/media/sandbox-options.txt"), S.CONFIG.sandboxOption, 1, true) == nil, "the main mod does not offer it: without the add-on it would set nothing")
        end

        -- validate() refuses a configuration that would hand out brass.
        do
            local function problems(change)
                local saved = {}
                for key, value in pairs(S.CONFIG) do saved[key] = value end
                change(S.CONFIG)
                local text = table.concat(S.validate(), "; ")
                for key, value in pairs(saved) do S.CONFIG[key] = value end
                return text
            end
            check(string.find(problems(function(c) c.recoveryPercent = 150 end), "recoveryPercent", 1, true) ~= nil, "more than every case is refused")
            check(string.find(problems(function(c) c.recoveryPercent = -1 end), "recoveryPercent", 1, true) ~= nil, "a negative share is refused")
            check(string.find(problems(function(c) c.recoveryPercent = 33.3 end), "recoveryPercent", 1, true) ~= nil, "a fractional percentage is refused")
            check(string.find(problems(function(c) c.placement = "pocket" end), "placement", 1, true) ~= nil, "an unknown placement is refused")
            check(string.find(problems(function(c) c.maximumPerEvent = 0 end), "maximumPerEvent", 1, true) ~= nil, "no cap is refused")
            local nine = AC_Calibres.get("9mm")
            local savedSpent = nine.spentCase
            nine.spentCase = nine.case
            check(string.find(table.concat(S.validate(), "; "), "could be loaded again", 1, true) ~= nil, "a calibre that leaves its unused case is refused")
            nine.spentCase = AC_Calibres.get(".308").spentCase
            check(string.find(table.concat(S.validate(), "; "), "two calibres", 1, true) ~= nil, "one spent case for two calibres is refused")
            nine.spentCase = savedSpent
            eq(#S.validate(), 0, "(restored)")
        end

        -- A build without one of the vanilla functions: that part is
        -- skipped and said, the rest installs.
        do
            MOCK.activeMods = { "AmmoMaking", "AmmoMakingSpentCases" }
            T.reloadMod()
            MODEL.install(MOCK)
            ISRackFirearm.ejectSpentRounds = nil
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            local partial = AC_SpentCases.installIfEnabled()
            MOCK.capturePrint(false)
            eq(partial.rack, false, "a missing rack function is not wrapped")
            check(partial.reload and partial.shot, "the reload wrapper and the shot listener still are")
            check(MOCK.printLogContains("ISRackFirearm.ejectSpentRounds is not a function on this build"), "and the log says which part is missing")
        end
        finish()
    end

    section("Spent cases: random play never leaves more cases than rounds fired (modelled vanilla actions)")
    do
        start(true)
        local S = AC_SpentCases
        S.CONFIG.recoveryPercent = 100
        local totalShots, totalCases = 0, 0
        for _, seed in ipairs({ 3, 20261003, 77, 4242 }) do
            local state = seed
            local function random(n)
                state = MOCK.nextRandom(state)
                return math.floor(state / 65536) % n
            end
            for _, family in ipairs(MODEL.FAMILIES) do
                local spec = MODEL.FIREARMS[family]
                local square = MOCK.newSquare(20, 20, 0, T.GRASS)
                local player = MODEL.newShooter(MOCK, square)
                local gun = MODEL.newFirearm(MOCK, family)
                local spentType = S.getSpentCaseForRound(spec.ammo)
                local magazines = {}
                if spec.magazine then
                    for index = 1, 2 do
                        magazines[index] = player.inventory:addItem(MODEL.newMagazine(MOCK, spec.magazine, spec.ammo, spec.maxAmmo, 0))
                    end
                end
                MODEL.giveRounds(MOCK, player, spec.ammo, 60)
                local fired, violations = 0, {}
                for step = 1, 400 do
                    local action = random(10)
                    if action <= 4 then
                        if MODEL.fire(player, gun) then fired = fired + 1 end
                    elseif action == 5 then
                        MODEL.rack(player, gun)
                    elseif action == 6 then
                        if spec.magazine then
                            local loose = nil
                            for _, item in ipairs(player.inventory.items) do
                                if item.isMagazine then loose = item end
                            end
                            if loose then MODEL.loadMagazine(player, loose, 1 + random(spec.maxAmmo)) end
                        else
                            MODEL.reload(player, gun)
                        end
                    elseif action == 7 then
                        if spec.magazine then
                            if gun:isContainsClip() then
                                MODEL.ejectMagazine(player, gun)
                            else
                                for _, item in ipairs(player.inventory.items) do
                                    if item.isMagazine then MODEL.insertMagazine(player, gun, item) break end
                                end
                            end
                        else
                            MODEL.unloadFirearm(player, gun, 1 + random(3))
                        end
                    elseif action == 8 then
                        -- A save and load: vanilla does not keep the spent state.
                        gun.spentCount, gun.spentChambered = 0, false
                    else
                        MODEL.giveRounds(MOCK, player, spec.ammo, 1 + random(4))
                    end
                    local cases = spentItemCount(square.worldItems, spentType)
                    if cases > fired and #violations < 3 then
                        table.insert(violations, family .. " step " .. step .. ": " .. cases .. " cases for " .. fired .. " shots")
                    end
                    if #square.worldItems ~= cases and #violations < 3 then
                        table.insert(violations, family .. " step " .. step .. ": something other than its spent case was left")
                    end
                end
                eq(#violations, 0, "seed " .. seed .. " " .. family .. ": never more cases than shots: " .. table.concat(violations, "; "))
                local cases = spentItemCount(square.worldItems, spentType)
                check(fired > 20, "seed " .. seed .. " " .. family .. ": the run fired (" .. fired .. ")")
                if not spec.manual and not spec.rackAfterShoot then
                    eq(cases, fired, "seed " .. seed .. " " .. family .. ": exactly one case per shot")
                else
                    check(cases <= fired and cases >= fired / 2, "seed " .. seed .. " " .. family .. ": cases only lost to a save or still in the gun (" .. cases .. " of " .. fired .. ")")
                end
                totalShots, totalCases = totalShots + fired, totalCases + cases
            end
        end
        print(string.format("  Spent cases: %d shots over 7 firearm families and 4 seeds left %d cases, never more than fired", totalShots, totalCases))
        finish()
    end

    section("Spent cases: the brass economy stays lossy, and factory ammunition is no brass mine")
    do
        start(true)
        local S = AC_SpentCases
        local C = AC_Calibres.CONFIG
        local perIngot = AC_Materials.CONFIG.unitsPerIngot

        -- On: the spent source and its recipes are in the lists, with
        -- material declarations, callbacks and no XP.
        eq(#AC_Recycling.getSources(), 2, "on: clean and spent")
        eq(#AC_Recycling.validate(), 0, "on: recycling is sound: " .. table.concat(AC_Recycling.validate(), "; "))
        local spentRecipes = 0
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.recyclingSource == "spent" then
                spentRecipes = spentRecipes + 1
                eq(type(AC_Materials[recipe.callback]), "function", recipe.id .. " has its callback")
                eq(AC_Materials.getRecipeXP(recipe), 0, recipe.id .. " awards no XP")
                local ok, reason = AC_Materials.checkConservation(recipe)
                check(ok, recipe.id .. " conserves metal: " .. tostring(reason))
                local consumed, created = AC_Materials.getRecipeUnits(recipe)
                eq(created.brass * 4, consumed.brass, recipe.id .. " hands back a quarter of the brass")
                local player = MOCK.newPlayer()
                MOCK.capturePrint(true)
                local granted = AC_Materials[recipe.callback]({}, player)
                MOCK.capturePrint(false)
                eq(granted, 0, recipe.id .. ": its callback grants nothing")
                eq(#player.xpLog, 0, recipe.id .. ": and never touches the XP")
            end
        end
        eq(spentRecipes, #AC_Recycling.buildGroups(AC_Recycling.getSpentSource()), "on: one spent recipe per brass size is in the list")
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local entry = AC_Materials.UNITS[calibre.spentCase]
            check(entry ~= nil and entry.metal == "brass", calibre.spentCase .. " is declared as brass")
            eq(entry and entry.units, AC_Materials.UNITS[calibre.case].units, calibre.spentCase .. " holds the brass of the case it was, and no more")
            -- Less brass than the round's (the primer cup is gone).
            check(entry.units < AC_Materials.UNITS[calibre.round].contents.brass, calibre.spentCase .. " holds less brass than the round did")
        end

        -- What a fired round is worth in brass, at the shipped settings:
        -- half are found, a quarter of those comes back. One part in eight.
        eq(S.CONFIG.recoveryPercent, 50, "half of the fired cases are found")
        local share = S.CONFIG.recoveryPercent / 100 * AC_Recycling.getRecovery(AC_Recycling.getSpentSource())
        eq(share, 0.125, "one eighth of a fired case's brass comes back")
        check(share < AC_Recycling.getRecovery(AC_Recycling.getSources()[1]), "far less than unused components return")
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local caseUnits = C.cupUnits * calibre.cupsPerCase
            local back = 100 * caseUnits * share / perIngot
            -- A hundred looted rounds fired, in ingots; an ore is an ingot.
            check(back < 2, calibre.id .. ": a hundred looted rounds fired return under two ingots of brass (" .. back .. ")")
            -- Against making them: the brass alone of a hundred new rounds.
            local needed = 100 * (caseUnits + AC_Calibres.getPrimer(calibre.primerFamily).brassUnits) / perIngot
            check(back < needed / 6, calibre.id .. ": under a sixth of what a hundred new rounds need in brass (" .. back .. " of " .. needed .. ")")
        end

        -- The long cycle, at the BEST case for the player (every case
        -- found): load, fire, scrap, recast, forge, punch, form, load ...
        -- Brass shrinks every time round and the rounds ever made from a
        -- stock are bounded; nothing grows.
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local group
            for _, candidate in ipairs(AC_Recycling.buildGroups(AC_Recycling.getSpentSource())) do
                for _, id in ipairs(candidate.items) do
                    if id == calibre.spentCase then group = candidate end
                end
            end
            check(group ~= nil, calibre.id .. ": its spent case has a scrapping recipe")
            local cases, rounds, cycles, scrap = 4000, 0, 0, 0
            local first = cases
            while cases > 0 and cycles < 50 do
                rounds = rounds + cases
                local spent = cases
                -- Whole batches only; the remainder waits and is lost here.
                scrap = scrap + math.floor(spent / group.count) * group.scrap
                local ingots = math.floor(scrap / AC_Recycling.CONFIG.scrapPerIngot)
                scrap = scrap - ingots * AC_Recycling.CONFIG.scrapPerIngot
                local cups = ingots * (perIngot / C.sheetUnits) * (C.sheetUnits / C.cupUnits)
                local nextCases = math.floor(cups / calibre.cupsPerCase)
                check(nextCases < cases, calibre.id .. ": cycle " .. cycles + 1 .. " ends with fewer cases than it began (" .. nextCases .. " of " .. cases .. ")")
                cases = nextCases
                cycles = cycles + 1
            end
            eq(cases, 0, calibre.id .. ": the stock runs out")
            check(rounds <= first / (1 - 0.25) + 1, calibre.id .. ": " .. first .. " cases never make more than " .. math.floor(first / 0.75) .. " rounds in all (" .. rounds .. ")")
        end

        -- The debug tree offers ten spent cases of each calibre and a
        -- hammer, enough for every spent scrapping recipe.
        MOCK.debug = true
        local debugPlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, T.GRASS) })
        local ammunition = T.fillWorldMenu(debugPlayer, debugPlayer.square):find("Ammo Making Debug").submenu:find("Ammunition")
        local entry = ammunition.submenu:find("Spawn Spent Cases Kit")
        check(entry ~= nil, "on: the debug tree offers the spent cases kit")
        MOCK.capturePrint(true)
        AC_GeologyDebug.spawnSpentCasesKit(debugPlayer)
        MOCK.capturePrint(false)
        local mirror = { ["base:hammer"] = debugPlayer.inventory:count("Base.BallPeenHammer") }
        eq(mirror["base:hammer"], 1, "the kit holds a hammer")
        for _, fullType in ipairs(S.getItems()) do
            eq(debugPlayer.inventory:count(fullType), 10, "the kit holds ten " .. fullType)
            mirror[fullType] = 10
        end
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.recyclingSource == "spent" then
                check(T.mirrorCraft(mirror, recipe), "the kit is enough for " .. recipe.id)
            end
        end
        check((mirror["Base.BrassScrap"] or 0) >= 3, "and scrapping it gives brass scrap (" .. tostring(mirror["Base.BrassScrap"]) .. ")")
        MOCK.debug = false

        -- The game-start check reports the feature and its parts.
        local ids = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
        MOCK.resetCraftRecipes(ids)
        AC_Materials.applySkillRequirements()
        local function labels(results)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            return found
        end
        MOCK.capturePrint(true)
        local found = labels((AC_Compat.run(false)))
        eq(found["feature Spent Cases: ON (on)"], "OK", "the check reports spent cases as on")
        eq(found["spent case items (" .. #AC_Calibres.LIST .. ")"], "OK", "finds every spent item")
        for _, part in ipairs({ "shot", "rack", "reload" }) do
            eq(found["spent case hook: " .. part], "OK", "and the " .. part .. " hook")
        end
        MOCK.knownScriptItems[AC_Calibres.get("9mm").spentCase] = nil
        found = labels((AC_Compat.run(false)))
        eq(found["spent case items missing: " .. AC_Calibres.get("9mm").spentCase], "WARNING", "a spent item the add-on did not bring is a WARNING")
        MOCK.capturePrint(false)
        finish()

        -- Off again: nothing of it is probed.
        local ids2 = {}
        for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids2, recipe.id) end
        MOCK.resetCraftRecipes(ids2)
        AC_Materials.applySkillRequirements()
        MOCK.capturePrint(true)
        found = labels((AC_Compat.run(false)))
        MOCK.capturePrint(false)
        eq(found["feature Spent Cases: off (off)"], "OK", "off: the check says so")
        MOCK.debug = true
        local offPlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, T.GRASS) })
        local offAmmunition = T.fillWorldMenu(offPlayer, offPlayer.square):find("Ammo Making Debug").submenu:find("Ammunition")
        eq(offAmmunition.submenu:find("Spawn Spent Cases Kit"), nil, "off: the debug tree has no spent cases kit")
        MOCK.debug = false
        for label in pairs(found) do
            check(string.find(label, "spent case", 1, true) == nil, "off: nothing of the spent cases is probed (" .. label .. ")")
        end
    end
end
