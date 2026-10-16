-- Ammo Making - Skill books for the Ammo Making skill
-- Project Zomboid Build 42.20
--
-- Five volumes, read like vanilla's: each one trains two
-- levels of the skill (1-2, 3-4, 5-6, 7-8, 9-10) and,
-- while it is read, multiplies the Ammo Making XP the
-- character earns in that band. The items are ordinary
-- literature in media/scripts/AC_Items.txt; this file
-- holds what the script cannot say.
--
-- How vanilla does it, as read in the installed 42.20.4
-- files (docs/AMMUNITION_DESIGN.md, section 9.2):
--
--   The item script names the skill with a free string,
--     "SkillTrained = Carpentry". The engine stores it as
--     it is (JAR: Item.DoParam puts the trimmed value in
--     a String field; Literature.setSkillTrained). No perk
--     is looked up while scripts are parsed, so a skill
--     registered from Lua - as Ammo Making is - can be
--     named there, unlike SkillRequired / xpAward /
--     AutoLearnAll on a craftRecipe (CraftRecipe.Load:
--     PerkFactory$Perks.FromString, "Unknown skill").
--   The reading code is Lua and looks the string up in a
--     Lua table: SkillBook[item:getSkillTrained()], with
--     .perk and .maxMultiplier1 to 5 for the volumes of
--     level 1, 3, 5, 7 and 9 (FILE: media/lua/server/
--     XpSystem/XPSystem_SkillBook.lua; users in
--     shared/TimedActions/ISReadABook.lua, client/ISUI/
--     ISInventoryPaneContextMenu.lua, ISInventoryPane.lua,
--     ISLiteratureUI.lua).
--   Reading calls addXpMultiplier(character, perk,
--     multiplier, level, maxLevel) (JAR: LuaManager
--     $GlobalObject, IsoGameCharacter$XP.addXpMultiplier),
--     a map keyed by the Perk object; XP.AddXP(perk, amount)
--     - the call AmmoMakingSkill.addXP makes - multiplies
--     by XP.getMultiplier(perk) on its boosted path.
--
-- So the whole support of a modded skill book is ONE
-- entry in vanilla's table, SkillBook.AmmoMaking. The
-- table is created by a SERVER file
-- ("SkillBook = {};" at its top), and server Lua is
-- loaded after shared Lua and after OnGameBoot on a
-- client (JAR: GameLoadingState.enter, LuaManager
-- .LoadDirBase("server")), and again for every world:
-- an entry added from shared Lua at load would be wiped.
-- The entry is therefore added
--
--   1. by media/lua/server/AC_SkillBookRegistration.lua,
--      at load: LoadDirBase runs every vanilla file of a
--      folder before any mod file of it (JAR: the base
--      list is sorted and the mods' lists appended), so
--      vanilla's table exists by then;
--   2. again at OnGameStart (client, single player) and
--      OnServerStarted (dedicated server), which fire
--      after the server folder is loaded. Adding it twice
--      is harmless: an entry that is there is left alone.
--
-- Without the entry the books are not merely useless:
-- vanilla's inventory menu indexes
-- SkillBook[...].perk without a nil check
-- (ISInventoryPaneContextMenu.lua), so reading would
-- raise an error. AC_Compat reports a missing entry.
--
-- The multipliers are vanilla's own, the smaller of its
-- two tables: the one it gives the firearm skills Aiming
-- and Reloading ("intentionally ... less of a xp
-- multiplier"), not the crafting table (3, 5, 8, 12, 16).
-- Why: docs/AMMUNITION_DESIGN.md 9.2.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the entry is
-- in place when a book is read (single player and
-- dedicated server), that the custom perk is accepted by
-- addXpMultiplier and getPerkLevel, and that the reading
-- window and the "too complicated / too simple" menu work
-- for these books.

require "AC_AmmoMakingSkill"

AC_SkillBooks = AC_SkillBooks or {}


------------------------------------------------
-- THE VOLUMES
------------------------------------------------
--
-- skill       what the items' SkillTrained names, and
--             the key in vanilla's SkillBook table
-- levels      levels trained per volume
--             (NumLevelsTrained); vanilla's is 2
-- VOLUMES     in order:
--   item        the item's full type
--   level       LvlSkillTrained: the first level the
--               volume trains; readable from one level
--               below it
--   pages       NumberOfPages, vanilla's for that level
--   multiplier  SkillBook.<skill>.maxMultiplier<n>: the
--               XP multiplier when the volume is read to
--               the end (vanilla grows it a tenth per
--               tenth of the pages)
--
-- Every number is vanilla's (tests/vanilla_snapshot.lua
-- records them from the installed game and the tests
-- compare).
------------------------------------------------

AC_SkillBooks.skill = "AmmoMaking"


AC_SkillBooks.levels = 2


AC_SkillBooks.VOLUMES = {

    { item = "AmmoMaking.BookAmmoMaking1", level = 1, pages = 220, multiplier = 1.5 },

    { item = "AmmoMaking.BookAmmoMaking2", level = 3, pages = 260, multiplier = 2.5 },

    { item = "AmmoMaking.BookAmmoMaking3", level = 5, pages = 300, multiplier = 4 },

    { item = "AmmoMaking.BookAmmoMaking4", level = 7, pages = 340, multiplier = 6 },

    { item = "AmmoMaking.BookAmmoMaking5", level = 9, pages = 380, multiplier = 8 },
}


-- The item ids, in volume order.
function AC_SkillBooks.getItems()

    local items = {}


    for _,
        volume
    in ipairs(
        AC_SkillBooks.VOLUMES
    )
    do

        table.insert(
            items,
            volume.item
        )
    end


    return items
end


-- The volume of an item id, or nil.
function AC_SkillBooks.getVolume(
    itemType
)

    for index,
        volume
    in ipairs(
        AC_SkillBooks.VOLUMES
    )
    do

        if volume.item == itemType then
            return volume, index
        end
    end


    return nil
end


------------------------------------------------
-- VALIDATION (pure)
------------------------------------------------
--
-- The volumes must cover the skill without a gap or an
-- overlap, one volume per vanilla multiplier key, and
-- each must be harder, longer and worth more than the
-- one before. Returns a list of problems, empty when the
-- table is sound.
------------------------------------------------

function AC_SkillBooks.validate(
    volumes
)

    volumes =
        volumes or AC_SkillBooks.VOLUMES


    local problems = {}


    local function problem(
        text
    )

        table.insert(
            problems,
            "skill books: " .. text
        )
    end


    -- Vanilla's reader knows exactly five volumes, by
    -- their first level (ISReadABook:new).
    if #volumes ~= 5 then
        problem("there must be five volumes, there are " .. #volumes)
    end


    local seen = {}


    for index,
        volume
    in ipairs(
        volumes
    )
    do

        local label =
            "volume " .. index


        if type(volume.item) ~= "string"
            or string.sub(volume.item, 1, 11) ~= "AmmoMaking."
        then
            problem(label .. " needs an item of the mod")
        elseif seen[volume.item] then
            problem(label .. " repeats " .. volume.item)
        end


        seen[tostring(volume.item)] = true


        local expectedLevel =
            1 + (index - 1) * AC_SkillBooks.levels


        if volume.level ~= expectedLevel then
            problem(label .. " must start at level " .. expectedLevel .. ", not " .. tostring(volume.level))
        end


        if type(volume.pages) ~= "number"
            or volume.pages <= 0
            or volume.pages ~= math.floor(volume.pages)
        then
            problem(label .. " needs a whole number of pages")
        end


        if type(volume.multiplier) ~= "number"
            or volume.multiplier <= 1
        then
            problem(label .. " must multiply XP by more than 1")
        end


        local previous =
            volumes[index - 1]


        if previous
            and type(previous.pages) == "number"
            and type(volume.pages) == "number"
            and volume.pages <= previous.pages
        then
            problem(label .. " must be longer than the one before")
        end


        if previous
            and type(previous.multiplier) == "number"
            and type(volume.multiplier) == "number"
            and volume.multiplier <= previous.multiplier
        then
            problem(label .. " must be worth more than the one before")
        end
    end


    local last =
        volumes[#volumes]


    if last
        and type(last.level) == "number"
        and last.level + AC_SkillBooks.levels - 1 ~= 10
    then
        problem("the last volume must train up to level 10")
    end


    return problems
end


------------------------------------------------
-- VANILLA'S TABLE ENTRY (pure)
------------------------------------------------
--
-- What SkillBook.AmmoMaking holds: the perk object and
-- maxMultiplier1 to 5, as vanilla's own entries do.
------------------------------------------------

function AC_SkillBooks.buildEntry(
    perk
)

    local entry = {

        perk = perk,
    }


    for index,
        volume
    in ipairs(
        AC_SkillBooks.VOLUMES
    )
    do

        entry["maxMultiplier" .. index] =
            volume.multiplier
    end


    return entry
end


-- Whether a table holds our entry, for this perk, with
-- these multipliers.
function AC_SkillBooks.isRegistered(
    skillBook,
    perk
)

    if skillBook == nil then
        skillBook = SkillBook
    end


    if perk == nil then
        perk = AmmoMakingSkill and AmmoMakingSkill.perk
    end


    if type(skillBook) ~= "table" then
        return false
    end


    local entry =
        skillBook[AC_SkillBooks.skill]


    if type(entry) ~= "table"
        or perk == nil
        or entry.perk ~= perk
    then
        return false
    end


    for key,
        value
    in pairs(
        AC_SkillBooks.buildEntry(perk)
    )
    do

        if entry[key] ~= value then
            return false
        end
    end


    return true
end


------------------------------------------------
-- REGISTRATION
------------------------------------------------
--
-- Puts the entry into vanilla's table. Returns one of
--
--   "added"     it was not there (or was out of date)
--   "present"   it was there already; nothing changed
--   "noTable"   vanilla's SkillBook table does not exist
--               (yet): nothing is created, since vanilla
--               would replace it
--   "noPerk"    the Ammo Making perk was not registered
--   "invalid"   VOLUMES does not validate
--
-- skillBook defaults to the global SkillBook, perk to the
-- Ammo Making perk.
------------------------------------------------

function AC_SkillBooks.register(
    skillBook,
    perk
)

    if skillBook == nil then
        skillBook = SkillBook
    end


    if perk == nil then
        perk = AmmoMakingSkill and AmmoMakingSkill.perk
    end


    if #AC_SkillBooks.validate() > 0 then
        return "invalid"
    end


    if type(skillBook) ~= "table" then
        return "noTable"
    end


    if perk == nil then
        return "noPerk"
    end


    if AC_SkillBooks.isRegistered(
        skillBook,
        perk
    ) then
        return "present"
    end


    skillBook[AC_SkillBooks.skill] =
        AC_SkillBooks.buildEntry(
            perk
        )


    return "added"
end


-- The last outcome and when it happened, for AC_Compat.
AC_SkillBooks.lastStatus =
    AC_SkillBooks.lastStatus or nil


AC_SkillBooks.lastWhen =
    AC_SkillBooks.lastWhen or nil


-- register(), pcall-guarded and logged. A failure here
-- must never stop a world from loading.
function AC_SkillBooks.registerLogged(
    when
)

    local ok,
          status =
        pcall(
            AC_SkillBooks.register
        )


    if not ok then

        print(
            "[AmmoMaking] WARNING: skill books not registered: "
            .. tostring(status)
        )


        AC_SkillBooks.lastStatus = "error"

        AC_SkillBooks.lastWhen = when


        return "error"
    end


    -- "present" after a good "added" says nothing new.
    if status == "present"
        and AC_SkillBooks.lastStatus == "added"
    then
        return status
    end


    AC_SkillBooks.lastStatus = status

    AC_SkillBooks.lastWhen = when


    if status == "added" then

        print(
            "[AmmoMaking] Skill books: Ammo Making entered in vanilla's reading table ("
            .. tostring(when)
            .. ")"
        )

    elseif status ~= "present" then

        print(
            "[AmmoMaking] WARNING: skill books not registered ("
            .. tostring(when)
            .. "): "
            .. tostring(status)
        )
    end


    return status
end


------------------------------------------------
-- EVENTS
------------------------------------------------
--
-- Both fire after the server folder has been loaded:
-- OnGameStart on a client and in single player
-- (IngameState.enter), OnServerStarted on a dedicated
-- server (GameServer.main). The server file has
-- normally added the entry already.
------------------------------------------------

Events.OnGameStart.Add(
    function()

        AC_SkillBooks.registerLogged(
            "game start"
        )
    end
)


Events.OnServerStarted.Add(
    function()

        AC_SkillBooks.registerLogged(
            "server start"
        )
    end
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Skill books loaded"
)
