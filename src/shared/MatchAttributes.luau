-- Noms des attributs de la manche, seule source de vérité pour le serveur (écriture) et le HUD (#9, lecture).
-- Valeurs possibles : constantes de `Match` (Phase, Role, MortalState, SoulFate, EndReason).
return table.freeze({
	-- Sur ReplicatedStorage (état de la manche)
	Phase = "MatchPhase", -- Match.Phase
	-- secondes restantes au sablier, entier arrondi au-dessus ; figé pendant Ended, nil en Waiting
	TimeLeft = "MatchTimeLeft",
	Duration = "MatchDuration", -- durée totale du sablier en secondes ; gardée pendant Ended, nil en Waiting
	EndReason = "MatchEndReason", -- Match.EndReason, pendant la phase Ended
	-- Résultat JSON de la dernière manche (HttpService:JSONDecode) : { reason, death = { userId, name },
	-- mortals = { { userId, name, state, soul?, cause? } }, saved, reaped, escaped }. Gardé jusqu'à la manche suivante.
	Result = "MatchResult",
	-- Objectif de fuite (#7), nil en Waiting : clés trouvées / à trouver, voiture démarrée (sortie ouverte)
	KeysFound = "EscapeKeysFound",
	KeysNeeded = "EscapeKeysNeeded",
	CarStarted = "EscapeCarStarted",

	-- Sur chaque Player de la manche (nil pour un joueur hors manche)
	Role = "Role", -- Match.Role
	MortalState = "MortalState", -- Match.MortalState (mortels seulement)
	SoulFate = "SoulFate", -- Match.SoulFate (mortels morts seulement)

	-- Debug, sur un Player, en contexte serveur, Studio seulement (lus par MatchService). Une commande par attribut et
	-- par frame : les signaux différés de Roblox ne livrent que la dernière valeur écrite dans la même frame.
	DebugStart = "DebugStartMatch", -- true : démarre une manche en mode test avec les joueurs présents
	DebugStop = "DebugStopMatch", -- true : annule la manche en cours, retour à l'attente sans résultat
	DebugRole = "DebugRole", -- "Death" ou "Mortal" : rôle imposé aux manches suivantes (nil pour le tirage)
	DebugState = "DebugSetState", -- "Agony", "Alive", "Dead", "Reaped" ou "Saved" : change l'état de ce mortel
	DebugTimeScale = "DebugTimeScale", -- multiplicateur du sablier (ex. 10), gardé jusqu'au retrait (nil = x1)
	DebugTimeLeft = "DebugTimeLeft", -- secondes : règle le temps restant du sablier
	-- "Key" : ramasse une clé restante comme ce joueur ; "Car" : démarre la voiture comme ce joueur (lu par
	-- Server.EscapeService, mêmes règles que les actions en jeu)
	DebugEscape = "DebugEscape",
})
