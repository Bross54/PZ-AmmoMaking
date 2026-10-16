-- Ammo Making - offline tests: the skill books (AC_SkillBooks, AC_Loot.BOOKS).
--
-- Loaded by tests/run_tests.lua. Pure logic: the volume table against
-- vanilla's own books (tests/vanilla_snapshot.lua, read from the installed
-- game), the item scripts, what the multipliers do to the climb to level 5,
-- and the loot judged per room. Mocked engine: the entry in vanilla's
-- SkillBook table (a stand-in for the vanilla server file) and the game-start
-- report. That a book can be read in game, that the custom perk is accepted
-- by addXpMultiplier, and how often a book is found are REQUIRES FUTURE
-- IN-GAME VERIFICATION.

return function(T)
    local check, eq, section, MOCK, VANILLA = T.check, T.eq, T.section, T.MOCK, T.VANILLA
    local readFile, ROOT = T.readFile, T.ROOT
    local B = AC_SkillBooks

    section("Skill books: five volumes with vanilla's levels, pages and the firearm skills' multipliers (pure)")
    do
        eq(#B.validate(), 0, "the volume table is sound: " .. table.concat(B.validate(), "; "))
        eq(B.skill, "AmmoMaking", "the books name the skill by the perk's id")
        local books = VANILLA.books
        check(type(books) == "table", "the snapshot records vanilla's skill books")
        local reloading = books.volumes.Reloading
        eq(#B.VOLUMES, #reloading, "as many volumes as vanilla's Reloading books")
        for index, volume in ipairs(B.VOLUMES) do
            local vanilla = reloading[index]
            eq(volume.level, vanilla.level, "volume " .. index .. " starts at vanilla's level " .. vanilla.level)
            eq(B.levels, vanilla.levels, "volume " .. index .. " trains vanilla's " .. vanilla.levels .. " levels")
            eq(volume.pages, vanilla.pages, "volume " .. index .. " has vanilla's " .. vanilla.pages .. " pages")
            eq(volume.pages, books.volumes.Carpentry[index].pages, "(the same as every other skill's volume " .. index .. ")")
            eq(volume.multiplier, books.multipliers.Reloading[index], "volume " .. index .. " multiplies as vanilla's Reloading volume does")
            eq(volume.multiplier, books.multipliers.Aiming[index], "and as its Aiming volume does")
            check(volume.multiplier < books.multipliers.Carpentry[index], "volume " .. index .. " is worth less than a crafting skill's (" .. books.multipliers.Carpentry[index] .. ")")
            eq(B.getVolume(volume.item), volume, volume.item .. " is found by its id")
        end
        eq(B.getVolume("Base.BookReloading1"), nil, "a vanilla book is not one of ours")
        eq(table.concat(B.getItems(), ","), "AmmoMaking.BookAmmoMaking1,AmmoMaking.BookAmmoMaking2,AmmoMaking.BookAmmoMaking3,AmmoMaking.BookAmmoMaking4,AmmoMaking.BookAmmoMaking5", "the five item ids, in order")

        -- What the support rests on, as read in the installed game.
        eq(books.tableCreatedInServerFile, true, "vanilla creates SkillBook anew in a server file: an entry added before it would be lost")
        eq(books.readerKeysBySkillTrained, true, "the reader looks a book's skill up by its SkillTrained string")
        eq(books.readerVolumeLevels, true, "and knows the volumes by their first level, 1 to 9")
        eq(books.menuIndexesWithoutCheck, true, "the inventory menu indexes the entry without a nil check: a missing entry is an error, hence the double registration")
        eq(books.multipliers.AmmoMaking, nil, "vanilla has no entry of its own for the skill")

        -- The entry has vanilla's shape.
        local perk = { name = "perk" }
        local entry = B.buildEntry(perk)
        eq(entry.perk, perk, "the entry holds the perk object")
        local keys = 0
        for _ in pairs(entry) do keys = keys + 1 end
        eq(keys, 6, "and maxMultiplier1 to 5, nothing else")
        for index, volume in ipairs(B.VOLUMES) do
            eq(entry["maxMultiplier" .. index], volume.multiplier, "maxMultiplier" .. index)
        end

        -- validate() refuses a table vanilla's reader could not use.
        local function refused(what, change, needle)
            local copy = {}
            for index, volume in ipairs(B.VOLUMES) do
                copy[index] = { item = volume.item, level = volume.level, pages = volume.pages, multiplier = volume.multiplier }
            end
            change(copy)
            local found = table.concat(B.validate(copy), "; ")
            check(string.find(found, needle, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
        end
        refused("four volumes", function(c) table.remove(c) end, "five volumes")
        refused("a volume at level 2", function(c) c[1].level = 2 end, "must start at level 1")
        refused("a gap between volumes", function(c) c[3].level = 7 end, "must start at level 5")
        refused("a shorter later volume", function(c) c[2].pages = 200 end, "longer than the one before")
        refused("a later volume worth less", function(c) c[4].multiplier = 3 end, "worth more than the one before")
        refused("a volume that multiplies nothing", function(c) c[1].multiplier = 1 end, "more than 1")
        refused("a vanilla book in the table", function(c) c[1].item = "Base.BookReloading1" end, "item of the mod")
        refused("the same book twice", function(c) c[2].item = c[1].item end, "repeats")
        refused("half a page", function(c) c[1].pages = 220.5 end, "whole number of pages")
    end

    section("Skill books: the item scripts are vanilla's skill books with the mod's name and icons (pure)")
    do
        local reloading = VANILLA.books.volumes.Reloading
        for index, volume in ipairs(B.VOLUMES) do
            local block = T.declaredItems[volume.item]
            check(block ~= nil, volume.item .. " is declared in AC_Items.txt")
            if block then
                local f, vanilla = block.fields, reloading[index]
                eq(f.DisplayCategory, vanilla.category, volume.item .. ": vanilla's category, so the skill book loot setting scales it")
                eq(f.ItemType, vanilla.itemType, volume.item .. ": literature")
                eq(tonumber(f.Weight), vanilla.weight, volume.item .. ": vanilla's weight")
                eq(tonumber(f.LvlSkillTrained), volume.level, volume.item .. ": LvlSkillTrained is the table's")
                eq(tonumber(f.NumLevelsTrained), B.levels, volume.item .. ": NumLevelsTrained is the table's")
                eq(tonumber(f.NumberOfPages), volume.pages, volume.item .. ": NumberOfPages is the table's")
                eq(f.SkillTrained, B.skill, volume.item .. ": SkillTrained is the key of the entry")
                eq(f.Icon, "AmmoMakingBook" .. index, volume.item .. ": its own icon")
                eq(AC_Visuals.findIcon(f.Icon) ~= nil, true, volume.item .. ": the icon is drawn by the mod")
                check(string.find(f.DisplayName, "Ammo Making " .. ({ "I", "II", "III", "IV", "V" })[index] .. ": ", 1, true) == 1, volume.item .. ": named like vanilla's volumes (" .. f.DisplayName .. ")")
            end
        end
        -- The names are what the translation file says.
        local names = readFile(T.TRANSLATE .. "ItemName.json")
        for _, volume in ipairs(B.VOLUMES) do
            check(string.find(names, "\"" .. volume.item .. "\"", 1, true) ~= nil, volume.item .. " has a name in ItemName.json")
        end
        -- No book is a component, and none is made.
        for _, id in ipairs(B.getItems()) do
            eq(AC_Calibres.identify(id), nil, id .. " is not a component of any calibre")
            for _, recipe in ipairs(AC_Materials.RECIPES) do
                for _, output in ipairs(recipe.outputs) do
                    check(output.item ~= id, id .. " is made by no recipe (" .. recipe.id .. ")")
                end
            end
        end
    end

    section("Skill books: what reading does to the climb to level 5 (pure model of vanilla's multiplier bands)")
    do
        -- A volume's multiplier applies while the perk's XP lies between the
        -- totals of its first level minus one and of its last level
        -- (IsoGameCharacter$XP.addXpMultiplier / AddXP, 42.20.4 jar). One
        -- multiplier per perk at a time; reading a later volume replaces it.
        local perLevel = MOCK.perkXP
        eq(#perLevel, 10, "the perk's ten level amounts are known")
        local function total(level)
            local sum = 0
            for index = 1, level do sum = sum + perLevel[index] end
            return sum
        end
        -- The XP the character must EARN (before any multiplier) to reach
        -- the target level with the given multipliers read at the right time.
        local function earned(target, multipliers)
            local need, xp = 0, 0
            local goal = total(target)
            for index, volume in ipairs(B.VOLUMES) do
                local from, to = total(volume.level - 1), math.min(goal, total(volume.level + B.levels - 1))
                if to > from and to > xp then
                    local start = math.max(from, xp)
                    need = need + (start - xp) + (to - start) / multipliers[index]
                    xp = to
                end
            end
            return need + math.max(0, goal - xp)
        end
        local mod, crafting = {}, {}
        for index, volume in ipairs(B.VOLUMES) do
            mod[index] = volume.multiplier
            crafting[index] = VANILLA.books.multipliers.Carpentry[index]
        end
        eq(total(5), 2775, "level 5, the last level a recipe asks for, is 2775 XP")
        eq(earned(5, { 1, 1, 1, 1, 1 }), 2775, "the model without books earns it all")
        local withBooks, withCrafting = earned(5, mod), earned(5, crafting)
        eq(withBooks, 945, "with volumes I to III read in time: 945 XP earned")
        eq(withCrafting, 472.5, "the crafting table would have made it 472.5")
        check(withBooks / 2775 >= 1 / 3, "the books never cut the climb to level 5 below a third (" .. string.format("%.2f", withBooks / 2775) .. ")")
        check(withCrafting / 2775 < 1 / 5, "the crafting table would have cut it below a fifth: the reason it was not chosen")
        -- The books shorten the climb; they open nothing. A recipe is still
        -- gated by its level, and every round still needs ore: reading
        -- awards no XP by itself (ISReadABook only sets the multiplier).
        print(string.format("  Skill books: level 5 takes %d XP earned without books, %d with volumes I to III (vanilla's crafting table would give %.1f)", 2775, withBooks, withCrafting))
    end

    section("Skill books: the entry in vanilla's reading table (mocked engine)")
    do
        local perk = AmmoMakingSkill.perk
        -- The server file ran at load (the mock loads server files last, as the
        -- engine does).
        eq(B.isRegistered(), true, "after the mod loaded, SkillBook.AmmoMaking is in place")
        check(SkillBook.Reloading ~= nil, "vanilla's own entries are untouched")

        -- Vanilla's server file loaded again: the table is new and empty of ours.
        MOCK.resetSkillBook()
        eq(B.isRegistered(), false, "a fresh vanilla table holds no Ammo Making entry")
        eq(B.register(), "added", "register() adds it")
        eq((SkillBook.AmmoMaking or {}).perk, perk, "for the Ammo Making perk object")
        eq(B.register(), "present", "a second call changes nothing")
        check(SkillBook.Reloading ~= nil and SkillBook.Reloading.maxMultiplier5 == 8, "and vanilla's entries are left as they were")
        SkillBook.AmmoMaking = SkillBook.AmmoMaking or {}
        SkillBook.AmmoMaking.maxMultiplier3 = 99
        eq(B.isRegistered(), false, "an entry with other multipliers is not ours")
        eq(B.register(), "added", "and is replaced")
        eq((SkillBook.AmmoMaking or {}).maxMultiplier3, B.VOLUMES[3].multiplier, "with the table's")

        -- Nothing is created where vanilla has no table: vanilla would replace it.
        local saved = SkillBook
        SkillBook = nil
        eq(B.register(), "noTable", "no vanilla table: nothing to enter")
        eq(SkillBook, nil, "and none is created")
        SkillBook = saved
        AmmoMakingSkill.perk = nil
        MOCK.resetSkillBook()
        eq(B.register(), "noPerk", "no perk: nothing is entered")
        eq(SkillBook.AmmoMaking, nil, "and the table is not touched")
        AmmoMakingSkill.perk = perk
        local level = B.VOLUMES[2].level
        B.VOLUMES[2].level = 4
        eq(B.register(), "invalid", "a volume table that does not validate enters nothing")
        B.VOLUMES[2].level = level

        -- The server file, as the engine runs it after vanilla's.
        MOCK.resetSkillBook()
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        dofile(T.LUA .. "server/AC_SkillBookRegistration.lua")
        MOCK.capturePrint(false)
        eq(B.isRegistered(), true, "the server file enters the books at load")
        check(MOCK.printLogContains("[AmmoMaking] Skill books: Ammo Making entered in vanilla's reading table (server Lua)"), "and says so")
        eq(B.lastWhen, "server Lua", "the report knows when")

        -- And again at server start, after a table that was made anew.
        MOCK.resetSkillBook()
        check(#Events.OnServerStarted.handlers >= 1, "the mod listens for the dedicated server's start")
        MOCK.capturePrint(true)
        Events.OnServerStarted.fire()
        MOCK.capturePrint(false)
        eq(B.isRegistered(), true, "a dedicated server enters them at its start")
        eq(B.lastWhen, "server start", "and the report knows it")
        MOCK.resetSkillBook()
        MOCK.capturePrint(true)
        eq(B.registerLogged("game start"), "added", "at game start the entry is added when it is missing")
        eq(B.registerLogged("game start"), "present", "and left alone when it is there")
        MOCK.capturePrint(false)
        eq(B.lastStatus, "added", "a later \"present\" keeps the report of the time it was added")

        -- A failure is logged and never raised.
        local register = B.register
        B.register = function() error("broken") end
        MOCK.clearPrintLog()
        MOCK.capturePrint(true)
        local ok, status = pcall(B.registerLogged, "game start")
        MOCK.capturePrint(false)
        B.register = register
        check(ok and status == "error", "an error while entering the books is caught")
        check(MOCK.printLogContains("[AmmoMaking] WARNING: skill books not registered"), "and reported")
        MOCK.resetSkillBook()
        MOCK.capturePrint(true)
        eq(B.registerLogged("game start"), "added", "the next attempt works")
        MOCK.capturePrint(false)

        -- What vanilla's reader then takes from the entry: ISReadABook:new
        -- picks maxMultiplier1 to 5 by the book's first level (a model of
        -- the 42.20.4 file, not the file itself).
        local function readerMultiplier(level)
            local entry = SkillBook[B.skill]
            local key = ({ [1] = 1, [3] = 2, [5] = 3, [7] = 4, [9] = 5 })[level]
            return key and entry["maxMultiplier" .. key] or 1
        end
        for _, volume in ipairs(B.VOLUMES) do
            eq(readerMultiplier(volume.level), volume.multiplier, "reading volume " .. volume.level .. " gives its multiplier")
        end

        -- The game-start report.
        local function labels()
            MOCK.capturePrint(true)
            local results = AC_Compat.run(false)
            MOCK.capturePrint(false)
            local found = {}
            for _, result in ipairs(results) do found[result.label] = result.status end
            return found
        end
        AC_Loot.lastBookSummary = AC_Loot.registerBooks(T.mockProceduralLists(), T.mockDistribution())
        local found = labels()
        eq(found["skill books entered in vanilla's reading table (game start)"], "OK", "the report says the books can be read")
        eq(found["skill book loot (" .. #AC_Loot.buildBookEntries() .. " entries)"], "OK", "and where they are found")
        for _, id in ipairs(B.getItems()) do eq(found[id], "OK", id .. " is probed at game start") end
        MOCK.resetSkillBook()
        eq(labels()["skill books are not in vanilla's reading table"], "WARNING", "a missing entry is a WARNING")
        saved = SkillBook
        SkillBook = nil
        eq(labels()["vanilla's SkillBook table does not exist"], "WARNING", "no vanilla table at all is a WARNING")
        SkillBook = saved
        local books = AC_Loot.lastBookSummary
        AC_Loot.lastBookSummary = nil
        eq(labels()["skill book loot was not registered"], "WARNING", "book loot that never registered is a WARNING")
        AC_Loot.lastBookSummary = books
        MOCK.capturePrint(true)
        B.registerLogged("game start")
        MOCK.capturePrint(false)
    end

    section("Skill book loot: where vanilla shelves its own, judged per room, outside the mod's multipliers")
    do
        local L = AC_Loot
        local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")
        eq(#L.validateBooks(), 0, "the book loot table is sound: " .. table.concat(L.validateBooks(), "; "))

        -- Pinned: where each volume is found, and how often. A change here
        -- is a balance decision (docs/LOOT_AND_RECYCLING.md 1.4).
        eq(table.concat(L.BOOKS.volumeWeight, ","), "1,0.8,0.6,0.4,0.2", "vanilla's ladder for a skill's five volumes")
        local expected = { GunStoreLiterature = 2, BookstoreBooks = 0.5, LibraryBooks = 0.5, SurvivalGear = 0.5 }
        local count = 0
        for _, target in ipairs(L.BOOKS.lists) do
            count = count + 1
            eq(target.scale, expected[target.list], target.list .. " scales the ladder by " .. tostring(expected[target.list]))
        end
        eq(count, 4, "four lists: a gun store's shelves, a bookstore, a library, a survivalist's things")
        local entries = L.buildBookEntries()
        eq(#entries, 20, "every volume in every list")
        local perList = {}
        for _, entry in ipairs(entries) do
            local facts = VANILLA.loot.lists[entry.list]
            local what = entry.item .. " in " .. entry.list
            check(facts ~= nil and facts.references >= 1 and facts.entries > 0, what .. ": the list is used by a container and holds items")
            eq(entry.book, true, what .. " is marked as a book")
            check(entry.weight > 0 and entry.weight <= L.CONFIG.maxBookWeight, what .. ": within the limit")
            if facts then
                eq(facts.rolls, 4, entry.list .. " rolls four times")
                check(entry.weight / facts.weight < 0.01, what .. " adds under 1 % to the list's weight")
            end
            perList[entry.list] = (perList[entry.list] or 0) + entry.weight
        end
        for list, sum in pairs(perList) do
            check(sum <= L.CONFIG.maxBookListWeight, list .. ": the five volumes weigh " .. sum .. ", within the limit")
        end
        check(math.abs(perList.GunStoreLiterature - 6) < 1e-9, "a gun store's literature holds the most: 6 in all")

        -- Per ROOM: every container that can be filled from a book list, in
        -- rooms of 4, 8 and 12 such containers. Twelve hold at most one book
        -- on average; a gun store is the likeliest place.
        local uses = BALANCE.expectedUses
        local most, mostWhere = 0, ""
        for _, target in ipairs(L.BOOKS.lists) do
            local users = VANILLA.loot.users[target.list]
            check(users ~= nil and #users >= 1, target.list .. " has its users in the snapshot")
            local each = VANILLA.loot.lists[target.list].rolls * perList[target.list] / 100
            for _, user in ipairs(users or {}) do
                local previous = 0
                for _, size in ipairs({ 4, 8, 12 }) do
                    local books = uses(user.lists, target.list, size) * each
                    check(books >= previous, target.list .. " in " .. user.container .. ": more containers never mean fewer books")
                    previous = books
                end
                check(previous <= 1, target.list .. " in " .. user.container .. ": twelve such containers hold at most one book on average (" .. string.format("%.3f", previous) .. ")")
                if previous > most then most, mostWhere = previous, user.container end
            end
        end
        local shelves
        for _, user in ipairs(VANILLA.loot.users.GunStoreLiterature) do
            if user.container == "gunstore.shelves" then shelves = user.lists end
        end
        check(shelves ~= nil, "the snapshot records a gun store's shelves")
        local store = uses(shelves, "GunStoreLiterature", 8) * VANILLA.loot.lists.GunStoreLiterature.rolls * perList.GunStoreLiterature / 100
        check(store > 0.2 and store < 0.6, "a gun store of eight shelves holds about a third of a book (" .. string.format("%.3f", store) .. ")")
        check(uses(shelves, "GunStoreLiterature", 40) <= 2, "and never fills more than two shelves with literature")
        print(string.format("  Loot: a gun store of 8 shelves holds %.3f Ammo Making books on average; the fullest room of twelve is %s at %.2f", store, mostWhere, most))

        -- Registration: appended once, a missing list named, never created.
        local lists, distribution = T.mockProceduralLists(), T.mockDistribution()
        local summary = L.registerBooks(lists, distribution)
        eq(summary.added, #entries, "every book entry is added")
        eq(#summary.missing + #summary.empty + #summary.unreferenced, 0, "to lists that exist, hold items and are used")
        eq(L.registerBooks(lists, distribution).added, 0, "a second world load adds nothing")
        local short = T.mockProceduralLists()
        short.LibraryBooks = nil
        local partial = L.registerBooks(short, distribution)
        eq(table.concat(partial.missing, ","), "LibraryBooks", "a list this build does not have is named")
        eq(short.LibraryBooks, nil, "and never created")
        L.CONFIG.enabled = false
        eq(L.registerBooks(T.mockProceduralLists(), distribution).added, 0, "loot switched off: no book is added")
        L.CONFIG.enabled = true

        -- Neither of the mod's loot multipliers touches a book: the engine's
        -- own skill book setting scales them (DisplayCategory = SkillBook).
        for _, owned in ipairs(L.owned) do
            if B.getVolume(owned.item) then eq(owned.option, nil, owned.item .. " in " .. owned.list .. " takes no mod multiplier") end
        end
        local savedVars = SandboxVars
        SandboxVars = { AmmoMaking = { DieSetLootMultiplier = 0, ComponentLootMultiplier = 0 } }
        L.applyMultipliers(lists)
        SandboxVars = savedVars
        for _, entry in ipairs(entries) do
            local items, found = lists[entry.list].items, nil
            for index = 1, #items, 2 do
                if items[index] == entry.item then found = items[index + 1] end
            end
            eq(found, entry.weight, entry.item .. " in " .. entry.list .. " keeps its weight with both multipliers at 0")
        end
        L.applyMultipliers(lists)

        -- validateBooks() refuses what would flood a room or skip the ladder.
        local function refused(what, change, needle)
            local copy = { volumeWeight = {}, lists = {} }
            for index, weight in ipairs(L.BOOKS.volumeWeight) do copy.volumeWeight[index] = weight end
            for index, target in ipairs(L.BOOKS.lists) do copy.lists[index] = { list = target.list, scale = target.scale } end
            change(copy)
            local found = table.concat(L.validateBooks(copy), "; ")
            check(string.find(found, needle, 1, true) ~= nil, what .. " is refused (" .. found .. ")")
        end
        refused("a common book", function(c) c.lists[1].scale = 3 end, "at most 2")
        refused("a heavy volume", function(c) c.volumeWeight[1] = 1.5 end, "at most 1 before the list's scale")
        refused("a last volume commoner than the first", function(c) c.volumeWeight[5] = 1 end, "commoner than the one before")
        refused("a ladder too short", function(c) table.remove(c.volumeWeight) end, "4 weights for 5 volumes")
        refused("the same list twice", function(c) c.lists[2].list = c.lists[1].list end, "named twice")
        refused("a list without a name", function(c) c.lists[1].list = "" end, "has no name")
        local saved = L.CONFIG.maxBookListWeight
        L.CONFIG.maxBookListWeight = 5
        check(string.find(table.concat(L.validateBooks(), "; "), "above 5", 1, true) ~= nil, "a list whose books outweigh the limit is refused")
        L.CONFIG.maxBookListWeight = saved
        local item = B.VOLUMES[1].item
        B.VOLUMES[1].item = AC_Calibres.get("9mm").case
        check(string.find(table.concat(L.validateBooks(), "; "), "is a component, not a book", 1, true) ~= nil, "a component in the book table is refused")
        eq(L.registerBooks(T.mockProceduralLists(), distribution).added, 0, "and a table that does not validate adds nothing")
        B.VOLUMES[1].item = item

        -- The documents quote what the code says.
        local checklist = string.gsub(readFile(ROOT .. "/docs/INGAME_VALIDATION.md"), "\n%s*", " ")
        for _, line in ipairs({
            "[AmmoMaking] Skill books: Ammo Making entered in vanilla's reading table (server Lua)",
            "[AmmoMaking] Skill book loot: " .. #entries .. " entries added",
            "OK: skill books entered in vanilla's reading table (server Lua)",
            "OK: skill book loot (" .. #entries .. " entries)",
        }) do
            check(string.find(checklist, line, 1, true) ~= nil, "docs/INGAME_VALIDATION.md quotes: " .. line)
        end
        local code = readFile(T.LUA .. "shared/AC_SkillBooks.lua") .. readFile(T.LUA .. "shared/AC_Loot.lua") .. readFile(T.LUA .. "shared/AC_Compat.lua")
        for _, fragment in ipairs({ "Skill books: Ammo Making entered in vanilla's reading table (", "Skill book loot: ", "skill books entered in vanilla's reading table (", "skill book loot (" }) do
            check(string.find(code, fragment, 1, true) ~= nil, "and the code prints: " .. fragment)
        end
        local design = readFile(ROOT .. "/docs/AMMUNITION_DESIGN.md")
        check(string.find(design, "### 9.2 Skill books", 1, true) ~= nil, "the design document has the section the code cites")
        check(string.find(design, "| volumes I to III, the mod's table | 945 |", 1, true) ~= nil, "and the climb it states is the model's")

        -- The loot document names every list.
        local document = readFile(ROOT .. "/docs/LOOT_AND_RECYCLING.md")
        for _, target in ipairs(L.BOOKS.lists) do
            check(string.find(document, "`" .. target.list .. "`", 1, true) ~= nil, "docs/LOOT_AND_RECYCLING.md names " .. target.list)
        end
    end
end
