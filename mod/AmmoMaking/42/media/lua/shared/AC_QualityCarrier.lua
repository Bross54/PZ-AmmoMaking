-- Ammo Making - Ammunition quality in magazines and firearms
-- Project Zomboid Build 42.20
--
-- EXPERIMENTAL, NOT YET SEEN IN GAME. Feature
-- "qualityTracking" (AC_Features): a sandbox option of
-- the save, false by default, single player only. With it
-- off this file wraps nothing, listens to nothing and
-- writes nothing.
--
-- WHAT IT DOES
--
-- A handloaded round carries its casing quality while it
-- is a loose item (AC_CaseQuality). Vanilla turns a
-- loaded round into a number, so that record used to be
-- lost at the magazine. This file keeps it: one
-- AC_QualityTally record in the ModData of each loose
-- magazine and each firearm says how many of the rounds
-- in it are handloaded and what their qualities add up
-- to, and rounds that come back out are given their
-- quality again.
--
-- It has NO effect on firing. A handloaded round still
-- shoots exactly like a factory round
-- (AC_QualityEffects is a separate, locked feature).
--
-- HOW (docs/AMMO_QUALITY_RUNTIME_DESIGN.md, 9)
--
-- Vanilla moves rounds in seven Lua functions and takes
-- one away at the shot. Each of the seven is wrapped, and
-- the shot is listened to. A wrapper does not re-implement
-- what vanilla does and does not trust its own idea of
-- it. It OBSERVES:
--
--   before   how many rounds the magazine or gun holds
--            (vanilla's own count, plus the chambered
--            round), and which loose rounds of that
--            calibre the character carries, with their
--            qualities
--   call     vanilla's function, with exactly the
--            arguments it was given
--   after    the same two observations
--
-- and the record follows the DIFFERENCE:
--
--   the container holds more   rounds went in. As many
--                              as left the inventory with
--                              a quality are handloaded,
--                              with those qualities; the
--                              rest are factory rounds
--   the container holds fewer, and loose rounds appeared
--                              rounds were unloaded. The
--                              record hands out its mix
--                              (AC_QualityTally.unload)
--                              and the new loose rounds
--                              are given the qualities
--   the container holds fewer, and nothing appeared
--                              rounds were fired
--
-- So the record cannot get ahead of vanilla: it only ever
-- describes rounds vanilla says are there. Whatever
-- changed the count without being seen (another mod's
-- reload action, a debug command) is found the next time
-- the item is looked at, and resolved toward factory
-- (AC_QualityTally.reconcile). No path creates a round, a
-- handloaded round or quality.
--
-- A magazine is not one object through its life: vanilla
-- destroys the item at insert and makes a new one at
-- eject. The record is merged into the gun's at insert
-- and split off again at eject.
--
-- Every wrapper calls vanilla's function exactly once and
-- hands its result on. The mod's own two steps are
-- pcall-guarded and logged once: a failure here never
-- breaks a reload.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: everything that
-- touches the engine (docs/INGAME_VALIDATION.md,
-- docs/AMMO_QUALITY_RUNTIME_DESIGN.md 6).

require "AC_Features"
require "AC_SaveData"
require "AC_QualityTally"
require "AC_CaseQuality"
require "AC_Compat"

AC_QualityCarrier = AC_QualityCarrier or {}


-- The ModData key of the record, on a firearm and on a
-- loose magazine (declared in AC_SaveData.SCHEMA).
AC_QualityCarrier.KEY = "AmmoMakingTally"


------------------------------------------------
-- WHAT AN ITEM HOLDS
------------------------------------------------
--
-- Live rounds: vanilla's count, plus one when a round is
-- chambered. The bare count falls when a round is
-- chambered, not when one is fired, so it is the wrong
-- number to follow for a gun with a chamber
-- (docs/SPENT_CASE_RESEARCH.md 1.6). A magazine has no
-- chamber and no isRoundChambered.
------------------------------------------------

function AC_QualityCarrier.liveRounds(
    item
)

    if not item
        or not item.getCurrentAmmoCount
    then
        return 0
    end


    local count =
        tonumber(item:getCurrentAmmoCount()) or 0


    if item.isRoundChambered
        and item:isRoundChambered()
    then
        count = count + 1
    end


    return count
