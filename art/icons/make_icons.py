"""Ammo Making - draws the mod's inventory icons.

    python art/icons/make_icons.py            draw every icon and the preview sheet
    python art/icons/make_icons.py --check    fail when a shipped icon differs from a fresh drawing

Original pixel art, drawn from the shapes below at the size the game shows
it: 32 x 32 (48 x 48 for the press's window icon, like vanilla's Build_
icons), a dark one-pixel outline, a few flat tones lit from the upper
left. It copies no vanilla or third-party pixel. The drawing is
deterministic: the same script gives the same bytes, so the release gate
can compare.

Every icon has a name of the mod's own (`AmmoMaking...`), so no vanilla
icon is ever replaced. Where each file goes is in ICONS at the end; the
preview sheet (`art/icons/preview.png`, every icon at eight times its
size) is for people, the game never reads it.
"""

import io
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SIZE = 32

MAIN = "mod/AmmoMaking/42/media/textures/"
PRESS = "mod/AmmoMakingPress/42/media/textures/"
SPENT = "mod/AmmoMakingSpentCases/42/media/textures/"

OUTLINE = (30, 24, 22, 255)
CLEAR = (0, 0, 0, 0)

# Five tones each, light to dark.
BRASS = [(252, 236, 160), (230, 196, 98), (196, 154, 62), (146, 108, 42), (98, 70, 28)]
TARNISH = [(196, 176, 122), (160, 134, 82), (124, 100, 60), (92, 72, 44), (62, 48, 32)]
COPPER = [(248, 186, 140), (220, 138, 92), (180, 98, 62), (130, 66, 44), (86, 42, 30)]
ZINC = [(232, 240, 246), (186, 202, 216), (136, 154, 174), (94, 110, 132), (60, 72, 92)]
STEEL = [(218, 222, 226), (168, 174, 180), (118, 124, 132), (78, 84, 92), (48, 52, 58)]
ROCK = [(150, 158, 170), (112, 120, 134), (82, 90, 104), (58, 64, 78), (40, 44, 56)]
CANVAS = [(206, 190, 150), (176, 158, 116), (140, 124, 88), (104, 90, 62), (72, 62, 44)]
OLIVE = [(150, 156, 104), (116, 124, 78), (86, 94, 58), (60, 68, 42), (42, 48, 32)]
CASE = [(196, 204, 210), (150, 160, 170), (108, 118, 130), (72, 80, 92), (46, 52, 62)]
CREAM = [(240, 232, 208), (212, 202, 174), (174, 164, 138), (130, 122, 102), (90, 84, 70)]
WOOD = [(190, 146, 96), (156, 114, 70), (122, 86, 52), (90, 62, 38), (62, 42, 28)]
SOOT = (44, 38, 34)
HOLE = (52, 38, 24)


def rgba(colour, alpha=255):
    return tuple(colour[:3]) + (alpha,)


def blank(size=SIZE):
    return Image.new("RGBA", (size, size), CLEAR)


