# Assets : modèles 3D, production et export

Les modèles du jeu (personnages, et bientôt viewmodels et objets) sont des `.rbxm` binaires versionnés dans
`assets/rbx/<Dossier>/<Nom>.rbxm` (Git LFS) et synchronisés par Rojo : `assets/rbx/Characters` →
`ReplicatedStorage.Characters`. Un fichier = une instance racine, nommée d'après le fichier. Rien ne se garde dans
Studio : une modification non réexportée est perdue. La CI fait un checkout LFS (`rojo build` lit les `.rbxm`).

## Modèles en place

| Modèle | Fichier | Utilisé par |
|---|---|---|
| La Mort (#73, #76) | `assets/rbx/Characters/Death.rbxm` | `Server.DeathBody` : le joueur Mort le revêt, il retrouve son avatar ensuite ; `Client.CloakAnimator` anime la cape |

**La Mort** (#76, retour de l'utilisateur sur #73, jugé trop humanoïde) : un voile en lambeaux, capuche vide, aucun
pied ; seuls le bras squelette et la main qui tient la faux dépassent. Modélisée à la main dans Blender par script
(`tools/blender/death_model.py`, rejouable : la source est le script, pas un `.blend`), exportée en GLB, envoyée par
Open Cloud (asset Model 112747301669865, dossier d'envoi approuvé `worktrees/.export` du checkout principal), puis
montée dans Studio sur le rig R15 de #73 :
- **rig R15 gardé, invisible** (`Transparency = 1` : un `Highlight` ne dessine pas ces pièces, vérifié) : il porte le
  Humanoid et les déplacements. `AutomaticScalingEnabled = false` et `HipHeight = 2,65` : sinon le Humanoid recalcule
  une hauteur de hanches nulle et reste en chute libre (constaté en jeu) ;
- **voile** (modèle `Veil`) : `Cloak` (robe à os, 16 chaînes de 4 os `Cxx_y` sous `HumanoidRootPart.Root`), `Hood`
  (capuche et pèlerine), `Void` (`Neon` noir dans la capuche), `HemSmokeArea` (pièce invisible, fumée `HemSmoke`) ;
  fumée `HoodShadow` dans `Void` ;
- **bras** (modèle `Arm`) : `Sleeve` (manche) et `BoneArm` (avant-bras et main squelette serrée sur la poignée) ;
- **faux** (modèle `Scythe`), une MeshPart par zone de skin, chacune avec ses UV (manche, poignée et gravure : u le
  long de la pièce) : `Blade` (acier, rainure), `Edge` (fil poli), `Engraving` (panneau dans la rainure, des deux
  côtés, prévu pour une texture gravée), `ScytheHead` (douille et éperon), `Gem` (sertie des deux côtés), `Rings`
  (bagues), `Shaft` (manche), `Grip` (cuir en hélice), `Pommel` (pointe) ;
- toutes les pièces ajoutées sont soudées à `HumanoidRootPart` (`WeldConstraint`), sans masse, collision, contact ni
  requête de rayon : elles ne suivent pas les membres animés, la Mort glisse.
- Couleurs et matériaux posés dans Studio (l'import GLB les perd) : tissus `Fabric` presque noirs, os ivoire, lame
  `Metal`, fil `Foil`, bagues laiton, manche `Wood`, poignée `Leather`, gemme `Neon` sarcelle.

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

**Refaire le modèle** : modifier `tools/blender/death_model.py`, l'exécuter dans Blender (MCP :
`exec(open(chemin).read(), {"__name__": "__main__"})`), exporter en GLB dans `worktrees/.export`, envoyer, insérer,
puis remplacer les MeshParts du modèle (même nom, même repère : l'import tourne le modèle de 180° autour de Y) et
remettre couleurs et matériaux. N'existent que dans Studio, à garder : `HemSmokeArea` et les fumées `HemSmoke` et
`HoodShadow`, les soudures, les réglages du Humanoid. Le premier import (asset 112747301669865) date d'avant le
renommage `Head` → `ScytheHead` et `Sphere` → `Void` dans le script, ces deux pièces ont été renommées dans Studio.

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
