-- Ammo Making - Project Zomboid API mocks for offline tests
--
-- Loaded by tests/run_tests.lua. Provides just enough of the Kahlua /
-- Project Zomboid surface for the shared modules and the client menus
-- and timed actions to load and run under plain Lua 5.1.
--
-- Everything here is a stand-in. It proves Lua-level logic only; it
-- says nothing about vanilla item ids, animations, sounds or Java
-- behaviour. Those need an in-game test.

local MOCK = {}

MOCK.saveName = "TestSave"
MOCK.modDataRegistry = {}
MOCK.randomSequence = nil   -- optional deterministic override for ZombRand
MOCK.worldHours = 0
MOCK.debug = false
MOCK.client = false
MOCK.players = {}
MOCK.walkAdjResult = true
MOCK.translations = nil     -- table key -> text, or nil for "not loaded"
MOCK.zombRandCalls = 0
MOCK.scriptManagerAvailable = true

------------------------------------------------
-- GLOBAL MODDATA
------------------------------------------------

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

-- Deep copy allowing only what Kahlua global ModData can persist
-- (string/number keys, string/number/boolean/table values).
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

MOCK.persistCopy = persistCopy

function MOCK.simulateSaveReload()
    local copy = {}
    for key, value in pairs(MOCK.modDataRegistry) do
        copy[key] = persistCopy(value, key)
    end
    MOCK.modDataRegistry = copy
end

function MOCK.clearModData()
    MOCK.modDataRegistry = {}
end

------------------------------------------------
-- WORLD / TIME
------------------------------------------------

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

------------------------------------------------
-- RANDOM
------------------------------------------------

local rngState = 12345

function ZombRand(a, b)
    MOCK.zombRandCalls = MOCK.zombRandCalls + 1
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

------------------------------------------------
-- EVENTS
------------------------------------------------

local function newEvents()
    return setmetatable({}, {
        __index = function(t, name)
            local ev = { handlers = {} }
            function ev.Add(fn) table.insert(ev.handlers, fn) end
            function ev.Remove(fn)
                for i, h in ipairs(ev.handlers) do
                    if h == fn then table.remove(ev.handlers, i) return end
                end
            end
            function ev.fire(...)
                for _, fn in ipairs(ev.handlers) do fn(...) end
            end
            rawset(t, name, ev)
            return ev
        end,
    })
end

Events = newEvents()

function MOCK.resetEvents()
    Events = newEvents()
end

------------------------------------------------
-- TRANSLATION
------------------------------------------------

function getTextOrNull(key, ...)
    if not MOCK.translations then
        return nil
    end
    local text = MOCK.translations[key]
    if text == nil then
        return nil
    end
    local args = { ... }
    return (string.gsub(text, "%%(%d)", function(i)
        local v = args[tonumber(i)]
        if v == nil then return "%" .. i end
        return tostring(v)
    end))
end

function getText(key, ...)
    return getTextOrNull(key, ...) or key
end

------------------------------------------------
-- ITEMS
------------------------------------------------

local nextItemId = 1

MOCK.knownScriptItems = {
    ["Base.CopperOre"] = true,
    ["AmmoMaking.ZincOre"] = true,
    ["AmmoMaking.GeologicalSample"] = true,
    ["AmmoMaking.FieldAssayKit"] = true,
    ["AmmoMaking.AdvancedFieldAssayKit"] = true,
    ["AmmoMaking.LaboratoryAssayAnalyzer"] = true,
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
        customName = false,
        jobType = nil,
        jobDelta = 0,
        tags = opts.tags or {},
    }
    nextItemId = nextItemId + 1
    function item:getFullType() return self.fullType end
    function item:getID() return self.id end
    function item:getModData() return self.modData end
    function item:getCondition() return self.condition end
    function item:setCondition(v) self.condition = v end
    function item:isBroken() return self.condition <= 0 end
    function item:getContainer() return self.container end
    function item:setJobType(t) self.jobType = t end
    function item:setJobDelta(d) self.jobDelta = d end
    function item:setCustomName(v) self.customName = v end
    function item:setName(n) self.name = n end
    function item:getName() return self.name end
    function item:hasTag(tag) return self.tags[tag] == true end
    return item
end

MOCK.newItem = newItem

local function createKnownItem(fullType)
    if not MOCK.knownScriptItems[fullType] then return nil end
    return newItem(fullType)
end

function instanceItem(fullType)
    return createKnownItem(fullType)
end

-- Older factory; independent of the instanceItem global so tests can
-- remove one without breaking the other.
InventoryItemFactory = {
    CreateItem = function(fullType) return createKnownItem(fullType) end,
}

