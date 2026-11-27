-- Noms des attributs et tags de la lumière et de la Mort (#4), seule source de vérité pour le serveur (écriture) et
-- les clients (lecture). Les rôles valent DeathRules.Role.
return table.freeze({
	-- Sur chaque Player : rôle effectif pour la lumière ("Death", "Mortal" ou nil), écrit par DeathController
	LightRole = "LightRole",
	-- Sur le Player qui joue la Mort : true quand elle est éclairée (silhouette visible, ralentie)
	Exposed = "DeathExposed",
	-- Sur le Player qui joue la Mort, public : true quand un faisceau de lampe la tient alors qu'elle est exposée (les
	-- mortels voient alors son vrai corps et sa faux, Shared.DeathLook, #80), nil sinon. Écrit par FlashlightService ;
	-- la progression de la dissipation reste privée (DispelProgress).
	InBeam = "DeathInBeam",

	-- Sur chaque lampe (MapTags.Lamp) : false quand elle est éteinte (aile coupée ou ampoule grillée)
	LampOn = "LampOn",
	-- Sur le disjoncteur (MapTags.Breaker) : aile coupée (WingId) ou nil
	CutWing = "CutWing",

	-- Invites d'action (ProximityPrompt) filtrées par le client (Client.LightPrompts : lumière, fuite, pièges) : tag,
	-- rôle qui peut s'en servir, état de mortel requis (optionnel), action possible maintenant (Shared.PromptVisibility).
	-- Le serveur crée l'invite avec Enabled = false puis ne le touche plus : chaque client l'ajuste pour son joueur.
	PromptTag = "LightPrompt",
	PromptRole = "PromptRole",
	PromptState = "PromptState", -- Match.MortalState requis (ex. "Alive"), nil : aucun
	PromptAvailable = "PromptAvailable",
	-- true : l'invite n'apparaît que si rien ne cache sa cible depuis le personnage (Shared.LineOfSight)
	PromptSight = "PromptSight",

	-- Lampe torche (#8, Server.FlashlightService, règles Shared.Flashlight). Sur chaque mortel (LightRole "Mortal") :
	-- batterie de 0 à 1 (1 = Flashlight.BATTERY_DURATION secondes d'usage), au centième près, pour le HUD (#9), et
	-- lampe allumée (true / false). Nil pour la Mort et hors rôle.
	FlashlightBattery = "FlashlightBattery",
	FlashlightOn = "FlashlightOn",
	-- Dans le conteneur privé de la Mort (Shared.TrapAttributes.PrivateName, #49), pas sur son Player : part de la
	-- dissipation déjà tenue par un faisceau, de 0 à 1 (nil à 0)
	DispelProgress = "DispelProgress",
	-- RemoteEvent (enfant de ReplicatedStorage) : le client demande d'allumer / éteindre (argument "toggle")
	FlashlightEvent = "FlashlightToggle",
	-- UnreliableRemoteEvent (enfant de ReplicatedStorage) : direction du regard (Vector3) envoyée par le client lampe
	-- allumée, pour orienter le faisceau vu des autres et le contrôle serveur
	FlashlightAimEvent = "FlashlightAim",
	-- Pile posée dans la maison (Part) : attribut AnchorId de l'emplacement ; nom des parts
	BatteryName = "Battery",

	-- Debug, sur un Player, en contexte serveur, Studio seulement
	DebugDeath = "DebugDeath", -- true : ce joueur joue la Mort hors manche (téléporté à une apparition de la Mort)
	-- Commande de lumière, remise à nil une fois lue : "cut:<WingId>", "restore", "burn:<RoomId>" ou "reset". Les
	-- recharges s'appliquent, pas les contrôles de rôle ni de distance.
	DebugLight = "DebugLight",
	-- Commande de lampe torche, remise à nil une fois lue : "on", "off", "battery:<0..1>" sur un mortel ;
	-- "beam" sur la Mort (faisceau factice de 4 s, pointé sur elle depuis 12 studs devant, ligne de vue comprise) ;
	-- "dispel" sur la Mort (dissipation immédiate). Les règles s'appliquent, pas le contrôle de rôle.
	DebugFlashlight = "DebugFlashlight",
})
