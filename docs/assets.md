# Assets : modèles 3D, production et export

Les modèles du jeu (personnages, et bientôt viewmodels et objets) sont des `.rbxm` binaires versionnés dans
`assets/rbx/<Dossier>/<Nom>.rbxm` (Git LFS) et synchronisés par Rojo : `assets/rbx/Characters` →
`ReplicatedStorage.Characters`. Un fichier = une instance racine, nommée d'après le fichier. Rien ne se garde dans
Studio : une modification non réexportée est perdue. La CI fait un checkout LFS (`rojo build` lit les `.rbxm`).

## Modèles en place

| Modèle | Fichier | Utilisé par |
|---|---|---|
| La Mort (#73, #76, #81, #89) | `assets/rbx/Characters/Death.rbxm` | `Server.DeathBody` : le joueur Mort le revêt, il retrouve son avatar ensuite ; `Client.CloakAnimator` anime le voile |

**La Mort** (#81, après #76 jugé « trop simpliste, un assemblage de formes basiques » ; outillage #79 ; deuxième passe
sculptée #89) : un spectre décharné de l'archétype « détraqueur » (l'archétype, pas un personnage existant), très
grand (7,2 studs sans la faux, 7,6 avec, sous les portes de 8), sans pieds, qui flotte à 0,2 stud du sol. Suaire
d'un seul tenant tendu sur un crâne étroit : arcade, orbites, pommettes, cavité nasale, maxillaire et mâchoire
tendent le tissu, des plis de tension en tombent vers le cou ; tête penchée, dos voûté, épaules osseuses ; robe
lourde trouée sur une cage thoracique (côtes et sternum sous une chair desséchée, ventre creusé sous le rebord
costal) ; manches très larges d'où sortent des bras maigres et des mains griffues (jointures noueuses, tendons,
griffes qui naissent sur le dos de la dernière phalange ; la droite serre la faux, la gauche se tend) ; le bas se
défait en 40 lanières de longueurs très inégales qui plongent vers l'arrière en traîne et se relèvent au-dessus du
sol, sans reculer de plus de 2,6 studs derrière la racine (sans collision, une traîne plus longue traverserait le mur
auquel la Mort s'adosse et la trahirait dans la pièce voisine ; contrôlé par `checks.py`). Avant /
après : `docs/renders/death/v76/`, `v81/` et `docs/renders/death/` (`textured/` : textures cuites ; `silhouette/` :
silhouette du modèle seul ; un mortel voit hors faisceau la colonne d'ombre de #98).

Écrite par script Blender (`tools/blender/death_model.py` et ses modules `tools/blender/death/` : `posture`, `veil`,
`anatomy`, `scythe`, `rig`, `checks` ; rejouable, la source est le script), puis sculptée à la brosse pour la tête,
le torse, les mains et la faux (section « Sculpt à la brosse »), produite par `tools/blender/pipeline.py`
(section « Produire un modèle détaillé sans crédits »), exportée en GLB, envoyée par Open Cloud (dossier d'envoi
approuvé `worktrees/.export` du checkout principal), puis remontée dans Studio par `tools/rbxm/remount.luau` sur le
rig R15 de #73 :
- **rig R15 gardé, invisible** (`Transparency = 1` : un `Highlight` ne dessine pas ces pièces, vérifié) : il porte le
  Humanoid et les déplacements. `AutomaticScalingEnabled = false` et `HipHeight = 2,65` : sinon le Humanoid recalcule
  une hauteur de hanches nulle et reste en chute libre (constaté en jeu). Ses articulations des bras (épaule, coude,
  poignet) sont recalées par le remontage sur les os du spectre (`bones.body.joints`) ;
- **voile** (modèle `Veil`) : `Cloak` (robe drapée par simulation de tissu, à os : 16 chaînes de 4 os `Cxx_y` sous
  `HumanoidRootPart.Root`), `Shroud` (suaire, forme dessinée), `HemSmokeArea` (pièce invisible, fumée `HemSmoke`) ;
- **lanières** (modèle `Tatters`) : `Tatters`, skinnée sur les mêmes os que la robe (vue d'un mortel hors faisceau,
  cachée avec le reste du corps sous la colonne d'ombre, #98) ;
- **bras** (modèle `Arm`) : `Hands` (avant-bras et mains d'un seul tenant, griffes comprises) et `Sleeves` (manches
  drapées), **skinnées sur les os du corps** (`BodyRig`, racine `Spine`, 37 os : bras, main, trois phalanges par
  doigt), que le remontage range sous les pièces du rig R15 (`bones.body.attach` : `Spine` sous `UpperTorso`,
  `R_UpperArm` sous `RightUpperArm`, etc.) : animer le rig anime les bras (#55, #74). Le corps de la Mort ne reprend
  pas le script `Animate` par défaut (`Server.DeathBody`) : la marche de Roblox balancerait les bras ;
- **corps** (modèle `Body`) : `Torso` (cage thoracique sous la peau, visible par les trous de la robe) ;
- **faux** (modèle `Scythe`, soudée à `RightHand` : elle suit la main), une MeshPart par zone de skin : `Blade` (lame
  forgée : dos renforcé, plat, rainure, biseau ; coups de marteau, piqûres de rouille et rayures sculptés), `Edge`
  (fil, ébréchures franches qui mordent aussi le biseau), `Engraving` (fond de la rainure, acier oxydé),
  `ScytheHead` (douille à deux colliers, attelles rivetées le long du manche, gemme sertie des deux côtés, soie,
  éperon), `Gem`, `Rings`, `Shaft` (branche noueuse, moignons de branches coupées, fentes et fil du bois), `Grip`
  (lanières de cuir, un bout libre), `Pommel` ;
- toutes les pièces sont sans masse, collision, contact ni requête de rayon, soudées à `HumanoidRootPart` (sauf la
  faux) ; les pièces de #76 (`Hood`, `Void`, `Sleeve`, `BoneArm`, fumée `HoodShadow`) sont retirées par le
  remontage (`studio.remove`).
- Couleurs et matériaux (l'import GLB les perd) : table `parts` de `tools/models/death.manifest.json`, reposés par le
  remontage ; les textures cuites (`SurfaceAppearance`) portent le détail : lin CC0 pour les tissus, chair procédurale
  (cendre grise marbrée, veines, rides, griffes de corne jaunie) pour `Hands` et `Torso`, bois CC0 pour `Shaft`, métal
  rouillé CC0 pour `Blade` et `ScytheHead` (avec une carte de métal uniforme, `MetalnessMap` : sans elle la
  `SurfaceAppearance` rend le fer non métallique).
- Contact de la main (#89, mesuré sur les maillages réels, main sculptée comprise : un rayon part de l'axe du manche,
  touche le cuir puis la peau du doigt) : les phalanges pressent le cuir de 0,005 stud au moins (110 points d'appui) ;
  les deux bouts de chaque doigt, qui ne sont pas des appuis (jointure de base qui quitte la paume, bout arrondi d'où
  part la griffe), sont à +0,01 stud au plus.

**Preuve `SurfaceAppearance` (#79, cape seule)** : modèle envoyé en asset Model 104750013155394 (#76 :
112747301669865), textures cuites de la cape en assets Image 90768318909720 (couleur), 75803274684492 (normales),
134709665699025 (rugosité), posées par le remontage sur la MeshPart skinnée `Cloak`. Mesuré dans Studio :
- mémoire des textures (`Stats:GetMemoryUsageMbForTag(GraphicsTexture)`, clone affiché à l'écran) : **+2,67 Mo** pour
  les trois cartes 1024 (99,78 → 102,45 Mo) ;
- la cape s'anime toujours (`Client.CloakAnimator`, os `C08_3` relevé à 3,39° puis 4,00° en jeu) ;
- le `Highlight` de `Client.DeathView` (noir, opaque, `Occluded`) recouvrait entièrement la texture ; depuis #98, le
  vrai corps est caché sous la colonne d'ombre. La texture ne compte donc que pour la Mort elle-même et pour la lumière
  d'une lampe (faisceau).

**Spectre (#81)**, mesuré dans Studio : modèle asset 118631689439173 (faux raccourcie ; premier envoi 136242008686173),
20 images (identifiants dans la table `surface` du manifeste) ; mémoire des textures **+10,3 Mo** pour sept pièces texturées (102,45 → 112,79 Mo : trois pièces en
1024, quatre en 512) ; remontage : 15 pièces remplacées, 4 retirées, 65 os de robe, 37 os du corps rangés sur le rig,
écart d'origine 0 ; relancé sur le modèle déjà remonté (second envoi), même résultat, sans avertissement. En jeu :
sommet à 7,57 studs (faux comprise), bas de l'embout à 0,13 stud du sol.

**Spectre sculpté (#89)**, mesuré dans Studio : modèle asset 122547302892751 (envois précédents 138707365299947 puis
72062636211130, avant les côtes approfondies et la traîne plafonnée), 30 images neuves au fil des envois (suaire, lanières, mains, torse, manche ; lame et douille avec leur carte
de métal ; robe et manches inchangées au bit près, non renvoyées). Remontage : 15 pièces remplacées, 65 os de robe,
37 os du corps, écart d'origine 0, aucun avertissement ; relancé sans import, même résultat. Mémoire des textures
(clone affiché) : 114,21 Mo avec le modèle #81, 124,55 Mo après le nouveau ; le cache des textures #81 ne se libère
pas à chaud, la part nette n'est donc pas isolée (estimée à +3,3 Mo d'après le coût mesuré en #81 : la lame en 1024,
la douille en 512). En jeu, sous la lampe d'un mortel : le crâne se lit sous le suaire (orbites, cavité nasale,
mâchoire), les côtes par le trou de la robe ![](mort/mortel-tete-lampe.jpg) ![](mort/mortel-torse.jpg).

**Cape vivante** : `Shared.CloakMotion` (règles pures, testées) et `Client.CloakAnimator`, qui écrit `Bone.Transform` en
`PreSimulation`, car l'Animator du Humanoid remet ces valeurs à zéro à chaque étape d'animation. Ondulation au repos,
traîne à l'opposé du mouvement ; les lanières suivent les mêmes os. Mesuré en jeu sur le spectre (#81, os du bas
arrière `C08_3`, angle à la verticale) : 7,5° immobile en moyenne (ondulation de 0 à 14°), 27° entre 12,5 et 15
studs/s (+20°), 38° entre 17,5 et 20 studs/s (+30°, pointes à 55°). Sur le voile de #76, évasé, la mesure était de
+24° à 14,7 studs/s (40° → 65°).

Pour un mortel, la Mort exposée hors faisceau est une **colonne d'ombre pleine** sans faux (#98, `Client.DeathView`,
géométrie `Shared.DeathLook.column`, réglages `DeathLook.COLUMN`) ; elle remplace l'ombre qui « épousait la
silhouette » (#80 : un `Highlight` par morceau du corps ; #90 : volutes `Beam` au bas), qui laissait voir des taches
d'ombre et des mains. Le vrai corps est caché tant qu'elle est affichée. Elle est faite de 19 ellipsoïdes locaux (pièces
dont la sphère remplit la taille) sous **un seul** `Highlight` plat et sans contour : 16 couches serrées du sol au
centre de la capuche (demi-hauteur 3 fois leur écart, d'où un flanc lisse : creux de moins de 0,05 stud, testé en
Lune), larges selon un profil lissé (`PROFILE` : évasé vers le sol, régulier, rétréci vers la capuche), centrées sur
les anneaux d'os du milieu et du bas de la robe (`Cxx_1`, `Cxx_3` : le bas ondule et traîne avec la cape) puis sur la
tête penchée (`Shroud`) ; chaque bord est déplacé par une onde lente (±3,5 % de la largeur, période 4,1 s à droite et
3,4 s à gauche, une demi-onde sur la hauteur, testée en Lune). Le pied s'arrête à 0,3 stud du sol (`LIFT`) : il se
perd dans la fumée au lieu de poser une ellipse nette sur le plancher ; dessous, une jupe basse pas plus large que la
base, et en glissant une langue étroite qui s'effile vers l'arrière (pointe à 3,7 studs derrière la racine à
9 studs/s, testée en Lune et mesurée en jeu). Itérations précédentes : 1 (couches espacées, bouffées et lobes : une pile
de boules, commit `97fb72b`) ; 2 (fumée en lames étirées qui traînaient sur les murs, cornes sur la capuche, pied en
disque, commit `f6f5f04`). Le bord bouillonne par la fumée : 4 émetteurs posés sur les flancs de la silhouette **tels
que la caméra les voit** (deux bandes de chaque côté, du pied aux épaules : rien au-dessus) lancent des bouffées presque
noires et presque rondes (`Squash` 0,1) qui naissent juste en deçà du bord et s'en écartent de 0,2 stud environ
(0,6 avec leur rayon) avant de se défaire ; **accrochées** à leur volume (`LockedToPart`), elles suivent la Mort qui
glisse au lieu de rester sur les murs. Au sol, une fumée épaisse et aplatie naît dans un disque plus large que le pied
(forme `Disc` : un `Cylinder` n'émettait que vers l'avant et l'arrière), tout autour, devant compris, et casse son
bord ; en glissant, une fumée accrochée à la langue la couvre (jamais plus loin que sa pointe). Braises claires ; la
fumée du modèle (`HemSmoke`) reste coupée tant que la colonne la remplace. **Texture de fumée** dédiée : bouffée ronde,
dense au cœur, bord vaporeux, blanche (la couleur vient de l'émetteur), écrite par `tools/blender/shadow_smoke.py`
(graine fixe, `blender -b --factory-startup --python tools/blender/shadow_smoke.py -- <sortie.png> 256 [aperçu.png]`),
source `assets/textures/death/shadow_smoke.png`, envoyée par Open Cloud (type Image, asset **105518246295498**,
modération approuvée en moins d'une minute ; la version à bords déchirés de l'itération 2 : 80745440503887) ;
`smoke_main` de Roblox est trop pâle pour se voir en sombre et `explosion01` fait des boules. Pièges mesurés en jeu :
une pièce de 1 stud agrandie par son seul maillage n'est plus dessinée au loin (la colonne disparaissait à 20 studs) ;
une pièce opaque prend le voile de l'atmosphère (bleu-gris à 20 studs, même sous le remplissage) : les pièces gardent
0,05 de transparence ; une fumée diffuse posée devant la colonne la grisait au loin, d'où des émetteurs sur les seuls
flancs vus de la caméra ; l'arc clair vu contre la capuche en itération 2 était l'horloge du mur (`LivingClock`, en
(0,6 ; 6,2 ; 22)) à demi cachée, pas un morceau du modèle. Mesuré en jeu (#98, salon éclairé) : une seule masse noire
au flanc lisse à 5,6 et 11 studs, de face et de profil, sans main ni trou ; repérable nettement à 29,4 studs en
diagonale du salon (#90 : 28,7) ; particules en vol en pleine ombre, débit × durée de vie : 72 en glissant (flancs bas
2 × 12/s × 0,75 s, flancs hauts 2 × 6/s × 0,75 s, sol 18/s × 1,15 s, langue 24/s × 0,65 s à 9 studs/s, braises
4/s × 2,1 s), 56 immobile, contre 18 en #90, et plus aucune traînée (16 `Beam` en #90). Coût par image non mesuré. Le
rendu ne dépend que des noms `Scythe` (la faux, cachée hors faisceau), `Shroud` et des os `Cxx_1`, `Cxx_3` (sans eux,
la colonne se pose d'après la boîte du corps). Rendu vu d'un mortel (salon éclairé ; positions de la racine du joueur,
caméra à la première personne tournée vers la Mort ; racine du bot posée et ancrée pour les vues fixes, son pivot
n'est pas la racine) : de face, Mort en (3,5 ; 27,5) devant la bibliothèque, joueur en (14 ; 27)
![](mort/mortel-ombre.jpg), à 5,6 studs, joueur en (8,5 ; 27,5) ![](mort/mortel-ombre-5-studs.jpg), de profil (Mort
tournée vers −Z) ![](mort/mortel-ombre-profil.jpg), de profil contre le mur beige, où la fumée des flancs se lit (Mort
en (3,5 ; 20,6), joueur en (11 ; 20,6)) ![](mort/mortel-ombre-mur.jpg), en déplacement (de z = 33 vers z = 6, joueur
en (16 ; 24)) ![](mort/mortel-ombre-mouvement.jpg), à 20,2 studs (Mort en (4,5 ; 6), joueur en (7 ; 26))
![](mort/mortel-ombre-20-studs.jpg), à 29,4 studs (joueur en (19 ; 31)) ![](mort/mortel-ombre-29-studs.jpg), dans le
faisceau ![](mort/mortel-faisceau.jpg) (#89) et de près (`DebugFlashlight = "beam"`, joueur en (9 ; 27))
![](mort/mortel-faisceau-pres.jpg). Prises en Play Solo avec un bot Mort (`DebugAddBot = "Death"`, revêtu du modèle)
et rien de sélectionné ; la Mort à la lumière (vue d'elle-même) ![](mort/v81/mort-lumiere.jpg), en déplacement
![](mort/v81/mort-deplacement.jpg) ; vue du joueur Mort ![](mort/v81/vue-mort.jpg) (#81, pas refaites depuis).
Captures de #76 et #80 : `docs/mort/v76/` ; de #81 : `docs/mort/v81/` ; de #90 et #96 (ombre qui épouse la
silhouette, volutes) : `docs/mort/v90/`.

**Refaire le modèle** (aucune retouche à la main) :
1. modifier `tools/blender/death_model.py` (ou le manifeste) ; si une base sculptée change (tête, torse, mains, faux),
   rejouer les séances de sculpt dans Blender avec interface (`tools/blender/death/sessions/run_all.py`, section
   « Sculpt à la brosse »), sinon la chaîne refuse le sculpt périmé ; puis, depuis la racine du worktree :
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
(`tools/blender/death/checks.py`) : contact des doigts avec la poignée, mesuré sur les maillages réels (appuis ≤ 0,005
stud, bouts des doigts ≤ 0,012, aucun point hors de la poignée), skinning (aucun sommet sans os, 4 os au plus),
silhouette (le tissu ne touche pas le sol, hauteur sous 8 studs, lanières à 2,7 studs au plus derrière la racine).
Le sculpt périmé (base changée) fait aussi échouer la chaîne.

**Cuisson propre (#85)** : les taches de la carte de normales de la cape venaient pour l'essentiel des traits de sculpt
qui se croisaient dans un pli serré (2 006 pixels, 0,19 % : 553 une fois les traits additionnés puis lissés et les faces
retournées ramenées), le reste des plis de l'ourlet couchés au sol, où un rayon long touche l'autre couche du pli
(232 avec des rayons courts). Rayons courts par défaut (`cage` du manifeste : extrusion 0,05, portée 0,1) ; la cuisson
est refusée au-delà de 0,2 % de pixels très inclinés (`spikesMax` par pièce : 2 % pour `Hands`, dont les griffes
gardées vives demandent de grandes corrections voulues ; pièces dures de la faux, #89 : 0,8 % pour `Blade`, piqûres
profondes et parois des ébréchures, 1,5 % pour `Shaft`, moignons de branches à 8 facettes, 6 % pour `ScytheHead`,
rivets à 8 facettes, colliers et sertissures que la carte arrondit ; vérifiés au rendu texturé). Garder vives au
sculpt les arêtes anguleuses aggravait la mesure (lame 0,48 → 0,67 %, douille 4,2 → 5,4 %) : la pièce jouable est
lissée à travers elles. `Tatters` n'a pas de carte de normales (`"normal": false`) :
ses rubans fins se croisent, les rayons touchaient le voisin.

## Sculpt à la brosse (#89)

Les formules ont plafonné sur les détails fins (tête, torse, mains, faux) : ces pièces sont **sculptées avec les vraies
brosses de Blender** (Draw, Clay Strips, Crease, Inflate, Pinch, Smooth, Flatten…, multirésolution), dans la session
avec interface (MCP `blender`), chaque geste regardé à l'image.

- **Séances** `tools/blender/death/sessions/` (`head`, `torso`, `hands`, `scythe`) : suites de traits posés en 3D
  sur la base construite par script (repères tirés de la posture : crâne, côtes, jointures relevées par
  `anatomy.JOINTS`, profil de la lame). `tools/blender/death/brush.py` projette chaque trait depuis une vue
  orthographique tournée vers la zone et le joue avec `bpy.ops.sculpt.brush_stroke` (rayon en studs, pression qui
  effile le trait, symétrie miroir X pour la tête et le torse). Chaque séance repart de la base : elle est rejouable.
- **Source versionnée** : `assets/sculpt/death_sculpt.blend` (Git LFS), un objet `<Pièce>__sculpt` par pièce (la base et
  sa multirésolution). `blender -b` ne peut pas rejouer les traits (pas de vue 3D pour les projeter) : la chaîne relit
  ce fichier (`tools/blender/death/sculpt.py`).
- **Pièce jouable** : même topologie que la base (poids d'os, UV, attributs gardés), sommets recalés sur le sculpt
  (« Apply Base » de la multirésolution). **Version détaillée de la cuisson** : le sculpt au niveau le plus fin, au
  lieu de la subdivision.
- **Garde-fou** : l'empreinte de la base est gardée avec le sculpt ; si le script construit une autre base, la chaîne
  échoue (« sculpt périmé »). Rejouer alors toutes les séances dans Blender avec interface, puis relancer la chaîne :

```python
p = r"<worktree>/tools/blender/death/sessions/run_all.py"
exec(open(p, encoding="utf-8").read(), {"__name__": "__main__", "__file__": p})
```

Les lanières (`Tatters`) restent écrites par script : leur base dépend du drapé de la robe.

**Manifeste** `tools/models/death.manifest.json` : noms des pièces et groupes, os, budgets, réglages de cuisson,
table de remontage (couleurs, matériaux, `SurfaceAppearance`, pièces et fumées ajoutées dans Studio, Humanoid).
`tests/specs/DeathManifest.spec.luau` (Lune, en CI) vérifie que chaque nom cherché par `Client.CloakAnimator`,
`Server.DeathBody` et `Client.DeathView` y figure, que les os sont ceux de `Shared.CloakMotion`, et que les mesures
versionnées (`death.measured.json`) tiennent dans les budgets.

**Budgets** (triangles, mesurés après épaisseur) : au plus **12 000 par pièce** (limite Roblox d'environ 20 000), total
de la Mort ≤ 70 000 (spectre de #81 : 59 000 environ ; #89 : 66 392, au plus 10 560 par pièce, détail dans
`death.measured.json`). Textures : 1024 pour les grandes pièces, 512 pour les petites (spectre : 1024 pour `Cloak`,
`Shroud`, `Hands` et `Blade`, ce qu'on voit le plus, la lame longue et fine ; 512 pour `Torso`, visible seulement par
les trous de la robe, `Tatters`, rubans fins et à demi effacés dans l'ombre, `Sleeves`, `Shaft` et `ScytheHead`) ;
une pièce texturée coûte trois images (couleur, normales, rugosité), quatre pour le fer (métal, 64 px).

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