function getScriptManager()
    if not MOCK.scriptManagerAvailable then
        error("script manager unavailable")
    end
    return {
        FindItem = function(_, fullType)
            if MOCK.knownScriptItems[fullType] then return {} end
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

MOCK.arrayList = arrayList

------------------------------------------------
-- INVENTORY
------------------------------------------------

local function newInventory()
    local inv = { items = {}, dirty = false }
    function inv:AddItem(fullType)
        local item = createKnownItem(fullType)
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
    function inv:count(fullType)
        local n = 0
        for _, it in ipairs(self.items) do
            if it.fullType == fullType then n = n + 1 end
        end
        return n
    end
    return inv
end

MOCK.newInventory = newInventory

------------------------------------------------
-- PLAYER
------------------------------------------------

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
            setXPToLevel = function(_, perk, level) end,
        }
    end
    function player:setPerkLevelDebug(perk, level) self.perkLevel = level end
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

function getPlayer()
    return MOCK.players[1]
end

function getSpecificPlayer(i)
    return MOCK.players[i + 1]
end

------------------------------------------------
-- SQUARES
------------------------------------------------

local function newSquare(x, y, z, spriteName, opts)
    opts = opts or {}
    local square = {
        x = x, y = y, z = z or 0,
        spriteName = spriteName,
        room = opts.room,
        water = opts.water or false,
        worldItems = {},
        objects = {},                       -- IsoObjects on the square
        specialObjects = {},                -- subset added with AddSpecialObject
        transmittedRemovals = {},           -- objects passed to transmitRemoveItemFromSquare
        spawnError = opts.spawnError,       -- string -> AddWorldInventoryItem throws
        spriteError = opts.spriteError,     -- true -> getSprite throws
        noSprite = opts.noSprite,           -- true -> floor without sprite
    }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return self.room end
    function square:getFloor()
        if self.spriteName == nil and not self.noSprite and not self.spriteError then
            return nil
        end
        local s = self
        return {
            getSprite = function()
                if s.spriteError then error("sprite lookup failed") end
                if s.noSprite then return nil end
                return { getName = function() return s.spriteName end }
            end,
        }
    end
    function square:AddWorldInventoryItem(item, ox, oy, oz)
        if self.spawnError then error(self.spawnError) end
        table.insert(self.worldItems, item)
        return { getItem = function() return item end }
    end
    function square:getWorldObjects() return arrayList({}) end
    function square:getObjects() return arrayList(self.objects) end
    function square:getSpecialObjects() return arrayList(self.specialObjects) end
    function square:AddSpecialObject(object)
        table.insert(self.objects, object)
        table.insert(self.specialObjects, object)
        object.square = self
    end
    -- Only records the call: what the engine does with it (network
    -- message, local removal) is not modelled here.
    function square:transmitRemoveItemFromSquare(object)
        table.insert(self.transmittedRemovals, object)
    end
    function square:RemoveTileObject(object)
        for _, list in ipairs({ self.objects, self.specialObjects }) do
            for i, o in ipairs(list) do
                if o == object then table.remove(list, i) break end
            end
        end
        object.square = nil
    end
    function square:RecalcAllWithNeighbours() end
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

------------------------------------------------
-- WORLD OBJECTS
------------------------------------------------

-- Generic IsoObject stand-in (walls, placed machines). ModData is created
-- lazily by getModData() and hasModData() reports whether it exists; that
-- is a mock convention, not a statement about the engine.
local function newWorldObject(opts)
    opts = opts or {}
    local object = {
        __class = opts.class or "IsoObject",
        name = opts.name,
        spriteName = opts.sprite,
        modData = opts.modData,
        square = nil,
    }
    function object:hasModData() return self.modData ~= nil end
    function object:getModData()
        if not self.modData then self.modData = {} end
        return self.modData
    end
    function object:getName() return self.name end
    function object:setName(n) self.name = n end
    function object:getSquare() return self.square end
    function object:getTextureName() return self.spriteName end
    function object:getObjectIndex()
        if not self.square then return -1 end
        for i, o in ipairs(self.square.objects) do
            if o == self then return i - 1 end
        end
        return -1
    end
    return object
end

MOCK.newWorldObject = newWorldObject

------------------------------------------------
-- MISC GLOBALS USED BY CLIENT FILES
------------------------------------------------

function isClient() return MOCK.client end
function isServer() return false end
function isDebugEnabled() return MOCK.debug end
function addSound() end
function instanceof(obj, className) return obj ~= nil and obj.__class == className end

HaloTextHelper = { log = {} }
function HaloTextHelper.addText(player, text)
    table.insert(HaloTextHelper.log, tostring(text))
