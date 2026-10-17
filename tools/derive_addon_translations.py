"""Ammo Making - derives the non-English names of the generated add-ons.

    python tools/derive_addon_translations.py            write them
    python tools/derive_addon_translations.py --check    fail when a written file differs

The calibre add-ons (one per gun mod) and the Hot Brass bridge name their
items and recipes after the main mod's, in English by tests/write_recipes.lua.
Every other language is derived here from that language's own names of the
same things, so nothing is machine-translated twice:

  a calibre add-on   each name is the language's name of the same item or
                     recipe of the calibre's template (.308, .357 Magnum or
                     12 Gauge), with the template's calibre written as that
                     language writes it (the longest text every one of
                     those names shares from the calibre's first character)
                     replaced by the add-on calibre's id
  Hot Brass          the language's name of the spent cases' resizing
                     recipe of the calibre, with " (Hot Brass)" added

A name that cannot be derived keeps the English one, and is listed.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "mod")
MAIN = os.path.join(MOD, "AmmoMaking", "common", "media", "lua", "shared", "Translate")
SPENT = os.path.join(MOD, "AmmoMakingSpentCases", "common", "media", "lua", "shared", "Translate")

# template calibre id -> its suffix in the main mod's ids
TEMPLATES = {".308": "308Win", ".357 Magnum": "357Magnum", "12 Gauge": "12Gauge"}
# Item ids of a template whose parts are not named Case/Bullet/CastBullet.
ROLE_NAMES = {"12 Gauge": {
    "AmmoMaking.Case12Gauge": "AmmoMaking.Hull12Gauge",
    "AmmoMaking.Bullet12Gauge": "AmmoMaking.ShotCharge12Gauge",
    "AmmoMaking.CastBullet12Gauge": "AmmoMaking.LeadShotCharge12Gauge",
}}
# The anchor a template's calibre starts with in every language.
ANCHORS = {".308": ".308", ".357 Magnum": ".357", "12 Gauge": "12"}

CALIBRE_ADDONS = ["AmmoMakingCalibre762x39", "AmmoMakingVFE", "AmmoMakingRains", "AmmoMakingRainsExpanded",
                  "AmmoMakingGaelGunStore", "AmmoMakingRealFirearms", "AmmoMakingMFS"]


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def languages():
    return sorted(name for name in os.listdir(MAIN) if name != "EN" and os.path.isdir(os.path.join(MAIN, name)))


def calibre_of(key, suffixes):
    """The add-on calibre suffix a key ends in (the longest that matches)."""
    best = None
    for suffix in suffixes:
        if suffix in key and (best is None or len(suffix) > len(best)):
            best = suffix
    return best


def template_token(values, anchor):
    """The longest text all values share from the anchor's first occurrence."""
    tails = []
    for value in values:
        index = value.find(anchor)
        if index < 0:
            return None
        tails.append(value[index:])
    token = os.path.commonprefix(tails)
    return token.rstrip() if token.strip() else None


def addon_calibres(addon):
    """suffix -> (calibre id, template id), read from the add-on's English names and AC_Calibres."""
    source = open(os.path.join(MOD, "AmmoMaking", "42", "media", "lua", "shared", "AC_Calibres.lua"), encoding="utf-8").read()
    found = {}
    for block in re.findall(r"AC_Calibres\.define\(\{(.*?)\}\),", source, re.S):
        fields = dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', block))
        if "extension" in block and "template" in fields:
            found[fields["suffix"]] = (fields["id"], fields["template"])
    return found


def derive(check):
    problems, written, unchanged = [], 0, 0
    calibres = addon_calibres(None)
    for lang in languages():
        main_items = load(os.path.join(MAIN, lang, "ItemName.json"))
        main_recipes = load(os.path.join(MAIN, lang, "Recipes.json"))
        tokens = {}
        for template, suffix in TEMPLATES.items():
            values = [v for k, v in main_items.items() if k.endswith(suffix)]
            values += [v for k, v in main_recipes.items() if suffix in k and not k.startswith("AmmoMaking_Regrind") and not k.startswith("AmmoMaking_Anneal")]
            tokens[template] = template_token(values, ANCHORS[template])
        outputs = []
        for addon in CALIBRE_ADDONS:
            base = os.path.join(MOD, addon, "common", "media", "lua", "shared", "Translate")
            for name, source in (("ItemName.json", main_items), ("Recipes.json", main_recipes)):
                english = load(os.path.join(base, "EN", name))
                result = {}
                for key, value in english.items():
                    suffix = calibre_of(key, calibres.keys())
                    calibre, template = calibres[suffix]
                    template_key = key.replace(suffix, TEMPLATES[template])
                    # The vanilla shell's parts are a hull and shot charges.
                    for mine, theirs in ROLE_NAMES.get(template, {}).items():
                        if template_key == mine:
                            template_key = theirs
                    their = source.get(template_key)
                    token = tokens[template]
                    if their and token and token in their:
                        result[key] = their.replace(token, calibre)
                    else:
                        result[key] = value
                        problems.append("%s %s %s" % (lang, addon, key))
                outputs.append((os.path.join(base, lang, name), result))
        # Hot Brass
        spent = load(os.path.join(SPENT, lang, "Recipes.json"))
        base = os.path.join(MOD, "AmmoMakingHotBrass", "common", "media", "lua", "shared", "Translate")
        english = load(os.path.join(base, "EN", "Recipes.json"))
        result = {}
        for key, value in english.items():
            their = spent.get(key.replace("ResizeHotBrassCase", "ResizeSpentCase"))
            if their:
                result[key] = their + " (Hot Brass)"
            else:
                result[key] = value
                problems.append("%s AmmoMakingHotBrass %s" % (lang, key))
        outputs.append((os.path.join(base, lang, "Recipes.json"), result))
        for path, data in outputs:
            text = json.dumps(data, ensure_ascii=False, indent=4) + "\n"
            old = open(path, encoding="utf-8").read() if os.path.isfile(path) else None
            if old == text:
                unchanged += 1
                continue
            if check:
                problems.append("differs: " + os.path.relpath(path, REPO))
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text)
            written += 1
    return problems, written, unchanged


def main(argv):
    check = "--check" in argv
    problems, written, unchanged = derive(check)
    for problem in problems[:40]:
        print("  " + problem)
    if problems:
        print("%d names kept in English or differing" % len(problems))
    print("add-on translations: %d written, %d unchanged" % (written, unchanged))
    return 1 if (check and problems) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
