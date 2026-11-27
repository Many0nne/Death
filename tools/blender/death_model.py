"""Modèle de la Mort (#76) : cape à os animable, capuche vide, bras squelette, faux en zones de skin.

Unités : 1 unité Blender = 1 stud. Origine = HumanoidRootPart du rig R15 ; sol à GROUND.
Face avant vers +Y (le glTF exporte (x, y, z) -> (x, z, -y), donc +Y Blender = -Z Roblox = l'avant).

Usage :
- interface (MCP) : exec(open(chemin).read(), {"__name__": "__main__"})
- sans interface : blender -b --factory-startup --python tools/blender/death_model.py -- <sortie.glb>
"""

import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector

GROUND = -3.65
random.seed(76)


def clear_scene():
    """Cette méthode permet de repartir d'une scène vide lorsqu'on reconstruit le modèle."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
        for d in list(coll):
            coll.remove(d)


def interp(keys, t):
    """Cette méthode permet d'interpoler en douceur un profil (t, valeurs...) lorsqu'on échantillonne une forme."""
    if t <= keys[0][0]:
        return list(keys[0][1:])
    for a, b in zip(keys, keys[1:]):
        if a[0] <= t <= b[0]:
            k = (t - a[0]) / (b[0] - a[0])
            k = k * k * (3 - 2 * k)
            return [a[i] + (b[i] - a[i]) * k for i in range(1, len(a))]
    return list(keys[-1][1:])


def material(name, rgb, metallic=0.0, roughness=0.8):
    """Cette méthode permet de créer un matériau nommé (une zone de skin) lorsqu'une pièce en a besoin."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*rgb, 1)
    return mat


def grid_object(name, cols, rows, fn, keep=None, weights=None, wrap=True):
    """Cette méthode permet de construire une surface en grille (colonnes x rangées) lorsqu'une forme est paramétrique ;
    weights(i, j) renvoie {groupe: poids} pour le skinning."""
    bm = bmesh.new()
    verts = [[bm.verts.new(fn(i, j)) for i in range(cols)] for j in range(rows)]
    last = cols if wrap else cols - 1
    for j in range(rows - 1):
        for i in range(last):
            if keep is None or keep(i, j):
                i2 = (i + 1) % cols
                bm.faces.new((verts[j][i], verts[j][i2], verts[j + 1][i2], verts[j + 1][i]))
    bm.verts.index_update()
    index = {verts[j][i].index: (i, j) for j in range(rows) for i in range(cols)}
    loose = [v for v in bm.verts if not v.link_faces]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if weights:
        groups = {}
        for v in me.vertices:
            for g, w in weights(*index[v.index]).items():
                if w <= 0:
                    continue
                if g not in groups:
                    groups[g] = ob.vertex_groups.new(name=g)
                groups[g].add([v.index], w, "REPLACE")
    # sommets isolés (faces retirées) : supprimés après le skinning pour garder les index
    if loose:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(me)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return ob


def solidify(ob, thickness):
    """Cette méthode permet de donner une épaisseur à une surface lorsqu'elle doit être étanche pour Roblox."""
    s = ob.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = thickness
    s.offset = 0
    s.use_even_offset = False  # l'épaisseur régulière fait exploser les angles vifs (poche de la capuche)
    s.use_quality_normals = True


# ---------------------------------------------------------------- cape
COLS, ROWS = 64, 30
CHAINS, CHAIN_BONES = 16, 4
T_SKIN = 0.22  # au-dessus : rigide (os racine), en dessous : chaînes de lambeaux
ROBE = [
    (0.0, 1.50, 0.38, 0.36),
    (0.05, 1.32, 0.72, 0.52),
    (0.13, 1.02, 0.98, 0.62),
    (0.30, 0.20, 0.98, 0.68),
    (0.50, -0.85, 1.00, 0.78),
    (0.75, -2.0, 1.30, 1.02),
    (1.0, -3.05, 1.65, 1.35),
]
TEETH = []
for _i in range(COLS):
    _b = random.uniform(0.0, 0.2)
    if random.random() < 0.55:
        _b += random.uniform(0.1, 0.45)
    if random.random() < 0.18:
        _b += random.uniform(0.3, 0.6)  # long lambeau
    TEETH.append(_b)
