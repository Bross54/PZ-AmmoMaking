"""Ammo Making - build a tile sheet (tile definitions and texture pack) from PNGs.

    python tools/build_tiles.py art/reloading_press/tiles.json
    python tools/build_tiles.py --selftest
    python tools/build_tiles.py --verify --install "<Project Zomboid install>"

The game reads a mod's tiles from two binary files named in mod.info:

    tiledef=<name> <number>   media/<name>.tiles
    pack=<name>               media/texturepacks/<name>.pack

This writes both from a small JSON description and one PNG per sprite, into
the description's own build/ folder. NOTHING is written into the mod: the
reloading press is switched off (docs/RELOADING_PRESS_DESIGN.md), and
putting a tile sheet into mod.info is a step for a session with the game.

The two formats, as read from the installed 42.20.4 files and checked by
--verify, which parses vanilla's own files and writes them back byte for
byte:

  .tiles   "tdef", int version (1), int tilesets; per tileset: name + LF,
           image file name + LF, int columns, int rows, int id, int tiles
           (columns * rows); per tile: int properties, then key + LF and
           value + LF for each
  .pack    "PZPK", int version (1), int pages; per page: int length + name,
           int entries, int flag (1 for every vanilla tile page); per entry:
           int length + name, int x, y, w, h (the rectangle in the page
           image), int offsetX, offsetY (where that rectangle sits in the
           full frame), int fullWidth, fullHeight; then int length + the
           page's PNG

All integers are little-endian and 32 bits. A 2x tile's full frame is 128 x
256; the rectangle is the frame trimmed to its opaque pixels.

--selftest needs Pillow and no game. It builds a sheet from generated
sprites, reads both files back and compares every name, property, rectangle
and pixel. It proves the files are well formed and say what the description
says. That the game draws them is REQUIRES FUTURE IN-GAME VERIFICATION.
"""

import argparse
import io
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
FRAME = (128, 256)


# ----------------------------------------------------------------------
# .tiles
# ----------------------------------------------------------------------

def read_tiles(data):
    """bytes -> { version, tilesets: [ { name, image, columns, rows, id, tiles: [ [ (key, value) ] ] } ] }"""
    if data[:4] != b"tdef":
        raise ValueError("not a tile definition file (no tdef magic)")
    version, count = struct.unpack_from("<ii", data, 4)
    position = 12

    def line():
        nonlocal position
        end = data.index(b"\n", position)
        text = data[position:end]
        position = end + 1
        return text

    tilesets = []
    for _ in range(count):
        name, image = line(), line()
        columns, rows, number, tiles = struct.unpack_from("<iiii", data, position)
        position += 16
        entries = []
        for _ in range(tiles):
            properties = struct.unpack_from("<i", data, position)[0]
            position += 4
            entries.append([(line(), line()) for _ in range(properties)])
        tilesets.append({"name": name, "image": image, "columns": columns, "rows": rows, "id": number, "tiles": entries})
    if position != len(data):
        raise ValueError("%d bytes after the last tileset" % (len(data) - position))
    return {"version": version, "tilesets": tilesets}


def write_tiles(definition):
    out = [b"tdef", struct.pack("<ii", definition["version"], len(definition["tilesets"]))]
    for tileset in definition["tilesets"]:
        out.append(tileset["name"] + b"\n" + tileset["image"] + b"\n")
        out.append(struct.pack("<iiii", tileset["columns"], tileset["rows"], tileset["id"], len(tileset["tiles"])))
        for properties in tileset["tiles"]:
            out.append(struct.pack("<i", len(properties)))
            for key, value in properties:
                out.append(key + b"\n" + value + b"\n")
    return b"".join(out)


# ----------------------------------------------------------------------
# .pack
# ----------------------------------------------------------------------

