"""Drapé par simulation de tissu native de Blender, déterministe (nombre d'images fixe), puis figé.

Le tissu part d'une forme trop ample, épinglée en haut (groupe de sommets), et tombe sur un corps de substitution
(surface de collision) : l'excédent de tour forme des plis naturels, à la place des plis en sinusoïdes. Le maillage
garde ses sommets (même nombre, mêmes attributs `grid_i`/`grid_j`, mêmes UV) : les poids d'os restent valides.
"""

import bpy

from . import mesh


def proxy_body(name, cols, rows, fn):
    """Cette méthode permet de créer un corps de substitution fermé (surface de révolution fn(i, j)) sur lequel le
    tissu se pose ; à supprimer après le drapé."""
    ob = mesh.grid_object(name, cols, rows, fn)
    ob.modifiers.new("Collision", "COLLISION")
    ob.collision.thickness_outer = 0.03
    ob.collision.cloth_friction = 8.0
    ob.hide_render = True
    return ob


def ground(z, size=20.0):
    """Cette méthode permet d'ajouter un sol de collision (le bas du tissu ne passe pas dessous)."""
    me = bpy.data.meshes.new("ClothGround")
    me.from_pydata([(-size, -size, z), (size, -size, z), (size, size, z), (-size, size, z)], [], [(0, 1, 2, 3)])
    ob = mesh.link(bpy.data.objects.new("ClothGround", me))
    ob.modifiers.new("Collision", "COLLISION")
    ob.collision.thickness_outer = 0.02
    ob.hide_render = True
    return ob


def drape(ob, pin_group, frames=60, quality=8, mass=0.3, stiffness=15.0, self_collision=True, self_distance=0.03,
          shrink=0.0, bending=0.6):
    """Cette méthode permet de laisser tomber le tissu `ob` (épinglé par `pin_group`) pendant `frames` images, puis de
    figer le résultat dans son maillage ; renvoie le nombre de sommets, inchangé (déterminisme : cf. fingerprint).
    `bending` : raideur à la flexion (plus haut : tissu lourd, peu de plis, larges)."""
    scene = bpy.context.scene
    n_before = len(ob.data.vertices)
    mod = ob.modifiers.new("Cloth", "CLOTH")
    # le tissu passe avant tout autre modificateur (épaisseur, armature)
    while ob.modifiers[0] != mod:
        with bpy.context.temp_override(object=ob, active_object=ob):
            bpy.ops.object.modifier_move_up(modifier=mod.name)
    s = mod.settings
    s.quality = quality
    s.mass = mass
    s.tension_stiffness = stiffness
    s.compression_stiffness = stiffness
    s.shear_stiffness = stiffness * 0.5
    s.bending_stiffness = bending
    s.air_damping = 2.0
    s.vertex_group_mass = pin_group
    s.shrink_min = shrink
    c = mod.collision_settings
    c.collision_quality = 4
    c.distance_min = 0.012
    c.use_self_collision = self_collision
    # plis tenus à l'écart d'au moins l'épaisseur du tissu (sinon ils se traversent une fois épaissis)
    c.self_distance_min = self_distance
    mod.point_cache.frame_start = 1
    mod.point_cache.frame_end = frames
    scene.frame_start = 1
    scene.frame_end = frames
    # la simulation avance image par image depuis la première
    for f in range(1, frames + 1):
        scene.frame_set(f)
    mesh.apply_modifier(ob, mod.name)
    scene.frame_set(1)
    assert len(ob.data.vertices) == n_before, "le drapé a changé le nombre de sommets"
    return n_before


def fingerprint(ob, digits=4):
    """Cette méthode permet de résumer les positions des sommets en une empreinte courte lorsqu'on vérifie que deux
    drapés identiques donnent le même maillage."""
    import hashlib

    h = hashlib.sha1()
    for v in ob.data.vertices:
        h.update(("%.*f,%.*f,%.*f;" % (digits, v.co.x, digits, v.co.y, digits, v.co.z)).encode())
    return h.hexdigest()[:12]
