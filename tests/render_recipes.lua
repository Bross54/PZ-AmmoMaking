-- Ammo Making - renders craftRecipe script blocks from AC_Materials.RECIPES
--
-- media/scripts/AC_Recipes.txt is what the game loads; AC_Materials.RECIPES
-- (with the calibre recipes of AC_Calibres) is what the mod and the tests
-- reason about. This file turns the second into the text of the first, so
-- the script never has to be typed by hand:
--
--   tests/run_tests.lua    asserts the script file equals the rendering
--   tests/write_recipes.lua rewrites the script file from the rendering
--
-- Only fields and line forms found in vanilla 42.20.4 recipes are emitted.
-- Returns a table of functions; it defines no globals.

local R = {}

local INDENT = "    "

local function join(list)
    return table.concat(list, ";")
end

-- "item 1 [A;B] mode:keep flags[X;Y]," / "item 4 tags[base:charcoal]," /
-- "item 1 [A;B] mode:destroy," (consumed, and no ReplaceOnUse item returned)
function R.renderInput(input)
    local line = "item " .. input.count .. " "
    if input.tags then
        line = line .. "tags[" .. join(input.tags) .. "]"
    else
        line = line .. "[" .. join(input.items) .. "]"
    end
    if input.keep then
        line = line .. " mode:keep"
    elseif input.destroy then
        line = line .. " mode:destroy"
    end
    if input.flags then
        line = line .. " flags[" .. join(input.flags) .. "]"
    end
    return line .. ","
end

-- "item 10 Base.BrassIngot,"
function R.renderOutput(output)
    return "item " .. output.count .. " " .. output.item .. ","
end

-- One craftRecipe block, indented for the inside of a module.
function R.renderRecipe(recipe)
    local i1, i2, i3 = INDENT, INDENT .. INDENT, INDENT .. INDENT .. INDENT
    local lines = {}
    table.insert(lines, i1 .. "craftRecipe " .. recipe.id)
    table.insert(lines, i1 .. "{")
    table.insert(lines, i2 .. "time = " .. recipe.time .. ",")
    if recipe.timedAction then
        table.insert(lines, i2 .. "timedAction = " .. recipe.timedAction .. ",")
    end
    table.insert(lines, i2 .. "Tags = " .. recipe.benchTag .. ",")
    table.insert(lines, i2 .. "category = " .. recipe.category .. ",")
    table.insert(lines, i2 .. "OnCreate = AC_Materials." .. recipe.callback .. ",")
    table.insert(lines, i2 .. "inputs")
    table.insert(lines, i2 .. "{")
    for _, input in ipairs(recipe.inputs) do
        table.insert(lines, i3 .. R.renderInput(input))
    end
    table.insert(lines, i2 .. "}")
    table.insert(lines, i2 .. "outputs")
    table.insert(lines, i2 .. "{")
    for _, output in ipairs(recipe.outputs) do
        table.insert(lines, i3 .. R.renderOutput(output))
    end
    table.insert(lines, i2 .. "}")
    table.insert(lines, i1 .. "}")
    return table.concat(lines, "\n")
end

-- The whole "module Base { ... }" body for a list of recipes.
function R.renderModule(recipes)
    local blocks = {}
    for _, recipe in ipairs(recipes) do
        table.insert(blocks, R.renderRecipe(recipe))
    end
    return "module Base\n{\n" .. table.concat(blocks, "\n\n") .. "\n}\n"
end

-- Splits a script file into its leading comment (kept verbatim when the
-- file is rewritten) and the rest.
function R.splitHeader(text)
    text = string.gsub(text, "\r", "")
    local header = string.match(text, "^(%s*/%*.-%*/%s*)")
    if not header then
        return "", text
    end
    return header, string.sub(text, #header + 1)
end

return R
