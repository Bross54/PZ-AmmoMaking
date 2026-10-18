"""Ammo Making - builds the placeholder world models of the items that had none.

    python art/models/make_models.py            write them
    python art/models/make_models.py --check    fail when a written file differs

Programmer art in three dimensions: each model is a few boxes and cylinders
in flat colours, written as a DirectX .X text file (one of the mesh formats
the 42.21 jar loads: ModelFileExtensionType X, Fbx, glTF, Txt) with a palette
texture beside it, and a model script that names both. It copies no vanilla
or third-party geometry. Good enough to see an item on the ground and turn
it; not meant as final art (docs/ART_HANDOFF.md).

The conventions are vanilla's own, read from media/models_X/CanClosed.X (the
closed tin can, a WorldStaticModel at scale 1): one frame with the identity
matrix, Y up, the origin at the middle of the bottom, metres (the can is
0.063 x 0.088), and triangles wound so that (v1 - v0) x (v2 - v0) points
out of the model, as its normals do.

Writes, per model, into the mod that ships the item:
  <mod>/42/media/models_X/WorldItems/<name>.X
  <mod>/42/media/textures/WorldItems/<name>.png
and one generated script per mod with the model blocks:
  <mod>/42/media/scripts/<script>
An item names its model as WorldStaticModel = AmmoMaking.<name>, the module
and the name, as other mods name theirs (e.g. MFSEject.9x19_Casing).

REQUIRES FUTURE IN-GAME VERIFICATION: that each model shows on the ground,
the right way up, at about the size here, and turns with the item.
"""

import io
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

MAIN = "mod/AmmoMaking"
SPENT = "mod/AmmoMakingSpentCases"
SCRIPTS = {MAIN: "AC_Models.txt", SPENT: "AC_SpentCaseModels.txt"}

# Colours: one column of the palette texture each.
CANVAS = (176, 158, 116)
CANVAS_DARK = (122, 106, 74)
OLIVE = (104, 112, 70)
OLIVE_DARK = (66, 72, 44)
CASE = (150, 160, 170)
CASE_DARK = (82, 90, 102)
STEEL = (168, 174, 180)
STEEL_DARK = (96, 102, 110)
IRON = (70, 70, 74)
WOOD = (150, 110, 68)
BRASS = (210, 172, 80)
GLASS = (60, 88, 104)
ROCK = (120, 116, 108)
RED = (170, 52, 44)
CREAM = (220, 210, 180)


class Model:
    def __init__(self):
        self.triangles = []  # (v0, v1, v2, normal, colour)

    def quad(self, a, b, c, d, colour):
        """A quad wound a, b, c, d counter-clockwise seen from outside."""
        normal = unit(cross(sub(b, a), sub(c, a)))
        self.triangles.append((a, b, c, normal, colour))
        self.triangles.append((a, c, d, normal, colour))

    def box(self, x0, y0, z0, x1, y1, z1, colour, top=None):
        p = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        # index = 4 * ix + 2 * iy + iz
        P = lambda ix, iy, iz: p[4 * ix + 2 * iy + iz]
        self.quad(P(1, 0, 0), P(1, 1, 0), P(1, 1, 1), P(1, 0, 1), colour)       # +x
        self.quad(P(0, 0, 1), P(0, 1, 1), P(0, 1, 0), P(0, 0, 0), colour)       # -x
        self.quad(P(0, 1, 0), P(0, 1, 1), P(1, 1, 1), P(1, 1, 0), top or colour)  # +y
        self.quad(P(0, 0, 0), P(1, 0, 0), P(1, 0, 1), P(0, 0, 1), colour)       # -y
        self.quad(P(0, 0, 1), P(1, 0, 1), P(1, 1, 1), P(0, 1, 1), colour)       # +z
        self.quad(P(1, 0, 0), P(0, 0, 0), P(0, 1, 0), P(1, 1, 0), colour)       # -z

    def cylinder(self, centre, axis, radius, length, colour, cap=None, segments=12):
        """A cylinder whose axis is "x", "y" or "z", centred on centre."""
        def point(angle, along):
            u, v = radius * math.cos(angle), radius * math.sin(angle)
            cx, cy, cz = centre
            if axis == "x":
                return (cx + along, cy + u, cz + v)
            if axis == "y":
                return (cx + v, cy + along, cz + u)
            return (cx + u, cy + v, cz + along)
        h = length / 2
        for i in range(segments):
            a0, a1 = 2 * math.pi * i / segments, 2 * math.pi * (i + 1) / segments
            q = [point(a0, -h), point(a1, -h), point(a1, h), point(a0, h)]
            normal = unit(cross(sub(q[1], q[0]), sub(q[2], q[0])))
            mid = point((a0 + a1) / 2, 0)
            outward = sub(mid, centre)
            if dot(normal, outward) < 0:
                q = [q[1], q[0], q[3], q[2]]
            self.quad(q[0], q[1], q[2], q[3], colour)
            for end in (-h, h):
                tip = point(0, end)
                c = tuple(tip[k] - (point(0, 0)[k] - centre[k]) for k in range(3))
                t = (c, point(a0, end), point(a1, end))
                n = unit(cross(sub(t[1], t[0]), sub(t[2], t[0])))
                if dot(n, sub(c, centre)) < 0:
                    t = (t[0], t[2], t[1])
                    n = unit(cross(sub(t[1], t[0]), sub(t[2], t[0])))
                self.triangles.append((t[0], t[1], t[2], n, cap or colour))


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def cross(u, w):
    return (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])