def read_pack(data):
    """bytes -> { version, pages: [ { name, flag, entries: [ (name, x, y, w, h, ox, oy, fw, fh) ], png } ] }"""
    if data[:4] != b"PZPK":
        raise ValueError("not a version 1 texture pack (no PZPK magic)")
    version, count = struct.unpack_from("<ii", data, 4)
    position = 12
    pages = []
    for _ in range(count):
        length = struct.unpack_from("<i", data, position)[0]
        position += 4
        name = data[position:position + length]
        position += length
        entries_count, flag = struct.unpack_from("<ii", data, position)
        position += 8
        entries = []
        for _ in range(entries_count):
            length = struct.unpack_from("<i", data, position)[0]
            position += 4
            entry_name = data[position:position + length]
            position += length
            entries.append((entry_name,) + struct.unpack_from("<8i", data, position))
            position += 32
        size = struct.unpack_from("<i", data, position)[0]
        position += 4
        png = data[position:position + size]
        position += size
        pages.append({"name": name, "flag": flag, "entries": entries, "png": png})
    if position != len(data):
        raise ValueError("%d bytes after the last page" % (len(data) - position))
    return {"version": version, "pages": pages}


def write_pack(pack):
    out = [b"PZPK", struct.pack("<ii", pack["version"], len(pack["pages"]))]
    for page in pack["pages"]:
        out.append(struct.pack("<i", len(page["name"])) + page["name"])
        out.append(struct.pack("<ii", len(page["entries"]), page["flag"]))
        for entry in page["entries"]:
            out.append(struct.pack("<i", len(entry[0])) + entry[0] + struct.pack("<8i", *entry[1:]))
        out.append(struct.pack("<i", len(page["png"])) + page["png"])
    return b"".join(out)


# ----------------------------------------------------------------------
# Building a sheet from a description
# ----------------------------------------------------------------------

def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def validate(description):
    """Problems of a sheet description, as a list of texts."""
    problems = []
    for key in ("pack", "tiledef", "fileNumber", "tilesets"):
        if key not in description:
            problems.append("no %s" % key)
    if problems:
        return problems
    if not (100 <= description["fileNumber"] <= 8189):
        problems.append("fileNumber must be from 100 to 8189 (ChooseGameInfo, 42.20.4)")
    names, ids = set(), set()
    for tileset in description["tilesets"]:
        name = tileset.get("name", "")
        if not name or not all(char.isalnum() or char == "_" for char in name) or name != name.lower():
            problems.append("tileset name %r must be lower-case letters, digits and underscores" % name)
        if name in names:
            problems.append("tileset %s is listed twice" % name)
        names.add(name)
        if tileset.get("id") in ids or not isinstance(tileset.get("id"), int) or tileset["id"] < 1:
            problems.append("tileset %s needs an id of 1 or more that no other tileset has" % name)
        ids.add(tileset.get("id"))
        if tileset.get("columns") != 8:
            problems.append("tileset %s must have 8 columns, as every vanilla sheet has" % name)
        if not isinstance(tileset.get("rows"), int) or tileset["rows"] < 1:
            problems.append("tileset %s needs at least one row" % name)
            continue
        seen = set()
        for tile in tileset.get("tiles", []):
            index = tile.get("index")
            if not isinstance(index, int) or not (0 <= index < tileset["columns"] * tileset["rows"]):
                problems.append("tileset %s: tile index %r is outside the sheet" % (name, index))
            if index in seen:
                problems.append("tileset %s: tile %r is listed twice" % (name, index))
            seen.add(index)
            if not tile.get("image"):
                problems.append("tileset %s: tile %r has no image" % (name, index))
            for key, value in (tile.get("properties") or {}).items():
                if "\n" in key or "\n" in str(value):
                    problems.append("tileset %s: tile %r has a line break in property %r" % (name, index, key))
    return problems


