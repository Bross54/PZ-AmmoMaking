"""Ammo Making - draws the mod list posters and the Workshop preview.

    python art/workshop/make_workshop_art.py            draw every image
    python art/workshop/make_workshop_art.py --check    fail when a shipped image differs from a fresh drawing

Twelve square images, 256 x 256 (the six gun-mod packs share the
7.62x39 add-on's scene with their own title):

  mod/AmmoMaking/42/poster.png               the main mod's `poster=`
  mod/AmmoMakingPress/42/poster.png          the press add-on's `poster=`
  mod/AmmoMakingSpentCases/42/poster.png     the spent-cases add-on's `poster=`
  mod/AmmoMakingCalibre762x39/42/poster.png  the 7.62x39 add-on's `poster=`
  art/workshop/preview.png                   the Workshop item's preview.png;
                                             tools/build_release.py puts it
                                             beside Contents/ of the item

Why there and that size:

  JAR  ChooseGameInfo.readModInfoAux: a `poster=` file is looked for in the
       version folder (42/) first and in common/ only when it is not there.
  FILE media/lua/client/OptionScreens/ModSelector/ModInfoPanelDesc.lua: the
       mod list draws poster 0 scaled into a 200 x 200 square, so a square
       image keeps its proportions.
  FILE Workshop/ModTemplate/preview.png of the installed game is 256 x 256,
       beside Contents/ and workshop.txt (its poster.png is 512 x 512).
  CLUE installed Workshop mods: 413 of 427 posters named in a 42/mod.info
       are in that folder; the common sizes are 512 x 512 and 256 x 256.

Original pixel art: a dark workbench with the mod's own inventory icons
(art/icons/make_icons.py, imported, never copied), drawn at twice their
size, and the title in a pixel alphabet defined below. No font file, no
vanilla or third-party pixel. Deterministic: the same script gives the same
bytes, so the release gate can compare.
"""

import io
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.dont_write_bytecode = True  # no __pycache__ beside the icon script
sys.path.insert(0, os.path.join(REPO, "art", "icons"))
import make_icons as I  # noqa: E402  (the icon drawings)

SIZE = 256
SCALE = 2  # icons and the background are drawn on a grid of 2 x 2 pixels

# ---------------------------------------------------------------- lettering

# A 5 x 7 pixel alphabet of the mod's own: only what the images write.
GLYPHS = {
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    " ": ["00000"] * 7,
}

INK_DARK = (24, 19, 17)
TITLE = [(252, 236, 160), (230, 196, 98), (196, 154, 62)]  # brass, light to dark
PAPER = (226, 218, 196)
WARNING = (232, 150, 70)


def text_width(text, scale):
    return (len(text) * 6 - 1) * scale


def letter_mask(text, scale):
    """The text as a mask, 1 = ink."""
    mask = Image.new("L", (text_width(text, scale), 7 * scale), 0)
    draw = ImageDraw.Draw(mask)
    for index, char in enumerate(text):
        rows = GLYPHS[char]
        for y, row in enumerate(rows):
            for x, bit in enumerate(row):
                if bit == "1":
                    x0 = (index * 6 + x) * scale
                    y0 = y * scale
                    draw.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=255)
    return mask