def dot(u, w):
    return sum(u[i] * w[i] for i in range(3))


def unit(v):
    length = math.sqrt(dot(v, v)) or 1.0
    return tuple(c / length for c in v)


# ---------------------------------------------------------------- the models

def sample():
    """A canvas sample bag tied at the neck, a rock showing."""
    m = Model()
    m.box(-0.045, 0.0, -0.035, 0.045, 0.065, 0.035, CANVAS, top=CANVAS_DARK)
    m.cylinder((0, 0.075, 0), "y", 0.016, 0.02, CANVAS_DARK)
    m.box(-0.012, 0.085, -0.010, 0.012, 0.098, 0.010, ROCK)
    m.box(-0.046, 0.030, -0.036, 0.046, 0.036, 0.036, RED)  # the label band
    return m


def field_kit():
    """A canvas tool roll lying on the ground, two straps."""
    m = Model()
    m.cylinder((0, 0.035, 0), "x", 0.035, 0.26, OLIVE, cap=OLIVE_DARK)
    for x in (-0.07, 0.07):
        m.cylinder((x, 0.035, 0), "x", 0.037, 0.016, WOOD)
    return m


def advanced_kit():
    """A hard instrument case with a handle and two latches."""
    m = Model()
    m.box(-0.14, 0.0, -0.09, 0.14, 0.10, 0.09, CASE, top=CASE)
    m.box(-0.141, 0.048, -0.091, 0.141, 0.054, 0.091, CASE_DARK)  # the seam
    m.box(-0.05, 0.10, -0.012, 0.05, 0.125, 0.012, IRON)           # handle
    for x in (-0.09, 0.09):
        m.box(x - 0.012, 0.04, 0.090, x + 0.012, 0.065, 0.096, STEEL)
    return m


def analyzer():
    """A bench-top instrument: steel cabinet, a window, a dial, a sample tray."""
    m = Model()
    m.box(-0.20, 0.0, -0.15, 0.20, 0.30, 0.15, CASE, top=CASE_DARK)
    m.box(-0.14, 0.13, 0.150, 0.06, 0.25, 0.158, GLASS)             # window
    m.cylinder((0.12, 0.20, 0.155), "z", 0.035, 0.016, CREAM, cap=CREAM)  # dial
    m.box(-0.10, 0.03, 0.150, 0.10, 0.07, 0.20, STEEL_DARK)         # tray
    m.box(-0.20, 0.0, -0.15, -0.17, 0.02, 0.15, IRON)               # feet
    m.box(0.17, 0.0, -0.15, 0.20, 0.02, 0.15, IRON)
    return m


def brass_catcher():
    """A canvas bag on a wire hoop, two cases in its mouth."""
    m = Model()
    m.box(-0.05, 0.0, -0.04, 0.05, 0.11, 0.04, CANVAS, top=CANVAS_DARK)
    w = 0.004
    for x0, z0, x1, z1 in ((-0.055, -0.045, 0.055, -0.045 + w), (-0.055, 0.045 - w, 0.055, 0.045),
                           (-0.055, -0.045, -0.055 + w, 0.045), (0.055 - w, -0.045, 0.055, 0.045)):
        m.box(x0, 0.11, z0, x1, 0.118, z1, STEEL)
    m.box(0.051, 0.11, -0.003, 0.09, 0.116, 0.003, STEEL)            # the clip
    m.cylinder((-0.015, 0.12, 0), "x", 0.005, 0.03, BRASS)
    m.cylinder((0.015, 0.122, 0.01), "z", 0.005, 0.03, BRASS)
    return m


