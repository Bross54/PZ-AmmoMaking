-- Ammo Making - offline tests for the geology / assay / mining loop
--
-- Runs outside Project Zomboid with plain Lua 5.1:
--
--     lua5.1 tests/run_tests.lua
--
-- The Project Zomboid API is mocked in tests/mock_pz.lua. These tests
-- verify Lua-level logic and the invariants the mining loop promises:
--
--   Extraction    one completed action -> at most one reserve decrement,
--                 one ore, one XP grant, one wear roll
--   Cancellation  an interrupted / invalidated action -> nothing
--   Persistence   only real extraction changes persistent depletion
--   Knowledge     the assay gates what may be attempted; true geology
--                 decides what exists
--   Hidden info   normal UI never shows exact geology or reserves
--   Laboratory    one sample at a time; collect / cancel exactly once;
--                 a placed analyzer moves only when idle and empty
--
-- They cannot verify vanilla item ids, animations, sounds or Java
-- behaviour; that still needs an in-game test. Sections that drive the
-- placement cursor, placed objects or the pickup action use mocked
-- engine objects and check Lua control flow only.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$") or "."
local LUA = ROOT .. "/mod/AmmoMaking/42/media/lua/"

local MOCK = dofile(ROOT .. "/tests/mock_pz.lua")

------------------------------------------------
-- MINIMAL TEST FRAMEWORK
------------------------------------------------

local passed, failed = 0, 0
local currentSection = ""

local function check(condition, message)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL [" .. currentSection .. "]: " .. tostring(message))
    end
end

local function eq(actual, expected, message)
    check(actual == expected,
        message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function section(name)
    currentSection = name
    print("== " .. name)
end

------------------------------------------------
-- LOAD
------------------------------------------------

MOCK.loadMod(LUA)

local function reloadMod()
    MOCK.resetLuaState()
    MOCK.loadMod(LUA)
end

------------------------------------------------
-- HELPERS
------------------------------------------------

local GRASS = "blends_natural_01_16"

-- Finds an unused tile whose initial reserve for the metal is within
-- [minReserve, maxReserve] (and optionally has some of another metal).
local usedTiles = {}

local function findTile(metal, minReserve, maxReserve, opts)
    opts = opts or {}
    for x = 0, 4000 do
        for y = 0, 80 do
            local key = x .. "," .. y
            if not usedTiles[key] then
                local r = AC_Deposits.getInitialReserve(x, y, metal)
                local otherOk = true
                if opts.otherMetal then
                    otherOk = AC_Deposits.getInitialReserve(x, y, opts.otherMetal) >= (opts.otherMin or 1)
                end
                if r >= minReserve and (not maxReserve or r <= maxReserve) and otherOk then
                    usedTiles[key] = true
                    return x, y, r
                end
            end
        end
    end
    error("no tile found for " .. metal .. " reserve " .. minReserve .. ".." .. tostring(maxReserve))
end

local function makeSample(x, y, rank, copperGrade, zincGrade)
    local sample = MOCK.newItem("AmmoMaking.GeologicalSample")
    local d = sample.modData
    d.AmmoMakingGeologicalSample = true
    d.sampleX = x
    d.sampleY = y
    d.assayRank = rank
    d.copperGrade = copperGrade
    d.zincGrade = zincGrade
    d.labProcessing = false
    return sample
end

local function equipPickaxe(player, fullType, condition)
    local pick = MOCK.newItem(fullType or "Base.PickAxe", { condition = condition })
    player.inventory:addItem(pick)
    player.primary = pick
    return pick
end

local function equipShovel(player, condition)
    local shovel = MOCK.newItem("Base.Shovel", { condition = condition })
    player.inventory:addItem(shovel)
    player.primary = shovel
    return shovel
end

-- Player standing on a mineable grass square at (x, y) with an equipped
-- pickaxe and an assayed sample covering the square.
local function miningSetup(x, y, copperGrade, zincGrade, rank)
    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square, x = x, y = y })
    local pick = equipPickaxe(player)
    local sample = makeSample(x, y, rank or 1, copperGrade or "Good", zincGrade or "Good")
    player.inventory:addItem(sample)
    return player, square, pick, sample
end

local function worldObjectsFor(square)
    return { { getSquare = function() return square end } }
end

local function fillWorldMenu(player, square)
    MOCK.players = { player }
    local ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjectsFor(square), false)
    return ctx
end

local function fillInventoryMenu(player, item)
    MOCK.players = { player }
    local ctx = MOCK.newContext()
    Events.OnFillInventoryObjectContextMenu.fire(0, ctx, { item })
    return ctx
end

local function hasDigit(text)
    return string.find(tostring(text), "%d") ~= nil
end

local function storeSnapshot()
    local store = ModData.getOrCreate(AC_Deposits.CONFIG.modDataKey)
    local out = {}
    for key, record in pairs(store.tiles or {}) do
        out[key] = { copper = record.copper, zinc = record.zinc }
    end
    return out
end

local function sameSnapshot(a, b)
    for key, ra in pairs(a) do
        local rb = b[key]
        if not rb or rb.copper ~= ra.copper or rb.zinc ~= ra.zinc then return false end
    end
    for key in pairs(b) do
        if not a[key] then return false end
    end
    return true
end

-- Stand-in for a placed analyzer: a mock world object carrying the
-- ModData flag the building object writes. Engine behaviour of the real
-- IsoThumpable (rendering, saving, networking) is not modelled.
local function placeAnalyzerObject(square)
    local object = MOCK.newWorldObject({ class = "IsoThumpable", name = AC_LaboratoryAnalyzer.OBJECT_NAME })
    object:getModData().AmmoMakingLaboratoryAnalyzerWorldObject = true
    square:AddSpecialObject(object)
    return object
end

local function poweredLabSquare(x, y)
    local square = MOCK.newSquare(x, y, 0, "floors_interior_tiles_01_0", { room = {} })
    square.haveElectricity = function() return true end
    return square
end

local function fillAnalyzerMenu(player, analyzer)
    MOCK.players = { player }
    local ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { analyzer }, false)
    return ctx
end

------------------------------------------------
-- TEXT HELPER
------------------------------------------------

section("AC_Text fallbacks and substitution")
do
    MOCK.translations = nil
    eq(AC_Text.get("IGUI_AmmoMaking_Nope", "Fallback"), "Fallback", "missing translation uses fallback")
    eq(AC_Text.get("IGUI_AmmoMaking_Nope", "Mine %1 Ore (%2)", "Copper", "Good"), "Mine Copper Ore (Good)", "fallback substitutes %1 %2")
    eq(AC_Text.get("IGUI_AmmoMaking_Nope", "%1: %2-%3% (%4)", "Cu", 40, 60, "Good"), "Cu: 40-60% (Good)", "literal percent after placeholder survives")
    eq(AC_Text.get("IGUI_AmmoMaking_Nope", "Only %1 here"), "Only %1 here", "unfilled placeholder left visible rather than erroring")
    eq(AC_Text.get("IGUI_AmmoMaking_Nope"), "IGUI_AmmoMaking_Nope", "no fallback at all falls back to key")
    eq(AC_Text.get(nil, "x"), "x", "nil key is safe")

    MOCK.translations = { IGUI_AmmoMaking_MineOreOption = "Kopaj %1 rudu (%2)" }
    eq(AC_Text.get("IGUI_AmmoMaking_MineOreOption", "Mine %1 Ore (%2)", "Bakar", "Dobro"), "Kopaj Bakar rudu (Dobro)", "loaded translation wins over fallback")
    eq(AC_Text.get("IGUI_AmmoMaking_Other", "English"), "English", "keys absent from the loaded table still fall back")
    MOCK.translations = nil

    -- A translator that throws must not propagate
    local real = getTextOrNull
    getTextOrNull = function() error("boom") end
    eq(AC_Text.get("k", "safe"), "safe", "throwing translator falls back")
    getTextOrNull = real

    -- Display names never expose raw keys
    eq(AC_Deposits.getMetalName("copper"), "Copper", "metal name fallback")
    eq(AC_Deposits.getMetalName("unobtainium"), "unobtainium", "unknown metal echoes id")
    eq(AC_Geology.getGradeName("Very Rich"), "Very Rich", "grade name fallback")
    eq(AC_Geology.getGradeName(nil), "nil", "nil grade does not error")
end

------------------------------------------------
-- GEOLOGY
------------------------------------------------

section("Deterministic geology and seeds")
do
    local c1 = AC_Geology.getCopperConcentration(1234, 567)
    eq(AC_Geology.getCopperConcentration(1234, 567), c1, "same tile, same save -> same copper concentration")
    eq(AC_Geology.getTileGeology(1234.9, 567.2).copper, c1, "float coordinates floor to the tile")

    local seedA = AC_WorldData.getCopperSeed()
    check(type(seedA) == "number" and seedA >= 100000 and seedA <= 999999, "seed is a six-digit number")
    check(AC_WorldData.getCopperSeed() ~= AC_WorldData.getZincSeed(), "copper and zinc seeds differ")
    check(AC_WorldData.getGeologySeed() ~= AC_WorldData.getCopperSeed(), "geology and copper seeds differ")

    -- Switching saves inside one Lua session (the real game keeps Lua alive)
    MOCK.saveName = "SwitchedSave"
    Events.OnInitGlobalModData.fire(true)
    local seedB = AC_WorldData.getCopperSeed()
    check(seedB ~= seedA, "OnInitGlobalModData clears the cached seed")
    local valuesB = {}
    for x = 0, 200 do valuesB[x] = AC_Geology.getCopperConcentration(x, 10) end

    MOCK.saveName = "TestSave"
    Events.OnInitGlobalModData.fire(false)
    eq(AC_WorldData.getCopperSeed(), seedA, "switching back restores the original seed")
    eq(AC_Geology.getCopperConcentration(1234, 567), c1, "original geology restored")
    local differs = false
    for x = 0, 200 do
        if AC_Geology.getCopperConcentration(x, 10) ~= valuesB[x] then differs = true break end
    end
    check(differs, "two saves produce different copper geology")

    -- Full Lua reload gives identical geology for the same save
    reloadMod()
    eq(AC_WorldData.getCopperSeed(), seedA, "seed survives a Lua reload for the same save")
    eq(AC_Geology.getCopperConcentration(1234, 567), c1, "geology survives a Lua reload")

    -- Missing save identity is handled without throwing
    local realGetWorld = getWorld
    getWorld = function() return nil end
    Events.OnInitGlobalModData.fire(true)
    eq(AC_WorldData.getGeologySeed(), nil, "no world -> nil seed, no error")
    getWorld = realGetWorld
    Events.OnInitGlobalModData.fire(false)
    eq(AC_WorldData.getCopperSeed(), seedA, "seed back after world returns")
end

section("Grades and survey")
do
    eq(AC_Geology.getGrade(0), "None", "0 -> None")
    eq(AC_Geology.getGrade(14.9), "Trace", "14.9 -> Trace")
    eq(AC_Geology.getGrade(15), "Poor", "15 -> Poor")
    eq(AC_Geology.getGrade(29.9), "Poor", "29.9 -> Poor")
    eq(AC_Geology.getGrade(30), "Moderate", "30 -> Moderate")
    eq(AC_Geology.getGrade(50), "Good", "50 -> Good")
    eq(AC_Geology.getGrade(70), "Rich", "70 -> Rich")
    eq(AC_Geology.getGrade(85), "Very Rich", "85 -> Very Rich")
    eq(AC_Geology.getGrade(100), "Very Rich", "100 -> Very Rich")

    local x, y = 300, 40
    local survey = AC_Geology.surveyArea(x, y)
    local total, peak = 0, 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local c = AC_Geology.getCopperConcentration(x + dx, y + dy)
            total = total + c
            if c > peak then peak = c end
        end
    end
    check(math.abs(survey.copperAverage - total / 9) < 1e-9, "survey average is the 3x3 mean")
    eq(survey.copperPeak, peak, "survey peak is the 3x3 maximum")
    check(survey.copperPeak >= survey.copperAverage, "peak >= average")
end

------------------------------------------------
-- RESERVES
------------------------------------------------

section("Reserves by grade and untouched tiles")
do
    MOCK.clearModData()
    eq(AC_Deposits.getReserveForConcentration(0), 0, "None -> 0")
    eq(AC_Deposits.getReserveForConcentration(10), 0, "Trace -> 0")
    eq(AC_Deposits.getReserveForConcentration(20), 1, "Poor -> 1")
    eq(AC_Deposits.getReserveForConcentration(40), 1, "Moderate -> 1")
    eq(AC_Deposits.getReserveForConcentration(60), 2, "Good -> 2")
    eq(AC_Deposits.getReserveForConcentration(75), 3, "Rich -> 3")
    eq(AC_Deposits.getReserveForConcentration(90), 4, "Very Rich -> 4")
    eq(AC_Deposits.getReserveForConcentration("abc"), 0, "non-numeric concentration -> 0")
    eq(AC_Deposits.getInitialReserve(5, 5, "gold"), 0, "unknown metal -> 0")
    eq(AC_Deposits.isMetal("copper"), true, "copper is a metal")
    eq(AC_Deposits.isMetal("Copper"), false, "metal ids are case sensitive")

    local x, y = findTile("copper", 2)
    -- Pure reads must not create persistent entries
    AC_Deposits.getRemaining(x, y, "copper")
    AC_Deposits.getExtracted(x, y, "copper")
    AC_Deposits.hasBeenWorked(x, y, "copper")
    AC_Deposits.isKnownExhausted(x, y, "copper")
    AC_Deposits.getTileInfo(x, y)
    AC_Deposits.getInitialReserve(x + 0.5, y + 0.5, "copper")
    eq(AC_Deposits.getWorkedTileCount(), 0, "reads never create save entries")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), false, "untouched tile is not worked")
    eq(AC_Deposits.isKnownExhausted(x, y, "copper"), false, "untouched tile is not known exhausted")

    AC_Deposits.markWorked(x, y, "gold")
    eq(AC_Deposits.getWorkedTileCount(), 0, "marking an unknown metal writes nothing")
    eq(AC_Deposits.recordExtraction(x, y, "gold", 1), 0, "extracting an unknown metal writes nothing")
    eq(AC_Deposits.getWorkedTileCount(), 0, "still nothing stored")
