# Assets : modèles 3D, production et export

Les modèles du jeu (personnages, et bientôt viewmodels et objets) sont des `.rbxm` binaires versionnés dans
`assets/rbx/<Dossier>/<Nom>.rbxm` (Git LFS) et synchronisés par Rojo : `assets/rbx/Characters` →
`ReplicatedStorage.Characters`. Un fichier = une instance racine, nommée d'après le fichier. Rien ne se garde dans
Studio : une modification non réexportée est perdue. La CI fait un checkout LFS (`rojo build` lit les `.rbxm`).

## Modèles en place

| Modèle | Fichier | Utilisé par |
|---|---|---|
| La Mort (#73, #76) | `assets/rbx/Characters/Death.rbxm` | `Server.DeathBody` : le joueur Mort le revêt, il retrouve son avatar ensuite ; `Client.CloakAnimator` anime la cape |

**La Mort** (#76, retour de l'utilisateur sur #73, jugé trop humanoïde ; outillage #79) : un voile en lambeaux,
capuche vide, aucun pied ; seuls le bras squelette et la main qui tient la faux dépassent. Écrite par script Blender
(`tools/blender/death_model.py`, rejouable : la source est le script, pas un `.blend`), produite par
`tools/blender/pipeline.py` (section « Produire un modèle détaillé sans crédits »), exportée en GLB, envoyée par Open
Cloud (dossier d'envoi approuvé `worktrees/.export` du checkout principal), puis remontée dans Studio par
`tools/rbxm/remount.luau` sur le rig R15 de #73 :
- **rig R15 gardé, invisible** (`Transparency = 1` : un `Highlight` ne dessine pas ces pièces, vérifié) : il porte le
  Humanoid et les déplacements. `AutomaticScalingEnabled = false` et `HipHeight = 2,65` : sinon le Humanoid recalcule
  une hauteur de hanches nulle et reste en chute libre (constaté en jeu) ;
- **voile** (modèle `Veil`) : `Cloak` (robe drapée par simulation de tissu, à os : 16 chaînes de 4 os `Cxx_y` sous
  `HumanoidRootPart.Root`, `SurfaceAppearance` cuite), `Hood` (capuche et pèlerine), `Void` (`Neon` noir qui tapisse
  le fond de la poche de la capuche), `HemSmokeArea` (pièce invisible, fumée `HemSmoke`) ; fumée `HoodShadow` dans
  `Void` ;
- **bras** (modèle `Arm`) : `Sleeve` (manche) et `BoneArm` (avant-bras et main squelette, phalanges courbées contre la
  poignée) ;
- **faux** (modèle `Scythe`), une MeshPart par zone de skin, chacune avec ses UV (manche, poignée et gravure : u le
  long de la pièce) : `Blade` (acier, rainure), `Edge` (fil poli), `Engraving` (panneau dans la rainure, des deux
  côtés, prévu pour une texture gravée), `ScytheHead` (douille et éperon), `Gem` (sertie des deux côtés), `Rings`
  (bagues), `Shaft` (manche), `Grip` (cuir en hélice), `Pommel` (pointe) ;
- toutes les pièces ajoutées sont soudées à `HumanoidRootPart` (`WeldConstraint`), sans masse, collision, contact ni
  requête de rayon : elles ne suivent pas les membres animés, la Mort glisse.
- Couleurs et matériaux (l'import GLB les perd) : table `parts` de `tools/models/death.manifest.json`, reposés par le
  remontage : tissus `Fabric` presque noirs, os ivoire, lame `Metal`, fil `Foil`, bagues laiton, manche `Wood`,
  poignée `Leather`, gemme `Neon` sarcelle.

**Preuve `SurfaceAppearance` (#79, cape seule)** : modèle envoyé en asset Model 104750013155394 (#76 :
112747301669865), textures cuites de la cape en assets Image 90768318909720 (couleur), 75803274684492 (normales),
134709665699025 (rugosité), posées par le remontage sur la MeshPart skinnée `Cloak`. Mesuré dans Studio :
- mémoire des textures (`Stats:GetMemoryUsageMbForTag(GraphicsTexture)`, clone affiché à l'écran) : **+2,67 Mo** pour
  les trois cartes 1024 (99,78 → 102,45 Mo) ;
- la cape s'anime toujours (`Client.CloakAnimator`, os `C08_3` relevé à 3,39° puis 4,00° en jeu) ;
- le `Highlight` de `Client.DeathView` (noir, opaque, `Occluded`) recouvre entièrement la texture : la Mort exposée
  reste une silhouette noire pleine, sans artefact. La texture ne compte donc que pour la Mort elle-même et pour la
  lumière d'une lampe avant exposition.

**Cape vivante** : `Shared.CloakMotion` (règles pures, testées) et `Client.CloakAnimator`, qui écrit `Bone.Transform` en
`PreSimulation`, car l'Animator du Humanoid remet ces valeurs à zéro à chaque étape d'animation. Ondulation au repos,
traîne à l'opposé du mouvement : mesuré en jeu, à 14,7 studs/s, l'os du bas arrière s'incline de 24° de plus
qu'immobile (40° → 65°), celui de devant de 7°.

Pour un mortel, la Mort exposée hors faisceau est une **ombre pleine** sans faux (`Client.DeathView`, #80 : un
`Highlight` sombre par morceau visible du corps, fumées créées par le client) : la forme du voile (capuche, lambeaux)
passe avant le détail des textures, qui ne se voit que dans le faisceau d'une lampe. Le rendu ne dépend que du nom
`Scythe` (la faux, cachée hors faisceau) : un nouveau modèle garde ce nom. Rendu vu d'un mortel (salon éclairé) :
ombre de près ![](mort/mortel-ombre.jpg), à 30 studs ![](mort/mortel-ombre-30-studs.jpg), dans le faisceau
![](mort/mortel-faisceau.jpg) ; vue du joueur Mort, dans l'ombre ![](mort/vue-mort.jpg).

**Refaire le modèle** (aucune retouche à la main) :
1. modifier `tools/blender/death_model.py` (ou le manifeste), puis, depuis la racine du worktree :
   `blender -b --factory-startup --python tools/blender/pipeline.py -- [--bake] --glb <worktrees/.export>/DeathVeil.glb`
   (contrôles, mesures `tools/models/death.measured.json`, textures si `--bake`) ;
2. rendre les 7 vues avant et après (`tools/blender/render_views.py`) et les comparer ;
3. sous le verrou Studio : envoyer le GLB (Open Cloud, type Model) et, si elles ont changé, les textures (type Image) ;
   reporter les identifiants d'images dans la table `surface` de la pièce (manifeste) ;
4. insérer le modèle envoyé dans `workspace` (nom `DeathVeil`), puis
   `lune run tools/rbxm/build-remount.luau -- death DeathVeil <%TEMP%>/remount.luau` et exécuter ce fichier dans
   Studio (MCP `execute_luau`, mode Edit) : il remplace les pièces de même nom, déplace les os de la cape, repose
   couleurs, matériaux, `SurfaceAppearance`, soudures, fumées et réglages du Humanoid, contrôle (un seul exemplaire
   par pièce, 65 os, cohérence des centres) et détruit l'import. Relancé sans import (`""`), il ne fait que
   réappliquer la table ;
5. exporter (section « Exporter vers le dépôt »).

## Produire un modèle détaillé sans crédits (#79)

Les outils de génération (`generate_3d`, `generate_mesh`) ne servent plus pour les modèles du jeu : un modèle s'écrit
par script Blender (graine fixe, rejouable), avec la bibliothèque `tools/blender/lib/` :

| Module | Rôle |
|---|---|
| `mesh` | grilles paramétriques (UV et indices `grid_i`/`grid_j` gardés sur les sommets), répartition dense là où il faut (`warp_samples`), tubes, sphères, épaisseur, poids d'os recalculés d'après la grille |
| `cloth` | drapé par simulation de tissu native : forme trop ample épinglée en haut, tombe pendant un nombre d'images fixe sur un corps de substitution, puis figée ; même nombre de sommets, empreinte (`fingerprint`) pour vérifier le déterminisme |
| `detail` | version détaillée, jamais exportée : subdivision, sculpt par script (sillons le long de traits), bosses Geometry Nodes appliquées, déplacement procédural fin |
| `textures` | matières CC0 sur un Principled (motif CC0 entre deux teintes choisies, saleté, rugosité, normales) ; textures cuites posées pour les rendus |
| `bake` | cuisson Cycles sans interface de la version détaillée vers la version jouable : normales (espace tangent OpenGL, comme Roblox), occlusion, couleur, rugosité ; couleur finale = couleur x occlusion |
| `manifest` | comparaison au manifeste (pièces, os, poids, UV, budgets) et écriture des mesures |

**Chaîne** : `tools/blender/pipeline.py` (construction, contrôles du manifeste et du modèle, cuisson avec `--bake`,
mesures, export GLB des seules pièces du manifeste). Code 1 si un contrôle échoue. Contrôles propres à la Mort :
contact des doigts avec la poignée (écart maximal ≤ 0,005 stud), aucun sommet de `Void` visible de derrière, des côtés
ni du dessus.

**Manifeste** `tools/models/death.manifest.json` : noms des pièces et groupes, os, budgets, réglages de cuisson,
table de remontage (couleurs, matériaux, `SurfaceAppearance`, pièces et fumées ajoutées dans Studio, Humanoid).
`tests/specs/DeathManifest.spec.luau` (Lune, en CI) vérifie que chaque nom cherché par `Client.CloakAnimator`,
`Server.DeathBody` et `Client.DeathView` y figure, que les os sont ceux de `Shared.CloakMotion`, et que les mesures
versionnées (`death.measured.json`) tiennent dans les budgets.

**Budgets** (triangles, mesurés après épaisseur) : au plus **12 000 par pièce** (limite Roblox d'environ 20 000), total
de la Mort ≤ 34 000. Textures : 1024 pour les grandes pièces, 512 pour les petites ; une pièce texturée coûte trois
images (couleur, normales, rugosité).

**Rendus de contrôle** : `blender -b --factory-startup --python tools/blender/render_views.py -- <dossier>` (7 vues :
face, 3/4, profil, dos, capuche, main, lame ; Workbench, tissus éclaircis pour lire la forme), `--textured` (EEVEE,
textures cuites), `--script <ancien death_model.py>` pour rendre une version antérieure (`git show main:...`).

**Matières CC0** (`assets/textures/cc0/`, Git LFS, 1k JPG ; `python -I tools/blender/fetch_cc0.py` les télécharge et
écrit `sources.json`) : toutes de [Poly Haven](https://polyhaven.com/license), licence **CC0 1.0** (domaine public,
sans attribution obligatoire) :

| Matière | Usage | Auteurs |
|---|---|---|
| [Rough Linen](https://polyhaven.com/a/rough_linen) | tissu (cape, capuche, manche) | Rico Cilliers, colormass |
| [Brown Leather](https://polyhaven.com/a/brown_leather) | cuir (poignée) | Rob Tuytel |
| [Rusty Metal 02](https://polyhaven.com/a/rusty_metal_02) | métal (lame, tête, bagues) | Rob Tuytel |
| [Dark Wood](https://polyhaven.com/a/dark_wood) | bois (manche) | Dario Barresi, Dimitrios Savva, Rico Cilliers |

Pas de matière d'os CC0 convenable chez Poly Haven : l'os se fera en procédural (bruit) dans la version détaillée.
Textures cuites : `assets/textures/<modèle>/<Pièce>_color|normal|roughness.png` (et `_ao`, intermédiaire).

## Base générée dans Studio (rig R15, #73)

1. Générer la base dans Studio, sous le verrou Studio (`-AcquireStudio`) : `generate_avatar` pour un rig R15 (seul
   usage gardé : le rig invisible qui porte le Humanoid). Ces outils publient des assets permanents sur le compte du
   créateur de la place ; les pièces visibles se produisent par script (section précédente).
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
