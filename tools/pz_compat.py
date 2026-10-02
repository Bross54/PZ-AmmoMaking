"""Ammo Making - does the installed game still match what the mod relies on?

    python tools/pz_compat.py --install "<Project Zomboid install>"
    python tools/pz_compat.py --install "<install>" --update

Run it after a Project Zomboid update. It reads the INSTALLED game (item and
recipe scripts, entity scripts, timed actions, tile definitions, vanilla Lua
and, through javap, projectzomboid.jar) and compares it with two things:

  1. what the mod names: every vanilla item, item tag, station tag, timed
     action, recipe, sprite, sound, event, global function and Java method.
     These come from the mod's own model and source (tools/mod_facts.lua and
     a scan of the Lua files), not from a list kept by hand, so a new calibre
     or recipe is covered without touching this file.
  2. the recorded snapshot of the build the mod was last checked against
     (tests/engine_snapshot.lua and tests/vanilla_snapshot.lua).

Each finding is one line:

  BREAKING  something the mod uses is gone or no longer fits: an item, a
            station tag, a method overload. That feature will not work.
  WARNING   a fact moved (a weight, a recipe body, a firearm's magazine, the
            game version) or could not be checked. Look, then --update.
  PASS      a group of checks found nothing.

Exit code: 0 all passed, 1 warnings only, 2 something breaking.

--update rewrites both snapshot files from the install. Run the suite
afterwards: it reads the snapshots, not the install.

The install is taken from --install or the PZ_INSTALL environment variable.
javap comes from --javap, JAVA_HOME or PATH; without it the Java checks are
skipped and reported as one WARNING. Needs Python with lupa (as the suite
does on a machine without a lua binary).

This proves what the files contain. It does not run the game.
"""

import argparse
import glob
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
MOD_LUA = ROOT + "/mod/AmmoMaking/42/media/lua/"
SNAPSHOT = ROOT + "/tests/engine_snapshot.lua"
VANILLA_SNAPSHOT = ROOT + "/tests/vanilla_snapshot.lua"

# Java classes behind the objects the mod talks to. The name on the left is
# how the snapshot and the test mock refer to the class. This list is the
# one thing here that is kept by hand: a Lua call does not say what class
# its receiver has.
CLASSES = {
    "InventoryItem": "zombie.inventory.InventoryItem",
    "HandWeapon": "zombie.inventory.types.HandWeapon",
    "ItemContainer": "zombie.inventory.ItemContainer",
    "IsoPlayer": "zombie.characters.IsoPlayer",
    "XP": "zombie.characters.IsoGameCharacter$XP",
    "IsoGridSquare": "zombie.iso.IsoGridSquare",
    "IsoObject": "zombie.iso.IsoObject",
    "IsoThumpable": "zombie.iso.objects.IsoThumpable",
    "IsoWorldInventoryObject": "zombie.iso.objects.IsoWorldInventoryObject",
    "IsoCell": "zombie.iso.IsoCell",
    "IsoWorld": "zombie.iso.IsoWorld",
    "IsoRoom": "zombie.iso.areas.IsoRoom",
    "IsoSprite": "zombie.iso.sprite.IsoSprite",
    "GameTime": "zombie.GameTime",
    "ScriptManager": "zombie.scripting.ScriptManager",
    "Item": "zombie.scripting.objects.Item",
    "CraftRecipe": "zombie.scripting.entity.components.crafting.CraftRecipe",
    "CraftRecipeData": "zombie.entity.components.crafting.recipe.CraftRecipeData",
    "PerkFactory": "zombie.characters.skills.PerkFactory",
    "Perk": "zombie.characters.skills.PerkFactory$Perk",
    "CharacterSoundEmitter": "zombie.characters.CharacterSoundEmitter",
    "HaloTextHelper": "zombie.characters.HaloTextHelper",
    "ItemPickerJava": "zombie.inventory.ItemPickerJava",
    "Core": "zombie.core.Core",
    "ArrayList": "java.util.ArrayList",
    "GlobalObject": "zombie.Lua.LuaManager$GlobalObject",
}

# Vanilla Lua the firearm designs (docs/SPENT_CASE_RESEARCH.md,
# docs/AMMO_QUALITY_RUNTIME_DESIGN.md) are built on. Nothing shipped calls
# these, so a change is a WARNING: the design has to be read again.
DESIGN_LUA = [
    "ISReloadWeaponAction.onShoot",
    "ISReloadWeaponAction.OnPlayerAttackFinished",
    "ISReloadWeaponAction:loadAmmo",
    "ISReloadWeaponAction:ejectSpentRounds",
    "ISRackFirearm:ejectSpentRounds",
    "ISRackFirearm:removeBullet",
    "ISRackFirearm:rackBullet",
    "ISInsertMagazine:loadAmmo",
    "ISEjectMagazine:unloadAmmo",
    "ISLoadBulletsInMagazine:animEvent",
    "ISUnloadBulletsFromMagazine:animEvent",
    "ISUnloadBulletsFromFirearm:animEvent",
]
DESIGN_METHODS = {
    "HandWeapon": [
        "getCurrentAmmoCount", "setCurrentAmmoCount", "getAmmoPerShoot", "getMaxAmmo",
        "isRoundChambered", "setRoundChambered", "isSpentRoundChambered", "setSpentRoundChambered",
        "getSpentRoundCount", "setSpentRoundCount", "haveChamber", "isRackAfterShoot",
        "isManuallyRemoveSpentRounds", "isContainsClip", "getMagazineType", "getShellFallSound",
        "checkJam", "getJamGunChance", "isRanged",
    ],
    "InventoryItem": ["getCurrentAmmoCount", "setCurrentAmmoCount", "getAmmoType", "getMaxAmmo"],
}

LUA_KEYWORDS = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())
LUA_STDLIB = set("assert error getmetatable ipairs next pairs pcall print rawequal rawget rawset require select setmetatable tonumber tostring type unpack math string table os io self _G".split())
# Methods of Lua's own string values (text:sub(1, 2)).
LUA_STRING_METHODS = set("byte find format gmatch gsub len lower match rep reverse sub upper".split())


# ----------------------------------------------------------------------
# Reading files
# ----------------------------------------------------------------------

def read(path):
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().replace("\r", "")