end

section("Geology rebalancing keeps extracted counts")
do
    MOCK.clearModData()
    local x, y, r = findTile("copper", 3)
    AC_Deposits.recordExtraction(x, y, "copper", 2)
    eq(AC_Deposits.getRemaining(x, y, "copper"), r - 2, "two extracted")

    local saved = AC_Deposits.CONFIG.reserveByGrade
    AC_Deposits.CONFIG.reserveByGrade = { ["None"] = 0, ["Trace"] = 0, ["Poor"] = 1, ["Moderate"] = 1, ["Good"] = 1, ["Rich"] = 1, ["Very Rich"] = 1 }
    eq(AC_Deposits.getExtracted(x, y, "copper"), 2, "extracted count untouched by rebalancing")
    eq(AC_Deposits.getRemaining(x, y, "copper"), 0, "remaining clamps at zero when reserves shrink below extracted")
    AC_Deposits.CONFIG.reserveByGrade = saved
    eq(AC_Deposits.getRemaining(x, y, "copper"), r - 2, "restored")

    local savedThreshold = AC_Geology.CONFIG.copperThreshold
    AC_Geology.CONFIG.copperThreshold = 0.99
    eq(AC_Deposits.getExtracted(x, y, "copper"), 2, "extracted count survives a geology change")
    eq(AC_Deposits.getRemaining(x, y, "copper"), 0, "remaining never negative")
    AC_Geology.CONFIG.copperThreshold = savedThreshold
end

section("Malformed ModData is tolerated")
do
    MOCK.clearModData()
    local x, y, r = findTile("copper", 2)
    local store = ModData.getOrCreate(AC_Deposits.CONFIG.modDataKey)
    store.tiles = "garbage"
    local ok = pcall(AC_Deposits.getRemaining, x, y, "copper")
    check(ok, "non-table tiles does not raise")
    eq(type(store.tiles), "table", "non-table tiles reset")

    store.tiles[x .. "," .. y] = 42
    eq(AC_Deposits.getRemaining(x, y, "copper"), r, "non-table record reads as unworked")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), false, "non-table record is not worked")
    AC_Deposits.recordExtraction(x, y, "copper", 1)
    eq(type(store.tiles[x .. "," .. y]), "table", "write replaces malformed record")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 1, "write after malformed record counts from zero")

    store.tiles[x .. "," .. y].copper = "abc"
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "non-numeric extracted reads as 0")
    eq(AC_Deposits.getRemaining(x, y, "copper"), r, "remaining from non-numeric extracted is the full reserve")

    store.tiles[x .. "," .. y].copper = -5
    check(AC_Deposits.getRemaining(x, y, "copper") <= r, "negative extracted count cannot inflate the reserve")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "negative extracted reads as 0")

    store.version = nil
    AC_Deposits.getRemaining(x, y, "copper")
    eq(store.version, 1, "version restored")
    MOCK.clearModData()
end

------------------------------------------------
-- TERRAIN
------------------------------------------------

section("Surveyable / mineable terrain")
do
    local function ok(sprite, opts, z)
        return AC_Mining.isMineableSquare(MOCK.newSquare(1, 1, z or 0, sprite, opts))
    end
    eq(ok("blends_natural_01_16"), true, "grass accepted")
    eq(ok("blends_natural_01_0"), true, "sand blend accepted")
    eq(ok("blends_natural_02_8"), true, "dark grass accepted")
    eq(ok("BLENDS_NATURAL_01_16"), true, "sprite name matching is case-insensitive")
    eq(ok("floors_exterior_natural_plowed_01"), true, "plowed land accepted")
    eq(ok("blends_street_01_16"), false, "asphalt street rejected")
    eq(ok("floors_exterior_street_01_8"), false, "concrete sidewalk rejected")
    eq(ok("carpentry_02_56"), false, "constructed wooden floor rejected")
    eq(ok("floors_interior_tiles_01_0"), false, "interior tiles rejected")
    eq(ok("floors_interior_wood_01_0"), false, "interior wood rejected")
    eq(ok(nil), false, "no floor object rejected")
    eq(ok(nil, { noSprite = true }), false, "floor without sprite rejected")
    eq(ok("blends_natural_01_16", { room = {} }), false, "square inside a room rejected")
    eq(ok("blends_natural_01_16", nil, 1), false, "z = 1 rejected")
    eq(ok("blends_natural_01_16", nil, -1), false, "basement z rejected")
    eq(ok("blends_natural_02_0", { water = true }), false, "water square rejected via hasWater")
    eq(AC_Mining.isMineableSquare(nil), false, "nil square rejected")

    -- Water detection uses hasWater() only. square:Is() does not exist on
    -- Build 42.20.4; the mock square has none, and a tripwire Is() proves
    -- it is never called.
    local isCalls = 0
    local function tripwire(sq)
        sq.Is = function()
            isCalls = isCalls + 1
            error("square:Is does not exist on 42.20.4")
        end
        return sq
    end

    local dry = MOCK.newSquare(1, 1, 0, GRASS)
    eq(dry.Is, nil, "mock square has no Is(), like 42.20.4")
    eq(AC_Geology.isWaterSquare(dry), false, "land without Is(): not water, no error")
    eq(AC_Geology.isSurveyableSquare(dry), true, "land without Is(): still surveyable")
    local wet = MOCK.newSquare(1, 1, 0, GRASS, { water = true })
    eq(AC_Geology.isWaterSquare(wet), true, "water without Is(): detected through hasWater")
    eq(AC_Geology.isSurveyableSquare(wet), false, "water without Is(): not surveyable")

    eq(AC_Geology.isWaterSquare(tripwire(MOCK.newSquare(1, 1, 0, GRASS))), false, "land: hasWater false")
    eq(AC_Geology.isSurveyableSquare(tripwire(MOCK.newSquare(1, 1, 0, GRASS))), true, "land: surveyable")
    eq(AC_Geology.isWaterSquare(tripwire(MOCK.newSquare(1, 1, 0, GRASS, { water = true }))), true, "water: hasWater true")
    eq(AC_Mining.isMineableSquare(tripwire(MOCK.newSquare(1, 1, 0, GRASS))), true, "mining check on land")

    local noMethod = tripwire(MOCK.newSquare(1, 1, 0, GRASS, { water = true }))
    noMethod.hasWater = nil
    local okNo, resultNo = pcall(AC_Geology.isWaterSquare, noMethod)
    check(okNo, "no hasWater(): no error")
    eq(resultNo, false, "no hasWater(): treated as dry, Is() not used instead")

    local throwing = tripwire(MOCK.newSquare(1, 1, 0, GRASS))
    throwing.hasWater = function() error("engine failure") end
    local okThrow, resultThrow = pcall(AC_Geology.isWaterSquare, throwing)
    check(okThrow, "hasWater() raising is contained")
    eq(resultThrow, false, "hasWater() raising -> not water")
    eq(isCalls, 0, "square:Is() never called")
    eq(AC_Geology.isWaterSquare(nil), false, "nil square is not water")

    -- Sampling and mining share the same verdict
    for _, sprite in ipairs({ "blends_natural_01_16", "blends_street_01_16", "carpentry_02_56" }) do
        local s = MOCK.newSquare(1, 1, 0, sprite)
        eq(AC_Mining.isMineableSquare(s), AC_Geology.isSurveyableSquare(s), "mining and sampling agree on " .. sprite)
    end
end

------------------------------------------------
-- PROSPECT LOOKUP
------------------------------------------------

section("Prospect lookup: coverage, overlap, rank, malformed samples")
do
    local square = MOCK.newSquare(500, 500, 0, GRASS)
    local player = MOCK.newPlayer({ square = square })

    eq(AC_Mining.findProspect(player, square, "copper"), nil, "no samples -> nil")
    eq(AC_Mining.findProspect(nil, square, "copper"), nil, "nil player -> nil")
    eq(AC_Mining.findProspect(player, nil, "copper"), nil, "nil square -> nil")
    eq(AC_Mining.findProspect(player, square, "gold"), nil, "unknown metal -> nil")

    -- Coverage boundaries around centre (500,500): |dx|<=1 and |dy|<=1
    local cases = {
        { 501, 501, true }, { 499, 499, true }, { 501, 499, true }, { 499, 501, true },
        { 502, 500, false }, { 500, 502, false }, { 498, 500, false }, { 500, 498, false },
        { 502, 502, false },
    }
    for _, c in ipairs(cases) do
        local s = makeSample(c[1], c[2], 1, "Poor", "Poor")
        eq(AC_Mining.sampleCoversSquare(s, square), c[3], "sample at " .. c[1] .. "," .. c[2] .. " covers 500,500")
    end

    local edge = makeSample(501, 499, 1, "Poor", "None")
    player.inventory:addItem(edge)
    local s, grade = AC_Mining.findProspect(player, square, "copper")
    eq(s, edge, "sample on the 3x3 edge covers")
    eq(grade, "Poor", "reported grade comes from the sample")
    eq(AC_Mining.findProspect(player, square, "zinc"), nil, "None grade gives no prospect")

    local untested = makeSample(500, 500, 0, nil, nil)
    player.inventory:addItem(untested)
    eq(AC_Mining.findProspect(player, square, "copper"), edge, "unassayed sample ignored")

    local advanced = makeSample(499, 501, 2, "Good", "Trace")
    player.inventory:addItem(advanced)
    s, grade = AC_Mining.findProspect(player, square, "copper")
    eq(s, advanced, "advanced assay preferred over field assay")
    eq(grade, "Good", "grade from the advanced sample")
    eq(AC_Mining.findProspect(player, square, "zinc"), advanced, "Trace still counts as knowledge")

    local lab = makeSample(500, 500, 3, "Moderate", "None")
    player.inventory:addItem(lab)
    s = AC_Mining.findProspect(player, square, "copper")
    eq(s, lab, "laboratory assay preferred over advanced")
    eq(AC_Mining.findProspect(player, square, "zinc"), advanced, "a lab None does not hide a lower-rank Trace (knowledge is per sample)")
    player.inventory:Remove(lab)

    advanced.modData.labProcessing = true
    eq(AC_Mining.findProspect(player, square, "copper"), edge, "lab-processing sample skipped")
    advanced.modData.labProcessing = false

    -- Malformed sample data never raises and never grants access
    local broken1 = makeSample(nil, nil, 2, "Rich", "Rich")
    local broken2 = makeSample("abc", 500, 2, "Rich", "Rich")
    local broken3 = makeSample(500, 500, "two", "Rich", "Rich")
    player.inventory:addItem(broken1)
    player.inventory:addItem(broken2)
    player.inventory:addItem(broken3)
    local okCall, result = pcall(AC_Mining.findProspect, player, square, "copper")
    check(okCall, "malformed samples do not raise")
    eq(result, advanced, "malformed samples are ignored")
    eq(AC_Mining.sampleCoversSquare(broken1, square), false, "sample without coordinates covers nothing")

    player.inventory:Remove(advanced)
    player.inventory:Remove(edge)
    eq(AC_Mining.findProspect(player, square, "copper"), nil, "removed samples no longer grant access")

    local saved = AC_Mining.CONFIG.minimumAssayRank
    player.inventory:addItem(edge)
    AC_Mining.CONFIG.minimumAssayRank = 2
    eq(AC_Mining.findProspect(player, square, "copper"), nil, "field assay below minimum rank ignored")
    AC_Mining.CONFIG.minimumAssayRank = saved
end

------------------------------------------------
-- PICKAXES
------------------------------------------------

