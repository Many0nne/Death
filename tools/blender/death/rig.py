"""Armature du corps du spectre (#81) : os des bras et des mains (`BodyRig`, racine `Spine`), sur lesquels sont skinnées
les pièces `Hands` et `Sleeves`. Dans Studio, le remontage (tools/rbxm/remount.luau) range chaque os sous la pièce du
rig R15 qui lui correspond (table `bones.body.attach` du manifeste) et cale les articulations du rig (épaule, coude,
poignet) sur ces os : animer le rig R15 anime les bras (#55, #74).
"""

import bpy
from mathutils import Vector

from lib import mesh

from . import posture

ROOT = "Spine"


def build_body_rig(bones, skinned):
    """Cette méthode permet de créer l'armature du corps (os (nom, tête, queue, parent)) et d'y skinner les pièces
    `skinned` (modificateur Armature, parentées à l'armature)."""
    arm = bpy.data.armatures.new("BodyRig")
    ob = mesh.link(bpy.data.objects.new("BodyRig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    spine = arm.edit_bones.new(ROOT)
    spine.head = posture.SPINE[2]
    spine.tail = posture.NECK_BASE
    made = {ROOT: spine}
    for name, head, tail, parent in bones:
        eb = arm.edit_bones.new(name)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        if (eb.tail - eb.head).length < 1e-3:
            eb.tail = eb.head + Vector((0, 0, 0.02))
        made[name] = eb
    for name, _h, _t, parent in bones:
        made[name].parent = made[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for part in skinned:
        mod = part.modifiers.new("Rig", "ARMATURE")
        mod.object = ob
        part.parent = ob
    return ob


def joints(rig):
    """Cette méthode permet de relever la tête et la queue de chaque os du corps (repère Roblox de la racine), pour le
    remontage : place des articulations du rig R15."""
    from lib.manifest import to_roblox

    out = {}
    for b in rig.data.bones:
        out[b.name] = {"head": to_roblox(rig.matrix_world @ b.head_local),
                       "tail": to_roblox(rig.matrix_world @ b.tail_local)}
    return out
