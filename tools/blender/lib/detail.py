"""Version détaillée d'une pièce, destinée à la cuisson (jamais exportée) : subdivision, sculpt par script (sillons et
bourrelets le long de traits), Geometry Nodes appliqués (bosses de bruit le long des normales), déplacement procédural
(texture de bruit fin). Tout est tiré d'une graine fixe : même graine, même détail.
"""

import math
import random

import bpy
from mathutils import Vector, kdtree

from . import mesh


def copy_geometry(ob, name):
    """Cette méthode permet de copier la géométrie d'une pièce, sans ses modificateurs (épaisseur, armature), lorsqu'on
    en fait une version détaillée."""
    me = ob.data.copy()
    me.name = name
    hi = mesh.link(bpy.data.objects.new(name, me))
    hi.matrix_world = ob.matrix_world.copy()
    return hi


def subdivide(ob, levels):
    """Cette méthode permet de subdiviser (Catmull-Clark, UV lissées) et d'appliquer."""
    m = ob.modifiers.new("Subdiv", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    m.uv_smooth = "PRESERVE_CORNERS"
    mesh.apply_modifier(ob, m.name)


def sculpt_strokes(ob, strokes):
    """Cette méthode permet de sculpter par script : chaque trait (points, rayon, profondeur) creuse un sillon
    (profondeur > 0) ou lève un bourrelet (< 0) le long des normales, avec une chute douce ; renvoie le nombre de
    sommets touchés."""
    me = ob.data
    n = len(me.vertices)
    kd = kdtree.KDTree(n)
    for v in me.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    offset = {}
    for pts, radius, depth in strokes:
        pts = [Vector(p) for p in pts]
        samples = []
        for a, b in zip(pts, pts[1:]):
            steps = max(1, int((b - a).length / (radius * 0.35)))
            samples += [a.lerp(b, k / steps) for k in range(steps)]
        samples.append(pts[-1])
        # la profondeur s'annule aux deux bouts du trait
        for s_i, p in enumerate(samples):
            taper = math.sin(math.pi * (s_i + 0.5) / len(samples))
            for _co, idx, dist in kd.find_range(p, radius):
                fall = 1 - mesh.smoothstep(0, 1, dist / radius)
                d = depth * taper * fall
                if abs(d) > abs(offset.get(idx, 0.0)):
                    offset[idx] = d
    for idx, d in offset.items():
        v = me.vertices[idx]
        v.co -= v.normal * d
    me.update()
    return len(offset)


def grid_strokes(ob, count, rows, cols, seed, radius=(0.06, 0.13), depth=(0.012, 0.03), length=(5, 12), drift=0.6,
                 j_min=0):
    """Cette méthode permet de tirer des traits de sculpt qui descendent une grille (plis de tissu qui tombent) : chaque
    trait suit la surface d'une rangée à l'autre, en dérivant un peu de colonne ; points pris sur `ob` (grille avec
    attributs grid_i/grid_j, avant subdivision)."""
    rnd = random.Random(seed)
    index = mesh.grid_index(ob)
    co = ob.data.vertices
    strokes = []
    for _ in range(count):
        i = rnd.uniform(0, cols)
        j = rnd.randint(j_min, max(j_min, rows - 3))
        n = rnd.randint(*length)
        pts = []
        for k in range(n):
            jj = min(rows - 1, j + k)
            i0 = int(math.floor(i)) % cols
            i1 = (i0 + 1) % cols
            w = i - math.floor(i)
            if (i0, jj) not in index or (i1, jj) not in index:
                break
            pts.append(co[index[(i0, jj)]].co.lerp(co[index[(i1, jj)]].co, w))
            i += rnd.uniform(-drift, drift)
        if len(pts) >= 3:
            sign = 1 if rnd.random() < 0.7 else -1  # surtout des sillons, quelques bourrelets
            strokes.append((pts, rnd.uniform(*radius), sign * rnd.uniform(*depth)))
    return strokes


def gn_noise(ob, scale, strength, seed):
    """Cette méthode permet d'ajouter des bosses de bruit le long des normales par Geometry Nodes, puis d'appliquer
    (le nœud reste dans le fichier source, jamais à l'export)."""
    ng = bpy.data.node_groups.new(f"DetailNoise_{ob.name}", "GeometryNodeTree")
    ng.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    nodes, links = ng.nodes, ng.links
    gin = nodes.new("NodeGroupInput")
    gout = nodes.new("NodeGroupOutput")
    pos = nodes.new("GeometryNodeInputPosition")
    nor = nodes.new("GeometryNodeInputNormal")
    offset_pos = nodes.new("ShaderNodeVectorMath")
    offset_pos.operation = "ADD"
    offset_pos.inputs[1].default_value = (seed * 7.31, seed * 3.17, seed * 1.93)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.55
    centre = nodes.new("ShaderNodeMath")
    centre.operation = "SUBTRACT"
    centre.inputs[1].default_value = 0.5
    amount = nodes.new("ShaderNodeMath")
    amount.operation = "MULTIPLY"
    amount.inputs[1].default_value = strength * 2
    scale_n = nodes.new("ShaderNodeVectorMath")
    scale_n.operation = "SCALE"
    setpos = nodes.new("GeometryNodeSetPosition")
    links.new(pos.outputs["Position"], offset_pos.inputs[0])
    links.new(offset_pos.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], centre.inputs[0])
    links.new(centre.outputs["Value"], amount.inputs[0])
    links.new(nor.outputs["Normal"], scale_n.inputs[0])
    links.new(amount.outputs["Value"], scale_n.inputs["Scale"])
    links.new(gin.outputs["Geometry"], setpos.inputs["Geometry"])
    links.new(scale_n.outputs["Vector"], setpos.inputs["Offset"])
    links.new(setpos.outputs["Geometry"], gout.inputs["Geometry"])
    m = ob.modifiers.new("DetailNoise", "NODES")
    m.node_group = ng
    mesh.apply_modifier(ob, m.name)


