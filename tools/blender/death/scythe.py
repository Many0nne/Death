"""Faux du spectre (#81) : lame forgée un peu irrégulière, ébréchée, manche en bois naturel (branche à peine
redressée, nœuds), douille de fer rivetée, bagues, poignée de cuir en lanières, embout. Une MeshPart par zone de skin,
noms inchangés depuis #76 : Blade, Edge, Engraving, ScytheHead, Gem, Rings, Shaft, Grip, Pommel.
"""

import math
import random

from mathutils import Vector

from lib import mesh
from lib.mesh import Builder, lerp, material

# manche : de l'embout (t = 0) à la tête (t = 1), tenu à droite devant le corps, presque droit
SHAFT_BOTTOM = Vector((1.62, 1.28, -3.18))  # embout au-dessus du sol
SHAFT_TOP = Vector((1.30, 1.06, 3.62))  # tête et lame sous les portes de 8 studs
SHAFT_R = 0.082
GRIP_T = 0.555  # la main droite serre le manche ici
GRIP_LEN = 0.11  # demi-longueur de la poignée de cuir (en t)
GRIP_R = SHAFT_R * 1.16  # rayon de la poignée, hors bourrelets des lanières

_rnd = random.Random(8101)
# nœuds du bois : (t, angle, hauteur, largeur) ; tirés une fois, la graine est fixe
KNOTS = [(_rnd.uniform(0.05, 0.95), _rnd.uniform(0, 2 * math.pi), _rnd.uniform(0.4, 0.9), _rnd.uniform(0.02, 0.04))
         for _ in range(14)]
KNOTS = [k for k in KNOTS if abs(k[0] - GRIP_T) > GRIP_LEN + 0.03]
# moignons de branches coupées : (t, angle, longueur, inclinaison vers le haut) ; loin de la main et de la lame
STUBS = [(0.24, 2.4, 0.14, 0.5), (0.78, -0.9, 0.11, 0.6), (0.36, -2.2, 0.08, 0.4)]


def shaft_point(t):
    """Cette méthode permet de suivre l'axe du manche (t de 0 à 1) : branche naturelle, deux courbures douces."""
    p = lerp(SHAFT_BOTTOM, SHAFT_TOP, t)
    p.x += 0.07 * math.sin(math.pi * t * 1.7) + 0.018 * math.sin(math.pi * t * 5.3 + 0.4)
    p.y += 0.05 * math.sin(math.pi * t) - 0.015 * math.sin(math.pi * t * 4.1)
    return p


def shaft_axis(t):
    """Cette méthode permet de donner la direction du manche au point t."""
    return (shaft_point(min(1, t + 0.01)) - shaft_point(max(0, t - 0.01))).normalized()


def shaft_radius(t):
    """Cette méthode permet de donner le rayon du manche au point t : plus épais en bas, aminci sous la tête,
    renflé irrégulièrement comme une branche."""
    return SHAFT_R * (1.12 - 0.2 * t + 0.045 * math.sin(t * 23.0) + 0.03 * math.sin(t * 61.0 + 1.3))


def wood_relief(u, t):
    """Cette méthode permet de moduler le rayon du bois (u autour, t le long) : section un peu ovale, fil du bois qui
    tourne lentement, nœuds en bosses."""
    th = 2 * math.pi * u
    r = 1 + 0.06 * math.cos(2 * th + 1.3 * t * 6) + 0.03 * math.cos(3 * th + 2.1)
    # fil du bois : côtes longues qui tournent lentement
    r += 0.025 * math.cos(7 * th + 9.0 * t)
    for kt, ka, kh, kw in KNOTS:
        dt = (t - kt) / kw
        da = math.atan2(math.sin(th - ka), math.cos(th - ka))
        # bourrelet autour du nœud, creux au milieu (l'œil du nœud)
        ring = math.exp(-dt * dt - da * da * 4)
        eye = math.exp(-(dt * dt + da * da * 4) * 6)
        r += 0.45 * kh * ring - 0.3 * kh * eye
    for st, sa, _sl, _su in STUBS:
        dt = (t - st) / 0.03
        da = math.atan2(math.sin(th - sa), math.cos(th - sa))
        r += 0.25 * math.exp(-dt * dt - da * da * 3)  # le bois enfle à la base de la branche
    return r