section("Pickaxe detection and wear")
do
    local player = MOCK.newPlayer()
    eq(AC_Mining.getEquippedPickaxe(player), nil, "no pickaxe")
    eq(AC_Mining.isPickaxe(nil), false, "nil is not a pickaxe")
    player.primary = MOCK.newItem("Base.PickAxeHead")
    eq(AC_Mining.getEquippedPickaxe(player), nil, "pickaxe head is not a pickaxe")
    player.primary = MOCK.newItem("Base.Shovel")
    eq(AC_Mining.getEquippedPickaxe(player), nil, "shovel is not a pickaxe")
    local forged = MOCK.newItem("Base.PickAxeForged", { condition = 0 })
    player.primary = nil
    player.secondary = forged
    eq(AC_Mining.getEquippedPickaxe(player), forged, "forged pickaxe in secondary hand found")
    eq(AC_Mining.isUsablePickaxe(forged), false, "condition 0 unusable")
    forged.condition = 1
    eq(AC_Mining.isUsablePickaxe(forged), true, "condition 1 usable")
    local plain = MOCK.newItem("Base.PickAxe")
    player.primary = plain
    eq(AC_Mining.getEquippedPickaxe(player), plain, "primary hand preferred")

    -- Wear: exactly one roll per successful extraction, never below 0
    MOCK.clearModData()
    local x, y = findTile("copper", 4)
    local p, square, pick = miningSetup(x, y, "Very Rich", "None")
    pick.condition = 1
    MOCK.zombRandCalls = 0
    MOCK.randomSequence = { 0 } -- roll < wear chance -> wear
    local result = AC_Mining.extract(p, square, "copper", pick)
    MOCK.randomSequence = nil
    check(result ~= nil, "extraction succeeded")
    eq(MOCK.zombRandCalls, 1, "exactly one wear roll per extraction")
    eq(pick.condition, 0, "wear reduces condition by 1")
    local r, e = AC_Mining.extract(p, square, "copper", pick)
    eq(e, "no_pickaxe", "broken pickaxe refused after wear")

    pick.condition = 5
    MOCK.randomSequence = { 99 }
    AC_Mining.extract(p, square, "copper", pick)
    MOCK.randomSequence = nil
    eq(pick.condition, 5, "roll above wear chance leaves condition")
end

------------------------------------------------
-- EXTRACTION INVARIANT
------------------------------------------------

