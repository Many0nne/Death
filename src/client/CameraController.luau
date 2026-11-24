-- Caméra du joueur local (client, #24) : première personne verrouillée pendant la manche (Mort et mortels en jeu),
-- caméra libre ailleurs. Le mode vient de Shared.CameraRules, d'après la phase, le rôle et l'état du mortel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRules = require(Shared:WaitForChild("CameraRules"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))

local CameraController = {}

-- Cette méthode permet de démarrer le pilotage de la caméra lorsque le client se lance.
function CameraController.start()
	local player = Players.LocalPlayer
	local applied: string? = nil

	-- Cette méthode permet d'appliquer le mode de caméra voulu lorsqu'il diffère de celui en place (la caméra de
	-- Roblox garde le mode de première personne d'un personnage à l'autre).
	local function update()
		local mode = CameraRules.modeFor(
			ReplicatedStorage:GetAttribute(MatchAttributes.Phase),
			player:GetAttribute(MatchAttributes.Role),
			player:GetAttribute(MatchAttributes.MortalState)
		)
		if mode == applied then
			return
		end
		applied = mode
		if mode == CameraRules.Mode.FirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		else
			player.CameraMode = Enum.CameraMode.Classic
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = if mode == CameraRules.Mode.FirstPerson
				then CameraRules.FOV_FIRST_PERSON
				else CameraRules.FOV_FREE
		end
	end

	RunService.RenderStepped:Connect(update)
end

return CameraController
