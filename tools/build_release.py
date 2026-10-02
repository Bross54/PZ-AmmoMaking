"""Ammo Making - build a clean release of the mod folder.

    python tools/build_release.py
    python tools/build_release.py --install "<Project Zomboid install>"
    python tools/build_release.py --check          gates only, writes nothing
    python tools/build_release.py --mutants        also run the mutation suite

What it does, in order, stopping at the first failure:

  1. reads the version from mod/AmmoMaking/42/mod.info (modversion=), the
     one place the version is written
  2. refuses a working tree with uncommitted changes (--allow-dirty to
     override: the package is then built from HEAD anyway and says so)
  3. validates the package: mod.info, file types, no test, doc, backup or
     temporary file, no local path, valid JSON, a changelog entry
  4. runs the gates: Lua 5.1 syntax of every file, the offline suite, the
     generated files against the model, the drift tool's self-test, that
     every mutant still applies, and (with --install) the installed game
     against what the mod relies on
  5. writes release/AmmoMaking/ and release/AmmoMaking-<version>.zip from
     the files git tracks under mod/AmmoMaking, as committed in HEAD

The archive is deterministic: the same commit gives the same bytes (sorted
entries, fixed timestamps, LF line endings as stored in git). Nothing
outside mod/AmmoMaking is shipped: no tests, tools or documents.

It does not publish anything. The Steam Workshop wants the folder inside
Contents/mods/ of a workshop item, with a preview.png and workshop.txt next
to it; see docs/WORKSHOP_DESCRIPTION.md.
"""

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
MOD = "mod/AmmoMaking"
MOD_INFO = MOD + "/42/mod.info"

# What a release may contain.
ALLOWED_EXTENSIONS = {".lua", ".txt", ".json", ".info", ".png", ".tiles", ".pack"}
FORBIDDEN_NAMES = re.compile(r"(?i)(\.bak$|\.orig$|\.rej$|\.tmp$|\.swp$|~$|^thumbs\.db$|^\.ds_store$|^desktop\.ini$|\.log$|\.md$|\.py$)")
# A drive letter path, a home directory, or this machine's library folders.
LOCAL_PATH = re.compile(r"(?i)([a-z]:[\\/](users|steamlibrary|program files|project zomboid)|/home/\w+|/users/\w+|steamapps)")
REQUIRED_KEYS = ("name", "id", "modversion", "versionMin", "description")
VERSION = re.compile(r"^\d+\.\d+\.\d+$")


class Failure(Exception):
    pass


def run(command, **options):
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, errors="replace", **options)


def git(*arguments):
    result = run(["git"] + list(arguments))
    if result.returncode != 0:
        raise Failure("git %s failed: %s" % (" ".join(arguments), result.stderr.strip()))
    return result.stdout


def git_bytes(path):
    result = subprocess.run(["git", "show", "HEAD:" + path], cwd=ROOT, capture_output=True)
    if result.returncode != 0:
        raise Failure("cannot read %s from HEAD" % path)
    return result.stdout


def read_mod_info(text):
    info = {}
    for line in text.replace("\r", "").split("\n"):
        if "=" in line:
            key, value = line.split("=", 1)
            info[key.strip()] = value.strip()
    return info


