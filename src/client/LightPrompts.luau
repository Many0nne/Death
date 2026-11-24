-- Invites d'action de la lumière (client) : n'active, pour le joueur local, que les invites de son rôle (attribut
-- LightRole) quand l'action est possible (PromptAvailable) et, pour une ampoule, quand rien ne la cache depuis le
-- personnage (PromptSight, même rayon que le serveur). Le serveur ne touche jamais Enabled et revérifie tout.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local LineOfSight = require(Shared:WaitForChild("LineOfSight"))
local CameraRules = require(Shared:WaitForChild("CameraRules"))

local LA = LightAttributes

-- Fréquence du test de vue des invites PromptSight (secondes) : assez vif pour suivre la marche, peu coûteux
local SIGHT_PERIOD = 0.1

local LightPrompts = {}

-- Cette méthode permet de démarrer le filtrage des invites lorsque le client se lance.
function LightPrompts.start()
	local player = Players.LocalPlayer
	-- Invite PromptSight -> cible visible depuis le personnage au dernier test
	local inSight: { [ProximityPrompt]: boolean } = {}
	-- Première personne verrouillée (#24) : l'invite n'est active que si le regard est posé sur sa cible
	local firstPerson = false
	-- Invite -> cible dans le cône du regard au dernier test (utilisé seulement en première personne)
	local inView: { [ProximityPrompt]: boolean } = {}
	-- Invite en cours de maintien : elle reste active même si le regard dérive (sinon l'action serait annulée)
	local holding: { [ProximityPrompt]: boolean } = {}

	-- Cette méthode permet d'activer ou non une invite pour le joueur local lorsque son rôle, l'action ou la vue change.
	local function refresh(prompt: ProximityPrompt)
		local role = player:GetAttribute(LA.LightRole)
		prompt.Enabled = role ~= nil
			and prompt:GetAttribute(LA.PromptRole) == role
			and prompt:GetAttribute(LA.PromptAvailable) == true
			and (prompt:GetAttribute(LA.PromptSight) ~= true or inSight[prompt] == true)
			and (not firstPerson or inView[prompt] == true or holding[prompt] == true)
	end

	-- Cette méthode permet de suivre une invite lorsqu'elle arrive sur le client.
	-- Invites déjà suivies : le signal d'ajout se redéclenche quand une invite revient (streaming, reparentage)
	local tracked: { [Instance]: boolean } = {}

	-- Cette méthode permet de suivre une invite lorsqu'elle arrive sur le client (une seule fois par invite).
	local function track(prompt: Instance)
		if not prompt:IsA("ProximityPrompt") then
			return
		end
		refresh(prompt)
		if tracked[prompt] then
			return
		end
		tracked[prompt] = true
		prompt.AttributeChanged:Connect(function()
			refresh(prompt)
		end)
		prompt.PromptButtonHoldBegan:Connect(function()
			holding[prompt] = true
		end)
		prompt.PromptButtonHoldEnded:Connect(function()
			holding[prompt] = nil
			refresh(prompt)
		end)
		prompt.Destroying:Connect(function()
			inSight[prompt] = nil
			inView[prompt] = nil
			holding[prompt] = nil
			tracked[prompt] = nil
		end)
	end

	-- Cette méthode permet de retester la vue des invites PromptSight proches lorsque le personnage bouge ; seules
	-- celles dont le résultat change sont rafraîchies.
	local function updateSight()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local checking = root ~= nil and player:GetAttribute(LA.LightRole) ~= nil
		local camera = workspace.CurrentCamera
		local wasFirstPerson = firstPerson
		firstPerson = player.CameraMode == Enum.CameraMode.LockFirstPerson and camera ~= nil
		if firstPerson ~= wasFirstPerson then
			table.clear(inView)
			for _, prompt in CollectionService:GetTagged(LA.PromptTag) do
				if prompt:IsA("ProximityPrompt") then
					refresh(prompt)
				end
			end
		end
		for _, prompt in CollectionService:GetTagged(LA.PromptTag) do
			if prompt:IsA("ProximityPrompt") and firstPerson and camera then
				local target = prompt.Parent
				local looked = false
				if target and target:IsA("BasePart") then
					local size = target.Size
					looked = CameraRules.isLookedAt(
						camera.CFrame.Position,
						camera.CFrame.LookVector,
						target.Position,
						math.max(size.X, size.Y, size.Z) / 2
					)
				end
				if inView[prompt] ~= looked then
					inView[prompt] = looked
					refresh(prompt)
				end
			end
			if prompt:IsA("ProximityPrompt") and prompt:GetAttribute(LA.PromptSight) == true then
				local target = prompt.Parent
				local visible = false
				if checking and root and target and target:IsA("BasePart") then
					local distance = (target.Position - root.Position).Magnitude
					visible = distance <= prompt.MaxActivationDistance
						and LineOfSight.clear(root.Position, target.Position, target)
				end
				if inSight[prompt] ~= visible then
					inSight[prompt] = visible
					refresh(prompt)
				end
			end
		end
	end

	for _, prompt in CollectionService:GetTagged(LA.PromptTag) do
		track(prompt)
	end
	CollectionService:GetInstanceAddedSignal(LA.PromptTag):Connect(track)
	player:GetAttributeChangedSignal(LA.LightRole):Connect(function()
		for _, prompt in CollectionService:GetTagged(LA.PromptTag) do
			if prompt:IsA("ProximityPrompt") then
				refresh(prompt)
			end
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= SIGHT_PERIOD then
			elapsed = 0
			updateSight()
		end
	end)
end

return LightPrompts
