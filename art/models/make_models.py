"""Ammo Making - builds the world models of the items that had none.

    python art/models/make_models.py            write them
    python art/models/make_models.py --check    fail when a written file differs
    python art/models/make_models.py --preview <png>   draw all six, for a look

Generated art in three dimensions: each model is built from bevelled boxes,
smooth cylinders and cones, rings, beams and a rock, with a painted texture
atlas (canvas weave, brushed metal with screws, wood grain, leather with
stitching, the analyzer's front panel with its window, dial, buttons and
vents). It is written as a DirectX .X text file (one of the mesh formats the
42.21 jar loads: ModelFileExtensionType X, Fbx, glTF, Txt) with its texture
beside it, and a model script that names both. It copies no vanilla or
third-party geometry or pixel. The textures carry no lettering, so a
texture read upside down still looks right. Final models drawn by hand
replace these under the same names (docs/ART_HANDOFF.md).

The conventions are vanilla's own, read from media/models_X/CanClosed.X (the
closed tin can, a WorldStaticModel at scale 1): one frame with the identity
matrix, Y up, the origin at the middle of the bottom, metres (the can is
0.063 x 0.088), and triangles wound so that (v1 - v0) x (v2 - v0) points
out of the model, as its normals do. Texture v = 0 is the top row of the
image (DirectX).

Writes, per model, into the mod that ships the item:
  <mod>/42/media/models_X/WorldItems/<name>.X
  <mod>/42/media/textures/WorldItems/<name>.png
and one generated script per mod with the model blocks:
  <mod>/42/media/scripts/<script>
An item names its model as WorldStaticModel = AmmoMaking.<name>, the module
and the name, as other mods name theirs (e.g. MFSEject.9x19_Casing).

Budget: about 300 triangles a model (vanilla's world items run 48 to 160;
these are 172 to 268). Round parts get twelve sides and smooth normals,
caps only where they are seen, bevels only on the main bodies.

Everything is deterministic: the same script gives the same bytes.

REQUIRES FUTURE IN-GAME VERIFICATION: that each model shows on the ground,
the right way up, at about the size here, and turns with the item.
"""

import io
import math
import os
import random
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

MAIN = "mod/AmmoMaking"
SPENT = "mod/AmmoMakingSpentCases"
SCRIPTS = {MAIN: "AC_Models.txt", SPENT: "AC_SpentCaseModels.txt"}

ATLAS = 256


# ---------------------------------------------------------------- vectors

def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def basis(axis):
    """Two unit vectors at right angles to axis and to each other."""
    axis = unit(axis)
    helper = (0, 1, 0) if abs(axis[1]) < 0.9 else (1, 0, 0)
    u = unit(cross(helper, axis))
    return u, cross(axis, u)


# ---------------------------------------------------------------- texture

def clamp(c):
    return max(0, min(255, int(round(c))))


def shade(colour, f):
    return tuple(clamp(c * f) for c in colour[:3])


