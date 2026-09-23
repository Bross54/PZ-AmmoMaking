-- Ammo Making - mocked unit tests for the geology / deposit / mining loop
--
-- Runs outside Project Zomboid with plain Lua 5.1:
--
--     lua5.1 tests/run_tests.lua
--
-- The Project Zomboid API is mocked just enough to load the shared
-- modules and the mining timed action. These tests verify Lua-level
-- logic (reserves, depletion, persistence, validation, action flow).
-- They cannot verify vanilla item ids, animations, sounds or Java
-- behaviour; that still needs an in-game test.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$") or "."
local LUA = ROOT .. "/mod/AmmoMaking/42/media/lua/"

------------------------------------------------
-- MINIMAL TEST FRAMEWORK
------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function check(condition, message)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(failures, message)
        print("  FAIL: " .. tostring(message))
    end
end

local function eq(actual, expected, message)
    check(actual == expected,
        message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function section(name)
    print("== " .. name)
end

------------------------------------------------
-- PZ API MOCKS
------------------------------------------------

local MOCK = {}

MOCK.saveName = "TestSave"
MOCK.modDataRegistry = {}
MOCK.randomSequence = nil   -- optional deterministic override
MOCK.worldHours = 0

-- Global ModData
ModData = {}
function ModData.getOrCreate(key)
    if not MOCK.modDataRegistry[key] then
        MOCK.modDataRegistry[key] = {}
    end
    return MOCK.modDataRegistry[key]
end
function ModData.exists(key)
    return MOCK.modDataRegistry[key] ~= nil
end

-- Deep copy that only allows what Kahlua global ModData can persist
-- (string/number keys, string/number/boolean/table values). Used to
-- simulate a save + reload.
local function persistCopy(value, path)
    path = path or "root"
    local t = type(value)
    if t == "number" or t == "string" or t == "boolean" then
        return value
    end
    if t ~= "table" then
        error("unpersistable value at " .. path .. ": " .. t)
    end
    local copy = {}
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            error("unpersistable key at " .. path .. ": " .. kt)
        end
        copy[k] = persistCopy(v, path .. "." .. tostring(k))
    end
    return copy
end

function MOCK.simulateSaveReload()
    local copy = {}
    for key, value in pairs(MOCK.modDataRegistry) do
        copy[key] = persistCopy(value, key)
    end
    MOCK.modDataRegistry = copy
end

-- World / time
function getWorld()
    return {
        getWorld = function() return MOCK.saveName end,
        isHydroPowerOn = function() return false end,
    }
end
function getGameTime()
    return {
        getWorldAgeHours = function() return MOCK.worldHours end,
        getMultiplier = function() return 1 end,
    }
end
function getTimestamp() return 0 end

-- Random
local rngState = 12345
function ZombRand(a, b)
    if MOCK.randomSequence then
        local v = table.remove(MOCK.randomSequence, 1)
        if v ~= nil then return v end
    end
    rngState = (rngState * 1103515245 + 12345) % 2147483648
    if b then
        return a + (rngState % (b - a))
    end
    return rngState % a
end
function ZombRandFloat(a, b)
    return a + (b - a) * 0.5
end

-- Events
Events = setmetatable({}, {
    __index = function(t, name)
        local ev = { handlers = {} }
        function ev.Add(fn) table.insert(ev.handlers, fn) end
        function ev.Remove(fn) end
        function ev.fire(...)
            for _, fn in ipairs(ev.handlers) do fn(...) end
        end
        rawset(t, name, ev)
        return ev
    end,
})

-- Items
local nextItemId = 1
local knownScriptItems = {
    ["Base.CopperOre"] = true,
    ["AmmoMaking.ZincOre"] = true,
    ["AmmoMaking.GeologicalSample"] = true,
    ["Base.PickAxe"] = true,
    ["Base.PickAxeForged"] = true,
    ["Base.PickAxeHead"] = true,
    ["Base.Shovel"] = true,
}

local function newItem(fullType, opts)
    opts = opts or {}
    local item = {
        fullType = fullType,
        condition = opts.condition or 10,
        conditionMax = 10,
        modData = {},
        id = nextItemId,
        container = nil,
        name = fullType,
    }
    nextItemId = nextItemId + 1
    function item:getFullType() return self.fullType end
    function item:getID() return self.id end
    function item:getModData() return self.modData end
    function item:getCondition() return self.condition end
    function item:setCondition(v) self.condition = v end
    function item:isBroken() return self.condition <= 0 end
    function item:getContainer() return self.container end
    function item:setJobType() end
    function item:setJobDelta() end
    function item:setCustomName() end
    function item:setName(n) self.name = n end
    function item:hasTag() return false end
    return item
end
MOCK.newItem = newItem

function instanceItem(fullType)
    if not knownScriptItems[fullType] then return nil end
    return newItem(fullType)
end
InventoryItemFactory = {
    CreateItem = function(fullType) return instanceItem(fullType) end,
}
function getScriptManager()
    return {
        FindItem = function(_, fullType)
            if knownScriptItems[fullType] then return {} end
            return nil
        end,
    }
end

-- Java ArrayList-like
local function arrayList(items)
    local list = { items = items }
    function list:size() return #self.items end
    function list:get(i) return self.items[i + 1] end
    return list
end

-- Inventory
local function newInventory()
    local inv = { items = {}, dirty = false }
    function inv:AddItem(fullType)
        local item = instanceItem(fullType)
        if item then
            item.container = self
            table.insert(self.items, item)
        end
        return item
    end
    function inv:addItem(item)
        item.container = self
        table.insert(self.items, item)
        return item
    end
    function inv:Remove(item)
        for i, it in ipairs(self.items) do
            if it == item then table.remove(self.items, i) break end
        end
        item.container = nil
    end
    function inv:getItemsFromFullType(fullType, recurse)
        local found = {}
        for _, it in ipairs(self.items) do
            if it.fullType == fullType then table.insert(found, it) end
        end
        return arrayList(found)
    end
    function inv:containsID(id)
        for _, it in ipairs(self.items) do
            if it.id == id then return true end
        end
        return false
    end
    function inv:getItemById(id)
        for _, it in ipairs(self.items) do
            if it.id == id then return it end
        end
        return nil
    end
    function inv:setDrawDirty(v) self.dirty = v end
    return inv
end

-- Player
local function newPlayer(opts)
    opts = opts or {}
    local player = {
        inventory = newInventory(),
        primary = nil,
        secondary = nil,
        xpLog = {},
        perkLevel = opts.perkLevel or 0,
        x = opts.x or 100,
        y = opts.y or 100,
        z = 0,
        square = opts.square,
    }
    function player:getInventory() return self.inventory end
    function player:getPrimaryHandItem() return self.primary end
    function player:getSecondaryHandItem() return self.secondary end
    function player:getXp()
        local p = self
        return {
            AddXP = function(_, perk, amount)
                table.insert(p.xpLog, amount)
            end,
        }
    end
    function player:getPerkLevel(perk) return self.perkLevel end
    function player:getX() return self.x end
    function player:getY() return self.y end
    function player:getZ() return self.z end
    function player:getSquare() return self.square end
    function player:getCurrentSquare() return self.square end
    function player:faceLocation() end
    function player:isTurning() return false end
    function player:shouldBeTurning() return false end
    function player:setMetabolicTarget() end
    function player:addCombatMuscleStrain() end
    function player:getEmitter() return nil end
    function player:isTimedActionInstant() return false end
    function player:totalXP()
        local total = 0
        for _, v in ipairs(self.xpLog) do total = total + v end
        return total
    end
    return player
end
MOCK.newPlayer = newPlayer

-- Squares
local function newSquare(x, y, z, spriteName, opts)
    opts = opts or {}
    local square = {
        x = x, y = y, z = z or 0,
        spriteName = spriteName,
        room = opts.room,
        water = opts.water or false,
        worldItems = {},
        properties = {},
    }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return self.room end
    function square:getFloor()
        if not self.spriteName then return nil end
        local s = self
        return {
            getSprite = function()
                return { getName = function() return s.spriteName end }
            end,
        }
    end
    function square:AddWorldInventoryItem(item, ox, oy, oz)
        table.insert(self.worldItems, item)
        return { getItem = function() return item end }
    end
    function square:getWorldObjects() return arrayList({}) end
    function square:hasWater() return self.water end
    function square:Is(flag)
        if flag == "water" then return self.water end
        return false
    end
    function square:haveElectricity() return false end
    return square
end
MOCK.newSquare = newSquare

IsoFlagType = { water = "water", exterior = "exterior" }

-- Misc globals used by client files
function isClient() return false end
function isServer() return false end
function isDebugEnabled() return MOCK.debug == true end
function getSpecificPlayer(i) return MOCK.players and MOCK.players[i + 1] or nil end
function addSound() end
function getText(key) return key end
HaloTextHelper = { log = {} }
function HaloTextHelper.addText(player, text)
    table.insert(HaloTextHelper.log, text)
end
Metabolics = { DiggingSpade = "DiggingSpade" }
Perks = { Strength = "Strength", Crafting = "Crafting" }
BuildingHelper = {
    getShovelAnim = function(item) return "DigShovel" end,
}
luautils = {
    walkAdj = function(player, square) return MOCK.walkAdjResult ~= false end,
}
ISWorldObjectContextMenu = {
    addToolTip = function() return {} end,
}
ISTimedActionQueue = { queue = {} }
function ISTimedActionQueue.add(action)
    table.insert(ISTimedActionQueue.queue, action)
    return action
end
function require(name) end

-- Skill (AC_AmmoMakingSkill needs PerkFactory; use an equivalent mock)
AmmoMakingSkill = {}
function AmmoMakingSkill.addXP(player, amount)
    if not player or not amount or amount <= 0 then return end
    player:getXp():AddXP("AmmoMaking", amount)
end
function AmmoMakingSkill.getLevel(player)
    return player and player.perkLevel or 0
end

-- Timed action base
ISBaseTimedAction = {}
ISBaseTimedAction.__index = ISBaseTimedAction
function ISBaseTimedAction:derive(name)
    local cls = {}
    cls.__index = cls
    cls.Type = name
    setmetatable(cls, { __index = ISBaseTimedAction })
    return cls
end
function ISBaseTimedAction:new(character)
    local o = {}
    setmetatable(o, self)
    o.character = character
    o.completed = false
    o.stopped = false
    return o
end
function ISBaseTimedAction:setActionAnim() end
function ISBaseTimedAction:setOverrideHandModels() end
function ISBaseTimedAction:getJobDelta() return 0 end
function ISBaseTimedAction:perform() self.completed = true end
function ISBaseTimedAction:stop() self.stopped = true end
function ISBaseTimedAction:forceStop() self.stopped = true end

-- Context menu mock
local function newContext()
    local ctx = { options = {} }
    function ctx:addOption(name, target, fn, ...)
        local option = { name = name, target = target, fn = fn, args = { ... } }
        table.insert(self.options, option)
        return option
    end
    function ctx:find(prefix)
        for _, o in ipairs(self.options) do
            if o.name:sub(1, #prefix) == prefix then return o end
        end
        return nil
    end
    function ctx:invoke(option)
        return option.fn(option.target, unpack(option.args))
    end
    return ctx
end
MOCK.newContext = newContext

------------------------------------------------
-- LOAD THE MOD (shared then client, like PZ)
------------------------------------------------

-- Silence the mod's load messages
local realPrint = print
local quiet = true
print = function(...)
    if not quiet then realPrint(...) end
end

local function loadMod()
    dofile(LUA .. "shared/AC_Text.lua")
    dofile(LUA .. "shared/AC_WorldData.lua")
    dofile(LUA .. "shared/AC_Geology.lua")
    dofile(LUA .. "shared/AC_GeologySampling.lua")
    dofile(LUA .. "shared/AC_LaboratoryAnalyzer.lua")
    dofile(LUA .. "shared/AC_Deposits.lua")
    dofile(LUA .. "shared/AC_Mining.lua")
    dofile(LUA .. "client/AC_MineOreAction.lua")
    dofile(LUA .. "client/AC_MiningContextMenu.lua")
end

-- Simulates PZ reloading Lua state for a fresh game session.
local function resetLuaState()
    AC_Text = nil
    AC_WorldData = nil
    AC_Geology = nil
    AC_LaboratoryAnalyzer = nil
    AC_GeologySampling = nil
    AC_Deposits = nil
    AC_Mining = nil
    AC_MineOreAction = nil
    Events = setmetatable({}, getmetatable(Events))
end

loadMod()
quiet = false
print = realPrint

------------------------------------------------
-- HELPERS
------------------------------------------------

local GRASS = "blends_natural_01_16"

local function findTile(metal, minReserve, maxReserve)
    for x = 0, 3000 do
        for y = 0, 60 do
            local r = AC_Deposits.getInitialReserve(x, y, metal)
            if r >= minReserve and (not maxReserve or r <= maxReserve) then
                return x, y, r
            end
        end
    end
    return nil
end

local function makeSample(x, y, rank, copperGrade, zincGrade)
    local sample = newItem("AmmoMaking.GeologicalSample")
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
    local pick = newItem(fullType or "Base.PickAxe", { condition = condition })
    player.inventory:addItem(pick)
    player.primary = pick
    return pick
end

------------------------------------------------
-- TESTS
------------------------------------------------

section("Deterministic reserves")
do
    local cx, cy, cr = findTile("copper", 2)
    check(cx ~= nil, "found a copper tile with reserve >= 2")
    local zx, zy, zr = findTile("zinc", 1)
    check(zx ~= nil, "found a zinc tile with reserve >= 1")

    eq(AC_Deposits.getInitialReserve(cx, cy, "copper"), cr, "reserve stable on repeat query")
    eq(AC_Deposits.getInitialReserve(cx + 0.7, cy + 0.2, "copper"), cr, "float coordinates floor to same tile")
    eq(AC_Deposits.getReserveForConcentration(0), 0, "None -> 0")
    eq(AC_Deposits.getReserveForConcentration(10), 0, "Trace -> 0")
    eq(AC_Deposits.getReserveForConcentration(20), 1, "Poor -> 1")
    eq(AC_Deposits.getReserveForConcentration(40), 1, "Moderate -> 1")
    eq(AC_Deposits.getReserveForConcentration(60), 2, "Good -> 2")
    eq(AC_Deposits.getReserveForConcentration(75), 3, "Rich -> 3")
    eq(AC_Deposits.getReserveForConcentration(90), 4, "Very Rich -> 4")
    eq(AC_Deposits.getInitialReserve(cx, cy, "gold"), 0, "unknown metal -> 0")
    eq(AC_Deposits.getWorkedTileCount(), 0, "nothing stored for untouched ground")
end

section("Extraction, depletion and XP")
do
    local cx, cy, cr = findTile("copper", 2, 2)
    local square = newSquare(cx, cy, 0, GRASS)
    local player = newPlayer({ square = square })
    local pick = equipPickaxe(player, "Base.PickAxe", 10)

    -- No sample -> no prospect
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_prospect", "extract without sample is refused")
    eq(AC_Deposits.hasBeenWorked(cx, cy, "copper"), false, "refused extraction does not mark tile")

    -- Sample covering the square (center one tile away)
    local sample = makeSample(cx + 1, cy + 1, 1, "Good", "None")
    player.inventory:addItem(sample)

    result, err = AC_Mining.extract(player, square, "copper", pick)
    check(result ~= nil, "extraction succeeds with covering sample: " .. tostring(err))
    eq(#square.worldItems, 1, "one ore dropped on the square")
    eq(square.worldItems[1].fullType, "Base.CopperOre", "dropped item is Base.CopperOre")
    eq(result.remaining, 1, "remaining after first extraction")
    eq(#player.xpLog, 1, "XP granted exactly once per extraction")
    eq(player.xpLog[1], AC_Mining.CONFIG.xpPerOre, "XP amount per ore")
    eq(AC_Deposits.getExtracted(cx, cy, "copper"), 1, "extracted count stored")

    result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(result and result.remaining, 0, "second extraction exhausts the tile")
    eq(#square.worldItems, 2, "two ore items total")
    eq(AC_Deposits.isKnownExhausted(cx, cy, "copper"), true, "tile known exhausted")

    result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_ore", "third extraction refused")
    eq(#square.worldItems, 2, "no ore duplicated after exhaustion")
    eq(#player.xpLog, 2, "no XP for failed extraction")
    eq(AC_Deposits.getExtracted(cx, cy, "copper"), 2, "extracted count never exceeds reserve")

    -- Zinc on same tile is untouched by copper work
    eq(AC_Deposits.hasBeenWorked(cx, cy, "zinc"), false, "zinc not marked by copper extraction")
end

section("Zero-resource tile inside an assayed area")
do
    local x, y = findTile("copper", 0, 0)
    local square = newSquare(x, y, 0, GRASS)
    local player = newPlayer({ square = square })
    local pick = equipPickaxe(player)
    player.inventory:addItem(makeSample(x, y, 2, "Rich", "None"))
    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "no_ore", "assay says Rich but true geology has no ore -> no_ore")
    eq(#square.worldItems, 0, "no ore spawned")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), true, "tile marked worked")
    eq(AC_Deposits.isKnownExhausted(x, y, "copper"), true, "shown as exhausted afterwards")
    eq(#player.xpLog, 0, "no XP")
end

section("Persistence across save/reload")
do
    local cx, cy, cr = findTile("copper", 3, 4)
    local square = newSquare(cx, cy, 0, GRASS)
    local player = newPlayer({ square = square })
    local pick = equipPickaxe(player)
    player.inventory:addItem(makeSample(cx, cy, 1, "Rich", "None"))
    AC_Mining.extract(player, square, "copper", pick)
    local before = AC_Deposits.getRemaining(cx, cy, "copper")
    eq(before, cr - 1, "one unit extracted before save")

    local okSave, saveErr = pcall(MOCK.simulateSaveReload)
    check(okSave, "deposit store only contains persistable data: " .. tostring(saveErr))

    -- Simulate a full Lua reload of a fresh game session
    quiet = true
    print = function() end
    resetLuaState()
    loadMod()
    quiet = false
    print = realPrint

    eq(AC_Deposits.getRemaining(cx, cy, "copper"), before, "remaining survives save/reload")
    eq(AC_Deposits.hasBeenWorked(cx, cy, "copper"), true, "worked flag survives save/reload")
    eq(AC_Deposits.getInitialReserve(cx, cy, "copper"), cr, "geology identical after reload")

    -- Different save identity -> different geology, no shared depletion key issues
    local oldSeed = AC_WorldData.getCopperSeed()
    MOCK.saveName = "OtherSave"
    quiet = true
    print = function() end
    resetLuaState()
    loadMod()
    quiet = false
    print = realPrint
    check(AC_WorldData.getCopperSeed() ~= oldSeed, "different save gives a different copper seed")
    MOCK.saveName = "TestSave"
    quiet = true
    print = function() end
    resetLuaState()
    loadMod()
    quiet = false
    print = realPrint
    eq(AC_WorldData.getCopperSeed(), oldSeed, "original save seed restored")
end

section("Seed cache invalidation when switching saves in one session")
do
    -- Real PZ keeps Lua state between loading different saves.
    local seedA = AC_WorldData.getCopperSeed()
    MOCK.saveName = "SwitchedSave"
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.fire(true)
    end
    local seedB = AC_WorldData.getCopperSeed()
    check(seedA ~= seedB, "loading another save without restarting recomputes seeds")
    MOCK.saveName = "TestSave"
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.fire(false)
    end
    eq(AC_WorldData.getCopperSeed(), seedA, "switching back restores seed")
end

section("Prospect lookup: coverage, overlap, rank")
do
    local square = newSquare(500, 500, 0, GRASS)
    local player = newPlayer({ square = square })

    eq(AC_Mining.findProspect(player, square, "copper"), nil, "no samples -> nil")

    local far = makeSample(503, 500, 1, "Rich", "Rich")
    player.inventory:addItem(far)
    eq(AC_Mining.findProspect(player, square, "copper"), nil, "sample 3 tiles away does not cover")

    local edge = makeSample(501, 499, 1, "Poor", "None")
    player.inventory:addItem(edge)
    local s, grade = AC_Mining.findProspect(player, square, "copper")
    eq(s, edge, "sample on the 3x3 edge covers")
    eq(grade, "Poor", "reported grade comes from the sample")
    eq(AC_Mining.findProspect(player, square, "zinc"), nil, "None grade gives no prospect")

    local untested = makeSample(500, 500, 0, nil, nil)
    player.inventory:addItem(untested)
    eq(AC_Mining.findProspect(player, square, "copper"), edge, "unassayed sample ignored")

    local better = makeSample(499, 501, 2, "Good", "Trace")
    player.inventory:addItem(better)
    s, grade = AC_Mining.findProspect(player, square, "copper")
    eq(s, better, "overlapping samples: highest assay rank wins")
    eq(grade, "Good", "grade from the higher-rank sample")
    s, grade = AC_Mining.findProspect(player, square, "zinc")
    eq(s, better, "Trace grade still counts as knowledge")

    better.modData.labProcessing = true
    eq(AC_Mining.findProspect(player, square, "copper"), edge, "lab-processing sample skipped")
    better.modData.labProcessing = false

    player.inventory:Remove(better)
    player.inventory:Remove(edge)
    eq(AC_Mining.findProspect(player, square, "copper"), nil, "removed samples no longer grant access")
end

section("Terrain validation")
do
    local function ok(sprite, opts)
        return AC_Mining.isMineableSquare(newSquare(1, 1, 0, sprite, opts))
    end
    eq(ok("blends_natural_01_16"), true, "grass is mineable")
    eq(ok("blends_natural_01_0"), true, "sand blend is mineable")
    eq(ok("blends_street_01_16"), false, "asphalt street rejected")
    eq(ok("floors_exterior_street_01_8"), false, "concrete sidewalk rejected")
    eq(ok("carpentry_02_56"), false, "constructed wooden floor rejected")
    eq(ok("floors_interior_tiles_01_0"), false, "interior tiles rejected")
    eq(ok(nil), false, "no floor rejected")
    eq(ok("blends_natural_01_16", { room = {} }), false, "indoors (room) rejected")
    eq(AC_Mining.isMineableSquare(newSquare(1, 1, 1, "blends_natural_01_16")), false, "z=1 rejected")
    eq(AC_Mining.isMineableSquare(newSquare(1, 1, -1, "blends_natural_01_16")), false, "basement z rejected")
    eq(AC_Mining.isMineableSquare(nil), false, "nil square rejected")
    eq(ok("blends_natural_02_0", { water = true }), false, "water square rejected")
end

section("Pickaxe handling")
do
    local player = newPlayer()
    eq(AC_Mining.getEquippedPickaxe(player), nil, "no pickaxe")
    local head = newItem("Base.PickAxeHead")
    player.primary = head
    eq(AC_Mining.getEquippedPickaxe(player), nil, "pickaxe head is not a pickaxe")
    local forged = newItem("Base.PickAxeForged", { condition = 0 })
    player.primary = nil
    player.secondary = forged
    eq(AC_Mining.getEquippedPickaxe(player), forged, "forged pickaxe in secondary hand found")
    eq(AC_Mining.isUsablePickaxe(forged), false, "broken pickaxe unusable")
    forged.condition = 1
    eq(AC_Mining.isUsablePickaxe(forged), true, "condition 1 usable")

    -- Wear never goes below 0 and never touches a broken tool
    local x, y = findTile("copper", 4)
    local square = newSquare(x, y, 0, GRASS)
    local p = newPlayer({ square = square })
    local pick = equipPickaxe(p, "Base.PickAxe", 1)
    p.inventory:addItem(makeSample(x, y, 1, "Very Rich", "None"))
    MOCK.randomSequence = { 0 } -- force wear
    AC_Mining.extract(p, square, "copper", pick)
    MOCK.randomSequence = nil
    eq(pick.condition, 0, "wear reduces condition by 1")
    local r, e = AC_Mining.extract(p, square, "copper", pick)
    eq(e, "no_pickaxe", "broken pickaxe refused after wear")
end

section("Timed action flow")
do
    local x, y, r = findTile("zinc", 2)
    local square = newSquare(x, y, 0, GRASS)
    local player = newPlayer({ square = square })
    local pick = equipPickaxe(player)
    local sample = makeSample(x, y, 1, "None", "Good")
    player.inventory:addItem(sample)

    local action = AC_MineOreAction:new(player, square, "zinc", pick)
    eq(action:isValid(), true, "action valid with pickaxe + sample")
    eq(action:getDuration(), AC_Mining.CONFIG.baseActionTime, "base duration at level 0")

    -- Interrupted: stop() must not extract
    action:start()
    action:update()
    action:stop()
    eq(#square.worldItems, 0, "interrupted action produces no ore")
    eq(AC_Deposits.getExtracted(x, y, "zinc"), 0, "interrupted action does not deplete")

    -- Completed: exactly one extraction
    action = AC_MineOreAction:new(player, square, "zinc", pick)
    action:start()
    action:perform()
    eq(#square.worldItems, 1, "completed action drops one ore")
    eq(square.worldItems[1].fullType, "AmmoMaking.ZincOre", "zinc ore item")
    eq(AC_Deposits.getExtracted(x, y, "zinc"), 1, "completed action depletes once")
    eq(#player.xpLog, 1, "XP once")

    -- Pickaxe unequipped mid action
    action = AC_MineOreAction:new(player, square, "zinc", pick)
    player.primary = nil
    eq(action:isValid(), false, "unequipped pickaxe invalidates action")
    player.primary = pick

    -- Broken pickaxe
    pick.condition = 0
    eq(action:isValid(), false, "broken pickaxe invalidates action")
    pick.condition = 10

    -- Sample removed mid action
    player.inventory:Remove(sample)
    eq(action:isValid(), false, "removing the sample invalidates the action")
    player.inventory:addItem(sample)

    -- Surface changes (e.g. indoors)
    square.room = {}
    eq(action:isValid(), false, "square no longer mineable invalidates action")
    square.room = nil

    -- Exhaust, then queued repeat attempts are invalid
    action = AC_MineOreAction:new(player, square, "zinc", pick)
    action:start()
    action:perform()
    if r == 2 then
        eq(AC_Deposits.isKnownExhausted(x, y, "zinc"), true, "tile exhausted")
        action = AC_MineOreAction:new(player, square, "zinc", pick)
        eq(action:isValid(), false, "queued action on known-exhausted tile is invalid")
    end

    -- Skill reduces time
    player.perkLevel = 10
    eq(AC_Mining.getActionTime(player), math.floor(AC_Mining.CONFIG.baseActionTime * 0.6), "level 10 = 40% faster")
end

section("Context menu")
do
    local x, y = findTile("copper", 1)
    local square = newSquare(x, y, 0, GRASS)
    local player = newPlayer({ square = square })
    MOCK.players = { player }
    local worldObjects = { { getSquare = function() return square end } }

    local ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, false)
    eq(#ctx.options, 0, "no options without a sample")

    player.inventory:addItem(makeSample(x, y, 1, "Poor", "None"))
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, false)
    local opt = ctx:find("Mine Copper Ore")
    check(opt ~= nil, "copper option offered with sample")
    check(ctx:find("Mine Zinc Ore") == nil, "no zinc option when assay says None")
    eq(opt and opt.notAvailable, true, "option disabled without a pickaxe")

    local pick = equipPickaxe(player, "Base.PickAxe", 0)
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, false)
    opt = ctx:find("Mine Copper Ore")
    eq(opt and opt.notAvailable, true, "option disabled with a broken pickaxe")

    pick.condition = 10
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, false)
    opt = ctx:find("Mine Copper Ore")
    check(opt and opt.notAvailable == nil, "option enabled with usable pickaxe")
    ISTimedActionQueue.queue = {}
    ctx:invoke(opt)
    eq(#ISTimedActionQueue.queue, 1, "selecting the option queues one action")
    eq(ISTimedActionQueue.queue[1].Type, "AC_MineOreAction", "queued action type")

    -- Asphalt: no options even with sample + pickaxe
    local asphalt = newSquare(x, y, 0, "blends_street_01_16")
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { { getSquare = function() return asphalt end } }, false)
    eq(#ctx.options, 0, "no options on asphalt")

    -- Test mode: nothing added
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, true)
    eq(#ctx.options, 0, "test flag adds nothing")

    -- Exhausted display
    AC_Deposits.recordExtraction(x, y, "copper", 99)
    ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, worldObjects, false)
    opt = ctx:find("Mine Copper Ore (Exhausted)")
    check(opt ~= nil and opt.notAvailable == true, "exhausted tile shown as disabled")
end

section("Multiplayer client guard")
do
    local x, y = findTile("copper", 1)
    AC_Deposits.resetTile(x, y) -- earlier sections may have worked this tile
    local square = newSquare(x, y, 0, GRASS)
    local player = newPlayer({ square = square })
    MOCK.players = { player }
    local pick = equipPickaxe(player)
    player.inventory:addItem(makeSample(x, y, 1, "Poor", "None"))

    local realIsClient = isClient
    isClient = function() return true end

    local result, err = AC_Mining.extract(player, square, "copper", pick)
    eq(err, "multiplayer_unsupported", "client-side extraction refused on a multiplayer client")
    eq(#square.worldItems, 0, "no ore spawned on a multiplayer client")
    eq(AC_Deposits.hasBeenWorked(x, y, "copper"), false, "no depletion recorded on a multiplayer client")

    local ctx = newContext()
    Events.OnFillWorldObjectContextMenu.fire(0, ctx, { { getSquare = function() return square end } }, false)
    local opt = ctx:find("Mine Ore")
    check(opt ~= nil and opt.notAvailable == true, "multiplayer client sees a disabled explanatory option")
    check(ctx:find("Mine Copper Ore") == nil, "no live mining option on a multiplayer client")

    isClient = realIsClient
end

------------------------------------------------
-- SUMMARY
------------------------------------------------

print("")
print("Passed: " .. passed .. "  Failed: " .. failed)
if failed > 0 then
    os.exit(1)
end
