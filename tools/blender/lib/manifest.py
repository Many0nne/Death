"""Manifeste d'un modèle (tools/models/<modèle>.manifest.json) : noms des pièces et des os attendus par le code,
budgets de triangles. Côté Blender, on compare la scène construite au manifeste et on écrit les mesures
(<modèle>.measured.json) : triangles, centre et taille de chaque pièce dans le repère Roblox de HumanoidRootPart.
Ces mesures sont relues par le test Lune (la CI n'a pas Blender) et par le remontage Studio (placement des pièces).
"""

import json

import bpy

from . import mesh


def load(path):
    """Cette méthode permet de lire un manifeste JSON."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def expected_bones(m):
    """Cette méthode permet de lister les os attendus : la racine puis Cxx_y (chaînes x os), comme les lit
    Shared.CloakMotion.parseBone."""
    b = m["bones"]
    return [b["root"]] + [f"C{c:02d}_{k}" for c in range(b["chains"]) for k in range(b["perChain"])]


def to_roblox(v):
    """Cette méthode permet de passer un vecteur Blender (Z haut, +Y avant) dans le repère Roblox de la racine
    (Y haut, -Z avant) : (x, y, z) -> (x, z, -y), comme l'export glTF."""
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def part_objects(m):
    """Cette méthode permet de retrouver l'objet Blender de chaque pièce : le glTF nomme la MeshPart d'après le
    maillage, donc on cherche par nom de maillage."""
    found = {}
    for o in bpy.data.objects:
        if o.type == "MESH" and o.data.name in m["parts"]:
            found.setdefault(o.data.name, []).append(o)
    return found


def check(m):
    """Cette méthode permet de comparer la scène au manifeste (pièces, os, poids, UV, budgets) ; renvoie (mesures,
    erreurs)."""
    errors = []
    found = part_objects(m)
    budget = m["budget"]
    measured = {"parts": {}, "totalTris": 0}
    for name, spec in m["parts"].items():
        obs = found.get(name, [])
        if len(obs) != 1:
            errors.append(f"pièce {name} : {len(obs)} maillage(s) de ce nom (1 attendu)")
            continue
        ob = obs[0]
        tris = mesh.tri_count(ob)
        lo, hi = mesh.bounds(ob)
        size = hi - lo
        measured["parts"][name] = {
            "group": spec["group"],
            "tris": tris,
            "center": to_roblox((lo + hi) / 2),
            "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
        }
        measured["totalTris"] += tris
        cap = min(spec.get("maxTris", budget["partTris"]), budget["partTris"])
        if tris > cap:
            errors.append(f"pièce {name} : {tris} triangles > budget {cap}")
        if spec.get("bake") and not ob.data.uv_layers:
            errors.append(f"pièce {name} : cuisson demandée mais pas d'UV")
    if measured["totalTris"] > budget["totalTris"]:
        errors.append(f"total : {measured['totalTris']} triangles > budget {budget['totalTris']}")
    # os de la pièce skinnée : armature, noms, groupes de sommets
    skin = m["bones"]["skin"]
    want = expected_bones(m)
    obs = found.get(skin, [])
    if len(obs) == 1:
        ob = obs[0]
        arm = next((md.object for md in ob.modifiers if md.type == "ARMATURE" and md.object), None)
        if arm is None:
            errors.append(f"{skin} : pas de modificateur Armature")
        else:
            have = [b.name for b in arm.data.bones]
            missing = sorted(set(want) - set(have))
            extra = sorted(set(have) - set(want))
            if missing or extra:
                errors.append(f"os de {skin} : manquants {missing}, en trop {extra}")
            groups = {g.name for g in ob.vertex_groups}
            unweighted = sorted(set(want) - groups)
            if unweighted:
                errors.append(f"{skin} : os sans poids {unweighted}")
            measured["bones"] = have
    exported = {o.data.name for o in bpy.data.objects if o.type == "MESH" and not o.hide_render}
    stray = sorted(exported - set(m["parts"]))
    if stray:
        errors.append(f"maillages hors manifeste (seraient exportés) : {stray}")
    return measured, errors


def write_measured(path, m, measured, extra=None):
    """Cette méthode permet d'écrire les mesures (versionnées, relues par Lune et par le remontage Studio)."""
    out = {
        "_doc": f"Mesuré par tools/blender/pipeline.py sur {m['script']} : ne pas modifier à la main.",
        "model": m["model"],
        "budget": m["budget"],
        **measured,
    }
    if extra:
        out.update(extra)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")
