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


def flesh_material(name, seed=0):
    """Cette méthode permet de créer la matière procédurale de la chair desséchée (pas de peau CC0 convenable chez
    Poly Haven) : gris cendré sale, marbré de taches brunâtres et de veines sombres, rides fines en relief ; les faces
    d'attribut `zone` = 1 (griffes) prennent une corne jaunie, striée et plus brillante."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    coord = nodes.new("ShaderNodeTexCoord")
    shift = nodes.new("ShaderNodeVectorMath")
    shift.operation = "ADD"
    shift.inputs[1].default_value = (seed * 3.1, seed * 1.7, seed * 2.3)
    links.new(coord.outputs["Object"], shift.inputs[0])

    def noise(scale, detail=6.0, rough=0.6):
        n = nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        links.new(shift.outputs["Vector"], n.inputs["Vector"])
        return n

    def mix(a, b, fac, clamp=True):
        m = nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        m.clamp_factor = clamp
        for sock, val in (("A", a), ("B", b)):
            if isinstance(val, tuple):
                m.inputs[sock].default_value = (*val, 1)
            else:
                links.new(val, m.inputs[sock])
        if isinstance(fac, float):
            m.inputs["Factor"].default_value = fac
        else:
            links.new(fac, m.inputs["Factor"])
        return m.outputs["Result"]

    def ramp(src, lo, hi):
        r = nodes.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        links.new(src, r.inputs["Value"])
        return r.outputs["Result"]

    # chair : cendre grise, taches brunâtres (marbrure large), veines sombres (bruit étiré en crêtes)
    mottle = ramp(noise(3.0).outputs["Fac"], 0.42, 0.68)
    flesh = mix((0.16, 0.155, 0.145), (0.3, 0.29, 0.265), ramp(noise(9.0).outputs["Fac"], 0.3, 0.7))
    flesh = mix(flesh, (0.2, 0.15, 0.11), mottle)
    vein_src = noise(5.0, detail=3.0, rough=0.4)
    vein = nodes.new("ShaderNodeMath")
    vein.operation = "PINGPONG"
    vein.inputs[1].default_value = 0.5
    links.new(vein_src.outputs["Fac"], vein.inputs[0])
    veins = ramp(vein.outputs["Value"], 0.47, 0.5)
    inv = nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    links.new(veins, inv.inputs[1])
    vein_mix = nodes.new("ShaderNodeMath")
    vein_mix.operation = "MULTIPLY"
    vein_mix.inputs[1].default_value = 0.45
    links.new(inv.outputs["Value"], vein_mix.inputs[0])
    flesh = mix(flesh, (0.07, 0.065, 0.075), vein_mix.outputs["Value"])
    # griffes : corne jaunie, striée en long
    claw = mix((0.2, 0.16, 0.09), (0.42, 0.36, 0.22), ramp(noise(40.0, detail=2.0).outputs["Fac"], 0.35, 0.65))
    zone = nodes.new("ShaderNodeAttribute")
    zone.attribute_type = "GEOMETRY"
    zone.attribute_name = "zone"
    color = mix(flesh, claw, zone.outputs["Fac"])
    links.new(color, bsdf.inputs["Base Color"])
    rough = nodes.new("ShaderNodeMix")
    rough.data_type = "FLOAT"
    rough_flesh = nodes.new("ShaderNodeMapRange")
    rough_flesh.inputs["To Min"].default_value = 0.6
    rough_flesh.inputs["To Max"].default_value = 0.85
    links.new(noise(20.0).outputs["Fac"], rough_flesh.inputs["Value"])
    links.new(rough_flesh.outputs["Result"], rough.inputs["A"])
    rough.inputs["B"].default_value = 0.35
    links.new(zone.outputs["Fac"], rough.inputs["Factor"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    # rides fines : bosses de bruit serré, plus fortes sur la chair que sur la corne
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.004
    wr = noise(160.0, detail=4.0, rough=0.7)
    links.new(wr.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
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