end


-- The full type of the loose round an item takes, or nil.
function AC_QualityCarrier.getRoundType(
    item
)

    if not item
        or not item.getAmmoType
    then
        return nil
    end


    local ammoType =
        item:getAmmoType()


    if not ammoType
        or not ammoType.getItemKey
    then
        return nil
    end


    return ammoType:getItemKey()
end


------------------------------------------------
-- THE RECORD ON AN ITEM
------------------------------------------------

-- The record as it is stored, or nil. Does not create an
-- empty ModData table on an item that has none.
local function stored(
    item
)

    if not item then
        return nil
    end


    if item.hasModData
        and not item:hasModData()
    then
        return nil
    end


    local holder =
        item:getModData()


    return holder and holder[AC_QualityCarrier.KEY] or nil
end


-- A sound record for the item, and the tally's status
-- word. A record written by a later release comes back
-- with the status "newer": it must not be written over.
function AC_QualityCarrier.read(
    item
)

    return AC_QualityTally.repair(stored(item))
end


-- The item's record brought into step with what the item
-- holds now. This is what everything else starts from.
-- Returns the record and whether it may be written back
-- (false for a later release's record).
function AC_QualityCarrier.observe(
    item
)

    local raw =
        stored(item)


    local record,
          status =
        AC_QualityTally.reconcile(
            raw,
            AC_QualityCarrier.liveRounds(item)
        )


    return record, status ~= AC_QualityTally.NEWER
end


-- Stores a record. A record with no handloaded round says
-- nothing vanilla's own count does not say, so it is not
-- stored at all: the key is removed, and an item that
-- never held a handloaded round never gets ModData from
-- this file.
function AC_QualityCarrier.write(
    item,
    record
)

    if not item then
        return
    end


    local keep =
        type(record) == "table"
        and (tonumber(record.handloaded) or 0) > 0


    if not keep then

        if stored(item) ~= nil then
            item:getModData()[AC_QualityCarrier.KEY] = nil
        end


        return
    end


    item:getModData()[AC_QualityCarrier.KEY] = {

        version = record.version,

        count = record.count,

        handloaded = record.handloaded,

        qualitySum = record.qualitySum,

        phase = record.phase,
    }
end


------------------------------------------------
-- THE LOOSE ROUNDS A CHARACTER CARRIES
------------------------------------------------
--
-- Returns { count, qualities = { q, ... }, plain = { item,
-- ... } }: how many loose rounds of the type, the quality
-- of each handloaded one, and the ones without a quality.
------------------------------------------------

function AC_QualityCarrier.census(
    character,
    roundType
)

    local found = {

        count = 0,

        qualities = {},

        plain = {},
    }


    if not character
        or not roundType
    then
        return found
    end


    local items =
        character:getInventory():getItemsFromFullType(
            roundType,
            true
        )


    if not items then
        return found
    end


    for index = 0, items:size() - 1 do

        local item =
            items:get(index)


        local quality =
            AC_CaseQuality.getRoundQuality(item)


        found.count = found.count + 1


        if quality then

            table.insert(
                found.qualities,
                quality
            )

        else

            table.insert(
                found.plain,
                item
            )
        end
    end


    return found
end


-- The qualities that are in before and no longer in
-- after: the handloaded rounds that left the inventory.
local function qualitiesGone(
    before,
    after
)

    local left = {}


    for _,
        quality
    in ipairs(
        after
    )
    do

        left[quality] = (left[quality] or 0) + 1
    end


    local gone = {}


    for _,
        quality
    in ipairs(
        before
    )
    do

        if (left[quality] or 0) > 0 then

            left[quality] = left[quality] - 1

        else

            table.insert(
                gone,
                quality
            )
        end
    end


    return gone
end


-- The plain rounds in after that were not there before:
-- the ones vanilla has just created.
local function plainAppeared(
    before,
    after
)

    local known = {}


    for _,
        item
    in ipairs(
        before
    )
    do

        known[item] = true
    end


    local appeared = {}


    for _,
        item
    in ipairs(
        after
    )
    do

        if not known[item] then

            table.insert(
                appeared,
                item
            )
        end
    end


    return appeared
end


------------------------------------------------
-- SETTLE: the record follows what changed
------------------------------------------------
--
-- record        the container's record, already in step
--               with liveBefore
-- liveBefore, liveAfter
--               what the container held around the call
-- before, after the two censuses of the loose rounds
--
-- Returns the new record. Changes no item except the new
-- loose rounds, which get their qualities.
------------------------------------------------

function AC_QualityCarrier.settle(
    record,
    liveBefore,
    liveAfter,
    before,
    after
)

    local delta =
        liveAfter - liveBefore


    if delta > 0 then

        -- Rounds went in. Only rounds that left the
        -- inventory can have been handloaded ones.
        local leftInventory =
            math.max(0, before.count - after.count)


        local gone =
            qualitiesGone(
                before.qualities,
                after.qualities
            )


        local handloaded =
            math.min(#gone, delta, leftInventory)


        for index = 1, handloaded do

            record =
                AC_QualityTally.addHandloaded(
                    record,
                    gone[index]
                )
        end


        if delta > handloaded then

            record =
                AC_QualityTally.addFactory(
                    record,
                    delta - handloaded
                )
        end

    elseif delta < 0 then

        local left =
            -delta


        -- As many as appeared as loose rounds were
        -- unloaded; the rest were fired.
        local appeared =
            math.max(0, after.count - before.count)


        local unloaded =
            math.min(appeared, left)


        if unloaded > 0 then

            local rest,
                  out =
                AC_QualityTally.unload(
                    record,
                    unloaded
                )


            record = rest


            local fresh =
                plainAppeared(
                    before.plain,
                    after.plain
                )


            for index,
                quality
            in ipairs(
                out and out.qualities or {}
            )
            do

                -- A quality with no new round to carry
                -- it is dropped: toward factory.
                if fresh[index] then

                    AC_CaseQuality.setRoundQuality(
                        fresh[index],
                        quality
                    )
                end
            end
        end


        if left > unloaded then

            local _,
                  stayed =
                AC_QualityTally.split(
                    record,
                    left - unloaded
                )


            record = stayed
        end
    end


    -- Whatever the arithmetic above did, the record
    -- describes what the container holds now.
    return (AC_QualityTally.reconcile(record, liveAfter))
end


------------------------------------------------
-- WARNINGS (once each)
------------------------------------------------

local function warnOnce(
    text
)

    AC_QualityCarrier.warned =
        AC_QualityCarrier.warned or {}


    if AC_QualityCarrier.warned[text] then
        return
    end


    AC_QualityCarrier.warned[text] = true


    print(
        "[AmmoMaking] WARNING: quality tracking: "
        .. text
    )
end


------------------------------------------------
-- THE THREE KINDS OF MOVE
------------------------------------------------
--
-- Each returns a context from "before" and takes it in
-- "after". A before that returns nil means "nothing to
-- follow here"; the wrapper then only calls vanilla.
------------------------------------------------

-- Loose rounds <-> one container (a magazine or a gun).
local function beforeRounds(
    character,
    container
)

    local roundType =
        AC_QualityCarrier.getRoundType(container)


    if not character
        or not roundType
    then
        return nil
    end


    local record,
          writable =
        AC_QualityCarrier.observe(container)


    if not writable then
        return nil
    end


    return {

        character = character,

        container = container,

        roundType = roundType,

        record = record,

        live = AC_QualityCarrier.liveRounds(container),

        census = AC_QualityCarrier.census(character, roundType),
    }
end


local function afterRounds(
    context
)

    local liveAfter =
        AC_QualityCarrier.liveRounds(context.container)


    local record =
        AC_QualityCarrier.settle(
            context.record,
            context.live,
            liveAfter,
            context.census,
            AC_QualityCarrier.census(context.character, context.roundType)
        )


    AC_QualityCarrier.write(
        context.container,
        record
    )
end


-- A magazine goes into a gun: the magazine item is
-- destroyed and its count becomes the gun's.
local function beforeInsert(
    character,
    gun,
    magazine
)

    if not gun
        or not magazine
    then
        return nil
    end


    local gunRecord,
          gunWritable =
        AC_QualityCarrier.observe(gun)

    local magazineRecord,
          magazineWritable =
        AC_QualityCarrier.observe(magazine)


    if not gunWritable
        or not magazineWritable
    then
        return nil
    end


    return {

        gun = gun,

        magazine = magazine,

        gunRecord = gunRecord,

        magazineRecord = magazineRecord,

        wasInside = gun:isContainsClip(),
    }
end


local function afterInsert(
    context
)

    local gun =
        context.gun


    -- Nothing was inserted (vanilla refused): leave both
    -- records as they were.
    if context.wasInside
        or not gun:isContainsClip()
    then
        return
    end


    local merged =
        AC_QualityTally.merge(
            context.gunRecord,
            context.magazineRecord
        )


    AC_QualityCarrier.write(
        gun,
        (AC_QualityTally.reconcile(merged, AC_QualityCarrier.liveRounds(gun)))
    )


    -- The magazine item is gone; so is its record.
    AC_QualityCarrier.write(
        context.magazine,
        nil
    )
end


-- The magazine comes out of a gun: a NEW magazine item is
-- made and takes the gun's count; the chambered round
-- stays.
local function magazinesCarried(
    character,
    magazineType
)

    local known = {}


    local items =
        character:getInventory():getItemsFromFullType(
            magazineType,
            true
        )


    if items then

        for index = 0, items:size() - 1 do
            known[items:get(index)] = true
        end
    end


    return known, items
end


local function beforeEject(
    character,
    gun
)

    if not character
        or not gun
        or not gun:isContainsClip()
    then
        return nil
    end


    local record,
          writable =
        AC_QualityCarrier.observe(gun)


    if not writable then
        return nil
    end


    local magazineType =
        gun:getMagazineType()


    if not magazineType then
        return nil
    end


    return {

        character = character,

        gun = gun,

        record = record,

        inMagazine = tonumber(gun:getCurrentAmmoCount()) or 0,

        magazineType = magazineType,

        carried = magazinesCarried(character, magazineType),
    }
end


local function afterEject(
    context
)

    local gun =
        context.gun


    if gun:isContainsClip() then
        return
    end


    local stays,
          leaves =
        AC_QualityTally.transfer(
            context.record,
            nil,
            context.inMagazine
        )


    AC_QualityCarrier.write(
        gun,
        (AC_QualityTally.reconcile(stays, AC_QualityCarrier.liveRounds(gun)))
    )


    -- The new magazine is the one of that type the
    -- character did not carry before. If it cannot be
    -- found, its rounds are factory rounds from now on.
    local _,
          items =
        magazinesCarried(
            context.character,
            context.magazineType
        )


    if not items then
        return
    end


    for index = 0, items:size() - 1 do

        local item =
            items:get(index)


        if not context.carried[item] then

            AC_QualityCarrier.write(
                item,
                (AC_QualityTally.reconcile(leaves, AC_QualityCarrier.liveRounds(item)))
            )


            return
        end
    end
end


------------------------------------------------
-- THE SHOT
------------------------------------------------
--
-- Listener on Events.OnWeaponSwingHitPoint, added after
-- vanilla's own (which registered when its file loaded),
-- so the gun already holds one round fewer. The rounds
-- the record still describes and the gun no longer holds
-- were fired: they leave by the tally's even split, not
-- by reconcile's rounding. Returns what was fired, for
-- AC_QualityEffects:
--
--   { rounds, handloaded, qualitySum, before = record }
--
-- or nil when there is nothing to say.
------------------------------------------------

function AC_QualityCarrier.onShot(
    character,
    weapon
)

    if not weapon
        or not weapon.isRanged
        or not weapon:isRanged()
        or not AC_QualityCarrier.getRoundType(weapon)
    then
        return nil
    end


    local raw =
        stored(weapon)


    -- A gun with no record holds factory rounds; nothing
    -- to follow, and nothing is written on it.
    if raw == nil then
        return nil
    end


    local record,
          status =
        AC_QualityTally.repair(raw)


    if status == AC_QualityTally.NEWER then
        return nil
    end


    local live =
        AC_QualityCarrier.liveRounds(weapon)


    local fired = nil


    if record.count > live then

        local taken,
              stayed =
            AC_QualityTally.split(
                record,
                record.count - live
            )


        fired = {

            rounds = taken.count,

            handloaded = taken.handloaded,

            qualitySum = taken.qualitySum,

            before = record,
        }


        record = stayed
    end


    AC_QualityCarrier.write(
        weapon,
        (AC_QualityTally.reconcile(record, live))
    )


    return fired
end


------------------------------------------------
-- WRAPPING
------------------------------------------------
--
-- wrap(original, before, after, events):
--
--   before(self, ...) -> context or nil
--   after(context)
--   events            for an animEvent function: the
--                     event names worth observing. Any
--                     other event goes straight to
--                     vanilla, so the inventory is not
--                     scanned for sound events.
------------------------------------------------

function AC_QualityCarrier.wrap(
    original,
    before,
    after,
    events
)

    return function(self, event, ...)

        if events
            and not events[event]
        then
            return original(self, event, ...)
        end


        local prepared,
              context =
            pcall(
                before,
                self,
                event,
                ...
            )


        if not prepared then

            warnOnce("could not look at a reload before it happened: " .. tostring(context))

            context = nil
        end


        local result = original(self, event, ...)


        if context then

            local settled,
                  err =
                pcall(
                    after,
                    context
                )


            if not settled then
                warnOnce("could not follow a reload: " .. tostring(err))
            end
        end


        return result
    end
end


-- What is wrapped: the seven functions of
-- docs/AMMO_QUALITY_RUNTIME_DESIGN.md 1, by the vanilla
-- class table and field they live in.
AC_QualityCarrier.WRAPS = {

    {
        key = "loadMagazine",

        global = "ISLoadBulletsInMagazine",

        field = "animEvent",

        events = { InsertBullet = true },

        before = function(self) return beforeRounds(self.character, self.magazine) end,

        after = afterRounds,
    },

    {
        key = "unloadMagazine",

        global = "ISUnloadBulletsFromMagazine",

        field = "animEvent",

        events = { RemoveBullet = true },

        before = function(self) return beforeRounds(self.character, self.magazine) end,

        after = afterRounds,
    },

    {
        key = "insertMagazine",

        global = "ISInsertMagazine",

        field = "loadAmmo",

        before = function(self) return beforeInsert(self.character, self.gun, self.magazine) end,

        after = afterInsert,
    },

    {
        key = "ejectMagazine",

        global = "ISEjectMagazine",

        field = "unloadAmmo",

        before = function(self) return beforeEject(self.character, self.gun) end,

        after = afterEject,
    },

    {
        key = "loadFirearm",

        global = "ISReloadWeaponAction",

        field = "loadAmmo",

        before = function(self) return beforeRounds(self.character, self.gun) end,

        after = afterRounds,
    },

    {
        key = "unloadFirearm",

        global = "ISUnloadBulletsFromFirearm",

        field = "animEvent",

        events = { playReloadSound = true },

        before = function(self) return beforeRounds(self.character, self.gun) end,

        after = afterRounds,
    },

    {
        key = "rack",

        global = "ISRackFirearm",

        field = "rackBullet",

        before = function(self) return beforeRounds(self.character, self.gun) end,

        after = afterRounds,
    },
}


local function guardedShot(
    character,
    weapon
)

    local ok,
          fired =
        pcall(
            AC_QualityCarrier.onShot,
            character,
            weapon
        )


    if not ok then

        warnOnce("could not follow a shot: " .. tostring(fired))


        return
    end


    -- The locked effects feature; does nothing unless it
    -- is on.
    if fired
        and AC_QualityEffects
        and AC_QualityEffects.afterShot
    then

        local effectOk,
              effectError =
            pcall(
                AC_QualityEffects.afterShot,
                character,
                weapon,
                fired
            )


        if not effectOk then
            warnOnce("a firing effect failed: " .. tostring(effectError))
        end
    end
end


------------------------------------------------
-- INSTALL
------------------------------------------------
--
-- Wraps what is there, adds the shot listener, does
-- nothing twice. AC_QualityCarrier.installed maps each
-- part's key (and "shot") to whether it was installed.
------------------------------------------------

function AC_QualityCarrier.install()

    if AC_QualityCarrier.installed then
        return AC_QualityCarrier.installed
    end


    local done = {}

    local count = 0


    for _,
        part
    in ipairs(
        AC_QualityCarrier.WRAPS
    )
    do

        local class =
            _G[part.global]


        if type(class) == "table"
            and type(class[part.field]) == "function"
        then

            class[part.field] =
                AC_QualityCarrier.wrap(
                    class[part.field],
                    part.before,
                    part.after,
                    part.events
                )


            done[part.key] = true

            count = count + 1

        else

            done[part.key] = false

            warnOnce(part.global .. "." .. part.field .. " is not a function on this build; rounds moved by it are not followed and will read as factory rounds")
        end
    end


    if Events
        and Events.OnWeaponSwingHitPoint
        and Events.OnWeaponSwingHitPoint.Add
    then

        Events.OnWeaponSwingHitPoint.Add(guardedShot)


        done.shot = true

    else

        done.shot = false

        warnOnce("Events.OnWeaponSwingHitPoint is not available; shots are not followed")
    end


    AC_QualityCarrier.installed = done


    print(
        "[AmmoMaking] Quality tracking installed ("
        .. count
        .. " of "
        .. #AC_QualityCarrier.WRAPS
        .. " reload functions, shot "
        .. tostring(done.shot)
        .. ")"
    )


    return done
end


function AC_QualityCarrier.installIfEnabled()

    if not AC_Features.isEnabled("qualityTracking") then
        return nil
    end


    return AC_QualityCarrier.install()
end


if Events
    and Events.OnGameStart
then

    Events.OnGameStart.Add(
        AC_QualityCarrier.installIfEnabled
    )
end


------------------------------------------------
-- WHAT A LOAD IS (for inspection)
------------------------------------------------
--
-- Read only. Returns nil for an item that holds no
-- rounds or has no calibre, otherwise
--
--   { rounds, handloaded, factory, meanQuality, share }
--
-- from the record as it would read now. Nothing is
-- written: inspecting never repairs.
------------------------------------------------

function AC_QualityCarrier.describe(
    item
)

    if not item
        or not AC_QualityCarrier.getRoundType(item)
    then
        return nil
    end


    local live =
        AC_QualityCarrier.liveRounds(item)


    local record =
        AC_QualityTally.reconcile(
            stored(item),
            live
        )


    return {

        rounds = live,

        handloaded = record.handloaded,

        factory = AC_QualityTally.getFactory(record),

        meanQuality = AC_QualityTally.getMeanQuality(record),

        share = AC_QualityTally.getHandloadedShare(record),
    }
end


------------------------------------------------
-- GAME-START CHECK (when the feature is on)
------------------------------------------------

AC_Compat.FEATURE_CHECKS.qualityTracking =
    function(
        results,
        tools
    )

        -- This check and the installation are both
        -- game-start listeners; install now if this one
        -- runs first (it does nothing twice).
        local installed =
            AC_QualityCarrier.installIfEnabled()


        if not installed then

            tools.addResult(
                results,
                "WARNING",
                "quality tracking is not installed",
                "the feature is on but nothing was hooked at game start"
            )


            return
        end


        for _,
            part
        in ipairs(
            AC_QualityCarrier.WRAPS
        )
        do

            tools.addResult(
                results,
                installed[part.key] and "OK" or "WARNING",
                "quality tracking: " .. part.global .. "." .. part.field,
                "not a function on this build; rounds moved by it read as factory rounds"
            )
        end


        tools.addResult(
            results,
            installed.shot and "OK" or "WARNING",
            "quality tracking: the shot",
            "Events.OnWeaponSwingHitPoint is not available"
        )
    end


print(
    "[AmmoMaking] Quality tracking loaded"
)
