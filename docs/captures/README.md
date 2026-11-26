# Captures de la carte

Rendu réel de la maison dans Studio, depuis des points de vue fixes (`tools/captures.luau`), pour suivre l'évolution de
la carte d'une PR à l'autre. L'historique git de chaque image montre les versions successives. Plan sans Studio :
`docs/plan/`.

| Vue | Capture |
|---|---|
| Ensemble côté rue (jour) | ![](ensemble-rue.jpg) |
| Ensemble côté jardin (jour) | ![](ensemble-jardin.jpg) |
| Cave en coupe (jour) | ![](niveau-cave.jpg) |
| Rez-de-chaussée en coupe (jour) | ![](niveau-rdc.jpg) |
| Étage en coupe (jour) | ![](niveau-etage.jpg) |
| Façade depuis la rue, éclairage du jeu (nuit) | ![](nuit-rue.jpg) |

Vues de dessus : le haut de l'image est le côté rue. Les vues « jour » remplacent l'éclairage de nuit pour lire le
décor ; seule `nuit-rue` montre la carte telle qu'en manche.

## Pièces

Une vue par pièce intérieure, calculée depuis `Shared.HouseLayout` : plongée depuis le côté rue (bas de l'image),
niveaux supérieurs masqués, pièces voisines visibles autour. Une pièce ajoutée au plan a sa vue sans retouche de
l'outil ; la galerie ci-dessous est réécrite par `stamp`. Les zones extérieures sont dans les vues d'ensemble.

<!-- pieces:debut (généré par lune run tools/captures -- stamp) -->

| Pièce | Niveau | Capture |
|---|---|---|
| Cave | Cave | ![](pieces/cave.jpg) |
| Cellier | Cave | ![](pieces/cellar.jpg) |
| Cave à vin | Cave | ![](pieces/winecellar.jpg) |
| Atelier | Cave | ![](pieces/workshop.jpg) |
| Escalier de la cave | Cave | ![](pieces/cavestairs.jpg) |
| Escalier de l'atelier | Cave | ![](pieces/workshopstairs.jpg) |
| Salon | Rez-de-chaussée | ![](pieces/living.jpg) |
| Entrée | Rez-de-chaussée | ![](pieces/entry.jpg) |
| Dégagement | Rez-de-chaussée | ![](pieces/halldown.jpg) |
| Salle à manger | Rez-de-chaussée | ![](pieces/dining.jpg) |
| Cuisine | Rez-de-chaussée | ![](pieces/kitchen.jpg) |
| Bibliothèque | Rez-de-chaussée | ![](pieces/library.jpg) |
| Buanderie | Rez-de-chaussée | ![](pieces/laundry.jpg) |
| Véranda | Rez-de-chaussée | ![](pieces/veranda.jpg) |
| Garage | Rez-de-chaussée | ![](pieces/garage.jpg) |
| Escalier | Rez-de-chaussée | ![](pieces/stairs.jpg) |
| Escalier du garage | Rez-de-chaussée | ![](pieces/garagestairs.jpg) |
| Bureau | Étage | ![](pieces/study.jpg) |
| Palier | Étage | ![](pieces/hallup.jpg) |
| Chambre des parents | Étage | ![](pieces/masterbedroom.jpg) |
| Dressing | Étage | ![](pieces/dressing.jpg) |
| Salle de bain | Étage | ![](pieces/bathroom.jpg) |
| Chambre d'enfant | Étage | ![](pieces/kidsbedroom.jpg) |
| Couloir de l'étage | Étage | ![](pieces/halleast.jpg) |
| Chambre d'amis | Étage | ![](pieces/guestbedroom.jpg) |
| Chambre d'ado | Étage | ![](pieces/teenbedroom.jpg) |
| Salle d'eau | Étage | ![](pieces/showerroom.jpg) |
| Grenier | Étage | ![](pieces/attic.jpg) |
| Abri de jardin | Rez-de-chaussée | ![](pieces/shed.jpg) |

<!-- pieces:fin -->

## Quand les reprendre

`tools/check.sh` (étape `captures`, aussi en CI) échoue dès qu'une source de la carte a changé depuis la dernière prise
(`sources.sha256` : HouseLayout, HouseGeometry, HouseStyle, NightLighting, HouseBuilder, NightAmbience), ou qu'une vue
n'a pas d'image (pièce ajoutée). La PR qui change la carte reprend donc les captures avant de merger.

## Procédure (Studio via le MCP, sous le verrou)

1. `.\scripts\dth-worktree.ps1 <branche> -AcquireStudio`, puis lancer le Play (`start_stop_play`).
2. `lune run tools/captures -- install` imprime la mise en scène : l'exécuter une fois avec `execute_luau`, contexte
   `Server` (elle installe `_G.DeathCapture`, gardé jusqu'à l'arrêt du Play).
3. `lune run tools/captures -- list` : les vues groupées par scène. Pour chaque groupe, exécuter sa ligne `scène`
   (`execute_luau`, `Server`), puis pour chaque vue `screen_capture` avec ses `camera_position` et
   `look_at_position` ; le MCP enregistre un jpg et donne son chemin.
4. Arrêter le Play, `-ReleaseStudio`.
5. `lune run tools/captures -- save <vue> <jpg> [<vue> <jpg> ...]`, puis `lune run tools/captures -- stamp`, et
   regarder les images avant de commiter (cadrage, éléments masqués).

Images en Git LFS (`.gitattributes`). Un nouveau point de vue fixe s'ajoute dans `VIEWS` (`tools/captures.luau`) et
dans le premier tableau.
