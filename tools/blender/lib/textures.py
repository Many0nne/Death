"""Matières CC0 (assets/textures/cc0, téléchargées par tools/blender/fetch_cc0.py) branchées sur un matériau
Principled de la version détaillée : la cuisson en tire couleur, rugosité et relief fin.

La couleur CC0 ne sert que de motif : sa luminance mélange deux teintes choisies par la pièce (la direction
artistique reste maîtresse de la palette), salie par un bruit large.
"""

import os

import bpy

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
CC0 = os.path.join(ROOT, "assets", "textures", "cc0")


def cc0_path(asset, suffix):
    """Cette méthode permet de trouver le fichier d'une carte CC0 (diff, nor_gl, rough, disp) ; erreur claire s'il
    manque (lancer fetch_cc0.py)."""
    path = os.path.join(CC0, asset, f"{asset}_{suffix}_1k.jpg")
    if not os.path.isfile(path):
        raise FileNotFoundError(f"{path} absent : python -I tools/blender/fetch_cc0.py")
    return path


def _image(nodes, asset, suffix, non_color):
    """Cette méthode permet d'ajouter un nœud d'image CC0 (espace de couleur adapté à la carte)."""
    node = nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(cc0_path(asset, suffix), check_existing=True)
    if non_color:
        img.colorspace_settings.is_data = True
    node.image = img
    return node


def cc0_material(name, asset, dark, light, rough=(0.7, 1.0), scale=(6.0, 4.0), normal_strength=1.0, grime=0.5,
                 metallic=0.0):
    """Cette méthode permet de créer le matériau détaillé d'une pièce à partir d'une matière CC0 : teinte entre
    `dark` et `light` (RGB linéaire) selon le motif CC0 et un bruit de saleté, rugosité CC0 ramenée dans `rough`,
    normales CC0 ; UV répétées `scale` fois."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = metallic
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale[0], scale[1], 1)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    diff = _image(nodes, asset, "diff", False)
    nor = _image(nodes, asset, "nor_gl", True)
    rgh = _image(nodes, asset, "rough", True)
    for n in (diff, nor, rgh):
        links.new(mapping.outputs["Vector"], n.inputs["Vector"])
    # couleur : luminance du motif x saleté (bruit large, coordonnées objet), entre les deux teintes
    lum = nodes.new("ShaderNodeRGBToBW")
    links.new(diff.outputs["Color"], lum.inputs["Color"])
    dirt = nodes.new("ShaderNodeTexNoise")
    dirt.inputs["Scale"].default_value = 1.4
    dirt.inputs["Detail"].default_value = 6.0
    links.new(uv.outputs["Object"], dirt.inputs["Vector"])
    mix_f = nodes.new("ShaderNodeMath")
    mix_f.operation = "MULTIPLY"
    links.new(lum.outputs["Val"], mix_f.inputs[0])
    dirt_mix = nodes.new("ShaderNodeMapRange")
    dirt_mix.inputs["To Min"].default_value = 1 - grime
    dirt_mix.inputs["To Max"].default_value = 1 + grime
    links.new(dirt.outputs["Fac"], dirt_mix.inputs["Value"])
    links.new(dirt_mix.outputs["Result"], mix_f.inputs[1])
    ramp = nodes.new("ShaderNodeMix")
    ramp.data_type = "RGBA"
    ramp.clamp_factor = True
    ramp.inputs["A"].default_value = (*dark, 1)
    ramp.inputs["B"].default_value = (*light, 1)
    links.new(mix_f.outputs["Value"], ramp.inputs["Factor"])
    links.new(ramp.outputs["Result"], bsdf.inputs["Base Color"])
    # rugosité CC0 ramenée dans la plage de la pièce
    rr = nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = rough[0]
    rr.inputs["To Max"].default_value = rough[1]
    links.new(rgh.outputs["Color"], rr.inputs["Value"])
    links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    nmap = nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = normal_strength
    links.new(nor.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def textured_material(name, maps, metallic=0.0):
    """Cette méthode permet de poser des textures cuites (chemins PNG color/normal/roughness) sur un matériau, comme
    les recevra la SurfaceAppearance de Roblox (rendus de contrôle)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = metallic
    if maps.get("color"):
        c = nodes.new("ShaderNodeTexImage")
        c.image = bpy.data.images.load(maps["color"], check_existing=True)
        links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    if maps.get("roughness"):
        r = nodes.new("ShaderNodeTexImage")
        r.image = bpy.data.images.load(maps["roughness"], check_existing=True)
        r.image.colorspace_settings.is_data = True
        links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    if maps.get("normal"):
        n = nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(maps["normal"], check_existing=True)
        n.image.colorspace_settings.is_data = True
        nm = nodes.new("ShaderNodeNormalMap")
        links.new(n.outputs["Color"], nm.inputs["Color"])
        links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat
