"""Anatomie décharnée du spectre (#81) : bras longs et maigres, mains griffues (la droite serre la faux, la gauche se
tend), torse aux côtes saillantes. Chair desséchée sur les os : les volumes suivent un squelette (lib.organic, Skin
puis subdivision), d'un seul tenant ; ongles en griffes jaunies, posés en maillages secondaires dans la même pièce.

Les mains et la faux sont ce que voit le plus le joueur Mort (première personne, #74) : elles ont le plus de détail.
"""

import math

from mathutils import Matrix, Vector

from lib import mesh, organic
from lib.mesh import Builder, interp, lerp, material, smoothstep

from . import posture, scythe

FINGERS = ("Index", "Middle", "Ring", "Pinky")
# chair grise et sale (couleur de la version jouable ; la texture cuite porte le détail)
FLESH_RGB = (0.24, 0.23, 0.21)
# rayons des phalanges (studs) : base du doigt, articulation du milieu, dernière, bout ; doigts longs et secs
FINGER_RADII = (0.04, 0.035, 0.03, 0.023)
# contact : le centre d'une phalange passe à GRIP_R + FINGER_SINK x son rayon de l'axe (elle presse le cuir) ;
# mesuré sur le maillage réel par checks.grip_contact
FINGER_SINK = 0.62
# chemins (points, rayons) des doigts qui serrent la poignée, pour la mesure du contact
GRIP_PATHS = []
# articulations des doigts (point, direction du doigt, côté dos, rayon), pour les plis de la chair (crease_strokes)
JOINTS = []
# griffes posées (bout du doigt, direction, dos de l'ongle, longueur), pour le sculpt (death/sessions/hands.py)
CLAWS = []
# main droite, doigt par doigt (index -> auriculaire) : hauteur le long du manche, angle de la jointure autour de la
# poignée (degrés depuis le côté paume), longueur relative, épaisseur relative ; les doigts ne sont pas des anneaux
# identiques : le majeur est le plus long, l'auriculaire court et fin, l'index serre plus haut
GRIP_H = (0.132, 0.05, -0.03, -0.104)
GRIP_KNUCKLE = (42, 36, 31, 27)
GRIP_LEN = (1.0, 1.07, 0.98, 0.8)
GRIP_SIZE = (1.0, 1.04, 0.97, 0.84)
# arc couvert par chaque phalange (degrés, longueur relative 1) ; descente le long du manche par phalange (spirale)
GRIP_SPANS = (92, 74, 54)
GRIP_DRIFT = 0.007


def phalanx_radius(r0, r1, s):
    """Cette méthode permet de donner le rayon d'une phalange au point s (0 à l'articulation de départ, 1 à la
    suivante) : chair desséchée, l'os se lit (articulations noueuses, milieu creusé)."""
    base = r0 + (r1 - r0) * s
    knob = 0.26 * math.exp(-((s / 0.14) ** 2)) + 0.2 * math.exp(-(((1 - s) / 0.14) ** 2))
    return base * (1 - 0.24 * math.sin(math.pi * s) + knob)


def _side_prefix(side):
    """Cette méthode permet de donner le préfixe des os d'un côté (R_ pour la droite, L_ pour la gauche)."""
    return "R_" if side > 0 else "L_"


def arm_nodes(side, hand):
    """Cette méthode permet de décrire le bras (du milieu du bras, caché dans la manche, au poignet) : coude osseux,
    avant-bras plat aux deux os qui se devinent ; `hand` (nœuds de la main) s'y raccroche au poignet."""
    p = _side_prefix(side)
    sh, el, wr = posture.arm_chain(side)
    up = el - sh
    fo = wr - el
    # le bras et le haut de l'avant-bras restent toujours dans la manche (elle suit les mêmes os) : la chair commence
    # à mi-avant-bras, la texture va aux mains
    n = [
        organic.Node("fore1", el + fo * 0.45, 0.066, None, p + "Forearm"),
        organic.Node("fore2", el + fo * 0.72, 0.058, "fore1", p + "Forearm"),
        organic.Node("wrist", wr, 0.05, "fore2", p + "Forearm"),
    ]
    return n + hand


def _arc(name, parent, bone, pts, radii):
    """Cette méthode permet d'enchaîner des nœuds le long d'un arc (doigt qui s'enroule) ; renvoie (nœuds, dernier)."""
    out = []
    for k, (q, r) in enumerate(zip(pts, radii)):
        nm = f"{name}{k}"
        out.append(organic.Node(nm, q, r, parent, bone))
        parent = nm
    return out, parent


