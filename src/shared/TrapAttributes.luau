-- Noms des attributs, des événements et des commandes de debug des pièges (#5), seule source de vérité pour le serveur
-- (écriture, Server.TrapService) et les clients (lecture : Client.TrapCues, Client.DeathTrapPrompts, HUD #9).
--
-- État privé (#49) : rien de ce que sait la Mort (pièges armés, souffle, dissipation en cours) n'est posé sur un objet
-- répliqué à tous (Player, maison, invites). Le serveur l'écrit dans le conteneur privé de chaque joueur, un ScreenGui
-- désactivé nommé `PrivateName` sous son PlayerGui (Server.PrivateState) : seul ce joueur le reçoit. Lecture côté client :
--   local private = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild(TrapAttributes.PrivateName)
--   private:GetAttribute(TrapAttributes.BreathCharges)              -- souffle de la Mort
--   private:FindFirstChild(TrapAttributes.TrapStates)               -- état de chaque piège (Mort seulement)
-- Le conteneur peut arriver après le démarrage du client (premier passage du serveur) : l'attendre, puis écouter
-- AttributeChanged.
return table.freeze({
	-- Conteneur privé (ScreenGui désactivé, ResetOnSpawn = false) sous le PlayerGui de chaque joueur
	PrivateName = "PrivateState",

	-- Attributs du conteneur privé du joueur qui joue la Mort (nil pour les autres) : charges de souffle, fin de la
	-- recharge en cours (horloge workspace:GetServerTimeNow(), nil quand le souffle est plein) et nombre de pièges armés.
	-- LightAttributes.DispelProgress (dissipation par une lampe torche, #8) y est aussi.
	BreathCharges = "BreathCharges",
	BreathRechargeEnd = "BreathRechargeEnd",
	ArmedTraps = "ArmedTraps",
	-- Folder enfant du conteneur privé de la Mort : un attribut par point fragile trafiqué, nommé par son identifiant
	-- (Shared.TrapPrompts.idOf, lettres et chiffres seulement) et valant Traps.State ("Preparing", "Armed", "Spent" ; nil = "Idle"), plus
	-- `<id>` .. StepSuffix = étapes faites pendant une préparation (grand piège commencé)
	TrapStates = "TrapStates",
	StepSuffix = "_Step",

	-- Attribut du conteneur privé d'un mortel vivant : true quand il est à environ 3 m d'un piège armé (buée et frisson,
	-- Client.TrapCues). Privé lui aussi : un autre client ne doit pas savoir qu'un piège est armé près de lui.
	Chill = "TrapChill",

	-- RemoteEvent (enfant de ReplicatedStorage) : message bref pour un seul joueur (résultat d'un examen, refus d'une
	-- préparation), argument : texte
	NoticeEvent = "TrapNotice",
	-- RemoteEvent (enfant de ReplicatedStorage) : invite de la Mort tenue ou déclenchée par son client,
	-- arguments (phase, id, action) : phase "began" | "ended" | "triggered", action "work" | "blow"
	-- (Shared.TrapPrompts.Action). Le serveur revérifie rôle, maintien, distance, vue et lumière.
	ActionEvent = "TrapAction",
	ActionPhase = table.freeze({ Began = "began", Ended = "ended", Triggered = "triggered" }),

	-- Nom des invites des pièges : elles portent le tag et les attributs de LightAttributes (PromptTag, PromptRole,
	-- PromptAvailable, PromptSight), filtrées par Client.LightPrompts comme celles de la lumière. Celles des mortels
	-- sont créées par le serveur, celles de la Mort par son client (DeathPromptName).
	PromptName = "TrapPrompt",
	DeathPromptName = "TrapDeathPrompt",

	-- Debug, sur un Player, en contexte serveur, Studio seulement. Commande remise à nil une fois lue :
	-- "prepare:<id>", "arm:<id>" (toutes les étapes), "disarm:<id>", "blow:<id>", "examine:<id>", "defuse:<id>",
	-- "drain" (retire une charge de souffle), "reset". Les règles s'appliquent (limite, charges), pas les contrôles de
	-- rôle, de lumière ni de distance. <id> : AnchorId d'un carrelage, nom du meuble ou LampId du lustre.
	DebugTrap = "DebugTrap",
})
