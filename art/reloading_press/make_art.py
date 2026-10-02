"""Ammo Making - draws the placeholder sprites of the reloading press.

    python art/reloading_press/make_art.py

Original programmer art, drawn from the shapes below: a single-stage bench
press on a short wooden stand, in the game's 2:1 isometric projection, one
128 x 256 frame per face (docs/RELOADING_PRESS_DESIGN.md, 7.1). It copies no
vanilla or third-party pixel. It is a placeholder: good enough to tell where
the station stands and which way it faces, not meant as final art.

Writes src/ammomaking_press_01_0.png (facing south) and _1.png (facing
east). The drawing is deterministic: the same script gives the same pixels.
"""

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = (128, 256)

# The floor diamond of a tile in a 128 x 256 frame: its top corner is at
# (64, 192) and it is 128 wide and 64 high. A point of the tile is (u, v),
# each from 0 to 1, with u running to the lower right (east) and v to the
# lower left (south); h is height above the floor in pixels.
def project(u, v, h=0):
    return (64 + (u - v) * 64, 192 + (u + v) * 32 - h)


OUTLINE = (28, 24, 22, 255)


def shade(colour, factor):
    return tuple(max(0, min(255, int(round(channel * factor)))) for channel in colour[:3]) + (255,)


def box(draw, u0, v0, u1, v1, bottom, top, colour):
    """A box standing on the tile: its two visible sides and its top."""
    # The side facing south (the viewer's lower left) and the one facing east.
    south = [project(u0, v1, bottom), project(u1, v1, bottom), project(u1, v1, top), project(u0, v1, top)]
    east = [project(u1, v0, bottom), project(u1, v1, bottom), project(u1, v1, top), project(u1, v0, top)]
    lid = [project(u0, v0, top), project(u1, v0, top), project(u1, v1, top), project(u0, v1, top)]
    draw.polygon(south, fill=shade(colour, 0.78), outline=OUTLINE)
    draw.polygon(east, fill=shade(colour, 0.58), outline=OUTLINE)
    draw.polygon(lid, fill=shade(colour, 1.0), outline=OUTLINE)


def press(facing):
    image = Image.new("RGBA", FRAME, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    wood = (150, 108, 66)
    iron = (96, 100, 106)
    steel = (150, 154, 160)
    brass = (190, 150, 60)

    # A soft shadow on the floor.
    shadow = [project(0.14, 0.14), project(0.86, 0.14), project(0.86, 0.86), project(0.14, 0.86)]
    draw.polygon(shadow, fill=(0, 0, 0, 60))

    # The stand: four legs and a top.
    for u, v in ((0.2, 0.2), (0.72, 0.2), (0.2, 0.72), (0.72, 0.72)):
        box(draw, u, v, u + 0.08, v + 0.08, 0, 46, wood)
    box(draw, 0.16, 0.16, 0.84, 0.84, 46, 54, wood)

    # The press: a base plate, two columns, a head, the ram between them.
    box(draw, 0.36, 0.36, 0.64, 0.64, 54, 60, iron)
    if facing == "S":
        columns = ((0.38, 0.46), (0.56, 0.46))
    else:
        columns = ((0.46, 0.38), (0.46, 0.56))
    for u, v in columns:
        box(draw, u, v, u + 0.06, v + 0.06, 60, 112, steel)
    box(draw, 0.47, 0.47, 0.53, 0.53, 60, 84, brass)      # the die and case holder
    box(draw, 0.36, 0.42, 0.64, 0.58, 112, 122, iron) if facing == "S" else box(draw, 0.42, 0.36, 0.58, 0.64, 112, 122, iron)
    box(draw, 0.47, 0.47, 0.53, 0.53, 96, 112, steel)     # the ram

    # The lever: from the head, up and out towards the side the press faces.
    pivot = project(0.5, 0.5, 122)
    if facing == "S":
        tip = project(0.5, 1.02, 168)
    else:
        tip = project(1.02, 0.5, 168)
    draw.line([pivot, tip], fill=OUTLINE, width=5)
    draw.line([pivot, tip], fill=steel + (255,), width=3)
    draw.ellipse((tip[0] - 5, tip[1] - 5, tip[0] + 5, tip[1] + 5), fill=(40, 40, 44, 255), outline=OUTLINE)
    return image


def main():
    out = os.path.join(HERE, "src")
    os.makedirs(out, exist_ok=True)
    for index, facing in enumerate(("S", "E")):
        path = os.path.join(out, "ammomaking_press_01_%d.png" % index)
        press(facing).save(path, format="PNG", optimize=False, compress_level=9)
        print("Wrote " + os.path.relpath(path, os.path.dirname(os.path.dirname(HERE))).replace("\\", "/"))


if __name__ == "__main__":
    main()