def displace(ob, size, strength, seed, kind="DISTORTED_NOISE"):
    """Cette méthode permet d'ajouter un déplacement procédural fin (froissé du tissu, grain de l'os) puis
    d'appliquer."""
    tex = bpy.data.textures.new(f"Displace_{ob.name}", kind)
    tex.noise_scale = size
    if hasattr(tex, "distortion"):
        tex.distortion = 1.2
    m = ob.modifiers.new("Displace", "DISPLACE")
    m.texture = tex
    m.strength = strength
    m.mid_level = 0.5
    # la graine décale la texture dans l'espace
    empty = bpy.data.objects.new(f"DisplaceOrigin_{ob.name}", None)
    mesh.link(empty)
    empty.location = (seed * 0.37, seed * 0.71, seed * 0.13)
    m.texture_coords = "OBJECT"
    m.texture_coords_object = empty
    mesh.apply_modifier(ob, m.name)
    bpy.data.objects.remove(empty, do_unlink=True)


def detailed_copy(ob, seed, levels=3, strokes=None, noise=(1.6, 0.035), fine=(0.12, 0.012)):
    """Cette méthode permet de construire la version détaillée d'une pièce (nom `<pièce>_hi`, cachée au rendu des
    vues) : subdivision, sculpt par script, bruit Geometry Nodes, déplacement fin ; renvoie l'objet."""
    hi = copy_geometry(ob, f"{ob.name}_hi")
    subdivide(hi, levels)
    if strokes:
        sculpt_strokes(hi, strokes)
    if noise:
        gn_noise(hi, noise[0], noise[1], seed)
    if fine:
        displace(hi, fine[0], fine[1], seed)
    for p in hi.data.polygons:
        p.use_smooth = True
    return hi
