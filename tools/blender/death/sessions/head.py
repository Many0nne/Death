"""Séance de sculpt de la tête (#89) : le suaire tendu sur un crâne étroit. Références : refs-81 `5850d62d` (crâne
qui tend le tissu, plis qui en tombent), `502f7a57` (crâne : orbites profondes, pommettes, dents), `b916cdf2` (tissu
qui coule du crâne).

Ordre d'un sculpteur : grandes masses (arcade, pommettes, mâchoire), creux (orbites, joues, nez), puis plis de
tension qui partent des reliefs, enfin les petits plis et un lissage léger. Symétrie miroir X pour les reliefs
pairs ; les traits du milieu (nez, menton) sans symétrie.
"""

import math

from mathutils import Vector

from .. import brush, posture, veil

LEVELS = 3


def at(u, v, lift=0.0):
    """Cette méthode permet de placer un point sur le tissu posé sur le crâne (u autour, 0 devant ; v de 0 au sommet
    à 1 sous la mâchoire), relevé de `lift` le long de la normale."""
    return veil.cloth_on_skull(u, v) + veil._skull_normal(u, v) * lift


def normal(u, v):
    """Cette méthode permet de donner la direction de vue d'un trait : la normale du crâne au point."""
    return veil._skull_normal(u, v)


def path(pairs, lift=0.0):
    """Cette méthode permet de tracer un trait par points (u, v) sur le crâne ; renvoie (points, vue au milieu)."""
    pts = [at(u, v, lift) for u, v in pairs]
    mu = sum(p[0] for p in pairs) / len(pairs)
    mv = sum(p[1] for p in pairs) / len(pairs)
    return pts, normal(mu, mv)


def arc(u0, v0, ru, rv, a0, a1, n=12):
    """Cette méthode permet de donner les points (u, v) d'un arc d'ellipse (orbite, contour de joue)."""
    return [(u0 + ru * math.cos(a0 + (a1 - a0) * k / (n - 1)), v0 + rv * math.sin(a0 + (a1 - a0) * k / (n - 1)))
            for k in range(n)]


def s(pairs, radius, strength, name, invert=False, sym=True, lift=0.0, spacing=0.12):
    """Cette méthode permet de jouer un trait de brosse sur le visage (points (u, v)), symétrique ou non."""
    brush.symmetry(x=sym)
    pts, view = path(pairs, lift)
    return brush.stroke(pts, radius, strength, view=view, invert=invert, brush=name, spacing=spacing)


def column(ob, u, v_from, v_to=1.0):
    """Cette méthode permet de suivre une colonne réelle de la grille du suaire (la plus proche de l'angle u), de la
    rangée relative v_from à v_to : points posés sur la surface, du crâne jusqu'au rideau."""
    from lib import mesh

    index = mesh.grid_index(ob)
    cols = veil._shroud_columns()
    i = min(range(veil.SC), key=lambda k: abs(((cols[k] - u + 0.5) % 1.0) - 0.5))
    j0, j1 = round(v_from * (veil.SR - 1)), round(v_to * (veil.SR - 1))
    co = ob.data.vertices
    return [ob.matrix_world @ co[index[(i, j)]].co for j in range(j0, j1 + 1) if (i, j) in index]


def run(ob):
    """Cette méthode permet de sculpter le suaire `ob` (multirésolution LEVELS) du début à la fin."""
    # lignes de chute relevées sur la base, avant la multirésolution
    falls = [(column(ob, u, a, b), r) for u, a, b, r in FALLS]
    brush.begin(ob, LEVELS)
    # ---- grandes masses
    # arcade sourcilière : un rebord osseux plat au-dessus des orbites
    s(arc(0.07, 0.51, 0.07, 0.05, math.pi * 1.1, math.pi * 1.9, 10), 0.05, 0.3, "Clay Strips")
    # pommettes (os zygomatique) : relief sous l'orbite, arcade qui file vers l'oreille
    s([(0.11, 0.66), (0.145, 0.645), (0.18, 0.615)], 0.045, 0.45, "Clay Strips")
    s([(0.18, 0.615), (0.215, 0.58)], 0.045, 0.3, "Smooth")
    # mâchoire : branche montante puis corps de la mandibule jusqu'au menton
    s([(0.19, 0.76), (0.16, 0.85), (0.1, 0.9), (0.04, 0.93)], 0.035, 0.35, "Clay Strips")
    s([(0.0, 0.92), (0.02, 0.925)], 0.05, 0.35, "Clay Strips")  # menton
    # maxillaire et rangée de dents : bourrelet arrondi sous le nez
    s(arc(0.0, 0.83, 0.07, 0.03, math.pi * 1.05, math.pi * 1.95, 9), 0.035, 0.3, "Clay Strips", sym=False)
    # ---- creux
    # orbites profondes, plus creuses en haut et vers le nez
    s(arc(0.07, 0.56, 0.03, 0.03, 0, 2 * math.pi, 14), 0.06, 0.45, "Draw", invert=True)
    s([(0.05, 0.54), (0.08, 0.535), (0.1, 0.55)], 0.04, 0.35, "Draw", invert=True)
    s(arc(0.07, 0.56, 0.035, 0.035, 0, 2 * math.pi, 14), 0.05, 0.35, "Smooth")
    # joues creusées sous les pommettes, tempes
    s([(0.1, 0.74), (0.14, 0.76), (0.17, 0.74)], 0.06, 0.5, "Draw", invert=True)
    s([(0.2, 0.42), (0.22, 0.48)], 0.09, 0.18, "Draw", invert=True)
    s([(0.17, 0.5), (0.22, 0.55), (0.26, 0.6)], 0.07, 0.35, "Smooth")
    # cavité nasale : triangle renversé
    s([(-0.01, 0.61), (0.0, 0.655), (0.01, 0.61)], 0.02, 0.4, "Draw", invert=True, sym=False)
    s([(0.0, 0.6), (0.0, 0.66)], 0.025, 0.25, "Smooth", sym=False)
    # dents : sillons verticaux courts sous le tissu, doux
    for k in range(-3, 4):
        u = k * 0.012
        s([(u, 0.8), (u, 0.855)], 0.008, 0.18, "Crease Polish", invert=True, sym=False, spacing=0.2)
    # ---- le tissu tendu adoucit tout : lissage du visage, les grandes formes restent
    for v in (0.5, 0.62, 0.74, 0.86):
        s([(0.0, v), (0.08, v), (0.16, v), (0.22, v)], 0.06, 0.3, "Smooth")
    # ---- plis de tension : partent des pommettes, de la mâchoire et du menton, coulent dans le rideau
    brush.symmetry(x=True)
    for pts, r in falls:
        if len(pts) < 3:
            continue
        mid = pts[len(pts) // 2]
        view = (mid - Vector((0, veil.SHROUD_AXIS.y, mid.z))).normalized()
        # crête de tissu tendu : levée, pincée, qui s'effile vers le bas
        fade = lambda t: math.sin(math.pi * t) ** 0.6
        brush.stroke(pts, r, 0.42, view=view, brush="Draw", pressure=fade)
        brush.stroke(pts, r * 1.2, 0.35, view=view, brush="Pinch/Magnify", pressure=fade)
    brush.end()


# lignes de chute : (angle u de la colonne, rangée relative de départ et d'arrivée, rayon de la crête)
FALLS = [(0.15, 0.5, 0.9, 0.03), (0.08, 0.54, 0.84, 0.025), (0.24, 0.46, 0.95, 0.035), (0.4, 0.4, 0.95, 0.045)]