PH = [random.uniform(0, 6.28) for _ in range(4)]


def robe_pt(i, j):
    """Cette méthode permet de placer un sommet de la robe (colonne i, rangée j) lorsqu'on construit la cape."""
    th = 2 * math.pi * (i % COLS) / COLS
    t = j / (ROWS - 1)
    z, rx, ry = interp(ROBE, t)
    if t > 0.85:
        k = (t - 0.85) / 0.15
        z -= TEETH[i % COLS] * k * k
    fa = 0.17 * max(0, t - 0.15) ** 0.8
    r = 1 + fa * (
        math.sin(8 * th + PH[0] + 2.5 * t) + 0.45 * math.sin(15 * th + PH[1] - t) + 0.25 * math.sin(23 * th + PH[2])
    )
    x, y = rx * r * math.sin(th), ry * r * math.cos(th)
    back = max(0, -math.cos(th))
    w = max(0, t - 0.2) ** 2 * (1 + 0.8 * back) + 0.8 * TEETH[i % COLS] * max(0, t - 0.85) / 0.15
    x -= 0.45 * w
    y -= 0.6 * w
    z += 0.25 * w * back
    return (x, y, max(z, GROUND + 0.12))


def chain_t(b):
    """Cette méthode permet de donner la hauteur relative (t) du début de l'os b d'une chaîne."""
    return T_SKIN + (1.0 - T_SKIN) * b / CHAIN_BONES


def robe_weights(i, j):
    """Cette méthode permet de répartir un sommet de la robe entre l'os racine et les deux chaînes voisines."""
    t = j / (ROWS - 1)
    if t <= T_SKIN:
        return {"Root": 1.0}
    c = i * CHAINS / COLS
    c0 = int(c) % CHAINS
    c1 = (c0 + 1) % CHAINS
    wc = c - int(c)
    s = (t - T_SKIN) / (1.0 - T_SKIN) * CHAIN_BONES  # position le long de la chaîne, en os
    out = {}
    root_w = max(0.0, 1 - s / 0.5)
    for b in range(CHAIN_BONES):
        wb = max(0.0, 1 - abs(s - (b + 0.5)))
        if b == CHAIN_BONES - 1 and s > b + 0.5:
            wb = 1.0
        if b == 0 and s < 0.5:
            wb = s / 0.5
        if wb > 0:
            out[f"C{c0:02d}_{b}"] = out.get(f"C{c0:02d}_{b}", 0) + wb * (1 - wc)
            out[f"C{c1:02d}_{b}"] = out.get(f"C{c1:02d}_{b}", 0) + wb * wc
    if root_w > 0:
        out["Root"] = root_w
    total = sum(out.values())
    return {k: v / total for k, v in out.items()}


def build_armature():
    """Cette méthode permet de créer l'armature de la cape (racine + chaînes de lambeaux) lorsqu'on la skinne."""
    arm = bpy.data.armatures.new("CloakRig")
    ob = bpy.data.objects.new("CloakRig", arm)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("Root")
    root.head, root.tail = (0, 0, 0.8), (0, 0, 1.4)
    for c in range(CHAINS):
        col = c * COLS / CHAINS
        parent = root
        for b in range(CHAIN_BONES):
            eb = arm.edit_bones.new(f"C{c:02d}_{b}")
            j0 = round(chain_t(b) * (ROWS - 1))
            j1 = round(chain_t(b + 1) * (ROWS - 1))
            eb.head = robe_pt(int(col), j0)
            eb.tail = robe_pt(int(col), j1)
            eb.parent = parent
            eb.use_connect = b > 0
            parent = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def build_cloak():
    """Cette méthode permet de construire la robe en lambeaux, skinnée sur l'armature de la cape."""
    rig = build_armature()
    cloak = grid_object("Cloak", COLS, ROWS, robe_pt, weights=robe_weights)
    solidify(cloak, 0.05)
    mod = cloak.modifiers.new("Rig", "ARMATURE")
    mod.object = rig
    cloak.parent = rig
    cloak.data.materials.append(material("CloakCloth", (0.012, 0.012, 0.016), 0, 0.95))
    return rig, cloak


