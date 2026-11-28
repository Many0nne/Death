"""Modèle de la Mort (#81, outillage #79) : spectre décharné à voile en lambeaux, archétype du « détraqueur » (pas un
personnage existant), qui tient la faux.

Le modèle est découpé en modules (tools/blender/death/) :
- posture : squelette de référence (colonne voûtée, crâne penché, épaules, bras), d'où part tout le reste ;
- veil : suaire, robe trouée à os, lanières, manches ; drapés par simulation de tissu sur un corps de substitution ;
- anatomy : bras et mains griffues (chair desséchée sur les os, d'un seul tenant), torse aux côtes saillantes ;
- scythe : faux forgée et ébréchée, manche de bois naturel ;
- rig : armature du corps (os des bras, remontés sur le rig R15 dans Studio) ;
- checks : contact des doigts, skinning, silhouette ;
- sculpt : sculpt à la brosse versionné (assets/sculpt/death_sculpt.blend, #89), plaqué sur les pièces construites ;
  séances rejouables dans Blender avec interface (death/sessions/, death/brush.py).

Unités : 1 unité Blender = 1 stud. Origine = HumanoidRootPart du rig R15 ; sol à GROUND. Face avant vers +Y (le glTF
exporte (x, y, z) -> (x, z, -y), donc +Y Blender = -Z Roblox = l'avant). Noms des pièces, budgets et cuisson :
tools/models/death.manifest.json. Chaîne complète : tools/blender/pipeline.py.

Usage :
- chaîne complète (recommandé) : blender -b --factory-startup --python tools/blender/pipeline.py -- --glb <sortie.glb>
- interface (MCP), construction seule : exec(open(chemin).read(), {"__name__": "__main__", "__file__": chemin})
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
# rechargement propre (session Blender avec interface : modules déjà importés)
for _name in [n for n in sys.modules if n in ("lib", "death") or n.startswith(("lib.", "death."))]:
    del sys.modules[_name]

from death import anatomy, checks as death_checks, posture, rig, scythe, sculpt, veil  # noqa: E402
from lib import mesh  # noqa: E402

GROUND = posture.GROUND
SEED = posture.SEED
# nombre d'images du drapé de la robe : fixe, le résultat en dépend (empreinte dans death.measured.json)
DRAPE_FRAMES = 70
# objets de la dernière construction (armature du corps, pour les mesures)
BUILT = {}


def build_all(drape=True, sculpted=True):
    """Cette méthode permet de reconstruire tout le spectre : corps de substitution, drapés, anatomie, faux, armatures ;
    les corps de substitution sont retirés à la fin ; `sculpted` plaque le sculpt versionné (False : bases à
    sculpter, pour les séances)."""
    mesh.clear_scene()
    sculpt.clear()
    bpy.context.scene.frame_set(1)
    proxies = []
    if drape:
        proxies = veil.body_proxies()
    cloak_rig, cloak = veil.build_cloak(drape, frames=DRAPE_FRAMES)
    veil.build_shroud()
    veil.build_tatters(cloak, cloak_rig)
    sleeves = veil.build_sleeves(drape)
    for ob in proxies:
        bpy.data.objects.remove(ob, do_unlink=True)
    scythe.build_scythe()
    hands, bones = anatomy.build_hands()
    anatomy.build_torso()
    BUILT["body_rig"] = rig.build_body_rig(bones, [hands, sleeves])
    for ob in bpy.data.objects:
        ob.hide_render = ob.hide_render or ob.name.endswith("Proxy")
    if sculpted:
        for ob in [o for o in bpy.data.objects if o.type == "MESH" and o.data.name in SCULPTED]:
            sculpt.apply(ob)


# pièces sculptées à la brosse (#89) : une séance chacune dans death/sessions/
SCULPTED = ("Shroud", "Torso", "Hands", "Blade", "ScytheHead", "Shaft")


def sculpted(name):
    """Cette méthode permet de donner la version détaillée sculptée d'une pièce (cuisson), ou None : pipeline.py la
    préfère alors à la subdivision."""
    return sculpt.detailed(name)


def checks():
    """Cette méthode permet de rendre les mesures propres à la Mort pour le rapport de pipeline.py (contact des doigts,
    skinning, silhouette) ; erreurs si un défaut connu revient."""
    return death_checks.run()


def measures():
    """Cette méthode permet de rendre les mesures écrites dans death.measured.json en plus des pièces : place des os
    du corps (repère Roblox de la racine, relue par le remontage pour caler le rig R15), sommets attendus de la robe."""
    body = BUILT.get("body_rig") or bpy.data.objects.get("BodyRig")
    out = {"cloakGridVertices": veil.expected_cloak_vertices()}
    if body:
        out["bodyBones"] = rig.joints(body)
    # sculpts plaqués (#89) : empreinte de la base et niveaux de multirésolution, relus par le test du manifeste
    out["sculpt"] = {name: {"base": sc.get("base"), "levels": sc.get("levels")} for name, sc in sculpt.LOADED.items()}
    out["sculptFile"] = os.path.relpath(sculpt.FILE, os.path.join(HERE, "..", "..")).replace("\\", "/")
    return out


def bake_strokes(name, low):
    """Cette méthode permet de donner les traits de sculpt propres à une pièce (plis de la chair aux articulations des
    doigts), ou None : pipeline.py les ajoute à la version détaillée avant cuisson."""
    if name == "Hands" and name not in sculpt.LOADED:  # sculptées : les plis sont dans le sculpt
        return anatomy.crease_strokes()
    return None


if __name__ == "__main__":
    build_all()