# lame : arc dans le plan XZ (face vers +Y), dos à l'extérieur, fil à l'intérieur, vers la gauche au-dessus du crâne
BLADE_R = 2.75
BLADE_A0, BLADE_A1 = math.radians(80), math.radians(170)
# profil en travers (w de 0, le dos, à 1, le fil) : dos renforcé, plat avec une rainure étroite, biseau, puis le fil
SPINE_W = 0.1  # dos renforcé
FULLER = (0.15, 0.3)  # rainure (gouttière) le long du dos
BEVEL_W = 0.56  # début du biseau
EDGE_BAND = 0.13  # largeur du fil (pièce Edge), prise sur le biseau
# ébréchures du fil : (position s, demi-largeur, profondeur en part de la largeur de la lame) ; franches (en V
# ou en U à bord vif), certaines mordent au-delà du fil, dans le biseau
CHIPS = [(0.13, 0.012, 0.11), (0.24, 0.022, 0.2), (0.33, 0.008, 0.08), (0.45, 0.03, 0.26), (0.52, 0.01, 0.12),
         (0.63, 0.018, 0.17), (0.74, 0.012, 0.1), (0.86, 0.02, 0.14)]


def blade_frame():
    """Cette méthode permet de calculer le centre de l'arc de la lame à partir du haut du manche."""
    root = shaft_point(0.985) + Vector((-0.04, 0, 0.06))
    return root - BLADE_R * Vector((math.cos(BLADE_A0), 0, math.sin(BLADE_A0)))


def blade_width(s):
    """Cette méthode permet de donner la largeur de la lame (dos -> fil) au point s (0 talon, 1 pointe) : talon large,
    ventre qui s'élargit un peu puis pointe effilée ; bord forgé légèrement ondulé."""
    base = 0.62 * (1 - s) ** 0.8 * (0.86 + 0.18 * math.sin(math.pi * min(1, s * 2.4)))
    return base * (1 + 0.025 * math.sin(s * 37.0) + 0.015 * math.sin(s * 91.0))


def chip_depth(s):
    """Cette méthode permet de donner la profondeur d'ébréchure au point s (part de la largeur de la lame) : profil
    en V vif (petits éclats) ou en U à flancs raides (grands)."""
    d = 0.0
    for cs, cw, cd in CHIPS:
        k = abs(s - cs) / cw
        if k < 1:
            d = max(d, cd * ((1 - k) if cw < 0.015 else (1 - k ** 4)))
    return d


def edge_line(s):
    """Cette méthode permet de donner où finit la lame (w) au point s : le fil, reculé aux ébréchures."""
    return 1.0 - chip_depth(s)


def blade_thickness(s, w):
    """Cette méthode permet de donner la demi-épaisseur de la lame au point (s, w) : dos renforcé arrondi, plat, rainure
    creuse, biseau droit jusqu'au fil ; s'amincit vers la pointe, épaisseur de fer battu un peu irrégulière."""
    flat = 0.03
    if w < SPINE_W:
        th = flat + 0.022 * math.cos(0.5 * math.pi * w / SPINE_W) ** 0.6
    elif w < BEVEL_W:
        th = flat
        if FULLER[0] < w < FULLER[1]:
            th -= 0.014 * math.sin(math.pi * (w - FULLER[0]) / (FULLER[1] - FULLER[0])) ** 0.7
    else:
        k = (w - BEVEL_W) / (1 - BEVEL_W)
        th = flat * (1 - k) + 0.0025 * k
    return th * (1 - 0.55 * s) * (1 + 0.06 * math.sin(s * 19.0 + w * 3))


def fuller_span(s):
    """Cette méthode permet de dire si la rainure existe au point s (elle s'arrête avant le talon et la pointe)."""
    return 0.05 < s < 0.74


def blade_point(s, w, side):
    """Cette méthode permet de placer un point de la lame : s le long, w de 0 (dos) à 1 (fil, tel que forgé), side =
    +1/-1 face ; la rainure ne court que sur fuller_span."""
    c = blade_frame()
    a = BLADE_A0 + (BLADE_A1 - BLADE_A0) * s
    back = 0.012 * math.sin(s * 13.0 + 0.7)  # dos martelé
    r = BLADE_R + back - blade_width(s) * w
    th = blade_thickness(s, w)
    if not fuller_span(s) and FULLER[0] < w < FULLER[1]:
        th = max(th, 0.03 * (1 - 0.55 * s) * (1 + 0.06 * math.sin(s * 19.0 + w * 3)))
    return c + Vector((r * math.cos(a), side * th, r * math.sin(a)))