def build(description, folder):
    """(tiles bytes, pack bytes, report lines) for a description whose images are under folder."""
    from PIL import Image

    problems = validate(description)
    if problems:
        raise ValueError("; ".join(problems))

    sprites = []  # (sprite name, trimmed image, offset)
    tilesets = []
    for tileset in description["tilesets"]:
        count = tileset["columns"] * tileset["rows"]
        tiles = [[] for _ in range(count)]
        for tile in tileset["tiles"]:
            properties = tile.get("properties") or {}
            tiles[tile["index"]] = [(key.encode("ascii"), str(value).encode("ascii")) for key, value in sorted(properties.items())]
            image = Image.open(os.path.join(folder, tile["image"])).convert("RGBA")
            if image.size != FRAME:
                raise ValueError("%s is %dx%d; a 2x tile frame is %dx%d" % (tile["image"], image.size[0], image.size[1], FRAME[0], FRAME[1]))
            box = image.getchannel("A").getbbox()
            if box is None:
                raise ValueError("%s is fully transparent" % tile["image"])
            sprites.append(("%s_%d" % (tileset["name"], tile["index"]), image.crop(box), (box[0], box[1])))
        tilesets.append({
            "name": tileset["name"].encode("ascii"),
            "image": (tileset["name"] + ".png").encode("ascii"),
            "columns": tileset["columns"],
            "rows": tileset["rows"],
            "id": tileset["id"],
            "tiles": tiles,
        })

    # One page: the trimmed sprites side by side, a pixel apart.
    width = sum(sprite[1].size[0] for sprite in sprites) + len(sprites) + 1
    height = max(sprite[1].size[1] for sprite in sprites) + 2
    page = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    entries = []
    x = 1
    report = []
    for name, image, offset in sprites:
        page.paste(image, (x, 1))
        entries.append((name.encode("ascii"), x, 1, image.size[0], image.size[1], offset[0], offset[1], FRAME[0], FRAME[1]))
        report.append("%s: %dx%d at offset (%d, %d) of a %dx%d frame" % (name, image.size[0], image.size[1], offset[0], offset[1], FRAME[0], FRAME[1]))
        x += image.size[0] + 1

    tiles_bytes = write_tiles({"version": 1, "tilesets": tilesets})
    pack_bytes = write_pack({"version": 1, "pages": [{
        "name": (description["pack"] + "0").encode("ascii"),
        "flag": 1,
        "entries": entries,
        "png": png_bytes(page),
    }]})
    return tiles_bytes, pack_bytes, report


def check_build(description, folder, tiles_bytes, pack_bytes):
    """Reads the built files back and compares them with the description. Returns problems."""
    from PIL import Image

    problems = []
    definition = read_tiles(tiles_bytes)
    pack = read_pack(pack_bytes)
    if write_tiles(definition) != tiles_bytes:
        problems.append("the tile definitions do not survive a read and a write")
    if write_pack(pack) != pack_bytes:
        problems.append("the pack does not survive a read and a write")
    if len(definition["tilesets"]) != len(description["tilesets"]):
        problems.append("tileset count")
    entries = {}
    for page in pack["pages"]:
        image = Image.open(io.BytesIO(page["png"])).convert("RGBA")
        for entry in page["entries"]:
            entries[entry[0].decode("ascii")] = (image, entry)
    for wanted, built in zip(description["tilesets"], definition["tilesets"]):
        if built["name"].decode("ascii") != wanted["name"] or built["columns"] != wanted["columns"] or built["rows"] != wanted["rows"] or built["id"] != wanted["id"]:
            problems.append("tileset %s header" % wanted["name"])
        if len(built["tiles"]) != wanted["columns"] * wanted["rows"]:
            problems.append("tileset %s tile count" % wanted["name"])
        listed = {tile["index"]: tile for tile in wanted["tiles"]}
        for index, properties in enumerate(built["tiles"]):
            expected = sorted((key, str(value)) for key, value in (listed.get(index, {}).get("properties") or {}).items())
            if [(key.decode("ascii"), value.decode("ascii")) for key, value in properties] != expected:
                problems.append("tileset %s tile %d properties" % (wanted["name"], index))
        for index, tile in listed.items():
            name = "%s_%d" % (wanted["name"], index)
            if name not in entries:
                problems.append("sprite %s is not in the pack" % name)
                continue
            page, entry = entries[name]
            _, x, y, w, h, ox, oy, fw, fh = entry
            if (fw, fh) != FRAME:
                problems.append("sprite %s frame size" % name)
            source = Image.open(os.path.join(folder, tile["image"])).convert("RGBA")
            rebuilt = Image.new("RGBA", FRAME, (0, 0, 0, 0))
            rebuilt.paste(page.crop((x, y, x + w, y + h)), (ox, oy))
            # Compare what is visible: premultiplied, a fully transparent
            # pixel is the same whatever colour it was stored with.
            if source.convert("RGBa").tobytes() != rebuilt.convert("RGBa").tobytes():
                problems.append("sprite %s is not pixel for pixel its source image" % name)
    if len(entries) != sum(len(tileset["tiles"]) for tileset in description["tilesets"]):
        problems.append("the pack holds a different number of sprites than the description")
    return problems