def outline(image, colour=OUTLINE):
    """A one-pixel outline round everything drawn (4-neighbours)."""
    source = image.load()
    width, height = image.size
    result = image.copy()
    target = result.load()
    for y in range(height):
        for x in range(width):
            if source[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and source[nx, ny][3] != 0:
                    target[x, y] = colour
                    break
    return result


def paste(base, layer, dx=0, dy=0):
    """Put a layer on top, moved by (dx, dy); opaque pixels win."""
    moved = Image.new("RGBA", base.size, CLEAR)
    moved.paste(layer, (dx, dy))
    base.alpha_composite(moved)
    return base


def turn(image, degrees):
    """Rotate pixel art without blending colours."""
    return image.rotate(degrees, resample=Image.NEAREST, expand=False)


def column(draw, x0, x1, y0, y1, ramp, bands=None):
    """An upright cylinder side: vertical bands, the highlight left of centre."""
    width = x1 - x0 + 1
    bands = bands or [1, 0, 0, 1, 1, 2, 2, 3, 3, 4]
    for i in range(width):
        tone = bands[min(len(bands) - 1, int(i * len(bands) / width))]
        draw.line([(x0 + i, y0), (x0 + i, y1)], fill=rgba(ramp[tone]))


def speckle(image, mask_colour_index, ramp, seed, share=0.22):
    """Break up a flat tone with its neighbours, the same way every run."""
    pixels = image.load()
    state = seed
    for y in range(image.size[1]):
        for x in range(image.size[0]):
            state = (state * 48271) % 2147483647
            if pixels[x, y][3] == 0:
                continue
            if pixels[x, y][:3] != tuple(ramp[mask_colour_index]):
                continue
            roll = (state % 1000) / 1000.0
            if roll < share / 2 and mask_colour_index > 0:
                pixels[x, y] = rgba(ramp[mask_colour_index - 1])
            elif roll < share and mask_colour_index < len(ramp) - 1:
                pixels[x, y] = rgba(ramp[mask_colour_index + 1])


# ---------------------------------------------------------------- cases

def case_shape(width, height, ramp, neck=None, shoulder=0, rim=1, spent=False, belt=False):
    """An empty case standing mouth up, its foot at the middle of the frame's lower edge.

    neck: width of a bottleneck's neck, or None for a straight wall.
    shoulder: height of the neck above the shoulder.
    rim: how far the rim stands out on each side.
    """
    image = blank()
    draw = ImageDraw.Draw(image)
    left = 16 - width // 2
    right = left + width - 1
    bottom = 29
    top = bottom - height + 1

    if neck:
        neck_left = 16 - neck // 2
        neck_right = neck_left + neck - 1
        shoulder_y = top + shoulder
        column(draw, neck_left, neck_right, top, shoulder_y, ramp)
        # The shoulder: two rows widening to the body.
        steps = 2
        for step in range(1, steps + 1):
            grow = int(round((left - neck_left) * step / (steps + 1.0)))
            column(draw, neck_left + grow, neck_right - grow, shoulder_y + step, shoulder_y + step, ramp)
        column(draw, left, right, shoulder_y + steps + 1, bottom - 3, ramp)
        mouth_left, mouth_right = neck_left, neck_right
    else:
        column(draw, left, right, top, bottom - 3, ramp)
        mouth_left, mouth_right = left, right

    # Extractor groove and rim.
    draw.line([(left, bottom - 2), (right, bottom - 2)], fill=rgba(ramp[4]))
    column(draw, left - rim, right + rim, bottom - 1, bottom, ramp)
    if belt:
        draw.line([(left, bottom - 5), (right, bottom - 5)], fill=rgba(ramp[3]))

    # The open mouth: a dark hole with a lit lip.
    draw.line([(mouth_left, top), (mouth_right, top)], fill=rgba(ramp[0]))
    if mouth_right - mouth_left >= 2:
        draw.line([(mouth_left + 1, top), (mouth_right - 1, top)], fill=rgba(HOLE))
        draw.line([(mouth_left, top - 1), (mouth_right, top - 1)], fill=rgba(ramp[1]))
        draw.point((mouth_left, top - 1), fill=CLEAR)
        draw.point((mouth_right, top - 1), fill=CLEAR)
        draw.line([(mouth_left + 1, top - 1), (mouth_right - 1, top - 1)], fill=rgba(ramp[1]))

    if spent:
        # Soot below the mouth, fading down the wall.
        pixels = image.load()
        for y in range(top, top + 4):
            for x in range(mouth_left, mouth_right + 1):
                if pixels[x, y][3] != 0 and pixels[x, y][:3] != HOLE and (x + y) % 2 == (0 if y < top + 2 else 1) or (y == top + 1 and pixels[x, y][3] != 0):
                    pixels[x, y] = rgba(SOOT)
    return image


def pair(shape, lean=24, spread=6, lift=2):
    """Two of a thing: one standing, one leaning against nothing, a little lower."""
    image = blank()
    paste(image, shape, -spread, -lift)
    paste(image, turn(shape, -lean), spread - 1, 1)
    return outline(image)


def icon_case_pistol(spent=False):
    ramp = TARNISH if spent else BRASS
    return pair(case_shape(7, 13, ramp, rim=0, spent=spent), lean=28, spread=6)


def icon_case_magnum(spent=False):
    ramp = TARNISH if spent else BRASS
    return pair(case_shape(7, 18, ramp, rim=1, spent=spent), lean=24, spread=6, lift=1)


def icon_case_rifle(spent=False):
    ramp = TARNISH if spent else BRASS
    return pair(case_shape(7, 24, ramp, neck=5, shoulder=6, rim=0, spent=spent), lean=20, spread=6, lift=0)


def icon_hull(spent=False):
    ramp = TARNISH if spent else BRASS
    return pair(case_shape(9, 20, ramp, rim=1, spent=spent, belt=True), lean=30, spread=7, lift=1)


# ---------------------------------------------------------------- projectiles

def bullet_shape(width, height, nose, ramp=COPPER):
    """A bullet standing on its base; nose is the height of the curved or pointed part."""
    image = blank()
    draw = ImageDraw.Draw(image)
    left = 16 - width // 2
    right = left + width - 1
    bottom = 27
    top = bottom - height + 1
    column(draw, left, right, top + nose, bottom, ramp)
    for row in range(nose):
        # Narrow toward the tip (row 0): a rounded profile for a short nose, an ogive for a long one.
        share = (nose - row) / float(nose)
        if nose <= width:
            inset = int(round((width / 2.0) * (1 - math.sqrt(max(0.0, 1 - share * share)))))
        else:
            inset = int(round((width / 2.0 - 0.5) * share ** 1.6))
        inset = min(inset, (width - 1) // 2)
        column(draw, left + inset, right - inset, top + row, top + row, ramp)
    # A cannelure and the flat base.
    draw.line([(left, bottom - 3), (right, bottom - 3)], fill=rgba(ramp[3]))
    draw.line([(left, bottom), (right, bottom)], fill=rgba(ramp[4]))
    return image


def row_of(shape, places):
    """The same thing several times, side by side, each on its own foot."""
    image = blank()
    for dx, dy in places:
        paste(image, shape, dx, dy)
    return outline(image)


def icon_bullet_pistol():
    return row_of(bullet_shape(8, 12, 5), [(-9, -6), (9, -4), (0, 2)])


def icon_bullet_rifle():
    return row_of(bullet_shape(6, 20, 12), [(-9, -3), (8, -1), (0, 2)])


def icon_shot():
    """A small heap of copper shot."""
    image = blank()
    draw = ImageDraw.Draw(image)
    balls = [
        (9, 24), (14, 25), (19, 24), (24, 24),
        (6, 21), (11, 20), (16, 21), (21, 20), (26, 21),
        (9, 17), (14, 16), (19, 17), (23, 17),
        (12, 13), (17, 12), (21, 14),
        (15, 9),
    ]
    for x, y in balls:
        draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=rgba(COPPER[2]))
        draw.ellipse([x - 2, y - 2, x + 1, y + 1], fill=rgba(COPPER[1]))
        draw.point((x - 1, y - 1), fill=rgba(COPPER[0]))
        draw.point((x + 1, y + 2), fill=rgba(COPPER[4]))
        draw.point((x + 2, y + 1), fill=rgba(COPPER[3]))
    return outline(image)


# ---------------------------------------------------------------- primers

def primer_shape(draw, cx, cy, rx, ry):
    """A primer cup seen from above and a little to the side: open, the anvil inside."""
    draw.ellipse([cx - rx, cy - ry + 2, cx + rx, cy + ry + 2], fill=rgba(BRASS[3]))
    draw.rectangle([cx - rx, cy, cx + rx, cy + 2], fill=rgba(BRASS[2]))
    draw.line([(cx - rx, cy), (cx - rx, cy + 2)], fill=rgba(BRASS[1]))
    draw.line([(cx + rx, cy), (cx + rx, cy + 2)], fill=rgba(BRASS[4]))
    draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rgba(BRASS[1]))
    draw.ellipse([cx - rx + 1, cy - ry + 1, cx + rx - 1, cy + ry - 1], fill=rgba(BRASS[3]))
    draw.line([(cx - 1, cy), (cx + 1, cy)], fill=rgba(BRASS[0]))
    draw.point((cx - rx + 1, cy - 1), fill=rgba(BRASS[0]))