def blocks(text, keyword):
    """Every 'keyword Name { ... }' of a script, brace matched: (name, body)."""
    for match in re.finditer(r"(?m)^[ \t]*" + keyword + r"[ \t]+([^\s{]+)\s*\{", text):
        depth, index = 0, match.end() - 1
        while index < len(text):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        yield match.group(1), text[match.end():index]


def properties(body):
    """'Key = Value,' lines of a script block, outside nested blocks."""
    found = {}
    depth = 0
    for line in body.split("\n"):
        if depth == 0:
            match = re.match(r"\s*([\w:]+)\s*=\s*(.*?),?\s*$", line)
            if match:
                found[match.group(1)] = match.group(2)
        depth += line.count("{") - line.count("}")
    return found


def strip_lua(text):
    """Lua source without comments and string contents."""
    out = []
    index, length = 0, len(text)
    while index < length:
        two = text[index:index + 2]
        char = text[index]
        if two == "--":
            long = re.match(r"--\[(=*)\[", text[index:])
            if long:
                end = text.find("]" + long.group(1) + "]", index)
                index = length if end < 0 else end + 2 + len(long.group(1))
            else:
                end = text.find("\n", index)
                index = length if end < 0 else end
        elif char in "\"'":
            end = index + 1
            while end < length and text[end] != char:
                end += 2 if text[end] == "\\" else 1
            out.append(char + char)
            index = end + 1
        elif two == "[[" or re.match(r"\[=+\[", text[index:]):
            level = re.match(r"\[(=*)\[", text[index:]).group(1)
            end = text.find("]" + level + "]", index)
            out.append('""')
            index = length if end < 0 else end + 2 + len(level)
        else:
            out.append(char)
            index += 1
    return "".join(out)


# ----------------------------------------------------------------------
# The mod
# ----------------------------------------------------------------------

def lua_runtime():
    from lupa.lua51 import LuaRuntime
    return LuaRuntime(unpack_returned_tuples=True)


def to_python(value):
    """A Lua table as a dict or a list."""
    from lupa import lua51
    if lua51.lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_python(value[key]) for key in range(1, len(keys) + 1)]
    return {key: to_python(value[key]) for key in keys}


def mod_facts():
    lua = lua_runtime()
    lua.execute("print = function() end")
    lua.execute('MOCK = dofile("%s/tests/mock_pz.lua")' % ROOT)
    lua.execute('MOCK.capturePrint = function() end')
    lua.execute('MOCK.loadMod("%s")' % MOD_LUA)
    facts = to_python(lua.eval('dofile("%s/tools/mod_facts.lua")' % ROOT))
    for key in ("items", "itemTags", "benchTags", "timedActions", "vanillaRecipes", "lootLists", "sprites", "sounds", "modItems", "uses"):
        if isinstance(facts.get(key), list):
            facts[key] = {}
    return facts


def mod_sources():
    files = sorted(glob.glob(MOD_LUA + "**/*.lua", recursive=True))
    return {path.replace("\\", "/")[len(MOD_LUA):]: read(path) for path in files}


def mod_calls(sources):
    """What the mod's Lua reaches for outside itself.

    methods  name -> set of argument counts, for every receiver:name(...)
    globals  bare names called or read that no mod file defines
    members  'Table.member' for tables the mod does not define
    events   names used as Events.<name>.Add
    """
    defined = set()
    stripped = {}
    for name, text in sources.items():
        clean = strip_lua(text)
        stripped[name] = clean
        for match in re.finditer(r"(?m)^\s*(?:local\s+)?function\s+([A-Za-z_]\w*)", clean):
            defined.add(match.group(1))
        for match in re.finditer(r"(?m)^([A-Za-z_]\w*)\s*=", clean):
            defined.add(match.group(1))
        for match in re.finditer(r"\blocal\s+((?:[A-Za-z_]\w*\s*,\s*)*[A-Za-z_]\w*)", clean):
            for local in match.group(1).split(","):
                defined.add(local.strip())
        for match in re.finditer(r"\bfunction\b[^(]*\(([^)]*)\)", clean):
            for parameter in match.group(1).split(","):
                defined.add(parameter.strip())
        for match in re.finditer(r"\bfor\s+([\w\s,]+?)\s+(?:in\b|=)", clean):
            for variable in match.group(1).split(","):
                defined.add(variable.strip())

    methods, global_names, members, events, probed = {}, {}, {}, {}, set()
    call_counts = {}
    for name, clean in stripped.items():
        for match in re.finditer(r":\s*([A-Za-z_]\w*)\s*\(", clean):
            count = argument_count(clean, match.end() - 1)
            methods.setdefault(match.group(1), {}).setdefault(count, name)
        for match in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)((?:\.[A-Za-z_]\w*)*)", clean):
            head, tail = match.group(1), match.group(2)
            if head in LUA_KEYWORDS or head in LUA_STDLIB or head in defined:
                continue
            before = clean[:match.start()].rstrip()[-1:]
            after = clean[match.end():].lstrip()[:2]
            # "x.\n    name" and "x:\n    name(": a member, not a global.
            if before in (".", ":"):
                continue
            # A table constructor's field name ("name = value") is not a reference.
            if not tail and after.startswith("=") and after != "==" and before in ("{", ","):
                continue
            # "if X and X.y", "type(X)": the mod asks whether X exists.
            previous_word = re.search(r"(\w+)\s*$", clean[:match.start()])
            if after.startswith("an") and clean[match.end():].lstrip().startswith("and") or (previous_word and previous_word.group(1) in ("not", "or")) or clean[:match.start()].rstrip().endswith("type("):
                probed.add(head)
            if head == "Events":
                parts = tail.split(".")
                if len(parts) > 1 and parts[1]:
                    events.setdefault(parts[1], name)
                continue
            global_names.setdefault(head, name)
            called = clean[match.end():].lstrip()[:1] == "("
            if tail:
                member = head + "." + tail.split(".")[1]
                members.setdefault(member, name)
                if called and tail.count(".") == 1:
                    call_counts.setdefault(member, {}).setdefault(argument_count(clean, clean.index("(", match.end())), name)
            elif called:
                call_counts.setdefault(head, {}).setdefault(argument_count(clean, clean.index("(", match.end())), name)
    return {"methods": methods, "globals": global_names, "members": members, "events": events, "probed": probed, "callCounts": call_counts}