# colonnes de la lame en travers (w) : placées sur le profil (dos, rainure, plat, début du biseau) ; le biseau
# jusqu'au fil est ensuite partagé en BEVEL_COLS
BLADE_COLS = (0.0, 0.04, 0.08, 0.11, 0.15, 0.19, 0.225, 0.26, 0.3, 0.38, 0.47, BEVEL_W)
BEVEL_COLS = 2
BLADE_ROWS = 80


def build_blade():
    """Cette méthode permet de construire la lame (dos, plat, rainure, biseau), son fil ébréché et le fond de la
    rainure (pièce Engraving, oxydée), trois MeshParts distinctes pour les skins ; les ébréchures mordent les deux
    premières."""
    rows_s = [k / BLADE_ROWS for k in range(BLADE_ROWS + 1)]

    def strip(name, columns, mat):
        """Cette méthode permet de tisser une bande de la lame (colonnes w(s) données), les deux faces."""
        b = Builder(name)
        rows = []
        for s in rows_s:
            ws = columns(s)
            ring = [(w, 1) for w in ws] + [(w, -1) for w in reversed(ws)]
            rows.append([blade_point(s, w, side) for (w, side) in ring])
        b.grid(rows, cap_start=True, cap_end=True)
        return b.finish(mat)

    def edge_lo(s):
        """Cette méthode permet de placer le début du fil : à EDGE_BAND du bout, sans passer sous le biseau."""
        return max(BEVEL_W + 0.02, edge_line(s) - EDGE_BAND)

    def blade_cols(s):
        """Cette méthode permet de donner les colonnes du corps de la lame au point s."""
        lo = edge_lo(s)
        fixed = [w for w in BLADE_COLS if w < lo - 0.01]
        start = fixed[-1]
        return fixed + [start + (lo - start) * (k + 1) / BEVEL_COLS for k in range(BEVEL_COLS)]

    def edge_cols(s):
        """Cette méthode permet de donner les colonnes du fil au point s."""
        lo, hi = edge_lo(s), edge_line(s)
        return [lo + (hi - lo) * k / 3 for k in range(4)]

    strip("Blade", blade_cols, material("BladeSteel", (0.22, 0.22, 0.24), 1.0, 0.5))
    strip("Edge", edge_cols, material("EdgeSteel", (0.62, 0.63, 0.66), 1.0, 0.2))
    # fond de la rainure, oxydé, posé juste au-dessus de la gouttière (mêmes rangées et colonnes que la lame)
    g = Builder("Engraving")
    cols = [w for w in BLADE_COLS if FULLER[0] <= w <= FULLER[1]]
    cols[0] += 0.008
    cols[-1] -= 0.008
    for side in (1, -1):
        rows = []
        for s in rows_s:
            if not 0.07 <= s <= 0.72:
                continue
            row = []
            for w in cols:
                p = blade_point(s, w, side)
                p.y += side * 0.002
                row.append(p)
            rows.append(row)
        g.grid(rows, closed_u=False)
    g.finish(material("Engraving", (0.12, 0.11, 0.1), 1.0, 0.55))  # acier oxydé, proche de la lame (pas une bande sombre)


def grip_radius(u, v):
    """Cette méthode permet de donner le rayon relatif de la poignée : lanières de cuir enroulées en hélice, bords
    qui se chevauchent."""
    ph = (u - v * 7.0) % 1.0
    return 1 + 0.06 * min(1.0, ph * 6) * (1 - ph) ** 0.5


