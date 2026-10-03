-- Ammo Making - Spent cases
-- Project Zomboid Build 42.20
--
-- EXPERIMENTAL, NOT YET SEEN IN GAME. Feature "spentCases"
-- (AC_Features): nothing in this file registers or wraps
-- anything unless the add-on mod AmmoMakingSpentCases is
-- active, the game is single player, and no other mod
-- that leaves casings is running. The add-on carries the
-- spent-case items and their scrapping recipes; this file
-- is the logic.
--
-- WHAT IT DOES
--
-- A fired round can leave its case behind. Which item is
-- decided by the calibre model (calibre.spentCase); this
-- file names no calibre. A spent case is NOT a case: it
-- cannot be loaded again. Its only use is to be scrapped,
-- at a worse rate than unused brass (AC_Recycling, source
-- "spent"), for no XP.
--
-- THE ECONOMY (docs/SPENT_CASE_RESEARCH.md, 4.2)
--
-- Every round leaves brass, factory or handloaded: where a
-- round came from does not survive loading (vanilla keeps
-- a count), so no rule may depend on it. To keep looted
-- ammunition from becoming a brass mine, two losses stack:
--
--   recoveryPercent   of a hundred rounds fired, how many
--                     leave a case that is found (50)
--   scrap recovery    a quarter of a spent case's brass
--                     comes back as scrap (AC_Recycling)
--
-- One round in eight, in brass. A hundred looted rounds
-- of the smallest pistol size are six brass scrap, a
-- little over half an ingot.
--
-- WHEN A CASE LEAVES THE GUN
--
-- No single moment fits every firearm, and vanilla's own
-- Lua already says which is which (ISReloadWeaponAction
-- .onShoot, 42.20.4). The two script flags it branches on
-- are the adapters here; no weapon is named:
--
--   not RackAfterShoot and not ManuallyRemoveSpentRounds
--       self-loading pistols and rifles, and the double
--       barrel: the case is thrown clear AT THE SHOT
--       (where vanilla plays the shell-fall sound)
--   ManuallyRemoveSpentRounds
--       revolvers: the cases stay in the cylinder
--       (vanilla counts them, getSpentRoundCount) and all
--       leave together WHEN IT IS OPENED
--   RackAfterShoot
--       pump, bolt and lever guns: the spent case stays
--       chambered and leaves AT THE RACK that follows
--
-- The last two happen in one vanilla function,
-- ejectSpentRounds(), which exists with the same body on
-- ISRackFirearm and on ISReloadWeaponAction. It is
-- wrapped on both: the wrapper reads how many spent
-- rounds the gun holds, calls the original, and only
-- then leaves the cases. It never changes the original's
-- arguments or result, and a failure of the mod's part
-- is caught and logged: vanilla's reload is never broken
-- by it.
--
-- The shot is an added listener on
-- Events.OnWeaponSwingHitPoint, the event vanilla's own
-- onShoot uses to take the round. It does not fire on a
-- dry fire.
--
-- Vanilla's spent state is not saved (HandWeapon.save):
-- a revolver holding fired cases across a save and load
-- has lost them. That is a loss, never a gain.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: everything that
-- touches the engine. Listed in docs/INGAME_VALIDATION.md
-- and docs/SPENT_CASE_RESEARCH.md 6.

require "AC_Features"
require "AC_Calibres"
require "AC_Compat"

AC_SpentCases = AC_SpentCases or {}


------------------------------------------------
-- CONFIG (tunable)
------------------------------------------------

AC_SpentCases.CONFIG = {

    -- Of a hundred rounds fired, how many leave a case
    -- that can be found. Whole number, 0 to 100. The rest
    -- roll under the furniture. This is the default; a
    -- save may set its own in the sandbox options
    -- (sandboxOption, shipped by the add-on).
    recoveryPercent = 50,

    sandboxOption = "SpentCaseRecovery",

    -- "ground": on the shooter's square, to be picked up.
    -- "inventory": straight into the shooter's inventory.
    -- The ground is what happens to brass; the inventory
    -- is tidier and costs the world no items.
    placement = "ground",

    -- Never more cases for one event than this, whatever
    -- the gun reports: a guard against a damaged count.
    maximumPerEvent = 30,

    -- The spent item of a case: its id and its name.
    itemPrefix = "Spent",

    namePrefix = "Spent ",

    -- The clean case's name starts with this; the spent
    -- one's with namePrefix instead.
    cleanNamePrefix = "Empty ",
}


