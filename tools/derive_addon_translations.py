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
  MFS casings        likewise, with " (MFS)", in the MFS calibre add-on
  press recipes      the hand recipe's name with the language's own
                     " (Press)" (read off a pair the press add-on names);
                     in the press add-on only where it names none yet

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
    "AmmoMaking.SpentCase12Gauge": "AmmoMaking.SpentHull12Gauge",
}}
# The anchor a template's calibre starts with in every language.
ANCHORS = {".308": ".308", ".357 Magnum": ".357", "12 Gauge": "12"}

# Resizings of another mod's casings that a calibre add-on carries
# (AC_SpentCases.CASING_BRIDGES): id prefix -> name suffix.
CASING_BRIDGES = [("AmmoMaking_ResizeMFSCase", " (MFS)")]

# The case tumbler of the spent cases add-on (AC_SpentCases.TUMBLER): its
# name, its build recipe's name, and the phrase that turns the language's
# steel-wool cleaning of a calibre into its tumbling (the calibre stays as
# that language writes it).
TUMBLER = {
    "AR": ("Pulidor de tambor", "Fabricar pulidor de tambor", "con lana de acero", "en un pulidor de tambor"),
    "CA": ("Polidor de tambor", "Fer un polidor de tambor", "amb llana d'acer", "en un polidor de tambor"),
    "CH": ("滾筒拋光機", "製作滾筒拋光機", "用鋼絲球清潔", "用滾筒拋光機清潔"),
    "CN": ("滚筒抛光机", "制作滚筒抛光机", "用钢丝球清洁", "用滚筒抛光机清洁"),
    "CS": ("Bubnová leštička", "Vyrobit bubnovou leštičku", "ocelovou vlnou", "v bubnové leštičce"),
    "DA": ("Tromlepolerer", "Lav tromlepolerer", "med ståluld", "i en tromlepolerer"),
    "DE": ("Trommelpolierer", "Trommelpolierer bauen", "mit Stahlwolle", "im Trommelpolierer"),
    "ES": ("Pulidor de tambor", "Fabricar pulidor de tambor", "con lana de acero", "en un pulidor de tambor"),
    "ES_CL": ("Pulidor de tambor", "Fabricar pulidor de tambor", "con lana de acero", "en un pulidor de tambor"),
    "ES_MX": ("Pulidor de tambor", "Fabricar pulidor de tambor", "con lana de acero", "en un pulidor de tambor"),
    "FI": ("Rumpukiillotin", "Valmista rumpukiillotin", "teräsvillalla", "rumpukiillottimessa"),
    "FR": ("Tonneau de polissage", "Fabriquer un tonneau de polissage", "à la paille de fer", "au tonneau de polissage"),
    "HU": ("Dobpolírozó", "Dobpolírozó készítése", "acél súrolóval", "dobpolírozóban"),
    "ID": ("Mesin Tumbler", "Buat Mesin Tumbler", "dengan Sabut Baja", "dengan Mesin Tumbler"),
    "IT": ("Burattatrice", "Costruisci burattatrice", "con lana d'acciaio", "nella burattatrice"),
    "JP": ("薬莢タンブラー", "薬莢タンブラーを作る", "スチールウールで", "タンブラーで"),
    "KO": ("탄피 텀블러", "탄피 텀블러 만들기", "강철 솜으로", "텀블러로"),
    "NL": ("Trommelpolijster", "Trommelpolijster maken", "met staalwol", "in een trommelpolijster"),
    "NO": ("Trommelpolerer", "Lag trommelpolerer", "med stålull", "i en trommelpolerer"),
    "PL": ("Bęben polerski", "Zrób bęben polerski", "wełną stalową", "w bębnie polerskim"),
    "PT": ("Polidor de tambor", "Fazer polidor de tambor", "com Lã de Aço", "num Polidor de Tambor"),
    "PTBR": ("Polidor de tambor", "Fazer polidor de tambor", "com Palha de Aço", "no Polidor de Tambor"),
    "RO": ("Tambur de lustruit", "Fă un tambur de lustruit", "cu Lână de Oțel", "în Tamburul de Lustruit"),
    "RU": ("Галтовочный барабан", "Сделать галтовочный барабан", "стальной ватой", "в галтовочном барабане"),
    "TH": ("เครื่องขัดแบบถัง", "ทำเครื่องขัดแบบถัง", "ด้วยฝอยขัดหม้อ", "ด้วยเครื่องขัดแบบถัง"),
    "TR": ("Kovan Tamburu", "Kovan Tamburu Yap", "Çelik Yünle", "Tamburda"),
    "UA": ("Галтувальний барабан", "Зробити галтувальний барабан", "сталевою ватою", "у галтувальному барабані"),
}

# A hand recipe and its press version that every language's press add-on
# names: the difference is that language's " (Press)".
PRESS_PAIR = ("AmmoMaking_FormCase9mm",)