class Atlas:
    """A texture of painted regions, packed in shelves."""

    def __init__(self, seed):
        self.image = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 255))
        self.random = random.Random(seed)
        self.x = self.y = self.row = 0

    def region(self, w, h, painter, *args):
        if self.x + w > ATLAS:
            self.x, self.y, self.row = 0, self.y + self.row, 0
        box = (self.x, self.y, self.x + w, self.y + h)
        assert box[3] <= ATLAS, "atlas full"
        self.x += w
        self.row = max(self.row, h)
        painter(self, box, *args)
        # A half-pixel inset so filtering never reaches a neighbour.
        return ((box[0] + 1) / ATLAS, (box[1] + 1) / ATLAS, (box[2] - 1) / ATLAS, (box[3] - 1) / ATLAS)

    # -- painters ---------------------------------------------------------

    def noise(self, box, base, amount):
        px = self.image.load()
        r = self.random
        for y in range(box[1], box[3]):
            for x in range(box[0], box[2]):
                f = 1 + (r.random() - 0.5) * amount
                px[x, y] = shade(base, f) + (255,)

    def edges(self, box, f=0.75, width=1):
        draw = ImageDraw.Draw(self.image)
        for i in range(width):
            draw.rectangle((box[0] + i, box[1] + i, box[2] - 1 - i, box[3] - 1 - i), outline=shade(self.pixel(box[0] + width, box[1] + width), f))

    def pixel(self, x, y):
        return self.image.getpixel((x, y))[:3]

    def canvas(self, box, base, seams=True):
        self.noise(box, base, 0.10)
        px = self.image.load()
        for y in range(box[1], box[3]):
            for x in range(box[0], box[2]):
                if (x + y) % 3 == 0:
                    px[x, y] = shade(px[x, y], 1.08) + (255,)
                elif (x - y) % 4 == 0:
                    px[x, y] = shade(px[x, y], 0.92) + (255,)
        if seams:
            draw = ImageDraw.Draw(self.image)
            dark = shade(base, 0.6)
            for x in range(box[0] + 3, box[2] - 3, 4):
                draw.line((x, box[1] + 3, x + 1, box[1] + 3), fill=dark)
                draw.line((x, box[3] - 4, x + 1, box[3] - 4), fill=dark)

    def leather(self, box, base):
        self.noise(box, base, 0.14)
        draw = ImageDraw.Draw(self.image)
        light = shade(base, 1.5)
        for x in range(box[0] + 2, box[2] - 2, 3):
            draw.point((x, box[1] + 2), fill=light)
            draw.point((x, box[3] - 3), fill=light)

    def metal(self, box, base, screws=False, brushed=True):
        px = self.image.load()
        r = self.random
        for y in range(box[1], box[3]):
            row = 1 + (r.random() - 0.5) * (0.10 if brushed else 0.02)
            for x in range(box[0], box[2]):
                px[x, y] = shade(base, row * (1 + (r.random() - 0.5) * 0.05)) + (255,)
        self.edges(box, 0.7)
        if screws:
            draw = ImageDraw.Draw(self.image)
            for cx, cy in ((box[0] + 5, box[1] + 5), (box[2] - 6, box[1] + 5), (box[0] + 5, box[3] - 6), (box[2] - 6, box[3] - 6)):
                draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=shade(base, 0.55))
                draw.point((cx - 1, cy - 1), fill=shade(base, 1.35))

    def ribbed(self, box, base):
        self.metal(box, base, brushed=False)
        draw = ImageDraw.Draw(self.image)
        for y in range(box[1] + 6, box[3] - 4, 6):
            draw.line((box[0] + 3, y, box[2] - 4, y), fill=shade(base, 0.78))
            draw.line((box[0] + 3, y + 1, box[2] - 4, y + 1), fill=shade(base, 1.18))

    def grille(self, box, base):
        self.metal(box, base)
        draw = ImageDraw.Draw(self.image)
        for y in range(box[1] + 8, box[3] - 8, 5):
            draw.rectangle((box[0] + 10, y, box[2] - 11, y + 2), fill=shade(base, 0.35))

    def wood(self, box, base):
        px = self.image.load()
        r = self.random
        phase = r.random() * 6
        h = box[3] - box[1]
        for y in range(box[1], box[3]):
            for x in range(box[0], box[2]):
                ring = math.sin((y - box[1]) / max(h, 1) * 18 + math.sin((x - box[0]) * 0.09 + phase) * 1.6)
                f = 1 + ring * 0.12 + (r.random() - 0.5) * 0.08
                px[x, y] = shade(base, f) + (255,)

    def drum(self, box, base):
        self.metal(box, base)
        draw = ImageDraw.Draw(self.image)
        w = box[2] - box[0]
        for i in (1, 2, 3):
            x = box[0] + i * w // 4
            draw.line((x, box[1], x, box[3] - 1), fill=shade(base, 0.7))
            for y in range(box[1] + 4, box[3] - 2, 8):
                draw.point((x + 2, y), fill=shade(base, 0.5))

    def rolled(self, box, base):
        """The end of a canvas roll: rings."""
        self.noise(box, shade(base, 0.6), 0.08)
        draw = ImageDraw.Draw(self.image)
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        for i, radius in enumerate(range(4, (box[2] - box[0]) // 2, 4)):
            draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=shade(base, 0.85 + 0.15 * (i % 2)))

    def pockets(self, box, base):
        self.canvas(box, base)
        draw = ImageDraw.Draw(self.image)
        w = box[2] - box[0]
        for i in range(5):
            x0 = box[0] + 6 + i * (w - 12) // 5
            x1 = x0 + (w - 12) // 5 - 3
            draw.rectangle((x0, box[1] + 18, x1, box[3] - 8), outline=shade(base, 0.6))
            draw.rectangle((x0 + 3, box[1] + 6, x1 - 3, box[1] + 20), fill=(150, 154, 160) if i % 2 else (120, 86, 52))

    def screen(self, box, base):
        draw = ImageDraw.Draw(self.image)
        h = box[3] - box[1]
        for y in range(box[1], box[3]):
            f = 0.6 + 0.6 * (y - box[1]) / max(h, 1)
            draw.line((box[0], y, box[2] - 1, y), fill=shade(base, f))
        draw.line((box[0] + 4, box[3] - 6, box[2] - 10, box[1] + 4), fill=shade(base, 1.9))

    def front_panel(self, box, base):
        """The analyzer's face: window, dial, buttons, vents."""
        self.metal(box, base, screws=True)
        draw = ImageDraw.Draw(self.image)
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        # window
        wx0, wy0, wx1, wy1 = x0 + w * 0.08, y0 + h * 0.12, x0 + w * 0.56, y0 + h * 0.52
        draw.rectangle((wx0 - 2, wy0 - 2, wx1 + 2, wy1 + 2), fill=shade(base, 0.5))
        self.screen((int(wx0), int(wy0), int(wx1), int(wy1)), (40, 70, 84))
        # dial with ticks and a needle
        cx, cy, radius = x0 + w * 0.78, y0 + h * 0.32, min(w, h) * 0.15
        draw.ellipse((cx - radius - 2, cy - radius - 2, cx + radius + 2, cy + radius + 2), fill=shade(base, 0.45))
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(226, 218, 190))
        for k in range(9):
            a = math.radians(210 - k * 30)
            draw.line((cx + math.cos(a) * radius * 0.75, cy - math.sin(a) * radius * 0.75,
                       cx + math.cos(a) * radius * 0.95, cy - math.sin(a) * radius * 0.95), fill=(40, 40, 40))
        a = math.radians(130)
        draw.line((cx, cy, cx + math.cos(a) * radius * 0.8, cy - math.sin(a) * radius * 0.8), fill=(170, 40, 30), width=2)
        # buttons
        for i, colour in enumerate(((60, 160, 70), (210, 170, 40), (190, 50, 40))):
            bx = x0 + w * (0.64 + i * 0.1)
            draw.ellipse((bx - 5, y0 + h * 0.62 - 5, bx + 5, y0 + h * 0.62 + 5), fill=shade(base, 0.4))
            draw.ellipse((bx - 4, y0 + h * 0.62 - 4, bx + 4, y0 + h * 0.62 + 4), fill=colour)
            draw.point((bx - 2, y0 + h * 0.62 - 2), fill=shade(colour, 1.6))
        # vents
        for k in range(6):
            vx = x0 + w * 0.08 + k * w * 0.075
            draw.rectangle((vx, y0 + h * 0.66, vx + w * 0.04, y0 + h * 0.88), fill=shade(base, 0.35))
        # a stripe
        draw.rectangle((x0 + 3, y0 + h * 0.93, x1 - 4, y0 + h * 0.96), fill=(160, 60, 40))

    def tag(self, box, base):
        self.noise(box, base, 0.05)
        draw = ImageDraw.Draw(self.image)
        x0, y0, x1, y1 = box
        draw.rectangle((x0, y0, x1 - 1, y0 + (y1 - y0) // 4), fill=(180, 50, 40))
        for y in range(y0 + (y1 - y0) // 3, y1 - 3, 5):
            draw.line((x0 + 4, y, x1 - 5, y), fill=shade(base, 0.6))
        draw.ellipse((x0 + 3, y0 + 2, x0 + 7, y0 + 6), fill=shade(base, 0.4))

    def mesh(self, box, base):
        self.canvas(box, base, seams=False)
        draw = ImageDraw.Draw(self.image)
        for x in range(box[0], box[2], 4):
            draw.line((x, box[1], x, box[3] - 1), fill=shade(base, 0.7))
        for y in range(box[1], box[3], 4):
            draw.line((box[0], y, box[2] - 1, y), fill=shade(base, 0.7))

    def flat(self, box, base, amount=0.06):
        self.noise(box, base, amount)

    def brass(self, box, base):
        draw = ImageDraw.Draw(self.image)
        w = box[2] - box[0]
        for x in range(box[0], box[2]):
            f = 0.75 + 0.6 * math.sin(math.pi * (x - box[0]) / max(w, 1))
            draw.line((x, box[1], x, box[3] - 1), fill=shade(base, f))

    def pile(self, box, base):
        """Spent cases heaped in a bag: brass ends and sides on a dark ground."""
        self.noise(box, shade(base, 0.35), 0.2)
        draw = ImageDraw.Draw(self.image)
        r = self.random
        for _ in range((box[2] - box[0]) * (box[3] - box[1]) // 40):
            x, y = r.randrange(box[0] + 2, box[2] - 4), r.randrange(box[1] + 2, box[3] - 4)
            f = 0.7 + r.random() * 0.6
            if r.random() < 0.5:
                draw.ellipse((x, y, x + 3, y + 3), fill=shade(base, f))
                draw.point((x + 1, y + 1), fill=shade(base, 0.45))
            else:
                draw.rectangle((x, y, x + 4, y + 1), fill=shade(base, f))

    def rock(self, box, base):
        self.noise(box, base, 0.35)
        px = self.image.load()
        r = self.random
        for _ in range((box[2] - box[0]) * (box[3] - box[1]) // 12):
            x, y = r.randrange(box[0], box[2]), r.randrange(box[1], box[3])
            px[x, y] = shade((190, 120, 70) if r.random() < 0.3 else base, 0.6 + r.random() * 0.8) + (255,)


# ---------------------------------------------------------------- geometry

class Model:
    def __init__(self, atlas):
        self.atlas = atlas
        self.corners = []  # (position, normal, uv) * 3 per triangle

    def triangle(self, points, normals, uvs):
        self.corners.append(tuple(zip(points, normals, uvs)))

    def polygon(self, points, region, inside, normal=None):
        """A flat convex polygon, wound and lit outwards from inside."""
        n = unit(cross(sub(points[1], points[0]), sub(points[2], points[0])))
        centre = mul(sum_points(points), 1.0 / len(points))
        if dot(n, sub(centre, inside)) < 0:
            points = points[::-1]
            n = mul(n, -1)
        n = normal or n
        uvs = planar_uvs(points, n, region)
        for i in range(1, len(points) - 1):
            self.triangle((points[0], points[i], points[i + 1]), (n, n, n), (uvs[0], uvs[i], uvs[i + 1]))

    def box(self, centre, size, regions, bevel=0.0):
        """A box, its edges bevelled by bevel. regions: one region, or a dict
        of side/top/bottom/front/back/bevel (front is +z)."""
        if not isinstance(regions, dict):
            regions = {"side": regions}
        get = lambda key: regions.get(key) or regions.get("side")
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        r = min(bevel, hx * 0.9, hy * 0.9, hz * 0.9)
        cx, cy, cz = centre
        P = lambda x, y, z: (cx + x, cy + y, cz + z)
        faces = {
            (1, 0, 0): ("side", [P(hx, sy * (hy - r), sz * (hz - r)) for sy, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
            (-1, 0, 0): ("side", [P(-hx, sy * (hy - r), sz * (hz - r)) for sy, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
            (0, 1, 0): ("top", [P(sx * (hx - r), hy, sz * (hz - r)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
            (0, -1, 0): ("bottom", [P(sx * (hx - r), -hy, sz * (hz - r)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
            (0, 0, 1): ("front", [P(sx * (hx - r), sy * (hy - r), hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
            (0, 0, -1): ("back", [P(sx * (hx - r), sy * (hy - r), -hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]),
        }
        for _, (key, points) in faces.items():
            self.polygon(points, get(key), centre)
        if r <= 0:
            return
        bev = get("bevel")
        for sx in (-1, 1):
            for sy in (-1, 1):  # edges along z
                self.polygon([P(sx * hx, sy * (hy - r), -(hz - r)), P(sx * hx, sy * (hy - r), hz - r),
                              P(sx * (hx - r), sy * hy, hz - r), P(sx * (hx - r), sy * hy, -(hz - r))], bev, centre)
            for sz in (-1, 1):  # edges along y
                self.polygon([P(sx * hx, -(hy - r), sz * (hz - r)), P(sx * hx, hy - r, sz * (hz - r)),
                              P(sx * (hx - r), hy - r, sz * hz), P(sx * (hx - r), -(hy - r), sz * hz)], bev, centre)
        for sy in (-1, 1):
            for sz in (-1, 1):  # edges along x
                self.polygon([P(-(hx - r), sy * hy, sz * (hz - r)), P(hx - r, sy * hy, sz * (hz - r)),
                              P(hx - r, sy * (hy - r), sz * hz), P(-(hx - r), sy * (hy - r), sz * hz)], bev, centre)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    self.polygon([P(sx * hx, sy * (hy - r), sz * (hz - r)), P(sx * (hx - r), sy * hy, sz * (hz - r)),
                                  P(sx * (hx - r), sy * (hy - r), sz * hz)], bev, centre)

    def cone(self, p0, p1, r0, r1, side, cap0=None, cap1=None, segments=12, smooth=True, turn=0.0):
        """A cylinder or cone from p0 (radius r0) to p1 (radius r1). A cap
        region left out leaves that end open; side None leaves out the
        wall (a disc). Smooth normals let twelve sides read as round. A
        cap costs segments - 2 triangles, the wall 2 * segments."""
        axis = sub(p1, p0)
        length = math.sqrt(dot(axis, axis))
        a = unit(axis)
        u, w = basis(a)
        ring = lambda p, radius, k: add(p, add(mul(u, radius * math.cos(turn + 2 * math.pi * k / segments)),
                                               mul(w, radius * math.sin(turn + 2 * math.pi * k / segments))))
        def radial(k):
            ang = turn + 2 * math.pi * k / segments
            out = add(mul(u, math.cos(ang)), mul(w, math.sin(ang)))
            return unit(add(mul(out, length), mul(a, r0 - r1)))
        top_is_p1 = p1[1] >= p0[1]
        x0, y0, x1, y1 = side or (0, 0, 0, 0)
        for k in range(segments if side else 0):
            q = [ring(p0, r0, k), ring(p0, r0, k + 1), ring(p1, r1, k + 1), ring(p1, r1, k)]
            if smooth:
                ns = [radial(k), radial(k + 1), radial(k + 1), radial(k)]
            else:
                mid = unit(cross(sub(q[1], q[0]), sub(q[2], q[0])))
                ns = [mid] * 4
            ua, ub = x0 + (x1 - x0) * k / segments, x0 + (x1 - x0) * (k + 1) / segments
            v_p0, v_p1 = (y1, y0) if top_is_p1 else (y0, y1)
            uv = [(ua, v_p0), (ub, v_p0), (ub, v_p1), (ua, v_p1)]
            # outward winding: (q1 - q0) x (q2 - q0) along the radial
            n = cross(sub(q[1], q[0]), sub(q[2], q[0]))
            if dot(n, ns[0]) < 0:
                q, ns, uv = [q[1], q[0], q[3], q[2]], [ns[1], ns[0], ns[3], ns[2]], [uv[1], uv[0], uv[3], uv[2]]
            self.triangle((q[0], q[1], q[2]), (ns[0], ns[1], ns[2]), (uv[0], uv[1], uv[2]))
            self.triangle((q[0], q[2], q[3]), (ns[0], ns[2], ns[3]), (uv[0], uv[2], uv[3]))
        for p, radius, cap, direction in ((p0, r0, cap0, mul(a, -1)), (p1, r1, cap1, a)):
            if not cap or radius <= 0:
                continue
            cx0, cy0, cx1, cy1 = cap
            mid_uv = ((cx0 + cx1) / 2, (cy0 + cy1) / 2)
            disc = lambda k: (mid_uv[0] + math.cos(turn + 2 * math.pi * k / segments) * (cx1 - cx0) / 2,
                              mid_uv[1] + math.sin(turn + 2 * math.pi * k / segments) * (cy1 - cy0) / 2)
            # A fan from the first rim point: no centre vertex.
            for k in range(1, segments - 1):
                tri, uvs = [ring(p, radius, 0), ring(p, radius, k), ring(p, radius, k + 1)], [disc(0), disc(k), disc(k + 1)]
                if dot(cross(sub(tri[1], tri[0]), sub(tri[2], tri[0])), direction) < 0:
                    tri, uvs = [tri[0], tri[2], tri[1]], [uvs[0], uvs[2], uvs[1]]
                self.triangle(tuple(tri), (direction,) * 3, tuple(uvs))

    def beam(self, p0, p1, width, region, cap0=True, cap1=True):
        """A square beam from p0 to p1: 8 triangles, and 2 for each end left on."""
        self.cone(p0, p1, width / math.sqrt(2), width / math.sqrt(2), region, region if cap0 else None,
                  region if cap1 else None, segments=4, smooth=False, turn=math.pi / 4)

    def tube(self, points, radius, region, segments=6):
        """Round lengths from point to point, open-ended, overlapping at the bends."""
        for a, b in zip(points, points[1:]):
            self.cone(a, b, radius, radius, region, None, None, segments=segments)

    def ring(self, centre, axis, radius, thickness, region, segments=12, sides=4):
        """A torus round axis."""
        a = unit(axis)
        u, w = basis(a)
        x0, y0, x1, y1 = region
        def point(i, j):
            t, s = 2 * math.pi * i / segments, 2 * math.pi * j / sides
            out = add(mul(u, math.cos(t)), mul(w, math.sin(t)))
            n = add(mul(out, math.cos(s)), mul(a, math.sin(s)))
            return add(centre, add(mul(out, radius), mul(n, thickness))), n
        for i in range(segments):
            for j in range(sides):
                (pa, na), (pb, nb), (pc, nc), (pd, nd) = point(i, j), point(i + 1, j), point(i + 1, j + 1), point(i, j + 1)
                uv = [(x0 + (x1 - x0) * i / segments, y0 + (y1 - y0) * j / sides), (x0 + (x1 - x0) * (i + 1) / segments, y0 + (y1 - y0) * j / sides),
                      (x0 + (x1 - x0) * (i + 1) / segments, y0 + (y1 - y0) * (j + 1) / sides), (x0 + (x1 - x0) * i / segments, y0 + (y1 - y0) * (j + 1) / sides)]
                q, ns = [pa, pb, pc, pd], [na, nb, nc, nd]
                if dot(cross(sub(q[1], q[0]), sub(q[2], q[0])), na) < 0:
                    q, ns, uv = [q[1], q[0], q[3], q[2]], [ns[1], ns[0], ns[3], ns[2]], [uv[1], uv[0], uv[3], uv[2]]
                self.triangle((q[0], q[1], q[2]), (ns[0], ns[1], ns[2]), (uv[0], uv[1], uv[2]))
                self.triangle((q[0], q[2], q[3]), (ns[0], ns[2], ns[3]), (uv[0], uv[2], uv[3]))

    def sphere(self, centre, radius, region, level=0, jitter=0.0, seed=1, squash=(1, 1, 1)):
        """An icosphere, its points pushed in and out by jitter (a rock)."""
        t = (1 + math.sqrt(5)) / 2
        verts = [unit(v) for v in [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                                   (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]]
        faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
                 (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        for _ in range(level):
            cache, new = {}, []
            def middle(i, j):
                key = (min(i, j), max(i, j))
                if key not in cache:
                    verts.append(unit(mul(add(verts[i], verts[j]), 0.5)))
                    cache[key] = len(verts) - 1
                return cache[key]
            for a, b, c in faces:
                ab, bc, ca = middle(a, b), middle(b, c), middle(c, a)
                new += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            faces = new
        rnd = random.Random(seed)
        scale = [radius * (1 + (rnd.random() - 0.5) * jitter) for _ in verts]
        pts = [add(centre, (v[0] * s * squash[0], v[1] * s * squash[1], v[2] * s * squash[2])) for v, s in zip(verts, scale)]
        flat = jitter > 0
        x0, y0, x1, y1 = region
        for a, b, c in faces:
            tri = [pts[a], pts[b], pts[c]]
            n = unit(cross(sub(tri[1], tri[0]), sub(tri[2], tri[0])))
            if dot(n, sub(tri[0], centre)) < 0:
                tri, (a, b, c), n = [tri[0], tri[2], tri[1]], (a, c, b), mul(n, -1)
            ns = (n, n, n) if flat else (verts[a], verts[b], verts[c])
            uvs = tuple((x0 + (x1 - x0) * (0.5 + 0.5 * math.atan2(verts[i][2], verts[i][0]) / math.pi),
                         y0 + (y1 - y0) * (0.5 - 0.5 * verts[i][1])) for i in (a, b, c))
            self.triangle(tuple(tri), ns, uvs)


def sum_points(points):
    s = (0.0, 0.0, 0.0)
    for p in points:
        s = add(s, p)
    return s


def planar_uvs(points, n, region):
    """Projects a flat polygon onto the region: up is +y on a wall, -z on a floor."""
    if abs(n[1]) > 0.7:
        right, up = (1, 0, 0), (0, 0, -1 if n[1] > 0 else 1)
    else:
        up = (0, 1, 0)
        right = unit(cross(up, n))
        up = unit(cross(n, right))
    s = [dot(p, right) for p in points]
    t = [dot(p, up) for p in points]
    s0, s1, t0, t1 = min(s), max(s), min(t), max(t)
    x0, y0, x1, y1 = region
    return [(x0 + (x1 - x0) * (si - s0) / ((s1 - s0) or 1), y1 - (y1 - y0) * (ti - t0) / ((t1 - t0) or 1)) for si, ti in zip(s, t)]


# ---------------------------------------------------------------- colours

CANVAS = (180, 160, 118)
CANVAS_DARK = (128, 110, 78)
OLIVE = (108, 116, 72)
LEATHER = (112, 70, 40)
CASE_GREY = (120, 128, 136)
CASE_DARK = (64, 70, 80)
STEEL = (172, 178, 184)
STEEL_DARK = (98, 104, 112)
IRON = (66, 66, 70)
WOOD = (150, 108, 66)
BRASS = (214, 176, 84)
GLASS = (54, 84, 100)
RUBBER = (34, 34, 36)
PAPER = (222, 212, 184)
TWINE = (170, 140, 90)
ROCK = (122, 116, 106)
NET = (150, 140, 110)


# ---------------------------------------------------------------- the models

def sample():
    """A canvas sample bag tied at the neck with twine, a labelled tag, a rock in its mouth."""
    t = Atlas(11)
    canvas = t.region(128, 64, Atlas.canvas, CANVAS)
    dark = t.region(64, 64, Atlas.canvas, CANVAS_DARK, False)
    twine = t.region(64, 32, Atlas.flat, TWINE, 0.2)
    tag = t.region(64, 48, Atlas.tag, PAPER)
    rock = t.region(64, 64, Atlas.rock, ROCK)
    m = Model(t)
    m.cone((0, 0.0, 0), (0, 0.010, 0), 0.032, 0.042, canvas, dark, None, segments=16)
    m.cone((0, 0.010, 0), (0, 0.055, 0), 0.042, 0.038, canvas, segments=16)
    m.cone((0, 0.055, 0), (0, 0.072, 0), 0.038, 0.013, canvas, segments=16)
    m.cone((0, 0.072, 0), (0, 0.082, 0), 0.013, 0.012, dark, segments=8)
    m.cone((0, 0.0745, 0), (0, 0.0795, 0), 0.0155, 0.0155, twine, segments=8)   # the twine wrap
    m.cone((0, 0.082, 0), (0, 0.093, 0), 0.012, 0.022, canvas, None, dark, segments=10)
    m.sphere((0.003, 0.094, 0.001), 0.012, rock, level=0, jitter=0.45, seed=4, squash=(1.1, 0.7, 1.0))
    m.tube([(0.012, 0.077, 0.006), (0.01, 0.058, 0.041)], 0.0012, twine, segments=4)
    m.box((0.004, 0.047, 0.0415), (0.028, 0.02, 0.002), {"side": tag, "front": tag})
    return m


def field_kit():
    """A canvas tool roll, half unrolled: pockets of tools, two leather straps, a hand lens."""
    t = Atlas(12)
    canvas = t.region(128, 64, Atlas.canvas, OLIVE)
    pockets = t.region(128, 64, Atlas.pockets, OLIVE)
    ends = t.region(64, 64, Atlas.rolled, OLIVE)
    leather = t.region(64, 32, Atlas.leather, LEATHER)
    steel = t.region(32, 32, Atlas.metal, STEEL)
    glass = t.region(32, 32, Atlas.screen, GLASS)
    wood = t.region(64, 32, Atlas.wood, WOOD)
    m = Model(t)
    m.cone((-0.11, 0.032, 0), (0.11, 0.032, 0), 0.032, 0.032, canvas, ends, ends)
    m.box((0, 0.0035, 0.072), (0.215, 0.007, 0.085), {"side": canvas, "top": pockets})
    for x in (-0.068, 0.068):
        m.cone((x - 0.006, 0.032, 0), (x + 0.006, 0.032, 0), 0.0345, 0.0345, leather)     # strap
        m.box((x, 0.066, 0), (0.012, 0.005, 0.016), steel)                                # buckle
    m.cone((0.07, 0.007, 0.075), (0.07, 0.0105, 0.075), 0.013, 0.013, steel, None, glass, segments=10)  # lens
    m.cone((0.083, 0.009, 0.075), (0.115, 0.009, 0.075), 0.0035, 0.004, wood, None, wood, segments=6)
    return m


def advanced_kit():
    """A hard instrument case: lid and shell, seam, carry handle, latches, corner guards."""
    t = Atlas(13)
    shell = t.region(128, 64, Atlas.ribbed, CASE_GREY)
    top = t.region(128, 96, Atlas.metal, CASE_GREY, True, False)
    dark = t.region(64, 32, Atlas.flat, CASE_DARK)
    steel = t.region(32, 32, Atlas.metal, STEEL)
    rubber = t.region(32, 32, Atlas.flat, RUBBER, 0.12)
    m = Model(t)
    m.box((0, 0.031, 0), (0.28, 0.058, 0.18), {"side": shell, "front": shell, "back": shell, "top": top, "bottom": dark}, bevel=0.009)
    m.box((0, 0.078, 0), (0.28, 0.034, 0.18), {"side": shell, "front": shell, "back": shell, "top": top}, bevel=0.009)
    m.box((0, 0.0605, 0), (0.274, 0.004, 0.174), dark)
    for x in (-0.045, 0.045):
        m.box((x, 0.1, 0), (0.014, 0.012, 0.016), dark)
    m.cone((-0.05, 0.109, 0), (0.05, 0.109, 0), 0.0075, 0.0075, rubber, rubber, rubber, segments=8)
    for x in (-0.09, 0.09):
        m.box((x, 0.06, 0.0915), (0.026, 0.026, 0.006), steel)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box((sx * 0.134, 0.012, sz * 0.084), (0.016, 0.024, 0.016), rubber)
    return m


def analyzer():
    """A bench-top instrument: steel cabinet with a face of window, dial, buttons and vents, a grille on top, a sample drawer, feet and a cable."""
    t = Atlas(14)
    front = t.region(128, 96, Atlas.front_panel, (150, 158, 166))
    side = t.region(64, 64, Atlas.metal, (140, 148, 156), True)
    top = t.region(64, 64, Atlas.grille, (140, 148, 156))
    dark = t.region(64, 32, Atlas.metal, CASE_DARK)
    rubber = t.region(32, 32, Atlas.flat, RUBBER, 0.1)
    red = t.region(32, 32, Atlas.flat, (180, 50, 40))
    m = Model(t)
    m.box((0, 0.16, 0), (0.38, 0.28, 0.30), {"side": side, "back": side, "front": front, "top": top, "bottom": dark, "bevel": side}, bevel=0.012)
    m.box((0, 0.065, 0.158), (0.2, 0.045, 0.026), {"side": dark, "front": dark})
    m.cone((-0.04, 0.07, 0.173), (0.04, 0.07, 0.173), 0.0035, 0.0035, side, segments=6)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cone((sx * 0.16, 0.0, sz * 0.12), (sx * 0.16, 0.022, sz * 0.12), 0.016, 0.014, rubber, segments=8)
    m.cone((0.11, 0.30, -0.05), (0.11, 0.318, -0.05), 0.026, 0.024, side)
    m.cone((0.11, 0.318, -0.05), (0.11, 0.326, -0.05), 0.027, 0.027, red, None, red)
    m.tube([(-0.15, 0.06, -0.15), (-0.15, 0.03, -0.19), (-0.13, 0.006, -0.24), (-0.05, 0.006, -0.27)], 0.006, rubber, segments=6)
    return m


def brass_catcher():
    """A net bag on a wire hoop with a clip, spent cases in its mouth."""
    t = Atlas(15)
    net = t.region(128, 64, Atlas.mesh, NET)
    bottom = t.region(64, 64, Atlas.canvas, CANVAS_DARK, False)
    steel = t.region(64, 32, Atlas.metal, STEEL)
    brass = t.region(32, 32, Atlas.brass, BRASS)
    pile = t.region(64, 64, Atlas.pile, BRASS)
    m = Model(t)
    m.cone((0, 0.0, 0), (0, 0.014, 0), 0.022, 0.034, net, bottom, None)
    m.cone((0, 0.014, 0), (0, 0.1, 0), 0.034, 0.05, net)
    # What it has caught, seen through the mouth.
    m.cone((0, 0.083, 0), (0, 0.084, 0), 0.047, 0.047, None, None, pile)
    m.ring((0, 0.102, 0), (0, 1, 0), 0.0505, 0.003, steel, segments=20, sides=3)
    m.tube([(0.052, 0.102, 0), (0.075, 0.108, 0), (0.095, 0.124, 0)], 0.0028, steel, segments=5)
    m.box((0.1, 0.13, 0), (0.014, 0.012, 0.01), steel)
    for p0, p1 in (((-0.018, 0.084, 0.004), (-0.008, 0.112, 0.01)), ((0.012, 0.084, -0.01), (0.02, 0.114, -0.004)),
                   ((0.0, 0.084, 0.018), (-0.004, 0.115, 0.03))):
        m.cone(p0, p1, 0.0048, 0.0048, brass, None, brass, segments=6)
    return m


def case_tumbler():
    """A steel drum with bands and a hatch, on a wooden A-frame stand, turned by a crank."""
    t = Atlas(16)
    drum = t.region(128, 64, Atlas.drum, STEEL)
    end = t.region(64, 64, Atlas.metal, STEEL_DARK, True)
    dark = t.region(64, 32, Atlas.metal, STEEL_DARK)
    wood = t.region(128, 32, Atlas.wood, WOOD)
    iron = t.region(32, 32, Atlas.metal, IRON)
    m = Model(t)
    for x in (-0.16, 0.16):
        for z in (-0.11, 0.11):
            m.beam((x, 0.0, z), (x, 0.29, z * 0.12), 0.022, wood, cap0=False)        # legs
        m.beam((x, 0.09, -0.085), (x, 0.09, 0.085), 0.018, wood, False, False)       # crossbar
    for z in (-0.11, 0.11):
        m.beam((-0.175, 0.012, z), (0.175, 0.012, z), 0.02, wood)                   # floor rails
    m.cone((-0.13, 0.30, 0), (0.13, 0.30, 0), 0.11, 0.11, drum, end, end, segments=14)
    for x in (-0.09, 0.09):
        m.cone((x - 0.005, 0.30, 0), (x + 0.005, 0.30, 0), 0.114, 0.114, dark, segments=14)   # bands
    m.box((0, 0.411, 0), (0.1, 0.01, 0.07), dark)
    m.box((0.035, 0.418, 0), (0.014, 0.006, 0.02), iron)
    m.cone((-0.17, 0.30, 0), (0.215, 0.30, 0), 0.01, 0.01, iron, iron, None, segments=6)      # axle
    m.beam((0.215, 0.305, 0), (0.215, 0.215, 0), 0.012, iron)                                  # crank arm
    m.cone((0.215, 0.215, 0), (0.26, 0.215, 0), 0.009, 0.009, wood, None, wood, segments=6)   # handle
    return m


# name, mod, builder
MODELS = [
    ("AmmoMakingSample", MAIN, sample),
    ("AmmoMakingFieldKit", MAIN, field_kit),
    ("AmmoMakingAdvancedKit", MAIN, advanced_kit),
    ("AmmoMakingAnalyzer", MAIN, analyzer),
    ("AmmoMakingBrassCatcher", SPENT, brass_catcher),
    ("AmmoMakingCaseTumbler", SPENT, case_tumbler),
]


# ---------------------------------------------------------------- writing

TEMPLATES = """xof 0303txt 0032
template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
 FLOAT alpha;
}

template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
}

template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor;
 FLOAT power;
 ColorRGB specularColor;
 ColorRGB emissiveColor;
 [...]
}

template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials;
 DWORD nFaceIndexes;
 array DWORD faceIndexes[nFaceIndexes];
 [Material]
}

template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}

template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}

template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}

template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}
"""


def f(x):
    return "%.6f" % (0.0 if abs(x) < 5e-7 else x)


def render(name, model):
    """The .X text of a model."""
    vertices, normals, uvs, faces = [], [], [], []
    for corner in model.corners:
        base = len(vertices)
        for position, normal, uv in corner:
            vertices.append(position)
            normals.append(unit(normal))
            uvs.append(uv)
        faces.append((base, base + 1, base + 2))

    def vector_list(items):
        return ",\n".join("  %s;%s;%s;" % (f(a), f(b), f(c)) for a, b, c in items) + ";"

    def face_list(items):
        return ",\n".join("  3;%d,%d,%d;" % face for face in items) + ";"

    return "".join([
        TEMPLATES,
        "\nMaterial Atlas {\n 1.000000;1.000000;1.000000;1.000000;;\n 10.000000;\n"
        " 0.000000;0.000000;0.000000;;\n 0.000000;0.000000;0.000000;;\n\n TextureFilename {\n  \"%s.png\";\n }\n}\n" % name,
        "\nFrame %s {\n\n FrameTransformMatrix {\n  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,"
        "0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;\n }\n\n" % name,
        " Mesh %s {\n  %d;\n%s\n  %d;\n%s\n\n" % (name, len(vertices), vector_list(vertices), len(faces), face_list(faces)),
        "  MeshNormals {\n   %d;\n%s\n   %d;\n%s\n  }\n\n" % (len(normals), vector_list(normals), len(faces), face_list(faces)),
        "  MeshMaterialList {\n   1;\n   %d;\n%s;\n   { Atlas }\n  }\n\n" % (len(faces), ",\n".join("   0" for _ in faces)),
        "  MeshTextureCoords c1 {\n   %d;\n%s;\n  }\n }\n}\n" % (len(uvs), ",\n".join("   %s;%s;" % (f(a), f(b)) for a, b in uvs)),
    ])


def script_text(mod):
    lines = ["/* Ammo Making - the world models of the mod's items that had none.", "",
             "   GENERATED by art/models/make_models.py: generated art from bevelled",
             "   boxes, cylinders, rings and a painted texture atlas, a .X mesh and a",
             "   texture each (PLACEHOLDER_VISUAL, docs/PLACEHOLDER_ASSETS.md). Do not",
             "   edit; replace the art and run it. REQUIRES FUTURE IN-GAME",
             "   VERIFICATION. */", "", "module AmmoMaking", "{"]
    blocks = []
    for name, owner, _ in MODELS:
        if owner == mod:
            blocks.append("    model %s\n    {\n        mesh = WorldItems/%s,\n        texture = WorldItems/%s,\n    }" % (name, name, name))
    lines.append("\n\n".join(blocks))
    lines.append("}")
    return "\n".join(lines) + "\n"


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def built():
    return [(name, mod, build()) for name, mod, build in MODELS]


def outputs(models=None):
    files = {}
    for name, mod, model in models or built():
        files["%s/42/media/models_X/WorldItems/%s.X" % (mod, name)] = render(name, model).encode("utf-8")
        files["%s/42/media/textures/WorldItems/%s.png" % (mod, name)] = png_bytes(model.atlas.image)
    for mod, script in SCRIPTS.items():
        files["%s/42/media/scripts/%s" % (mod, script)] = script_text(mod).encode("utf-8")
    return files


# ---------------------------------------------------------------- preview

def preview(models, path):
    """Each model from above at the game's three-quarter angle, textured,
    lit and depth-buffered, three to a row. For looking at, not shipped."""
    cell = 360
    sheet = Image.new("RGB", (cell * 3, cell * 2), (88, 94, 106))
    pixels = sheet.load()
    light = unit((-0.45, 0.8, 0.4))
    yaw, pitch = math.radians(45), math.radians(35)

    def view(v):
        # turn about y, then tip the far side up: the camera looks down
        x, y, z = v
        x, z = x * math.cos(yaw) - z * math.sin(yaw), x * math.sin(yaw) + z * math.cos(yaw)
        y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
        return x, y, z  # larger z: nearer the camera

    for k, (name, _, model) in enumerate(models):
        tex = model.atlas.image.convert("RGB").load()
        pts = [view(p) for corner in model.corners for p, _, _ in corner]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        scale = cell * 0.82 / max(max(xs) - min(xs), max(ys) - min(ys))
        ox = (k % 3) * cell + cell / 2 - (max(xs) + min(xs)) / 2 * scale
        oy = (k // 3) * cell + cell / 2 + (max(ys) + min(ys)) / 2 * scale
        depth = {}
        for corner in model.corners:
            (pa, na, ua), (pb, nb, ub), (pc, nc, uc) = corner
            va, vb, vc = view(pa), view(pb), view(pc)
            sa, sb, sc = [(ox + q[0] * scale, oy - q[1] * scale) for q in (va, vb, vc)]
            area = (sb[0] - sa[0]) * (sc[1] - sa[1]) - (sb[1] - sa[1]) * (sc[0] - sa[0])
            if area >= 0:  # seen from behind (screen y points down)
                continue
            lit = [0.4 + 0.6 * max(0.0, dot(unit(n), light)) for n in (na, nb, nc)]
            x0, x1 = int(max(min(sa[0], sb[0], sc[0]), 0)), int(min(max(sa[0], sb[0], sc[0]) + 1, sheet.width))
            y0, y1 = int(max(min(sa[1], sb[1], sc[1]), 0)), int(min(max(sa[1], sb[1], sc[1]) + 1, sheet.height))
            for y in range(y0, y1):
                for x in range(x0, x1):
                    px, py = x + 0.5, y + 0.5
                    w0 = ((sb[0] - px) * (sc[1] - py) - (sb[1] - py) * (sc[0] - px)) / area
                    w1 = ((sc[0] - px) * (sa[1] - py) - (sc[1] - py) * (sa[0] - px)) / area
                    w2 = 1 - w0 - w1
                    if w0 < 0 or w1 < 0 or w2 < 0:
                        continue
                    z = w0 * va[2] + w1 * vb[2] + w2 * vc[2]
                    if depth.get((x, y), -1e9) >= z:
                        continue
                    depth[(x, y)] = z
                    u = w0 * ua[0] + w1 * ub[0] + w2 * uc[0]
                    v = w0 * ua[1] + w1 * ub[1] + w2 * uc[1]
                    colour = tex[min(ATLAS - 1, max(0, int(u * ATLAS))), min(ATLAS - 1, max(0, int(v * ATLAS)))]
                    pixels[x, y] = shade(colour, w0 * lit[0] + w1 * lit[1] + w2 * lit[2])
        ImageDraw.Draw(sheet).text(((k % 3) * cell + 6, (k // 3) * cell + 6), name, fill=(240, 240, 240))
    sheet.save(path)


def main(argv):
    check = "--check" in argv
    models = built()
    if "--preview" in argv:
        preview(models, argv[argv.index("--preview") + 1])
        return 0
    differing = []
    files = outputs(models)
    for path, data in files.items():
        full = os.path.join(REPO, path)
        old = open(full, "rb").read() if os.path.isfile(full) else None
        # Text files may come back from git with CRLF; a PNG holds \r\n of
        # its own and is compared as it is.
        if old is not None and not path.endswith(".png"):
            old = old.replace(b"\r\n", b"\n")
        if old == data:
            continue
        if check:
            differing.append(path)
            continue
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as handle:
            handle.write(data)
        print("Wrote " + path)
    if check:
        for path in differing:
            print("differs: " + path)
        print("models: %d of %d files differ" % (len(differing), len(files)) if differing else "models: %d files equal a fresh build" % len(files))
        return 1 if differing else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