------------------------------------------------
-- CALIBRE MAPPING (built once)
------------------------------------------------
--
-- round item -> spent case item, from the calibre model.
------------------------------------------------

local spentByRound = nil


function AC_SpentCases.getSpentCaseForRound(
    roundType
)

    if not spentByRound then

        spentByRound = {}


        for _,
            calibre
        in ipairs(
            AC_Calibres.LIST
        )
        do

            spentByRound[calibre.round] =
                calibre.spentCase
        end
    end


    return spentByRound[roundType]
end


-- Every spent-case item, in calibre order.
function AC_SpentCases.getItems()

    local items = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        table.insert(
            items,
            calibre.spentCase
        )
    end


    return items
end


------------------------------------------------
-- ITEM DEFINITIONS (for the generator)
------------------------------------------------
--
-- The add-on's item script is generated. A spent case
-- looks and weighs like the case it was: cleanFields is
-- a function that returns the script fields of an item
-- of the main mod (tests/render_addons.lua reads them
-- from AC_Items.txt), and everything but the name is
-- taken from the calibre's own case. PLACEHOLDER_VISUAL:
-- the icon and world model are therefore the same
-- vanilla placeholders the clean case uses.
--
-- Returns a list of
--   { name, fullType, displayName, fields = { { key, value }, ... } }
------------------------------------------------

AC_SpentCases.ITEM_FIELDS = {
    "DisplayCategory",
    "ItemType",
    "Weight",
    "Icon",
    "WorldStaticModel",
    "Tags",
}


