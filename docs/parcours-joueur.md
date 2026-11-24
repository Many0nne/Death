# Faucheuse — parcours du joueur, lobby et interface

Complète [design.md](design.md). Statut : proposition, à valider. Les durées sont des réglages de départ.
Maquettes de principe : [maquettes.html](maquettes.html) (disposition et idées, pas le rendu).

## Parti pris d'ambiance : l'administration de la mort
Tout le hors-manche se passe dans un **bâtiment administratif entre la vie et la mort** : néons qui grésillent, lino
usé, chaises en plastique, guichets en verre dépoli, brouillard derrière les fenêtres (les Limbes). Réaliste dans les
matériaux, absurde dans la situation : la mort comme un guichet de préfecture. L'interface devient des documents :
ticket, avis, registre, certificat.

Fil rouge graphique : papier jauni, encre, tampons, police machine à écrire pour les documents, police sobre pour les
chiffres. Palette désaturée, une seule couleur d'accent (rouge tampon) pour les alertes.

## Vue d'ensemble
Deux lieux distincts, deux rôles distincts :

```
Le Hall (choisir son côté, former son groupe, inviter)  →  recherche de manche
  → Salle d'attente (manche formée : prêt, tenue, 30 s max)  →  Avis d'échéance / Registre (chargement)
  → Manche (~8 min)  →  Bilan  →  retour au Hall, même groupe
```

