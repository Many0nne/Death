# Assets : modèles 3D, production et export

Les modèles du jeu (personnages, et bientôt viewmodels et objets) sont des `.rbxm` binaires versionnés dans
`assets/rbx/<Dossier>/<Nom>.rbxm` (Git LFS) et synchronisés par Rojo : `assets/rbx/Characters` →
`ReplicatedStorage.Characters`. Un fichier = une instance racine, nommée d'après le fichier. Rien ne se garde dans
Studio : une modification non réexportée est perdue. La CI fait un checkout LFS (`rojo build` lit les `.rbxm`).

## Modèles en place

| Modèle | Fichier | Utilisé par |
|---|---|---|
| La Mort (#73) | `assets/rbx/Characters/Death.rbxm` | `Server.DeathBody` : le joueur Mort le revêt, il retrouve son avatar ensuite |

**La Mort** : direction artistique abstraite (décision de l'utilisateur, 2026-11-27) : pas de visage, robe en
lambeaux, bras longs, mains noires griffues, faux. Base générée par l'IA de Roblox dans Studio (`generate_avatar`,
pipeline `npc`, R15 statique), puis :
- rig converti en R15 classique : `AnimationConstraint` → `Motor6D` (C0/C1 = CFrame des attachements),
  `BallSocketConstraint` et dossier `InitialPoses` retirés, `Animator` ajouté ; le script `Animate` du joueur est
  repris tel quel au moment du changement de corps ;
- tête en `Neon` noir : vide sans ombrage sous la capuche (le générateur avait mis un crâne) ;
- faux (`generate_mesh`, sans segmentation) : MeshPart `Scythe` soudée à `RightHand` (`WeldConstraint`), sans
  masse, collision, contact ni requête de rayon ;
- fumée noire au bas de la robe : `ParticleEmitter` `HemSmoke` dans `LeftLowerLeg` et `RightLowerLeg`
  (texture intégrée `smoke_main.dds`), coupée par `Client.DeathView` quand la Mort est invisible.

Pour un mortel, la Mort exposée reste une **silhouette noire pleine** (`Highlight` opaque, `Client.DeathView`) : ce qui
compte chez elle est la forme (capuche, lambeaux, griffes, faux), pas le détail des textures.

## Produire un modèle

1. Générer la base dans Studio, sous le verrou Studio (`-AcquireStudio`) : `generate_avatar` pour un personnage R15,
   `generate_mesh` pour un objet. Ces outils publient des assets permanents sur le compte du créateur de la place.
   Comparer plusieurs générations si la première trahit la direction artistique.
2. Retoucher dans Studio (mode Edit) sur une copie, puis la ranger sous `ReplicatedStorage.<Dossier>` avec un nom en
   `[A-Za-z0-9_-]`.
3. Exporter (section suivante), retirer les copies de travail de Studio, puis **reconnecter** Rojo (Release puis
   Acquire) : voir le piège ci-dessous.

## Exporter vers le dépôt

1. Depuis la racine du worktree : `lune run tools/rbxm/receive.luau` (serveur local, port 34990, le même que l'export
   de CSGO_surf_combat : un seul export à la fois, tous jeux confondus).
2. Exécuter `tools/rbxm/studio_export.luau` dans Studio (MCP `execute_luau`, contexte Edit) : il sérialise chaque
   modèle de `ReplicatedStorage.Characters` et l'envoie au serveur, qui écrit `assets/rbx/Characters/<Nom>.rbxm`,
   supprime les fichiers absents de la place, puis s'arrête.
   Le MCP refuse l'envoi tant que `localhost:34990` n'est pas dans la liste HTTP autorisée de l'Assistant
   (Studio > Assistant > Settings > MCP Permissions) ; c'est fait sur ce poste depuis #73.
3. Ajouter un dossier : l'ajouter à `FOLDERS` (`receive.luau`), à `sources` (`studio_export.luau`) et à
   `default.project.json`.

**Piège : un `MeshPart` créé par la synchronisation en direct de Rojo arrive sans mesh** (`MeshId` vide, boîte grise),
par exemple quand on ajoute un dossier au projet pendant que Studio est connecté. Rojo 7.7 ne crée correctement les
MeshParts qu'à la connexion (endpoint `/api/serialize`) : supprimer l'instance vide dans Studio, puis
`-ReleaseStudio` et `-AcquireStudio`. Constaté et corrigé ainsi pendant #73.

**Ne pas réécrire un `.rbxm` pendant que Studio est connecté à ce serveur Rojo** (règle reprise de CSGO_surf_combat :
Rojo peut remplacer un `Model` par une copie sans `PrimaryPart`) : déconnecter avant l'export ou reconnecter après.