def argument_count(text, open_index):
    """Arguments of the call whose '(' is at open_index."""
    depth, index, commas, seen = 0, open_index, 0, False
    while index < len(text):
        char = text[index]
        if char in "({[":
            depth += 1
        elif char in ")}]":
            depth -= 1
            if depth == 0:
                break
        elif depth == 1:
            if char == ",":
                commas += 1
            elif not char.isspace():
                seen = True
        index += 1
    return commas + 1 if seen else 0


def mock_methods():
    """Method names the test mock gives its engine objects."""
    text = strip_lua(read(ROOT + "/tests/mock_pz.lua"))
    names = set(re.findall(r"\bfunction\s+\w+:(\w+)\(", text))
    names.update(re.findall(r"(?m)^\s*(\w+)\s*=\s*(?:\w+\s+and\s+)?function\(", text))
    return names


# ----------------------------------------------------------------------
# The installed game
# ----------------------------------------------------------------------

class Install:
    def __init__(self, root):
        self.root = root.replace("\\", "/").rstrip("/")
        self.scripts = self.root + "/media/scripts/"
        if not os.path.isdir(self.scripts):
            raise SystemExit("not a Project Zomboid install (no media/scripts): " + self.root)
        self._script_texts = None
        self._lua_index = None

    def script_texts(self):
        if self._script_texts is None:
            self._script_texts = {
                path.replace("\\", "/"): read(path)
                for path in sorted(glob.glob(self.scripts + "**/*.txt", recursive=True))
            }
        return self._script_texts

    def items(self):
        found = {}
        for path, text in self.script_texts().items():
            if "/items/" not in path:
                continue
            for name, body in blocks(text, "item"):
                found["Base." + name] = properties(body)
        return found

    def recipes(self):
        found = {}
        for text in self.script_texts().values():
            if "craftRecipe" not in text:
                continue
            for name, body in blocks(text, "craftRecipe"):
                found[name] = body
        return found

    def entities(self):
        found = {}
        for text in self.script_texts().values():
            if "entity" not in text:
                continue
            for name, body in blocks(text, "entity"):
                found[name] = body
        return found

    def timed_actions(self):
        names = set()
        for text in self.script_texts().values():
            names.update(re.findall(r"(?m)^\s*timedAction\s+(\w+)\s*$", text))
        return names

    def sounds(self):
        names = set()
        for path, text in self.script_texts().items():
            if "/sounds/" in path:
                names.update(re.findall(r"(?m)^\s*sound\s+(\w+)\s*$", text))
        return names

    def tile(self, sprite):
        """The property block of a tile, or None when the tile is not defined."""
        for path in sorted(glob.glob(self.root + "/media/*.tiles.txt")):
            text = read(path)
            at = text.find("// " + sprite + "\n")
            if at >= 0:
                open_at = text.find("{", at)
                return properties(text[open_at + 1:text.find("}", open_at)])
        return None

    def lua_index(self):
        """Global names and Table.member names vanilla Lua defines."""
        if self._lua_index is None:
            names, members, parents = set(), set(), {}
            for path in glob.glob(self.root + "/media/lua/**/*.lua", recursive=True):
                text = read(path).lstrip("\ufeff")
                for match in re.finditer(r"(?m)^ ?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*):derive\(", text):
                    parents[match.group(1)] = match.group(2)
                for match in re.finditer(r"(?m)^(?:local\s+)?function\s+([A-Za-z_]\w*)([.:])?([A-Za-z_]\w*)?", text):
                    if match.group(0).startswith("local"):
                        continue
                    names.add(match.group(1))
                    if match.group(3):
                        members.add(match.group(1) + "." + match.group(3))
                        members.add(match.group(1) + ":" + match.group(3))
                for match in re.finditer(r"(?m)^ ?([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?\s*=[^=]", text):
                    names.add(match.group(1))
                    if match.group(2):
                        members.add(match.group(1) + "." + match.group(2))
            # A class made with Parent:derive("Name") has its parent's members.
            for child in list(parents):
                seen, parent = set(), parents.get(child)
                while parent and parent not in seen:
                    seen.add(parent)
                    for member in list(members):
                        if member.startswith(parent + ".") or member.startswith(parent + ":"):
                            members.add(child + member[len(parent):])
                    parent = parents.get(parent)
            self._lua_index = (names, members)
        return self._lua_index


# ----------------------------------------------------------------------
# The jar
# ----------------------------------------------------------------------

