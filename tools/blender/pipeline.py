"""Chaîne de production d'un modèle (#79) : construire, contrôler, cuire, mesurer, exporter. Sans interface.

  blender -b --factory-startup --python tools/blender/pipeline.py -- [options]   (depuis la racine du dépôt)

Options :
  --model death     manifeste tools/models/<modèle>.manifest.json (défaut : death)
  --bake            cuit les pièces qui ont une entrée "bake" (version détaillée -> textures PNG dans
                    assets/textures/<modèle>/) ; sans cette option, les textures déjà cuites restent
  --glb <chemin>    exporte la version jouable (pièces du manifeste et armature) en GLB
  --blend <chemin>  enregistre la scène (contrôle à l'œil, jamais versionnée)
  --no-drape        robe sans simulation de tissu (forme dessinée, plus rapide)
  --no-write        n'écrit pas <modèle>.measured.json

Sortie : rapport (triangles par pièce, contrôles propres au modèle, empreinte du drapé), code 1 si un contrôle échoue.
"""

import importlib.util
import os
import sys
import time

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from lib import bake, cloth, detail, manifest, textures  # noqa: E402


def args():
    """Cette méthode permet de lire les options passées après `--`."""
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    opts = {"model": "death", "bake": False, "glb": None, "blend": None, "drape": True, "write": True}
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("--model", "--glb", "--blend"):
            opts[a[2:]] = argv[k + 1]
            k += 1
        elif a == "--bake":
            opts["bake"] = True
        elif a == "--no-drape":
            opts["drape"] = False
        elif a == "--no-write":
            opts["write"] = False
        else:
            raise SystemExit(f"option inconnue : {a}")
        k += 1
    return opts


def load_model(m):
    """Cette méthode permet de charger le script de modèle désigné par le manifeste."""
    path = os.path.join(ROOT, m["script"])
    spec = importlib.util.spec_from_file_location("model_script", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def bake_part(m, name, spec, out_dir):
    """Cette méthode permet de cuire une pièce : version détaillée (sculpt le long de la grille si la pièce en a
    une), matériau CC0, cuisson vers la pièce jouable ; renvoie {carte: chemin relatif}."""
    low = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == name and not o.name.endswith("_hi"))
    cfg = spec["bake"]
    seed = cfg.get("seed", 0)
    strokes = None
    if cfg.get("strokes") and "grid_i" in low.data.attributes:
        ai = low.data.attributes["grid_i"].data
        aj = low.data.attributes["grid_j"].data
        cols = max(a.value for a in ai) + 1
        rows = max(a.value for a in aj) + 1
        strokes = detail.grid_strokes(low, cfg["strokes"], rows, cols, seed, j_min=rows // 6)
    t0 = time.time()
    hi = detail.detailed_copy(
        low, seed, levels=cfg.get("subdiv", 3), strokes=strokes, noise=tuple(cfg["noise"]), fine=tuple(cfg["fine"])
    )
    hi.data.materials.clear()
    hi.data.materials.append(
        textures.cc0_material(
            f"{name}_hi",
            cfg["cc0"],
            cfg["dark"],
            cfg["light"],
            rough=tuple(cfg["rough"]),
            scale=tuple(cfg["scale"]),
            normal_strength=cfg.get("normalStrength", 1.0),
            grime=cfg.get("grime", 0.5),
        )
    )
    hi_tris = len(hi.data.polygons)
    t1 = time.time()
    maps = bake.bake_maps(hi, low, out_dir, name, size=cfg["size"])
    t2 = time.time()
    bpy.data.objects.remove(hi, do_unlink=True)
    print(f"BAKE {name}: détail {hi_tris} faces en {t1 - t0:.1f}s, cuisson {cfg['size']}px en {t2 - t1:.1f}s")
    for kind, path in maps.items():
        print(f"BAKE {name} {kind}: {bake.stats(path)}")
    return {k: os.path.relpath(v, ROOT).replace("\\", "/") for k, v in maps.items() if k != "ao"}


def export_glb(m, path):
    """Cette méthode permet d'exporter en GLB les seules pièces du manifeste et l'armature qui les anime."""
    found = manifest.part_objects(m)
    keep = [obs[0] for obs in found.values()]
    for ob in list(keep):
        for md in ob.modifiers:
            if md.type == "ARMATURE" and md.object and md.object not in keep:
                keep.append(md.object)
    for o in bpy.context.view_layer.objects:
        o.select_set(o in keep)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_apply=True, export_yup=True, use_selection=True
    )
    print(f"GLB {path} ({os.path.getsize(path)} octets)")


def main():
    """Cette méthode permet d'enchaîner construction, contrôles, cuisson, mesures et export."""
    opts = args()
    mpath = os.path.join(ROOT, "tools", "models", f"{opts['model']}.manifest.json")
    m = manifest.load(mpath)
    model = load_model(m)
    t0 = time.time()
    model.build_all(drape=opts["drape"])
    print(f"BUILD {m['model']} en {time.time() - t0:.1f}s (drapé : {opts['drape']})")
    measured, errors = manifest.check(m)
    extra = {}
    if hasattr(model, "checks"):
        report, model_errors = model.checks()
        errors += model_errors
        extra["checks"] = report
        for k, v in report.items():
            print(f"CHECK {k}: {v}")
    skin = m["bones"]["skin"]
    skin_ob = manifest.part_objects(m).get(skin, [None])[0]
    if skin_ob is not None:
        extra["drape"] = {"frames": getattr(model, "DRAPE_FRAMES", 0) if opts["drape"] else 0,
                          "vertices": len(skin_ob.data.vertices),
                          "fingerprint": cloth.fingerprint(skin_ob)}
        print(f"DRAPE {extra['drape']}")
    out_dir = os.path.join(ROOT, "assets", "textures", opts["model"])
    baked = {}
    for name, spec in m["parts"].items():
        if not spec.get("bake"):
            continue
        if opts["bake"]:
            baked[name] = bake_part(m, name, spec, out_dir)
        else:
            maps = {k: f"assets/textures/{opts['model']}/{name}_{k}.png" for k in ("color", "normal", "roughness")}
            if all(os.path.isfile(os.path.join(ROOT, p)) for p in maps.values()):
                baked[name] = maps
    if baked:
        extra["textures"] = baked
    for name, p in measured["parts"].items():
        print(f"TRIS {name}: {p['tris']}")
    print(f"TRIS TOTAL: {measured['totalTris']} (budget {m['budget']['totalTris']})")
    if opts["write"] and not errors:
        if opts["drape"]:
            manifest.write_measured(os.path.join(ROOT, "tools", "models", f"{opts['model']}.measured.json"), m,
                                    measured, extra)
        else:
            print("mesures non écrites : sans drapé, la cape n'est pas celle du jeu")
    if opts["glb"]:
        export_glb(m, opts["glb"])
    if opts["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=opts["blend"])
    for e in errors:
        print(f"ERREUR {e}")
    print("PIPELINE " + ("ÉCHEC" if errors else "OK"))
    sys.stdout.flush()
    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
