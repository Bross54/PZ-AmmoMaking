-- Ammo Making - offline tests: what the skill gives at every level, 0 to 10.
--
-- Loaded by tests/run_tests.lua. The craft times are the mod's reading of
-- the engine's rule (CraftRecipe.getTime in the 42.20.4 jar); that the game
-- applies it is REQUIRES FUTURE IN-GAME VERIFICATION.

return function(T)
    local check, eq, section = T.check, T.eq, T.section

    section("Progression: every Ammo Making level from 1 to 10 improves something")
    do
        local BALANCE = dofile(T.ROOT .. "/tests/render_balance.lua")
        local rows, reference = BALANCE.progression()
        eq(#rows, 11, "eleven rows: levels 0 to 10")
        eq(BALANCE.MAX_LEVEL, AC_CaseQuality.CONFIG.maxLevel, "the table runs to the level the quality roll runs to")

        -- The document's table is the rendering.
        local document = T.readFile(T.ROOT .. "/docs/AMMUNITION_DESIGN.md")
        local from = string.find(document, BALANCE.PROGRESSION_START, 1, true)
        local _, to = string.find(document, BALANCE.PROGRESSION_FINISH, 1, true)
        check(from ~= nil and to ~= nil and to > from, "the design document has the progression table markers")
        eq(string.sub(document, from or 1, to or 1), BALANCE.renderProgressionBlock(), "the progression table equals the rendered model (run tests/write_recipes.lua)")

        -- Recipes: every recipe opens at some level from 0 to 5, and the
        -- upper half opens none (pinned: a gate added there is a decision).
        local opened, highest = 0, 0
        for _, row in ipairs(rows) do
            opened = opened + row.opens
            if row.opens > 0 then highest = row.level end
        end
        eq(opened, #AC_Materials.RECIPES, "every recipe opens at one level")
        eq(highest, 5, "the last recipes open at level 5")
        check(rows[1].opens > 0, "level 0 opens recipes: the chain can be started without skill")

        -- And yet no level is empty. From each level to the next:
        for level = 1, 10 do
            local before, now = rows[level], rows[level + 1]
            local what = "level " .. level
            -- a better case, in the worst, the typical and the best roll,
            eq(now.quality[2], before.quality[2] + AC_CaseQuality.CONFIG.qualityPerLevel, what .. ": a typical case is " .. AC_CaseQuality.CONFIG.qualityPerLevel .. " points better")
            check(now.quality[1] > before.quality[1], what .. ": the worst case is better")
            check(now.quality[3] >= before.quality[3], what .. ": the best case is no worse")
            check(now.quality[1] <= now.quality[2] and now.quality[2] <= now.quality[3], what .. ": worst, typical, best are in order")
            -- faster mining,
            check(now.mining < before.mining, what .. ": mining is faster (" .. now.mining .. " after " .. before.mining .. ")")
            -- and, once the reference recipe is open, faster crafting.
            if before.craft then
                check(now.craft < before.craft, what .. ": forming a case is faster (" .. now.craft .. " after " .. before.craft .. ")")
            end
        end
        eq(rows[1].quality[2], 50, "a novice's typical case is 50")
        eq(rows[11].quality[2], 90, "a master's is 90")
        eq(rows[11].quality[3], 100, "and a master's best case is perfect")
        check(rows[1].quality[1] >= 1 and rows[11].quality[3] <= 100, "no roll leaves the quality scale")
        eq(rows[1].mining, AC_Mining.CONFIG.baseActionTime, "mining takes the base time at level 0")
        eq(rows[11].mining, AC_Mining.CONFIG.baseActionTime * 0.6, "and three fifths of it at level 10")
        check(rows[11].mining >= 1 and rows[11].craft >= 1, "nothing ever takes no time")
        -- The reference recipe: closed below its level, its own time at it.
        local required = AC_Materials.getRequiredLevel(reference)
        for level = 0, 10 do
            eq(rows[level + 1].craft ~= nil, level >= required, "level " .. level .. (level >= required and ": the reference recipe is open" or ": the reference recipe is closed"))
        end
        eq(rows[required + 1].craft, reference.time, "at the level that opens it, a recipe takes its own time")

        -- Every recipe, not only the reference one, keeps getting faster to
        -- level 10 and never reaches zero.
        for _, recipe in ipairs(AC_Materials.RECIPES) do
            local opens = AC_Materials.getRequiredLevel(recipe)
            local previous = recipe.time
            for level = opens + 1, 10 do
                local time = AC_Materials.getExpectedTime(recipe, level)
                check(time < previous and time >= 1, recipe.id .. " is faster at level " .. level .. " and still takes time (" .. time .. ")")
                previous = time
            end
        end
    end
end