# ---------------------------------------------------------------- capuche
# capuche et pèlerine d'un seul tenant : v = 0 au bord de la pèlerine, 1 à la pointe ; (v, z, rx, ry, décalage y)
HOOD = [
    (0.0, -0.10, 1.30, 1.02, -0.05),
    (0.18, 0.55, 1.22, 0.92, -0.02),
    (0.32, 1.10, 1.02, 0.80, 0.00),
    (0.42, 1.42, 0.80, 0.78, 0.04),
    (0.62, 2.05, 0.78, 0.84, 0.08),
    (0.82, 2.55, 0.58, 0.66, -0.02),
    (1.0, 2.95, 0.05, 0.06, -0.30),
]
HC, HR = 64, 34
HOOD_TEETH = [random.uniform(0.0, 0.12) + (random.uniform(0.15, 0.4) if k % 2 else 0) for k in range(HC)]
OPEN_V = (0.40, 0.80)  # bande de l'ouverture (du menton au sommet du visage absent)


def hood_hollow(th, v):
    """Cette méthode permet de mesurer (0 à 1) combien un point de la capuche est creusé vers l'intérieur : 1 au centre
    de l'ouverture en ogive, 0 hors d'elle ; la surface reste continue, donc le bord est lisse."""
    d = min(th, 2 * math.pi - th)
    lo, hi = OPEN_V
    if v <= lo or v >= hi:
        return 0.0
    k = (v - lo) / (hi - lo)
    w = 0.62 * math.sin(math.pi * min(1.0, k * 1.1)) ** 0.5 * (1 - k) ** 0.35
    if d >= w:
        return 0.0
    s = 1 - d / w
    return min(1.0, s * 2.2) ** 0.8


def hood_pt(i, j):
    """Cette méthode permet de placer un sommet de la capuche, bord avant avancé et tombant devant l'ouverture."""
    th = 2 * math.pi * i / HC
    v = j / (HR - 1)
    z, rx, ry, yc = interp(HOOD, v)
    if v < 0.12:  # bord de la pèlerine en lambeaux
        z -= HOOD_TEETH[i] * (1 - v / 0.12) ** 2
    d = min(th, 2 * math.pi - th)
    fold = 1 + (0.06 if v < 0.35 else 0.03) * math.sin(9 * th + 4 * v + PH[3])
    x, y = rx * fold * math.sin(th), ry * fold * math.cos(th) + yc
    lo, hi = OPEN_V
    if d < 1.1 and lo - 0.06 < v < 0.95:
        k = min(1.0, (v - lo + 0.06) / (hi - lo + 0.06))
        y += 0.30 * (1 - d / 1.1) * math.sin(math.pi * min(1.0, k * 0.9))  # rebord qui avance
        z -= 0.12 * (1 - d / 1.1) * k  # et retombe devant le vide
    h = hood_hollow(th, v)
    if h > 0:  # poche : la face avant rentre profondément dans la capuche
        x *= 1 - 0.25 * h
        y -= 1.05 * h
    back = max(0, -math.cos(th))
    if v < 0.2:  # la pèlerine flotte un peu derrière
        y -= 0.25 * back * (1 - v / 0.2)
    return (x, y, z)


def build_hood():
    """Cette méthode permet de construire la capuche et le vide noir qu'elle contient (aucune tête)."""
    hood = grid_object("Hood", HC, HR, hood_pt)
    solidify(hood, 0.05)
    hood.data.materials.append(material("HoodCloth", (0.012, 0.012, 0.016), 0, 0.95))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=(0, 0.12, 1.95))
    void = bpy.context.active_object
    void.name = "Void"
    void.data.name = "Void"  # le glTF nomme la MeshPart d'après le maillage (sinon « Sphere »)
    void.scale = (0.66, 0.62, 0.78)
    void.data.materials.append(material("Void", (0, 0, 0), 0, 1))
    return hood, void