def grip_hand():
    """Cette méthode permet de décrire la main droite qui serre la poignée (paume côté corps, doigts enroulés,
    griffes dans le cuir, pouce par-dessus) ; renvoie (nœuds, os (nom, tête, queue, parent), griffes)."""
    g, ax, palm, side = scythe.hand_frame()
    gr = scythe.GRIP_R
    wrist = scythe.hand_wrist()
    nodes = []
    bones = []
    claws = []
    GRIP_PATHS.clear()
    JOINTS.clear()
    knuckles = []
    for f in range(4):
        knuckles.append(scythe.around(GRIP_KNUCKLE[f], GRIP_H[f], gr + 0.052 * GRIP_SIZE[f]))
    kc = sum(knuckles, Vector()) / 4
    palm_c = lerp(wrist, kc, 0.52)
    nodes.append(organic.Node("palm", palm_c, (0.08, 0.08), "wrist", "R_Hand"))
    nodes.append(organic.Node("palm2", lerp(palm_c, kc, 0.55), (0.07, 0.07), "palm", "R_Hand"))
    bones.append(("R_Hand", wrist, kc, "R_Forearm"))
    for f, finger in enumerate(FINGERS):
        h = GRIP_H[f]
        size = GRIP_SIZE[f]
        bname = f"R_{finger}"
        nodes.append(organic.Node(f"k{f}", knuckles[f], 0.042 * size, "palm2", "R_Hand"))
        parent = f"k{f}"
        heads = [knuckles[f]]
        a = GRIP_KNUCKLE[f]
        for k in range(3):
            a0, a1 = a, a + GRIP_SPANS[k] * GRIP_LEN[f]
            a = a1
            r0, r1 = FINGER_RADII[k] * size, FINGER_RADII[k + 1] * size
            pts, rs = [], []
            for m in range(1, 5):
                s = m / 4
                rf = phalanx_radius(r0, r1, s)
                pts.append(scythe.around(a0 + (a1 - a0) * s, h - GRIP_DRIFT * (k + s), gr + rf * FINGER_SINK))
                rs.append(rf)
            arc_nodes, parent = _arc(f"f{f}_{k}_", parent, f"{bname}{k + 1}", pts, rs)
            nodes += arc_nodes
            heads.append(pts[-1])
            samples = [m / 8 for m in range(9)]
            GRIP_PATHS.append(([scythe.around(a0 + (a1 - a0) * s, h - GRIP_DRIFT * (k + s),
                                              gr + phalanx_radius(r0, r1, s) * FINGER_SINK) for s in samples],
                               [phalanx_radius(r0, r1, s) for s in samples]))
        for k in range(3):
            bones.append((f"{bname}{k + 1}", heads[k], heads[k + 1], "R_Hand" if k == 0 else f"{bname}{k}"))
            radial = heads[k] - g - ax * (heads[k] - g).dot(ax)
            JOINTS.append((heads[k], (heads[k + 1] - heads[k]).normalized(), radial.normalized(),
                           FINGER_RADII[k] * size))
        tip = heads[-1]
        nxt = scythe.around(a + 14, h - GRIP_DRIFT * 3.4, gr + FINGER_RADII[-1] * size * FINGER_SINK)
        claws.append((tip, (nxt - tip).normalized(), f"{bname}3", "grip"))
    # pouce : part du talon de la main, passe par-dessus la poignée dans l'autre sens, au-dessus de l'index
    t0 = lerp(wrist, palm_c, 0.55) + ax * 0.09 - side * 0.05
    t1 = scythe.around(-12, 0.175, gr + 0.05)
    t2 = scythe.around(-82, 0.18, gr + 0.03 * FINGER_SINK)
    t3 = scythe.around(-138, 0.182, gr + 0.024 * FINGER_SINK)
    nodes.append(organic.Node("t0", t0, 0.045, "palm", "R_Thumb1"))
    nodes.append(organic.Node("t1", t1, 0.038, "t0", "R_Thumb1"))
    pts = [scythe.around(-12 - 70 * m / 3, 0.175 + 0.005 * m / 3, gr + (0.038 - 0.008 * m / 3) * FINGER_SINK)
           for m in range(1, 4)]
    arc_nodes, parent = _arc("t1_", "t1", "R_Thumb2", pts, [0.035, 0.032, 0.03])
    nodes += arc_nodes
    pts = [scythe.around(-82 - 56 * m / 3, 0.18, gr + (0.03 - 0.006 * m / 3) * FINGER_SINK) for m in range(1, 4)]
    arc_nodes, parent = _arc("t2_", parent, "R_Thumb3", pts, [0.028, 0.026, 0.024])
    nodes += arc_nodes
    GRIP_PATHS.append(([scythe.around(-12 - 126 * m / 12, 0.175, gr + (0.036 - 0.012 * m / 12) * FINGER_SINK)
                        for m in range(1, 13)], [0.036 - 0.012 * m / 12 for m in range(1, 13)]))
    bones += [("R_Thumb1", t0, t1, "R_Hand"), ("R_Thumb2", t1, t2, "R_Thumb1"), ("R_Thumb3", t2, t3, "R_Thumb2")]
    nxt = scythe.around(-152, 0.18, gr + 0.02 * FINGER_SINK)
    claws.append((t3, (nxt - t3).normalized(), "R_Thumb3", "grip"))
    return nodes, bones, claws


