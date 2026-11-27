"""Construction de maillages par script : grilles paramétriques, tubes, sphères, épaisseur, matériaux simples.

Unités : 1 unité Blender = 1 stud. Une grille garde ses indices (attributs entiers `grid_i`, `grid_j` sur les sommets)
et ses UV : une simulation ou un sculpt qui ne change pas le nombre de sommets laisse donc les poids d'os et les UV
valides, et les poids peuvent être recalculés d'après (i, j).
"""

import math

import bmesh
import bpy
from mathutils import Vector


def clear_scene():
    """Cette méthode permet de repartir d'une scène vide lorsqu'on reconstruit un modèle."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images, bpy.data.textures):
        for d in list(coll):
            coll.remove(d)
    for ng in list(bpy.data.node_groups):
        bpy.data.node_groups.remove(ng)


def interp(keys, t):
    """Cette méthode permet d'interpoler en douceur un profil (t, valeurs...) lorsqu'on échantillonne une forme."""
    if t <= keys[0][0]:
        return list(keys[0][1:])
    for a, b in zip(keys, keys[1:]):
        if a[0] <= t <= b[0]:
            k = (t - a[0]) / (b[0] - a[0])
            k = k * k * (3 - 2 * k)
            return [a[i] + (b[i] - a[i]) * k for i in range(1, len(a))]
    return list(keys[-1][1:])


def smoothstep(e0, e1, x):
    """Cette méthode permet de passer en douceur de 0 à 1 entre e0 et e1."""
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    k = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return k * k * (3 - 2 * k)


def warp_samples(n, density, closed=False, steps=2000):
    """Cette méthode permet de répartir n échantillons dans [0, 1] selon une densité (plus dense là où density(u)
    est grand) lorsqu'une zone demande plus de résolution (bord d'ouverture) ; closed : [0, 1[ périodique."""
    cum = [0.0]
    for k in range(steps):
        cum.append(cum[-1] + density((k + 0.5) / steps))
    total = cum[-1]
    out = []
    count = n if closed else n - 1
    m = 0
    for s in range(n):
        target = total * s / count
        while m < steps and cum[m + 1] < target:
            m += 1
        if m >= steps:
            out.append(1.0)
            continue
        a, b = cum[m], cum[m + 1]
        out.append((m + (target - a) / (b - a if b > a else 1)) / steps)
    return out


def lerp(a, b, t):
    """Cette méthode permet d'interpoler deux points."""
    return Vector(a).lerp(Vector(b), t)


def material(name, rgb, metallic=0.0, roughness=0.8):
    """Cette méthode permet de créer un matériau nommé (une zone de skin) lorsqu'une pièce en a besoin."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*rgb, 1)
    return mat


def link(ob):
    """Cette méthode permet de rattacher un objet neuf à la collection de la scène."""
    bpy.context.scene.collection.objects.link(ob)
    return ob


def grid_object(name, cols, rows, fn, keep=None, weights=None, wrap=True, uv_shift=0):
    """Cette méthode permet de construire une surface en grille (colonnes x rangées) lorsqu'une forme est
    paramétrique ; weights(i, j) renvoie {groupe: poids} pour le skinning. UV : u = colonne (décalée de uv_shift
    colonnes, pour cacher la couture), v = rangée ; attributs `grid_i`, `grid_j` gardés sur chaque sommet."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    gi = bm.verts.layers.int.new("grid_i")
    gj = bm.verts.layers.int.new("grid_j")
    verts = [[bm.verts.new(fn(i, j)) for i in range(cols)] for j in range(rows)]
    for j in range(rows):
        for i in range(cols):
            verts[j][i][gi] = i
            verts[j][i][gj] = j
    last = cols if wrap else cols - 1
    span = cols if wrap else cols - 1
    for j in range(rows - 1):
        for i in range(last):
            if keep is None or keep(i, j):
                i2 = (i + 1) % cols
                f = bm.faces.new((verts[j][i], verts[j][i2], verts[j + 1][i2], verts[j + 1][i]))
                iu = (i + uv_shift) % cols if wrap else i
                corners = ((iu, j), (iu + 1, j), (iu + 1, j + 1), (iu, j + 1))
                for loop, (cu, cv) in zip(f.loops, corners):
                    loop[uv].uv = (cu / span, cv / (rows - 1))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = link(bpy.data.objects.new(name, me))
    if weights:
        set_weights(ob, weights)
    return ob


def grid_index(ob):
    """Cette méthode permet de retrouver l'index de sommet de chaque case (i, j) d'une grille, après simulation ou
    sculpt (les attributs suivent les sommets)."""
    me = ob.data
    ai = me.attributes["grid_i"].data
    aj = me.attributes["grid_j"].data
    return {(ai[k].value, aj[k].value): k for k in range(len(me.vertices))}


def set_weights(ob, weights):
    """Cette méthode permet de (re)calculer les poids d'os d'une grille d'après ses attributs (i, j) lorsqu'on la
    skinne, avant ou après un drapé."""
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {}
    for (i, j), k in grid_index(ob).items():
        for g, w in weights(i, j).items():
            if w <= 0:
                continue
            if g not in groups:
                groups[g] = ob.vertex_groups.new(name=g)
            groups[g].add([k], w, "REPLACE")


def set_group(ob, name, fn):
    """Cette méthode permet de créer un groupe de sommets dont le poids vient de fn(i, j) (épinglage du tissu, masque
    de détail)."""
    old = ob.vertex_groups.get(name)
    if old:
        ob.vertex_groups.remove(old)
    g = ob.vertex_groups.new(name=name)
    for (i, j), k in grid_index(ob).items():
        w = fn(i, j)
        if w > 0:
            g.add([k], min(1.0, w), "REPLACE")
    return g


def solidify(ob, thickness):
    """Cette méthode permet de donner une épaisseur à une surface lorsqu'elle doit être étanche pour Roblox."""
    s = ob.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = thickness
    s.offset = 0
    s.use_even_offset = False  # l'épaisseur régulière fait exploser les angles vifs (poche de la capuche)
    s.use_quality_normals = True
    return s


def apply_modifier(ob, name):
    """Cette méthode permet d'appliquer un modificateur sans interface (contexte forcé sur l'objet)."""
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=name)


def tri_count(ob):
    """Cette méthode permet de compter les triangles d'un objet après ses modificateurs (ce que Roblox recevra)."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(deps)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ev.to_mesh_clear()
    return n


def bounds(ob):
    """Cette méthode permet de donner la boîte englobante (min, max) monde d'un objet évalué (modificateurs, armature
    au repos compris)."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [ob.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