class Jar:
    def __init__(self, install, javap):
        self.jar = install.root + "/projectzomboid.jar"
        self.javap = javap
        self.cache = {}

    def run(self, classes, code=False):
        command = [self.javap, "-cp", self.jar, "-p"]
        if code:
            command += ["-c", "-constants"]
        result = subprocess.run(command + list(classes), capture_output=True, text=True, errors="replace")
        return result.stdout

    def load(self, names):
        """Parses the public methods and fields of classes, and their superclasses."""
        wanted = [name for name in names if name not in self.cache]
        while wanted:
            output = self.run(wanted)
            parsed = parse_javap(output)
            for name in wanted:
                self.cache[name] = parsed.get(name)
            wanted = []
            for info in parsed.values():
                parent = info["extends"]
                if parent and parent not in self.cache and parent not in wanted:
                    wanted.append(parent)

    def methods(self, name):
        """Method name -> signatures, the class's own and inherited ones."""
        self.load([name])
        found = {}
        seen = set()
        while name and name not in seen:
            seen.add(name)
            self.load([name])
            info = self.cache.get(name)
            if not info:
                break
            for method, signatures in info["methods"].items():
                bucket = found.setdefault(method, [])
                for signature in signatures:
                    if signature not in bucket:
                        bucket.append(signature)
            name = info["extends"]
        return found

    def fields(self, name):
        self.load([name])
        info = self.cache.get(name)
        return info["fields"] if info else set()

    def constructors(self, name):
        self.load([name])
        info = self.cache.get(name)
        return info["constructors"] if info else []

    def exists(self, name):
        self.load([name])
        return self.cache.get(name) is not None

    def lua_globals(self):
        """The functions the engine gives Lua as globals: Lua name -> signatures.

        The Lua name is the one in the method's @LuaMethod annotation, which
        is not always the Java name (instanceof is instof in Java).
        """
        command = [self.javap, "-cp", self.jar, "-p", "-v", CLASSES["GlobalObject"]]
        output = subprocess.run(command, capture_output=True, text=True, errors="replace").stdout
        found = {}
        current = None
        lines = output.split("\n")
        for index, line in enumerate(lines):
            method = re.match(r"^  public\s+(static\s+)?(?:final\s+|synchronized\s+|native\s+)*(?:<.+?>\s+)?[\w.$<>\[\],? ]+?\s+(\w+)\((.*?)\)(?:\s+throws\s+.*)?;$", line)
            if method:
                current = signature(method.group(3), True)
            elif "LuaMethod(" in line and current is not None:
                block = " ".join(lines[index:index + 4])
                name = re.search(r'name="(\w+)"', block)
                if name and "global=true" in block.replace(" ", ""):
                    bucket = found.setdefault(name.group(1), [])
                    if current not in bucket:
                        bucket.append(current)
        return found

    def nearest_exposed(self, name, exposed):
        """The class itself, or the closest superclass the game exposes to Lua."""
        seen = set()
        while name and name not in seen:
            if name in exposed or name.startswith("java."):
                return name
            seen.add(name)
            self.load([name])
            info = self.cache.get(name)
            name = info["extends"] if info else None
        return None

    def ammo_types(self):
        """'base:bullets_9mm' -> 'Base.Bullets9mm', from the engine's AmmoType registry."""
        found = {}
        keys = {}
        lines = self.run(["zombie.scripting.objects.AmmoType"], code=True).split("\n")
        for index, line in enumerate(lines):
            name = re.search(r"// String (\w+)$", line)
            if name and index + 1 < len(lines):
                key = re.search(r"Field zombie/scripting/objects/(ItemKey\$\w+)\.(\w+):", lines[index + 1])
                if key:
                    keys[name.group(1)] = (key.group(1), key.group(2))
        tables = {}
        for name, (owner, field) in keys.items():
            if owner not in tables:
                table = {}
                previous = None
                for line in self.run(["zombie.scripting.objects." + owner], code=True).split("\n"):
                    text = re.search(r"// String (\w+)$", line)
                    stored = re.search(r"putstatic .*// Field (\w+):", line)
                    if text:
                        previous = text.group(1)
                    elif stored and previous:
                        table[stored.group(1)] = previous
                        previous = None
                tables[owner] = table
            if field in tables[owner]:
                found["base:" + name] = "Base." + tables[owner][field]
        return found

    def strings(self, name):
        """String constants loaded by a class's code."""
        return set(re.findall(r"// String (\S+)", self.run([name], code=True)))

    def exposed(self):
        """Classes the game hands to Lua (LuaManager.Exposer.exposeAll)."""
        output = self.run(["zombie.Lua.LuaManager$Exposer"], code=True)
        names = set()
        previous = ""
        for line in output.split("\n"):
            if "setExposed" in line:
                match = re.search(r"// class (\S+)", previous)
                if match:
                    names.add(match.group(1).strip('"').replace("/", "."))
            previous = line
        return names

    def version(self):
        output = self.run(["zombie.core.Core"], code=True)
        numbers = []
        lines = output.split("\n")
        for index, line in enumerate(lines):
            if "Field gameVersion:" in line and "putstatic" in line:
                for back in lines[max(0, index - 8):index]:
                    match = re.search(r"\b(?:bipush|sipush)\s+(\d+)|\biconst_(\d)", back)
                    if match:
                        numbers.append(match.group(1) or match.group(2))
        build = re.search(r"static final int buildVersion = (\d+);", output)
        if len(numbers) >= 2:
            return ".".join(numbers[-2:]) + ("." + build.group(1) if build else "")
        return None


def parse_javap(output):
    classes = {}
    current = None
    for line in output.split("\n"):
        header = re.match(r"^(?:public |protected |private )?(?:abstract |final |static |sealed |non-sealed )*(?:class|interface|enum) ([\w.$]+)(?:<.*?>)?(?: extends ([\w.$]+))?", line)
        if header and line.rstrip().endswith("{"):
            current = {"name": header.group(1), "extends": header.group(2), "methods": {}, "fields": set(), "constructors": []}
            if " interface " in " " + line:
                current["extends"] = None
            classes[header.group(1)] = current
            continue
        if current is None:
            continue
        method = re.match(r"^\s+public\s+(static\s+)?(?:final\s+|synchronized\s+|native\s+|abstract\s+|default\s+|strictfp\s+)*(?:<.+?>\s+)?[\w.$<>\[\],? ]+?\s+(\w+)\((.*?)\)(?:\s+throws\s+.*)?;$", line)
        if method:
            current["methods"].setdefault(method.group(2), []).append(signature(method.group(3), bool(method.group(1))))
            continue
        # A public constructor: Kahlua exposes it as Class.new(...).
        constructor = re.match(r"^\s+public\s+([\w.$]+)\((.*?)\)(?:\s+throws\s+.*)?;$", line)
        if constructor and constructor.group(1) == current["name"]:
            current["constructors"].append(signature(constructor.group(2), True))
            continue
        field = re.match(r"^\s+public\s+(?:static\s+)?(?:final\s+)?[\w.$<>\[\],? ]+\s+(\w+)(?:\s*=.*)?;$", line)
        if field:
            current["fields"].add(field.group(1))
    return classes


def signature(parameters, static):
    """'static InventoryItem,float' : simple type names, '...' kept for varargs."""
    parts, depth, piece = [], 0, ""
    for char in parameters:
        if char == "<":
            depth += 1
        elif char == ">":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(piece)
            piece = ""
        elif depth == 0:
            piece += char
    if piece.strip():
        parts.append(piece)
    simple = []
    for part in parts:
        part = part.strip()
        varargs = part.endswith("...")
        array = ""
        while part.endswith("[]"):
            part, array = part[:-2], array + "[]"
        name = part.rstrip(".").split(".")[-1].split("$")[-1] + array + ("..." if varargs else "")
        simple.append(name)
    return ("static " if static else "") + ",".join(simple)