| | Le Hall | La Salle d'attente |
|---|---|---|
| Quand | Avant la recherche | Manche formée, avant le départ |
| Qui | Mon groupe (et d'autres joueurs du serveur) | Exactement les 5 joueurs de la manche |
| On peut | Choisir son côté, inviter, partie privée, vestiaire | Se déclarer prêt, changer de tenue, observer l'adversaire |
| On ne peut pas | — | Inviter, changer de rôle, quitter sans pénalité légère |

Objectif : **moins de 60 s entre l'arrivée et le début d'une manche** pour un joueur seul.

## 1. Le Hall (avant la recherche)
Le hall d'entrée du bâtiment, coupé en deux par une **rangée de guichets**. Le côté du guichet où l'on se tient, c'est
le rôle qu'on joue. Changer de rôle = passer de l'autre côté (bouton, avec un fondu ; pas besoin de marcher).

### Côté public : les Mortels
- Hall d'attente public : bancs, distributeur de tickets, écran « Numéro appelé », autres groupes du serveur visibles.
- **Mon groupe = mon banc** (jusqu'à 4 mortels). Une place vide du banc porte le bouton **Inviter** (invitation Roblox
  native) ; un ami invité arrive sur le même serveur et s'assoit sur le banc.
- Le chef du groupe prend le **ticket** : la recherche commence pour tout le banc. Le ticket montre le numéro et
  l'attente estimée.
- Boutons : Groupe, Inviter, Partie privée, Vestiaire, Registre (stats).

### Côté administration : la Mort
- Derrière les guichets : un **bureau** en enfilade, lampe de bureau, piles de dossiers, tampon. On voit le public à
  travers le verre dépoli (silhouettes floues), le public ne voit que des ombres.
- La Mort est **seule** (pas de groupe, pas d'invitation en partie publique). Les autres joueurs du serveur qui
  attendent comme Mort sont assis aux autres bureaux.
- Bouton **Ouvrir le guichet** = lancer la recherche. Le bureau sert aussi de vestiaire de la Mort (cape, faux, effet
  de fauchage) et montre la réserve d'âmes (un bocal ou un classeur qui se remplit).

### Partie privée (payante)
- Serveur privé Roblox natif, payant en Robux (abonnement mensuel fixé par nous). Le propriétaire et ses invités
  arrivent dans un Hall privé. Le chef désigne la Mort ou tire au sort, choisit la carte. Les amis peuvent donc jouer
  la Mort contre leur groupe ici, et seulement ici.
- Gains de monnaie **normaux** (pas de réduction).
- Toujours 1 Mort + 4 mortels : il faut 5 joueurs (bots plus tard, voir « File »).

### File et équilibre des rôles
- La Mort est très demandée sur Roblox : la file de la Mort sera plus longue. On affiche l'attente estimée **des deux
  côtés** et un **bonus « rôle en manque »** (+25 % de monnaie) sur le côté qui manque de joueurs, comme un panneau
  « Guichet en sous-effectif ». À valider.
- Pas de tirage imposé : chacun choisit son côté.
- **Jamais de manche à moins de 4 mortels** (une manche à 3 avantage la Mort). On attend. Plus tard : bots mortels
  pour compléter une manche après une longue attente, ou remplacer un joueur parti (complexité à évaluer).

## 2. La Salle d'attente (manche formée)
Une fois les 5 joueurs trouvés, téléportation vers le serveur de la manche. On arrive dans une **petite salle
d'attente** attenante à la carte (techniquement dans la place de la manche : elle masque le chargement).

- **Mortels** : 4 chaises face à un guichet fermé. Chacun voit les autres mortels, leur tenue, et un voyant
  **Prêt / Pas prêt** au-dessus de la chaise.
- **Mort** : derrière le guichet, elle voit les 4 mortels à travers le verre et prépare sa tenue. Les mortels ne voient
  qu'une ombre et un nom (pseudo seulement, pas de niveau ni de cosmétique : garder la surprise).
- Écran « Numéro appelé » = compte à rebours. Départ quand tout le monde est prêt, ou **au bout de 30 s**.
- Actions possibles : prêt, vestiaire (tenue de cette manche), regarder les autres. **Pas** d'invitation, **pas** de
  changement de rôle.
- Quitter ici : retour au Hall avec une courte pénalité de file (1 min). La manche cherche un remplaçant ; s'il n'en
  trouve pas en 30 s, les joueurs restants retournent en file **en priorité**.
- Signal de départ : le guichet s'ouvre, sonnette, fondu au noir → Avis d'échéance.

## 3. Avant la manche : Avis d'échéance et Registre (15 s)
- **Mortels** : un **avis d'échéance** à leur nom, tamponné, avec le lieu et l'objectif de fuite tiré pour la partie.
  Rappel des touches en bas.
- **Mort** : le **registre** de la nuit : une ligne par mortel avec une case « Âme » à tamponner, nombre de points
  fragiles, plafond de pièges armés.

## 4. Interface en manche
Principe : **HUD minimal**, l'information vit dans le monde (bruits, buée, ampoules qui grésillent, cœur entendu).

### Commun aux deux rôles
- **Haut centre** : sablier discret, sans chiffre (les chiffres apparaissent sous 1 min).
- **Haut gauche : les mortels**, même emplacement, même ordre, même portraits pour les deux rôles. États : vivant,
  agonie (cœur qui bat + temps restant), ranimé, mort, sauvé. Un joueur qui change de rôle retrouve ses repères.
  - En plus pour la Mort : une petite case **Âme** sous chaque portrait (tamponnée si fauchée, barrée si échappée).

### Mortel
- **Objectifs repliés par défaut** : une seule ligne discrète en bas à gauche, l'étape en cours
  (« Réparer la voiture 2/3 »). Une touche (Tab) déplie la note complète tant qu'elle est maintenue. La ligne s'affiche
  quelques secondes à chaque progrès, puis s'estompe.
- **Bas droite** : l'objet tenu ; la batterie de la lampe se lit sur sa LED.
- **Au centre, contextuel** : Examiner, Désamorcer, Masser. Le massage affiche une ligne d'électrocardiogramme à frapper
  en rythme.
- **Agonie** : écran désaturé, bords sombres, battement de plus en plus lent.

### Mort
- **Bas droite** : souffles (3) et pièges armés (0/4). Rendu à revoir plus tard (piste : objets du monde, par exemple
  sceaux de cire ou sablier de poche, plutôt que des icônes).
- **Indicateur d'ombre / exposée** : la lumière change ses pouvoirs.
- **Vision de la Mort** : écran gris, fils rouges entre les points fragiles, enchaînements possibles en pointillés.

### Mort ou fauché
- Spectateur des survivants. En v2 : âme errante (design.md).

## 5. Le Bilan (validé)
- **Mortel sauvé** : « Avis de report » tamponné ANNULÉ, temps de fuite.
- **Mortel mort** : **certificat de décès** avec cause et heure (« Chute dans l'escalier, 02 h 14 »).
- **Mort** : registre complet, âmes tamponnées, Échec / Moisson / Moisson parfaite.
- Écran commun : gains par action, **rejouer de la mort** (3 s cinématiques, moment fort pour les clips).
- Boutons : **Rester ensemble** (par défaut, garde le groupe et le remet au Hall) / Retour au Hall.

## 6. Première arrivée
1. Arrivée au Hall côté public, flèche discrète vers une **salle d'essai** facultative (examiner, désamorcer, massage).
2. Le côté administration est verrouillé jusqu'à 1 manche jouée en mortel.
3. Infobulles contextuelles pendant la première manche seulement.

## 7. Architecture Roblox (repères)
- **Deux places** : `Hall` (serveurs publics, ~24 joueurs) et `Manche` (une par carte plus tard), qui contient aussi la
  salle d'attente.
- **File** : `MemoryStoreService` (files séparées Mort / groupes de mortels), un groupe reste indivisible.
- **Manche** : `TeleportService:ReserveServer` puis `TeleportAsync` avec `TeleportOptions` ; rôles et groupe passés en
  `TeleportData`, revérifiés côté serveur.
- **Invitations** : `SocialService:PromptGameInvite` ; l'ami rejoint le serveur de Hall de l'invitant.
- **Parties privées** : serveurs privés Roblox natifs (prix en Robux réglé dans les paramètres de l'expérience) ;
  le serveur privé du `Hall` détecte `game.PrivateServerOwnerId` et active le choix de la Mort et de la carte.
- **Retour** : téléportation du groupe vers un même serveur de Hall.
- **Profils** : `DataStoreService` (monnaies, cosmétiques, stats).

## Décisions
Tranchées :
- Thème administratif ; Hall et Salle d'attente séparés ; pas d'invitation en salle d'attente ; bilan.
- 1 Mort contre **4 mortels**, jamais moins (bots plus tard si besoin).
- Parties privées **payantes en Robux**, gains normaux.
- En salle d'attente, les mortels voient le pseudo de la Mort, sans niveau ni tenue.

Ouvertes (recommandation entre parenthèses) :
1. Bonus « rôle en manque » (+25 % de monnaie pour le côté qui manque de joueurs) : oui.
2. Achats donnant un avantage en manche (plus de pièges, plus de souffles) : non, voir « Monétisation ».
3. Rendu des souffles et pièges de la Mort : à revoir plus tard.

## Monétisation (piste)
- **Sûr** : serveurs privés (Robux), cosmétiques (capes, faux, effets de fauchage, tenues, certificats de décès
  personnalisés), passe de saison cosmétique, emotes en salle d'attente.
- **Acceptable** : bonus de monnaie (×2 pendant 1 h), emplacements de tenue supplémentaires, accès anticipé à une carte.
- **Déconseillé** : plus de pièges armés, plus de souffles, lampe plus longue. Dans un jeu asymétrique 1 contre 4,
  une Mort payante fait perdre 4 joueurs qui n'ont rien payé ; ils partent, la file des mortels se vide, et la Mort
  payante n'a plus personne à affronter. Les jeux du genre vendent l'apparence, pas la force.
- **Variante si un avantage payant est voulu** : de la **variété** à puissance égale (pièges ou souffles alternatifs
  qui changent le style sans être plus forts, ex. souffle plus fort mais 2 charges au lieu de 3).
