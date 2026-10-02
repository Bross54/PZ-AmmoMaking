-- Ammo Making - regenerates media/scripts/AC_Recipes.txt and the balance table
--
--     lua5.1 tests/write_recipes.lua
--
-- Loads the mod against the mocked API, renders every recipe of
-- AC_Materials.RECIPES with tests/render_recipes.lua and rewrites the body
-- of AC_Recipes.txt, keeping its leading comment. It also rewrites the
-- generated balance tables of docs/AMMUNITION_DESIGN.md, the loot and
-- recycling tables of docs/LOOT_AND_RECYCLING.md and the calibre table of README.md, between
-- their marker comments
-- (tests/render_balance.lua). Run it after changing a
-- recipe in AC_Materials.lua or a calibre in AC_Calibres.lua; then run
-- tests/run_tests.lua, which fails while either differs from the model.
--
-- It only writes text. Whether the game accepts the result still needs the
-- game.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$") or "."
local LUA = ROOT .. "/mod/AmmoMaking/42/media/lua/"
local SCRIPT = ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Recipes.txt"
local DOCUMENT = ROOT .. "/docs/AMMUNITION_DESIGN.md"

local MOCK = dofile(ROOT .. "/tests/mock_pz.lua")
local RENDER = dofile(ROOT .. "/tests/render_recipes.lua")
local BALANCE = dofile(ROOT .. "/tests/render_balance.lua")

MOCK.loadMod(LUA)

local handle = assert(io.open(SCRIPT, "r"), "cannot open " .. SCRIPT)
local header = RENDER.splitHeader(handle:read("*a"))
handle:close()

handle = assert(io.open(SCRIPT, "w"), "cannot write " .. SCRIPT)
handle:write(header .. RENDER.renderModule(AC_Materials.RECIPES))
handle:close()

print("Wrote " .. #AC_Materials.RECIPES .. " recipes to " .. SCRIPT)

-- The documents are read and written in text mode, like the script, so
-- their line endings are whatever the platform's are.
local function rewrite(path, replace, what)
    local file = assert(io.open(path, "r"), "cannot open " .. path)
    local text = string.gsub(file:read("*a"), "\r", "")
    file:close()

    local updated = assert(replace(text), what .. " markers not found in " .. path)

    file = assert(io.open(path, "w"), "cannot write " .. path)
    file:write(updated)
    file:close()

    print("Wrote the " .. what .. " to " .. path)
end

rewrite(DOCUMENT, BALANCE.replaceBlock, "balance tables")
rewrite(DOCUMENT, BALANCE.replaceEconomy, "economy table")

local VANILLA = dofile(ROOT .. "/tests/vanilla_snapshot.lua")
rewrite(ROOT .. "/docs/LOOT_AND_RECYCLING.md", function(text) return BALANCE.replaceLoot(text, VANILLA) end, "loot table")
rewrite(ROOT .. "/docs/LOOT_AND_RECYCLING.md", BALANCE.replaceRecycling, "recycling table")
rewrite(ROOT .. "/README.md", BALANCE.replaceSummary, "calibre table")
