"""Modèle de la Mort (#76, outillage #79) : cape à os drapée, capuche vide, bras squelette, faux en zones de skin.

Unités : 1 unité Blender = 1 stud. Origine = HumanoidRootPart du rig R15 ; sol à GROUND.
Face avant vers +Y (le glTF exporte (x, y, z) -> (x, z, -y), donc +Y Blender = -Z Roblox = l'avant).
Noms des pièces, budgets et cuisson : tools/models/death.manifest.json. Chaîne complète : tools/blender/pipeline.py.

Usage :
- chaîne complète (recommandé) : blender -b --factory-startup --python tools/blender/pipeline.py -- --glb <sortie.glb>
- interface (MCP), construction seule : exec(open(chemin).read(), {"__name__": "__main__", "__file__": chemin})
L'export GLB passe par pipeline.py (pièces du manifeste seulement, après contrôles).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import cloth, mesh  # noqa: E402
from lib.mesh import Builder, grid_object, interp, lerp, material, smoothstep, solidify  # noqa: E402

GROUND = -3.65
SEED = 76
random.seed(SEED)
# nombre d'images du drapé : fixe, le résultat en dépend
DRAPE_FRAMES = 70


# ---------------------------------------------------------------- cape
COLS, ROWS = 64, 30
CHAINS, CHAIN_BONES = 16, 4
T_SKIN = 0.22  # au-dessus : rigide (os racine, épinglé pendant le drapé), en dessous : chaînes de lambeaux
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


def robe_shape(i, j, ample=0.0, folds=1.0, teeth=True):
    """Cette méthode permet de placer un sommet de la robe (colonne i, rangée j) : `ample` élargit le bas (tissu en
    trop qui plissera au drapé), `folds` dose les plis dessinés, `teeth` ajoute les lambeaux."""
    th = 2 * math.pi * (i % COLS) / COLS
    t = j / (ROWS - 1)
    z, rx, ry = interp(ROBE, t)
    if teeth and t > 0.85:
        k = (t - 0.85) / 0.15
        z -= TEETH[i % COLS] * k * k
    fa = 0.17 * folds * max(0, t - 0.15) ** 0.8
    r = 1 + fa * (
        math.sin(8 * th + PH[0] + 2.5 * t) + 0.45 * math.sin(15 * th + PH[1] - t) + 0.25 * math.sin(23 * th + PH[2])
    )
    r *= 1 + ample * smoothstep(T_SKIN, 0.55, t)
    x, y = rx * r * math.sin(th), ry * r * math.cos(th)
    back = max(0, -math.cos(th))
    tooth = TEETH[i % COLS] if teeth else 0
    w = max(0, t - 0.2) ** 2 * (1 + 0.8 * back) + 0.8 * tooth * max(0, t - 0.85) / 0.15
    x -= 0.45 * w
    y -= 0.6 * w
    z += 0.25 * w * back
    return (x, y, max(z, GROUND + 0.12))


def robe_pt(i, j):
    """Cette méthode permet de placer un sommet de la robe dessinée, sans drapé (ancienne forme, plis en sinusoïdes)."""
    return robe_shape(i, j)


def robe_start(i, j):
    """Cette méthode permet de placer un sommet de la robe avant le drapé : trop ample, plis dessinés atténués (ils
    ne servent qu'à briser la symétrie) ; la simulation fait le reste."""
    return robe_shape(i, j, ample=0.22, folds=0.25)


PROXY_COLS, PROXY_ROWS = 32, 22


def proxy_pt(i, j):
    """Cette méthode permet de placer un sommet du corps de substitution : la silhouette de la robe un peu rentrée,
    sans plis ni lambeaux, fermée en haut et en bas (le tissu s'y pose)."""
    s = j / (PROXY_ROWS - 1)
    t = 0.04 + 0.86 * s
    x, y, z = robe_shape(i * COLS / PROXY_COLS, t * (ROWS - 1), folds=0, teeth=False)
    k = 0.9 * (smoothstep(0, 0.08, s) * smoothstep(1, 0.93, s)) ** 0.5  # se referme aux deux bouts
    return (x * k, y * k, z)


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


def build_armature(cloak):
    """Cette méthode permet de créer l'armature de la cape (racine + chaînes de lambeaux), chaque os posé sur la robe
    telle qu'elle est (drapée ou non), d'après les indices de grille gardés sur ses sommets."""
    index = mesh.grid_index(cloak)
    co = cloak.data.vertices
    arm = bpy.data.armatures.new("CloakRig")
    ob = mesh.link(bpy.data.objects.new("CloakRig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("Root")
    root.head, root.tail = (0, 0, 0.8), (0, 0, 1.4)
    for c in range(CHAINS):
        col = int(c * COLS / CHAINS)
        parent = root
        for b in range(CHAIN_BONES):
            eb = arm.edit_bones.new(f"C{c:02d}_{b}")
            j0 = round(chain_t(b) * (ROWS - 1))
            j1 = round(chain_t(b + 1) * (ROWS - 1))
            eb.head = co[index[(col, j0)]].co
            eb.tail = co[index[(col, j1)]].co
            eb.parent = parent
            eb.use_connect = b > 0
            parent = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def build_cloak(drape=True):
    """Cette méthode permet de construire la robe en lambeaux : drapée par simulation de tissu sur un corps de
    substitution (puis figée), puis skinnée sur l'armature de la cape (poids recalculés d'après la grille)."""
    cloak = grid_object("Cloak", COLS, ROWS, robe_start if drape else robe_pt, uv_shift=COLS // 2)
    if drape:
        body = cloth.proxy_body("ClothBody", PROXY_COLS, PROXY_ROWS, proxy_pt)
        floor = cloth.ground(GROUND + 0.04)
        mesh.set_group(cloak, "Pin", lambda i, j: 1.0 if j / (ROWS - 1) <= T_SKIN + 1e-6 else 0.0)
        cloth.drape(cloak, "Pin", frames=DRAPE_FRAMES)
        cloak.vertex_groups.remove(cloak.vertex_groups["Pin"])
        for o in (body, floor):
            bpy.data.objects.remove(o, do_unlink=True)
    rig = build_armature(cloak)
    mesh.set_weights(cloak, robe_weights)
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
HC, HR = 64, 40
HOOD_TEETH = [random.uniform(0.0, 0.12) + (random.uniform(0.15, 0.4) if k % 2 else 0) for k in range(HC)]
OPEN_V = (0.40, 0.80)  # bande de l'ouverture (du menton au sommet du visage absent)
# colonnes et rangées resserrées autour de l'ouverture : son bord reste lisse (plus de marches d'escalier)
HOOD_U = mesh.warp_samples(HC, lambda u: 1 + 2.2 * math.exp(-((min(u, 1 - u) / 0.11) ** 2)), closed=True)
HOOD_V = mesh.warp_samples(HR, lambda v: 1 + 1.6 * math.exp(-(((v - 0.6) / 0.22) ** 2)))
VOID_GAP = 0.045  # écart du vide au tissu de la poche (le tissu fait ±0,025)


def opening_width(v):
    """Cette méthode permet de donner la demi-largeur angulaire (radians) de l'ouverture à la hauteur v (0 hors de
    la bande de l'ouverture) : une ogive, étroite au menton, pointue en haut."""
    lo, hi = OPEN_V
    if v <= lo or v >= hi:
        return 0.0
    k = (v - lo) / (hi - lo)
    return 0.62 * math.sin(math.pi * min(1.0, k * 1.1)) ** 0.5 * (1 - k) ** 0.35


def hood_hollow(th, v):
    """Cette méthode permet de mesurer (0 à 1) combien un point de la capuche est creusé vers l'intérieur : 1 au centre
    de l'ouverture en ogive, 0 hors d'elle ; transition douce, donc le bord de l'ouverture est lisse."""
    d = min(th, 2 * math.pi - th)
    w = opening_width(v)
    if d >= w:
        return 0.0
    return smoothstep(0.0, 0.75, 1 - d / w)


def pocket_depth(v):
    """Cette méthode permet de donner la profondeur de la poche à la hauteur v : pleine au milieu, réduite là où
    l'ouverture se resserre (sinon la paroi se replie sur elle-même au menton et à la pointe de l'ogive)."""
    return 1.05 * smoothstep(0.0, 0.32, opening_width(v))


def hood_param(i, j):
    """Cette méthode permet de donner l'angle et la hauteur relative (v) de la case (i, j) de la capuche."""
    return 2 * math.pi * HOOD_U[i % HC], HOOD_V[min(max(j, 0), HR - 1)]


def hood_at(th, v, i):
    """Cette méthode permet de placer un point de la capuche (angle, hauteur relative), bord avant avancé et tombant
    devant l'ouverture ; i choisit la dent de la pèlerine."""
    z, rx, ry, yc = interp(HOOD, v)
    if v < 0.12:  # bord de la pèlerine en lambeaux
        z -= HOOD_TEETH[i % HC] * (1 - v / 0.12) ** 2
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
        y -= pocket_depth(v) * h
    back = max(0, -math.cos(th))
    if v < 0.2:  # la pèlerine flotte un peu derrière
        y -= 0.25 * back * (1 - v / 0.2)
    return Vector((x, y, z))


def hood_pt(i, j):
    """Cette méthode permet de placer le sommet (i, j) de la capuche."""
    th, v = hood_param(i, j)
    return hood_at(th, v, i)


VOID_COLS, VOID_ROWS = 17, 24
VOID_SPAN = 0.8  # le vide couvre la poche jusqu'à 80 % de la demi-largeur de l'ouverture : bord caché dans la paroi
VOID_MIN_DEPTH = 0.35  # et seulement là où la poche est assez creuse (pas à la pointe de l'ogive ni au menton)


def void_band():
    """Cette méthode permet de trouver la bande de hauteurs (v) où la poche est assez profonde pour cacher le vide."""
    lo, hi = OPEN_V
    vs = [lo + (hi - lo) * k / 400 for k in range(401)]
    deep = [v for v in vs if pocket_depth(v) >= VOID_MIN_DEPTH]
    return deep[0], deep[-1]


def void_param(i, j):
    """Cette méthode permet de donner l'angle et la hauteur d'un sommet du vide : rangées dans la bande assez creuse
    de l'ouverture, colonnes réparties sur sa largeur (le contour suit l'ogive, donc il est lisse)."""
    lo, hi = void_band()
    v = lo + (hi - lo) * j / (VOID_ROWS - 1)
    s = 2 * i / (VOID_COLS - 1) - 1
    return (s * VOID_SPAN * opening_width(v)) % (2 * math.pi), v


def void_pt(i, j):
    """Cette méthode permet de placer un sommet du vide noir : sur le tissu de la poche, décalé vers l'ouverture le
    long de la normale (jamais au-delà du tissu : il ne peut plus percer la capuche)."""
    th, v = void_param(i, j)
    p = hood_at(th, v, 0)
    e = 1e-3
    du = hood_at(th + e, v, 0) - hood_at(th - e, v, 0)
    dv = hood_at(th, v + e, 0) - hood_at(th, v - e, 0)
    n = du.cross(dv).normalized()
    if n.y < 0:
        n = -n
    return p + n * VOID_GAP


def build_hood():
    """Cette méthode permet de construire la capuche et le vide noir qui tapisse sa poche (aucune tête)."""
    hood = grid_object("Hood", HC, HR, hood_pt)
    solidify(hood, 0.05)
    hood.data.materials.append(material("HoodCloth", (0.012, 0.012, 0.016), 0, 0.95))
    void = grid_object("Void", VOID_COLS, VOID_ROWS, void_pt, wrap=False)
    solidify(void, 0.02)
    void.data.materials.append(material("Void", (0, 0, 0), 0, 1))
    return hood, void


# ---------------------------------------------------------------- faux
SHAFT_BOTTOM = Vector((1.48, 1.18, -3.25))
SHAFT_TOP = Vector((1.22, 1.02, 3.45))
GRIP_T = 0.56  # position de la main le long du manche (0 = embout, 1 = tête)
SHAFT_R = 0.085
GRIP_R = SHAFT_R * 1.18  # rayon de la poignée (cuir), hors bourrelets


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


def grip_radius(u, v):
    """Cette méthode permet de donner le rayon relatif de la poignée (cuir enroulé en hélice) ; u autour, v le long."""
    return 1 + 0.07 * math.sin(2 * math.pi * (u * 1 - v * 9)) ** 2


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
    g.tube([shaft_point(t) for t in gt], [GRIP_R] * len(gt), segs=14, radial=grip_radius)
    g.finish(material("GripLeather", (0.11, 0.05, 0.04), 0.0, 0.85))
    # bagues de métal
    r = Builder("Rings")
    for t in (0.06, GRIP_T - 0.075, GRIP_T + 0.075, 0.93):
        a = shaft_axis(t)
        p = shaft_point(t)
        r.tube(
            [p - a * 0.035, p - a * 0.02, p + a * 0.02, p + a * 0.035],
            [SHAFT_R * 1.15, SHAFT_R * 1.32, SHAFT_R * 1.32, SHAFT_R * 1.15],
            segs=14,
        )
    r.finish(material("RingMetal", (0.5, 0.45, 0.36), 1.0, 0.3))
    # embout : collerette puis pointe
    p0 = shaft_point(0.0)
    a = shaft_axis(0.0)
    pm = Builder("Pommel")
    pm.tube(
        [p0 + a * 0.12, p0 + a * 0.02, p0 - a * 0.06, p0 - a * 0.2, p0 - a * 0.42],
        [SHAFT_R * 1.1, SHAFT_R * 1.5, SHAFT_R * 1.25, SHAFT_R * 0.7, 0.005],
        segs=10,
    )
    pm.finish(metal)
    # tête : douille autour du haut du manche, éperon arrière, sertissure de la gemme
    top = shaft_point(1.0)
    a = shaft_axis(1.0)
    h = Builder("ScytheHead")  # pas « Head » : le rig R15 a déjà une pièce Head
    h.tube(
        [top - a * 0.42, top - a * 0.36, top - a * 0.1, top + a * 0.08, top + a * 0.16],
        [SHAFT_R * 1.2, SHAFT_R * 1.55, SHAFT_R * 1.45, SHAFT_R * 1.7, SHAFT_R * 0.6],
        segs=8,
    )
    spur = [
        top + Vector((0.08, 0, -0.05)),
        top + Vector((0.3, 0, 0.02)),
        top + Vector((0.5, 0, 0.18)),
        top + Vector((0.6, 0, 0.4)),
    ]
    h.tube(spur, [0.07, 0.055, 0.035, 0.004], segs=8)
    gem_c = top + Vector((0, 0, -0.22))
    h.tube(
        [gem_c + Vector((0, -0.13, 0)), gem_c + Vector((0, -0.1, 0)), gem_c + Vector((0, 0.1, 0)),
         gem_c + Vector((0, 0.13, 0))],
        [0.1, 0.16, 0.16, 0.1],
        segs=16,
    )
    h.finish(metal)
    gem = Builder("Gem")
    for side in (1, -1):
        gem.sphere(gem_c + Vector((0, side * 0.13, 0)), 0.1, segs=14, rings=8, scale=(1, 0.45, 1))
    gem.finish(material("Gem", (0.25, 0.75, 0.65), 0.0, 0.1))
    build_blade()


# ---------------------------------------------------------------- bras squelette et manche de la cape
# contact des doigts : le centre d'un doigt passe à GRIP_R + FINGER_SINK x son rayon de l'axe (il s'enfonce un peu
# dans le cuir) ; mesuré par grip_contact()
FINGER_SINK = 0.7
FINGER_PATHS = []  # (points, rayons) des phalanges qui serrent la poignée, pour la mesure du contact


def hand_frame():
    """Cette méthode permet de donner le repère de la main sur la poignée : centre, axe du manche, côté paume, côté."""
    g = shaft_point(GRIP_T)
    ax = shaft_axis(GRIP_T)
    palm = Vector((-0.85, -0.55, 0)).normalized()  # la paume est côté corps
    palm = (palm - ax * palm.dot(ax)).normalized()
    return g, ax, palm, ax.cross(palm)


def wrap_path(g, ax, palm, side, h, a0, a1, r0, r1, step=12):
    """Cette méthode permet de suivre la poignée en arc de cercle (angles a0 -> a1 en degrés, rayons de doigt r0 ->
    r1) à la hauteur h le long du manche : chaque point est posé contre le cuir."""
    n = max(2, int(abs(a1 - a0) / step) + 1)
    pts, radii = [], []
    for k in range(n):
        s = k / (n - 1)
        a = math.radians(a0 + (a1 - a0) * s)
        rf = r0 + (r1 - r0) * s
        rr = GRIP_R + rf * FINGER_SINK
        pts.append(g + ax * (h - 0.012 * s) + (palm * math.cos(a) + side * math.sin(a)) * rr)
        radii.append(rf)
    return pts, radii


def build_arm():
    """Cette méthode permet de construire la manche (tissu) et l'avant-bras squelette dont la main serre la faux :
    phalanges courbées contre la poignée, griffes plantées dans le cuir ; l'autre bras reste caché sous la cape."""
    g, ax, palm, side = hand_frame()
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
        radial=lambda u, v: 1
        + 0.06 * math.sin(u * 2 * math.pi * 4)
        + (0.12 * math.sin(u * 2 * math.pi * 7) if v > 0.75 else 0),
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
    FINGER_PATHS.clear()
    for f in range(4):
        h = 0.105 - f * 0.07
        # métacarpe : du poignet à la jointure, posée contre la poignée côté paume
        knuckle = g + ax * h + (palm * math.cos(math.radians(18)) + side * math.sin(math.radians(18))) * (
            GRIP_R + 0.03 * FINGER_SINK + 0.012
        )
        hb.tube([wrist + side * (0.04 - f * 0.027) + ax * h * 0.4, knuckle], [0.026, 0.03], segs=7)
        hb.sphere(knuckle, 0.034)
        # trois phalanges en arc contre le cuir, articulations marquées, puis la griffe qui s'y plante
        joints = (18, 92, 165, 225)
        radii = (0.029, 0.025, 0.021, 0.017)
        for k in range(3):
            pts, rs = wrap_path(g, ax, palm, side, h - 0.004 * k, joints[k], joints[k + 1], radii[k], radii[k + 1])
            hb.tube(pts, rs, segs=7)
            hb.sphere(pts[-1], rs[-1] * 1.12)
            FINGER_PATHS.append((pts, rs))
        tip_pts, tip_rs = wrap_path(g, ax, palm, side, h - 0.016, 225, 262, 0.016, 0.003, step=8)
        # la pointe de la griffe s'enfonce jusqu'au cuir
        tip_pts[-1] = g + ax * (h - 0.03) + (
            palm * math.cos(math.radians(264)) + side * math.sin(math.radians(264))
        ) * (GRIP_R * 0.97)
        hb.tube(tip_pts, tip_rs, segs=6)
    # pouce : de l'autre côté, autour du manche vers le haut
    thumb_root = wrist - side * 0.06
    pts, rs = wrap_path(g, ax, palm, side, 0.17, -30, -150, 0.03, 0.02)
    hb.tube([thumb_root] + pts[:1], [0.032, rs[0]], segs=7)
    hb.tube(pts, rs, segs=7)
    hb.sphere(pts[len(pts) // 2], rs[len(pts) // 2] * 1.12)
    FINGER_PATHS.append((pts, rs))
    hb.finish(bone)


def build_all(drape=True):
    """Cette méthode permet de reconstruire tout le modèle de la Mort lorsqu'on lance le script."""
    mesh.clear_scene()
    random.seed(SEED)
    build_cloak(drape)
    build_hood()
    build_scythe()
    build_arm()


# ---------------------------------------------------------------- contrôles propres au modèle (pipeline.py)
def grip_contact():
    """Cette méthode permet de mesurer l'écart entre les phalanges et le maillage réel de la poignée (studs, point le
    plus proche) : négatif = le doigt s'enfonce, positif = il flotte ; renvoie (pire écart, écart moyen)."""
    deps = bpy.context.evaluated_depsgraph_get()
    grip = bpy.data.objects["Grip"].evaluated_get(deps)
    tree = BVHTree.FromObject(grip, deps)
    gaps = []
    for pts, rs in FINGER_PATHS:
        for p, rf in zip(pts, rs):
            nearest = tree.find_nearest(p)[0]
            gaps.append((p - nearest).length - rf)
    return max(gaps), sum(gaps) / len(gaps)


def void_leaks():
    """Cette méthode permet de compter les sommets du vide noir visibles de derrière, du dessus ou des côtés (il ne
    doit se voir que par l'ouverture) : rayons depuis des points de vue autour de la capuche."""
    deps = bpy.context.evaluated_depsgraph_get()
    hood = bpy.data.objects["Hood"].evaluated_get(deps)
    tree = BVHTree.FromObject(hood, deps)
    void = bpy.data.objects["Void"].evaluated_get(deps)
    me = void.to_mesh()
    pts = [void.matrix_world @ v.co for v in me.vertices]
    void.to_mesh_clear()
    eyes = [Vector(e) for e in ((0, 0, 9), (0, -9, 2), (-9, 0, 2), (9, 0, 2), (-6, -6, 6), (6, -6, 6), (0, -6, 7))]
    leaks = 0
    for p in pts:
        for eye in eyes:
            d = p - eye
            hit = tree.ray_cast(eye, d.normalized(), d.length - 1e-3)
            if hit[0] is None:
                leaks += 1
                break
    return leaks, len(pts)


def checks():
    """Cette méthode permet de rendre les mesures propres à la Mort (contact des doigts, fuites du vide) pour le
    rapport de pipeline.py ; erreurs si un défaut connu revient."""
    worst, mean = grip_contact()
    leaks, total = void_leaks()
    report = {
        "grip_gap_max": round(worst, 4),
        "grip_gap_mean": round(mean, 4),
        "void_leaks": leaks,
        "void_vertices": total,
    }
    errors = []
    if worst > 0.005:
        errors.append(f"doigts décollés de la poignée : écart maximal {worst:.3f} stud")
    if leaks:
        errors.append(f"le vide noir se voit hors de l'ouverture : {leaks} sommet(s) sur {total}")
    return report, errors


if __name__ == "__main__":
    build_all()
