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
- **Lumière ambiante** : Mort visible (silhouette), ralentie, ne peut pas préparer de piège. Ses pièges armés
  fonctionnent et elle peut souffler depuis l'ombre.
- **Faisceau de lampe torche** tenu 3 s sur elle : elle est **dissipée**, se reforme dans une ombre lointaine et perd
  une charge de souffle.
- **Limites** : batterie de lampe d'environ 40 s, piles rares cachées dans la carte ; courant coupable par la Mort ;
  bougies soufflables. Rester groupés en lumière est sûr mais lent, et expose à un grand piège.

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
Deux étages et une cave (disjoncteur). Pièces : cuisine, salon (lustre), salle de bain, escalier, chambres, garage
(voiture de fuite).

## Prototype v0 (objectif : savoir si c'est amusant)
- Maison en blocs gris, aucun travail graphique.
- 3 pièges : carrelage mouillé (petit), étagère (moyen), lustre (grand).
- Lumière ambiante, lampe torche, disjoncteur.
- Agonie, fauchage, massage cardiaque.
- Un objectif de fuite, sablier, fin de manche.
- Test à plusieurs, puis petit budget de pub Roblox ou clips courts pour mesurer si les joueurs restent.

## Décisions ouvertes
- Âme errante : retenue, en v1 ou plus tard (recommandé : après le prototype v0), avec réglage d'équilibre en test.
