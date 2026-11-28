"""Rejoue toutes les séances de sculpt (#89) puis enregistre assets/sculpt/death_sculpt.blend. Blender avec interface
seulement (les brosses projettent leurs traits depuis la vue 3D) ; depuis le MCP `blender` :

    p = r"<worktree>/tools/blender/death/sessions/run_all.py"
    exec(open(p, encoding="utf-8").read(), {"__name__": "__main__", "__file__": p})

À relancer quand le script change une base sculptée (la chaîne signale alors un sculpt périmé), puis relancer
tools/blender/pipeline.py (sans interface) pour cuire et exporter.
"""

import io
import os
import sys
import time
from contextlib import redirect_stdout

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.path.normpath(os.path.join(HERE, "..", ".."))
if BLENDER not in sys.path:
    sys.path.insert(0, BLENDER)


def sessions():
    """Cette méthode permet de donner la séance de chaque pièce sculptée (death_model.SCULPTED) ; importées après la
    construction, pour lire les mêmes modules qu'elle (articulations des mains relevées par anatomy)."""
    from death.sessions import hands, head, scythe as scythe_s, torso

    return {
        "Shroud": head.run,
        "Torso": torso.run,
        "Hands": hands.run,
        "Blade": scythe_s.blade,
        "ScytheHead": scythe_s.head,
        "Shaft": scythe_s.shaft,
    }


def part(name):
    """Cette méthode permet de trouver la pièce jouable d'un nom (maillage du même nom)."""
    return next(o for o in bpy.data.objects if o.type == "MESH" and o.data.name == name)


def main(only=None):
    """Cette méthode permet de reconstruire les bases (sans sculpt, sans drapé), de jouer les séances (toutes, ou
    celles de `only`) et d'enregistrer le résultat ; renvoie les pièces enregistrées."""
    path = os.path.join(BLENDER, "death_model.py")
    g = {"__name__": "death_model_sessions", "__file__": path}
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), g)
    g["build_all"](drape=False, sculpted=False)
    from death import sculpt

    done = []
    for name, run in sessions().items():
        if only and name not in only:
            continue
        t0 = time.time()
        with redirect_stdout(io.StringIO()):  # la vue 3D se redessine à chaque trait (journal bavard)
            run(part(name))
        print(f"SCULPT {name} en {time.time() - t0:.1f}s")
        done.append(part(name))
    saved = sculpt.save(done)
    print(f"SCULPT enregistré : {saved} -> {sculpt.FILE}")
    return saved


if __name__ == "__main__":
    main()
