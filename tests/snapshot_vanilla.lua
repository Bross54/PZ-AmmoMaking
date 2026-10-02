-- Ammo Making - records the vanilla facts the mod relies on
--
--     lua5.1 tests/snapshot_vanilla.lua "<Project Zomboid install>" [version]
--
-- Reads the INSTALLED game's loot tables and ammunition recipes and writes
-- tests/vanilla_snapshot.lua: a plain data table. tests/run_tests.lua then
-- compares the mod's assumptions with that table, so the suite itself needs
-- no game install and still fails when the mod names a loot list nothing
-- uses, or a box recipe that does not take its rounds.
--
-- Re-run it after a game update. It writes facts only: which procedural
-- lists exist and which a container names, where the raw inputs of the mod
-- are loot, and what vanilla's box recipes accept. It proves nothing about
-- how the running game behaves.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$") or "."
local INSTALL = assert(arg and arg[1], "usage: snapshot_vanilla.lua <install dir> [version]")
local VERSION = arg[2] or "42.20.4"
INSTALL = string.gsub(INSTALL, "\\", "/")
local ITEMS_LUA = INSTALL .. "/media/lua/server/Items/"
local SCRIPTS = INSTALL .. "/media/scripts/generated/"

local function readFile(path)
    local handle = assert(io.open(path, "r"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (string.gsub(text, "\r", ""))
end

------------------------------------------------
-- LOOT TABLES
------------------------------------------------

-- The distribution files need only Events at load.
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
-- Alphabetical, as the engine loads a folder: the junk tables first.
for _, name in ipairs({
    "Distribution_BagsAndContainers", "Distribution_BinJunk", "Distribution_ClosetJunk",
    "Distribution_CounterJunk", "Distribution_DeskJunk", "Distribution_ShelfJunk",
    "Distribution_SideTableJunk", "Distributions", "ProceduralDistributions",
}) do
    dofile(ITEMS_LUA .. name .. ".lua")
end

local references = {}
local function walk(node)
    for key, value in pairs(node) do
        if type(value) == "table" then
            if key == "procList" then
                for _, entry in ipairs(value) do
                    references[entry.name] = (references[entry.name] or 0) + 1
                end
            else
                walk(value)
            end
        end
    end
end
walk(Distributions[1])

local names = {}
for name in pairs(ProceduralDistributions.list) do table.insert(names, name) end
table.sort(names)

local unreferenced = {}
for _, name in ipairs(names) do
    if not references[name] then table.insert(unreferenced, name) end
end

local function listFacts(name)
    local list = ProceduralDistributions.list[name]
    local entries, weight = 0, 0
    for index = 1, #list.items, 2 do
        entries = entries + 1
        weight = weight + (tonumber(list.items[index + 1]) or 0)
    end
    return { rolls = list.rolls, entries = entries, weight = weight, references = references[name] or 0 }
end

-- Lists a container names that hold the item, with the weight (the first
-- when it is listed more than once). A list's "junk" table counts too, and
-- is marked: the engine parses it (ItemPickerJava.ExtractContainersFromLua)
-- and rolls it after the list's own items (rollProceduralItemInternal).
local function liveListsWith(itemType)
    local found = {}
    local bare = string.gsub(itemType, "^Base%.", "")
    for _, name in ipairs(names) do
        if references[name] then
            local list = ProceduralDistributions.list[name]
            local seen = false
            for _, part in ipairs({ { list.items, false }, { type(list.junk) == "table" and list.junk.items or nil, true } }) do
                local items = part[1]
                if items and not seen then
                    for index = 1, #items, 2 do
                        if items[index] == bare or items[index] == itemType then
                            table.insert(found, { list = name, weight = items[index + 1], junk = part[2] })
                            seen = true
                            break
                        end
                    end
                end
            end
        end
    end
    return found
end

-- The lists the mod adds die sets to, the three dead gun-store lists it
-- must not use, and a few to compare weights with.
local DETAILED = {
    "GunStoreAccessories", "GunStoreMagsAmmo", "GarageFirearms", "Hunter", "HuntingLockers",
    "GunStoreCounter", "GunStoreDisplayCase", "GunStoreShelf",
    "GunStoreAmmunition", "GunStoreLiterature", "ArmyStorageAmmunition",
    "PoliceStorageAmmunition", "MetalWorkerTools", "ToolFactoryTools",
}
-- Lists whose users are recorded in full: for each container that names
-- the list, every list that container can be filled from. The engine fills
-- a container from ONE of them (ItemPickerJava.rollProceduralItemInternal),
-- so how often a list is used depends on its neighbours, not on itself.
local WITH_USERS = { "GunStoreAccessories", "GunStoreMagsAmmo", "GarageFirearms", "Hunter", "HuntingLockers" }

-- { container = "room.container", lists = { { name, min, max, weight, forced }, ... } }
local function usersOf(listName)
    local found = {}
    for room, containers in pairs(Distributions[1]) do
        if type(containers) == "table" then
            for container, definition in pairs(containers) do
                if type(definition) == "table" and type(definition.procList) == "table" then
                    local named = false
                    for _, entry in ipairs(definition.procList) do
                        if entry.name == listName then named = true end
                    end
                    if named then
                        local lists = {}
                        for _, entry in ipairs(definition.procList) do
                            local forced = entry.forceForItems ~= nil or entry.forceForZones ~= nil or entry.forceForTiles ~= nil or entry.forceForRooms ~= nil
                            table.insert(lists, { entry.name, entry.min or 0, entry.max or 0, entry.weightChance or 0, forced })
                        end
                        table.insert(found, { container = room .. "." .. container, lists = lists })
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.container < b.container end)
    return found
end

-- Vanilla items the mod's recipes consume.
local RAW_INPUTS = {
    "Base.BrassScrap", "Base.CopperScrap", "Base.GunPowder", "Base.CapGunCap", "Base.CapGunCapBox",
    "Base.Matches", "Base.Matchbox", "Base.Fertilizer", "Base.Charcoal", "Base.SteelBarQuarter",
    "Base.BrassIngot", "Base.CopperIngot", "Base.CopperOre",
    -- What the assay kits and the analyzer are made from.
    "Base.MagnifyingGlass", "Base.Loupe", "Base.Tweezers", "Base.Tweezers_Forged", "Base.SheetPaper2",
    "Base.Calculator", "Base.ElectronicsScrap", "Base.ElectricWire", "Base.Amplifier", "Base.LightBulb",
    "Base.Screws", "Base.SheetMetal", "Base.CarBatteryCharger", "Base.Speaker",
}

------------------------------------------------
-- AMMUNITION RECIPES
------------------------------------------------

local ammunition = readFile(SCRIPTS .. "recipes/recipes_ammunition.txt")
local packing = readFile(SCRIPTS .. "recipes/recipes_packing.txt")

-- The body of "craftRecipe <name> { ... }" (brace matched).
local function recipeBody(text, name)
    local start = assert(string.find(text, "craftRecipe%s+" .. name .. "%s*{"), "no recipe " .. name)
    local open = string.find(text, "{", start, true)
    local depth, index = 0, open
    while index <= #text do
        local c = string.sub(text, index, index)
        if c == "{" then depth = depth + 1 end
        if c == "}" then
            depth = depth - 1
            if depth == 0 then return string.sub(text, open, index) end
        end
        index = index + 1
    end
    error("unbalanced braces in " .. name)
end

-- "itemMapper x { A = B, ... }" as { A = B }.
local function mapper(body)
    local map = {}
    local block = assert(string.match(body, "itemMapper%s+%w+%s*(%b{})"), "no item mapper")
    for key, value in string.gmatch(block, "([%w%.]+)%s*=%s*([%w%.]+)") do
        map[key] = value
    end
    return map
end

-- "item 20 [A;25:B;50:C]" as { A = 20, B = 25, C = 50 }.
local function inputCounts(body)
    local default, items = string.match(body, "inputs%s*{%s*item%s+(%d+)%s+%[([^%]]+)%]")
    assert(default, "no bracketed input line")
    local counts = {}
    for entry in string.gmatch(items, "[^;]+") do
        local count, item = string.match(entry, "^(%d+):(.+)$")
        counts[item or entry] = tonumber(count or default)
    end
    return counts
end

local place = recipeBody(ammunition, "place_ammo_in_box")
local boxOf = {}
for box, round in pairs(mapper(place)) do boxOf[round] = box end
local roundsPerBox = inputCounts(place)

-- What opening a box hands back.
local opened = {}
for _, name in ipairs({ "OpenBoxOfBullets50", "OpenBoxOfBullets20" }) do
    local body = recipeBody(ammunition, name)
    local count = tonumber(string.match(body, "outputs%s*{%s*item%s+(%d+)%s+mapper"))
    for round, box in pairs(mapper(body)) do opened[box] = { round = round, count = count } end
end
do
    local body = recipeBody(ammunition, "OpenBoxOfShotgunShells")
    local box = string.match(body, "item%s+1%s+%[([%w%.]+)%]")
    local count, round = string.match(body, "outputs%s*{%s*item%s+(%d+)%s+([%w%.]+)")
    opened[box] = { round = round, count = tonumber(count) }
end

local cartonOf = {}
for carton, box in pairs(mapper(recipeBody(packing, "Place12BoxesInCarton"))) do cartonOf[box] = carton end

local gather = recipeBody(ammunition, "GatherGunpowder")

-- Every item that carries the base:ammo tag, which is what GatherGunpowder
-- takes apart, and each one's weight.
local tagged = {}
local weightOf = {}
for _, file in ipairs({ "normal", "weapon" }) do
    local text = readFile(SCRIPTS .. "items/" .. file .. ".txt")
    for name, body in string.gmatch(text, "\n%s*item%s+([%w_]+)%s*(%b{})") do
        local tags = string.match(body, "\n%s*Tags%s*=%s*([^\n]*)")
        if tags and string.find(";" .. string.gsub(tags, "[%s,]", "") .. ";", ";base:ammo;", 1, true) then
            table.insert(tagged, "Base." .. name)
            weightOf["Base." .. name] = tonumber(string.match(body, "\n%s*Weight%s*=%s*([%d%.]+)"))
        end
    end
end
table.sort(tagged)

------------------------------------------------
-- WRITE
------------------------------------------------

local out = {}
local function emit(text) table.insert(out, text) end
local function quote(text) return string.format("%q", text) end
local function number(value)
    if value == math.floor(value) then return string.format("%d", value) end
    return (string.gsub(string.format("%.4f", value), "0+$", ""))
end
local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do table.insert(keys, key) end
    table.sort(keys)
    return keys
end

emit("-- GENERATED by tests/snapshot_vanilla.lua from the installed game files.")
emit("-- Do not edit: re-run the script after a game update.")
emit("return {")
emit("    version = " .. quote(VERSION) .. ",")
emit("    loot = {")
emit("        listCount = " .. #names .. ",")
emit("        -- Procedural lists no container of Distributions.lua names.")
emit("        unreferenced = {")
for _, name in ipairs(unreferenced) do emit("            " .. quote(name) .. ",") end
emit("        },")
emit("        lists = {")
for _, name in ipairs(DETAILED) do
    local facts = listFacts(name)
    emit(string.format("            %s = { rolls = %s, entries = %d, weight = %s, references = %d },",
        name, number(facts.rolls), facts.entries, number(facts.weight), facts.references))
end
emit("        },")
emit("        -- For each of these lists: the containers that name it, each with every")
emit("        -- list it can be filled from, as { name, min, max, weightChance, forced }.")
emit("        users = {")
for _, name in ipairs(WITH_USERS) do
    emit("            " .. name .. " = {")
    for _, user in ipairs(usersOf(name)) do
        local parts = {}
        for _, list in ipairs(user.lists) do
            table.insert(parts, string.format("{ %s, %d, %d, %d, %s }", quote(list[1]), list[2], list[3], list[4], tostring(list[5])))
        end
        emit("                { container = " .. quote(user.container) .. ", lists = { " .. table.concat(parts, ", ") .. " } },")
    end
    emit("            },")
end
emit("        },")
emit("        -- Referenced lists that hold each vanilla item the mod consumes.")
emit("        items = {")
for _, itemType in ipairs(RAW_INPUTS) do
    local parts = {}
    for _, found in ipairs(liveListsWith(itemType)) do
        table.insert(parts, "{ list = " .. quote(found.list) .. ", weight = " .. number(found.weight) .. (found.junk and ", junk = true" or "") .. " }")
    end
    emit("            [" .. quote(itemType) .. "] = { " .. table.concat(parts, ", ") .. " },")
end
emit("        },")
emit("    },")
emit("    ammo = {")
emit("        -- Items tagged base:ammo: what GatherGunpowder takes apart.")
emit("        tagged = {")
for _, itemType in ipairs(tagged) do emit("            " .. quote(itemType) .. ",") end
emit("        },")
emit("        gatherTakesAmmoTag = " .. tostring(string.find(gather, "tags[base:ammo] mode:destroy", 1, true) ~= nil) .. ",")
emit("        gatherReturnsOneUse = " .. tostring(string.find(gather, "item 1 Base.GunPowder flags[HasOneUse]", 1, true) ~= nil) .. ",")
emit("        -- place_ammo_in_box, OpenBoxOf..., Place12BoxesInCarton.")
emit("        boxInputLines = " .. select(2, string.gsub(string.match(place, "inputs%s*(%b{})"), "item%s+%d+", "")) .. ",")
emit("        boxIsExclusive = " .. tostring(string.find(place, "IsExclusive", 1, true) ~= nil) .. ",")
emit("        boxHasOnCreate = " .. tostring(string.find(place, "OnCreate", 1, true) ~= nil) .. ",")
emit("        rounds = {")
for _, round in ipairs(sortedKeys(boxOf)) do
    local box = boxOf[round]
    local back = opened[box] or {}
    emit(string.format("            [%s] = { box = %s, perBox = %d, opensTo = %s, opensCount = %s, carton = %s, weight = %s },",
        quote(round), quote(box), roundsPerBox[round], quote(tostring(back.round)), tostring(back.count), quote(tostring(cartonOf[box])), number(weightOf[round])))
end
emit("        },")
emit("    },")
emit("}")
emit("")

local path = ROOT .. "/tests/vanilla_snapshot.lua"
local handle = assert(io.open(path, "w"), "cannot write " .. path)
handle:write(table.concat(out, "\n"))
handle:close()
print("Wrote " .. path .. " (" .. #names .. " lists, " .. #unreferenced .. " unreferenced, " .. #tagged .. " ammo items)")
