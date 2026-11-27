# Death

## Overview
Jeu Roblox (projet Rojo) d'horreur asymétrique, 1 Mort contre 4 mortels : la Mort ne tue pas directement, elle arme des
accidents cachés dans le décor ; les mortels doivent fuir avant la fin de la nuit. Titre de travail : Faucheuse.
Dépôt : `Many0nne/Death`. Étude de marché commune aux jeux Roblox : vault Obsidian
`C:\Users\tbarillon\Documents\Obsidian Vault\Jeu Roblox\` (le collecteur vit dans le dépôt FlingADummy, `market/`).

## Rôles
Claude est **responsable du projet et du code** : il tranche le game feel, le périmètre et la technique, signale chaque
choix en une ligne, crée les issues et merge les PR. Les **décisions de conception** listées comme ouvertes dans
`docs/` (règles, lobby, monétisation) restent à l'utilisateur : les poser, ne pas les trancher. L'utilisateur est
**testeur**, seulement en **sprint review** (section « Sprints »). Une action destructive ou hors du dépôt se confirme
toujours avec lui.

## Sprints
- On produit en continu : chaque tâche est vérifiée par Claude (tests, `check.sh`, Studio via MCP, mesures), puis mergée
  dès que la CI est verte, **sans attendre l'avis de l'utilisateur**. Un doute de rendu ou de game feel se tranche (choix
  signalé en une ligne) et part dans la review.
- Questions : une vraie décision de design peut être posée dans le thread de la tâche, sans bloquer le reste. Pas de
  question « est-ce que ça te va en jeu ? » : c'est pour la review.
- Sprint review : quand plusieurs issues sont mergées depuis la dernière review (repère : tag `review/<n>`) et qu'un avis
  de jeu est utile, Claude demande à l'utilisateur de jouer, sur le checkout principal à jour (`main`, port 34930, verrou
  `main -AcquireStudio`), avec **la liste des changements** : par issue, ce qui change pour le joueur, comment le voir,
  quoi observer. Liste construite à partir de `git log review/<n>..main --merges` et des sections « Pour la sprint
  review » des comptes rendus.
- Jeu asymétrique : un test utile demande souvent plusieurs joueurs. Indiquer pour chaque point s'il se teste seul,
  en Studio multi-clients (Test > Clients and Servers) ou à plusieurs comptes.
- Retours de la review : chacun devient une issue (ou rouvre la tâche), puis tag `review/<n+1>` sur le `main` testé.
- Tout compte rendu de tâche (délégué ou non) se termine par une section « Pour la sprint review » (3 à 5 lignes).

## Où trouver quoi
| Sujet | Document |
|---|---|
| Règles du jeu, pièges, lumière, âmes, prototype v0 | `docs/design.md` |
| Hall, salle d'attente, groupes, HUD, bilan, monétisation, architecture des places | `docs/parcours-joueur.md` |
| Maquettes de principe (disposition, pas le rendu) | `docs/maquettes.html` |
| Plan de la carte sans Studio (généré : `lune run tools/house-map`) | `docs/plan/plan.svg`, `docs/plan/maison-3d.html` |
| Captures de la carte dans Studio, versionnées (procédure de reprise) | `docs/captures/README.md` |
| Modèles 3D (`assets/rbx`), production par l'IA de Studio, export `.rbxm` | `docs/assets.md` |

## Rojo et Studio
- Mapping : `src/shared` → `ReplicatedStorage/Shared`, `src/server` → `ServerScriptService/Server`,
  `src/client` → `StarterPlayer/StarterPlayerScripts/Client`. Garder `default.project.json` synchronisé avec `src/`.
- Place Studio : **placeId 102016917441408** (universe 10778894071). Une seule place pour l'instant ; le découpage
  `Hall` / `Manche` de `docs/parcours-joueur.md` viendra avec un second projet Rojo.
- `rojo serve` du checkout principal écoute sur le port **34930** (`servePort`), les worktrees sur `34930+N`, hors des
  plages de `CSGO_surf_combat` (34872+) et `FlingADummy` (34900+).
- Connexion automatique : plugin « CSGO autoconnect » multi-projets (`Many0nne/CSGO_surf_combat`,
  `tools/rojo-plugin/README.md`), déjà installé sur le poste. `-AcquireStudio` connecte la place Death au port du
  worktree sans toucher les fenêtres des autres jeux (section « Studio et Blender partagés »).
- Connexion à la main (secours) : Studio en mode Edit, plugin Rojo, Disconnect, port, Connect. Vérifier le port connecté
  avant un test.
- Rien ne se modifie dans Studio pour être gardé : le code vit dans `src/`, le décor est généré par le code ou importé
  comme asset versionné (`assets/`).

## Roblox Studio MCP
- **Ne jamais modifier de scripts via le MCP** : le code se modifie uniquement dans `src/` (Rojo écrase Studio).
- **Appels courts** : jamais d'attente dans `execute_luau` (boucle, `task.wait` long), qui peut figer Studio. Lancer
  l'action, puis lire le résultat par un appel suivant (`get_console_output`).
- Piloter le jeu par attributs de debug (sur le joueur, en contexte `Server`) plutôt qu'en simulant l'input.
- **Faux joueur (Play Solo, Studio seulement)** : poser `DebugAddBot = "Mortal"` (ou `"Death"`) sur son Player ajoute un
  mannequin `workspace["Bot Mortel 1"]` compté par `DebugStartMatch` (1 Mort + 1 à 4 mortels, bots compris). Ses
  attributs `Debug*` se posent sur le mannequin : `DebugSetState = "Agony"` vise ce faux mortel. `DebugClearBots = true`
  retire tous les bots (comme un départ de joueur). Pièges, lumière, lampe torche, Mort et agonie parcourent
  `MatchService:roster()` (joueurs + bots, API de `Players`) : un bot mortel est touché par un piège, porte une lampe
  (`DebugFlashlight = "on"` sur le mannequin), un bot Mort est exposé par la lumière (attribut `DeathExposed` sur le
  mannequin). Limites : les vues client (`Client.DeathView`, `Client.AgonyClient`) parcourent encore `Players`, donc un
  bot Mort reste visible dans l'ombre ; `Server.EscapeService` aussi, donc un bot mortel ne peut pas s'échapper. Code : `Server.DebugBots`, `Server.Roster`.

## Qualité
- Outils Rokit (`rokit.toml`) : `rojo`, `stylua`, `selene`, `luau-lsp`, `lune`. Installer avec `rokit install`.
- Après toute modification `.luau` : `bash tools/check.sh` (selene, stylua, luau-lsp, tests Lune). Lire la sortie
  complète, sans filtre. `--fix` applique le formatage.
- Tests unitaires Lune dans `tests/specs/*.spec.luau` (chaque spec retourne `function(T, Loader, Lib)`, cf.
  `tests/lib/`). La logique pure (règles des pièges, sablier, âmes, file) va dans `src/shared` pour être testable.
- **Mesurer avant de promettre** : un effet de gameplay annoncé (durée, portée, bruit) se mesure, et la valeur figure
  dans le compte rendu. Sans mesure, écrire « non mesuré ».

## Workflow d'une tâche
1. Une tâche = une issue = une branche `feature|fix|tooling/<n>-<slug>` = un worktree `worktrees/dth-<slug>/` (ignoré par
   git), créé ou repris par `.\scripts\dth-worktree.ps1 <branche>` (section « Worktrees »).
2. Implémenter, puis `bash tools/check.sh` dans le worktree ; vérifier en jeu via le MCP Studio si le changement le demande,
   sous le verrou Studio. Une PR qui change la carte reprend aussi ses captures (`docs/captures/README.md`) : sinon
   l'étape `captures` de `check.sh` échoue.
3. Pas de test par l'utilisateur à ce stade : noter dans le compte rendu la section « Pour la sprint review ».
4. Fonctionnement vérifié : commit, push, PR vers `main` avec `Closes #<n>`.
5. **Merger soi-même**, sans attendre d'ordre (règle propre à ce dépôt, elle remplace le « pas de merge sans ordre
   explicite » des consignes globales) : CI verte, puis `gh pr merge <n> --merge --delete-branch`. CI rouge : corriger,
   ne pas merger. Puis fermer le thread (settle) : le nettoyage automatique supprime alors le worktree et la branche
   locale.
- Git : identité locale `Many0nne` et push par `gh auth git-credential` (config git locale) ; ne pas les retirer. Un
  worktree hérite de cette config.
- **Rubrique « Trouvé »** : chaque point qui mérite une suite devient une issue, créée sans demander, avec ses labels
  (chercher d'abord une issue ouverte qui le couvre).
- Labels : `gameplay`, `game-feel`, `ui`, `lobby`, `economie`, `direction-artistique`, `tooling`, `backlog`.

## Worktrees (travail en parallèle)
Une branche = un worktree `worktrees/dth-<slug>/` (slug = branche avec `/` → `-`) = un `rojo serve` sur son propre port.
Script idempotent, à relancer au début de chaque tâche (PowerShell, depuis la racine du checkout principal ou d'un worktree) :

```powershell
.\scripts\dth-worktree.ps1 feature/x             # crée/reprend, lance rojo serve, vérifie [OK (200)]
.\scripts\dth-worktree.ps1 fix/y -Base feature/x # nouvelle branche depuis une autre base (défaut : main)
.\scripts\dth-worktree.ps1 feature/x -NoUp       # sans démarrer Rojo
.\scripts\dth-worktree.ps1 feature/x -Slot 2     # impose le slot (port 34932)
.\scripts\dth-worktree.ps1 feature/x -Stop       # arrête Rojo (et libère Studio)
.\scripts\dth-worktree.ps1 feature/x -Remove     # arrête Rojo, supprime le worktree (branche gardée)
```

- Ports par slot N : checkout principal = slot 0 = `34930` (`rojo serve` lancé à la main), worktrees `34930+N`. Port, pid
  et journal : `worktrees/.run/<slug>.port|.pid|.log`.
- Le script écrit `.claude/settings.local.json` dans le worktree (exclu de git) : la session peut écrire dans
  `worktrees/.briefs` et `%TEMP%`.
- `/delegate` : `-NoUp -NoRegister` pour créer le worktree depuis le thread qui délègue, puis `-RegisterThread <id>` avec
  l'id du thread créé. Règles propres à ce dépôt : skill de projet `delegation-dth`.
- Nettoyage auto (registre `worktrees/.owners.json`) : `scripts/dth-worktree-cleanup.ps1` arrête Rojo quand les threads T3
  du worktree ne sont plus actifs, et supprime le worktree quand la PR de la branche est mergée (ou fermée) et que tout
  est poussé ; la branche locale est aussi supprimée si la PR est mergée. Tâche planifiée « Death worktree cleanup »
  (toutes les 10 min) : `scripts/install-cleanup-task.ps1`. Elle avance aussi le checkout principal sur `origin/main`
  (fast-forward, seulement s'il est sur `main` sans modification). Journal : `worktrees/.cleanup.log`.
- Tests de limites des scripts (Pester 3.4.0, bac à sable `%TEMP%`, Windows seulement) :
  `Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts`. À lancer après toute modification de
  `scripts/dth-worktree*.ps1`. Ils tournent aussi en CI (job `pester`) quand `scripts/**` ou `tests/scripts/**` changent.
- Les scripts sont une copie de ceux de FlingADummy (préfixe `dth`) : un correctif de fond se reporte dans les deux
  dépôts.

## Studio et Blender partagés
Une seule place Studio (placeId 102016917441408) sert tous les worktrees : les tâches se la relaient par un verrou,
`worktrees/.run/studio.lock`. Tout faire d'abord sans Studio (code, `check.sh`, tests Lune, `rojo build`, Blender sans
interface), puis ne garder Studio que le temps de la vérification :

```powershell
.\scripts\dth-worktree.ps1 <branche> -AcquireStudio                # réserve et connecte la place, ou code 2 avec le détenteur
.\scripts\dth-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20 # attend jusqu'à 20 min
.\scripts\dth-worktree.ps1 <branche> -ReleaseStudio                # libère, place renvoyée sur 34930
.\scripts\dth-worktree.ps1 -StudioStatus                           # détenteur, port connecté, dernier état du plugin
```

- Réserver avant toute action Studio (MCP, connexion du plugin, demande de test), libérer juste après. Code 2 : continuer
  sans Studio et réessayer, ou attendre avec `-WaitStudio`. Ne jamais déconnecter Studio d'un autre worktree sans le
  verrou.
- Depuis le checkout principal : réserver avec la branche `main`. Studio connecté à 34930 à la main : sans doute
  l'utilisateur qui teste ; demander avant Disconnect.
- La réservation inscrit le projet au registre commun (`%LOCALAPPDATA%\RojoAutoconnect\projects\dth.json`) et utilise le
  serveur de commande partagé (`http://127.0.0.1:34870/health`, jamais arrêté : il sert aussi CSGO et FlingADummy).
- Garde-fou : `ALERTE` quand la place est connectée à un port qui n'est d'aucun Rojo de ce dépôt (code d'un autre jeu
  synchronisé dans la place) : ne pas sauvegarder ni publier la place.
- Plusieurs places Studio ouvertes (CSGO, FlingADummy, Death) : toujours passer le `studio_id` de la fenêtre Death aux
  outils MCP (`list_roblox_studios`, nom « Death »).
- Blender : la session avec interface (MCP `blender`) sert une tâche à la fois ; les traitements par script passent par
  `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup` (parallélisable). Sources
  `.blend`, meshes, textures et sons dans `assets/`, en Git LFS (`.gitattributes`).
- Après chaque synchronisation Rojo, relancer le playtest : la copie en Play ne prend pas les modifications.
