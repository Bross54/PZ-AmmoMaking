-- Ammo Making - a model of vanilla's firearm actions, for the offline tests
--
-- The spent-case and quality-tracking features attach to vanilla's firearm
-- Lua: an event and a handful of functions on the reload actions. Offline
-- there is no vanilla Lua, so this file MODELS it: the state changes of
--
--   ISReloadWeaponAction   onShoot, canShoot, canRack, loadAmmo, ejectSpentRounds,
--                          OnPlayerAttackFinished
--   ISRackFirearm          rackBullet, removeBullet, ejectSpentRounds
--   ISInsertMagazine       loadAmmo
--   ISEjectMagazine        unloadAmmo
--   ISLoadBulletsInMagazine        animEvent "InsertBullet"
--   ISUnloadBulletsFromMagazine    animEvent "RemoveBullet"
--   ISUnloadBulletsFromFirearm     animEvent "playReloadSound"
--
-- re-implemented from media/lua/shared/TimedActions/*.lua of the installed
-- 42.20.4 (read on 2026-10-03). Animation, sound, XP, job progress and
-- network calls are left out; every read and write of a count, a chamber,
-- the spent state, the clip flag and an inventory item is kept, in
-- vanilla's order. Method dispatch is vanilla's too: an action calls
-- self:ejectSpentRounds(), so a function the mod has replaced on the class
-- table is the one that runs.
--
-- It is a MODEL. It proves what the mod's hooks do given that vanilla
-- behaves as it reads; it does not prove that the game calls them.
-- tools/pz_compat.py records that each modelled function still exists in
-- an installed game, and a digest of its body: a change there is a
-- WARNING to read this file again.
--
-- The firearms are the vanilla ones, by the script flags that decide their
-- behaviour (docs/SPENT_CASE_RESEARCH.md 1.4).

local M = {}

------------------------------------------------
-- FIREARMS AND MAGAZINES (mocked HandWeapon / InventoryItem)
------------------------------------------------

-- One of each family, with the values of a vanilla gun of that family.
M.FIREARMS = {
    pistol = { type = "Base.Pistol", ammo = "Base.Bullets9mm", magazine = "Base.9mmClip", maxAmmo = 15 },
    assaultRifle = { type = "Base.AssaultRifle", ammo = "Base.556Bullets", magazine = "Base.556Clip", maxAmmo = 30 },
    revolver = { type = "Base.Revolver", ammo = "Base.Bullets357", maxAmmo = 6, manual = true, haveChamber = false },
    doubleBarrel = { type = "Base.DoubleBarrelShotgun", ammo = "Base.ShotgunShells", maxAmmo = 2, haveChamber = false, insertAll = true },
    pumpShotgun = { type = "Base.Shotgun", ammo = "Base.ShotgunShells", maxAmmo = 5, rackAfterShoot = true },
    boltRifle = { type = "Base.HuntingRifle", ammo = "Base.308Bullets", maxAmmo = 4, rackAfterShoot = true },
    leverRifle = { type = "Base.L94_Rifle", ammo = "Base.3030Bullets", maxAmmo = 6, rackAfterShoot = true },
}

M.FAMILIES = { "pistol", "assaultRifle", "revolver", "doubleBarrel", "pumpShotgun", "boltRifle", "leverRifle" }

-- zombie.scripting.objects.AmmoType: getItemKey() is the round's full type.
local function ammoType(MOCK, itemKey)
    return MOCK.strict({ getItemKey = function() return itemKey end }, "AmmoType")
end

-- An item with the ammunition state every InventoryItem has.
local function ammoItem(MOCK, fullType, itemKey, maxAmmo)
    local item = MOCK.newItem(fullType)
    item.ammoCount = 0
    item.maxAmmo = maxAmmo
    item.ammoKey = itemKey
    function item:getCurrentAmmoCount() return self.ammoCount end
    function item:setCurrentAmmoCount(count) self.ammoCount = count end
    function item:getMaxAmmo() return self.maxAmmo end
    function item:getAmmoType() return self.ammoKey and ammoType(MOCK, self.ammoKey) or nil end
    function item:hasModData() return next(self.modData) ~= nil end
    return item
end

function M.newMagazine(MOCK, fullType, itemKey, maxAmmo, count)
    local magazine = ammoItem(MOCK, fullType, itemKey, maxAmmo)
    magazine.ammoCount = count or 0
    magazine.isMagazine = true
    -- Checked against the engine's signatures like every mocked object.
    return MOCK.strict(magazine, "InventoryItem")
end

function M.newFirearm(MOCK, family)
    local spec = assert(M.FIREARMS[family], "no firearm family " .. tostring(family))
    local gun = ammoItem(MOCK, spec.type, spec.ammo, spec.maxAmmo)
    gun.family = family
    gun.roundChambered = false
    gun.spentChambered = false
    gun.spentCount = 0
    gun.containsClip = false
    gun.jammed = false
    function gun:isRanged() return true end
    function gun:getMagazineType() return spec.magazine end
    function gun:getAmmoPerShoot() return 1 end
    function gun:haveChamber() return spec.haveChamber ~= false end
    function gun:isRackAfterShoot() return spec.rackAfterShoot == true end
    function gun:isManuallyRemoveSpentRounds() return spec.manual == true end
    function gun:isInsertAllBulletsReload() return spec.insertAll == true end
    function gun:isRoundChambered() return self.roundChambered end
    function gun:setRoundChambered(value) self.roundChambered = value end
    function gun:isSpentRoundChambered() return self.spentChambered end
    function gun:setSpentRoundChambered(value) self.spentChambered = value end
    function gun:getSpentRoundCount() return self.spentCount end
    -- HandWeapon.setSpentRoundCount clamps to 0..getMaxAmmo() (jar).
    function gun:setSpentRoundCount(count) self.spentCount = math.max(0, math.min(count, self.maxAmmo)) end
    function gun:isContainsClip() return self.containsClip end
    function gun:setContainsClip(value) self.containsClip = value end
    function gun:isJammed() return self.jammed end
    function gun:setJammed(value) self.jammed = value end
    function gun:getJamGunChance() return 0 end
    function gun:checkJam() end
    function gun:getShellFallSound() return nil end
    -- Refuses a call HandWeapon would refuse (tests/engine_snapshot.lua).
    return MOCK.strict(gun, "HandWeapon")
end

-- What the gun really holds: the count, plus one when a round is chambered.
function M.liveRounds(gun)
    return gun:getCurrentAmmoCount() + ((gun.isRoundChambered and gun:isRoundChambered()) and 1 or 0)
end

------------------------------------------------
-- INVENTORY: the calls vanilla's actions make
------------------------------------------------

local function decorateInventory(MOCK, inventory)
    if inventory.firearmModel then return end
    inventory.firearmModel = true
    local addByType = inventory.AddItem
    -- ItemContainer.AddItem(String) and AddItem(InventoryItem) both exist.
    function inventory:AddItem(item)
        if type(item) == "table" then return self:addItem(item) end
        return addByType(self, item)
    end
    -- RemoveOneOf(String, boolean): removes one item of the type, returns it.
    function inventory:RemoveOneOf(fullType)
        for index, item in ipairs(self.items) do
            if item.fullType == fullType then
                table.remove(self.items, index)
                item.container = nil
                return item
            end
        end
        return nil
    end
    function inventory:getItemCountRecurse(fullType) return self:count(fullType) end
    function inventory:containsWithModule(fullType) return self:count(fullType) > 0 end
    -- getSomeType(String, int): up to count items of the type, as a list
    -- the action removes from as it loads.
    function inventory:getSomeType(fullType, count)
        local found = {}
        for _, item in ipairs(self.items) do
            if item.fullType == fullType and #found < count then table.insert(found, item) end
        end
        local list = { items = found }
        function list:isEmpty() return #self.items == 0 end
        function list:size() return #self.items end
        function list:get(index) return self.items[index + 1] end
        function list:remove(item)
            for index, held in ipairs(self.items) do
                if held == item then table.remove(self.items, index) return true end
            end
            return false
        end
        return list
    end
end

------------------------------------------------
-- THE ACTIONS
------------------------------------------------

local function class(name)
    local definition = { Type = name }
    definition.__index = definition
    return definition
end

local function newAction(definition, fields)
    return setmetatable(fields, definition)
end

function M.install(MOCK)
    M.MOCK = MOCK

    -- Engine globals the actions (and the mod's hooks) use.
    getDebug = function() return MOCK.debug == true end
    syncHandWeaponFields = function() end
    syncItemFields = function() end
    sendAddItemToContainer = function() end
    sendRemoveItemFromContainer = function() end
    -- The rounds and magazines the model's guns take must be items the
    -- factory knows; what was not known before is forgotten again by
    -- M.uninstall(), so the mock claims nothing it did not claim before.
    local known = MOCK.knownScriptItems
    M.addedItems = M.addedItems or {}
    for _, spec in pairs(M.FIREARMS) do
        for _, fullType in ipairs({ spec.ammo, spec.magazine }) do
            if not known[fullType] then
                known[fullType] = true
                M.addedItems[fullType] = true
            end
        end
    end
    -- A magazine made by instanceItem (ISEjectMagazine) is a magazine.
    local plainInstance = instanceItem
    local magazineSpec = {}
    for _, spec in pairs(M.FIREARMS) do
        if spec.magazine then magazineSpec[spec.magazine] = spec end
    end
    instanceItem = function(fullType)
        local spec = magazineSpec[fullType]
        if spec then return M.newMagazine(MOCK, fullType, spec.ammo, spec.maxAmmo, 0) end
        return plainInstance(fullType)
    end
    M.uninstall = function()
        instanceItem = plainInstance
        for fullType in pairs(M.addedItems) do known[fullType] = nil end
        M.addedItems = {}
    end

    --------------------------------------------
    -- ISReloadWeaponAction
    --------------------------------------------
    ISReloadWeaponAction = class("ISReloadWeaponAction")

    -- :17-43
    ISReloadWeaponAction.canRack = function(weapon)
        if not weapon:getMagazineType() and not weapon:getAmmoType() then return false end
        if weapon:isJammed() then return true end
        if weapon:haveChamber() and weapon:isRoundChambered() then return true end
        if weapon:haveChamber() and weapon:isSpentRoundChambered() then return true end
        if weapon:haveChamber() and not weapon:isRoundChambered() and weapon:getMagazineType() and weapon:getCurrentAmmoCount() > 0 then return true end
        if not weapon:haveChamber() and weapon:getCurrentAmmoCount() > 0 then return true end
        if not weapon:haveChamber() and weapon:getSpentRoundCount() > 0 then return true end
        if not weapon:getMagazineType() and weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot() then return true end
        return false
    end

    -- :408-423
    ISReloadWeaponAction.canShoot = function(player, weapon)
        if player:isUnlimitedAmmo() then return true end
        if weapon:isJammed() then return false end
        if weapon:haveChamber() and not weapon:isRoundChambered() then return false end
        if not weapon:haveChamber() and weapon:getCurrentAmmoCount() <= 0 then return false end
        return true
    end

    -- :470-528, registered on OnWeaponSwingHitPoint at :542
    ISReloadWeaponAction.onShoot = function(player, weapon)
        if not weapon:isRanged() then return end
        if getDebug() and player:isUnlimitedAmmo() then return end
        if weapon:haveChamber() then
            weapon:setRoundChambered(false)
            weapon:setSpentRoundChambered(true)
        end
        if not weapon:isRackAfterShoot() then
            if not weapon:isManuallyRemoveSpentRounds() then
                weapon:setSpentRoundChambered(false)
            end
            if weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot() then
                if weapon:haveChamber() then weapon:setRoundChambered(true) end
                if not isClient() then
                    weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() - weapon:getAmmoPerShoot())
                end
            end
        end
        if weapon:isManuallyRemoveSpentRounds() then
            weapon:setSpentRoundCount(weapon:getSpentRoundCount() + weapon:getAmmoPerShoot())
        end
    end

    -- :118-132
    function ISReloadWeaponAction:initVars()
        local type = self.gun:getAmmoType()
        if type then
            local itemKey = type:getItemKey()
            local ammoCount = self.character:getInventory():getItemCountRecurse(itemKey)
            ammoCount = math.min(ammoCount, self.gun:getMaxAmmo() - self.gun:getCurrentAmmoCount())
            local bullets = self.character:getInventory():getSomeType(itemKey, ammoCount)
            if bullets and not bullets:isEmpty() then
                self.bullets = bullets
                self.ammoCount = ammoCount
            end
        end
    end

    -- :45-67 (the state part)
    function ISReloadWeaponAction:start()
        self:initVars()
        self:ejectSpentRounds()
        if not self.bullets then self.stopped = true end
    end

    -- :235-269
    function ISReloadWeaponAction:loadAmmo()
        if self.bullets then
            if not self.bullets:isEmpty() and self.gun:getCurrentAmmoCount() < self.gun:getMaxAmmo() then
                local bullet = self.bullets:get(0)
                self.bullets:remove(bullet)
                self.character:getInventory():Remove(bullet)
                self.gun:setCurrentAmmoCount(self.gun:getCurrentAmmoCount() + 1)
            end
            if self.bullets:isEmpty() or self.gun:getCurrentAmmoCount() >= self.gun:getMaxAmmo() then
                if self.gun:haveChamber() and not self.gun:isRoundChambered() then
                    self.rackAfter = true
                end
                self.finished = true
            elseif self.gun:isInsertAllBulletsReload() then
                self:loadAmmo()
            end
        end
    end

    -- :271-284
    function ISReloadWeaponAction:ejectSpentRounds()
        if self.gun:getSpentRoundCount() > 0 then
            self.gun:setSpentRoundCount(0)
        elseif self.gun:isSpentRoundChambered() then
            self.gun:setSpentRoundChambered(false)
        else
            return
        end
    end

    function ISReloadWeaponAction:new(character, gun)
        return newAction(ISReloadWeaponAction, { character = character, gun = gun })
    end

    --------------------------------------------
    -- ISRackFirearm
    --------------------------------------------
    ISRackFirearm = class("ISRackFirearm")

    -- :6-32 (the state part)
    function ISRackFirearm:start()
        if not ISReloadWeaponAction.canRack(self.gun) then
            self.stopped = true
            return
        end
        self:ejectSpentRounds()
    end

    -- :36-67
    function ISRackFirearm:rackBullet()
        if self.gun:haveChamber() then
            if not self.gun:isJammed() and self.gun:isRoundChambered() then
                self:removeBullet()
            end
            self.gun:setRoundChambered(false)
            self.gun:setJammed(false)
            if self.gun:getCurrentAmmoCount() >= self.gun:getAmmoPerShoot() then
                self.gun:setRoundChambered(true)
                self.gun:setCurrentAmmoCount(self.gun:getCurrentAmmoCount() - self.gun:getAmmoPerShoot())
            end
        else
            if not self.gun:isJammed() and self.gun:getCurrentAmmoCount() > 0 then
                self:removeBullet()
                self.gun:setCurrentAmmoCount(self.gun:getCurrentAmmoCount() - self.gun:getAmmoPerShoot())
            end
            self.gun:setJammed(false)
        end
    end

    -- :68-73
    function ISRackFirearm:removeBullet()
        local itemKey = self.gun:getAmmoType():getItemKey()
        local newBullet = instanceItem(itemKey)
        self.character:getInventory():AddItem(newBullet)
    end

    -- :74-87
    function ISRackFirearm:ejectSpentRounds()
        if self.gun:getSpentRoundCount() > 0 then
            self.gun:setSpentRoundCount(0)
        elseif self.gun:isSpentRoundChambered() then
            self.gun:setSpentRoundChambered(false)
        else
            return
        end
    end

    function ISRackFirearm:new(character, gun)
        return newAction(ISRackFirearm, { character = character, gun = gun })
    end

    --------------------------------------------
    -- ISInsertMagazine :36-49, ISEjectMagazine :25-36
    --------------------------------------------
    ISInsertMagazine = class("ISInsertMagazine")

    function ISInsertMagazine:loadAmmo()
        self.character:getInventory():Remove(self.magazine)
        self.gun:setCurrentAmmoCount(self.magazine:getCurrentAmmoCount())
        self.gun:setContainsClip(true)
        if not self.gun:isRoundChambered() and self.gun:getCurrentAmmoCount() >= self.gun:getAmmoPerShoot() then
            self.rackAfter = true
        end
    end

    function ISInsertMagazine:new(character, gun, magazine)
        return newAction(ISInsertMagazine, { character = character, gun = gun, magazine = magazine })
    end

    ISEjectMagazine = class("ISEjectMagazine")

    function ISEjectMagazine:unloadAmmo()
        if self.gun:isContainsClip() then
            local newMag = instanceItem(self.gun:getMagazineType())
            newMag:setCurrentAmmoCount(self.gun:getCurrentAmmoCount())
            self.character:getInventory():AddItem(newMag)
            self.gun:setContainsClip(false)
            self.gun:setCurrentAmmoCount(0)
        end
    end

    function ISEjectMagazine:new(character, gun)
        return newAction(ISEjectMagazine, { character = character, gun = gun })
    end

    --------------------------------------------
    -- ISLoadBulletsInMagazine :75-136, ISUnloadBulletsFromMagazine :71-117
    --------------------------------------------
    ISLoadBulletsInMagazine = class("ISLoadBulletsInMagazine")

    function ISLoadBulletsInMagazine:isLoadFinished()
        local itemKey = self.magazine:getAmmoType():getItemKey()
        return self.magazine:getCurrentAmmoCount() >= self.magazine:getMaxAmmo() or not self.character:getInventory():containsWithModule(itemKey)
    end

    function ISLoadBulletsInMagazine:animEvent(event, parameter)
        if event == "InsertBullet" then
            if self:isLoadFinished() then return end
            if not isClient() then
                local itemKey = self.magazine:getAmmoType():getItemKey()
                self.character:getInventory():RemoveOneOf(itemKey, true)
                self.magazine:setCurrentAmmoCount(self.magazine:getCurrentAmmoCount() + 1)
            end
        elseif event == "loadFinished" then
            if self:isLoadFinished() then self.loadFinished = true end
        end
    end

    function ISLoadBulletsInMagazine:new(character, magazine, ammoCount)
        return newAction(ISLoadBulletsInMagazine, { character = character, magazine = magazine, ammoCount = ammoCount })
    end

    ISUnloadBulletsFromMagazine = class("ISUnloadBulletsFromMagazine")

    function ISUnloadBulletsFromMagazine:animEvent(event, parameter)
        if event == "RemoveBullet" then
            if self.magazine:getCurrentAmmoCount() <= 0 then return end
            if not isClient() then
                local itemKey = self.magazine:getAmmoType():getItemKey()
                local newBullet = instanceItem(itemKey)
                self.character:getInventory():AddItem(newBullet)
                self.magazine:setCurrentAmmoCount(self.magazine:getCurrentAmmoCount() - 1)
            end
        elseif event == "unloadFinished" then
            if self.magazine:getCurrentAmmoCount() <= 0 then self.unloadFinished = true end
        end
    end

    function ISUnloadBulletsFromMagazine:new(character, magazine)
        return newAction(ISUnloadBulletsFromMagazine, { character = character, magazine = magazine })
    end

    --------------------------------------------
    -- ISUnloadBulletsFromFirearm :42-95
    --------------------------------------------
    ISUnloadBulletsFromFirearm = class("ISUnloadBulletsFromFirearm")

    function ISUnloadBulletsFromFirearm:animEvent(event, parameter)
        if event == "playReloadSound" then
            if parameter == "ejectAmmoStart" then return end
            if self.gun:getCurrentAmmoCount() <= 0 then return end
            local count = 1
            if self.gun:isInsertAllBulletsReload() then
                count = self.gun:getCurrentAmmoCount()
            end
            if not isClient() then
                while self.gun:getCurrentAmmoCount() > 0 do
                    local itemKey = self.gun:getAmmoType():getItemKey()
                    local newBullet = instanceItem(itemKey)
                    self.character:getInventory():AddItem(newBullet)
                    self.gun:setCurrentAmmoCount(self.gun:getCurrentAmmoCount() - 1)
                    count = count - 1
                    if count == 0 then break end
                end
            end
        elseif event == "unloadFinished" then
            if self.gun:getCurrentAmmoCount() <= 0 then self.unloadFinished = true end
        end
    end

    function ISUnloadBulletsFromFirearm:new(character, gun)
        return newAction(ISUnloadBulletsFromFirearm, { character = character, gun = gun })
    end

    -- Vanilla's listener is registered when its file loads, before any
    -- mod's: Event.trigger walks the callbacks in the order they were
    -- added (jar), so a mod listener sees the gun after onShoot.
    Events.OnWeaponSwingHitPoint.Add(function(player, weapon) ISReloadWeaponAction.onShoot(player, weapon) end)
end

------------------------------------------------
-- WHAT A PLAYER DOES (sequences of the actions above)
------------------------------------------------

function M.newShooter(MOCK, square)
    local player = MOCK.newPlayer({ square = square })
    decorateInventory(MOCK, player.inventory)
    player.unlimitedAmmo = false
    function player:isUnlimitedAmmo() return self.unlimitedAmmo end
    if not player.getCurrentSquare then
        function player:getCurrentSquare() return square end
    end
    return player
end

-- count loose rounds of a type into the inventory; returns them.
function M.giveRounds(MOCK, player, fullType, count)
    local rounds = {}
    for index = 1, count do
        rounds[index] = player.inventory:addItem(MOCK.newItem(fullType))
        local item = rounds[index]
        function item:hasModData() return next(self.modData) ~= nil end
    end
    return rounds
end

-- Rack: eject what is spent, then rackBullet. Returns false when the gun
-- cannot be racked.
function M.rack(player, gun)
    local action = ISRackFirearm:new(player, gun)
    action:start()
    if action.stopped then return false end
    action:rackBullet()
    return true
end

-- Pull the trigger once. Returns true when a round was fired. A dry fire
-- fires no event (FirearmEmpty.xml has no collision check).
function M.fire(player, gun)
    if not ISReloadWeaponAction.canShoot(player, gun) then return false end
    Events.OnWeaponSwingHitPoint.fire(player, gun)
    -- OnPlayerAttackFinished :530-538
    if not (getDebug() and player:isUnlimitedAmmo()) and gun:isRackAfterShoot() then
        M.rack(player, gun)
    end
    return true
end

-- Load loose rounds into a gun without a magazine, as far as they go; then
-- the rack vanilla queues when nothing is chambered.
function M.reload(player, gun)
    local action = ISReloadWeaponAction:new(player, gun)
    action:start()
    if action.stopped then return 0 end
    local before = gun:getCurrentAmmoCount()
    local guard = 0
    while not action.finished and guard < 200 do
        action:loadAmmo()
        guard = guard + 1
    end
    if action.rackAfter then M.rack(player, gun) end
    return gun:getCurrentAmmoCount() - before
end

-- Load up to count rounds into a loose magazine.
function M.loadMagazine(player, magazine, count)
    local action = ISLoadBulletsInMagazine:new(player, magazine, count)
    local loaded = 0
    for _ = 1, count do
        local before = magazine:getCurrentAmmoCount()
        action:animEvent("InsertBullet", nil)
        if magazine:getCurrentAmmoCount() > before then loaded = loaded + 1 end
    end
    return loaded
end

-- Take up to count rounds out of a loose magazine.
function M.unloadMagazine(player, magazine, count)
    local action = ISUnloadBulletsFromMagazine:new(player, magazine)
    local taken = 0
    for _ = 1, count do
        local before = magazine:getCurrentAmmoCount()
        action:animEvent("RemoveBullet", nil)
        if magazine:getCurrentAmmoCount() < before then taken = taken + 1 end
    end
    return taken
end

-- Insert a magazine; then the rack vanilla queues when nothing is chambered.
function M.insertMagazine(player, gun, magazine)
    if gun:isContainsClip() or not player.inventory:contains(magazine) then return false end
    local action = ISInsertMagazine:new(player, gun, magazine)
    action:loadAmmo()
    if action.rackAfter then M.rack(player, gun) end
    return true
end

-- Eject the magazine; returns the new magazine item.
function M.ejectMagazine(player, gun)
    if not gun:isContainsClip() then return nil end
    local before = {}
    for _, item in ipairs(player.inventory.items) do before[item] = true end
    ISEjectMagazine:new(player, gun):unloadAmmo()
    for _, item in ipairs(player.inventory.items) do
        if not before[item] then return item end
    end
    return nil
end

-- Unload a gun without a magazine, one animation event at a time.
function M.unloadFirearm(player, gun, events)
    local action = ISUnloadBulletsFromFirearm:new(player, gun)
    for _ = 1, events or 200 do
        if gun:getCurrentAmmoCount() <= 0 then break end
        action:animEvent("playReloadSound", "unload")
    end
end

return M