def build_scythe():
    """Cette méthode permet de construire la faux : manche de bois, poignée, bagues, embout, douille, gemme et lame."""
    wood = material("ShaftWood", (0.16, 0.11, 0.07), 0.0, 0.75)
    iron = material("HeadMetal", (0.13, 0.12, 0.12), 1.0, 0.55)
    N = 84
    ts = [k / N for k in range(N + 1)]
    b = Builder("Shaft")
    b.tube([shaft_point(t) for t in ts], [shaft_radius(t) for t in ts], segs=14,
           radial=lambda u, v: wood_relief(u, v))
    main_faces = len(b.bm.faces)
    # moignons de branches coupées net, un peu relevés
    for st, sa, sl, su in STUBS:
        p = shaft_point(st)
        ax = shaft_axis(st)
        ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
        e1 = ax.cross(ref).normalized()
        e2 = ax.cross(e1)
        out = (e1 * math.cos(sa) + e2 * math.sin(sa)).normalized()
        d = (out + ax * su).normalized()
        r0 = shaft_radius(st) * 0.55
        b.tube([p + out * shaft_radius(st) * 0.4, p + d * (shaft_radius(st) + sl * 0.5), p + d * (shaft_radius(st) + sl)],
               [r0, r0 * 0.8, r0 * 0.72], segs=8, radial=lambda u, v: 1 + 0.06 * math.sin(2 * math.pi * u * 3))
    shaft_uv(b.finish(wood), main_faces)
    # poignée : lanières de cuir enroulées sous la main, un bout libre qui pend
    g = Builder("Grip")
    gt = [GRIP_T - GRIP_LEN + 2 * GRIP_LEN * k / 34 for k in range(35)]
    g.tube([shaft_point(t) for t in gt], [GRIP_R] * len(gt), segs=14, radial=grip_radius)
    end = shaft_point(GRIP_T - GRIP_LEN)
    a = shaft_axis(GRIP_T - GRIP_LEN)
    tail = [end + Vector((0.0, 0.03 * k, 0)) - a * (0.07 * k) + Vector((0.02 * k * k, 0, 0)) for k in range(5)]
    g.tube(tail, [0.03, 0.028, 0.024, 0.018, 0.008], segs=6)
    g.finish(material("GripLeather", (0.09, 0.05, 0.035), 0.0, 0.85))
    # bagues de fer battu (un peu irrégulières)
    r = Builder("Rings")
    for k, t in enumerate((0.05, GRIP_T - GRIP_LEN - 0.012, GRIP_T + GRIP_LEN + 0.012, 0.935)):
        ax = shaft_axis(t)
        p = shaft_point(t)
        rr = shaft_radius(t)
        r.tube([p - ax * 0.04, p - ax * 0.025, p + ax * 0.025, p + ax * 0.04],
               [rr * 1.05, rr * 1.28, rr * 1.3, rr * 1.06], segs=14,
               radial=lambda u, v, k=k: 1 + 0.04 * math.sin(2 * math.pi * u * 3 + k))
    r.finish(material("RingMetal", (0.2, 0.17, 0.14), 1.0, 0.5))
    # embout : virole puis courte pointe
    p0 = shaft_point(0.0)
    a = shaft_axis(0.0)
    pm = Builder("Pommel")
    pm.tube([p0 + a * 0.1, p0 + a * 0.02, p0 - a * 0.05, p0 - a * 0.16, p0 - a * 0.34],
            [SHAFT_R * 1.15, SHAFT_R * 1.45, SHAFT_R * 1.2, SHAFT_R * 0.65, 0.006], segs=10)
    pm.finish(iron)
    build_head(iron)
    build_blade()


LANGET = (0.94, 0.855)  # attelles : de la douille (t) jusqu'à leur pointe sur le manche