def icon_primer(large, rifle):
    image = blank()
    draw = ImageDraw.Draw(image)
    if large:
        spots = [(10, 11, 5, 3), (21, 14, 5, 3), (13, 22, 5, 3)]
    else:
        spots = [(8, 9, 3, 2), (17, 8, 3, 2), (25, 11, 3, 2), (11, 17, 3, 2), (20, 18, 3, 2), (14, 25, 3, 2), (24, 25, 3, 2)]
    for spot in spots:
        primer_shape(draw, *spot)
    if rifle:
        # Rifle primers: a sealed, nickel-coloured cup among them, so the two families differ at a glance.
        cx, cy, rx, ry = spots[-1]
        draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rgba(STEEL[1]))
        draw.ellipse([cx - rx + 1, cy - ry + 1, cx + rx - 1, cy + ry - 1], fill=rgba(STEEL[0]))
        draw.rectangle([cx - rx, cy + 1, cx + rx, cy + 2], fill=rgba(STEEL[3]))
        cx, cy, rx, ry = spots[0]
        draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rgba(STEEL[1]))
        draw.ellipse([cx - rx + 1, cy - ry + 1, cx + rx - 1, cy + ry - 1], fill=rgba(STEEL[0]))
        draw.rectangle([cx - rx, cy + 1, cx + rx, cy + 2], fill=rgba(STEEL[3]))
    return outline(image)


# ---------------------------------------------------------------- die set

def die(draw, x, bottom, height, ring):
    column(draw, x, x + 4, bottom - height + 1, bottom, STEEL)
    # Knurled band and the lock ring.
    for row in (bottom - height + 3, bottom - height + 5):
        for i in range(5):
            if (i + row) % 2 == 0:
                draw.point((x + i, row), fill=rgba(STEEL[3]))
    column(draw, x - 1, x + 5, ring, ring + 1, BRASS)
    draw.line([(x + 1, bottom - height), (x + 3, bottom - height)], fill=rgba(STEEL[1]))


def icon_die_set():
    image = blank()
    draw = ImageDraw.Draw(image)
    # The far wall of an open box.
    draw.polygon([(4, 14), (27, 14), (29, 18), (2, 18)], fill=rgba(OLIVE[3]))
    # Three dies standing in it.
    die(draw, 6, 22, 15, 15)
    die(draw, 14, 22, 17, 13)
    die(draw, 22, 22, 14, 16)
    # The near wall and its label.
    draw.polygon([(2, 19), (29, 19), (28, 28), (3, 28)], fill=rgba(OLIVE[2]))
    draw.line([(2, 19), (29, 19)], fill=rgba(OLIVE[0]))
    draw.line([(3, 28), (28, 28)], fill=rgba(OLIVE[4]))
    draw.line([(28, 20), (28, 27)], fill=rgba(OLIVE[3]))
    draw.rectangle([10, 22, 21, 25], fill=rgba(CREAM[1]))
    draw.line([(12, 23), (19, 23)], fill=rgba(CREAM[3]))
    draw.line([(12, 24), (16, 24)], fill=rgba(CREAM[3]))
    return outline(image)


