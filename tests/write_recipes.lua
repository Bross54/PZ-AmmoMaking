-- Ammo Making - regenerates media/scripts/AC_Recipes.txt
--
--     lua5.1 tests/write_recipes.lua
--
-- Loads the mod against the mocked API, renders every recipe of
-- AC_Materials.RECIPES with tests/render_recipes.lua and rewrites the body
-- of AC_Recipes.txt, keeping its leading comment. Run it after changing a
-- recipe in AC_Materials.lua or a calibre in AC_Calibres.lua; then run
-- tests/run_tests.lua, which fails while the two differ.
--
-- It only writes text. Whether the game accepts the result still needs the
-- game.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]*$") or "."
local LUA = ROOT .. "/mod/AmmoMaking/42/media/lua/"
local SCRIPT = ROOT .. "/mod/AmmoMaking/42/media/scripts/AC_Recipes.txt"

local MOCK = dofile(ROOT .. "/tests/mock_pz.lua")
local RENDER = dofile(ROOT .. "/tests/render_recipes.lua")

MOCK.loadMod(LUA)

local handle = assert(io.open(SCRIPT, "r"), "cannot open " .. SCRIPT)
local header = RENDER.splitHeader(handle:read("*a"))
handle:close()

handle = assert(io.open(SCRIPT, "w"), "cannot write " .. SCRIPT)
handle:write(header .. RENDER.renderModule(AC_Materials.RECIPES))
handle:close()

print("Wrote " .. #AC_Materials.RECIPES .. " recipes to " .. SCRIPT)