def case_tumbler():
    """A steel drum on a wooden stand, with a crank."""
    m = Model()
    for x in (-0.16, 0.13):
        m.box(x, 0.0, -0.10, x + 0.03, 0.18, -0.07, WOOD)
        m.box(x, 0.0, 0.07, x + 0.03, 0.18, 0.10, WOOD)
        m.box(x, 0.16, -0.10, x + 0.03, 0.19, 0.10, WOOD)
    m.box(-0.16, 0.02, -0.10, 0.16, 0.04, -0.07, WOOD)
    m.box(-0.16, 0.02, 0.07, 0.16, 0.04, 0.10, WOOD)
    m.cylinder((0, 0.30, 0), "x", 0.12, 0.30, STEEL, cap=STEEL_DARK)
    for x in (-0.08, 0.0, 0.08):
        m.cylinder((x, 0.30, 0), "x", 0.122, 0.01, STEEL_DARK)
    m.box(0.15, 0.295, -0.005, 0.22, 0.305, 0.005, IRON)              # axle
    m.box(0.215, 0.23, -0.005, 0.225, 0.305, 0.005, IRON)             # crank arm
    m.cylinder((0.235, 0.235, 0), "x", 0.008, 0.03, WOOD)             # handle
    return m


# name, mod, builder, script note
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
    """The .X text and the palette image of a model."""
    colours = []
    for tri in model.triangles:
        if tri[4] not in colours:
            colours.append(tri[4])
    width = 8 * len(colours)
    palette = Image.new("RGBA", (width, 8))
    for i, colour in enumerate(colours):
        for x in range(8 * i, 8 * i + 8):
            for y in range(8):
                palette.putpixel((x, y), colour + (255,))
    vertices, normals, uvs, faces = [], [], [], []
    for tri in model.triangles:
        u = (colours.index(tri[4]) + 0.5) / len(colours)
        base = len(vertices)
        for v in tri[:3]:
            vertices.append(v)
            normals.append(tri[3])
            uvs.append((u, 0.5))
        faces.append((base, base + 1, base + 2))

    def vector_list(items):
        return ",\n".join("  %s;%s;%s;" % (f(a), f(b), f(c)) for a, b, c in items) + ";"

    def face_list(items):
        return ",\n".join("  3;%d,%d,%d;" % face for face in items) + ";"

    out = [TEMPLATES, "\nMaterial Palette {\n 1.000000;1.000000;1.000000;1.000000;;\n 10.000000;\n"
           " 0.000000;0.000000;0.000000;;\n 0.000000;0.000000;0.000000;;\n\n TextureFilename {\n  \"%s.png\";\n }\n}\n" % name,
           "\nFrame %s {\n\n FrameTransformMatrix {\n  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,"
           "0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;\n }\n\n" % name,
           " Mesh %s {\n  %d;\n%s\n  %d;\n%s\n\n" % (name, len(vertices), vector_list(vertices), len(faces), face_list(faces)),
           "  MeshNormals {\n   %d;\n%s\n   %d;\n%s\n  }\n\n" % (len(normals), vector_list(normals), len(faces), face_list(faces)),
           "  MeshMaterialList {\n   1;\n   %d;\n%s;\n   { Palette }\n  }\n\n" % (len(faces), ",\n".join("   0" for _ in faces)),
           "  MeshTextureCoords c1 {\n   %d;\n%s;\n  }\n }\n}\n" % (len(uvs), ",\n".join("   %s;%s;" % (f(a), f(b)) for a, b in uvs))]
    return "".join(out), palette


def script_text(mod):
    lines = ["/* Ammo Making - the world models of the mod's items that had none.", "",
             "   GENERATED by art/models/make_models.py: programmer art from boxes and",
             "   cylinders, a .X mesh and a palette texture each (PLACEHOLDER_VISUAL,",
             "   docs/PLACEHOLDER_ASSETS.md). Do not edit; replace the art and run it.",
             "   REQUIRES FUTURE IN-GAME VERIFICATION. */", "", "module AmmoMaking", "{"]
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


def outputs():
    files = {}
    for name, mod, build in MODELS:
        text, palette = render(name, build())
        files["%s/42/media/models_X/WorldItems/%s.X" % (mod, name)] = text.encode("utf-8")
        files["%s/42/media/textures/WorldItems/%s.png" % (mod, name)] = png_bytes(palette)
    for mod, script in SCRIPTS.items():
        files["%s/42/media/scripts/%s" % (mod, script)] = script_text(mod).encode("utf-8")
    return files


def main(argv):
    check = "--check" in argv
    differing = []
    for path, data in outputs().items():
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
        print("models: %d of %d files differ" % (len(differing), len(outputs())) if differing else "models: %d files equal a fresh build" % len(outputs()))
        return 1 if differing else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