# ---------------------------------------------------------------- zinc and brass stock

def icon_zinc_ore():
    image = blank()
    draw = ImageDraw.Draw(image)
    # An angular lump, lit from the upper left.
    draw.polygon([(5, 20), (8, 11), (15, 6), (23, 8), (28, 15), (27, 23), (20, 27), (10, 26)], fill=rgba(ROCK[2]))
    draw.polygon([(8, 11), (15, 6), (23, 8), (19, 13), (12, 14)], fill=rgba(ROCK[1]))
    draw.polygon([(8, 11), (15, 6), (16, 9), (11, 12)], fill=rgba(ROCK[0]))
    draw.polygon([(19, 13), (23, 8), (28, 15), (27, 23), (22, 19)], fill=rgba(ROCK[3]))
    draw.polygon([(22, 19), (27, 23), (20, 27), (16, 23)], fill=rgba(ROCK[4]))
    speckle(image, 2, ROCK, 11)
    speckle(image, 3, ROCK, 23, 0.16)
    # Pale blue-white ore showing on the broken faces.
    for points in ([(9, 17), (11, 15), (13, 17), (11, 20)], [(15, 15), (18, 14), (19, 17), (16, 19)], [(13, 22), (16, 21), (17, 24), (14, 25)], [(21, 21), (23, 20), (24, 23)]):
        draw.polygon(points, fill=rgba(ZINC[1]))
        draw.point(points[0], fill=rgba(ZINC[0]))
        draw.point(points[1], fill=rgba(ZINC[0]))
    draw.point((20, 10), fill=rgba(ZINC[1]))
    draw.point((21, 11), fill=rgba(ZINC[0]))
    return outline(image)


def shard(draw, points, top, side):
    draw.polygon(points, fill=rgba(ZINC[side]))
    draw.polygon(points[:3] + [points[-1]], fill=rgba(ZINC[top]))
    draw.line([points[0], points[1]], fill=rgba(ZINC[0]))


def icon_zinc_scrap():
    image = blank()
    draw = ImageDraw.Draw(image)
    shard(draw, [(4, 22), (12, 14), (17, 17), (15, 24), (8, 27)], 2, 3)
    shard(draw, [(13, 12), (22, 7), (27, 11), (22, 17), (16, 17)], 1, 3)
    shard(draw, [(16, 21), (24, 16), (29, 20), (25, 26), (18, 27)], 1, 2)
    shard(draw, [(9, 9), (13, 5), (16, 8), (13, 12), (10, 12)], 2, 4)
    draw.line([(18, 13), (23, 10)], fill=rgba(ZINC[0]))
    draw.line([(20, 23), (25, 20)], fill=rgba(ZINC[0]))
    return outline(image)


def bar(ramp):
    """An ingot lying from the upper left to the lower right."""
    image = blank()
    draw = ImageDraw.Draw(image)
    # Top face, near long face, near end.
    draw.polygon([(4, 12), (10, 8), (27, 16), (21, 20)], fill=rgba(ramp[1]))
    draw.polygon([(4, 12), (21, 20), (20, 26), (2, 17)], fill=rgba(ramp[2]))
    draw.polygon([(21, 20), (27, 16), (29, 21), (20, 26)], fill=rgba(ramp[3]))
    draw.line([(5, 12), (10, 9)], fill=rgba(ramp[0]))
    draw.line([(10, 9), (25, 16)], fill=rgba(ramp[0]))
    draw.line([(8, 12), (19, 17)], fill=rgba(ramp[0]))
    draw.line([(3, 17), (20, 25)], fill=rgba(ramp[3]))
    draw.line([(21, 25), (28, 21)], fill=rgba(ramp[4]))
    return outline(image)


def icon_zinc_ingot():
    return bar(ZINC)


def icon_brass_sheet():
    image = blank()
    draw = ImageDraw.Draw(image)
    draw.polygon([(3, 17), (17, 7), (29, 14), (15, 25)], fill=rgba(BRASS[1]))
    # Its thin near edges.
    draw.polygon([(3, 17), (15, 25), (15, 27), (3, 19)], fill=rgba(BRASS[3]))
    draw.polygon([(15, 25), (29, 14), (29, 16), (15, 27)], fill=rgba(BRASS[4]))
    # Light running across the rolled surface.
    draw.line([(8, 15), (18, 8)], fill=rgba(BRASS[0]))
    draw.line([(10, 17), (21, 9)], fill=rgba(BRASS[0]))
    draw.line([(14, 21), (25, 13)], fill=rgba(BRASS[2]))
    draw.line([(16, 23), (27, 14)], fill=rgba(BRASS[2]))
    return outline(image)


