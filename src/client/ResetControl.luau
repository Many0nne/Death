-- Reset du personnage (client, #17) : le bouton « Reset Character » de Roblox est désactivé pendant une manche pour un
-- participant en jeu (téléportation à l'apparition, comportements étranges avec l'agonie et le fauchage), et reste
-- disponible en attente ou en spectateur (Shared.PromptVisibility.canReset, règle pure testée).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))
local PromptVisibility = require(Shared:WaitForChild("PromptVisibility"))

-- Nombre d'essais de SetCore au chargement : le coeur de l'interface Roblox n'est pas toujours prêt tout de suite
local SETCORE_TRIES = 20
local SETCORE_RETRY_DELAY = 0.5

local ResetControl = {}

-- Cette méthode permet de démarrer le contrôle du reset lorsque le client se lance : réglé selon le rôle et l'état du
-- joueur local, puis à chaque changement.
function ResetControl.start()
	local player = Players.LocalPlayer

	-- Cette méthode permet d'appliquer le réglage du bouton lorsque le rôle ou l'état change ; réessaie si le coeur de
	-- l'interface n'est pas prêt (SetCore échoue avant son chargement).
	local function apply()
		local allowed = PromptVisibility.canReset(
			player:GetAttribute(MatchAttributes.Role),
			player:GetAttribute(MatchAttributes.MortalState)
		)
		for _ = 1, SETCORE_TRIES do
			if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", allowed) then
				return
			end
			task.wait(SETCORE_RETRY_DELAY)
		end
		warn("[Reset] bouton de reset non réglable")
	end

	player:GetAttributeChangedSignal(MatchAttributes.Role):Connect(apply)
	player:GetAttributeChangedSignal(MatchAttributes.MortalState):Connect(apply)
	task.spawn(apply)
end

return ResetControl
