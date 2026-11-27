"""Cuisson Cycles sans interface (`blender -b`) de la version détaillée vers la version jouable (UV) : normales
(espace tangent, convention OpenGL comme Roblox), occlusion, couleur, rugosité ; PNG 1024 (grandes pièces) ou 512.

La couleur finale multiplie la couleur cuite par l'occlusion (Roblox n'a pas de carte d'occlusion), en valeurs sRGB
codées : voulu, les creux en sortent un peu plus sombres qu'un produit linéaire (choix de rendu, pas d'erreur). Les
modificateurs de la pièce jouable (épaisseur, armature) sont coupés pendant la cuisson : on cuit la surface seule, les
deux faces de l'épaisseur partagent ensuite les UV.
"""

import os

import bpy
import numpy as np

MAPS = ("normal", "ao", "color", "roughness")


def _setup(scene, samples):
    """Cette méthode permet de régler Cycles pour une cuisson reproductible (CPU, graine fixe)."""
    try:
        scene.render.engine = "CYCLES"
    except TypeError as e:  # le message liste les moteurs valides
        raise RuntimeError(f"Cycles indisponible : {e}") from e
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.seed = 0
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 8
    scene.render.bake.use_selected_to_active = True


def _image(name, size, data):
    """Cette méthode permet de créer l'image cible d'une carte (données brutes pour normales, rugosité, occlusion)."""
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    if data:
        img.colorspace_settings.is_data = True
    return img


def _save(img, path):
    """Cette méthode permet d'écrire une image en PNG 8 bits."""
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def bake_maps(high, low, out_dir, prefix, size=1024, samples=32, extrusion=0.08, max_ray=0.25, ao_floor=0.35):
    """Cette méthode permet de cuire `high` sur `low` et d'écrire `<prefix>_color|normal|roughness.png` dans out_dir
    (plus `<prefix>_ao.png`, intermédiaire) ; renvoie {carte: chemin}."""
    scene = bpy.context.scene
    _setup(scene, samples)
    os.makedirs(out_dir, exist_ok=True)
    # la pièce jouable ne fait pas d'ombre sur sa version détaillée (elles se confondent)
    saved_vis = {k: getattr(low, k) for k in ("visible_diffuse", "visible_glossy", "visible_shadow",
                                               "visible_transmission", "visible_volume_scatter")}
    for k in saved_vis:
        setattr(low, k, False)
    saved_mods = [(m, m.show_render, m.show_viewport) for m in low.modifiers]
    for m, _r, _v in saved_mods:
        m.show_render = False
        m.show_viewport = False
    mat = low.active_material
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = node
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bk = scene.render.bake
    bk.cage_extrusion = extrusion
    bk.max_ray_distance = max_ray
    out = {}
    pixels = {}
    try:
        for kind in MAPS:
            img = _image(f"{prefix}_{kind}", size, kind != "color")
            node.image = img
            with bpy.context.temp_override(active_object=low, object=low, selected_objects=[high, low]):
                if kind == "normal":
                    bk.normal_space = "TANGENT"
                    bpy.ops.object.bake(type="NORMAL")
                elif kind == "ao":
                    bpy.ops.object.bake(type="AO")
                elif kind == "color":
                    bk.use_pass_direct = False
                    bk.use_pass_indirect = False
                    bk.use_pass_color = True
                    bpy.ops.object.bake(type="DIFFUSE")
                else:
                    bpy.ops.object.bake(type="ROUGHNESS")
            arr = np.empty(size * size * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            pixels[kind] = arr
            path = os.path.join(out_dir, f"{prefix}_{kind}.png")
            if kind != "color":
                _save(img, path)
                out[kind] = path
        # couleur x occlusion (plancher ao_floor : l'occlusion assombrit sans noircir)
        col = pixels["color"].reshape(-1, 4)
        ao = pixels["ao"].reshape(-1, 4)[:, :1]
        col[:, :3] *= ao_floor + (1 - ao_floor) * ao
        img = bpy.data.images[f"{prefix}_color"]
        img.pixels.foreach_set(col.ravel())
        path = os.path.join(out_dir, f"{prefix}_color.png")
        _save(img, path)
        out["color"] = path
    finally:
        mat.node_tree.nodes.remove(node)
        for k, v in saved_vis.items():
            setattr(low, k, v)
        for m, r, v in saved_mods:
            m.show_render = r
            m.show_viewport = v
    return out


def stats(path):
    """Cette méthode permet de résumer une carte cuite (moyenne et écart par canal) pour le compte rendu."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    arr = arr.reshape(-1, 4)[:, :3]
    bpy.data.images.remove(img)
    return {"size": [w, h], "mean": [round(float(x), 3) for x in arr.mean(0)],
            "std": [round(float(x), 3) for x in arr.std(0)]}
