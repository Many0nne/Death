"""Voile du spectre (#81) : tout le tissu, drapé par simulation sur un corps de substitution tiré de la posture.

- Shroud : suaire qui recouvre le crâne (le relief du visage se devine à travers), tombe sur les épaules et le haut de
  la poitrine, bord effiloché ;
- Cloak : robe lourde qui tombe des épaules en longs plis verticaux, trouée sur la poitrine (le torse décharné se voit
  à travers), ourlet en langues irrégulières ; à os (chaînes Cxx_y animées par Client.CloakAnimator) ;
- Tatters : longues lanières de longueurs très différentes, presque liquides, qui pendent sous la robe et traînent
  vers l'arrière ; pièce séparée (Client.DeathView peut l'estomper), skinnée sur les mêmes os que la robe ;
- Sleeves : manches très larges, épinglées aux épaules, qui pendent sous les bras, poignet en lambeaux.
"""

import math
import random

import bpy
from mathutils import Vector

from lib import cloth, mesh, organic
from lib.mesh import grid_object, interp_cr, material, smoothstep, solidify

from . import posture

GROUND = posture.GROUND
CLOTH_RGB = (0.012, 0.012, 0.016)
_rnd = random.Random(posture.SEED)


def _phases(n):
    """Cette méthode permet de tirer n phases aléatoires (graine fixe) pour les bruits de forme."""
    return [_rnd.uniform(0, 2 * math.pi) for _ in range(n)]


PH = _phases(12)


def wave(th, terms):
    """Cette méthode permet de sommer des sinusoïdes (amplitude, fréquence, phase) autour du corps : bruit périodique
    doux, sans dents de scie."""
    return sum(a * math.sin(f * th + p) for a, f, p in terms)


# ---------------------------------------------------------------- corps de substitution
def collider(ob, thickness=0.03, friction=6.0):
    """Cette méthode permet de faire d'un objet une surface de collision pour le tissu (cachée aux rendus)."""
    ob.modifiers.new("Collision", "COLLISION")
    ob.collision.thickness_outer = thickness
    ob.collision.cloth_friction = friction
    ob.hide_render = True
    return ob


def body_proxies():
    """Cette méthode permet de construire le reste du corps de substitution : cou, épaules osseuses, colonne voûtée,
    puis une colonne qui s'évase sous le bassin (la robe d'un spectre sans jambes ne retombe pas à plat)."""
    s = posture.SHOULDER
    sp = posture.SPINE
    yoke = [
        organic.Node("n", posture.NECK_BASE + Vector((0, 0, 0.12)), 0.13),
        organic.Node("r", s[1] + Vector((0.03, 0, 0)), 0.14, "n"),
        organic.Node("l", s[-1] + Vector((-0.03, 0, 0)), 0.14, "n"),
    ]
    column = [
        organic.Node("c0", sp[4] + Vector((0, -0.02, 0)), 0.3),
        organic.Node("c1", sp[3], 0.46, "c0"),
        organic.Node("c2", sp[2], 0.5, "c1"),
        organic.Node("c3", sp[1], 0.5, "c2"),
        organic.Node("c4", sp[0], 0.5, "c3"),
        organic.Node("c5", Vector((0, -0.18, -1.0)), 0.56, "c4"),
        organic.Node("c6", Vector((0, -0.32, -2.3)), 0.66, "c5"),
    ]
    out = [organic.skin_object("YokeProxy", yoke, subdiv=1), organic.skin_object("ColumnProxy", column, subdiv=1)]
    for ob in out:
        collider(ob)
    return out


def arm_proxy(side):
    """Cette méthode permet de construire le bras de substitution (capsules un peu plus épaisses que le bras) sur lequel
    pend la manche."""
    sh, el, wr = posture.arm_chain(side)
    nodes = [
        organic.Node("s", sh, 0.15),
        organic.Node("e", el, 0.12, "s"),
        organic.Node("w", wr, 0.1, "e"),
    ]
    return collider(organic.skin_object(f"ArmProxy{side}", nodes, subdiv=1), 0.02)


