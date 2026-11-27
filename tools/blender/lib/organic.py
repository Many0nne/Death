"""Formes organiques par script (#81) : un maillage d'un seul tenant tiré d'un squelette de nœuds (modificateur Skin,
puis subdivision), là où des tubes et des sphères assemblés se reconnaîtraient (mains, bras, cou) ; poids d'os
d'après les segments du squelette ; aplatissement local (paume) ; lissage d'un champ de déplacement.

Un squelette est une liste de nœuds (nom, position, rayon, parent, os) : chaque segment parent -> nœud appartient à
l'os du nœud ; le maillage obtenu se skinne d'après le segment le plus proche, avec un fondu aux articulations.
"""

import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

from . import mesh


class Node:
    """Nœud d'un squelette organique : position, rayon (studs), parent (nom ou None) et os qui porte le segment."""

    def __init__(self, name, pos, radius, parent=None, bone=None):
        """Cette méthode permet de créer un nœud lorsqu'on décrit un squelette (bras, doigt)."""
        self.name = name
        self.pos = Vector(pos)
        self.radius = radius if isinstance(radius, tuple) else (radius, radius)
        self.parent = parent
        self.bone = bone


def skin_object(name, nodes, subdiv=1, smooth_iter=0):
    """Cette méthode permet de construire un maillage d'un seul tenant autour d'un squelette de nœuds (modificateur
    Skin appliqué, puis `subdiv` niveaux de Catmull-Clark) ; renvoie l'objet."""
    index = {n.name: k for k, n in enumerate(nodes)}
    me = bpy.data.meshes.new(name)
    edges = [(index[n.parent], k) for k, n in enumerate(nodes) if n.parent is not None]
    me.from_pydata([n.pos for n in nodes], edges, [])
    ob = mesh.link(bpy.data.objects.new(name, me))
    mod = ob.modifiers.new("Skin", "SKIN")
    mod.use_smooth_shade = True
    mod.branch_smoothing = 0.6
    layer = me.skin_vertices[0].data
    roots = 0
    for k, n in enumerate(nodes):
        layer[k].radius = n.radius
        layer[k].use_root = n.parent is None
        roots += n.parent is None
    assert roots >= 1, "squelette sans racine"
    mesh.apply_modifier(ob, mod.name)
    if smooth_iter:
        sm = ob.modifiers.new("Lisse", "SMOOTH")
        sm.iterations = smooth_iter
        sm.factor = 0.5
        mesh.apply_modifier(ob, sm.name)
    if subdiv:
        sub = ob.modifiers.new("Subdiv", "SUBSURF")
        sub.levels = subdiv
        sub.render_levels = subdiv
        mesh.apply_modifier(ob, sub.name)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def segments(nodes):
    """Cette méthode permet de lister les segments (a, b, os) d'un squelette, chaque nœud racine compté comme un point."""
    pos = {n.name: n for n in nodes}
    out = []
    for n in nodes:
        if n.parent is None:
            out.append((n.pos, n.pos, n.bone))
        else:
            out.append((pos[n.parent].pos, n.pos, n.bone))
    return out


def point_segment(p, a, b):
    """Cette méthode permet de donner la distance d'un point à un segment et la position relative (0 à 1) du projeté."""
    ab = b - a
    ll = ab.length_squared
    t = 0.0 if ll < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ll))
    return (p - (a + ab * t)).length, t


def skeleton_weights(ob, nodes, blend=0.6, limit=4):
    """Cette méthode permet de skinner un maillage organique d'après son squelette : chaque sommet suit l'os de ses
    segments les plus proches, avec un fondu (part `blend` du rayon) près des articulations ; au plus `limit` os par
    sommet (Roblox en lit 4), poids normalisés."""
    segs = [s for s in segments(nodes) if s[2]]
    radius = {n.bone: max(n.radius) for n in nodes if n.bone}
    groups = {}
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        scored = []
        for a, b, bone in segs:
            d, _t = point_segment(p, a, b)
            scored.append((d, bone))
        scored.sort(key=lambda x: x[0])
        best = scored[0][0]
        w = {}
        for d, bone in scored:
            # au-delà de best + blend x rayon, l'os ne compte plus ; fondu en cosinus
            span = blend * radius.get(bone, 0.05) + 1e-4
            k = (d - best) / span
            if k >= 1:
                continue
            w[bone] = max(w.get(bone, 0.0), 0.5 + 0.5 * math.cos(math.pi * k))
        top = sorted(w.items(), key=lambda x: -x[1])[:limit]
        total = sum(x[1] for x in top)
        for bone, x in top:
            if bone not in groups:
                groups[bone] = ob.vertex_groups.new(name=bone)
            groups[bone].add([v.index], x / total, "REPLACE")
    return groups


def flatten(ob, center, normal, factor, radius):
    """Cette méthode permet d'aplatir un maillage le long de `normal` autour du plan passant par `center` (part
    `factor`, 0 = inchangé), avec une chute douce au-delà de `radius` (paume, plat de l'avant-bras)."""
    n = Vector(normal).normalized()
    c = Vector(center)
    inv = ob.matrix_world.inverted()
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        d = (p - c).length
        k = factor * (1 - mesh.smoothstep(radius * 0.6, radius, d))
        if k <= 0:
            continue
        h = (p - c).dot(n)
        v.co = inv @ (p - n * h * k)
    ob.data.update()


def smooth_field(ob, field, iterations=3, factor=0.5):
    """Cette méthode permet de lisser un champ par sommet (dict index -> valeur) sur le maillage (voisins par arête)
    lorsqu'un déplacement sculpté ne doit pas créer de marche brutale (taches de la carte de normales, #85)."""
    me = ob.data
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    cur = [field.get(k, 0.0) for k in range(len(me.vertices))]
    for _ in range(iterations):
        nxt = cur[:]
        for k, ns in enumerate(nbr):
            if ns:
                avg = sum(cur[j] for j in ns) / len(ns)
                nxt[k] = cur[k] + (avg - cur[k]) * factor
        cur = nxt
    return {k: x for k, x in enumerate(cur) if abs(x) > 1e-7}


def set_zone(ob, zone):
    """Cette méthode permet de marquer toutes les faces d'un objet d'une zone de matière (attribut de face entier
    « zone » : 0 chair, 1 griffe...) lorsqu'une pièce n'a qu'une matière mais plusieurs aspects à la cuisson."""
    me = ob.data
    attr = me.attributes.get("zone") or me.attributes.new("zone", "INT", "FACE")
    for d in attr.data:
        d.value = zone


def merge_objects(name, obs):
    """Cette méthode permet de réunir plusieurs objets maillages en un seul (même pièce Roblox), groupes de sommets et
    UV gardés ; renvoie l'objet réuni (nommé `name`, maillage du même nom)."""
    base = obs[0]
    with bpy.context.temp_override(active_object=base, object=base, selected_editable_objects=obs,
                                   selected_objects=obs):
        bpy.ops.object.join()
    base.name = name
    base.data.name = name
    return base


def nearest_surface(ob):
    """Cette méthode permet de préparer une recherche du sommet le plus proche sur un objet (KD-tree monde)."""
    me = ob.data
    kd = KDTree(len(me.vertices))
    for v in me.vertices:
        kd.insert(ob.matrix_world @ v.co, v.index)
    kd.balance()
    return kd


def triangulate_count(ob):
    """Cette méthode permet de compter les triangles d'un objet sans ses modificateurs."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n = sum(len(f.verts) - 2 for f in bm.faces)
    bm.free()
    return n
