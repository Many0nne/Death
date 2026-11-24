-- Point d'entrée serveur : démarre les services du prototype v0 (chaque service vit dans son module).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

require(script.NightAmbience).apply(game:GetService("Lighting"))
require(script.HouseBuilder).build(workspace)
require(script.MatchService).get():start()

print(string.format("Death : serveur prêt (%d mortels par manche)", GameConfig.MORTALS_PER_MATCH))