def claw_hand():
    """Cette méthode permet de décrire la main gauche tendue devant le corps : doigts écartés, à demi pliés en crochet,
    paume vers le bas ; renvoie (nœuds, os, griffes) comme grip_hand."""
    sh, el, wr = posture.arm_chain(-1)
    d = (wr - el).normalized()
    d = (d + Vector((0.0, 0.25, -0.12))).normalized()  # la main se casse un peu au poignet, vers l'avant
    down = Vector((0.0, 0.25, -1.0))
    n = (down - d * down.dot(d)).normalized()  # côté paume
    lat = d.cross(n)
    if lat.x < 0:  # côté pouce vers le corps (+X pour la main gauche)
        lat = -lat
    nodes, bones, claws = [], [], []
    kc = wr + d * 0.4
    palm_c = wr + d * 0.2
    nodes.append(organic.Node("palm", palm_c, (0.085, 0.085), "wrist", "L_Hand"))
    bones.append(("L_Hand", wr, kc, "L_Forearm"))
    spread = (9, 1, -8, -17)
    offs = (0.075, 0.026, -0.024, -0.07)
    lengths = (0.21, 0.165, 0.125)
    flex = ((14, 38, 30), (10, 34, 34), (16, 40, 32), (22, 44, 30))
    for f, finger in enumerate(FINGERS):
        bname = f"L_{finger}"
        k = kc + lat * offs[f] - d * (0.015 * abs(f - 1.2))
        nodes.append(organic.Node(f"k{f}", k, 0.042 * GRIP_SIZE[f], "palm", "L_Hand"))
        direction = Matrix.Rotation(math.radians(spread[f]), 3, n) @ d
        axis = direction.cross(n).normalized()
        heads = [k]
        parent = f"k{f}"
        p = k
        for j in range(3):
            direction = Matrix.Rotation(math.radians(flex[f][j]), 3, axis) @ direction
            q = p + direction * lengths[j] * GRIP_LEN[f]
            r0, r1 = FINGER_RADII[j] * GRIP_SIZE[f], FINGER_RADII[j + 1] * GRIP_SIZE[f]
            ss = (0.25, 0.5, 0.75, 1.0)
            mids = [p.lerp(q, s) for s in ss]
            arc_nodes, parent = _arc(f"f{f}_{j}_", parent, f"{bname}{j + 1}", mids,
                                     [phalanx_radius(r0, r1, s) for s in ss])
            nodes += arc_nodes
            heads.append(q)
            p = q
        for j in range(3):
            bones.append((f"{bname}{j + 1}", heads[j], heads[j + 1], "L_Hand" if j == 0 else f"{bname}{j}"))
            fd = (heads[j + 1] - heads[j]).normalized()
            dorsal = (-n - fd * (-n).dot(fd)).normalized()
            JOINTS.append((heads[j], fd, dorsal, FINGER_RADII[j] * GRIP_SIZE[f]))
        claw_dir = (Matrix.Rotation(math.radians(24), 3, axis) @ direction).normalized()
        claws.append((heads[-1], claw_dir, f"{bname}3", "free"))
    # pouce : écarté vers le corps, plié vers la paume
    t0 = wr + d * 0.08 + lat * 0.06 + n * 0.02
    td = (d * 0.55 + lat * 0.75 + n * 0.25).normalized()
    t_axis = td.cross(n).normalized()
    t1 = t0 + td * 0.17
    td2 = Matrix.Rotation(math.radians(28), 3, t_axis) @ td
    t2 = t1 + td2 * 0.14
    td3 = Matrix.Rotation(math.radians(26), 3, t_axis) @ td2
    t3 = t2 + td3 * 0.11
    nodes += [organic.Node("t0", t0, 0.045, "palm", "L_Thumb1"),
              organic.Node("t1", t1, 0.036, "t0", "L_Thumb1"),
              organic.Node("t2", t2, 0.03, "t1", "L_Thumb2"),
              organic.Node("t3", t3, 0.024, "t2", "L_Thumb3")]
    bones += [("L_Thumb1", t0, t1, "L_Hand"), ("L_Thumb2", t1, t2, "L_Thumb1"), ("L_Thumb3", t2, t3, "L_Thumb2")]
    claws.append((t3, (Matrix.Rotation(math.radians(20), 3, t_axis) @ td3).normalized(), "L_Thumb3", "free"))
    return nodes, bones, claws


