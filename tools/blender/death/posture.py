"""Posture du spectre (#81) : squelette de référence, d'où partent tous les volumes (corps de substitution du drapé,
anatomie, manches, faux, os du rig).

Unités : 1 unité Blender = 1 stud ; origine = HumanoidRootPart ; sol à GROUND ; avant vers +Y ; droite du personnage
vers +X. Silhouette voulue (#81) : très grande et étirée (sommet du crâne vers 3,6, soit 7,3 studs au-dessus du sol,
sous les portes de 8), dos voûté, tête étroite penchée en avant, épaules osseuses, bras longs et maigres ; la main
droite serre la faux, la gauche se tend en avant, griffes ouvertes.
"""

import math

from mathutils import Matrix, Vector

GROUND = -3.65
SEED = 81

# colonne vertébrale, du bas du ventre à la base du crâne : le dos se voûte, la nuque part en avant
SPINE = [
    Vector((0.0, 0.02, 0.10)),
    Vector((0.0, -0.10, 0.75)),
    Vector((0.0, -0.22, 1.40)),
    Vector((0.0, -0.24, 1.95)),
    Vector((0.0, -0.10, 2.38)),
    Vector((0.0, 0.14, 2.66)),
]
NECK_BASE = Vector((0.0, 0.02, 2.40))
# crâne : centre, demi-axes (largeur, profondeur, hauteur), tangage vers l'avant (tête penchée)
SKULL_CENTER = Vector((0.0, 0.40, 3.08))
SKULL_RADII = Vector((0.30, 0.42, 0.40))
SKULL_PITCH = math.radians(24)
# épaules osseuses (acromion), un peu en avant : dos voûté
SHOULDER = {1: Vector((0.70, 0.06, 2.26)), -1: Vector((-0.70, 0.06, 2.26))}
STERNUM_TOP = Vector((0.0, 0.30, 2.22))
# longueurs des segments du bras (studs) : longs et maigres
UPPER_ARM = 1.42
FOREARM = 1.34


def skull_frame():
    """Cette méthode permet de donner le repère du crâne (matrice monde) : tête penchée en avant de SKULL_PITCH."""
    rot = Matrix.Rotation(-SKULL_PITCH, 4, "X")
    return Matrix.Translation(SKULL_CENTER) @ rot


def _bump(th, v, th0, v0, sth, sv):
    """Cette méthode permet de donner une bosse gaussienne (0 à 1) centrée en (th0, v0) sur la calotte (angle replié)."""
    d = math.atan2(math.sin(th - th0), math.cos(th - th0))
    return math.exp(-((d / sth) ** 2) - ((v - v0) / sv) ** 2)


def skull_relief(th, v):
    """Cette méthode permet de donner le relief du crâne (multiplicateur du rayon) à l'angle th et à la hauteur v
    lorsque le suaire doit le laisser deviner : orbites, arcade, pommettes, joues, tempes, maxillaire, occiput."""
    r = 1.0
    for s in (-1, 1):
        r -= 0.27 * _bump(th, v, s * 0.44, 0.55, 0.2, 0.075)  # orbites
        r += 0.08 * _bump(th, v, s * 0.4, 0.44, 0.32, 0.04)  # arcade
        r += 0.11 * _bump(th, v, s * 0.92, 0.63, 0.2, 0.06)  # pommettes
        r -= 0.15 * _bump(th, v, s * 0.78, 0.77, 0.24, 0.07)  # joues creusées
        r -= 0.07 * _bump(th, v, s * 1.35, 0.42, 0.3, 0.12)  # tempes
    r += 0.03 * _bump(th, v, 0.0, 0.5, 0.1, 0.05)  # racine du nez
    r -= 0.08 * _bump(th, v, 0.0, 0.63, 0.09, 0.05)  # cavité nasale
    r += 0.06 * _bump(th, v, 0.0, 0.8, 0.35, 0.06)  # maxillaire, dents
    r += 0.05 * _bump(th, v, math.pi, 0.42, 0.7, 0.18)  # occiput
    return r


def skull_point(u, v, r_scale=1.0, relief=True):
    """Cette méthode permet de placer un point du crâne (u autour, 0 devant ; v de 0 au sommet à 1 sous la mâchoire)
    dans le repère monde : ovoïde étroit, mâchoire resserrée, relief du visage (skull_relief)."""
    th = 2 * math.pi * u
    ph = math.pi * v
    k = (skull_relief(th, v) if relief else 1.0) * r_scale
    narrow = 1 - 0.22 * max(0.0, (v - 0.62) / 0.38) ** 1.3  # mâchoire étroite
    x = SKULL_RADII.x * math.sin(ph) * math.sin(th) * k * narrow
    y = SKULL_RADII.y * math.sin(ph) * math.cos(th) * k
    z = SKULL_RADII.z * math.cos(ph) * k
    if v > 0.7:  # le menton descend devant
        z -= 0.08 * max(0.0, math.cos(th)) * (v - 0.7) / 0.3
    return skull_frame() @ Vector((x, y, z))


def ik_elbow(shoulder, target, upper, fore, pole):
    """Cette méthode permet de placer le coude d'un bras à deux segments qui atteint `target` depuis `shoulder`, plié
    vers la direction `pole` ; la cible est ramenée à portée si besoin."""
    d = target - shoulder
    dist = min(d.length, (upper + fore) * 0.999)
    axis = d.normalized()
    # loi des cosinus : distance du coude le long de l'axe et écart perpendiculaire
    a = (upper * upper - fore * fore + dist * dist) / (2 * dist)
    h = math.sqrt(max(upper * upper - a * a, 0.0))
    side = (pole - axis * pole.dot(axis)).normalized()
    return shoulder + axis * a + side * h


def arm_chain(side):
    """Cette méthode permet de donner (épaule, coude, poignet) d'un bras : le droit (+1) vient serrer la faux, le gauche
    (-1) se tend devant le corps."""
    from . import scythe  # import tardif : la faux dépend aussi de la posture

    shoulder = SHOULDER[side]
    if side > 0:
        wrist = scythe.hand_wrist()
        # coude vers l'arrière et vers le bas : le bras pend le long du corps, l'avant-bras remonte vers la poignée
        elbow = ik_elbow(shoulder, wrist, UPPER_ARM, FOREARM, Vector((0.35, -0.8, -0.45)))
    else:
        # bras tendu devant, à peine plié, la main griffue vers la victime
        wrist = Vector((-0.78, 2.12, 1.2))
        elbow = ik_elbow(shoulder, wrist, UPPER_ARM, FOREARM, Vector((-0.3, 0.0, -1.0)))
    return shoulder, elbow, wrist
