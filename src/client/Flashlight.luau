-- Lampe torche du joueur local (client, #8) : interrupteur (clic gauche, gâchette droite, bouton tactile) pour un
-- mortel en jeu, faisceau qui suit la caméra à chaque image, regard envoyé au serveur lampe allumée. Le serveur
-- (Server.FlashlightService) décide de tout : batterie, cône, ligne de vue, dissipation de la Mort ; il pose aussi le
-- faisceau (Attachment « FlashlightBeam » sur la tête), vu de tous.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local FlashlightRules = require(Shared:WaitForChild("Flashlight"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))

local LA = LightAttributes

local ACTION = "Flashlight"
-- Regard envoyé au serveur au plus AIM_RATE fois par seconde, et seulement s'il a bougé (cosinus)
local AIM_RATE = 15
local AIM_MIN_DOT = 0.9995
-- Même décalage que le serveur (Server.FlashlightService) : lampe tenue devant le visage, à droite
local BEAM_OFFSET = FlashlightRules.HOLD_OFFSET

local Flashlight = {}

-- Cette méthode permet de démarrer la lampe du joueur local lorsque le client se lance.
function Flashlight.start()
	local player = Players.LocalPlayer
	local toggle = ReplicatedStorage:WaitForChild(LA.FlashlightEvent) :: RemoteEvent
	local aim = ReplicatedStorage:WaitForChild(LA.FlashlightAimEvent) :: UnreliableRemoteEvent
	local bound = false
	local sentAim: Vector3? = nil
	local aimClock = 0

	-- Cette méthode permet de demander au serveur d'allumer ou d'éteindre la lampe lorsque le joueur appuie.
	local function onAction(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			toggle:FireServer("toggle")
		end
		-- Le clic reste disponible pour le reste du jeu (interface, invites)
		return Enum.ContextActionResult.Pass
	end

	-- Cette méthode permet de proposer l'interrupteur seulement à un mortel en jeu lorsque son rôle change.
	local function updateBinding()
		local mortal = player:GetAttribute(LA.LightRole) == DeathRules.Role.Mortal
		if mortal and not bound then
			bound = true
			ContextActionService:BindAction(
				ACTION,
				onAction,
				true,
				Enum.UserInputType.MouseButton1,
				Enum.KeyCode.ButtonR2
			)
			ContextActionService:SetTitle(ACTION, "Lampe")
		elseif not mortal and bound then
			bound = false
			ContextActionService:UnbindAction(ACTION)
		end
	end

	updateBinding()
	player:GetAttributeChangedSignal(LA.LightRole):Connect(updateBinding)

	-- Faisceau : orienté sur la caméra à chaque image (le serveur ne le fait qu'au rythme du regard reçu)
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not camera or not head or not head:IsA("BasePart") or player:GetAttribute(LA.FlashlightOn) ~= true then
			sentAim = nil
			return
		end
		local look = camera.CFrame.LookVector
		local attachment = head:FindFirstChild("FlashlightBeam")
		if attachment and attachment:IsA("Attachment") then
			local origin = (head.CFrame * BEAM_OFFSET).Position
			attachment.CFrame = head.CFrame:ToObjectSpace(CFrame.lookAt(origin, origin + look))
		end
		aimClock += dt
		if aimClock >= 1 / AIM_RATE and (sentAim == nil or sentAim:Dot(look) < AIM_MIN_DOT) then
			aimClock = 0
			sentAim = look
			aim:FireServer(look)
		end
	end)
end

return Flashlight
