-- Ammo Making - offline tests: multiplayer server authority (AC_Authority).
--
-- Loaded by tests/run_tests.lua. Three kinds of check, kept apart:
--
--   * single player is unchanged. tests/sp_reference/ holds the files whose
--     single-player code the feature touched, byte for byte as they were in
--     commit eaa7a3e, the last state seen working in game (geology,
--     sampling, assays, analyzer, mining). One scenario is played through
--     the menus and timed actions twice, once with those frozen files and
--     once with the current ones, with the feature off and on; every
--     message, item, ModData value, XP grant and console line must be the
--     same, and nothing may touch the network.
--   * a client asks and the server performs (simulated: one Lua state,
--     MOCK.client / MOCK.server switched, requests and answers delivered by
--     firing OnClientCommand / OnServerCommand by hand, timed actions rebuilt
--     from their fields as the engine's NetTimedAction does).
--   * requests a client should never send are refused: wrong distance, no
--     tool, items that are not the player's, made-up tiles and metals,
--     malformed values, floods.
--
-- Mocked engine throughout. Nothing here shows that the engine delivers a
-- request or an answer, or that a server and a client agree: that needs a
-- dedicated server (docs/INGAME_VALIDATION.md, After the session).

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK
    local readFile, ROOT, LUA = T.readFile, T.ROOT, T.LUA

    local DEPOSITS = "AmmoMakingDeposits"

    local function sides(side)
        MOCK.client = side == "client"
        MOCK.server = side == "server"
    end

    local function authority(on)
        SandboxVars = { AmmoMaking = { ServerAuthority = on } }
    end

    -- Parameter names of a constructor, read from its source.
    local function parameters(source, class)
        local list = string.match(source, "function " .. class .. ":new%(([^)]*)%)")
        local names = {}
        for name in string.gmatch(list or "", "[%a_][%w_]*") do table.insert(names, name) end
        return names
    end

    -- What NetTimedAction does on the server: Type.new(Type, fields named like
    -- new()'s parameters...), then complete() when the duration is over.
    local PARAMETERS = {}
    for _, entry in ipairs({
        { "AC_MineOreAction", "shared/AC_MineOreAction" },
        { "AC_DigGeologicalSampleAction", "shared/AC_DigGeologicalSampleAction" },
        { "AC_PickUpAnalyzerAction", "shared/AC_PickUpAnalyzerAction" },
    }) do
        PARAMETERS[entry[1]] = parameters(readFile(LUA .. entry[2] .. ".lua"), entry[1])
    end

    local function onServer(action, replace)
        local class = getmetatable(action)
        local names = PARAMETERS[class.Type]
        local values = {}
        for index, name in ipairs(names) do
            values[index] = action[name]
            if replace and replace[name] ~= nil then values[index] = replace[name] end
        end
        sides("server")
        local rebuilt = class:new(unpack(values, 1, #names))
        local returned = rebuilt:complete()
        sides("client")
        return returned
    end

    local function deliverRequests()
        local queue = MOCK.network.toServer
        MOCK.network.toServer = {}
        sides("server")
        for _, message in ipairs(queue) do
            Events.OnClientCommand.fire(message.module, message.command, message.player, MOCK.persistCopy(message.args))
        end
        sides("client")
        return queue
    end

    local function deliverAnswers()
        local queue = MOCK.network.toClient
        MOCK.network.toClient = {}
        sides("client")
        HaloTextHelper.clear()
        for _, message in ipairs(queue) do
            Events.OnServerCommand.fire(message.module, message.command, MOCK.persistCopy(message.args))
        end
        return queue
    end

    local function later()
        MOCK.timestampMs = MOCK.timestampMs + 5000
    end

    local function findOreTile(metal, minimum, maximum, fromX)
        for x = fromX, fromX + 3000 do
            for y = 300, 340 do
                local reserve = AC_Deposits.getInitialReserve(x, y, metal)
                if reserve >= minimum and reserve <= maximum then return x, y end
            end
        end
        error("no tile with " .. metal .. " reserve " .. minimum .. ".." .. maximum)
    end

    local function networkSilent(label)
        for _, list in ipairs({ "toServer", "toClient", "transmitted", "requested", "added", "removed", "fields", "modData", "xp" }) do
            eq(#MOCK.network[list], 0, label .. ": nothing on the network (" .. list .. ")")
        end
    end

    ------------------------------------------------------------------------
    section("Server authority: one switch, and the engine mechanism it relies on")
    do
        T.reloadMod()
        MOCK.activeMods, MOCK.debug = {}, false
        local F = AC_Features
        local definition = F.get("serverAuthority")
        check(definition ~= nil, "the feature exists")
        eq(definition.stability, F.EXPERIMENTAL, "experimental: nothing of it has run on a server")
        eq(definition.sandbox, "ServerAuthority", "switched by a sandbox option")
        eq(definition.singlePlayerOnly, false, "it is the multiplayer feature itself")

        -- Who decides, in every combination.
        for _, case in ipairs({
            { "sp", false, false, false }, { "sp", true, false, false },
            { "client", false, false, false }, { "client", true, true, false },
            { "server", false, false, false }, { "server", true, false, true },
        }) do
            sides(case[1])
            authority(case[2])
            local label = case[1] .. (case[2] and ", switch on" or ", switch off")
            eq(AC_Authority.canRequest(), case[3], label .. ": a client asks")
            eq(AC_Authority.decides(), case[4], label .. ": the server decides")
        end
        sides("sp")
        authority(true)
        eq(AC_Features.isEnabled("serverAuthority"), true, "(in single player the switch reads on ...)")
        eq(AC_Authority.canRequest() or AC_Authority.decides(), false, "(... and changes nothing)")

        -- The three timed actions are shared files (a dedicated server loads
        -- shared and server Lua, never client), define complete(), and keep
        -- every parameter of new() as a field of that name: those fields are
        -- what the engine sends (JAR NetTimedAction.set).
        for class, names in pairs(PARAMETERS) do
            local source = readFile(LUA .. "shared/" .. class .. ".lua")
            check(io.open(LUA .. "client/" .. class .. ".lua", "r") == nil, class .. " is no longer a client file")
            eq(type(rawget(_G[class], "complete")), "function", class .. " defines complete()")
            check(#names >= 2 and names[1] == "character", class .. ": new() starts with character")
            for _, name in ipairs(names) do
                check(string.find(source, "\n    o%." .. name .. " =\n") ~= nil, class .. ": new() keeps " .. name .. " as a field")
            end
        end
        -- The analyzer's building object travels the same way (JAR
        -- BuildAction.write): its first parameter must not be the field
        -- "player", which holds the player NUMBER for the cursor.
        local placing = parameters(readFile(LUA .. "server/BuildingObjects/AC_LaboratoryAnalyzerObject.lua"), "AC_LaboratoryAnalyzerObject")
        eq(table.concat(placing, ","), "character,sourceItem", "the building object is rebuilt from character and sourceItem")

        -- Nothing is listened to unless the switch is on, and on the right side.
        T.reloadMod()
        for _, side in ipairs({ "sp", "client", "server" }) do
            sides(side)
            authority(false)
            eq(AC_Authority.installServer(), nil, side .. ", switch off: no server listener")
            eq(AC_AuthorityClient.install(), nil, side .. ", switch off: no client listener")
        end
        sides("sp")
        authority(true)
        eq(AC_Authority.installServer(), nil, "single player, switch on: no server listener")
        eq(AC_AuthorityClient.install(), nil, "single player, switch on: no client listener")
        for _, event in ipairs({ "OnClientCommand", "OnServerCommand", "OnReceiveGlobalModData" }) do
            eq(#Events[event].handlers, 0, "nothing listens to " .. event .. " yet")
        end
        MOCK.resetNetwork()
        sides("server")
        eq(AC_Authority.installServer(), true, "server, switch on: installed")
        eq(AC_Authority.installServer(), true, "installing twice ...")
        eq(#Events.OnClientCommand.handlers, 1, "... listens once")
        eq(#Events.OnReceiveGlobalModData.handlers, 0, "the server never takes global ModData from a client")
        sides("client")
        eq(AC_AuthorityClient.install(), true, "client, switch on: installed")
        eq(#Events.OnServerCommand.handlers, 1, "the client listens to answers")
        eq(#Events.OnReceiveGlobalModData.handlers, 1, "and to the depletion store")
        eq(MOCK.network.requested[1], DEPOSITS, "and asks the server for the store once")
        check(MOCK.printLogContains == nil or true, "")
        sides("sp")
        T.reloadMod()
    end

    ------------------------------------------------------------------------
    -- One single-player session through the menus and timed actions: dig,
    -- field and advanced assay, mining to an empty tile, placing the
    -- analyzer, a laboratory assay collected and one cancelled, picking the
    -- analyzer up. Returns everything a player or the save could tell apart.
    local function serial(value, seen)
        local kind = type(value)
        if kind ~= "table" then return tostring(value) end
        if value.fullType then return "<" .. value.fullType .. ">" end
        seen = seen or {}
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do
            if type(value[key]) ~= "function" then table.insert(keys, tostring(key)) end
        end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do
            local item = value[key]
            if item == nil then item = value[tonumber(key)] end
            table.insert(parts, key .. "=" .. serial(item, seen))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    local function inventoryText(container)
        local lines = {}
        for _, item in ipairs(container.items) do
            table.insert(lines, item.fullType .. "/" .. tostring(item.name) .. "/c" .. tostring(item.condition) .. "/" .. serial(item.modData))
        end
        table.sort(lines)
        return table.concat(lines, " | ")
    end

    local function playSinglePlayer(switch)
        sides("sp")
        authority(switch)
        MOCK.activeMods, MOCK.debug = {}, false
        MOCK.clearModData()
        MOCK.resetNetwork()
        MOCK.seedRandom(4242)
        MOCK.walkAdjResult = true
        MOCK.worldHours = 1000
        HaloTextHelper.clear()
        ISTimedActionQueue.clear()
        AC_GeologyAssayUI.opened = 0
        AC_WorldData.resetCache()
        MOCK.capturePrint(true)
        MOCK.clearPrintLog()
        local trace = {}
        local completed = {}

        local x, y = findOreTile("copper", 2, 3, 1700)
        local square = MOCK.registerSquare(MOCK.newSquare(x, y, 0, T.GRASS))
        local player = MOCK.newPlayer({ square = square, x = x, y = y })
        MOCK.players = { player }
        local labSquare = MOCK.registerSquare(T.poweredLabSquare(x + 2, y))

        local function step(label)
            local special = {}
            for _, object in ipairs(labSquare.specialObjects) do table.insert(special, serial(object.modData) .. "/" .. tostring(object.name)) end
            table.insert(trace, label
                .. " | halo=" .. tostring(HaloTextHelper.last())
                .. " | xp=" .. player:totalXP()
                .. " | queue=" .. #ISTimedActionQueue.queue
                .. " | ui=" .. AC_GeologyAssayUI.opened
                .. " | inventory=" .. inventoryText(player.inventory)
                .. " | ground=" .. #square.worldItems
                .. " | store=" .. serial(MOCK.modDataRegistry[DEPOSITS])
                .. " | lab=" .. table.concat(special, ";")
                .. " | drag=" .. tostring(MOCK.drag ~= nil))
            for _, line in ipairs(MOCK.printLog) do table.insert(trace, "  console: " .. line) end
            MOCK.clearPrintLog()
        end

        -- The engine runs a finished action's perform(), then, when it is not
        -- a client, its complete() (JAR IsoGameCharacter).
        local function runQueued()
            local queue = ISTimedActionQueue.queue
            ISTimedActionQueue.clear()
            for _, action in ipairs(queue) do
                if action:isValid() then
                    action:start()
                    action:update()
                    action:perform()
                    -- Not traced: the reference has no complete(), and
                    -- its effects show in the next step's state.
                    if action.complete then table.insert(completed, action:complete()) end
                else
                    table.insert(trace, "  not valid")
                end
            end
        end

        local function choose(menu, prefix)
            local option = menu:find(prefix)
            table.insert(trace, "  option " .. prefix .. ": " .. (option == nil and "absent" or (option.notAvailable and "disabled" or "live")))
            if option and option.fn then menu:invoke(option) end
            return option
        end

        -- Dig.
        T.equipShovel(player)
        choose(T.fillWorldMenu(player, square), "Dig Geological Sample")
        runQueued()
        step("dig")
        local dug = player.inventory:getItemsFromFullType(AC_GeologySampling.ITEMS.Sample):get(0)

        -- Assays.
        player.inventory:AddItem(AC_GeologySampling.ITEMS.FieldKit)
        player.inventory:AddItem(AC_GeologySampling.ITEMS.AdvancedFieldKit)
        choose(T.fillInventoryMenu(player, dug), "Analyze with Field Assay Kit")
        step("field assay")
        choose(T.fillInventoryMenu(player, dug), "Re-analyze with Advanced Field Assay Kit")
        step("advanced assay")
        choose(T.fillInventoryMenu(player, dug), "Analyze with Field Assay Kit")
        step("field assay again")

        -- Mining until the tile is empty, and once more.
        local pick = MOCK.newItem("Base.PickAxe")
        player.inventory:addItem(pick)
        player.primary = pick
        player.inventory:addItem(T.makeSample(x, y, 1, "Good", "Good"))
        for round = 1, 4 do
            choose(T.fillWorldMenu(player, square), "Mine Copper Ore")
            runQueued()
            step("mine " .. round)
        end
        -- An assay that promised ore where the ground holds none.
        local ex, ey = findOreTile("copper", 0, 0, x + 3)
        local barren = MOCK.registerSquare(MOCK.newSquare(ex, ey, 0, T.GRASS))
        player.x, player.y, player.square = ex, ey, barren
        player.inventory:addItem(T.makeSample(ex, ey, 1, "Good", "None"))
        choose(T.fillWorldMenu(player, barren), "Mine Copper Ore")
        runQueued()
        step("mine barren ground")

        -- The analyzer: place, start, collect, start, cancel, pick up.
        player.x, player.y, player.square = x + 2, y, labSquare
        local analyzerItem = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
        choose(T.fillInventoryMenu(player, analyzerItem), "Place Laboratory Assay Analyzer")
        local cursor = MOCK.drag and MOCK.drag.object
        if cursor then cursor:create(x + 2, y, 0, false, cursor.sprite) end
        MOCK.drag = nil
        step("place")
        local analyzer = labSquare.specialObjects[1]
        if analyzer then
            choose(T.fillAnalyzerMenu(player, analyzer), "Start Lab Assay")
            step("lab start")
            choose(T.fillAnalyzerMenu(player, analyzer), "Check Laboratory Progress")
            step("lab check")
            MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours + 1
            choose(T.fillAnalyzerMenu(player, analyzer), "Collect Laboratory Sample")
            step("lab collect")
            player.inventory:addItem(T.makeSample(x, y, 1, "Poor", "None"))
            choose(T.fillAnalyzerMenu(player, analyzer), "Start Lab Assay")
            choose(T.fillAnalyzerMenu(player, analyzer), "Cancel Laboratory Assay")
            step("lab cancel")
            choose(T.fillAnalyzerMenu(player, analyzer), "Pick Up Laboratory Assay Analyzer")
            runQueued()
            step("pick up")
        end

        MOCK.capturePrint(false)
        return trace, completed
    end

    local REFERENCE = {
        ["shared/AC_MineOreAction"] = ROOT .. "/tests/sp_reference/AC_MineOreAction.lua",
        ["shared/AC_DigGeologicalSampleAction"] = ROOT .. "/tests/sp_reference/AC_DigGeologicalSampleAction.lua",
        ["shared/AC_PickUpAnalyzerAction"] = ROOT .. "/tests/sp_reference/AC_PickUpAnalyzerAction.lua",
        ["client/AC_GeologySamplingContextMenu"] = ROOT .. "/tests/sp_reference/AC_GeologySamplingContextMenu.lua",
        ["client/AC_MiningContextMenu"] = ROOT .. "/tests/sp_reference/AC_MiningContextMenu.lua",
        ["shared/AC_AmmoMakingSkill"] = ROOT .. "/tests/sp_reference/AC_AmmoMakingSkill.lua",
        ["server/BuildingObjects/AC_LaboratoryAnalyzerObject"] = ROOT .. "/tests/sp_reference/AC_LaboratoryAnalyzerObject.lua",
    }

    local function loadWith(replacements)
        MOCK.resetLuaState()
        MOCK.loadMod(LUA, replacements)
    end

    local function compare(expected, actual, label)
        local first = nil
        for index = 1, math.max(#expected, #actual) do
            if expected[index] ~= actual[index] then first = index break end
        end
        eq(first, nil, label .. (first and (": first difference at line " .. first .. "\n    reference: " .. tostring(expected[first]) .. "\n    now:       " .. tostring(actual[first])) or ""))
    end

    ------------------------------------------------------------------------
    section("Single player is unchanged: the current files replay the frozen reference exactly")
    do
        -- The reference is what was in the game when sampling, assays and
        -- mining were seen working; nothing in it knows about the authority.
        for name, path in pairs(REFERENCE) do
            local handle = io.open(path, "r")
            check(handle ~= nil, "the frozen copy of " .. name .. " is there")
            if handle then
                local source = handle:read("*a")
                handle:close()
                check(string.find(source, "AC_Authority", 1, true) == nil, name .. ": the reference has no server authority in it")
            end
        end

        loadWith(REFERENCE)
        local reference = playSinglePlayer(false)
        local referenceOn = playSinglePlayer(true)
        check(#reference > 40, "the scenario produced a full trace (" .. #reference .. " lines)")
        local joined = table.concat(reference, "\n")
        for _, needle in ipairs({ "Geological sample collected", "Sample analyzed", "Copper ore extracted", "No workable copper ore here",
            "Laboratory assay started", "Laboratory tested sample collected", "Laboratory assay cancelled", "Laboratory Assay Analyzer picked up" }) do
            check(string.find(joined, needle, 1, true) ~= nil, "the scenario reaches: " .. needle)
        end
        compare(reference, referenceOn, "(the reference ignores the switch, as it must)")

        loadWith(nil)
        local current, completed = playSinglePlayer(false)
        networkSilent("single player, switch off")
        local currentOn = playSinglePlayer(true)
        networkSilent("single player, switch on")
        compare(reference, current, "single player, switch off: every message, item, ModData value, XP grant and console line as before")
        compare(reference, currentOn, "single player, switch on: the same")

        -- complete() in single player: called by the engine after perform(),
        -- it returns true and changes nothing.
        eq(#completed, 5, "the engine's complete() was played after each of the five timed actions")
        for index, returned in ipairs(completed) do eq(returned, true, "complete() " .. index .. " returns true") end
        T.reloadMod()
    end

    ------------------------------------------------------------------------
    -- A multiplayer world: switch on, both sides installed.
    local function multiplayerWorld()
        T.reloadMod()
        MOCK.activeMods, MOCK.debug = {}, false
        MOCK.clearModData()
        MOCK.resetNetwork()
        MOCK.walkAdjResult = true
        MOCK.worldHours = 2000
        MOCK.timestampMs = 1000000
        ISTimedActionQueue.clear()
        authority(true)
        sides("server")
        AC_Authority.installServer()
        sides("client")
        AC_AuthorityClient.install()
        MOCK.resetNetwork()
    end

    section("Multiplayer: a client asks, the server checks and performs, the client shows the answer")
    do
        multiplayerWorld()
        local G, L = AC_GeologySampling, AC_LaboratoryAnalyzer
        local x, y = findOreTile("copper", 2, 3, 1900)
        local square = MOCK.registerSquare(MOCK.newSquare(x, y, 0, T.GRASS))
        local alice = MOCK.newPlayer({ square = square, x = x, y = y, onlineID = 7, username = "Alice" })
        MOCK.players = { alice }
        local shovel = T.equipShovel(alice)

        -- Dig: a live option, a timed action the client only plays.
        local menu = T.fillWorldMenu(alice, square)
        local dig = menu:find("Dig Geological Sample")
        check(dig ~= nil and dig.notAvailable ~= true and dig.fn ~= nil, "client: digging is offered")
        menu:invoke(dig)
        local action = ISTimedActionQueue.queue[1]
        ISTimedActionQueue.clear()
        eq(action:isValid(), true, "the dig action is valid on the client")
        action:start()
        action:perform()
        eq(alice.inventory:count(G.ITEMS.Sample), 0, "the client's perform() digs nothing")
        eq(#MOCK.network.toServer, 0, "a timed action is sent by the engine, not as a command")
        eq(onServer(action), true, "the server's complete() runs")
        eq(alice.inventory:count(G.ITEMS.Sample), 1, "the server dug one sample")
        local sample = alice.inventory:getItemsFromFullType(G.ITEMS.Sample):get(0)
        check(MOCK.network.added[1] and MOCK.network.added[1].item == sample and MOCK.network.added[1].server, "the sample is sent to the client's inventory")
        eq(sample.modData.sampleX, x, "with its geology already in its ModData")
        check(MOCK.network.fields[1] and MOCK.network.fields[1].item == shovel, "the shovel's wear is synced")
        local answers = deliverAnswers()
        eq(#answers, 1, "one answer")
        eq(answers[1].args.onlineID, 7, "addressed to the player who asked")
        eq(HaloTextHelper.last(), "Geological sample collected", "the client shows the single-player message")

        -- Field assay: a client command.
        local kit = alice.inventory:AddItem(G.ITEMS.FieldKit)
        local uses = G.getKitUses(kit)
        MOCK.resetNetwork()
        later()
        menu = T.fillInventoryMenu(alice, sample)
        local assay = menu:find("Analyze with Field Assay Kit")
        check(assay ~= nil and assay.notAvailable ~= true, "client: the assay is offered")
        menu:invoke(assay)
        eq(tonumber(sample.modData.assayRank) or 0, 0, "the client assays nothing itself")
        eq(#MOCK.network.toServer, 1, "it sends one request")
        eq(MOCK.network.toServer[1].command, "assay", "named assay")
        eq(MOCK.network.toServer[1].args.sampleId, sample:getID(), "naming the sample by id")
        eq(MOCK.network.toServer[1].args.kitId, kit:getID(), "and the kit")
        deliverRequests()
        eq(sample.modData.assayRank, 1, "the server assayed the sample")
        eq(G.getKitUses(kit), uses - 1, "and took one use of the kit")
        eq(#MOCK.network.xp, 1, "XP went through vanilla's addXp ...")
        check(MOCK.network.xp[1] and MOCK.network.xp[1].server and MOCK.network.xp[1].amount == G.CONFIG.fieldAssayXP, "... on the server, the field assay's amount")
        eq(#MOCK.network.modData, 2, "sample and kit ModData synced")
        deliverAnswers()
        eq(HaloTextHelper.last(), "Sample analyzed", "the client shows the answer")

        -- Mining: the server mines, transmits the store, the client keeps it.
        local pick = MOCK.newItem("Base.PickAxe")
        alice.inventory:addItem(pick)
        alice.primary = pick
        alice.inventory:addItem(T.makeSample(x, y, 1, "Good", "Good"))
        local before = AC_Deposits.getRemaining(x, y, "copper")
        MOCK.resetNetwork()
        later()
        menu = T.fillWorldMenu(alice, square)
        local mine = menu:find("Mine Copper Ore")
        check(mine ~= nil and mine.notAvailable ~= true, "client: mining is offered")
        menu:invoke(mine)
        action = ISTimedActionQueue.queue[1]
        ISTimedActionQueue.clear()
        action:start()
        action:perform()
        eq(AC_Deposits.getRemaining(x, y, "copper"), before, "the client's perform() mines nothing")
        eq(#square.worldItems, 0, "and drops no ore")
        onServer(action)
        eq(AC_Deposits.getRemaining(x, y, "copper"), before - 1, "the server extracted one unit")
        eq(#square.worldItems, 1, "and dropped one ore on the square")
        eq(#MOCK.network.transmitted, 1, "the depletion store is transmitted ...")
        eq(MOCK.network.transmitted[1].key, DEPOSITS, "... under its key")
        eq(MOCK.network.transmitted[1].server, true, "... by the server")
        check(MOCK.network.xp[1] and MOCK.network.xp[1].amount == AC_Mining.CONFIG.xpPerOre, "mining XP through addXp")
        deliverAnswers()
        check(string.find(tostring(HaloTextHelper.last()), "Copper ore extracted", 1, true) == 1, "the client shows the single-player result: " .. tostring(HaloTextHelper.last()))

        -- The client keeps the server's store; nothing else.
        local sent = MOCK.network.transmitted[1].data
        MOCK.clearModData()
        eq(AC_AuthorityClient.onReceiveGlobalModData("OtherKey", sent), false, "another key is ignored")
        eq(AC_AuthorityClient.onReceiveGlobalModData(DEPOSITS, false), false, "a missing table is ignored")
        eq(AC_AuthorityClient.onReceiveGlobalModData(DEPOSITS, "text"), false, "so is anything that is not a table")
        eq(MOCK.modDataRegistry[DEPOSITS], nil, "nothing stored from them")
        Events.OnReceiveGlobalModData.fire(DEPOSITS, MOCK.persistCopy(sent))
        eq(AC_Deposits.getRemaining(x, y, "copper"), before - 1, "with the server's store, the client's menu sees the depletion")

        -- Two players, one unit left: the first gets it, the second is told.
        local lx, ly = findOreTile("zinc", 1, 1, 2300)
        local last = MOCK.registerSquare(MOCK.newSquare(lx, ly, 0, T.GRASS))
        local bob = MOCK.newPlayer({ square = last, x = lx + 1, y = ly, onlineID = 8, username = "Bob" })
        alice.x, alice.y, alice.square = lx, ly, last
        local bobPick = MOCK.newItem("Base.PickAxe")
        bob.inventory:addItem(bobPick)
        bob.primary = bobPick
        alice.inventory:addItem(T.makeSample(lx, ly, 1, "Good", "Good"))
        bob.inventory:addItem(T.makeSample(lx, ly, 1, "Good", "Good"))
        MOCK.players = { alice, bob }
        MOCK.resetNetwork()
        later()
        local aliceMines = AC_MineOreAction:new(alice, last, "zinc", pick)
        local bobMines = AC_MineOreAction:new(bob, last, "zinc", bobPick)
        onServer(aliceMines)
        onServer(bobMines)
        eq(#last.worldItems, 1, "one unit, one ore")
        eq(AC_Deposits.getRemaining(lx, ly, "zinc"), 0, "the tile is empty")
        answers = deliverAnswers()
        eq(answers[1].args.ok, true, "the first request got the ore")
        eq(answers[2].args.ok, false, "the second did not")
        eq(answers[2].args.error, "no_ore", "and was told there is no ore")
        eq(HaloTextHelper.last(), "No workable zinc ore here", "in the single-player words")

        -- The analyzer, placed through vanilla's build action.
        local ax, ay = 2600, 310
        local labSquare = MOCK.registerSquare(T.poweredLabSquare(ax, ay))
        alice.x, alice.y, alice.square = ax, ay, labSquare
        bob.x, bob.y, bob.square = ax + 1, ay, labSquare
        local analyzerItem = alice.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
        MOCK.drag = nil
        menu = T.fillInventoryMenu(alice, analyzerItem)
        local place = menu:find("Place Laboratory Assay Analyzer")
        check(place ~= nil and place.notAvailable ~= true, "client: placing is offered")
        menu:invoke(place)
        local cursor = MOCK.drag and MOCK.drag.object
        check(cursor ~= nil, "the placement cursor starts")
        -- JAR BuildAction: new(fields named like the parameters ...), then
        -- the field "player" set to the IsoPlayer, then create().
        MOCK.resetNetwork()
        sides("server")
        local built = AC_LaboratoryAnalyzerObject:new(cursor.character, cursor.sourceItem)
        built.player = alice
        built.character = alice
        MOCK.capturePrint(true)
        built:create(ax, ay, 0, false, built.sprite)
        MOCK.capturePrint(false)
        sides("client")
        local analyzer = labSquare.specialObjects[1]
        check(L.isPlacedAnalyzerObject(analyzer), "the server placed the analyzer")
        eq(alice.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 0, "and took the item")
        check(MOCK.network.removed[1] and MOCK.network.removed[1].item == analyzerItem, "the item's removal is sent")

        -- Start.
        local labSample = T.makeSample(ax, ay, 1, "Good", "None")
        alice.inventory:addItem(labSample)
        MOCK.resetNetwork()
        later()
        menu = T.fillAnalyzerMenu(alice, analyzer)
        local start = menu:find("Start Lab Assay")
        check(start ~= nil and start.notAvailable ~= true, "client: starting is offered")
        menu:invoke(start)
        eq(analyzer.modData.labAnalyzerState, "idle", "the client starts nothing itself")
        eq(MOCK.network.toServer[1].command, "labStart", "it asks")
        eq(MOCK.network.toServer[1].args.x, ax, "naming the analyzer's square")
        local chosen = alice.inventory:getItemWithIDRecursiv(MOCK.network.toServer[1].args.sampleId)
        check(chosen ~= nil, "and one of the player's samples by id")
        deliverRequests()
        eq(analyzer.modData.labAnalyzerState, "processing", "the server started the assay")
        eq(alice.inventory:contains(chosen), false, "and took that sample")
        check(MOCK.network.removed[1] and MOCK.network.removed[1].item == chosen, "the sample's removal is sent")
        eq(analyzer.transmits, 1, "the analyzer's ModData is transmitted")
        deliverAnswers()
        eq(HaloTextHelper.last(), "Laboratory assay started - " .. L.CONFIG.processingHours .. " hours", "the client shows it")

        -- Collect too early, then in time; a second collect finds it empty.
        later()
        AC_Authority.request(alice, "labCollect", { x = ax, y = ay, z = 0 })
        deliverRequests()
        deliverAnswers()
        eq(HaloTextHelper.last(), "Laboratory assay is still processing", "too early: refused")
        MOCK.worldHours = MOCK.worldHours + L.CONFIG.processingHours + 1
        later()
        MOCK.resetNetwork()
        local aliceSamples, bobSamples = alice.inventory:count(G.ITEMS.Sample), bob.inventory:count(G.ITEMS.Sample)
        menu = T.fillAnalyzerMenu(alice, analyzer)
        menu:invoke(menu:find("Collect Laboratory Sample"))
        AC_Authority.request(bob, "labCollect", { x = ax, y = ay, z = 0 })
        deliverRequests()
        eq(alice.inventory:count(G.ITEMS.Sample), aliceSamples + 1, "the first collector got the sample")
        eq(bob.inventory:count(G.ITEMS.Sample), bobSamples, "the second got nothing")
        local collected = alice.inventory.items[#alice.inventory.items]
        eq(collected.fullType, G.ITEMS.Sample, "the collected sample is the newest item")
        eq(collected.modData.assayRank, 3, "a laboratory result")
        eq(#MOCK.network.xp, 1, "laboratory XP once")
        check(MOCK.network.xp[1].player == alice and MOCK.network.xp[1].amount == L.CONFIG.assayXP, "to the collector")
        answers = deliverAnswers()
        eq(answers[2].args.error, "empty", "the second collector was told the analyzer is empty")
        eq(answers[1].args.xp, L.CONFIG.assayXP, "the first was told the XP")

        -- Cancel returns the sample.
        later()
        AC_Authority.request(alice, "labStart", { x = ax, y = ay, z = 0, sampleId = collected:getID() })
        deliverRequests()
        eq(analyzer.modData.labAnalyzerState, "idle", "a laboratory-tested sample cannot be started again")
        local second = T.makeSample(ax, ay, 1, "Poor", "None")
        alice.inventory:addItem(second)
        later()
        AC_Authority.request(alice, "labStart", { x = ax, y = ay, z = 0, sampleId = second:getID() })
        deliverRequests()
        eq(analyzer.modData.labAnalyzerState, "processing", "a second assay runs")
        later()
        MOCK.resetNetwork()
        menu = T.fillAnalyzerMenu(alice, analyzer)
        local beforeCancel = alice.inventory:count(G.ITEMS.Sample)
        menu:invoke(menu:find("Cancel Laboratory Assay"))
        deliverRequests()
        eq(analyzer.modData.labAnalyzerState, "idle", "cancelled")
        eq(alice.inventory:count(G.ITEMS.Sample), beforeCancel + 1, "the sample came back")
        eq(#MOCK.network.xp, 0, "for no XP")
        deliverAnswers()
        eq(HaloTextHelper.last(), "Laboratory assay cancelled - sample returned", "the client shows it")

        -- Pick it up again: a timed action completed on the server.
        later()
        MOCK.resetNetwork()
        menu = T.fillAnalyzerMenu(alice, analyzer)
        local pickUp = menu:find("Pick Up Laboratory Assay Analyzer")
        check(pickUp ~= nil and pickUp.notAvailable ~= true, "client: picking up is offered")
        menu:invoke(pickUp)
        action = ISTimedActionQueue.queue[1]
        ISTimedActionQueue.clear()
        action:start()
        action:perform()
        eq(#labSquare.specialObjects, 1, "the client's perform() removes nothing")
        onServer(action)
        eq(#labSquare.specialObjects, 0, "the server removed the analyzer")
        eq(alice.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "and gave the item")
        check(MOCK.network.added[1] and MOCK.network.added[1].item.fullType == "AmmoMaking.LaboratoryAssayAnalyzer", "the item is sent")
        deliverAnswers()
        eq(HaloTextHelper.last(), "Laboratory Assay Analyzer picked up", "the client shows it")
        sides("sp")
    end

    ------------------------------------------------------------------------
    section("Multiplayer: requests a client should never send are refused, and change nothing")
    do
        multiplayerWorld()
        local G, L = AC_GeologySampling, AC_LaboratoryAnalyzer
        local x, y = findOreTile("copper", 3, 6, 2700)
        local square = MOCK.registerSquare(MOCK.newSquare(x, y, 0, T.GRASS))
        local alice = MOCK.newPlayer({ square = square, x = x, y = y, onlineID = 7, username = "Alice" })
        local bob = MOCK.newPlayer({ square = square, x = x, y = y, onlineID = 8, username = "Bob" })
        MOCK.players = { alice, bob }
        local pick = MOCK.newItem("Base.PickAxe")
        alice.inventory:addItem(pick)
        alice.primary = pick
        alice.inventory:addItem(T.makeSample(x, y, 1, "Good", "Good"))
        local bobPick = MOCK.newItem("Base.PickAxe")
        bob.inventory:addItem(bobPick)
        bob.primary = bobPick
        local reserve = AC_Deposits.getRemaining(x, y, "copper")

        local function lastAnswer()
            local queue = MOCK.network.toClient
            return queue[#queue] and queue[#queue].args
        end

        local function refusedMine(label, errorCode, replace, setup, undo)
            later()
            if setup then setup() end
            local action = AC_MineOreAction:new(alice, square, "copper", pick)
            onServer(action, replace)
            if undo then undo() end
            local answer = lastAnswer()
            eq(answer and answer.ok, false, "mine, " .. label .. ": refused")
            eq(answer and answer.error, errorCode, "mine, " .. label .. ": " .. errorCode)
            eq(AC_Deposits.getRemaining(x, y, "copper"), reserve, "mine, " .. label .. ": the reserve is untouched")
            eq(#square.worldItems, 0, "mine, " .. label .. ": no ore")
            eq(#MOCK.network.xp, 0, "mine, " .. label .. ": no XP")
        end

        -- Spoofed metal and tile, wrong distance, tools that are not his.
        refusedMine("a metal that does not exist", "invalid_metal", { metal = "gold" })
        refusedMine("a metal spelled another way", "invalid_metal", { metal = "Copper" })
        refusedMine("no metal", "invalid_metal", { metal = false })
        local far = MOCK.newSquare(x + 10, y, 0, T.GRASS)
        refusedMine("a tile ten steps away", "too_far", { square = far })
        refusedMine("a tile one level up", "too_far", { square = MOCK.newSquare(x, y, 1, T.GRASS) })
        refusedMine("a square the server does not have", "no_square", { square = false })
        refusedMine("standing far away", "too_far", nil, function() alice.x = x + 5 end, function() alice.x = x end)
        refusedMine("another player's pickaxe", "no_pickaxe", { pickaxe = bobPick })
        refusedMine("a pickaxe in the bag, not in the hands", "no_pickaxe", nil, function() alice.primary = nil end, function() alice.primary = pick end)
        refusedMine("no pickaxe at all", "no_pickaxe", { pickaxe = false })
        refusedMine("a broken pickaxe", "no_pickaxe", nil, function() pick.condition = 0 end, function() pick.condition = 10 end)
        local prospect = alice.inventory:getItemsFromFullType(G.ITEMS.Sample):get(0)
        refusedMine("without an assayed sample", "no_prospect", nil, function() alice.inventory:Remove(prospect) end, function() alice.inventory:addItem(prospect) end)

        -- Flooding: one extraction per second and player.
        later()
        onServer(AC_MineOreAction:new(alice, square, "copper", pick))
        eq(AC_Deposits.getRemaining(x, y, "copper"), reserve - 1, "an honest extraction goes through")
        onServer(AC_MineOreAction:new(alice, square, "copper", pick))
        eq(lastAnswer().error, "rate_limited", "a second one in the same second is refused")
        eq(AC_Deposits.getRemaining(x, y, "copper"), reserve - 1, "and takes nothing")
        later()
        reserve = AC_Deposits.getRemaining(x, y, "copper")

        -- Digging.
        local function refusedDig(label, errorCode, args, setup, undo)
            later()
            if setup then setup() end
            local count = alice.inventory:count(G.ITEMS.Sample)
            local dig = AC_DigGeologicalSampleAction:new(alice, args.square or square, args.shovel)
            onServer(dig, args.replace)
            if undo then undo() end
            eq(lastAnswer() and lastAnswer().error, errorCode, "dig, " .. label .. ": " .. errorCode)
            eq(alice.inventory:count(G.ITEMS.Sample), count, "dig, " .. label .. ": no sample")
        end
        local shovel = MOCK.newItem("Base.Shovel")
        alice.inventory:addItem(shovel)
        local bobShovel = MOCK.newItem("Base.Shovel")
        bob.inventory:addItem(bobShovel)
        refusedDig("another player's shovel", "no_shovel", { shovel = bobShovel })
        refusedDig("a pickaxe for a shovel", "no_shovel", { shovel = pick })
        refusedDig("a broken shovel", "no_shovel", { shovel = shovel }, function() shovel.condition = 0 end, function() shovel.condition = 10 end)
        refusedDig("ten steps away", "too_far", { shovel = shovel, square = MOCK.newSquare(x, y + 10, 0, T.GRASS) })
        refusedDig("indoors", "invalid_surface", { shovel = shovel, square = MOCK.newSquare(x, y, 0, "floors_interior_tiles_01_0", { room = {} }) })

        -- Assays by command: made-up ids and someone else's kit.
        local sample = T.makeSample(x, y, 0)
        alice.inventory:addItem(sample)
        local kit = alice.inventory:AddItem(G.ITEMS.FieldKit)
        local bobKit = bob.inventory:AddItem(G.ITEMS.AdvancedFieldKit)
        local uses, bobUses = G.getKitUses(kit), G.getKitUses(bobKit)
        local function refusedAssay(label, errorCode, args, who)
            later()
            MOCK.resetNetwork()
            sides("server")
            local answer = AC_Authority.onClientCommand("AmmoMaking", "assay", who or alice, args)
            sides("client")
            eq(answer and answer.error, errorCode, "assay, " .. label .. ": " .. errorCode)
            eq(tonumber(sample.modData.assayRank) or 0, 0, "assay, " .. label .. ": the sample is unchanged")
            eq(G.getKitUses(kit), uses, "assay, " .. label .. ": the kit keeps its uses")
            eq(G.getKitUses(bobKit), bobUses, "assay, " .. label .. ": so does the other player's")
            eq(#MOCK.network.xp, 0, "assay, " .. label .. ": no XP")
        end
        refusedAssay("another player's kit", "invalid_kit", { sampleId = sample:getID(), kitId = bobKit:getID() })
        refusedAssay("a sample of another player", "invalid_sample", { sampleId = sample:getID(), kitId = bobKit:getID() }, bob)
        refusedAssay("a made-up sample id", "invalid_sample", { sampleId = 99999999, kitId = kit:getID() })
        refusedAssay("a sample id as text", "invalid_sample", { sampleId = tostring(sample:getID()), kitId = kit:getID() })
        refusedAssay("a fractional id", "invalid_sample", { sampleId = sample:getID() + 0.5, kitId = kit:getID() })
        refusedAssay("not a number", "invalid_sample", { sampleId = 0 / 0, kitId = kit:getID() })
        refusedAssay("an infinite id", "invalid_sample", { sampleId = math.huge, kitId = kit:getID() })
        refusedAssay("no ids", "invalid_sample", {})
        refusedAssay("the kit named as the sample", "invalid_sample", { sampleId = kit:getID(), kitId = kit:getID() })
        refusedAssay("the sample named as the kit", "invalid_kit", { sampleId = sample:getID(), kitId = sample:getID() })
        later()
        sides("server")
        local malformed = AC_Authority.onClientCommand("AmmoMaking", "assay", alice, "sampleId=1")
        sides("client")
        eq(malformed and malformed.error, "bad_request", "a request whose arguments are not a table is answered bad_request")
        eq(tonumber(sample.modData.assayRank) or 0, 0, "and performs nothing")

        -- Not ours, not known, not on, not a player.
        later()
        MOCK.resetNetwork()
        sides("server")
        eq(AC_Authority.onClientCommand("OtherMod", "assay", alice, { sampleId = sample:getID(), kitId = kit:getID() }), nil, "another mod's module is not ours")
        eq(AC_Authority.onClientCommand("AmmoMaking", "giveOre", alice, {}), nil, "an unknown command is ignored")
        eq(AC_Authority.onClientCommand("AmmoMaking", "assay", nil, { sampleId = sample:getID(), kitId = kit:getID() }), nil, "a request without a player is ignored")
        eq(AC_Authority.onClientCommand("AmmoMaking", "reply", alice, {}), nil, "the answer's own name is not a command")
        authority(false)
        eq(AC_Authority.onClientCommand("AmmoMaking", "assay", alice, { sampleId = sample:getID(), kitId = kit:getID() }), nil, "switch off on the server: not performed")
        local offMine = AC_MineOreAction:new(alice, square, "copper", pick)
        sides("client")
        onServer(offMine)
        eq(lastAnswer() and lastAnswer().error, "multiplayer_unsupported", "switch off: a timed action is answered as refused")
        eq(AC_Deposits.getRemaining(x, y, "copper"), reserve, "and mines nothing")
        authority(true)
        sides("client")
        eq(#MOCK.network.toClient, 1, "only the timed action was answered")
        eq(tonumber(sample.modData.assayRank) or 0, 0, "and the sample is still unassayed")

        -- Flooding an assay: one per second; the rest are dropped unanswered.
        later()
        MOCK.resetNetwork()
        local dropped = AC_Authority.dropped
        sides("client")
        for _ = 1, 50 do
            AC_Authority.request(alice, "assay", { sampleId = sample:getID(), kitId = kit:getID() })
        end
        eq(#MOCK.network.toServer, 50, "a client floods fifty requests")
        deliverRequests()
        eq(G.getKitUses(kit), uses - 1, "one use is taken")
        eq(sample.modData.assayRank, 1, "one assay is done")
        eq(#MOCK.network.toClient, 1, "one answer goes back")
        eq(AC_Authority.dropped - dropped, 49, "forty-nine are dropped")
        eq(#MOCK.network.xp, 1, "XP once")
        -- Bob is not slowed down by Alice, nor one kind of request by another.
        local bobSample = T.makeSample(x, y, 0)
        bob.inventory:addItem(bobSample)
        AC_Authority.request(bob, "assay", { sampleId = bobSample:getID(), kitId = bobKit:getID() })
        deliverRequests()
        eq(bobSample.modData.assayRank, 2, "another player in the same second is served")
        -- A clock that goes back does not lock anyone out.
        MOCK.timestampMs = MOCK.timestampMs - 60000
        local fresh = T.makeSample(x, y, 0)
        alice.inventory:addItem(fresh)
        AC_Authority.request(alice, "assay", { sampleId = fresh:getID(), kitId = kit:getID() })
        deliverRequests()
        eq(fresh.modData.assayRank, 1, "a clock that went backwards lets the request through")
        later()

        -- A handler that fails is answered, not left hanging.
        local realAnalyze = G.analyzeSample
        G.analyzeSample = function() error("boom") end
        local broken = T.makeSample(x, y, 0)
        alice.inventory:addItem(broken)
        MOCK.resetNetwork()
        later()
        sides("server")
        MOCK.capturePrint(true)
        local answer = AC_Authority.onClientCommand("AmmoMaking", "assay", alice, { sampleId = broken:getID(), kitId = kit:getID() })
        MOCK.capturePrint(false)
        sides("client")
        G.analyzeSample = realAnalyze
        eq(answer and answer.error, "server_error", "an error in a handler is answered server_error")

        -- The analyzer: distance, coordinates, someone else's sample.
        local ax, ay = 2900, 310
        local labSquare = MOCK.registerSquare(T.poweredLabSquare(ax, ay))
        local analyzer = T.placeAnalyzerObject(labSquare)
        local emptySquare = MOCK.registerSquare(T.poweredLabSquare(ax + 1, ay))
        alice.x, alice.y, alice.square = ax, ay, labSquare
        local labSample = T.makeSample(ax, ay, 1, "Good", "None")
        alice.inventory:addItem(labSample)
        local bobLab = T.makeSample(ax, ay, 1, "Good", "None")
        bob.inventory:addItem(bobLab)
        local function refusedLab(label, errorCode, command, args, setup, undo)
            later()
            MOCK.resetNetwork()
            if setup then setup() end
            sides("server")
            local result = AC_Authority.onClientCommand("AmmoMaking", command, alice, args)
            sides("client")
            if undo then undo() end
            eq(result and result.error, errorCode, command .. ", " .. label .. ": " .. errorCode)
            eq(analyzer.modData.labAnalyzerState or "idle", "idle", command .. ", " .. label .. ": the analyzer is unchanged")
            eq(alice.inventory:contains(labSample), true, command .. ", " .. label .. ": the sample stays")
            eq(analyzer.transmits or 0, 0, command .. ", " .. label .. ": nothing transmitted")
            eq(#MOCK.network.xp, 0, command .. ", " .. label .. ": no XP")
        end
        local id = labSample:getID()
        refusedLab("from ten steps away", "too_far", "labStart", { x = ax, y = ay, z = 0, sampleId = id }, function() alice.x = ax + 10 end, function() alice.x = ax end)
        refusedLab("the analyzer one level down", "too_far", "labStart", { x = ax, y = ay, z = 0, sampleId = id }, function() alice.z = 1 end, function() alice.z = 0 end)
        refusedLab("fractional coordinates", "bad_request", "labStart", { x = ax + 0.5, y = ay, z = 0, sampleId = id })
        refusedLab("coordinates as text", "bad_request", "labStart", { x = tostring(ax), y = ay, z = 0, sampleId = id })
        refusedLab("coordinates that are not numbers", "bad_request", "labStart", { x = 0 / 0, y = ay, z = 0, sampleId = id })
        refusedLab("coordinates far outside the map", "bad_request", "labStart", { x = 1e12, y = ay, z = 0, sampleId = id })
        refusedLab("negative coordinates", "bad_request", "labStart", { x = -ax, y = ay, z = 0, sampleId = id })
        refusedLab("a level that does not exist", "bad_request", "labStart", { x = ax, y = ay, z = 99, sampleId = id })
        refusedLab("no coordinates", "bad_request", "labStart", { sampleId = id })
        refusedLab("a square the server does not have", "no_square", "labStart", { x = ax + 50, y = ay, z = 0, sampleId = id })
        refusedLab("a square with no analyzer", "invalid_analyzer", "labStart", { x = ax + 1, y = ay, z = 0, sampleId = id })
        refusedLab("another player's sample", "invalid_sample", "labStart", { x = ax, y = ay, z = 0, sampleId = bobLab:getID() })
        refusedLab("collecting from an idle analyzer", "empty", "labCollect", { x = ax, y = ay, z = 0 })
        refusedLab("cancelling an idle analyzer", "not_processing", "labCancel", { x = ax, y = ay, z = 0 })
        eq(bob.inventory:contains(bobLab), true, "the other player's sample never moved")
        check(emptySquare ~= nil, "(the empty square is loaded)")
        -- A dropped analyzer (an item on the floor) is single player only.
        local droppedItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
        local dropped = MOCK.newWorldObject({ class = "IsoWorldInventoryObject" })
        dropped.getItem = function() return droppedItem end
        emptySquare.getWorldObjects = function() return MOCK.arrayList({ dropped }) end
        refusedLab("a dropped analyzer item", "invalid_analyzer", "labStart", { x = ax + 1, y = ay, z = 0, sampleId = id })

        -- Pick up: too far, busy, not an analyzer.
        local function refusedPickUp(label, errorCode, target, setup, undo)
            later()
            MOCK.resetNetwork()
            if setup then setup() end
            local action = AC_PickUpAnalyzerAction:new(alice, analyzer)
            onServer(action, target and { analyzer = target } or nil)
            if undo then undo() end
            eq(lastAnswer() and lastAnswer().error, errorCode, "pick up, " .. label .. ": " .. errorCode)
            eq(#labSquare.specialObjects, 1, "pick up, " .. label .. ": the analyzer stays")
            eq(alice.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 0, "pick up, " .. label .. ": no item")
        end
        refusedPickUp("from ten steps away", "too_far", nil, function() alice.y = ay + 10 end, function() alice.y = ay end)
        refusedPickUp("a wall instead of the analyzer", "invalid_analyzer", MOCK.newWorldObject({ name = "wall" }))
        refusedPickUp("while an assay runs", "processing", nil,
            function() analyzer.modData.labAnalyzerState = "processing"; analyzer.modData.storedSample = true; analyzer.modData.labRemainingHours = 5; analyzer.modData.labLastUpdateAt = MOCK.worldHours end,
            function() analyzer.modData.labAnalyzerState = "idle"; analyzer.modData.storedSample = nil; analyzer.modData.labRemainingHours = nil; analyzer.modData.labLastUpdateAt = nil end)

        -- Placing: the server checks distance and the switch before create() builds.
        local placeSquare = MOCK.registerSquare(T.poweredLabSquare(ax + 20, ay))
        local item = alice.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
        sides("server")
        MOCK.capturePrint(true)
        local cursor = AC_LaboratoryAnalyzerObject:new(alice, item)
        cursor:create(ax + 20, ay, 0, false, cursor.sprite)
        eq(#placeSquare.specialObjects, 0, "place: twenty steps away, nothing is built")
        eq(alice.inventory:contains(item), true, "and the item stays")
        alice.x = ax + 20
        authority(false)
        cursor:create(ax + 20, ay, 0, false, cursor.sprite)
        eq(#placeSquare.specialObjects, 0, "place: with the switch off on the server, nothing is built")
        authority(true)
        cursor:create(ax + 20, ay, 0, false, cursor.sprite)
        eq(#placeSquare.specialObjects, 1, "place: next to it, with the switch on, it is built")
        MOCK.capturePrint(false)
        sides("client")

        -- A client never decides: on a client every server function refuses.
        sides("client")
        MOCK.resetNetwork()
        later()
        local clientAnswer = AC_Authority.serverMine(alice, square, "copper", pick)
        eq(clientAnswer.error, "multiplayer_unsupported", "called on a client, the server's mining refuses")
        eq(AC_Deposits.getRemaining(x, y, "copper"), reserve, "and mines nothing")
        eq(AC_Authority.onClientCommand("AmmoMaking", "assay", alice, { sampleId = sample:getID(), kitId = kit:getID() }), nil, "a command handled on a client does nothing")
        eq(AC_AuthorityClient.onServerCommand("OtherMod", "result", { action = "mine", ok = true }), nil, "an answer of another mod is not shown")
        eq(AC_AuthorityClient.onServerCommand("AmmoMaking", "result", { action = "giveOre", ok = true }), nil, "nor an answer to nothing the mod asks")
        eq(AC_AuthorityClient.onServerCommand("AmmoMaking", "result", "text"), nil, "nor one that is not a table")
        sides("sp")
    end

    section("Multiplayer: every refusal has a message in the single-player words")
    do
        T.reloadMod()
        local seen = {}
        for _, case in ipairs({
            { "mine", "no_ore", "No workable copper ore here", { metal = "copper" } },
            { "mine", "no_prospect", "You need an assayed sample of this site" },
            { "mine", "no_pickaxe", "Your pickaxe is not usable" },
            { "mine", "multiplayer_unsupported", "Ore extraction is not available in multiplayer yet" },
            { "mine", "too_far", "Could not extract ore" },
            { "mine", "rate_limited", "Could not extract ore" },
            { "mine", "invalid_metal", "Could not extract ore", { metal = "gold" } },
            { "dig", "too_far", "Cannot reach sampling location" },
            { "dig", "no_shovel", "Could not collect geological sample" },
            { "dig", "multiplayer_unsupported", "Geological sampling and assays are not available in multiplayer yet" },
            { "assay", "kit_empty", "Assay kit is empty" },
            { "assay", "already_analyzed", "Sample already has an equal or better assay" },
            { "assay", "lab_processing", "Sample is currently being analyzed" },
            { "assay", "invalid_kit", "Analysis failed" },
            { "labStart", "no_power", "Laboratory analyzer requires electricity" },
            { "labStart", "busy", "Laboratory analyzer is already occupied" },
            { "labStart", "invalid_sample", "This sample cannot be analyzed" },
            { "labStart", "invalid_analyzer", "Could not start laboratory assay" },
            { "labStart", "too_far", "Cannot reach the laboratory analyzer" },
            { "labStart", "multiplayer_unsupported", "Using the laboratory analyzer is not available in multiplayer yet" },
            { "labCollect", "not_ready", "Laboratory assay is still processing" },
            { "labCollect", "empty", "Laboratory analyzer is empty" },
            { "labCollect", "bad_request", "Could not collect laboratory sample" },
            { "labCancel", "not_processing", "Could not cancel the laboratory assay" },
            { "pickUp", "processing", "Cancel the laboratory assay before moving the analyzer" },
            { "pickUp", "ready", "Collect the laboratory sample before moving the analyzer" },
            { "pickUp", "too_far", "Cannot reach the laboratory analyzer" },
            { "pickUp", "gone", "Could not pick up the laboratory analyzer" },
        }) do
            local answer = { action = case[1], ok = false, error = case[2] }
            for key, value in pairs(case[4] or {}) do answer[key] = value end
            eq(AC_AuthorityClient.getText(answer), case[3], case[1] .. " / " .. case[2])
            seen[case[1]] = true
        end
        for _, case in ipairs({
            { { action = "dig", ok = true }, "Geological sample collected" },
            { { action = "assay", ok = true, xp = 3 }, "Sample analyzed" },
            { { action = "labStart", ok = true }, "Laboratory assay started - " .. AC_LaboratoryAnalyzer.CONFIG.processingHours .. " hours" },
            { { action = "labCollect", ok = true, xp = 10 }, "Laboratory tested sample collected - +10 Ammo Making XP" },
            { { action = "labCollect", ok = true, xp = 0 }, "Laboratory tested sample collected" },
            { { action = "labCancel", ok = true }, "Laboratory assay cancelled - sample returned" },
            { { action = "pickUp", ok = true }, "Laboratory Assay Analyzer picked up" },
            { { action = "mine", ok = true, metal = "zinc", remaining = 0, initial = 2, xp = 5 }, "Zinc ore extracted - deposit exhausted - +5 Ammo Making XP" },
        }) do
            eq(AC_AuthorityClient.getText(case[1]), case[2], case[1].action .. ": ok")
        end
        for action in pairs(AC_AuthorityClient.TEXT) do
            check(seen[action], "the refusals of " .. action .. " are covered")
        end
        eq(AC_AuthorityClient.getText({ action = "nothing" }), nil, "no text for an answer to nothing")
        sides("sp")
        T.reloadMod()
    end
end