# ---------------------------------------------------------------- outils de maillage (tubes, sphères, UV)
class Builder:
    """Accumule de la géométrie (tubes, sphères, grilles) dans un bmesh avec UV, puis crée l'objet."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _face(self, vs, uvs):
        """Cette méthode permet d'ajouter une face avec ses UV lorsqu'on tisse une grille."""
        f = self.bm.faces.new(vs)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def grid(self, rows, closed_u=True, cap_start=False, cap_end=False):
        """Cette méthode permet de tisser une grille de sommets (rows[j][i]) en quads, UV u = i, v = j normalisés,
        avec des bouchons éventuels aux extrémités."""
        bm = self.bm
        vs = [[bm.verts.new(p) for p in row] for row in rows]
        n = len(rows[0])
        last = n if closed_u else n - 1
        for j in range(len(rows) - 1):
            for i in range(last):
                i2 = (i + 1) % n
                u0, u1 = i / n if closed_u else i / (n - 1), (i + 1) / n if closed_u else (i + 1) / (n - 1)
                v0, v1 = j / (len(rows) - 1), (j + 1) / (len(rows) - 1)
                self._face(
                    (vs[j][i], vs[j][i2], vs[j + 1][i2], vs[j + 1][i]), ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
                )
        for flag, row in ((cap_start, vs[0]), (cap_end, vs[-1])):
            if flag:
                c = bm.verts.new(sum((v.co for v in row), Vector()) / len(row))
                for i in range(len(row)):
                    self._face((row[i], row[(i + 1) % len(row)], c), ((0.5, 0.5), (0.5, 0.5), (0.5, 0.5)))
        return vs

    def tube(self, pts, radii, segs=10, cap=True, radial=None):
        """Cette méthode permet de balayer un cercle le long d'une polyligne (repère transporté) lorsqu'on modélise
        un manche, un os ou une bague ; radial(u, v) module le rayon (filetage, nœuds)."""
        pts = [Vector(p) for p in pts]
        rows = []
        prev_n = None
        for k, p in enumerate(pts):
            t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
            if prev_n is None:
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                n = t.cross(ref).normalized()
            else:
                n = (prev_n - t * prev_n.dot(t)).normalized()
            prev_n = n
            b = t.cross(n)
            row = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                r = radii[k] * (radial(i / segs, k / (len(pts) - 1)) if radial else 1)
                row.append(p + (n * math.cos(a) + b * math.sin(a)) * r)
            rows.append(row)
        return self.grid(rows, cap_start=cap, cap_end=cap)

    def sphere(self, center, radius, segs=10, rings=6, scale=(1, 1, 1)):
        """Cette méthode permet d'ajouter une sphère (articulation, gemme) lorsqu'une pièce en a besoin."""
        c = Vector(center)
        rows = []
        for j in range(1, rings):
            ph = math.pi * j / rings
            rows.append(
                [
                    c
                    + Vector(
                        (
                            radius * scale[0] * math.sin(ph) * math.cos(2 * math.pi * i / segs),
                            radius * scale[1] * math.sin(ph) * math.sin(2 * math.pi * i / segs),
                            radius * scale[2] * math.cos(ph),
                        )
                    )
                    for i in range(segs)
                ]
            )
        return self.grid(rows, cap_start=True, cap_end=True)

    def finish(self, mat, smooth=True):
        """Cette méthode permet de créer l'objet Blender à partir de la géométrie accumulée."""
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        for p in me.polygons:
            p.use_smooth = smooth
        ob.data.materials.append(mat)
        return ob


def lerp(a, b, t):
    """Cette méthode permet d'interpoler deux points."""
    return Vector(a).lerp(Vector(b), t)


# ---------------------------------------------------------------- faux
SHAFT_BOTTOM = Vector((1.48, 1.18, -3.25))
SHAFT_TOP = Vector((1.22, 1.02, 3.45))
GRIP_T = 0.56  # position de la main le long du manche (0 = embout, 1 = tête)
SHAFT_R = 0.085


