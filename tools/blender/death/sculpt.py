"""Sculpt versionné du spectre (#89) : les pièces sculptées à la brosse (tools/blender/death/sessions/, Blender avec
interface) sont enregistrées dans assets/sculpt/death_sculpt.blend (Git LFS), puis relues sans interface par la chaîne
(tools/blender/pipeline.py, via death_model.build_all).

Une pièce sculptée y est un objet `<Pièce>__sculpt` : la base construite par script (même topologie) et son
modificateur multirésolution, qui porte le sculpt. À la construction :
- la pièce jouable garde sa topologie, ses poids d'os, ses UV et ses attributs ; ses sommets sont recalés sur le sculpt
  (« Apply Base » de la multirésolution : la base qui, subdivisée, approche le mieux le sculpt) ;
- la version détaillée de la cuisson est le sculpt à son niveau le plus fin (detail.detailed_copy, `sculpted`).

Garde-fou : l'empreinte de la base (sommets, faces, positions) est gardée avec le sculpt. Si le script construit une
autre base (posture, grille changées), le sculpt est périmé : la chaîne échoue au lieu de plaquer un sculpt décalé.
Le rejouer : séance de la pièce dans Blender avec interface, puis `save`.
"""

import hashlib
import os

import bpy

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
FILE = os.path.join(ROOT, "assets", "sculpt", "death_sculpt.blend")
SUFFIX = "__sculpt"
# sculpts relus par la dernière construction : {pièce: objet sculpt (caché)}
LOADED = {}


def fingerprint(ob):
    """Cette méthode permet de résumer la base d'une pièce (nombre de sommets et de faces, positions arrondies au
    dix-millième) lorsqu'on vérifie qu'un sculpt correspond toujours au script."""
    me = ob.data
    h = hashlib.sha1()
    h.update(f"{len(me.vertices)}/{len(me.polygons)}".encode())
    for v in me.vertices:
        h.update(("%.4f,%.4f,%.4f;" % tuple(v.co)).encode())
    return h.hexdigest()[:12]


def part_name(ob):
    """Cette méthode permet de donner le nom de pièce d'un objet (nom du maillage sans suffixe .001 de Blender)."""
    return ob.data.name.split(".")[0].removesuffix(SUFFIX)


def save(objects, path=None):
    """Cette méthode permet d'enregistrer les pièces sculptées (objets à multirésolution, Blender avec interface)
    dans le fichier versionné : copie `<Pièce>__sculpt` de la base et de sa seule multirésolution, empreinte de la
    base ; les sculpts déjà enregistrés des autres pièces sont gardés."""
    path = path or FILE
    keep = {}
    if os.path.isfile(path):
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = [n for n in src.objects if n.endswith(SUFFIX)]
        for o in dst.objects:
            if o is not None:
                keep[o.name.split(".")[0]] = o
    out = set()
    for ob in objects:
        mr = next(m for m in ob.modifiers if m.type == "MULTIRES")
        name = part_name(ob)
        old = keep.pop(name + SUFFIX, None)
        if old is not None:
            bpy.data.objects.remove(old, do_unlink=True)
        cp = ob.copy()
        cp.data = ob.data.copy()
        cp.name = cp.data.name = name + SUFFIX
        cp.parent = None
        cp.matrix_world = ob.matrix_world.copy()
        for m in list(cp.modifiers):
            if m.name != mr.name:
                cp.modifiers.remove(m)
        cp.vertex_groups.clear()
        cp["base"] = fingerprint(cp)
        cp["levels"] = mr.total_levels
        out.add(cp)
    out.update(keep.values())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.data.libraries.write(path, out, fake_user=True, compress=True)
    names = sorted(o.name for o in out)
    for o in out:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
    return names


def load(name, path=None):
    """Cette méthode permet de relire le sculpt d'une pièce (objet caché, multirésolution au niveau le plus fin), ou
    None si la pièce n'est pas sculptée."""
    path = path or FILE
    if not os.path.isfile(path):
        return None
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n == name + SUFFIX]
    if not dst.objects or dst.objects[0] is None:
        return None
    ob = dst.objects[0]
    bpy.context.scene.collection.objects.link(ob)
    mr = next(m for m in ob.modifiers if m.type == "MULTIRES")
    mr.levels = mr.sculpt_levels = mr.render_levels = mr.total_levels
    ob.hide_render = True
    ob.hide_set(True)
    return ob


def apply(part, path=None):
    """Cette méthode permet de recaler la pièce jouable `part` sur son sculpt (mêmes sommets, positions de la base
    qui approche le sculpt) lorsqu'il existe ; renvoie l'objet sculpt (gardé pour la cuisson) ou None ; erreur si le
    sculpt est périmé."""
    name = part_name(part)
    sc = load(name, path)
    if sc is None:
        return None
    base = fingerprint(part)
    if sc.get("base") != base:
        raise RuntimeError(f"sculpt de {name} périmé : base {base} construite, {sc.get('base')} sculptée "
                           f"(rejouer tools/blender/death/sessions/ dans Blender avec interface)")
    tmp = sc.copy()
    tmp.data = sc.data.copy()
    bpy.context.scene.collection.objects.link(tmp)
    mr = next(m for m in tmp.modifiers if m.type == "MULTIRES")
    with bpy.context.temp_override(object=tmp, active_object=tmp, selected_objects=[tmp],
                                   selected_editable_objects=[tmp]):
        bpy.ops.object.multires_base_apply(modifier=mr.name)
    for v, w in zip(part.data.vertices, tmp.data.vertices):
        v.co = w.co
    part.data.update()
    bpy.data.meshes.remove(tmp.data)
    LOADED[name] = sc
    return sc


def detailed(name):
    """Cette méthode permet de construire la version détaillée d'une pièce sculptée (le sculpt au niveau le plus fin,
    appliqué), nommée `<pièce>_hi` ; None si la pièce n'est pas sculptée."""
    sc = LOADED.get(name)
    if sc is None:
        return None
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(sc.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
    me.name = f"{name}_hi"
    hi = bpy.data.objects.new(f"{name}_hi", me)
    bpy.context.scene.collection.objects.link(hi)
    hi.matrix_world = sc.matrix_world.copy()
    return hi


def clear():
    """Cette méthode permet d'oublier les sculpts relus (nouvelle construction)."""
    LOADED.clear()
