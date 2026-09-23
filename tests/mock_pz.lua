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
MOCK.invalidHasTagCalls = 0  -- item:hasTag("string") calls; invalid on 42.20.4
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

-- Squares reachable through getCell():getGridSquare(); tests register
-- the ones a placement should find.
MOCK.cellSquares = {}
MOCK.drag = nil

function MOCK.registerSquare(square)
    MOCK.cellSquares[square.x .. "," .. square.y .. "," .. square.z] = square
    return square
end

MOCK.cell = {
    getGridSquare = function(_, x, y, z)
        return MOCK.cellSquares[x .. "," .. y .. "," .. (z or 0)]
    end,
    setDrag = function(_, object, playerNum)
        MOCK.drag = { object = object, player = playerNum }
    end,
}

function getCell() return MOCK.cell end

MOCK.hydroPowerOn = false

function getWorld()
    return {
        getWorld = function() return MOCK.saveName end,
        isHydroPowerOn = function() return MOCK.hydroPowerOn end,
        getCell = function() return MOCK.cell end,
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
    function item:getType() return (string.match(self.fullType, "%.(.+)$")) or self.fullType end
    function item:getDigType() return opts.digType end
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
    -- 42.20.4 InventoryItem only has hasTag(ItemTag) / hasTag(ItemTag...)
    -- (javap of projectzomboid.jar). A string argument raises the engine's
    -- "No implementation found" error, so the mock raises too and counts it.
    function item:hasTag(tag)
        if type(tag) == "string" then
            MOCK.invalidHasTagCalls = MOCK.invalidHasTagCalls + 1
            error("No implementation found for function: hasTag("
                .. tostring(self.fullType) .. ", class java.lang.String " .. tag .. ")")
        end
        return self.tags[tag] == true
    end
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
        self.removeCalls = (self.removeCalls or 0) + 1
        for i, it in ipairs(self.items) do
            if it == item then table.remove(self.items, i) break end
        end
        item.container = nil
    end
    function inv:contains(item)
        for _, it in ipairs(self.items) do
            if it == item then return true end
        end
        return false
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
    function player:setPrimaryHandItem(item) self.primary = item end
    function player:setSecondaryHandItem(item) self.secondary = item end
    function player:getPlayerNum() return opts.playerNum or 0 end
    function player:getXp()
        local p = self
        return {
            AddXP = function(_, perk, amount)
                table.insert(p.xpLog, amount)
            end,
            setXPToLevel = function(_, perk, level) end,
            getXP = function(_, perk) return p:totalXP() end,
        }
    end
    function player:SetVariable(key, value)
        self.animVariables = self.animVariables or {}
        self.animVariables[key] = value
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
    -- No square:Is(): it does not exist on Build 42.20.4 (calling it
    -- raised "Tried to call nil" in game).
    function square:hasWater() return self.water end
    function square:haveElectricity() return false end
    function square:hasGridPower() return opts.gridPower == true end
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

-- Tile sprites getSprite() knows; unknown names return nil.
MOCK.knownSprites = { ["industry_03_61"] = true }

function getSprite(name)
    if not MOCK.knownSprites[name] then return nil end
    return { getName = function() return name end }
end

------------------------------------------------
-- PLACEMENT CURSOR BASE AND THUMPABLES
------------------------------------------------

-- Minimal ISBuildingObject: derive / init / sprite setters and an
-- isValid() whose answer the test chooses. The real class walks the
-- player over, runs ISBuildAction and renders the ghost sprite; none of
-- that is modelled, so tests of create() prove Lua control flow only.
ISBuildingObject = { Type = "ISBuildingObject" }
ISBuildingObject.__index = ISBuildingObject
MOCK.buildingObjectValid = true

function ISBuildingObject:derive(name)
    local cls = {}
    setmetatable(cls, self)
    self.__index = self
    cls.Type = name
    return cls
end
function ISBuildingObject:init()
    self.modData = {}
    self.canBeAlwaysPlaced = false
    self.isThumpable = true
end
function ISBuildingObject:setSprite(s) self.sprite = s end
function ISBuildingObject:setNorthSprite(s) self.northSprite = s end
function ISBuildingObject:setEastSprite(s) self.eastSprite = s end
function ISBuildingObject:setSouthSprite(s) self.southSprite = s end
function ISBuildingObject:isValid(square) return MOCK.buildingObjectValid end

-- IsoThumpable.new stand-in returning a mock world object.
IsoThumpable = {}
MOCK.thumpableFails = false

function IsoThumpable.new(cell, square, sprite, north, luaObject)
    if MOCK.thumpableFails then return nil end
    local o = newWorldObject({ class = "IsoThumpable", sprite = sprite })
    o.north = north
    o.transmitted = 0
    function o:setCanBarricade(v) self.canBarricade = v end
    function o:setIsThumpable(v) self.isThumpable = v end
    function o:setIsDismantable(v) self.dismantable = v end
    function o:transmitCompleteItemToClients() self.transmitted = self.transmitted + 1 end
    return o
end

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

Metabolics = { DiggingSpade = "DiggingSpade", HeavyDomestic = "HeavyDomestic" }

-- Records the items the placement menu asked to move into the main
-- inventory; the real function queues a transfer action.
ISInventoryPaneContextMenu = { transfers = {} }
function ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    table.insert(ISInventoryPaneContextMenu.transfers, item)
end
Perks = { Strength = "Strength", Crafting = "Crafting" }

-- Same branches as vanilla BuildingHelper.getShovelAnim in the installed
-- 42.20.4 shared/Util/BuildingHelper.lua. In game the results are
-- CharacterActionAnims enum values (Java), not strings; the mock uses
-- tagged tables so a test can tell them apart from plain strings.
CharacterActionAnims = {}
for _, name in ipairs({ "Dig", "DigShovel", "DigHoe", "DigPickAxe", "DigTrowel" }) do
    CharacterActionAnims[name] = { enum = "CharacterActionAnims", name = name }
end

BuildingHelper = {
    getShovelAnim = function(item)
        if not item then
            return CharacterActionAnims.Dig
        end
        if item:getDigType() == "Trowel" or item:getType() == "HandShovel" or item:getType() == "HandFork" or item:getType() == "EntrenchingTool" then
            return CharacterActionAnims.DigTrowel
        elseif item:getDigType() == "Hoe" or item:getType() == "GardenHoe" then
            return CharacterActionAnims.DigHoe
        elseif item:getDigType() == "PickAxe" or item:getType() == "PickAxe" then
            return CharacterActionAnims.DigPickAxe
        end
        return CharacterActionAnims.DigShovel
    end,
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

-- Skill: just enough of the Java PerkFactory for the real
-- AC_AmmoMakingSkill.lua to load. Registration itself is engine behaviour
-- and is not tested; the mock player ignores which perk XP goes to.
PerkFactory = {
    Perk = {
        new = function(name, parent)
            return {
                name = name,
                setCustom = function() end,
                getName = function(self) return self.name end,
            }
        end,
    },
    AddPerk = function() end,
    initTranslations = function() end,
}

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

-- Mod Lua files the tests load, relative to media/lua/ (UI panels are
-- mocked instead of loaded).
MOCK.MOD_FILES = {
    "shared/AC_AmmoInspection", "shared/AC_AmmoMakingSkill", "shared/AC_AmmoQuality", "shared/AC_Compat",
    "shared/AC_Deposits", "shared/AC_Geology", "shared/AC_GeologySampling",
    "shared/AC_LaboratoryAnalyzer", "shared/AC_Mining", "shared/AC_Text",
    "shared/AC_WorldData",
    "client/AC_AmmoContextMenu", "client/AC_DigGeologicalSampleAction",
    "client/AC_GeologyDebug", "client/AC_GeologySamplingContextMenu",
    "client/AC_MineOreAction", "client/AC_MiningContextMenu",
    "client/AC_PickUpAnalyzerAction",
    "server/BuildingObjects/AC_LaboratoryAnalyzerObject",
}

-- Loads every mod file: shared, then client, then server, each
-- alphabetical. Prints during load are captured.
function MOCK.loadMod(luaRoot)
    MOCK.capturePrint(true)
    for _, name in ipairs(MOCK.MOD_FILES) do dofile(luaRoot .. name .. ".lua") end
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
    AC_LaboratoryAnalyzerObject = nil
    AC_Deposits = nil
    AC_Mining = nil
    AC_Compat = nil
    AC_MineOreAction = nil
    AC_PickUpAnalyzerAction = nil
    AC_GeologyDebug = nil
    AmmoInspection = nil
    AmmoQuality = nil
    AmmoMakingSkill = nil
    MOCK.resetEvents()
end

return MOCK
