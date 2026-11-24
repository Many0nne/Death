-- Invites d'action de la lumière (client) : n'active, pour le joueur local, que les invites de son rôle (attribut
-- LightRole) quand l'action est possible (PromptAvailable). Le serveur ne touche jamais Enabled et revérifie tout.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightAttributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LightAttributes"))

local LA = LightAttributes

local LightPrompts = {}

-- Cette méthode permet de démarrer le filtrage des invites lorsque le client se lance.
function LightPrompts.start()
	local player = Players.LocalPlayer

	-- Cette méthode permet d'activer ou non une invite pour le joueur local lorsque son rôle ou l'action change.
	local function refresh(prompt: ProximityPrompt)
		prompt.Enabled = prompt:GetAttribute(LA.PromptAvailable) == true
			and player:GetAttribute(LA.LightRole) ~= nil
			and prompt:GetAttribute(LA.PromptRole) == player:GetAttribute(LA.LightRole)
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
end

return LightPrompts
