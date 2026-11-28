-- Caméra du joueur local (client, #24) : première personne verrouillée pendant la manche (Mort et mortels en jeu),
-- caméra libre ailleurs. Le mode vient de Shared.CameraRules, d'après la phase, le rôle et l'état du mortel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRules = require(Shared:WaitForChild("CameraRules"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))

-- Attribut posé par Server.DeathBody sur le corps de la Mort
local DEATH_BODY_ATTRIBUTE = "DeathBody"

local CameraController = {}

-- Cette méthode permet de démarrer le pilotage de la caméra lorsque le client se lance.
function CameraController.start()
	local player = Players.LocalPlayer
	local applied: string? = nil
	local releaseZoom = false

	-- Cette méthode permet d'appliquer le mode de caméra voulu lorsqu'il diffère de celui en place (la caméra de
	-- Roblox garde le mode de première personne d'un personnage à l'autre).
	local function update()
		local mode = CameraRules.modeFor(
			ReplicatedStorage:GetAttribute(MatchAttributes.Phase),
			player:GetAttribute(MatchAttributes.Role),
			player:GetAttribute(MatchAttributes.MortalState)
		)
		local firstPerson = mode == CameraRules.Mode.FirstPerson
		if mode ~= applied then
			if applied == CameraRules.Mode.FirstPerson then
				-- Sortie de la première personne : la caméra de Roblox garde son zoom à 0,5 ; on force un recul
				-- pendant une frame, puis on rend la plage de zoom normale
				player.CameraMinZoomDistance = CameraRules.FREE_ZOOM_DISTANCE
				releaseZoom = true
			end
			applied = mode
			player.CameraMode = if firstPerson then Enum.CameraMode.LockFirstPerson else Enum.CameraMode.Classic
		elseif releaseZoom then
			releaseZoom = false
			player.CameraMinZoomDistance = CameraRules.DEFAULT_MIN_ZOOM
		end
		-- Caméra aux yeux du spectre quand le personnage porte le corps de la Mort (#91) ; posée sur le Humanoid local,
		-- le serveur et les autres clients ne la voient pas
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local offset = CameraRules.cameraOffsetFor(character:GetAttribute(DEATH_BODY_ATTRIBUTE) == true)
			if humanoid.CameraOffset ~= offset then
				humanoid.CameraOffset = offset
			end
		end
		-- Champ de vision réappliqué à chaque frame : la caméra peut apparaître après le changement de mode
		local camera = workspace.CurrentCamera
		local fov = if firstPerson then CameraRules.FOV_FIRST_PERSON else CameraRules.FOV_FREE
		if camera and camera.FieldOfView ~= fov then
			camera.FieldOfView = fov
		end
	end

	RunService.RenderStepped:Connect(update)
end

return CameraController
