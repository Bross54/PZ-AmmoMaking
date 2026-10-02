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
-- The Java overloads of the installed build: mocked engine objects refuse a
-- call the real engine would refuse (see mock_pz.lua, ENGINE SIGNATURES).
local ENGINE = dofile(ROOT .. "/tests/engine_snapshot.lua")
MOCK.useEngineSnapshot(ENGINE)
local RENDER = dofile(ROOT .. "/tests/render_recipes.lua")

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

section("Mining result feedback: one message per action, XP granted and logged once")
do
    -- Lua-level only: HaloTextHelper and print are mocked. How the halo
    -- looks in game, and whether the engine scales the XP, is not tested.
    MOCK.clearModData()
    MOCK.debug = false
    local xp = AC_Mining.CONFIG.xpPerOre
    local x, y = findTile("copper", 2, 2)
    local player, square, pick = miningSetup(x, y, "Good", "None")

    local function mineOnce()
        HaloTextHelper.clear()
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        local action = AC_MineOreAction:new(player, square, "copper", pick)
        action:start()
        action:perform()
        MOCK.capturePrint(false)
        return HaloTextHelper.log
    end

    local halos = mineOnce()
    eq(#halos, 1, "exactly one halo message for a successful extraction")
    eq(halos[1], "Copper ore extracted - vein thinning out - +" .. xp .. " Ammo Making XP", "normal-mode message (1 of 2 left)")
    eq(#player.xpLog, 1, "XP granted once")
    eq(player.xpLog[1], xp, "XP value unchanged")
    check(MOCK.printLogContains("[AmmoMaking] Mining: +" .. xp .. " Ammo Making XP (total 0 -> " .. xp .. ")"), "XP award logged with before/after total")

    halos = mineOnce()
    eq(#halos, 1, "one halo message for the exhausting extraction")
    eq(halos[1], "Copper ore extracted - deposit exhausted - +" .. xp .. " Ammo Making XP", "exhausted message")
    eq(#player.xpLog, 2, "second extraction adds exactly one more XP grant")
    check(MOCK.printLogContains("[AmmoMaking] Mining: +" .. xp .. " Ammo Making XP (total " .. xp .. " -> " .. (2 * xp) .. ")"), "second award logged")

    -- Debug mode shows the exact reserve for in-game testing.
    MOCK.clearModData()
    MOCK.debug = true
    local dx, dy = findTile("zinc", 2, 2)
    local dPlayer, dSquare, dPick = miningSetup(dx, dy, "None", "Good")
    player, square, pick = dPlayer, dSquare, dPick
    HaloTextHelper.clear()
    local action = AC_MineOreAction:new(player, square, "zinc", pick)
    action:start()
    action:perform()
    eq(#HaloTextHelper.log, 1, "one halo message in debug mode")
    eq(HaloTextHelper.last(), "Zinc ore extracted - 1/2 remaining - +" .. xp .. " Ammo Making XP", "debug message shows the reserve")
    action = AC_MineOreAction:new(player, square, "zinc", pick)
    action:start()
    action:perform()
    eq(HaloTextHelper.last(), "Zinc ore extracted - deposit exhausted - +" .. xp .. " Ammo Making XP", "debug exhausted message")
    eq(#player.xpLog, 2, "one XP grant per extraction in debug mode")
    MOCK.debug = false

    -- No ore: one message, no XP, no XP log line.
    local ex, ey = findTile("zinc", 0, 0)
    local ePlayer, eSquare, ePick = miningSetup(ex, ey, "None", "Good")
    HaloTextHelper.clear()
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    action = AC_MineOreAction:new(ePlayer, eSquare, "zinc", ePick)
    action:start()
    action:perform()
    MOCK.capturePrint(false)
    eq(#HaloTextHelper.log, 1, "one halo message for no ore")
    eq(HaloTextHelper.last(), "No workable zinc ore here", "no-ore message")
    eq(#ePlayer.xpLog, 0, "no XP when there is no ore")
    check(not MOCK.printLogContains("Ammo Making XP"), "no XP log line when there is no ore")

    -- A stopped action shows nothing and grants nothing.
    local sx, sy = findTile("copper", 1)
    local sPlayer, sSquare, sPick = miningSetup(sx, sy, "Good", "None")
    HaloTextHelper.clear()
    action = AC_MineOreAction:new(sPlayer, sSquare, "copper", sPick)
    action:start()
    action:stop()
    eq(#HaloTextHelper.log, 0, "no message when the action is stopped")
    eq(#sPlayer.xpLog, 0, "no XP when the action is stopped")

    -- awardXP guards
    eq(AmmoMakingSkill.awardXP(sPlayer, 0, "Test"), 0, "zero XP is not awarded")
    eq(AmmoMakingSkill.awardXP(nil, 5, "Test"), 0, "no player -> nothing")
    eq(#sPlayer.xpLog, 0, "guards add nothing")
    eq(AmmoMakingSkill.formatXP(5), "5", "whole XP formatted without decimals")
    eq(AmmoMakingSkill.formatXP(2.5), "2.50", "fractional XP formatted")
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
    eq(HaloTextHelper.last(), "No workable copper ore here", "player told there is nothing")
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
    -- The XP gain is not geology; everything else must be number-free.
    local withoutXP = string.gsub(tostring(HaloTextHelper.last()), " %- %+%d+ Ammo Making XP$", "")
    check(withoutXP ~= HaloTextHelper.last(), "extraction message ends with the XP gain: " .. tostring(HaloTextHelper.last()))
    check(not hasDigit(withoutXP), "extraction message without reserve numbers: " .. tostring(HaloTextHelper.last()))

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

-- Lua logic plus one mocked engine rule: the mock item raises on
-- hasTag("string"), as InventoryItem does on 42.20.4 (it only has
-- hasTag(ItemTag) / hasTag(ItemTag...)). In game, that error also
-- corrupts a Kahlua argument pool and breaks the next StartAction.
section("Shovel detection never calls hasTag with a string")
do
    MOCK.invalidHasTagCalls = 0

    -- Base.PickAxe is a HandWeapon; vanilla tags it base:digplow.
    local pick = MOCK.newItem("Base.PickAxe", { tags = { DigPlow = true } })
    local okPick, pickIsShovel = pcall(AC_GeologySampling.isShovel, pick)
    check(okPick, "isShovel(Base.PickAxe) raises no error: " .. tostring(pickIsShovel))
    eq(pickIsShovel, false, "pickaxe is not a shovel")
    eq(MOCK.invalidHasTagCalls, 0, "no hasTag(string) call for a pickaxe")

    local player = MOCK.newPlayer()
    player.primary = pick
    local okEq, equipped = pcall(AC_GeologySampling.getEquippedShovel, player)
    check(okEq, "getEquippedShovel with a pickaxe raises no error: " .. tostring(equipped))
    eq(equipped, nil, "pickaxe in hand gives no shovel")
    player.primary = nil
    player.secondary = pick
    eq(AC_GeologySampling.getEquippedShovel(player), nil, "pickaxe in off hand gives no shovel")

    for _, fullType in ipairs({ "Base.Shovel", "Base.Shovel2", "Base.HandShovel" }) do
        local shovel = MOCK.newItem(fullType)
        eq(AC_GeologySampling.isShovel(shovel), true, fullType .. " is a supported shovel")
        player.primary = shovel
        player.secondary = nil
        eq(AC_GeologySampling.getEquippedShovel(player), shovel, fullType .. " found in hand")
    end

    eq(AC_GeologySampling.isShovel(nil), false, "nil is not a shovel")
    eq(AC_GeologySampling.isShovel(MOCK.newItem("Base.Hammer", { tags = { DigGrave = true } })), false,
        "unlisted items are not shovels, whatever their tags")

    -- The right-click path that raised the error in game: pickaxe equipped,
    -- assayed sample carried, world context menu filled.
    MOCK.clearModData()
    local x, y = findTile("zinc", 1)
    local p, square = miningSetup(x, y, "None", "Good")
    local okMenu, ctxOrErr = pcall(fillWorldMenu, p, square)
    check(okMenu, "world context menu with a pickaxe raises no error: " .. tostring(ctxOrErr))
    eq(MOCK.invalidHasTagCalls, 0, "world context menu makes no hasTag(string) call")
    if okMenu then
        check(ctxOrErr:find("Dig Geological Sample") == nil, "no dig option with only a pickaxe")
    end
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

-- Mocked ISBaseTimedAction and BuildingHelper. Covers the Lua side of
-- the lifecycle only. Vanilla begin() -> create() -> LuaTimedActionNew
-- -> IsoGameCharacter:StartAction() -> start() is Java and is not run
-- here; that mining actually starts needs the in-game check.
section("Mining action lifecycle matches the working dig action (mocked timed-action base)")
do
    local LIFECYCLE = { "new", "isValid", "waitToStart", "start", "update", "stop", "perform", "getDuration" }
    for _, name in ipairs(LIFECYCLE) do
        eq(type(rawget(AC_MineOreAction, name)), type(rawget(AC_DigGeologicalSampleAction, name)),
            "mining and dig both define " .. name)
    end
    for _, name in ipairs({ "begin", "create", "adjustMaxTime", "complete" }) do
        eq(rawget(AC_MineOreAction, name), nil, "mining leaves vanilla " .. name .. " alone")
        eq(rawget(AC_DigGeologicalSampleAction, name), nil, "dig leaves vanilla " .. name .. " alone")
    end

    MOCK.clearModData()
    local x, y = findTile("zinc", 3)
    local player, square, pick = miningSetup(x, y, "None", "Good")
    local digSquare = MOCK.newSquare(x, y, 0, GRASS)
    local digPlayer = MOCK.newPlayer({ square = digSquare })
    local shovel = equipShovel(digPlayer, 10)

    local mine = AC_MineOreAction:new(player, square, "zinc", pick)
    local dig = AC_DigGeologicalSampleAction:new(digPlayer, digSquare, shovel)
    for _, field in ipairs({ "stopOnWalk", "stopOnRun", "stopOnAim" }) do
        eq(mine[field], dig[field], "constructor " .. field .. " matches dig")
    end
    eq(mine.character, player, "character set")
    eq(mine.item, pick, "pickaxe stored as item, like dig's shovel")
    eq(type(mine.maxTime), "number", "maxTime is a number")
    check(mine.maxTime > 0, "maxTime positive")
    eq(mine.maxTime, mine:getDuration(), "maxTime comes from getDuration()")
    eq(mine.caloriesModifier, dig.caloriesModifier, "caloriesModifier matches dig")

    -- Vanilla order: isValid, waitToStart, start, then update/isValid ticks.
    MOCK.invalidHasTagCalls = 0
    eq(mine:isValid(), true, "valid before start")
    eq(mine:waitToStart(), false, "no turning wait in the mock")
    eq(mine:start(), nil, "start() returns nothing, like dig")
    eq(dig:start(), nil, "dig start() returns nothing")
    eq(mine.anim, CharacterActionAnims.DigPickAxe,
        "pickaxe gets vanilla getShovelAnim's DigPickAxe (enum), not a string fallback")
    eq(dig.anim, CharacterActionAnims.DigShovel, "shovel still gets DigShovel")
    check(mine.item.jobType ~= nil, "job type set on the pickaxe")
    mine:update()
    eq(mine:isValid(), true, "still valid after an update tick")
    eq(MOCK.invalidHasTagCalls, 0, "no hasTag(string) call anywhere in the mining lifecycle")

    local before = AC_Deposits.getRemaining(x, y, "zinc")
    mine:stop()
    eq(AC_Deposits.getRemaining(x, y, "zinc"), before, "stop() extracts nothing")

    mine = AC_MineOreAction:new(player, square, "zinc", pick)
    mine:start()
    mine:perform()
    eq(AC_Deposits.getRemaining(x, y, "zinc"), before - 1, "perform() extracts exactly once")
    eq(mine.completed, true, "perform() ends with ISBaseTimedAction.perform")

    -- An error in the anim selector is no longer swallowed by a pcall.
    local saved = BuildingHelper.getShovelAnim
    BuildingHelper.getShovelAnim = function() error("anim selector failed") end
    local okStart = pcall(function() AC_MineOreAction:new(player, square, "zinc", pick):start() end)
    BuildingHelper.getShovelAnim = saved
    eq(okStart, false, "start() does not hide anim-selector errors")
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

section("Analyzer test loop: start, busy, complete, collect once, pick up (mocked placed object)")
do
    -- The loop the next in-game test follows, driven through the menus.
    -- Lua state and messages only; the placed object is a mock.
    local x, y = 880, 30
    local square = poweredLabSquare(x, y)
    local player = MOCK.newPlayer({ square = square })
    local xp = AC_LaboratoryAnalyzer.CONFIG.assayXP
    MOCK.worldHours = 3000
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    local function carried(sx)
        local s = makeSample(sx, y, 1, "Good", "None")
        s.modData.trueCopper = 61
        s.modData.trueZinc = 3
        player.inventory:addItem(s)
        return s
    end
    carried(x)
    carried(x + 1)
    local function firstSample()
        return player.inventory:getItemsFromFullType("AmmoMaking.GeologicalSample"):get(0)
    end

    -- Unpowered: no start option, and a direct start is refused and logged
    local analyzer = placeAnalyzerObject(square)
    square.haveElectricity = function() return false end
    local ctx = fillAnalyzerMenu(player, analyzer)
    check(ctx:find("Laboratory Analyzer - Requires Electricity") ~= nil, "no-power option while unpowered")
    check(ctx:find("Start Lab Assay: Sample " .. x .. ", " .. y) == nil, "no start option while unpowered")
    square.haveElectricity = function() return true end

    -- Start: exactly one of two samples stored, processing, no XP
    ctx = fillAnalyzerMenu(player, analyzer)
    local start = ctx:find("Start Lab Assay: Sample " .. x .. ", " .. y)
    square.haveElectricity = function() return false end
    ctx:invoke(start)
    check(MOCK.printLogContains("Laboratory assay start refused: no_power"), "refused start logged")
    eq(analyzer.modData.labAnalyzerState, "idle", "refused start leaves the analyzer idle")
    square.haveElectricity = function() return true end
    ctx:invoke(start)
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "only the chosen sample went in")
    eq(analyzer.modData.storedSample, true, "one sample stored")
    eq(analyzer.modData.stored_sampleX, x, "the chosen sample is stored")
    eq(analyzer.modData.labAnalyzerState, "processing", "processing after start")
    eq(#player.xpLog, 0, "no XP at start")
    check(MOCK.printLogContains("Laboratory assay started for sample " .. x), "start logged")

    -- Busy: no second sample, no pickup, no second analyzer, cancel offered
    ctx = fillAnalyzerMenu(player, analyzer)
    check(ctx:find("Start Lab Assay: Sample " .. (x + 1) .. ", " .. y) == nil, "no start option while busy")
    check(ctx:find("Cancel Laboratory Assay") ~= nil, "cancel offered while busy")
    eq(select(2, AC_LaboratoryAnalyzer.startAssay(player, analyzer, firstSample())), "busy", "direct start refused while busy")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 1, "refused start keeps the sample")
    eq(analyzer.modData.stored_sampleX, x, "refused start does not replace the stored sample")
    eq(select(2, AC_PickUpAnalyzerAction.pickUp(player, analyzer)), "processing", "pickup refused while busy")
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 0, "no analyzer item created while busy")
    eq(#square.specialObjects, 1, "analyzer still placed")

    -- Cancel reveals nothing and grants nothing
    HaloTextHelper.clear()
    ctx:invoke(ctx:find("Cancel Laboratory Assay"))
    check(not hasDigit(HaloTextHelper.last()), "cancel message reveals no result: " .. tostring(HaloTextHelper.last()))
    check(MOCK.printLogContains("Laboratory assay cancelled; sample " .. x), "cancel logged")
    eq(#player.xpLog, 0, "no XP from cancel")
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 2, "both samples carried again")

    -- Complete: ready, sample still stored, no XP until collection
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, firstSample())
    local storedX = analyzer.modData.stored_sampleX
    MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours
    eq(AC_LaboratoryAnalyzer.getState(analyzer), "ready", "ready after the processing time")
    eq(analyzer.modData.storedSample, true, "sample still stored when ready")
    eq(analyzer.modData.stored_sampleX, storedX, "same sample stored")
    eq(#player.xpLog, 0, "no XP on completion")
    check(MOCK.printLogContains("Laboratory analyzer completed sample " .. storedX), "completion logged")

    -- Collect: one sample, XP once, one message with the gain, idle
    HaloTextHelper.clear()
    MOCK.clearPrintLog()
    ctx = fillAnalyzerMenu(player, analyzer)
    ctx:invoke(ctx:find("Collect Laboratory Sample"))
    eq(player.inventory:count("AmmoMaking.GeologicalSample"), 2, "exactly one sample returned")
    eq(#player.xpLog, 1, "laboratory XP granted once")
    eq(player.xpLog[1], xp, "laboratory XP value unchanged")
    eq(#HaloTextHelper.log, 1, "one message on collection")
    eq(HaloTextHelper.last(), "Laboratory tested sample collected - +" .. xp .. " Ammo Making XP", "collect message shows the XP")
    check(MOCK.printLogContains("[AmmoMaking] Laboratory: +" .. xp .. " Ammo Making XP (total 0 -> " .. xp .. ")"), "laboratory XP logged")
    check(MOCK.printLogContains("Laboratory tested sample collected: sample " .. storedX), "collection logged")
    eq(analyzer.modData.labAnalyzerState, "idle", "idle after collection")
    AC_LaboratoryAnalyzer.collectSample(player, analyzer)
    eq(#player.xpLog, 1, "second collect grants nothing")

    -- Pick up: idle and empty -> exactly one analyzer item, logged
    ctx = fillAnalyzerMenu(player, analyzer)
    local pick = ctx:find("Pick Up Laboratory Assay Analyzer")
    check(pick ~= nil and not pick.notAvailable, "pick up offered once idle and empty")
    ISTimedActionQueue.clear()
    MOCK.walkAdjResult = true
    if pick then ctx:invoke(pick) end
    local action = ISTimedActionQueue.queue[1]
    if action then action:perform() end
    eq(player.inventory:count("AmmoMaking.LaboratoryAssayAnalyzer"), 1, "exactly one analyzer item")
    eq(#square.specialObjects, 0, "placed analyzer removed")
    check(MOCK.printLogContains("Laboratory Assay Analyzer picked up at " .. x), "pickup logged")
    eq(#player.xpLog, 1, "no XP from cancel or pickup")

    MOCK.capturePrint(false)
    ISTimedActionQueue.clear()
    MOCK.worldHours = 0
end

section("Laboratory analyzer power accounting (lazy, on interaction; mocked power)")
do
    local x, y = 900, 30
    local square = poweredLabSquare(x, y)
    local power = true
    square.haveElectricity = function() return power end
    local player = MOCK.newPlayer({ square = square })
    local analyzer = placeAnalyzerObject(square)
    local total = AC_LaboratoryAnalyzer.CONFIG.processingHours
    local s = makeSample(x, y, 1, "Good", "None")
    s.modData.trueCopper = 50
    s.modData.trueZinc = 0
    player.inventory:addItem(s)
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    MOCK.worldHours = 4000
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, s)
    MOCK.worldHours = 4005
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 5, "powered hours are credited")
    check(MOCK.printLogContains("Laboratory analyzer powered: 5.00 h since last check credited"), "credited hours logged")

    power = false
    MOCK.worldHours = 4010
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 5, "unpowered processing does not advance")
    check(MOCK.printLogContains("Laboratory analyzer UNPOWERED: 5.00 h since last check not credited (paused)"), "paused hours logged")
    MOCK.worldHours = 4030
    eq(AC_LaboratoryAnalyzer.getState(analyzer), "processing", "still processing after a long outage")
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 5, "still no progress without power")

    power = true
    MOCK.worldHours = 4032
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 7, "restored power resumes processing from the last check")

    MOCK.clearPrintLog()
    for i = 1, 20 do
        fillAnalyzerMenu(player, analyzer)
        AC_LaboratoryAnalyzer.getStatusInfo(analyzer)
        AC_LaboratoryAnalyzer.canPickUp(analyzer)
    end
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 7, "opening the menu repeatedly creates no progress")
    check(not MOCK.printLogContains("since last check"), "no log lines when no time passed")

    -- Documented limitation: an outage nobody observed, which ended
    -- before the next check, is credited as powered time.
    MOCK.worldHours = 4040
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 15, "LIMITATION: unobserved outage counted as powered")

    -- Documented limitation, other direction: power lost just before a
    -- check discards the powered hours since the previous check.
    MOCK.worldHours = 4044
    power = false
    eq(AC_LaboratoryAnalyzer.getHoursRemaining(analyzer), total - 15, "LIMITATION: powered hours lost when power fails before the check")
    power = true

    MOCK.worldHours = 4044 + (total - 15)
    eq(AC_LaboratoryAnalyzer.getState(analyzer), "ready", "completes once enough powered time is credited")
    eq(#player.xpLog, 0, "no XP from processing")

    MOCK.capturePrint(false)
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

    -- The English file and the fallback written next to the key say the
    -- same thing, so the text a player reads does not depend on whether the
    -- translation file loaded, and neither can drift from the other.
    local english = {}
    for key, value in string.gmatch(json, '"([^"]+)"%s*:%s*"([^"]*)"') do english[key] = value end
    local compared, different = 0, {}
    for _, name in ipairs(MOCK.MOD_FILES) do
        local file = io.open(LUA .. name .. ".lua", "r")
        local source = file:read("*a")
        file:close()
        for key, fallback in string.gmatch(source, '"(IGUI_AmmoMaking_[%w_]+)",%s*"([^"]*)"') do
            compared = compared + 1
            if english[key] ~= fallback then table.insert(different, key) end
        end
    end
    check(compared > 100, "fallbacks found beside their keys (" .. compared .. ")")
    eq(#different, 0, "every fallback equals the English file's text: " .. table.concat(different, ", "))
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
    -- One tree, grouped by stage: no level of it is a long flat list.
    local expected = {
        { "Geology", {
            "Inspect Current Tile", "Survey Current Area (3x3)", "Show Geology Seed",
            "Inspect Clicked Tile Objects (sprites, analyzer state)",
            "Reset Depletion: Current Tile", "Reset Depletion: 3x3 Area",
            "Spawn Sampling Kit (shovel + assay kits)", "Spawn Mining Kit (pickaxes)",
            "Spawn Assayed Sample (current 3x3)",
        } },
        { "Analyzer", { "Spawn Laboratory Analyzer" } },
        { "Metallurgy", {
            "Spawn Metallurgy Kit (furnace tools + materials)",
            "Spawn Case Stock Kit (brass + forge and punch tools)",
            "Spawn Recycling Kit (one mixed batch per scrapping recipe + one recast)",
            "Inspect Station Recipes",
        } },
        { "Ammunition", {
            "Spawn Calibre Kit", "Spawn Primer and Powder Kit", "Print Calibre Definitions",
            "Print Primer Families", "Verify Ammo Dependencies", "Inspect Ammo Components (inventory)",
        } },
        { "Set Ammo Making Level" },
        { "Run Compatibility Check" },
    }
    eq(#root.submenu.options, #expected, "six entries at the top of the debug tree")
    for index, group in ipairs(expected) do
        local entry = root.submenu.options[index]
        eq(entry and entry.name, group[1], "debug entry " .. index .. " is " .. group[1])
        if group[2] then
            check(entry and entry.submenu ~= nil, group[1] .. " is a submenu")
            check(entry and entry.fn == nil, group[1] .. " itself does nothing when clicked")
            local names = entry and entry.submenu and entry.submenu:names() or {}
            eq(table.concat(names, " | "), table.concat(group[2], " | "), group[1] .. " entries")
            check(#names <= 10, group[1] .. " is not a long flat list")
        end
    end
    -- Every leaf of the tree does something.
    local function leaves(menu, path)
        for _, option in ipairs(menu.options) do
            if option.submenu then
                leaves(option.submenu, path .. option.name .. " > ")
            else
                eq(type(option.fn), "function", "debug entry has an action: " .. path .. option.name)
            end
        end
    end
    leaves(root.submenu, "")
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

section("Debug analyzer tools: gated, clicked analyzer only, no XP (mocked placed object)")
do
    local x, y = 920, 30
    local square = poweredLabSquare(x, y)
    local player = MOCK.newPlayer({ square = square })
    local analyzer = placeAnalyzerObject(square)
    local hours = AC_LaboratoryAnalyzer.CONFIG.processingHours
    local s = makeSample(x, y, 1, "Good", "None")
    s.modData.trueCopper = 70
    s.modData.trueZinc = 0
    player.inventory:addItem(s)
    MOCK.worldHours = 5000
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    -- The analyzer entries live in the Analyzer submenu of the debug tree.
    local function debugMenu(objects)
        MOCK.players = { player }
        local ctx = MOCK.newContext()
        Events.OnFillWorldObjectContextMenu.fire(0, ctx, objects, false)
        local root = ctx:find("Ammo Making Debug")
        local group = root and root.submenu:find("Analyzer")
        return group and group.submenu, ctx
    end

    -- Normal mode: nothing, and the helper itself refuses
    MOCK.debug = false
    local menu, ctx = debugMenu({ analyzer })
    eq(menu, nil, "no debug submenu in normal mode, even on an analyzer")
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, s)
    local ok, why = AC_LaboratoryAnalyzer.debugFinishProcessing(analyzer)
    eq(ok, false, "helper refuses outside debug mode")
    eq(why, "debug_only", "reason: debug_only")
    eq(analyzer.modData.labAnalyzerState, "processing", "state unchanged outside debug mode")
    eq(analyzer.modData.labRemainingHours, hours, "remaining time unchanged outside debug mode")

    -- Debug mode: entries only when an analyzer was clicked
    MOCK.debug = true
    menu = debugMenu({ analyzer })
    check(menu and menu:find("Inspect Analyzer State") ~= nil, "inspect entry for a clicked analyzer")
    check(menu and menu:find("Complete Analyzer Job (no XP; collect normally)") ~= nil, "complete entry for a clicked analyzer")
    local floor = { getSquare = function() return square end }
    menu = debugMenu({ floor })
    check(menu and menu:find("Inspect Analyzer State") ~= nil, "analyzer found via the clicked square")
    local grass = MOCK.newSquare(x + 3, y, 0, GRASS)
    menu = debugMenu({ { getSquare = function() return grass end } })
    check(menu and menu:find("Inspect Analyzer State") == nil, "no analyzer entries without an analyzer")
    check(menu and menu:find("Complete Analyzer Job (no XP; collect normally)") == nil, "no complete entry without an analyzer")

    -- Inspect is read-only
    MOCK.worldHours = 5003
    local lastUpdate = analyzer.modData.labLastUpdateAt
    MOCK.clearPrintLog()
    check(pcall(AC_GeologyDebug.inspectAnalyzer, player, analyzer), "inspect runs")
    check(MOCK.printLogContains("state=processing storedSample=true sample at " .. x), "inspect prints the state")
    check(MOCK.printLogContains("pending=3.00 h"), "inspect prints uncredited hours")
    eq(analyzer.modData.labLastUpdateAt, lastUpdate, "inspect does not advance the analyzer")
    eq(analyzer.modData.labRemainingHours, hours, "inspect credits nothing")
    check(pcall(AC_GeologyDebug.inspectAnalyzer, player, MOCK.newWorldObject()), "inspect tolerates a non-analyzer")

    -- Complete: ready, same sample and result, no XP, CONFIG untouched
    local rolled = analyzer.modData.labCopperResult
    menu = debugMenu({ analyzer })
    menu:invoke(menu:find("Complete Analyzer Job (no XP; collect normally)"))
    eq(analyzer.modData.labAnalyzerState, "ready", "job complete -> ready")
    eq(analyzer.modData.storedSample, true, "sample still stored")
    eq(analyzer.modData.stored_sampleX, x, "same sample stored")
    eq(analyzer.modData.labCopperResult, rolled, "result rolled at start is kept")
    eq(#player.xpLog, 0, "debug completion grants no XP")
    eq(AC_LaboratoryAnalyzer.CONFIG.processingHours, hours, "production duration unchanged")
    check(MOCK.printLogContains("DEBUG: analyzer processing finished early"), "debug completion logged")
    check(MOCK.printLogContains("Laboratory analyzer completed sample " .. x), "normal completion path ran")

    -- Refusals: ready, idle, not an analyzer
    eq(select(2, AC_LaboratoryAnalyzer.debugFinishProcessing(analyzer)), "not_processing", "ready analyzer refused")
    eq(select(2, AC_LaboratoryAnalyzer.debugFinishProcessing(MOCK.newWorldObject())), "invalid_analyzer", "ordinary object refused")
    HaloTextHelper.clear()
    AC_GeologyDebug.completeAnalyzerJob(player, analyzer)
    eq(HaloTextHelper.last(), "Analyzer is not processing (not_processing)", "refusal shown")

    -- Normal collection still grants the XP, exactly once
    ctx = fillAnalyzerMenu(player, analyzer)
    ctx:invoke(ctx:find("Collect Laboratory Sample"))
    eq(#player.xpLog, 1, "collection after debug completion grants XP once")
    eq(player.xpLog[1], AC_LaboratoryAnalyzer.CONFIG.assayXP, "normal laboratory XP")
    eq(select(2, AC_LaboratoryAnalyzer.debugFinishProcessing(analyzer)), "not_processing", "idle analyzer refused")

    -- Unpowered analyzer can still be completed for testing
    local back = player.inventory:getItemsFromFullType("AmmoMaking.GeologicalSample"):get(0)
    back.modData.assayRank = 1                              -- re-analysable for the test
    AC_LaboratoryAnalyzer.startAssay(player, analyzer, back)
    square.haveElectricity = function() return false end
    eq(AC_LaboratoryAnalyzer.debugFinishProcessing(analyzer), true, "debug completion ignores power")
    square.haveElectricity = function() return true end
    eq(#player.xpLog, 1, "still no extra XP")

    MOCK.capturePrint(false)
    MOCK.debug = false
    MOCK.worldHours = 0
end

------------------------------------------------
-- METALLURGY
------------------------------------------------
--
-- Metallurgy (ore to brass) and case stock (brass to case cups). These
-- sections read the mod's own script files and AC_Materials. They prove
-- that the files say what the design says and that the numbers conserve
-- metal. They do NOT prove the engine loads the recipes, shows
-- them at a furnace or calls the callbacks: that needs the game.

local SCRIPTS = ROOT .. "/mod/AmmoMaking/42/media/scripts/"
local TRANSLATE = ROOT .. "/mod/AmmoMaking/common/media/lua/shared/Translate/EN/"

local function readFile(path)
    local handle = assert(io.open(path, "r"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (string.gsub(text, "\r", ""))
end

local function stripComments(text)
    return (string.gsub(text, "/%*.-%*/", ""))
end

local function trim(text)
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function split(text, separator)
    local parts = {}
    for part in string.gmatch(text, "([^" .. separator .. "]+)") do
        table.insert(parts, trim(part))
    end
    return parts
end

-- Parses "module X { <kind> Name { key = value, ... sub { line, } } }" into
-- { module = "X", blocks = { { kind, name, fields = {}, fieldOrder = {},
--   sections = { inputs = { "line", ... } } } } }. Enough for the item and
-- craftRecipe blocks this mod writes; not a general script parser.
local function parseScript(path)
    local text = stripComments(readFile(path))
    local moduleName, body = string.match(text, "^%s*module%s+([%w_]+)%s*(%b{})%s*$")
    assert(moduleName, "one module block expected in " .. path)
    body = string.sub(body, 2, -2)
    local result = { module = moduleName, blocks = {} }
    for kind, name, block in string.gmatch(body, "([%a]+)%s+([%w_]+)%s*(%b{})") do
        local entry = { kind = kind, name = name, fields = {}, fieldOrder = {}, sections = {} }
        local inner = string.sub(block, 2, -2)
        inner = string.gsub(inner, "([%a]+)%s*(%b{})", function(sectionName, sectionBody)
            local lines = {}
            for line in string.gmatch(string.sub(sectionBody, 2, -2), "([^\n]+)") do
                line = trim(line)
                if line ~= "" then
                    table.insert(lines, (string.gsub(line, ",$", "")))
                end
            end
            entry.sections[sectionName] = lines
            return ""
        end)
        for line in string.gmatch(inner, "([^\n]+)") do
            local key, value = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*,%s*$")
            if key then
                entry.fields[key] = value
                table.insert(entry.fieldOrder, key)
            else
                assert(trim(line) == "", "unparsed line in " .. name .. ": " .. line)
            end
        end
        table.insert(result.blocks, entry)
    end
    return result
end

-- "item 1 [A;B] mode:keep flags[X;Y]" / "item 4 tags[base:charcoal]" /
-- "item 10 Base.CopperScrap" (output form)
local function parseItemLine(line)
    local count, rest = string.match(line, "^item%s+(%d+)%s+(.+)$")
    assert(count, "not an item line: " .. line)
    local parsed = { count = tonumber(count) }
    local tags = string.match(rest, "tags%[([^%]]*)%]")
    if tags then
        parsed.tags = split(tags, ";")
        rest = string.gsub(rest, "tags%[[^%]]*%]", "", 1)
    end
    local flags = string.match(rest, "flags%[([^%]]*)%]")
    if flags then
        parsed.flags = split(flags, ";")
        rest = string.gsub(rest, "flags%[[^%]]*%]", "", 1)
    end
    local mode = string.match(rest, "mode:(%a+)")
    if mode then
        parsed.keep = (mode == "keep") or nil
        parsed.mode = mode
        rest = string.gsub(rest, "mode:%a+", "", 1)
    end
    local items = string.match(rest, "%[([^%]]*)%]")
    if items then
        parsed.items = split(items, ";")
        rest = string.gsub(rest, "%[[^%]]*%]", "", 1)
    end
    rest = trim(rest)
    if rest ~= "" then
        parsed.item = rest
    end
    return parsed
end

local function sameList(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function listText(list)
    return table.concat(list or {}, ";")
end

local itemScript = parseScript(SCRIPTS .. "AC_Items.txt")
local recipeScript = parseScript(SCRIPTS .. "AC_Recipes.txt")

local declaredItems = {}
for _, block in ipairs(itemScript.blocks) do
    declaredItems[itemScript.module .. "." .. block.name] = block
end

section("Material items: script definitions follow the vanilla metal items")
do
    eq(itemScript.module, "AmmoMaking", "items live in module AmmoMaking")

    local seen, duplicates = {}, {}
    for _, block in ipairs(itemScript.blocks) do
        eq(block.kind, "item", block.name .. " is an item block")
        if seen[block.name] then table.insert(duplicates, block.name) end
        seen[block.name] = true
    end
    eq(#duplicates, 0, "no duplicate item ids: " .. table.concat(duplicates, ", "))

    -- Fields and tags seen on the vanilla 42.20.4 metal items
    -- (media/scripts/generated/items/normal.txt). Anything else would be a
    -- guessed field.
    local knownFields = {
        DisplayName = true, DisplayCategory = true, ItemType = true, Weight = true, Icon = true,
        StaticModel = true, WorldStaticModel = true, Tags = true, RequiresEquippedBothHands = true,
    }
    local knownTags = { ["base:hasmetal"] = true, ["base:heavyitem"] = true, ["base:ingot"] = true }
    for _, block in ipairs(itemScript.blocks) do
        for _, key in ipairs(block.fieldOrder) do
            check(knownFields[key], block.name .. " uses only fields vanilla metal items use (" .. key .. ")")
        end
        for _, tag in ipairs(split(block.fields.Tags or "", ";")) do
            check(knownTags[tag], block.name .. " uses only vanilla tags (" .. tag .. ")")
        end
        eq(block.fields.ItemType, "base:normal", block.name .. " item type")
        check(block.fields.DisplayName ~= nil, block.name .. " has a display name")
    end

    -- Values recorded from Base.CopperOre / CopperScrap / CopperIngot.
    local ore = declaredItems["AmmoMaking.ZincOre"]
    local scrap = declaredItems["AmmoMaking.ZincScrap"]
    local ingot = declaredItems["AmmoMaking.ZincIngot"]
    check(ore and scrap and ingot, "zinc ore, scrap and ingot are declared")
    eq(tonumber(ore.fields.Weight), 40.0, "zinc ore weighs what copper ore weighs")
    eq(ore.fields.RequiresEquippedBothHands, "true", "zinc ore is two-handed like copper ore")
    eq(ore.fields.Tags, "base:hasmetal;base:heavyitem", "zinc ore tags")
    eq(tonumber(scrap.fields.Weight), 0.5, "zinc scrap weighs what copper scrap weighs")
    eq(scrap.fields.Tags, "base:hasmetal", "zinc scrap tags")
    eq(tonumber(ingot.fields.Weight), 6.0, "zinc ingot weighs what copper ingot weighs")
    eq(ingot.fields.Tags, "base:hasmetal;base:ingot", "zinc ingot tags")
    for _, block in ipairs({ ore, scrap, ingot }) do
        eq(block.fields.DisplayCategory, "Material", block.name .. " category")
        check(block.fields.Icon ~= nil and block.fields.WorldStaticModel ~= nil, block.name .. " has an icon and a world model")
    end

    -- Case stock. The small sheet copies Base.SmallCopperSheet (0.5).
    local sheet = declaredItems["AmmoMaking.SmallBrassSheet"]
    local cup = declaredItems["AmmoMaking.BrassCaseCup"]
    check(sheet and cup, "small brass sheet and case cup are declared")
    eq(tonumber(sheet.fields.Weight), 0.5, "small brass sheet weighs what a small copper sheet weighs")
    check(tonumber(cup.fields.Weight) * 2 <= tonumber(sheet.fields.Weight), "two cups do not outweigh the sheet they come from")
    for _, block in ipairs({ sheet, cup }) do
        eq(block.fields.DisplayCategory, "Material", block.name .. " category")
        eq(block.fields.Tags, "base:hasmetal", block.name .. " tags")
        check(block.fields.Icon ~= nil and block.fields.WorldStaticModel ~= nil, block.name .. " has an icon and a world model")
    end
    -- Vanilla has the powder and the round; the mod must not copy them.
    for _, name in ipairs({ "GunPowder", "Bullets9mm", "Round9mm", "Cartridge9mm", "Lead", "LeadOre", "Sulfur", "Nitrate" }) do
        check(declaredItems["AmmoMaking." .. name] == nil, "no mod copy or speculative resource: " .. name)
    end

    -- Vanilla already has these; the mod must not shadow them.
    for _, name in ipairs({ "CopperOre", "CopperScrap", "CopperIngot", "BrassIngot", "BrassScrap" }) do
        check(declaredItems["AmmoMaking." .. name] == nil, "no AmmoMaking duplicate of vanilla " .. name)
    end

    -- Every id the materials module names is declared or probed.
    local probed = {}
    for _, id in ipairs(AC_Compat.REQUIRED_ITEMS) do probed[id] = true end
    for name, id in pairs(AC_Materials.ITEMS) do
        if string.sub(id, 1, 11) == "AmmoMaking." then
            check(declaredItems[id] ~= nil, "AC_Materials.ITEMS." .. name .. " is declared in AC_Items.txt")
        end
        check(probed[id], "AC_Materials.ITEMS." .. name .. " (" .. id .. ") is probed by AC_Compat")
    end
    for id in pairs(AC_Materials.UNITS) do
        check(probed[id], "tracked item " .. id .. " is probed by AC_Compat")
    end
    eq(AC_Geology.ITEMS.ZincOre, AC_Materials.ITEMS.ZincOre, "mining and metallurgy agree on the zinc ore id")
    eq(AC_Geology.ITEMS.CopperOre, AC_Materials.ITEMS.CopperOre, "mining and metallurgy agree on the copper ore id")
end

section("Station recipes: AC_Recipes.txt equals AC_Materials.RECIPES")
do
    -- Vanilla keeps every recipe in module Base (42.20.4: all 1004 module
    -- declarations), and a name without a dot is looked up there.
    eq(recipeScript.module, "Base", "recipes live in module Base like vanilla recipes")
    eq(#recipeScript.blocks, #AC_Materials.RECIPES, "one script block per mirrored recipe")

    local byId, duplicates = {}, {}
    for _, block in ipairs(recipeScript.blocks) do
        eq(block.kind, "craftRecipe", block.name .. " is a craftRecipe block")
        if byId[block.name] then table.insert(duplicates, block.name) end
        byId[block.name] = block
        eq(string.sub(block.name, 1, 11), "AmmoMaking_", block.name .. " carries the mod prefix")
        check(not string.find(block.name, "[^%w_]"), block.name .. " has no spaces or punctuation")
    end
    eq(#duplicates, 0, "no duplicate recipe ids: " .. table.concat(duplicates, ", "))

    local mirrorIds = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        check(not mirrorIds[recipe.id], "mirror id unique: " .. recipe.id)
        mirrorIds[recipe.id] = true
    end

    -- Only what the vanilla 42.20.4 template recipes use (furnace recipes,
    -- Forge_Copper_Sheet, the scrap-armour cold work, NailSpikeWeapon),
    -- plus OnCreate.
    local knownFields = { time = true, timedAction = true, Tags = true, category = true, OnCreate = true }
    local knownBenchTags = { PrimitiveFurnace = true, Furnace = true, PrimitiveForge = true, Forge = true, AnySurfaceCraft = true }
    local knownTimedActions = { HammerMetalStanding = true, MakingHammer_Surface = true, Making = true }
    local knownCategories = { Blacksmithing = true, Metalworking = true, Tools = true, Weaponry = true, Miscellaneous = true }
    local knownFlags = { IsEmpty = true, MayDegradeLight = true, MayDegradeVeryLight = true, Prop1 = true, Prop2 = true }
    local destroyLines = 0
    local knownItemTags = {
        ["base:charcoal"] = true, ["base:crudetongs"] = true, ["base:tongs"] = true,
        ["base:hammer"] = true, ["base:clubhammer"] = true, ["base:metalworkingpliers"] = true,
        ["base:metalworkingpunch"] = true, ["base:smallpunch"] = true,
        ["base:ballpeenhammer"] = true, ["base:whetstone"] = true, ["base:file"] = true,
        ["base:mortarpestle"] = true,
    }
    local probed = {}
    for _, id in ipairs(AC_Compat.REQUIRED_ITEMS) do probed[id] = true end

    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local block = byId[recipe.id]
        check(block ~= nil, recipe.id .. " exists in AC_Recipes.txt")
        if block then
            for _, key in ipairs(block.fieldOrder) do
                check(knownFields[key], recipe.id .. " uses only verified recipe fields (" .. key .. ")")
            end
            -- The engine drops these for a Lua-registered perk.
            check(block.fields.SkillRequired == nil, recipe.id .. " has no SkillRequired line")
            check(block.fields.xpAward == nil, recipe.id .. " has no xpAward line")

            eq(tonumber(block.fields.time), recipe.time, recipe.id .. " time")
            eq(block.fields.Tags, recipe.benchTag, recipe.id .. " bench tag")
            check(knownBenchTags[block.fields.Tags], recipe.id .. " attaches to a vanilla bench tag")
            eq(block.fields.category, recipe.category, recipe.id .. " category")
            check(knownCategories[block.fields.category], recipe.id .. " uses a vanilla crafting category")
            eq(block.fields.timedAction, recipe.timedAction, recipe.id .. " timed action")
            check(recipe.timedAction == nil or knownTimedActions[recipe.timedAction], recipe.id .. " timed action is one a vanilla template uses")
            if block.fields.Tags == "PrimitiveFurnace" or block.fields.Tags == "Furnace" then
                eq(block.fields.timedAction, nil, recipe.id .. " has no timed action, like vanilla furnace recipes")
            end
            eq(block.fields.OnCreate, "AC_Materials." .. recipe.callback, recipe.id .. " OnCreate")
            eq(type(AC_Materials[recipe.callback]), "function", recipe.id .. " OnCreate target exists")

            local inputs = block.sections.inputs or {}
            eq(#inputs, #recipe.inputs, recipe.id .. " input count")
            for i, line in ipairs(inputs) do
                local parsed = parseItemLine(line)
                local mirror = recipe.inputs[i] or {}
                eq(parsed.count, mirror.count, recipe.id .. " input " .. i .. " count")
                check(sameList(parsed.items, mirror.items), recipe.id .. " input " .. i .. " items (" .. listText(parsed.items) .. ")")
                check(sameList(parsed.tags, mirror.tags), recipe.id .. " input " .. i .. " tags (" .. listText(parsed.tags) .. ")")
                check(sameList(parsed.flags, mirror.flags), recipe.id .. " input " .. i .. " flags (" .. listText(parsed.flags) .. ")")
                eq(parsed.keep == true, mirror.keep == true, recipe.id .. " input " .. i .. " keep")
                -- mode:destroy is how vanilla consumes a rag without handing
                -- back its ReplaceOnUse item; only a wad line may use it.
                eq(parsed.mode == "destroy", mirror.destroy == true, recipe.id .. " input " .. i .. " destroy")
                check(parsed.mode == nil or parsed.mode == "keep" or parsed.mode == "destroy", recipe.id .. " input " .. i .. " uses no other mode")
                check(not (mirror.keep and mirror.destroy), recipe.id .. " input " .. i .. " is not both kept and destroyed")
                if mirror.destroy then
                    destroyLines = destroyLines + 1
                    check(sameList(mirror.items, AC_Calibres.WAD.items), recipe.id .. " input " .. i .. ": only the wad line is mode:destroy")
                end
                check(parsed.item == nil, recipe.id .. " input " .. i .. " has no stray text")
                check((parsed.items ~= nil) ~= (parsed.tags ~= nil), recipe.id .. " input " .. i .. " is either items or tags")
                for _, flag in ipairs(parsed.flags or {}) do
                    check(knownFlags[flag], recipe.id .. " input flag seen in the vanilla templates (" .. flag .. ")")
                end
                for _, tag in ipairs(parsed.tags or {}) do
                    check(knownItemTags[tag], recipe.id .. " input tag seen in the vanilla templates (" .. tag .. ")")
                end
                for _, id in ipairs(parsed.items or {}) do
                    check(probed[id], recipe.id .. " input item is probed by AC_Compat (" .. id .. ")")
                    check(string.sub(id, 1, 5) == "Base." or declaredItems[id] ~= nil, recipe.id .. " input item exists (" .. id .. ")")
                end
            end

            local outputs = block.sections.outputs or {}
            eq(#outputs, #recipe.outputs, recipe.id .. " output count")
            for i, line in ipairs(outputs) do
                local parsed = parseItemLine(line)
                local mirror = recipe.outputs[i] or {}
                eq(parsed.count, mirror.count, recipe.id .. " output " .. i .. " count")
                eq(parsed.item, mirror.item, recipe.id .. " output " .. i .. " item")
                check(probed[parsed.item], recipe.id .. " output item is probed by AC_Compat (" .. tostring(parsed.item) .. ")")
                check(string.sub(parsed.item or "", 1, 5) == "Base." or declaredItems[parsed.item] ~= nil, recipe.id .. " output item exists")
            end
        end
    end

    local wadded = 0
    for _, calibre in ipairs(AC_Calibres.LIST) do
        if calibre.wads > 0 then wadded = wadded + 1 end
    end
    eq(destroyLines, wadded, "one mode:destroy line per calibre that takes a wad")

    -- Design decisions pinned.
    eq(AC_Materials.getRecipe("AmmoMaking_SmeltZincOre").benchTag, "PrimitiveFurnace", "zinc ore smelts where copper ore smelts")
    for _, id in ipairs({ "AmmoMaking_CastCopperIngot", "AmmoMaking_CastZincIngot", "AmmoMaking_CastBrassIngots" }) do
        eq(AC_Materials.getRecipe(id).benchTag, "Furnace", id .. " casts where vanilla casts")
    end
    local brassOut = AC_Materials.getRecipe("AmmoMaking_CastBrassIngots").outputs[1]
    eq(brassOut.item, "Base.BrassIngot", "brass is the vanilla item")
    eq(AC_Materials.getRecipe("nope"), nil, "unknown recipe id")
    eq(AC_Materials.getRecipe("AmmoMaking_ForgeSmallBrassSheets").benchTag, "PrimitiveForge", "brass sheets are forged where copper sheets are")
    eq(AC_Materials.getRecipe("AmmoMaking_PunchBrassCaseCups").benchTag, "AnySurfaceCraft", "cups are punched cold on a surface")
    eq(#AC_Materials.RECIPES, 6 + 1 + #AC_Calibres.PRIMERS * #AC_Calibres.COMPOUND_SOURCES + 4 * #AC_Calibres.LIST + #AC_Recycling.buildGroups() + 1,
        "metallurgy 4, case stock 2, gunpowder 1, primers per family and source, four per calibre, one scrapping recipe per brass size and the recast")
    eq(#AC_Materials.RECIPES, 55, "fifty-five recipes")

    -- The script body is exactly what tests/render_recipes.lua makes of the
    -- mirror: the file is generated, never typed.
    local header, body = RENDER.splitHeader(readFile(SCRIPTS .. "AC_Recipes.txt"))
    check(header ~= "" and string.find(header, "GENERATED", 1, true) ~= nil, "the script header says the body is generated")
    eq(body, RENDER.renderModule(AC_Materials.RECIPES), "AC_Recipes.txt body equals the rendered mirror (run tests/write_recipes.lua)")

    local alloys = 0
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        if recipe.alloy then alloys = alloys + 1 end
    end
    eq(alloys, 1, "exactly one alloy recipe")

    -- The audit of every recipe, one row at a time: what the script and
    -- the mirror must agree on, and what each recipe must declare. A recipe
    -- in one and not the other, a missing callback, name or material
    -- declaration fails here by name.
    local names = {}
    for key, value in string.gmatch(readFile(TRANSLATE .. "Recipes.json"), '"([^"]+)"%s*:%s*"([^"]*)"') do names[key] = value end
    local inMirror = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        inMirror[recipe.id] = true
        check(byId[recipe.id] ~= nil, recipe.id .. ": in the mirror and in the script")
        check(type(recipe.callback) == "string" and type(AC_Materials[recipe.callback]) == "function", recipe.id .. ": has its OnCreate callback")
        check(names[recipe.id] ~= nil and names[recipe.id] ~= "", recipe.id .. ": has a name")
        check(type(recipe.time) == "number" and recipe.time >= 20, recipe.id .. ": takes at least 20, so the skill speed-up applies")
        check(type(recipe.benchTag) == "string" and type(recipe.category) == "string", recipe.id .. ": names its station tag and category")
        local level = AC_Materials.getRequiredLevel(recipe)
        check(level >= 0 and level <= 10 and level == math.floor(level), recipe.id .. ": a whole Ammo Making level from 0 to 10")
        local xp = AC_Materials.getRecipeXP(recipe)
        check(xp >= 0 and xp == math.floor(xp), recipe.id .. ": a whole, non-negative XP amount")
        -- Material declaration: every output is either tracked or a declared tool,
        -- and every consumed item named by id is tracked or a known untracked input.
        local untracked = { ["Base.SteelBarQuarter"] = true, ["Base.Fertilizer"] = true }
        for _, id in ipairs(AC_Calibres.WAD.items) do untracked[id] = true end
        for _, output in ipairs(recipe.outputs) do
            check(recipe.tool or AC_Materials.UNITS[output.item] ~= nil, recipe.id .. ": its output " .. tostring(output.item) .. " has a material declaration")
            check(output.count >= 1, recipe.id .. ": makes at least one")
        end
        local consumes = false
        for _, input in ipairs(recipe.inputs) do
            check(input.count >= 1, recipe.id .. ": every input line asks for at least one")
            if not input.keep then
                consumes = true
                for _, id in ipairs(input.items or {}) do
                    check(AC_Materials.UNITS[id] ~= nil or untracked[id], recipe.id .. ": its input " .. id .. " has a material declaration or is a known untracked input")
                end
            end
        end
        check(consumes, recipe.id .. ": consumes something")
    end
    for _, block in ipairs(recipeScript.blocks) do
        check(inMirror[block.name], block.name .. ": in the script and in the mirror")
    end
    for id in pairs(names) do
        check(inMirror[id], id .. ": a recipe name belongs to a recipe")
    end

    -- docs/DEVELOPMENT.md carries the audit table, rendered from the mirror.
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local document = readFile(ROOT .. "/docs/DEVELOPMENT.md")
    local from = string.find(document, BALANCE.AUDIT_START, 1, true)
    local _, to = string.find(document, BALANCE.AUDIT_FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the development document has the recipe audit markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderRecipeAuditBlock(), "the recipe audit table equals the rendered mirror (run tests/write_recipes.lua)")
    local families = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local family = BALANCE.recipeFamily(recipe)
        families[family] = (families[family] or 0) + 1
    end
    eq(families.metallurgy, 4, "four metallurgy recipes")
    eq(families.caseStock, 2, "two case-stock recipes")
    eq(families.powder, 1, "one gunpowder recipe")
    eq(families.primer, 8, "eight primer recipes")
    for _, step in ipairs({ "dieSet", "case", "bullet", "assemble" }) do eq(families[step], #AC_Calibres.LIST, "one " .. step .. " recipe per calibre") end
    eq(families.scrap, 3, "three scrapping recipes")
    eq(families.recast, 1, "one recast")
    check(string.find(BALANCE.renderRecipeAudit(), "| **All** | **55** |", 1, true) ~= nil, "the audit table counts 55 recipes")
end

section("Material conservation: no recipe or chain creates metal")
do
    local U = AC_Materials.UNITS
    local INGOT = AC_Materials.CONFIG.unitsPerIngot
    eq(INGOT, 100, "accounting unit")
    eq(U["Base.CopperOre"].units, INGOT, "one copper ore is one ingot of metal")
    eq(U["AmmoMaking.ZincOre"].units, INGOT, "one zinc ore is one ingot of metal")
    eq(U["Base.CopperIngot"].units, INGOT, "copper ingot")
    eq(U["AmmoMaking.ZincIngot"].units, INGOT, "zinc ingot")
    eq(U["AmmoMaking.SmallBrassSheet"].units * 10, INGOT, "ten small brass sheets per ingot")
    eq(U["AmmoMaking.BrassCaseCup"].units * 2, U["AmmoMaking.SmallBrassSheet"].units, "two cups per small sheet")
    eq(U["Base.BrassScrap"].units, U["Base.CopperScrap"].units, "brass scrap counts like copper scrap")
    for id, entry in pairs(U) do
        check((entry.contents ~= nil) ~= (entry.metal ~= nil), id .. " is either one material or a contents table")
        for material, units in pairs(entry.contents or { [entry.metal] = entry.units }) do
            check(type(units) == "number" and units == math.floor(units) and units > 0, id .. " has a whole, positive amount of " .. tostring(material))
        end
    end
    eq(U["Base.CopperScrap"].units * 10, U["Base.CopperIngot"].units, "ten copper scrap per ingot")
    eq(U["AmmoMaking.ZincScrap"].units * 10, U["AmmoMaking.ZincIngot"].units, "ten zinc scrap per ingot")
    eq(U["Base.BrassIngot"].units, AC_Materials.CONFIG.unitsPerIngot, "a brass ingot is one ingot")

    local function total(units)
        local sum = 0
        for _, v in pairs(units) do sum = sum + v end
        return sum
    end

    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local ok, reason = AC_Materials.checkConservation(recipe)
        check(ok, recipe.id .. " conserves metal: " .. tostring(reason))
        local consumed, created = AC_Materials.getRecipeUnits(recipe)
        if recipe.source then
            -- The one material it brings in from untracked raw inputs.
            created[recipe.source] = nil
        end
        if recipe.loss then
            -- Scrapping is the one kind of recipe that must come out short.
            check(total(created) < total(consumed), recipe.id .. " hands back less than it takes")
            eq(created.brass, consumed.brass * AC_Recycling.getRecovery(), recipe.id .. " hands back the recycling share of the brass")
        else
            eq(total(created), total(consumed), recipe.id .. " units out equal units in")
            for material, units in pairs(created) do
                local parts = AC_Materials.ALLOYS[material]
                if not parts then
                    eq(units, consumed[material], recipe.id .. " " .. material .. " out equals " .. material .. " in")
                end
            end
        end
        if recipe.tool then
            eq(total(created), 0, recipe.id .. " makes a tool, no tracked material")
        elseif not recipe.source then
            check(total(created) > 0, recipe.id .. " produces tracked material")
        end

        local charcoalInputs = 0
        for _, input in ipairs(recipe.inputs) do
            if input.keep then
                for _, id in ipairs(input.items or {}) do
                    check(U[id] == nil, recipe.id .. " keeps no metal-bearing item (" .. id .. ")")
                end
            end
            if input.tags and input.tags[1] == "base:charcoal" then
                charcoalInputs = charcoalInputs + 1
                check(not input.keep, recipe.id .. " consumes its charcoal")
                check(input.count >= 1, recipe.id .. " charcoal count")
            end
        end
        -- Hot work burns charcoal; cold work on a surface has none, except
        -- gunpowder, where charcoal is an ingredient.
        local expectedCharcoal = 1
        if recipe.benchTag == "AnySurfaceCraft" and recipe.source ~= "powder" then expectedCharcoal = 0 end
        eq(charcoalInputs, expectedCharcoal, recipe.id .. " charcoal inputs")

        -- Tools named by tag are never consumed (charcoal is the only
        -- consumed tag input), and every die set is kept.
        for _, input in ipairs(recipe.inputs) do
            if input.tags and input.tags[1] ~= "base:charcoal" then
                check(input.keep == true, recipe.id .. " keeps its tool " .. input.tags[1])
            end
            for _, id in ipairs(input.items or {}) do
                if AC_Calibres.identify(id) == "dieSet" then
                    check(input.keep == true, recipe.id .. " keeps the die set")
                end
            end
        end
    end

    -- Casting recipes keep exactly crucible, tongs and mold.
    for _, id in ipairs({ "AmmoMaking_CastCopperIngot", "AmmoMaking_CastZincIngot", "AmmoMaking_CastBrassIngots", "AmmoMaking_CastBrassIngotFromScrap" }) do
        local kept = {}
        for _, input in ipairs(AC_Materials.getRecipe(id).inputs) do
            if input.keep then table.insert(kept, (input.items or input.tags)[1]) end
        end
        table.sort(kept)
        eq(table.concat(kept, ","), "Base.CeramicCrucible,Base.ClayIngotMold,base:crudetongs", id .. " keeps crucible, mold and tongs")
    end
    local smelt = AC_Materials.getRecipe("AmmoMaking_SmeltZincOre")
    for _, input in ipairs(smelt.inputs) do
        check(not input.keep, "ore smelting needs no tool, like vanilla copper")
    end

    -- Brass: 7 copper + 3 zinc -> 10 brass, exactly.
    local brass = AC_Materials.getRecipe("AmmoMaking_CastBrassIngots")
    local consumed, created = AC_Materials.getRecipeUnits(brass)
    eq(consumed.copper, 7 * INGOT, "brass takes 7 copper ingots")
    eq(consumed.zinc, 3 * INGOT, "brass takes 3 zinc ingots")
    eq(created.brass, 10 * INGOT, "brass yields 10 ingots")
    eq(consumed.zinc / (consumed.copper + consumed.zinc), 0.3, "30% zinc")
    eq(brass.alloy, "brass", "brass is marked as the alloy")

    -- The checker itself: it must reject what it is there to reject.
    local function variant(base, change)
        local copy = { id = base.id .. "_tampered", alloy = base.alloy, inputs = base.inputs, outputs = base.outputs }
        for k, v in pairs(change) do copy[k] = v end
        return copy
    end
    check(not AC_Materials.checkConservation(variant(smelt, { outputs = { { count = 11, item = "AmmoMaking.ZincScrap" } } })), "11 scrap from one ore is rejected")
    check(not AC_Materials.checkConservation(variant(brass, { outputs = { { count = 11, item = "Base.BrassIngot" } } })), "11 brass from 10 ingots is rejected")
    check(not AC_Materials.checkConservation(variant(brass, { outputs = { { count = 9, item = "Base.BrassIngot" } } })), "an alloy that loses metal is rejected as inexact")
    check(AC_Materials.checkConservation(variant(smelt, { outputs = { { count = 9, item = "AmmoMaking.ZincScrap" } } })), "a lossy non-alloy recipe is allowed")
    check(not AC_Materials.checkConservation(variant(smelt, { outputs = { { count = 1, item = "Base.CopperIngot" } } })), "zinc cannot become copper")
    check(not AC_Materials.checkConservation(variant(brass, { inputs = { { count = 10, items = { "Base.CopperIngot" }, keep = true } } })), "kept inputs pay for nothing")
    check(not AC_Materials.checkConservation({
        id = "cheapest",
        inputs = { { count = 1, items = { "Base.CopperIngot", "Base.CopperScrap" } } },
        outputs = { { count = 2, item = "Base.CopperScrap" } },
    }), "an either-or input counts as its cheapest alternative")

    -- Whole graph, vanilla copper recipes included: every recipe is
    -- non-increasing, and a metal item can be turned back into itself only
    -- by way of a recipe that LOSES metal. Brass recycling closes one loop
    -- (ingot -> sheet -> cup -> case -> scrap -> ingot); the proof that it
    -- cannot be farmed is in two parts: each scrapping recipe strictly
    -- loses (checkConservation with recipe.loss), and with those recipes
    -- taken out the graph has no loop at all.
    local all = {}
    for _, r in ipairs(AC_Materials.RECIPES) do table.insert(all, r) end
    for _, r in ipairs(AC_Materials.VANILLA_RECIPES) do table.insert(all, r) end
    -- An edge A -> B means a recipe moves METAL from A into B (the same
    -- metal, or a part into its alloy). Powder is not metal: a round and
    -- the gunpowder gathered from it share none, and that non-metal cycle
    -- is tested on its own below.
    local METALS = { copper = true, zinc = true, brass = true }
    local function contents(id)
        local entry = U[id]
        if not entry then return {} end
        return entry.contents or { [entry.metal] = entry.units }
    end
    local function movesMetal(from, to)
        for a in pairs(contents(from)) do
            if METALS[a] then
                for b in pairs(contents(to)) do
                    if a == b then return true end
                    for _, part in ipairs(AC_Materials.ALLOYS[b] or {}) do
                        if part == a then return true end
                    end
                end
            end
        end
        return false
    end
    -- edges: without the lossy recipes. lossyEdges: with them.
    local edges, lossyEdges = {}, {}
    local lossRecipes = 0
    for _, recipe in ipairs(all) do
        check(AC_Materials.checkConservation(recipe), recipe.id .. " does not create material")
        if recipe.loss then lossRecipes = lossRecipes + 1 end
        for _, input in ipairs(recipe.inputs) do
            for _, from in ipairs(input.items or {}) do
                if U[from] and not input.keep then
                    for _, output in ipairs(recipe.outputs) do
                        if movesMetal(from, output.item) then
                            lossyEdges[from] = lossyEdges[from] or {}
                            lossyEdges[from][output.item] = true
                            if not recipe.loss then
                                edges[from] = edges[from] or {}
                                edges[from][output.item] = true
                            end
                        end
                    end
                end
            end
        end
    end
    local graph = edges
    local function reaches(from, target, visited)
        for nextItem in pairs(graph[from] or {}) do
            if nextItem == target then return true end
            if not visited[nextItem] then
                visited[nextItem] = true
                if reaches(nextItem, target, visited) then return true end
            end
        end
        return false
    end
    for id in pairs(U) do
        check(not reaches(id, id, {}), "no loop returns to " .. id .. " without a recipe that loses metal")
    end
    eq(lossRecipes, #AC_Recycling.buildGroups(), "the lossy recipes are the scrapping recipes")
    -- With them, the loop exists, and it is brass all the way round.
    graph = lossyEdges
    check(reaches("Base.BrassIngot", "Base.BrassIngot", {}), "recycling closes the brass loop")
    for id in pairs(U) do
        if reaches(id, id, {}) then
            local entry = U[id]
            check(entry.metal == "brass" and entry.contents == nil, id .. " is on the recycling loop and is nothing but brass")
        end
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(reaches(calibre.case, "Base.BrassScrap", {}), calibre.id .. " cases can be scrapped")
        check(not reaches(calibre.round, calibre.round, {}), "a finished " .. calibre.id .. " round is on no metal loop")
        check(not reaches(calibre.bullet, calibre.bullet, {}), "a " .. calibre.id .. " bullet is on no metal loop")
    end
    check(lossyEdges["Base.BrassScrap"]["Base.BrassIngot"], "brass scrap is cast back into ingots")
    check(not reaches("Base.CopperScrap", "Base.CopperScrap", {}) and not reaches("AmmoMaking.ZincScrap", "AmmoMaking.ZincScrap", {}), "copper and zinc are on no loop")
    graph = edges
    check(reaches("Base.CopperOre", "Base.BrassIngot", {}), "copper ore reaches brass")
    check(reaches("AmmoMaking.ZincOre", "Base.BrassIngot", {}), "zinc ore reaches brass")
    check(reaches("Base.CopperOre", "AmmoMaking.BrassCaseCup", {}), "copper ore reaches case cups")
    check(edges["Base.BrassIngot"] ~= nil and edges["Base.BrassIngot"]["AmmoMaking.SmallBrassSheet"], "brass ingots become small sheets")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(edges["AmmoMaking.BrassCaseCup"][calibre.case], "case cups become " .. calibre.id .. " cases")
        check(reaches("Base.CopperOre", calibre.round, {}), "copper ore reaches the " .. calibre.id .. " round")
        check(reaches("AmmoMaking.ZincOre", calibre.round, {}), "zinc ore reaches the " .. calibre.id .. " round")
        check(edges[calibre.round] == nil, "no recipe takes metal back out of a " .. calibre.id .. " round")
    end
    check(not reaches("Base.BrassIngot", "Base.BrassScrap", {}), "brass scrap comes only from the scrapping recipes")
    check(edges["Base.BrassScrap"] ~= nil and edges["Base.BrassScrap"]["Base.BrassIngot"], "brass scrap has one use: the ingot")

    -- Run the chain on a pretend inventory. This executes the mirror
    -- table, not the game's crafting system.
    local function craft(inventory, recipe)
        for _, input in ipairs(recipe.inputs) do
            local id = input.items and input.items[1] or input.tags[1]
            if (inventory[id] or 0) < input.count then return false end
        end
        for _, input in ipairs(recipe.inputs) do
            if not input.keep then
                local id = input.items and input.items[1] or input.tags[1]
                inventory[id] = inventory[id] - input.count
            end
        end
        for _, output in ipairs(recipe.outputs) do
            -- A drainable is held as uses: a full item unless marked oneUse.
            local perItem = 1
            if U[output.item] and U[output.item].uses and not output.oneUse then perItem = U[output.item].uses end
            inventory[output.item] = (inventory[output.item] or 0) + output.count * perItem
        end
        return true
    end
    -- Units of one material in the inventory, or of all metals when the
    -- material is nil.
    local function materialIn(inventory, material)
        local sum = 0
        for id, count in pairs(inventory) do
            for m, units in pairs(contents(id)) do
                if (material and m == material) or (not material and METALS[m]) then
                    sum = sum + units * count
                end
            end
        end
        return sum
    end
    local function metalIn(inventory)
        return materialIn(inventory, nil)
    end
    local function freshInventory()
        return {
            ["Base.CopperOre"] = 7, ["AmmoMaking.ZincOre"] = 3, ["base:charcoal"] = 200,
            ["Base.CeramicCrucible"] = 1, ["base:crudetongs"] = 1, ["Base.ClayIngotMold"] = 1,
            ["base:hammer"] = 1, ["base:tongs"] = 1, ["base:metalworkingpunch"] = 1,
        }
    end

    local inv = freshInventory()
    local vanillaSmelt = AC_Materials.VANILLA_RECIPES[1]
    eq(vanillaSmelt.id, "SmeltCopperOre", "vanilla copper smelting is recorded")
    for _ = 1, 7 do check(craft(inv, vanillaSmelt), "smelt copper ore") end
    for _ = 1, 3 do check(craft(inv, smelt), "smelt zinc ore") end
    check(not craft(inv, smelt), "no fourth zinc ore to smelt")
    eq(inv["Base.CopperScrap"], 70, "7 copper ore -> 70 scrap")
    eq(inv["AmmoMaking.ZincScrap"], 30, "3 zinc ore -> 30 scrap")
    for _ = 1, 7 do check(craft(inv, AC_Materials.getRecipe("AmmoMaking_CastCopperIngot")), "cast copper ingot") end
    for _ = 1, 3 do check(craft(inv, AC_Materials.getRecipe("AmmoMaking_CastZincIngot")), "cast zinc ingot") end
    eq(inv["Base.CopperIngot"], 7, "70 scrap -> 7 copper ingots")
    eq(inv["AmmoMaking.ZincIngot"], 3, "30 scrap -> 3 zinc ingots")
    check(craft(inv, brass), "cast brass")
    check(not craft(inv, brass), "the ingots are gone after one batch")
    eq(inv["Base.BrassIngot"], 10, "10 ore -> 10 brass ingots")
    eq(inv["Base.CopperIngot"] + inv["AmmoMaking.ZincIngot"] + inv["Base.CopperScrap"] + inv["AmmoMaking.ZincScrap"], 0, "nothing left over")
    eq(metalIn(inv), metalIn(freshInventory()), "metal units unchanged from ore to brass")
    eq(200 - inv["base:charcoal"], 7 * 4 + 3 * 4 + 10 * 4 + 10, "charcoal consumed by every step")
    eq(inv["Base.CeramicCrucible"] + inv["base:crudetongs"] + inv["Base.ClayIngotMold"], 3, "kept tools are still there")

    -- On to case stock: 10 ingots -> 100 small sheets -> 200 cups.
    local forge = AC_Materials.getRecipe("AmmoMaking_ForgeSmallBrassSheets")
    local punch = AC_Materials.getRecipe("AmmoMaking_PunchBrassCaseCups")
    local charcoalBefore = inv["base:charcoal"]
    check(not craft(inv, punch), "no cups before there are sheets")
    for _ = 1, 10 do check(craft(inv, forge), "forge small brass sheets") end
    check(not craft(inv, forge), "no eleventh ingot to forge")
    eq(inv["AmmoMaking.SmallBrassSheet"], 100, "10 brass ingots -> 100 small sheets")
    for _ = 1, 100 do check(craft(inv, punch), "punch case cups") end
    eq(inv["AmmoMaking.BrassCaseCup"], 200, "100 small sheets -> 200 case cups")
    eq(inv["Base.BrassIngot"] + inv["AmmoMaking.SmallBrassSheet"], 0, "no brass stock left over")
    eq(metalIn(inv), metalIn(freshInventory()), "metal units unchanged from ore to case cups")
    eq(charcoalBefore - inv["base:charcoal"], 10, "one charcoal per forged ingot, none for punching")
    eq(inv["base:hammer"] + inv["base:tongs"] + inv["base:metalworkingpunch"], 3, "hammer, tongs and punch are kept")
    eq(inv["AmmoMaking.BrassCaseCup"] / 10, 20, "20 cups per ore")

    -- Any order of any recipes never increases the metal in the inventory.
    local seed = 12345
    local function nextRandom(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed % n) + 1
    end
    inv = freshInventory()
    inv["Base.SteelBarQuarter"] = 4
    inv["base:ballpeenhammer"] = 1
    inv["base:metalworkingpliers"] = 1
    inv["base:whetstone"] = 1
    inv["base:mortarpestle"] = 1
    inv["Base.Fertilizer"] = 16
    inv["Base.CapGunCap"] = 100
    inv["Base.Matches"] = 40
    inv["Base.Bullets9mm"] = 5
    local mix = AC_Materials.getRecipe("AmmoMaking_MixGunpowder")
    local initial = metalIn(inv)
    local initialCompound = materialIn(inv, "compound")
    local initialPowder = materialIn(inv, "powder")
    local worst, worstCompound, worstPowderExcess, mixes = initial, initialCompound, 0, 0
    for _ = 1, 3000 do
        local recipe = all[nextRandom(#all)]
        if craft(inv, recipe) and recipe == mix then mixes = mixes + 1 end
        local now = metalIn(inv)
        if now > worst then worst = now end
        local compound = materialIn(inv, "compound")
        if compound > worstCompound then worstCompound = compound end
        local excess = materialIn(inv, "powder") - initialPowder - mixes * AC_Calibres.POWDER.usesPerJar
        if excess > worstPowderExcess then worstPowderExcess = excess end
    end
    eq(worst, initial, "3000 crafts in random order never exceed the starting metal")
    eq(worstCompound, initialCompound, "priming compound is never created")
    eq(worstPowderExcess, 0, "powder only ever comes from mixing; taking rounds apart and reassembling gains none")
    check(mixes > 0 and mixes <= 16 / AC_Calibres.POWDER.fertilizerUses, "mixing is bounded by the fertilizer (" .. mixes .. ")")
end

section("Recipe XP: one grant per completed craft (OnCreate callbacks)")
do
    -- The engine calls OnCreate(craftRecipeData, character). The callbacks
    -- must not need anything from craftRecipeData.
    local untouchable = setmetatable({}, { __index = function(_, key) error("craftRecipeData." .. tostring(key) .. " was read") end })

    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local xp = AC_Materials.getRecipeXP(recipe)
        -- Recycling is the one family that awards nothing.
        eq(xp > 0, not recipe.recycling, recipe.id .. (recipe.recycling and " awards no XP" or " awards XP"))
        local player = MOCK.newPlayer()
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        -- Recipes with an effect read the created / consumed items.
        local data = untouchable
        if recipe.effect then
            data = {
                getAllCreatedItems = function() return MOCK.arrayList({}) end,
                getAllConsumedItems = function() return MOCK.arrayList({}) end,
            }
        end
        local ok, granted = pcall(AC_Materials[recipe.callback], data, player)
        MOCK.capturePrint(false)
        check(ok, recipe.id .. " callback runs: " .. tostring(granted))
        check(not MOCK.printLogContains("WARNING"), recipe.id .. " callback logs no warning")
        eq(granted, xp, recipe.id .. " callback reports the XP")
        if recipe.recycling then
            eq(granted, 0, recipe.id .. " callback grants nothing")
            eq(#player.xpLog, 0, recipe.id .. " never touches the XP")
            check(not MOCK.printLogContains("Ammo Making XP"), recipe.id .. " logs no XP line")
        else
            eq(#player.xpLog, 1, recipe.id .. " grants XP exactly once")
            eq(player.xpLog[1], xp, recipe.id .. " XP amount")
            check(MOCK.printLogContains("[AmmoMaking] Crafting (" .. recipe.id .. "): +" .. xp .. " Ammo Making XP (total 0 -> " .. xp .. ")"), recipe.id .. " XP logged")
        end

        MOCK.capturePrint(true)
        check(pcall(AC_Materials[recipe.callback], data, nil), recipe.id .. " callback tolerates a missing character")
        eq(AC_Materials[recipe.callback](data, nil), 0, recipe.id .. " no character, no XP")
        MOCK.capturePrint(false)
    end

    local player = MOCK.newPlayer()
    eq(AC_Materials.onRecipeCreated("not_a_recipe", player), 0, "unknown recipe id grants nothing")
    eq(#player.xpLog, 0, "no XP for an unknown recipe")
    eq(AC_Materials.getRecipeXP(nil), 0, "no recipe, no XP")

    -- Skill never creates metal: XP and level appear nowhere in the units.
    local before = AC_Materials.getRecipeUnits(AC_Materials.getRecipe("AmmoMaking_CastBrassIngots"))
    player.perkLevel = 10
    local after = AC_Materials.getRecipeUnits(AC_Materials.getRecipe("AmmoMaking_CastBrassIngots"))
    eq(after.copper, before.copper, "level does not change what a recipe consumes")
    eq(AC_Materials.getRecipeXP(AC_Materials.getRecipe("AmmoMaking_CastBrassIngots")), AC_Materials.CONFIG.xpCastBrass, "brass XP comes from CONFIG")
end

section("Recipe skill requirement (mocked CraftRecipe scripts)")
do
    -- The mock implements the two methods the 42.20.4 jar declares. That
    -- the engine exposes them to Lua is REQUIRES FUTURE IN-GAME VERIFICATION.
    local ids = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end

    MOCK.resetCraftRecipes(ids)
    local summary = AC_Materials.applySkillRequirements()
    eq(summary.attached, #ids, "every recipe gets the requirement")
    eq(summary.missing + summary.unsupported + summary.present, 0, "nothing else reported")
    for _, id in ipairs(ids) do
        local script = MOCK.craftRecipeScripts[id]
        eq(#script.requiredSkills, 1, id .. " has one required skill")
        eq(script.requiredSkills[1].perk, AmmoMakingSkill.perk, id .. " requires the Ammo Making perk")
        eq(script.requiredSkills[1].level, AC_Materials.getRequiredLevel(AC_Materials.getRecipe(id)), id .. " carries its own required level")
    end
    eq(AC_Materials.CONFIG.requiredLevel, 0, "smelting is reachable at level 0")

    summary = AC_Materials.applySkillRequirements()
    eq(summary.attached, 0, "a second run attaches nothing")
    eq(summary.present, #ids, "a second run finds them present")
    for _, id in ipairs(ids) do
        eq(#MOCK.craftRecipeScripts[id].requiredSkills, 1, id .. " still has exactly one")
    end

    MOCK.resetCraftRecipes({ ids[1] })
    summary = AC_Materials.applySkillRequirements()
    eq(summary.attached, 1, "the one known recipe is handled")
    eq(summary.missing, #ids - 1, "unknown recipes are counted, not raised")

    MOCK.resetCraftRecipes(ids)
    MOCK.craftRecipeScripts[ids[2]].addRequiredSkill = nil
    summary = AC_Materials.applySkillRequirements()
    eq(summary.unsupported, 1, "a script without addRequiredSkill is unsupported")
    eq(summary.attached, #ids - 1, "the others still get it")

    MOCK.resetCraftRecipes(ids)
    MOCK.craftRecipeLookup = false
    local ok
    ok, summary = pcall(AC_Materials.applySkillRequirements)
    MOCK.craftRecipeLookup = true
    check(ok, "no getCraftRecipe on the script manager does not raise")
    eq(summary.missing, #ids, "without the lookup every recipe is missing")

    MOCK.scriptManagerAvailable = false
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okBoot = pcall(Events.OnGameBoot.fire)
    MOCK.capturePrint(false)
    MOCK.scriptManagerAvailable = true
    check(okBoot, "a failing script manager at boot does not raise")
    check(MOCK.printLogContains("WARNING: recipe skill requirements not applied"), "boot failure is logged as a WARNING")

    MOCK.resetCraftRecipes(ids)
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    Events.OnGameBoot.fire()
    Events.OnGameStart.fire()
    MOCK.capturePrint(false)
    for _, id in ipairs(ids) do
        eq(#MOCK.craftRecipeScripts[id].requiredSkills, 1, id .. " attached once across OnGameBoot and OnGameStart")
    end
    local lines = 0
    for _, line in ipairs(MOCK.printLog) do
        if string.find(line, "Station recipes: " .. #ids .. " given the Ammo Making requirement", 1, true) then lines = lines + 1 end
    end
    eq(lines, 1, "the attachment is logged once, not on the no-op second run")

    -- Predicted craft time, mirroring CraftRecipe.getTime in the jar.
    local brass = AC_Materials.getRecipe("AmmoMaking_CastBrassIngots")
    eq(AC_Materials.getExpectedTime(brass, 0), 200, "level 0: the script time")
    eq(AC_Materials.getExpectedTime(brass, 1), 190, "5% faster per level")
    eq(AC_Materials.getExpectedTime(brass, 10), 100, "level 10: half the time")
    eq(AC_Materials.getExpectedTime(brass, nil), 200, "unknown level counts as 0")
    local punch = AC_Materials.getRecipe("AmmoMaking_PunchBrassCaseCups")
    eq(AC_Materials.getExpectedTime(punch, 0), 100, "cup punching: the script time at level 0")
    eq(AC_Materials.getExpectedTime(punch, 10), 50, "cup punching: half at level 10")
    local previous = 201
    for level = 0, 10 do
        local t = AC_Materials.getExpectedTime(brass, level)
        check(t < previous and t > 0, "time falls with level and stays positive (" .. level .. ")")
        previous = t
    end
end

section("Recipe and item translations: every recipe and item has an English name")
do
    local function keys(file)
        local defined = {}
        for key, value in string.gmatch(readFile(TRANSLATE .. file), '"([^"]+)"%s*:%s*"([^"]*)"') do
            defined[key] = value
        end
        return defined
    end

    -- Recipes.json keys are the recipe id without a module prefix
    -- (42.20.4: Translator.getRecipeName(name)).
    local recipeNames = keys("Recipes.json")
    local count = 0
    for _ in pairs(recipeNames) do count = count + 1 end
    eq(count, #AC_Materials.RECIPES, "no stale recipe names")
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        check(recipeNames[recipe.id] ~= nil and recipeNames[recipe.id] ~= "", "recipe name for " .. recipe.id)
    end

    -- ItemName.json keys are full types, as in vanilla ("Base.CopperIngot").
    local itemNames = keys("ItemName.json")
    count = 0
    for key in pairs(itemNames) do
        count = count + 1
        check(declaredItems[key] ~= nil, "item name key belongs to a declared item (" .. key .. ")")
    end
    local declaredCount = 0
    for id, block in pairs(declaredItems) do
        declaredCount = declaredCount + 1
        eq(itemNames[id], block.fields.DisplayName, "ItemName.json agrees with the script DisplayName for " .. id)
    end
    eq(count, declaredCount, "one item name per declared item")
end

section("Metallurgy and case stock debug tools")
do
    MOCK.debug = true
    local player = MOCK.newPlayer({ square = MOCK.newSquare(5, 5, 0, GRASS) })
    local ids = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
    MOCK.resetCraftRecipes(ids)
    AC_Materials.applySkillRequirements()

    MOCK.capturePrint(true)
    AC_GeologyDebug.spawnMetallurgyKit(player)
    MOCK.capturePrint(false)
    local inv = player.inventory
    eq(inv:count("Base.Tongs"), 1, "tongs spawned")
    eq(inv:count("Base.CeramicCrucible"), 1, "crucible spawned")
    eq(inv:count("Base.IronIngotMold"), 1, "a mold that does not break is spawned")
    eq(inv:count("AmmoMaking.ZincOre"), 1, "zinc ore spawned")
    eq(inv:count("Base.CopperScrap"), 10, "copper scrap for one ingot")
    eq(inv:count("AmmoMaking.ZincScrap"), 10, "zinc scrap for one ingot")
    eq(inv:count("Base.CopperIngot") + 1, 7, "copper ingots: one short of a batch, cast the last")
    eq(inv:count("AmmoMaking.ZincIngot") + 1, 3, "zinc ingots: one short of a batch, cast the last")
    eq(inv:count("Base.Charcoal"), 4 + 4 + 4 + 10, "charcoal for every recipe once")
    eq(inv:count("Base.BrassIngot"), 0, "the kit does not hand out brass")

    local stockPlayer = MOCK.newPlayer({ square = MOCK.newSquare(6, 5, 0, GRASS) })
    MOCK.capturePrint(true)
    AC_GeologyDebug.spawnCaseStockKit(stockPlayer)
    MOCK.capturePrint(false)
    local stock = stockPlayer.inventory
    eq(stock:count("Base.BallPeenHammer"), 1, "hammer spawned")
    eq(stock:count("Base.Tongs"), 1, "tongs spawned")
    eq(stock:count("Base.MetalworkingPunch"), 1, "punch spawned")
    eq(stock:count("Base.Charcoal"), 1, "charcoal for one forging")
    eq(stock:count("Base.BrassIngot"), 1, "one brass ingot to forge")
    eq(stock:count("AmmoMaking.SmallBrassSheet"), 2, "two sheets to punch at once")
    eq(stock:count("AmmoMaking.BrassCaseCup"), 0, "the kit does not hand out cups")

    player.perkLevel = 4
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local ok = pcall(AC_GeologyDebug.inspectMetallurgyRecipes, player)
    MOCK.capturePrint(false)
    check(ok, "recipe inspector runs")
    check(MOCK.printLogContains("STATION RECIPES (Ammo Making level 4)"), "inspector header")
    check(MOCK.printLogContains("AmmoMaking_PunchBrassCaseCups [AnySurfaceCraft]: loaded, required skills 1; level 0; XP 1; expected time 80/100; metal conserved"), "inspector lists the case-stock recipes")
    check(MOCK.printLogContains("AmmoMaking_CastBrassIngots [Furnace]: loaded, required skills 1; level 0; XP 25; expected time 160/200; metal conserved"), "inspector line")
    for _, id in ipairs(ids) do
        eq(#MOCK.craftRecipeScripts[id].requiredSkills, 1, "inspector attaches nothing (" .. id .. ")")
    end

    MOCK.resetCraftRecipes({})
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    ok = pcall(AC_GeologyDebug.inspectMetallurgyRecipes, player)
    MOCK.capturePrint(false)
    check(ok, "recipe inspector runs without loaded recipes")
    check(MOCK.printLogContains("AmmoMaking_SmeltZincOre [PrimitiveFurnace]: NOT FOUND in the script manager"), "missing recipe reported")
    check(pcall(AC_GeologyDebug.inspectMetallurgyRecipes, nil), "inspector tolerates no player")

    MOCK.resetCraftRecipes(ids)
    AC_Materials.applySkillRequirements()
    MOCK.debug = false
end

------------------------------------------------
-- AMMUNITION COMPONENTS
------------------------------------------------
--
-- The calibre model, primer families, case quality, progression and the
-- complete chain from brass to the vanilla round, for every calibre in
-- AC_Calibres.LIST. As above: this proves the Lua logic, the file contents
-- and the arithmetic, not that the game runs it.

-- Mirror inventory shared by the sections below. Drainables are held as
-- uses: an output is a full item unless the mirror marks it oneUse.
-- An input line that names several items is paid from any of them, in the
-- order listed, as the engine fills a line from whatever matches.
local function mirrorHeld(inventory, input)
    if not input.items then return inventory[input.tags[1]] or 0 end
    local held = 0
    for _, id in ipairs(input.items) do held = held + (inventory[id] or 0) end
    return held
end

local function mirrorCanCraft(inventory, recipe)
    for _, input in ipairs(recipe.inputs) do
        if mirrorHeld(inventory, input) < input.count then return false end
    end
    return true
end

local function mirrorCraft(inventory, recipe)
    local U = AC_Materials.UNITS
    if not mirrorCanCraft(inventory, recipe) then return false end
    for _, input in ipairs(recipe.inputs) do
        if not input.keep then
            local owed = input.count
            for _, id in ipairs(input.items or { input.tags[1] }) do
                local take = math.min(owed, inventory[id] or 0)
                if take > 0 then
                    inventory[id] = inventory[id] - take
                    owed = owed - take
                end
            end
        end
    end
    for _, output in ipairs(recipe.outputs) do
        local perItem = 1
        if U[output.item] and U[output.item].uses and not output.oneUse then perItem = U[output.item].uses end
        inventory[output.item] = (inventory[output.item] or 0) + output.count * perItem
    end
    return true
end

local function calibreRecipe(calibre, step)
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        if recipe.calibre == calibre.id and recipe.step == step then return recipe end
    end
    return nil
end

local function primerRecipe(primer, sourceId)
    return AC_Materials.getRecipe("AmmoMaking_Make" .. primer.id .. "PrimersFrom" .. sourceId)
end

-- Every AmmoType a firearm or magazine names in the installed 42.20.4
-- scripts (items/weapon.txt, items/normal.txt), cap guns aside.
local VANILLA_AMMO_TYPES = {
    ["base:bullets_9mm"] = true, ["base:bullets_38"] = true, ["base:bullets_45"] = true,
    ["base:bullets_357"] = true, ["base:bullets_44"] = true, ["base:bullets_556"] = true,
    ["base:bullets_3030"] = true, ["base:bullets_308"] = true, ["base:shotgun_shells"] = true,
}

section("Calibre model: definitions are complete and generate everything")
do
    eq(#AC_Calibres.validate(), 0, "the live model has no problems: " .. table.concat(AC_Calibres.validate(), "; "))
    eq(AC_Calibres.LIST[1].id, "9mm", "9mm is the first calibre")

    local ids, suffixes, itemsSeen = {}, {}, {}
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local name = calibre.id
        check(not ids[name], name .. " id is unique")
        ids[name] = true
        check(not suffixes[calibre.suffix], name .. " suffix is unique")
        suffixes[calibre.suffix] = true
        check(type(calibre.suffix) == "string" and not string.find(calibre.suffix, "[^%w]"), name .. " suffix is letters and digits")

        -- The product is a vanilla item; the components are the mod's.
        eq(string.sub(calibre.round, 1, 5), "Base.", name .. " assembles a vanilla round")
        check(MOCK.knownScriptItems[calibre.round], name .. " round id is one recorded from the installed scripts")
        check(VANILLA_AMMO_TYPES[calibre.ammoType], name .. " records a vanilla ammo type (" .. tostring(calibre.ammoType) .. ")")
        for _, kind in ipairs({ "case", "bullet", "dieSet" }) do
            local id = calibre[kind]
            check(declaredItems[id] ~= nil, name .. " " .. kind .. " is declared in AC_Items.txt (" .. tostring(id) .. ")")
            check(not itemsSeen[id], name .. " " .. kind .. " item is not shared with another calibre")
            itemsSeen[id] = true
            local kindFound, owner = AC_Calibres.identify(id)
            eq(kindFound, kind, name .. " " .. kind .. " is identified")
            eq(owner, calibre, name .. " " .. kind .. " belongs to its calibre")
        end
        check(not itemsSeen[calibre.round], name .. " round is not shared with another calibre")
        itemsSeen[calibre.round] = true
        local kindFound, owner = AC_Calibres.identify(calibre.round)
        eq(kindFound, "round", name .. " round is identified")
        eq(owner, calibre, name .. " round belongs to its calibre")

        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        check(primer ~= nil, name .. " names an existing primer family")
        check(calibre.powderUses >= 1 and calibre.powderUses == math.floor(calibre.powderUses), name .. " takes at least one whole use of powder")
        check(calibre.cupsPerCase >= 1 and calibre.cupsPerCase == math.floor(calibre.cupsPerCase), name .. " takes a whole number of cups")
        local bulletUnits = AC_Calibres.CONFIG.scrapUnits / calibre.bulletsPerScrap
        eq(bulletUnits, math.floor(bulletUnits), name .. " bullets divide a scrap evenly")
        for _, step in ipairs({ "dieSet", "case", "bullet", "assemble" }) do
            check(type(calibre.levels[step]) == "number", name .. " level for " .. step)
            check(type(calibre.xp[step]) == "number" and calibre.xp[step] > 0, name .. " xp for " .. step)
            check(type(calibre.time[step]) == "number" and calibre.time[step] > 0, name .. " time for " .. step)
        end

        -- Four recipes per calibre, generated from the definition alone.
        local recipes = AC_Calibres.buildCalibreRecipes(calibre)
        eq(#recipes, 4, name .. " has four recipes")
        for _, recipe in ipairs(recipes) do
            eq(recipe.calibre, name, recipe.id .. " names its calibre")
            check(string.find(recipe.id, calibre.suffix, 1, true) ~= nil, recipe.id .. " id carries the suffix")
            eq(AC_Materials.getRecipe(recipe.id) ~= nil, true, recipe.id .. " is in AC_Materials.RECIPES")
            local usesDieSet = false
            for _, input in ipairs(recipe.inputs) do
                if input.items and input.items[1] == calibre.dieSet then usesDieSet = true end
            end
            eq(usesDieSet, recipe.step ~= "dieSet", recipe.id .. " needs the die set unless it makes it")
        end

        -- The assembly recipe is exactly what the definition says.
        local assemble = recipes[4]
        eq(assemble.step, "assemble", name .. " fourth recipe is the assembly")
        eq(assemble.inputs[1].items[1], calibre.case, name .. " assembly takes its own case")
        eq(assemble.inputs[1].count, 1, name .. " assembly takes one case")
        eq(assemble.inputs[2].items[1], primer.item, name .. " assembly takes its family's primer")
        eq(#assemble.inputs[2].items, 1, name .. " assembly accepts no other primer")
        eq(assemble.inputs[2].count, 1, name .. " assembly takes one primer")
        eq(assemble.inputs[3].items[1], calibre.bullet, name .. " assembly takes its own bullet")
        eq(assemble.inputs[4].items[1], AC_Calibres.POWDER.item, name .. " assembly takes vanilla gunpowder")
        eq(assemble.inputs[4].count, calibre.powderUses, name .. " assembly takes its charge")
        eq(assemble.inputs[5].items[1], calibre.dieSet, name .. " assembly uses its own die set")
        eq(assemble.outputs[1].item, calibre.round, name .. " assembly outputs the vanilla round")
        eq(assemble.outputs[1].count, 1, name .. " assembly makes one round per craft (one vanilla item is one cartridge)")
        eq(assemble.requiredLevel, calibre.levels.assemble, name .. " assembly level")
        eq(assemble.xp, calibre.xp.assemble, name .. " assembly xp")
        eq(assemble.time, calibre.time.assemble, name .. " assembly time")
        -- Five lines, and a sixth for the wad of a shell.
        eq(#assemble.inputs, calibre.wads > 0 and 6 or 5, name .. " assembly has no other input line")
        if calibre.wads > 0 then
            local wad = assemble.inputs[6]
            eq(wad.count, calibre.wads, name .. " assembly takes its wadding")
            check(sameList(wad.items, AC_Calibres.WAD.items), name .. " wadding is the shared wad list")
            check(wad.destroy == true and not wad.keep, name .. " wadding is consumed outright")
        end
        eq(recipes[2].inputs[1].count, calibre.cupsPerCase, name .. " case forming takes its cups")
        eq(recipes[3].outputs[1].count, calibre.bulletsPerScrap, name .. " swaging yields its bullets per scrap")
    end

    eq(AC_Calibres.get("9mm"), AC_Calibres.LIST[1], "lookup by id")
    eq(AC_Calibres.get("nope"), nil, "unknown calibre")
    eq(AC_Calibres.getPrimer("nope"), nil, "unknown primer family")
    eq(AC_Calibres.identify("Base.Plank"), nil, "an unrelated item is not identified")

    -- Definitions state only what differs; the rest comes from DEFAULTS.
    local D = AC_Calibres.DEFAULTS
    local custom = AC_Calibres.define({ id = "test", suffix = "Test", round = "Base.X", ammoType = "base:bullets_x", levels = { bullet = 1 }, assembleLevel = 6, powderUses = 2 })
    eq(custom.case, "AmmoMaking.CaseTest", "item ids derive from the suffix")
    eq(custom.bullet, "AmmoMaking.BulletTest", "bullet id derives from the suffix")
    eq(custom.dieSet, "AmmoMaking.DieSetTest", "die set id derives from the suffix")
    eq(custom.levels.assemble, 6, "the round unlocks at assembleLevel")
    eq(custom.levels.case, 4, "the case two levels earlier")
    eq(custom.levels.dieSet, 4, "the die set with the case")
    eq(custom.levels.bullet, 1, "one step can still be overridden")
    eq(custom.powderUses, 2, "a scalar can be overridden")
    eq(custom.primerFamily, D.primerFamily, "an omitted scalar is the default")
    eq(custom.cupsPerCase, D.cupsPerCase, "cups default")
    eq(D.assembleLevel, 3, "overriding does not write into DEFAULTS")
    eq(AC_Calibres.define({ id = "t", suffix = "T", round = "Base.X", ammoType = "a", case = "AmmoMaking.Odd" }).case, "AmmoMaking.Odd", "an explicit item id wins")
    eq(#AC_Calibres.buildCalibreRecipes(custom), 4, "a new definition yields its four recipes with no other code")
    eq(AC_Calibres.buildCalibreRecipes(custom)[4].inputs[4].count, 2, "its powder charge reaches the assembly recipe")
    eq(AC_Calibres.buildCalibreRecipes(custom)[4].requiredLevel, 6, "its level reaches the assembly recipe")
    -- Class defaults sit between DEFAULTS and the definition.
    local rifle = AC_Calibres.define({ id = "r", class = "rifle", suffix = "R", round = "Base.X", ammoType = "a", xp = { bullet = 9 } })
    local RC = AC_Calibres.CLASSES.rifle
    eq(rifle.primerFamily, RC.primerFamily, "a rifle takes the rifle class's primer family")
    eq(rifle.cupsPerCase, RC.cupsPerCase, "and its cups")
    eq(rifle.powderUses, RC.powderUses, "and its charge")
    eq(rifle.time.case, RC.time.case, "and its times")
    eq(rifle.xp.case, RC.xp.case, "and its class XP")
    eq(rifle.xp.dieSet, D.xp.dieSet, "a step the class does not set comes from DEFAULTS")
    eq(rifle.xp.bullet, 9, "the definition still wins over the class")
    eq(rifle.levels.assemble, RC.assembleLevel, "the class sets the round level")
    eq(custom.class, "pistol", "a definition without a class is a pistol")
    eq(custom.wads, 0, "a cartridge has no wad")
    eq(rifle.wads, 0, "nor has a rifle round")
    eq(#AC_Calibres.buildCalibreRecipes(custom)[4].inputs, 5, "so its assembly has five lines")
    -- The shotgun class: hull, shot charge, wad, and the pistol class's primers.
    local SC = AC_Calibres.CLASSES.shotgun
    local shell = AC_Calibres.define({ id = "s", class = "shotgun", suffix = "S", round = "Base.X", ammoType = "a" })
    eq(shell.wads, 1, "a shell takes one wad")
    eq(shell.primerFamily, "LargePistol", "a shell takes the large pistol primer")
    eq(SC.primerClass, "pistol", "the shotgun class borrows the pistol class's primer families")
    eq(AC_Calibres.CLASSES.rifle.primerClass, nil, "the rifle class borrows nothing")
    eq(AC_Calibres.CLASSES.pistol.primerClass, nil, "nor does the pistol class")
    eq(shell.time.case, D.time.case, "shell times are the pistol times")
    eq(#AC_Calibres.buildCalibreRecipes(shell), 4, "a shell has the same four recipes")
    eq(#AC_Calibres.buildCalibreRecipes(shell)[4].inputs, 6, "and one more assembly line")
    eq(D.wads, 0, "DEFAULTS were not written to by the shotgun class")
    eq(custom.time.case, D.time.case, "pistol times are untouched by the rifle class")
    eq(D.time.case, 80, "DEFAULTS were not written to")
    for key in pairs(AC_Calibres.CLASSES.pistol) do
        eq(key, "label", "the pistol class adds nothing to DEFAULTS but its label")
    end
    for name, class in pairs(AC_Calibres.CLASSES) do
        check(type(class.label) == "string" and class.label ~= "", "class " .. name .. " has a label for the summaries")
    end

    local ladder = AC_Calibres.levelsFor(1)
    eq(ladder.dieSet, 1, "levels never drop below 1")
    eq(ladder.bullet, 1, "bullet level clamped")
    eq(AC_Calibres.levelsFor(5).case, 3, "ladder for level 5")

    -- Every item the recipes name is probed at game start.
    local probed = {}
    for _, id in ipairs(AC_Compat.REQUIRED_ITEMS) do
        check(not probed[id], "compat list has no duplicate: " .. id)
        probed[id] = true
    end
    for _, id in ipairs(AC_Calibres.getItems()) do
        check(probed[id], "component recipe item is probed by AC_Compat (" .. id .. ")")
    end
    for _, id in ipairs({ "Base.Bullets9mm", "Base.Bullets38", "Base.Bullets45", "Base.Bullets357", "Base.Bullets44",
                          "Base.ShotgunShells", "Base.RippedSheets", "Base.CottonBalls",
                          "Base.GunPowder", "Base.Fertilizer", "Base.CapGunCap", "Base.Matches", "Base.SteelBarQuarter" }) do
        check(probed[id], "vanilla dependency probed: " .. id)
    end

    -- No calibre is hard-coded outside the calibre table.
    for _, name in ipairs(MOCK.MOD_FILES) do
        if name ~= "shared/AC_Calibres" then
            local source = readFile(LUA .. name .. ".lua")
            for _, calibre in ipairs(AC_Calibres.LIST) do
                check(string.find(source, calibre.suffix, 1, true) == nil, name .. ".lua does not mention " .. calibre.suffix)
            end
            for _, primer in ipairs(AC_Calibres.PRIMERS) do
                check(string.find(source, primer.item, 1, true) == nil, name .. ".lua does not name the primer item " .. primer.item)
            end
        end
    end
end

section("Calibre matrix (pinned): five pistol, three rifle, one shotgun")
do
    -- Vanilla round ids and ammo types as extracted from the installed
    -- 42.20.4 scripts. Balance values are tunable; a change here should be
    -- deliberate.
    --        id             class     suffix       round               ammo type            primer family  cups b/scrap powder level
    local matrix = {
        { "9mm",         "pistol", "9mm",       "Base.Bullets9mm",  "base:bullets_9mm",  "SmallPistol", 1, 2, 1, 3 },
        { ".38 Special", "pistol", "38Special", "Base.Bullets38",   "base:bullets_38",   "SmallPistol", 1, 2, 1, 3 },
        { ".45 ACP",     "pistol", "45ACP",     "Base.Bullets45",   "base:bullets_45",   "LargePistol", 1, 1, 1, 4 },
        { ".357 Magnum", "pistol", "357Magnum", "Base.Bullets357",  "base:bullets_357",  "SmallPistol", 1, 2, 2, 4 },
        { ".44 Magnum",  "pistol", "44Magnum",  "Base.Bullets44",   "base:bullets_44",   "LargePistol", 2, 1, 3, 5 },
        { "5.56",        "rifle",  "556NATO",   "Base.556Bullets",  "base:bullets_556",  "SmallRifle",  2, 2, 3, 5 },
        { ".30-30",      "rifle",  "3030Win",   "Base.3030Bullets", "base:bullets_3030", "LargeRifle",  2, 1, 4, 5 },
        { ".308",        "rifle",  "308Win",    "Base.308Bullets",  "base:bullets_308",  "LargeRifle",  3, 1, 5, 5 },
        { "12 Gauge",    "shotgun", "12Gauge",  "Base.ShotgunShells", "base:shotgun_shells", "LargePistol", 3, 1, 3, 4,
          case = "AmmoMaking.Hull12Gauge", bullet = "AmmoMaking.ShotCharge12Gauge", wads = 1 },
    }
    eq(#AC_Calibres.LIST, #matrix, "nine calibres")
    local U = AC_Materials.UNITS
    local nine = U["Base.Bullets9mm"].contents
    local pistols, rifles, shotguns = {}, {}, {}
    local byClass = { pistol = pistols, rifle = rifles, shotgun = shotguns }
    for index, row in ipairs(matrix) do
        local calibre = AC_Calibres.LIST[index]
        local name = row[1]
        eq(calibre.id, name, "calibre " .. index)
        eq(calibre.class, row[2], name .. " class")
        eq(calibre.suffix, row[3], name .. " suffix")
        eq(calibre.round, row[4], name .. " vanilla round")
        eq(calibre.ammoType, row[5], name .. " vanilla ammo type")
        eq(calibre.primerFamily, row[6], name .. " primer family")
        eq(calibre.cupsPerCase, row[7], name .. " cups per case")
        eq(calibre.bulletsPerScrap, row[8], name .. " bullets per scrap")
        eq(calibre.powderUses, row[9], name .. " powder charges")
        eq(calibre.levels.assemble, row[10], name .. " assembly level")
        eq(calibre.case, row.case or ("AmmoMaking.Case" .. row[3]), name .. " case item")
        eq(calibre.bullet, row.bullet or ("AmmoMaking.Bullet" .. row[3]), name .. " bullet item")
        eq(calibre.wads, row.wads or 0, name .. " wads")
        eq(calibre.dieSet, "AmmoMaking.DieSet" .. row[3], name .. " die set item")

        -- The round holds exactly its components.
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        eq(primer.class, AC_Calibres.CLASSES[calibre.class].primerClass or calibre.class, name .. " takes a primer family of the class its own class names")
        local round = U[calibre.round].contents
        eq(round.brass, 5 * row[7] + primer.brassUnits, name .. " brass per round")
        eq(round.copper, 10 / row[8], name .. " copper per round")
        eq(round.powder, row[9], name .. " powder per round")
        eq(round.compound, primer.compoundUnits, name .. " compound per round")
        eq(U[calibre.case].units, 5 * row[7], name .. " case brass")
        eq(U[calibre.bullet].units, 10 / row[8], name .. " bullet copper")
        for _, material in ipairs({ "brass", "copper", "powder", "compound" }) do
            check(round[material] >= nine[material], name .. " uses at least as much " .. material .. " as 9mm")
        end
        table.insert(byClass[calibre.class], calibre)
    end
    eq(#pistols, 5, "five pistol calibres")
    eq(#rifles, 3, "three rifle calibres")
    eq(#shotguns, 1, "one shotgun shell")
    eq(U["Base.Bullets9mm"].contents.brass, U["Base.Bullets38"].contents.brass, "9mm and .38 Special are the baseline pair")

    -- Pistols: .44 Magnum is the most expensive in every material.
    for _, calibre in ipairs(pistols) do
        for _, material in ipairs({ "brass", "copper", "powder", "compound" }) do
            check(U["Base.Bullets44"].contents[material] >= U[calibre.round].contents[material], ".44 Magnum uses at least as much " .. material .. " as " .. calibre.id)
        end
    end

    -- Rifles are the tier above: more brass than any standard pistol round,
    -- a charge at least as large as the largest pistol charge, more priming
    -- compound than the pistol primer of the same size, longer at every
    -- step, and never unlocked before the pistol ladder is climbed.
    local largestPistolCharge, highestPistolLevel = 0, 0
    for _, calibre in ipairs(pistols) do
        largestPistolCharge = math.max(largestPistolCharge, calibre.powderUses)
        highestPistolLevel = math.max(highestPistolLevel, calibre.levels.assemble)
    end
    local D = AC_Calibres.DEFAULTS
    for _, calibre in ipairs(rifles) do
        local round = U[calibre.round].contents
        check(calibre.powderUses >= largestPistolCharge, calibre.id .. " takes at least the largest pistol charge")
        check(calibre.powderUses <= 5, calibre.id .. " charge is compressed: at most half a jar per round")
        check(calibre.cupsPerCase >= 2, calibre.id .. " case takes at least two cups")
        check(round.brass > nine.brass, calibre.id .. " uses more brass than 9mm")
        check(calibre.levels.assemble >= highestPistolLevel, calibre.id .. " does not unlock before the top pistol calibre")
        for _, step in ipairs({ "dieSet", "case", "bullet", "assemble" }) do
            check(calibre.time[step] > D.time[step], calibre.id .. " " .. step .. " takes longer than the pistol step")
            check(calibre.xp[step] >= D.xp[step], calibre.id .. " " .. step .. " is worth at least the pistol XP")
        end
        for _, material in ipairs({ "brass", "powder", "compound" }) do
            check(U["Base.308Bullets"].contents[material] >= round[material], ".308 uses at least as much " .. material .. " as " .. calibre.id)
        end
    end
    -- The shell sits between the tiers: the brass of a .308, the charge
    -- and primer of a .44 Magnum, a whole scrap of shot, pistol times, and
    -- a level between the standard pistol rounds and the rifles.
    for _, calibre in ipairs(shotguns) do
        local round = U[calibre.round].contents
        eq(round.brass, U["Base.308Bullets"].contents.brass, calibre.id .. " holds as much brass as a .308")
        eq(round.powder, U["Base.Bullets44"].contents.powder, calibre.id .. " takes the .44 Magnum charge")
        eq(round.compound, U["Base.Bullets44"].contents.compound, calibre.id .. " takes the .44 Magnum primer")
        eq(round.copper, AC_Calibres.CONFIG.scrapUnits, calibre.id .. " shot charge is one whole scrap")
        check(calibre.levels.assemble > 3 and calibre.levels.assemble < AC_Calibres.CLASSES.rifle.assembleLevel, calibre.id .. " unlocks after the standard pistol rounds and before rifles")
        for _, step in ipairs({ "dieSet", "case", "bullet", "assemble" }) do
            eq(calibre.time[step], D.time[step], calibre.id .. " " .. step .. " takes the pistol time")
        end
        eq(calibre.wads, 1, calibre.id .. " takes one wad")
        eq(U[AC_Calibres.WAD.items[1]], nil, "wadding is not a tracked material")
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        if calibre.class ~= "shotgun" then eq(calibre.wads, 0, calibre.id .. " takes no wad") end
    end

    -- The three rifle calibres differ from each other.
    local seen = {}
    for _, calibre in ipairs(rifles) do
        local key = calibre.cupsPerCase .. "/" .. calibre.bulletsPerScrap .. "/" .. calibre.powderUses .. "/" .. calibre.primerFamily
        check(not seen[key], calibre.id .. " has its own material profile (" .. key .. ")")
        seen[key] = true
    end
end

section("Balance table: the document is generated from the calibre model")
do
    -- docs/AMMUNITION_DESIGN.md carries the one balance table. It is
    -- rendered from AC_Calibres (tests/render_balance.lua), so no number
    -- is typed twice.
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local document = readFile(ROOT .. "/docs/AMMUNITION_DESIGN.md")
    local from = string.find(document, BALANCE.START, 1, true)
    local _, to = string.find(document, BALANCE.FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the design document has the balance table markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderBlock(), "the balance tables equal the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceBlock(document), document, "regenerating changes nothing")
    eq(BALANCE.replaceBlock("no markers here"), nil, "a document without markers is not rewritten")

    -- README.md carries the players' shorter table of the same model.
    local readme = readFile(ROOT .. "/README.md")
    local rFrom = string.find(readme, BALANCE.SUMMARY_START, 1, true)
    local _, rTo = string.find(readme, BALANCE.SUMMARY_FINISH, 1, true)
    check(rFrom ~= nil and rTo ~= nil and rTo > rFrom, "the README has the calibre table markers")
    eq(string.sub(readme, rFrom or 1, rTo or 1), BALANCE.renderSummaryBlock(), "the README calibre table equals the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceSummary(readme), readme, "regenerating the README changes nothing")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(string.find(BALANCE.renderSummary(), "| " .. calibre.id .. " | " .. calibre.class .. " | `" .. calibre.round .. "` |", 1, true) ~= nil, calibre.id .. " has a README row")
    end
    -- No other table in the README repeats a calibre's numbers by hand.
    local outside = string.sub(readme, 1, (rFrom or 1) - 1) .. string.sub(readme, (rTo or 0) + 1)
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(string.find(outside, "| `" .. calibre.round .. "` |", 1, true) == nil, "the README has no hand-typed table row for " .. calibre.round)
    end

    -- One row per calibre and per family, and every value a consumer reads.
    local block = BALANCE.renderBlock()
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        local row = string.match(block, "\n(| " .. string.gsub(calibre.id, "%p", "%%%0") .. " | " .. calibre.class .. " |[^\n]*)")
        check(row ~= nil, calibre.id .. " has a balance row")
        row = row or ""
        for _, value in ipairs({ calibre.round, calibre.dieSet, calibre.primerFamily,
                                 calibre.levels.dieSet .. " / " .. calibre.levels.case .. " / " .. calibre.levels.bullet .. " / " .. calibre.levels.assemble,
                                 calibre.xp.dieSet .. " / " .. calibre.xp.case .. " / " .. calibre.xp.bullet .. " / " .. calibre.xp.assemble,
                                 calibre.time.dieSet .. " / " .. calibre.time.case .. " / " .. calibre.time.bullet .. " / " .. calibre.time.assemble }) do
            check(string.find(row, value, 1, true) ~= nil, calibre.id .. " row shows " .. value)
        end
        check(string.find(block, "| " .. calibre.id .. " | " .. (calibre.cupsPerCase * 5) .. " + " .. primer.brassUnits .. " = ", 1, true) ~= nil, calibre.id .. " has a material row")
    end
    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        check(string.find(block, "| " .. primer.id .. " | " .. primer.class .. " | `" .. primer.item .. "` |", 1, true) ~= nil, primer.id .. " has a primer row")
    end
    -- The table follows the model: a changed value changes the rendering.
    local nine = AC_Calibres.LIST[1]
    local saved = nine.powderUses
    nine.powderUses = 7
    check(BALANCE.renderBlock() ~= block, "a changed charge changes the rendered table")
    nine.powderUses = saved
    eq(BALANCE.renderBlock(), block, "and restoring it restores the table")
end

section("Primer families: pistol and rifle, small and large")
do
    eq(#AC_Calibres.PRIMERS, 4, "four primer families")
    local expectedItems = {
        SmallPistol = "AmmoMaking.SmallPistolPrimer", LargePistol = "AmmoMaking.LargePistolPrimer",
        SmallRifle = "AmmoMaking.SmallRiflePrimer", LargeRifle = "AmmoMaking.LargeRiflePrimer",
    }
    local expectedClass = { SmallPistol = "pistol", LargePistol = "pistol", SmallRifle = "rifle", LargeRifle = "rifle" }
    local itemsSeen = {}
    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        eq(primer.item, expectedItems[primer.id], primer.id .. " primer item")
        eq(primer.class, expectedClass[primer.id], primer.id .. " class")
        check(declaredItems[primer.item] ~= nil, primer.id .. " item is declared in AC_Items.txt")
        check(not itemsSeen[primer.item], primer.id .. " item is its own, not another family's")
        itemsSeen[primer.item] = true
        eq(AC_Calibres.identify(primer.item), "primer", primer.id .. " identified")
    end

    -- Family per calibre lives in the definition.
    local expected = {
        ["9mm"] = "SmallPistol", [".38 Special"] = "SmallPistol", [".357 Magnum"] = "SmallPistol",
        [".45 ACP"] = "LargePistol", [".44 Magnum"] = "LargePistol",
        ["5.56"] = "SmallRifle", [".30-30"] = "LargeRifle", [".308"] = "LargeRifle",
        ["12 Gauge"] = "LargePistol",
    }
    for _, calibre in ipairs(AC_Calibres.LIST) do
        eq(calibre.primerFamily, expected[calibre.id], calibre.id .. " primer family")
    end
    -- No shotshell family: the shell reuses the large pistol primer.
    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        check(primer.class ~= "shotgun", primer.id .. " is not a shotgun-only family")
    end

    -- Same abstraction for all four. Large = two small; rifle = the pistol
    -- primer of its size with half as much compound again.
    local U = AC_Materials.UNITS
    local P = AC_Calibres.getPrimer
    for _, class in ipairs({ "Pistol", "Rifle" }) do
        local small, large = P("Small" .. class), P("Large" .. class)
        eq(large.brassUnits, 2 * small.brassUnits, class .. ": a large primer holds twice the brass")
        eq(large.compoundUnits, 2 * small.compoundUnits, class .. ": and twice the compound")
        eq(large.perSheet * 2, small.perSheet, class .. ": so a sheet yields half as many")
        check(large.requiredLevel >= small.requiredLevel, class .. ": large primers do not unlock before small ones")
    end
    for _, size in ipairs({ "Small", "Large" }) do
        local pistol, rifle = P(size .. "Pistol"), P(size .. "Rifle")
        eq(rifle.brassUnits, pistol.brassUnits, size .. ": a rifle primer holds the brass of the pistol primer of its size")
        eq(rifle.compoundUnits * 2, pistol.compoundUnits * 3, size .. ": and half as much compound again")
        eq(rifle.perSheet, pistol.perSheet, size .. ": the same number per sheet")
        check(rifle.requiredLevel > pistol.requiredLevel, size .. ": rifle primers unlock after pistol primers")
    end

    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        eq(U[primer.item].contents.brass, primer.brassUnits, primer.id .. " brass units")
        eq(U[primer.item].contents.compound, primer.compoundUnits, primer.id .. " compound units")
        eq(primer.perSheet * primer.brassUnits, AC_Calibres.CONFIG.sheetUnits, primer.id .. " uses the whole sheet")
        for _, source in ipairs(AC_Calibres.COMPOUND_SOURCES) do
            local recipe = primerRecipe(primer, source.id)
            check(recipe ~= nil, primer.id .. " has a recipe from " .. source.id)
            eq(#recipe.inputs, 4, primer.id .. "/" .. source.id .. ": sheet, charge, punch, hammer")
            eq(recipe.inputs[1].items[1], "AmmoMaking.SmallBrassSheet", primer.id .. "/" .. source.id .. ": one small brass sheet")
            eq(recipe.inputs[1].count, 1, primer.id .. "/" .. source.id .. ": exactly one sheet")
            eq(recipe.inputs[2].count * source.units, primer.perSheet * primer.compoundUnits, primer.id .. "/" .. source.id .. ": the charge is exactly the compound in the primers")
            eq(recipe.inputs[2].count, math.floor(recipe.inputs[2].count), primer.id .. "/" .. source.id .. ": a whole number of " .. source.id)
            check(recipe.inputs[3].keep and recipe.inputs[4].keep, primer.id .. "/" .. source.id .. ": punch and hammer are kept")
            eq(#recipe.outputs, 1, primer.id .. "/" .. source.id .. ": one output line")
            eq(recipe.outputs[1].item, primer.item, primer.id .. "/" .. source.id .. ": makes its own family's primer")
            eq(recipe.outputs[1].count, primer.perSheet, primer.id .. "/" .. source.id .. ": primers per sheet")
            eq(recipe.requiredLevel, primer.requiredLevel, primer.id .. "/" .. source.id .. ": level")
            local consumed, created = AC_Materials.getRecipeUnits(recipe)
            eq(consumed.brass, created.brass, primer.id .. "/" .. source.id .. ": exact in brass")
            eq(consumed.compound, created.compound, primer.id .. "/" .. source.id .. ": exact in compound")
            check(AC_Materials.checkConservation(recipe), primer.id .. "/" .. source.id .. ": conserves")
            check(not AC_Materials.checkConservation({ id = "x", inputs = recipe.inputs, outputs = { { count = primer.perSheet + 1, item = primer.item } } }), primer.id .. "/" .. source.id .. ": one primer more is rejected")
        end
    end
    -- Toy caps: 10 per sheet for pistol primers, 15 for rifle primers.
    eq(primerRecipe(P("SmallPistol"), "Caps").inputs[2].count, 10, "small pistol: 10 caps")
    eq(primerRecipe(P("LargePistol"), "Caps").inputs[2].count, 10, "large pistol: 10 caps")
    eq(primerRecipe(P("SmallRifle"), "Caps").inputs[2].count, 15, "small rifle: 15 caps")
    eq(primerRecipe(P("LargeRifle"), "Caps").inputs[2].count, 15, "large rifle: 15 caps")
    eq(primerRecipe(P("LargeRifle"), "Matches").inputs[2].count, 30, "large rifle: 30 match uses")
    eq(#AC_Calibres.PRIMERS * #AC_Calibres.COMPOUND_SOURCES, 8, "eight primer recipes")

    -- A primer of one family is not material for another: no recipe turns
    -- a primer into anything but a round of a calibre of its family.
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        for _, input in ipairs(recipe.inputs) do
            for _, id in ipairs(input.items or {}) do
                local kind, family = AC_Calibres.identify(id)
                if kind == "primer" then
                    eq(recipe.step, "assemble", recipe.id .. " is the only kind of recipe that consumes a primer")
                    eq(AC_Calibres.get(recipe.calibre).primerFamily, family.id, recipe.id .. " consumes its own family's primer")
                end
            end
        end
    end
end

section("Calibre validation rejects broken definitions (mutations)")
do
    local function copy(t)
        local c = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                local inner = {}
                for k2, v2 in pairs(v) do inner[k2] = v2 end
                c[k] = inner
            else
                c[k] = v
            end
        end
        return c
    end
    local function listWith(index, change)
        local list = {}
        for i, calibre in ipairs(AC_Calibres.LIST) do
            list[i] = copy(calibre)
        end
        change(list[index], list)
        return list
    end
    local function rejects(what, index, change, needle)
        local problems = AC_Calibres.validate(listWith(index, change))
        local text = table.concat(problems, "; ")
        check(#problems > 0, what .. " is rejected")
        check(string.find(text, needle, 1, true) ~= nil, what .. " is named: " .. text)
    end

    local nine, fortyfive, fortyfour = 1, 3, 5
    rejects("a .44 recipe that takes the 9mm case", fortyfour, function(c, list) c.case = list[nine].case end, ".44 Magnum: case item AmmoMaking.Case9mm is already used by 9mm case")
    rejects("a .45 die set that is the 9mm die set", fortyfive, function(c, list) c.dieSet = list[nine].dieSet end, ".45 ACP: dieSet item AmmoMaking.DieSet9mm is already used by 9mm dieSet")
    rejects("two calibres sharing a bullet", fortyfive, function(c, list) c.bullet = list[fortyfour].bullet end, "is already used by")
    rejects("two calibres making the same round", 2, function(c, list) c.round = list[nine].round end, ".38 Special: round item Base.Bullets9mm is already used by 9mm round")
    rejects("a case that is also a bullet", nine, function(c) c.bullet = c.case end, "9mm: bullet item AmmoMaking.Case9mm is already used by 9mm case")
    rejects("a bullet that is a primer", nine, function(c) c.bullet = "AmmoMaking.SmallPistolPrimer" end, "is already used by primer SmallPistol")
    rejects("an unknown primer family", fortyfive, function(c) c.primerFamily = "Magnum" end, ".45 ACP: unknown primer family Magnum")
    rejects("a mod item as the round", nine, function(c) c.round = "AmmoMaking.Round9mm" end, "9mm: the round must be a vanilla item")
    rejects("no powder", nine, function(c) c.powderUses = 0 end, "9mm: powderUses must be a whole number of at least 1")
    rejects("half a charge", nine, function(c) c.powderUses = 0.5 end, "powderUses must be a whole number")
    rejects("a fractional bullet", nine, function(c) c.bulletsPerScrap = 3 end, "9mm: bulletsPerScrap must divide a scrap into whole units")
    rejects("half a cup", nine, function(c) c.cupsPerCase = 1.5 end, "9mm: cupsPerCase must be a whole number of at least 1")
    rejects("no cup at all", nine, function(c) c.cupsPerCase = 0 end, "cupsPerCase")
    rejects("a duplicate id", 2, function(c, list) c.id = list[nine].id end, "duplicate calibre id")
    rejects("a duplicate suffix", 2, function(c, list) c.suffix = list[nine].suffix end, "duplicate suffix 9mm")
    rejects("a suffix with punctuation", nine, function(c) c.suffix = "9 mm" end, "suffix must be letters and digits")
    rejects("a case that unlocks after its round", nine, function(c) c.levels.case = 9 end, "9mm: a component unlocks after the round it is for")
    rejects("a round below its primer's level", fortyfive, function(c) c.levels = AC_Calibres.levelsFor(1) end, ".45 ACP: its primer unlocks after its round")
    rejects("a round below the powder level", nine, function(c) c.levels = AC_Calibres.levelsFor(2) end, "9mm: gunpowder unlocks after its round")
    rejects("a missing level", nine, function(c) c.levels.bullet = nil end, "9mm: invalid level for bullet")
    rejects("zero xp", nine, function(c) c.xp.assemble = 0 end, "9mm: invalid xp for assemble")
    rejects("a missing case item", nine, function(c) c.case = nil end, "9mm: no case item")

    -- Rifle definitions (indexes 6-8).
    local five56, thirty30, three08 = 6, 7, 8
    rejects("a rifle recipe that takes a pistol primer", three08, function(c) c.primerFamily = "LargePistol" end, ".308: a rifle calibre cannot take the pistol primer family LargePistol")
    rejects("a pistol recipe that takes a rifle primer", nine, function(c) c.primerFamily = "SmallRifle" end, "9mm: a pistol calibre cannot take the rifle primer family SmallRifle")
    rejects("the wrong rifle case", three08, function(c, list) c.case = list[thirty30].case end, ".308: case item AmmoMaking.Case3030Win is already used by .30-30 case")
    rejects("the wrong rifle projectile", thirty30, function(c, list) c.bullet = list[three08].bullet end, "is already used by")
    rejects("a rifle using a pistol projectile", five56, function(c, list) c.bullet = list[nine].bullet end, "5.56: bullet item AmmoMaking.Bullet9mm is already used by 9mm bullet")
    rejects("the wrong rifle die set", five56, function(c, list) c.dieSet = list[three08].dieSet end, "is already used by")
    rejects("a rifle with no powder", three08, function(c) c.powderUses = 0 end, ".308: powderUses must be a whole number of at least 1")
    rejects("a rifle with half a cup more", three08, function(c) c.cupsPerCase = 2.5 end, ".308: cupsPerCase must be a whole number")
    rejects("an unknown class", five56, function(c) c.class = "cannon" end, "5.56: unknown class cannon")

    -- The shell (index 9).
    local twelve = 9
    eq(AC_Calibres.LIST[twelve].id, "12 Gauge", "the shell is the ninth definition")
    rejects("a shell that takes a rifle primer", twelve, function(c) c.primerFamily = "LargeRifle" end, "12 Gauge: a shotgun calibre cannot take the rifle primer family LargeRifle")
    rejects("a shell without a wad", twelve, function(c) c.wads = 0 end, "12 Gauge: a shotgun round needs at least 1 wad")
    rejects("a shell with half a wad", twelve, function(c) c.wads = 0.5 end, "12 Gauge: wads must be a whole number")
    rejects("a shell with no wad field", twelve, function(c) c.wads = nil end, "12 Gauge: wads must be a whole number")
    rejects("a shell in a .308 case", twelve, function(c, list) c.case = list[three08].case end, "12 Gauge: case item AmmoMaking.Case308Win is already used by .308 case")
    rejects("a shell loaded with a .44 bullet", twelve, function(c, list) c.bullet = list[fortyfour].bullet end, "12 Gauge: bullet item AmmoMaking.Bullet44Magnum is already used by .44 Magnum bullet")
    rejects("a shell made with the 9mm die set", twelve, function(c, list) c.dieSet = list[nine].dieSet end, "is already used by")
    rejects("a pistol round that makes shells", nine, function(c) c.round = "Base.ShotgunShells" end, "12 Gauge: round item Base.ShotgunShells is already used by 9mm round")
    rejects("a shell with no powder", twelve, function(c) c.powderUses = 0 end, "12 Gauge: powderUses must be a whole number of at least 1")
    rejects("a shell below its primer's level", twelve, function(c) c.levels = AC_Calibres.levelsFor(2) end, "12 Gauge: its primer unlocks after its round")
    rejects("a negative wad count on a pistol round", nine, function(c) c.wads = -1 end, "9mm: wads must be a whole number")
    -- A pistol or rifle calibre may not borrow a family: only a class that
    -- says so (primerClass) can.
    rejects("a rifle borrowing the shell's primer", thirty30, function(c) c.primerFamily = "LargePistol" end, ".30-30: a rifle calibre cannot take the pistol primer family LargePistol")
    do
        local shotgun = AC_Calibres.CLASSES.shotgun
        local saved = shotgun.primerClass
        shotgun.primerClass = nil
        local text = table.concat(AC_Calibres.validate(), "; ")
        shotgun.primerClass = "mortar"
        local unknown = table.concat(AC_Calibres.validate(), "; ")
        shotgun.primerClass = saved
        check(string.find(text, "12 Gauge: a shotgun calibre cannot take the pistol primer family LargePistol", 1, true) ~= nil, "without primerClass the shell may not take a pistol primer: " .. text)
        check(string.find(unknown, "class shotgun: unknown primer class mortar", 1, true) ~= nil, "an unknown primer class is named: " .. unknown)
    end

    -- Primer families.
    local function primersWith(change)
        local primers = {}
        for i, primer in ipairs(AC_Calibres.PRIMERS) do primers[i] = copy(primer) end
        change(primers)
        return primers
    end
    local function rejectsPrimer(what, change, needle)
        local text = table.concat(AC_Calibres.validate(nil, primersWith(change)), "; ")
        check(string.find(text, needle, 1, true) ~= nil, what .. " is rejected: " .. text)
    end
    rejectsPrimer("a large primer that is cheaper in brass", function(p) p[2].brassUnits = 1 end, "primer LargePistol: does not use exactly one small brass sheet")
    rejectsPrimer("six large primers from a sheet", function(p) p[2].perSheet = 6 end, "primer LargePistol: does not use exactly one small brass sheet")
    rejectsPrimer("a fractional priming charge", function(p) p[1].perSheet = 5; p[1].brassUnits = 2; p[1].compoundUnits = 1 end, "primer SmallPistol: takes a fractional amount of Caps")
    rejectsPrimer("both families using one item", function(p) p[2].item = p[1].item end, "primer LargePistol: item AmmoMaking.SmallPistolPrimer is already used by primer SmallPistol")
    rejectsPrimer("a duplicate family id", function(p) p[2].id = p[1].id end, "duplicate primer family id")
    rejectsPrimer("a removed family", function(p) table.remove(p, 2) end, "unknown primer family LargePistol")
    rejectsPrimer("a rifle primer with a fractional cap count", function(p) p[3].perSheet = 5; p[3].brassUnits = 2 end, "primer SmallRifle: takes a fractional amount of Caps")
    rejectsPrimer("a rifle primer family declared as pistol", function(p) p[4].class = "pistol" end, "a rifle calibre cannot take the pistol primer family LargeRifle")
    rejectsPrimer("a family with an unknown class", function(p) p[3].class = "mortar" end, "primer SmallRifle: unknown class mortar")

    eq(#AC_Calibres.validate(), 0, "the live tables were not touched by the mutations")
end

section("Cross-calibre isolation: no component fits another calibre")
do
    -- In the mirror: a calibre's recipes name only its own items.
    local owners = {}
    for _, calibre in ipairs(AC_Calibres.LIST) do
        for _, kind in ipairs({ "case", "bullet", "dieSet", "round" }) do
            owners[calibre[kind]] = calibre.id
        end
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        for _, recipe in ipairs(AC_Calibres.buildCalibreRecipes(calibre)) do
            local function own(id, where)
                if owners[id] then
                    eq(owners[id], calibre.id, recipe.id .. " " .. where .. " " .. id .. " belongs to its own calibre")
                end
                local kind, family = AC_Calibres.identify(id)
                if kind == "primer" then
                    eq(family, primer, recipe.id .. " takes only its own primer family")
                end
            end
            for _, input in ipairs(recipe.inputs) do
                for _, id in ipairs(input.items or {}) do own(id, "input") end
            end
            for _, output in ipairs(recipe.outputs) do own(output.item, "output") end
        end
    end

    -- In the generated script: a calibre's blocks mention no other calibre.
    local script = stripComments(readFile(SCRIPTS .. "AC_Recipes.txt"))
    for _, calibre in ipairs(AC_Calibres.LIST) do
        for _, recipe in ipairs(AC_Calibres.buildCalibreRecipes(calibre)) do
            local block = string.match(script, "craftRecipe " .. recipe.id .. "%s*(%b{})")
            check(block ~= nil, recipe.id .. " block found in the script")
            for _, other in ipairs(AC_Calibres.LIST) do
                if other ~= calibre then
                    check(string.find(block or "", other.suffix, 1, true) == nil, recipe.id .. " script block does not mention " .. other.suffix)
                end
            end
            for _, primer in ipairs(AC_Calibres.PRIMERS) do
                if primer.id ~= calibre.primerFamily then
                    check(string.find(block or "", primer.item, 1, true) == nil, recipe.id .. " script block does not take " .. primer.item)
                end
            end
        end
    end

    -- Executed on the mirror inventory: with every OTHER calibre's
    -- components and die sets in stock, and the wrong primer family,
    -- nothing can be formed, swaged or assembled.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local stock = { ["AmmoMaking.BrassCaseCup"] = 50, ["Base.CopperScrap"] = 50, ["Base.GunPowder"] = 50, ["base:hammer"] = 1 }
        for _, other in ipairs(AC_Calibres.LIST) do
            if other ~= calibre then
                stock[other.case], stock[other.bullet], stock[other.dieSet], stock[other.round] = 20, 20, 1, 20
            end
        end
        for _, primer in ipairs(AC_Calibres.PRIMERS) do stock[primer.item] = 20 end
        for _, step in ipairs({ "case", "bullet", "assemble" }) do
            check(not mirrorCraft(stock, calibreRecipe(calibre, step)), calibre.id .. " " .. step .. " cannot use another calibre's die set or components")
        end
        eq(stock[calibre.round], nil, calibre.id .. " no round appeared")

        -- Own die set, case and bullet, but only the other primer family.
        local own = { [calibre.case] = 1, [calibre.bullet] = 1, [calibre.dieSet] = 1, ["Base.GunPowder"] = 10, [AC_Calibres.WAD.items[1]] = 1 }
        for _, primer in ipairs(AC_Calibres.PRIMERS) do
            if primer.id ~= calibre.primerFamily then own[primer.item] = 10 end
        end
        check(not mirrorCraft(own, calibreRecipe(calibre, "assemble")), calibre.id .. " cannot be assembled with the other primer family")
        own[AC_Calibres.getPrimer(calibre.primerFamily).item] = 1
        check(mirrorCraft(own, calibreRecipe(calibre, "assemble")), calibre.id .. " assembles with its own family's primer")
        eq(own[calibre.round], 1, calibre.id .. " one round")
    end
end

section("Startup cost: validation and generation run at load, never per frame or per menu")
do
    -- Which events the mod listens to. Nothing per frame or per tick.
    local perFrame = {
        OnTick = true, OnTickEvenPaused = true, OnRenderTick = true, OnPlayerUpdate = true,
        OnPreUIDraw = true, OnPostUIDraw = true, OnPostRender = true, OnFETick = true,
        EveryOneMinute = true, OnObjectCollide = true, OnCharacterCollide = true,
    }
    local allowed = {
        OnFillWorldObjectContextMenu = true, OnFillInventoryObjectContextMenu = true,
        OnGameStart = true, OnGameBoot = true, OnInitGlobalModData = true,
        -- Once per world load, just before the engine parses the loot tables.
        OnPreDistributionMerge = true,
    }
    local registrations = 0
    local heavy = {
        "AC_Calibres.validate", "AC_Calibres.buildRecipes", "AC_Calibres.buildUnits", "AC_Calibres.getItems", "AC_Compat.run", "applySkillRequirements",
        "AC_Loot.register", "AC_Loot.validate", "AC_Loot.buildEntries", "AC_Loot.findReferencedLists",
        "AC_Recycling.validate", "AC_Recycling.buildRecipes", "AC_Recycling.buildGroups", "AC_Recycling.getScrappable",
        "AC_SaveData.check",
    }
    for _, name in ipairs(MOCK.MOD_FILES) do
        local source = readFile(LUA .. name .. ".lua")
        for event in string.gmatch(source, "Events%.([%w_]+)%.Add") do
            registrations = registrations + 1
            check(not perFrame[event], name .. ".lua does not listen to " .. event)
            check(allowed[event], name .. ".lua listens only to load and menu events (" .. event .. ")")
        end
        -- Menus and timed actions never rebuild the model or run the checks.
        local isMenuOrAction = string.find(name, "ContextMenu", 1, true) or string.find(name, "Action", 1, true) or string.find(name, "UI", 1, true)
        if isMenuOrAction then
            for _, call in ipairs(heavy) do
                check(string.find(source, call, 1, true) == nil, name .. ".lua does not call " .. call)
            end
        end
    end
    check(registrations >= 8, "event registrations were found (" .. registrations .. ")")

    -- Counted: loading the mod builds the recipe list twice (AC_Materials
    -- for the mirror, AC_Compat for its item list) and validates nothing;
    -- an inventory right-click builds and validates nothing.
    local counts = { validate = 0, buildRecipes = 0, buildCalibreRecipes = 0 }
    local real = {}
    for key in pairs(counts) do
        real[key] = AC_Calibres[key]
        AC_Calibres[key] = function(...)
            counts[key] = counts[key] + 1
            return real[key](...)
        end
    end
    local player = MOCK.newPlayer()
    local nine = AC_Calibres.get("9mm")
    for _ = 1, 50 do
        fillInventoryMenu(player, MOCK.newItem(nine.case))
        fillInventoryMenu(player, MOCK.newItem(nine.round))
        fillInventoryMenu(player, MOCK.newItem("Base.Plank"))
        AmmoInspection.inspectComponent(player, MOCK.newItem(nine.case))
    end
    MOCK.debug = false
    local square = MOCK.newSquare(3, 3, 0, GRASS)
    for _ = 1, 20 do fillWorldMenu(MOCK.newPlayer({ square = square }), square) end
    eq(counts.validate, 0, "no menu validates the calibre model")
    eq(counts.buildRecipes, 0, "no menu rebuilds the recipe list")
    eq(counts.buildCalibreRecipes, 0, "no menu rebuilds a calibre's recipes")

    -- One callback call does none of it either: it looks its recipe up.
    AC_Materials.onAssembleRound9mm(nil, player)
    eq(counts.validate + counts.buildRecipes + counts.buildCalibreRecipes, 0, "an OnCreate callback builds and validates nothing")

    -- The compatibility check validates once per run, and runs once per start.
    MOCK.capturePrint(true)
    AC_Compat.run(false)
    MOCK.capturePrint(false)
    eq(counts.validate, 1, "one compatibility run validates the model once")
    eq(counts.buildRecipes, 0, "and does not rebuild the whole recipe list")
    for key in pairs(counts) do AC_Calibres[key] = real[key] end

    -- The mining menu scans the inventory for samples once per right-click,
    -- whatever the number of metals, and not at all off natural ground.
    do
        local px, py = findTile("copper", 1)
        local scanPlayer, scanSquare = miningSetup(px, py, "Good", "Good", 1)
        local scans = 0
        local realScan = scanPlayer.inventory.getItemsFromFullType
        scanPlayer.inventory.getItemsFromFullType = function(self, fullType, recurse)
            scans = scans + 1
            return realScan(self, fullType, recurse)
        end
        local ctx = fillWorldMenu(scanPlayer, scanSquare)
        check(#ctx.options >= 1, "the mining menu offered something")
        local samplingScans = scans
        check(samplingScans <= 2, "one right-click on natural ground scans the inventory at most twice in all (" .. scans .. ")")
        -- The mining handler's own share: one scan for both metals.
        scans = 0
        local list = AC_Mining.getCarriedSamples(scanPlayer)
        eq(scans, 1, "getCarriedSamples is one scan")
        for _, metal in ipairs(AC_Deposits.METALS) do AC_Mining.findProspect(scanPlayer, scanSquare, metal, list) end
        eq(scans, 1, "findProspect with a list scans nothing more, for either metal")
        local alone = AC_Mining.findProspect(scanPlayer, scanSquare, "copper")
        eq(scans, 2, "findProspect without a list still scans for itself")
        eq(AC_Mining.findProspect(scanPlayer, scanSquare, "copper", list), alone, "and both ways find the same sample")
        eq(AC_Mining.findProspect(scanPlayer, scanSquare, "copper", false), nil, "an explicit 'no samples' finds nothing and does not scan")
        eq(scans, 2, "(no scan)")
        eq(AC_Mining.getCarriedSamples(nil), nil, "no player, no samples")
    end

    -- The panels look their constant strings up once, not every frame:
    -- nothing in a prerender or render body passes AC_Text.get straight to
    -- drawText. (The panels are not loaded offline; this reads the source.)
    for _, name in ipairs({ "client/AC_AmmoInspectionUI", "client/AC_GeologyAssayUI" }) do
        local source = readFile(LUA .. name .. ".lua")
        check(string.find(source, "drawText%(%s*AC_Text%.get%(") == nil, name .. ".lua draws no text it translates on the spot")
        check(string.find(source, "self%.titleText%s*=%s*self%.titleText%s*or AC_Text%.get%(") ~= nil, name .. ".lua caches its title")
    end

    -- The modules added later follow the same rule. Counted over a fresh
    -- load of the mod, a world load, a game start and a burst of menus:
    -- recycling builds its recipes once (for AC_Materials) and is validated
    -- once per compatibility run; loot is validated and built once per
    -- world load and never at file load; the schema is only consulted in
    -- -debug inspection.
    do
        reloadMod()
        local tally = {}
        local wrapped = {}
        local function count(module, moduleName, name)
            local key = moduleName .. "." .. name
            tally[key] = 0
            wrapped[key] = { module, name, module[name] }
            local original = module[name]
            module[name] = function(...)
                tally[key] = tally[key] + 1
                return original(...)
            end
        end
        for _, name in ipairs({ "register", "validate", "buildEntries", "findReferencedLists" }) do count(AC_Loot, "AC_Loot", name) end
        for _, name in ipairs({ "validate", "buildRecipes", "buildGroups", "getScrappable" }) do count(AC_Recycling, "AC_Recycling", name) end
        count(AC_SaveData, "AC_SaveData", "check")

        local menuPlayer = MOCK.newPlayer()
        local nineMm = AC_Calibres.get("9mm")
        local menuSquare = MOCK.newSquare(4, 3, 0, GRASS)
        for _ = 1, 30 do
            fillInventoryMenu(menuPlayer, MOCK.newItem(nineMm.case))
            fillInventoryMenu(menuPlayer, MOCK.newItem(nineMm.dieSet))
            fillInventoryMenu(menuPlayer, MOCK.newItem("Base.BrassScrap"))
            fillWorldMenu(MOCK.newPlayer({ square = menuSquare }), menuSquare)
            AmmoInspection.inspectComponent(menuPlayer, MOCK.newItem(nineMm.case))
            AC_Materials.onScrapBrass5(nil, menuPlayer)
        end
        for key, calls in pairs(tally) do eq(calls, 0, "no menu, inspection or callback calls " .. key) end

        local savedProcedural, savedDistributions = ProceduralDistributions, Distributions
        local lists, procList = {}, {}
        for _, target in ipairs(AC_Loot.TARGETS) do
            lists[target.list] = { rolls = 4, items = { "Nails", 1 } }
            table.insert(procList, { name = target.list, min = 0, max = 99 })
        end
        ProceduralDistributions = { list = lists }
        Distributions = { { gunstore = { displaycase = { procedural = true, procList = procList } } } }
        MOCK.capturePrint(true)
        Events.OnPreDistributionMerge.fire()
        MOCK.capturePrint(false)
        ProceduralDistributions, Distributions = savedProcedural, savedDistributions
        eq(tally["AC_Loot.register"], 1, "one world load registers the loot once")
        eq(tally["AC_Loot.validate"], 1, "validating the loot model once")
        eq(tally["AC_Loot.findReferencedLists"], 1, "and walking the distribution table once")
        check(tally["AC_Loot.buildEntries"] <= 2, "building the entries at most twice (" .. tally["AC_Loot.buildEntries"] .. ")")
        eq(tally["AC_Recycling.buildRecipes"] + tally["AC_Recycling.validate"], 0, "a world load does not touch recycling")

        MOCK.capturePrint(true)
        AC_Compat.run(false)
        MOCK.capturePrint(false)
        eq(tally["AC_Recycling.validate"], 1, "one compatibility run validates recycling once")
        eq(tally["AC_Loot.validate"], 2, "and the loot model once more")
        eq(tally["AC_Loot.register"], 1, "without registering anything")
        eq(tally["AC_SaveData.check"], 0, "the schema check is for -debug inspection only")
        for _, entry in pairs(wrapped) do entry[1][entry[2]] = entry[3] end

        -- At file load: the recipe list holds the recycling recipes, built once.
        local built = 0
        local realBuild = AC_Recycling.buildRecipes
        reloadMod()
        eq(#AC_Materials.RECIPES, 55, "the reloaded mod has its 55 recipes")
        eq(type(AC_Loot.lastSummary), "nil", "loading the mod registers no loot by itself")
        check(realBuild ~= nil and built == 0, "the counters above were removed before the reload")
    end

    -- identify() allocates nothing per call that depends on the list size:
    -- same answers as before, for every item of every calibre.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        for _, kind in ipairs({ "case", "bullet", "dieSet", "round" }) do
            local found, owner = AC_Calibres.identify(calibre[kind])
            eq(found, kind, calibre.id .. " " .. kind .. " identified")
            eq(owner, calibre, calibre.id .. " " .. kind .. " owner")
        end
    end
end

section("Reloading press recipes: prepared from the model, switched off")
do
    local P = AC_Calibres.PRESS
    local U = AC_Materials.UNITS

    -- Off: the station entity does not exist, so nothing of the press
    -- reaches the recipe list, the script, the callbacks or the names.
    eq(P.enabled, false, "the press is switched off")
    eq(#AC_Calibres.validatePress(), 0, "the press description is sound: " .. table.concat(AC_Calibres.validatePress(), "; "))
    local script = readFile(SCRIPTS .. "AC_Recipes.txt")
    check(string.find(script, P.benchTag, 1, true) == nil, "the recipe script names no press bench tag")
    check(string.find(script, P.idSuffix, 1, true) == nil, "nor any press recipe")
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        check(not recipe.press, recipe.id .. " is not a press recipe")
        check(recipe.benchTag ~= P.benchTag, recipe.id .. " does not use the press tag")
    end
    for key in pairs(AC_Materials) do
        check(type(key) ~= "string" or string.sub(key, -#P.idSuffix) ~= P.idSuffix, "no press callback is registered: " .. tostring(key))
    end
    check(not string.find(P.benchTag, "[^%w]"), "the bench tag has no separator the engine's tag query reads")
    eq(P.timedAction, "UseHandPress", "the vanilla press timed action")

    for _, calibre in ipairs(AC_Calibres.LIST) do
        local name = calibre.id
        local press = AC_Calibres.buildPressRecipes(calibre)
        eq(#press, #P.steps, name .. ": one press recipe per hand step")
        local seen = {}
        for _, recipe in ipairs(press) do
            local hand = AC_Materials.getRecipe(recipe.handRecipe)
            local what = name .. " " .. recipe.step
            check(hand ~= nil, what .. ": made from a real hand recipe")
            check(recipe.step ~= "dieSet", what .. ": the die set is forged, not pressed")
            check(not seen[recipe.step], what .. ": once")
            seen[recipe.step] = true
            eq(recipe.id, hand.id .. "AtPress", what .. ": id")
            eq(recipe.callback, hand.callback .. "AtPress", what .. ": callback name")
            eq(AC_Materials.getRecipe(recipe.id), nil, what .. ": not in the live recipe list")
            eq(recipe.benchTag, P.benchTag, what .. ": at the press")
            eq(recipe.timedAction, P.timedAction, what .. ": press timed action")
            eq(recipe.calibre, name, what .. ": names its calibre")
            eq(recipe.press, true, what .. ": marked as a press recipe")

            -- Faster, never free, and still long enough for the engine's
            -- skill speed-up (time / 20) to do something.
            eq(recipe.time, math.floor(hand.time * P.timePercent / 100), what .. ": time is the press's share of the hand time")
            -- The press saves time and nothing else: the ratio is the same
            -- for every calibre and step, to the rounding.
            check(recipe.time * 100 <= hand.time * P.timePercent and (recipe.time + 1) * 100 > hand.time * P.timePercent, what .. ": exactly the configured share, rounded down")
            check(recipe.time < hand.time, what .. ": the press is faster than the hand")
            check(recipe.time >= P.minimumTime, what .. ": at least " .. P.minimumTime)
            check(math.floor(recipe.time / 20) >= 1, what .. ": the skill speed-up still applies")

            -- Exactly the same material, level, XP, effect and outputs.
            local handIn, handOut = AC_Materials.getRecipeUnits(hand)
            local pressIn, pressOut = AC_Materials.getRecipeUnits(recipe)
            for _, material in ipairs({ "brass", "copper", "powder", "compound" }) do
                eq(pressIn[material], handIn[material], what .. ": consumes the same " .. material)
                eq(pressOut[material], handOut[material], what .. ": creates the same " .. material)
            end
            check(AC_Materials.checkConservation(recipe), what .. ": conserves material")
            eq(#recipe.outputs, #hand.outputs, what .. ": same output lines")
            eq(recipe.outputs[1].item, hand.outputs[1].item, what .. ": same output item")
            eq(recipe.outputs[1].count, hand.outputs[1].count, what .. ": same output count, no bonus")
            eq(recipe.requiredLevel, hand.requiredLevel, what .. ": same level")
            eq(recipe.xp, hand.xp, what .. ": same XP per craft")
            eq(recipe.effect, hand.effect, what .. ": same quality effect")

            -- The same die set, kept; no hammer; every other line unchanged.
            local dieSets, hammers, consumedLines = 0, 0, 0
            for _, input in ipairs(recipe.inputs) do
                if input.items and input.items[1] == calibre.dieSet then
                    dieSets = dieSets + 1
                    check(input.keep == true, what .. ": the die set is kept")
                end
                if input.tags and input.tags[1] == "base:hammer" then hammers = hammers + 1 end
                if not input.keep then consumedLines = consumedLines + 1 end
            end
            eq(dieSets, 1, what .. ": needs this calibre's own die set")
            eq(hammers, 0, what .. ": no hammer at the press")
            local handConsumed, handHammers = 0, 0
            for _, input in ipairs(hand.inputs) do
                if not input.keep then handConsumed = handConsumed + 1 end
                if input.tags and input.tags[1] == "base:hammer" then handHammers = handHammers + 1 end
            end
            eq(consumedLines, handConsumed, what .. ": every consumed line of the hand recipe is still there")
            eq(#recipe.inputs, #hand.inputs - handHammers, what .. ": only the hammer line is gone")
            for _, other in ipairs(AC_Calibres.LIST) do
                if other ~= calibre then
                    for _, input in ipairs(recipe.inputs) do
                        for _, id in ipairs(input.items or {}) do
                            check(id ~= other.dieSet and id ~= other.case and id ~= other.bullet, what .. ": takes nothing of " .. other.id)
                        end
                    end
                end
            end

            -- It renders as a well-formed block, like any recipe.
            local block = RENDER.renderRecipe(recipe)
            check(string.find(block, "craftRecipe " .. recipe.id, 1, true) ~= nil, what .. ": renders")
            check(string.find(block, "Tags = " .. P.benchTag .. ",", 1, true) ~= nil, what .. ": renders the press tag")
            check(string.find(block, "[" .. calibre.dieSet .. "] mode:keep", 1, true) ~= nil, what .. ": renders the kept die set")
        end
        -- The hand recipes are untouched by building the press versions.
        for _, hand in ipairs(AC_Calibres.buildCalibreRecipes(calibre)) do
            eq(AC_Materials.getRecipe(hand.id).benchTag, hand.benchTag, hand.id .. " keeps its own bench")
            check(hand.benchTag ~= P.benchTag, hand.id .. " stays a hand recipe")
        end
    end

    -- With skill. The engine shortens a recipe by time / 20 (whole
    -- division) for each level above its requirement (CraftRecipe.getTime
    -- in the 42.20.4 jar, mirrored by AC_Materials.getExpectedTime). A
    -- press time of 48 loses 2 per level where the hand's 80 loses 4, so
    -- the press's share of the hand time creeps up with skill. It must
    -- stay an advantage at every level, and never become a different deal
    -- for one calibre than for another.
    do
        local lowest, highest = math.huge, 0
        for _, calibre in ipairs(AC_Calibres.LIST) do
            for _, recipe in ipairs(AC_Calibres.buildPressRecipes(calibre)) do
                local hand = AC_Materials.getRecipe(recipe.handRecipe)
                for level = recipe.requiredLevel, 10 do
                    local byHand = AC_Materials.getExpectedTime(hand, level)
                    local pressed = AC_Materials.getExpectedTime(recipe, level)
                    local what = calibre.id .. " " .. recipe.step .. " at level " .. level
                    check(pressed > 0, what .. ": the press time stays positive (" .. pressed .. ")")
                    check(pressed < byHand, what .. ": the press is faster than the hand (" .. pressed .. " against " .. byHand .. ")")
                    local share = pressed / byHand
                    lowest, highest = math.min(lowest, share), math.max(highest, share)
                end
                eq(AC_Materials.getExpectedTime(recipe, recipe.requiredLevel), recipe.time, calibre.id .. " " .. recipe.step .. ": no speed-up at the level it unlocks")
            end
        end
        check(lowest >= P.timePercent / 100 - 0.005, "the press never takes less than its configured share (" .. string.format("%.3f", lowest) .. ")")
        check(highest <= 0.70, "and at most seven tenths of the hand time at any level (" .. string.format("%.3f", highest) .. ")")
        print(string.format("  Press: %d %% of the hand time at the unlock level, at most %.1f %% at level 10", P.timePercent, highest * 100))
    end

    -- Switched on, the generator adds three recipes per calibre after that
    -- calibre's own, and nothing else changes. (Not left on: restored below.)
    local before = AC_Calibres.buildRecipes()
    P.enabled = true
    local after = AC_Calibres.buildRecipes()
    P.enabled = false
    eq(#after, #before + #P.steps * #AC_Calibres.LIST, "enabled: three more recipes per calibre")
    local ids = {}
    for _, recipe in ipairs(after) do
        check(not ids[recipe.id], "enabled: recipe id unique: " .. recipe.id)
        ids[recipe.id] = true
    end
    for _, recipe in ipairs(before) do check(ids[recipe.id], "enabled: " .. recipe.id .. " is still there") end
    eq(#AC_Calibres.buildRecipes(), #before, "switched off again: the list is what it was")

    -- Names: a press recipe is called after its hand recipe. None is in
    -- Recipes.json while the press is off; each can be derived, is unique
    -- and collides with no existing name.
    do
        local names = {}
        for key, value in string.gmatch(readFile(TRANSLATE .. "Recipes.json"), '"([^"]+)"%s*:%s*"([^"]*)"') do names[key] = value end
        local taken, derived = {}, 0
        for _, value in pairs(names) do taken[value] = true end
        eq(P.nameSuffix, " (Press)", "the press name suffix")
        for _, calibre in ipairs(AC_Calibres.LIST) do
            for _, recipe in ipairs(AC_Calibres.buildPressRecipes(calibre)) do
                eq(names[recipe.id], nil, recipe.id .. " has no name yet")
                local handName = names[recipe.handRecipe]
                check(handName ~= nil and handName ~= "", recipe.id .. " can be named after " .. recipe.handRecipe)
                local name = tostring(handName) .. P.nameSuffix
                check(not taken[name], recipe.id .. " would get a name nothing else has (" .. name .. ")")
                taken[name] = true
                derived = derived + 1
            end
        end
        eq(derived, #P.steps * #AC_Calibres.LIST, "twenty-seven press names are ready to be written")
    end

    -- The press's advantage is pinned and bounded: 60 % of the hand time,
    -- tunable between a half and nine tenths, nothing else.
    eq(P.timePercent, 60, "the press takes 60 % of the hand time")
    eq(P.minimumPercent, 50, "it may be tuned down to half")
    eq(P.maximumPercent, 90, "and up to nine tenths")
    local nine = AC_Calibres.get("9mm")
    local times = {}
    for _, recipe in ipairs(AC_Calibres.buildPressRecipes(nine)) do times[recipe.step] = recipe.time end
    eq(times.case, 48, "9mm case at the press: 80 -> 48")
    eq(times.bullet, 48, "9mm bullets at the press: 80 -> 48")
    eq(times.assemble, 24, "9mm assembly at the press: 40 -> 24")
    for _, recipe in ipairs(AC_Calibres.buildPressRecipes(AC_Calibres.get(".308"))) do times[recipe.step] = recipe.time end
    eq(times.case, 96, ".308 case at the press: 160 -> 96")
    eq(times.assemble, 48, ".308 assembly at the press: 80 -> 48")

    -- A press that would be too fast, too slow or not a whole percentage
    -- is refused.
    local savedPercent, savedMinimum = P.timePercent, P.minimumTime
    local function pressProblems(percent)
        P.timePercent = percent
        local text = table.concat(AC_Calibres.validatePress(), "; ")
        P.timePercent = savedPercent
        return text
    end
    local bounds = "press: timePercent must be a whole number from 50 to 90"
    check(string.find(pressProblems(25), bounds, 1, true) ~= nil, "a press four times as fast is refused")
    check(string.find(pressProblems(49), bounds, 1, true) ~= nil, "just under half is refused")
    check(string.find(pressProblems(100), bounds, 1, true) ~= nil, "a press no faster than the hand is refused")
    check(string.find(pressProblems(0), bounds, 1, true) ~= nil, "a free press is refused")
    check(string.find(pressProblems(62.5), bounds, 1, true) ~= nil, "a fractional percentage is refused")
    check(string.find(pressProblems("fast"), bounds, 1, true) ~= nil, "a word is refused")
    eq(pressProblems(50), "", "half is the fastest allowed, and no step drops below the minimum")
    eq(pressProblems(90), "", "nine tenths is the slowest allowed")
    P.minimumTime = 30
    local text = table.concat(AC_Calibres.validatePress(), "; ")
    P.minimumTime = savedMinimum
    check(string.find(text, "9mm: press time of assemble is 24, below 30", 1, true) ~= nil, "a step that drops below the minimum time is named: " .. text)
    local savedSteps = P.steps
    P.steps = { "case", "dieSet" }
    local badStep = table.concat(AC_Calibres.validatePress(), "; ")
    P.steps = {}
    local noSteps = table.concat(AC_Calibres.validatePress(), "; ")
    P.steps = savedSteps
    check(string.find(badStep, "press: dieSet is not a step the press can do", 1, true) ~= nil, "a pressed die set is refused: " .. badStep)
    check(string.find(noSteps, "press: no steps", 1, true) ~= nil, "a press with no steps is refused")
    local savedTag = P.benchTag
    P.benchTag = "Ammo-Press"
    local badTag = table.concat(AC_Calibres.validatePress(), "; ")
    P.benchTag = savedTag
    check(string.find(badTag, "press: the bench tag must be letters and digits", 1, true) ~= nil, "a tag with a query separator is refused")
    eq(#AC_Calibres.validatePress(), 0, "the live press description was restored")
end

section("Case quality: one code path for every calibre (mocked recipe data)")
do
    -- What is stored is always a whole number from 1 to 100, whatever is
    -- handed to set().
    do
        local Q = AC_CaseQuality.CONFIG
        local stored = MOCK.newItem(AC_Calibres.get("9mm").case)
        for _, pair in ipairs({ { 900, Q.maxQuality }, { -5, Q.minQuality }, { 0, Q.minQuality }, { 55.6, 56 }, { 55.4, 55 }, { 100, 100 }, { 1, 1 } }) do
            eq(AC_CaseQuality.set(stored, pair[1]), true, "set(" .. pair[1] .. ") is accepted")
            eq(stored.modData[Q.qualityKey], pair[2], "set(" .. pair[1] .. ") stores " .. pair[2])
        end
        eq(AC_CaseQuality.set(stored, "good"), false, "a word is not a quality")
        eq(AC_CaseQuality.set(nil, 50), false, "no item, nothing stored")
        eq(stored.modData[Q.qualityKey], 1, "a refused set() leaves the stored value alone")
    end
    local C = AC_CaseQuality.CONFIG

    -- Pure roll.
    eq(AC_CaseQuality.roll(0, 0.5), C.baseQuality, "level 0, centre roll")
    eq(AC_CaseQuality.roll(10, 0.5), C.baseQuality + 10 * C.qualityPerLevel, "level 10, centre roll")
    eq(AC_CaseQuality.roll(3, 0.5), AC_CaseQuality.roll(3, 0.5), "same inputs, same quality")
    eq(AC_CaseQuality.roll(0, 0), C.baseQuality - C.spread, "lowest roll")
    eq(AC_CaseQuality.roll(0, 1), C.baseQuality + C.spread, "highest roll")
    eq(AC_CaseQuality.roll(10, 1), C.maxQuality, "clamped at the top")
    eq(AC_CaseQuality.roll(0, 0, -500), C.minQuality, "clamped at the bottom")
    eq(AC_CaseQuality.roll(99, 0.5), AC_CaseQuality.roll(10, 0.5), "level clamped to 10")
    eq(AC_CaseQuality.roll(-3, 0.5), AC_CaseQuality.roll(0, 0.5), "negative level counts as 0")
    eq(AC_CaseQuality.roll(nil, nil), C.baseQuality, "missing inputs give the level-0 centre")
    eq(AC_CaseQuality.roll(5, 7), AC_CaseQuality.roll(5, 1), "a roll above 1 is clamped")
    eq(AC_CaseQuality.roll(5, 0.5, 10), AC_CaseQuality.roll(5, 0.5) + 10, "a tool bonus is added (future press)")
    eq(C.minQuality, 1, "scale starts at 1")
    eq(C.maxQuality, 100, "scale ends at 100")
    local previous = 0
    for level = 0, 10 do
        local q = AC_CaseQuality.roll(level, 0.5)
        check(q > previous, "quality rises with level (" .. level .. ")")
        previous = q
        for step = 0, 10 do
            local rolled = AC_CaseQuality.roll(level, step / 10)
            check(rolled >= C.minQuality and rolled <= C.maxQuality and rolled == math.floor(rolled), "in range and whole at level " .. level)
        end
        check(AC_CaseQuality.roll(level, 0) >= 30, "even the worst roll at level " .. level .. " is not Dangerous")
    end
    check(AC_CaseQuality.roll(0, 0.9) > AC_CaseQuality.roll(0, 0.1), "quality rises with the roll")

    -- Labels are the existing AmmoQuality scale.
    eq(AC_CaseQuality.getLabel(95), "Excellent", "label 95")
    eq(AC_CaseQuality.getLabel(65), "Average", "label 65")
    eq(AC_CaseQuality.getLabel(10), "Dangerous", "label 10")
    eq(AC_CaseQuality.getLabel(nil), "Unknown", "label for no quality")
    eq(AmmoQuality.getQualityLabel(nil), "Unknown", "the cartridge label still works through the shared function")

    local function recipeData(created, consumed)
        return {
            getAllCreatedItems = function() return MOCK.arrayList(created or {}) end,
            getAllConsumedItems = function() return MOCK.arrayList(consumed or {}) end,
        }
    end

    -- Storage.
    local first = AC_Calibres.LIST[1]
    local case = MOCK.newItem(first.case)
    eq(AC_CaseQuality.get(case), nil, "a fresh case has no quality")
    eq(AC_CaseQuality.set(case, 72.4), true, "set")
    eq(AC_CaseQuality.get(case), 72, "stored as a whole number")
    eq(case.modData[C.flagKey], true, "case flagged")
    AC_CaseQuality.set(case, 500)
    eq(AC_CaseQuality.get(case), C.maxQuality, "stored value clamped")
    AC_CaseQuality.set(case, -40)
    eq(AC_CaseQuality.get(case), C.minQuality, "stored value clamped at the bottom")
    eq(AC_CaseQuality.set(case, "good"), false, "non-numeric quality refused")
    eq(AC_CaseQuality.set(nil, 50), false, "no item")
    case.modData[C.qualityKey] = "broken"
    eq(AC_CaseQuality.get(case), nil, "malformed stored quality counts as none")
    case.modData[C.qualityKey] = 9000
    eq(AC_CaseQuality.get(case), C.maxQuality, "an out-of-range stored value is clamped when read")
    eq(AC_CaseQuality.get(nil), nil, "no item, no quality")

    -- A seeded sequence of rolls gives the same qualities every time, for
    -- every calibre, through the same function.
    local function withRolls(sequence, fn)
        local realRandom = ZombRandFloat
        local index = 0
        ZombRandFloat = function()
            index = index + 1
            return sequence[(index - 1) % #sequence + 1]
        end
        local ok, result = pcall(fn)
        ZombRandFloat = realRandom
        assert(ok, result)
        return result
    end
    local sequence = { 0.0, 0.25, 0.5, 0.75, 0.999 }
    local reference
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local player = MOCK.newPlayer()
        player.perkLevel = 4
        local function formFive()
            local made = {}
            for i = 1, 5 do made[i] = MOCK.newItem(calibre.case) end
            return AC_CaseQuality.onCasesFormed(recipeData(made), player, 0), made
        end
        local writtenA = withRolls(sequence, formFive)
        local writtenB = withRolls(sequence, formFive)
        eq(table.concat(writtenA, ","), table.concat(writtenB, ","), calibre.id .. ": the same seeded rolls give the same qualities")
        eq(#writtenA, 5, calibre.id .. ": one quality per case")
        reference = reference or table.concat(writtenA, ",")
        eq(table.concat(writtenA, ","), reference, calibre.id .. ": quality does not depend on the calibre")
        for i, q in ipairs(writtenA) do
            eq(q, AC_CaseQuality.roll(4, sequence[i], 0), calibre.id .. ": case " .. i .. " is the pure roll")
        end

        -- Through the real callbacks, forming then assembling.
        local form, assemble = calibreRecipe(calibre, "case"), calibreRecipe(calibre, "assemble")
        eq(form.effect, "caseQuality", calibre.id .. ": forming rolls the quality")
        eq(assemble.effect, "roundQuality", calibre.id .. ": assembly inherits it")
        local formed = MOCK.newItem(calibre.case)
        local crafter = MOCK.newPlayer()
        crafter.perkLevel = 2
        MOCK.capturePrint(true)
        AC_Materials[form.callback](recipeData({ formed }), crafter)
        MOCK.capturePrint(false)
        eq(AC_CaseQuality.get(formed), C.baseQuality + 2 * C.qualityPerLevel, calibre.id .. ": the forming callback sets the quality")
        eq(#crafter.xpLog, 1, calibre.id .. ": forming grants XP once")
        local newRound = MOCK.newItem(calibre.round)
        MOCK.capturePrint(true)
        AC_Materials[assemble.callback](recipeData({ newRound }, { formed, MOCK.newItem(calibre.bullet) }), crafter)
        MOCK.capturePrint(false)
        eq(AC_CaseQuality.getRoundQuality(newRound), AC_CaseQuality.get(formed), calibre.id .. ": the assembly callback passes it to the round")
        eq(newRound.modData[C.roundFlagKey], true, calibre.id .. ": round flagged as handloaded")
        eq(#crafter.xpLog, 2, calibre.id .. ": one more XP grant, no more")

        -- A case of another calibre never lends its quality.
        local other = AC_Calibres.LIST[(calibre == first) and 2 or 1]
        local foreign = MOCK.newItem(other.case)
        AC_CaseQuality.set(foreign, 99)
        local lonely = MOCK.newItem(calibre.round)
        eq(AC_CaseQuality.onRoundsAssembled(recipeData({ lonely }, { foreign })), nil, calibre.id .. ": another calibre's case is ignored")
        eq(next(lonely.modData), nil, calibre.id .. ": and the round is left untouched")
    end

    -- Forming details.
    local player = MOCK.newPlayer()
    player.perkLevel = 4
    local made = { MOCK.newItem(first.case), MOCK.newItem(first.case), MOCK.newItem("Base.Plank") }
    local written = AC_CaseQuality.onCasesFormed(recipeData(made), player, 0)
    eq(#written, 2, "only the cases get a quality")
    eq(AC_CaseQuality.get(made[1]), C.baseQuality + 4 * C.qualityPerLevel, "quality follows the maker's level")
    eq(made[3].modData[C.qualityKey], nil, "other items are untouched")
    eq(#AC_CaseQuality.onCasesFormed(recipeData({ MOCK.newItem(first.case) }), nil, 0), 1, "no character: level 0, still a quality")
    eq(#AC_CaseQuality.onCasesFormed(nil, player, 0), 0, "no recipe data: nothing written, no error")
    eq(#AC_CaseQuality.onCasesFormed({}, player, 0), 0, "recipe data without the method: nothing written")

    -- Assembly: average of the consumed cases.
    local a, b = MOCK.newItem(first.case), MOCK.newItem(first.case)
    AC_CaseQuality.set(a, 60)
    AC_CaseQuality.set(b, 81)
    local round = MOCK.newItem(first.round)
    local plank = MOCK.newItem("Base.Plank")
    eq(AC_CaseQuality.onRoundsAssembled(recipeData({ round, plank }, { a, b, MOCK.newItem(first.bullet) })), 71, "average of the consumed cases, rounded")
    eq(round.modData.casingQuality, 71, "under the field name the AmmoQuality prototype uses")
    eq(plank.modData.casingQuality, nil, "other created items untouched")
    local plain = MOCK.newItem(first.round)
    eq(AC_CaseQuality.onRoundsAssembled(recipeData({ plain }, { MOCK.newItem(first.case) })), nil, "cases without a quality give the round none")
    eq(next(plain.modData), nil, "no ModData is created on such a round")
    eq(AC_CaseQuality.onRoundsAssembled(nil), nil, "no recipe data")
    eq(AC_CaseQuality.getRoundQuality(nil), nil, "no round")

    -- Only case forming and assembly have an effect.
    local effects = 0
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        if recipe.effect then
            effects = effects + 1
            check(type(AC_CaseQuality.EFFECTS[recipe.effect]) == "function", recipe.id .. " effect exists")
            check(recipe.step == "case" or recipe.step == "assemble", recipe.id .. " is a case or assembly step")
        end
    end
    eq(effects, 2 * #AC_Calibres.LIST, "nothing upstream of the case carries quality")

    -- A broken effect must not break the craft or the XP.
    local form = calibreRecipe(first, "case")
    local crafter = MOCK.newPlayer()
    local broken = { getAllCreatedItems = function() error("engine said no") end }
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okEffect, granted = pcall(AC_Materials[form.callback], broken, crafter)
    MOCK.capturePrint(false)
    check(okEffect, "a failing effect does not raise")
    eq(granted, AC_Materials.getRecipeXP(form), "XP is still granted")
    check(MOCK.printLogContains("WARNING: caseQuality failed for " .. form.id), "the failure is logged")

    -- Quality never touches material, in any calibre: the worst and the
    -- best case make the same round from the same inputs.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local assemble = calibreRecipe(calibre, "assemble")
        local consumed, created = AC_Materials.getRecipeUnits(assemble)
        for _, quality in ipairs({ 1, 100 }) do
            local c = MOCK.newItem(calibre.case)
            AC_CaseQuality.set(c, quality)
            local r = MOCK.newItem(calibre.round)
            AC_CaseQuality.onRoundsAssembled(recipeData({ r }, { c }))
            local consumedAfter, createdAfter = AC_Materials.getRecipeUnits(assemble)
            eq(createdAfter.brass, created.brass, calibre.id .. ": quality " .. quality .. " does not change the output")
            eq(consumedAfter.brass, consumed.brass, calibre.id .. ": quality " .. quality .. " does not change the input")
        end
        eq(#assemble.outputs, 1, calibre.id .. ": one output line whatever the quality")
    end
end

section("Progression: the pistol ladder")
do
    for _, id in ipairs({ "AmmoMaking_SmeltZincOre", "AmmoMaking_CastCopperIngot", "AmmoMaking_CastZincIngot", "AmmoMaking_CastBrassIngots", "AmmoMaking_ForgeSmallBrassSheets", "AmmoMaking_PunchBrassCaseCups" }) do
        eq(AC_Materials.getRequiredLevel(AC_Materials.getRecipe(id)), 0, id .. " stays open from level 0")
    end
    eq(AC_Materials.getRequiredLevel(nil), AC_Materials.CONFIG.requiredLevel, "no recipe: the default")

    -- The ladder: die set / case, bullet, round.
    local ladder = {
        ["9mm"] = { 1, 1, 2, 3 }, [".38 Special"] = { 1, 1, 2, 3 },
        [".45 ACP"] = { 2, 2, 3, 4 }, [".357 Magnum"] = { 2, 2, 3, 4 },
        [".44 Magnum"] = { 3, 3, 4, 5 },
        ["5.56"] = { 3, 3, 4, 5 }, [".30-30"] = { 3, 3, 4, 5 }, [".308"] = { 3, 3, 4, 5 },
        ["12 Gauge"] = { 2, 2, 3, 4 },
    }
    local roundLevels = {}
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local expected = ladder[calibre.id]
        eq(calibre.levels.dieSet, expected[1], calibre.id .. " die set level")
        eq(calibre.levels.case, expected[2], calibre.id .. " case level")
        eq(calibre.levels.bullet, expected[3], calibre.id .. " bullet level")
        eq(calibre.levels.assemble, expected[4], calibre.id .. " round level")
        roundLevels[calibre.levels.assemble] = true
    end
    check(roundLevels[3] and roundLevels[4] and roundLevels[5], "rounds unlock across levels 3, 4 and 5, not all at once")
    eq(AC_Calibres.getPrimer("SmallPistol").requiredLevel, 2, "small pistol primers at level 2")
    eq(AC_Calibres.getPrimer("LargePistol").requiredLevel, 3, "large pistol primers at level 3")
    eq(AC_Calibres.getPrimer("SmallRifle").requiredLevel, 4, "small rifle primers at level 4")
    eq(AC_Calibres.getPrimer("LargeRifle").requiredLevel, 4, "large rifle primers at level 4")
    eq(AC_Calibres.POWDER.requiredLevel, 3, "gunpowder at level 3")

    local highest = 0
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local level = AC_Materials.getRequiredLevel(recipe)
        check(level >= 0 and level <= 10 and level == math.floor(level), recipe.id .. " has a valid level")
        if level > highest then highest = level end
        if recipe.calibre then
            local calibre = AC_Calibres.get(recipe.calibre)
            eq(level, calibre.levels[recipe.step], recipe.id .. " level comes from its calibre definition")
            eq(AC_Materials.getRecipeXP(recipe), calibre.xp[recipe.step], recipe.id .. " xp comes from its calibre definition")
            eq(recipe.time, calibre.time[recipe.step], recipe.id .. " time comes from its calibre definition")
        end
    end
    eq(highest, 5, "the ladder tops out at level 5: no recipe sits behind the steep part of the XP curve")
    for level = 1, highest do
        local open = false
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if AC_Materials.getRequiredLevel(recipe) < level and AC_Materials.getRecipeXP(recipe) > 0 then open = true end
        end
        check(open, "XP can be earned below level " .. level)
    end

    -- The requirement the engine enforces is the one attached to the script.
    local ids = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
    MOCK.resetCraftRecipes(ids)
    AC_Materials.applySkillRequirements()
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local attached = MOCK.craftRecipeScripts[recipe.id].requiredSkills
        eq(#attached, 1, recipe.id .. " has one requirement attached")
        eq(attached[1].level, AC_Materials.getRequiredLevel(recipe), recipe.id .. " attached level")
        eq(attached[1].perk, AmmoMakingSkill.perk, recipe.id .. " requires Ammo Making, not another skill")
    end

    local assemble = AC_Materials.getRecipe("AmmoMaking_AssembleRound9mm")
    eq(AC_Materials.getExpectedTime(assemble, 3), assemble.time, "no speed-up at the required level")
    eq(AC_Materials.getExpectedTime(assemble, 2), assemble.time, "nor below it")
    eq(AC_Materials.getExpectedTime(assemble, 10), assemble.time - 7 * math.floor(assemble.time / 20), "5% per level above the requirement")
end

section("XP economy: a simulated career from the first ore (mirror inventory)")
do
    -- The perk's per-level XP amounts, as the mod registers them.
    local perLevel = MOCK.perkXP
    check(type(perLevel) == "table" and #perLevel == 10, "the perk registers ten level thresholds")
    local total, cumulative = 0, {}
    for level, amount in ipairs(perLevel) do
        total = total + amount
        cumulative[level] = total
    end
    eq(cumulative[3], 525, "level 3 at 525 XP")
    eq(cumulative[5], 2775, "level 5 at 2775 XP")
    local function levelFor(xp)
        local level = 0
        for l, needed in ipairs(cumulative) do
            if xp >= needed then level = l end
        end
        return level
    end

    local R = AC_Materials.getRecipe
    local career = { xp = 0, ore = 0, rounds = 0, byClass = { pistol = 0, rifle = 0, shotgun = 0 }, reached = {}, roundsAt = {}, byRecipe = {}, byFamily = {}, inventory = {} }
    -- Which family of work a recipe belongs to, for the XP breakdown.
    local function familyOf(recipe)
        if recipe.calibre then
            return AC_Calibres.get(recipe.calibre).class .. " " .. recipe.step
        elseif recipe.step then
            return recipe.step
        elseif recipe.benchTag == "PrimitiveFurnace" or recipe.benchTag == "Furnace" then
            return "metallurgy"
        end
        return "case stock"
    end
    local inv = career.inventory
    -- Loot and tools are assumed available; ore is what is counted.
    for _, id in ipairs({ "base:hammer", "base:tongs", "base:crudetongs", "base:metalworkingpunch", "base:ballpeenhammer",
                          "base:metalworkingpliers", "base:whetstone", "base:mortarpestle", "Base.CeramicCrucible", "Base.ClayIngotMold" }) do
        inv[id] = 1
    end
    inv["base:charcoal"], inv["Base.Fertilizer"], inv["Base.CapGunCap"], inv["Base.SteelBarQuarter"] = 100000, 100000, 100000, 100
    inv[AC_Calibres.WAD.items[1]] = 100000

    local function gain(amount, label, family)
        career.xp = career.xp + amount
        career.byRecipe[label] = (career.byRecipe[label] or 0) + amount
        career.byFamily[family] = (career.byFamily[family] or 0) + amount
        local level = levelFor(career.xp)
        for l = 1, level do
            if not career.reached[l] then
                career.reached[l] = career.ore
                career.roundsAt[l] = career.rounds
            end
        end
    end
    -- Prospecting comes before ore. A sampled 3x3 site of Moderate grade
    -- holds one ore per tile; when it is worked out the next site is dug
    -- and field-assayed. Digging itself grants nothing. The advanced and
    -- laboratory assays are optional and left out, so this is the lower
    -- bound of prospecting XP; the upper bound is reported below.
    local orePerSite = 9 * AC_Deposits.CONFIG.reserveByGrade["Moderate"]
    career.sites = 0
    local function mine(item, n)
        for _ = 1, n do
            if career.ore % orePerSite == 0 then
                career.sites = career.sites + 1
                gain(AC_GeologySampling.CONFIG.fieldAssayXP, "field assay", "prospecting")
            end
            inv[item] = (inv[item] or 0) + 1
            career.ore = career.ore + 1
            gain(AC_Mining.CONFIG.xpPerOre, "mining", "mining")
        end
    end
    -- A craft only happens when the character's level allows it.
    local function make(recipe, n)
        local done = 0
        for _ = 1, n do
            if levelFor(career.xp) < AC_Materials.getRequiredLevel(recipe) then break end
            if not mirrorCraft(inv, recipe) then break end
            gain(AC_Materials.getRecipeXP(recipe), recipe.id, familyOf(recipe))
            done = done + 1
        end
        return done
    end
    local vanillaSmelt = AC_Materials.VANILLA_RECIPES[1]
    local function smeltCopper(n)
        for _ = 1, n do mirrorCraft(inv, vanillaSmelt) end
    end

    -- One cycle: a ten-ore brass batch, the copper for its bullets, and as
    -- many rounds as possible of the most advanced calibre the character
    -- can assemble (the last one in the list at the highest open level, so
    -- the career moves from pistols on to rifles).
    local function cycle()
        local level = levelFor(career.xp)
        local target = AC_Calibres.LIST[1]
        for _, calibre in ipairs(AC_Calibres.LIST) do
            if calibre.levels.assemble <= math.max(level, 3) and calibre.levels.assemble >= target.levels.assemble then
                target = calibre
            end
        end
        local primer = AC_Calibres.getPrimer(target.primerFamily)

        mine("Base.CopperOre", 7)
        mine("AmmoMaking.ZincOre", 3)
        smeltCopper(7)
        make(R("AmmoMaking_SmeltZincOre"), 3)
        make(R("AmmoMaking_CastCopperIngot"), 7)
        make(R("AmmoMaking_CastZincIngot"), 3)
        make(R("AmmoMaking_CastBrassIngots"), 1)
        make(R("AmmoMaking_ForgeSmallBrassSheets"), 10)

        -- Split the hundred sheets between primers and cups.
        local rounds = math.floor(200 / (target.cupsPerCase + 2 / primer.perSheet))
        local primerSheets = math.ceil(rounds / primer.perSheet)
        make(R("AmmoMaking_PunchBrassCaseCups"), (inv["AmmoMaking.SmallBrassSheet"] or 0) - primerSheets)

        local copperOre = math.ceil(rounds / target.bulletsPerScrap / 10)
        mine("Base.CopperOre", copperOre)
        smeltCopper(copperOre)

        if (inv[target.dieSet] or 0) == 0 then make(calibreRecipe(target, "dieSet"), 1) end
        make(calibreRecipe(target, "case"), rounds)
        make(calibreRecipe(target, "bullet"), math.ceil(rounds / target.bulletsPerScrap))
        make(primerRecipe(primer, "Caps"), primerSheets)
        make(R("AmmoMaking_MixGunpowder"), math.ceil(rounds * target.powderUses / AC_Calibres.POWDER.usesPerJar))
        local made = make(calibreRecipe(target, "assemble"), rounds)
        if target.class == "rifle" and made > 0 and not career.firstRifleOre then
            career.firstRifleOre = career.ore
            career.roundsBeforeRifle = career.rounds
        end
        if target.class == "shotgun" and made > 0 and not career.firstShellOre then
            career.firstShellOre = career.ore
        end
        career.rounds = career.rounds + made
        career.byClass[target.class] = career.byClass[target.class] + made
        return target
    end

    local CYCLES = 10
    local targets = {}
    for i = 1, CYCLES do targets[i] = cycle().id end

    -- Recycling is not part of the climb: scrapping every leftover cup and
    -- sheet of the career and casting the scrap adds no XP at any point.
    do
        local xpBefore, brassBefore = career.xp, 0
        for _, id in ipairs({ "AmmoMaking.BrassCaseCup", "AmmoMaking.SmallBrassSheet", "Base.BrassIngot", "Base.BrassScrap" }) do
            brassBefore = brassBefore + (inv[id] or 0) * AC_Materials.UNITS[id].units
        end
        local scrapped = 0
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.recycling then scrapped = scrapped + make(recipe, 100000) end
        end
        eq(career.xp, xpBefore, "recycling the career's leftovers earns no XP (" .. scrapped .. " recycling crafts)")
        eq(career.byFamily.scrap, scrapped > 0 and 0 or nil, "the scrap family holds no XP")
        local brassAfter = 0
        for _, id in ipairs({ "AmmoMaking.BrassCaseCup", "AmmoMaking.SmallBrassSheet", "Base.BrassIngot", "Base.BrassScrap" }) do
            brassAfter = brassAfter + (inv[id] or 0) * AC_Materials.UNITS[id].units
        end
        check(brassAfter <= brassBefore, "and never adds brass (" .. brassBefore .. " -> " .. brassAfter .. " units)")
        career.byFamily.scrap, career.byFamily.recast = nil, nil
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.recycling then career.byRecipe[recipe.id] = nil end
        end
    end

    -- How much ore each level takes.
    check(career.reached[1] ~= nil and career.reached[1] <= 10, "level 1 within the first brass batch (" .. tostring(career.reached[1]) .. " ore)")
    check(career.reached[3] ~= nil and career.reached[3] <= 20, "level 3 within the first cycle (" .. tostring(career.reached[3]) .. " ore)")
    check(career.reached[4] ~= nil and career.reached[4] <= 45, "level 4 by the third cycle (" .. tostring(career.reached[4]) .. " ore)")
    check(career.reached[5] ~= nil and career.reached[5] <= 90, "level 5, the top of the pistol ladder, within about five cycles (" .. tostring(career.reached[5]) .. " ore)")
    check(career.reached[1] <= career.reached[2] and career.reached[2] <= career.reached[3] and career.reached[3] < career.reached[4] and career.reached[4] < career.reached[5], "levels come in order")
    print("  XP economy: ore to reach levels 1-5 = " .. table.concat({ career.reached[1], career.reached[2], career.reached[3], career.reached[4], career.reached[5] }, ", ")
        .. "; rounds made by then = " .. table.concat({ career.roundsAt[1], career.roundsAt[2], career.roundsAt[3], career.roundsAt[4], career.roundsAt[5] }, ", ")
        .. "; after " .. CYCLES .. " cycles: " .. career.ore .. " ore, " .. career.byClass.pistol .. " pistol + " .. career.byClass.shotgun .. " shotgun + " .. career.byClass.rifle .. " rifle rounds, " .. career.xp .. " XP (level " .. levelFor(career.xp) .. ")")
    print("  XP economy: level 6 after " .. tostring(career.reached[6]) .. " ore (" .. tostring(career.roundsAt[6]) .. " rounds), level 7 after " .. tostring(career.reached[7]) .. " ore; nothing requires either")
    print("  XP economy: targets " .. table.concat(targets, " / ") .. "; first shell after " .. tostring(career.firstShellOre) .. " ore; first rifle round after " .. tostring(career.firstRifleOre) .. " ore and " .. tostring(career.roundsBeforeRifle) .. " pistol rounds and shells")
    do
        local families = {}
        for family, amount in pairs(career.byFamily) do table.insert(families, { family, amount }) end
        table.sort(families, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for _, entry in ipairs(families) do
            table.insert(parts, entry[1] .. " " .. math.floor(100 * entry[2] / career.xp + 0.5) .. "%")
        end
        print("  XP economy: share by family = " .. table.concat(parts, ", "))
        local top, topAmount = nil, 0
        for label, amount in pairs(career.byRecipe) do
            if amount > topAmount then top, topAmount = label, amount end
        end
        print("  XP economy: largest single source = " .. tostring(top) .. " (" .. math.floor(100 * topAmount / career.xp + 0.5) .. "%)")
        career.topFamilyShare = families[1][2] / career.xp
    end

    -- Every source of Ammo Making XP in the mod is in the career: assays,
    -- mining and every recipe. Prospecting stays a small share even when
    -- every site also gets the advanced and the laboratory assay.
    eq(orePerSite, 9, "a Moderate 3x3 site holds nine ore")
    eq(career.sites, math.ceil(career.ore / orePerSite), "one site per nine ore")
    eq(career.byFamily.prospecting, career.sites * AC_GeologySampling.CONFIG.fieldAssayXP, "one field assay per site")
    local thorough = career.sites * (AC_GeologySampling.CONFIG.fieldAssayXP + AC_GeologySampling.CONFIG.advancedAssayXP + AC_LaboratoryAnalyzer.CONFIG.assayXP)
    check(career.byFamily.prospecting / career.xp < 0.05, "field assays are a small share of the career's XP")
    check(thorough / (career.xp - career.byFamily.prospecting + thorough) < 0.10, "even with every assay on every site, prospecting stays under a tenth")
    print("  XP economy: " .. career.sites .. " sites prospected; prospecting XP " .. career.byFamily.prospecting .. " with field assays only, " .. thorough .. " with all three assays on every site")

    -- Ammunition is not unlocked before there is material to use it on:
    -- by level 3 the first batch's cases and bullets exist.
    eq(career.roundsAt[3], 0, "no round is assembled before level 3")
    check(career.rounds > 100, "rounds are being produced (" .. career.rounds .. ")")
    eq(AC_Calibres.get(targets[1]).class, "pistol", "the career starts with a pistol calibre")
    eq(AC_Calibres.get(targets[1]).levels.assemble, 3, "one of the level-3 calibres")
    eq(AC_Calibres.get(targets[CYCLES]).class, "rifle", "and moves on to rifles")

    -- Rifles are the tier after pistols: reachable, but only once the
    -- pistol ladder has been climbed by making pistol ammunition.
    check(career.firstRifleOre ~= nil, "rifle rounds are produced within the simulated career")
    check(career.firstRifleOre >= career.reached[5], "no rifle round before level 5")
    check(career.firstRifleOre <= 100, "the first rifle round within about a hundred ore (" .. tostring(career.firstRifleOre) .. ")")
    check(career.roundsBeforeRifle >= 200, "pistols and shells establish the skill: at least 200 rounds first (" .. tostring(career.roundsBeforeRifle) .. ")")
    check(career.byClass.rifle > 0, "rifle rounds made (" .. career.byClass.rifle .. ")")
    -- Shells are the middle tier: after the first pistol rounds, before rifles.
    check(career.byClass.pistol > 0, "pistol rounds made (" .. career.byClass.pistol .. ")")
    check(career.byClass.shotgun > 0, "shells made (" .. career.byClass.shotgun .. ")")
    check(career.firstShellOre ~= nil and career.firstShellOre >= career.reached[4], "no shell before level 4")
    check(career.firstShellOre < career.firstRifleOre, "shells come before rifle rounds")
    eq(career.byClass.pistol + career.byClass.shotgun + career.byClass.rifle, career.rounds, "every round is counted in its class")
    check(career.topFamilyShare <= 0.45, "no family of work gives more than 45% of the career's XP")
    -- Nothing in the mod sits behind level 6 or beyond.
    check(career.reached[6] == nil or career.reached[6] > career.reached[5], "level 6, if reached, is not needed for anything")

    -- No recipe dominates, and nothing is massively over-rewarded.
    local recipeTotal = 0
    for _, amount in pairs(career.byRecipe) do recipeTotal = recipeTotal + amount end
    eq(recipeTotal, career.xp, "every XP point is accounted for")
    for label, amount in pairs(career.byRecipe) do
        check(amount <= 0.45 * career.xp, label .. " gives less than 45% of all XP (" .. amount .. "/" .. career.xp .. ")")
    end
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local consumed = AC_Materials.getRecipeUnits(recipe)
        local units = 0
        for _, amount in pairs(consumed) do units = units + amount end
        if units > 0 then
            check(AC_Materials.getRecipeXP(recipe) / units <= 0.5, recipe.id .. " XP per unit of material stays modest")
        end
        check(AC_Materials.getRecipeXP(recipe) <= 25, recipe.id .. " gives at most the brass batch's XP")
    end

    -- XP cannot be farmed: every XP-granting recipe destroys something, and
    -- apart from brass recycling (which loses half of the brass per
    -- round trip and awards nothing; see the recycling section) the only
    -- cycle among all items is round <-> gunpowder, which loses the case,
    -- the primer and the bullet each time round.
    local edges = {}
    local all = {}
    for _, r in ipairs(AC_Materials.RECIPES) do table.insert(all, r) end
    for _, r in ipairs(AC_Materials.VANILLA_RECIPES) do table.insert(all, r) end
    for _, recipe in ipairs(all) do
        local consumes = false
        for _, input in ipairs(recipe.inputs) do
            if not input.keep then
                consumes = true
                for _, from in ipairs(input.items or {}) do
                    if not recipe.loss then
                        edges[from] = edges[from] or {}
                        for _, output in ipairs(recipe.outputs) do edges[from][output.item] = recipe end
                    end
                end
            end
        end
        check(consumes, recipe.id .. " consumes something")
    end
    local function reaches(from, target, visited)
        for nextItem in pairs(edges[from] or {}) do
            if nextItem == target then return true end
            if not visited[nextItem] then
                visited[nextItem] = true
                if reaches(nextItem, target, visited) then return true end
            end
        end
        return false
    end
    local onCycle = {}
    for id in pairs(edges) do
        if reaches(id, id, {}) then table.insert(onCycle, id) end
    end
    table.sort(onCycle)
    local expectedCycle = { "Base.GunPowder" }
    for _, calibre in ipairs(AC_Calibres.LIST) do table.insert(expectedCycle, calibre.round) end
    table.sort(expectedCycle)
    eq(table.concat(onCycle, ","), table.concat(expectedCycle, ","), "scrapping aside, the only reversible items are the rounds and the powder gathered from them")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        -- Ten rounds, taken apart and rebuilt as far as possible, with the
        -- die set at hand: XP earned must be zero, because nothing can be
        -- assembled from powder alone.
        local loop = { [calibre.round] = 10, [calibre.dieSet] = 1 }
        local gather
        for _, vanilla in ipairs(AC_Materials.VANILLA_RECIPES) do
            if vanilla.id == "GatherGunpowder_" .. calibre.suffix then gather = vanilla end
        end
        check(gather ~= nil, calibre.id .. ": vanilla Gather Gunpowder is modelled")
        for _ = 1, 10 do mirrorCraft(loop, gather) end
        eq(loop["Base.GunPowder"], 10, calibre.id .. ": ten rounds give ten uses, whatever the charge was")
        check(not mirrorCraft(loop, calibreRecipe(calibre, "assemble")), calibre.id .. ": powder alone rebuilds nothing, so the loop earns no XP")
        check(loop["Base.GunPowder"] <= 10 * calibre.powderUses, calibre.id .. ": gathering never returns more powder than went in")
    end
end

section("Economy: a hundred rounds of every calibre and four loadouts, from ore")
do
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local R = AC_Materials.getRecipe

    -- The document's table is the rendering of the model.
    local document = readFile(ROOT .. "/docs/AMMUNITION_DESIGN.md")
    local from = string.find(document, BALANCE.ECONOMY_START, 1, true)
    local _, to = string.find(document, BALANCE.ECONOMY_FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the design document has the economy table markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderEconomyBlock(), "the economy table equals the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceEconomy(document), document, "regenerating the economy table changes nothing")

    local function near(a, b) return math.abs(a - b) < 1e-6 end

    -- 9mm by hand: six ingots of brass and five ore of copper for bullets.
    local nine = BALANCE.economy(AC_Calibres.get("9mm"), 100)
    eq(nine.brassIngots, 6, "9mm: six brass ingots per hundred")
    check(near(nine.copperOre, 9.2) and near(nine.zincOre, 1.8), "9mm: 9.2 copper ore and 1.8 zinc ore")
    check(near(nine.ore, 11), "9mm: eleven ore in all")
    eq(nine.copperScrap, 50, "9mm: fifty copper scrap for bullets")
    eq(nine.caseCups, 100, "9mm: a hundred cups")
    eq(nine.powderJars, 10, "9mm: ten jars of powder")
    eq(nine.fertilizerUses, 20, "9mm: twenty uses of fertilizer")
    eq(nine.toyCaps, 100, "9mm: a hundred toy caps")
    eq(nine.matchUses, 200, "9mm: or two hundred match uses")
    check(near(nine.charcoal, 102), "9mm: 102 charcoal (" .. nine.charcoal .. ")")
    check(near(nine.totalXP, 55 + 5.4 + 30 + 15 + 30 + 50 + 20 + 10 + 100 + 50 + 50 + 200 + 11 / 9 * 3), "9mm: the XP is the sum of every step (" .. nine.totalXP .. ")")

    -- The arithmetic agrees with a mirror-inventory run of the real
    -- recipes, from brass ingots on, for every canonical calibre.
    local economies = {}
    for _, id in ipairs(BALANCE.ECONOMY_CALIBRES) do
        local calibre = AC_Calibres.get(id)
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        local e = BALANCE.economy(calibre, 100)
        economies[id] = e
        eq(e.brassIngots, math.floor(e.brassIngots), id .. ": a whole number of brass ingots per hundred")
        local inv = {
            ["Base.BrassIngot"] = e.brassIngots, ["Base.CopperScrap"] = e.copperScrap, ["Base.CapGunCap"] = e.toyCaps,
            ["Base.Fertilizer"] = e.fertilizerUses, ["base:charcoal"] = 100000, ["Base.SteelBarQuarter"] = 2,
            [AC_Calibres.WAD.items[1]] = e.wads,
            ["base:hammer"] = 1, ["base:tongs"] = 1, ["base:metalworkingpunch"] = 1, ["base:ballpeenhammer"] = 1,
            ["base:metalworkingpliers"] = 1, ["base:whetstone"] = 1, ["base:mortarpestle"] = 1,
        }
        local xp = 0
        local function run(recipe, n)
            for _ = 1, n do
                check(mirrorCraft(inv, recipe), id .. ": " .. recipe.id .. " runs")
                xp = xp + AC_Materials.getRecipeXP(recipe)
            end
        end
        run(R("AmmoMaking_ForgeSmallBrassSheets"), e.brassIngots)
        run(R("AmmoMaking_PunchBrassCaseCups"), e.cupSheets)
        run(primerRecipe(primer, "Caps"), e.primerSheets)
        run(calibreRecipe(calibre, "dieSet"), 1)
        run(calibreRecipe(calibre, "case"), 100)
        run(calibreRecipe(calibre, "bullet"), e.copperScrap)
        run(R("AmmoMaking_MixGunpowder"), e.powderJars)
        run(calibreRecipe(calibre, "assemble"), 100)
        eq(inv[calibre.round], 100, id .. ": the batch is a hundred rounds")
        for _, left in ipairs({ "Base.BrassIngot", "AmmoMaking.SmallBrassSheet", "AmmoMaking.BrassCaseCup", "Base.CopperScrap", "Base.CapGunCap", "Base.Fertilizer", "Base.GunPowder" }) do
            eq(inv[left], 0, id .. ": nothing left over of " .. left)
        end
        local x = e.xp
        check(near(xp, x.caseStock + x.primers + x.dieSet + x.cases + x.bullets + x.powder + x.assembly), id .. ": the XP from brass to round is what the recipes paid (" .. xp .. ")")
        eq(100000 - inv["base:charcoal"], e.brassIngots + e.powderJars * AC_Calibres.POWDER.charcoal + 2, id .. ": charcoal from brass to round")
        -- Metallurgy: ore in equals metal in the rounds.
        local units = AC_Materials.UNITS[calibre.round].contents
        check(near(e.ore * 100, 100 * (units.brass + units.copper)), id .. ": the ore is exactly the metal in the rounds")
        check(near(e.zincOre, 0.3 * e.brassIngots) and near(e.copperOre, 0.7 * e.brassIngots + e.copperScrap / 10), id .. ": seven parts copper to three of zinc, and the projectiles")
    end

    -- Outliers: no calibre is out of line with the others.
    local lowOre, highOre, lowRate, highRate = math.huge, 0, math.huge, 0
    for id, e in pairs(economies) do
        lowOre, highOre = math.min(lowOre, e.ore), math.max(highOre, e.ore)
        local rate = e.totalXP / e.ore
        lowRate, highRate = math.min(lowRate, rate), math.max(highRate, rate)
        check(e.ore >= 10 and e.ore <= 30, id .. ": a hundred rounds take between 10 and 30 ore (" .. e.ore .. ")")
        check(rate >= 45 and rate <= 80, id .. ": between 45 and 80 XP per ore (" .. rate .. ")")
        for part, amount in pairs(e.xp) do
            check(amount <= 0.5 * e.totalXP, id .. ": " .. part .. " is at most half of the batch's XP")
            check(amount > 0, id .. ": " .. part .. " pays something")
        end
        local calibre = AC_Calibres.get(id)
        eq(e.fertilizerUses, 20 * calibre.powderUses, id .. ": fertilizer follows the charge")
        check(e.fertilizerUses <= 100, id .. ": at most a hundred uses of fertilizer per hundred rounds")
        check(e.charcoal <= 350, id .. ": at most 350 charcoal per hundred rounds (" .. e.charcoal .. ")")
    end
    check(highOre / lowOre < 3, "the dearest calibre takes under three times the ore of the cheapest (" .. lowOre .. " to " .. highOre .. ")")
    check(highRate / lowRate < 1.6, "XP per ore differs by under 1.6 between calibres (" .. string.format("%.1f to %.1f", lowRate, highRate) .. ")")
    eq(#BALANCE.ECONOMY_CALIBRES, #AC_Calibres.LIST, "every calibre of the model is in the economy table")
    -- Pistol to rifle: more of everything, powder most of all.
    local rifle = economies[".308"]
    check(rifle.ore > nine.ore and rifle.ore / nine.ore < 3, ".308 takes more ore than 9mm, under three times")
    eq(rifle.fertilizerUses / nine.fertilizerUses, 5, ".308 takes five times the powder of 9mm")
    check(rifle.fertilizerUses / nine.fertilizerUses > rifle.ore / nine.ore, "powder, not metal, is the rifle's price")
    eq(economies["12 Gauge"].ore, rifle.ore, "a shell costs the metal of a .308")
    check(economies["12 Gauge"].powderJars < rifle.powderJars, "and less powder")
    eq(economies["12 Gauge"].wads, 100, "and a wad each")
    check(economies[".44 Magnum"].ore > economies[".45 ACP"].ore and economies[".45 ACP"].ore > nine.ore, "pistol calibres rise with the round: 9mm, .45, .44")

    -- The mixed loadout.
    local mix = BALANCE.economyMix()
    eq(mix.rounds, 350, "the mixed loadout is 350 rounds")
    check(near(mix.ore, 2 * nine.ore + rifle.ore + economies["12 Gauge"].ore / 2), "its ore is the sum of its parts (" .. mix.ore .. ")")
    check(near(mix.ore, 62.5), "62.5 ore")
    eq(mix.xp.dieSet, 30, "three die sets")
    check(mix.totalXP > 2775, "a first full kit of ammunition carries a character past level 5 (" .. string.format("%.0f", mix.totalXP) .. " XP)")
    check(mix.totalXP < 5775, "and not to level 6")
    print(string.format("  Economy: per 100 rounds %.0f to %.0f ore, %.0f to %.0f XP per ore; mixed loadout %.1f ore, %.0f charcoal, %.0f fertilizer uses, %.0f XP",
        lowOre, highOre, lowRate, highRate, mix.ore, mix.charcoal, mix.fertilizerUses, mix.totalXP))

    -- The loadouts: A is the mixed kit above, B, C and D one calibre in quantity.
    eq(#BALANCE.ECONOMY_LOADOUTS, 4, "four canonical loadouts")
    local loadouts = {}
    for _, loadout in ipairs(BALANCE.ECONOMY_LOADOUTS) do
        local e = BALANCE.economyOf(loadout.parts)
        loadouts[loadout.id] = e
        local rounds, ore = 0, 0
        for _, part in ipairs(loadout.parts) do
            rounds = rounds + part[2]
            ore = ore + BALANCE.economy(AC_Calibres.get(part[1]), part[2]).ore
        end
        eq(e.rounds, rounds, "loadout " .. loadout.id .. ": its rounds")
        check(near(e.ore, ore), "loadout " .. loadout.id .. ": its ore is the sum of its parts")
        check(e.totalXP / e.ore >= 45 and e.totalXP / e.ore <= 80, "loadout " .. loadout.id .. ": between 45 and 80 XP per ore")
    end
    check(near(loadouts.A.ore, mix.ore), "loadout A is the mixed loadout")
    check(near(loadouts.B.ore, 5 * nine.ore - 0), "loadout B: five hundred 9mm take five times the ore of a hundred")
    check(near(loadouts.C.ore, 2 * rifle.ore), "loadout C: two hundred .308")
    check(near(loadouts.D.ore, 2 * economies["12 Gauge"].ore), "loadout D: two hundred shells")
    -- A die set is forged once, however large the batch.
    eq(loadouts.B.xp.dieSet, nine.xp.dieSet, "a bigger batch forges no second die set")

    -- Work: crafts and station time, by hand and with the prepared press.
    -- The press touches three steps and nothing else, so it can save at
    -- most its share of those steps, and it never changes a count or XP.
    local P = AC_Calibres.PRESS
    local leastSaved, mostSaved = math.huge, 0
    for id, e in pairs(economies) do
        local calibre = AC_Calibres.get(id)
        eq(e.work.cases[1], 100, id .. ": a hundred cases formed")
        eq(e.work.assembly[1], 100, id .. ": a hundred rounds assembled")
        eq(e.work.bullets[1], 100 / calibre.bulletsPerScrap, id .. ": projectile crafts follow bullets per scrap")
        eq(e.work.dieSet[1], 1, id .. ": one die set")
        check(near(e.crafts, e.hotCrafts + e.benchCrafts), id .. ": every craft is at a fire or at a surface")
        local byHand, pressed = 0, 0
        for _, step in ipairs({ "case", "bullet", "assemble" }) do
            local hand = calibreRecipe(calibre, step)
            local count = ({ case = e.work.cases[1], bullet = e.work.bullets[1], assemble = e.work.assembly[1] })[step]
            byHand = byHand + count * hand.time
            pressed = pressed + count * math.floor(hand.time * P.timePercent / 100)
        end
        check(near(e.pressableTime, byHand), id .. ": the time the press can shorten is the three die-set steps")
        check(near(e.handTime - e.pressTime, byHand - pressed), id .. ": the press saves exactly its share of those steps")
        check(e.pressTime < e.handTime, id .. ": the press saves time")
        local saved = (e.handTime - e.pressTime) / e.handTime
        leastSaved, mostSaved = math.min(leastSaved, saved), math.max(mostSaved, saved)
        -- No step is counted that is not a recipe: the time by hand is the
        -- sum over the mirror recipes of crafts times time.
        check(e.handTime > e.pressableTime, id .. ": most of the work is not at the press")
    end
    -- The press is a convenience: it cannot halve a batch's work, because
    -- furnace, forge, primers and powder are untouched.
    check(mostSaved < (100 - P.timePercent) / 100, "the press saves less than its nominal " .. (100 - P.timePercent) .. " % of any whole batch (" .. string.format("%.1f %%", mostSaved * 100) .. ")")
    check(leastSaved > 0.10, "and more than a tenth of every batch (" .. string.format("%.1f %%", leastSaved * 100) .. ")")
    check(mostSaved / leastSaved < 1.6, "no calibre gains much more from the press than another")
    print(string.format("  Economy: the press saves %.0f %% to %.0f %% of a batch's station time; loadouts A-D take %.1f, %.0f, %.0f and %.0f ore",
        leastSaved * 100, mostSaved * 100, loadouts.A.ore, loadouts.B.ore, loadouts.C.ore, loadouts.D.ore))

    -- Powder: taking rounds apart never pays.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(calibre.powderUses >= 1, calibre.id .. ": the charge is at least the one use vanilla gives back")
    end
    -- The table follows the model.
    local rendered = BALANCE.renderEconomy()
    local saved = AC_Calibres.POWDER.fertilizerUses
    AC_Calibres.POWDER.fertilizerUses = 3
    check(BALANCE.renderEconomy() ~= rendered, "a changed powder recipe changes the rendered economy table")
    AC_Calibres.POWDER.fertilizerUses = saved
    eq(BALANCE.renderEconomy(), rendered, "and restoring it restores the table")
end

section("Complete chain for every calibre: 100 rounds, exactly accounted")
do
    local U = AC_Materials.UNITS
    local R = AC_Materials.getRecipe
    local tools = {
        "base:hammer", "base:tongs", "base:metalworkingpunch", "base:ballpeenhammer",
        "base:metalworkingpliers", "base:whetstone", "base:mortarpestle",
    }
    local function times(inventory, recipe, n, what)
        local done = 0
        for _ = 1, n do
            if mirrorCraft(inventory, recipe) then done = done + 1 end
        end
        eq(done, n, what .. " x" .. n)
    end

    eq(U["Base.GunPowder"].uses, 10, "a jar of gunpowder is 10 uses")

    for _, calibre in ipairs(AC_Calibres.LIST) do
        local name = calibre.id
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        local rounds = 100

        -- Requirements derived from the definition, all whole numbers.
        local primerSheets = rounds / primer.perSheet
        local cups = rounds * calibre.cupsPerCase
        local cupSheets = cups / 2
        local ingots = (primerSheets + cupSheets) / 10
        local scrap = rounds / calibre.bulletsPerScrap
        local mixes = rounds * calibre.powderUses / AC_Calibres.POWDER.usesPerJar
        for label, value in pairs({ primerSheets = primerSheets, cupSheets = cupSheets, ingots = ingots, scrap = scrap, mixes = mixes }) do
            eq(value, math.floor(value), name .. ": " .. label .. " is a whole number for 100 rounds")
        end
        local caps = primerSheets * primer.perSheet * primer.compoundUnits / 2
        local charcoal = ingots + 2 + mixes * AC_Calibres.POWDER.charcoal

        local inv = {
            ["Base.BrassIngot"] = ingots,
            ["Base.CopperScrap"] = scrap,
            ["Base.CapGunCap"] = caps,
            ["Base.Fertilizer"] = mixes * AC_Calibres.POWDER.fertilizerUses,
            ["base:charcoal"] = charcoal,
            ["Base.SteelBarQuarter"] = 2,
            [AC_Calibres.WAD.items[1]] = rounds * calibre.wads,
        }
        for _, tool in ipairs(tools) do inv[tool] = 1 end

        times(inv, R("AmmoMaking_ForgeSmallBrassSheets"), ingots, name .. " forge sheets")
        times(inv, R("AmmoMaking_PunchBrassCaseCups"), cupSheets, name .. " punch cups")
        times(inv, primerRecipe(primer, "Caps"), primerSheets, name .. " make primers")
        times(inv, calibreRecipe(calibre, "dieSet"), 1, name .. " forge die set")
        times(inv, calibreRecipe(calibre, "case"), rounds, name .. " form case")
        times(inv, calibreRecipe(calibre, "bullet"), scrap, name .. " swage bullets")
        times(inv, R("AmmoMaking_MixGunpowder"), mixes, name .. " mix powder")
        eq(inv["Base.GunPowder"], rounds * calibre.powderUses, name .. ": powder for every charge")
        eq(inv[calibre.case], rounds, name .. ": 100 cases")
        eq(inv[calibre.bullet], rounds, name .. ": 100 bullets")
        eq(inv[primer.item], rounds, name .. ": 100 primers")
        times(inv, calibreRecipe(calibre, "assemble"), rounds, name .. " assemble")
        eq(inv[calibre.round], rounds, name .. ": 100 vanilla rounds")
        check(not mirrorCraft(inv, calibreRecipe(calibre, "assemble")), name .. ": no 101st round")

        for _, id in ipairs({ "Base.BrassIngot", "AmmoMaking.SmallBrassSheet", "AmmoMaking.BrassCaseCup", "Base.CopperScrap",
                              "Base.CapGunCap", "Base.Fertilizer", "base:charcoal", "Base.SteelBarQuarter",
                              calibre.case, calibre.bullet, primer.item, "Base.GunPowder", AC_Calibres.WAD.items[1] }) do
            eq(inv[id], 0, name .. ": nothing left over: " .. id)
        end
        for _, tool in ipairs(tools) do eq(inv[tool], 1, name .. ": tool kept: " .. tool) end
        eq(inv[calibre.dieSet], 1, name .. ": the die set is made once and kept")

        -- Nothing of any other calibre or primer family appeared.
        for _, other in ipairs(AC_Calibres.LIST) do
            if other ~= calibre then
                eq(inv[other.round], nil, name .. ": no " .. other.id .. " round appeared")
                eq(inv[other.case], nil, name .. ": no " .. other.id .. " case appeared")
            end
        end
        for _, otherPrimer in ipairs(AC_Calibres.PRIMERS) do
            if otherPrimer ~= primer then eq(inv[otherPrimer.item], nil, name .. ": no " .. otherPrimer.id .. " primer appeared") end
        end

        -- The rounds hold exactly the material that was put in.
        local round = U[calibre.round].contents
        eq(rounds * round.brass, ingots * AC_Materials.CONFIG.unitsPerIngot, name .. ": brass in the rounds equals the ingots")
        eq(rounds * round.copper, scrap * U["Base.CopperScrap"].units, name .. ": copper in the rounds equals the scrap")
        eq(rounds * round.compound, caps * U["Base.CapGunCap"].units, name .. ": compound in the rounds equals the caps")
        eq(rounds * round.powder, mixes * AC_Calibres.POWDER.usesPerJar, name .. ": powder in the rounds equals the jars")

        -- Batch arithmetic: k crafts are k times one craft, tools once.
        for _, step in ipairs({ "case", "bullet", "assemble" }) do
            local recipe = calibreRecipe(calibre, step)
            local k = 7
            local stock, expected = {}, {}
            for _, input in ipairs(recipe.inputs) do
                local id = input.items and input.items[1] or input.tags[1]
                stock[id] = input.keep and 1 or input.count * k
                expected[id] = input.keep and 1 or 0
            end
            times(stock, recipe, k, name .. " " .. step .. " batch")
            check(not mirrorCraft(stock, recipe), name .. " " .. step .. ": no craft beyond the batch")
            for id, left in pairs(expected) do eq(stock[id], left, name .. " " .. step .. " batch leaves " .. id) end
            eq(stock[recipe.outputs[1].item], k * recipe.outputs[1].count, name .. " " .. step .. " batch output is k times one craft")
        end

        -- Each recipe refuses to run with any one input missing.
        for _, recipe in ipairs(AC_Calibres.buildCalibreRecipes(calibre)) do
            for index in ipairs(recipe.inputs) do
                local stock = {}
                for other, otherInput in ipairs(recipe.inputs) do
                    if other ~= index then
                        stock[otherInput.items and otherInput.items[1] or otherInput.tags[1]] = otherInput.count
                    end
                end
                check(not mirrorCraft(stock, recipe), recipe.id .. " cannot run without input " .. index)
            end
        end

        -- Mutations the conservation check must catch, for this calibre.
        local assemble = calibreRecipe(calibre, "assemble")
        local function variant(change)
            local copy = {}
            for k, v in pairs(assemble) do copy[k] = v end
            for k, v in pairs(change) do copy[k] = v end
            copy.id = assemble.id .. "_tampered"
            return copy
        end
        local function without(index)
            local inputs = {}
            for i, input in ipairs(assemble.inputs) do
                if i ~= index then table.insert(inputs, input) end
            end
            return inputs
        end
        check(AC_Materials.checkConservation(assemble), name .. ": the real assembly conserves every material")
        check(not AC_Materials.checkConservation(variant({ outputs = { { count = 2, item = calibre.round } } })), name .. ": two rounds from one set of components is rejected")
        check(not AC_Materials.checkConservation(variant({ inputs = without(1) })), name .. ": a round without a case is rejected")
        check(not AC_Materials.checkConservation(variant({ inputs = without(2) })), name .. ": a round without a primer is rejected")
        check(not AC_Materials.checkConservation(variant({ inputs = without(3) })), name .. ": a round without a bullet is rejected")
        check(not AC_Materials.checkConservation(variant({ inputs = without(4) })), name .. ": a round without powder is rejected")
        check(AC_Materials.checkConservation(variant({ inputs = without(5) })), name .. ": the die set carries no material")
        if calibre.wads > 0 then
            -- The wad is not a tracked material: leaving it out is caught by
            -- the model validator and by the recipe needing it, not here.
            check(AC_Materials.checkConservation(variant({ inputs = without(6) })), name .. ": the wad carries no tracked material")
            local stock = {}
            for index, input in ipairs(assemble.inputs) do
                if index ~= 6 then stock[input.items[1]] = input.count end
            end
            check(not mirrorCraft(stock, assemble), name .. ": no shell without a wad")
        end
        if calibre.powderUses > 1 then
            local short = {}
            for i, input in ipairs(assemble.inputs) do short[i] = input end
            short[4] = { count = calibre.powderUses - 1, items = assemble.inputs[4].items }
            check(not AC_Materials.checkConservation(variant({ inputs = short })), name .. ": one charge less than the definition is rejected")
        end
        -- A primer of another family cannot pay for this round's primer,
        -- unless it holds at least as much of everything (then it is only
        -- kept out by the recipe naming its own family, tested above).
        for _, otherPrimer in ipairs(AC_Calibres.PRIMERS) do
            if otherPrimer.brassUnits < primer.brassUnits or otherPrimer.compoundUnits < primer.compoundUnits then
                local swapped = {}
                for i, input in ipairs(assemble.inputs) do swapped[i] = input end
                swapped[2] = { count = 1, items = { otherPrimer.item } }
                check(not AC_Materials.checkConservation(variant({ inputs = swapped })), name .. ": a " .. otherPrimer.id .. " primer does not pay for its primer")
            end
        end
        -- A smaller calibre's components cannot pay for this round.
        for _, other in ipairs(AC_Calibres.LIST) do
            local otherRound = U[other.round].contents
            local cheaper = otherRound.brass < round.brass or otherRound.copper < round.copper or otherRound.powder < round.powder or otherRound.compound < round.compound
            if cheaper then
                local swapped = variant({ inputs = calibreRecipe(other, "assemble").inputs })
                check(not AC_Materials.checkConservation(swapped), name .. ": a round built from " .. other.id .. " components is rejected")
            end
        end
        local swage = calibreRecipe(calibre, "bullet")
        check(not AC_Materials.checkConservation({ id = "more_bullets", inputs = swage.inputs, outputs = { { count = calibre.bulletsPerScrap + 1, item = calibre.bullet } } }), name .. ": an extra bullet from one scrap is rejected")
        local form = calibreRecipe(calibre, "case")
        check(not AC_Materials.checkConservation({ id = "more_cases", inputs = form.inputs, outputs = { { count = 2, item = calibre.case } } }), name .. ": a second case from the same cups is rejected")
        if calibre.cupsPerCase > 1 then
            check(not AC_Materials.checkConservation({ id = "thin_case", inputs = { { count = 1, items = { "AmmoMaking.BrassCaseCup" } } }, outputs = form.outputs }), name .. ": a case from too few cups is rejected")
        end
    end

    -- Sources and the powder loop.
    local sources = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        if recipe.source then table.insert(sources, recipe.id .. ":" .. recipe.source) end
    end
    eq(table.concat(sources, ","), "AmmoMaking_MixGunpowder:powder", "gunpowder mixing is the only source recipe")
    local mix = R("AmmoMaking_MixGunpowder")
    check(AC_Materials.checkConservation(mix), "gunpowder mixing is a declared source")
    check(not AC_Materials.checkConservation({ id = "free_powder", source = "powder", inputs = { mix.inputs[3] }, outputs = mix.outputs }), "powder from a kept tool alone is rejected")
    check(not AC_Materials.checkConservation({ id = "undeclared", inputs = mix.inputs, outputs = mix.outputs }), "an undeclared source is rejected")
    check(not AC_Materials.checkConservation({ id = "powder_to_brass", source = "powder", inputs = mix.inputs, outputs = { { count = 1, item = "Base.BrassIngot" } } }), "a source recipe may only create its own material")
    for _, vanilla in ipairs(AC_Materials.VANILLA_RECIPES) do
        if string.sub(vanilla.id, 1, 15) == "GatherGunpowder" then
            local consumed, created = AC_Materials.getRecipeUnits(vanilla)
            eq(created.powder, 1, vanilla.id .. " returns one use")
            check(created.powder <= consumed.powder, vanilla.id .. " never creates powder")
            eq(created.brass, nil, vanilla.id .. " returns no brass")
            check(not AC_Materials.checkConservation({ id = "gather_jar", inputs = vanilla.inputs, outputs = { { count = 1, item = "Base.GunPowder" } } }), vanilla.id .. ": a full jar from one round would be caught")
        end
    end

    -- A net-new loop: no mod recipe needs finished ammunition.
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        for _, input in ipairs(recipe.inputs) do
            for _, id in ipairs(input.items or {}) do
                check(AC_Calibres.identify(id) ~= "round", recipe.id .. " does not consume finished ammunition")
            end
            for _, tag in ipairs(input.tags or {}) do
                check(tag ~= "base:ammo", recipe.id .. " does not consume ammunition by tag")
            end
        end
    end

    -- From ore: one ten-ore brass batch and five copper ore, every recipe
    -- of the chain in order, through to 9mm rounds. Metal in equals metal
    -- in the rounds plus what is still in stock.
    local nine = AC_Calibres.get("9mm")
    local inv = {
        ["Base.CopperOre"] = 12, ["AmmoMaking.ZincOre"] = 3, ["base:charcoal"] = 1000, ["Base.Fertilizer"] = 1000,
        ["Base.CapGunCap"] = 1000, ["Base.SteelBarQuarter"] = 2, ["Base.CeramicCrucible"] = 1, ["base:crudetongs"] = 1, ["Base.ClayIngotMold"] = 1,
    }
    for _, tool in ipairs(tools) do inv[tool] = 1 end
    local function metal(inventory)
        local sum = 0
        for id, count in pairs(inventory) do
            local entry = U[id]
            if entry then
                for material, units in pairs(entry.contents or { [entry.metal] = entry.units }) do
                    if material == "copper" or material == "zinc" or material == "brass" then sum = sum + units * count end
                end
            end
        end
        return sum
    end
    local startMetal = metal(inv)
    eq(startMetal, 15 * AC_Materials.CONFIG.unitsPerIngot, "fifteen ore is fifteen ingots of metal")
    times(inv, AC_Materials.VANILLA_RECIPES[1], 12, "ore chain: smelt copper")
    times(inv, R("AmmoMaking_SmeltZincOre"), 3, "ore chain: smelt zinc")
    times(inv, R("AmmoMaking_CastCopperIngot"), 7, "ore chain: cast copper")
    times(inv, R("AmmoMaking_CastZincIngot"), 3, "ore chain: cast zinc")
    times(inv, R("AmmoMaking_CastBrassIngots"), 1, "ore chain: brass")
    times(inv, R("AmmoMaking_ForgeSmallBrassSheets"), 6, "ore chain: sheets")
    times(inv, R("AmmoMaking_PunchBrassCaseCups"), 50, "ore chain: cups")
    times(inv, primerRecipe(AC_Calibres.getPrimer(nine.primerFamily), "Caps"), 10, "ore chain: primers")
    times(inv, calibreRecipe(nine, "dieSet"), 1, "ore chain: die set")
    times(inv, calibreRecipe(nine, "case"), 100, "ore chain: cases")
    times(inv, calibreRecipe(nine, "bullet"), 50, "ore chain: bullets")
    times(inv, R("AmmoMaking_MixGunpowder"), 10, "ore chain: powder")
    times(inv, calibreRecipe(nine, "assemble"), 100, "ore chain: rounds")
    eq(inv[nine.round], 100, "fifteen ore: 100 rounds of 9mm")
    eq(inv["Base.BrassIngot"], 4, "and four brass ingots to spare")
    eq(metal(inv), startMetal, "not one unit of metal was created or lost from ore to round")
end

section("Whole-chain random crafting: thousands of valid crafts, one ledger per material")
do
    -- Every mod recipe and every modelled vanilla recipe, crafted in random
    -- order from ore to finished rounds. At each step one of the recipes
    -- that CAN run is picked, so the run goes deep instead of failing most
    -- draws. After every craft, each material is compared with the step
    -- before: nothing may appear that the craft's own definition does not
    -- account for. This executes the mirror table, not the game.
    local U = AC_Materials.UNITS
    local all = {}
    for _, r in ipairs(AC_Materials.RECIPES) do table.insert(all, r) end
    for _, r in ipairs(AC_Materials.VANILLA_RECIPES) do table.insert(all, r) end
    local brassRecipe = AC_Materials.getRecipe("AmmoMaking_CastBrassIngots")
    local mix = AC_Materials.getRecipe("AmmoMaking_MixGunpowder")
    local MATERIALS = { "copper", "zinc", "brass", "compound", "powder" }

    local function ledger(inventory)
        local totals = { copper = 0, zinc = 0, brass = 0, compound = 0, powder = 0 }
        for id, count in pairs(inventory) do
            local entry = U[id]
            if entry then
                for material, units in pairs(entry.contents or { [entry.metal] = entry.units }) do
                    totals[material] = totals[material] + units * count
                end
            end
        end
        return totals
    end
    local canCraft = mirrorCanCraft

    local totalCrafts, totalRounds, classesSeen, calibresSeen = 0, 0, {}, {}
    -- How often each recipe ran, over every seed.
    local ran = {}
    local SEEDS = { 1, 20261002, 987654321, 42, 7, 31337, 1993, 4220420 }
    local violations = {}
    local function violation(text)
        if #violations < 5 then table.insert(violations, text) end
    end

    for _, startSeed in ipairs(SEEDS) do
        local seed = startSeed
        local function nextRandom(n)
            seed = (seed * 1103515245 + 12345) % 2147483648
            return (math.floor(seed / 65536) % n) + 1
        end
        local inv = {
            ["Base.CopperOre"] = 300, ["AmmoMaking.ZincOre"] = 60,
            -- A few hulls somebody formed and no longer wants: ten three-cup
            -- cases rarely pile up by chance, and their scrapping recipe
            -- should run too.
            ["AmmoMaking.Hull12Gauge"] = 30,
            ["base:charcoal"] = 50000, ["Base.Fertilizer"] = 2000, ["Base.CapGunCap"] = 20000, ["Base.Matches"] = 2000,
            ["Base.SteelBarQuarter"] = 2 * #AC_Calibres.LIST, [AC_Calibres.WAD.items[1]] = 2000,
            ["Base.CeramicCrucible"] = 1, ["base:crudetongs"] = 1, ["Base.ClayIngotMold"] = 1,
            ["base:hammer"] = 1, ["base:tongs"] = 1, ["base:metalworkingpunch"] = 1, ["base:ballpeenhammer"] = 1,
            ["base:metalworkingpliers"] = 1, ["base:whetstone"] = 1, ["base:mortarpestle"] = 1, ["base:pliers"] = 1,
        }
        local tools = {}
        for id, count in pairs(inv) do
            if string.sub(id, 1, 5) == "base:" and id ~= "base:charcoal" then tools[id] = count end
        end
        tools["Base.CeramicCrucible"], tools["Base.ClayIngotMold"] = 1, 1

        local before = ledger(inv)
        local start = before
        local xp, expectedXP, crafts, assembled = 0, 0, 0, 0
        for _ = 1, 6000 do
            local able = {}
            for _, recipe in ipairs(all) do
                if canCraft(inv, recipe) then table.insert(able, recipe) end
            end
            if #able == 0 then break end
            local recipe = able[nextRandom(#able)]
            local dieSetsBefore = 0
            for _, calibre in ipairs(AC_Calibres.LIST) do dieSetsBefore = dieSetsBefore + (inv[calibre.dieSet] or 0) end
            check(mirrorCraft(inv, recipe), "a craftable recipe crafts")
            crafts = crafts + 1
            ran[recipe.id] = (ran[recipe.id] or 0) + 1
            xp = xp + AC_Materials.getRecipeXP(recipe)
            if recipe.step == "assemble" then
                local calibre = AC_Calibres.get(recipe.calibre)
                assembled = assembled + 1
                classesSeen[calibre.class] = true
                calibresSeen[calibre.id] = true
            end
            expectedXP = expectedXP + (tonumber(recipe.xp) or tonumber(AC_Materials.CONFIG[recipe.xpKey]) or 0)

            local now = ledger(inv)
            local what = recipe.id .. " (seed " .. startSeed .. ", craft " .. crafts .. ")"
            -- Copper, zinc and priming compound are never created by anything.
            for _, material in ipairs({ "copper", "zinc", "compound" }) do
                if now[material] > before[material] then violation(what .. " created " .. material) end
            end
            -- Brass appears only in the alloy recipe, and then exactly as much
            -- as the copper and zinc that went in.
            if recipe == brassRecipe then
                if now.brass - before.brass ~= (before.copper - now.copper) + (before.zinc - now.zinc) then violation(what .. " alloy is not exact") end
            elseif now.brass > before.brass then
                violation(what .. " created brass")
            end
            -- Metal as a whole never grows.
            if now.copper + now.zinc + now.brass > before.copper + before.zinc + before.brass then violation(what .. " created metal") end
            -- Scrapping loses exactly half of the brass it takes, and no
            -- recycling craft earns anything.
            if recipe.loss then
                local taken = AC_Materials.getRecipeUnits(recipe).brass
                if before.brass - now.brass ~= taken / 2 then violation(what .. " did not lose half of its brass") end
            end
            if recipe.recycling and AC_Materials.getRecipeXP(recipe) ~= 0 then violation(what .. " earned XP") end
            -- Powder appears only in the mix, one jar at a time.
            if recipe == mix then
                if now.powder - before.powder ~= AC_Calibres.POWDER.usesPerJar then violation(what .. " mixed another amount than a jar") end
            elseif now.powder > before.powder then
                violation(what .. " created powder")
            end
            -- Kept tools are all still there; a die set is never lost.
            for id, count in pairs(tools) do
                if inv[id] ~= count then violation(what .. " changed the tool " .. id) end
            end
            local dieSetsNow = 0
            for _, calibre in ipairs(AC_Calibres.LIST) do dieSetsNow = dieSetsNow + (inv[calibre.dieSet] or 0) end
            if dieSetsNow < dieSetsBefore then violation(what .. " consumed a die set") end
            -- Nothing goes negative, and nothing is fractional.
            for id, count in pairs(inv) do
                if count < 0 or count ~= math.floor(count) then violation(what .. " left " .. tostring(count) .. " of " .. id) end
            end
            before = now
        end

        check(crafts >= 3000, "seed " .. startSeed .. ": thousands of valid crafts ran (" .. crafts .. ")")
        eq(xp, expectedXP, "seed " .. startSeed .. ": XP is exactly the sum of one grant per craft")
        local finish = ledger(inv)
        for _, material in ipairs({ "copper", "zinc", "compound" }) do
            check(finish[material] <= start[material], "seed " .. startSeed .. ": no more " .. material .. " at the end than at the start")
        end
        check(finish.copper + finish.zinc + finish.brass <= start.copper + start.zinc + start.brass, "seed " .. startSeed .. ": no more metal at the end than at the start")
        -- Rounds are counted as they are assembled: vanilla's Gather
        -- Gunpowder is one of the recipes drawn, and takes them apart again.
        check(assembled > 0, "seed " .. startSeed .. ": the run reached finished ammunition (" .. assembled .. " rounds assembled)")
        totalCrafts = totalCrafts + crafts
        totalRounds = totalRounds + assembled
    end

    eq(#violations, 0, "no craft broke a material ledger: " .. table.concat(violations, "; "))
    for _, class in ipairs({ "pistol", "rifle", "shotgun" }) do
        check(classesSeen[class], "the random runs assembled " .. class .. " ammunition")
    end
    local reached = 0
    for _ in pairs(calibresSeen) do reached = reached + 1 end
    eq(reached, #AC_Calibres.LIST, "every calibre was assembled in some run")
    -- Every stage of the chain was exercised: metallurgy, case stock,
    -- powder, every primer family, the shell, and recycling.
    local neverRan = {}
    for _, recipe in ipairs(all) do
        if not ran[recipe.id] then table.insert(neverRan, recipe.id) end
    end
    eq(#neverRan, 0, "every recipe ran at least once: " .. table.concat(neverRan, ", "))
    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        local made = 0
        for _, source in ipairs(AC_Calibres.COMPOUND_SOURCES) do made = made + (ran[primerRecipe(primer, source.id).id] or 0) end
        check(made > 0, primer.id .. " primers were made (" .. made .. " crafts)")
    end
    local recycled = 0
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        if recipe.recycling then recycled = recycled + (ran[recipe.id] or 0) end
    end
    check(recycled > 100, "recycling was exercised (" .. recycled .. " crafts)")
    check((ran["AmmoMaking_CastBrassIngotFromScrap"] or 0) > 0, "scrap was cast back into ingots (" .. tostring(ran["AmmoMaking_CastBrassIngotFromScrap"]) .. " crafts)")
    check((ran["AmmoMaking_MixGunpowder"] or 0) > 0 and (ran["AmmoMaking_CastBrassIngots"] or 0) > 0, "powder was mixed and brass was cast")
    print("  Random crafting: " .. totalCrafts .. " valid crafts over " .. #SEEDS .. " seeds, " .. totalRounds .. " rounds assembled, " .. reached .. " of " .. #AC_Calibres.LIST .. " calibres reached, " .. recycled .. " recycling crafts, 0 ledger violations")

    -- The ledger itself must be able to fail: a tampered recipe is caught by
    -- the same comparison.
    local function tamperedRun(change)
        local inv = { ["AmmoMaking.BrassCaseCup"] = 10, ["Base.CopperScrap"] = 10, ["base:hammer"] = 1 }
        local nine = AC_Calibres.get("9mm")
        inv[nine.dieSet] = 1
        local recipe = {}
        for k, v in pairs(calibreRecipe(nine, change.step)) do recipe[k] = v end
        recipe.outputs = change.outputs(nine)
        local before = ledger(inv)
        mirrorCraft(inv, recipe)
        local now = ledger(inv)
        return now[change.material] > before[change.material]
    end
    check(tamperedRun({ step = "case", material = "brass", outputs = function(c) return { { count = 2, item = c.case } } end }), "the ledger sees brass created by a doubled case output")
    check(tamperedRun({ step = "bullet", material = "copper", outputs = function(c) return { { count = 3, item = c.bullet } } end }), "the ledger sees copper created by a third bullet")
    check(not tamperedRun({ step = "case", material = "brass", outputs = function(c) return { { count = 1, item = c.case } } end }), "and sees nothing for the real recipe")
end

section("Ammunition component debug tools")
do
    MOCK.debug = true
    local nine = AC_Calibres.get("9mm")
    local player = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, GRASS) })

    -- Each calibre's kit covers five rounds of that calibre.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local kitPlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 6, 0, GRASS) })
        MOCK.capturePrint(true)
        AC_GeologyDebug.spawnComponentsKit(kitPlayer, calibre)
        MOCK.capturePrint(false)
        local inv = kitPlayer.inventory
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        eq(inv:count(calibre.dieSet), 1, calibre.id .. " kit: die set")
        eq(inv:count("Base.Hammer"), 1, calibre.id .. " kit: hammer")
        eq(inv:count("AmmoMaking.BrassCaseCup"), 5 * calibre.cupsPerCase, calibre.id .. " kit: cups for five cases")
        check(inv:count("Base.CopperScrap") * calibre.bulletsPerScrap >= 5, calibre.id .. " kit: copper for five bullets")
        eq(inv:count(primer.item), 5, calibre.id .. " kit: five primers of its family")
        check(inv:count("Base.GunPowder") * 10 >= 5 * calibre.powderUses, calibre.id .. " kit: powder for five charges")
        eq(inv:count(calibre.round), 0, calibre.id .. " kit: no finished ammunition")
        eq(inv:count(AC_Calibres.WAD.items[1]), 5 * calibre.wads, calibre.id .. " kit: wadding for five rounds, if it takes any")
        for _, otherPrimer in ipairs(AC_Calibres.PRIMERS) do
            if otherPrimer ~= primer then eq(inv:count(otherPrimer.item), 0, calibre.id .. " kit: no primer of the other family") end
        end
    end

    local chem = MOCK.newPlayer({ square = MOCK.newSquare(8, 5, 0, GRASS) })
    MOCK.capturePrint(true)
    AC_GeologyDebug.spawnPrimerPowderKit(chem)
    MOCK.capturePrint(false)
    eq(chem.inventory:count("Base.CapGunCap"), 10, "toy caps for one primer batch")
    eq(chem.inventory:count("Base.Matchbox"), 1, "matches for the other primer recipe")
    eq(chem.inventory:count("AmmoMaking.SmallBrassSheet"), 2, "a sheet for each primer recipe")
    eq(chem.inventory:count("Base.Charcoal"), 2, "charcoal for one powder mix")
    eq(chem.inventory:count("Base.Fertilizer"), 1, "fertilizer")
    eq(chem.inventory:count("Base.MortarPestle"), 1, "mortar and pestle")
    eq(chem.inventory:count("Base.GunPowder"), 0, "no ready powder in the raw-material kit")

    -- The calibre kits sit in a submenu, one entry per calibre.
    local ctx = fillWorldMenu(player, player.square)
    local root = ctx:find("Ammo Making Debug")
    local ammunition = root.submenu:find("Ammunition")
    check(ammunition ~= nil and ammunition.submenu ~= nil, "ammunition tools are a submenu")
    local kits = ammunition.submenu:find("Spawn Calibre Kit")
    check(kits ~= nil and kits.submenu ~= nil, "calibre kits are a submenu")
    eq(#kits.submenu.options, #AC_Calibres.LIST, "one kit entry per calibre")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(kits.submenu:find(calibre.id) ~= nil, "kit entry for " .. calibre.id)
    end

    -- Inspector: lists cases and rounds with their stored quality.
    local inv = player.inventory
    local good = MOCK.newItem(nine.case)
    AC_CaseQuality.set(good, 84)
    inv:addItem(good)
    inv:addItem(MOCK.newItem(nine.case))
    local loaded = MOCK.newItem(nine.round)
    loaded.modData.casingQuality = 66
    inv:addItem(loaded)
    local magnum = AC_Calibres.get(".44 Magnum")
    local big = MOCK.newItem(magnum.case)
    AC_CaseQuality.set(big, 91)
    inv:addItem(big)
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local ok = pcall(AC_GeologyDebug.inspectAmmoComponents, player)
    MOCK.capturePrint(false)
    check(ok, "component inspector runs")
    check(MOCK.printLogContains(nine.case .. " (9mm case): quality 84 (Very Good)"), "case quality listed with its label")
    check(MOCK.printLogContains(nine.case .. " (9mm case): no stored quality"), "a case without quality is listed as such")
    check(MOCK.printLogContains(nine.round .. " (9mm round): quality 66 (Average)"), "handloaded round listed")
    check(MOCK.printLogContains(magnum.case .. " (.44 Magnum case): quality 91 (Excellent)"), "the calibre is named for each component")
    eq(AC_CaseQuality.get(good), 84, "the inspector changes nothing")
    check(pcall(AC_GeologyDebug.inspectAmmoComponents, nil), "inspector tolerates no player")

    -- Calibre definitions printout.
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    ok = pcall(AC_GeologyDebug.printCalibreDefinitions, player)
    MOCK.capturePrint(false)
    check(ok, "calibre printout runs")
    check(MOCK.printLogContains("CALIBRE DEFINITIONS (9)"), "printout header")
    check(MOCK.printLogContains("12 Gauge [shotgun] -> Base.ShotgunShells | case AmmoMaking.Hull12Gauge (3 cup) | bullet AmmoMaking.ShotCharge12Gauge (1 per scrap) | primer LargePistol (AmmoMaking.LargePistolPrimer) | powder 3 | wad 1 | die set AmmoMaking.DieSet12Gauge | levels die 2, case 2, bullet 3, round 4"), "printout line for the shell")
    check(MOCK.printLogContains(".308 [rifle] -> Base.308Bullets | case AmmoMaking.Case308Win (3 cup) | bullet AmmoMaking.Bullet308Win (1 per scrap) | primer LargeRifle (AmmoMaking.LargeRiflePrimer) | powder 5 | die set AmmoMaking.DieSet308Win | levels die 3, case 3, bullet 4, round 5"), "printout line for .308")
    check(MOCK.printLogContains(".44 Magnum [pistol] -> Base.Bullets44 | case AmmoMaking.Case44Magnum (2 cup) | bullet AmmoMaking.Bullet44Magnum (1 per scrap) | primer LargePistol (AmmoMaking.LargePistolPrimer) | powder 3 | die set AmmoMaking.DieSet44Magnum | levels die 3, case 3, bullet 4, round 5"), "printout line for .44 Magnum")
    check(not MOCK.printLogContains("WARNING"), "no model problem is printed for the live definitions")
    check(pcall(AC_GeologyDebug.printCalibreDefinitions, nil), "printout tolerates no player")

    -- Primer families printout: every family, and the rounds that take it.
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    ok = pcall(AC_GeologyDebug.printPrimerFamilies, player)
    MOCK.capturePrint(false)
    check(ok, "primer printout runs")
    check(MOCK.printLogContains("PRIMER FAMILIES (4)"), "primer printout header")
    check(MOCK.printLogContains("LargePistol [pistol] AmmoMaking.LargePistolPrimer | brass 2, compound 4 | 5 per sheet | level 3 | rounds: .45 ACP, .44 Magnum, 12 Gauge"), "large pistol family line, with the shell")
    check(MOCK.printLogContains("SmallRifle [rifle] AmmoMaking.SmallRiflePrimer | brass 1, compound 3 | 10 per sheet | level 4 | rounds: 5.56"), "small rifle family line")
    check(pcall(AC_GeologyDebug.printPrimerFamilies, nil), "primer printout tolerates no player")

    -- Verify Ammo Dependencies: only the ammunition probes, concise.
    local recipeIds = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(recipeIds, recipe.id) end
    MOCK.resetCraftRecipes(recipeIds)
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    ok = pcall(AC_GeologyDebug.verifyAmmoDependencies, player)
    MOCK.capturePrint(false)
    check(ok, "ammo dependency check runs")
    check(MOCK.printLogContains("[AmmoMaking] Pistol calibres: 5/5 complete"), "pistol summary line")
    check(MOCK.printLogContains("[AmmoMaking] Rifle calibres: 3/3 complete"), "rifle summary line")
    check(MOCK.printLogContains("[AmmoMaking] Shotgun shells: 1/1 complete"), "shotgun summary line")
    check(MOCK.printLogContains("[AmmoMaking] Ammunition dependencies: "), "its own totals line")
    check(not MOCK.printLogContains("[AmmoMaking] OK: "), "no OK line per probe: the summary is concise")
    check(not MOCK.printLogContains("WARNING"), "and nothing to warn about")
    check(not MOCK.printLogContains("Compatibility check:"), "it is not the full compatibility check")
    eq(AC_Compat.hasRun, AC_Compat.hasRun, "it leaves the once-per-start flag alone")
    -- With a round missing, the detail appears and the class count drops.
    MOCK.knownScriptItems["Base.556Bullets"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    pcall(AC_GeologyDebug.verifyAmmoDependencies, player)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.556Bullets"] = true
    check(MOCK.printLogContains("WARNING: calibre 5.56 incomplete (missing Base.556Bullets; the other calibres are unaffected)"), "the missing dependency is detailed")
    check(MOCK.printLogContains("[AmmoMaking] Rifle calibres: 2/3 complete"), "and the rifle count drops")
    check(MOCK.printLogContains("[AmmoMaking] Pistol calibres: 5/5 complete"), "pistols are unaffected")
    check(pcall(AC_GeologyDebug.verifyAmmoDependencies, nil), "dependency check tolerates no player")

    -- Station recipe inspector shows the level of a gated recipe.
    local ids = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
    MOCK.resetCraftRecipes(ids)
    AC_Materials.applySkillRequirements()
    player.perkLevel = 5
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_GeologyDebug.inspectMetallurgyRecipes(player)
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("AmmoMaking_AssembleRound9mm [AnySurfaceCraft]: loaded, required skills 1; level 3; XP 2; expected time 36/40; metal conserved"), "assembly listed with its level and predicted time")
    check(MOCK.printLogContains("AmmoMaking_AssembleRound44Magnum [AnySurfaceCraft]: loaded, required skills 1; level 5; XP 4; expected time 40/40; metal conserved"), "the top calibre is listed at its level")
    check(not MOCK.printLogContains("NOT CONSERVED"), "every recipe is reported as conserving")
    MOCK.debug = false
end

------------------------------------------------
-- SAVE DATA
------------------------------------------------
--
-- Every key the mod persists, damaged in every way a save can be damaged,
-- then pushed through the code a player actually runs: menus, assays, the
-- analyzer, mining, inspection. Nothing may raise, and what comes back must
-- stay inside its documented range. This runs the mod's Lua against mocked
-- items and objects; that ModData survives a real save is the engine's.

-- The kinds of damage: missing, wrong type, negative, huge, not a number,
-- an unknown word, a fraction.
local NIL = {}
local DAMAGE = {
    { "missing", NIL }, { "true", true }, { "false", false }, { "an empty string", "" },
    { "a word", "excellent" }, { "a numeric string", "42" }, { "a negative number", -5 },
    { "zero", 0 }, { "900", 900 }, { "a huge number", 1e15 }, { "infinity", math.huge },
    { "minus infinity", -math.huge }, { "not-a-number", 0 / 0 }, { "a table", {} }, { "a fraction", 3.7 },
}

local function isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

section("Save data schema: every persisted key is declared, and the mod writes what it declares")
do
    local S = AC_SaveData

    -- Reading numbers.
    eq(S.isFinite(5), true, "5 is finite")
    eq(S.isFinite(0 / 0), false, "NaN is not")
    eq(S.isFinite(math.huge), false, "infinity is not")
    eq(S.isFinite(-math.huge), false, "minus infinity is not")
    eq(S.isFinite("5"), false, "a string is not a number")
    eq(S.isFinite(nil), false, "nil is not a number")
    eq(S.number(42, 0, 0, 100), 42, "a value in range is itself")
    eq(S.number("42", 0, 0, 100), 42, "a numeric string counts, as for tonumber")
    eq(S.number(900, 0, 0, 100), 100, "above the range: the maximum")
    eq(S.number(-5, 7, 0, 100), 0, "below the range: the minimum, not the default")
    eq(S.number("excellent", 7, 0, 100), 7, "a word: the default")
    eq(S.number(nil, 7, 0, 100), 7, "missing: the default")
    eq(S.number({}, 7, 0, 100), 7, "a table: the default")
    eq(S.number(true, 7, 0, 100), 7, "a boolean: the default")
    eq(S.number(0 / 0, 7, 0, 100), 7, "NaN: the default")
    eq(S.number(math.huge, 7, 0, 100), 7, "infinity: the default, not the maximum")
    eq(S.number(-math.huge, 7, 0, 100), 7, "minus infinity: the default")
    eq(S.number(1e15, 7, 0, 100), 100, "a huge finite number: the maximum")
    eq(S.number(12.5, 0), 12.5, "no range: the number")
    eq(S.number(-3, 0, nil, 10), -3, "no minimum")
    eq(S.number("x", nil), nil, "a nil default is returned as nil")
    eq(S.whole(3.7, 0, 0, 10), 3, "whole rounds down")
    eq(S.whole(-0.5, 9, 0, 10), 0, "whole clamps first")
    eq(S.whole("abc", 9, 0, 10), 9, "whole gives the default for a word")
    eq(S.whole(0 / 0, 9), 9, "whole gives the default for NaN")

    -- The schema is well formed.
    local ids = {}
    for _, structure in ipairs(S.SCHEMA) do
        check(not ids[structure.id], "structure id unique: " .. tostring(structure.id))
        ids[structure.id] = true
        for _, field in ipairs({ "owner", "carrier", "version" }) do
            check(type(structure[field]) == "string" and structure[field] ~= "", structure.id .. " states its " .. field)
        end
        check(_G[structure.owner] ~= nil, structure.id .. " is owned by a loaded module (" .. structure.owner .. ")")
        local seen = {}
        for _, entry in ipairs(structure.keys) do
            local name = structure.id .. "." .. tostring(entry.key)
            check(not seen[entry.key], name .. " is declared once")
            seen[entry.key] = true
            check(type(entry.type) == "string", name .. " has a type")
            check(type(entry.repair) == "string" and entry.repair ~= "", name .. " says what happens to a damaged value")
            if entry.type == "number" and entry.min ~= nil and entry.max ~= nil then
                local low = type(entry.min) == "function" and entry.min() or entry.min
                local high = type(entry.max) == "function" and entry.max() or entry.max
                check(low <= high, name .. " has an ordered range")
            end
        end
        eq(S.getStructure(structure.id), structure, structure.id .. " is found by id")
    end
    eq(S.getStructure("nope"), nil, "unknown structure")
    for _, id in ipairs({ "deposits", "depositsTile", "sample", "kit", "analyzer", "case", "round", "testCartridge" }) do
        check(ids[id], "structure " .. id .. " is declared")
    end

    -- Every ModData key the code touches is in the schema. The mod names
    -- its ModData tables "...data" / "...Data" and the deposits store
    -- "store" / "record", and writes keys as plain fields.
    local declared = {}
    for _, structure in ipairs(S.SCHEMA) do
        for _, entry in ipairs(structure.keys) do
            if entry.family then
                for _, member in ipairs(entry.family) do declared["stored_" .. member.key] = true end
            else
                declared[entry.key] = true
            end
        end
    end
    local used, usedCount = {}, 0
    for _, name in ipairs(MOCK.MOD_FILES) do
        if name ~= "shared/AC_SaveData" then
            local source = readFile(LUA .. name .. ".lua")
            for variable, key in string.gmatch(source, "([%a_]*[dD]ata)%.([%a_][%w_]*)") do
                -- The engine's ModData global and event are not tables of ours,
                -- nor are the mod's own modules whose names end in "Data".
                if variable ~= "ModData" and variable ~= "OnInitGlobalModData" and variable ~= "craftRecipeData"
                    and string.sub(variable, 1, 3) ~= "AC_" then
                    if not used[key] then usedCount = usedCount + 1 end
                    used[key] = name
                end
            end
            for key in string.gmatch(source, "%f[%w_]store%.([%a_][%w_]*)") do used[key] = name end
        end
    end
    check(usedCount > 40, "the scan found the mod's ModData keys (" .. usedCount .. ")")
    for key, file in pairs(used) do
        check(declared[key], "ModData key '" .. key .. "' (used in " .. file .. ".lua) is declared in AC_SaveData.SCHEMA")
    end
    -- And nothing is declared that the code no longer uses.
    local Q = AC_CaseQuality.CONFIG
    local byConfig = { [Q.flagKey] = true, [Q.qualityKey] = true, [Q.roundFlagKey] = true, [Q.roundQualityKey] = true, copper = true, zinc = true }
    for key in pairs(AmmoQuality.DEFAULTS) do byConfig[key] = true end
    for _, structure in ipairs(S.SCHEMA) do
        for _, entry in ipairs(structure.keys) do
            if not entry.family then
                check(used[entry.key] ~= nil or byConfig[entry.key], structure.id .. "." .. entry.key .. " is still used by the code")
            end
        end
    end
    eq(S.getStructure("case").keys[2].key, Q.qualityKey, "the case's quality key is the one AC_CaseQuality writes")
    eq(S.getStructure("round").keys[2].key, Q.roundQualityKey, "the round's quality key is the one AC_CaseQuality writes")
    -- The analyzer's stored copy covers exactly the sample's fields.
    local sampleKeys = {}
    for _, entry in ipairs(S.getStructure("sample").keys) do sampleKeys[entry.key] = true end
    for _, field in ipairs(AC_LaboratoryAnalyzer.SAMPLE_FIELDS or {}) do
        check(sampleKeys[field], "analyzer stored field " .. field .. " is a declared sample key")
    end

    -- check(): what the mod itself writes is always in the schema.
    local function clean(id, data, what)
        local problems = S.check(id, data)
        eq(#problems, 0, what .. " matches the schema: " .. table.concat(problems, "; "))
    end
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    MOCK.clearModData()
    local x, y = findTile("copper", 2)
    AC_Deposits.recordExtraction(x, y, "copper", 1)
    AC_Deposits.markWorked(x, y, "zinc")
    local store = ModData.getOrCreate(AC_Deposits.CONFIG.modDataKey)
    MOCK.capturePrint(false)
    clean("deposits", store, "the deposits store after an extraction")
    clean("depositsTile", store.tiles[x .. "," .. y], "a worked tile's record")
    MOCK.capturePrint(true)

    local square = MOCK.newSquare(x, y, 0, GRASS)
    local player = MOCK.newPlayer({ square = square, x = x, y = y })
    equipShovel(player)
    local sample = AC_GeologySampling.createSample(player, square)
    MOCK.capturePrint(false)
    check(sample ~= nil, "a sample was dug for the schema check")
    if sample then
        clean("sample", sample.modData, "a freshly dug sample")
        for _, kitType in ipairs({ "AmmoMaking.FieldAssayKit", "AmmoMaking.AdvancedFieldAssayKit" }) do
            local kit = MOCK.newItem(kitType)
            MOCK.capturePrint(true)
            AC_GeologySampling.initializeKit(kit)
            MOCK.capturePrint(false)
            clean("kit", kit.modData, "a new " .. kitType)
            MOCK.capturePrint(true)
            AC_GeologySampling.analyzeSample(sample, kit)
            MOCK.capturePrint(false)
            clean("kit", kit.modData, kitType .. " after one use")
            clean("sample", sample.modData, "the sample after " .. kitType)
        end
        MOCK.capturePrint(true)
        MOCK.worldHours = 200
        local labSquare = poweredLabSquare(x + 1, y)
        local labPlayer = MOCK.newPlayer({ square = labSquare })
        labPlayer.inventory:addItem(sample)
        local analyzer = placeAnalyzerObject(labSquare)
        AC_LaboratoryAnalyzer.getState(analyzer)
        MOCK.capturePrint(false)
        clean("analyzer", analyzer.modData, "an idle analyzer")
        MOCK.capturePrint(true)
        AC_LaboratoryAnalyzer.startAssay(labPlayer, analyzer, sample)
        MOCK.capturePrint(false)
        clean("analyzer", analyzer.modData, "a processing analyzer")
        MOCK.capturePrint(true)
        MOCK.worldHours = 200 + AC_LaboratoryAnalyzer.CONFIG.processingHours / 2
        AC_LaboratoryAnalyzer.getState(analyzer)
        MOCK.capturePrint(false)
        clean("analyzer", analyzer.modData, "an analyzer half way through")
        MOCK.capturePrint(true)
        MOCK.worldHours = 200 + AC_LaboratoryAnalyzer.CONFIG.processingHours + 1
        AC_LaboratoryAnalyzer.getState(analyzer)
        MOCK.capturePrint(false)
        clean("analyzer", analyzer.modData, "a ready analyzer")
        MOCK.capturePrint(true)
        local collected = AC_LaboratoryAnalyzer.collectSample(labPlayer, analyzer)
        MOCK.capturePrint(false)
        check(collected ~= nil, "the laboratory sample was collected")
        if collected then clean("sample", collected.modData, "a sample collected from the laboratory") end
        clean("analyzer", analyzer.modData, "an analyzer after collection")
        MOCK.worldHours = 0
    end

    local nine = AC_Calibres.get("9mm")
    local case, round = MOCK.newItem(nine.case), MOCK.newItem(nine.round)
    AC_CaseQuality.onCasesFormed({ getAllCreatedItems = function() return MOCK.arrayList({ case }) end, getAllConsumedItems = function() return MOCK.arrayList({}) end }, MOCK.newPlayer())
    clean("case", case.modData, "a formed case")
    AC_CaseQuality.onRoundsAssembled({ getAllCreatedItems = function() return MOCK.arrayList({ round }) end, getAllConsumedItems = function() return MOCK.arrayList({ case }) end })
    clean("round", round.modData, "an assembled round")
    local cartridge = MOCK.newItem("AmmoMaking.TestCartridge")
    MOCK.capturePrint(true)
    AmmoInspection.inspect(MOCK.newPlayer(), cartridge)
    MOCK.capturePrint(false)
    clean("testCartridge", cartridge.modData, "an inspected test cartridge")

    -- check() itself: it reports, it does not change.
    local damaged = { caseQuality = 900, AmmoMakingCase = "yes", shiny = true }
    local problems = table.concat(S.check("case", damaged), "; ")
    check(string.find(problems, "caseQuality: outside 1..100", 1, true) ~= nil, "an out-of-range quality is reported: " .. problems)
    check(string.find(problems, "AmmoMakingCase: a flag must be true or absent", 1, true) ~= nil, "a damaged flag is reported")
    check(string.find(problems, "shiny: not a key of case", 1, true) ~= nil, "an unknown key is reported")
    eq(damaged.caseQuality, 900, "check() changes nothing")
    eq(#S.check("case", {}), 0, "an empty table has no problems: every key may be absent")
    eq(S.check("case", "garbage")[1], "case: not a table", "a non-table is reported")
    eq(S.check("nope", {})[1], "unknown structure nope", "an unknown structure is reported")
    check(string.find(table.concat(S.check("kit", { assayUsesRemaining = 2.5 }), "; "), "assayUsesRemaining: not a whole number", 1, true) ~= nil, "a fractional count is reported")
    check(string.find(table.concat(S.check("kit", { assayUsesRemaining = 0 / 0 }), "; "), "assayUsesRemaining: not a finite number", 1, true) ~= nil, "NaN is reported")
    check(string.find(table.concat(S.check("analyzer", { labAnalyzerState = "banana" }), "; "), "labAnalyzerState: unknown value banana", 1, true) ~= nil, "an unknown state is reported")
    check(string.find(table.concat(S.check("analyzer", { stored_trueCopper = 250 }), "; "), "stored_trueCopper: outside 0..100", 1, true) ~= nil, "a stored sample field is checked as the sample's own")
    check(string.find(table.concat(S.check("analyzer", { stored_nonsense = 1 }), "; "), "stored_nonsense: not a key of analyzer", 1, true) ~= nil, "an unknown stored field is reported")
    check(string.find(table.concat(S.check("sample", { copperGrade = "Splendid" }), "; "), "copperGrade: unknown value Splendid", 1, true) ~= nil, "an unknown grade is reported")
    eq(#S.check("sample", { copperGrade = "Good", assayRank = 3, trueCopper = 62 }), 0, "valid sample fields pass")

    -- The module only describes: it stores nothing and listens to nothing.
    local source = readFile(LUA .. "shared/AC_SaveData.lua")
    check(string.find(source, "getModData(", 1, true) == nil and string.find(source, "ModData.getOrCreate", 1, true) == nil, "AC_SaveData reads no ModData itself")
    check(string.find(source, "Events%.") == nil, "and registers no event")
    MOCK.clearModData()
end

section("Save data fuzz: every persisted key, every kind of damage")
do
    -- The mod's own log lines are captured for the whole section; a failed
    -- check must still be printed.
    local outerCheck = check
    local function check(condition, message)
        if not condition then MOCK.capturePrint(false) end
        outerCheck(condition, message)
        if not condition then MOCK.capturePrint(true) end
    end
    local function eq(actual, expected, message)
        check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
    local cases, raised = 0, {}
    local function attempt(what, fn, ...)
        cases = cases + 1
        local results = { pcall(fn, ...) }
        if not results[1] and #raised < 12 then table.insert(raised, what .. ": " .. tostring(results[2])) end
        return results[1], results[2], results[3]
    end
    -- Text shown to a player never carries a broken number.
    local function cleanText(text)
        text = string.lower(tostring(text))
        return string.find(text, "nan", 1, true) == nil and string.find(text, "inf", 1, true) == nil
    end
    local function cleanLines(lines)
        for _, line in ipairs(lines or {}) do
            if not cleanText(line) then return false, line end
        end
        return true
    end

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)

    ------------------------------------------------
    -- The global depletion store
    ------------------------------------------------
    local x, y, reserve = findTile("copper", 2)
    local function freshStore()
        MOCK.clearModData()
        local store = ModData.getOrCreate(AC_Deposits.CONFIG.modDataKey)
        AC_Deposits.recordExtraction(x, y, "copper", 1)
        return store
    end
    local function useStore(what)
        attempt(what .. " getRemaining", AC_Deposits.getRemaining, x, y, "copper")
        attempt(what .. " getExtracted", AC_Deposits.getExtracted, x, y, "zinc")
        attempt(what .. " hasBeenWorked", AC_Deposits.hasBeenWorked, x, y, "copper")
        attempt(what .. " isKnownExhausted", AC_Deposits.isKnownExhausted, x, y, "copper")
        attempt(what .. " getTileInfo", AC_Deposits.getTileInfo, x, y)
        attempt(what .. " getWorkedTileCount", AC_Deposits.getWorkedTileCount)
        local player, square = miningSetup(x, y, "Good", "Good", 1)
        attempt(what .. " mining menu", fillWorldMenu, player, square)
        for _, metal in ipairs({ "copper", "zinc" }) do
            local ok, remaining = attempt(what .. " remaining " .. metal, AC_Deposits.getRemaining, x, y, metal)
            if ok then
                local initial = AC_Deposits.getInitialReserve(x, y, metal)
                check(isFinite(remaining) and remaining >= 0 and remaining <= initial, what .. ": remaining " .. metal .. " stays within 0.." .. initial .. " (" .. tostring(remaining) .. ")")
            end
            local okE, extracted = attempt(what .. " extracted " .. metal, AC_Deposits.getExtracted, x, y, metal)
            if okE then check(isFinite(extracted) and extracted >= 0, what .. ": extracted " .. metal .. " is a count (" .. tostring(extracted) .. ")") end
        end
        attempt(what .. " recordExtraction", AC_Deposits.recordExtraction, x, y, "copper", 1)
        local okA, after = attempt(what .. " remaining after a write", AC_Deposits.getRemaining, x, y, "copper")
        if okA then check(isFinite(after) and after >= 0 and after <= reserve, what .. ": a write after the damage leaves a sane reserve (" .. tostring(after) .. ")") end
    end
    for _, damage in ipairs(DAMAGE) do
        local name, value = damage[1], damage[2]
        if value == NIL then value = nil end
        local store = freshStore()
        store.version = value
        useStore("deposits version = " .. name)
        store = freshStore()
        store.tiles = value
        useStore("deposits tiles = " .. name)
        store = freshStore()
        store.tiles[x .. "," .. y] = value
        useStore("deposits record = " .. name)
        for _, metal in ipairs({ "copper", "zinc" }) do
            store = freshStore()
            store.tiles[x .. "," .. y][metal] = value
            useStore("deposits record." .. metal .. " = " .. name)
        end
    end
    do
        -- Old and unknown fields beside the known ones are ignored.
        local store = freshStore()
        store.legacyField, store.tiles.notATile, store.tiles[x .. "," .. y].tin = "old", "junk", 7
        useStore("deposits with unknown fields")
        eq(AC_Deposits.getExtracted(x, y, "copper"), 2, "unknown fields do not disturb the count")
    end
    MOCK.clearModData()

    ------------------------------------------------
    -- A geological sample
    ------------------------------------------------
    -- The keys come from the schema, so a key added there is fuzzed here.
    local function schemaKeys(id)
        local keys = {}
        for _, entry in ipairs(AC_SaveData.getStructure(id).keys) do
            if entry.family then
                for _, member in ipairs(entry.family) do table.insert(keys, "stored_" .. member.key) end
            else
                table.insert(keys, entry.key)
            end
        end
        return keys
    end
    local sampleKeys = schemaKeys("sample")
    check(#sampleKeys >= 21, "the sample's keys were taken from the schema (" .. #sampleKeys .. ")")
    local sx, sy = findTile("copper", 1)
    local function freshSample(rank)
        local sample = makeSample(sx, sy, rank or 2, "Good", "Poor")
        local d = sample.modData
        d.geologySeed, d.trueCopper, d.trueZinc, d.trueCopperPeak, d.trueZincPeak = 1, 62, 8, 70, 12
        d.assayType, d.copperMin, d.copperMax, d.zincMin, d.zincMax = "advanced", 55, 70, 0, 15
        d.labCopperResult, d.labZincResult, d.labStartedAt, d.labReadyAt = 61, 9, 10, 16
        return sample
    end
    local function useSample(what, sample)
        local square = MOCK.newSquare(sx, sy, 0, GRASS)
        local player = MOCK.newPlayer({ square = square, x = sx, y = sy })
        equipPickaxe(player)
        player.inventory:addItem(sample)
        for _, kitType in ipairs({ "AmmoMaking.FieldAssayKit", "AmmoMaking.AdvancedFieldAssayKit" }) do
            player.inventory:addItem(MOCK.newItem(kitType))
        end
        attempt(what .. " isSample", AC_GeologySampling.isSample, sample)
        local okL, lines = attempt(what .. " getResultLines", AC_GeologySampling.getResultLines, sample)
        if okL and type(lines) == "table" then
            local clean, bad = cleanLines(lines)
            check(clean, what .. ": the result panel shows no broken number (" .. tostring(bad) .. ")")
        end
        attempt(what .. " inventory menu", fillInventoryMenu, player, sample)
        attempt(what .. " world menu", fillWorldMenu, player, square)
        for _, metal in ipairs({ "copper", "zinc" }) do
            attempt(what .. " findProspect " .. metal, AC_Mining.findProspect, player, square, metal)
            attempt(what .. " getReportedGrade " .. metal, AC_Mining.getReportedGrade, sample, metal)
        end
        attempt(what .. " sampleCoversSquare", AC_Mining.sampleCoversSquare, sample, square)
        attempt(what .. " canAnalyzeSample", AC_LaboratoryAnalyzer.canAnalyzeSample, sample)
        attempt(what .. " field assay", AC_GeologySampling.analyzeSample, sample, AC_GeologySampling.findKit(player, "AmmoMaking.FieldAssayKit"))
        attempt(what .. " advanced assay", AC_GeologySampling.analyzeSample, sample, AC_GeologySampling.findKit(player, "AmmoMaking.AdvancedFieldAssayKit"))
        -- Whatever an assay read, what it WROTE is in the schema: a damaged
        -- truth must not become a stored NaN range or an unknown grade.
        do
            local written = {}
            for _, key in ipairs({ "copperMin", "copperMax", "zincMin", "zincMax", "copperGrade", "zincGrade", "assayRank" }) do
                written[key] = sample.modData[key]
            end
            local rank = tonumber(sample.modData.assayRank) or 0
            if rank >= 1 and (string.find(what, "trueCopper", 1, true) or string.find(what, "trueZinc", 1, true)) then
                local left = AC_SaveData.check("sample", written)
                check(#left == 0, what .. ": the assay stored only valid values (" .. table.concat(left, "; ") .. ")")
            end
        end
        local okR, after = attempt(what .. " getResultLines after assays", AC_GeologySampling.getResultLines, sample)
        if okR and type(after) == "table" then
            local clean, bad = cleanLines(after)
            check(clean, what .. ": the result panel is still clean after an assay (" .. tostring(bad) .. ")")
        end
        -- The laboratory takes it, finishes and hands it back.
        local labSquare = poweredLabSquare(sx + 1, sy)
        local labPlayer = MOCK.newPlayer({ square = labSquare })
        labPlayer.inventory:addItem(sample)
        local analyzer = placeAnalyzerObject(labSquare)
        local okS, started = attempt(what .. " startAssay", AC_LaboratoryAnalyzer.startAssay, labPlayer, analyzer, sample)
        if okS and started == true then
            MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours + 1
            attempt(what .. " analyzer status", AC_LaboratoryAnalyzer.getStatusInfo, analyzer)
            local okC, collected = attempt(what .. " collectSample", AC_LaboratoryAnalyzer.collectSample, labPlayer, analyzer)
            if okC and collected then
                for _, key in ipairs({ "labCopperResult", "labZincResult" }) do
                    local result = collected.modData[key]
                    check(isFinite(result) and result >= 0 and result <= 100, what .. ": " .. key .. " collected from the laboratory is 0..100 (" .. tostring(result) .. ")")
                end
            end
        end
    end
    MOCK.worldHours = 100
    for _, key in ipairs(sampleKeys) do
        for _, damage in ipairs(DAMAGE) do
            local value = damage[2]
            if value == NIL then value = nil end
            for _, rank in ipairs({ 0, 2 }) do
                local sample = freshSample(rank)
                sample.modData[key] = value
                useSample("sample (rank " .. rank .. ") " .. key .. " = " .. damage[1], sample)
            end
        end
    end
    do
        local partial = MOCK.newItem("AmmoMaking.GeologicalSample")
        useSample("sample with no data at all", partial)
        local old = freshSample(3)
        old.modData.sampleGrade, old.modData.legacyAssay = "Rich", { 1, 2 }
        useSample("sample with old fields", old)
        local all = freshSample(2)
        for _, key in ipairs(sampleKeys) do all.modData[key] = "broken" end
        useSample("sample with every field a word", all)
    end

    ------------------------------------------------
    -- An assay kit
    ------------------------------------------------
    local kitKeys = schemaKeys("kit")
    for _, kitType in ipairs({ "AmmoMaking.FieldAssayKit", "AmmoMaking.AdvancedFieldAssayKit" }) do
        for _, key in ipairs(kitKeys) do
            for _, damage in ipairs(DAMAGE) do
                local value = damage[2]
                if value == NIL then value = nil end
                local what = kitType .. " " .. key .. " = " .. damage[1]
                local kit = MOCK.newItem(kitType)
                AC_GeologySampling.initializeKit(kit)
                kit.modData[key] = value
                local square = MOCK.newSquare(sx, sy, 0, GRASS)
                local player = MOCK.newPlayer({ square = square })
                local sample = freshSample(0)
                player.inventory:addItem(sample)
                player.inventory:addItem(kit)
                attempt(what .. " initializeKit", AC_GeologySampling.initializeKit, kit)
                attempt(what .. " updateKitName", AC_GeologySampling.updateKitName, kit)
                local okU, uses = attempt(what .. " getKitUses", AC_GeologySampling.getKitUses, kit)
                if okU and uses ~= nil then
                    local maxUses = math.max(AC_GeologySampling.CONFIG.fieldKitUses or 0, AC_GeologySampling.CONFIG.advancedKitUses or 0, 20)
                    check(isFinite(uses) and uses >= 0 and uses <= maxUses, what .. ": uses stay within 0.." .. maxUses .. " (" .. tostring(uses) .. ")")
                end
                attempt(what .. " inventory menu", fillInventoryMenu, player, sample)
                attempt(what .. " analyzeSample", AC_GeologySampling.analyzeSample, sample, kit)
                attempt(what .. " consumeKitUse", AC_GeologySampling.consumeKitUse, kit)
                if key == "assayMaxUses" or key == "assayUsesRemaining" then
                    local left = AC_SaveData.check("kit", { assayMaxUses = kit.modData.assayMaxUses, assayUsesRemaining = kit.modData.assayUsesRemaining })
                    check(#left == 0, what .. ": the kit's counters were repaired in place (" .. table.concat(left, "; ") .. ")")
                end
                local okA, afterUses = attempt(what .. " getKitUses after use", AC_GeologySampling.getKitUses, kit)
                if okA and afterUses ~= nil then
                    check(isFinite(afterUses) and afterUses >= 0, what .. ": uses never go negative (" .. tostring(afterUses) .. ")")
                end
                check(cleanText(kit:getName()), what .. ": the kit's name shows no broken number (" .. tostring(kit:getName()) .. ")")
                -- Uses that are not a number at all: an empty kit, not a full one.
                if key == "assayUsesRemaining" and not isFinite(tonumber(value)) then
                    local emptied = MOCK.newItem(kitType)
                    AC_GeologySampling.initializeKit(emptied)
                    emptied.modData.assayUsesRemaining = value
                    eq(AC_GeologySampling.getKitUses(emptied), 0, what .. ": a kit whose uses are not a number is empty, not refilled")
                    eq(AC_GeologySampling.consumeKitUse(emptied), false, what .. ": and gives no assay")
                end
            end
        end
    end

    ------------------------------------------------
    -- The laboratory analyzer (placed object)
    ------------------------------------------------
    local analyzerKeys = schemaKeys("analyzer")
    check(#analyzerKeys >= 30, "the analyzer's keys, stored sample fields included, were taken from the schema (" .. #analyzerKeys .. ")")
    local STATES = { idle = true, processing = true, ready = true }
    for _, phase in ipairs({ "idle", "processing", "ready" }) do
        for _, key in ipairs(analyzerKeys) do
            for _, damage in ipairs(DAMAGE) do
                local value = damage[2]
                if value == NIL then value = nil end
                local what = "analyzer (" .. phase .. ") " .. key .. " = " .. damage[1]
                MOCK.worldHours = 500
                local square = poweredLabSquare(sx + 2, sy)
                local player = MOCK.newPlayer({ square = square })
                local analyzer = placeAnalyzerObject(square)
                if phase ~= "idle" then
                    local sample = freshSample(1)
                    player.inventory:addItem(sample)
                    AC_LaboratoryAnalyzer.startAssay(player, analyzer, sample)
                    if phase == "ready" then
                        MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours + 1
                        AC_LaboratoryAnalyzer.getState(analyzer)
                    end
                end
                analyzer.modData[key] = value
                local okS, state = attempt(what .. " getState", AC_LaboratoryAnalyzer.getState, analyzer)
                if okS and key ~= "AmmoMakingLaboratoryAnalyzerWorldObject" then
                    check(STATES[state] == true, what .. ": the state is one of the three (" .. tostring(state) .. ")")
                end
                local okH, hours = attempt(what .. " getHoursRemaining", AC_LaboratoryAnalyzer.getHoursRemaining, analyzer)
                if okH and hours ~= nil then
                    check(isFinite(hours) and hours >= 0 and hours <= AC_LaboratoryAnalyzer.CONFIG.processingHours, what .. ": hours remaining stay within 0.." .. AC_LaboratoryAnalyzer.CONFIG.processingHours .. " (" .. tostring(hours) .. ")")
                end
                local okI, info = attempt(what .. " getStatusInfo", AC_LaboratoryAnalyzer.getStatusInfo, analyzer)
                if okI and type(info) == "table" then
                    for field, text in pairs(info) do
                        if type(text) == "string" then check(cleanText(text), what .. ": status " .. field .. " shows no broken number (" .. text .. ")") end
                    end
                end
                attempt(what .. " canPickUp", AC_LaboratoryAnalyzer.canPickUp, analyzer)
                attempt(what .. " isIdleAndEmpty", AC_LaboratoryAnalyzer.isIdleAndEmpty, analyzer)
                attempt(what .. " menu", fillAnalyzerMenu, player, analyzer)
                local another = freshSample(0)
                player.inventory:addItem(another)
                attempt(what .. " startAssay", AC_LaboratoryAnalyzer.startAssay, player, analyzer, another)
                MOCK.worldHours = MOCK.worldHours + AC_LaboratoryAnalyzer.CONFIG.processingHours + 1
                local okC, collected = attempt(what .. " collectSample", AC_LaboratoryAnalyzer.collectSample, player, analyzer)
                if okC and collected then
                    for _, resultKey in ipairs({ "labCopperResult", "labZincResult" }) do
                        local result = collected.modData[resultKey]
                        check(isFinite(result) and result >= 0 and result <= 100, what .. ": " .. resultKey .. " handed back is 0..100 (" .. tostring(result) .. ")")
                    end
                end
                attempt(what .. " cancelAssay", AC_LaboratoryAnalyzer.cancelAssay, player, analyzer)
                local okF, final = attempt(what .. " final state", AC_LaboratoryAnalyzer.getState, analyzer)
                if okF and key ~= "AmmoMakingLaboratoryAnalyzerWorldObject" then
                    check(STATES[final] == true, what .. ": still one of the three states afterwards (" .. tostring(final) .. ")")
                end
            end
        end
    end
    MOCK.worldHours = 0

    ------------------------------------------------
    -- A case, a hull, a handloaded round
    ------------------------------------------------
    local Q = AC_CaseQuality.CONFIG
    for _, calibre in ipairs({ AC_Calibres.get("9mm"), AC_Calibres.get(".308"), AC_Calibres.get("12 Gauge") }) do
        for _, kind in ipairs({ "case", "round" }) do
            local keys = kind == "case" and { Q.qualityKey, Q.flagKey } or { Q.roundQualityKey, Q.roundFlagKey or "AmmoMakingHandloaded" }
            for _, key in ipairs(keys) do
                for _, damage in ipairs(DAMAGE) do
                    local value = damage[2]
                    if value == NIL then value = nil end
                    local what = calibre.id .. " " .. kind .. " " .. key .. " = " .. damage[1]
                    local item = MOCK.newItem(calibre[kind])
                    if kind == "case" then
                        AC_CaseQuality.set(item, 80)
                    else
                        item.modData[Q.roundQualityKey], item.modData.AmmoMakingHandloaded = 80, true
                    end
                    item.modData[key] = value
                    local reader = kind == "case" and AC_CaseQuality.get or AC_CaseQuality.getRoundQuality
                    local okQ, quality = attempt(what .. " read", reader, item)
                    if okQ then
                        check(quality == nil or (isFinite(quality) and quality >= Q.minQuality and quality <= Q.maxQuality), what .. ": quality is none or " .. Q.minQuality .. ".." .. Q.maxQuality .. " (" .. tostring(quality) .. ")")
                    end
                    for _, level in ipairs({ 0, 3, 7 }) do
                        local player = MOCK.newPlayer()
                        player.perkLevel = level
                        local okI, result = attempt(what .. " inspect at level " .. level, AmmoInspection.inspectComponent, player, item)
                        if okI and result then
                            local clean, bad = cleanLines(result.lines)
                            check(clean, what .. ": inspection at level " .. level .. " shows no broken number (" .. tostring(bad) .. ")")
                            for _, line in ipairs(result.lines) do
                                local shown = tonumber(string.match(line, "%((%-?%d+)%)"))
                                check(shown == nil or (shown >= Q.minQuality and shown <= Q.maxQuality), what .. ": inspection never shows a quality outside the range (" .. line .. ")")
                            end
                        end
                        attempt(what .. " menu at level " .. level, fillInventoryMenu, player, item)
                    end
                    if kind == "case" then
                        -- Assembled into a round, the damage is not inherited.
                        local round = MOCK.newItem(calibre.round)
                        local data = {
                            getAllCreatedItems = function() return MOCK.arrayList({ round }) end,
                            getAllConsumedItems = function() return MOCK.arrayList({ item }) end,
                        }
                        attempt(what .. " assembled", AC_CaseQuality.onRoundsAssembled, data)
                        local inherited = AC_CaseQuality.getRoundQuality(round)
                        check(inherited == nil or (isFinite(inherited) and inherited >= Q.minQuality and inherited <= Q.maxQuality), what .. ": the round inherits none or " .. Q.minQuality .. ".." .. Q.maxQuality .. " (" .. tostring(inherited) .. ")")
                        local stored = round.modData[Q.roundQualityKey]
                        check(stored == nil or (isFinite(stored) and stored >= Q.minQuality and stored <= Q.maxQuality), what .. ": nothing out of range is written to the round (" .. tostring(stored) .. ")")
                    end
                end
            end
        end
    end

    ------------------------------------------------
    -- The prototype test cartridge
    ------------------------------------------------
    local cartridgeKeys = schemaKeys("testCartridge")
    for _, key in ipairs(cartridgeKeys) do
        for _, damage in ipairs(DAMAGE) do
            local value = damage[2]
            if value == NIL then value = nil end
            local what = "test cartridge " .. key .. " = " .. damage[1]
            local item = MOCK.newItem("AmmoMaking.TestCartridge")
            AmmoQuality.initialize(item)
            item.modData[key] = value
            for _, level in ipairs({ 0, 4, 9 }) do
                local player = MOCK.newPlayer()
                player.perkLevel = level
                local okI, result = attempt(what .. " inspect at level " .. level, AmmoInspection.inspect, player, item)
                if okI and result then
                    local clean, bad = cleanLines(result.lines)
                    check(clean, what .. ": inspection at level " .. level .. " shows no broken number (" .. tostring(bad) .. ")")
                end
                attempt(what .. " menu", fillInventoryMenu, player, item)
            end
            for field in pairs(AmmoQuality.DEFAULTS) do
                check(isFinite(item.modData[field]), what .. ": " .. field .. " is a finite number after inspection (" .. tostring(item.modData[field]) .. ")")
            end
            if key ~= "AmmoMakingQualityInitialized" then
                local left = AC_SaveData.check("testCartridge", item.modData)
                check(#left == 0, what .. ": the cartridge was repaired in place (" .. table.concat(left, "; ") .. ")")
            end
        end
    end

    MOCK.capturePrint(false)
    eq(#raised, 0, "no damaged value raised an error: " .. table.concat(raised, " | "))
    check(cases > 25000, "tens of thousands of damaged reads were run (" .. cases .. ")")
    print("  Save data fuzz: " .. cases .. " calls on damaged data, " .. #raised .. " raised")
    MOCK.clearModData()
end

------------------------------------------------
-- RECYCLING SOURCES (the architecture, with a source that does not exist)
------------------------------------------------

section("Recycling sources: a kind of brass is data, not a second copy of the logic")
do
    local C = AC_Recycling.CONFIG
    -- Today there is one source, and it is CONFIG.
    local sources = AC_Recycling.getSources()
    eq(#sources, 1, "one source of brass to scrap today: unused components")
    eq(sources[1].id, "clean", "it is the clean one")
    eq(sources[1].batchUnits, C.batchUnits, "with CONFIG's batch")
    eq(sources[1].scrapPerBatch, C.scrapPerBatch, "and CONFIG's yield")
    eq(sources[1].idPrefix, C.idPrefix, "and CONFIG's recipe ids")
    eq(AC_Recycling.getRecovery(), AC_Recycling.getRecovery(sources[1]), "getRecovery() is the clean source's")
    for _, recipe in ipairs(AC_Recycling.buildRecipes()) do
        if recipe.loss then eq(recipe.recyclingSource, "clean", recipe.id .. " names its source") end
    end
    -- Passing the source explicitly changes nothing.
    local implicit, explicit = AC_Recycling.buildRecipes(), AC_Recycling.buildRecipes(sources)
    eq(#explicit, #implicit, "buildRecipes(getSources()) is buildRecipes()")
    for index, recipe in ipairs(implicit) do
        eq(explicit[index].id, recipe.id, "same recipe " .. index)
        eq(explicit[index].outputs[1].count, recipe.outputs[1].count, "same yield " .. index)
    end
    eq(#AC_Recycling.validate(nil, sources), 0, "and validates the same")

    -- A second, dirtier source (spent cases, were they ever to exist) is a
    -- table. The items below are invented for this test: the mod defines
    -- no spent-case item, and a test below fails if it starts to.
    local function spentSource(batchUnits, scrapPerBatch)
        return {
            id = "spent",
            idPrefix = "Test_ScrapSpentBrass",
            callbackPrefix = "onScrapSpentBrass",
            batchUnits = batchUnits,
            scrapPerBatch = scrapPerBatch,
            components = function()
                return { ["Test.SpentCaseSmall"] = 5, ["Test.SpentCaseLarge"] = 15 }, { "Test.SpentCaseSmall", "Test.SpentCaseLarge" }
            end,
        }
    end
    local quarter = spentSource(40, 1)
    eq(AC_Recycling.getRecovery(quarter), 0.25, "a source of 40 units to one scrap returns a quarter")
    local groups = AC_Recycling.buildGroups(quarter)
    eq(#groups, 2, "the spent source groups its two brass sizes")
    eq(groups[1].count, 8, "eight small spent cases (40 units) to a batch")
    eq(groups[1].scrap, 1, "for one scrap")
    eq(groups[2].count, 8, "eight large ones (120 units)")
    eq(groups[2].scrap, 3, "for three")
    local both = { sources[1], quarter }
    local recipes = AC_Recycling.buildRecipes(both)
    eq(#recipes, #implicit + 2, "two more scrapping recipes, generated by the same code")
    local ids, spentRecipes = {}, 0
    for _, recipe in ipairs(recipes) do
        check(not ids[recipe.id], "recipe id unique across sources: " .. recipe.id)
        ids[recipe.id] = true
        if recipe.recyclingSource == "spent" then
            spentRecipes = spentRecipes + 1
            eq(recipe.xp, 0, recipe.id .. " awards nothing, like every recycling recipe")
            eq(recipe.loss, true, recipe.id .. " is marked as losing brass")
            check(string.sub(recipe.callback, 1, 17) == "onScrapSpentBrass", recipe.id .. " has the source's callback name")
        end
    end
    eq(spentRecipes, 2, "both belong to the spent source")
    local problems = AC_Recycling.validate(recipes, both)
    eq(#problems, 0, "clean and spent together are sound: " .. table.concat(problems, "; "))

    -- What validate() refuses of a source.
    local function refused(what, list, needle)
        local found = table.concat(AC_Recycling.validate(AC_Recycling.buildRecipes(list), list), "; ")
        check(string.find(found, needle, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
    end
    refused("a dirty source that returns more than the clean one", { sources[1], spentSource(40, 3) }, "returns more brass than a cleaner source")
    refused("a source that loses nothing", { sources[1], spentSource(10, 1) }, "scrapping must lose brass")
    refused("a source with a fractional yield", { sources[1], spentSource(40, 0.5) }, "whole and positive")
    refused("the same source twice", { sources[1], sources[1] }, "is listed twice")
    local overlapping = spentSource(40, 1)
    overlapping.components = function() return { ["AmmoMaking.BrassCaseCup"] = 5 }, { "AmmoMaking.BrassCaseCup" } end
    refused("a component in two sources", { sources[1], overlapping }, "belongs to two sources")
    -- The same recovery as the clean source is allowed (not more).
    eq(#AC_Recycling.validate(AC_Recycling.buildRecipes({ sources[1], spentSource(20, 1) }), { sources[1], spentSource(20, 1) }), 0, "a second source at the same recovery is allowed")

    -- None of it exists in the mod: one source, no spent-case item anywhere.
    eq(#AC_Recycling.getSources(), 1, "the invented source did not stay behind")
    for id in pairs(declaredItems) do
        check(string.find(string.lower(id), "spent", 1, true) == nil, id .. " is not a spent-case item (none is defined; SPENT_CASE_RESEARCH.md)")
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        eq(calibre.spentCase, nil, calibre.id .. " names no spent case")
    end
end

section("Spent-case policies: the analysis follows the model and no policy creates brass")
do
    -- An analysis for a decision, not a feature: the mod defines no spent
    -- case. The table in SPENT_CASE_RESEARCH.md is generated, so it moves
    -- with the calibre model.
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local document = readFile(ROOT .. "/docs/SPENT_CASE_RESEARCH.md")
    local from = string.find(document, BALANCE.SPENT_START, 1, true)
    local _, to = string.find(document, BALANCE.SPENT_FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the research document has the policy table markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderSpentBlock(), "the policy table equals the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceSpent(document), document, "regenerating it changes nothing")

    local function near(a, b) return math.abs(a - b) < 1e-9 end
    local byId = {}
    for _, policy in ipairs(BALANCE.SPENT_POLICIES) do byId[policy.id] = policy end
    eq(#BALANCE.SPENT_POLICIES, 5, "five policies are compared")
    local clean = AC_Recycling.getRecovery()
    for _, policy in ipairs(BALANCE.SPENT_POLICIES) do
        local what = "policy " .. policy.id
        check(policy.scrap <= clean, what .. ": spent brass never scraps better than unused components")
        check(policy.resize <= 1 and policy.factoryResize <= 1, what .. ": resizing never makes more cases than it takes")
        check(policy.factory <= 1 and policy.handloaded <= 1, what .. ": at most one case per round fired")
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local caseBrass = AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase / AC_Materials.CONFIG.unitsPerIngot
            for _, origin in ipairs({ "factory", "handloaded" }) do
                local s = BALANCE.spentCases(policy, calibre, 100, origin)
                check(s.cases <= 100, what .. " " .. calibre.id .. " " .. origin .. ": no more cases than rounds")
                check(s.reloadable <= s.cases, what .. " " .. calibre.id .. " " .. origin .. ": no more reloadable cases than spent ones")
                check(s.scrapIngots <= s.cases * caseBrass + 1e-9, what .. " " .. calibre.id .. " " .. origin .. ": scrap holds no more brass than the cases did")
                check(s.reloadIngots <= 100 * caseBrass + 1e-9, what .. " " .. calibre.id .. " " .. origin .. ": reloaded cases hold no more brass than the rounds' cases")
                check(s.brassNeeded <= s.brassFromScratch + 1e-9 and s.brassNeeded >= 0, what .. " " .. calibre.id .. " " .. origin .. ": the next hundred never cost more brass than from scratch")
                -- Primers are never recovered: some brass is always needed.
                check(s.brassNeeded > 0, what .. " " .. calibre.id .. " " .. origin .. ": the primers still take brass")
                check(s.oreNeeded >= s.oreFromScratch - s.brassFromScratch - 1e-9, what .. " " .. calibre.id .. " " .. origin .. ": the projectiles' copper is never recovered")
            end
        end
    end
    -- The figures the document's prose quotes.
    local nine, rifle = AC_Calibres.get("9mm"), AC_Calibres.get(".308")
    eq(BALANCE.spentCases(byId.A, nine, 100, "factory").reloadIngots, 5, "A: a hundred looted 9mm are five ingots of ready cases")
    eq(BALANCE.spentCases(byId.A, rifle, 100, "factory").reloadIngots, 15, "A: a hundred looted .308 are fifteen")
    check(near(BALANCE.spentCases(byId.A, rifle, 100, "handloaded").oreFromScratch, 27), "(of the 27 ore a hundred .308 take)")
    eq(BALANCE.spentCases(byId.A, nine, 50, "factory").reloadIngots, 2.5, "A: a box of fifty 9mm is two and a half")
    eq(BALANCE.spentCases(byId.B, nine, 100, "factory").reloadIngots, 0, "B: looted cases cannot be reloaded")
    check(near(BALANCE.spentCases(byId.B, rifle, 100, "factory").scrapIngots, 3.75), "B: a hundred looted .308 are 3.75 ingots of scrap")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local c = BALANCE.spentCases(byId.C, calibre, 100, "factory")
        eq(c.cases + c.scrapIngots + c.reloadIngots, 0, "C: looted " .. calibre.id .. " give no brass at all")
        local e = BALANCE.spentCases(byId.E, calibre, 100, "handloaded")
        check(near(e.brassNeeded, e.brassFromScratch), "E: " .. calibre.id .. " costs what it costs today")
    end
    check(near(BALANCE.spentCases(byId.C, nine, 100, "handloaded").brassNeeded, 2.25), "C: the next hundred 9mm take 2.25 ingots of brass instead of 6")
    check(near(BALANCE.spentCases(byId.C, rifle, 100, "handloaded").brassNeeded, 5.75), "C: the next hundred .308 take 5.75 instead of 17")
    -- The ordering the recommendation rests on: only A, B and D turn
    -- factory ammunition into brass.
    for _, id in ipairs({ "A", "B", "D" }) do
        check(BALANCE.spentCases(byId[id], nine, 100, "factory").scrapIngots > 0, id .. " makes brass out of looted ammunition")
    end
end

------------------------------------------------
-- QUALITY TALLY (pure arithmetic; no firearm, no save)
------------------------------------------------

section("Quality tally: pure arithmetic, conserving, doubt resolves toward factory")
do
    local T = AC_QualityTally
    local Q = AC_CaseQuality.CONFIG
    local function sound(tally, what)
        local problems = T.check(tally)
        eq(#problems, 0, what .. " obeys the rules: " .. table.concat(problems, "; "))
    end
    local function same(a, b)
        return a.count == b.count and a.handloaded == b.handloaded and a.qualitySum == b.qualitySum and a.version == b.version
    end
    local function load(tally, handloaded, quality, factory)
        for _ = 1, handloaded do tally = T.addHandloaded(tally, quality) end
        return T.addFactory(tally, factory)
    end

    -- Pinned shape.
    eq(T.CONFIG.version, 1, "the record's layout is version 1")
    eq(Q.minQuality, 1, "a round's quality starts at 1")
    eq(Q.maxQuality, 100, "and ends at 100")
    local empty = T.empty()
    eq(empty.count + empty.handloaded + empty.qualitySum, 0, "an empty record holds nothing")
    sound(empty, "an empty record")
    eq(T.empty(7).count, 7, "empty(7) is seven factory rounds")
    eq(T.getFactory(T.empty(7)), 7, "all of them factory")
    eq(T.empty(-3).count, 0, "a negative count is no rounds")
    eq(T.empty(0 / 0).count, 0, "NaN is no rounds")

    -- Loading.
    local mag = load(nil, 5, 80, 5)
    sound(mag, "five handloaded and five factory rounds")
    eq(mag.count, 10, "ten rounds")
    eq(mag.handloaded, 5, "five handloaded")
    eq(mag.qualitySum, 400, "their qualities added up")
    eq(T.getFactory(mag), 5, "five factory")
    eq(T.getMeanQuality(mag), 80, "mean quality 80")
    eq(T.getHandloadedShare(mag), 0.5, "half the magazine")
    eq(T.getMeanQuality(T.empty(4)), nil, "factory rounds have no quality")
    eq(T.getHandloadedShare(T.empty()), 0, "an empty record has no share")
    eq(T.addFactory(mag).count, 11, "addFactory adds one round by default")
    -- A round with no usable quality is a factory round, never a good one.
    for _, bad in ipairs({ "excellent", 0 / 0, math.huge, -math.huge, true, {} }) do
        local after = T.addHandloaded(mag, bad)
        eq(after.count, 11, "a round of quality " .. tostring(bad) .. " is still a round")
        eq(after.handloaded, 5, "but not a handloaded one")
        eq(after.qualitySum, 400, "and adds no quality")
    end
    eq(T.addHandloaded(nil, nil).handloaded, 0, "a factory round (no quality) is counted as factory")
    eq(T.addHandloaded(nil, 900).qualitySum, Q.maxQuality, "a quality above the range is the maximum, as AC_CaseQuality reads it")
    eq(T.addHandloaded(nil, -5).qualitySum, Q.minQuality, "below the range: the minimum")
    eq(T.addHandloaded(nil, 71.9).qualitySum, 71, "a fraction is rounded down")
    eq(mag.count, 10, "no function changed the record it was given")

    -- Splitting: the mix leaves evenly.
    local kinds = {}
    local rest = mag
    for _ = 1, 10 do
        local round
        rest, round = T.consume(rest)
        table.insert(kinds, round.handloaded and "H" or "F")
        sound(rest, "the magazine after a shot")
        if round.handloaded then eq(round.quality, 80, "a fired handloaded round has the mean quality") end
    end
    eq(table.concat(kinds), "FHFHFHFHFH", "a half-and-half magazine fires factory and handloaded rounds in turn")
    eq(rest.count, 0, "ten shots empty it")
    local afterEmpty, nothing = T.consume(rest)
    eq(nothing, nil, "an empty magazine fires nothing")
    eq(afterEmpty.count, 0, "and stays empty")
    do
        local one = load(nil, 1, 60, 9)
        local order = {}
        for _ = 1, 10 do
            local round
            one, round = T.consume(one)
            table.insert(order, round.handloaded and "H" or "F")
        end
        eq(table.concat(order), "FFFFFFFFFH", "one handloaded round among nine factory rounds is fired last")
        local nine = load(nil, 9, 60, 1)
        order = {}
        for _ = 1, 10 do
            local round
            nine, round = T.consume(nine)
            table.insert(order, round.handloaded and "H" or "F")
        end
        eq(table.concat(order), "HHHHHHHHFH", "one factory round among nine handloaded ones leaves near the end, never first")
    end
    do
        local taken, stay = T.split(mag, 4)
        eq(taken.count, 4, "four rounds leave")
        eq(taken.handloaded, 2, "two of them handloaded")
        eq(taken.qualitySum, 160, "with their share of the quality")
        eq(stay.count, 6, "six stay")
        eq(stay.handloaded, 3, "three of them handloaded")
        eq(stay.qualitySum, 240, "with the rest of the quality")
        local all, none = T.split(mag, 99)
        check(same(all, mag), "asking for more than there is takes everything")
        eq(none.count, 0, "and leaves nothing")
        local zero, whole = T.split(mag, 0)
        eq(zero.count, 0, "taking nothing takes nothing")
        check(same(whole, mag), "and leaves everything")
        for _, bad in ipairs({ -1, "x", 0 / 0, math.huge, 2.5 }) do
            local t, r = T.split(mag, bad)
            eq(t.count + r.count, 10, "split(" .. tostring(bad) .. ") loses no round")
            sound(t, "what split(" .. tostring(bad) .. ") takes")
        end
    end
    -- Uneven quality: the rounding stays behind, nothing is lost.
    do
        local uneven = T.addHandloaded(T.addHandloaded(T.addHandloaded(nil, 71), 70), 70)
        eq(uneven.qualitySum, 211, "three rounds of 71, 70 and 70")
        local taken, stay = T.split(uneven, 1)
        eq(taken.qualitySum, 70, "one leaves with the mean rounded down")
        eq(stay.qualitySum, 141, "and the remainder stays")
        local list = T.qualities(uneven)
        eq(#list, 3, "three loose rounds")
        eq(list[1] + list[2] + list[3], 211, "whose qualities add up to the sum exactly")
        eq(list[1], 71, "the remainder goes to the first")
        eq(list[3], 70, "the rest get the mean rounded down")
        local left, out = T.unload(load(uneven, 0, 0, 2), 5)
        eq(left.count, 0, "unloading everything empties the record")
        eq(out.factory, 2, "two factory rounds come out")
        eq(#out.qualities, 3, "and three handloaded ones")
        eq(#T.qualities(T.empty(5)), 0, "factory rounds carry no quality")
    end

    -- Merge and transfer: a magazine into a gun with a round chambered,
    -- and out again.
    do
        local chamber = T.addHandloaded(nil, 90)
        local gun, fits = T.merge(chamber, mag)
        eq(fits, true, "a magazine fits a gun")
        eq(gun.count, 11, "eleven rounds in the gun")
        eq(gun.handloaded, 6, "six handloaded")
        eq(gun.qualitySum, 490, "all their quality")
        local from, to = T.transfer(gun, nil, 10)
        eq(from.count + to.count, 11, "ejecting the magazine moves ten and leaves one")
        eq(from.handloaded + to.handloaded, 6, "no handloaded round appears or is lost")
        eq(from.qualitySum + to.qualitySum, 490, "nor any quality")
        eq(to.count, 10, "the magazine holds ten again")
        local full = T.empty(T.CONFIG.maxRounds)
        local unchanged, refused = T.merge(full, mag)
        eq(refused, false, "a merge above the limit is refused")
        eq(unchanged.count, T.CONFIG.maxRounds, "and changes nothing")
        local source, target = T.transfer(mag, full, 4)
        check(same(source, mag), "a transfer the destination cannot take moves nothing")
        eq(target.count, T.CONFIG.maxRounds, "(the destination is unchanged)")
        eq(T.addFactory(full, 5).count, T.CONFIG.maxRounds, "nothing is counted above the limit")
        eq(T.addHandloaded(full, 80).handloaded, 0, "nor loaded above it")
    end

    -- Repair: what is damage, and what it becomes.
    do
        local fine, status = T.repair(mag)
        eq(status, T.OK, "a sound record is ok")
        check(same(fine, mag) and fine ~= mag, "and comes back as a copy")
        local none, noneStatus = T.repair(nil)
        eq(noneStatus, T.OK, "no record at all is a sound empty one")
        eq(none.count, 0, "(empty)")
        for _, case in ipairs({
            { "a word", "garbage", 0 },
            { "a number", 42, 0 },
            { "an empty table", {}, 0 },
            { "no version", { count = 10, handloaded = 5, qualitySum = 400 }, 10 },
            { "version 0", { version = 0, count = 10, handloaded = 5, qualitySum = 400 }, 10 },
            { "a fractional version", { version = 1.5, count = 10, handloaded = 5, qualitySum = 400 }, 10 },
            { "more handloaded than rounds", { version = 1, count = 3, handloaded = 5, qualitySum = 400 }, 3 },
            { "a quality sum of 900 on five rounds", { version = 1, count = 10, handloaded = 5, qualitySum = 900 }, 10 },
            { "a quality sum below the minimum", { version = 1, count = 10, handloaded = 5, qualitySum = 4 }, 10 },
            { "quality without handloaded rounds", { version = 1, count = 10, handloaded = 0, qualitySum = 50 }, 10 },
            { "a negative handloaded count", { version = 1, count = 10, handloaded = -2, qualitySum = 0 }, 10 },
            { "a fractional handloaded count", { version = 1, count = 10, handloaded = 2.5, qualitySum = 200 }, 10 },
            { "a NaN quality sum", { version = 1, count = 10, handloaded = 5, qualitySum = 0 / 0 }, 10 },
            { "an infinite quality sum", { version = 1, count = 10, handloaded = 5, qualitySum = math.huge }, 10 },
            { "a NaN count", { version = 1, count = 0 / 0, handloaded = 5, qualitySum = 400 }, 0 },
            { "a negative count", { version = 1, count = -4, handloaded = 0, qualitySum = 0 }, 0 },
            { "a count as a string", { version = 1, count = "10", handloaded = 5, qualitySum = 400 }, 0 },
            { "a count above the limit", { version = 1, count = 1e15, handloaded = 5, qualitySum = 400 }, T.CONFIG.maxRounds },
        }) do
            local repaired, how = T.repair(case[2])
            eq(how, T.REPAIRED, case[1] .. " is damage")
            sound(repaired, case[1] .. ", repaired,")
            eq(repaired.handloaded, 0, case[1] .. " reads as all factory")
            eq(repaired.qualitySum, 0, case[1] .. " carries no quality")
            eq(repaired.count, case[3], case[1] .. " keeps a usable count")
        end
        -- A later release's record is not ours to rewrite.
        local newer, newerStatus = T.repair({ version = 2, count = 10, handloaded = 5, qualitySum = 400, queue = { 80, 80 } })
        eq(newerStatus, T.NEWER, "a higher version is reported as newer")
        eq(newer.handloaded, 0, "and read as nothing known")
        local kept, keptStatus = T.reconcile({ version = 7, count = 3 }, 10)
        eq(keptStatus, T.NEWER, "reconcile reports it too")
        eq(kept.count, 0, "and does not pretend to know the load")
    end

    -- Reconcile: the game's count is the authority.
    do
        local inStep, status = T.reconcile(mag, 10)
        eq(status, T.OK, "a record in step with the game is ok")
        check(same(inStep, mag), "and unchanged")
        local more, moreStatus = T.reconcile(mag, 14)
        eq(moreStatus, T.ADJUSTED, "rounds nobody reported are an adjustment")
        eq(more.count, 14, "the count follows the game")
        eq(more.handloaded, 5, "the unknown rounds are factory rounds")
        eq(more.qualitySum, 400, "and bring no quality")
        local fewer, fewerStatus = T.reconcile(mag, 3)
        eq(fewerStatus, T.ADJUSTED, "missing rounds are an adjustment")
        eq(fewer.count, 3, "the count follows the game")
        eq(fewer.handloaded, 1, "the handloaded share is rounded down (5 of 10, 3 left: 1, not 2)")
        eq(fewer.qualitySum, 80, "with its share of the quality")
        sound(fewer, "a record that lost rounds")
        local gone = T.reconcile(mag, 0)
        eq(gone.count + gone.handloaded + gone.qualitySum, 0, "an emptied gun has an empty record")
        local unknown = T.reconcile(mag, "ten")
        eq(unknown.count, 0, "an unusable count from the game is no rounds")
        local damaged, damagedStatus = T.reconcile({ version = 1, count = 10, handloaded = 50, qualitySum = 400 }, 10)
        eq(damagedStatus, T.REPAIRED, "a damaged record stays reported as repaired")
        eq(damaged.handloaded, 0, "and is all factory")
        eq(damaged.count, 10, "at the game's count")
    end

    -- Property run: a pool of loose rounds, a magazine, a gun and a second
    -- gun, with every operation the future carrier needs and the accidents
    -- it has to survive. One ledger: rounds, handloaded rounds and quality,
    -- over everything that exists and everything that was fired.
    do
        local seed = 20261002
        local function random(n)
            seed = (seed * 1103515245 + 12345) % 2147483648
            return math.floor(seed / 65536) % n
        end
        local operations, violations = 0, {}
        local function violation(text)
            if #violations < 8 then table.insert(violations, text) end
        end
        for run = 1, 40 do
            local records = { T.empty(), T.empty(), T.empty() }
            local loose = { factory = 0, handloaded = 0, quality = 0 }
            local fired = { factory = 0, handloaded = 0, quality = 0 }
            -- What exists, counted from the records and the loose rounds.
            local function ledger()
                local rounds, handloaded, quality = loose.factory + loose.handloaded + fired.factory + fired.handloaded, loose.handloaded + fired.handloaded, loose.quality + fired.quality
                for _, record in ipairs(records) do
                    rounds, handloaded, quality = rounds + record.count, handloaded + record.handloaded, quality + record.qualitySum
                end
                return rounds, handloaded, quality
            end
            for step = 1, 400 do
                local before = { ledger() }
                local which = 1 + random(#records)
                local other = 1 + random(#records)
                local op = random(9)
                local exact = true
                local expected = { 0, 0, 0 }
                if op == 0 then
                    -- Factory rounds are loaded.
                    local rounds = 1 + random(3)
                    records[which] = T.addFactory(records[which], rounds)
                    expected = { rounds, 0, 0 }
                elseif op == 1 then
                    -- A handloaded round is loaded.
                    local quality = 1 + random(100)
                    records[which] = T.addHandloaded(records[which], quality)
                    expected = { 1, 1, quality }
                elseif op == 2 and which ~= other then
                    records[which], records[other] = T.transfer(records[which], records[other], random(12))
                elseif op == 3 then
                    local round
                    records[which], round = T.consume(records[which])
                    if round then
                        if round.handloaded then
                            fired.handloaded, fired.quality = fired.handloaded + 1, fired.quality + round.quality
                            if round.quality < Q.minQuality or round.quality > Q.maxQuality then violation("a fired round of quality " .. round.quality) end
                        else
                            fired.factory = fired.factory + 1
                        end
                    end
                elseif op == 4 then
                    local out
                    records[which], out = T.unload(records[which], random(8))
                    loose.factory = loose.factory + out.factory
                    for _, quality in ipairs(out.qualities) do
                        loose.handloaded, loose.quality = loose.handloaded + 1, loose.quality + quality
                        if quality < Q.minQuality or quality > Q.maxQuality or quality ~= math.floor(quality) then violation("an unloaded round of quality " .. tostring(quality)) end
                    end
                elseif op == 5 and which ~= other then
                    local merged, fits = T.merge(records[which], records[other])
                    if fits then records[which], records[other] = merged, T.empty() end
                elseif op == 6 then
                    local taken, stay = T.split(records[which], random(6))
                    local back = T.merge(stay, taken)
                    if back.count ~= records[which].count or back.handloaded ~= records[which].handloaded or back.qualitySum ~= records[which].qualitySum then
                        violation("split then merge is not the record it started from")
                    end
                elseif op == 7 then
                    -- An accident: the game's count moved without the tally
                    -- being told. Rounds may vanish or appear; handloaded
                    -- rounds and quality may only go down.
                    local old = records[which]
                    local actual = math.max(0, old.count + random(9) - 4)
                    records[which] = T.reconcile(old, actual)
                    exact = false
                    if records[which].count ~= actual then violation("reconcile did not follow the game's count") end
                    if records[which].handloaded > old.handloaded then violation("reconcile created a handloaded round") end
                    if records[which].qualitySum > old.qualitySum then violation("reconcile created quality") end
                    if old.handloaded > 0 and records[which].handloaded > 0
                        and records[which].qualitySum * old.handloaded > old.qualitySum * records[which].handloaded then
                        violation("reconcile raised the mean quality")
                    end
                elseif op == 8 then
                    -- Damage: a field is overwritten in the stored record.
                    local old = records[which]
                    local broken = { version = old.version, count = old.count, handloaded = old.handloaded, qualitySum = old.qualitySum }
                    local field = ({ "version", "count", "handloaded", "qualitySum" })[1 + random(4)]
                    broken[field] = ({ -1, 900, 0 / 0, math.huge, "x", 2.5, 1e15 })[1 + random(7)]
                    records[which] = T.reconcile(broken, old.count)
                    exact = false
                    if records[which].handloaded > old.handloaded then violation("damage to " .. field .. " created a handloaded round") end
                    if records[which].qualitySum > old.qualitySum then violation("damage to " .. field .. " created quality") end
                end
                operations = operations + 1
                for index, record in ipairs(records) do
                    local problems = T.check(record)
                    if #problems > 0 then violation("run " .. run .. " step " .. step .. " record " .. index .. ": " .. problems[1]) end
                end
                local after = { ledger() }
                if exact then
                    for index, name in ipairs({ "rounds", "handloaded rounds", "quality" }) do
                        if after[index] ~= before[index] + expected[index] then
                            violation("run " .. run .. " step " .. step .. " op " .. op .. " changed the " .. name .. " in existence from " .. before[index] .. " to " .. after[index])
                        end
                    end
                end
            end
        end
        eq(#violations, 0, "the property run found no violation: " .. table.concat(violations, " | "))
        check(operations >= 16000, "thousands of operations were run (" .. operations .. ")")
        print("  Quality tally: " .. operations .. " random operations over 40 runs, " .. #violations .. " violations")
    end

    -- Emptying a record one shot at a time hands out exactly what it held,
    -- for every mix of a magazine up to thirty rounds.
    do
        local wrong = 0
        for count = 1, 30 do
            for handloaded = 0, count do
                -- Uneven qualities: 37, 38, 39 ...
                local record = T.empty(count - handloaded)
                local sum = 0
                for index = 1, handloaded do
                    record = T.addHandloaded(record, 36 + index)
                    sum = sum + 36 + index
                end
                local firedHandloaded, firedQuality, shots = 0, 0, 0
                while true do
                    local round
                    record, round = T.consume(record)
                    if not round then break end
                    shots = shots + 1
                    if round.handloaded then firedHandloaded, firedQuality = firedHandloaded + 1, firedQuality + round.quality end
                end
                if shots ~= count or firedHandloaded ~= handloaded or firedQuality ~= sum then wrong = wrong + 1 end
            end
        end
        eq(wrong, 0, "every mix up to thirty rounds fires exactly its rounds, its handloaded rounds and its quality")
    end

    -- Fuzz: every field, every kind of damage, through every function. None
    -- may raise, and what comes out obeys the rules and holds no more
    -- handloaded rounds or quality than the sound record did.
    do
        local calls, raised, advantages = 0, {}, {}
        local base = { version = 1, count = 10, handloaded = 5, qualitySum = 400 }
        local function attempt(what, fn, ...)
            calls = calls + 1
            local results = { pcall(fn, ...) }
            if not results[1] then
                if #raised < 8 then table.insert(raised, what .. ": " .. tostring(results[2])) end
                return
            end
            for index = 2, #results do
                local result = results[index]
                if type(result) == "table" and result.count ~= nil then
                    local problems = T.check(result)
                    if #problems > 0 and #advantages < 8 then table.insert(advantages, what .. " returned an unsound record: " .. problems[1]) end
                end
            end
            return results[2], results[3]
        end
        for _, field in ipairs({ "version", "count", "handloaded", "qualitySum" }) do
            for _, damage in ipairs(DAMAGE) do
                local value = damage[2]
                if value == NIL then value = nil end
                local function broken()
                    local record = { version = base.version, count = base.count, handloaded = base.handloaded, qualitySum = base.qualitySum }
                    record[field] = value
                    return record
                end
                local what = "tally " .. field .. " = " .. damage[1]
                local repaired = attempt(what .. " repair", T.repair, broken())
                if repaired then
                    if repaired.handloaded > base.handloaded or repaired.qualitySum > base.qualitySum then
                        table.insert(advantages, what .. ": the repair holds more than the record did")
                    end
                    -- A record wrong in one field is not trusted for the others.
                    if #T.check(broken()) > 0 and repaired.handloaded ~= 0 then
                        table.insert(advantages, what .. ": a damaged record still reads as handloaded")
                    end
                end
                attempt(what .. " check", T.check, broken())
                for _, actual in ipairs({ 0, 3, 10, 25, "x", 0 / 0 }) do
                    local reconciled = attempt(what .. " reconcile", T.reconcile, broken(), actual)
                    if reconciled and reconciled.handloaded > base.handloaded then table.insert(advantages, what .. ": reconcile created handloaded rounds") end
                end
                attempt(what .. " addFactory", T.addFactory, broken(), 2)
                local grown = attempt(what .. " addHandloaded", T.addHandloaded, broken(), 70)
                if grown and (grown.handloaded > base.handloaded + 1 or grown.qualitySum > base.qualitySum + 70) then table.insert(advantages, what .. ": loading one round added more than one") end
                attempt(what .. " split", T.split, broken(), 4)
                attempt(what .. " merge", T.merge, broken(), broken())
                attempt(what .. " transfer", T.transfer, broken(), broken(), 3)
                local _, round = attempt(what .. " consume", T.consume, broken())
                if round and round.handloaded and (not isFinite(round.quality) or round.quality < Q.minQuality or round.quality > Q.maxQuality) then
                    table.insert(advantages, what .. ": a fired round of quality " .. tostring(round.quality))
                end
                local _, out = attempt(what .. " unload", T.unload, broken(), 10)
                if out then
                    for _, quality in ipairs(out.qualities) do
                        if not isFinite(quality) or quality < Q.minQuality or quality > Q.maxQuality then table.insert(advantages, what .. ": an unloaded round of quality " .. tostring(quality)) end
                    end
                    if #out.qualities > base.handloaded then table.insert(advantages, what .. ": more handloaded rounds unloaded than were loaded") end
                end
                attempt(what .. " qualities", T.qualities, broken())
                for _, getter in ipairs({ "getFactory", "getMeanQuality", "getHandloadedShare" }) do
                    local number = attempt(what .. " " .. getter, T[getter], broken())
                    if number ~= nil and not isFinite(number) then table.insert(advantages, what .. ": " .. getter .. " is not a finite number") end
                end
            end
        end
        -- Damaged arguments on a sound record.
        for _, damage in ipairs(DAMAGE) do
            local value = damage[2]
            if value == NIL then value = nil end
            local what = "tally argument = " .. damage[1]
            attempt(what .. " empty", T.empty, value)
            attempt(what .. " addFactory", T.addFactory, base, value)
            attempt(what .. " split", T.split, base, value)
            attempt(what .. " transfer", T.transfer, base, base, value)
            attempt(what .. " unload", T.unload, base, value)
            attempt(what .. " reconcile", T.reconcile, base, value)
            attempt(what .. " merge", T.merge, base, value)
            attempt(what .. " repair", T.repair, value)
            local grown = attempt(what .. " addHandloaded", T.addHandloaded, base, value)
            if grown and grown.qualitySum > base.qualitySum + Q.maxQuality then table.insert(advantages, what .. ": one round added more than the maximum quality") end
        end
        eq(#raised, 0, "no damaged tally raised an error: " .. table.concat(raised, " | "))
        eq(#advantages, 0, "no damaged tally came out better than it went in: " .. table.concat(advantages, " | "))
        check(calls > 1000, "the tally fuzz ran (" .. calls .. " calls)")
        eq(base.handloaded, 5, "and the record it was given is untouched")
        print("  Quality tally fuzz: " .. calls .. " calls on damaged records and arguments, " .. #raised .. " raised")
    end

    -- It is arithmetic and nothing else: no event, no ModData, no engine
    -- object, and no other file of the mod uses it yet. Wiring it to the
    -- firearms is a later, in-game-verified step; this fails when it starts.
    do
        local source = readFile(LUA .. "shared/AC_QualityTally.lua")
        check(string.find(source, "Events%.") == nil, "the tally registers no event")
        check(string.find(source, "getModData", 1, true) == nil and string.find(source, "ModData%.") == nil, "reads and writes no ModData")
        for _, engine in ipairs({ "getPlayer", "getCell", "instanceItem", "ZombRand", "isClient", "isServer", "getCurrentAmmoCount", "ISReloadWeaponAction" }) do
            check(string.find(source, engine .. "(", 1, true) == nil, "calls no " .. engine)
        end
        for _, name in ipairs(MOCK.MOD_FILES) do
            if name ~= "shared/AC_QualityTally" then
                check(string.find(readFile(LUA .. name .. ".lua"), "AC_QualityTally", 1, true) == nil, name .. ".lua does not use the quality tally (it is not wired to anything)")
            end
        end
        eq(AC_SaveData.getStructure("tally"), nil, "and no tally is declared as persisted, because none is")
    end
end

------------------------------------------------
-- RECYCLING
------------------------------------------------

section("Brass recycling: loses brass, teaches nothing")
do
    local C = AC_Recycling.CONFIG
    local U = AC_Materials.UNITS
    local R = AC_Materials.getRecipe
    eq(#AC_Recycling.validate(), 0, "recycling is sound: " .. table.concat(AC_Recycling.validate(), "; "))

    -- Pinned numbers.
    eq(C.batchUnits, 20, "a batch is 20 units of brass")
    eq(C.scrapPerBatch, 1, "and returns one brass scrap")
    eq(AC_Recycling.getRecovery(), 0.5, "half of the brass comes back")
    eq(C.xp, 0, "recycling awards no XP")
    eq(C.requiredLevel, 0, "and needs no level")
    eq(C.scrapItem, "Base.BrassScrap", "the output is the vanilla brass scrap, not a new item")
    eq(declaredItems["AmmoMaking.BrassScrap"], nil, "the mod declares no brass scrap of its own")
    eq(C.ingotUnits, AC_Materials.CONFIG.unitsPerIngot, "an ingot is the accounting ingot")
    eq(C.scrapPerIngot * U["Base.BrassScrap"].units, U["Base.BrassIngot"].units, "ten scrap are exactly one ingot")

    -- What can be scrapped: plain brass only, every case exactly once.
    local scrappable, order = AC_Recycling.getScrappable()
    eq(#order, 2 + #AC_Calibres.LIST, "the cup, the sheet and one case or hull per calibre")
    for id, units in pairs(scrappable) do
        check(declaredItems[id] ~= nil, id .. " is a declared mod item")
        eq(U[id].metal, "brass", id .. " is brass")
        eq(U[id].contents, nil, id .. " is nothing but brass")
        eq(U[id].units, units, id .. " is worth what the material table says")
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        eq(scrappable[calibre.case], AC_Calibres.CONFIG.cupUnits * calibre.cupsPerCase, calibre.id .. " case is scrappable for its cups")
        for _, kind in ipairs({ "round", "bullet", "dieSet" }) do
            eq(scrappable[calibre[kind]], nil, calibre.id .. " " .. kind .. " cannot be scrapped")
        end
    end
    for _, primer in ipairs(AC_Calibres.PRIMERS) do
        eq(scrappable[primer.item], nil, primer.id .. " primers cannot be scrapped")
    end
    eq(scrappable["Base.GunPowder"], nil, "powder is not scrap")

    -- Groups: one recipe per brass size.
    local groups = AC_Recycling.buildGroups()
    eq(#groups, 3, "three sizes of brass component")
    local pinned = { { 5, 4, 1 }, { 10, 2, 1 }, { 15, 4, 3 } }
    local grouped = {}
    for index, group in ipairs(groups) do
        eq(group.units, pinned[index][1], "group " .. index .. " units")
        eq(group.count, pinned[index][2], "group " .. index .. " components per craft")
        eq(group.scrap, pinned[index][3], "group " .. index .. " scrap per craft")
        eq(group.count * group.units % C.batchUnits, 0, "group " .. index .. " takes whole batches")
        eq(group.scrap * U["Base.BrassScrap"].units, group.count * group.units / 2, "group " .. index .. " returns half")
        for _, id in ipairs(group.items) do
            eq(scrappable[id], group.units, id .. " is in the group of its own size")
            check(not grouped[id], id .. " is in one group only")
            grouped[id] = true
        end
    end
    for id in pairs(scrappable) do check(grouped[id], id .. " is in a group") end
    check(grouped["AmmoMaking.BrassCaseCup"] and grouped["AmmoMaking.SmallBrassSheet"] and grouped["AmmoMaking.Hull12Gauge"], "cups, sheets and hulls are covered")

    -- The recipes.
    local recipes = AC_Recycling.buildRecipes()
    eq(#recipes, #groups + 1, "one scrapping recipe per group and the recast")
    local scrapRecipes = 0
    for _, built in ipairs(recipes) do
        local recipe = R(built.id)
        check(recipe ~= nil, built.id .. " is in the live recipe list")
        eq(recipe.recycling, true, built.id .. " is marked as recycling")
        eq(AC_Materials.getRecipeXP(recipe), 0, built.id .. " awards no XP")
        eq(AC_Materials.getRequiredLevel(recipe), 0, built.id .. " needs no level")
        check(AC_Materials.checkConservation(recipe), built.id .. " passes the conservation check")
        local consumed, created = AC_Materials.getRecipeUnits(recipe)
        for _, material in ipairs({ "copper", "zinc", "powder", "compound" }) do
            eq(consumed[material], nil, built.id .. " consumes no " .. material)
            eq(created[material], nil, built.id .. " creates no " .. material)
        end
        if recipe.loss then
            scrapRecipes = scrapRecipes + 1
            eq(created.brass * 2, consumed.brass, built.id .. " returns exactly half of the brass")
            check(created.brass < consumed.brass, built.id .. " loses brass")
            eq(recipe.outputs[1].item, "Base.BrassScrap", built.id .. " makes vanilla brass scrap")
            eq(#recipe.outputs, 1, built.id .. " makes nothing else")
            eq(recipe.benchTag, "AnySurfaceCraft", built.id .. " is cold work on a surface")
            eq(recipe.inputs[2].tags[1], "base:hammer", built.id .. " needs a hammer")
            eq(recipe.inputs[2].keep, true, built.id .. " keeps the hammer")
            eq(#recipe.inputs, 2, built.id .. " takes components and a hammer, nothing else")
            eq(recipe.inputs[1].flags, nil, built.id .. " accepts a mix of its components")
        else
            eq(consumed.brass, created.brass, built.id .. " casts scrap into an ingot with nothing lost or gained")
            eq(recipe.benchTag, "Furnace", built.id .. " casts where vanilla casts")
            eq(recipe.timedAction, nil, built.id .. " has no timed action, like vanilla furnace recipes")
        end
        -- No finished round, primer, bullet, die set or powder goes in.
        for _, input in ipairs(recipe.inputs) do
            for _, id in ipairs(input.items or {}) do
                local kind = AC_Calibres.identify(id)
                check(kind == nil or kind == "case", built.id .. " takes no " .. tostring(kind) .. " (" .. id .. ")")
                check(id ~= AC_Calibres.POWDER.item, built.id .. " takes no gunpowder")
            end
            for _, tag in ipairs(input.tags or {}) do
                check(tag ~= "base:ammo", built.id .. " takes no ammunition by tag")
            end
        end
    end
    eq(scrapRecipes, #groups, "every scrapping recipe is a lossy one")
    local recast = R(C.castId)
    eq(recast.inputs[4].count, 10, "the recast takes ten brass scrap")
    eq(recast.inputs[4].items[1], "Base.BrassScrap", "of the vanilla item")
    eq(recast.outputs[1].item, "Base.BrassIngot", "and yields the vanilla brass ingot")
    eq(recast.outputs[1].count, 1, "one of them")
    -- The recast is the copper casting recipe with brass in it.
    local copperCast = R("AmmoMaking_CastCopperIngot")
    eq(#recast.inputs, #copperCast.inputs, "the recast has the casting recipe's lines")
    for index, input in ipairs(copperCast.inputs) do
        if index ~= 4 then
            eq(RENDER.renderInput(recast.inputs[index]), RENDER.renderInput(input), "recast line " .. index .. " is the casting recipe's")
        end
    end
    eq(recast.time, copperCast.time, "the recast takes as long as casting copper")

    -- Manufacture -> recycle -> manufacture always ends with less brass.
    local function brassIn(inventory)
        local sum = 0
        for id, count in pairs(inventory) do
            local entry = U[id]
            if entry and entry.metal == "brass" then sum = sum + entry.units * count end
        end
        return sum
    end
    local function freshStock(ingots)
        return {
            ["Base.BrassIngot"] = ingots, ["base:charcoal"] = 100000, ["base:hammer"] = 1, ["base:tongs"] = 1, ["base:crudetongs"] = 1,
            ["base:metalworkingpunch"] = 1, ["Base.CeramicCrucible"] = 1, ["Base.ClayIngotMold"] = 1,
        }
    end
    local function drain(inventory, recipe)
        local crafts = 0
        while mirrorCraft(inventory, recipe) do crafts = crafts + 1 end
        return crafts
    end
    local forge, punch = R("AmmoMaking_ForgeSmallBrassSheets"), R("AmmoMaking_PunchBrassCaseCups")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local inv = freshStock(30)
        inv[calibre.dieSet] = 1
        local form = calibreRecipe(calibre, "case")
        local start = brassIn(inv)
        local previous, cycles, xp, firstPassXP = start, 0, 0, nil
        -- Until not one more case can be formed.
        while true do
            local crafted = 0
            local function run(recipe)
                local n = drain(inv, recipe)
                crafted = crafted + n
                xp = xp + n * AC_Materials.getRecipeXP(recipe)
                return n
            end
            run(forge)
            run(punch)
            local cases = run(form)
            if firstPassXP == nil then firstPassXP = xp end
            if cases == 0 then break end
            local formedBrass = brassIn(inv)
            eq(formedBrass, previous, calibre.id .. " cycle " .. (cycles + 1) .. ": making cases neither adds nor loses brass")
            local xpBeforeScrap = xp
            local scrapCrafts = 0
            for _, recipe in ipairs(AC_Materials.RECIPES) do
                if recipe.loss then scrapCrafts = scrapCrafts + run(recipe) end
            end
            -- Fewer cases than one batch: the brass stays as cases and the
            -- loop is over.
            if scrapCrafts == 0 then break end
            cycles = cycles + 1
            check(brassIn(inv) < formedBrass, calibre.id .. " cycle " .. cycles .. ": scrapping lost brass")
            run(recast)
            eq(xp, xpBeforeScrap, calibre.id .. " cycle " .. cycles .. ": scrapping and recasting earned no XP")
            local now = brassIn(inv)
            check(now < previous, calibre.id .. " cycle " .. cycles .. ": less brass than the cycle before (" .. previous .. " -> " .. now .. ")")
            check(now <= previous * AC_Recycling.getRecovery() + calibre.cupsPerCase * 5 * 4 + 100, calibre.id .. " cycle " .. cycles .. ": at most half survives, leftovers aside")
            previous = now
            check(cycles < 50, calibre.id .. ": the loop ends")
            if cycles >= 50 then break end
        end
        check(cycles >= 2, calibre.id .. ": the brass went round more than once (" .. cycles .. " cycles)")
        check(brassIn(inv) < start * 0.2, calibre.id .. ": most of the brass is gone at the end (" .. brassIn(inv) .. " of " .. start .. ")")
        -- The XP a fixed stock of brass can ever give is bounded: at most
        -- 1 / (1 - recovery) times what one pass gives.
        check(xp <= firstPassXP / (1 - AC_Recycling.getRecovery()) + 1e-9, calibre.id .. ": recycling at most doubles what one pass gives (" .. firstPassXP .. " -> " .. xp .. " XP)")

        -- Recycling is never the better way to train. A case that is
        -- scrapped and formed again, for ever, returns at most
        -- recovery / (1 - recovery) times the XP of making it once; loading
        -- it into a round instead gives the XP of its primer, its bullet,
        -- its powder and its assembly. The first must stay below the second.
        local primer = AC_Calibres.getPrimer(calibre.primerFamily)
        local brass = calibre.cupsPerCase * AC_Calibres.CONFIG.cupUnits
        local makeOnce = brass / 100 * AC_Materials.CONFIG.xpForgeBrassSheets
            + calibre.cupsPerCase / 2 * AC_Materials.CONFIG.xpPunchCaseCups
            + calibre.xp.case
        local recovery = AC_Recycling.getRecovery()
        local regained = makeOnce * recovery / (1 - recovery)
        local forgone = calibre.xp.assemble
            + primer.xp / primer.perSheet
            + calibre.xp.bullet / calibre.bulletsPerScrap
            + AC_Calibres.POWDER.xp * calibre.powderUses / AC_Calibres.POWDER.usesPerJar
        check(regained < forgone, calibre.id .. ": scrapping a case forgoes more XP than re-forming it can ever return (" .. regained .. " < " .. forgone .. ")")
        check(xp > firstPassXP, calibre.id .. ": the re-formed cases do earn their forming XP again, by design and at a cost")
        if calibre.id == "9mm" then
            print("  Recycling: 30 brass ingots formed into 9mm cases, scrapped and recast until nothing is left: " .. cycles .. " cycles, " .. start .. " -> " .. brassIn(inv) .. " units of brass, " .. firstPassXP .. " XP in one pass, " .. xp .. " XP with every round trip (x" .. string.format("%.2f", xp / firstPassXP) .. ")")
        end
    end

    -- The same for stock that never became a case: sheets and cups.
    for _, id in ipairs({ "AmmoMaking.SmallBrassSheet", "AmmoMaking.BrassCaseCup" }) do
        local inv = freshStock(0)
        inv[id] = 1000
        local start = brassIn(inv)
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            if recipe.loss then drain(inv, recipe) end
        end
        eq(brassIn(inv) * 2, start, id .. ": a thousand scrapped return exactly half")
        drain(inv, recast)
        eq(inv["Base.BrassIngot"], start / 2 / 100, id .. ": and recast into that many ingots")
    end

    -- A mix of components of one size pays for one craft together.
    local mixed = { ["AmmoMaking.BrassCaseCup"] = 2, ["AmmoMaking.Case9mm"] = 1, ["AmmoMaking.Case38Special"] = 1, ["base:hammer"] = 1 }
    check(mirrorCraft(mixed, R("AmmoMaking_ScrapBrass5")), "four mixed small components are one batch")
    eq(mixed["Base.BrassScrap"], 1, "and return one scrap")
    eq(mixed["AmmoMaking.BrassCaseCup"] + mixed["AmmoMaking.Case9mm"] + mixed["AmmoMaking.Case38Special"], 0, "all four are gone")
    check(not mirrorCraft({ ["AmmoMaking.BrassCaseCup"] = 3, ["base:hammer"] = 1 }, R("AmmoMaking_ScrapBrass5")), "three are not a batch")
    check(not mirrorCraft({ ["AmmoMaking.BrassCaseCup"] = 4 }, R("AmmoMaking_ScrapBrass5")), "no scrapping without a hammer")
    check(not mirrorCraft({ ["Base.BrassScrap"] = 9, ["base:charcoal"] = 4, ["base:crudetongs"] = 1, ["Base.CeramicCrucible"] = 1, ["Base.ClayIngotMold"] = 1 }, recast), "nine scrap are not an ingot")

    -- The validator refuses what it is there to refuse.
    local function withConfig(key, value)
        local saved = C[key]
        C[key] = value
        local text = table.concat(AC_Recycling.validate(), "; ")
        C[key] = saved
        return text
    end
    check(string.find(withConfig("scrapPerBatch", 2), "scrapping must lose brass: 20 units back for 20", 1, true) ~= nil, "a lossless scrap yield is refused")
    check(string.find(withConfig("scrapPerBatch", 3), "scrapping must lose brass: 30 units back for 20", 1, true) ~= nil, "a scrap yield that creates brass is refused")
    check(string.find(withConfig("scrapPerBatch", 1.5), "must be whole and positive", 1, true) ~= nil, "a fractional scrap yield is refused")
    check(string.find(withConfig("batchUnits", 10), "scrapping must lose brass: 10 units back for 10", 1, true) ~= nil, "a batch no bigger than its scrap is refused")
    check(string.find(withConfig("xp", 1), "recycling must award no XP, not 1", 1, true) ~= nil, "recycling XP is refused")
    check(string.find(withConfig("xp", 1), "AmmoMaking_ScrapBrass5 awards XP", 1, true) ~= nil, "and each recipe that would award it is named")
    check(string.find(withConfig("scrapPerIngot", 9), "an ingot of 100 units cannot be cast from 90 units of scrap", 1, true) ~= nil, "an ingot from nine scrap is refused")
    check(string.find(withConfig("scrapPerIngot", 9), "AmmoMaking_CastBrassIngotFromScrap creates brass: 100 units from 90", 1, true) ~= nil, "and the recast is named as creating brass")
    eq(#AC_Recycling.validate(), 0, "the live recycling model was restored")
    local function tampered(index, change)
        local list = AC_Recycling.buildRecipes()
        change(list[index])
        return table.concat(AC_Recycling.validate(list), "; ")
    end
    check(string.find(tampered(1, function(r) r.outputs[1].count = 2 end), "AmmoMaking_ScrapBrass5 loses no brass: 20 units from 20", 1, true) ~= nil, "a scrapping recipe that returns everything is refused")
    check(string.find(tampered(1, function(r) r.outputs[1].count = 3 end), "AmmoMaking_ScrapBrass5 creates brass: 30 units from 20", 1, true) ~= nil, "one that returns more than it took is refused")
    check(string.find(tampered(2, function(r) r.xp = 2 end), "AmmoMaking_ScrapBrass10 awards XP", 1, true) ~= nil, "one that awards XP is refused")
    check(string.find(tampered(1, function(r) table.insert(r.inputs[1].items, "AmmoMaking.Case308Win") end), "mixes components of different brass content", 1, true) ~= nil, "a line mixing brass sizes is refused")
    check(string.find(tampered(1, function(r) table.insert(r.inputs[1].items, "AmmoMaking.SmallPistolPrimer") end), "takes AmmoMaking.SmallPistolPrimer, which is not plain brass", 1, true) ~= nil, "a primer in a scrapping recipe is refused")
    check(string.find(tampered(1, function(r) table.insert(r.inputs[1].items, "Base.Bullets9mm") end), "takes Base.Bullets9mm, which is not plain brass", 1, true) ~= nil, "a finished round in a scrapping recipe is refused")
    check(string.find(tampered(3, function(r) r.outputs[1].item = "Base.CopperScrap" end), "makes Base.CopperScrap, which is not plain brass", 1, true) ~= nil, "brass cannot be scrapped into copper")
    check(string.find(tampered(1, function(r) table.remove(r.inputs[1].items, 1) end), "AmmoMaking.BrassCaseCup is taken by 0 scrapping recipes", 1, true) ~= nil, "a component no recipe takes is named")
    check(string.find(tampered(4, function(r) r.recycling = nil end), "is not marked as recycling", 1, true) ~= nil, "an unmarked recycling recipe is refused")

    -- The general conservation check agrees on the lossy rule.
    local scrap5 = R("AmmoMaking_ScrapBrass5")
    local function variant(change)
        local copy = {}
        for k, v in pairs(scrap5) do copy[k] = v end
        for k, v in pairs(change) do copy[k] = v end
        copy.id = scrap5.id .. "_tampered"
        return copy
    end
    local ok, reason = AC_Materials.checkConservation(variant({ outputs = { { count = 2, item = "Base.BrassScrap" } } }))
    check(not ok and string.find(reason, "must lose brass: 20 in, 20 out", 1, true) ~= nil, "a lossless scrapping recipe fails the conservation check: " .. tostring(reason))
    check(not AC_Materials.checkConservation(variant({ outputs = { { count = 3, item = "Base.BrassScrap" } } })), "one that creates brass fails it too")
    check(AC_Materials.checkConservation(variant({ outputs = { { count = 1, item = "Base.BrassScrap" } } })), "half is a loss")
    check(AC_Materials.checkConservation(variant({ loss = false, outputs = { { count = 2, item = "Base.BrassScrap" } } })), "the rule comes from the loss mark, not from the item")

    -- docs/LOOT_AND_RECYCLING.md carries the recycling table, rendered from
    -- the model.
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local document = readFile(ROOT .. "/docs/LOOT_AND_RECYCLING.md")
    local from = string.find(document, BALANCE.RECYCLING_START, 1, true)
    local _, to = string.find(document, BALANCE.RECYCLING_FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the document has the recycling table markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderRecyclingBlock(), "the recycling table equals the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceRecycling(document), document, "regenerating the recycling table changes nothing")
    local rendered = BALANCE.renderRecycling()
    for _, built in ipairs(recipes) do
        check(string.find(rendered, "| `" .. built.id .. "` |", 1, true) ~= nil, built.id .. " has a row in the recycling table")
    end
    local savedYield = C.scrapPerBatch
    C.scrapPerBatch = 2
    check(BALANCE.renderRecycling() ~= rendered, "a changed yield changes the rendered recycling table")
    C.scrapPerBatch = savedYield
    eq(BALANCE.renderRecycling(), rendered, "and restoring it restores the table")

    MOCK.debug = true
    -- The debug kit follows the model: one mixed batch per scrapping
    -- recipe, and exactly what one recast still needs.
    local recyclePlayer = MOCK.newPlayer({ square = MOCK.newSquare(7, 5, 0, GRASS) })
    MOCK.capturePrint(true)
    AC_GeologyDebug.spawnRecyclingKit(recyclePlayer)
    MOCK.capturePrint(false)
    local bin = recyclePlayer.inventory
    local mirror = { ["base:hammer"] = 1, ["base:crudetongs"] = 1, ["base:charcoal"] = bin:count("Base.Charcoal") }
    for _, entry in ipairs(AC_GeologyDebug.buildRecyclingKit()) do
        mirror[entry[1]] = (mirror[entry[1]] or 0) + entry[2]
        eq(bin:count(entry[1]) >= entry[2], true, "the recycling kit holds " .. entry[2] .. " of " .. entry[1])
        check(AC_Compat ~= nil and (string.sub(entry[1], 1, 5) == "Base." or declaredItems[entry[1]] ~= nil), "recycling kit item exists: " .. entry[1])
    end
    eq(bin:count("Base.BallPeenHammer"), 1, "a hammer for scrapping")
    eq(bin:count("Base.CeramicCrucible") + bin:count("Base.Tongs") + bin:count("Base.IronIngotMold"), 3, "and the furnace tools for the recast")
    local mixedGroups = 0
    for _, group in ipairs(AC_Recycling.buildGroups()) do
        local held, kinds = 0, 0
        for _, id in ipairs(group.items) do
            held = held + bin:count(id)
            if bin:count(id) > 0 then kinds = kinds + 1 end
        end
        eq(held, group.count, "exactly one batch for the " .. group.units .. "-unit scrapping recipe")
        if kinds > 1 then mixedGroups = mixedGroups + 1 end
        check(mirrorCraft(mirror, AC_Materials.getRecipe(AC_Recycling.CONFIG.idPrefix .. group.units)), "the kit's batch scraps (" .. group.units .. " units)")
        check(not mirrorCraft(mirror, AC_Materials.getRecipe(AC_Recycling.CONFIG.idPrefix .. group.units)), "and only once")
    end
    eq(mixedGroups, #AC_Recycling.buildGroups(), "every batch is a mix of two components")
    eq(mirror["Base.BrassScrap"], AC_Recycling.CONFIG.scrapPerIngot, "scrapping the kit leaves exactly ten brass scrap")
    check(mirrorCraft(mirror, AC_Materials.getRecipe(AC_Recycling.CONFIG.castId)), "which the kit's furnace tools and charcoal cast")
    eq(mirror["Base.BrassIngot"], 1, "into one ingot")
    eq(mirror["Base.BrassScrap"], 0, "with no scrap left")
    eq(mirror["base:charcoal"], 0, "and no charcoal left")
    MOCK.debug = false

    -- The module is data and arithmetic only.
    local source = readFile(LUA .. "shared/AC_Recycling.lua")
    check(string.find(source, "Events%.") == nil, "the recycling module registers no event")
    check(string.find(source, "getModData", 1, true) == nil, "and persists nothing")
end

------------------------------------------------
-- LOOT
------------------------------------------------
--
-- tests/vanilla_snapshot.lua is what tests/snapshot_vanilla.lua read from
-- the installed 42.20.4 files: which procedural loot lists exist and which
-- a container names. The sections below prove the mod's loot model against
-- that record and against a mocked ProceduralDistributions table. They do
-- NOT prove that the game spawns a die set: that is the engine's roll.

local VANILLA = dofile(ROOT .. "/tests/vanilla_snapshot.lua")

-- A stand-in for ProceduralDistributions.list holding the snapshot's lists,
-- each with as many placeholder entries as the real one has.
local function mockProceduralLists()
    local lists = {}
    for name, facts in pairs(VANILLA.loot.lists) do
        local items = {}
        for index = 1, facts.entries do
            table.insert(items, "Vanilla" .. index)
            table.insert(items, 1)
        end
        lists[name] = { rolls = facts.rolls, items = items }
    end
    return lists
end

-- A stand-in for Distributions[1] in which a container names every list
-- the snapshot records as referenced.
local function mockDistribution()
    local procList = {}
    for name, facts in pairs(VANILLA.loot.lists) do
        if facts.references > 0 then table.insert(procList, { name = name, min = 0, max = 99 }) end
    end
    return { gunstore = { displaycase = { procedural = true, procList = procList } }, all = { crate = { rolls = 1, items = { "Nails", 1 }, junk = { rolls = 1, items = {} } } } }
end

section("Die set loot: rare, centralised, only in lists the game uses")
do
    local C = AC_Loot.CONFIG
    eq(VANILLA.version, "42.20.4", "the snapshot is of the build the mod targets")
    eq(#AC_Loot.validate(), 0, "the loot model is sound: " .. table.concat(AC_Loot.validate(), "; "))
    eq(C.enabled, true, "die set loot is switched on")

    local dead = {}
    for _, name in ipairs(VANILLA.loot.unreferenced) do dead[name] = true end
    check(dead.GunStoreCounter and dead.GunStoreDisplayCase and dead.GunStoreShelf, "the three deprecated gun-store lists are recorded as unused")
    check(#VANILLA.loot.unreferenced > 100, "vanilla carries many lists no container names (" .. #VANILLA.loot.unreferenced .. ")")

    -- Every target is a list that exists, has entries and is named by a container.
    local targetNames = {}
    for _, target in ipairs(AC_Loot.TARGETS) do
        local facts = VANILLA.loot.lists[target.list]
        check(facts ~= nil, target.list .. " is a vanilla procedural list recorded in the snapshot")
        check(not dead[target.list], target.list .. " is not one of the unused lists")
        if facts then
            check(facts.references > 0, target.list .. " is named by a container (" .. facts.references .. ")")
            check(facts.entries > 0, target.list .. " has not been emptied")
            eq(facts.rolls, 4, target.list .. " rolls four times, as the documented chances assume")
        end
        check(not targetNames[target.list], target.list .. " is targeted once")
        targetNames[target.list] = true
    end
    eq(#AC_Loot.TARGETS, 4, "four lists, not everywhere")

    -- The entries: die sets only, each a real item with a forging recipe.
    local entries = AC_Loot.buildEntries()
    local perList, perItem, pairsSeen = {}, {}, {}
    for _, entry in ipairs(entries) do
        local kind, calibre = AC_Calibres.identify(entry.item)
        eq(kind, "dieSet", entry.item .. " is a die set")
        check(declaredItems[entry.item] ~= nil, entry.item .. " is declared in AC_Items.txt")
        eq(calibre and calibre.id, entry.calibre, entry.item .. " belongs to the calibre the entry names")
        check(targetNames[entry.list], entry.item .. " goes to a declared target (" .. entry.list .. ")")
        check(not pairsSeen[entry.list .. entry.item], entry.item .. " is in " .. entry.list .. " once")
        pairsSeen[entry.list .. entry.item] = true
        perList[entry.list] = (perList[entry.list] or 0) + entry.weight
        perItem[entry.item] = (perItem[entry.item] or 0) + 1

        local target
        for _, t in ipairs(AC_Loot.TARGETS) do if t.list == entry.list then target = t end end
        eq(entry.weight, C.tierWeight[calibre.lootTier] * target.scale, entry.item .. " weight is tier times scale in " .. entry.list)
        if target.classes then
            local wanted = {}
            for _, class in ipairs(target.classes) do wanted[class] = true end
            check(wanted[calibre.class], entry.item .. " is of a class " .. entry.list .. " takes")
        end
        check(entry.weight > 0 and entry.weight <= C.maxWeight, entry.item .. " weighs at most " .. C.maxWeight .. " in " .. entry.list)
        -- At most about a 4 % chance per container, at default settings.
        local chance = AC_Loot.chancePerContainer(entry.weight, VANILLA.loot.lists[entry.list].rolls)
        check(chance > 0 and chance < 4, entry.item .. " is rare in " .. entry.list .. " (" .. string.format("%.2f", chance) .. " %)")
    end
    for _, item in ipairs({ "AmmoMaking.SmallPistolPrimer", "AmmoMaking.BrassCaseCup", "AmmoMaking.SmallBrassSheet", "AmmoMaking.Case9mm", "AmmoMaking.Bullet9mm", "Base.GunPowder" }) do
        check(perItem[item] == nil, item .. " is not loot: components are manufactured")
    end

    -- Looting is an alternative, never the only way: every lootable die set
    -- is still forged from vanilla materials, and no recipe asks how a die
    -- set was obtained (an item type, kept, no flag).
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check((perItem[calibre.dieSet] or 0) >= 1, calibre.id .. " die set can be found")
        check((perItem[calibre.dieSet] or 0) <= C.maxListsPerCalibre, calibre.id .. " die set is in at most " .. C.maxListsPerCalibre .. " lists")
        check(pairsSeen["GunStoreAccessories" .. calibre.dieSet], calibre.id .. " die set is in the gun store list")
        local forge = AC_Materials.getRecipe("AmmoMaking_ForgeDieSet" .. calibre.suffix)
        check(forge ~= nil and forge.outputs[1].item == calibre.dieSet, calibre.id .. " die set can still be forged")
        for _, input in ipairs(forge.inputs) do
            for _, id in ipairs(input.items or {}) do
                eq(string.sub(id, 1, 5), "Base.", calibre.id .. " die set is forged from vanilla items only (" .. id .. ")")
            end
        end
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            for _, input in ipairs(recipe.inputs) do
                if input.items and input.items[1] == calibre.dieSet then
                    eq(#input.items, 1, recipe.id .. " names the die set by item type alone")
                    eq(input.keep, true, recipe.id .. " keeps the die set")
                    eq(input.flags, nil, recipe.id .. " puts no condition on the die set: found, forged or spawned all work")
                end
            end
        end
        -- Finding the tool does not open the recipes: the level gates stay.
        check(calibre.levels.case >= 1 and calibre.levels.assemble >= 3, calibre.id .. " recipes keep their Ammo Making levels whatever the die set's origin")
    end

    -- Pinned numbers: a change to any loot probability shows here.
    eq(C.maxWeight, 1, "no single die set weighs more than 1")
    eq(C.maxListWeight, 5, "all die sets of a list together weigh at most 5")
    eq(C.maxListsPerCalibre, 4, "a die set is in at most four lists")
    eq(C.tierWeight.common, 1, "common tier weight")
    eq(C.tierWeight.uncommon, 0.6, "uncommon tier weight")
    eq(C.tierWeight.rare, 0.3, "rare tier weight")
    check(C.tierWeight.common > C.tierWeight.uncommon and C.tierWeight.uncommon > C.tierWeight.rare, "the tiers are ordered")
    local pinned = { GunStoreAccessories = 5.0, GarageFirearms = 1.9, Hunter = 0.6, HuntingLockers = 0.6 }
    for name, expected in pairs(pinned) do
        check(math.abs((perList[name] or 0) - expected) < 1e-9, name .. " holds a die set weight of " .. expected .. " in all (got " .. tostring(perList[name]) .. ")")
        check(perList[name] <= C.maxListWeight, name .. " stays under the per-list cap")
        -- Next to what the list already holds, die sets are a sliver.
        check(perList[name] / VANILLA.loot.lists[name].weight < 0.03, name .. ": die sets add under 3 % to the list's weight")
    end
    eq(#entries, 9 + 5 + 4 + 4, "twenty-two entries in all")
    local tierCount = { common = 0, uncommon = 0, rare = 0 }
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local tier = calibre.lootTier
        tierCount[tier] = tierCount[tier] + 1
        if calibre.class ~= "pistol" then eq(tier, "rare", calibre.id .. ": rifle and shotgun dies are the rare find") end
        -- Handgun dies in the garage gun locker, long-gun dies with a hunter's things.
        eq(pairsSeen["GarageFirearms" .. calibre.dieSet] == true, calibre.class == "pistol", calibre.id .. ": in the garage list only if it is a handgun calibre")
        eq(pairsSeen["Hunter" .. calibre.dieSet] == true, calibre.class ~= "pistol", calibre.id .. ": in the hunter list only if it is a long-gun calibre")
        eq(pairsSeen["HuntingLockers" .. calibre.dieSet] == true, calibre.class ~= "pistol", calibre.id .. ": in the hunting lockers only if it is a long-gun calibre")
    end
    eq(AC_Calibres.get("9mm").lootTier, "common", "9mm dies are common")
    eq(AC_Calibres.get(".38 Special").lootTier, "common", ".38 Special dies are common")
    eq(AC_Calibres.get(".44 Magnum").lootTier, "uncommon", ".44 Magnum dies are uncommon")
    eq(tierCount.common, 2, "two common dies")
    eq(tierCount.uncommon, 3, "three uncommon dies")
    eq(tierCount.rare, 4, "four rare dies")
    check(math.abs(AC_Loot.chancePerContainer(1, 4) - 3.940399) < 1e-5, "a weight of 1 over four rolls is 3.94 % per container")
    check(math.abs(AC_Loot.chancePerContainer(5, 4) - 18.549375) < 1e-5, "all nine in the gun store list: 18.5 % that one display case holds a die set")

    -- The validator refuses what it is there to refuse.
    local function problemsWith(change)
        local targets, calibres = {}, {}
        for _, t in ipairs(AC_Loot.TARGETS) do
            table.insert(targets, { list = t.list, scale = t.scale, classes = t.classes })
        end
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local copy = {}
            for key, value in pairs(calibre) do copy[key] = value end
            table.insert(calibres, copy)
        end
        change(targets, calibres)
        return table.concat(AC_Loot.validate(targets, calibres), "; ")
    end
    local function refuses(what, change, text)
        local found = problemsWith(change)
        check(string.find(found, text, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
    end
    refuses("a scale above 1", function(t) t[1].scale = 4 end, "must have a scale above 0 and at most 1")
    refuses("a zero scale", function(t) t[2].scale = 0 end, "must have a scale above 0 and at most 1")
    refuses("an unknown class", function(t) t[2].classes = { "pistol", "cannon" } end, "names an unknown class cannon")
    refuses("a class named twice", function(t) t[3].classes = { "rifle", "rifle" } end, "names rifle twice")
    refuses("a list targeted twice", function(t) t[4].list = t[1].list end, "is targeted twice")
    refuses("a target without classes", function(t) t[2].classes = {} end, "names no classes")
    refuses("a target without a list", function(t) t[2].list = nil end, "a target has no list name")
    refuses("a calibre without a tier", function(_, calibres) calibres[8].lootTier = nil end, ".308 has no loot tier")
    refuses("an unknown tier", function(_, calibres) calibres[1].lootTier = "everywhere" end, "9mm has an unknown loot tier everywhere")
    refuses("a die set in no list", function(t) t[1].classes = { "rifle" } t[2].classes = { "shotgun" } end, "9mm die set is in no list")
    refuses("a die set in too many lists", function(t)
        for index = 1, 5 do t[index] = { list = "List" .. index, scale = 0.1 } end
    end, "9mm die set is in 5 lists, above 4")
    local saved = C.tierWeight.common
    C.tierWeight.common = 25
    local heavy = table.concat(AC_Loot.validate(), "; ")
    C.tierWeight.common = saved
    check(string.find(heavy, "tier common must weigh more than 0 and at most 1", 1, true) ~= nil, "a tier weight of 25 is refused: " .. heavy)
    local savedCap = C.maxListWeight
    C.maxListWeight = 4
    local crowded = table.concat(AC_Loot.validate(), "; ")
    C.maxListWeight = savedCap
    check(string.find(crowded, "die sets weigh 5 in GunStoreAccessories, above 4", 1, true) ~= nil, "a list over its cap is refused: " .. crowded)
    eq(#AC_Loot.validate(), 0, "the live loot model was restored")

    -- docs/LOOT_AND_RECYCLING.md carries the loot table, rendered from
    -- AC_Loot and the snapshot's roll counts; no weight is typed by hand.
    local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
    local document = readFile(ROOT .. "/docs/LOOT_AND_RECYCLING.md")
    local from = string.find(document, BALANCE.LOOT_START, 1, true)
    local _, to = string.find(document, BALANCE.LOOT_FINISH, 1, true)
    check(from ~= nil and to ~= nil and to > from, "the loot document has the loot table markers")
    eq(string.sub(document, from or 1, to or 1), BALANCE.renderLootBlock(VANILLA), "the loot table equals the rendered model (run tests/write_recipes.lua)")
    eq(BALANCE.replaceLoot(document, VANILLA), document, "regenerating the loot table changes nothing")
    local rendered = BALANCE.renderLoot(VANILLA)
    for _, target in ipairs(AC_Loot.TARGETS) do
        check(string.find(rendered, "| `" .. target.list .. "` | " .. target.where .. " |", 1, true) ~= nil, target.list .. " has a loot row")
    end
    local savedScale = AC_Loot.TARGETS[1].scale
    AC_Loot.TARGETS[1].scale = 0.25
    check(BALANCE.renderLoot(VANILLA) ~= rendered, "a changed scale changes the rendered loot table")
    AC_Loot.TARGETS[1].scale = savedScale
    eq(BALANCE.renderLoot(VANILLA), rendered, "and restoring it restores the table")
end

section("Die set loot registration (mocked ProceduralDistributions; the engine's parse and roll are not run)")
do
    local entries = AC_Loot.buildEntries()
    local lists = mockProceduralLists()
    local before = {}
    for name, list in pairs(lists) do before[name] = #list.items end

    local summary = AC_Loot.register(lists, mockDistribution())
    eq(summary.added, #entries, "every entry is inserted")
    eq(summary.present, 0, "nothing was there before")
    eq(#summary.missing + #summary.empty + #summary.unreferenced, 0, "every target exists, is used and has entries")
    for name, list in pairs(lists) do
        local added = 0
        for _, entry in ipairs(entries) do if entry.list == name then added = added + 1 end end
        eq(#list.items, before[name] + 2 * added, name .. " grew by its entries only")
        eq(#list.items % 2, 0, name .. " keeps the item, weight pairing")
        for index = 1, #list.items, 2 do
            eq(type(list.items[index]), "string", name .. " item name at an odd index")
            eq(type(list.items[index + 1]), "number", name .. " weight at an even index")
        end
    end
    for _, entry in ipairs(entries) do
        local count, weight = 0, nil
        local items = lists[entry.list].items
        for index = 1, #items, 2 do
            if items[index] == entry.item then
                count = count + 1
                weight = items[index + 1]
            end
        end
        eq(count, 1, entry.item .. " is in " .. entry.list .. " exactly once")
        eq(weight, entry.weight, entry.item .. " carries its weight in " .. entry.list)
    end
    for _, name in ipairs({ "GunStoreCounter", "GunStoreDisplayCase", "GunStoreShelf", "GunStoreAmmunition", "PoliceStorageAmmunition", "MetalWorkerTools" }) do
        eq(#lists[name].items, before[name], name .. " is left alone")
    end

    -- A second and third world load in the same Lua state add nothing.
    for _ = 1, 2 do
        local again = AC_Loot.register(lists, mockDistribution())
        eq(again.added, 0, "a repeated registration adds nothing")
        eq(again.present, #entries, "and finds every entry present")
    end
    for name, list in pairs(lists) do
        local added = 0
        for _, entry in ipairs(entries) do if entry.list == name then added = added + 1 end end
        eq(#list.items, before[name] + 2 * added, name .. " did not grow on re-registration")
    end

    -- A list this build does not have is never created.
    lists = mockProceduralLists()
    lists.Hunter = nil
    summary = AC_Loot.register(lists, mockDistribution())
    eq(lists.Hunter, nil, "a missing list is not created")
    eq(table.concat(summary.missing, ","), "Hunter", "and is reported once")
    eq(summary.added, #entries - 4, "the other lists still get their entries")

    -- A list vanilla has emptied, and a list no container names, are reported.
    lists = mockProceduralLists()
    lists.HuntingLockers.items = {}
    local distribution = mockDistribution()
    local procList = distribution.gunstore.displaycase.procList
    for index = #procList, 1, -1 do
        if procList[index].name == "GarageFirearms" then table.remove(procList, index) end
    end
    summary = AC_Loot.register(lists, distribution)
    eq(table.concat(summary.empty, ","), "HuntingLockers", "an emptied list is reported")
    eq(table.concat(summary.unreferenced, ","), "GarageFirearms", "a list no container names is reported")

    -- The dead lists of 42.20.4 would be caught at run time as well.
    local savedTargets = AC_Loot.TARGETS
    AC_Loot.TARGETS = { { list = "GunStoreDisplayCase", scale = 1, calibres = "all" } }
    lists = mockProceduralLists()
    summary = AC_Loot.register(lists, mockDistribution())
    AC_Loot.TARGETS = savedTargets
    eq(table.concat(summary.empty, ","), "GunStoreDisplayCase", "the deprecated display-case list is flagged as emptied")
    eq(table.concat(summary.unreferenced, ","), "GunStoreDisplayCase", "and as used by no container")

    -- Switched off, or with a broken model, nothing is touched.
    lists = mockProceduralLists()
    AC_Loot.CONFIG.enabled = false
    summary = AC_Loot.register(lists, mockDistribution())
    AC_Loot.CONFIG.enabled = true
    eq(summary.added, 0, "switched off: nothing is added")
    for name, list in pairs(lists) do eq(#list.items, before[name], name .. " untouched when switched off") end
    local savedWeight = AC_Loot.CONFIG.tierWeight.rare
    AC_Loot.CONFIG.tierWeight.rare = 50
    summary = AC_Loot.register(lists, mockDistribution())
    AC_Loot.CONFIG.tierWeight.rare = savedWeight
    eq(summary.added, 0, "a model the validator refuses adds nothing")
    for name, list in pairs(lists) do eq(#list.items, before[name], name .. " untouched by a refused model") end

    -- Malformed tables do not raise.
    check(pcall(AC_Loot.register, nil, nil), "no ProceduralDistributions: no error")
    eq(AC_Loot.register(nil, nil).unavailable, true, "and the summary says the tables were not there")
    eq(AC_Loot.register(mockProceduralLists(), mockDistribution()).unavailable, nil, "a normal registration is not marked unavailable")
    check(pcall(AC_Loot.register, { Hunter = "not a table", GarageFirearms = { items = 7 } }, "not a table"), "malformed lists: no error")
    eq(next(AC_Loot.findReferencedLists(nil, { "Hunter" })), nil, "no distribution table: nothing referenced")
    local cyclic = { a = {} }
    cyclic.a.back = cyclic
    cyclic.a.procList = { { name = "Hunter" }, "junk", { name = "Other" } }
    local found = AC_Loot.findReferencedLists(cyclic, { "Hunter" })
    check(found.Hunter == true and found.Other == nil, "the walk survives a cycle and finds only what was asked for")

    -- The event handler: the globals the engine provides at that moment.
    local savedProcedural, savedDistributions = ProceduralDistributions, Distributions
    ProceduralDistributions = { list = mockProceduralLists() }
    Distributions = { mockDistribution() }
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    Events.OnPreDistributionMerge.fire()
    Events.OnPreDistributionMerge.fire()
    MOCK.capturePrint(false)
    eq(AC_Loot.lastSummary.added, 0, "the second firing added nothing")
    eq(AC_Loot.lastSummary.present, #entries, "the first had added every entry")
    check(MOCK.printLogContains("[AmmoMaking] Die set loot: " .. #entries .. " entries added, 0 already present; lists missing: 0, empty: 0, used by no container: 0"), "the registration is logged once")
    local lines = 0
    for _, line in ipairs(MOCK.printLog) do
        if string.find(line, "Die set loot:", 1, true) then lines = lines + 1 end
    end
    eq(lines, 1, "the no-op second firing logs nothing")
    ProceduralDistributions, Distributions = nil, nil
    MOCK.capturePrint(true)
    local okFire = pcall(Events.OnPreDistributionMerge.fire)
    MOCK.capturePrint(false)
    check(okFire, "the handler does not raise without the loot tables")
    ProceduralDistributions, Distributions = savedProcedural, savedDistributions

    -- Where it is registered: once per world load, nowhere else.
    local source = readFile(LUA .. "shared/AC_Loot.lua")
    local registrations = 0
    for event in string.gmatch(source, "Events%.([%w_]+)%.Add") do
        registrations = registrations + 1
        eq(event, "OnPreDistributionMerge", "the loot handler listens to the pre-merge event")
    end
    eq(registrations, 1, "one registration")
    check(string.find(source, "ProceduralDistributions.list[", 1, true) == nil, "no list is indexed at file load")
end

------------------------------------------------
-- AMMO BOXES
------------------------------------------------

section("Ammo boxes: vanilla's own recipe takes handloaded rounds; the mod adds none")
do
    -- What the installed 42.20.4 recipes say (tests/vanilla_snapshot.lua).
    local A = VANILLA.ammo
    eq(A.boxInputLines, 1, "place_ammo_in_box has one input line: the rounds, no empty box, no tool")
    eq(A.boxIsExclusive, true, "that line is IsExclusive: one round type per box")
    eq(A.boxHasOnCreate, false, "it has no OnCreate: nothing is copied from the rounds onto the box")
    eq(A.gatherTakesAmmoTag, true, "GatherGunpowder takes anything tagged base:ammo")
    eq(A.gatherReturnsOneUse, true, "and returns one use of gunpowder")

    local boxedRounds = 0
    for _ in pairs(A.rounds) do boxedRounds = boxedRounds + 1 end
    eq(boxedRounds, #AC_Calibres.LIST, "vanilla boxes exactly as many round types as the mod makes")
    eq(#A.tagged, #AC_Calibres.LIST, "and tags exactly as many items as ammunition")

    local boxes = {}
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local name = calibre.id
        local facts = A.rounds[calibre.round]
        check(facts ~= nil, name .. ": vanilla's box recipe takes " .. calibre.round)
        if facts then
            eq(calibre.box, facts.box, name .. ": the model names vanilla's box item")
            eq(calibre.roundsPerBox, facts.perBox, name .. ": and its size")
            eq(facts.opensTo, calibre.round, name .. ": opening the box hands back the same round item")
            eq(facts.opensCount, facts.perBox, name .. ": as many as went in")
            check(facts.carton ~= "nil" and string.sub(facts.carton, 1, 5) == "Base.", name .. ": twelve boxes go into a vanilla carton (" .. facts.carton .. ")")
        end
        if facts then
            -- Weight: a round's parts weigh no more than vanilla's round, so
            -- carrying components is not a way round the weight of ammunition.
            local primer = AC_Calibres.getPrimer(calibre.primerFamily)
            local parts = tonumber(declaredItems[calibre.case].fields.Weight) + tonumber(declaredItems[calibre.bullet].fields.Weight) + tonumber(declaredItems[primer.item].fields.Weight)
            check(parts > 0 and parts <= facts.weight + 1e-9, name .. ": case, projectile and primer weigh no more than the vanilla round (" .. parts .. " against " .. tostring(facts.weight) .. ")")
            check(parts >= facts.weight / 3, name .. ": and at least a third of it (the rest is the powder)")
        end
        check(not boxes[calibre.box], name .. ": its box is no other calibre's")
        boxes[calibre.box] = true
        eq(string.sub(calibre.box, 1, 5), "Base.", name .. ": the box is a vanilla item")
        check(declaredItems[calibre.box] == nil, name .. ": the mod declares no box item")
        local tagged = false
        for _, itemType in ipairs(A.tagged) do
            if itemType == calibre.round then tagged = true end
        end
        check(tagged, name .. ": the round is tagged base:ammo, so vanilla can take it apart for powder")
    end

    -- A handloaded round is the vanilla item: the assembly recipe's output
    -- is the very type the box recipe names.
    for _, calibre in ipairs(AC_Calibres.LIST) do
        eq(calibreRecipe(calibre, "assemble").outputs[1].item, calibre.round, calibre.id .. ": assembly makes the item vanilla boxes")
    end

    -- The mod adds nothing of its own: no recipe makes, takes or names a
    -- box, and no mod item is tagged as ammunition (which would let
    -- vanilla's GatherGunpowder take a case or a primer apart for powder).
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        check(string.find(string.lower(recipe.id), "box", 1, true) == nil, recipe.id .. " is not a box recipe")
        for _, output in ipairs(recipe.outputs) do
            check(not boxes[output.item], recipe.id .. " does not make a box")
        end
        for _, input in ipairs(recipe.inputs) do
            for _, id in ipairs(input.items or {}) do
                check(not boxes[id], recipe.id .. " does not take a box")
            end
        end
    end
    local script = readFile(SCRIPTS .. "AC_Recipes.txt")
    check(string.find(script, "Box", 1, true) == nil and string.find(script, "Carton", 1, true) == nil, "the recipe script names no box or carton")
    for id, block in pairs(declaredItems) do
        check(string.find(";" .. tostring(block.fields.Tags or "") .. ";", ";base:ammo;", 1, true) == nil, id .. " is not tagged base:ammo")
    end

    -- The validator knows the box.
    local function problemsWith(change)
        local list = {}
        for _, calibre in ipairs(AC_Calibres.LIST) do
            local copy = {}
            for key, value in pairs(calibre) do copy[key] = value end
            table.insert(list, copy)
        end
        change(list)
        return table.concat(AC_Calibres.validate(list), "; ")
    end
    check(string.find(problemsWith(function(l) l[1].box = nil end), "9mm: the box must be a vanilla item", 1, true) ~= nil, "a calibre without a box is refused")
    check(string.find(problemsWith(function(l) l[1].box = "AmmoMaking.Box9mm" end), "9mm: the box must be a vanilla item", 1, true) ~= nil, "a mod box is refused")
    check(string.find(problemsWith(function(l) l[2].box = l[1].box end), "box item Base.Bullets9mmBox is already used by 9mm box", 1, true) ~= nil, "a shared box is refused")
    check(string.find(problemsWith(function(l) l[1].roundsPerBox = 0 end), "9mm: roundsPerBox must be a whole number of at least 1", 1, true) ~= nil, "an empty box is refused")
    check(string.find(problemsWith(function(l) l[1].roundsPerBox = 12.5 end), "roundsPerBox must be a whole number", 1, true) ~= nil, "a fractional box is refused")

    -- The game-start probe (mocked script manager).
    local function boxRun(change, restore)
        change()
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        local _, summary = AC_Compat.run(true)
        MOCK.capturePrint(false)
        restore()
        return summary
    end
    local ids = {}
    for _, recipe in ipairs(AC_Materials.RECIPES) do table.insert(ids, recipe.id) end
    MOCK.resetCraftRecipes(ids)
    AC_Materials.applySkillRequirements()
    AC_Loot.lastSummary = AC_Loot.register(mockProceduralLists(), mockDistribution())
    MOCK.players = { MOCK.newPlayer({ square = MOCK.newSquare(1, 1, 0, GRASS) }) }
    local clean = boxRun(function() end, function() end)
    check(MOCK.printLogContains("[AmmoMaking] OK: vanilla ammo boxes (9 rounds, boxed by vanilla's own recipe)"), "the boxes are probed at game start")
    local renamed = boxRun(function() MOCK.knownScriptItems["Base.556Box"] = nil end, function() MOCK.knownScriptItems["Base.556Box"] = true end)
    eq(renamed.warnings, clean.warnings + 1, "a box this build does not have is one warning")
    check(MOCK.printLogContains("WARNING: vanilla ammo boxes changed (missing Base.556Box; handloaded rounds may not be boxable, everything else is unaffected)"), "and it is named")
    check(MOCK.printLogContains("OK: calibre 5.56 complete"), "the calibre itself is still complete: making rounds does not need the box")
    local gone = boxRun(function() MOCK.craftRecipeScripts["place_ammo_in_box"] = nil end, function() MOCK.resetCraftRecipes(ids) AC_Materials.applySkillRequirements() end)
    eq(gone.warnings, clean.warnings + 1, "a missing box recipe is one warning")
    check(MOCK.printLogContains("missing recipe place_ammo_in_box"), "and the recipe is named")
    eq(AC_Compat.BOX_RECIPE, "place_ammo_in_box", "the probed recipe id is vanilla's")
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
    -- As after a world load: the loot registration has run.
    AC_Loot.lastSummary = AC_Loot.register(mockProceduralLists(), mockDistribution())

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local results, summary = AC_Compat.run(true)
    MOCK.capturePrint(false)
    eq(summary.warnings, 0, "no warnings with every API mocked")
    eq(summary.unverified, 0, "nothing unverified with a player present")
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.CopperOre"), "OK line format")
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.BrassIngot"), "vanilla brass ingot probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: AmmoMaking.ZincScrap"), "zinc scrap probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: recipe AmmoMaking_CastBrassIngots"), "brass recipe probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: recipe AmmoMaking_PunchBrassCaseCups"), "case cup recipe probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: calibre model (9 calibres, 4 primer families)"), "calibre model probed")
    for _, id in ipairs({ "Base.ShotgunShells", "AmmoMaking.Hull12Gauge", "AmmoMaking.ShotCharge12Gauge", "AmmoMaking.DieSet12Gauge", "Base.RippedSheets", "Base.CottonBalls" }) do
        check(MOCK.printLogContains("[AmmoMaking] OK: " .. id), "shell item probed: " .. id)
    end
    for _, calibre in ipairs(AC_Calibres.LIST) do
        check(MOCK.printLogContains("[AmmoMaking] OK: calibre " .. calibre.id .. " complete"), "calibre " .. calibre.id .. " reported complete")
        check(MOCK.printLogContains("[AmmoMaking] OK: " .. calibre.round), "vanilla round probed: " .. calibre.round)
        check(MOCK.printLogContains("[AmmoMaking] OK: recipe AmmoMaking_AssembleRound" .. calibre.suffix), "assembly recipe probed: " .. calibre.id)
    end
    check(MOCK.printLogContains("[AmmoMaking] OK: AmmoMaking.LargePistolPrimer"), "large pistol primer probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: AmmoMaking.SmallRiflePrimer"), "small rifle primer probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: AmmoMaking.LargeRiflePrimer"), "large rifle primer probed")
    for _, id in ipairs({ "Base.556Bullets", "Base.308Bullets", "Base.3030Bullets", "AmmoMaking.DieSet556NATO", "AmmoMaking.Case308Win", "AmmoMaking.Bullet3030Win" }) do
        check(MOCK.printLogContains("[AmmoMaking] OK: " .. id), "rifle item probed: " .. id)
    end
    check(MOCK.printLogContains("[AmmoMaking] OK: calibre 5.56 complete"), "5.56 reported complete")

    -- A rifle round missing on this build: its calibre is named, pistols
    -- and the other rifles are unaffected.
    MOCK.knownScriptItems["Base.3030Bullets"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local rR, sR = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.3030Bullets"] = true
    eq(sR.warnings, 2, "a missing rifle round is the item warning plus one calibre warning")
    check(MOCK.printLogContains("WARNING: calibre .30-30 incomplete (missing Base.3030Bullets; the other calibres are unaffected)"), "the incomplete rifle calibre is named")
    check(MOCK.printLogContains("OK: calibre .308 complete") and MOCK.printLogContains("OK: calibre 9mm complete"), "other rifle and pistol calibres stay complete")
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.GunPowder holds 10 uses"), "gunpowder uses probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: AC_CaseQuality effects"), "quality effects probed")

    -- Brass recycling: its own rule is checked at game start.
    check(MOCK.printLogContains("[AmmoMaking] OK: brass recycling (half of the brass comes back, no XP)"), "recycling reported sound")
    for _, id in ipairs({ "AmmoMaking_ScrapBrass5", "AmmoMaking_ScrapBrass10", "AmmoMaking_ScrapBrass15", "AmmoMaking_CastBrassIngotFromScrap" }) do
        check(MOCK.printLogContains("[AmmoMaking] OK: recipe " .. id), "recycling recipe probed: " .. id)
    end
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.BrassScrap"), "brass scrap probed")
    do
        local savedXP = AC_Recycling.CONFIG.xp
        AC_Recycling.CONFIG.xp = 3
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        local _, broken = AC_Compat.run(true)
        MOCK.capturePrint(false)
        AC_Recycling.CONFIG.xp = savedXP
        check(broken.warnings >= 1, "recycling that awards XP is a warning at game start")
        check(MOCK.printLogContains("WARNING: recycling: recycling must award no XP, not 3 (recycling may create brass or award XP)"), "and names the problem")
    end

    -- Die set loot: what the registration found when the world loaded.
    local function lootRun(change)
        local savedSummary = AC_Loot.lastSummary
        change()
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        local _, lootSummary = AC_Compat.run(true)
        MOCK.capturePrint(false)
        AC_Loot.lastSummary = savedSummary
        return lootSummary
    end
    local lootEntries = #AC_Loot.buildEntries()
    eq(lootRun(function() end).warnings, 0, "registered loot raises no warning")
    check(MOCK.printLogContains("[AmmoMaking] OK: die set loot (" .. lootEntries .. " entries in 4 lists)"), "the registered loot is reported")
    eq(lootRun(function() AC_Loot.lastSummary = nil end).warnings, 1, "loot that never registered is one warning")
    check(MOCK.printLogContains("WARNING: die set loot was not registered (OnPreDistributionMerge did not reach the mod; die sets can only be forged)"), "and says what follows")
    eq(lootRun(function()
        AC_Loot.lastSummary = { added = lootEntries - 4, present = 0, missing = { "Hunter" }, empty = { "GunStoreAccessories" }, unreferenced = { "GarageFirearms" } }
    end).warnings, 3, "a missing, an emptied and an unused list are one warning each")
    check(MOCK.printLogContains("WARNING: loot list Hunter does not exist on this build (die sets will not be found there; they can still be forged)"), "missing list named")
    check(MOCK.printLogContains("WARNING: loot list GunStoreAccessories has been emptied by vanilla"), "emptied list named")
    check(MOCK.printLogContains("WARNING: loot list GarageFirearms is used by no container"), "unused list named")
    eq(lootRun(function() AC_Loot.lastSummary = AC_Loot.register(nil, nil) end).warnings, 1, "loot tables that were not there are one warning")
    check(MOCK.printLogContains("WARNING: die set loot was not registered (ProceduralDistributions.list was not there when the loot tables were merged; die sets can only be forged)"), "and says so")
    AC_Loot.CONFIG.enabled = false
    eq(lootRun(function() AC_Loot.lastSummary = nil end).warnings, 0, "switched off: no warning")
    AC_Loot.CONFIG.enabled = true
    check(MOCK.printLogContains("[AmmoMaking] OK: die set loot is switched off"), "switched off is reported as such")
    local savedRare = AC_Loot.CONFIG.tierWeight.rare
    AC_Loot.CONFIG.tierWeight.rare = 9
    local brokenLoot = lootRun(function() end)
    AC_Loot.CONFIG.tierWeight.rare = savedRare
    check(brokenLoot.warnings >= 1, "a broken loot model is a warning")
    check(MOCK.printLogContains("WARNING: loot: tier rare must weigh more than 0 and at most 1 (no die set is added to any loot list)"), "and names the problem")

    -- Concise by default: a normal game start prints no OK line per probe,
    -- only the class summaries and the totals. -debug mode prints them all.
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    results, summary = AC_Compat.run(true)
    MOCK.capturePrint(false)
    eq(#summary.calibres, 3, "one summary entry per class")
    local wanted = { { "pistol", "Pistol calibres", 5 }, { "rifle", "Rifle calibres", 3 }, { "shotgun", "Shotgun shells", 1 } }
    for index, row in ipairs(wanted) do
        local tally = summary.calibres[index] or {}
        eq(tally.class, row[1], "summary " .. index .. " class")
        eq(tally.label, row[2], "summary " .. index .. " label")
        eq(tally.total, row[3], row[2] .. " total")
        eq(tally.complete, row[3], row[2] .. " complete")
        check(MOCK.printLogContains("[AmmoMaking] " .. row[2] .. ": " .. row[3] .. "/" .. row[3] .. " complete"), row[2] .. " summary line")
    end
    local classTotal = 0
    for _, tally in ipairs(summary.calibres) do classTotal = classTotal + tally.total end
    eq(classTotal, #AC_Calibres.LIST, "every calibre is counted in exactly one class")

    MOCK.debug = false
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local quietResults, quiet = AC_Compat.run()
    MOCK.capturePrint(false)
    eq(quiet.ok, summary.ok, "the quiet run performs the same probes")
    eq(#quietResults, #results, "and returns the same result list")
    check(not MOCK.printLogContains("[AmmoMaking] OK: "), "no OK lines outside -debug mode")
    check(MOCK.printLogContains("[AmmoMaking] Pistol calibres: 5/5 complete"), "the class summary is printed in a normal start")
    check(MOCK.printLogContains("Compatibility check: " .. summary.ok .. " ok, 0 warnings, 0 unverified"), "and the totals")
    eq(#MOCK.printLog, 4, "a clean normal start prints four lines: three classes and the totals")

    MOCK.knownScriptItems["Base.Bullets45"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.Bullets45"] = true
    check(MOCK.printLogContains("[AmmoMaking] WARNING: Base.Bullets45 not found"), "a missing dependency is still detailed in a quiet run")
    check(MOCK.printLogContains("WARNING: calibre .45 ACP incomplete"), "with its calibre")
    check(MOCK.printLogContains("[AmmoMaking] Pistol calibres: 4/5 complete"), "and the class count shows it")
    check(not MOCK.printLogContains("[AmmoMaking] OK: "), "still no OK lines")

    MOCK.debug = true
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run()
    MOCK.capturePrint(false)
    MOCK.debug = false
    check(MOCK.printLogContains("[AmmoMaking] OK: Base.CopperOre"), "-debug mode prints the OK lines without being asked")

    -- Once per world load: a second game start in the same world does
    -- nothing, a second world loaded in the same Lua session is checked.
    do
        local runs = 0
        local realRun = AC_Compat.run
        AC_Compat.run = function(...)
            runs = runs + 1
            return realRun(...)
        end
        MOCK.capturePrint(true)
        AC_Compat.hasRun = false
        Events.OnGameStart.fire()
        Events.OnGameStart.fire()
        local firstWorld = runs
        Events.OnInitGlobalModData.fire()
        local resetByWorldLoad = AC_Compat.hasRun
        Events.OnGameStart.fire()
        MOCK.capturePrint(false)
        AC_Compat.run = realRun
        eq(firstWorld, 1, "the check runs once per game start, not once per OnGameStart")
        eq(resetByWorldLoad, false, "a new world load clears the flag")
        eq(runs, 2, "so a second save in the same session is checked too")
        eq(AC_Compat.hasRun, true, "and is then marked as checked")
    end

    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run(false)
    MOCK.capturePrint(false)
    check(not MOCK.printLogContains("[AmmoMaking] OK: "), "an explicit false is quiet")

    -- A build without one of the wadding items: the shell is named, the
    -- cartridges are unaffected.
    MOCK.knownScriptItems["Base.CottonBalls"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local rS, sS = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.CottonBalls"] = true
    eq(sS.warnings, 2, "a missing wadding item is the item warning plus one calibre warning")
    check(MOCK.printLogContains("WARNING: calibre 12 Gauge incomplete (missing Base.CottonBalls; the other calibres are unaffected)"), "the shell is named with the missing wadding")
    check(MOCK.printLogContains("OK: calibre .44 Magnum complete") and MOCK.printLogContains("OK: calibre .308 complete"), "the cartridges stay complete")

    -- One calibre missing its round: named clearly, the others stay complete.
    MOCK.knownScriptItems["Base.Bullets44"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local rC, sC = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.Bullets44"] = true
    eq(sC.warnings, 2, "a missing vanilla round is the item warning plus one calibre warning")
    check(MOCK.printLogContains("WARNING: calibre .44 Magnum incomplete (missing Base.Bullets44; the other calibres are unaffected)"), "the incomplete calibre is named with what is missing")
    check(MOCK.printLogContains("OK: calibre 9mm complete") and MOCK.printLogContains("OK: calibre .45 ACP complete"), "the other calibres are still reported complete")

    -- A calibre whose recipes did not load.
    local savedForm = MOCK.craftRecipeScripts["AmmoMaking_FormCase357Magnum"]
    MOCK.craftRecipeScripts["AmmoMaking_FormCase357Magnum"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rC, sC = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.craftRecipeScripts["AmmoMaking_FormCase357Magnum"] = savedForm
    check(MOCK.printLogContains("WARNING: calibre .357 Magnum incomplete (missing AmmoMaking_FormCase357Magnum; the other calibres are unaffected)"), "a missing recipe makes its calibre incomplete")
    eq(sC.warnings, 2, "recipe warning plus calibre warning")

    -- A broken definition is reported by name, and nothing raises.
    local savedCase = AC_Calibres.LIST[5].case
    AC_Calibres.LIST[5].case = AC_Calibres.LIST[1].case
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local okModel, rM2, sM2 = pcall(AC_Compat.run, true)
    MOCK.capturePrint(false)
    AC_Calibres.LIST[5].case = savedCase
    check(okModel, "a broken calibre definition does not stop the check")
    check(MOCK.printLogContains("WARNING: calibre model: .44 Magnum: case item AmmoMaking.Case9mm is already used by 9mm case"), "the broken definition is named")
    check(sM2.warnings >= 1, "and counted as a warning")

    -- Gunpowder that holds another number of uses than the model assumes.
    MOCK.useDeltas["Base.GunPowder"] = 0.2
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rC, sC = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.useDeltas["Base.GunPowder"] = 0.1
    eq(sC.warnings, 1, "a different jar size is one WARNING")
    check(MOCK.printLogContains("WARNING: Base.GunPowder holds 5 uses, the mod assumes 10"), "the real jar size is reported")

    MOCK.useDeltaMethod = false
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rC, sC = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.useDeltaMethod = true
    eq(sC.warnings, 0, "no getUseDelta is not a warning")
    check(MOCK.printLogContains("UNVERIFIED: uses per jar of Base.GunPowder"), "it is reported as unverified")
    check(MOCK.printLogContains("[AmmoMaking] OK: AmmoMaking.BrassCaseCup"), "case cup item probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: CraftRecipe:addRequiredSkill"), "skill attachment method probed")
    check(MOCK.printLogContains("[AmmoMaking] OK: Ammo Making requirement on AmmoMaking_SmeltZincOre"), "attached requirement probed")

    -- Metallurgy recipe probes
    local savedRecipe = MOCK.craftRecipeScripts["AmmoMaking_CastZincIngot"]
    MOCK.craftRecipeScripts["AmmoMaking_CastZincIngot"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local rM, sM = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.craftRecipeScripts["AmmoMaking_CastZincIngot"] = savedRecipe
    eq(sM.warnings, 1, "a recipe the script manager does not know is one WARNING")
    check(MOCK.printLogContains("WARNING: recipe AmmoMaking_CastZincIngot not found (AC_Recipes.txt did not load; this recipe is unavailable)"), "missing recipe WARNING line")

    local bare = MOCK.newCraftRecipeScript("AmmoMaking_CastZincIngot")
    MOCK.craftRecipeScripts["AmmoMaking_CastZincIngot"] = bare
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rM, sM = AC_Compat.run(true)
    MOCK.capturePrint(false)
    eq(sM.warnings, 1, "a recipe without the requirement is one WARNING")
    check(MOCK.printLogContains("WARNING: Ammo Making requirement not attached to AmmoMaking_CastZincIngot"), "unattached requirement WARNING line")
    eq(#bare.requiredSkills, 0, "the compatibility check attaches nothing itself")
    MOCK.craftRecipeScripts["AmmoMaking_CastZincIngot"] = savedRecipe

    MOCK.craftRecipeLookup = false
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rM, sM = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.craftRecipeLookup = true
    eq(sM.warnings, 1, "no getCraftRecipe is one WARNING, not one per recipe")
    check(MOCK.printLogContains("WARNING: ScriptManager:getCraftRecipe missing"), "missing lookup WARNING line")

    local savedCallback = AC_Materials.onCastBrassIngots
    AC_Materials.onCastBrassIngots = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    rM, sM = AC_Compat.run(true)
    MOCK.capturePrint(false)
    AC_Materials.onCastBrassIngots = savedCallback
    eq(sM.warnings, 1, "a missing OnCreate callback is one WARNING")
    check(MOCK.printLogContains("WARNING: OnCreate callback AC_Materials.onCastBrassIngots missing (no Ammo Making XP for AmmoMaking_CastBrassIngots)"), "missing callback WARNING line")
    check(MOCK.printLogContains("Compatibility check:"), "summary line printed")

    MOCK.knownScriptItems["Base.CopperOre"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    results, summary = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.knownScriptItems["Base.CopperOre"] = true
    eq(summary.warnings, 1, "one warning for the missing item")
    check(MOCK.printLogContains("[AmmoMaking] WARNING: Base.CopperOre not found"), "WARNING line format")

    MOCK.players = {}
    MOCK.scriptManagerAvailable = false
    MOCK.capturePrint(true)
    local okRun, r2, s2 = pcall(AC_Compat.run, true)
    MOCK.capturePrint(false)
    MOCK.scriptManagerAvailable = true
    check(okRun, "run without player or script manager does not raise")
    check(s2.unverified > 0, "unavailable probes reported as unverified")
    eq(s2.warnings, 0, "unavailable probes are not warnings")

    MOCK.players = { player }
    MOCK.translations = fullTranslations
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run(true)
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("translation file loaded"), "loaded translation detected")
    check(MOCK.printLogContains("perk level descriptions resolve (spaced key)"), "spaced description key reported")

    MOCK.translations = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local r3, s3 = AC_Compat.run(true)
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("WARNING: translation file not loaded"), "missing translation file is a WARNING")
    check(MOCK.printLogContains("UNVERIFIED: perk level descriptions"), "unresolvable description keys are UNVERIFIED, not WARNING")
    eq(s3.warnings, 1, "only the translation warning without a translation table")
    MOCK.translations = fullTranslations

    -- Laboratory analyzer assumptions
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    AC_Compat.run(true)
    MOCK.capturePrint(false)
    check(MOCK.printLogContains("OK: analyzer world sprite (industry_03_61)"), "analyzer sprite probed")
    check(MOCK.printLogContains("OK: IsoGridSquare:AddSpecialObject"), "placement square method probed")
    check(MOCK.printLogContains("OK: IsoGridSquare:hasGridPower"), "grid power method probed")
    check(MOCK.printLogContains("OK: AC_LaboratoryAnalyzerObject loaded"), "building object load probed")
    check(MOCK.printLogContains("OK: IsoPlayer:getPlayerNum"), "placement player method probed")

    MOCK.knownSprites["industry_03_61"] = nil
    MOCK.clearPrintLog()
    MOCK.capturePrint(true)
    local r4, s4 = AC_Compat.run(true)
    MOCK.capturePrint(false)
    MOCK.knownSprites["industry_03_61"] = true
    eq(s4.warnings, 1, "missing analyzer sprite is one WARNING")
    check(MOCK.printLogContains("WARNING: analyzer world sprite industry_03_61 not found"), "sprite WARNING line")

    local realGetSprite = getSprite
    getSprite = nil
    MOCK.capturePrint(true)
    local r5, s5 = AC_Compat.run(true)
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
    local rW, sW = AC_Compat.run(true)
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
    local r6, s6 = AC_Compat.run(true)
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

    -- A fresh cartridge gets exactly the prototype's fields.
    local fresh = MOCK.newItem("AmmoMaking.TestCartridge")
    AmmoQuality.initialize(fresh)
    eq(fresh.modData.AmmoMakingQualityInitialized, true, "initialised flag")
    for key, default in pairs(AmmoQuality.DEFAULTS) do
        eq(fresh.modData[key], default, "fresh cartridge " .. key)
    end
    -- A preset survives a second initialise: only damaged fields are touched.
    fresh.modData.casingQuality, fresh.modData.powderLoad, fresh.modData.reloadCount = 35, 1.22, 5
    AmmoQuality.initialize(fresh)
    eq(fresh.modData.casingQuality, 35, "an existing value is kept")
    eq(fresh.modData.powderLoad, 1.22, "an existing powder load is kept")
    eq(fresh.modData.reloadCount, 5, "an existing reload count is kept")

    -- Damaged data (the flag set, fields missing or of the wrong type) used
    -- to raise "arithmetic on a nil value" in the menu click. It is repaired.
    player.perkLevel = 10
    for _, damage in ipairs({
        { "casingQuality", nil }, { "primerQuality", "high" }, { "powderLoad", "abc" },
        { "reloadCount", {} }, { "assemblyQuality", false }, { "projectileQuality", nil },
    }) do
        local broken = MOCK.newItem("AmmoMaking.TestCartridge")
        AmmoQuality.initialize(broken)
        broken.modData[damage[1]] = damage[2]
        local ok, result = pcall(AmmoInspection.inspect, player, broken)
        check(ok, "a cartridge with a damaged " .. damage[1] .. " can still be inspected: " .. tostring(result))
        eq(broken.modData[damage[1]], AmmoQuality.DEFAULTS[damage[1]], "the damaged " .. damage[1] .. " gets its default back")
        check(pcall(AmmoQuality.getQualityLabel, broken), "and its label can be read")
    end
    local emptied = MOCK.newItem("AmmoMaking.TestCartridge")
    emptied.modData.AmmoMakingQualityInitialized = true
    check(pcall(AmmoInspection.inspect, player, emptied), "a cartridge with the flag and no fields at all can be inspected")
    eq(emptied.modData.overallQuality, 100, "and reads as a default cartridge")
    player.perkLevel = 0
end

section("Component inspection: cases and loose handloaded rounds, read-only")
do
    local C = AC_CaseQuality.CONFIG
    local player = MOCK.newPlayer()

    -- An item whose ModData refuses every write: the inspection must only read.
    local function frozen(fullType, data)
        local item = MOCK.newItem(fullType)
        item.modData = setmetatable({}, {
            __index = data,
            __newindex = function(_, key) error("inspection wrote ModData." .. tostring(key)) end,
        })
        return item
    end

    for _, calibre in ipairs(AC_Calibres.LIST) do
        local name = calibre.id
        local case = frozen(calibre.case, { [C.flagKey] = true, [C.qualityKey] = 84 })
        local bare = frozen(calibre.case, {})
        local loaded = frozen(calibre.round, { [C.roundFlagKey] = true, [C.roundQualityKey] = 66 })
        local factory = frozen(calibre.round, {})

        eq(AmmoInspection.getComponent(case), "case", name .. ": a case can be inspected")
        eq(AmmoInspection.getComponent(bare), "case", name .. ": so can a case without a record")
        eq(AmmoInspection.getComponent(loaded), "round", name .. ": a handloaded round can be inspected")
        eq(AmmoInspection.getComponent(factory), nil, name .. ": a factory round has nothing to inspect")
        eq(AmmoInspection.getComponent(MOCK.newItem(calibre.bullet)), nil, name .. ": a bullet carries no quality")
        eq(AmmoInspection.getComponent(MOCK.newItem(calibre.dieSet)), nil, name .. ": nor does a die set")
        eq(AmmoInspection.inspectComponent(player, factory), nil, name .. ": no inspection for a factory round")

        -- A factory round has no ModData, and asking for it would make the
        -- engine create an empty table on a vanilla item. Right-clicking
        -- one must not.
        local untouched = MOCK.newItem(calibre.round)
        untouched.hasModData = function() return false end
        untouched.getModData = function() error("getModData was called on a round without ModData") end
        local okQuiet, kindQuiet = pcall(AmmoInspection.getComponent, untouched)
        check(okQuiet and kindQuiet == nil, name .. ": a round without ModData is not asked for it")
        check(pcall(fillInventoryMenu, player, untouched), name .. ": nor by the inventory menu")
        eq(AC_CaseQuality.getRoundQuality(untouched), nil, name .. ": it has no record")

        -- -debug mode adds the item type, the stored value and the schema's
        -- verdict, whatever the level; a normal game shows none of it.
        player.perkLevel = 0
        local quiet = AmmoInspection.inspectComponent(player, case)
        for _, line in ipairs(quiet.lines) do
            check(string.find(line, "[debug]", 1, true) == nil, name .. ": no debug line in a normal game")
            check(string.find(line, "84", 1, true) == nil, name .. ": and no stored number at level 0")
        end
        MOCK.debug = true
        local verbose = AmmoInspection.inspectComponent(player, case)
        local damaged = MOCK.newItem(calibre.round)
        damaged.modData[C.roundFlagKey], damaged.modData[C.roundQualityKey] = true, 9999
        local damagedLines = table.concat(AmmoInspection.inspectComponent(player, damaged).lines, " | ")
        MOCK.debug = false
        eq(#verbose.lines, #quiet.lines + 3, name .. ": -debug adds three lines")
        eq(verbose.lines[#verbose.lines - 2], "[debug] " .. calibre.case, name .. ": the item type")
        eq(verbose.lines[#verbose.lines - 1], "[debug] stored " .. C.qualityKey .. " = 84", name .. ": the stored value")
        eq(verbose.lines[#verbose.lines], "[debug] save data: ok", name .. ": and the schema's verdict")
        for index = 1, #quiet.lines do eq(verbose.lines[index], quiet.lines[index], name .. ": the player's lines are unchanged in -debug") end
        check(string.find(damagedLines, "[debug] stored " .. C.roundQualityKey .. " = 9999", 1, true) ~= nil, name .. ": -debug shows a damaged record as it is stored")
        check(string.find(damagedLines, "[debug] save data: " .. C.roundQualityKey .. ": outside 1..100", 1, true) ~= nil, name .. ": and says what is wrong with it: " .. damagedLines)

        player.perkLevel = 0
        local r = AmmoInspection.inspectComponent(player, case)
        eq(r.title, "Ammo Inspection", name .. ": title")
        eq(r.kind, "case", name .. ": kind")
        eq(r.calibre, name, name .. ": calibre")
        eq(r.lines[1], "Empty case: " .. name, name .. ": the calibre is always shown")
        eq(r.lines[2], "You do not know enough about ammunition to judge it.", name .. ": level 0 cannot judge quality")
        eq(#r.lines, 2, name .. ": two lines at level 0")

        player.perkLevel = 3
        r = AmmoInspection.inspectComponent(player, case)
        eq(r.lines[2], "Case quality: Very Good", name .. ": levels 1-4 see the label")
        eq(#r.lines, 2, name .. ": a case has two lines")
        eq(AmmoInspection.inspectComponent(player, bare).lines[2], "Case quality: not recorded", name .. ": a case without a record says so")

        player.perkLevel = 5
        r = AmmoInspection.inspectComponent(player, case)
        eq(r.lines[2], "Case quality: Very Good (84)", name .. ": level 5 sees the number")

        r = AmmoInspection.inspectComponent(player, loaded)
        eq(r.kind, "round", name .. ": round kind")
        eq(r.lines[1], "Handloaded round: " .. name, name .. ": round header")
        eq(r.lines[2], "Case quality: Average (66)", name .. ": the inherited casing quality")
        eq(r.lines[3], "This record stays with the loose round; loading or boxing it keeps only a count.", name .. ": the limit is stated")
        eq(#r.lines, 3, name .. ": a round has three lines")
        for _, line in ipairs(r.lines) do
            check(not string.find(line, "IGUI_", 1, true), name .. ": no raw translation key")
        end
        -- Nothing the mod does not store is shown.
        for _, line in ipairs(r.lines) do
            for _, word in ipairs({ "Primer", "Projectile", "Powder", "Failure", "Reliability", "Reload" }) do
                check(not string.find(line, word, 1, true), name .. ": no invented " .. word .. " line")
            end
        end
    end

    -- Malformed or out-of-range data is tolerated.
    local nine = AC_Calibres.get("9mm")
    player.perkLevel = 10
    local odd = frozen(nine.case, { [C.qualityKey] = "high" })
    eq(AmmoInspection.inspectComponent(player, odd).lines[2], "Case quality: not recorded", "a non-number quality counts as none")
    local huge = frozen(nine.case, { [C.qualityKey] = 900 })
    eq(AmmoInspection.inspectComponent(player, huge).lines[2], "Case quality: Excellent (100)", "an out-of-range quality is clamped for display")
    eq(AmmoInspection.getComponent(frozen(nine.round, { [C.roundQualityKey] = "x" })), nil, "a round with a malformed record counts as factory")
    eq(AmmoInspection.inspectComponent(player, frozen(nine.round, { [C.roundQualityKey] = 900 })).lines[2], "Case quality: Excellent (100)", "a round's out-of-range quality is clamped too")
    eq(AmmoInspection.inspectComponent(player, frozen(nine.round, { [C.roundQualityKey] = -5 })).lines[2], "Case quality: Dangerous (1)", "and never reads below the minimum")
    eq(AC_CaseQuality.getRoundQuality(frozen(nine.round, { [C.roundQualityKey] = 66 })), 66, "a sound round quality is returned as stored")
    eq(AmmoInspection.inspectComponent(nil, odd), nil, "no player")
    eq(AmmoInspection.inspectComponent(player, nil), nil, "no item")
    eq(AmmoInspection.getComponent({}), nil, "something that is not an item")
    eq(AmmoInspection.inspectComponent(player, MOCK.newItem("Base.Plank")), nil, "an unrelated item")

    -- The context menu: one entry for a case and for a handloaded round,
    -- none for a factory round or anything else, in normal and debug mode.
    local case = MOCK.newItem(nine.case)
    AC_CaseQuality.set(case, 72)
    local handloaded = MOCK.newItem(nine.round)
    handloaded.modData[C.roundFlagKey] = true
    handloaded.modData[C.roundQualityKey] = 61
    for _, debug in ipairs({ false, true }) do
        MOCK.debug = debug
        local mode = debug and "debug" or "normal"
        local ctx = fillInventoryMenu(player, case)
        local option = ctx:find("Inspect Ammunition")
        check(option ~= nil, mode .. ": inspect entry on a case")
        eq(#ctx.options, 1, mode .. ": and nothing else, not even in debug mode")
        local before = AC_AmmoInspectionUI.opened
        ctx:invoke(option)
        eq(AC_AmmoInspectionUI.opened, before + 1, mode .. ": the entry opens the inspection window")
        eq(AC_CaseQuality.get(case), 72, mode .. ": inspecting leaves the quality alone")
        eq(case.modData.AmmoMakingQualityInitialized, nil, mode .. ": and does not run the prototype's initialiser on a real item")

        ctx = fillInventoryMenu(player, handloaded)
        check(ctx:find("Inspect Ammunition") ~= nil, mode .. ": inspect entry on a handloaded round")
        eq(#ctx.options, 1, mode .. ": one entry")
        ctx = fillInventoryMenu(player, MOCK.newItem(nine.round))
        eq(#ctx.options, 0, mode .. ": no entry on a factory round")
        ctx = fillInventoryMenu(player, MOCK.newItem(nine.bullet))
        eq(#ctx.options, 0, mode .. ": no entry on a bullet")
        ctx = fillInventoryMenu(player, MOCK.newItem("Base.Plank"))
        eq(#ctx.options, 0, mode .. ": no entry on an unrelated item")
    end
    MOCK.debug = false
end

------------------------------------------------
-- RELEASE METADATA
------------------------------------------------

section("Release metadata: one version, a changelog entry, nothing shipped that should not be")
do
    local info = {}
    local infoText = readFile(ROOT .. "/mod/AmmoMaking/42/mod.info")
    for key, value in string.gmatch(infoText, "([%w_]+)=([^\r\n]*)") do info[key] = value end
    eq(info.id, "AmmoMaking", "mod.info id is the folder name")
    check(type(info.name) == "string" and info.name ~= "", "mod.info has a name")
    check(type(info.description) == "string" and info.description ~= "", "mod.info has a description")
    check(type(info.modversion) == "string" and string.match(info.modversion, "^%d+%.%d+%.%d+$") ~= nil, "mod.info has a MAJOR.MINOR.PATCH version (" .. tostring(info.modversion) .. ")")
    -- Below 1.0 until the chain has been made in game.
    check(tonumber(string.match(info.modversion or "", "^(%d+)")) == 0, "the version is a development version (0.x)")
    -- versionMin is the build the snapshots were taken from: GameVersion
    -- compares major and minor (42.20), so the patch number is always 0.
    local major, minor = string.match(ENGINE.version, "^(%d+)%.(%d+)")
    eq(info.versionMin, major .. "." .. minor .. ".0", "versionMin is the game build the mod was checked against")
    eq(info.require, nil, "the mod requires no other mod")
    eq(info.poster, nil, "no poster is named while there is no art to ship")
    eq(info.pack, nil, "no texture pack is named: the mod ships no tile sheet")
    eq(info.tiledef, nil, "and no tile definition")

    -- The version is written once. Other files may name it only where they
    -- are told to follow it.
    local changelog = readFile(ROOT .. "/CHANGELOG.md")
    check(string.find(changelog, "\n## " .. string.gsub(info.modversion, "%.", "%%.") .. "[ \n(]") ~= nil, "CHANGELOG.md has an entry for " .. info.modversion)
    local first = string.match(changelog, "\n## (%d+%.%d+%.%d+)")
    eq(first, info.modversion, "and it is the newest entry")
    for _, name in ipairs(MOCK.MOD_FILES) do
        check(string.find(readFile(LUA .. name .. ".lua"), info.modversion, 1, true) == nil, name .. ".lua does not repeat the version number")
    end

    -- The workshop text claims no dependency and no feature the mod lacks.
    local workshop = readFile(ROOT .. "/docs/WORKSHOP_DESCRIPTION.md")
    check(string.find(workshop, "NOT PUBLISHED", 1, true) ~= nil, "the Workshop material says it is not published")
    check(string.find(workshop, info.description, 1, true) ~= nil, "its short description is mod.info's")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        local shown = calibre.id == "12 Gauge" and "12 gauge" or calibre.id
        check(string.find(workshop, shown, 1, true) ~= nil, "the Workshop text names " .. calibre.id)
    end
    check(string.find(workshop, "fires exactly like a factory round", 1, true) ~= nil, "it says quality has no effect on shooting")
    check(string.find(workshop, "Not supported", 1, true) ~= nil, "it says multiplayer is not supported")
    eq(AC_Calibres.PRESS.enabled, false, "(the press is off, as the Workshop text says)")
end

------------------------------------------------
-- MOCK FIDELITY (last: it looks back over the whole run)
------------------------------------------------

section("Mock fidelity: the mocked engine answers as the installed build does")
do
    -- tests/engine_snapshot.lua is written by tools/pz_compat.py from the
    -- installed jar and scripts. Everything above ran against mocked engine
    -- objects that refuse a call no real overload takes. This section
    -- checks the refusal itself, and that the mock claims nothing the game
    -- does not have. It still proves nothing about what a method DOES.
    eq(ENGINE.version, VANILLA.version, "both snapshots were taken from the same game build")
    check(type(ENGINE.classes) == "table" and ENGINE.classes.InventoryItem ~= nil, "the snapshot holds Java signatures (it was written with javap available)")

    -- Kahlua's rules (LuaJavaInvoker.prepareCall), on the pure matcher.
    local takes = MOCK.overloadTakes
    eq(takes("InventoryItem,float,float,float", 4, { {}, 0.5, 0.5, 0 }), true, "an exact match is taken")
    eq(takes("InventoryItem,float,float,float", 3, { {}, 0.5, 0.5 }), false, "too few arguments are refused")
    eq(takes("InventoryItem,float,float,float", 5, { {}, 0.5, 0.5, 0, 1 }), false, "too many arguments are refused for a method with a receiver")
    eq(takes("static String", 2, { "x", 1 }), true, "a function without a receiver ignores extra arguments")
    eq(takes("static String", 0, {}), false, "but not missing ones")
    eq(takes("ItemTag", 1, { "Shovel" }), false, "a string is not an ItemTag (the hasTag failure of 42.20.4)")
    eq(takes("ItemTag", 1, { {} }), true, "an object is")
    eq(takes("ItemTag...", 0, {}), true, "varargs take none")
    eq(takes("ItemTag...", 3, { {}, {}, {} }), true, "or several")
    eq(takes("ItemTag...", 2, { {}, "x" }), false, "each of the right kind")
    eq(takes("int", 1, { 3 }), true, "a number is an int")
    eq(takes("int", 1, { "3" }), false, "a numeric string is not")
    eq(takes("int", 1, { nil }), false, "nil is not a primitive")
    eq(takes("String", 1, { nil }), true, "nil is accepted for an object")
    eq(takes("String", 1, { 5 }), false, "a number is not a String")
    eq(takes("boolean", 1, { true }), true, "a boolean is a boolean")
    eq(takes("boolean", 1, { 1 }), false, "a number is not")
    eq(takes("Object", 1, { 5 }), true, "anything is an Object")
    eq(takes("", 0, {}), true, "no parameters, no arguments")
    eq(takes("", 1, { 1 }), false, "no parameters, one argument: refused")

    -- The mocked objects refuse what the engine refuses.
    local refusedBefore = #MOCK.invalidEngineCalls
    local function refused(what, fn)
        local ok, message = pcall(fn)
        check(not ok and string.find(tostring(message), "No implementation found", 1, true) ~= nil, what .. " is refused (" .. tostring(message) .. ")")
    end
    local function accepted(what, fn)
        local ok, message = pcall(fn)
        check(ok, what .. " is accepted (" .. tostring(message) .. ")")
    end
    local item = MOCK.newItem("Base.PickAxe")
    local square = MOCK.newSquare(1, 1, 0, GRASS)
    local player = MOCK.newPlayer({ square = square })
    refused("item:hasTag(\"Shovel\")", function() item:hasTag("Shovel") end)
    accepted("item:hasTag(tag object)", function() item:hasTag({ enum = "ItemTag" }) end)
    refused("item:setCondition(\"full\")", function() item:setCondition("full") end)
    refused("item:getModData(1)", function() item:getModData(1) end)
    refused("square:hasWater(true)", function() square:hasWater(true) end)
    refused("square:AddWorldInventoryItem(item)", function() square:AddWorldInventoryItem(item) end)
    accepted("square:AddWorldInventoryItem(item, x, y, z)", function() square:AddWorldInventoryItem(item, 0.5, 0.5, 0) end)
    refused("player:getPerkLevel()", function() player:getPerkLevel() end)
    refused("player:getXp():AddXP(perk)", function() player:getXp():AddXP(Perks.Strength) end)
    accepted("player:getXp():AddXP(perk, amount)", function() player:getXp():AddXP(Perks.Strength, 5) end)
    refused("inventory:AddItem(5)", function() player:getInventory():AddItem(5) end)
    refused("inventory:containsID(\"7\")", function() player:getInventory():containsID("7") end)
    refused("getSpecificPlayer()", function() getSpecificPlayer() end)
    accepted("getSpecificPlayer(0)", function() getSpecificPlayer(0) end)
    refused("instanceItem(5)", function() instanceItem(5) end)
    refused("ModData.getOrCreate()", function() ModData.getOrCreate() end)
    refused("getScriptManager():FindItem()", function() getScriptManager():FindItem() end)
    refused("getGameTime():getWorldAgeHours(1)", function() getGameTime():getWorldAgeHours(1) end)
    -- The refusals above are the only ones of the whole run: no test and no
    -- mod code made a call the engine would not take.
    local provoked = #MOCK.invalidEngineCalls - refusedBefore
    eq(provoked, 14, "each refusal above was recorded")
    local unexpected = {}
    for index = 1, refusedBefore do
        -- Earlier sections provoke hasTag(string) on purpose, to pin that the
        -- mod's shovel and pickaxe detection never does.
        if string.sub(MOCK.invalidEngineCalls[index], 1, 21) ~= "InventoryItem.hasTag(" then
            table.insert(unexpected, MOCK.invalidEngineCalls[index])
        end
    end
    eq(#unexpected, 0, "no other call in the whole run was one the engine refuses: " .. table.concat(unexpected, " | "))

    -- The mock has no method the engine class lacks (the square:Is() that
    -- hid a crash was such a method).
    local unknown = {}
    for name in pairs(MOCK.unknownMockMethods) do table.insert(unknown, name) end
    table.sort(unknown)
    eq(#unknown, 0, "every method of a mocked engine object exists on the real class: " .. table.concat(unknown, ", "))
    for class, helpers in pairs(MOCK.HELPERS) do
        for name in pairs(helpers) do
            check(ENGINE.classes[class].methods[name] == nil, class .. "." .. name .. " is a test helper, not an engine method")
        end
    end
    for name, class in pairs(ENGINE.classes) do
        check(class.exposed ~= false and not class.missing, name .. " exists and is exposed to Lua on the recorded build")
    end

    -- What the mock says the game has, the game has.
    local missing = {}
    for id in pairs(MOCK.knownScriptItems) do
        if string.sub(id, 1, 5) == "Base." and not ENGINE.items[id] then table.insert(missing, id) end
    end
    table.sort(missing)
    eq(#missing, 0, "every vanilla item the mock knows is in the installed scripts: " .. table.concat(missing, ", "))
    for id in pairs(MOCK.knownScriptItems) do
        if string.sub(id, 1, 11) == "AmmoMaking." then
            check(declaredItems[id] ~= nil, "the mock's " .. id .. " is declared in AC_Items.txt")
        end
    end
    for id, delta in pairs(MOCK.useDeltas) do
        eq(ENGINE.items[id] and ENGINE.items[id].uses, math.floor(1 / delta + 0.5), "the mock's use count of " .. id .. " is the installed script's")
    end
    for sprite in pairs(MOCK.knownSprites) do
        check(type(ENGINE.sprites[sprite]) == "table", "the mock's sprite " .. sprite .. " is a defined tile")
    end
    for _, id in ipairs(MOCK.vanillaCraftRecipes) do
        check(type(ENGINE.recipes[id]) == "string", "the mock's vanilla recipe " .. id .. " is in the installed scripts")
    end
    -- The mock's shovel animation chooser mirrors a vanilla function that exists.
    eq(ENGINE.members["BuildingHelper.getShovelAnim"], true, "BuildingHelper.getShovelAnim exists in vanilla Lua")

    -- The model against the snapshot: what the game-start check will probe
    -- in game is already known to hold on the recorded build.
    for _, id in ipairs(AC_Compat.REQUIRED_ITEMS) do
        if string.sub(id, 1, 5) == "Base." then
            check(ENGINE.items[id] ~= nil and ENGINE.items[id] ~= false, id .. " (AC_Compat.REQUIRED_ITEMS) exists on the recorded build")
        end
    end
    eq(ENGINE.items[AC_Calibres.POWDER.item].uses, AC_Calibres.POWDER.usesPerJar, "a jar of gunpowder holds the uses the model assumes")
    for _, calibre in ipairs(AC_Calibres.LIST) do
        eq(ENGINE.ammoTypes[calibre.ammoType], calibre.round, calibre.id .. ": the engine's ammo type names the round the mod makes")
        local taken = false
        for _, group in ipairs({ ENGINE.firearms, ENGINE.magazines }) do
            for _, entry in pairs(group) do
                if entry.ammoType == calibre.ammoType then taken = true end
            end
        end
        check(taken, calibre.id .. ": a vanilla firearm or magazine takes it")
    end
    for _, recipe in ipairs(AC_Materials.RECIPES) do
        local tag = ENGINE.benchTags[recipe.benchTag]
        check(tag ~= nil and (tag.stations > 0 or tag.vanillaRecipes > 0), recipe.id .. ": its station tag " .. tostring(recipe.benchTag) .. " is one vanilla provides")
        if recipe.timedAction then
            eq(ENGINE.timedActions[recipe.timedAction], true, recipe.id .. ": its timed action exists")
        end
        for _, input in ipairs(recipe.inputs) do
            for _, tag in ipairs(input.tags or {}) do
                check((ENGINE.itemTags[tag] or 0) > 0, recipe.id .. ": a vanilla item carries " .. tag)
            end
        end
    end
    -- The press's own names: the tag is free, the timed action is vanilla's.
    local pressTag = ENGINE.benchTags[AC_Calibres.PRESS.benchTag]
    check(pressTag ~= nil and pressTag.stations == 0 and pressTag.vanillaRecipes == 0, "the press's bench tag is used by nothing in vanilla")
    eq(ENGINE.timedActions[AC_Calibres.PRESS.timedAction], true, "the press's timed action exists in vanilla")
    local analyzerTile = ENGINE.sprites[AC_LaboratoryAnalyzer.CONFIG.worldSprite]
    check(type(analyzerTile) == "table" and analyzerTile.entity == false and analyzerTile.moveable == false, "the analyzer's tile exists, is claimed by no entity and is not a vanilla moveable")
end

------------------------------------------------
-- SUMMARY
------------------------------------------------

print("")
print("Passed: " .. passed .. "  Failed: " .. failed)
if failed > 0 then
    os.exit(1)
end