# ---------------------------------------------------------------- robe
COLS, ROWS = 72, 34
CHAINS, CHAIN_BONES = 16, 4
T_SKIN = 0.14  # au-dessus : épinglé pendant le drapé, os racine ; en dessous : chaînes
ROBE = [  # (t, z, demi-largeur, demi-profondeur, centre y) : étroite sous les épaules, s'évase vers le bas
    (0.0, 2.46, 0.25, 0.21, 0.02),
    (0.06, 2.34, 0.6, 0.36, 0.03),
    (0.12, 2.16, 0.8, 0.44, 0.0),
    (0.3, 1.25, 0.7, 0.5, -0.1),
    (0.55, -0.15, 0.78, 0.6, -0.2),
    (0.8, -1.4, 0.95, 0.74, -0.34),
    (1.0, -2.35, 1.1, 0.88, -0.48),
]
HEM = [(0.2, 3, PH[0]), (0.13, 5, PH[1]), (0.07, 9, PH[2]), (0.045, 14, PH[3])]
# trous du voile : (angle, hauteur, demi-largeur angulaire, demi-hauteur) ; bord déchiré par un bruit
HOLES = [(-0.38, 1.42, 0.36, 0.42), (0.22, 0.95, 0.16, 0.2), (1.25, 0.7, 0.14, 0.32), (-1.9, 1.2, 0.12, 0.2)]


def hem_drop(th):
    """Cette méthode permet de donner l'ourlet de la robe (z) à l'angle th : plus long derrière, langues irrégulières."""
    back = 0.5 - 0.5 * math.cos(th)
    return -1.95 - 0.55 * back + wave(th, HEM)


def robe_shape(i, j, ample=0.0):
    """Cette méthode permet de placer un sommet de la robe (colonne i, 0 devant ; rangée j depuis le cou) : `ample`
    élargit le bas (tissu en trop qui plissera au drapé)."""
    th = 2 * math.pi * (i % COLS) / COLS
    t = j / (ROWS - 1)
    z, rx, ry, cy = interp_cr(ROBE, t)
    if t > 0.55:  # l'ourlet suit hem_drop
        k = smoothstep(0.55, 1.0, t)
        z = z + (hem_drop(th) - ROBE[-1][1]) * k
    r = 1 + ample * smoothstep(T_SKIN, 0.5, t)
    # les épaules : la robe s'appuie dessus, plus large de côté
    x, y = rx * r * math.sin(th), cy + ry * r * math.cos(th)
    return (x, y, z)


def robe_start(i, j):
    """Cette méthode permet de placer un sommet de la robe avant le drapé (trop ample : la simulation fait les plis) ;
    un sommet du bord d'un trou glisse sur le contour déchiré, sinon le bord suivrait les cases en escalier."""
    i, j = snap_to_hole(i, j)
    return robe_shape(i, j, ample=0.16)


def hole_index(th, z):
    """Cette méthode permet de donner le trou du voile (indice dans HOLES) où tombe le point (angle, hauteur) de la
    robe, ou None ; bord déchiré par un bruit."""
    for k, (h_th, h_z, w, hgt) in enumerate(HOLES):
        d = math.atan2(math.sin(th - h_th), math.cos(th - h_th))
        rag = 1 + 0.25 * math.sin(7 * math.atan2(z - h_z, d) + PH[4 + k]) + 0.12 * math.sin(13 * d + 5 * z)
        if (d / w) ** 2 + ((z - h_z) / hgt) ** 2 < rag:
            return k
    return None


def hole_at(th, z):
    """Cette méthode permet de savoir si le point (angle, hauteur) de la robe tombe dans un trou du voile."""
    return hole_index(th, z) is not None


def _grid_hole(i, j):
    """Cette méthode permet de donner le trou où tombe le point de grille (i, j) fractionnaire, ou None."""
    th = 2 * math.pi * (i % COLS) / COLS
    return hole_index(th, robe_shape(i, j)[2])


