"""Chaîne de production d'un modèle (#79) : construire, contrôler, cuire, mesurer, exporter. Sans interface.

  blender -b --factory-startup --python tools/blender/pipeline.py -- [options]   (depuis la racine du dépôt)

Options :
  --model death     manifeste tools/models/<modèle>.manifest.json (défaut : death)
  --bake            cuit les pièces qui ont une entrée "bake" (version détaillée -> textures PNG dans
                    assets/textures/<modèle>/), seulement si les contrôles passent ; sinon les textures restent
  --glb <chemin>    exporte la version jouable (pièces du manifeste et armature) en GLB
  --blend <chemin>  enregistre la scène (contrôle à l'œil, jamais versionnée)
  --no-drape        robe sans simulation de tissu (forme dessinée, plus rapide ; ni --bake ni --glb)
  --no-write        n'écrit pas <modèle>.measured.json
  --accept-drape    accepte un drapé différent avec les mêmes sources (nouvelle version de Blender constatée)

Sortie : rapport (triangles par pièce, contrôles propres au modèle, empreinte du drapé), code 1 si un contrôle échoue
(dont un drapé différent avec les mêmes sources) ; dans ce cas ni cuisson, ni mesures, ni GLB.
"""

import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from lib import bake, cloth, detail, manifest, textures  # noqa: E402

# part des pixels très inclinés de chaque carte de normales cuite (%, #85), écrite dans les mesures
BAKE_SPIKES = {}
# au-delà, la cuisson est refusée (taches visibles, #85) : ni mesures ni GLB
SPIKES_MAX_PCT = 0.2


def args():
    """Cette méthode permet de lire les options passées après `--`."""
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    opts = {"model": "death", "bake": False, "glb": None, "blend": None, "drape": True, "write": True,
            "accept_drape": False}
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("--model", "--glb", "--blend"):
            if k + 1 >= len(argv):
                raise SystemExit(f"{a} attend une valeur")
            opts[a[2:]] = argv[k + 1]
            k += 1
        elif a == "--bake":
            opts["bake"] = True
        elif a == "--no-drape":
            opts["drape"] = False
        elif a == "--no-write":
            opts["write"] = False
        elif a == "--accept-drape":
            opts["accept_drape"] = True
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


