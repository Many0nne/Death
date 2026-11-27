"""Faux du spectre (#81) : lame forgée un peu irrégulière, ébréchée, manche en bois naturel (branche à peine
redressée, nœuds), douille de fer rivetée, bagues, poignée de cuir en lanières, embout. Une MeshPart par zone de skin,
noms inchangés depuis #76 : Blade, Edge, Engraving, ScytheHead, Gem, Rings, Shaft, Grip, Pommel.
"""

import math
import random

from mathutils import Vector

from lib.mesh import Builder, lerp, material

# manche : de l'embout (t = 0) à la tête (t = 1), tenu à droite devant le corps, presque droit
SHAFT_BOTTOM = Vector((1.62, 1.28, -3.42))
SHAFT_TOP = Vector((1.30, 1.06, 4.12))
SHAFT_R = 0.082
GRIP_T = 0.555  # la main droite serre le manche ici
GRIP_LEN = 0.11  # demi-longueur de la poignée de cuir (en t)
GRIP_R = SHAFT_R * 1.16  # rayon de la poignée, hors bourrelets des lanières

_rnd = random.Random(8101)
# nœuds du bois : (t, angle, hauteur, largeur) ; tirés une fois, la graine est fixe
KNOTS = [(_rnd.uniform(0.05, 0.95), _rnd.uniform(0, 2 * math.pi), _rnd.uniform(0.25, 0.6), _rnd.uniform(0.015, 0.03))
         for _ in range(9)]
KNOTS = [k for k in KNOTS if abs(k[0] - GRIP_T) > GRIP_LEN + 0.03]


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
    """Cette méthode permet de donner le rayon du manche au point t : plus épais en bas, aminci sous la tête."""
    return SHAFT_R * (1.12 - 0.2 * t + 0.03 * math.sin(t * 23.0))


def wood_relief(u, t):
    """Cette méthode permet de moduler le rayon du bois (u autour, t le long) : section un peu ovale, fil du bois qui
    tourne lentement, nœuds en bosses."""
    th = 2 * math.pi * u
    r = 1 + 0.05 * math.cos(2 * th + 1.3 * t * 6) + 0.025 * math.cos(3 * th + 2.1)
    for kt, ka, kh, kw in KNOTS:
        dt = (t - kt) / kw
        da = math.atan2(math.sin(th - ka), math.cos(th - ka))
        r += 0.35 * kh * math.exp(-dt * dt - da * da * 5)
    return r


# lame : arc dans le plan XZ (face vers +Y), dos à l'extérieur, fil à l'intérieur, vers la gauche au-dessus du crâne
BLADE_R = 2.75
BLADE_A0, BLADE_A1 = math.radians(80), math.radians(170)
EDGE_W = 0.8  # part de la largeur occupée par le corps de lame (le fil prend le reste)
# ébréchures du fil : (position s, demi-largeur, profondeur en part de la bande du fil)
CHIPS = [(0.18, 0.012, 0.85), (0.31, 0.02, 0.6), (0.47, 0.008, 0.9), (0.56, 0.028, 0.45), (0.71, 0.014, 0.8),
         (0.83, 0.01, 0.55)]


def blade_frame():
    """Cette méthode permet de calculer le centre de l'arc de la lame à partir du haut du manche."""
    root = shaft_point(0.985) + Vector((-0.04, 0, 0.06))
    return root - BLADE_R * Vector((math.cos(BLADE_A0), 0, math.sin(BLADE_A0)))


def blade_width(s):
    """Cette méthode permet de donner la largeur de la lame (dos -> fil) au point s (0 talon, 1 pointe) : talon large,
    ventre qui s'élargit un peu puis pointe effilée ; bord forgé légèrement ondulé."""
    base = 0.66 * (1 - s) ** 0.8 * (0.86 + 0.18 * math.sin(math.pi * min(1, s * 2.4)))
    return base * (1 + 0.025 * math.sin(s * 37.0) + 0.015 * math.sin(s * 91.0))


def chip_depth(s):
    """Cette méthode permet de donner la profondeur d'ébréchure du fil (0 à 1, en part de la bande du fil) au point s."""
    d = 0.0
    for cs, cw, cd in CHIPS:
        k = abs(s - cs) / cw
        if k < 1:
            d = max(d, cd * (1 - k * k) ** 0.6)
    return d