def find_javap(argument):
    candidates = [argument, os.environ.get("JAVAP")]
    if os.environ.get("JAVA_HOME"):
        candidates.append(os.path.join(os.environ["JAVA_HOME"], "bin", "javap"))
    candidates.append(shutil.which("javap"))
    candidates += sorted(glob.glob("C:/Program Files/Java/*/bin/javap.exe"), reverse=True)
    candidates += sorted(glob.glob("/usr/lib/jvm/*/bin/javap"), reverse=True)
    for candidate in candidates:
        if candidate and (os.path.isfile(candidate) or os.path.isfile(candidate + ".exe")):
            return candidate
    return None


# ----------------------------------------------------------------------
# The snapshot: what the installed game says about everything the mod names
# ----------------------------------------------------------------------

def number(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def uses_of(properties_):
    delta = number(properties_.get("UseDelta"))
    return int(round(1 / delta)) if delta else None


def digest(body):
    return hashlib.sha1(re.sub(r"\s+", " ", body).strip().encode("utf-8")).hexdigest()[:12]


def build_snapshot(install, jar, facts, calls):
    snapshot = {}
    items = install.items()

    snapshot["items"] = {}
    for item in sorted(facts["items"]):
        script = items.get(item)
        if script is None:
            snapshot["items"][item] = False
            continue
        entry = {"type": script.get("ItemType", script.get("Type", "")), "weight": number(script.get("Weight"))}
        if uses_of(script):
            entry["uses"] = uses_of(script)
        if script.get("AmmoType"):
            entry["ammoType"] = script["AmmoType"]
        if script.get("Tags"):
            entry["tags"] = ";".join(sorted(tag.strip() for tag in script["Tags"].split(";") if tag.strip()))
        snapshot["items"][item] = entry

    snapshot["itemTags"] = {}
    for tag in sorted(facts["itemTags"]):
        carriers = sorted(name for name, script in items.items() if tag in [part.strip() for part in script.get("Tags", "").split(";")])
        snapshot["itemTags"][tag] = len(carriers)

    recipes = install.recipes()
    entities = install.entities()
    providers = {}
    for name, body in entities.items():
        match = re.search(r"component\s+CraftBench\s*\{[^}]*?Recipes\s*=\s*([^,\n}]*)", body)
        if match:
            for tag in match.group(1).split(";"):
                providers.setdefault(tag.strip(), []).append(name)
    recipe_tags = {}
    for name, body in recipes.items():
        match = re.search(r"(?m)^\s*Tags\s*=\s*([^,\n]*)", body)
        if match:
            for tag in match.group(1).split(";"):
                recipe_tags[tag.strip()] = recipe_tags.get(tag.strip(), 0) + 1

    snapshot["benchTags"] = {}
    wanted_tags = set(facts["benchTags"]) | {facts["press"]["benchTag"]}
    for tag in sorted(wanted_tags):
        snapshot["benchTags"][tag] = {
            "stations": len(providers.get(tag, [])),
            "vanillaRecipes": recipe_tags.get(tag, 0),
        }

    actions = install.timed_actions()
    snapshot["timedActions"] = {name: name in actions for name in sorted(set(facts["timedActions"]) | {facts["press"]["timedAction"]})}

    snapshot["recipes"] = {}
    watched = set(facts["vanillaRecipes"]) | {"GatherGunpowder", "OpenBoxOfBullets50", "OpenBoxOfBullets20", "OpenBoxOfShotgunShells", "Place12BoxesInCarton", "PressClayBrick"}
    for name in sorted(watched):
        snapshot["recipes"][name] = digest(recipes[name]) if name in recipes else False

    # Firearms and magazines: what takes each round.
    snapshot["firearms"] = {}
    snapshot["magazines"] = {}
    for name, script in sorted(items.items()):
        if not script.get("AmmoType"):
            continue
        short = name[5:]
        if script.get("GunType"):
            snapshot["magazines"][short] = {"ammoType": script["AmmoType"], "maxAmmo": number(script.get("MaxAmmo")), "gunType": script["GunType"]}
        elif script.get("ItemType", "").endswith("weapon") or script.get("MaxAmmo"):
            entry = {"ammoType": script["AmmoType"], "maxAmmo": number(script.get("MaxAmmo"))}
            for key, field in (("MagazineType", "magazine"), ("RackAfterShoot", "rackAfterShoot"), ("ManuallyRemoveSpentRounds", "manuallyRemoveSpentRounds"), ("HaveChamber", "haveChamber"), ("InsertAllBulletsReload", "insertAllBulletsReload"), ("JamGunChance", "jamGunChance")):
                if key in script:
                    entry[field] = script[key]
            snapshot["firearms"][short] = entry

    snapshot["sprites"] = {}
    claimed = {}
    for name, body in entities.items():
        for row in re.findall(r"row\s*=\s*([^,\n]*)", body):
            for sprite in row.split():
                claimed[sprite] = name
    for sprite in sorted(facts["sprites"]):
        tile = install.tile(sprite)
        snapshot["sprites"][sprite] = False if tile is None else {
            "moveable": "IsMoveAble" in tile,
            "entity": claimed.get(sprite, False),
        }

    sounds = install.sounds()
    snapshot["sounds"] = {name: name in sounds for name in sorted(facts["sounds"])}

    lua_names, lua_members = install.lua_index()
    snapshot["design"] = {name: (name in lua_members) for name in DESIGN_LUA}
    # Methods of the vanilla Lua classes the mod itself uses (and of their
    # parents): a receiver:name() call may be one of those.
    lua_classes = set(name for name in calls["globals"] if name in lua_names)
    vanilla_methods = set(re.split(r"[.:]", member)[1] for member in lua_members if re.split(r"[.:]", member)[0] in lua_classes)
    snapshot["luaMethods"] = {name: True for name in sorted(calls["methods"]) if name in vanilla_methods}

    snapshot["globals"] = {}
    snapshot["functions"] = {}
    snapshot["members"] = {}
    snapshot["events"] = {}
    snapshot["classes"] = {}
    snapshot["ammoTypes"] = {}
    snapshot["version"] = None
    if jar is None:
        return snapshot

    snapshot["version"] = jar.version()
    snapshot["ammoTypes"] = jar.ammo_types()
    exposed = jar.exposed()
    global_methods = jar.lua_globals()
    snapshot["functions"] = {}
    for name in sorted(calls["globals"]):
        if name in global_methods:
            snapshot["globals"][name] = "java"
            snapshot["functions"][name] = sorted(global_methods[name])
        elif name in lua_names:
            snapshot["globals"][name] = "lua"
        else:
            simple = [full for full in exposed if full.split(".")[-1].split("$")[-1] == name]
            snapshot["globals"][name] = "class " + sorted(simple)[0] if simple else False

    for member in sorted(calls["members"]):
        head, tail = member.split(".", 1)
        kind = snapshot["globals"].get(head)
        if kind == "lua":
            snapshot["members"][member] = member in lua_members
        elif isinstance(kind, str) and kind.startswith("class "):
            full = kind[6:]
            # Kahlua exposes a public constructor as Class.new.
            if tail in jar.methods(full):
                snapshot["members"][member] = sorted(jar.methods(full)[tail])
            elif tail == "new":
                snapshot["members"][member] = sorted(jar.constructors(full)) or False
            else:
                snapshot["members"][member] = tail in jar.fields(full) or jar.exists(full + "$" + tail)

    event_names = jar.strings("zombie.Lua.LuaEventManager")
    snapshot["events"] = {name: name in event_names for name in sorted(calls["events"])}

    wanted_methods = set(calls["methods"]) | mock_methods()
    for short, full in sorted(CLASSES.items()):
        if short == "GlobalObject":
            continue
        # Lua sees the methods of the class, or of its nearest exposed ancestor.
        visible = jar.nearest_exposed(full, exposed)
        methods = jar.methods(visible) if visible else {}
        entry = {"class": full, "exposed": visible or False, "methods": {}}
        for name in sorted(wanted_methods | set(DESIGN_METHODS.get(short, []))):
            if name in methods:
                entry["methods"][name] = sorted(methods[name])
        if not jar.exists(full):
            entry["missing"] = True
        snapshot["classes"][short] = entry
    return snapshot


# ----------------------------------------------------------------------
# Writing and reading the snapshot (a Lua table, so the suite can read it)
# ----------------------------------------------------------------------

def lua_value(value, indent):
    pad = "    " * indent
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return ("%d" % value) if float(value).is_integer() else repr(round(value, 6))
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, list):
        if not value:
            return "{}"
        return "{ " + ", ".join(lua_value(item, indent) for item in value) + " }"
    lines = ["{"]
    for key in sorted(value):
        name = key if re.match(r"^[A-Za-z_]\w*$", key) and key not in LUA_KEYWORDS else '["%s"]' % key
        lines.append("%s    %s = %s," % (pad, name, lua_value(value[key], indent + 1)))
    lines.append(pad + "}")
    return "\n".join(lines) if len(lines) > 2 else "{}"


