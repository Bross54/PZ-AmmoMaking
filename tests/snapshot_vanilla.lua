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
-- when it is listed more than once).
local function liveListsWith(itemType)
    local found = {}
    local bare = string.gsub(itemType, "^Base%.", "")
    for _, name in ipairs(names) do
        if references[name] then
            local items = ProceduralDistributions.list[name].items
            for index = 1, #items, 2 do
                if items[index] == bare or items[index] == itemType then
                    table.insert(found, { list = name, weight = items[index + 1] })
                    break
                end
            end
        end
    end
    return found
end

-- The lists the mod adds die sets to, the three dead gun-store lists it
-- must not use, and a few to compare weights with.
local DETAILED = {
    "GunStoreAccessories", "GarageFirearms", "Hunter", "HuntingLockers",
    "GunStoreCounter", "GunStoreDisplayCase", "GunStoreShelf",
    "GunStoreAmmunition", "GunStoreLiterature", "ArmyStorageAmmunition",
    "PoliceStorageAmmunition", "MetalWorkerTools", "ToolFactoryTools",
}
-- Vanilla items the mod's recipes consume.
local RAW_INPUTS = {
    "Base.BrassScrap", "Base.CopperScrap", "Base.GunPowder", "Base.CapGunCap", "Base.CapGunCapBox",
    "Base.Matches", "Base.Matchbox", "Base.Fertilizer", "Base.Charcoal", "Base.SteelBarQuarter",
    "Base.BrassIngot", "Base.CopperIngot", "Base.CopperOre",
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
-- takes apart.
local tagged = {}
for _, file in ipairs({ "normal", "weapon" }) do
    local text = readFile(SCRIPTS .. "items/" .. file .. ".txt")
    for name, body in string.gmatch(text, "\n%s*item%s+([%w_]+)%s*(%b{})") do
        local tags = string.match(body, "\n%s*Tags%s*=%s*([^\n]*)")
        if tags and string.find(";" .. string.gsub(tags, "[%s,]", "") .. ";", ";base:ammo;", 1, true) then
            table.insert(tagged, "Base." .. name)
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
emit("        -- Referenced lists that hold each vanilla item the mod consumes.")
emit("        items = {")
for _, itemType in ipairs(RAW_INPUTS) do
    local parts = {}
    for _, found in ipairs(liveListsWith(itemType)) do
        table.insert(parts, "{ list = " .. quote(found.list) .. ", weight = " .. number(found.weight) .. " }")
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
    emit(string.format("            [%s] = { box = %s, perBox = %d, opensTo = %s, opensCount = %s, carton = %s },",
        quote(round), quote(box), roundsPerBox[round], quote(tostring(back.round)), tostring(back.count), quote(tostring(cartonOf[box]))))
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
