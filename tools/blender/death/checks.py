"""Contrôles propres au spectre (#81), lancés par tools/blender/pipeline.py après la construction : contact réel des
doigts avec la poignée, skinning des pièces animées, silhouette (hauteur, pieds absents, lanières au-dessus du sol)."""

import bpy
from mathutils.bvhtree import BVHTree

from lib import mesh

from . import anatomy, posture, scythe

# écart maximal toléré entre une phalange et le cuir (stud) : au-delà, le doigt flotte
GRIP_TOLERANCE = 0.005
# profondeur sous le cuir où commence la recherche de la peau d'un doigt (un doigt peut l'enfoncer jusque-là)
GRIP_SINK_SEARCH = 0.03
# écart toléré aux bouts des doigts (jointure de base, bout arrondi), qui ne sont pas des appuis
GRIP_ENDS_TOLERANCE = 0.012
# hauteur maximale du modèle, faux comprise (portes de 8 studs, HouseLayout.DOOR_HEIGHT)
DOOR_CLEARANCE = 7.9
# recul maximal des lanières derrière la racine (veil.TRAIL_MAX et une marge d'épaisseur)
TRAIL_LIMIT = 2.7
# Roblox lit au plus 4 os par sommet
MAX_INFLUENCES = 4


def grip_contact():
    """Cette méthode permet de mesurer sur les maillages réels l'écart peau du doigt / cuir (négatif : le doigt presse)
    lorsqu'on vérifie la prise ; renvoie (pire, moyen, nombre) des appuis, pire des bouts, rayons perdus."""
    # un rayon part de l'axe du manche vers chaque phalange, touche le cuir puis la peau ; les deux bouts de chaque
    # doigt (jointure de base qui quitte la paume, bout arrondi d'où part la griffe) ne sont pas des appuis
    deps = bpy.context.evaluated_depsgraph_get()

    def tree(name):
        """Cette méthode permet de construire l'arbre de recherche d'une pièce évaluée (modificateurs appliqués)."""
        ob = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == name)
        return BVHTree.FromObject(ob.evaluated_get(deps), deps)

    grip, hands = tree("Grip"), tree("Hands")
    g = scythe.shaft_point(scythe.GRIP_T)
    ax = scythe.shaft_axis(scythe.GRIP_T)
    gaps, ends, missed = [], [], 0
    for i, (pts, _rs) in enumerate(anatomy.GRIP_PATHS):
        thumb = i >= 3 * len(anatomy.FINGERS)  # chemins : 3 phalanges par doigt, puis le pouce d'un trait
        for m, p in enumerate(pts):
            end = (m == 0 and (thumb or i % 3 == 0)) or (m == len(pts) - 1 and (thumb or i % 3 == 2))
            axis_pt = g + ax * (p - g).dot(ax)
            radial = (p - axis_pt).normalized()
            hit = grip.ray_cast(axis_pt, radial, 1.0)
            if hit[0] is None:
                missed += 1  # phalange hors de la poignée : compté comme un échec, pas ignoré
                continue
            r_grip = (hit[0] - axis_pt).length
            # départ un peu sous le cuir : un doigt qui l'enfonce est aussi trouvé
            start = axis_pt + radial * (r_grip - GRIP_SINK_SEARCH)
            skin = hands.ray_cast(start, radial, 0.3)
            if skin[0] is None:
                missed += 1
                continue
            (ends if end else gaps).append((skin[0] - axis_pt).length - r_grip)
    if not gaps:
        return float("inf"), float("inf"), 0, float("inf"), missed
    return max(gaps), sum(gaps) / len(gaps), len(gaps), max(ends, default=0.0), missed