def cup(draw, cx, cy):
    column(draw, cx - 5, cx + 5, cy, cy + 6, BRASS)
    draw.ellipse([cx - 5, cy + 4, cx + 5, cy + 8], fill=rgba(BRASS[3]))
    draw.line([(cx - 3, cy + 8), (cx + 3, cy + 8)], fill=rgba(BRASS[4]))
    draw.ellipse([cx - 5, cy - 2, cx + 5, cy + 2], fill=rgba(BRASS[1]))
    draw.ellipse([cx - 4, cy - 1, cx + 4, cy + 1], fill=rgba(HOLE))
    draw.line([(cx - 3, cy - 2), (cx + 2, cy - 2)], fill=rgba(BRASS[0]))


def icon_case_cup():
    image = blank()
    draw = ImageDraw.Draw(image)
    cup(draw, 20, 8)
    cup(draw, 11, 18)
    return outline(image)


# ---------------------------------------------------------------- geology

def icon_sample():
    """A cloth sample bag, tied, with a paper tag."""
    image = blank()
    draw = ImageDraw.Draw(image)
    draw.polygon([(8, 14), (12, 11), (20, 11), (24, 14), (26, 22), (23, 28), (9, 28), (6, 22)], fill=rgba(CANVAS[1]))
    draw.polygon([(8, 14), (12, 11), (16, 11), (12, 20), (7, 22)], fill=rgba(CANVAS[0]))
    draw.polygon([(20, 14), (24, 14), (26, 22), (23, 28), (18, 28), (22, 21)], fill=rgba(CANVAS[2]))
    draw.line([(10, 28), (22, 28)], fill=rgba(CANVAS[3]))
    # The gathered neck and the tie.
    draw.polygon([(12, 10), (20, 10), (22, 5), (18, 7), (15, 4), (13, 7), (10, 5)], fill=rgba(CANVAS[1]))
    draw.line([(13, 5), (13, 8)], fill=rgba(CANVAS[3]))
    draw.line([(17, 6), (17, 8)], fill=rgba(CANVAS[3]))
    draw.line([(11, 10), (21, 10)], fill=rgba(WOOD[3]))
    draw.line([(12, 11), (20, 11)], fill=rgba(WOOD[4]))
    # Grit showing through the weave.
    for x, y in ((11, 24), (14, 22), (17, 25), (20, 23), (13, 26)):
        draw.point((x, y), fill=rgba(CANVAS[3]))
    # The tag on its string.
    draw.line([(21, 11), (24, 13)], fill=rgba(WOOD[4]))
    draw.polygon([(22, 14), (28, 14), (28, 20), (22, 20)], fill=rgba(CREAM[0]))
    draw.line([(23, 16), (26, 16)], fill=rgba(CREAM[3]))
    draw.line([(23, 18), (25, 18)], fill=rgba(CREAM[3]))
    draw.point((23, 15), fill=rgba(WOOD[4]))
    return outline(image)


def loupe(draw, cx, cy, radius=4):
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=rgba(STEEL[3]))
    draw.ellipse([cx - radius + 1, cy - radius + 1, cx + radius - 1, cy + radius - 1], fill=(150, 200, 224, 255))
    draw.line([(cx - 2, cy - 1), (cx - 1, cy - 2)], fill=(226, 244, 250, 255))
    draw.line([(cx + 3, cy + 3), (cx + 6, cy + 6)], fill=rgba(WOOD[3]), width=2)


def icon_field_kit():
    """A canvas tool roll, half open, with a hand lens."""
    image = blank()
    draw = ImageDraw.Draw(image)
    # The unrolled flap.
    draw.polygon([(3, 15), (20, 11), (29, 17), (12, 22)], fill=rgba(OLIVE[1]))
    draw.line([(4, 15), (20, 11)], fill=rgba(OLIVE[0]))
    # Pockets with a steel tool in each.
    for x, y in ((9, 16), (13, 15), (17, 14)):
        draw.line([(x, y - 3), (x + 2, y + 2)], fill=rgba(STEEL[1]))
        draw.line([(x + 1, y), (x + 4, y - 1)], fill=rgba(OLIVE[3]))
    # The rolled part.
    draw.polygon([(12, 22), (29, 17), (30, 22), (27, 27), (14, 29), (11, 26)], fill=rgba(OLIVE[2]))
    draw.line([(13, 23), (29, 18)], fill=rgba(OLIVE[1]))
    draw.line([(14, 28), (27, 26)], fill=rgba(OLIVE[4]))
    draw.ellipse([10, 22, 15, 29], fill=rgba(OLIVE[3]))
    draw.ellipse([11, 24, 13, 27], fill=rgba(OLIVE[4]))
    # A strap.
    draw.line([(21, 20), (22, 27)], fill=rgba(WOOD[3]))
    draw.line([(22, 20), (23, 27)], fill=rgba(WOOD[2]))
    loupe(draw, 9, 8)
    return outline(image)


