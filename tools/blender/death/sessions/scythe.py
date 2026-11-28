"""Séances de sculpt de la faux (#89) : fer forgé et bois noueux. La forme (dos renforcé, rainure, biseau,
ébréchures, douille, attelles, moignons de branches) est dans le script (death/scythe.py) ; le sculpt ajoute ce qu'un
forgeron et le temps laissent : coups de marteau, piqûres de rouille, rayures le long du fil ; fentes et fil du bois,
cernes autour des nœuds. Ce détail passe dans les cartes cuites (normales, rugosité, couleur).

Graine fixe : mêmes coups au même endroit à chaque séance.
"""

import math
import random

from mathutils import Vector

from .. import brush, scythe

LEVELS = 3


def blade(ob):
    """Cette méthode permet de sculpter la lame (deux faces) : coups de marteau sur le plat, piqûres serrées vers le
    fil et dans la rainure, rayures en long près du fil."""
    rnd = random.Random(8901)
    brush.begin(ob, LEVELS)
    brush.symmetry(x=False)
    for side in (1, -1):
        view = Vector((0, side, 0))
        # coups de marteau : facettes larges et peu profondes sur le plat et le dos
        for _ in range(70):
            s = rnd.uniform(0.03, 0.9)
            w = rnd.uniform(0.02, 0.5)
            p = scythe.blade_point(s, w, side)
            brush.stroke([p, p + Vector((0.01, 0, 0.005))], rnd.uniform(0.025, 0.045), rnd.uniform(0.12, 0.22),
                         view=view, brush="Flatten/Contrast")
        # piqûres : plus nombreuses vers le fil et dans la rainure (l'eau y stagne)
        for _ in range(240):
            s = rnd.uniform(0.02, 0.95)
            w = min(0.98, abs(rnd.gauss(0.75, 0.2))) if rnd.random() < 0.6 else rnd.uniform(0.15, 0.3)
            if w > scythe.edge_line(s) - scythe.EDGE_BAND:
                continue
            p = scythe.blade_point(s, w, side)
            brush.stroke([p, p + Vector((0.002, 0, 0.001))], rnd.uniform(0.004, 0.011), rnd.uniform(0.35, 0.7),
                         view=view, invert=True, brush="Draw")
        # rayures en long, près du fil (affûtage, coups portés)
        for _ in range(26):
            s0 = rnd.uniform(0.05, 0.85)
            w = rnd.uniform(0.6, scythe.BEVEL_W + 0.25)
            ds = rnd.uniform(0.03, 0.09)
            pts = [scythe.blade_point(s0 + ds * k / 4, w + 0.01 * math.sin(k), side) for k in range(5)]
            brush.stroke(pts, 0.004, 0.3, view=view, invert=True, brush="Crease Polish",
                         pressure=lambda t: math.sin(math.pi * t))
    brush.end()


def head(ob):
    """Cette méthode permet de sculpter la douille : coups de marteau tout autour, piqûres."""
    rnd = random.Random(8902)
    brush.begin(ob, LEVELS)
    brush.symmetry(x=False)
    for _ in range(60):
        t = rnd.uniform(0.935, 1.0)
        a = rnd.uniform(0, 2 * math.pi)
        p, d = _around(t, a, 1.4)
        brush.stroke([p, p + d.orthogonal().normalized() * 0.004], rnd.uniform(0.02, 0.035), 0.18, view=d,
                     brush="Flatten/Contrast")
    for _ in range(90):
        t = rnd.uniform(0.86, 1.0)
        a = rnd.uniform(0, 2 * math.pi)
        p, d = _around(t, a, 1.4 if t > 0.935 else 1.05)
        brush.stroke([p, p + d.orthogonal().normalized() * 0.002], rnd.uniform(0.004, 0.009), 0.5, view=d,
                     invert=True, brush="Draw")
    brush.end()


def shaft(ob):
    """Cette méthode permet de sculpter le manche : fentes du bois en long, fil serré, cernes autour des nœuds."""
    rnd = random.Random(8903)
    brush.begin(ob, LEVELS)
    brush.symmetry(x=False)
    # fil du bois et fentes sèches, en long, qui tournent un peu avec le fil
    for _ in range(55):
        t0 = rnd.uniform(0.02, 0.9)
        if abs(t0 - scythe.GRIP_T) < scythe.GRIP_LEN + 0.04:
            continue
        a0 = rnd.uniform(0, 2 * math.pi)
        length = rnd.uniform(0.03, 0.12)
        pts, views = [], []
        for k in range(8):
            t = t0 + length * k / 7
            p, d = _around(t, a0 + 0.6 * (t - t0), 1.0)
            pts.append(p)
            views.append(d)
        deep = rnd.random() < 0.3  # quelques vraies fentes, le reste du fil
        brush.stroke(pts, 0.006 if deep else 0.004, 0.55 if deep else 0.3, view=views[4], invert=True,
                     brush="Crease Polish", pressure=lambda t: math.sin(math.pi * t) ** 0.5)
    # nœuds : le bois gonfle en bourrelet autour, l'œil du nœud se creuse
    for kt, ka, kh, kw in scythe.KNOTS:
        p, d = _around(kt, ka, 1.0 + 0.3 * kh)
        brush.stroke([p, p + scythe.shaft_axis(kt) * 0.01], 0.08 + 0.6 * kw, 0.5 + 0.25 * kh, view=d,
                     brush="Inflate/Deflate")
        brush.stroke([p, p + scythe.shaft_axis(kt) * 0.004], 0.018, 0.6, view=d, invert=True, brush="Draw")
    # cernes autour des nœuds (le bois a poussé autour)
    for kt, ka, kh, kw in scythe.KNOTS:
        for ring in (1.0, 1.7):
            pts = []
            for m in range(13):
                ang = 2 * math.pi * m / 12
                t = kt + kw * ring * 0.9 * math.cos(ang)
                p, d = _around(t, ka + 0.28 * ring * math.sin(ang), 1.0 + 0.3 * kh)
                pts.append(p)
            _p, d = _around(kt, ka, 1.0)
            brush.stroke(pts, 0.004, 0.3, view=d, invert=True, brush="Crease Polish")
    brush.end()


def _around(t, a, k):
    """Cette méthode permet de placer un point à la surface du manche (t le long, angle a) à k fois son rayon, avec la
    direction de vue (normale)."""
    ax = scythe.shaft_axis(t)
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    e1 = ax.cross(ref).normalized()
    e2 = ax.cross(e1)
    d = e1 * math.cos(a) + e2 * math.sin(a)
    return scythe.shaft_point(t) + d * scythe.shaft_radius(t) * k, d
