-- Vue dégagée entre deux points (rayon), partagée par le serveur (contrôle d'une action) et le client (affichage de
-- l'invite) pour qu'ils tranchent pareil. Les lampes et les volumes de pièce ne répondent pas aux rayons
-- (Server.HouseBuilder) ; les personnages sont ignorés.
-- Pourquoi pas ProximityPrompt.RequiresLineOfSight : Roblox teste la vue depuis la caméra, qui, placée derrière le
-- personnage, perd une lampe de plafond dès qu'elle passe sous un linteau de porte (mesuré en jeu).
local Players = game:GetService("Players")

local LineOfSight = {}

-- Cette méthode permet de lister les personnages des joueurs lorsqu'un rayon doit les traverser.
function LineOfSight.characters(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- Cette méthode permet de savoir si rien du décor ne sépare un personnage de sa cible lorsqu'il vise une lampe ou le
-- disjoncteur ; toucher la cible elle-même (`target`) compte comme une vue dégagée.
function LineOfSight.clear(from: Vector3, to: Vector3, target: Instance?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = LineOfSight.characters()
	local hit = workspace:Raycast(from, to - from, params)
	return hit == nil or (target ~= nil and hit.Instance:IsDescendantOf(target))
end

return LineOfSight
