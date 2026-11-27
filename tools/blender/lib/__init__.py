"""Bibliothèque de production des modèles Blender du jeu (#79), sans crédits de génération.

- mesh : surfaces paramétriques en grille (UV et indices de grille gardés), tubes, sphères, épaisseur ;
- detail : version détaillée d'une pièce (subdivision, sculpt par script, Geometry Nodes, déplacement procédural) ;
- cloth : drapé par simulation de tissu native, déterministe, puis figé ;
- textures : matières CC0 (assets/textures/cc0) branchées sur un matériau Principled ;
- bake : cuisson Cycles sans interface (normales, occlusion, couleur, rugosité) en PNG ;
- manifest : noms attendus par le code, budgets de triangles, mesures écrites pour Lune et le remontage Studio.

Les scripts de modèle ajoutent tools/blender au chemin Python puis font `from lib import mesh, ...`.
"""