section("Extraction invariant: one action -> one ore, one decrement, one XP, one wear roll")
do
    MOCK.clearModData()
    local x, y, r = findTile("copper", 2, 2)
    local player, square, pick = miningSetup(x, y, "Good", "None")

    local action = AC_MineOreAction:new(player, square, "copper", pick)
    eq(action:isValid(), true, "action valid")
    action:start()
    action:update()
    MOCK.zombRandCalls = 0
    action:perform()
    eq(action.completed, true, "parent perform called")
    eq(#square.worldItems, 1, "exactly one ore on the square")
    eq(square.worldItems[1].fullType, "Base.CopperOre", "it is Base.CopperOre")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 1, "exactly one reserve decrement")
    eq(#player.xpLog, 1, "exactly one XP grant")
    eq(player.xpLog[1], AC_Mining.CONFIG.xpPerOre, "XP amount per ore")
    eq(MOCK.zombRandCalls, 1, "exactly one wear roll")
    eq(pick.jobDelta, 0, "job delta cleared")
    eq(player.inventory.dirty, true, "container redraw requested")

    action = AC_MineOreAction:new(player, square, "copper", pick)
    action:start()
    action:perform()
    eq(AC_Deposits.getRemaining(x, y, "copper"), 0, "tile exhausted")
    eq(AC_Deposits.isKnownExhausted(x, y, "copper"), true, "known exhausted")
    eq(#square.worldItems, 2, "two ores total")

    local snapshot = storeSnapshot()
    local xpBefore = #player.xpLog
    action = AC_MineOreAction:new(player, square, "copper", pick)
    eq(action:isValid(), false, "action on known-exhausted tile invalid")
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_ore", "direct extract refused")
    eq(#square.worldItems, 2, "no duplicate ore")
    eq(#player.xpLog, xpBefore, "no XP for failed extraction")
    check(sameSnapshot(storeSnapshot(), snapshot), "store unchanged by refused extraction on exhausted tile")
    eq(AC_Deposits.getExtracted(x, y, "copper"), r, "extracted never exceeds the initial reserve")
end

section("Copper and zinc extract independently")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1, nil, { otherMetal = "zinc", otherMin = 1 })
    local player, square, pick = miningSetup(x, y, "Good", "Good")
    local rc = AC_Deposits.getInitialReserve(x, y, "copper")
    local rz = AC_Deposits.getInitialReserve(x, y, "zinc")

    local result = AC_Mining.extract(player, square, "zinc", pick)
    check(result ~= nil, "zinc extraction succeeded")
    eq(square.worldItems[1].fullType, "AmmoMaking.ZincOre", "zinc drops AmmoMaking.ZincOre")
    eq(AC_Deposits.getRemaining(x, y, "copper"), rc, "copper reserve untouched by zinc extraction")
    eq(AC_Deposits.getRemaining(x, y, "zinc"), rz - 1, "zinc reserve decremented")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), false, "copper not marked worked")

    result = AC_Mining.extract(player, square, "copper", pick)
    check(result ~= nil, "copper extraction succeeded")
    eq(square.worldItems[2].fullType, "Base.CopperOre", "copper drops Base.CopperOre")
    eq(AC_Deposits.getRemaining(x, y, "zinc"), rz - 1, "zinc reserve untouched by copper extraction")
end

------------------------------------------------
-- CANCELLATION INVARIANT
------------------------------------------------

section("Cancellation invariant: interrupted or invalidated actions change nothing")
do
    MOCK.clearModData()
    local x, y = findTile("zinc", 2)
    local player, square, pick, sample = miningSetup(x, y, "None", "Good")
    local snapshot = storeSnapshot()

    local function assertNothingHappened(label)
        eq(#square.worldItems, 0, label .. ": no ore")
        eq(AC_Deposits.getExtracted(x, y, "zinc"), 0, label .. ": no decrement")
        eq(#player.xpLog, 0, label .. ": no XP")
        eq(pick.condition, 10, label .. ": no wear")
        check(sameSnapshot(storeSnapshot(), snapshot), label .. ": store unchanged")
    end

    -- Interrupted mid-way (walk/run/aim -> engine calls stop())
    local action = AC_MineOreAction:new(player, square, "zinc", pick)
    eq(action.stopOnWalk, true, "stopOnWalk set")
    eq(action.stopOnRun, true, "stopOnRun set")
    eq(action.stopOnAim, true, "stopOnAim set")
    action:start()
    action:update()
    action:stop()
    eq(action.stopped, true, "parent stop called")
    eq(action.completed, false, "perform never ran")
    assertNothingHappened("interrupted")

    action = AC_MineOreAction:new(player, square, "zinc", pick)
    action:start()
    player.primary = nil
    eq(action:isValid(), false, "unequipped pickaxe invalidates")
    player.primary = pick
    assertNothingHappened("pickaxe unequipped")

    MOCK.client = true
    player.inventory:Remove(pick)
    eq(action:isValid(), false, "pickaxe gone from inventory invalidates (client)")
    player.inventory:addItem(pick)
    MOCK.client = false

    pick.condition = 0
    eq(action:isValid(), false, "broken pickaxe invalidates")
    pick.condition = 10

    player.inventory:Remove(sample)
    eq(action:isValid(), false, "removing the sample invalidates")
    player.inventory:addItem(sample)

    square.spriteName = "carpentry_02_56"
    eq(action:isValid(), false, "square no longer mineable invalidates")
    square.spriteName = GRASS

    -- (a nil character never reaches the constructor: mineOre() returns first)
    eq(AC_MineOreAction:new(player, nil, "zinc", pick):isValid(), false, "nil square invalid")
    eq(AC_MineOreAction:new(player, square, nil, pick):isValid(), false, "nil metal invalid")
    eq(AC_MineOreAction:new(player, square, "zinc", nil):isValid(), false, "nil pickaxe invalid")
    assertNothingHappened("validity checks")
    eq(AC_Deposits.getWorkedTileCount(), 0, "isValid never creates save entries")
end

section("Repeated queued mining actions")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1, 1)
    local player, square, pick = miningSetup(x, y, "Poor", "None")

    -- Player spams "Mine" five times: the queue holds five actions and
    -- the engine checks isValid before starting each one.
    local actions = {}
    for i = 1, 5 do
        actions[i] = AC_MineOreAction:new(player, square, "copper", pick)
    end
    local performed = 0
    for i = 1, 5 do
        if actions[i]:isValid() then
            actions[i]:start()
            actions[i]:perform()
            performed = performed + 1
        end
    end
    eq(performed, 1, "only the first queued action runs on a reserve-1 tile")
    eq(#square.worldItems, 1, "exactly one ore")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 1, "exactly one decrement")
    eq(#player.xpLog, 1, "exactly one XP grant")
end

------------------------------------------------
-- FAILURE MODES DURING EXTRACTION
------------------------------------------------

section("Item creation failure")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1)
    local player, square, pick = miningSetup(x, y, "Good", "None")
    MOCK.knownScriptItems["Base.CopperOre"] = nil
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    MOCK.knownScriptItems["Base.CopperOre"] = true
    eq(err, "item_creation_failed", "unknown item id reported")
    eq(#square.worldItems, 0, "no ore")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "no decrement")
    eq(#player.xpLog, 0, "no XP")
    eq(pick.condition, 10, "no wear")
    eq(AC_Deposits.getWorkedTileCount(), 0, "no persistent entry")

    local realInstance = instanceItem
    instanceItem = function() error("factory exploded") end
    result, err = AC_Mining.extract(player, square, "copper", pick)
    instanceItem = realInstance
    eq(err, "item_creation_failed", "throwing factory reported, not raised")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "no decrement after factory error")

    instanceItem = nil
    result, err = AC_Mining.extract(player, square, "copper", pick)
    instanceItem = realInstance
    check(result ~= nil, "InventoryItemFactory fallback works: " .. tostring(err))
    eq(AC_Deposits.getExtracted(x, y, "copper"), 1, "fallback extraction decremented once")
end

section("World item spawn failure")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1)
    local square = MOCK.newSquare(x, y, 0, GRASS, { spawnError = "AddWorldInventoryItem exploded" })
    local player = MOCK.newPlayer({ square = square })
    local pick = equipPickaxe(player)
    player.inventory:addItem(makeSample(x, y, 1, "Good", "None"))
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "spawn_failed", "engine spawn error reported, not raised")
    eq(#square.worldItems, 0, "no ore")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "no decrement")
    eq(#player.xpLog, 0, "no XP")
    eq(pick.condition, 10, "no wear")
    eq(AC_Deposits.getWorkedTileCount(), 0, "no persistent entry")

    local action = AC_MineOreAction:new(player, square, "copper", pick)
    action:start()
    HaloTextHelper.clear()
    local okPerform = pcall(function() action:perform() end)
    check(okPerform, "perform survives spawn failure")
    eq(HaloTextHelper.last(), "Could not extract ore", "generic failure message shown")
end

section("Zero-resource tile inside an assayed area")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 0, 0)
    local player, square, pick = miningSetup(x, y, "Rich", "None", 2)
    HaloTextHelper.clear()
    local action = AC_MineOreAction:new(player, square, "copper", pick)
    eq(action:isValid(), true, "attempt allowed: the assay says Rich")
    action:start()
    action:perform()
    eq(#square.worldItems, 0, "true geology has nothing -> no ore")
    eq(#player.xpLog, 0, "no XP")
    eq(pick.condition, 10, "no wear")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "no decrement")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), true, "tile recorded as worked")
    eq(AC_Deposits.isKnownExhausted(x, y, "copper"), true, "shown as exhausted afterwards")
    eq(HaloTextHelper.last(), "No workable ore here (Copper)", "player told there is nothing")
    eq(AC_MineOreAction:new(player, square, "copper", pick):isValid(), false, "further attempts refused")
end

------------------------------------------------
-- PERSISTENCE INVARIANT
------------------------------------------------

section("Persistence invariant: only extraction changes depletion")
do
    MOCK.clearModData()
    local x, y, r = findTile("copper", 2)
    local player, square, pick, sample = miningSetup(x, y, "Good", "Good")

    fillWorldMenu(player, square)
    fillInventoryMenu(player, sample)
    AC_Mining.findProspect(player, square, "copper")
    AC_MineOreAction:new(player, square, "copper", pick):isValid()
    eq(AC_Deposits.getWorkedTileCount(), 0, "menus/lookups/validity create no entries")

    AC_Mining.extract(player, MOCK.newSquare(x, y, 0, "blends_street_01_16"), "copper", pick)
    player.inventory:Remove(sample)
    AC_Mining.extract(player, square, "copper", pick)
    player.inventory:addItem(sample)
    pick.condition = 0
    AC_Mining.extract(player, square, "copper", pick)
    pick.condition = 10
    AC_Mining.extract(player, square, "gold", pick)
    eq(AC_Deposits.getWorkedTileCount(), 0, "refused extractions create no entries")

    AC_Mining.extract(player, square, "copper", pick)
    eq(AC_Deposits.getWorkedTileCount(), 1, "one entry after one extraction")
    eq(AC_Deposits.getExtracted(x, y, "copper"), 1, "one unit recorded")
    eq(AC_Deposits.getExtracted(x, y, "zinc"), 0, "zinc untouched")

    local okSave, saveErr = pcall(MOCK.simulateSaveReload)
    check(okSave, "store only holds persistable data: " .. tostring(saveErr))
    reloadMod()
    eq(AC_Deposits.getRemaining(x, y, "copper"), r - 1, "remaining survives save/reload")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), true, "worked flag survives save/reload")
    eq(AC_Deposits.hasBeenWorked(x, y, "zinc"), false, "zinc still unworked after reload")
    eq(AC_Deposits.getWorkedTileCount(), 1, "still exactly one entry")
    eq(AC_Deposits.getInitialReserve(x, y, "copper"), r, "geology identical after reload")

    for i = 1, r do AC_Mining.extract(player, square, "copper", pick) end
    pcall(MOCK.simulateSaveReload)
    reloadMod()
    eq(AC_Deposits.isKnownExhausted(x, y, "copper"), true, "exhaustion survives reload")
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_ore", "no ore after reload of an exhausted tile")
    eq(#square.worldItems, r, "total ore equals the initial reserve")

    AC_Deposits.resetTile(x, y)
    eq(AC_Deposits.getWorkedTileCount(), 0, "reset removes the entry")
    eq(AC_Deposits.getRemaining(x, y, "copper"), r, "reserve restored")
end

section("Store keys are exact per tile")
do
    MOCK.clearModData()
    AC_Deposits.recordExtraction(10, 20, "copper", 1)
    eq(AC_Deposits.getExtracted(10, 20, "copper"), 1, "10,20 recorded")
    eq(AC_Deposits.getExtracted(20, 10, "copper"), 0, "20,10 is a different tile")
    eq(AC_Deposits.getExtracted(10.9, 20.9, "copper"), 1, "float coordinates map to the same tile")
    eq(AC_Deposits.getExtracted(102, 0, "copper"), 0, "'102,0' does not collide with '10,20'")
    local store = ModData.getOrCreate(AC_Deposits.CONFIG.modDataKey)
    eq(store.tiles["10,20"].copper, 1, "key format is 'x,y'")
    MOCK.clearModData()
end

------------------------------------------------
-- KNOWLEDGE INVARIANT
------------------------------------------------

section("Knowledge invariant: assay gates attempts, geology decides output")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 2, 2)
    local player, square, pick, sample = miningSetup(x, y, "None", "None")
    local ctx = fillWorldMenu(player, square)
    check(ctx:find("Mine Copper Ore") == nil, "assay None hides the option despite real ore")
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_prospect", "direct extraction refused without knowledge")
    eq(#square.worldItems, 0, "no ore without knowledge")

    sample.modData.copperGrade = "Poor"
    ctx = fillWorldMenu(player, square)
    check(ctx:find("Mine Copper Ore (Assay: Poor)") ~= nil, "option label shows the assay, not the geology")
    result = AC_Mining.extract(player, square, "copper", pick)
    check(result ~= nil, "extraction allowed with knowledge")
    eq(AC_Deposits.getInitialReserve(x, y, "copper"), 2, "true reserve unaffected by the assay grade")

    for _, g in ipairs({ "Trace", "Very Rich", "Good" }) do
        sample.modData.copperGrade = g
        eq(AC_Deposits.getInitialReserve(x, y, "copper"), 2, "assay '" .. g .. "' does not alter the reserve")
    end
end

------------------------------------------------
-- HIDDEN INFORMATION INVARIANT
------------------------------------------------

section("Hidden information invariant: normal UI reveals no exact geology")
do
    MOCK.clearModData()
    MOCK.debug = false
    local x, y = findTile("copper", 3)
    local player, square, pick = miningSetup(x, y, "Rich", "Poor", 1)

    local ctx = fillWorldMenu(player, square)
    for _, name in ipairs(ctx:names()) do
        check(not hasDigit(name), "menu label without numbers: " .. name)
        check(not string.find(name, "Debug", 1, true), "no debug entry in normal mode: " .. name)
    end

    HaloTextHelper.clear()
    local action = AC_MineOreAction:new(player, square, "copper", pick)
    action:start()
    action:perform()
    check(not hasDigit(HaloTextHelper.last()), "extraction message without numbers: " .. tostring(HaloTextHelper.last()))

    for i = 1, 3 do AC_Mining.extract(player, square, "copper", pick) end
    ctx = fillWorldMenu(player, square)
    local exhausted = ctx:find("Mine Copper Ore (Exhausted)")
    check(exhausted ~= nil and not hasDigit(exhausted.name), "exhausted label without numbers")

    local sample = makeSample(x, y, 1, "Rich", "Poor")
    sample.modData.trueCopper = 77.7
    local leaked = false
    for _, line in ipairs(AC_GeologySampling.getResultLines(sample)) do
        if string.find(line, "77", 1, true) then leaked = true end
    end
    check(not leaked, "field assay lines do not contain the true concentration")

    local ex, ey = findTile("copper", 0, 0)
    local p2, s2 = miningSetup(ex, ey, "Good", "None")
    ctx = fillWorldMenu(p2, s2)
    check(ctx:find("Mine Copper Ore (Assay: Good)") ~= nil, "unworked empty tile still offers the attempt")
    check(ctx:find("Mine Copper Ore (Exhausted)") == nil, "unworked empty tile is not labelled exhausted")
end

------------------------------------------------
-- MULTIPLAYER GUARD
------------------------------------------------

section("Multiplayer client guard")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1)
    local player, square, pick = miningSetup(x, y, "Poor", "None")
    MOCK.client = true

    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "multiplayer_unsupported", "client-side extraction refused")
    eq(#square.worldItems, 0, "no ore on a multiplayer client")
    eq(AC_Deposits.getWorkedTileCount(), 0, "no depletion recorded on a multiplayer client")

    local ctx = fillWorldMenu(player, square)
    local opt = ctx:find("Mine Ore")
    check(opt ~= nil and opt.notAvailable == true, "disabled explanatory option shown")
    check(ctx:find("Mine Copper Ore") == nil, "no live mining option")

    local action = AC_MineOreAction:new(player, square, "copper", pick)
    action:start()
    HaloTextHelper.clear()
    action:perform()
    eq(#square.worldItems, 0, "timed action produces nothing on a client")
    eq(HaloTextHelper.last(), "Ore extraction is not available in multiplayer yet", "client told why")
    MOCK.client = false
end

------------------------------------------------
-- CONTEXT MENU
------------------------------------------------

section("Mining context menu states")
do
    MOCK.clearModData()
    MOCK.debug = false
    local x, y = findTile("copper", 1)
    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square })

    local ctx = fillWorldMenu(player, square)
    eq(#ctx.options, 0, "no options without a sample")

    player.inventory:addItem(makeSample(x, y, 1, "Poor", "None"))
    ctx = fillWorldMenu(player, square)
    local opt = ctx:find("Mine Copper Ore")
    check(opt ~= nil, "copper option offered with sample")
    check(ctx:find("Mine Zinc Ore") == nil, "no zinc option when assay says None")
    eq(opt and opt.notAvailable, true, "option disabled without a pickaxe")
    check(opt and opt.toolTip ~= nil, "disabled option has a tooltip")

    local pick = equipPickaxe(player, "Base.PickAxe", 0)
    ctx = fillWorldMenu(player, square)
    opt = ctx:find("Mine Copper Ore")
    eq(opt and opt.notAvailable, true, "option disabled with a broken pickaxe")

    pick.condition = 10
    ctx = fillWorldMenu(player, square)
    opt = ctx:find("Mine Copper Ore")
    check(opt and opt.notAvailable == nil, "option enabled with usable pickaxe")
    ISTimedActionQueue.clear()
    ctx:invoke(opt)
    eq(#ISTimedActionQueue.queue, 1, "selecting the option queues one action")
    eq(ISTimedActionQueue.queue[1].Type, "AC_MineOreAction", "queued action type")

    MOCK.walkAdjResult = false
    ISTimedActionQueue.clear()
    HaloTextHelper.clear()
    ctx:invoke(opt)
    eq(#ISTimedActionQueue.queue, 0, "unreachable square queues nothing")
    eq(HaloTextHelper.last(), "Cannot reach mining location", "player told the square is unreachable")
    MOCK.walkAdjResult = true

    pick.condition = 0
    ISTimedActionQueue.clear()
    ctx:invoke(opt)
    eq(#ISTimedActionQueue.queue, 0, "stale option with broken pickaxe queues nothing")
    pick.condition = 10

    local far = MOCK.newSquare(x + 2, y, 0, GRASS)
    ctx = fillWorldMenu(player, far)
    eq(#ctx.options, 0, "no options two tiles from the sample centre")

    ctx = fillWorldMenu(player, MOCK.newSquare(x, y, 0, "blends_street_01_16"))
    eq(#ctx.options, 0, "no options on asphalt")
    ctx = fillWorldMenu(player, MOCK.newSquare(x, y, 0, GRASS, { room = {} }))
    eq(#ctx.options, 0, "no options indoors")
    ctx = fillWorldMenu(player, MOCK.newSquare(x, y, 0, GRASS, { water = true }))
    eq(#ctx.options, 0, "no options on water")

    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjectsFor(square), true)
    eq(#ctx.options, 0, "test flag adds nothing")
    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, {}, false)
    eq(#ctx.options, 0, "no world objects adds nothing")
    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, nil, false)
    eq(#ctx.options, 0, "nil world objects adds nothing")

    AC_Deposits.recordExtraction(x, y, "copper", 99)
    ctx = fillWorldMenu(player, square)
    opt = ctx:find("Mine Copper Ore (Exhausted)")
    check(opt ~= nil and opt.notAvailable == true, "exhausted tile shown as disabled")
end

------------------------------------------------
-- SAMPLING AND ASSAY
------------------------------------------------

section("Geological sampling")
do
    MOCK.clearModData()
    local x, y = 700, 30
    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square })

    local s, err = AC_GeologySampling.createSample(player, square, nil)
    eq(err, "no_shovel", "no shovel refused")
    local shovel = equipShovel(player, 10)
    s, err = AC_GeologySampling.createSample(player, MOCK.newSquare(x, y, 0, "blends_street_01_16"), shovel)
    eq(err, "invalid_surface", "asphalt refused")
    s, err = AC_GeologySampling.createSample(player, MOCK.newSquare(x, y, 0, GRASS, { water = true }), shovel)
    eq(err, "invalid_surface", "water refused")
    s, err = AC_GeologySampling.createSample(player, MOCK.newSquare(x, y, 0, GRASS, { room = {} }), shovel)
    eq(err, "invalid_surface", "indoors refused")

    MOCK.zombRandCalls = 0
    s, err = AC_GeologySampling.createSample(player, square, shovel)
    check(s ~= nil, "sample created: " .. tostring(err))
    eq(MOCK.zombRandCalls, 1, "exactly one shovel wear roll")
    local d = s.modData
    eq(d.sampleX, x, "sampleX stored")
    eq(d.sampleY, y, "sampleY stored")
    eq(d.assayRank, 0, "new sample is unassayed")
    eq(d.copperGrade, nil, "no grade before assay")
    local survey = AC_Geology.surveyArea(x, y)
    eq(d.trueCopper, survey.copperAverage, "true copper average stored on the item")
    eq(d.trueCopperPeak, survey.copperPeak, "true copper peak stored on the item")
    eq(d.labProcessing, false, "labProcessing initialised false")
    eq(s.name, "Geological Sample", "item named")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "sample in inventory")

    MOCK.knownScriptItems["AmmoMaking.GeologicalSample"] = nil
    s, err = AC_GeologySampling.createSample(player, square, shovel)
    MOCK.knownScriptItems["AmmoMaking.GeologicalSample"] = true
    eq(err, "item_creation_failed", "missing sample item reported")

    player.inventory.items = {}
    equipShovel(player, 10)
    local ctx = fillWorldMenu(player, square)
    check(ctx:find("Dig Geological Sample") ~= nil, "dig option with shovel on grass")
    local digEntries = 0
    for _, name in ipairs(ctx:names()) do
        if name == "Dig Geological Sample" then digEntries = digEntries + 1 end
    end
    eq(digEntries, 1, "exactly one dig entry per right-click")
    ctx = fillWorldMenu(player, MOCK.newSquare(x, y, 0, GRASS, { water = true }))
    check(ctx:find("Dig Geological Sample") == nil, "no dig option on water")
    player.primary = nil
    ctx = fillWorldMenu(player, square)
    check(ctx:find("Dig Geological Sample") == nil, "no dig option without shovel")
end

section("Dig action flow")
do
    local x, y = 720, 30
    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square })
    local shovel = equipShovel(player, 10)

    local action = AC_DigGeologicalSampleAction:new(player, square, shovel)
    eq(action:getDuration(), AC_GeologySampling.CONFIG.digActionTime, "duration from CONFIG")
    eq(action:isValid(), true, "valid with shovel")
    action:start()
    action:update()
    action:stop()
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 0, "interrupted dig gives no sample")

    action = AC_DigGeologicalSampleAction:new(player, square, shovel)
    action:start()
    action:perform()
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "completed dig gives exactly one sample")

    shovel.condition = 0
    eq(AC_DigGeologicalSampleAction:new(player, square, shovel):isValid(), false, "broken shovel invalid")
    shovel.condition = 10
    square.room = {}
    eq(AC_DigGeologicalSampleAction:new(player, square, shovel):isValid(), false, "indoors invalid")
    square.room = nil
end

section("Portable assays: kit uses and XP exactly once")
do
    local player = MOCK.newPlayer()
    local sample = makeSample(700, 30, 0, nil, nil)
    sample.modData.trueCopper = 55
    sample.modData.trueZinc = 0
    player.inventory:addItem(sample)

    local ctx = fillInventoryMenu(player, sample)
    check(ctx:find("Analyze with Field Assay Kit") == nil, "no analyze option without a kit")
    check(ctx:find("View Assay Result") == nil, "no view option before assay")

    local fieldKit = player.inventory:AddItem("AmmoMaking.FieldAssayKit")
    ctx = fillInventoryMenu(player, sample)
    local opt = ctx:find("Analyze with Field Assay Kit")
    check(opt ~= nil, "field analyze option with a kit")
    eq(fieldKit.name, "Field Assay Kit (20/20)", "kit name initialised with uses")

    ctx:invoke(opt)
    eq(sample.modData.assayRank, 1, "field assay applied")
    check(sample.modData.copperGrade ~= nil, "copper grade set")
    eq(#player.xpLog, 1, "XP granted once")
    eq(player.xpLog[1], AC_GeologySampling.CONFIG.fieldAssayXP, "field assay XP amount")
    eq(AC_GeologySampling.getKitUses(fieldKit), 19, "one kit use consumed")
    eq(sample.name, "Tested Geological Sample", "sample renamed")

    local okAgain, errAgain = AC_GeologySampling.analyzeSample(sample, fieldKit)
    eq(errAgain, "already_analyzed", "re-analysis at the same rank refused")
    eq(#player.xpLog, 1, "no second XP")
    eq(AC_GeologySampling.getKitUses(fieldKit), 19, "no kit use on refusal")
    ctx = fillInventoryMenu(player, sample)
    check(ctx:find("Analyze with Field Assay Kit") == nil, "field option gone after field assay")
    check(ctx:find("View Assay Result") ~= nil, "view option after assay")

    local advKit = player.inventory:AddItem("AmmoMaking.AdvancedFieldAssayKit")
    ctx = fillInventoryMenu(player, sample)
    opt = ctx:find("Re-analyze with Advanced Field Assay Kit")
    check(opt ~= nil, "re-analyze option offered")
    ctx:invoke(opt)
    eq(sample.modData.assayRank, 2, "advanced assay applied")
    check(sample.modData.copperMin ~= nil and sample.modData.copperMax ~= nil, "range stored")
    check(sample.modData.copperMax - sample.modData.copperMin <= 2 * AC_GeologySampling.CONFIG.advancedRangeHalfWidth, "range width bounded")
    eq(#player.xpLog, 2, "XP granted once more for the better assay")
    eq(player.xpLog[2], AC_GeologySampling.CONFIG.advancedAssayXP, "advanced XP amount")
    eq(AC_GeologySampling.getKitUses(advKit), 9, "advanced kit use consumed")

    local center = (sample.modData.copperMin + sample.modData.copperMax) / 2
    check(math.abs(center - 55) <= AC_GeologySampling.CONFIG.advancedMeasurementError + 1, "advanced centre within error of the truth")

    advKit.modData.assayUsesRemaining = 0
    local sample2 = makeSample(700, 30, 0, nil, nil)
    player.inventory:addItem(sample2)
    local okEmpty, errEmpty = AC_GeologySampling.analyzeSample(sample2, advKit)
    eq(errEmpty, "kit_empty", "empty kit refused")
    ctx = fillInventoryMenu(player, sample2)
    check(ctx:find("Analyze with Advanced Field Assay Kit") == nil, "empty kit not offered")

    eq(select(2, AC_GeologySampling.analyzeSample(nil, fieldKit)), "invalid_sample", "nil sample")
    eq(select(2, AC_GeologySampling.analyzeSample(sample2, MOCK.newItem("Base.Shovel"))), "invalid_kit", "non-kit item")
    sample2.modData.labProcessing = true
    eq(select(2, AC_GeologySampling.analyzeSample(sample2, fieldKit)), "lab_processing", "lab-processing sample refused")
    sample2.modData.labProcessing = false

    local lines = AC_GeologySampling.getResultLines(sample)
    eq(lines[2], "Analysis: Advanced Field Assay", "advanced result header")
    check(string.find(lines[3], "^Copper: %d+%-%d+%% %(") ~= nil, "advanced copper line format: " .. lines[3])
    local fresh = makeSample(1, 1, 0, nil, nil)
    eq(AC_GeologySampling.getResultLines(fresh)[2], "Status: Untested", "untested line")
    eq(AC_GeologySampling.getResultLines(MOCK.newItem("Base.Shovel")), nil, "non-sample -> nil lines")
end

section("Laboratory analyzer flow and XP once")
do
    local x, y = 740, 30
    local powered = MOCK.newSquare(x, y, 0, "floors_interior_tiles_01_0", { room = {} })
    powered.haveElectricity = function() return true end
    local analyzerItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local analyzerObject = { __class = "IsoWorldInventoryObject", getItem = function() return analyzerItem end, getSquare = function() return powered end }
    local player = MOCK.newPlayer({ square = powered })
    local sample = makeSample(x, y, 2, "Good", "None")
    sample.modData.trueCopper = 60
    sample.modData.trueZinc = 5
    player.inventory:addItem(sample)
    MOCK.worldHours = 100

    MOCK.players = { player }
    local ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { analyzerObject }, false)
    local start = ctx:find("Start Lab Assay: Sample " .. x .. ", " .. y)
    check(start ~= nil, "start option lists the carried sample")
    ctx:invoke(start)
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 0, "sample moved into the analyzer")
    eq(analyzerItem.modData.labAnalyzerState, "processing", "analyzer processing")
    eq(#player.xpLog, 0, "no XP at start")

    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { analyzerObject }, false)
    check(ctx:find("Check Laboratory Progress") ~= nil, "progress option while processing")
    check(ctx:find("Collect Laboratory Sample") == nil, "no collect option while processing")

    powered.haveElectricity = function() return false end
    MOCK.worldHours = 130
    eq(AC_LaboratoryAnalyzer.getState(analyzerObject), "processing", "still processing after unpowered hours")
    powered.haveElectricity = function() return true end
    MOCK.worldHours = 154
    eq(AC_LaboratoryAnalyzer.getState(analyzerObject), "ready", "ready after 24 powered hours")

    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { analyzerObject }, false)
    local collect = ctx:find("Collect Laboratory Sample")
    check(collect ~= nil, "collect option when ready")
    ctx:invoke(collect)
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "sample returned")
    local returned = player.inventory:getItemsFromFullType("AmmoMaking.GeologicalSample"):get(0)
    eq(returned.modData.assayRank, 3, "laboratory rank")
    eq(returned.modData.sampleX, x, "sample location preserved")
    check(math.abs(returned.modData.labCopperResult - 60) <= AC_LaboratoryAnalyzer.CONFIG.measurementError, "lab result within tolerance")
    eq(#player.xpLog, 1, "XP granted exactly once on collection")
    eq(player.xpLog[1], AC_LaboratoryAnalyzer.CONFIG.assayXP, "lab XP amount")
    eq(analyzerItem.modData.labAnalyzerState, "idle", "analyzer idle again")

    local again, errAgain = AC_LaboratoryAnalyzer.collectSample(player, analyzerObject)
    eq(errAgain, "empty", "second collect refused")
    eq(#player.xpLog, 1, "no second XP")
    eq(AC_LaboratoryAnalyzer.canAnalyzeSample(returned), false, "lab sample cannot be re-analysed")

    local square = MOCK.newSquare(x, y, 0, GRASS)
    local p2 = MOCK.newPlayer({ square = square })
    p2.inventory:addItem(returned)
    eq(AC_Mining.findProspect(p2, square, "copper"), returned, "laboratory sample is a valid prospect")
    MOCK.worldHours = 0
end

section("Placed laboratory analyzer: detection and flow on object ModData")
do
    -- Lua state machine only; the object is a mock (see placeAnalyzerObject).
    local x, y = 760, 30
    local powered = poweredLabSquare(x, y)
    local analyzer = placeAnalyzerObject(powered)

    check(AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(analyzer), "placed analyzer recognised by its ModData flag")
    check(AC_LaboratoryAnalyzer.isAnalyzerWorldObject(analyzer), "placed analyzer is an analyzer world object")
    check(not AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(analyzer), "placed analyzer is not a dropped item")
    eq(AC_LaboratoryAnalyzer.getAnalyzerItem(analyzer), nil, "placed analyzer has no item")

    local wall = MOCK.newWorldObject({ name = "wall" })
    check(not AC_LaboratoryAnalyzer.isAnalyzerWorldObject(wall), "ordinary object is not an analyzer")
    eq(wall:hasModData(), false, "checking an ordinary object creates no ModData on it")
    check(not AC_LaboratoryAnalyzer.isAnalyzerWorldObject({ getSquare = function() return powered end }), "plain table is not an analyzer")

    local nameOnly = MOCK.newWorldObject({ class = "IsoThumpable", name = AC_LaboratoryAnalyzer.OBJECT_NAME })
    check(AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(nameOnly), "object name is a fallback when the ModData flag is missing")

    local droppedItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local dropped = { __class = "IsoWorldInventoryObject", getItem = function() return droppedItem end, getSquare = function() return powered end }
    check(AC_LaboratoryAnalyzer.isLegacyDroppedAnalyzer(dropped), "dropped analyzer still recognised")
    check(not AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(dropped), "dropped analyzer is not a placed object")

    local player = MOCK.newPlayer({ square = powered })
    local sample = makeSample(x, y, 1, "Poor", "None")
    sample.modData.trueCopper = 30
    sample.modData.trueZinc = 0
    player.inventory:addItem(sample)
    MOCK.worldHours = 200

    local ctx = fillAnalyzerMenu(player, analyzer)
    local start = ctx:find("Start Lab Assay: Sample " .. x .. ", " .. y)
    check(start ~= nil, "start option on a placed analyzer")
    ctx:invoke(start)
    eq(analyzer.modData.labAnalyzerState, "processing", "state stored on the object")
    eq(analyzer.modData.stored_sampleX, x, "sample stored on the object")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 0, "sample moved into the placed analyzer")
    eq(#player.xpLog, 0, "no XP at start")

    local ok2, err2 = AC_LaboratoryAnalyzer.startAssay(player, analyzer, makeSample(x, y, 0))
    eq(ok2, false, "second start refused")
    eq(err2, "busy", "busy while processing")

    MOCK.worldHours = 224
    eq(AC_LaboratoryAnalyzer.getState(analyzer), "ready", "placed analyzer completes after 24 powered hours")

    ctx = fillAnalyzerMenu(player, analyzer)
    local collect = ctx:find("Collect Laboratory Sample")
    check(collect ~= nil, "collect option on a ready placed analyzer")
    if collect then ctx:invoke(collect) end
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "sample returned from the placed analyzer")
    eq(#player.xpLog, 1, "XP once on collection")
    eq(player.xpLog[1], AC_LaboratoryAnalyzer.CONFIG.assayXP, "lab XP amount")
    eq(analyzer.modData.labAnalyzerState, "idle", "placed analyzer idle again")
    eq(analyzer.modData.stored_sampleX, nil, "stored sample cleared from the object")
    eq(select(2, AC_LaboratoryAnalyzer.collectSample(player, analyzer)), "empty", "second collection refused")
    eq(#player.xpLog, 1, "still one XP grant")
    MOCK.worldHours = 0
end

section("Malformed laboratory analyzer ModData")
do
    local x, y = 780, 30
    local square = poweredLabSquare(x, y)
    local player = MOCK.newPlayer({ square = square })
    MOCK.worldHours = 50

    local function analyzerWith(fields)
        local a = placeAnalyzerObject(square)
        for k, v in pairs(fields) do a.modData[k] = v end
        return a
    end

    local function withStoredSample(fields)
        fields.storedSample = true
        fields.stored_sampleX = x
        fields.stored_sampleY = y
        fields.stored_trueCopper = 70
        fields.stored_trueZinc = 10
        fields.stored_assayRank = 1
        return fields
    end

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    local a = analyzerWith({ labAnalyzerState = "banana", labRemainingHours = 3 })
    local okA, infoA = pcall(AC_LaboratoryAnalyzer.getStatusInfo, a)
    check(okA, "unknown state does not raise")
    eq(okA and infoA.state, "idle", "unknown state without a sample -> idle")
    eq(a.modData.labRemainingHours, nil, "stale timer cleared")

    local b = analyzerWith(withStoredSample({ labAnalyzerState = 42 }))
    eq(AC_LaboratoryAnalyzer.getState(b), "processing", "unknown state with a sample -> processing")
    check(tonumber(b.modData.labCopperResult) ~= nil, "missing results rolled")

    local c = analyzerWith(withStoredSample({ labAnalyzerState = "idle", labCopperResult = 71, labZincResult = 9 }))
    eq(AC_LaboratoryAnalyzer.getState(c), "processing", "idle with a stored sample -> processing, sample kept")
    eq(select(2, AC_LaboratoryAnalyzer.startAssay(player, c, makeSample(x, y, 0))), "busy", "stored sample is not overwritten by a new start")
    eq(c.modData.stored_trueCopper, 70, "stored sample intact")

    local d = analyzerWith({ labAnalyzerState = "ready", labCopperResult = 50 })
    eq(AC_LaboratoryAnalyzer.getState(d), "idle", "ready without a sample -> idle (not stuck)")
    local freshSample = makeSample(x, y, 0)
    freshSample.modData.trueCopper = 20
    freshSample.modData.trueZinc = 0
    player.inventory:addItem(freshSample)
    eq(AC_LaboratoryAnalyzer.startAssay(player, d, freshSample), true, "repaired analyzer accepts a new sample")

    local e = analyzerWith(withStoredSample({ labAnalyzerState = "processing", labRemainingHours = "soon", labReadyAt = {}, labLastUpdateAt = "x", labCopperResult = 70, labZincResult = 10 }))
    local okE, stateE = pcall(AC_LaboratoryAnalyzer.getState, e)
    check(okE, "non-numeric timers do not raise: " .. tostring(stateE))
    eq(stateE, "processing", "still processing after timer repair")
    eq(e.modData.labRemainingHours, AC_LaboratoryAnalyzer.CONFIG.processingHours, "remaining time rebuilt from CONFIG")
    MOCK.worldHours = 50 + AC_LaboratoryAnalyzer.CONFIG.processingHours
    eq(AC_LaboratoryAnalyzer.getState(e), "ready", "repaired analyzer still completes")

    local f = analyzerWith(withStoredSample({ labAnalyzerState = "ready" }))
    local sampleF = AC_LaboratoryAnalyzer.collectSample(player, f)
    check(sampleF ~= nil, "ready sample without results can be collected")
    check(sampleF and math.abs(sampleF.modData.labCopperResult - 70) <= AC_LaboratoryAnalyzer.CONFIG.measurementError, "result rolled from the stored truth, not 0")

    MOCK.capturePrint(false)
    check(MOCK.printLogContains("WARNING: laboratory analyzer state repaired (banana -> idle)"), "repair is logged")

    local droppedItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    droppedItem.modData.labAnalyzerState = "???"
    local dropped = { __class = "IsoWorldInventoryObject", getItem = function() return droppedItem end, getSquare = function() return square end }
    MOCK.capturePrint(true)
    eq(AC_LaboratoryAnalyzer.getState(dropped), "idle", "dropped analyzer data repaired the same way")
    MOCK.capturePrint(false)
    MOCK.worldHours = 0
end

section("Laboratory analyzer: pick-up rule, cancel, placement state")
do
    local x, y = 800, 30
    local square = poweredLabSquare(x, y)
    local player = MOCK.newPlayer({ square = square })
    MOCK.worldHours = 300
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    local function carriedSample(rank)
        local s = makeSample(x, y, rank, rank > 0 and "Good" or nil, rank > 0 and "Trace" or nil)
        s.modData.trueCopper = 64
        s.modData.trueZinc = 6
        player.inventory:addItem(s)
        return s
    end

    -- Pick-up rule
    local analyzer = placeAnalyzerObject(square)
    eq(AC_LaboratoryAnalyzer.canPickUp(analyzer), true, "idle empty analyzer can be picked up")
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, carriedSample(1))
    local okP, whyP = AC_LaboratoryAnalyzer.canPickUp(analyzer)
    eq(okP, false, "processing analyzer cannot be picked up")
    eq(whyP, "processing", "reason: processing")
    MOCK.worldHours = 300 + AC_LaboratoryAnalyzer.CONFIG.processingHours
    local okR, whyR = AC_LaboratoryAnalyzer.canPickUp(analyzer)
    eq(okR, false, "ready analyzer cannot be picked up")
    eq(whyR, "ready", "reason: ready")
    AC_LaboratoryAnalyzer.collectSample(player, analyzer)
    eq(AC_LaboratoryAnalyzer.canPickUp(analyzer), true, "pick-up allowed again once collected")
    local droppedItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local dropped = { __class = "IsoWorldInventoryObject", getItem = function() return droppedItem end, getSquare = function() return square end }
    eq(select(2, AC_LaboratoryAnalyzer.canPickUp(dropped)), "invalid_analyzer", "rule only applies to placed analyzers")
    eq(select(2, AC_LaboratoryAnalyzer.canPickUp(MOCK.newWorldObject())), "invalid_analyzer", "ordinary object refused")

    -- Cancel
    player.inventory.items = {}
    player.xpLog = {}
    local s1 = carriedSample(1)
    local copperGrade = s1.modData.copperGrade
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, s1)
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 0, "sample inside before cancel")
    local back, errC = AC_LaboratoryAnalyzer.cancelAssay(player, analyzer)
    check(back ~= nil, "cancel returns the sample: " .. tostring(errC))
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "exactly one sample back")
    eq(back.modData.assayRank, 1, "original assay rank kept")
    eq(back.modData.copperGrade, copperGrade, "original grade kept")
    eq(back.modData.sampleX, x, "sample location kept")
    eq(back.modData.trueCopper, 64, "hidden geology kept")
    eq(back.modData.labCopperResult, nil, "no laboratory result on a cancelled sample")
    eq(back.modData.labProcessing, false, "not flagged as processing")
    eq(back.name, "Tested Geological Sample", "tested sample name restored")
    eq(#player.xpLog, 0, "no XP for a cancelled assay")
    eq(AC_LaboratoryAnalyzer.getState(analyzer), "idle", "analyzer idle after cancel")
    eq(analyzer.modData.stored_sampleX, nil, "stored sample cleared")
    eq(select(2, AC_LaboratoryAnalyzer.cancelAssay(player, analyzer)), "not_processing", "second cancel refused")
    eq(select(2, AC_LaboratoryAnalyzer.collectSample(player, analyzer)), "empty", "nothing to collect after cancel")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "no duplicate sample")
    eq(AC_LaboratoryAnalyzer.canPickUp(analyzer), true, "cancel makes the analyzer movable")

    AC_LaboratoryAnalyzer.startAssay(player, analyzer, back)
    MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours
    eq(select(2, AC_LaboratoryAnalyzer.cancelAssay(player, analyzer)), "not_processing", "finished assay is not cancellable")
    check(AC_LaboratoryAnalyzer.collectSample(player, analyzer) ~= nil, "finished assay still collectable")

    local raw = carriedSample(0)
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, raw)
    local rawBack = AC_LaboratoryAnalyzer.cancelAssay(player, analyzer)
    eq(rawBack and rawBack.modData.assayRank, 0, "untested sample comes back untested")
    eq(rawBack and rawBack.name, "Geological Sample", "untested sample name restored")

    -- State carried by an item into a newly placed analyzer
    local fresh = AC_LaboratoryAnalyzer.initializePlacedData({}, MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer").modData)
    eq(fresh.labAnalyzerState, "idle", "fresh item places an idle analyzer")
    eq(fresh.AmmoMakingLaboratoryAnalyzerWorldObject, true, "placed-object flag written")
    eq(AC_LaboratoryAnalyzer.initializePlacedData({}, nil).labAnalyzerState, "idle", "no item data -> idle")

    local busyItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local droppedBusy = { __class = "IsoWorldInventoryObject", getItem = function() return busyItem end, getSquare = function() return square end }
    MOCK.worldHours = 1000
    AC_LaboratoryAnalyzer.startAssay(player, droppedBusy, carriedSample(2))
    MOCK.worldHours = 1010
    AC_LaboratoryAnalyzer.getState(droppedBusy)                       -- 10 powered hours on the floor
    MOCK.worldHours = 1500                                            -- then carried around for a long time
    local placed = placeAnalyzerObject(square)
    AC_LaboratoryAnalyzer.initializePlacedData(placed.modData, busyItem.modData)
    eq(placed.modData.labAnalyzerState, "processing", "running assay carried onto the placed analyzer")
    eq(placed.modData.stored_sampleX, x, "stored sample carried")
    eq(placed.modData.labLastUpdateAt, 1500, "clock restarts at placement")
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(placed), AC_LaboratoryAnalyzer.CONFIG.processingHours - 10, "inventory time not counted")
    MOCK.worldHours = 1500 + AC_LaboratoryAnalyzer.CONFIG.processingHours - 10
    eq(AC_LaboratoryAnalyzer.getState(placed), "ready", "carried assay completes")
    local carried = AC_LaboratoryAnalyzer.collectSample(player, placed)
    check(carried and math.abs(carried.modData.labCopperResult - 64) <= AC_LaboratoryAnalyzer.CONFIG.measurementError, "carried result valid")

    local brokenItemData = { labAnalyzerState = "processing" }            -- no stored sample
    eq(AC_LaboratoryAnalyzer.initializePlacedData({}, brokenItemData).labAnalyzerState, "idle", "malformed item state repaired on placement")

    -- Save / reload representation (value types only; engine persistence is not tested)
    local saved = placeAnalyzerObject(square)
    MOCK.worldHours = 2000
    AC_LaboratoryAnalyzer.startAssay(player, saved, carriedSample(1))
    local okCopy, copy = pcall(MOCK.persistCopy, saved.modData, "analyzer")
    check(okCopy, "analyzer ModData holds only persistable values: " .. tostring(copy))
    local reloaded = MOCK.newWorldObject({ class = "IsoThumpable", modData = copy })
    square:AddSpecialObject(reloaded)
    eq(AC_LaboratoryAnalyzer.getState(reloaded), "processing", "copied state still processing")
    MOCK.worldHours = 2000 + AC_LaboratoryAnalyzer.CONFIG.processingHours
    local fromCopy = AC_LaboratoryAnalyzer.collectSample(player, reloaded)
    check(fromCopy ~= nil and fromCopy.modData.sampleX == x, "copied state yields the stored sample")
    eq(fromCopy and fromCopy.modData.labCopperResult, saved.modData.labCopperResult, "result rolled at start survives the copy")

    -- Multiplayer guard
    MOCK.client = true
    eq(AC_LaboratoryAnalyzer.isPlacementAvailable(), false, "place/pick up disabled on a multiplayer client")
    MOCK.client = false
    eq(AC_LaboratoryAnalyzer.isPlacementAvailable(), true, "place/pick up available in single-player")

    MOCK.capturePrint(false)
    MOCK.worldHours = 0