def snap_to_hole(i, j):
    """Cette méthode permet de déplacer (en coordonnées de grille) un sommet du bord d'un trou sur le contour du trou :
    recherche par dichotomie le long de la droite qui va du centre du trou au sommet."""
    if j <= 0 or j >= ROWS - 1:
        return i, j
    faces = [((i + di) % COLS, j + dj) for di in (-1, 0) for dj in (-1, 0)]
    kept = [robe_keep(fi, fj) for fi, fj in faces]
    if all(kept) or not any(kept):
        return i, j
    removed = next(f for f, k in zip(faces, kept) if not k)
    k = _grid_hole(removed[0] + 0.5, removed[1] + 0.5)
    if k is None:
        return i, j
    h_th, h_z = HOLES[k][0], HOLES[k][1]
    ic = (h_th / (2 * math.pi) * COLS) % COLS
    jc = min((abs(robe_shape(ic, jj / 10)[2] - h_z), jj / 10) for jj in range(10 * (ROWS - 1) + 1))[1]
    di = ((i - ic + COLS / 2) % COLS) - COLS / 2
    dj = j - jc

    def inside(s):
        """Cette méthode permet de savoir si le point à la part s du centre du trou au sommet est dans le trou."""
        return _grid_hole(ic + di * s, jc + dj * s) == k

    if not inside(0):
        return i, j
    lo, hi = 0.0, 1.0
    while inside(hi) and hi < 3:
        hi *= 1.5
    for _ in range(24):
        mid = (lo + hi) / 2
        if inside(mid):
            lo = mid
        else:
            hi = mid
    s = hi
    return (ic + di * s) % COLS, jc + dj * s


def robe_keep(i, j):
    """Cette méthode permet de garder une case de la robe (False : trou du voile)."""
    th = 2 * math.pi * (i + 0.5) / COLS
    _x, _y, z = robe_shape(i + 0.5, j + 0.5)
    return not hole_at(th, z)


