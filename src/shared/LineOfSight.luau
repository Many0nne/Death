-- Vue dégagée entre deux points (rayon), partagée par le serveur (contrôle d'une action) et le client (affichage de
-- l'invite) pour qu'ils tranchent pareil. Les lampes et les volumes de pièce ne répondent pas aux rayons
-- (Server.HouseBuilder) ; les personnages et les blocs invisibles (ancrages) sont traversés.
-- Pourquoi pas ProximityPrompt.RequiresLineOfSight : Roblox teste la vue depuis la caméra, qui, placée derrière le
-- personnage, perd une lampe de plafond dès qu'elle passe sous un linteau de porte (mesuré en jeu).
local Players = game:GetService("Players")

local LineOfSight = {}

-- Nombre maximal de blocs invisibles traversés par un même rayon
local MAX_SKIPS = 8

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
	-- Volume invisible d'un meuble habillé (étagère piège, #5) : ses blocs visibles, frères dans le modèle, font partie de
	-- la cible
	local parent = target and target.Parent
	if parent and parent:IsA("Model") and parent.PrimaryPart == target then
		target = parent
	end
	local ignore = LineOfSight.characters()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 0, MAX_SKIPS do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(from, to - from, params)
		-- IsDescendantOf ne compte pas la cible elle-même (mesuré en jeu : le disjoncteur était jugé caché)
		if hit == nil or (target ~= nil and (hit.Instance == target or hit.Instance:IsDescendantOf(target))) then
			return true
		end
		-- Un ancrage invisible (apparition, carrelage mouillé) ne cache rien : on relance le rayon sans lui
		if hit.Instance.Transparency < 1 then
			return false
		end
		table.insert(ignore, hit.Instance)
	end
	return false
end

return LineOfSight