end

section("Analyzer placement cursor (mocked ISBuildingObject / IsoThumpable)")
do
    -- Walking, ISBuildAction, ghost rendering and the real IsoThumpable
    -- are mocked: these checks cover create() / isValid() control flow
    -- only. Everything else needs the in-game test.
    local x, y = 820, 30
    local square = MOCK.registerSquare(poweredLabSquare(x, y))
    local player = MOCK.newPlayer({ square = square, playerNum = 0 })
    local item = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
    MOCK.worldHours = 400

    local cursor = AC_LaboratoryAnalyzerObject:new(player, item)
    eq(cursor.sprite, AC_LaboratoryAnalyzer.CONFIG.worldSprite, "cursor sprite from CONFIG")
    eq(cursor.northSprite, AC_LaboratoryAnalyzer.CONFIG.worldSprite, "same sprite facing north")
    eq(cursor.player, 0, "player number stored")
    eq(cursor.noNeedHammer, true, "no hammer needed")
    eq(cursor.dragNilAfterPlace, true, "cursor ends after one placement")
    eq(cursor.ignoreNorth, true, "one thumpable per tile")
    eq(cursor.maxTime, AC_LaboratoryAnalyzer.CONFIG.placeActionTime, "placement time from CONFIG")
    check(cursor.maxTime > 50, "placement time survives the Handy trait's -50")

    eq(cursor:isValid(square), true, "valid with the item carried")
    eq(cursor:isValid(nil), false, "no square -> invalid")
    MOCK.buildingObjectValid = false
    eq(cursor:isValid(square), false, "vanilla checks can refuse")
    MOCK.buildingObjectValid = true
    eq(AC_LaboratoryAnalyzerObject:new(player, player.inventory:AddItem("Base.Shovel")):isValid(square), false, "only the analyzer item can be placed")

    player.primary = item
    MOCK.capturePrint(true)
    cursor:create(x, y, 0, false, cursor.sprite)
    MOCK.capturePrint(false)
    local placed = square.specialObjects[1]
    check(placed ~= nil, "analyzer object added to the square")
    eq(#square.specialObjects, 1, "exactly one object added")
    check(AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(placed), "created object is a placed analyzer")
    eq(placed and placed.name, AC_LaboratoryAnalyzer.OBJECT_NAME, "object name set")
    eq(placed and placed.isThumpable, false, "zombies cannot thump it")
    eq(placed and placed.dismantable, false, "not handed to vanilla dismantle / move handling")
    eq(placed and placed.canBarricade, false, "not barricadable")
    eq(placed and placed.transmitted, 1, "object transmitted once")
    eq(placed and placed.modData.labAnalyzerState, "idle", "new analyzer idle")
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 0, "item consumed")
    eq(player.inventory.removeCalls, 1, "item removed exactly once")
    eq(player.primary, nil, "item unequipped from the hands")
    eq(cursor.javaObject, placed, "javaObject recorded")

    MOCK.capturePrint(true)
    cursor:create(x, y, 0, false, cursor.sprite)
    MOCK.capturePrint(false)
    eq(#square.specialObjects, 1, "a consumed item cannot place a second analyzer")
    eq(cursor:isValid(square), false, "cursor invalid once the item is gone")

    local square2 = MOCK.registerSquare(poweredLabSquare(x + 1, y))
    local item2 = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local cursor2 = AC_LaboratoryAnalyzerObject:new(player, item2)
    player.inventory:Remove(item2)
    MOCK.capturePrint(true)
    cursor2:create(x + 1, y, 0, false, cursor2.sprite)
    MOCK.capturePrint(false)
    eq(#square2.specialObjects, 0, "no analyzer when the item left the inventory mid-action")

    local item3 = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local cursor3 = AC_LaboratoryAnalyzerObject:new(player, item3)
    MOCK.thumpableFails = true
    MOCK.capturePrint(true)
    cursor3:create(x + 1, y, 0, false, cursor3.sprite)
    MOCK.capturePrint(false)
    MOCK.thumpableFails = false
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "item kept when the object cannot be created")
    eq(#square2.specialObjects, 0, "nothing added on failure")
    MOCK.capturePrint(true)
    cursor3:create(x + 50, y, 0, false, cursor3.sprite)
    MOCK.capturePrint(false)
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "item kept when the square is missing")

    local busyItem = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local busy = busyItem.modData
    busy.labAnalyzerState = "processing"
    busy.storedSample = true
    busy.stored_sampleX = x
    busy.stored_trueCopper = 40
    busy.labRemainingHours = 5
    busy.labCopperResult = 41
    busy.labZincResult = 0
    local square3 = MOCK.registerSquare(poweredLabSquare(x + 2, y))
    local cursor4 = AC_LaboratoryAnalyzerObject:new(player, busyItem)
    MOCK.capturePrint(true)
    cursor4:create(x + 2, y, 0, false, cursor4.sprite)
    MOCK.capturePrint(false)
    local placedBusy = square3.specialObjects[1]
    eq(placedBusy and placedBusy.modData.labAnalyzerState, "processing", "placing an item mid-assay keeps the assay")
    eq(placedBusy and placedBusy.modData.stored_sampleX, x, "stored sample kept on placement")
    eq(placedBusy and AC_LaboratoryAnalyzer.getHoursRemaining(placedBusy), 5, "remaining time kept")
    MOCK.worldHours = 0
end

section("Analyzer menus: place, pick up, cancel")
do
    -- Menus and the pickup timed action against mocks: which options
    -- appear, what they queue, and that the pick-up rule holds at every
    -- step. Walking, animation and object removal by the engine are not
    -- modelled.
    local x, y = 840, 30
    local square = poweredLabSquare(x, y)
    local player = MOCK.newPlayer({ square = square })
    MOCK.worldHours = 600
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    local function carriedSample()
        local s = makeSample(x, y, 1, "Good", "None")
        s.modData.trueCopper = 58
        s.modData.trueZinc = 0
        player.inventory:addItem(s)
        return s
    end

    -- Place from the inventory
    local item = player.inventory:AddItem("AmmoMaking.LaboratoryAssayAnalyzer")
    ISInventoryPaneContextMenu.transfers = {}
    MOCK.drag = nil
    local ctx = fillInventoryMenu(player, item)
    local place = ctx:find("Place Laboratory Assay Analyzer")
    check(place ~= nil and not place.notAvailable, "place option for the analyzer item")
    if place then ctx:invoke(place) end
    check(MOCK.drag ~= nil and getmetatable(MOCK.drag.object) == AC_LaboratoryAnalyzerObject, "placement cursor started")
    eq(MOCK.drag and MOCK.drag.object.sourceItem, item, "cursor carries the item")
    eq(MOCK.drag and MOCK.drag.player, 0, "cursor for the right player")
    eq(ISInventoryPaneContextMenu.transfers[1], item, "item moved to the main inventory if needed")
    check(ctx:find("View Assay Result") == nil, "no sample options on the analyzer item")

    MOCK.client = true
    MOCK.drag = nil
    ctx = fillInventoryMenu(player, item)
    place = ctx:find("Place Laboratory Assay Analyzer")
    eq(place and place.notAvailable, true, "place option disabled on a multiplayer client")
    check(place and place.toolTip and string.find(place.toolTip.description, "multiplayer", 1, true) ~= nil, "multiplayer reason shown")
    MOCK.client = false

    -- Idle placed analyzer: pick up through the timed action
    local analyzer = placeAnalyzerObject(square)
    ctx = fillAnalyzerMenu(player, analyzer)
    local pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    check(pick ~= nil and not pick.notAvailable, "pick up offered for an idle analyzer")
    check(ctx:find("Cancel Laboratory Assay") == nil, "no cancel while idle")
    ISTimedActionQueue.clear()
    MOCK.walkAdjResult = false
    HaloTextHelper.clear()
    if pick then ctx:invoke(pick) end
    eq(#ISTimedActionQueue.queue, 0, "nothing queued when the analyzer is unreachable")
    eq(HaloTextHelper.last(), "Cannot reach the laboratory analyzer", "unreachable message")
    MOCK.walkAdjResult = true
    if pick then ctx:invoke(pick) end
    local action = ISTimedActionQueue.queue[1]
    check(action ~= nil and getmetatable(action) == AC_PickUpAnalyzerAction, "pickup action queued")
    eq(action and action.maxTime, AC_LaboratoryAnalyzer.CONFIG.pickUpActionTime, "pickup time from CONFIG")
    eq(action and action:isValid(), true, "action valid while idle")

    -- An assay started before the action completes blocks the pickup
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, carriedSample())
    eq(action:isValid(), false, "action invalid once an assay runs")
    HaloTextHelper.clear()
    action:perform()
    eq(#square.specialObjects, 1, "forced perform does not remove a busy analyzer")
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "no analyzer item created")
    eq(HaloTextHelper.last(), "Cancel the laboratory assay before moving the analyzer", "refusal explained")

    -- Processing: progress, cancel, disabled pick up with the reason
    ctx = fillAnalyzerMenu(player, analyzer)
    check(ctx:find("Check Laboratory Progress") ~= nil, "progress while processing")
    local cancel = ctx:find("Cancel Laboratory Assay")
    check(cancel ~= nil, "cancel offered while processing")
    pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    eq(pick and pick.notAvailable, true, "pick up disabled while processing")
    eq(pick and pick.toolTip and pick.toolTip.description, "Cancel the laboratory assay before moving the analyzer", "reason in the tooltip")
    HaloTextHelper.clear()
    if cancel then ctx:invoke(cancel) end
    eq(HaloTextHelper.last(), "Laboratory assay cancelled - sample returned", "cancel message")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "sample back after cancel")
    eq(#player.xpLog, 0, "no XP from a cancel")

    -- Ready: collect, disabled pick up with the reason
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, player.inventory:getItemsFromFullType("AmmoMaking.GeologicalSample"):get(0))
    MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours
    ctx = fillAnalyzerMenu(player, analyzer)
    check(ctx:find("Collect Laboratory Sample") ~= nil, "collect when ready")
    check(ctx:find("Cancel Laboratory Assay") == nil, "no cancel when ready")
    pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    eq(pick and pick.notAvailable, true, "pick up disabled while a result waits")
    eq(pick and pick.toolTip and pick.toolTip.description, "Collect the laboratory sample before moving the analyzer", "ready reason in the tooltip")
    ctx:invoke(ctx:find("Collect Laboratory Sample"))
    eq(#player.xpLog, 1, "XP once on collection")

    -- Idle again, unpowered: still movable
    square.haveElectricity = function() return false end
    ctx = fillAnalyzerMenu(player, analyzer)
    pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    check(pick ~= nil and not pick.notAvailable, "unpowered idle analyzer can still be moved")
    square.haveElectricity = function() return true end

    -- Two queued pickups: exactly one item
    ISTimedActionQueue.clear()
    local a1 = AC_PickUpAnalyzerAction:new(player, analyzer)
    local a2 = AC_PickUpAnalyzerAction:new(player, analyzer)
    HaloTextHelper.clear()
    a1:perform()
    eq(HaloTextHelper.last(), "Laboratory Assay Analyzer picked up", "pickup message")
    eq(#square.specialObjects, 0, "analyzer removed from the square")
    eq(square.transmittedRemovals[1], analyzer, "removal transmitted like vanilla")
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 2, "analyzer item added")
    eq(a2:isValid(), false, "second action invalid once the analyzer is gone")
    a2:perform()
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 2, "no second item")
    eq(select(2, AC_PickUpAnalyzerAction.pickUp(player, analyzer)), "gone", "pickUp reports the analyzer gone")

    -- Item creation failure keeps the analyzer placed
    local kept = placeAnalyzerObject(square)
    MOCK.knownScriptItems["AmmoMaking.LaboratoryAssayAnalyzer"] = nil
    local noItem, errItem = AC_PickUpAnalyzerAction.pickUp(player, kept)
    MOCK.knownScriptItems["AmmoMaking.LaboratoryAssayAnalyzer"] = true
    eq(noItem, nil, "no item")
    eq(errItem, "item_creation_failed", "failure reported")
    eq(#square.specialObjects, 1, "analyzer stays placed when the item cannot be created")

    -- Placed analyzer found through the square's special objects
    local floor = { getSquare = function() return square end }
    MOCK.players = { player }
    ctx = MOCK.newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { floor }, false)
    check(ctx:find("Check Laboratory Analyzer") ~= nil, "analyzer found via special objects of the clicked square")

    -- Multiplayer client: pick up disabled with the reason
    MOCK.client = true
    ctx = fillAnalyzerMenu(player, kept)
    pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    eq(pick and pick.notAvailable, true, "pick up disabled on a multiplayer client")
    MOCK.client = false

    -- Dropped analyzer: vanilla pickup, but cancel is available
    local droppedItem = MOCK.newItem("AmmoMaking.LaboratoryAssayAnalyzer")
    local dropped = { __class = "IsoWorldInventoryObject", getItem = function() return droppedItem end, getSquare = function() return square end }
    AC_LaboratoryAnalyzer.startAssay(player, dropped, carriedSample())
    ctx = fillAnalyzerMenu(player, dropped)
    check(ctx:find("Pick Up Laboratory Assay Analyzer") == nil, "no mod pick-up option for a dropped analyzer")
    check(ctx:find("Cancel Laboratory Assay") ~= nil, "cancel offered for a dropped analyzer")

    MOCK.capturePrint(false)
    ISTimedActionQueue.clear()
    MOCK.worldHours = 0
