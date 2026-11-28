# Faucheuse — document de conception

Titre provisoire. Statut : concept, avant prototype. Toutes les durées et distances sont des réglages de départ, à
ajuster en test.

## Le jeu en une phrase
Horreur asymétrique (1 contre 4) : on joue la Mort, qui ne peut pas tuer directement. Elle arme des accidents
cachés dans le décor et les déclenche au bon moment, puis vient faucher l'âme des mortels à terre. Les mortels doivent
accomplir des objectifs pour fuir avant la fin de la nuit, en repérant les présages et en se protégeant par la lumière.

## Intentions
- **Original** : *Destination Finale* du point de vue de la Mort.
- **Lisible** : pièges prévus dans la carte, actions contextuelles, pas de construction libre.
- **Profond** : la difficulté vient du placement, du timing et des enchaînements, pas des commandes.
- **Sans gore** : mort indirecte (accidents), pour garder une classification large.
- **Immersif** : première personne verrouillée pour les deux rôles pendant la manche (décision de l'utilisateur,
  2026-11-24), sans dézoom. Hors manche (attente, résultat, spectateur), caméra libre. Champ de vision 80°, sensibilité
  par défaut de Roblox, pas d'animation de tête. Un mortel en agonie garde la première personne, depuis la tête de son personnage tombé.
- **Réalisme sobre** : matériaux réalistes, éclairage avancé, brouillard, palette désaturée. Le réalisme physique compte
  plus que le photoréalisme (impossible sur Roblox).

## Manche
- 1 Mort contre 4 mortels, environ 8 minutes (sablier visible par tous).
- **Mortels** : fuir en accomplissant les objectifs (ex. trouver les clés et réparer la voiture, ou rétablir le
  téléphone et appeler les secours). Un mortel qui atteint la sortie une fois l'objectif rempli est sauvé.
- **Fin du sablier** : l'heure de tous les mortels encore présents est venue, ils meurent. Pas de victoire passive en
  se cachant.
- **Résultat** : compté par mortel (sauvé ou mort), et par âme pour la Mort (voir « Âmes »).

## Ce qui force les mortels à bouger
- Pas de victoire passive (fin du sablier = mort).
- Objectifs et objets placés au hasard à chaque partie.
- Environ 30 points fragiles par carte, dont seule la Mort sait lesquels sont armés. Chaque pièce en contient plusieurs.
- 4 pièges armés au plus en même temps. La Mort peut en désarmer un pour le replacer : les pièges bougent pendant la
  partie.
- Camper dans une pièce indique à la Mort où concentrer ses pièges.