end
function HaloTextHelper.clear() HaloTextHelper.log = {} end
function HaloTextHelper.last() return HaloTextHelper.log[#HaloTextHelper.log] end

Metabolics = { DiggingSpade = "DiggingSpade" }
Perks = { Strength = "Strength", Crafting = "Crafting" }

BuildingHelper = {
    getShovelAnim = function(item) return "DigShovel" end,
}

luautils = {
    walkAdj = function(player, square) return MOCK.walkAdjResult end,
}

ISWorldObjectContextMenu = {
    addToolTip = function() return {} end,
}

ISTimedActionQueue = { queue = {} }
function ISTimedActionQueue.add(action)
    table.insert(ISTimedActionQueue.queue, action)
    return action
end
function ISTimedActionQueue.clear() ISTimedActionQueue.queue = {} end

function require(name) end

-- UI panels are not loaded offline; the menus only call open().
AC_GeologyAssayUI = { opened = 0, open = function() AC_GeologyAssayUI.opened = AC_GeologyAssayUI.opened + 1 end }
AC_AmmoInspectionUI = { opened = 0, open = function() AC_AmmoInspectionUI.opened = AC_AmmoInspectionUI.opened + 1 end }

-- Skill: PerkFactory is not mocked; the real file registers a perk with
-- the Java factory. This equivalent keeps the same public functions.
AmmoMakingSkill = { perk = { name = "AmmoMaking" } }
function AmmoMakingSkill.addXP(player, amount)
    if not player then return end
    if not amount or amount <= 0 then return end
    player:getXp():AddXP(AmmoMakingSkill.perk, amount)
end
function AmmoMakingSkill.getLevel(player)
    return player and player.perkLevel or 0
end
function AmmoMakingSkill.hasLevel(player, required)
    return AmmoMakingSkill.getLevel(player) >= required
end

------------------------------------------------
-- TIMED ACTION BASE
------------------------------------------------

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
    o.anim = nil
    return o
end

function ISBaseTimedAction:setActionAnim(anim) self.anim = anim end
function ISBaseTimedAction:setOverrideHandModels() end
function ISBaseTimedAction:getJobDelta() return 0 end
function ISBaseTimedAction:perform() self.completed = true end
function ISBaseTimedAction:stop() self.stopped = true end
function ISBaseTimedAction:forceStop() self.stopped = true end

------------------------------------------------
-- CONTEXT MENU
------------------------------------------------

local function newContext()
    local ctx = { options = {}, submenus = {} }
    function ctx:addOption(name, target, fn, ...)
        local option = { name = name, target = target, fn = fn, args = { ... } }
        table.insert(self.options, option)
        return option
    end
    function ctx:addSubMenu(option, submenu)
        option.submenu = submenu
        table.insert(self.submenus, submenu)
    end
    function ctx:find(prefix)
        for _, o in ipairs(self.options) do
            if o.name:sub(1, #prefix) == prefix then return o end
        end
        return nil
    end
    function ctx:names()
        local out = {}
        for _, o in ipairs(self.options) do table.insert(out, o.name) end
        return out
    end
    function ctx:invoke(option)
        return option.fn(option.target, unpack(option.args))
    end
    return ctx
end

MOCK.newContext = newContext

ISContextMenu = {}
function ISContextMenu:getNew(parent)
    return newContext()
end

------------------------------------------------
-- LOADING THE MOD
------------------------------------------------

local realPrint = print

MOCK.printLog = {}

function MOCK.capturePrint(enable)
    if enable then
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
            table.insert(MOCK.printLog, table.concat(parts, "\t"))
        end
    else
        print = realPrint
    end
end

function MOCK.clearPrintLog()
    MOCK.printLog = {}
end

function MOCK.printLogContains(needle)
    for _, line in ipairs(MOCK.printLog) do
        if string.find(line, needle, 1, true) then return true end
    end
    return false
end

-- Loads every mod file in Project Zomboid's order: shared (alphabetical)
-- then client (alphabetical). Prints during load are captured.
function MOCK.loadMod(luaRoot)
    MOCK.capturePrint(true)
    local shared = {
        "AC_AmmoInspection", "AC_AmmoQuality", "AC_Compat", "AC_Deposits",
        "AC_Geology", "AC_GeologySampling", "AC_LaboratoryAnalyzer",
        "AC_Mining", "AC_Text", "AC_WorldData",
    }
    local client = {
        "AC_AmmoContextMenu", "AC_DigGeologicalSampleAction", "AC_GeologyDebug",
        "AC_GeologySamplingContextMenu", "AC_MineOreAction", "AC_MiningContextMenu",
    }
    for _, name in ipairs(shared) do dofile(luaRoot .. "shared/" .. name .. ".lua") end
    for _, name in ipairs(client) do dofile(luaRoot .. "client/" .. name .. ".lua") end
    MOCK.capturePrint(false)
end

-- Simulates Project Zomboid reloading its Lua state for a fresh game
-- session (module globals are dropped, events re-registered).
function MOCK.resetLuaState()
    AC_Text = nil
    AC_WorldData = nil
    AC_Geology = nil
    AC_GeologySampling = nil
    AC_LaboratoryAnalyzer = nil
    AC_Deposits = nil
    AC_Mining = nil
    AC_Compat = nil
    AC_MineOreAction = nil
    AC_GeologyDebug = nil
    AmmoInspection = nil
    AmmoQuality = nil
    MOCK.resetEvents()
end

return MOCK