def icon_advanced_kit():
    """A hard instrument case with a test tube rack on its lid."""
    image = blank()
    draw = ImageDraw.Draw(image)
    # Body: front, top, right side.
    draw.polygon([(3, 16), (22, 16), (22, 28), (3, 28)], fill=rgba(CASE[2]))
    draw.polygon([(3, 16), (9, 11), (28, 11), (22, 16)], fill=rgba(CASE[1]))
    draw.polygon([(22, 16), (28, 11), (28, 23), (22, 28)], fill=rgba(CASE[3]))
    draw.line([(4, 16), (21, 16)], fill=rgba(CASE[0]))
    draw.line([(3, 20), (22, 20)], fill=rgba(CASE[4]))
    draw.line([(22, 20), (28, 15)], fill=rgba(CASE[4]))
    # Latches and corner guards.
    for x in (6, 17):
        draw.rectangle([x, 19, x + 2, 22], fill=rgba(BRASS[1]))
        draw.point((x + 1, 22), fill=rgba(BRASS[3]))
    draw.rectangle([3, 26, 5, 28], fill=rgba(CASE[4]))
    draw.rectangle([20, 26, 22, 28], fill=rgba(CASE[4]))
    # An orange hazard label.
    draw.rectangle([10, 23, 15, 26], fill=(226, 130, 44, 255))
    draw.point((12, 24), fill=(60, 40, 24, 255))
    draw.point((13, 25), fill=(60, 40, 24, 255))
    # Handle.
    draw.line([(11, 13), (13, 9)], fill=rgba(CASE[4]))
    draw.line([(13, 9), (20, 9)], fill=rgba(CASE[4]))
    draw.line([(20, 9), (21, 13)], fill=rgba(CASE[4]))
    # Two reagent tubes standing beside it.
    for x, colour in ((24, (120, 196, 150)), (27, (214, 120, 150))):
        draw.line([(x, 3), (x, 9)], fill=(214, 232, 240, 255))
        draw.line([(x + 1, 3), (x + 1, 9)], fill=(168, 198, 214, 255))
        draw.line([(x, 6), (x, 9)], fill=rgba(colour))
        draw.line([(x + 1, 6), (x + 1, 9)], fill=rgba([int(c * 0.72) for c in colour]))
        draw.line([(x - 1, 3), (x + 2, 3)], fill=rgba(STEEL[2]))
    return outline(image)


def icon_analyzer():
    """A bench instrument: cabinet, window, dial, lamp and a sample drawer."""
    image = blank()
    draw = ImageDraw.Draw(image)
    draw.polygon([(2, 10), (21, 10), (21, 28), (2, 28)], fill=rgba(CREAM[1]))
    draw.polygon([(2, 10), (9, 4), (29, 4), (21, 10)], fill=rgba(CREAM[0]))
    draw.polygon([(21, 10), (29, 4), (29, 21), (21, 28)], fill=rgba(CREAM[3]))
    draw.line([(3, 28), (20, 28)], fill=rgba(CREAM[4]))
    draw.line([(2, 25), (21, 25)], fill=rgba(CREAM[3]))
    # Vent slots on the side.
    for y in (11, 14, 17):
        draw.line([(23, y + 2), (27, y - 2)], fill=rgba(CREAM[4]))
    # The display window with a trace on it.
    draw.rectangle([4, 12, 13, 18], fill=(34, 52, 44, 255))
    draw.line([(5, 16), (7, 16)], fill=(110, 230, 140, 255))
    draw.line([(7, 16), (8, 13)], fill=(110, 230, 140, 255))
    draw.line([(8, 13), (9, 17)], fill=(110, 230, 140, 255))
    draw.line([(9, 17), (12, 15)], fill=(110, 230, 140, 255))
    # A dial and a lamp.
    draw.ellipse([15, 12, 19, 16], fill=rgba(STEEL[3]))
    draw.point((17, 13), fill=rgba(STEEL[0]))
    draw.point((17, 14), fill=rgba(STEEL[1]))
    draw.rectangle([15, 18, 16, 19], fill=(232, 80, 60, 255))
    draw.rectangle([18, 18, 19, 19], fill=(110, 230, 140, 255))
    # The sample drawer, a little open.
    draw.rectangle([4, 21, 18, 23], fill=rgba(STEEL[2]))
    draw.line([(4, 21), (18, 21)], fill=rgba(STEEL[0]))
    draw.line([(9, 22), (13, 22)], fill=rgba(STEEL[4]))
    # Feet.
    draw.rectangle([3, 29, 5, 29], fill=rgba(STEEL[4]))
    draw.rectangle([18, 29, 20, 29], fill=rgba(STEEL[4]))
    return outline(image)


# ---------------------------------------------------------------- skill books

NAVY = [(150, 170, 206), (98, 120, 166), (64, 84, 128), (42, 56, 92), (28, 36, 62)]
OXBLOOD = [(214, 132, 120), (170, 82, 72), (128, 50, 46), (92, 32, 32), (60, 22, 22)]

# One cover per volume, I to V: olive, navy, brown, oxblood, steel.
BOOK_COVERS = [OLIVE, NAVY, WOOD, OXBLOOD, STEEL]