def shaft_point(t):
    """Cette méthode permet de suivre l'axe légèrement courbé du manche (t de 0 à 1) lorsqu'on y place une pièce."""
    p = lerp(SHAFT_BOTTOM, SHAFT_TOP, t)
    p.x += 0.09 * math.sin(math.pi * t * 1.6)
    p.y += 0.04 * math.sin(math.pi * t)
    return p


def shaft_axis(t):
    """Cette méthode permet de donner la direction du manche au point t."""
    return (shaft_point(min(1, t + 0.01)) - shaft_point(max(0, t - 0.01))).normalized()


# lame : arc de cercle dans le plan XZ (face vers +Y), dos à l'extérieur, fil à l'intérieur
BLADE_R = 2.6
BLADE_A0, BLADE_A1 = math.radians(78), math.radians(172)


def blade_frame():
    """Cette méthode permet de calculer le centre de l'arc de la lame à partir du haut du manche."""
    root = shaft_point(0.985) + Vector((-0.05, 0, 0.05))
    return root - BLADE_R * Vector((math.cos(BLADE_A0), 0, math.sin(BLADE_A0)))


def blade_width(s):
    """Cette méthode permet de donner la largeur de la lame (du dos vers le fil) au point s (0 base, 1 pointe)."""
    return 0.62 * (1 - s) ** 0.75 * (0.85 + 0.15 * math.sin(math.pi * min(1, s * 3)))


def blade_point(s, w, side):
    """Cette méthode permet de placer un point de la lame : s le long, w de 0 (dos) à 1 (fil), side = +1/-1 face."""
    c = blade_frame()
    a = BLADE_A0 + (BLADE_A1 - BLADE_A0) * s
    r = BLADE_R - blade_width(s) * w
    # épaisseur : dos épais, rainure au milieu, fil fin
    th = 0.055 * (1 - w) ** 0.6 + 0.006
    if 0.22 < w < 0.6 and 0.06 < s < 0.78:
        th -= 0.018 * math.sin(math.pi * (w - 0.22) / 0.38)  # rainure (accueille la gravure)
    th *= 1 - 0.6 * s
    return c + Vector((r * math.cos(a), side * th, r * math.sin(a)))


def build_blade():
    """Cette méthode permet de construire la lame (acier), son fil poli et le panneau gravable de la rainure,
    trois MeshParts distinctes pour les skins."""
    S, W, EDGE_W = 48, 10, 0.78
    for name, w0, w1, mat in (
        ("Blade", 0.0, EDGE_W, material("BladeSteel", (0.32, 0.33, 0.36), 1.0, 0.38)),
        ("Edge", EDGE_W, 1.0, material("EdgeSteel", (0.78, 0.8, 0.84), 1.0, 0.12)),
    ):
        b = Builder(name)
        ws = [w0 + (w1 - w0) * k / W for k in range(W + 1)]
        # contour fermé : face avant de w0 à w1, puis face arrière de w1 à w0
        ring = [(w, 1) for w in ws] + [(w, -1) for w in reversed(ws)]
        rows = [[blade_point(s, w, side) for (w, side) in ring] for s in (k / S for k in range(S + 1))]
        b.grid(rows, cap_start=True, cap_end=True)
        b.finish(mat)
    # gravure : panneau dans la rainure, des deux côtés, UV u = longueur (0..1), v = largeur
    g = Builder("Engraving")
    for side in (1, -1):
        rows = []
        for k in range(33):
            s = 0.08 + 0.68 * k / 32
            row = []
            for m in range(5):
                w = 0.26 + 0.30 * m / 4
                p = blade_point(s, w, side)
                p.y += side * 0.003
                row.append(p)
            rows.append(row)
        g.grid(rows, closed_u=False)
    g.finish(material("Engraving", (0.2, 0.2, 0.22), 1.0, 0.5))