def validate_package(files):
    """files: path under mod/AmmoMaking -> bytes. Returns a list of problems."""
    problems = []
    if "42/mod.info" not in files:
        return ["42/mod.info is missing"]
    info = read_mod_info(files["42/mod.info"].decode("utf-8", "replace"))
    for key in REQUIRED_KEYS:
        if not info.get(key):
            problems.append("mod.info has no %s=" % key)
    if info.get("id") and info["id"] != os.path.basename(MOD):
        problems.append("mod.info id=%s is not the folder name %s" % (info["id"], os.path.basename(MOD)))
    if info.get("modversion") and not VERSION.match(info["modversion"]):
        problems.append("modversion=%s is not MAJOR.MINOR.PATCH" % info["modversion"])
    if info.get("versionMin") and not re.match(r"^\d+\.\d+", info["versionMin"]):
        problems.append("versionMin=%s is not a game version" % info["versionMin"])
    for key in ("poster", "icon"):
        if info.get(key) and ("42/" + info[key]) not in files and info[key] not in files:
            problems.append("mod.info %s=%s names a file that is not in the package" % (key, info[key]))
    for key in ("pack", "tiledef"):
        if info.get(key):
            name = info[key].split()[0]
            if not any(path.endswith("/" + name + extension) or path.endswith("/" + name) for path in files for extension in (".pack", ".tiles")):
                problems.append("mod.info %s=%s names a file that is not in the package" % (key, info[key]))

    for path, data in sorted(files.items()):
        name = os.path.basename(path)
        extension = os.path.splitext(name)[1].lower()
        if FORBIDDEN_NAMES.search(name):
            problems.append("%s must not be shipped" % path)
        elif extension not in ALLOWED_EXTENSIONS:
            problems.append("%s has an extension a release does not contain" % path)
        if re.search(r"(?i)(^|/)(tests?|docs?|tools)(/|$)", path):
            problems.append("%s is in a folder a release does not contain" % path)
        if extension in (".lua", ".txt", ".json", ".info"):
            text = data.decode("utf-8", "replace")
            found = LOCAL_PATH.search(text)
            if found:
                problems.append("%s contains a local path (%s)" % (path, found.group(0)))
            if b"\r" in data:
                problems.append("%s is stored with CR line endings" % path)
            if data.startswith(b"\xef\xbb\xbf"):
                problems.append("%s starts with a byte order mark" % path)
        if extension == ".json":
            try:
                json.loads(data.decode("utf-8"))
            except ValueError as error:
                problems.append("%s is not valid JSON: %s" % (path, error))
        if len(data) == 0:
            problems.append("%s is empty" % path)

    lua_files = [path for path in files if path.endswith(".lua")]
    if not any(path.startswith("42/media/lua/") for path in lua_files):
        problems.append("no Lua under 42/media/lua")
    if not any(path.startswith("42/media/scripts/") for path in files):
        problems.append("no scripts under 42/media/scripts")
    return problems


def changelog_has(version):
    path = ROOT + "/CHANGELOG.md"
    if not os.path.isfile(path):
        return False
    with io.open(path, encoding="utf-8") as handle:
        return re.search(r"(?m)^## %s\b" % re.escape(version), handle.read()) is not None


def lua_runtime():
    from lupa.lua51 import LuaRuntime
    return LuaRuntime(unpack_returned_tuples=True)


def gate_syntax():
    lua = lua_runtime()
    check = lua.eval("function(path) local chunk, problem = loadfile(path) if chunk then return nil end return problem end")
    bad = []
    count = 0
    for folder in ("mod", "tests", "tools"):
        for directory, _, names in os.walk(os.path.join(ROOT, folder)):
            for name in sorted(names):
                if name.endswith(".lua"):
                    count += 1
                    problem = check(os.path.join(directory, name).replace("\\", "/"))
                    if problem:
                        bad.append(problem)
    if bad:
        raise Failure("Lua syntax: " + "; ".join(bad))
    return "%d Lua files load as Lua 5.1" % count


def gate_suite():
    lua = lua_runtime()
    lua.execute('arg = { [0] = "%s/tests/run_tests.lua" }' % ROOT)
    lua.execute('''
        __summary, __failures = nil, {}
        print = function(...)
            local first = tostring((select(1, ...)))
            if string.find(first, "^Passed: ") then __summary = first end
            if string.find(first, "FAIL", 1, true) and #__failures < 5 then __failures[#__failures + 1] = first end
        end
        os.exit = function() error("__exit__", 0) end
    ''')
    error = None
    try:
        lua.execute("dofile(arg[0])")
    except Exception as raised:
        if "__exit__" not in str(raised):
            error = str(raised).splitlines()[0]
    summary = lua.globals()["__summary"]
    failures = list(lua.globals()["__failures"].values())
    if error or not summary or not summary.endswith("Failed: 0"):
        raise Failure("the offline suite does not pass: %s %s %s" % (summary, error or "", " | ".join(failures)))
    return "offline suite: " + " ".join(summary.split())


def gate_generated():
    """The generated script and tables equal what the model renders now."""
    lua = lua_runtime()
    lua.execute('arg = { [0] = "%s/tests/write_recipes.lua" }' % ROOT)
    lua.execute("print = function() end")
    lua.execute("dofile(arg[0])")
    # By content, not by status: the generator writes the platform's line
    # endings, and a file rewritten with other line endings and the same
    # text is not a change.
    run(["git", "update-index", "-q", "--refresh"])
    changed = git("diff", "--name-only").strip()
    if changed:
        raise Failure("tests/write_recipes.lua changed files: the generated script or tables were out of step with the model. Review and commit them.\n" + changed)
    return "generated recipe script and tables are in step with the model"