def shaft_uv(ob, main_faces):
    """Cette méthode permet de séparer les UV du manche (cuisson) : le tube garde son dépliage (u autour, v le long :
    le fil du bois suit le manche) sur le bas de la carte, chaque moignon a sa case dans une bande en haut."""
    uv = ob.data.uv_layers.active.data
    stub_faces = (len(ob.data.polygons) - main_faces) // max(1, len(STUBS))
    for p in ob.data.polygons:
        for li in p.loop_indices:
            u, v = uv[li].uv
            if p.index < main_faces:
                uv[li].uv = (u, v * 0.88)
            else:
                k = min(len(STUBS) - 1, (p.index - main_faces) // max(1, stub_faces))
                uv[li].uv = (k / len(STUBS) + u * 0.95 / len(STUBS), 0.9 + v * 0.09)


def build_head(iron):
    """Cette méthode permet de construire la douille forgée (collier autour du manche, soie qui part vers la lame,
    rivets, éperon) et la gemme sertie des deux côtés."""
    top = shaft_point(1.0)
    a = shaft_axis(1.0)
    h = Builder("ScytheHead")  # pas « Head » : le rig R15 a déjà une pièce Head
    # douille forgée : deux colliers en bourrelet, corps martelé, chapeau
    prof = [(-0.46, 1.16), (-0.44, 1.42), (-0.4, 1.46), (-0.37, 1.3), (-0.2, 1.32), (-0.1, 1.34), (-0.06, 1.55),
            (-0.02, 1.58), (0.02, 1.4), (0.08, 1.5), (0.14, 0.72)]
    h.tube([top + a * z for z, _r in prof], [SHAFT_R * r for _z, r in prof], segs=14,
           radial=lambda u, v: 1 + 0.035 * math.sin(2 * math.pi * u * 3 + 1.1) + 0.02 * math.sin(2 * math.pi * u * 7))
    # attelles : deux bandes de fer battu qui descendent le long du manche (devant, derrière), rivetées
    ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
    e1 = a.cross(ref).normalized()
    e2 = a.cross(e1)
    for side_v in (e2, -e2):
        pts, rads = [], []
        for k in range(10):
            t = LANGET[0] - (LANGET[0] - LANGET[1]) * k / 9
            p = shaft_point(t)
            pts.append(p + side_v * shaft_radius(t) * 0.92)
            rads.append(0.05 * (1 - 0.4 * (k / 9) ** 1.5))
        # bande plate plaquée sur le bois (section aplatie), bout en pointe
        h.tube(pts, rads, segs=10, radial=lambda u, v: 1 - 0.78 * abs(math.sin(2 * math.pi * u)) ** 1.2)
        for t in (LANGET[0] - 0.02, LANGET[0] - 0.05, LANGET[1] + 0.01):
            p = shaft_point(t) + side_v * (shaft_radius(t) * 0.92 + 0.018)
            h.sphere(p, 0.016, segs=8, rings=4)
    # soie : lame de fer aplatie qui relie la douille au talon de la lame
    c = blade_frame()
    a0 = BLADE_A0 - math.radians(3)
    heel = c + Vector((BLADE_R * math.cos(a0), 0, BLADE_R * math.sin(a0))) - Vector((0.03, 0, 0.12))
    pts = [top - a * 0.05, lerp(top - a * 0.05, heel, 0.5) + Vector((0, 0, 0.03)), heel]
    h.tube(pts, [0.07, 0.06, 0.055], segs=8, radial=lambda u, v: 1 - 0.55 * abs(math.sin(2 * math.pi * u)) ** 2)
    # rivets
    for k, t in enumerate((0.2, 0.55)):
        p = lerp(pts[0], pts[2], t)
        for side in (1, -1):
            h.sphere(p + Vector((0, side * 0.035, 0)), 0.024, segs=8, rings=4, scale=(1, 0.6, 1))
    # éperon arrière, court et recourbé
    spur = [top + Vector((0.07, 0, -0.06)), top + Vector((0.24, 0, 0.0)), top + Vector((0.36, 0, 0.13)),
            top + Vector((0.4, 0, 0.3))]
    h.tube(spur, [0.06, 0.045, 0.028, 0.004], segs=8, radial=lambda u, v: 1 - 0.4 * abs(math.sin(2 * math.pi * u)))
    gem_c = top + Vector((0, 0, -0.26))
    # sertissures : une coupelle de chaque côté de la douille, la gemme y affleure
    for side in (1, -1):
        h.tube([gem_c + Vector((0, side * y, 0)) for y in (0.07, 0.11, 0.125, 0.135)], [0.072, 0.088, 0.086, 0.074],
               segs=14, cap=True, radial=lambda u, v: 1 + 0.06 * math.cos(2 * math.pi * u * 6) * v)
    head = h.finish(iron)
    # tubes, sphères et coupelles se chevauchent en UV : dépliage en îlots pour la cuisson
    mesh.atlas_uv(head)
    gem = Builder("Gem")
    for side in (1, -1):
        gem.sphere(gem_c + Vector((0, side * 0.12, 0)), 0.068, segs=12, rings=6, scale=(1, 0.45, 1))
    gem.finish(material("Gem", (0.35, 0.55, 0.45), 0.0, 0.2))


# ---------------------------------------------------------------- main droite sur la poignée
def hand_frame():
    """Cette méthode permet de donner le repère de la main sur la poignée : centre, axe du manche (vers la tête), côté
    paume (vers le poignet, côté corps), côté (axe x paume)."""
    g = shaft_point(GRIP_T)
    ax = shaft_axis(GRIP_T)
    palm = Vector((-0.8, -0.6, -0.05)).normalized()
    palm = (palm - ax * palm.dot(ax)).normalized()
    return g, ax, palm, ax.cross(palm)


def around(angle_deg, h, radius):
    """Cette méthode permet de placer un point autour de la poignée : angle depuis le côté paume (degrés, vers `side`),
    hauteur h le long du manche, distance `radius` à l'axe."""
    g, ax, palm, side = hand_frame()
    a = math.radians(angle_deg)
    return g + ax * h + (palm * math.cos(a) + side * math.sin(a)) * radius


def hand_wrist():
    """Cette méthode permet de placer le poignet droit : côté corps de la poignée, l'avant-bras vient d'en dessous."""
    g, ax, palm, side = hand_frame()
    return g + palm * 0.46 - ax * 0.13 + side * 0.06