end

section("Laboratory analyzer power rule")
do
    -- Mirrors vanilla 42.20's car battery charger check:
    -- haveElectricity() or (hasGridPower() and getRoom()).
    local function analyzerOn(opts)
        local square = MOCK.newSquare(860, 30, 0, "floors_interior_tiles_01_0", opts)
        return placeAnalyzerObject(square), square
    end

    local indoorGrid = analyzerOn({ room = {}, gridPower = true })
    eq(AC_LaboratoryAnalyzer.hasPower(indoorGrid), true, "grid power inside a room")

    local indoorNoGrid = analyzerOn({ room = {}, gridPower = false })
    eq(AC_LaboratoryAnalyzer.hasPower(indoorNoGrid), false, "no grid power inside a room")

    local outdoorGrid = analyzerOn({ gridPower = true })
    eq(AC_LaboratoryAnalyzer.hasPower(outdoorGrid), false, "grid power does not reach an analyzer outdoors")

    local generator, generatorSquare = analyzerOn({})
    generatorSquare.haveElectricity = function() return true end
    eq(AC_LaboratoryAnalyzer.hasPower(generator), true, "generator power outdoors")

    local legacy, legacySquare = analyzerOn({ room = {} })
    legacySquare.hasGridPower = nil
    MOCK.hydroPowerOn = true
    eq(AC_LaboratoryAnalyzer.hasPower(legacy), true, "falls back to hydro power without hasGridPower")
    MOCK.hydroPowerOn = false
    eq(AC_LaboratoryAnalyzer.hasPower(legacy), false, "fallback respects hydro power off")

    eq(AC_LaboratoryAnalyzer.hasPower(MOCK.newWorldObject()), false, "not an analyzer -> no power")