def write_snapshot(snapshot):
    text = (
        "-- GENERATED by tools/pz_compat.py --update from the installed game files.\n"
        "-- Do not edit: re-run the tool after a game update.\n"
        "--\n"
        "-- What the installed build says about everything the mod names: items,\n"
        "-- tags, stations, timed actions, vanilla recipes (as digests), firearms,\n"
        "-- sprites, sounds, events, globals, and the Java overloads of every\n"
        "-- method the mod or the test mock calls. false means: not there.\n"
        "return " + lua_value(snapshot, 0) + "\n"
    )
    with io.open(SNAPSHOT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def read_snapshot():
    if not os.path.isfile(SNAPSHOT):
        return None
    lua = lua_runtime()
    return to_python(lua.eval('dofile("%s")' % SNAPSHOT))


def vanilla_snapshot_text(install, version):
    """What tests/snapshot_vanilla.lua would write for this install."""
    lua = lua_runtime()
    lua.execute('arg = { [0] = "%s/tests/snapshot_vanilla.lua", "%s", "%s" }' % (ROOT, install.root, version or "unknown"))
    lua.execute('''
        __written = nil
        print = function() end
        local realOpen = io.open
        io.open = function(path, mode)
            if mode == "w" then
                return { write = function(_, text) __written = text end, close = function() end }
            end
            return realOpen(path, mode)
        end
    ''')
    lua.execute("dofile(arg[0])")
    return lua.globals()["__written"]


# ----------------------------------------------------------------------
# The verdict
# ----------------------------------------------------------------------

class Report:
    def __init__(self):
        self.lines = []
        self.worst = 0

    def add(self, level, text):
        self.lines.append((level, text))
        self.worst = max(self.worst, {"PASS": 0, "WARNING": 1, "BREAKING": 2}[level])

    def group(self, title, findings):
        """findings: list of (level, text). An empty list is a PASS line."""
        if not findings:
            self.add("PASS", title)
        for level, text in findings:
            self.add(level, title + ": " + text)

    def print(self):
        for level, text in self.lines:
            print("%-8s %s" % (level, text))
        counts = {level: sum(1 for entry in self.lines if entry[0] == level) for level in ("PASS", "WARNING", "BREAKING")}
        print("")
        print("%d passed, %d warnings, %d breaking" % (counts["PASS"], counts["WARNING"], counts["BREAKING"]))


def fits(signature_, count):
    """Can an instance call with count arguments use this overload?

    Kahlua (LuaJavaInvoker.prepareCall): too few arguments fail; too many fail
    for a method with a receiver; a varargs method takes any number beyond its
    fixed parameters.
    """
    static = signature_.startswith("static ")
    body = signature_[7:] if static else signature_
    parameters = [part for part in body.split(",") if part]
    if parameters and parameters[-1].endswith("..."):
        return count >= len(parameters) - 1
    if static:
        return count >= len(parameters)
    return count == len(parameters)


def judge(snapshot, facts, calls, recorded, have_jar):
    report = Report()

    # ---- what the mod names must exist
    findings = []
    for item, entry in snapshot["items"].items():
        if entry is False:
            findings.append(("BREAKING", "%s does not exist (used by %s)" % (item, facts["items"][item])))
    report.group("vanilla items the mod names (%d)" % len(snapshot["items"]), findings)

    findings = []
    for item, uses in sorted(facts["uses"].items()):
        entry = snapshot["items"].get(item)
        if entry and entry.get("uses") != uses:
            findings.append(("BREAKING", "%s holds %s uses, the material model assumes %s" % (item, entry.get("uses"), uses)))
    report.group("drainable use counts", findings)

    findings = []
    for tag, count in snapshot["itemTags"].items():
        if count == 0:
            findings.append(("BREAKING", "no vanilla item carries %s (used by %s)" % (tag, facts["itemTags"][tag])))
    report.group("item tags in recipe lines (%d)" % len(snapshot["itemTags"]), findings)

    findings = []
    for tag, entry in snapshot["benchTags"].items():
        if tag == facts["press"]["benchTag"]:
            if entry["stations"] or entry["vanillaRecipes"]:
                findings.append(("WARNING", "%s, the press's own tag, is now used by vanilla" % tag))
            continue
        if entry["stations"] == 0 and entry["vanillaRecipes"] == 0:
            findings.append(("BREAKING", "no station provides %s and no vanilla recipe uses it (used by %s)" % (tag, facts["benchTags"][tag])))
    report.group("station tags (%d)" % len(facts["benchTags"]), findings)

    findings = []
    for name, present in snapshot["timedActions"].items():
        if not present:
            level = "WARNING" if name not in facts["timedActions"] else "BREAKING"
            findings.append((level, "timed action %s does not exist" % name))
    report.group("timed actions", findings)

    findings = []
    for name, value in snapshot["recipes"].items():
        if value is False and name in facts["vanillaRecipes"]:
            findings.append(("WARNING", "vanilla recipe %s does not exist; the conservation model and the box check refer to it" % name))
    report.group("vanilla recipes the model refers to", findings)

    findings = []
    takers = {}
    for group in ("firearms", "magazines"):
        for name, entry in snapshot[group].items():
            takers.setdefault(entry["ammoType"], []).append(name)
    for calibre in facts["calibres"]:
        if calibre["ammoType"] not in takers:
            findings.append(("BREAKING", "nothing fires %s: no firearm or magazine has AmmoType %s" % (calibre["round"], calibre["ammoType"])))
        entry = snapshot["items"].get(calibre["round"])
        if entry and "base:ammo" not in (entry.get("tags") or ""):
            findings.append(("WARNING", "%s no longer carries base:ammo (GatherGunpowder, the conservation model)" % calibre["round"]))
    report.group("every round has a firearm (%d calibres)" % len(facts["calibres"]), findings)

    findings = []
    for sprite, entry in snapshot["sprites"].items():
        if entry is False:
            findings.append(("BREAKING", "tile %s is not defined (%s)" % (sprite, facts["sprites"][sprite])))
        else:
            if entry["entity"]:
                findings.append(("BREAKING", "tile %s is now claimed by entity %s (%s)" % (sprite, entry["entity"], facts["sprites"][sprite])))
            if entry["moveable"]:
                findings.append(("WARNING", "tile %s is now a vanilla moveable: furniture pickup can take it" % sprite))
    report.group("sprites", findings)

    findings = [("WARNING", "sound %s does not exist (%s)" % (name, facts["sounds"][name])) for name, present in snapshot["sounds"].items() if not present]
    report.group("sounds", findings)

    findings = [("WARNING", "%s is gone: the firearm designs rely on it" % name) for name, present in snapshot["design"].items() if not present]
    report.group("vanilla firearm Lua the designs rely on (%d)" % len(snapshot["design"]), findings)

    if not have_jar:
        report.add("WARNING", "javap not found: the game version, ammo types, events, globals and Java methods were not checked")
    else:
        findings = []
        for calibre in facts["calibres"]:
            item = snapshot["ammoTypes"].get(calibre["ammoType"])
            if item != calibre["round"]:
                findings.append(("BREAKING", "ammo type %s is %s in the engine, the calibre model makes %s for it" % (calibre["ammoType"], item or "not registered", calibre["round"])))
        report.group("the engine's ammo types name the rounds the mod makes", findings)

        findings = [("BREAKING", "event %s is not registered by the engine (%s)" % (name, calls["events"][name])) for name, present in snapshot["events"].items() if not present]
        report.group("events the mod listens to (%d)" % len(snapshot["events"]), findings)

        findings = []
        for name, kind in snapshot["globals"].items():
            # A name the mod asks about before using it ("if X and X.y") may
            # be a fallback for an older build. Its absence is an error only
            # if the recorded build had it.
            known_absent = name in calls["probed"] and (recorded is None or (recorded.get("globals") or {}).get(name) is False)
            if kind is False and not known_absent:
                findings.append(("BREAKING", "%s is neither a Java global, an exposed class nor defined by vanilla Lua (%s)" % (name, calls["globals"][name])))
        for member, present in snapshot["members"].items():
            if not present:
                findings.append(("BREAKING", "%s does not exist (%s)" % (member, calls["members"][member])))
        report.group("globals and their members (%d, %d)" % (len(snapshot["globals"]), len(snapshot["members"])), findings)

        # Calls of Java globals and of static Java methods: an overload must
        # take that many arguments.
        findings = []
        checked = 0
        for name, counts in sorted(calls["callCounts"].items()):
            signatures = snapshot["functions"].get(name)
            if signatures is None and isinstance(snapshot["members"].get(name), list):
                signatures = snapshot["members"][name]
            if not signatures:
                continue
            checked += 1
            for count, where in sorted(counts.items()):
                if not any(fits(signature_, count) for signature_ in signatures):
                    findings.append(("BREAKING", "%s() is called with %d argument%s in %s; the overloads are (%s)" % (name, count, "" if count == 1 else "s", where, ") (".join(signatures))))
        report.group("calls of Java globals and static methods (%d)" % checked, findings)

        findings = []
        for short, entry in snapshot["classes"].items():
            if entry.get("missing"):
                findings.append(("BREAKING", "class %s is gone" % entry["class"]))
            elif not entry["exposed"]:
                findings.append(("BREAKING", "class %s is no longer exposed to Lua" % entry["class"]))
        report.group("engine classes (%d)" % len(snapshot["classes"]), findings)

        # Every receiver:method(n arguments) in the mod: some engine class, a
        # vanilla Lua class or the mod itself must take that call.
        findings = []
        lua_method_names = set()
        for path in glob.glob(ROOT + "/mod/**/*.lua", recursive=True):
            lua_method_names.update(re.findall(r"\bfunction\s+[\w.]+:(\w+)\(", read(path)))
        vanilla_members = snapshot["luaMethods"]
        for method, counts in sorted(calls["methods"].items()):
            signatures = []
            for entry in snapshot["classes"].values():
                signatures += entry["methods"].get(method, [])
            in_lua = method in lua_method_names or method in vanilla_members or method in LUA_STRING_METHODS
            if not signatures and not in_lua:
                findings.append(("BREAKING", ":%s() is defined by no engine class in the list, no vanilla Lua class and no mod file (%s)" % (method, sorted(counts.values())[0])))
                continue
            if in_lua:
                continue
            for count, where in sorted(counts.items()):
                if not any(fits(signature_, count) for signature_ in signatures):
                    findings.append(("BREAKING", ":%s() is called with %d argument%s in %s; the overloads are (%s)" % (method, count, "" if count == 1 else "s", where, ") (".join(signatures))))
        report.group("method calls and their argument counts (%d methods)" % len(calls["methods"]), findings)

        # A method the mod calls that one of these classes had in the recorded
        # build and has lost, or no longer takes with that many arguments.
        # The receiver of a Lua call is not known, so this reports on every
        # class that had the method.
        findings = []
        for short, old in sorted(((recorded or {}).get("classes") or {}).items()):
            now = snapshot["classes"].get(short, {}).get("methods", {})
            for method, counts in sorted(calls["methods"].items()):
                before = (old.get("methods") or {}).get(method)
                if not before:
                    continue
                if method not in now:
                    findings.append(("BREAKING", "%s.%s is gone; the mod calls :%s() in %s" % (short, method, method, sorted(counts.values())[0])))
                    continue
                for count, where in sorted(counts.items()):
                    if any(fits(signature_, count) for signature_ in before) and not any(fits(signature_, count) for signature_ in now[method]):
                        findings.append(("BREAKING", "%s.%s no longer takes %d argument%s (%s); the overloads are (%s)" % (short, method, count, "" if count == 1 else "s", where, ") (".join(now[method]))))
        report.group("methods the recorded build had", findings)

        findings = []
        for short, names in DESIGN_METHODS.items():
            for name in names:
                if name not in snapshot["classes"][short]["methods"]:
                    findings.append(("WARNING", "%s.%s is gone: the firearm designs rely on it" % (short, name)))
        report.group("firearm methods the designs rely on", findings)

    # ---- what moved since the recorded snapshot
    findings = []
    if recorded is None:
        findings.append(("WARNING", "tests/engine_snapshot.lua does not exist; run with --update"))
    else:
        if have_jar and recorded.get("version") != snapshot["version"]:
            findings.append(("WARNING", "game version %s, recorded %s" % (snapshot["version"], recorded.get("version"))))
        for section in ("items", "itemTags", "benchTags", "timedActions", "recipes", "firearms", "magazines", "sprites", "sounds", "design", "luaMethods") + (("ammoTypes", "events", "globals", "functions", "members", "classes") if have_jar else ()):
            for line in difference(recorded.get(section) or {}, snapshot[section] or {}, section):
                findings.append(("WARNING", line))
    report.group("the installed game against the recorded snapshot", findings)
    return report


def difference(old, new, path, limit=40):
    """Readable differences between two nested structures."""
    lines = []

    def walk(a, b, where):
        if len(lines) >= limit:
            return
        if isinstance(a, dict) and isinstance(b, dict):
            for key in sorted(set(a) | set(b), key=str):
                if key not in a:
                    lines.append("%s.%s is new: %s" % (where, key, brief(b[key])))
                elif key not in b:
                    lines.append("%s.%s is gone (was %s)" % (where, key, brief(a[key])))
                else:
                    walk(a[key], b[key], "%s.%s" % (where, key))
        elif normal(a) != normal(b):
            lines.append("%s changed: %s -> %s" % (where, brief(a), brief(b)))

    walk(old, new, path)
    return lines


def normal(value):
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, dict) and not value:
        return []
    if isinstance(value, list):
        return [normal(item) for item in value]
    return value