def icon_book(volume):
    """A closed hardback standing a little turned: spine on the left, the page
    block showing at the right and the foot, a cartridge stamped on the cover
    and one brass band on the spine per volume."""
    cover = BOOK_COVERS[volume - 1]
    image = blank()
    draw = ImageDraw.Draw(image)
    # The page block behind the cover.
    draw.polygon([(10, 5), (26, 4), (27, 27), (11, 29)], fill=rgba(CREAM[1]))
    for y in (8, 12, 16, 20, 24):
        draw.line([(25, y), (26, y)], fill=rgba(CREAM[3]))
    draw.line([(12, 28), (26, 26)], fill=rgba(CREAM[3]))
    # The cover and the spine.
    draw.polygon([(8, 3), (24, 2), (25, 25), (9, 27)], fill=rgba(cover[2]))
    draw.polygon([(4, 5), (8, 3), (9, 27), (5, 28)], fill=rgba(cover[3]))
    draw.line([(9, 4), (23, 3)], fill=rgba(cover[1]))
    draw.line([(9, 4), (10, 25)], fill=rgba(cover[1]))
    draw.line([(10, 26), (24, 24)], fill=rgba(cover[4]))
    draw.line([(5, 6), (5, 27)], fill=rgba(cover[2]))
    # A title plate.
    draw.polygon([(12, 6), (21, 5), (21, 8), (12, 9)], fill=rgba(CREAM[0]))
    draw.line([(13, 7), (19, 6)], fill=rgba(CREAM[3]))
    # The stamped cartridge: brass case, copper bullet.
    draw.rectangle([15, 15, 18, 22], fill=rgba(BRASS[1]))
    draw.line([(15, 15), (15, 22)], fill=rgba(BRASS[0]))
    draw.line([(18, 15), (18, 22)], fill=rgba(BRASS[3]))
    draw.line([(14, 22), (19, 22)], fill=rgba(BRASS[2]))
    draw.polygon([(15, 14), (16, 11), (17, 11), (18, 14)], fill=rgba(COPPER[1]))
    draw.point((16, 12), fill=rgba(COPPER[0]))
    # The volume bands on the spine.
    for band in range(volume):
        y = 9 + band * 3
        draw.line([(5, y + 1), (7, y)], fill=rgba(BRASS[1]))
        draw.point((6, y + 1), fill=rgba(BRASS[0]))
    return outline(image)


# ---------------------------------------------------------------- the press

def icon_press():
    """The reloading press, small: base, column, ram, die and the long lever.

    48 x 48, the size of vanilla's Build_ icons; drawn on a 16-unit grid of three pixels.
    """
    image = blank(48)
    draw = ImageDraw.Draw(image)

    def p(*points):
        return [(int(x * 1.5), int(y * 1.5)) for x, y in points]

    def rect(x0, y0, x1, y1, colour):
        draw.rectangle([int(x0 * 1.5), int(y0 * 1.5), int(x1 * 1.5 + 0.5), int(y1 * 1.5 + 0.5)], fill=rgba(colour))

    def post(x0, x1, y0, y1, ramp, bands):
        column(draw, int(x0 * 1.5), int(x1 * 1.5 + 0.5), int(y0 * 1.5), int(y1 * 1.5 + 0.5), ramp, bands)

    # A slab of bench.
    draw.polygon(p((2, 25), (10, 21), (30, 21), (22, 25)), fill=rgba(WOOD[1]))
    draw.polygon(p((2, 25), (22, 25), (22, 29), (2, 29)), fill=rgba(WOOD[2]))
    draw.polygon(p((22, 25), (30, 21), (30, 25), (22, 29)), fill=rgba(WOOD[3]))
    draw.line(p((3, 25), (21, 25)), fill=rgba(WOOD[0]))
    draw.line(p((4, 27), (12, 27)), fill=rgba(WOOD[3]))
    draw.line(p((14, 28), (20, 28)), fill=rgba(WOOD[3]))
    # The cast frame: foot, two posts, the head.
    rect(11, 21, 22, 23, STEEL[3])
    draw.line(p((11, 21), (22.5, 21)), fill=rgba(STEEL[1]))
    post(12, 13, 8, 20, STEEL, [1, 2, 3])
    post(20, 21, 8, 20, STEEL, [2, 3, 4])
    rect(11, 5, 22, 8, STEEL[3])
    draw.line(p((11, 5), (22.5, 5)), fill=rgba(STEEL[1]))
    draw.line(p((11, 8.7), (22.5, 8.7)), fill=rgba(STEEL[4]))
    # The die in the head and the ram with a case on it.
    post(15, 18, 2, 10, STEEL, [1, 0, 0, 1, 2, 3])
    rect(14, 3.4, 19, 4, BRASS[1])
    post(16, 17, 16, 20, STEEL, [1, 2, 3])
    post(15, 18, 12, 15, BRASS, [1, 0, 1, 2, 3, 4])
    draw.line(p((15, 12), (18.7, 12)), fill=rgba(HOLE))
    # The lever, up and to the left, with its ball.
    draw.line(p((14, 19), (5, 6)), fill=rgba(STEEL[1]), width=3)
    draw.line(p((15, 19), (6, 6)), fill=rgba(STEEL[3]))
    draw.ellipse([3, 3, 11, 11], fill=rgba((54, 50, 48)))
    draw.ellipse([5, 5, 7, 7], fill=rgba((126, 120, 116)))
    return outline(image)