def gate_python(script, label, *arguments):
    result = run([sys.executable, script] + list(arguments), env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    last = (result.stdout.strip().splitlines() or [""])[-1]
    return result.returncode, last, result.stdout


def main():
    parser = argparse.ArgumentParser(description="Build a clean release of the Ammo Making mod folder.")
    parser.add_argument("--out", default="release", help="output directory, relative to the repository (default: release)")
    parser.add_argument("--install", default=os.environ.get("PZ_INSTALL"), help="also check this Project Zomboid install with tools/pz_compat.py")
    parser.add_argument("--check", action="store_true", help="run the gates and write nothing")
    parser.add_argument("--mutants", action="store_true", help="also run the whole mutation suite (several minutes)")
    parser.add_argument("--allow-dirty", action="store_true", help="build although the working tree has uncommitted changes")
    arguments = parser.parse_args()

    try:
        tracked = [path for path in git("ls-files", MOD).split("\n") if path]
        files = {path[len(MOD) + 1:]: git_bytes(path) for path in tracked}
        info = read_mod_info(files.get("42/mod.info", b"").decode("utf-8", "replace"))
        version = info.get("modversion", "")
        commit = git("rev-parse", "--short", "HEAD").strip()
        print("Ammo Making %s (commit %s), for Project Zomboid %s and later" % (version or "?", commit, info.get("versionMin", "?")))

        dirty = git("status", "--porcelain").strip()
        if dirty and not arguments.allow_dirty:
            raise Failure("the working tree has uncommitted changes; commit them or pass --allow-dirty:\n" + dirty)
        if dirty:
            print("WARNING  uncommitted changes are NOT in the package: it is built from HEAD")

        untracked = [line[3:] for line in git("status", "--porcelain", "--ignored", MOD).split("\n") if line[:2] in ("??", "!!")]
        if untracked:
            print("NOTE     not tracked by git, not shipped: " + ", ".join(untracked))

        problems = validate_package(files)
        if not changelog_has(version):
            problems.append("CHANGELOG.md has no '## %s' entry" % version)
        if problems:
            raise Failure("the package is not valid:\n  " + "\n  ".join(problems))
        print("PASS     package: %d files, mod.info complete, no stray files, no local paths" % len(files))

        print("PASS     " + gate_syntax())
        print("PASS     " + gate_suite())
        if dirty:
            print("SKIPPED  generated files (the working tree is dirty)")
        else:
            print("PASS     " + gate_generated())

        code, last, _ = gate_python("tools/test_pz_compat.py", "drift tool self-test")
        if code != 0:
            raise Failure("tools/test_pz_compat.py fails: " + last)
        print("PASS     drift tool self-test: " + last)

        code, last, _ = gate_python("tools/build_tiles.py", "tile builder", "--selftest")
        if code != 0:
            raise Failure("tools/build_tiles.py --selftest fails: " + last)
        print("PASS     " + last)

        code, last, output = gate_python("tests/run_mutants.py", "mutants", *([] if arguments.mutants else ["check"]))
        if code != 0:
            raise Failure("tests/run_mutants.py: " + last + "\n" + output[-800:])
        print("PASS     mutation suite: " + last)

        if arguments.install:
            code, last, output = gate_python("tools/pz_compat.py", "installed game", "--install", arguments.install)
            if code >= 2:
                raise Failure("the installed game no longer matches the mod:\n" + "\n".join(line for line in output.splitlines() if line.startswith("BREAKING")))
            print("%s installed game: %s" % ("PASS    " if code == 0 else "WARNING ", last))
        else:
            print("SKIPPED  installed game (no --install and no PZ_INSTALL)")

        if arguments.check:
            print("All gates passed. Nothing written (--check).")
            return 0

        out = os.path.join(ROOT, arguments.out)
        target = os.path.join(out, "AmmoMaking")
        if os.path.isdir(target):
            shutil.rmtree(target)
        archive = os.path.join(out, "AmmoMaking-%s.zip" % version)
        os.makedirs(out, exist_ok=True)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
            for path in sorted(files):
                destination = os.path.join(target, path)
                os.makedirs(os.path.dirname(destination), exist_ok=True)
                with open(destination, "wb") as handle:
                    handle.write(files[path])
                entry = zipfile.ZipInfo("AmmoMaking/" + path, date_time=(2020, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                bundle.writestr(entry, files[path], compresslevel=9)
        with open(archive, "rb") as handle:
            checksum = hashlib.sha256(handle.read()).hexdigest()

        print("")
        print("Included files:")
        for path in sorted(files):
            print("  %7d  %s" % (len(files[path]), path))
        print("")
        print("Wrote %s" % os.path.relpath(target, ROOT).replace("\\", "/"))
        print("Wrote %s  (%d bytes, sha256 %s)" % (os.path.relpath(archive, ROOT).replace("\\", "/"), os.path.getsize(archive), checksum))
        return 0
    except Failure as failure:
        print("FAILED   " + str(failure))
        return 1


if __name__ == "__main__":
    sys.exit(main())
