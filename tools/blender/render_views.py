"""Rendus de contrôle d'un modèle : 7 vues fixes en PNG (face, 3/4, profil, dos, gros plans capuche, main, lame), à
comparer avant et après chaque changement (#79 ; base reprise de worktrees/.render/render_views.py).

  blender -b --factory-startup --python tools/blender/render_views.py -- <dossier> [options]   (racine du dépôt)

Options :
  --model death        manifeste tools/models/<modèle>.manifest.json (défaut : death)
  --script <chemin>    construit avec un autre script de modèle (ancienne version : `git show main:<script>`) ;
                       il est exécuté comme `__main__`, sans argument
  --textured           EEVEE, textures cuites posées sur les pièces (ce que reçoit la SurfaceAppearance) ;
                       défaut : Workbench, tissus éclaircis, pour lire la forme
  --no-drape           robe sans simulation de tissu
Affiche aussi les triangles par pièce.
"""

import importlib.util
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from lib import mesh, textures  # noqa: E402

# nom -> (position de la caméra, cible, focale) ; repère Blender du modèle (sol à -3,65, avant vers +Y)
VIEWS = {
    "front": ((0, 16, 0), (0, 0, -0.2), 45),
    "three_quarter": ((10, 11, 2), (0.3, 0, 0), 45),
    "side": ((16, 0, 0.5), (0, 0, 0), 45),
    "back": ((-4, -15, 1), (0, 0, 0), 45),
    "hood_close": ((0.6, 4.5, 2.4), (0, 0, 1.9), 50),
    "hand_close": ((2.8, 3.4, 0.6), (1.35, 1.1, 0.3), 50),
    "blade_close": ((0.2, 7, 3.8), (-0.3, 1.0, 3.6), 45),
}
CLOTH = ("CloakCloth", "HoodCloth")


def args():
    """Cette méthode permet de lire le dossier de sortie et les options passés après `--`."""
    argv = sys.argv[sys.argv.index("--") + 1 :]
    opts = {"out": argv[0], "model": "death", "script": None, "textured": False, "drape": True}
    k = 1
    while k < len(argv):
        a = argv[k]
        if a in ("--model", "--script"):
            opts[a[2:]] = argv[k + 1]
            k += 1
        elif a == "--textured":
            opts["textured"] = True
        elif a == "--no-drape":
            opts["drape"] = False
        else:
            raise SystemExit(f"option inconnue : {a}")
        k += 1
    return opts


def build(opts):
    """Cette méthode permet de construire le modèle (script du manifeste, ou ancien script exécuté tel quel)."""
    if opts["script"]:
        path = os.path.abspath(opts["script"])
        saved = sys.argv
        sys.argv = [path]  # un ancien script exporte s'il voit `--`
        try:
            exec(open(path, encoding="utf-8").read(), {"__name__": "__main__", "__file__": path})
        finally:
            sys.argv = saved
        return None
    with open(os.path.join(ROOT, "tools", "models", f"{opts['model']}.manifest.json"), encoding="utf-8") as f:
        m = json.load(f)
    spec = importlib.util.spec_from_file_location("model_script", os.path.join(ROOT, m["script"]))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.build_all(drape=opts["drape"])
    return m


def count_tris():
    """Cette méthode permet d'afficher les triangles par pièce et le total."""
    total = 0
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.hide_render:
            n = mesh.tri_count(o)
            total += n
            print(f"TRIS {o.data.name}: {n}")
    print(f"TRIS TOTAL: {total}")


def setup_form(sc):
    """Cette méthode permet de régler Workbench pour lire la forme : tissus presque noirs éclaircis."""
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = True
    for mat in bpy.data.materials:
        if mat.name in CLOTH:
            mat.diffuse_color = (0.35, 0.33, 0.38, 1)
        if mat.name == "Void":
            mat.diffuse_color = (0.02, 0.02, 0.02, 1)


def setup_textured(sc, model):
    """Cette méthode permet de régler EEVEE avec une lumière de nuit froide et une lampe chaude, et de poser les
    textures cuites (mesures du manifeste) sur leurs pièces."""
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = engine
            break
        except TypeError:
            continue
    world = bpy.data.worlds.new("Nuit")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.03, 0.035, 0.05, 1)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    for name, energy, color, rot in (
        ("Lune", 2.5, (0.75, 0.82, 1.0), (0.9, 0.2, 0.6)),
        ("Lampe", 6.0, (1.0, 0.85, 0.65), (1.2, 0.0, -0.9)),
    ):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.data.color = color
        light.rotation_euler = rot
        mesh.link(light)
    measured = os.path.join(ROOT, "tools", "models", f"{model}.measured.json")
    maps = {}
    if os.path.isfile(measured):
        with open(measured, encoding="utf-8") as f:
            maps = json.load(f).get("textures", {})
    for o in bpy.data.objects:
        if o.type == "MESH" and o.data.name in maps:
            paths = {k: os.path.join(ROOT, v) for k, v in maps[o.data.name].items()}
            o.data.materials.clear()
            o.data.materials.append(textures.textured_material(f"{o.data.name}_baked", paths))
            print(f"TEXTURES {o.data.name}: {sorted(paths)}")


def shot(sc, cam, out, name, pos, target, lens):
    """Cette méthode permet de rendre une vue depuis pos vers target."""
    cam.location = Vector(pos)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    sc.render.filepath = os.path.join(out, f"{name}.png")
    bpy.ops.render.render(write_still=True)


def main():
    """Cette méthode permet de construire le modèle puis de rendre les 7 vues."""
    opts = args()
    if opts["textured"] and opts["script"]:
        raise SystemExit("--textured ne s'applique qu'au modèle du manifeste (pas à --script)")
    build(opts)
    count_tris()
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    if opts["textured"]:
        setup_textured(sc, opts["model"])
    else:
        setup_form(sc)
    cam = mesh.link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    sc.camera = cam
    os.makedirs(opts["out"], exist_ok=True)
    for name, (pos, target, lens) in VIEWS.items():
        shot(sc, cam, opts["out"], name, pos, target, lens)


if __name__ == "__main__":
    main()
