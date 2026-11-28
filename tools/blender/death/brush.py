"""Sculpt à la brosse dans la session Blender avec interface (#89) : vraies brosses de sculpt (Draw, Clay Strips,
Crease, Inflate, Pinch, Grab, Layer...), multirésolution et masques, pilotés par des traits posés en 3D.

Chaque trait est projeté depuis une vue orthographique tournée vers la zone (direction `view`, de la cible vers
l'œil), puis joué par `bpy.ops.sculpt.brush_stroke` : la brosse raycaste la surface comme sous la souris. Rayon en
studs (taille de brosse verrouillée sur la scène), indépendant du zoom.

Ne marche qu'avec une fenêtre (projection par la vue 3D) : `blender -b` ne peut pas rejouer ces traits. Le résultat
est donc enregistré comme maillage source (assets/sculpt/death_sculpt.blend, LFS) que tools/blender/death/sculpt.py
relit sans interface ; les séances de sculpt (tools/blender/death/sessions/) restent la recette, rejouable ici.
"""

import math

import bpy
from bpy_extras import view3d_utils
from mathutils import Quaternion, Vector

LIBRARY = "brushes/essentials_brushes-mesh_sculpt.blend/Brush/"


def view3d():
    """Cette méthode permet de trouver la fenêtre, la zone et la région de la vue 3D lorsqu'on projette un trait."""
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                region = next(r for r in area.regions if r.type == "WINDOW")
                return win, area, region
    raise RuntimeError("pas de vue 3D : le sculpt à la brosse demande Blender avec interface")


def begin(ob, levels):
    """Cette méthode permet de préparer une pièce au sculpt (objet actif, mode sculpt, multirésolution à `levels`
    niveaux) lorsqu'une séance commence."""
    win, area, region = view3d()
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.view_layer.objects:
        o.select_set(o is ob)
    bpy.context.view_layer.objects.active = ob
    mr = next((m for m in ob.modifiers if m.type == "MULTIRES"), None)
    if mr is None:
        from lib import detail

        # bords et arêtes marquées gardés vifs (ourlet, griffes), comme la subdivision de la cuisson. Pas les arêtes
        # anguleuses : la pièce jouable est lissée à travers elles, une arête vive au sculpt demandait à la carte de
        # normales des corrections plus fortes (mesuré : lame 0,48 -> 0,67 %, douille 4,2 -> 5,4 %)
        detail.crease_boundary(ob)
        mr = ob.modifiers.new("Sculpt", "MULTIRES")
        mr.use_creases = True
        mr.boundary_smooth = "PRESERVE_CORNERS"
        # avant l'épaisseur et l'armature : on sculpte la surface seule
        _move_first(ob, mr)
    with bpy.context.temp_override(window=win, area=area, region=region, object=ob, active_object=ob):
        while mr.total_levels < levels:
            bpy.ops.object.multires_subdivide(modifier=mr.name, mode="CATMULL_CLARK")
    mr.levels = mr.sculpt_levels = mr.render_levels = levels
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.object.mode_set(mode="SCULPT")
    return mr


def _move_first(ob, mod):
    """Cette méthode permet de placer un modificateur en tête de pile lorsqu'on ajoute la multirésolution."""
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)


def end():
    """Cette méthode permet de revenir en mode objet après une séance."""
    win, area, region = view3d()
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.object.mode_set(mode="OBJECT")


def use(name):
    """Cette méthode permet d'activer une brosse des brosses essentielles de Blender (nom affiché)."""
    win, area, region = view3d()
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.brush.asset_activate(asset_library_type="ESSENTIALS", asset_library_identifier="",
                                     relative_asset_identifier=LIBRARY + name)
    return bpy.context.tool_settings.sculpt.brush


def symmetry(x=False):
    """Cette méthode permet de régler la symétrie miroir du sculpt (axe X du maillage : la tête, le torse)."""
    me = bpy.context.object.data
    me.use_mirror_x = x


def look_from(target, view, distance=3.0, scale=1.6):
    """Cette méthode permet de tourner la vue 3D (orthographique) vers `target`, l'œil dans la direction `view`."""
    win, area, region = view3d()
    rv = area.spaces[0].region_3d
    d = Vector(view).normalized()
    # la vue regarde le long de -Z local : on aligne -Z sur -d, Y (haut de l'écran) au plus près de +Z monde
    up = Vector((0, 0, 1))
    if abs(d.dot(up)) > 0.98:
        up = Vector((0, 1, 0))
    z = d
    x = up.cross(z).normalized()
    y = z.cross(x)
    from mathutils import Matrix

    m = Matrix((x, y, z)).transposed()
    rv.view_rotation = m.to_quaternion()
    rv.view_perspective = "ORTHO"
    rv.view_location = Vector(target)
    rv.view_distance = scale
    rv.update()
    area.tag_redraw()
    bpy.ops.wm.redraw_timer(type="DRAW_WIN_SWAP", iterations=1)
    return win, area, region, rv


def resample(points, step):
    """Cette méthode permet de répartir des points réguliers (pas `step`) le long d'une polyligne 3D."""
    pts = [Vector(p) for p in points]
    if len(pts) == 1:
        return pts
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.ceil((b - a).length / step)))
        out += [a.lerp(b, k / n) for k in range(1, n + 1)]
    return out


def stroke(points, radius, strength=0.5, view=None, invert=False, brush=None, spacing=0.15, pressure=1.0,
           scale=None):
    """Cette méthode permet de jouer un trait de brosse le long de `points` (monde, rayon en studs), vu depuis `view`
    lorsqu'une séance sculpte ; renvoie le nombre de touches posées."""
    if brush:
        use(brush)
    sculpt = bpy.context.tool_settings.sculpt
    b = sculpt.brush
    sculpt.unified_paint_settings.use_unified_size = False
    sculpt.unified_paint_settings.use_unified_strength = False
    b.use_locked_size = "SCENE"
    b.unprojected_size = 2 * radius  # Blender 5 : diamètre
    b.strength = strength
    if hasattr(b, "direction"):
        try:
            b.direction = "SUBTRACT" if invert else "ADD"
        except TypeError:
            try:
                b.direction = "DEFLATE" if invert else "INFLATE"
            except TypeError:
                pass
    # pression : constante, ou fonction de la position le long du trait (0 au début, 1 à la fin) ; elle règle la
    # force et la taille, comme un stylet (un pli qui s'effile)
    taper = callable(pressure)
    b.use_pressure_strength = taper
    b.use_pressure_size = taper
    pts = resample(points, max(radius * spacing, 1e-4))
    center = sum(pts, Vector()) / len(pts)
    span = max((p - center).length for p in pts) + radius * 2
    win, area, region, rv = look_from(center, view or Vector((0, 1, 0)), scale=scale or max(span * 1.3, 0.3))
    items = []
    for k, p in enumerate(pts):
        co = view3d_utils.location_3d_to_region_2d(region, rv, p)
        if co is None:
            continue
        pr = pressure(k / max(1, len(pts) - 1)) if taper else pressure
        items.append({"name": "", "location": p, "mouse": co, "mouse_event": co, "pressure": pr,
                      "size": 50.0, "x_tilt": 0.0, "y_tilt": 0.0, "time": float(k),
                      "is_start": k == 0})
    if not items:
        return 0
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.sculpt.brush_stroke(stroke=items, mode="NORMAL")
    return len(items)
