-- Ammo Making - offline tests: quality tracking in magazines and firearms
-- (AC_QualityCarrier) and the locked firing effects (AC_QualityEffects).
--
-- Loaded by tests/run_tests.lua. The firearm side runs against
-- tests/firearm_model.lua, a model of vanilla's reload actions. It shows
-- that the record stays in step IF vanilla behaves as it reads. That the
-- game does is REQUIRES FUTURE IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK = T.check, T.eq, T.section, T.MOCK
    local readFile, ROOT = T.readFile, T.ROOT
    local MODEL = dofile(ROOT .. "/tests/firearm_model.lua")

    local function start(on)
        MOCK.activeMods = {}
        MOCK.client, MOCK.server, MOCK.debug = false, false, false
        MOCK.randomSequence = nil
        SandboxVars = { AmmoMaking = { QualityTracking = on == true } }
        T.reloadMod()
        MODEL.install(MOCK)
        MOCK.capturePrint(true)
        local installed = AC_QualityCarrier.installIfEnabled()
        MOCK.capturePrint(false)
        return installed
    end

    local function finish()
        if MODEL.uninstall then MODEL.uninstall() end
        SandboxVars = {}
        MOCK.client, MOCK.server, MOCK.debug = false, false, false
        T.reloadMod()
    end

    -- A shooter carrying loose rounds: `qualities` handloaded ones (one per
    -- entry) and `factory` plain ones, shuffled together by `order`.
    local function shooter(family, qualities, factory)
        local square = MOCK.newSquare(30, 30, 0, T.GRASS)
        local player = MODEL.newShooter(MOCK, square)
        local spec = MODEL.FIREARMS[family]
        local rounds = MODEL.giveRounds(MOCK, player, spec.ammo, #qualities + factory)
        for index, quality in ipairs(qualities) do
            AC_CaseQuality.setRoundQuality(rounds[index], quality)
        end
        return player, MODEL.newFirearm(MOCK, family), spec
    end

    -- Handloaded rounds and quality among the loose rounds carried.
    local function loose(player, roundType)
        local found = AC_QualityCarrier.census(player, roundType)
        local sum = 0
        for _, quality in ipairs(found.qualities) do sum = sum + quality end
        return found.count, #found.qualities, sum
    end

    -- The record an item stores, as numbers: zeros when it stores none,
    -- or one that is damaged (which reads as factory rounds).
    local function held(item)
        local record = item.modData[AC_QualityCarrier.KEY]
        if type(record) ~= "table" or #AC_QualityTally.check(record) > 0 then return 0, 0 end
        return record.handloaded, record.qualitySum
    end

    local function sum(list)
        local total = 0
        for _, value in ipairs(list) do total = total + value end
        return total
    end

    section("Quality tracking: off unless its sandbox option is on")
    do
        local installed = start(false)
        eq(installed, nil, "off: installIfEnabled does nothing")
        eq(AC_QualityCarrier.installed, nil, "off: nothing is recorded as installed")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 1, "off: the only listener on the shot is vanilla's own")
        local originals = {}
        for _, part in ipairs(AC_QualityCarrier.WRAPS) do originals[part.key] = _G[part.global][part.field] end
        Events.OnGameStart.fire()
        for _, part in ipairs(AC_QualityCarrier.WRAPS) do
            check(_G[part.global][part.field] == originals[part.key], "off: game start leaves " .. part.global .. "." .. part.field .. " as it is")
        end
        eq(#Events.OnWeaponSwingHitPoint.handlers, 1, "off: and adds no listener")
        eq(#AC_QualityCarrier.WRAPS, 7, "seven vanilla functions are the touch points")

        -- Handloaded rounds loaded and fired: nothing is written anywhere,
        -- and what is unloaded is plain, as before this feature existed.
        local player, gun, spec = shooter("revolver", { 80, 60, 40 }, 3)
        MODEL.reload(player, gun)
        eq(next(gun.modData), nil, "off: loading writes nothing on the gun")
        MODEL.fire(player, gun)
        MODEL.unloadFirearm(player, gun)
        eq(next(gun.modData), nil, "off: nor does firing or unloading")
        local _, handloaded = loose(player, spec.ammo)
        eq(handloaded, 0, "off: the rounds that come back are plain, as vanilla makes them")
        -- Off: no load inspection, no menu entry, and a loose round still
        -- says its record is lost at loading.
        MODEL.reload(player, gun)
        eq(AmmoInspection.getLoad(gun), nil, "off: a loaded gun has nothing to inspect")
        eq(T.fillInventoryMenu(player, gun):find("Inspect Loaded Ammunition"), nil, "off: and no menu entry")
        local offRound = MODEL.giveRounds(MOCK, player, spec.ammo, 1)[1]
        AC_CaseQuality.setRoundQuality(offRound, 50)
        player.perkLevel = 3
        check(string.find(table.concat(AmmoInspection.inspectComponent(player, offRound).lines, "\n"), "loading or boxing it keeps only a count", 1, true) ~= nil, "off: a loose round says loading keeps only a count")

        -- The option on a multiplayer client or server changes nothing.
        for _, side in ipairs({ "client", "server" }) do
            SandboxVars = { AmmoMaking = { QualityTracking = true } }
            T.reloadMod()
            MODEL.install(MOCK)
            MOCK[side] = true
            eq(AC_QualityCarrier.installIfEnabled(), nil, "on a multiplayer " .. side .. " nothing is installed")
            MOCK[side] = false
        end

        -- The sandbox option: one for each experimental Lua-only feature,
        -- off by default, with its texts; none for a locked feature.
        local options = readFile(ROOT .. "/mod/AmmoMaking/42/media/sandbox-options.txt")
        check(string.find(options, "^VERSION = 1,") ~= nil, "the sandbox file starts with the version line the engine requires")
        check(string.find(options, "/*", 1, true) == nil, "and carries no comment (the engine's option parser is not known to skip one)")
        local texts = {}
        for key, value in string.gmatch(readFile(T.TRANSLATE .. "Sandbox.json"), '"([^"]+)"%s*:%s*"([^"]*)"') do texts[key] = value end
        local declared = {}
        for name, body in string.gmatch(options, "option%s+([%w_%.]+)%s*(%b{})") do
            declared[name] = body
            local page = string.match(body, "page%s*=%s*([%w_]+)")
            local translation = string.match(body, "translation%s*=%s*([%w_]+)")
            eq(string.match(body, "type%s*=%s*(%a+)"), "boolean", name .. " is a boolean")
            eq(string.match(body, "default%s*=%s*(%a+)"), "false", name .. " is off by default")
            check(texts["Sandbox_" .. tostring(page)] ~= nil, name .. ": its page has a title")
            check(texts["Sandbox_" .. tostring(translation)] ~= nil, name .. " has a label")
            check(string.find(texts["Sandbox_" .. tostring(translation) .. "_tooltip"] or "", "EXPERIMENTAL", 1, true) ~= nil, name .. " has a tooltip that says it is experimental")
        end
        for _, definition in ipairs(AC_Features.DEFINITIONS) do
            if definition.sandbox then
                local name = AC_Features.SANDBOX_TABLE .. "." .. definition.sandbox
                eq(declared[name] ~= nil, definition.stability == AC_Features.EXPERIMENTAL, name .. (definition.stability == AC_Features.EXPERIMENTAL and " is offered in the sandbox options" or " is not offered: the feature is locked"))
                declared[name] = nil
            end
        end
        eq(next(declared), nil, "no sandbox option without a feature")
        finish()
    end

    section("Quality tracking: rounds keep their quality through every magazine and firearm (modelled vanilla actions)")
    do
        local installed = start(true)
        check(installed ~= nil and installed.shot, "on: the shot listener is installed")
        for _, part in ipairs(AC_QualityCarrier.WRAPS) do eq(installed[part.key], true, "on: " .. part.global .. "." .. part.field .. " is wrapped") end
        eq(AC_QualityCarrier.install(), installed, "installing again does nothing")
        eq(#Events.OnWeaponSwingHitPoint.handlers, 2, "one listener beside vanilla's")
        local C = AC_QualityCarrier

        for _, family in ipairs(MODEL.FAMILIES) do
            local spec = MODEL.FIREARMS[family]
            local qualities = {}
            for index = 1, math.max(1, math.floor(spec.maxAmmo / 2)) do qualities[index] = 30 + ((index * 17) % 60) end
            local factory = spec.maxAmmo - #qualities
            local player, gun = shooter(family, qualities, factory)
            local total = sum(qualities)
            local what = family

            -- Load everything.
            local magazine
            if spec.magazine then
                magazine = player.inventory:addItem(MODEL.newMagazine(MOCK, spec.magazine, spec.ammo, spec.maxAmmo, 0))
                MODEL.loadMagazine(player, magazine, spec.maxAmmo)
                eq(magazine:getCurrentAmmoCount(), spec.maxAmmo, what .. ": the magazine is full")
                local handloaded, quality = held(magazine)
                eq(handloaded, #qualities, what .. ": the loose magazine knows its handloaded rounds")
                eq(quality, total, what .. ": and their quality, exactly")
                eq(magazine.modData[C.KEY].count, spec.maxAmmo, what .. ": its record describes every round in it")
                MODEL.insertMagazine(player, gun, magazine)
            else
                MODEL.reload(player, gun)
            end
            eq(MODEL.liveRounds(gun), spec.maxAmmo, what .. " holds a full load")
            local handloaded, quality = held(gun)
            eq(handloaded, #qualities, what .. ": the gun knows its handloaded rounds")
            eq(quality, total, what .. ": and their quality, exactly")
            eq(gun.modData[C.KEY].count, MODEL.liveRounds(gun), what .. ": its record describes what it holds, chamber included")
            local looseCount, looseHandloaded = loose(player, spec.ammo)
            eq(looseCount, 0, what .. ": no loose round is left")
            eq(looseHandloaded, 0, what .. ": and no quality stayed behind")
            local described = C.describe(gun)
            eq(described.rounds, spec.maxAmmo, what .. ": describe() counts the rounds")
            eq(described.handloaded, #qualities, what .. ": and the handloaded ones")
            eq(described.factory, factory, what .. ": and the factory ones")
            eq(described.meanQuality, total / #qualities, what .. ": and their mean quality")

            -- Take everything out again, by the family's own way.
            if spec.magazine then
                local out = MODEL.ejectMagazine(player, gun)
                check(out ~= nil and out ~= magazine, what .. ": ejecting makes a new magazine item")
                -- The chambered round stayed in the gun.
                eq(MODEL.liveRounds(gun), 1, what .. ": the chambered round stays")
                local gunHandloaded, gunQuality = held(gun)
                local outHandloaded, outQuality = held(out)
                eq(gunHandloaded + outHandloaded, #qualities, what .. ": gun and magazine together still hold every handloaded round")
                eq(gunQuality + outQuality, total, what .. ": and every point of quality")
                check(gunHandloaded <= 1, what .. ": at most the one chambered round is handloaded")
                MODEL.unloadMagazine(player, out, spec.maxAmmo)
                eq(out.modData[C.KEY], nil, what .. ": an emptied magazine keeps no record")
                MODEL.rack(player, gun)
            else
                MODEL.unloadFirearm(player, gun)
                -- A chambered round comes out by racking.
                for _ = 1, 3 do MODEL.rack(player, gun) end
            end
            eq(MODEL.liveRounds(gun), 0, what .. " is empty")
            eq(gun.modData[C.KEY], nil, what .. ": an empty gun keeps no record")
            local count, backHandloaded, backQuality = loose(player, spec.ammo)
            eq(count, spec.maxAmmo, what .. ": every round came back")
            eq(backHandloaded, #qualities, what .. ": every handloaded round came back handloaded")
            eq(backQuality, total, what .. ": with every point of quality")
        end

        -- Inspecting a load: a menu entry on a loaded magazine or firearm,
        -- lines gated by skill, and nothing written.
        do
            local player, gun, spec = shooter("revolver", { 82, 60 }, 2)
            MODEL.reload(player, gun)
            local record = gun.modData[C.KEY]
            local calibre, load = AmmoInspection.getLoad(gun)
            eq(calibre and calibre.round, spec.ammo, "a loaded revolver is a load of its calibre")
            eq(load.rounds, 4, "of four rounds")
            local menu = T.fillInventoryMenu(player, gun)
            check(menu:find("Inspect Loaded Ammunition") ~= nil, "its context menu offers the inspection")
            player.perkLevel = 0
            local lines = AmmoInspection.inspectLoad(player, gun).lines
            check(string.find(lines[1], "Loaded: 4 x ", 1, true) ~= nil, "the first line counts the rounds: " .. lines[1])
            eq(#lines, 2, "level 0: the count and nothing about quality")
            check(string.find(table.concat(lines, " "), "71", 1, true) == nil and string.find(table.concat(lines, " "), "andloaded", 1, true) == nil, "level 0 learns nothing about the handloads")
            player.perkLevel = 2
            local novice = table.concat(AmmoInspection.inspectLoad(player, gun).lines, "\n")
            check(string.find(novice, "Handloaded rounds: 2, case quality ", 1, true) ~= nil, "level 2 sees how many are handloaded and a word for their quality")
            check(string.find(novice, "Factory rounds: 2", 1, true) ~= nil, "and how many are factory rounds")
            check(string.find(novice, "71", 1, true) == nil, "but not the number")
            check(string.find(novice, "average of the handloaded rounds", 1, true) ~= nil, "and is told it is an average")
            player.perkLevel = 6
            local expert = table.concat(AmmoInspection.inspectLoad(player, gun).lines, "\n")
            check(string.find(expert, "(71)", 1, true) ~= nil, "level 6 sees the mean quality as a number")
            check(string.find(expert, "[debug]", 1, true) == nil, "no debug line in a normal game")
            MOCK.debug = true
            local debugLines = table.concat(AmmoInspection.inspectLoad(player, gun).lines, "\n")
            check(string.find(debugLines, "[debug] stored record: version 1, count 4, handloaded 2, qualitySum 142", 1, true) ~= nil, "in -debug the stored record is shown")
            check(string.find(debugLines, "[debug] record: ok", 1, true) ~= nil, "and that it is sound")
            MOCK.debug = false
            check(gun.modData[C.KEY] == record, "inspecting writes nothing")

            -- Not a load: an empty gun, a loose round, something else.
            eq(AmmoInspection.getLoad(MODEL.newFirearm(MOCK, "revolver")), nil, "an empty gun has nothing to inspect")
            eq(AmmoInspection.getLoad(MOCK.newItem("Base.Plank")), nil, "nor has a plank")
            eq(AmmoInspection.getLoad(nil), nil, "nor nothing")
            eq(T.fillInventoryMenu(player, MODEL.newFirearm(MOCK, "revolver")):find("Inspect Loaded Ammunition"), nil, "an empty gun gets no menu entry")
            -- All factory: said in one line.
            local plainPlayer, plainGun = shooter("pumpShotgun", {}, 3)
            MODEL.reload(plainPlayer, plainGun)
            plainPlayer.perkLevel = 3
            local plain = table.concat(AmmoInspection.inspectLoad(plainPlayer, plainGun).lines, "\n")
            check(string.find(plain, "Factory rounds, as far as you can tell.", 1, true) ~= nil, "a load of factory rounds says so")

            -- A loose handloaded round says what loading it does now.
            local round = MODEL.giveRounds(MOCK, player, spec.ammo, 1)[1]
            AC_CaseQuality.setRoundQuality(round, 77)
            player.perkLevel = 3
            local component = table.concat(AmmoInspection.inspectComponent(player, round).lines, "\n")
            check(string.find(component, "Loading this round keeps its quality", 1, true) ~= nil, "with tracking on, a loose round says loading keeps its quality")

            -- The debug printout of everything carried.
            MOCK.debug = true
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            player.inventory:addItem(gun)
            AC_GeologyDebug.inspectLoads(player)
            MOCK.capturePrint(false)
            MOCK.debug = false
            check(MOCK.printLogContains("AMMUNITION LOADS (quality tracking ON)"), "the debug printout says tracking is on")
            check(MOCK.printLogContains("4 rounds, 2 handloaded (mean quality 71.0), 2 factory"), "and describes the carried revolver")
            check(MOCK.printLogContains("stored: version 1, count 4, handloaded 2, qualitySum 142"), "with its stored record")
        end

        -- Factory rounds only: the gun never gets ModData from this file.
        do
            local player, gun = shooter("pumpShotgun", {}, 5)
            MODEL.reload(player, gun)
            MODEL.fire(player, gun)
            MODEL.unloadFirearm(player, gun)
            eq(next(gun.modData), nil, "a gun that only ever held factory rounds carries no record and no ModData")
            eq(C.describe(gun).handloaded, 0, "and describes itself as all factory")
        end

        -- Firing: what leaves the record is what was fired, exactly.
        for _, family in ipairs(MODEL.FAMILIES) do
            local spec = MODEL.FIREARMS[family]
            local qualities = {}
            for index = 1, math.max(1, math.floor(spec.maxAmmo * 2 / 3)) do qualities[index] = 20 + ((index * 23) % 75) end
            local player, gun = shooter(family, qualities, spec.maxAmmo - #qualities)
            if spec.magazine then
                local magazine = player.inventory:addItem(MODEL.newMagazine(MOCK, spec.magazine, spec.ammo, spec.maxAmmo, 0))
                MODEL.loadMagazine(player, magazine, spec.maxAmmo)
                MODEL.insertMagazine(player, gun, magazine)
            else
                MODEL.reload(player, gun)
            end
            local firedHandloaded, firedQuality, shots = 0, 0, 0
            local realAfterShot = AC_QualityEffects.afterShot
            AC_QualityEffects.afterShot = function(_, _, fired)
                firedHandloaded = firedHandloaded + fired.handloaded
                firedQuality = firedQuality + fired.qualitySum
                eq(fired.rounds, 1, family .. ": one round per shot")
            end
            local violations = 0
            for _ = 1, spec.maxAmmo + 2 do
                if MODEL.fire(player, gun) then
                    shots = shots + 1
                    local handloaded, quality = held(gun)
                    if handloaded + firedHandloaded ~= #qualities or quality + firedQuality ~= sum(qualities) then violations = violations + 1 end
                    local record = gun.modData[C.KEY]
                    if record and record.count ~= MODEL.liveRounds(gun) then violations = violations + 1 end
                end
            end
            AC_QualityEffects.afterShot = realAfterShot
            eq(shots, spec.maxAmmo, family .. ": the whole load fired")
            eq(violations, 0, family .. ": after every shot, fired plus loaded is what was loaded, in rounds and in quality")
            eq(firedHandloaded, #qualities, family .. ": exactly the handloaded rounds were fired as handloaded")
            eq(firedQuality, sum(qualities), family .. ": with exactly their quality")
            eq(gun.modData[C.KEY], nil, family .. ": the emptied gun keeps no record")
        end
        finish()
    end

    section("Quality tracking: random play creates no round, no handloaded round and no quality (modelled vanilla actions)")
    do
        start(true)
        local C = AC_QualityCarrier
        local operations, exactRuns = 0, 0
        for seedIndex, seed in ipairs({ 5, 20261003, 911, 60606 }) do
            -- Every other seed plays with nothing unseen and nothing
            -- damaged: there the ledger must balance EXACTLY to the end,
            -- not merely never grow.
            local clean = seedIndex % 2 == 1
            local state = seed
            local function random(n)
                state = MOCK.nextRandom(state)
                return math.floor(state / 65536) % n
            end
            for _, family in ipairs(MODEL.FAMILIES) do
                local spec = MODEL.FIREARMS[family]
                local qualities = {}
                for index = 1, 40 do qualities[index] = 1 + random(100) end
                local player, gun = shooter(family, qualities, 40)
                local magazines = {}
                if spec.magazine then
                    for index = 1, 3 do
                        magazines[index] = player.inventory:addItem(MODEL.newMagazine(MOCK, spec.magazine, spec.ammo, spec.maxAmmo, 0))
                    end
                end
                local startRounds, startHandloaded, startQuality = 80, 40, sum(qualities)
                local firedRounds, firedHandloaded, firedQuality = 0, 0, 0
                local lostRounds = 0
                local realAfterShot = AC_QualityEffects.afterShot
                AC_QualityEffects.afterShot = function(_, _, fired)
                    firedHandloaded = firedHandloaded + fired.handloaded
                    firedQuality = firedQuality + fired.qualitySum
                end

                -- Everything that exists: loose rounds, every magazine the
                -- character carries, and the gun.
                local function ledger()
                    local rounds, handloaded, quality = loose(player, spec.ammo)
                    local carriers = { gun }
                    for _, item in ipairs(player.inventory.items) do
                        if item.isMagazine then table.insert(carriers, item) end
                    end
                    for _, item in ipairs(carriers) do
                        rounds = rounds + C.liveRounds(item)
                        local h, q = held(item)
                        handloaded, quality = handloaded + h, quality + q
                    end
                    return rounds, handloaded, quality
                end

                local violations = {}
                local function violation(text)
                    if #violations < 4 then table.insert(violations, text) end
                end
                local unseen = false
                for step = 1, 500 do
                    local action = random(12)
                    if clean and action >= 10 then action = action - 10 end
                    local loosest = nil
                    for _, item in ipairs(player.inventory.items) do
                        if item.isMagazine then loosest = item end
                    end
                    if action <= 3 then
                        if MODEL.fire(player, gun) then firedRounds = firedRounds + 1 end
                    elseif action == 4 then
                        MODEL.rack(player, gun)
                    elseif action == 5 or action == 6 then
                        if spec.magazine then
                            if loosest then MODEL.loadMagazine(player, loosest, 1 + random(spec.maxAmmo)) end
                        else
                            MODEL.reload(player, gun)
                        end
                    elseif action == 7 then
                        if spec.magazine then
                            if loosest then MODEL.unloadMagazine(player, loosest, 1 + random(spec.maxAmmo)) end
                        else
                            MODEL.unloadFirearm(player, gun, 1 + random(3))
                        end
                    elseif action == 8 or action == 9 then
                        if spec.magazine then
                            if gun:isContainsClip() then
                                MODEL.ejectMagazine(player, gun)
                            elseif loosest then
                                MODEL.insertMagazine(player, gun, loosest)
                            end
                        end
                    elseif action == 10 then
                        -- Something the mod never saw takes rounds out of the
                        -- gun (another mod's action, a debug command).
                        local count = gun:getCurrentAmmoCount()
                        if count > 0 then
                            local taken = 1 + random(count)
                            gun:setCurrentAmmoCount(count - taken)
                            lostRounds = lostRounds + taken
                            unseen = true
                        end
                    else
                        -- Or damages the record itself.
                        if gun.modData[C.KEY] then
                            local damage = ({ "broken", { count = 3, handloaded = 99, qualitySum = 1, version = 1, phase = 0 }, { version = 1, count = 0 / 0 } })[1 + random(3)]
                            gun.modData[C.KEY] = damage
                            unseen = true
                        end
                    end
                    operations = operations + 1

                    local rounds, handloaded, quality = ledger()
                    if rounds + firedRounds + lostRounds ~= startRounds then violation("step " .. step .. ": " .. rounds + firedRounds + lostRounds .. " rounds of " .. startRounds) end
                    -- A damaged record that is still on the gun counts for
                    -- nothing until it is read; it never counts for more.
                    local raw = gun.modData[C.KEY]
                    local sound = raw == nil or (type(raw) == "table" and #AC_QualityTally.check(raw) == 0)
                    if sound then
                        if handloaded + firedHandloaded > startHandloaded then violation("step " .. step .. ": more handloaded rounds than were made") end
                        if quality + firedQuality > startQuality then violation("step " .. step .. ": more quality than was made") end
                        if not unseen then
                            if handloaded + firedHandloaded ~= startHandloaded then violation("step " .. step .. ": a handloaded round was lost with nothing unseen (" .. handloaded + firedHandloaded .. " of " .. startHandloaded .. ")") end
                            if quality + firedQuality ~= startQuality then violation("step " .. step .. ": quality was lost with nothing unseen") end
                        end
                        for _, item in ipairs({ gun, loosest }) do
                            local record = item and item.modData[C.KEY]
                            if record then
                                if record.count ~= C.liveRounds(item) and item ~= gun then violation("step " .. step .. ": a magazine's record is out of step") end
                                if record.handloaded > record.count then violation("step " .. step .. ": more handloaded than rounds") end
                                if record.qualitySum > record.handloaded * 100 or record.qualitySum < record.handloaded then violation("step " .. step .. ": an impossible quality sum") end
                                if record.qualitySum ~= record.qualitySum or record.count ~= record.count then violation("step " .. step .. ": a NaN in a record") end
                            end
                        end
                    end
                end
                AC_QualityEffects.afterShot = realAfterShot
                eq(#violations, 0, "seed " .. seed .. " " .. family .. ": " .. table.concat(violations, "; "))
                if clean then
                    eq(unseen, false, "seed " .. seed .. " " .. family .. ": (a clean run: nothing unseen happened)")
                    local rounds, handloaded, quality = ledger()
                    eq(rounds + firedRounds, startRounds, "seed " .. seed .. " " .. family .. ": every round is accounted for at the end")
                    eq(handloaded + firedHandloaded, startHandloaded, "seed " .. seed .. " " .. family .. ": every handloaded round is accounted for at the end")
                    eq(quality + firedQuality, startQuality, "seed " .. seed .. " " .. family .. ": every point of quality is accounted for at the end")
                    exactRuns = exactRuns + 1
                end
                check(firedRounds > 10, "seed " .. seed .. " " .. family .. ": the run fired (" .. firedRounds .. ")")
            end
        end
        eq(exactRuns, 14, "two seeds of seven families ran clean and balanced exactly")
        print(string.format("  Quality tracking: %d random operations over 7 firearm families and 4 seeds (two clean, two with unseen changes and damaged records); one ledger, nothing created", operations))
        finish()
    end

    section("Quality tracking: damage, later releases and failures resolve toward factory and never break a reload")
    do
        start(true)
        local C = AC_QualityCarrier

        -- A record of a later release is never written over, by any path.
        do
            local player, gun = shooter("revolver", { 70, 70 }, 4)
            local later = { version = 99, count = 2, handloaded = 2, qualitySum = 199, future = "field" }
            gun.modData[C.KEY] = later
            MODEL.reload(player, gun)
            MODEL.fire(player, gun)
            MODEL.rack(player, gun)
            MODEL.unloadFirearm(player, gun)
            check(gun.modData[C.KEY] == later, "a later release's record is still the same table")
            eq(later.count, 2, "its fields are untouched")
            eq(later.future, "field", "including the ones this release does not know")
            eq(C.describe(gun).handloaded, 0, "and it reads as nothing known")
            local _, writable = C.observe(gun)
            eq(writable, false, "observe() says it must not be written")
        end

        -- Damaged records read as factory rounds; nothing is clamped into
        -- good ammunition, and looking does not write.
        for label, damage in pairs({
            ["a word"] = "full of good rounds",
            ["a number"] = 42,
            ["more handloaded than rounds"] = { version = 1, count = 2, handloaded = 5, qualitySum = 400, phase = 0.5 },
            ["an impossible quality"] = { version = 1, count = 4, handloaded = 2, qualitySum = 900, phase = 0.5 },
            ["a NaN"] = { version = 1, count = 4, handloaded = 0 / 0, qualitySum = 100, phase = 0.5 },
            ["no version"] = { count = 4, handloaded = 2, qualitySum = 150, phase = 0.5 },
        }) do
            local player, gun = shooter("revolver", {}, 6)
            MODEL.reload(player, gun)
            gun.modData[C.KEY] = damage
            local described = C.describe(gun)
            eq(described.handloaded, 0, label .. " reads as no handloaded round")
            eq(described.rounds, 6, label .. ": the gun's own count is kept")
            check(gun.modData[C.KEY] == damage, label .. ": looking at it writes nothing")
            MODEL.unloadFirearm(player, gun)
            local _, handloaded = loose(player, MODEL.FIREARMS.revolver.ammo)
            eq(handloaded, 0, label .. ": unloading hands out factory rounds")
            eq(gun.modData[C.KEY], nil, label .. ": and the damage is gone from the emptied gun")
        end

        -- Rounds that arrive unseen are factory rounds; rounds that leave
        -- unseen take their share with them, rounded down.
        do
            local player, gun = shooter("revolver", { 90, 90, 90 }, 0)
            MODEL.reload(player, gun)
            gun:setCurrentAmmoCount(6)
            local described = C.describe(gun)
            eq(described.rounds, 6, "three unseen rounds: six in the gun")
            eq(described.handloaded, 3, "the unseen ones are factory rounds")
            gun:setCurrentAmmoCount(1)
            described = C.describe(gun)
            check(described.handloaded <= 1, "five rounds gone unseen: at most one handloaded round is left")
            check(described.meanQuality == nil or described.meanQuality <= 90, "and its quality did not rise")
        end

        -- A wrapper is transparent, and a failure of the mod's part never
        -- reaches vanilla.
        do
            local calls, got = 0, nil
            local wrapped = C.wrap(function(self, event, parameter)
                calls = calls + 1
                got = { self, event, parameter }
                return "vanilla result"
            end, function() error("the mod's before step failed") end, function() error("unreachable") end)
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            local action = {}
            local ok, result = pcall(wrapped, action, "InsertBullet", "parameter")
            local ok2 = pcall(wrapped, action, "InsertBullet", "parameter")
            MOCK.capturePrint(false)
            check(ok and ok2, "a failing before step does not break the action")
            eq(result, "vanilla result", "vanilla's result is handed on")
            eq(calls, 2, "vanilla's function ran once per call")
            check(got[1] == action and got[2] == "InsertBullet" and got[3] == "parameter", "with exactly its arguments")
            local warnings = 0
            for _, line in ipairs(MOCK.printLog) do
                if string.find(line, "quality tracking: could not look at a reload", 1, true) then warnings = warnings + 1 end
            end
            eq(warnings, 1, "the failure is logged once, not per call")

            -- A failing after step likewise.
            local after = C.wrap(function() return 7 end, function() return {} end, function() error("the mod's after step failed") end)
            MOCK.capturePrint(true)
            local ok3, result3 = pcall(after, action)
            MOCK.capturePrint(false)
            check(ok3 and result3 == 7, "a failing after step does not break the action either")

            -- An animEvent wrapper looks at the inventory only for the
            -- events that move rounds.
            local scans = 0
            local filtered = C.wrap(function() return "played" end, function() scans = scans + 1 return nil end, function() end, { InsertBullet = true })
            eq(filtered(action, "InsertBulletSound", "sound"), "played", "another event goes straight to vanilla")
            eq(scans, 0, "without the mod looking at anything")
            filtered(action, "InsertBullet", nil)
            eq(scans, 1, "the event that moves a round is observed")
        end

        -- A build without one of the vanilla functions: that part is
        -- skipped and said; rounds it moves read as factory rounds.
        do
            SandboxVars = { AmmoMaking = { QualityTracking = true } }
            T.reloadMod()
            MODEL.install(MOCK)
            ISEjectMagazine.unloadAmmo = nil
            MOCK.clearPrintLog()
            MOCK.capturePrint(true)
            local partial = AC_QualityCarrier.installIfEnabled()
            MOCK.capturePrint(false)
            eq(partial.ejectMagazine, false, "a missing function is not wrapped")
            eq(partial.loadMagazine, true, "the others are")
            check(MOCK.printLogContains("ISEjectMagazine.unloadAmmo is not a function on this build"), "and the log says which")

            -- The game-start check reports each part.
            local ids = {}
            for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
            MOCK.resetCraftRecipes(ids)
            AC_Materials.applySkillRequirements()
            MOCK.capturePrint(true)
            local results = AC_Compat.run(false)
            MOCK.capturePrint(false)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            eq(found["feature Ammunition Quality Tracking: ON (on)"], "OK", "the check reports tracking as on")
            eq(found["quality tracking: ISEjectMagazine.unloadAmmo"], "WARNING", "the missing function is a WARNING")
            eq(found["quality tracking: ISInsertMagazine.loadAmmo"], "OK", "a wrapped one is OK")
            eq(found["quality tracking: the shot"], "OK", "and so is the shot")
            eq(found["feature Ammunition Quality Firing Effects: off (locked)"], "OK", "the firing effects are reported as locked")
        end
        finish()
    end

    section("Quality effects: written, linear in quality, and locked")
    do
        start(true)
        local E = AC_QualityEffects
        eq(#E.validate(), 0, "the effects description is sound: " .. table.concat(E.validate(), "; "))
        eq(AC_Features.get("qualityEffects").stability, AC_Features.DISABLED, "the feature is locked")

        -- Locked: afterShot looks at nothing and does nothing.
        local touched = false
        local probe = setmetatable({}, { __index = function() touched = true return nil end })
        eq(E.afterShot(probe, probe, probe), nil, "locked: afterShot returns nil")
        eq(touched, false, "without reading the character, the weapon or what was fired")

        -- The chance: nothing for factory rounds or perfect handloads, the
        -- maximum for a load of the worst, linear in between.
        local maximum = E.CONFIG.maximumExtraJamPercent
        eq(E.getExtraJamPercent({ count = 10, handloaded = 0, qualitySum = 0 }), 0, "factory rounds add no jam chance")
        eq(E.getExtraJamPercent({ count = 10, handloaded = 10, qualitySum = 1000 }), 0, "nor do handloads of quality 100")
        eq(E.getExtraJamPercent({ count = 10, handloaded = 10, qualitySum = 10 }), maximum, "a load of quality-1 handloads adds the maximum")
        local half = E.getExtraJamPercent({ count = 10, handloaded = 5, qualitySum = 5 })
        check(math.abs(half - maximum / 2) < 1e-9, "half a load of them adds half")
        for _, bad in ipairs({ "load", { count = 0, handloaded = 0, qualitySum = 0 }, { count = 2, handloaded = 5, qualitySum = 100 }, { count = 5, handloaded = 2, qualitySum = 900 }, { count = 5, handloaded = 2, qualitySum = 0 / 0 }, {} }) do
            eq(E.getExtraJamPercent(bad), 0, "a load that is not sane adds nothing")
        end
        -- Linear: the chance summed over the shots of a load depends only
        -- on the rounds in it. Two loads fired apart and the same rounds
        -- mixed in one load add up to the same, so nothing is gained by
        -- loading a bad round among good ones.
        local function summed(load) return E.getExtraJamPercent(load) * load.count end
        for _, case in ipairs({
            { { count = 6, handloaded = 6, qualitySum = 6 * 20 }, { count = 6, handloaded = 6, qualitySum = 6 * 95 } },
            { { count = 5, handloaded = 1, qualitySum = 3 }, { count = 15, handloaded = 15, qualitySum = 15 * 88 } },
            { { count = 30, handloaded = 0, qualitySum = 0 }, { count = 30, handloaded = 30, qualitySum = 30 * 50 } },
        }) do
            local a, b = case[1], case[2]
            local mixed = { count = a.count + b.count, handloaded = a.handloaded + b.handloaded, qualitySum = a.qualitySum + b.qualitySum }
            check(math.abs(summed(a) + summed(b) - summed(mixed)) < 1e-9, "mixing two loads changes nothing in total (" .. summed(mixed) .. ")")
        end

        -- Unlocked (as a later version would be): a poor load can set
        -- vanilla's own jam, only on a firearm that can jam.
        local definition = AC_Features.get("qualityEffects")
        definition.stability = AC_Features.EXPERIMENTAL
        SandboxVars = { AmmoMaking = { QualityTracking = true, QualityEffects = true } }
        local poor = { rounds = 1, handloaded = 1, qualitySum = 1, before = { count = 6, handloaded = 6, qualitySum = 6 } }
        local gun = MODEL.newFirearm(MOCK, "pistol")
        MOCK.randomSequence = { 0 }
        eq(#E.afterShot({}, gun, poor), 0, "unlocked: a firearm whose jam chance is 0 never jams")
        eq(gun:isJammed(), false, "and is not jammed")
        local jamChance = 2
        gun.modData.test = nil
        local canJam = setmetatable({}, { __index = gun })
        local jammed = false
        function canJam:getJamGunChance() return jamChance end
        function canJam:isJammed() return jammed end
        function canJam:setJammed(value) jammed = value end
        MOCK.randomSequence = { maximum * 100 - 1 }
        eq(table.concat(E.afterShot({}, canJam, poor), ","), "jam", "unlocked: a roll under the chance jams the gun")
        eq(jammed, true, "through vanilla's own jam state")
        jammed = false
        MOCK.randomSequence = { maximum * 100 }
        eq(#E.afterShot({}, canJam, poor), 0, "unlocked: a roll at the chance does not")
        MOCK.randomSequence = { 0 }
        local fine = { rounds = 1, handloaded = 1, qualitySum = 100, before = { count = 6, handloaded = 6, qualitySum = 600 } }
        eq(#E.afterShot({}, canJam, fine), 0, "unlocked: perfect handloads never add a jam")
        eq(#E.afterShot({}, canJam, "nonsense"), 0, "unlocked: nothing fired, nothing done")
        MOCK.randomSequence = nil
        -- Without the tracking under it, still nothing.
        SandboxVars = { AmmoMaking = { QualityEffects = true } }
        eq(E.afterShot({}, canJam, poor), nil, "unlocked but without tracking: off")
        definition.stability = AC_Features.DISABLED
        eq(E.afterShot({}, canJam, poor), nil, "locked again")

        -- validate() refuses a nonsense configuration.
        local saved = E.CONFIG.maximumExtraJamPercent
        E.CONFIG.maximumExtraJamPercent = 250
        check(#E.validate() > 0, "a chance above 100 % is refused")
        E.CONFIG.maximumExtraJamPercent = saved
        finish()
    end
end