class Builder:
    """Accumule de la géométrie (tubes, sphères, grilles) dans un bmesh avec UV, puis crée l'objet."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _face(self, vs, uvs):
        """Cette méthode permet d'ajouter une face avec ses UV lorsqu'on tisse une grille."""
        f = self.bm.faces.new(vs)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def grid(self, rows, closed_u=True, cap_start=False, cap_end=False):
        """Cette méthode permet de tisser une grille de sommets (rows[j][i]) en quads, UV u = i, v = j normalisés,
        avec des bouchons éventuels aux extrémités."""
        bm = self.bm
        vs = [[bm.verts.new(p) for p in row] for row in rows]
        n = len(rows[0])
        last = n if closed_u else n - 1
        for j in range(len(rows) - 1):
            for i in range(last):
                i2 = (i + 1) % n
                u0, u1 = i / n if closed_u else i / (n - 1), (i + 1) / n if closed_u else (i + 1) / (n - 1)
                v0, v1 = j / (len(rows) - 1), (j + 1) / (len(rows) - 1)
                self._face(
                    (vs[j][i], vs[j][i2], vs[j + 1][i2], vs[j + 1][i]), ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
                )
        for flag, row in ((cap_start, vs[0]), (cap_end, vs[-1])):
            if flag:
                c = bm.verts.new(sum((v.co for v in row), Vector()) / len(row))
                for i in range(len(row)):
                    self._face((row[i], row[(i + 1) % len(row)], c), ((0.5, 0.5), (0.5, 0.5), (0.5, 0.5)))
        return vs

    def tube(self, pts, radii, segs=10, cap=True, radial=None):
        """Cette méthode permet de balayer un cercle le long d'une polyligne (repère transporté) lorsqu'on modélise
        un manche, un os ou une bague ; radial(u, v) module le rayon (filetage, nœuds)."""
        pts = [Vector(p) for p in pts]
        rows = []
        prev_n = None
        for k, p in enumerate(pts):
            t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
            if prev_n is None:
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                n = t.cross(ref).normalized()
            else:
                n = (prev_n - t * prev_n.dot(t)).normalized()
            prev_n = n
            b = t.cross(n)
            row = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                r = radii[k] * (radial(i / segs, k / (len(pts) - 1)) if radial else 1)
                row.append(p + (n * math.cos(a) + b * math.sin(a)) * r)
            rows.append(row)
        return self.grid(rows, cap_start=cap, cap_end=cap)

    def sphere(self, center, radius, segs=10, rings=6, scale=(1, 1, 1)):
        """Cette méthode permet d'ajouter une sphère (articulation, gemme) lorsqu'une pièce en a besoin."""
        c = Vector(center)
        rows = []
        for j in range(1, rings):
            ph = math.pi * j / rings
            rows.append(
                [
                    c
                    + Vector(
                        (
                            radius * scale[0] * math.sin(ph) * math.cos(2 * math.pi * i / segs),
                            radius * scale[1] * math.sin(ph) * math.sin(2 * math.pi * i / segs),
                            radius * scale[2] * math.cos(ph),
                        )
                    )
                    for i in range(segs)
                ]
            )
        return self.grid(rows, cap_start=True, cap_end=True)

    def finish(self, mat, smooth=True):
        """Cette méthode permet de créer l'objet Blender à partir de la géométrie accumulée."""
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = link(bpy.data.objects.new(self.name, me))
        for p in me.polygons:
            p.use_smooth = smooth
        ob.data.materials.append(mat)
        return ob