end

section("Translation keys used in code exist in IG_UI.json")
do
    local handle = io.open(ROOT .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/IG_UI.json", "r")
    local json = handle:read("*a")
    handle:close()
    local defined = {}
    for key in string.gmatch(json, '"([^"]+)"%s*:') do defined[key] = true end

    local used, missing = 0, {}
    for _, name in ipairs(MOCK.MOD_FILES) do
        local file = io.open(LUA .. name .. ".lua", "r")
        local source = file:read("*a")
        file:close()
        -- Literal keys only; a key built with ".." is skipped.
        for key, after in string.gmatch(source, 'AC_Text%.get%(%s*"([^"]+)"%s*(.)') do
            if after ~= "." then
                used = used + 1
                if not defined[key] then table.insert(missing, key .. " (" .. name .. ")") end
            end
        end
    end
    check(used > 50, "keys found in code (" .. used .. ")")
    eq(#missing, 0, "every literal key has an English entry: " .. table.concat(missing, ", "))
end

------------------------------------------------
-- ACTION TIME
------------------------------------------------

section("Action time scaling")
do
    local player = MOCK.newPlayer()
    eq(AC_Mining.getActionTime(player), AC_Mining.CONFIG.baseActionTime, "level 0 = base")
    player.perkLevel = 10
    eq(AC_Mining.getActionTime(player), math.floor(AC_Mining.CONFIG.baseActionTime * 0.6), "level 10 = 40% faster")
    player.perkLevel = 30
    check(AC_Mining.getActionTime(player) >= 1, "absurd level never yields a non-positive duration")
    player.perkLevel = 0
    player.isTimedActionInstant = function() return true end
    local sq = MOCK.newSquare(1, 1, 0, GRASS)
    eq(AC_MineOreAction:new(player, sq, "copper", MOCK.newItem("Base.PickAxe")):getDuration(), 1, "instant actions (debug/cheat) take 1")
end

------------------------------------------------
-- DEBUG GATING AND TOOLS
------------------------------------------------

section("Debug menu gating")
do
    MOCK.clearModData()
    local x, y = findTile("copper", 1)
    local player, square = miningSetup(x, y, "Poor", "None")

    MOCK.debug = false
    local ctx = fillWorldMenu(player, square)
    check(ctx:find("Ammo Making Debug") == nil, "no debug submenu in normal mode")
    local cartridge = MOCK.newItem("AmmoMaking.TestCartridge")
    ctx = fillInventoryMenu(player, cartridge)
    check(ctx:find("Inspect Ammunition") ~= nil, "inspect option always present")
    check(ctx:find("Debug Ammo Quality") == nil, "no quality debug in normal mode")
    check(ctx:find("Set Ammo Making Level") == nil, "no level debug in normal mode")

    MOCK.debug = true
    ctx = fillWorldMenu(player, square)
    local root = ctx:find("Ammo Making Debug")
    check(root ~= nil and root.submenu ~= nil, "debug submenu in debug mode")
    local expected = {
        "Inspect Current Tile", "Survey Current Area (3x3)", "Show Geology Seed",
        "Inspect Clicked Tile Objects (sprites, analyzer state)",
        "Reset Depletion: Current Tile", "Reset Depletion: 3x3 Area",
        "Spawn Sampling Kit (shovel + assay kits)", "Spawn Mining Kit (pickaxes)",
        "Spawn Laboratory Analyzer", "Spawn Assayed Sample (current 3x3)",
        "Set Ammo Making Level", "Run Compatibility Check",
    }
    for _, e in ipairs(expected) do
        check(root.submenu:find(e) ~= nil, "debug entry present: " .. e)
    end
    eq(#root.submenu.options, #expected, "no unexpected debug entries")
    ctx = fillInventoryMenu(player, cartridge)
    check(ctx:find("Debug Ammo Quality") ~= nil, "quality debug in debug mode")
    check(ctx:find("Set Ammo Making Level") ~= nil, "level debug in debug mode")
    MOCK.debug = false
end

section("Debug tools behave")
do
    MOCK.clearModData()
    MOCK.debug = true
    local x, y, r = findTile("copper", 2)
    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square, x = x + 0.4, y = y + 0.6 })
    MOCK.players = { player }

    AC_GeologyDebug.spawnSamplingKit(player)
    eq(player.inventory:count("Base.Shovel"), 1, "shovel spawned")
    eq(player.inventory:count("AmmoMaking.FieldAssayKit"), 1, "field kit spawned")
    eq(player.inventory:count("AmmoMaking.AdvancedFieldAssayKit"), 1, "advanced kit spawned")
    AC_GeologyDebug.spawnMiningKit(player)
    eq(player.inventory:count("Base.PickAxe"), 1, "pickaxe spawned")
    eq(player.inventory:count("Base.PickAxeForged"), 1, "forged pickaxe spawned")
    AC_GeologyDebug.spawnLaboratoryAnalyzer(player)
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "analyzer spawned")

    MOCK.knownScriptItems["Base.PickAxeForged"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okSpawn = pcall(AC_GeologyDebug.spawnMiningKit, player)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.PickAxeForged"] = true
    check(okSpawn, "spawn with missing item does not raise")
    check(MOCK.printLogContains("WARNING: debug spawn FAILED: Base.PickAxeForged"), "missing item logged as WARNING")

    AC_GeologyDebug.spawnAssayedSample(player)
    local sample = player.inventory:getItemsFromFullType("AmmoMaking.GeologicalSample"):get(0)
    check(sample ~= nil, "debug sample created")
    eq(sample.modData.sampleX, x, "debug sample centred on the player tile")
    eq(sample.modData.assayRank, 2, "debug sample carries an advanced assay")
    eq(AC_GeologySampling.getKitUses(player.inventory:getItemsFromFullType("AmmoMaking.AdvancedFieldAssayKit"):get(0)), 10, "no kit use consumed")

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okInspect = pcall(AC_GeologyDebug.tile, player)
    MOCK.capturePrint(false)
    check(okInspect, "inspect tile does not raise")
    check(MOCK.printLogContains("reserve " .. r .. "/" .. r), "inspect prints initial reserve")
    check(MOCK.printLogContains("mineable = true"), "inspect prints terrain verdict")

    AC_Deposits.recordExtraction(x, y, "copper", 1)
    AC_Deposits.recordExtraction(x + 1, y + 1, "copper", 1)
    AC_GeologyDebug.resetTile(player)
    eq(AC_Deposits.getExtracted(x, y, "copper"), 0, "reset tile clears the player's tile")
    eq(AC_Deposits.getExtracted(x + 1, y + 1, "copper"), 1, "reset tile leaves neighbours")
    AC_GeologyDebug.resetArea(player)
    eq(AC_Deposits.getExtracted(x + 1, y + 1, "copper"), 0, "reset area clears neighbours")
    eq(AC_Deposits.getWorkedTileCount(), 0, "store empty after area reset")

    AC_GeologyDebug.setSkillLevel(player, 7)
    eq(AmmoMakingSkill.getLevel(player), 7, "skill level set")
    AC_GeologyDebug.setSkillLevel(player, 99)
    eq(AmmoMakingSkill.getLevel(player), 10, "skill level clamped")

    check(pcall(AC_GeologyDebug.seed, player), "seed tool runs")
    check(pcall(AC_GeologyDebug.survey, player), "survey tool runs")
    MOCK.capturePrint(true)
    local okCompat = pcall(AC_GeologyDebug.compat, player)
    MOCK.capturePrint(false)
    check(okCompat, "compat tool runs")

    -- Tile object inspector (recovered sprite inspector)
    local labSquare = poweredLabSquare(x + 5, y)
    local wall = MOCK.newWorldObject({ name = "wall", sprite = "walls_exterior_house_01_0" })
    labSquare:AddSpecialObject(wall)
    local analyzer = placeAnalyzerObject(labSquare)
    local s = makeSample(x + 5, y, 1, "Good", "None")
    s.modData.trueCopper = 60
    s.modData.trueZinc = 0
    player.inventory:addItem(s)
    MOCK.worldHours = 900
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, s)
    local stateBefore = analyzer.modData.labLastUpdateAt
    MOCK.worldHours = 905
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okObjects = pcall(AC_GeologyDebug.objects, player, labSquare)
    MOCK.capturePrint(false)
    check(okObjects, "tile object inspector runs")
    check(MOCK.printLogContains("sprite=walls_exterior_house_01_0"), "sprite names listed")
    check(MOCK.printLogContains("analyzer (placed) state=processing"), "placed analyzer state listed")
    eq(analyzer.modData.labLastUpdateAt, stateBefore, "inspector does not advance the analyzer")
    eq(wall:hasModData(), false, "inspector creates no ModData on ordinary objects")
    check(pcall(AC_GeologyDebug.objects, player, nil), "inspector tolerates a missing square")
    check(pcall(AC_GeologyDebug.objects, player, { getX = function() return 1 end, getY = function() return 1 end, getZ = function() return 0 end }), "inspector tolerates a square without object lists")
    MOCK.worldHours = 0
    MOCK.debug = false
