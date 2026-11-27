"""Modèle de la Mort (#81, outillage #79) : spectre décharné à voile en lambeaux, archétype du « détraqueur » (pas un
personnage existant), qui tient la faux.

Le modèle est découpé en modules (tools/blender/death/) :
- posture : squelette de référence (colonne voûtée, crâne penché, épaules, bras), d'où part tout le reste ;
- veil : suaire, robe trouée à os, lanières, manches ; drapés par simulation de tissu sur un corps de substitution ;
- anatomy : bras et mains griffues (chair desséchée sur les os, d'un seul tenant), torse aux côtes saillantes ;
- scythe : faux forgée et ébréchée, manche de bois naturel ;
- rig : armature du corps (os des bras, remontés sur le rig R15 dans Studio) ;
- checks : contact des doigts, skinning, silhouette.

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

from death import anatomy, checks as death_checks, posture, rig, scythe, veil  # noqa: E402
from lib import mesh  # noqa: E402

GROUND = posture.GROUND
SEED = posture.SEED
# nombre d'images du drapé de la robe : fixe, le résultat en dépend (empreinte dans death.measured.json)
DRAPE_FRAMES = 70
# objets de la dernière construction (armature du corps, pour les mesures)
BUILT = {}


def build_all(drape=True):
    """Cette méthode permet de reconstruire tout le spectre : corps de substitution, drapés, anatomie, faux, armatures ;
    les corps de substitution sont retirés à la fin."""
    mesh.clear_scene()
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


def checks():
    """Cette méthode permet de rendre les mesures propres à la Mort pour le rapport de pipeline.py (contact des doigts,
    skinning, silhouette) ; erreurs si un défaut connu revient."""
    return death_checks.run()


def measures():
    """Cette méthode permet de rendre les mesures écrites dans death.measured.json en plus des pièces : place des os
    du corps (repère Roblox de la racine), relue par le remontage pour caler le rig R15."""
    body = BUILT.get("body_rig") or bpy.data.objects.get("BodyRig")
    return {"bodyBones": rig.joints(body)} if body else {}


def bake_strokes(name, low):
    """Cette méthode permet de donner les traits de sculpt propres à une pièce (plis de la chair aux articulations des
    doigts), ou None : pipeline.py les ajoute à la version détaillée avant cuisson."""
    if name == "Hands":
        return anatomy.crease_strokes()
    return None


if __name__ == "__main__":
    build_all()