function AC_SpentCases.buildItems(
    cleanFields
)

    local config =
        AC_SpentCases.CONFIG


    local items = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local clean =
            cleanFields(calibre.case) or {}


        local cleanName =
            tostring(clean.DisplayName or "")


        local displayName =
            config.namePrefix .. cleanName


        if string.sub(cleanName, 1, #config.cleanNamePrefix) == config.cleanNamePrefix then

            displayName =
                config.namePrefix
                .. string.sub(cleanName, #config.cleanNamePrefix + 1)
        end


        local fields = {
            { "DisplayName", displayName },
        }


        for _,
            key
        in ipairs(
            AC_SpentCases.ITEM_FIELDS
        )
        do

            if clean[key] ~= nil then

                table.insert(
                    fields,
                    { key, clean[key] }
                )
            end
        end


        table.insert(
            items,
            {
                name = string.match(calibre.spentCase, "([^%.]+)$"),

                fullType = calibre.spentCase,

                displayName = displayName,

                fields = fields,
            }
        )
    end


    return items
end


------------------------------------------------
-- WHAT LEAVES THE GUN, AND WHEN
------------------------------------------------

-- The spent-case item for a firearm, or nil when the mod
-- has no calibre for what it fires.
function AC_SpentCases.getSpentCaseFor(
    weapon
)

    if not weapon
        or not weapon.getAmmoType
    then
        return nil
    end


    local ammoType =
        weapon:getAmmoType()


    if not ammoType
        or not ammoType.getItemKey
    then
        return nil
    end


    return
        AC_SpentCases.getSpentCaseForRound(
            ammoType:getItemKey()
        )
end


-- Does this firearm throw its case clear at the shot?
-- The same two flags vanilla's onShoot branches on.
function AC_SpentCases.ejectsAtShot(
    weapon
)

    return
        not weapon:isRackAfterShoot()
        and not weapon:isManuallyRemoveSpentRounds()
end


-- How many spent rounds would leave the gun if it were
-- opened or racked now. Mirrors vanilla's
-- ejectSpentRounds(): the counted ones, or else the one
-- that is chambered.
function AC_SpentCases.countHeld(
    weapon
)

    if not weapon then
        return 0
    end


    local count =
        tonumber(weapon:getSpentRoundCount()) or 0


    if count > 0 then
        return count
    end


    if weapon:isSpentRoundChambered() then
        return 1
    end


    return 0
end


------------------------------------------------
-- RECOVERY (how many of the fired cases are found)
------------------------------------------------

-- The percentage in force: the save's sandbox option when
-- it is a whole number from 0 to 100, otherwise the
-- default of CONFIG. Anything else in the option (a
-- word, a fraction, 250) is not a setting and is ignored.
function AC_SpentCases.getRecoveryPercent()

    local config =
        AC_SpentCases.CONFIG


    local options =
        type(SandboxVars) == "table"
        and SandboxVars[AC_Features.SANDBOX_TABLE]
        or nil


    local chosen =
        type(options) == "table"
        and options[config.sandboxOption]
        or nil


    if type(chosen) == "number"
        and chosen == math.floor(chosen)
        and chosen >= 0
        and chosen <= 100
    then
        return chosen
    end


    return tonumber(config.recoveryPercent) or 0
end


function AC_SpentCases.roll(
    fired
)

    local config =
        AC_SpentCases.CONFIG


    fired =
        math.floor(tonumber(fired) or 0)


    -- A count that is not a sane number of rounds leaves
    -- nothing rather than a pile.
    if fired ~= fired
        or fired < 1
    then
        return 0
    end


    if fired > config.maximumPerEvent then
        fired = config.maximumPerEvent
    end


    local percent =
        AC_SpentCases.getRecoveryPercent()


    if percent <= 0 then
        return 0
    end


    if percent >= 100 then
        return fired
    end


    local found = 0


    for _ = 1, fired do

        if ZombRand(100) < percent then
            found = found + 1
        end
    end


    return found
end


------------------------------------------------
-- LEAVING THE CASES
------------------------------------------------
--
-- On the ground: the item factory and
-- IsoGridSquare:AddWorldInventoryItem(item, x, y, z), the
-- same two calls mining uses to drop ore (that path was
-- seen working in game). In the inventory: AddItem.
--
-- Returns how many were placed.
------------------------------------------------

local function createItem(
    fullType
)

    local factory =
        instanceItem
        or (
            InventoryItemFactory
            and InventoryItemFactory.CreateItem
        )


    if not factory then
        return nil
    end


    local ok,
          item =
        pcall(
            factory,
            fullType
        )


    return ok and item or nil
end


function AC_SpentCases.leave(
    character,
    fullType,
    count
)

    if not character
        or not fullType
        or count < 1
    then
        return 0
    end


    local toGround =
        AC_SpentCases.CONFIG.placement ~= "inventory"


    local square =
        toGround
        and character.getCurrentSquare
        and character:getCurrentSquare()
        or nil


    local placed = 0


    for _ = 1, count do

        local item =
            createItem(fullType)


        if not item then
            break
        end


        if square then

            square:AddWorldInventoryItem(
                item,
                ZombRandFloat(0.1, 0.9),
                ZombRandFloat(0.1, 0.9),
                0
            )

        else

            -- No square (or the inventory was asked for).
            character:getInventory():AddItem(item)
        end


        placed = placed + 1
    end


    return placed
end


-- fired rounds of this weapon have just left it as cases.
function AC_SpentCases.casesLeft(
    character,
    weapon,
    fired
)

    local fullType =
        AC_SpentCases.getSpentCaseFor(weapon)


    if not fullType then
        return 0
    end


    return
        AC_SpentCases.leave(
            character,
            fullType,
            AC_SpentCases.roll(fired)
        )
end


------------------------------------------------
-- THE SHOT
------------------------------------------------
--
-- Listener on Events.OnWeaponSwingHitPoint(character,
-- weapon). The guards are vanilla's own, in vanilla's
-- order: melee is not a shot, and nothing is consumed
-- with unlimited ammunition in debug.
------------------------------------------------

function AC_SpentCases.onShot(
    character,
    weapon
)

    if not weapon
        or not weapon.isRanged
        or not weapon:isRanged()
    then
        return 0
    end


    if type(getDebug) == "function"
        and getDebug()
        and character
        and character.isUnlimitedAmmo
        and character:isUnlimitedAmmo()
    then
        return 0
    end


    if not AC_SpentCases.ejectsAtShot(weapon) then
        return 0
    end


    return
        AC_SpentCases.casesLeft(
            character,
            weapon,
            weapon:getAmmoPerShoot()
        )
end


------------------------------------------------
-- THE EJECT (revolvers; pump, bolt and lever guns)
------------------------------------------------
--
-- wrapEject(original) returns the function that replaces
-- an action's ejectSpentRounds: count, call the original
-- with exactly what it was given, then leave the cases.
-- The mod's two steps are pcall-guarded; the original is
-- not, so it behaves exactly as it would alone.
------------------------------------------------

local function warnOnce(
    text
)

    AC_SpentCases.warned =
        AC_SpentCases.warned or {}


    if AC_SpentCases.warned[text] then
        return
    end


    AC_SpentCases.warned[text] = true


    print(
        "[AmmoMaking] WARNING: spent cases: "
        .. text
    )
end


function AC_SpentCases.wrapEject(
    original
)

    return function(self, ...)

        local held = 0


        local counted,
              countError =
            pcall(
                function()

                    held =
                        AC_SpentCases.countHeld(self.gun)
                end
            )


        if not counted then

            held = 0

            warnOnce("could not read the spent rounds of a gun: " .. tostring(countError))
        end


        -- Vanilla's function returns nothing; whatever it
        -- returns is handed on.
        local result = original(self, ...)


        if held > 0 then

            local left,
                  leaveError =
                pcall(
                    AC_SpentCases.casesLeft,
                    self.character,
                    self.gun,
                    held
                )


            if not left then
                warnOnce("could not leave spent cases: " .. tostring(leaveError))
            end
        end


        return result
    end
end


local function guardedShot(
    character,
    weapon
)

    local ok,
          err =
        pcall(
            AC_SpentCases.onShot,
            character,
            weapon
        )


    if not ok then
        warnOnce("the shot listener failed: " .. tostring(err))
    end
end


------------------------------------------------
-- INSTALL
------------------------------------------------
--
-- Wraps the two vanilla functions and adds the listener.
-- Does nothing twice. If a function is not where 42.20.4
-- has it, that part is skipped and reported; the rest
-- still works.
--
-- AC_SpentCases.installed describes what was done:
--   { shot = bool, rack = bool, reload = bool }
------------------------------------------------

AC_SpentCases.EJECT_ACTIONS = {
    { key = "rack", global = "ISRackFirearm" },
    { key = "reload", global = "ISReloadWeaponAction" },
}


function AC_SpentCases.install()

    if AC_SpentCases.installed then
        return AC_SpentCases.installed
    end


    local done = {

        shot = false,

        rack = false,

        reload = false,
    }


    for _,
        action
    in ipairs(
        AC_SpentCases.EJECT_ACTIONS
    )
    do

        local class =
            _G[action.global]


        if type(class) == "table"
            and type(class.ejectSpentRounds) == "function"
        then

            class.ejectSpentRounds =
                AC_SpentCases.wrapEject(
                    class.ejectSpentRounds
                )


            done[action.key] = true

        else

            warnOnce(action.global .. ".ejectSpentRounds is not a function on this build; cases from that action are not left")
        end
    end


    if Events
        and Events.OnWeaponSwingHitPoint
        and Events.OnWeaponSwingHitPoint.Add
    then

        Events.OnWeaponSwingHitPoint.Add(guardedShot)


        done.shot = true

    else

        warnOnce("Events.OnWeaponSwingHitPoint is not available; cases at the shot are not left")
    end


    AC_SpentCases.installed = done


    print(
        "[AmmoMaking] Spent cases installed (shot "
        .. tostring(done.shot)
        .. ", rack "
        .. tostring(done.rack)
        .. ", reload "
        .. tostring(done.reload)
        .. "; "
        .. tostring(AC_SpentCases.getRecoveryPercent())
        .. " % found, placed on the "
        .. tostring(AC_SpentCases.CONFIG.placement)
        .. ")"
    )


    return done
end


-- At game start, and only when the feature is on: then
-- the add-on's items exist, the game is single player
-- and no other casing mod is active.
function AC_SpentCases.installIfEnabled()

    if not AC_Features.isEnabled("spentCases") then
        return nil
    end


    return AC_SpentCases.install()
end


if Events
    and Events.OnGameStart
then

    Events.OnGameStart.Add(
        AC_SpentCases.installIfEnabled
    )
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------

function AC_SpentCases.validate()

    local config =
        AC_SpentCases.CONFIG


    local problems = {}


    local percent =
        config.recoveryPercent


    if type(percent) ~= "number"
        or percent ~= math.floor(percent)
        or percent < 0
        or percent > 100
    then

        table.insert(
            problems,
            "spent cases: recoveryPercent must be a whole number from 0 to 100"
        )
    end


    if config.placement ~= "ground"
        and config.placement ~= "inventory"
    then

        table.insert(
            problems,
            "spent cases: placement must be ground or inventory"
        )
    end


    if type(config.maximumPerEvent) ~= "number"
        or config.maximumPerEvent < 1
    then

        table.insert(
            problems,
            "spent cases: maximumPerEvent must be at least 1"
        )
    end


    local seen = {}


    for _,
        calibre
    in ipairs(
        AC_Calibres.LIST
    )
    do

        local spent =
            calibre.spentCase


        if type(spent) ~= "string"
            or spent == ""
        then

            table.insert(
                problems,
                "spent cases: " .. tostring(calibre.id) .. " has no spent case"
            )

        elseif spent == calibre.case then

            table.insert(
                problems,
                "spent cases: " .. tostring(calibre.id) .. " leaves its unused case, which could be loaded again"
            )

        elseif seen[spent] then

            table.insert(
                problems,
                "spent cases: " .. spent .. " is the spent case of two calibres"
            )
        end


        seen[spent or calibre.id] = true
    end


    return problems
end


------------------------------------------------
-- GAME-START CHECK (when the feature is on)
------------------------------------------------

if AC_Compat
    and AC_Compat.FEATURE_CHECKS
then

    AC_Compat.FEATURE_CHECKS.spentCases =
        function(
            results,
            tools
        )

            for _,
                problem
            in ipairs(
                AC_SpentCases.validate()
            )
            do

                tools.addResult(
                    results,
                    "WARNING",
                    problem,
                    "AC_SpentCases.CONFIG / AC_Calibres"
                )
            end


            local manager =
                type(getScriptManager) == "function"
                and tools.safe(getScriptManager)
                or nil


            local missing = {}

            local found = 0


            for _,
                fullType
            in ipairs(
                AC_SpentCases.getItems()
            )
            do

                local script =
                    manager
                    and tools.safe(
                        function()

                            return
                                manager:FindItem(fullType)
                        end
                    )


                if script then

                    found = found + 1

                else

                    table.insert(
                        missing,
                        fullType
                    )
                end
            end


            if #missing == 0 then

                tools.addResult(
                    results,
                    "OK",
                    "spent case items (" .. found .. ")"
                )

            else

                tools.addResult(
                    results,
                    "WARNING",
                    "spent case items missing: " .. table.concat(missing, ", "),
                    "the add-on is active but its item script did not load; those calibres leave nothing"
                )
            end


            -- This check and the installation are both
            -- game-start listeners, and this one may run
            -- first: install now (it does nothing twice).
            local installed =
                AC_SpentCases.installIfEnabled()


            if not installed then

                tools.addResult(
                    results,
                    "WARNING",
                    "spent case hooks are not installed",
                    "the feature is on but nothing was hooked at game start"
                )

            else

                for _,
                    part
                in ipairs(
                    { "shot", "rack", "reload" }
                )
                do

                    tools.addResult(
                        results,
                        installed[part] and "OK" or "WARNING",
                        "spent case hook: " .. part,
                        "the vanilla function or event it attaches to was not found on this build"
                    )
                end
            end
        end
end


print(
    "[AmmoMaking] Spent cases loaded"
)