def blade_point(s, w, side):
    """Cette méthode permet de placer un point de la lame : s le long, w de 0 (dos) à 1 (fil), side = +1/-1 face ; le
    fil recule aux ébréchures, l'épaisseur varie comme un fer battu."""
    c = blade_frame()
    a = BLADE_A0 + (BLADE_A1 - BLADE_A0) * s
    if w > EDGE_W:
        w = EDGE_W + (w - EDGE_W) * (1 - chip_depth(s))
    back = 0.012 * math.sin(s * 13.0 + 0.7)  # dos martelé
    r = BLADE_R + back - blade_width(s) * w
    th = 0.06 * (1 - w) ** 0.55 + 0.005
    if 0.2 < w < 0.6 and 0.06 < s < 0.74:
        th -= 0.02 * math.sin(math.pi * (w - 0.2) / 0.4) * math.sin(math.pi * (s - 0.06) / 0.68) ** 0.3  # gouttière
    th *= (1 - 0.55 * s) * (1 + 0.08 * math.sin(s * 19.0 + w * 3))
    return c + Vector((r * math.cos(a), side * th, r * math.sin(a)))


def build_blade():
    """Cette méthode permet de construire la lame (corps forgé), son fil ébréché et le panneau gravable de la gouttière,
    trois MeshParts distinctes pour les skins."""
    S, W = 72, 8
    for name, w0, w1, mat in (
        ("Blade", 0.0, EDGE_W, material("BladeSteel", (0.22, 0.22, 0.24), 1.0, 0.5)),
        ("Edge", EDGE_W, 1.0, material("EdgeSteel", (0.62, 0.63, 0.66), 1.0, 0.2)),
    ):
        b = Builder(name)
        ws = [w0 + (w1 - w0) * k / W for k in range(W + 1)]
        ring = [(w, 1) for w in ws] + [(w, -1) for w in reversed(ws)]
        rows = [[blade_point(s, w, side) for (w, side) in ring] for s in (k / S for k in range(S + 1))]
        b.grid(rows, cap_start=True, cap_end=True)
        b.finish(mat)
    g = Builder("Engraving")
    for side in (1, -1):
        rows = []
        for k in range(29):
            s = 0.1 + 0.6 * k / 28
            row = []
            for m in range(5):
                w = 0.27 + 0.26 * m / 4
                p = blade_point(s, w, side)
                p.y += side * 0.003
                row.append(p)
            rows.append(row)
        g.grid(rows, closed_u=False)
    g.finish(material("Engraving", (0.14, 0.14, 0.15), 1.0, 0.55))


def grip_radius(u, v):
    """Cette méthode permet de donner le rayon relatif de la poignée : lanières de cuir enroulées en hélice, bords
    qui se chevauchent."""
    ph = (u - v * 7.0) % 1.0
    return 1 + 0.06 * min(1.0, ph * 6) * (1 - ph) ** 0.5


def build_scythe():
    """Cette méthode permet de construire la faux : manche de bois, poignée, bagues, embout, douille, gemme et lame."""
    wood = material("ShaftWood", (0.16, 0.11, 0.07), 0.0, 0.75)
    iron = material("HeadMetal", (0.13, 0.12, 0.12), 1.0, 0.55)
    N = 56
    ts = [k / N for k in range(N + 1)]
    b = Builder("Shaft")
    b.tube([shaft_point(t) for t in ts], [shaft_radius(t) for t in ts], segs=12,
           radial=lambda u, v: wood_relief(u, v))
    b.finish(wood)
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


def build_head(iron):
    """Cette méthode permet de construire la douille forgée (collier autour du manche, soie qui part vers la lame,
    rivets, éperon) et la gemme sertie des deux côtés."""
    top = shaft_point(1.0)
    a = shaft_axis(1.0)
    h = Builder("ScytheHead")  # pas « Head » : le rig R15 a déjà une pièce Head
    h.tube([top - a * 0.46, top - a * 0.4, top - a * 0.12, top + a * 0.06, top + a * 0.14],
           [SHAFT_R * 1.18, SHAFT_R * 1.5, SHAFT_R * 1.42, SHAFT_R * 1.62, SHAFT_R * 0.7], segs=10,
           radial=lambda u, v: 1 + 0.05 * math.sin(2 * math.pi * u * 2 + 1.1) * (1 - v))
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
    h.tube([gem_c + Vector((0, -0.12, 0)), gem_c + Vector((0, -0.095, 0)), gem_c + Vector((0, 0.095, 0)),
            gem_c + Vector((0, 0.12, 0))], [0.075, 0.12, 0.12, 0.075], segs=14)
    h.finish(iron)
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