end

------------------------------------------------
-- COMPATIBILITY CHECK
------------------------------------------------

section("Compatibility self-check")
do
    local player = MOCK.newPlayer({ square = MOCK.newSquare(1, 1, 0, GRASS) })
    MOCK.players = { player }
    local fullTranslations = {
        IGUI_perks_AmmoMaking = "Ammo Making",
        ["IGUI_perks_Ammo Making_Description1"] = "level one",
    }
    MOCK.translations = fullTranslations

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local results, summary = AC_Compat.run()
    MOCK.capturePrint(false)
    eq(summary.warnings, 0, "no warnings with every API mocked")
    eq(summary.unverified, 0, "nothing unverified with a player present")
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.CopperOre"), "OK line format")
    check(MOCK.printLogContains("Compatibility check:"), "summary line printed")

    MOCK.knownScriptItems["Base.CopperOre"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    results, summary = AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.CopperOre"] = true
    eq(summary.warnings, 1, "one warning for the missing item")
    check(MOCK.printLogContains("[AmmoMaking] WARNING: Base.CopperOre not found"), "WARNING line format")

    MOCK.players = {}
    MOCK.scriptManagerAvailable = false
    MOCK.capturePrint(true)
    local okRun, r2, s2 = pcall(AC_Compat.run)
    MOCK.capturePrint(false)
    MOCK.scriptManagerAvailable = true
    check(okRun, "run without player or script manager does not raise")
    check(s2.unverified > 0, "unavailable probes reported as unverified")
    eq(s2.warnings, 0, "unavailable probes are not warnings")

    MOCK.players = { player }
    MOCK.translations = fullTranslations
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run()
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("translation file loaded"), "loaded translation detected")
    check(MOCK.printLogContains("perk level descriptions resolve (spaced key)"), "spaced description key reported")

    MOCK.translations = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local r3, s3 = AC_Compat.run()
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("WARNING: translation file not loaded"), "missing translation file is a WARNING")
    check(MOCK.printLogContains("UNVERIFIED: perk level descriptions"), "unresolvable description keys are UNVERIFIED, not WARNING")
    eq(s3.warnings, 1, "only the translation warning without a translation table")
    MOCK.translations = fullTranslations

    -- Laboratory analyzer assumptions
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run()
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("OK: analyzer world sprite (industry_03_61)"), "analyzer sprite probed")
    check(MOCK.printLogContains("OK: IsoGridSquare:AddSpecialObject"), "placement square method probed")
    check(MOCK.printLogContains("OK: IsoGridSquare:hasGridPower"), "grid power method probed")
    check(MOCK.printLogContains("OK: AC_LaboratoryAnalyzerObject loaded"), "building object load probed")
    check(MOCK.printLogContains("OK: IsoPlayer:getPlayerNum"), "placement player method probed")

    MOCK.knownSprites["industry_03_61"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local r4, s4 = AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.knownSprites["industry_03_61"] = true
    eq(s4.warnings, 1, "missing analyzer sprite is one WARNING")
    check(MOCK.printLogContains("WARNING: analyzer world sprite industry_03_61 not found"), "sprite WARNING line")

    local realGetSprite = getSprite
    getSprite = nil
    MOCK.capturePrint(true)
    local r5, s5 = AC_Compat.run()
    MOCK.capturePrint(false)
    getSprite = realGetSprite
    eq(s5.warnings, 0, "no getSprite is not a warning")
    check(s5.unverified >= 1, "no getSprite reported as unverified")

    local noWaterSquare = MOCK.newSquare(1, 1, 0, GRASS)
    noWaterSquare.hasWater = nil
    noWaterSquare.Is = function() return false end
    MOCK.players = { MOCK.newPlayer({ square = noWaterSquare }) }
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local rW, sW = AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.players = { player }
    eq(sW.warnings, 1, "missing hasWater is one WARNING")
    check(MOCK.printLogContains("WARNING: water detection unavailable"), "square:Is() no longer counts as water detection")
    check(not MOCK.printLogContains("Is(IsoFlagType.water)"), "Is() fallback not reported")

    local bareSquare = MOCK.newSquare(1, 1, 0, GRASS)
    bareSquare.AddSpecialObject = nil
    MOCK.players = { MOCK.newPlayer({ square = bareSquare }) }
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local r6, s6 = AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.players = { player }
    eq(s6.warnings, 1, "missing square method is one WARNING")
    check(MOCK.printLogContains("WARNING: IsoGridSquare:AddSpecialObject missing (the laboratory analyzer cannot be placed)"), "consequence named")

    AC_Compat.hasRun = false
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    Events.OnGameStart.fire()
    Events.OnGameStart.fire()
    MOCK.capturePrint(false)
    local count = 0
    for _, line in ipairs(MOCK.printLog) do
        if string.find(line, "Compatibility check:", 1, true) then count = count + 1 end
    end
    eq(count, 1, "OnGameStart runs the check once")
    MOCK.translations = nil
end

------------------------------------------------
-- INSPECTION PROTOTYPE (smoke)
------------------------------------------------

section("Ammunition inspection lines")
do
    local player = MOCK.newPlayer()
    local cartridge = MOCK.newItem("AmmoMaking.TestCartridge")
    local r = AmmoInspection.inspect(player, cartridge)
    eq(r.title, "Ammo Inspection", "title separate from lines")
    eq(#r.lines, 1, "level 0: one line")
    for level = 1, 10 do
        player.perkLevel = level
        r = AmmoInspection.inspect(player, cartridge)
        check(#r.lines >= 1, "level " .. level .. " produces lines")
        for _, line in ipairs(r.lines) do
            check(not string.find(line, "IGUI_", 1, true), "no raw keys at level " .. level)
        end
    end
    eq(AmmoQuality.getQualityLabel(nil), "Unknown", "nil item label")
end

------------------------------------------------
-- SUMMARY
------------------------------------------------

print("")
print("Passed: " .. passed .. "  Failed: " .. failed)
if failed > 0 then
    os.exit(1)
end
