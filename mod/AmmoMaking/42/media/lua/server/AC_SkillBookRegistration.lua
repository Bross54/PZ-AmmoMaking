-- Ammo Making - Skill books: the entry in vanilla's table
-- Project Zomboid Build 42.20
--
-- Vanilla creates its SkillBook table in a server file
-- (media/lua/server/XpSystem/XPSystem_SkillBook.lua,
-- "SkillBook = {};"), and the engine loads every vanilla
-- file of the server folder before any mod file of it
-- (JAR, 42.20.4: LuaManager.LoadDirBase). So when this
-- file runs the table exists, and nothing after it in the
-- same load replaces it. Everything else is in
-- AC_SkillBooks (shared), which also adds the entry again
-- at game and server start.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: the console line
-- "[AmmoMaking] Skill books: Ammo Making entered in
-- vanilla's reading table (server Lua)" at world load.

require "AC_SkillBooks"


AC_SkillBooks.registerLogged(
    "server Lua"
)
