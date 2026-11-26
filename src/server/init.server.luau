-- Point d'entrée serveur : démarre les services du prototype v0 (chaque service vit dans son module).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

require(script.NightAmbience).apply(game:GetService("Lighting"))
local house = require(script.HouseBuilder).build(workspace)
require(script.WaitingZone).build(workspace)

-- Les modules de manche s'abonnent aux événements avant le démarrage du service
local matchService = require(script.MatchService).get()
require(script.MatchSpawner).start(matchService, house)
require(script.EscapeService).start(matchService, house)
require(script.LightService).get():start()
require(script.DeathController).get():start()
require(script.TrapService).get():start()
matchService:start()

print(string.format("Death : serveur prêt (%d mortels par manche)", GameConfig.MORTALS_PER_MATCH))