CLAW_RINGS, CLAW_SEGS = 12, 12  # anneaux le long, sommets autour (un sommet sur l'arête du dos)
CLAW_ROOT = 0.045  # longueur de la griffe posée sur le dos de la dernière phalange, avant le bout du doigt


def claw_creases(claw, tip, direction, up_hint, length):
    """Cette méthode permet de garder vives la pointe et l'arête du dos d'une griffe (la subdivision et le sculpt
    adouciraient le reste, au lieu des facettes de #81)."""
    d = direction.normalized()
    up = (up_hint - d * up_hint.dot(d)).normalized()
    lat = d.cross(up)
    me = claw.data
    crease = me.attributes.new("crease_edge", "FLOAT", "EDGE")
    tipk, ridge = [], []
    for v in me.vertices:
        rel = v.co - tip
        tipk.append(rel.dot(d) / length > 0.72)
        ridge.append(rel.dot(up) > 0 and abs(rel.dot(lat)) < 1e-4 + 0.0005)
    for e in me.edges:
        a, b = e.vertices
        if tipk[a] and tipk[b]:
            crease.data[e.index].value = 1.0
        elif ridge[a] and ridge[b]:
            crease.data[e.index].value = 0.7


def build_claw(b, tip, direction, up_hint, length=0.13, base=0.022):
    """Cette méthode permet d'ajouter une griffe (ongle épais, long, recourbé, à arête dorsale) au bout d'un doigt :
    section en goutte qui s'effile jusqu'à la pointe, courbée vers la paume."""
    d = direction.normalized()
    up = (up_hint - d * up_hint.dot(d)).normalized()  # dos de l'ongle
    lat = d.cross(up)
    rows = []
    n = CLAW_RINGS
    for k in range(n + 1):
        s = k / n
        # elle naît sur le dos de la dernière phalange (base enfoncée dans le doigt, comme un ongle), puis recourbe
        # vers la paume (-up) en s'allongeant
        c = tip + d * (length * s - CLAW_ROOT * (1 - s)) - up * (0.05 * s * s) + up * (base * 0.7 * (1 - s))
        w = base * (1 - s) ** 0.8 + 0.002
        hgt = base * 0.75 * (1 - s) ** 0.9 + 0.0015
        ring = []
        for m in range(CLAW_SEGS):
            a = 2 * math.pi * m / CLAW_SEGS
            # goutte : arête sur le dos, ventre plat
            ry = hgt * (1.25 if math.sin(a) > 0 else 0.55)
            ring.append(c + lat * (w * math.cos(a)) + up * (ry * math.sin(a) * (1 + 0.35 * math.sin(a) ** 8)))
        rows.append(ring)
    b.grid(rows, cap_start=True, cap_end=True)