def bake_part(m, model, name, spec, out_dir):
    """Cette méthode permet de cuire une pièce : version détaillée (sculpt le long de la grille si la pièce en a
    une, traits propres au modèle), matériau CC0 ou procédural, cuisson vers la pièce jouable dans `out_dir` ;
    renvoie {carte: chemin}."""
    low = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == name and not o.name.endswith("_hi"))
    cfg = spec["bake"]
    seed = cfg.get("seed", 0)
    strokes = []
    if cfg.get("strokes") and "grid_i" in low.data.attributes:
        ai = low.data.attributes["grid_i"].data
        aj = low.data.attributes["grid_j"].data
        cols = max(a.value for a in ai) + 1
        rows = max(a.value for a in aj) + 1
        strokes += detail.grid_strokes(low, cfg["strokes"], rows, cols, seed, j_min=rows // 6)
    if hasattr(model, "bake_strokes"):
        strokes += model.bake_strokes(name, low) or []
    t0 = time.time()
    hi = detail.detailed_copy(
        low, seed, levels=cfg.get("subdiv", 3), strokes=strokes or None, noise=tuple(cfg["noise"]),
        fine=tuple(cfg["fine"])
    )
    hi.data.materials.clear()
    if cfg.get("shader") == "flesh":
        hi.data.materials.append(textures.flesh_material(f"{name}_hi", seed))
    else:
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
    extrusion, max_ray = cfg.get("cage", (0.05, 0.1))
    maps = bake.bake_maps(hi, low, out_dir, name, size=cfg["size"], extrusion=extrusion, max_ray=max_ray,
                          normal=cfg.get("normal", True))
    t2 = time.time()
    bpy.data.objects.remove(hi, do_unlink=True)
    print(f"BAKE {name}: détail {hi_tris} faces en {t1 - t0:.1f}s, cuisson {cfg['size']}px en {t2 - t1:.1f}s")
    for kind, path in maps.items():
        st = bake.stats(path, normal=kind == "normal")
        print(f"BAKE {name} {kind}: {st}")
        if kind == "normal":
            BAKE_SPIKES[name] = st["spikesPct"]
    return maps


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


def sources_hash(m):
    """Cette méthode permet de résumer le script du modèle et la bibliothèque en une empreinte lorsqu'on vérifie que
    le drapé n'a changé que parce que ses sources ont changé."""
    h = hashlib.sha1()
    paths = [os.path.join(ROOT, m["script"])]
    lib = os.path.join(HERE, "lib")
    paths += sorted(os.path.join(lib, f) for f in os.listdir(lib) if f.endswith(".py"))
    for p in paths:
        with open(p, "rb") as f:
            h.update(f.read().replace(b"\r\n", b"\n"))
    return h.hexdigest()[:12]


def main():
    """Cette méthode permet d'enchaîner construction, contrôles, cuisson, mesures et export."""
    opts = args()
    if (opts["bake"] or opts["glb"]) and not opts["drape"]:
        raise SystemExit("--bake et --glb exigent le drapé : sans lui, la cape n'est pas celle du jeu (ni des mesures)")
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
    measured_path = os.path.join(ROOT, "tools", "models", f"{opts['model']}.measured.json")
    if skin_ob is not None:
        extra["drape"] = {"frames": getattr(model, "DRAPE_FRAMES", 0) if opts["drape"] else 0,
                          "vertices": len(skin_ob.data.vertices),
                          "fingerprint": cloth.fingerprint(skin_ob),
                          "sources": sources_hash(m),
                          "blender": bpy.app.version_string}
        print(f"DRAPE {extra['drape']}")
        # mêmes sources, autre drapé : la simulation n'est plus déterministe (version de Blender, threads)
        if opts["drape"] and os.path.isfile(measured_path):
            with open(measured_path, encoding="utf-8") as f:
                before = json.load(f).get("drape", {})
            same = before.get("sources") == extra["drape"]["sources"] and before.get("blender") == bpy.app.version_string
            if same and before.get("fingerprint") != extra["drape"]["fingerprint"] and not opts["accept_drape"]:
                errors.append(f"drapé non déterministe : empreinte {extra['drape']['fingerprint']} au lieu de "
                              f"{before.get('fingerprint')} avec les mêmes sources")
    out_dir = os.path.join(ROOT, "assets", "textures", opts["model"])
    # cuisson dans un dossier temporaire : les textures versionnées ne sont remplacées que si la cuisson est acceptée
    bake_dir = tempfile.mkdtemp(prefix=f"bake_{opts['model']}_")
    fresh = {}
    baked = {}
    for name, spec in m["parts"].items():
        if not spec.get("bake"):
            continue
        if opts["bake"] and not errors:
            fresh[name] = bake_part(m, model, name, spec, bake_dir)
        else:
            kinds = ("color", "normal", "roughness") if spec["bake"].get("normal", True) else ("color", "roughness")
            maps = {k: f"assets/textures/{opts['model']}/{name}_{k}.png" for k in kinds}
            if all(os.path.isfile(os.path.join(ROOT, p)) for p in maps.values()):
                baked[name] = maps
    if BAKE_SPIKES:
        extra["bakeSpikesPct"] = dict(BAKE_SPIKES)
        for name, pct in BAKE_SPIKES.items():
            limit = m["parts"][name]["bake"].get("spikesMax", SPIKES_MAX_PCT)
            if pct > limit:
                errors.append(f"carte de normales de {name} : {pct} % de pixels très inclinés (> {limit})")
    if fresh and not errors:
        os.makedirs(out_dir, exist_ok=True)
        for name, maps in fresh.items():
            baked[name] = {}
            for kind, path in maps.items():
                dest = os.path.join(out_dir, os.path.basename(path))
                shutil.move(path, dest)
                if kind != "ao":
                    baked[name][kind] = os.path.relpath(dest, ROOT).replace("\\", "/")
    elif fresh:
        print(f"textures cuites refusées, laissées dans {bake_dir} (assets/textures inchangé)")
    elif os.path.isfile(measured_path):
        # sans cuisson, les mesures de la dernière cuisson acceptée restent
        with open(measured_path, encoding="utf-8") as f:
            kept = json.load(f).get("bakeSpikesPct")
        if kept:
            extra["bakeSpikesPct"] = kept
    if baked:
        extra["textures"] = baked
    if hasattr(model, "measures"):
        extra.update(model.measures())
    for name, p in measured["parts"].items():
        print(f"TRIS {name}: {p['tris']}")
    print(f"TRIS TOTAL: {measured['totalTris']} (budget {m['budget']['totalTris']})")
    if opts["write"] and not errors:
        if opts["drape"]:
            manifest.write_measured(measured_path, m, measured, extra)
        else:
            print("mesures non écrites : sans drapé, la cape n'est pas celle du jeu")
    if opts["glb"] and not errors:
        export_glb(m, opts["glb"])
    elif opts["glb"]:
        print("GLB non exporté : contrôles en échec")
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
