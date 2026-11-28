"""Séance de sculpt du torse (#89) : cage thoracique sous une chair desséchée et tendue. Référence : refs-81
`37f59873` (à droite : côtes et sternum qui saillent sous la peau, ventre creusé sous la cage).

Côtes posées une par une, du dos vers le sternum (elles descendent en avançant) ; creux entre elles ; sternum et
rebord costal ; ventre qui s'enfonce sous la cage ; peau qui se plisse un peu ; lissage léger. Symétrie miroir X.
"""

import math

from mathutils import Vector

from .. import anatomy, brush

LEVELS = 3
TRUE_RIBS = 7  # rattachées au sternum ; les suivantes s'arrêtent au rebord costal
RIBS = 9  # côtes qui se voient (les flottantes restent sous la chair)


# irrégularités des côtes (hauteur dans le dos, plongée) : tirées une fois, graine fixe
JITTER = [(0.012 * math.sin(k * 2.7 + 0.4), 0.02 * math.sin(k * 1.9 + 1.1)) for k in range(12)]


def rib(k):
    """Cette méthode permet de donner le trajet (angle, hauteur) d'une côte, côté droit, du dos vers l'avant : elle
    part haut près de la colonne, plonge sur le flanc, puis son cartilage remonte vers le sternum (vraies côtes) ou
    vers le rebord costal (fausses côtes) ; écarts un peu irréguliers."""
    dz, dd = JITTER[k]
    zb = 2.04 - 0.088 * k - 0.0035 * k * k + dz
    if k < TRUE_RIBS:
        th_end = 0.12 + 0.01 * k
        z_low = zb - 0.3 - 0.02 * k + dd  # point bas du flanc avant
        rise = 0.02 + 0.022 * k  # le cartilage remonte vers le sternum
    else:
        th_end = 0.55 + 0.25 * (k - TRUE_RIBS)
        z_low = anatomy.costal_margin(th_end) + 0.04
        rise = 0.0
    out = []
    n = 30
    for m in range(n):
        t = m / (n - 1)
        th = math.pi - 0.16 - (math.pi - 0.16 - th_end) * t
        # tient sa hauteur dans le dos, plonge sur le flanc, puis remonte (cartilage) sur le dernier tiers
        z = zb + (z_low - zb) * min(1.0, t / 0.72) ** 1.5 + rise * max(0.0, (t - 0.72) / 0.28) ** 1.3
        if z < anatomy.costal_margin(th) + 0.015:
            break
        out.append((th, z))
    return out


def rib_pressure(t):
    """Cette méthode permet de faire varier la côte le long de son trajet : pleine sur le flanc, mince au cartilage."""
    return 0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.15 + t * 0.95)) ** 0.8


def surface(pairs, lift=0.0):
    """Cette méthode permet de poser des points (angle, hauteur) sur le torse, relevés de `lift`."""
    return [anatomy.torso_at(th, z) + anatomy.torso_normal(th, z) * lift for th, z in pairs]


def stroke_wrapped(pairs, radius, strength, name, invert=False, sym=True, pressure=1.0, chunk=0.7):
    """Cette méthode permet de jouer un trait qui fait le tour du corps en morceaux d'au plus `chunk` radians, chacun
    vu de face (la brosse ne touche que ce qu'elle voit)."""
    brush.symmetry(x=sym)
    if len(pairs) < 2:
        return
    # morceaux qui se chevauchent d'un point ; la pression suit la position sur le trait entier
    last = len(pairs) - 1
    pieces, start = [], 0
    for k in range(1, len(pairs)):
        if abs(pairs[k][0] - pairs[start][0]) >= chunk or k == last:
            pieces.append((start, k))
            start = k
    for a, b in pieces:
        piece = pairs[a : b + 1]
        th, z = piece[len(piece) // 2]
        pr = pressure
        if callable(pressure):
            pr = (lambda a, b: lambda t: pressure((a + (b - a) * t) / last))(a, b)
        brush.stroke(surface(piece), radius, strength, view=anatomy.torso_normal(th, z), invert=invert, brush=name,
                     pressure=pr)


def run(ob):
    """Cette méthode permet de sculpter le torse `ob` (multirésolution LEVELS) du début à la fin."""
    brush.begin(ob, LEVELS)
    # ---- côtes : os arrondis sous la peau, pleins sur le flanc, minces au cartilage
    for k in range(RIBS):
        path = rib(k)
        r = 0.06 if k < TRUE_RIBS else 0.05
        stroke_wrapped(path, r, 0.42, "Draw", pressure=rib_pressure)
    # creux discret entre deux côtes : la peau desséchée s'y enfonce
    for k in range(RIBS - 1):
        a, b = rib(k), rib(k + 1)
        n = min(len(a), len(b))
        mid = [((a[m][0] + b[m][0]) / 2, (a[m][1] + b[m][1]) / 2) for m in range(n)]
        stroke_wrapped(mid, 0.032, 0.24, "Draw", invert=True, pressure=rib_pressure)
    # ---- sternum : manubrium, corps, appendice xiphoïde ; sillons de part et d'autre
    brush.symmetry(x=False)
    pts = surface([(0.0, z) for z in (2.04, 1.9, 1.7, 1.5, 1.34)])
    brush.stroke(pts, 0.07, 0.3, view=Vector((0, 1, 0.1)), brush="Draw")
    # manubrium, plus large en haut, entre les clavicules
    brush.stroke(surface([(-0.05, 2.03), (0.0, 1.98), (0.05, 2.03)]), 0.05, 0.25, view=Vector((0, 1, 0.2)), brush="Draw")
    brush.stroke(surface([(0.0, 1.34), (0.0, 1.24)]), 0.025, 0.4, view=Vector((0, 1, -0.2)), brush="Draw",
                 pressure=lambda t: 1 - 0.7 * t)
    # ---- rebord costal : arête de la cage, ventre creusé dessous
    edge = [(th, anatomy.costal_margin(th) + 0.02) for th in [0.04 + 0.08 * m for m in range(18)]]
    stroke_wrapped(edge, 0.028, 0.35, "Draw")
    below = [(th, anatomy.costal_margin(th) - 0.09) for th in [0.05 + 0.08 * m for m in range(16)]]
    stroke_wrapped(below, 0.07, 0.3, "Draw", invert=True)
    # ---- lissage très léger : la peau tendue relie les côtes
    for z in (1.2, 1.5, 1.8):
        stroke_wrapped([(th, z) for th in [0.05 + 0.12 * m for m in range(22)]], 0.06, 0.12, "Smooth")
    brush.end()
