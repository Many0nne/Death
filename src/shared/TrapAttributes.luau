-- Noms des attributs, de l'événement et des commandes de debug des pièges (#5), seule source de vérité pour le serveur
-- (écriture, Server.TrapService) et les clients (lecture : Client.TrapCues, HUD #9). L'état de chaque piège n'est
-- jamais publié sur l'objet : seule la Mort sait lesquels sont armés.
return table.freeze({
	-- Sur le Player qui joue la Mort (nil pour les autres) : charges de souffle, fin de la recharge en cours (horloge
	-- workspace:GetServerTimeNow(), nil quand le souffle est plein) et nombre de pièges armés
	BreathCharges = "BreathCharges",
	BreathRechargeEnd = "BreathRechargeEnd",
	ArmedTraps = "ArmedTraps",

	-- Sur un mortel vivant : true quand il est à environ 3 m d'un piège armé (buée et frisson, Client.TrapCues)
	Chill = "TrapChill",

	-- RemoteEvent (enfant de ReplicatedStorage) : message bref pour un seul joueur (résultat d'un examen, refus d'une
	-- préparation), argument : texte
	NoticeEvent = "TrapNotice",

	-- Nom des invites des pièges : elles portent le tag et les attributs de LightAttributes (PromptTag, PromptRole,
	-- PromptAvailable, PromptSight), filtrées par Client.LightPrompts comme celles de la lumière
	PromptName = "TrapPrompt",

	-- Debug, sur un Player, en contexte serveur, Studio seulement. Commande remise à nil une fois lue :
	-- "prepare:<id>", "arm:<id>" (toutes les étapes), "disarm:<id>", "blow:<id>", "examine:<id>", "defuse:<id>",
	-- "drain" (retire une charge de souffle), "reset". Les règles s'appliquent (limite, charges), pas les contrôles de
	-- rôle, de lumière ni de distance. <id> : AnchorId d'un carrelage, nom du meuble ou LampId du lustre.
	DebugTrap = "DebugTrap",
})
