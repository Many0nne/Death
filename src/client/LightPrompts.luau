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

local LA = LightAttributes

-- Fréquence du test de vue des invites PromptSight (secondes) : assez vif pour suivre la marche, peu coûteux
local SIGHT_PERIOD = 0.2

local LightPrompts = {}

-- Cette méthode permet de démarrer le filtrage des invites lorsque le client se lance.
function LightPrompts.start()
	local player = Players.LocalPlayer
	-- Invite PromptSight -> cible visible depuis le personnage au dernier test
	local inSight: { [ProximityPrompt]: boolean } = {}

	-- Cette méthode permet d'activer ou non une invite pour le joueur local lorsque son rôle, l'action ou la vue change.
	local function refresh(prompt: ProximityPrompt)
		local role = player:GetAttribute(LA.LightRole)
		prompt.Enabled = role ~= nil
			and prompt:GetAttribute(LA.PromptRole) == role
			and prompt:GetAttribute(LA.PromptAvailable) == true
			and (prompt:GetAttribute(LA.PromptSight) ~= true or inSight[prompt] == true)
	end

	-- Cette méthode permet de suivre une invite lorsqu'elle arrive sur le client.
	local function track(prompt: Instance)
		if not prompt:IsA("ProximityPrompt") then
			return
		end
		refresh(prompt)
		prompt.AttributeChanged:Connect(function()
			refresh(prompt)
		end)
		prompt.Destroying:Connect(function()
			inSight[prompt] = nil
		end)
	end

	-- Cette méthode permet de retester la vue des invites PromptSight proches lorsque le personnage bouge ; seules
	-- celles dont le résultat change sont rafraîchies.
	local function updateSight()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local checking = root ~= nil and player:GetAttribute(LA.LightRole) ~= nil
		for _, prompt in CollectionService:GetTagged(LA.PromptTag) do
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