def brief(value):
    text = str(value)
    return text if len(text) <= 90 else text[:87] + "..."


def main():
    parser = argparse.ArgumentParser(description="Check the installed Project Zomboid against what Ammo Making relies on.")
    parser.add_argument("--install", default=os.environ.get("PZ_INSTALL"), help="the Project Zomboid install directory (or set PZ_INSTALL)")
    parser.add_argument("--javap", default=None, help="path to javap (default: JAVA_HOME, then PATH)")
    parser.add_argument("--update", action="store_true", help="rewrite the recorded snapshots from this install")
    arguments = parser.parse_args()
    if not arguments.install:
        parser.error("give --install <dir> or set PZ_INSTALL")

    install = Install(arguments.install)
    javap = find_javap(arguments.javap)
    jar = Jar(install, javap) if javap and os.path.isfile(install.root + "/projectzomboid.jar") else None

    facts = mod_facts()
    calls = mod_calls(mod_sources())
    snapshot = build_snapshot(install, jar, facts, calls)

    if arguments.update:
        if jar is None:
            raise SystemExit("--update needs javap: the snapshot records Java signatures")
        write_snapshot(snapshot)
        text = vanilla_snapshot_text(install, snapshot["version"])
        with io.open(VANILLA_SNAPSHOT, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("Wrote tests/engine_snapshot.lua and tests/vanilla_snapshot.lua for game version %s" % snapshot["version"])

    report = judge(snapshot, facts, calls, read_snapshot(), jar is not None)

    current = read(VANILLA_SNAPSHOT) if os.path.isfile(VANILLA_SNAPSHOT) else ""
    fresh = vanilla_snapshot_text(install, (snapshot["version"] if jar else None) or re.search(r'version = "([^"]*)"', current or 'version = ""').group(1))
    if fresh.replace("\r", "") != current:
        report.add("WARNING", "tests/vanilla_snapshot.lua (loot lists, ammo boxes) differs from this install; --update, then run the suite")
    else:
        report.add("PASS", "loot lists and ammo box recipes equal the recorded snapshot")

    print("Project Zomboid %s at %s" % (snapshot["version"] or "(version unknown)", install.root))
    report.print()
    return report.worst


if __name__ == "__main__":
    sys.exit(main())
