# Assets : modèles 3D, production et export

Les modèles du jeu (personnages, et bientôt viewmodels et objets) sont des `.rbxm` binaires versionnés dans
`assets/rbx/<Dossier>/<Nom>.rbxm` (Git LFS) et synchronisés par Rojo : `assets/rbx/Characters` →
`ReplicatedStorage.Characters`. Un fichier = une instance racine, nommée d'après le fichier. Rien ne se garde dans
Studio : une modification non réexportée est perdue. La CI fait un checkout LFS (`rojo build` lit les `.rbxm`).

## Modèles en place

| Modèle | Fichier | Utilisé par |
|---|---|---|
| La Mort (#73, #76, #81) | `assets/rbx/Characters/Death.rbxm` | `Server.DeathBody` : le joueur Mort le revêt, il retrouve son avatar ensuite ; `Client.CloakAnimator` anime le voile |

**La Mort** (#81, après #76 jugé « trop simpliste, un assemblage de formes basiques » ; outillage #79) : un spectre
décharné de l'archétype « détraqueur » (l'archétype, pas un personnage existant), très grand (7,2 studs, sous les
portes de 8), sans pieds, qui flotte à 0,2 stud du sol. Suaire tendu sur un crâne sculpté (orbites, arcade, pommettes
et cavité nasale se devinent), tête penchée, dos voûté, épaules osseuses ; robe lourde trouée sur des côtes
saillantes ; manches très larges d'où sortent des bras maigres et des mains griffues (la droite serre la faux, la
gauche se tend) ; le bas se défait en 44 lanières de longueurs très différentes qui traînent vers l'arrière. Avant /
après : `docs/renders/death/v76/` et `docs/renders/death/` (`textured/` : textures cuites ; `silhouette/` : ombre
pleine, ce que voit un mortel hors faisceau).

Écrite par script Blender (`tools/blender/death_model.py` et ses modules `tools/blender/death/` : `posture`, `veil`,
`anatomy`, `scythe`, `rig`, `checks` ; rejouable, la source est le script), produite par `tools/blender/pipeline.py`
(section « Produire un modèle détaillé sans crédits »), exportée en GLB, envoyée par Open Cloud (dossier d'envoi
approuvé `worktrees/.export` du checkout principal), puis remontée dans Studio par `tools/rbxm/remount.luau` sur le
rig R15 de #73 :
- **rig R15 gardé, invisible** (`Transparency = 1` : un `Highlight` ne dessine pas ces pièces, vérifié) : il porte le
  Humanoid et les déplacements. `AutomaticScalingEnabled = false` et `HipHeight = 2,65` : sinon le Humanoid recalcule
  une hauteur de hanches nulle et reste en chute libre (constaté en jeu). Ses articulations des bras (épaule, coude,
  poignet) sont recalées par le remontage sur les os du spectre (`bones.body.joints`) ;
- **voile** (modèle `Veil`) : `Cloak` (robe drapée par simulation de tissu, à os : 16 chaînes de 4 os `Cxx_y` sous
  `HumanoidRootPart.Root`), `Shroud` (suaire, forme dessinée), `HemSmokeArea` (pièce invisible, fumée `HemSmoke`) ;