CALIBRE_ADDONS = ["AmmoMakingCalibre762x39", "AmmoMakingVFE", "AmmoMakingRains", "AmmoMakingRainsExpanded",
                  "AmmoMakingGaelGunStore", "AmmoMakingRealFirearms", "AmmoMakingMFS",
                  "AmmoMakingGuns93", "AmmoMakingPSA"]


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
        spent = load(os.path.join(SPENT, lang, "Recipes.json"))
        # The press add-on: its names were translated by hand; a press recipe
        # it does not name yet is its hand recipe's name with the language's
        # own word for the press (read off a pair it does name).
        press_base = os.path.join(MOD, "AmmoMakingPress", "common", "media", "lua", "shared", "Translate")
        press_lang = load(os.path.join(press_base, lang, "Recipes.json"))
        hand_pair = main_recipes.get(PRESS_PAIR[0], "")
        press_pair = press_lang.get(PRESS_PAIR[0] + "AtPress", "")
        press_suffix = press_pair[len(hand_pair):] if hand_pair and press_pair.startswith(hand_pair) else None
        press_word = re.match(r"^\s*\((.*)\)\s*$", press_suffix).group(1) if press_suffix and re.match(r"^\s*\((.*)\)\s*$", press_suffix) else None

        def press_name(hand):
            if not hand or not press_suffix:
                return None
            if hand.endswith(")") and press_word:
                return hand[:-1] + ", " + press_word + ")"
            return hand + press_suffix

        english = load(os.path.join(press_base, "EN", "Recipes.json"))
        result = {}
        for key, value in english.items():
            if key in press_lang:
                result[key] = press_lang[key]
                continue
            derived = press_name(main_recipes.get(key[:-len("AtPress")])) if key.endswith("AtPress") else None
            if derived:
                result[key] = derived
            else:
                result[key] = value
                problems.append("%s AmmoMakingPress %s" % (lang, key))
        outputs.append((os.path.join(press_base, lang, "Recipes.json"), result))
        # A calibre add-on carries its spent cases too: their names come from
        # the spent cases add-on's names of the template's.
        spent_items = load(os.path.join(SPENT, lang, "ItemName.json"))
        item_source = dict(main_items, **spent_items)
        recipe_source = dict(main_recipes, **spent)
        for addon in CALIBRE_ADDONS:
            base = os.path.join(MOD, addon, "common", "media", "lua", "shared", "Translate")
            for name, source in (("ItemName.json", item_source), ("Recipes.json", recipe_source)):
                english = load(os.path.join(base, "EN", name))
                result = {}
                for key, value in english.items():
                    # A pack's casing bridge (MFS): the spent cases' resizing
                    # of the vanilla calibre, with the bridge's suffix.
                    bridge = next((b for b in CASING_BRIDGES if key.startswith(b[0])), None)
                    if bridge:
                        their = spent.get(key.replace(bridge[0], "AmmoMaking_ResizeSpentCase"))
                        if their:
                            result[key] = their + bridge[1]
                        else:
                            result[key] = value
                            problems.append("%s %s %s" % (lang, addon, key))
                        continue
                    # A press recipe: named after its hand recipe, below.
                    if key.endswith("AtPress"):
                        result[key] = None
                        continue
                    suffix = calibre_of(key, calibres.keys())
                    # Scrapping its spent cases: the spent add-on's scrapping
                    # of the same size, with the calibre in brackets.
                    scrap = re.match(r"^(AmmoMaking_ScrapSpentBrass)" + re.escape(suffix) + r"_(\d+)$", key)
                    if scrap:
                        # The largest size the spent add-on names, not above
                        # this one (AC_Recycling.getSpentSizeName).
                        sizes = sorted((int(m.group(1)) for m in (re.match(r"^AmmoMaking_ScrapSpentBrass(\d+)$", k) for k in spent) if m), reverse=True)
                        size = next((s for s in sizes if s <= int(scrap.group(2))), None)
                        their = spent.get(scrap.group(1) + str(size)) if size else None
                        if their:
                            result[key] = "%s - %s" % (their, calibres[suffix][0])
                        else:
                            result[key] = value
                            problems.append("%s %s %s" % (lang, addon, key))
                        continue
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
                for key in [k for k, v in result.items() if v is None]:
                    derived = press_name(result.get(key[:-len("AtPress")]))
                    if derived:
                        result[key] = derived
                    else:
                        result[key] = english[key]
                        problems.append("%s %s %s" % (lang, addon, key))
                outputs.append((os.path.join(base, lang, name), result))
        # The spent cases add-on: its names were translated by hand; the case
        # tumbler's are filled in where they are missing.
        item_name, make_name, steel, drum = TUMBLER[lang]
        for name, current in (("ItemName.json", spent_items), ("Recipes.json", spent)):
            english = load(os.path.join(SPENT, "EN", name))
            result = {}
            for key, value in english.items():
                if key in current:
                    result[key] = current[key]
                elif key == "AmmoMaking.CaseTumbler":
                    result[key] = item_name
                elif key == "AmmoMaking_MakeCaseTumbler":
                    result[key] = make_name
                elif key.startswith("AmmoMaking_TumbleSpentCases") and steel in current.get(key.replace("TumbleSpentCases", "CleanSpentCases"), ""):
                    result[key] = current[key.replace("TumbleSpentCases", "CleanSpentCases")].replace(steel, drum)
                else:
                    result[key] = value
                    problems.append("%s AmmoMakingSpentCases %s" % (lang, key))
            outputs.append((os.path.join(SPENT, lang, name), result))
        # Hot Brass
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
