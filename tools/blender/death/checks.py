"""Contrôles propres au spectre (#81), lancés par tools/blender/pipeline.py après la construction : contact réel des
doigts avec la poignée, skinning des pièces animées, silhouette (hauteur, pieds absents, lanières au-dessus du sol)."""

import bpy
from mathutils.bvhtree import BVHTree

from lib import mesh

from . import anatomy, posture

# écart maximal toléré entre une phalange et le cuir (stud) : au-delà, le doigt flotte
GRIP_TOLERANCE = 0.005
# Roblox lit au plus 4 os par sommet
MAX_INFLUENCES = 4


def grip_contact():
    """Cette méthode permet de mesurer l'écart entre les phalanges qui serrent et le maillage réel de la poignée (studs,
    point le plus proche) : négatif = le doigt presse le cuir, positif = il flotte ; renvoie (pire, moyen, nombre)."""
    deps = bpy.context.evaluated_depsgraph_get()
    grip = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == "Grip").evaluated_get(deps)
    tree = BVHTree.FromObject(grip, deps)
    gaps = []
    for pts, rs in anatomy.GRIP_PATHS:
        for p, rf in zip(pts, rs):
            nearest = tree.find_nearest(p)[0]
            gaps.append((p - nearest).length - rf)
    return max(gaps), sum(gaps) / len(gaps), len(gaps)


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


def silhouette():
    """Cette méthode permet de mesurer la silhouette : sommet, bas du tissu le plus bas, recul des lanières derrière la
    racine (studs, repère Blender)."""
    top, bottom, back = -1e9, 1e9, 0.0
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render or o.data.name not in ("Shroud", "Cloak", "Tatters", "Sleeves"):
            continue
        lo, hi = mesh.bounds(o)
        top = max(top, hi.z)
        bottom = min(bottom, lo.z)
        back = min(back, lo.y)
    return {"top": round(top, 3), "bottom": round(bottom, 3), "height": round(top - posture.GROUND, 3),
            "clearance": round(bottom - posture.GROUND, 3), "trailBack": round(-back, 3)}


def run():
    """Cette méthode permet de rendre les mesures et les erreurs des contrôles du spectre pour le rapport."""
    worst, mean, n = grip_contact()
    report = {"grip_gap_max": round(worst, 4), "grip_gap_mean": round(mean, 4), "grip_samples": n}
    errors = []
    if worst > GRIP_TOLERANCE:
        errors.append(f"doigts décollés de la poignée : écart maximal {worst:.3f} stud")
    for name in ("Hands", "Sleeves", "Tatters", "Cloak"):
        r, e = skin_report(name)
        report[f"skin_{name}"] = r
        errors += e
    sil = silhouette()
    report["silhouette"] = sil
    if sil["clearance"] < 0.05:
        errors.append(f"le tissu touche le sol (marge {sil['clearance']} stud) : le spectre doit flotter")
    if sil["top"] - posture.GROUND > 7.9:
        errors.append(f"trop grand pour passer les portes de 8 studs ({sil['height']})")
    return report, errors
