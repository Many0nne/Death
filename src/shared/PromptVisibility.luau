-- Règle pure de visibilité d'une invite (ProximityPrompt) pour le joueur local (#18, #19), testable sous Lune.
-- Le client (Client.LightPrompts) l'applique à chaque invite taguée LightAttributes.PromptTag ; le serveur crée ces
-- invites avec Enabled = false et ne réécrit jamais Enabled (il revérifie toute action à son niveau).
local Match = require(script.Parent.Match)

local PromptVisibility = {}

-- Exigences d'une invite, lues sur ses attributs : `role` (PromptRole, nil = tous), `state` (PromptState : état de
-- mortel requis, nil = aucun), `available` (PromptAvailable : l'action est possible maintenant).
export type Spec = { role: string?, state: string?, available: boolean }

-- Cette méthode permet de savoir si une invite est visible pour un joueur lorsque son rôle ou son état change : rôle
-- connu et conforme, état conforme s'il est exigé, action disponible.
function PromptVisibility.visible(spec: Spec, role: string?, state: string?): boolean
	if role == nil or not spec.available then
		return false
	end
	if spec.role ~= nil and spec.role ~= role then
		return false
	end
	return spec.state == nil or spec.state == state
end

-- Cette méthode permet de savoir si un joueur peut réinitialiser son personnage lorsque le client règle le bouton
-- « Reset » : hors manche (pas de rôle) ou spectateur (mortel mort ou sauvé), jamais pour un participant en jeu.
function PromptVisibility.canReset(role: string?, state: string?): boolean
	if role == nil then
		return true
	end
	return role == Match.Role.Mortal and state ~= nil and Match.isResolved(state)
end

return PromptVisibility