## La Mort
- **Déplacement** : d'ombre en ombre. Pas d'attaque directe sur un vivant.
- **Apparence** (#73, refaite en #76) : un voile, pas un corps. Robe et pèlerine en lambeaux jusqu'au sol, capuche
  vide (noir pur, aucune tête), aucun pied : on ne doit pas deviner un humanoïde. Seuls dépassent le bras squelette et
  la main qui tiennent la faux. La Mort **glisse** (aucun pas) ; la cape n'est jamais figée : elle ondule au repos,
  traîne derrière elle en mouvement, et une fumée d'ombre monte du bas de la robe et sort de la capuche. Le joueur Mort
  revêt ce modèle pendant la manche et retrouve son avatar ensuite (`docs/assets.md`).
- **Ce que voit un mortel** (#80, règles `src/shared/DeathLook.luau`, rendu `Client.DeathView`) :
  - **dans l'ombre** : rien (ni corps, ni ombre portée, ni fumée) ;
  - **à la lumière ambiante** : une **ombre**, pas une figure transparente. Une masse sombre et pleine (noir bleuté,
    contour gris à peine visible) qui **épouse la silhouette** (suaire, épaules, manches, bras tendu), sans nuage ni
    disque autour du bas (#90) : le bas se défait en **volutes** sombres, une par pli de la robe, qui ondulent et
    s'étirent vers le bas et l'arrière dans le prolongement des lanières, et se couchent derrière elle quand elle
    glisse ; quelques fumerolles sur les bords et quelques braises claires. **Pas de faux** ;
  - **dans le faisceau d'une lampe** (les 3 s avant la dissipation) : l'ombre se déchire (bouffée de fumée, 0,4 s) et
    laisse voir le **vrai corps** et la **faux** ; hors du faisceau, elle se referme en 0,8 s. Puis la dissipation se
    joue comme avant.
  - **Le joueur Mort** voit toujours sa faux, son corps voilé dans l'ombre et plein à la lumière.
- **Vue** : première personne verrouillée. Elle prépare un piège, coupe le disjoncteur ou grille une ampoule **en le
  regardant** (les invites n'apparaissent que sur la cible dans le cône du regard, environ 37°, ou tout près d'elle) ;
  son corps ne la gêne pas (pas de voile sur ses propres bras, l'indicateur ombre/lumière reste).
- **Vision de la Mort** (touche) : écran gris, fils du destin reliant les points fragiles et leurs enchaînements
  possibles. Aide le débutant, récompense l'expert.
- **Préparer** un point fragile : maintenir une touche (durée selon la taille du piège).
- **Souffle** : petite poussée qui déclenche un piège armé. 3 charges, recharge lente. Sert aussi à éteindre une
  bougie.
- **Sabotage de la lumière** : couper le disjoncteur (éteint une aile, bruyant, prévient tout le monde), griller une
  ampoule (une pièce, discret).
- **Faucher** : sur un mortel en agonie, 4 s d'animation.

## Pièges
| Taille | Préparation | Exemples | Bruit pendant la préparation |
|---|---|---|---|
| Petit | 2 à 3 s | carrelage mouillé, marche fêlée | presque rien |
| Moyen | 5 à 6 s | étagère dévissée, câble dénudé | grincement audible à environ 15 m |
| Grand | 10 s en 2 étapes | lustre, fuite de gaz et étincelle | bruit fort, entendu dans les pièces voisines |

- Un grand piège peut toucher plusieurs mortels.
- **Réglages du prototype (#5)**, source `src/shared/Traps.luau` : carrelage 2,5 s, étagère 5,5 s, lustre 2 × 5 s ;
  un piège commencé compte dans la limite de 4 ; souffle 3 charges, une charge rendue toutes les 45 s, portée 24 studs ;
  zone touchée : carrelage 3 studs, étagère la bande où elle s'abat (sa largeur, sa hauteur devant elle), lustre
  8 studs ; désamorcer 4 / 6 / 8 s. Éclairée, la Mort ne prépare, ne désarme ni ne souffle ; un piège éclairé (lustre
  allumé, cuisine) ne se prépare pas : il faut d'abord éteindre. Un grand piège commencé se finit, s'abandonne (touche du
  souffle, sans charge dépensée) ou se fait désamorcer.
  Buée et accidents seulement dans la pièce du piège (rien à travers un mur). Le lustre tombé s'éteint jusqu'à la fin
  de la manche.
- **Enchaînements** : un piège peut en déclencher un autre (l'étagère renverse la bougie, qui enflamme le rideau).
- **Technique** : accidents scriptés (résultat maîtrisé, pas de raté dû à la latence), joués avec la vraie physique
  pour le rendu.

### Indices (aucun marqueur à l'écran)
1. **Pendant la préparation** : le bruit (tableau ci-dessus).
2. **Piège armé** : indice visuel discret et intermittent (vis au sol, étincelle toutes les 8 à 10 s, eau qui suinte,
   ampoule qui grésille).
3. **À environ 3 m d'un piège armé** : buée de respiration et léger frisson à l'écran.

### Contre-jeu des mortels
- **Examiner** un objet : 1 s, révèle s'il est armé.
- **Désamorcer** : 4 à 8 s selon la taille, en restant exposé.
- La Mort veut des mortels pressés : plus le sablier avance, moins ils regardent.

## Lumière
La lumière **révèle** la Mort, elle ne la bloque pas.
- **Lumière ambiante** : Mort visible (ombre, voir « La Mort »), ralentie, ne peut pas préparer de piège. Ses pièges armés
  fonctionnent et elle peut souffler depuis l'ombre.
- **Faisceau de lampe torche** tenu 3 s sur elle : elle est **dissipée**, se reforme dans une ombre lointaine et perd
  une charge de souffle.
- **Limites** : batterie de lampe d'environ 40 s, piles rares cachées dans la carte ; courant coupable par la Mort ;
  bougies soufflables. Rester groupés en lumière est sûr mais lent, et expose à un grand piège.
- **Réglages du prototype (#8)**, source `src/shared/Flashlight.luau` : lampe allumée / éteinte au clic gauche
  (gâchette droite, bouton tactile), faisceau qui suit la caméra ; batterie 40 s, une pile la remplit ; 3 piles par
  manche (`GameConfig.FLASHLIGHT_BATTERY_COUNT`) sur les emplacements de clés restés libres, une par pièce au plus.
  Faisceau : portée 40 studs, cône qui agit de 18° de demi-angle (la tache visible est un peu plus large : 45° au
  total, soit 22,5° de demi-angle), arrêté par les murs. Il éclaire au sens de la règle ci-dessus (la Mort dedans est
  visible et ralentie, ne prépare pas). Dissipation :
  3 s de faisceau cumulées (une coupure de moins de 0,3 s est tolérée), puis bouffée de fumée, reformation sur un
  ancrage au sol dans l'ombre à plus de 50 studs de la Mort et de chaque mortel, une charge de souffle perdue, 2 s de
  répit.

## Agonie, fauchage, réanimation
- **Accident** : le mortel tombe **en agonie**. Il rampe lentement, son cœur s'entend à distance. 45 s avant de
  mourir seul.
- **Fauchage** : 4 s. Dans une pièce éclairée, la Mort doit d'abord couper la lumière ou accepter d'être exposée.
- **Massage cardiaque** (partout) : jeu de rythme en cadence (100 à 120 battements par minute), environ 8 s. Mauvais
  rythme = plus lent.
- **Défibrillateur** (objet rare) : 2 s, très bruyant, 1 ou 2 charges.
- **Lutte pour l'âme** : si la Mort fauche pendant un massage, l'âme est à moitié sortie, la faux tire d'un côté et le
  massage de l'autre. La qualité du rythme décide.
- **Mortel ranimé** : visible par la Mort à travers les murs pendant 20 s. Un deuxième accident le tue sans agonie.
- **Réglages du prototype (#6)**, sources `src/shared/GameConfig.luau` et `src/shared/Agony.luau` : reptation à
  4 studs/s sans saut ; cœur de 90 à 40 battements par minute au fil de l'agonie, entendu à environ 70 studs ;
  « Faucher » (Mort, F, maintien 4 s, 8 studs) ; « Masser » (mortel, E) puis compressions sur Espace, clic ou bouton A,
  masseur immobile : chaque compression notée selon l'écart avec la précédente (pleine entre 100 et 120 par minute,
  ± 0,04 s de latence, nulle à 0,2 s au-delà), 16 compressions au rythme parfait (≈ 8 s à 110), massage abandonné
  après 1,5 s sans compression (avancée perdue). Lutte : fauchage fini pendant un massage, l'âme part à moitié
  sortie, la faux la tire en 4 s, chaque compression la repousse de 0,125 × qualité : il faut une qualité moyenne
  d'environ 55 % pour gagner. Mort immobile pendant la lutte, minuterie de l'agonie arrêtée.
- **Mort par Roblox pendant la manche (#48)** : un mortel vivant tué par Roblox (`/reset`, chute, Health = 0) subit un
  accident (agonie, ou mort s'il a déjà été ranimé) ; un agonisant tué ainsi reste en agonie et réapparaît là où il
  est mort.

## Âmes (validé dans le principe)
- **Âme fauchée** : la Mort la récolte. Dans la manche, elle recharge entièrement son souffle. Hors manche, c'est la
  monnaie de progression de la Mort.
- **Âme non fauchée** (mort seul en 45 s, deuxième accident, fin du sablier) : le mortel est mort, mais son âme
  **s'échappe**. La Mort ne gagne ni recharge ni monnaie.
- **Âme errante (v2)** : le joueur mort incarne son âme, un feu follet qui peut, une ou deux fois, signaler un piège armé
  à ses alliés. Laisser une âme s'échapper aide donc les vivants : c'est le vrai coût d'un mortel non fauché.
  **Point de vigilance** : ne pas rendre l'âme errante trop forte. Pistes de réglage : signal rare (1 ou 2 par manche),
  bref, imprécis (une zone, pas l'objet exact), et dissipable par la Mort si elle le touche.
- **Bilan de la Mort** : 0 âme = échec, moitié des âmes = moisson, toutes = moisson parfaite.
- **Côté mortels** : monnaie propre gagnée par objectif, réanimation, désamorçage, fuite.
- **Dépense** : uniquement cosmétique (capes, faux, effets de fauchage ; tenues des mortels). Pas d'avantage payant.

## Parcours joueur, lobby et interface
Détaillés dans [parcours-joueur.md](parcours-joueur.md) : salle d'attente, tickets de rôle, groupes d'amis, avis
d'échéance, HUD, bilan.

## Méta : les Limbes (après validation du cœur)
Lobby explorable, brumeux : la Mort y dépose ses âmes, essaie ses capes et ses faux, croise d'autres joueurs. Version
réduite de l'idée de petit monde ouvert.

## Première carte : maison familiale de nuit
Maison à étage avec cave et terrain clos, au bord d'une rue (#25). Plan en boucles : on peut toujours contourner un
piège ou la Mort, et la Mort peut couper par les pièces sombres. Description : `src/shared/HouseLayout.luau` ; mesures :
`lune run tools/house-report` ; plan sans Studio : `docs/plan/plan.svg` (2D) et `docs/plan/maison-3d.html` (3D),
régénérés par `lune run tools/house-map` (`check.sh` échoue s'ils ne sont plus à jour).

- **Rez-de-chaussée** : entrée (porte d'entrée fermée à clé), grand salon (lustre, porte-fenêtre sur le côté),
  salle à manger, cuisine, dégagement sombre au centre, bibliothèque sombre, buanderie, véranda ouverte sur le jardin,
  garage (voiture de fuite). Pièces traversantes : entrée ↔ salon ↔ dégagement ↔ entrée, entrée ↔ salle à manger ↔
  cuisine ↔ dégagement, salon ↔ bibliothèque ↔ véranda ↔ buanderie ↔ cuisine.
- **Étage** : palier et couloir est sombres, bureau, suite des parents (chambre, dressing sombre, salle de bain),
  chambre d'enfant, chambre d'amis, chambre d'ado et salle d'eau communicantes, grenier sombre au-dessus du garage.
- **Cave** : cave (disjoncteur), cellier, cave à vin, atelier sous le garage, toutes sombres ; la Mort y apparaît.
- **Accès entre niveaux** : escalier principal (dégagement ↔ palier) et escalier du garage (garage ↔ grenier) ;
  escalier de la cave (cuisine ↔ cave) et escalier de l'atelier (garage ↔ atelier).
- **Dehors** (nuit) : devant de la maison, allée du garage jusqu'au portail de la rue, côté ouest, passage nord, cour,
  potager, jardin, abri de jardin. Haie haute tout autour (limite de la carte), rue et terrains voisins au-delà.
  Lumières : applique du porche, lampadaire de l'allée, lanterne du jardin ; tout le reste est sombre.
- **Fuite** : clés dans trois pièces tirées au hasard (hors allée), voiture au garage ; une fois la voiture démarrée,
  la porte du garage s'ouvre et la sortie est au bout de l'allée, devant le portail.
- **Habillage** (#26, `src/shared/HouseStyle.luau`) : blocs travaillés, sans asset modélisé. Matériaux Roblox par
  pièce (parquet, carrelage, moquette, papier peint, béton à la cave, brique à la cave à vin), façade crépie, haie,
  gravier dans l'allée. Chaque meuble est un modèle : un volume invisible qui porte les tags (pièges, clés) et des blocs
  visibles qui arrêtent joueurs et rayons. Fenêtres factices sur les façades (ni lumière ni vue au travers), habillage
  des lampes (abat-jour, bras du lustre) et tapis sans collision ni ombre. Vue 3D : case « Rendu ».
- **Petits objets** (#38, `HouseLayout.clutter`, `HouseStyle.clutter`) : livres un par un, bouteilles couchées, objets
  posés sur les meubles, cadres, horloges et miroirs aux murs, jouets, vêtements et cartons au sol, toiles d'araignée
  dans les pièces abandonnées. Une identité par pièce (soirée interrompue au salon, repas abandonné en cuisine, bureau
  d'enquête, chambre d'ado ≠ chambre d'enfant ≠ chambre d'amis). Tous visibles, sans collision, ni rayon, ni ombre ;
  au sol une marche de haut au plus, jamais sur un emplacement de clés, une porte, une fenêtre ou un meuble piège.
  Variation tirée de l'identifiant (même maison à chaque construction). Budget : environ 3 150 Parts (1 300 avant).
- **Mesures** (#25) : environ 13 500 studs² à l'intérieur et 6 500 dehors (prototype #3 : 7 900), aucun cul-de-sac,
  au moins deux boucles par niveau, une trentaine de points fragiles répartis dans la maison et dehors.

## Prototype v0 (objectif : savoir si c'est amusant)
- Maison en blocs gris, aucun travail graphique.
- 3 pièges : carrelage mouillé (petit), étagère (moyen), lustre (grand).
- Lumière ambiante, lampe torche, disjoncteur.
- Agonie, fauchage, massage cardiaque.
- Un objectif de fuite, sablier, fin de manche.
- Test à plusieurs, puis petit budget de pub Roblox ou clips courts pour mesurer si les joueurs restent.

## Décisions ouvertes
- Âme errante : retenue, en v1 ou plus tard (recommandé : après le prototype v0), avec réglage d'équilibre en test.
