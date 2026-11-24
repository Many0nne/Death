-- Point d'entrée serveur (prototype v0 à venir).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

print(string.format("Death : serveur prêt (%d mortels par manche)", GameConfig.MORTALS_PER_MATCH))