# ---------------------------------------------------------------- output

# name of the icon (what an item's `Icon =` says, without `Item_`), where it goes, how it is drawn.
ICONS = [
    ("AmmoMakingZincOre", MAIN, "Item_", icon_zinc_ore),
    ("AmmoMakingZincScrap", MAIN, "Item_", icon_zinc_scrap),
    ("AmmoMakingZincIngot", MAIN, "Item_", icon_zinc_ingot),
    ("AmmoMakingBrassSheet", MAIN, "Item_", icon_brass_sheet),
    ("AmmoMakingCaseCup", MAIN, "Item_", icon_case_cup),
    ("AmmoMakingPrimerSmallPistol", MAIN, "Item_", lambda: icon_primer(False, False)),
    ("AmmoMakingPrimerLargePistol", MAIN, "Item_", lambda: icon_primer(True, False)),
    ("AmmoMakingPrimerSmallRifle", MAIN, "Item_", lambda: icon_primer(False, True)),
    ("AmmoMakingPrimerLargeRifle", MAIN, "Item_", lambda: icon_primer(True, True)),
    ("AmmoMakingDieSet", MAIN, "Item_", icon_die_set),
    ("AmmoMakingCasePistol", MAIN, "Item_", icon_case_pistol),
    ("AmmoMakingCaseMagnum", MAIN, "Item_", icon_case_magnum),
    ("AmmoMakingCaseRifle", MAIN, "Item_", icon_case_rifle),
    ("AmmoMakingHull", MAIN, "Item_", icon_hull),
    ("AmmoMakingBulletPistol", MAIN, "Item_", icon_bullet_pistol),
    ("AmmoMakingBulletRifle", MAIN, "Item_", icon_bullet_rifle),
    ("AmmoMakingShot", MAIN, "Item_", icon_shot),
    ("AmmoMakingSample", MAIN, "Item_", icon_sample),
    ("AmmoMakingFieldKit", MAIN, "Item_", icon_field_kit),
    ("AmmoMakingAdvancedKit", MAIN, "Item_", icon_advanced_kit),
    ("AmmoMakingAnalyzer", MAIN, "Item_", icon_analyzer),
    ("AmmoMakingBook1", MAIN, "Item_", lambda: icon_book(1)),
    ("AmmoMakingBook2", MAIN, "Item_", lambda: icon_book(2)),
    ("AmmoMakingBook3", MAIN, "Item_", lambda: icon_book(3)),
    ("AmmoMakingBook4", MAIN, "Item_", lambda: icon_book(4)),
    ("AmmoMakingBook5", MAIN, "Item_", lambda: icon_book(5)),
    ("AmmoMakingSpentCasePistol", SPENT, "Item_", lambda: icon_case_pistol(True)),
    ("AmmoMakingSpentCaseMagnum", SPENT, "Item_", lambda: icon_case_magnum(True)),
    ("AmmoMakingSpentCaseRifle", SPENT, "Item_", lambda: icon_case_rifle(True)),
    ("AmmoMakingSpentHull", SPENT, "Item_", lambda: icon_hull(True)),
    ("AmmoMakingReloadingPress", PRESS, "Build_", icon_press),
]


def encode(image):
    """PNG bytes with nothing but the pixels: no time stamp, no text chunk."""
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def preview(drawn):
    scale, columns, gap = 8, 7, 8
    rows = (len(drawn) + columns - 1) // columns
    cell = SIZE * scale + gap
    sheet = Image.new("RGBA", (columns * cell + gap, rows * cell + gap), (112, 116, 132, 255))
    for index, image in enumerate(drawn):
        zoom = scale * SIZE // image.size[0]
        big = image.resize((image.size[0] * zoom, image.size[1] * zoom), Image.NEAREST)
        sheet.alpha_composite(big, (gap + (index % columns) * cell, gap + (index // columns) * cell))
    return sheet


def main(argv):
    check = "--check" in argv
    problems = []
    drawn = []
    for name, folder, prefix, draw in ICONS:
        image = draw()
        assert image.size in ((SIZE, SIZE), (48, 48)), name
        drawn.append(image)
        data = encode(image)
        path = os.path.join(REPO, folder, prefix + name + ".png")
        if check:
            if not os.path.isfile(path) or open(path, "rb").read() != data:
                problems.append(folder + prefix + name + ".png")
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(data)
    if check:
        if problems:
            print("icons differ from a fresh drawing (run art/icons/make_icons.py):")
            for problem in problems:
                print("  " + problem)
            return 1
        print("icons: %d files equal a fresh drawing" % len(ICONS))
        return 0
    with open(os.path.join(HERE, "preview.png"), "wb") as handle:
        handle.write(encode(preview(drawn)))
    print("drew %d icons" % len(ICONS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
