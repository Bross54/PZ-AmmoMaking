-- Ammo Making - Player-facing text lookup
-- Project Zomboid Build 42.20
--
-- Every string a player can see goes through
-- AC_Text.get(key, fallback, ...).
--
--   * The key is looked up in the game's translation
--     tables (common/media/lua/shared/Translate).
--   * If the key is missing, the English fallback given
--     at the call site is used, with %1..%9 substituted,
--     so a missing or unloaded translation never shows a
--     raw key such as "IGUI_AmmoMaking_MineOre".
--
-- Console/log output stays in plain English and does not
-- use this helper.

AC_Text = AC_Text or {}


------------------------------------------------
-- PLACEHOLDER SUBSTITUTION
------------------------------------------------
--
-- Same convention as the vanilla translator:
-- "%1", "%2", ... are replaced by the arguments.
------------------------------------------------

local function substitute(
    text,
    args
)

    if #args == 0 then
        return text
    end


    return (
        string.gsub(
            text,
            "%%(%d)",
            function(index)

                local value =
                    args[
                        tonumber(index)
                    ]


                if value == nil then
                    return "%" .. index
                end


                return
                    tostring(value)
            end
        )
    )
end


------------------------------------------------
-- LOOKUP
------------------------------------------------

function AC_Text.get(
    key,
    fallback,
    ...
)

    local args = { ... }


    if type(key) == "string"
        and type(getTextOrNull) == "function"
    then

        local ok,
              text =
            pcall(
                getTextOrNull,
                key,
                ...
            )


        if ok
            and type(text) == "string"
            and text ~= ""
            and text ~= key
        then

            ------------------------------------------------
            -- The engine substitutes %1.. itself, but
            -- run it again in case a translation was
            -- loaded by a path that does not.
            ------------------------------------------------

            return
                substitute(
                    text,
                    args
                )
        end
    end


    return
        substitute(
            tostring(
                fallback
                or key
                or ""
            ),
            args
        )
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Text helper loaded"
)