def write(image, text, y, scale, colours, shadow=True):
    """Centred lettering; a vertical brass ramp when given three colours,
    a dark outline and a drop shadow one grid step down."""
    mask = letter_mask(text, scale)
    width, height = mask.size
    x = (SIZE - width) // 2
    x -= x % SCALE
    fill = Image.new("RGBA", mask.size)
    draw = ImageDraw.Draw(fill)
    for row in range(height):
        band = min(len(colours) - 1, row * len(colours) // height)
        draw.line([(0, row), (width, row)], fill=I.rgba(colours[band]))
    letters = Image.new("RGBA", mask.size, I.CLEAR)
    letters.paste(fill, (0, 0), mask)
    # Outline: the mask grown by one grid step in the four directions.
    edge = Image.new("RGBA", (width + 2 * SCALE, height + 2 * SCALE), I.CLEAR)
    dark = Image.new("RGBA", mask.size, I.rgba(INK_DARK))
    for dx, dy in ((0, SCALE), (2 * SCALE, SCALE), (SCALE, 0), (SCALE, 2 * SCALE), (SCALE, SCALE)):
        edge.paste(dark, (dx, dy), mask)
    if shadow:
        image.alpha_composite(edge, (x - SCALE, y + SCALE))
    image.alpha_composite(edge, (x - SCALE, y - SCALE))
    image.alpha_composite(letters, (x, y))


# ---------------------------------------------------------------- the scene

WALL = [(58, 54, 60), (48, 45, 51), (40, 37, 43), (33, 31, 36)]
BENCH = I.WOOD
BENCH_TOP = 166


def lcg(seed):
    """MINSTD, as the icons use: the same speckle every run."""
    state = seed
    while True:
        state = (state * 48271) % 2147483647
        yield state


def background(seed):
    """A dark wall of vertical boards and a wooden bench top, on the 2 x 2 grid."""
    half = SIZE // SCALE
    top = BENCH_TOP // SCALE
    small = Image.new("RGBA", (half, half), I.rgba(WALL[1]))
    draw = ImageDraw.Draw(small)
    rolls = lcg(seed)
    # The wall: boards 16 wide, a dark seam, darker towards the top corners.
    for x in range(half):
        seam = x % 16 == 0
        for y in range(top):
            tone = 1
            if seam:
                tone = 3
            elif x % 16 == 1:
                tone = 0
            if y < 10 and tone < 2:
                tone += 1
            if not seam and next(rolls) % 100 < 8:
                tone = min(3, tone + 1)
            small.putpixel((x, y), I.rgba(WALL[tone]))
    # A shelf line and its shadow.
    draw.line([(0, top - 18), (half, top - 18)], fill=I.rgba(BENCH[3]))
    draw.line([(0, top - 17), (half, top - 17)], fill=I.rgba(WALL[3]))
    # The bench: planks running across, a lit front edge, grain.
    draw.rectangle([0, top, half, half], fill=I.rgba(BENCH[2]))
    draw.line([(0, top), (half, top)], fill=I.rgba(BENCH[0]))
    draw.line([(0, top + 1), (half, top + 1)], fill=I.rgba(BENCH[1]))
    for plank in range(top + 12, half, 12):
        draw.line([(0, plank), (half, plank)], fill=I.rgba(BENCH[4]))
        draw.line([(0, plank + 1), (half, plank + 1)], fill=I.rgba(BENCH[1]))
    for y in range(top + 2, half):
        for x in range(half):
            roll = next(rolls) % 1000
            if small.getpixel((x, y))[:3] != tuple(BENCH[2]):
                continue
            if roll < 70:
                small.putpixel((x, y), I.rgba(BENCH[3]))
            elif roll < 95:
                small.putpixel((x, y), I.rgba(BENCH[1]))
    # Darken the bottom rows: the light comes from above.
    for y in range(half - 6, half):
        for x in range(half):
            r, g, b, a = small.getpixel((x, y))
            small.putpixel((x, y), (r * 3 // 4, g * 3 // 4, b * 3 // 4, a))
    return small.resize((SIZE, SIZE), Image.NEAREST)


def place(image, icon, x, y, zoom=SCALE, shadow=True):
    """An icon at zoom times its size; (x, y) is its top left, kept on the
    grid. A soft-edged dark ellipse under it where it stands on the bench."""
    big = icon.resize((icon.size[0] * zoom, icon.size[1] * zoom), Image.NEAREST)
    x -= x % SCALE
    y -= y % SCALE
    if shadow:
        # The lowest opaque row of the icon is where it stands.
        box = icon.getbbox()
        foot = y + box[3] * zoom
        left, right = x + box[0] * zoom, x + box[2] * zoom
        layer = Image.new("RGBA", image.size, I.CLEAR)
        draw = ImageDraw.Draw(layer)
        draw.ellipse([left + 2, foot - 6, right - 2, foot + 4], fill=(0, 0, 0, 90))
        image.alpha_composite(layer)
    image.alpha_composite(big, (x, y))


def frame(image):
    """A dark border two grid steps wide, and a lit inner line."""
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=I.rgba(INK_DARK), width=4)
    draw.rectangle([4, 4, SIZE - 5, SIZE - 5], outline=I.rgba(I.BRASS[3]), width=2)


def badge(image, text, y):
    """A small dark plate with light lettering, for the add-ons' warning."""
    width = text_width(text, SCALE)
    x = (SIZE - width) // 2
    x -= x % SCALE
    draw = ImageDraw.Draw(image)
    draw.rectangle([x - 6, y - 6, x + width + 5, y + 7 * SCALE + 5], fill=I.rgba(INK_DARK))
    draw.rectangle([x - 4, y - 4, x + width + 3, y + 7 * SCALE + 3], outline=I.rgba(WARNING), width=2)
    write(image, text, y, SCALE, [WARNING], shadow=False)


def finish(image):
    frame(image)
    return image.convert("RGB")


def main_scene(subtitle):
    """The main mod: ore to round along the bench, no press (that is an add-on)."""
    image = background(seed=4242)
    write(image, "AMMO MAKING", 18, 3, TITLE)
    write(image, subtitle, 52, SCALE, [PAPER])
    # On the shelf: the ore, the ingot, a book.
    place(image, I.icon_zinc_ore(), 22, 76, shadow=False)
    place(image, I.icon_zinc_ingot(), 96, 76, shadow=False)
    place(image, I.icon_book(1), 170, 70, shadow=False)
    # On the bench, back row: the die set, sheets and cups, primers.
    place(image, I.icon_brass_sheet(), 10, 138)
    place(image, I.icon_die_set(), 96, 132)
    place(image, I.icon_primer(False, False), 182, 140)
    # Front row: the cases and the bullets that go in them.
    place(image, I.icon_case_cup(), 4, 186)
    place(image, I.icon_case_pistol(), 64, 184)
    place(image, I.icon_case_rifle(), 128, 182)
    place(image, I.icon_bullet_pistol(), 190, 188)
    return finish(image)


def press_scene():
    """The press add-on: the press itself, large, with cases beside it."""
    image = background(seed=6142)
    write(image, "AMMO MAKING", 18, 3, TITLE)
    write(image, "RELOADING PRESS", 52, SCALE, [PAPER])
    place(image, I.icon_press(), 56, 66, zoom=3)
    place(image, I.icon_case_pistol(), 4, 148)
    place(image, I.icon_bullet_pistol(), 188, 150)
    badge(image, "EXPERIMENTAL", 228)
    return finish(image)


def spent_scene(title="SPENT CASES"):
    """The spent-cases add-on: fired brass on the bench, the die set that resizes it."""
    image = background(seed=2222)
    write(image, "AMMO MAKING", 18, 3, TITLE)
    write(image, title, 52, SCALE, [PAPER])
    place(image, I.icon_die_set(), 96, 76, shadow=False)
    place(image, I.icon_case_pistol(True), 8, 136)
    place(image, I.icon_case_rifle(True), 70, 140)
    place(image, I.icon_hull(True), 134, 136)
    place(image, I.icon_case_magnum(True), 192, 140)
    badge(image, "EXPERIMENTAL", 228)
    return finish(image)


def calibre_scene(title="7.62X39", seed=7639):
    """A calibre add-on: its die set, rifle cases, cast bullets with gas checks."""
    image = background(seed=seed)
    write(image, "AMMO MAKING", 18, 3, TITLE)
    write(image, title, 52, SCALE, [PAPER])
    place(image, I.icon_die_set(), 96, 76, shadow=False)
    place(image, I.icon_case_rifle(), 8, 138)
    place(image, I.icon_cast_bullet_rifle(), 70, 140)
    place(image, I.icon_gas_check(), 134, 140)
    place(image, I.icon_bullet_rifle(), 192, 138)
    badge(image, "EXPERIMENTAL", 228)
    return finish(image)


# ---------------------------------------------------------------- output

# Where each image goes, relative to the repository, and how it is drawn.
IMAGES = [
    ("mod/AmmoMaking/42/poster.png", lambda: main_scene("BUILD 42")),
    ("mod/AmmoMakingPress/42/poster.png", press_scene),
    ("mod/AmmoMakingSpentCases/42/poster.png", spent_scene),
    ("mod/AmmoMakingCalibre762x39/42/poster.png", calibre_scene),
    ("mod/AmmoMakingVFE/42/poster.png", lambda: calibre_scene("VFE", 3761)),
    ("mod/AmmoMakingRains/42/poster.png", lambda: calibre_scene("RAIN'S", 3773)),
    ("mod/AmmoMakingRainsExpanded/42/poster.png", lambda: calibre_scene("RAIN'S EXP", 3774)),
    ("mod/AmmoMakingGaelGunStore/42/poster.png", lambda: calibre_scene("GAELGUNSTORE", 3616)),
    ("mod/AmmoMakingRealFirearms/42/poster.png", lambda: calibre_scene("REAL FIREARMS", 3238)),
    ("mod/AmmoMakingMFS/42/poster.png", lambda: calibre_scene("MFS", 3633)),
    ("mod/AmmoMakingHotBrass/42/poster.png", lambda: spent_scene("HOT BRASS")),
    ("art/workshop/preview.png", lambda: main_scene("FROM ORE TO ROUND")),
]


def encode(image):
    return I.encode(image)


def main(argv):
    check = "--check" in argv
    problems = []
    for path, draw in IMAGES:
        image = draw()
        assert image.size == (SIZE, SIZE), path
        data = encode(image)
        target = os.path.join(REPO, path)
        if check:
            if not os.path.isfile(target) or open(target, "rb").read() != data:
                problems.append(path)
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as handle:
                handle.write(data)
    if check:
        if problems:
            print("workshop images differ from a fresh drawing (run art/workshop/make_workshop_art.py):")
            for problem in problems:
                print("  " + problem)
            return 1
        print("workshop images: %d files equal a fresh drawing" % len(IMAGES))
        return 0
    print("drew %d workshop images" % len(IMAGES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
