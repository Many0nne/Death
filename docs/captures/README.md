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

## Quand les reprendre

`tools/check.sh` (étape `captures`, aussi en CI) échoue dès qu'une source de la carte a changé depuis la dernière prise
(`sources.sha256` : HouseLayout, HouseGeometry, HouseStyle, NightLighting, HouseBuilder, NightAmbience). La PR qui
change la carte reprend donc les captures avant de merger.

## Procédure (Studio via le MCP, sous le verrou)

1. `.\scripts\dth-worktree.ps1 <branche> -AcquireStudio`, puis lancer le Play (`start_stop_play`).
2. `lune run tools/captures -- list` : nom, lumière, coupe et caméra de chaque vue.
3. Pour chaque vue, en commençant par `nuit-rue` (éclairage du jeu intact) :
   - `lune run tools/captures -- scene <vue>` imprime le code de mise en scène ; l'exécuter avec `execute_luau`,
     contexte `Server` (il annule d'abord la mise en scène précédente) ;
   - `screen_capture` avec `camera_position` et `look_at_position` de la liste ; le MCP enregistre un jpg et donne
     son chemin ;
   - `lune run tools/captures -- save <vue> <chemin du jpg>`.
4. Arrêter le Play, `-ReleaseStudio`.
5. `lune run tools/captures -- stamp`, puis regarder les images avant de commiter (cadrage, éléments masqués).

Images en Git LFS (`.gitattributes`). Un nouveau point de vue s'ajoute dans `VIEWS` (`tools/captures.luau`) et dans
le tableau ci-dessus.
