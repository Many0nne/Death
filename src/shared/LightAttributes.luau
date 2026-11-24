-- Noms des attributs et tags de la lumière et de la Mort (#4), seule source de vérité pour le serveur (écriture) et
-- les clients (lecture). Les rôles valent DeathRules.Role.
return table.freeze({
	-- Sur chaque Player : rôle effectif pour la lumière ("Death", "Mortal" ou nil), écrit par DeathController
	LightRole = "LightRole",
	-- Sur le Player qui joue la Mort : true quand elle est éclairée (silhouette visible, ralentie)
	Exposed = "DeathExposed",

	-- Sur chaque lampe (MapTags.Lamp) : false quand elle est éteinte (aile coupée ou ampoule grillée)
	LampOn = "LampOn",
	-- Sur le disjoncteur (MapTags.Breaker) : aile coupée (WingId) ou nil
	CutWing = "CutWing",

	-- Invites d'action (ProximityPrompt) de la lumière : tag, rôle qui peut s'en servir, action possible maintenant.
	-- Le serveur ne touche jamais Enabled : chaque client l'ajuste pour son joueur (rôle et disponibilité).
	PromptTag = "LightPrompt",
	PromptRole = "PromptRole",
	PromptAvailable = "PromptAvailable",
	-- true : l'invite n'apparaît que si rien ne cache sa cible depuis le personnage (Shared.LineOfSight)
	PromptSight = "PromptSight",

	-- Debug, sur un Player, en contexte serveur, Studio seulement
	DebugDeath = "DebugDeath", -- true : ce joueur joue la Mort hors manche (téléporté à une apparition de la Mort)
	-- Commande de lumière, remise à nil une fois lue : "cut:<WingId>", "restore", "burn:<RoomId>" ou "reset". Les
	-- recharges s'appliquent, pas les contrôles de rôle ni de distance.
	DebugLight = "DebugLight",
})