def skin_report(name):
    """Cette méthode permet de vérifier le skinning d'une pièce : sommets sans os, au-delà de 4 influences, groupes qui
    ne sont pas des os de son armature ; renvoie (rapport, erreurs)."""
    ob = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == name)
    arm = next((m.object for m in ob.modifiers if m.type == "ARMATURE" and m.object), None)
    errors = []
    if arm is None:
        return {}, [f"{name} : pas d'armature"]
    bones = {b.name for b in arm.data.bones}
    names = {g.index: g.name for g in ob.vertex_groups}
    stray = sorted({n for n in names.values() if n not in bones})
    unweighted = over = 0
    for v in ob.data.vertices:
        ws = [g for g in v.groups if g.weight > 1e-4]
        if not ws:
            unweighted += 1
        if len(ws) > MAX_INFLUENCES:
            over += 1
    if stray:
        errors.append(f"{name} : groupes hors armature {stray}")
    if unweighted:
        errors.append(f"{name} : {unweighted} sommet(s) sans os")
    if over:
        errors.append(f"{name} : {over} sommet(s) à plus de {MAX_INFLUENCES} os")
    used = sorted({names[g.group] for v in ob.data.vertices for g in v.groups if g.weight > 1e-4})
    return {"bones": len(used), "unweighted": unweighted, "over4": over}, errors


CLOTH = ("Shroud", "Cloak", "Tatters", "Sleeves")
SCYTHE = ("Blade", "Edge", "Engraving", "ScytheHead", "Gem", "Rings", "Shaft", "Grip", "Pommel")


def silhouette():
    """Cette méthode permet de mesurer la silhouette (studs, repère Blender) : sommet de tout le modèle (faux comprise),
    bas du tissu et bas de la faux au-dessus du sol, recul des lanières derrière la racine."""
    top, cloth_bottom, scythe_bottom, back = -1e9, 1e9, 1e9, 0.0
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render or o.data.name not in CLOTH + SCYTHE:
            continue
        lo, hi = mesh.bounds(o)
        top = max(top, hi.z)
        if o.data.name in CLOTH:
            cloth_bottom = min(cloth_bottom, lo.z)
            back = min(back, lo.y)
        else:
            scythe_bottom = min(scythe_bottom, lo.z)
    g = posture.GROUND
    return {"top": round(top, 3), "height": round(top - g, 3), "clearance": round(cloth_bottom - g, 3),
            "scytheClearance": round(scythe_bottom - g, 3), "trailBack": round(-back, 3)}


def run():
    """Cette méthode permet de rendre les mesures et les erreurs des contrôles du spectre pour le rapport."""
    worst, mean, n, ends, missed = grip_contact()
    report = {"grip_gap_max": round(worst, 4), "grip_gap_mean": round(mean, 4), "grip_samples": n,
              "grip_ends_max": round(ends, 4), "grip_missed": missed}
    errors = []
    if worst > GRIP_TOLERANCE:
        errors.append(f"doigts décollés de la poignée : écart maximal {worst:.3f} stud")
    if ends > GRIP_ENDS_TOLERANCE:
        errors.append(f"bouts des doigts décollés de la poignée : {ends:.3f} stud")
    if missed:
        errors.append(f"{missed} point(s) de prise hors de la poignée ou de la main")
    for name in ("Hands", "Sleeves", "Tatters", "Cloak"):
        r, e = skin_report(name)
        report[f"skin_{name}"] = r
        errors += e
    sil = silhouette()
    report["silhouette"] = sil
    if sil["clearance"] < 0.05:
        errors.append(f"le tissu touche le sol (marge {sil['clearance']} stud) : le spectre doit flotter")
    if sil["scytheClearance"] < 0.05:
        errors.append(f"la faux traverse le sol (marge {sil['scytheClearance']} stud)")
    if sil["trailBack"] > TRAIL_LIMIT:
        errors.append(f"lanières trop loin derrière ({sil['trailBack']} stud) : elles traverseraient un mur")
    if sil["height"] > DOOR_CLEARANCE:
        errors.append(f"trop grand pour passer les portes de 8 studs, faux comprise ({sil['height']})")
    return report, errors