def build_scythe():
    """Cette méthode permet de construire la faux : manche, poignée, bagues, embout, tête, gemme et lame."""
    wood = material("ShaftWood", (0.09, 0.06, 0.045), 0.0, 0.7)
    metal = material("HeadMetal", (0.16, 0.16, 0.18), 1.0, 0.35)
    # manche : nœuds discrets, UV le long du manche
    N = 40
    ts = [k / N for k in range(N + 1)]
    b = Builder("Shaft")
    b.tube(
        [shaft_point(t) for t in ts],
        [SHAFT_R * (1.08 - 0.12 * t) for t in ts],
        segs=12,
        radial=lambda u, v: 1 + 0.06 * max(0, math.sin(v * 37 + u * 2)) ** 8,
    )
    b.finish(wood)
    # poignée : cuir enroulé en hélice autour de la main
    g = Builder("Grip")
    gt = [GRIP_T - 0.06 + 0.12 * k / 30 for k in range(31)]
    g.tube(
        [shaft_point(t) for t in gt],
        [SHAFT_R * 1.18] * len(gt),
        segs=14,
        radial=lambda u, v: 1 + 0.07 * math.sin(2 * math.pi * (u * 1 - v * 9)) ** 2,
    )
    g.finish(material("GripLeather", (0.11, 0.05, 0.04), 0.0, 0.85))
    # bagues de métal
    r = Builder("Rings")
    for t in (0.06, GRIP_T - 0.075, GRIP_T + 0.075, 0.93):
        a = shaft_axis(t)
        p = shaft_point(t)
        r.tube([p - a * 0.035, p - a * 0.02, p + a * 0.02, p + a * 0.035], [SHAFT_R * 1.15, SHAFT_R * 1.32,
               SHAFT_R * 1.32, SHAFT_R * 1.15], segs=14)
    r.finish(material("RingMetal", (0.5, 0.45, 0.36), 1.0, 0.3))
    # embout : collerette puis pointe
    p0 = shaft_point(0.0)
    a = shaft_axis(0.0)
    pm = Builder("Pommel")
    pm.tube([p0 + a * 0.12, p0 + a * 0.02, p0 - a * 0.06, p0 - a * 0.2, p0 - a * 0.42],
            [SHAFT_R * 1.1, SHAFT_R * 1.5, SHAFT_R * 1.25, SHAFT_R * 0.7, 0.005], segs=10)
    pm.finish(metal)
    # tête : douille autour du haut du manche, éperon arrière, sertissure de la gemme
    top = shaft_point(1.0)
    a = shaft_axis(1.0)
    h = Builder("ScytheHead")  # pas « Head » : le rig R15 a déjà une pièce Head
    h.tube([top - a * 0.42, top - a * 0.36, top - a * 0.1, top + a * 0.08, top + a * 0.16],
           [SHAFT_R * 1.2, SHAFT_R * 1.55, SHAFT_R * 1.45, SHAFT_R * 1.7, SHAFT_R * 0.6], segs=8)
    spur = [top + Vector((0.08, 0, -0.05)), top + Vector((0.3, 0, 0.02)), top + Vector((0.5, 0, 0.18)),
            top + Vector((0.6, 0, 0.4))]
    h.tube(spur, [0.07, 0.055, 0.035, 0.004], segs=8)
    gem_c = top + Vector((0, 0, -0.22))
    h.tube([gem_c + Vector((0, -0.13, 0)), gem_c + Vector((0, -0.1, 0)), gem_c + Vector((0, 0.1, 0)),
            gem_c + Vector((0, 0.13, 0))], [0.1, 0.16, 0.16, 0.1], segs=16)
    h.finish(metal)
    gem = Builder("Gem")
    for side in (1, -1):
        gem.sphere(gem_c + Vector((0, side * 0.13, 0)), 0.1, segs=14, rings=8, scale=(1, 0.45, 1))
    gem.finish(material("Gem", (0.25, 0.75, 0.65), 0.0, 0.1))
    build_blade()