def build_hands():
    """Cette méthode permet de construire les deux bras et leurs mains, chair et griffes, dans la pièce `Hands`
    (skinnée sur les os du corps) ; renvoie (objet, os du corps des bras, squelettes) pour le rig et les mesures."""
    parts = []
    bones = []
    CLAWS.clear()
    flesh = material("Flesh", FLESH_RGB, 0.0, 0.7)
    for side in (1, -1):
        nodes, hbones, claws = grip_hand() if side > 0 else claw_hand()
        arm = arm_nodes(side, nodes)
        ob = organic.skin_object(f"Hands{'R' if side > 0 else 'L'}", arm, subdiv=1)
        organic.skeleton_weights(ob, arm)
        organic.set_zone(ob, 0)
        ob.data.materials.append(flesh)
        sh, el, wr = posture.arm_chain(side)
        p = _side_prefix(side)
        bones += [(p + "UpperArm", sh, el, "Spine"), (p + "Forearm", el, wr, p + "UpperArm")] + hbones
        parts.append(ob)
        # griffes : ongle épais, jauni, qui prolonge chaque doigt ; chacune suit la dernière phalange
        for k, (tip, direction, bone, kind) in enumerate(claws):
            if kind == "free":
                hint = Vector((0, 0, 1))
            else:  # dos de l'ongle vers l'extérieur de la poignée, à la hauteur du bout du doigt
                g, ax = scythe.shaft_point(scythe.GRIP_T), scythe.shaft_axis(scythe.GRIP_T)
                hint = (tip - g) - ax * (tip - g).dot(ax)
            cb = Builder(f"Claw{p}{k}")
            length = 0.09 if kind == "grip" else 0.17
            build_claw(cb, tip, direction, hint, length=length)
            CLAWS.append((tip.copy(), direction.copy(), hint.copy(), length))
            claw = cb.finish(flesh)
            claw.vertex_groups.new(name=bone).add(list(range(len(claw.data.vertices))), 1.0, "REPLACE")
            organic.set_zone(claw, 1)
            # pointe et arête du dos gardées vives dans la version détaillée (la subdivision émousserait la pointe,
            # et la cuisson la raterait)
            claw_creases(claw, tip, direction, hint, length)
            parts.append(claw)
    hands = organic.merge_objects("Hands", parts)
    # une seule matière (une MeshPart Roblox = une matière) : les griffes se distinguent par l'attribut de face
    # « zone » (1), lu par la matière détaillée à la cuisson
    mesh.atlas_uv(hands)
    return hands, bones


def crease_strokes():
    """Cette méthode permet de donner les traits de sculpt des plis de la chair sur le dos de chaque articulation des
    doigts (trois sillons serrés en travers, peau desséchée qui se plisse sur l'os), pour la version détaillée."""
    strokes = []
    for p, fd, dorsal, r in JOINTS:
        across = fd.cross(dorsal).normalized()
        for k, off in enumerate((-0.012, 0.0, 0.012)):
            c = p + fd * off + dorsal * r * 0.95
            half = r * (0.75 if k == 1 else 0.55)
            pts = [c - across * half + dorsal * (-0.25 * r), c, c + across * half + dorsal * (-0.25 * r)]
            strokes.append((pts, 0.006, 0.0035 if k == 1 else 0.0022))
    return strokes


# ---------------------------------------------------------------- torse
# profil du torse le long de la hauteur : (z, centre y, demi-largeur, demi-profondeur) ; cage en tonneau, ventre creusé
TORSO = [
    (0.0, 0.10, 0.30, 0.22),
    (0.55, 0.04, 0.27, 0.17),
    (0.95, 0.01, 0.40, 0.26),
    (1.45, -0.02, 0.49, 0.32),
    (1.85, 0.00, 0.49, 0.30),
    (2.12, 0.04, 0.60, 0.26),
    (2.30, 0.06, 0.24, 0.17),
    (2.50, 0.10, 0.12, 0.12),
    (2.78, 0.26, 0.10, 0.11),
]
# grille : colonnes autour, rangées du bas vers le cou, deux fois plus serrées sur la cage (les côtes sculptées)
TORSO_COLS, TORSO_ROWS = 52, 96
RIBS = 10
# bas du sternum (pointe du rebord costal) et bas de la cage sur les côtés
XIPHOID_Z = 1.28
CAGE_LOW_Z = 0.98


def _torso_rows():
    """Cette méthode permet de répartir les rangées du torse, serrées sur la cage thoracique."""
    lo, hi = TORSO[0][0], TORSO[-1][0]
    return [lo + (hi - lo) * t for t in mesh.warp_samples(
        TORSO_ROWS, lambda t: 1 + 1.3 * smoothstep(0.28, 0.36, t) * smoothstep(0.8, 0.72, t))]