def expected_cloak_vertices():
    """Cette méthode permet de compter les sommets que la grille de la robe doit garder (ceux d'au moins une case non
    trouée) lorsqu'on vérifie que le drapé n'en a ni ajouté ni retiré (poids d'os recalculés d'après la grille)."""
    used = set()
    for j in range(ROWS - 1):
        for i in range(COLS):
            if robe_keep(i, j):
                used.update({(i, j), ((i + 1) % COLS, j), (i, j + 1), ((i + 1) % COLS, j + 1)})
    return len(used)


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
    s = (t - T_SKIN) / (1.0 - T_SKIN) * CHAIN_BONES
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
    """Cette méthode permet de créer l'armature de la robe (racine + chaînes), chaque os posé sur la robe drapée
    d'après les indices de grille ; la dernière chaîne descend jusqu'au bas des lanières."""
    index = mesh.grid_index(cloak)
    co = cloak.data.vertices
    arm = bpy.data.armatures.new("CloakRig")
    ob = mesh.link(bpy.data.objects.new("CloakRig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("Root")
    root.head, root.tail = (0, 0, 1.6), (0, 0, 2.2)
    for c in range(CHAINS):
        col = int(c * COLS / CHAINS)
        parent = root
        for b in range(CHAIN_BONES):
            eb = arm.edit_bones.new(f"C{c:02d}_{b}")
            j0 = round(chain_t(b) * (ROWS - 1))
            j1 = round(chain_t(b + 1) * (ROWS - 1))
            # une case trouée n'a pas de sommet : on prend la colonne voisine qui en a un
            eb.head = _grid_co(co, index, col, j0)
            eb.tail = _grid_co(co, index, col, j1)
            eb.parent = parent
            eb.use_connect = b > 0
            parent = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def _grid_co(co, index, col, j):
    """Cette méthode permet de trouver la position du sommet (col, j) de la grille, ou du plus proche sur la rangée."""
    for d in range(COLS):
        for c in (col + d, col - d):
            k = index.get((c % COLS, j))
            if k is not None:
                return co[k].co.copy()
    raise KeyError(f"rangée {j} vide")


def bone_segments(rig):
    """Cette méthode permet de relever (tête, queue) monde de chaque os de chaîne, pour skinner les lanières."""
    return {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)
            for b in rig.data.bones if b.name != "Root"}


def build_cloak(drape=True, frames=70):
    """Cette méthode permet de construire la robe trouée : drapée sur le corps de substitution (épinglée aux épaules),
    puis skinnée sur l'armature de la robe."""
    cloak = grid_object("Cloak", COLS, ROWS, robe_start if drape else robe_shape, keep=robe_keep, uv_shift=COLS // 2)
    if drape:
        mesh.set_group(cloak, "Pin", lambda i, j: 1.0 if j / (ROWS - 1) <= T_SKIN + 1e-6 else 0.0)
        cloth.drape(cloak, "Pin", frames=frames, stiffness=18.0)
        cloak.vertex_groups.remove(cloak.vertex_groups["Pin"])
    rig = build_armature(cloak)
    mesh.set_weights(cloak, robe_weights)
    solidify(cloak, 0.05)
    mod = cloak.modifiers.new("Rig", "ARMATURE")
    mod.object = rig
    cloak.parent = rig
    cloak.data.materials.append(material("CloakCloth", CLOTH_RGB, 0, 0.95))
    return rig, cloak


# ---------------------------------------------------------------- suaire
SC, SR = 60, 40
SKULL_V = 0.42  # au-dessus : le suaire épouse le crâne (calotte tendue, épinglée au drapé) ; en dessous : il pend
SKULL_VS = 0.66  # hauteur du crâne (0 sommet, 1 sous la mâchoire) où la calotte s'arrête : sous les pommettes
SKULL_HUG = 0.9  # part du relief du crâne que garde la calotte tendue (le tissu enjambe un peu les orbites)
SHROUD_HEM = [(0.07, 4, PH[5]), (0.05, 7, PH[6]), (0.035, 11, PH[7])]


def shroud_hem(th):
    """Cette méthode permet de donner le bas du suaire (z) : court devant (les clavicules et le haut des côtes se
    voient par les trous de la robe), long sur les épaules et dans le dos."""
    front = max(0.0, math.cos(th))
    return 1.72 + 0.42 * front ** 2 - 0.12 * (0.5 - 0.5 * math.cos(th)) + wave(th, SHROUD_HEM)


SHROUD_FOLDS = [(0.1, 7, PH[10]), (0.05, 11, PH[11]), (0.03, 17, PH[5])]
SHROUD_AXIS = Vector((0.0, 0.06, 0.0))  # axe vertical du rideau (repère du corps)


def support_radius(th, z):
    """Cette méthode permet de donner la distance à l'axe du corps, à l'angle th et à la hauteur z, du dessus de la robe
    (cou, épaules, poitrine) sur lequel le rideau du suaire vient se poser."""
    if z >= ROBE[0][1]:
        return 0.0
    keys = [(-k[1], k[2], k[3], k[4]) for k in ROBE]  # profil indexé par la hauteur (croissante en -z)
    rx, ry, cy = interp_cr(keys, -z)
    # rayon de l'ellipse (centrée en cy) dans la direction th, mesuré depuis l'axe du rideau
    d = Vector((math.sin(th), math.cos(th), 0.0))
    a = d.x * d.x / (rx * rx) + d.y * d.y / (ry * ry)
    b = 2 * d.y * (SHROUD_AXIS.y - cy) / (ry * ry)
    c = (SHROUD_AXIS.y - cy) ** 2 / (ry * ry) - 1
    disc = max(b * b - 4 * a * c, 0.0)
    return (-b + math.sqrt(disc)) / (2 * a)


def shroud_shape(i, j):
    """Cette méthode permet de placer un sommet du suaire : calotte tendue sur le crâne jusqu'aux pommettes, puis
    rideau qui tombe du visage et se pose sur le cou et les épaules, plis verticaux, bord effiloché."""
    u = (i % SC) / SC
    th = 2 * math.pi * u
    v = j / (SR - 1)
    if v <= SKULL_V:
        vs = 0.04 + (SKULL_VS - 0.04) * v / SKULL_V
        smooth = posture.skull_point(u, vs, relief=False)
        hug = smooth.lerp(posture.skull_point(u, vs), SKULL_HUG)
        return hug + _skull_normal(u, vs) * 0.035
    smooth = posture.skull_point(u, SKULL_VS, relief=False)
    top = smooth.lerp(posture.skull_point(u, SKULL_VS), SKULL_HUG) + _skull_normal(u, SKULL_VS) * 0.035
    k = (v - SKULL_V) / (1 - SKULL_V)
    z = top.z + (shroud_hem(th) - top.z) * k ** 0.9
    rel = top - SHROUD_AXIS
    ring = Vector((rel.x, rel.y, 0.0)).length
    # le tissu tombe d'aplomb du bord de la calotte, puis s'appuie sur le corps (+ épaisseur de la robe) : maximum
    # adouci, le rideau s'évase sur les épaules au lieu d'y faire une marche
    a = ring * (1 + 0.3 * smoothstep(0.0, 0.6, k))
    b = support_radius(th, z) + 0.08
    r = 0.5 * (a + b + math.sqrt((a - b) ** 2 + 0.12 ** 2))
    r *= 1 + smoothstep(0.0, 0.55, k) * wave(th + 0.25 * k, SHROUD_FOLDS)
    # devant, le voile pend en avant du visage (le menton ne se lit pas)
    fwd = 0.1 * max(0.0, math.cos(th)) ** 2 * smoothstep(0.0, 0.35, k)
    return SHROUD_AXIS + Vector((r * math.sin(th), r * math.cos(th) + fwd, z))


def _skull_normal(u, v):
    """Cette méthode permet de donner la normale extérieure du crâne lisse au point (u, v)."""
    e = 1e-3
    du = posture.skull_point(u + e, v, relief=False) - posture.skull_point(u - e, v, relief=False)
    dv = posture.skull_point(u, v + e, relief=False) - posture.skull_point(u, v - e, relief=False)
    n = dv.cross(du).normalized()
    c = posture.SKULL_CENTER
    if n.dot(posture.skull_point(u, v, relief=False) - c) < 0:
        n = -n
    return n


def build_shroud():
    """Cette méthode permet de construire le suaire, forme dessinée (calotte sur le crâne sculpté, rideau posé sur
    le corps) ; un drapé simulé le froissait en écharpe au cou, illisible en ombre pleine."""
    ob = grid_object("Shroud", SC, SR, shroud_shape)
    mesh.cap_row(ob, 0, inward=0.01)
    solidify(ob, 0.04)
    ob.data.materials.append(material("ShroudCloth", CLOTH_RGB, 0, 0.95))
    return ob


# ---------------------------------------------------------------- manches
SLC, SLR = 28, 24


def sleeve_frame(side):
    """Cette méthode permet de donner l'axe de la manche (points de l'épaule au poignet) et le rayon de chaque point."""
    sh, el, wr = posture.arm_chain(side)
    pts = []
    for k in range(SLR):
        s = k / (SLR - 1)
        # de l'épaule (rentrée sous la robe) au poignet, en passant par le coude
        if s < 0.5:
            p = sh.lerp(el, s / 0.5)
        else:
            p = el.lerp(wr, (s - 0.5) / 0.5)
        pts.append(p)
    return pts


def sleeve_start(side):
    """Cette méthode permet de construire la fonction de placement d'une manche avant le drapé : tube évasé autour du
    bras, épaule rentrée dans la robe, bord du poignet en lambeaux plus longs dessous."""
    pts = sleeve_frame(side)
    frames = []
    prev = None
    for k, p in enumerate(pts):
        t = (pts[min(k + 1, SLR - 1)] - pts[max(k - 1, 0)]).normalized()
        if prev is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            n = t.cross(ref).normalized()
        else:
            n = (prev - t * prev.dot(t)).normalized()
        prev = n
        frames.append((p, t, n, t.cross(n)))
    ph = PH[8] if side > 0 else PH[9]

    def fn(i, j):
        """Cette méthode permet de placer le sommet (i autour, j le long) de la manche."""
        p, t, n, b = frames[j]
        a = 2 * math.pi * i / SLC
        s = j / (SLR - 1)
        r = 0.17 + 0.42 * s ** 2.2
        d = n * math.cos(a) + b * math.sin(a)
        q = p + d * r
        if s > 0.8:  # lambeaux du poignet : plus longs sur le dessous (là où le tissu pend)
            low = max(0.0, -d.z)
            q += t * (0.1 + 0.28 * low) * (s - 0.8) / 0.2 * (1 + 0.5 * math.sin(5 * a + ph))
        return q

    return fn


def sleeve_skeleton(side):
    """Cette méthode permet de donner le squelette d'une manche (épaule, coude, poignet) : elle suit l'os du bras ou de
    l'avant-bras le plus proche (bras animables, #55)."""
    sh, el, wr = posture.arm_chain(side)
    p = "R_" if side > 0 else "L_"
    return [
        organic.Node("s", sh, 0.15, None, p + "UpperArm"),
        organic.Node("e", el, 0.12, "s", p + "UpperArm"),
        organic.Node("w", wr, 0.1, "e", p + "Forearm"),
    ]


def build_sleeves(drape=True, frames=50):
    """Cette méthode permet de construire les deux manches (pièce `Sleeves`) : épinglées à l'épaule, elles tombent sur
    le bras de substitution et pendent sous lui, très larges ; skinnées sur les os des bras."""
    obs = []
    for side in (1, -1):
        ob = grid_object(f"Sleeve{side}", SLC, SLR, sleeve_start(side))
        if drape:
            proxy = arm_proxy(side)
            mesh.set_group(ob, "Pin", lambda i, j: 1.0 if j <= 3 else 0.0)
            cloth.drape(ob, "Pin", frames=frames, stiffness=14.0, mass=0.25, bending=2.0)
            ob.vertex_groups.remove(ob.vertex_groups["Pin"])
            bpy.data.objects.remove(proxy, do_unlink=True)
        organic.skeleton_weights(ob, sleeve_skeleton(side), blend=1.5)
        obs.append(ob)
    sleeves = organic.merge_objects("Sleeves", obs)
    mesh.atlas_uv(sleeves)
    solidify(sleeves, 0.04)
    sleeves.data.materials.clear()
    sleeves.data.materials.append(material("SleeveCloth", CLOTH_RGB, 0, 0.95))
    return sleeves


# ---------------------------------------------------------------- lanières
STRIPS = 44
STRIP_ROWS = 18
STRIP_COLS = 3  # sommets en travers d'une lanière (gouttière en V adoucie par le lissage)


def strip_specs():
    """Cette méthode permet de tirer les lanières (graine fixe) : angle d'attache, longueur (bien plus longues derrière,
    certaines très courtes), largeur, torsion."""
    rnd = random.Random(posture.SEED * 7)
    out = []
    for k in range(STRIPS):
        th = 2 * math.pi * (k + rnd.uniform(-0.35, 0.35)) / STRIPS
        back = 0.5 - 0.5 * math.cos(th)
        length = 0.9 + 1.4 * back ** 1.3 + rnd.uniform(0.0, 1.0) * (0.4 + back)
        if rnd.random() < 0.2:
            length *= 0.45  # quelques lambeaux courts
        out.append({
            "th": th,
            "length": length,
            "width": rnd.uniform(0.15, 0.34),
            "twist": rnd.uniform(-0.6, 0.6),
            "sway": rnd.uniform(-0.25, 0.25),
            "phase": rnd.uniform(0, 2 * math.pi),
            "drip": rnd.random() < 0.55,
        })
    return out


def strip_root(cloak, th):
    """Cette méthode permet de trouver le point d'attache d'une lanière sous la robe drapée : un peu au-dessus de
    l'ourlet de la colonne la plus proche, légèrement rentré."""
    index = mesh.grid_index(cloak)
    i = round(th / (2 * math.pi) * COLS) % COLS
    j = ROWS - 9
    p = _grid_co(cloak.data.vertices, index, i, j)
    inward = Vector((-p.x, -(p.y + 0.3), 0)).normalized()
    return p + inward * 0.09


def strip_path(root, spec):
    """Cette méthode permet de suivre l'axe d'une lanière depuis son attache : elle tombe, s'écarte un peu du corps
    puis part vers l'arrière en s'allongeant, sans toucher le sol (le spectre flotte) ; renvoie les points."""
    out = Vector((math.sin(spec["th"]), math.cos(spec["th"]), 0))
    pts = []
    p = root.copy()
    # elle s'arrête au-dessus du sol : longueur bornée par la hauteur disponible (un peu de traîne en plus)
    length = min(spec["length"], (root.z - (GROUND + 0.35)) * 1.25)
    step = length / (STRIP_ROWS - 1)
    for k in range(STRIP_ROWS):
        pts.append(p.copy())
        s = k / (STRIP_ROWS - 1)
        drift_back = 0.1 + 0.9 * s * s
        d = Vector((0, 0, -1)) + out * (0.04 * (1 - s)) + Vector((0, -1, 0)) * drift_back * 0.45
        d += Vector((spec["sway"] * math.sin(3 * s + spec["phase"]), 0, 0))
        # près du sol, la lanière se couche vers l'arrière au lieu de descendre
        floor = GROUND + 0.3
        if p.z < floor + 0.5:
            d.z *= max(0.0, (p.z - floor) / 0.5)
        p = p + d.normalized() * step
    return pts


def strip_width(spec, s):
    """Cette méthode permet de donner la largeur d'une lanière au point s : s'effile, puis coulure (étranglement,
    goutte, pointe) pour certaines."""
    # étroite à l'attache (cachée sous la robe), pleine largeur à la sortie, puis s'effile
    w = spec["width"] * (0.35 + 0.65 * smoothstep(0.0, 0.22, s)) * (1 - 0.75 * s ** 1.2)
    if spec["drip"] and s > 0.78:
        k = (s - 0.78) / 0.22
        w *= 0.55 + 0.45 * math.cos(2.4 * math.pi * k) * (1 - k)
    return max(w, 0.004)


def build_tatters(cloak, rig):
    """Cette méthode permet de construire les lanières (pièce `Tatters`) : rubans creusés en gouttière, tordus,
    effilés en coulures ; skinnées sur les deux chaînes de la robe les plus proches."""
    from lib.mesh import Builder

    b = Builder("Tatters")
    weights = []
    segs = bone_segments(rig)
    for spec in strip_specs():
        root = strip_root(cloak, spec["th"])
        pts = strip_path(root, spec)
        out = Vector((math.sin(spec["th"]), math.cos(spec["th"]), 0))
        rows = []
        for k, p in enumerate(pts):
            s = k / (STRIP_ROWS - 1)
            t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
            across = t.cross(out).normalized()
            normal = across.cross(t)
            tw = spec["twist"] * s
            across, normal = (across * math.cos(tw) + normal * math.sin(tw),
                              normal * math.cos(tw) - across * math.sin(tw))
            w = strip_width(spec, s)
            row = []
            for m in range(STRIP_COLS):
                a = 2 * m / (STRIP_COLS - 1) - 1
                # gouttière : les bords se relèvent un peu
                row.append(p + across * (a * w) + normal * (0.25 * w * a * a))
            rows.append(row)
        vs = b.grid(rows, closed_u=False)
        for row in vs:
            for v in row:
                weights.append((v, tatter_weights(v.co, spec["th"], segs)))
    ob = b.finish(material("TatterCloth", CLOTH_RGB, 0, 0.95))
    # les sommets du bmesh sont recréés dans le même ordre : index = rang d'ajout
    groups = {}
    for k, (_v, w) in enumerate(weights):
        for name, x in w.items():
            if name not in groups:
                groups[name] = ob.vertex_groups.new(name=name)
            groups[name].add([k], x, "REPLACE")
    mesh.atlas_uv(ob)
    solidify(ob, 0.025)
    mod = ob.modifiers.new("Rig", "ARMATURE")
    mod.object = rig
    ob.parent = rig
    return ob


def tatter_weights(p, th, segs):
    """Cette méthode permet de skinner un sommet de lanière : les deux chaînes voisines (selon l'angle), puis l'os de
    la chaîne le plus proche en hauteur (le dernier sous l'ourlet), fondu entre os voisins."""
    c = (th % (2 * math.pi)) / (2 * math.pi) * CHAINS
    c0 = int(c) % CHAINS
    c1 = (c0 + 1) % CHAINS
    wc = c - int(c)
    out = {}
    for chain, wchain in ((c0, 1 - wc), (c1, wc)):
        best = []
        for b in range(CHAIN_BONES):
            head, tail = segs[f"C{chain:02d}_{b}"]
            d, _t = organic.point_segment(Vector((0, 0, p.z)), Vector((0, 0, head.z)), Vector((0, 0, tail.z)))
            best.append((d, b))
        best.sort()
        d0, b0 = best[0]
        d1, b1 = best[1]
        k = 0.5 * max(0.0, 1 - (d1 - d0) / 0.3)
        for b, x in ((b0, 1 - k), (b1, k)):
            if x > 0:
                name = f"C{chain:02d}_{b}"
                out[name] = out.get(name, 0.0) + x * wchain
    total = sum(out.values())
    return {k: v / total for k, v in out.items() if v > 1e-4}