# ---------------------------------------------------------------- bras squelette et manche de la cape
def build_arm():
    """Cette méthode permet de construire la manche (tissu) et l'avant-bras squelette dont la main serre la faux ;
    l'autre bras reste caché sous la cape."""
    g = shaft_point(GRIP_T)
    ax = shaft_axis(GRIP_T)
    palm = Vector((-0.85, -0.55, 0)).normalized()  # la paume est côté corps
    palm = (palm - ax * palm.dot(ax)).normalized()
    side = ax.cross(palm)
    wrist = g + palm * 0.36 - ax * 0.12
    cuff = wrist + Vector((-0.12, -0.32, -0.18))
    shoulder = Vector((1.0, 0.25, 0.75))
    # manche évasée, bord en lambeaux
    sl = Builder("Sleeve")
    pts = [lerp(shoulder, cuff, k / 12) for k in range(13)]
    for k, p in enumerate(pts):
        p.z -= 0.12 * math.sin(math.pi * k / 12)  # le tissu pend sous son poids
    sl.tube(
        pts,
        [0.24 + 0.16 * (k / 12) ** 1.5 for k in range(13)],
        segs=24,
        cap=False,
        radial=lambda u, v: 1 + 0.06 * math.sin(u * 2 * math.pi * 4) + (0.12 * math.sin(u * 2 * math.pi * 7) if v > 0.75 else 0),
    )
    sleeve = sl.finish(material("CloakCloth", (0.012, 0.012, 0.016), 0, 0.95))
    solidify(sleeve, 0.04)
    # os : radius et ulna, poignet, cinq doigts enroulés autour du manche
    bone = material("Bone", (0.62, 0.57, 0.48), 0.0, 0.6)
    hb = Builder("BoneArm")
    elbow = lerp(shoulder, cuff, 0.45)
    for off in (side * 0.05, -side * 0.05):
        hb.tube([elbow + off, lerp(elbow, wrist, 0.5) + off * 0.8, wrist + off * 0.6], [0.045, 0.035, 0.04], segs=8)
    hb.sphere(wrist, 0.075, scale=(1.1, 1.1, 0.8))
    rr = SHAFT_R * 1.18 + 0.04  # les doigts passent par-dessus la poignée
    for f in range(4):
        h = (0.105 - f * 0.07) * 1.0
        knuckle = g + palm * 0.17 + ax * h
        hb.tube([wrist + side * (0.04 - f * 0.027) + ax * h * 0.4, knuckle], [0.028, 0.032], segs=7)
        prev = knuckle
        hb.sphere(knuckle, 0.035)
        for k, ang in enumerate((60, 125, 190)):
            a = math.radians(ang)
            p = g + ax * (h - 0.01 * k) + (palm * math.cos(a) + side * math.sin(a)) * rr
            hb.tube([prev, p], [0.028 - k * 0.004, 0.024 - k * 0.004], segs=7)
            hb.sphere(p, 0.026 - k * 0.004)
            prev = p
        # griffe au bout
        a = math.radians(222)
        tip = g + ax * (h - 0.025) + (palm * math.cos(a) + side * math.sin(a)) * (SHAFT_R * 1.18 + 0.005)
        hb.tube([prev, tip], [0.016, 0.003], segs=6)
    # pouce : de l'autre côté, autour du manche vers le haut
    prev = wrist - side * 0.06
    for k, ang in enumerate((-40, -95, -150)):
        a = math.radians(ang)
        p = g + ax * (0.16 + 0.02 * k) + (palm * math.cos(a) + side * math.sin(a)) * rr
        hb.tube([prev, p], [0.03 - k * 0.005, 0.026 - k * 0.005], segs=7)
        hb.sphere(p, 0.028 - k * 0.005)
        prev = p
    hb.finish(bone)


def build_all():
    """Cette méthode permet de reconstruire tout le modèle de la Mort lorsqu'on lance le script."""
    clear_scene()
    build_cloak()
    build_hood()
    build_scythe()
    build_arm()


if __name__ == "__main__":
    build_all()
    if "--" in sys.argv:
        out = sys.argv[sys.argv.index("--") + 1]
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_yup=True)