def costal_margin(th):
    """Cette méthode permet de donner la hauteur du rebord costal (bas de la cage) à l'angle th (0 devant) : un V
    renversé qui part du bas du sternum et descend sur les côtés."""
    a = abs(math.atan2(math.sin(th), math.cos(th)))
    return CAGE_LOW_Z + (XIPHOID_Z - CAGE_LOW_Z) * max(0.0, 1 - a / 1.25) ** 1.4


def rib_relief(th, z):
    """Cette méthode permet de donner la forme lisse du torse (multiplicateur du rayon) au point d'angle th (0 devant)
    et de hauteur z : cage qui déborde du ventre au rebord costal, ventre rentré, clavicules, colonne ; les côtes
    elles-mêmes sont sculptées à la brosse (death/sessions/torso.py)."""
    front = math.cos(th)
    lateral = abs(math.sin(th))
    rel = 0.0
    # sous le rebord costal, le ventre desséché se creuse (surtout devant)
    margin = costal_margin(th)
    below = smoothstep(margin + 0.02, margin - 0.12, z) * smoothstep(0.15, 0.45, z)
    rel -= below * (0.1 + 0.16 * max(0.0, front) ** 1.5)
    # clavicules
    clav = math.exp(-((z - 2.13) / 0.04) ** 2) * smoothstep(0.2, 0.6, lateral) * max(0.0, front)
    rel += 0.08 * clav
    # creux sous les clavicules
    rel -= 0.05 * math.exp(-((z - 2.02) / 0.05) ** 2) * smoothstep(0.2, 0.6, lateral) * max(0.0, front)
    # colonne saillante dans le dos
    spine = math.exp(-((th - math.pi) / 0.12) ** 2) * (0.5 + 0.5 * math.cos(2 * math.pi * z / 0.12))
    rel += 0.04 * spine * smoothstep(0.5, 0.8, z) * smoothstep(2.4, 2.2, z)
    return 1 + rel


def torso_at(th, z, relief=True):
    """Cette méthode permet de placer un point de la surface du torse à l'angle th (0 devant, + vers la droite) et à
    la hauteur z (repère monde)."""
    cy, rx, ry = interp(TORSO, z)
    k = rib_relief(th, z) if relief else 1.0
    # le dos se voûte avec la colonne
    sp = posture.SPINE
    back = interp([(p.z, p.y) for p in sp], z)[0]
    cy += 0.35 * (back - (-0.1))
    return Vector((rx * k * math.sin(th), cy + ry * k * math.cos(th), z))


def torso_normal(th, z):
    """Cette méthode permet de donner la normale extérieure du torse au point (th, z)."""
    e = 1e-3
    around = torso_at(th + e, z) - torso_at(th - e, z)  # vers +X devant (th croît de l'avant vers la droite)
    up = torso_at(th, z + e) - torso_at(th, z - e)
    return up.cross(around).normalized()


def build_torso():
    """Cette méthode permet de construire le torse décharné (pièce `Torso`) : cage en tonneau, rebord costal, ventre
    creusé, clavicules, cou maigre ; ouvert en bas (caché dans la robe) et en haut (sous le suaire), sans épaisseur
    (on ne le voit que du dehors, par les trous de la robe). Les côtes et le sternum sont sculptés à la brosse."""
    rows = _torso_rows()

    def pt(i, j):
        """Cette méthode permet de placer le sommet (i autour, 0 devant ; j du bas vers le cou) du torse."""
        return tuple(torso_at(2 * math.pi * i / TORSO_COLS, rows[j]))

    ob = mesh.grid_object("Torso", TORSO_COLS, TORSO_ROWS, pt, uv_shift=TORSO_COLS // 2)
    # tube ouvert : le recalcul des normales peut les tourner vers l'intérieur (masqué en #81 par l'épaisseur) ;
    # sans épaisseur, Roblox n'afficherait que l'intérieur
    me = ob.data
    outward = sum(1 for p in me.polygons if p.normal.dot(Vector((p.center.x, p.center.y - torso_at(0, p.center.z,
                  relief=False).y + interp(TORSO, p.center.z)[2], 0))) > 0)
    if outward < len(me.polygons) / 2:
        me.flip_normals()
    organic.set_zone(ob, 0)
    ob.data.materials.append(material("Flesh", FLESH_RGB, 0.0, 0.7))
    return ob