# ----------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------

def selftest():
    from PIL import Image, ImageDraw
    import tempfile

    failed = []

    def check(condition, message):
        if not condition:
            failed.append(message)

    # The two formats, on hand-made data.
    definition = {"version": 1, "tilesets": [{"name": b"a_01", "image": b"a_01.png", "columns": 8, "rows": 1, "id": 1,
                                              "tiles": [[(b"solid", b""), (b"Facing", b"S")]] + [[] for _ in range(7)]}]}
    data = write_tiles(definition)
    check(read_tiles(data) == definition, "tile definitions survive a write and a read")
    check(data[:4] == b"tdef" and struct.unpack_from("<ii", data, 4) == (1, 1), "the tile definition header")
    pack = {"version": 1, "pages": [{"name": b"P0", "flag": 1, "entries": [(b"a_01_0", 1, 1, 4, 5, 6, 7, 128, 256)], "png": b"\x89PNG-not-really"}]}
    data = write_pack(pack)
    check(read_pack(data) == pack, "a pack survives a write and a read")
    for bad in (b"nope" + b"\0" * 20, write_tiles(definition) + b"x"):
        try:
            read_tiles(bad)
            check(False, "a damaged tile definition file is refused")
        except (ValueError, struct.error):
            pass
    try:
        read_pack(write_pack(pack) + b"extra")
        check(False, "a pack with trailing bytes is refused")
    except ValueError:
        pass

    # A whole build, from generated sprites.
    with tempfile.TemporaryDirectory() as folder:
        for index, colour in enumerate(((200, 60, 60, 255), (60, 60, 200, 255))):
            image = Image.new("RGBA", FRAME, (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            draw.rectangle((20 + index * 9, 100, 90 + index * 9, 240), fill=colour, outline=(10, 10, 10, 255))
            draw.line((30, 110, 80, 230), fill=(255, 255, 255, 128))
            image.save(os.path.join(folder, "s%d.png" % index))
        description = {
            "pack": "SelfTest", "tiledef": "selftest", "fileNumber": 4000,
            "tilesets": [{"name": "selftest_01", "columns": 8, "rows": 1, "id": 1, "tiles": [
                {"index": 0, "image": "s0.png", "properties": {"Facing": "S", "solidtrans": ""}},
                {"index": 1, "image": "s1.png", "properties": {"Facing": "E", "PickUpWeight": 400}},
            ]}],
        }
        check(validate(description) == [], "a sound description has no problems: %s" % validate(description))
        tiles_bytes, pack_bytes, report = build(description, folder)
        problems = check_build(description, folder, tiles_bytes, pack_bytes)
        check(problems == [], "the built sheet reads back as described: %s" % "; ".join(problems))
        again = build(description, folder)
        check(again[0] == tiles_bytes and again[1] == pack_bytes, "the same description builds the same bytes")
        built = read_pack(pack_bytes)
        check(built["pages"][0]["name"] == b"SelfTest0" and built["pages"][0]["flag"] == 1, "one page, named after the pack, flagged as vanilla's tile pages are")
        check([entry[0] for entry in built["pages"][0]["entries"]] == [b"selftest_01_0", b"selftest_01_1"], "sprites are named tileset_index")
        check(all(entry[7:9] == FRAME for entry in built["pages"][0]["entries"]), "every sprite has the 128 x 256 frame")
        check(len(read_tiles(tiles_bytes)["tilesets"][0]["tiles"]) == 8, "the sheet has columns x rows tiles, empty ones included")
        # A changed pixel is noticed.
        tampered = Image.open(os.path.join(folder, "s0.png")).convert("RGBA")
        tampered.putpixel((40, 150), (1, 2, 3, 255))
        tampered.save(os.path.join(folder, "s0.png"))
        check(check_build(description, folder, tiles_bytes, pack_bytes) != [], "a sprite that differs from its source is reported")

        for change, what in (
            (lambda d: d.update(fileNumber=50), "a file number below 100"),
            (lambda d: d["tilesets"][0].update(columns=4), "a sheet that is not 8 columns wide"),
            (lambda d: d["tilesets"][0].update(name="Bad Name"), "a tileset name with a space"),
            (lambda d: d["tilesets"][0]["tiles"][0].update(index=99), "a tile outside the sheet"),
            (lambda d: d["tilesets"][0]["tiles"].append({"index": 0, "image": "s0.png"}), "a tile listed twice"),
        ):
            broken = json.loads(json.dumps(description))
            change(broken)
            check(validate(broken) != [], what + " is refused")

    for message in failed:
        print("  FAIL: " + message)
    print("Tile builder self-test: %s" % ("%d failed" % len(failed) if failed else "passed"))
    return 1 if failed else 0


def verify(install):
    """Reads vanilla's own files and writes them back: the formats are byte exact."""
    install = install.replace("\\", "/").rstrip("/")
    failed = 0
    for name in ("newtiledefinitions.tiles", "tiledefinitions_erosion.tiles"):
        path = install + "/media/" + name
        with open(path, "rb") as handle:
            data = handle.read()
        definition = read_tiles(data)
        same = write_tiles(definition) == data
        failed += 0 if same else 1
        print("%s  %s: %d tilesets, %d bytes, written back %s" % ("PASS    " if same else "BREAKING", name, len(definition["tilesets"]), len(data), "identically" if same else "DIFFERENTLY"))
    for name in ("B42ChunkCaching2x.pack", "Overlays2x.floor.pack"):
        path = install + "/media/texturepacks/" + name
        with open(path, "rb") as handle:
            data = handle.read()
        pack = read_pack(data)
        same = write_pack(pack) == data
        failed += 0 if same else 1
        frames = set(entry[7:9] for page in pack["pages"] for entry in page["entries"])
        flags = set(page["flag"] for page in pack["pages"])
        print("%s  %s: %d pages, %d sprites, frames %s, page flags %s, written back %s" % (
            "PASS    " if same else "BREAKING", name, len(pack["pages"]), sum(len(page["entries"]) for page in pack["pages"]),
            sorted(frames)[:3], sorted(flags), "identically" if same else "DIFFERENTLY"))
    return 2 if failed else 0


def main():
    parser = argparse.ArgumentParser(description="Build a Project Zomboid tile sheet (.tiles and .pack) from PNGs.")
    parser.add_argument("description", nargs="?", help="a tiles.json; output goes to build/ beside it")
    parser.add_argument("--selftest", action="store_true", help="check the builder on generated sprites (needs Pillow, no game)")
    parser.add_argument("--verify", action="store_true", help="read vanilla's own files and write them back byte for byte")
    parser.add_argument("--install", default=os.environ.get("PZ_INSTALL"), help="the Project Zomboid install, for --verify")
    arguments = parser.parse_args()

    if arguments.selftest:
        return selftest()
    if arguments.verify:
        if not arguments.install:
            parser.error("--verify needs --install <dir> or PZ_INSTALL")
        return verify(arguments.install)
    if not arguments.description:
        parser.error("give a tiles.json, --selftest or --verify")

    path = os.path.abspath(arguments.description)
    folder = os.path.dirname(path)
    with io.open(path, encoding="utf-8") as handle:
        description = json.load(handle)
    tiles_bytes, pack_bytes, report = build(description, folder)
    problems = check_build(description, folder, tiles_bytes, pack_bytes)
    if problems:
        print("FAILED   the built sheet does not read back as described: " + "; ".join(problems))
        return 1
    out = os.path.join(folder, "build")
    os.makedirs(os.path.join(out, "texturepacks"), exist_ok=True)
    tiles_path = os.path.join(out, description["tiledef"] + ".tiles")
    pack_path = os.path.join(out, "texturepacks", description["pack"] + ".pack")
    with open(tiles_path, "wb") as handle:
        handle.write(tiles_bytes)
    with open(pack_path, "wb") as handle:
        handle.write(pack_bytes)
    for line in report:
        print("  " + line)
    print("Wrote %s (%d bytes)" % (os.path.relpath(tiles_path, ROOT).replace("\\", "/"), len(tiles_bytes)))
    print("Wrote %s (%d bytes)" % (os.path.relpath(pack_path, ROOT).replace("\\", "/"), len(pack_bytes)))
    print("mod.info lines, for the day the press is switched on:")
    print("  pack=%s" % description["pack"])
    print("  tiledef=%s %d" % (description["tiledef"], description["fileNumber"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
