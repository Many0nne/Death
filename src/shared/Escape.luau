-- Règles pures de l'objectif de fuite (#7, docs/design.md « Manche ») : objectif collectif du groupe de mortels.
-- 1. Trouver les clés, posées au hasard à chaque manche sur des emplacements de la maison (ancrages KeySpot).
-- 2. Démarrer la voiture du garage, une fois toutes les clés trouvées.
-- 3. Un mortel vivant qui atteint la sortie, voiture démarrée, est sauvé.
-- Sans Instance Roblox (testable sous Lune) ; Server.EscapeService applique ces règles et les réplique par attributs.
local Match = require(script.Parent.Match)

local Escape = {}
Escape.__index = Escape

export type Spot = { id: string, room: string }

-- Cette méthode permet de tirer les emplacements des clés lorsque la manche démarre : `count` emplacements
-- distincts, au plus un par pièce, jamais dans `excludeRoom` (la pièce de la sortie, trop près du but) ; `pick(n)`
-- renvoie un index de 1 à n. Renvoie moins de `count` emplacements s'il n'y a pas assez de pièces.
function Escape.drawKeySpots(spots: { Spot }, count: number, pick: (number) -> number, excludeRoom: string?): { string }
	local pool = {}
	for _, spot in spots do
		if spot.room ~= excludeRoom then
			table.insert(pool, spot)
		end
	end
	-- Tri par identifiant : le tirage ne dépend que de `pick`, pas de l'ordre de CollectionService
	table.sort(pool, function(a, b)
		return a.id < b.id
	end)
	local chosen, usedRooms = {}, {}
	while #chosen < count and #pool > 0 do
		local spot = table.remove(pool, math.clamp(pick(#pool), 1, #pool))
		if not usedRooms[spot.room] then
			usedRooms[spot.room] = true
			table.insert(chosen, spot.id)
		end
	end
	return chosen
end

-- Cette méthode permet de créer l'objectif d'une manche lorsque les clés sont posées sur `keySpots` (identifiants
-- des emplacements tirés) : aucune clé trouvée, voiture à l'arrêt.
function Escape.new(keySpots: { string })
	local keys = {}
	for _, id in keySpots do
		keys[id] = false
	end
	return setmetatable({
		keys = keys,
		keysNeeded = #keySpots,
		keysFound = 0,
		carStarted = false,
	}, Escape)
end

-- Cette méthode permet de savoir si un joueur peut agir sur l'objectif (ramasser, démarrer) lorsqu'il déclenche une
-- action : seulement un mortel vivant (ni la Mort, ni un mortel en agonie, mort ou déjà sauvé).
function Escape.canAct(role: string?, state: string?): boolean
	return role == Match.Role.Mortal and state == Match.MortalState.Alive
end

-- Cette méthode permet de ramasser la clé posée sur l'emplacement `spotId` lorsqu'un mortel la prend ; renvoie
-- (true) ou (false, raison).
function Escape:collectKey(spotId: string): (boolean, string?)
	local found = self.keys[spotId]
	if found == nil then
		return false, "aucune clé sur cet emplacement"
	end
	if found then
		return false, "clé déjà ramassée"
	end
	self.keys[spotId] = true
	self.keysFound += 1
	return true
end

-- Cette méthode permet de savoir si la voiture peut être démarrée lorsque l'action sur la voiture est proposée :
-- toutes les clés trouvées, voiture encore à l'arrêt.
function Escape:canStartCar(): boolean
	return not self.carStarted and self.keysFound >= self.keysNeeded
end

-- Cette méthode permet de démarrer la voiture lorsqu'un mortel termine l'action ; renvoie (true) ou (false, raison).
function Escape:startCar(): (boolean, string?)
	if self.carStarted then
		return false, "voiture déjà démarrée"
	end
	if self.keysFound < self.keysNeeded then
		return false, string.format("il manque des clés (%d/%d)", self.keysFound, self.keysNeeded)
	end
	self.carStarted = true
	return true
end

-- Cette méthode permet de savoir si l'objectif est rempli (voiture démarrée) lorsque la sortie teste un mortel.
function Escape:isComplete(): boolean
	return self.carStarted
end

-- Cette méthode permet de savoir si un mortel qui se tient sur la sortie est sauvé lorsque la sortie le détecte :
-- objectif rempli et mortel vivant (un mortel en agonie doit d'abord être ranimé).
function Escape:canEscape(role: string?, state: string?): boolean
	return self:isComplete() and Escape.canAct(role, state)
end

-- Cette méthode permet de savoir si une position est sur la sortie lorsque le serveur surveille les mortels :
-- à moins de `radius` studs à l'horizontale du centre de la sortie, et à moins de `height` studs au-dessus du sol.
function Escape.isAtExit(position: Vector3, exitPosition: Vector3, radius: number, height: number): boolean
	local dx, dz = position.X - exitPosition.X, position.Z - exitPosition.Z
	local dy = position.Y - exitPosition.Y
	return dx * dx + dz * dz <= radius * radius and dy >= -1 and dy <= height
end

return Escape
