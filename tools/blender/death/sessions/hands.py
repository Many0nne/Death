"""Séance de sculpt des mains (#89) : peau desséchée tendue sur les os. Références : refs-81 `b5e292ae` (mains
griffues aux jointures noueuses), `2914dc67` et `5850d62d` (doigts longs, secs), `502f7a57` (griffes).

Ordre : jointures renflées (la plus grosse à la base du doigt), arête de l'os le long des phalanges, plis de peau
en travers des jointures, tendons et creux du dos de la main, os de l'avant-bras et du poignet, griffes fendues et
striées. Pas de symétrie : les deux mains ont des poses différentes.

S'appuie sur les articulations relevées par le script (anatomy.JOINTS : point, axe du doigt, côté dos, rayon), dans
l'ordre : main droite (4 doigts x 3 jointures), puis main gauche.
"""

import math

from mathutils import Vector

from .. import anatomy, brush, posture, scythe

LEVELS = 3


def joints(side):
    """Cette méthode permet de donner les jointures d'une main, doigt par doigt : [[(point, axe, dos, rayon) x 3] x 4]."""
    js = anatomy.JOINTS[:12] if side > 0 else anatomy.JOINTS[12:24]
    return [js[f * 3 : f * 3 + 3] for f in range(4)]


def wrist(side):
    """Cette méthode permet de donner le poignet d'une main."""
    return scythe.hand_wrist() if side > 0 else posture.arm_chain(-1)[2]


def dab(p, view, radius, strength, name, invert=False):
    """Cette méthode permet de poser une touche de brosse (trait très court) en p, vue depuis `view`."""
    return brush.stroke([p, p + view.orthogonal().normalized() * radius * 0.2], radius, strength, view=view,
                        invert=invert, brush=name)


def run(ob):
    """Cette méthode permet de sculpter les mains `ob` (multirésolution LEVELS) du début à la fin."""
    brush.begin(ob, LEVELS)
    brush.symmetry(x=False)
    for side in (1, -1):
        fingers = joints(side)
        w = wrist(side)
        back = sum((j[0][2] for j in fingers), Vector()).normalized()  # dos de la main
        for f, js in enumerate(fingers):
            for k, (p, fd, dorsal, r) in enumerate(js):
                top = p + dorsal * r * 1.05
                # jointure renflée : grosse à la base du doigt, plus petite vers le bout
                dab(top, dorsal, r * (2.0 if k == 0 else 1.6), 0.4 if k == 0 else 0.3, "Inflate/Deflate")
                dab(top, dorsal, r * (1.6 if k == 0 else 1.3), 0.3, "Draw")
                dab(top, dorsal, r * 1.8, 0.25, "Smooth")
                # plis de peau en travers de la jointure (peau sèche qui se ride sur l'os)
                across = fd.cross(dorsal).normalized()
                for off in (-0.35, 0.0, 0.35):
                    c = top + fd * (off * r)
                    brush.stroke([c - across * r * 0.75, c + across * r * 0.75], r * 0.2, 0.26, view=dorsal,
                                 invert=True, brush="Crease Polish", pressure=lambda t: math.sin(math.pi * t))
            # arête de l'os sur le dos de chaque phalange, peau creusée sur les flancs
            for k in range(2):
                p0, fd0, d0, r0 = js[k]
                p1, _fd1, d1, r1 = js[k + 1]
                a = p0 + fd0 * r0 * 1.2 + d0 * r0 * 0.95
                b = p1 - fd0 * r1 * 1.2 + d1 * r1 * 0.95
                brush.stroke([a, b], r0 * 0.5, 0.3, view=d0, brush="Pinch/Magnify")
                across = fd0.cross(d0).normalized()
                for sgn in (1, -1):
                    brush.stroke([a + across * sgn * r0 * 0.8, b + across * sgn * r1 * 0.8], r0 * 0.4, 0.2,
                                 view=(d0 + across * sgn * 0.8).normalized(), invert=True, brush="Draw")
            # tendon extenseur : de la jointure de base au poignet, sur le dos de la main
            p, _fd, dorsal, r = js[0]
            start = p + dorsal * r - (p - w).normalized() * r * 1.3
            end = w + back * 0.045 + (p - w) * 0.35  # ils s'écartent encore au poignet (sinon nœud de traits)
            brush.stroke([start, start.lerp(end, 0.5) + back * 0.008, end], 0.014, 0.45, view=back, brush="Draw",
                         pressure=lambda t: 1 - 0.6 * t)
        # creux entre les tendons (os de la main sous la peau)
        for f in range(3):
            pa, pb = fingers[f][0][0], fingers[f + 1][0][0]
            mid = (pa + pb) / 2
            brush.stroke([mid + back * 0.03, mid.lerp(w, 0.6) + back * 0.04], 0.016, 0.3, view=back, invert=True,
                         brush="Draw", pressure=lambda t: math.sin(math.pi * t))
        # poignet : bosse de l'os (styloïde), os de l'avant-bras qui se devinent
        el = posture.arm_chain(side)[1]
        fo = (w - el).normalized()
        across = fo.cross(back).normalized()
        dab(w + back * 0.035 + across * 0.035, (back + across).normalized(), 0.03, 0.35, "Inflate/Deflate")
        # cubitus : une arête douce le long de l'avant-bras, peau creusée à côté
        a = w - fo * 0.08 + across * 0.03 + back * 0.04
        b = w - fo * 0.45 + across * 0.03 + back * 0.045
        brush.stroke([a, b], 0.035, 0.18, view=(back + across * 0.6).normalized(), brush="Draw",
                     pressure=lambda t: math.sin(math.pi * t))
        brush.stroke([a - across * 0.05, b - across * 0.05], 0.03, 0.12, view=back, invert=True, brush="Draw",
                     pressure=lambda t: math.sin(math.pi * t))
    # griffes : sillon fendu sur le dessus, stries le long, éclat au bout
    for tip, direction, up, length in anatomy.CLAWS:
        d = direction.normalized()
        u = (up - d * up.dot(d)).normalized()
        lat = d.cross(u)
        a = tip + d * length * 0.15 + u * 0.012
        b = tip + d * length * 0.7 + u * 0.004
        brush.stroke([a, b], 0.006, 0.6, view=u, invert=True, brush="Crease Sharp")
        for sgn in (1, -1):
            brush.stroke([a + lat * sgn * 0.008, b + lat * sgn * 0.004], 0.004, 0.35, view=(u + lat * sgn).normalized(),
                         invert=True, brush="Crease Polish")
    brush.end()