- **lanières** (modèle `Tatters`) : `Tatters`, skinnée sur les mêmes os que la robe ; vue d'un mortel dans l'ombre,
  `Client.DeathView` ne la remplit pas et l'efface à demi (`Shared.DeathLook.TATTER_FADE`) : le bas de l'ombre se
  défait dans la fumée au lieu de finir sur un bord net (#80) ;
- **bras** (modèle `Arm`) : `Hands` (avant-bras et mains d'un seul tenant, griffes comprises) et `Sleeves` (manches
  drapées), **skinnées sur les os du corps** (`BodyRig`, racine `Spine`, 37 os : bras, main, trois phalanges par
  doigt), que le remontage range sous les pièces du rig R15 (`bones.body.attach` : `Spine` sous `UpperTorso`,
  `R_UpperArm` sous `RightUpperArm`, etc.) : animer le rig anime les bras (#55, #74). Le corps de la Mort ne reprend
  pas le script `Animate` par défaut (`Server.DeathBody`) : la marche de Roblox balancerait les bras ;
- **corps** (modèle `Body`) : `Torso` (cage thoracique sous la peau, visible par les trous de la robe) ;
- **faux** (modèle `Scythe`, soudée à `RightHand` : elle suit la main), une MeshPart par zone de skin : `Blade` (fer
  battu, gouttière, épaisseur irrégulière), `Edge` (fil ébréché en six endroits), `Engraving`, `ScytheHead` (douille,
  soie rivetée, éperon), `Gem`, `Rings`, `Shaft` (branche à peine redressée, nœuds), `Grip` (lanières de cuir, un bout
  libre), `Pommel` ;
- toutes les pièces sont sans masse, collision, contact ni requête de rayon, soudées à `HumanoidRootPart` (sauf la
  faux) ; les pièces de #76 (`Hood`, `Void`, `Sleeve`, `BoneArm`, fumée `HoodShadow`) sont retirées par le
  remontage (`studio.remove`).
- Couleurs et matériaux (l'import GLB les perd) : table `parts` de `tools/models/death.manifest.json`, reposés par le
  remontage ; les textures cuites (`SurfaceAppearance`) portent le détail : lin CC0 pour les tissus, chair procédurale
  (cendre grise marbrée, veines, rides, griffes de corne jaunie) pour `Hands` et `Torso`, bois CC0 pour `Shaft`.
- Contact de la main : les phalanges pressent le cuir de 0,006 stud au pire (mesuré sur le maillage, 120 points).

**Preuve `SurfaceAppearance` (#79, cape seule)** : modèle envoyé en asset Model 104750013155394 (#76 :
112747301669865), textures cuites de la cape en assets Image 90768318909720 (couleur), 75803274684492 (normales),
134709665699025 (rugosité), posées par le remontage sur la MeshPart skinnée `Cloak`. Mesuré dans Studio :
- mémoire des textures (`Stats:GetMemoryUsageMbForTag(GraphicsTexture)`, clone affiché à l'écran) : **+2,67 Mo** pour
  les trois cartes 1024 (99,78 → 102,45 Mo) ;
- la cape s'anime toujours (`Client.CloakAnimator`, os `C08_3` relevé à 3,39° puis 4,00° en jeu) ;
- le `Highlight` de `Client.DeathView` (noir, opaque, `Occluded`) recouvre entièrement la texture : la Mort exposée
  reste une silhouette noire pleine, sans artefact. La texture ne compte donc que pour la Mort elle-même et pour la
  lumière d'une lampe avant exposition.

**Spectre (#81)**, mesuré dans Studio : modèle asset 136242008686173, 20 images (identifiants dans la table `surface`
du manifeste) ; mémoire des textures **+10,3 Mo** pour sept pièces texturées (102,45 → 112,79 Mo : trois pièces en
1024, quatre en 512) ; remontage : 15 pièces remplacées, 4 retirées, 65 os de robe, 37 os du corps rangés sur le rig,
écart d'origine 0.

**Cape vivante** : `Shared.CloakMotion` (règles pures, testées) et `Client.CloakAnimator`, qui écrit `Bone.Transform` en
`PreSimulation`, car l'Animator du Humanoid remet ces valeurs à zéro à chaque étape d'animation. Ondulation au repos,
traîne à l'opposé du mouvement ; les lanières suivent les mêmes os. Mesuré en jeu sur le spectre (#81, os du bas
arrière `C08_3`, angle à la verticale) : 7,5° immobile en moyenne (ondulation de 0 à 14°), 27° entre 12,5 et 15
studs/s (+20°), 38° entre 17,5 et 20 studs/s (+30°, pointes à 55°). Sur le voile de #76, évasé, la mesure était de
+24° à 14,7 studs/s (40° → 65°).

Pour un mortel, la Mort exposée hors faisceau est une **ombre pleine** sans faux (`Client.DeathView`, #80 : un
`Highlight` sombre par morceau visible du corps, fumées créées par le client), dont les lanières s'effacent à demi
dans la fumée (#81) : la forme du voile passe avant le détail des textures, qui ne se voit que dans le faisceau d'une
lampe. Le rendu ne dépend que des noms `Scythe` (la faux, cachée hors faisceau) et `Tatters`. Rendu vu d'un mortel
(salon éclairé) : ombre de près ![](mort/mortel-ombre.jpg), à 20 studs ![](mort/mortel-ombre-20-studs.jpg), dans le
faisceau ![](mort/mortel-faisceau.jpg) et de près ![](mort/mortel-faisceau-pres.jpg) ; la Mort à la lumière (vue
d'elle-même) ![](mort/mort-lumiere.jpg), en déplacement ![](mort/mort-deplacement.jpg) ; vue du joueur Mort
![](mort/vue-mort.jpg). Captures de #76 et #80 : `docs/mort/v76/`.

**Refaire le modèle** (aucune retouche à la main) :
1. modifier `tools/blender/death_model.py` (ou le manifeste), puis, depuis la racine du worktree :
   `blender -b --factory-startup --python tools/blender/pipeline.py -- [--bake] --glb <worktrees/.export>/DeathVeil.glb`
   (contrôles, mesures `tools/models/death.measured.json`, textures si `--bake`) ;
2. rendre les vues avant et après (`tools/blender/render_views.py`, aussi `--textured` et `--silhouette`) et les
   comparer ;
3. sous le verrou Studio : envoyer le GLB (Open Cloud, type Model) et, si elles ont changé, les textures (type Image,
   copiées dans le dossier d'envoi approuvé) ; reporter les identifiants d'images dans la table `surface` de la pièce
   (manifeste) ;
4. insérer le modèle envoyé dans `workspace` (nom `DeathVeil`), puis
   `lune run tools/rbxm/build-remount.luau -- death DeathVeil <%TEMP%>/remount.luau` et exécuter ce fichier dans
   Studio (MCP `execute_luau`, mode Edit ; un fichier trop long pour un appel se sert sur `localhost:34990` et se lit
   par `HttpService:GetAsync` puis `loadstring`) : il retire les pièces d'un ancien modèle, recale les articulations
   des bras du rig, remplace les pièces de même nom, range les os (robe sous la racine, corps sous le rig), repose
   couleurs, matériaux, `SurfaceAppearance`, soudures, fumées et réglages du Humanoid, contrôle (un seul exemplaire
   par pièce, 65 os de robe, chaque os du corps une fois et à sa place, cohérence des centres) et détruit l'import.
   Relancé sans import (`""`), il ne fait que réappliquer la table ;
5. exporter (section « Exporter vers le dépôt »).

## Produire un modèle détaillé sans crédits (#79)

Les outils de génération (`generate_3d`, `generate_mesh`) ne servent plus pour les modèles du jeu : un modèle s'écrit
par script Blender (graine fixe, rejouable), avec la bibliothèque `tools/blender/lib/` :

| Module | Rôle |
|---|---|
| `mesh` | grilles paramétriques (UV et indices `grid_i`/`grid_j` gardés sur les sommets), répartition dense là où il faut (`warp_samples`), tubes, sphères, épaisseur, poids d'os recalculés d'après la grille |
| `cloth` | drapé par simulation de tissu native : forme trop ample épinglée en haut, tombe pendant un nombre d'images fixe sur un corps de substitution, puis figée ; même nombre de sommets, empreinte (`fingerprint`) pour vérifier le déterminisme ; raideur à la flexion réglable |
| `organic` | formes d'un seul tenant tirées d'un squelette de nœuds (modificateur Skin puis subdivision : mains, bras, corps de substitution), poids d'os d'après les segments (4 os au plus par sommet), zones de matière par face (`zone`), réunion de pièces |
| `detail` | version détaillée, jamais exportée : subdivision (bords et arêtes marquées gardés vifs), sculpt par script (traits additionnés puis lissés), bosses Geometry Nodes appliquées, déplacement procédural fin, faces retournées par le détail ramenées vers la surface |
| `textures` | matières CC0 sur un Principled (motif CC0 entre deux teintes choisies, saleté, rugosité, normales), chair procédurale (`flesh_material`) ; textures cuites posées pour les rendus |
| `bake` | cuisson Cycles sans interface de la version détaillée vers la version jouable : normales (espace tangent OpenGL, comme Roblox), occlusion locale (0,3 stud, la pièce seule), couleur, rugosité ; couleur finale = couleur x occlusion ; part des pixels très inclinés mesurée |
| `manifest` | comparaison au manifeste (pièces, os de la robe et du corps, poids, UV, budgets) et écriture des mesures |

**Chaîne** : `tools/blender/pipeline.py` (construction, contrôles du manifeste et du modèle, cuisson avec `--bake`,
mesures, export GLB des seules pièces du manifeste). Code 1 si un contrôle échoue. Contrôles propres à la Mort
(`tools/blender/death/checks.py`) : contact des doigts avec la poignée (écart maximal ≤ 0,005 stud), skinning (aucun
sommet sans os, 4 os au plus), silhouette (le tissu ne touche pas le sol, hauteur sous 8 studs).

**Cuisson propre (#85)** : les taches de la carte de normales de la cape venaient pour l'essentiel des traits de sculpt
qui se croisaient dans un pli serré (2 006 pixels, 0,19 % : 553 une fois les traits additionnés puis lissés et les faces
retournées ramenées), le reste des plis de l'ourlet couchés au sol, où un rayon long touche l'autre couche du pli
(232 avec des rayons courts). Rayons courts par défaut (`cage` du manifeste : extrusion 0,05, portée 0,1) ; la cuisson
est refusée au-delà de 0,2 % de pixels très inclinés (`spikesMax` par pièce : 2 % pour `Hands`, dont les griffes
gardées vives demandent de grandes corrections voulues). `Tatters` n'a pas de carte de normales (`"normal": false`) :
ses rubans fins se croisent, les rayons touchaient le voisin.

**Manifeste** `tools/models/death.manifest.json` : noms des pièces et groupes, os, budgets, réglages de cuisson,
table de remontage (couleurs, matériaux, `SurfaceAppearance`, pièces et fumées ajoutées dans Studio, Humanoid).
`tests/specs/DeathManifest.spec.luau` (Lune, en CI) vérifie que chaque nom cherché par `Client.CloakAnimator`,
`Server.DeathBody` et `Client.DeathView` y figure, que les os sont ceux de `Shared.CloakMotion`, et que les mesures
versionnées (`death.measured.json`) tiennent dans les budgets.

**Budgets** (triangles, mesurés après épaisseur) : au plus **12 000 par pièce** (limite Roblox d'environ 20 000), total
de la Mort ≤ 70 000 (spectre de #81 : 59 000 environ, détail dans `death.measured.json`). Textures : 1024 pour les grandes pièces, 512 pour les petites ; une pièce texturée coûte trois
images (couleur, normales, rugosité).

**Rendus de contrôle** : `blender -b --factory-startup --python tools/blender/render_views.py -- <dossier>` (8 vues :
face, 3/4, profil, dos, tête, main sur la faux, main griffue, lame ; Workbench, tissus éclaircis pour lire la forme),
`--textured` (EEVEE, textures cuites), `--silhouette` (4 vues en noir uni sur blanc : la silhouette doit se lire
seule), `--script <ancien death_model.py>` pour rendre une version antérieure (`git show main:...`).

**Matières CC0** (`assets/textures/cc0/`, Git LFS, 1k JPG ; `python -I tools/blender/fetch_cc0.py` les télécharge et
écrit `sources.json`) : toutes de [Poly Haven](https://polyhaven.com/license), licence **CC0 1.0** (domaine public,
sans attribution obligatoire) :

| Matière | Usage | Auteurs |
|---|---|---|
| [Rough Linen](https://polyhaven.com/a/rough_linen) | tissu (cape, capuche, manche) | Rico Cilliers, colormass |
| [Brown Leather](https://polyhaven.com/a/brown_leather) | cuir (poignée) | Rob Tuytel |
| [Rusty Metal 02](https://polyhaven.com/a/rusty_metal_02) | métal (lame, tête, bagues) | Rob Tuytel |
| [Dark Wood](https://polyhaven.com/a/dark_wood) | bois (manche) | Dario Barresi, Dimitrios Savva, Rico Cilliers |

Pas de matière de peau ni d'os CC0 convenable chez Poly Haven : la chair est procédurale (`textures.flesh_material`).
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
