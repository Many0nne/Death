-- Noms des attributs, de l'événement et des commandes de debug de l'agonie (#6), seule source de vérité pour le
-- serveur (écriture, Server.AgonyService) et les clients (lecture : Client.AgonyClient, HUD #9).
return table.freeze({
	-- Sur un mortel en agonie : fin de l'agonie (horloge workspace:GetServerTimeNow()), et pendant une lutte pour l'âme
	-- la part de l'âme sortie (0 à 1, arrondie au vingtième)
	AgonyEnd = "AgonyEnd",
	SoulPull = "SoulPull",
	-- Sur un mortel ranimé : fin de sa visibilité par la Mort à travers les murs (horloge du serveur)
	RevealedUntil = "RevealedUntil",

	-- RemoteEvent (enfant de ReplicatedStorage) du massage cardiaque :
	--   serveur -> client : ("Massage", UserId de l'agonisant | nil) massage commencé ou arrêté ;
	--                       ("Beat", qualité 0..1, avancée 0..1, lutte 0..1 | nil) après chaque compression
	--   client -> serveur : ("Press") une compression
	Event = "AgonyEvent",

	-- Nom des invites « Faucher » (Mort) et « Masser » (mortels), posées sur la racine du personnage agonisant : elles
	-- portent le tag et les attributs de LightAttributes, filtrées par Client.LightPrompts
	PromptName = "AgonyPrompt",

	-- Debug, sur le Player en agonie (ou le mannequin d'un faux joueur, #12), en contexte serveur, Studio seulement. Commande remise à nil une fois lue :
	-- "reap" (fauchage fini par une Mort simulée), "massage:<bpm>" (masseur simulé qui appuie à cette cadence),
	-- "stop" (le masseur simulé s'arrête). Les règles de Shared.Agony s'appliquent, pas les contrôles de distance.
	DebugAgony = "DebugAgony",
})
