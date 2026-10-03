-- Ammo Making - offline tests: explicit multiplayer guards.
--
-- Loaded by tests/run_tests.lua. Mining and analyzer placement have had a
-- client guard since the first passes (section "Multiplayer client guard"
-- there). This suite covers what was still accidental: digging a sample,
-- the portable assays, and starting, cancelling and collecting at the
-- analyzer. On a multiplayer client each is refused in the logic and shown
-- as a disabled option that says why. isClient() is mocked; nothing here
-- has run on a server.

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK

    section("Multiplayer client: sampling, assays and the analyzer are refused, and say so")
    do
        local G, L = AC_GeologySampling, AC_LaboratoryAnalyzer
        MOCK.activeMods, MOCK.debug = {}, false
        MOCK.clearModData()

        -- Single player first: everything is available (the sections of
        -- the main suite exercise it; here only the switch itself).
        MOCK.client = false
        eq(G.isAvailable(), true, "single player: sampling and assays are available")
        eq(L.isAvailable(), true, "single player: the analyzer can be used")

        MOCK.client = true
        eq(G.isAvailable(), false, "client: sampling and assays are not available")
        eq(L.isAvailable(), false, "client: the analyzer cannot be used")

        -- Digging: no item, no shovel wear, and the reason as an error code.
        local square = MOCK.newSquare(120, 130, 0, T.GRASS)
        local player = MOCK.newPlayer({ square = square, x = 120, y = 130 })
        local shovel = T.equipShovel(player)
        local condition = shovel:getCondition()
        local sample, err = G.createSample(player, square, shovel)
        eq(sample, nil, "client: digging creates no sample")
        eq(err, "multiplayer_unsupported", "and says why")
        eq(player.inventory:count(G.ITEMS.Sample), 0, "nothing is added to the inventory")
        eq(shovel:getCondition(), condition, "and the shovel is not worn")
        local dig = T.fillWorldMenu(player, square):find("Dig Geological Sample")
        check(dig ~= nil and dig.notAvailable == true, "the dig option is shown disabled")
        check(dig and dig.fn == nil, "and does nothing when clicked")

        -- Assays: the kit keeps its uses, the sample its rank, no XP.
        local unassayed = T.makeSample(120, 130, 0)
        player.inventory:addItem(unassayed)
        for _, case in ipairs({
            { G.ITEMS.FieldKit, "Analyze with Field Assay Kit" },
            { G.ITEMS.AdvancedFieldKit, "Analyze with Advanced Field Assay Kit" },
        }) do
            local kit = player.inventory:AddItem(case[1])
            local uses = G.getKitUses(kit)
            local ok, reason = G.analyzeSample(unassayed, kit)
            eq(ok, false, "client: " .. case[1] .. " assays nothing")
            eq(reason, "multiplayer_unsupported", "and says why")
            eq(G.getKitUses(kit), uses, "the kit keeps its uses")
            local option = T.fillInventoryMenu(player, unassayed):find(case[2])
            check(option ~= nil and option.notAvailable == true, "the option '" .. case[2] .. "' is shown disabled")
        end
        eq(tonumber(unassayed.modData.assayRank) or 0, 0, "the sample is still unassayed")
        eq(#player.xpLog, 0, "no XP was granted")

        -- The analyzer: start, cancel and collect.
        local labSquare = T.poweredLabSquare(140, 150)
        local labPlayer = MOCK.newPlayer({ square = labSquare, x = 140, y = 150 })
        local analyzer = T.placeAnalyzerObject(labSquare)
        local labSample = T.makeSample(140, 150, 0)
        labPlayer.inventory:addItem(labSample)
        local started, startError = L.startAssay(labPlayer, analyzer, labSample)
        eq(started, false, "client: no assay is started")
        eq(startError, "multiplayer_unsupported", "and says why")
        eq(labPlayer.inventory:count(G.ITEMS.Sample), 1, "the sample stays in the inventory")
        local collected, collectError = L.collectSample(labPlayer, analyzer)
        eq(collected, nil, "client: nothing is collected")
        eq(collectError, "multiplayer_unsupported", "and says why")
        local cancelled, cancelError = L.cancelAssay(labPlayer, analyzer)
        eq(cancelled, nil, "client: nothing is cancelled")
        eq(cancelError, "multiplayer_unsupported", "and says why")
        eq(#labPlayer.xpLog, 0, "no XP at the analyzer either")
        local startOption = T.fillAnalyzerMenu(labPlayer, analyzer):find("Start Lab Assay")
        check(startOption ~= nil and startOption.notAvailable == true, "the start option is shown disabled")
        -- Looking is still allowed: it changes nothing.
        check(T.fillAnalyzerMenu(labPlayer, analyzer):find("Check Laboratory Analyzer") ~= nil, "checking the analyzer is still offered")

        -- Back in single player the same calls work.
        MOCK.client = false
        local made = G.createSample(player, square, shovel)
        check(made ~= nil, "single player: digging makes a sample again")
        local live = T.fillWorldMenu(player, square):find("Dig Geological Sample")
        check(live ~= nil and live.notAvailable ~= true and type(live.fn) == "function", "and the dig option is live")
        local liveStart = T.fillAnalyzerMenu(labPlayer, analyzer):find("Start Lab Assay")
        check(liveStart ~= nil and liveStart.notAvailable ~= true, "and so is the analyzer's start option")
        MOCK.clearModData()
    end

    section("Multiplayer: every system is classified, and what changes items from Lua is switched off there")
    do
        -- The switched features that change items from Lua say so, and are
        -- off on a client and on a server (tests/suite_features.lua checks
        -- the mechanism; this pins which they are).
        local luaItemFeatures = { spentCases = true, qualityTracking = true, qualityEffects = true }
        for _, definition in ipairs(AC_Features.DEFINITIONS) do
            eq(definition.singlePlayerOnly, luaItemFeatures[definition.id] == true, definition.id .. (luaItemFeatures[definition.id] and " is single player only" or " is the engine's own and needs no guard"))
        end
        -- The availability switches of the always-on systems all read the
        -- same engine fact.
        for _, side in ipairs({ false, true }) do
            MOCK.client = side
            eq(AC_Mining.isAvailable(), not side, "mining available: " .. tostring(not side))
            eq(AC_GeologySampling.isAvailable(), not side, "sampling available: " .. tostring(not side))
            eq(AC_LaboratoryAnalyzer.isAvailable(), not side, "analyzer use available: " .. tostring(not side))
            eq(AC_LaboratoryAnalyzer.isPlacementAvailable(), not side, "analyzer placement available: " .. tostring(not side))
        end
        MOCK.client = false
        -- The design document's authority map names each of them.
        local document = T.readFile(T.ROOT .. "/docs/MULTIPLAYER_DESIGN.md")
        for _, needle in ipairs({ "Digging a sample", "Field and advanced assay", "Laboratory analyzer: start, cancel, collect", "Mining", "Reloading press", "Quality tracking", "Spent cases" }) do
            check(string.find(document, needle, 1, true) ~= nil, "the multiplayer authority map covers: " .. needle)
        end
    end
end
