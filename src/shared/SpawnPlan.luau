-- Règle pure de l'apparition en début de manche (#11) : chaque mortel sur son propre point d'apparition (ordre tiré
-- au hasard à chaque manche), la Mort sur l'un des siens. Sans Instance Roblox (testable sous Lune) : identifiants =
-- UserId, points = index dans la liste triée des ancrages (Server.MatchSpawner).
local SpawnPlan = {}

export type Placement = { kind: string, index: number }

-- Cette méthode permet de répartir la Mort et les mortels sur les points d'apparition lorsque la manche démarre ;
-- `pick(n)` renvoie un index de 1 à n. Renvoie UserId -> { kind = "Death" | "Mortal", index }, ou nil et la raison
-- s'il manque des points (un mortel par point, jamais deux mortels sur le même).
function SpawnPlan.assign(
	deathId: number,
	mortalIds: { number },
	mortalSpawns: number,
	deathSpawns: number,
	pick: (number) -> number
): ({ [number]: Placement }?, string?)
	if deathSpawns < 1 then
		return nil, "aucun point d'apparition de la Mort"
	end
	if #mortalIds > mortalSpawns then
		return nil, string.format("%d mortels pour %d points d'apparition", #mortalIds, mortalSpawns)
	end
	-- Mélange de Fisher-Yates des points : un mortel ne retombe pas toujours au même endroit
	local spots = {}
	for i = 1, mortalSpawns do
		spots[i] = i
	end
	for i = mortalSpawns, 2, -1 do
		local j = math.clamp(pick(i), 1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local plan: { [number]: Placement } = {}
	for i, id in mortalIds do
		plan[id] = { kind = "Mortal", index = spots[i] }
	end
	plan[deathId] = { kind = "Death", index = math.clamp(pick(deathSpawns), 1, deathSpawns) }
	return plan
end

return SpawnPlan
