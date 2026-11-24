-- Règle d'éclairage (docs/design.md « Lumière ») : « est-ce éclairé ici ? » selon les lampes allumées. Logique pure
-- (aucun service Roblox), partagée par la Mort (#4), les pièges (#5) et la lampe torche (#8).
--
-- Règle : un point est éclairé s'il est dans le volume d'une pièce et à moins de `reach` d'une lampe allumée de cette
-- même pièce (les murs et les dalles arrêtent la lumière ; elle déborde seulement sur la moitié du seuil de porte de
-- son côté, voir THRESHOLD). `reach` vaut
-- REACH_FACTOR fois la portée (Range) de la PointLight : au-delà, son apport ne domine plus la lumière ambiante.
-- Une lampe est allumée si son aile a du courant (disjoncteur) et si elle n'est pas grillée.
local MapTags = require(script.Parent.MapTags)

local Attr = MapTags.Attributes

export type Room = { id: string, wingId: string, min: Vector3, max: Vector3 }
export type Lamp = { id: string, roomId: string, wingId: string, position: Vector3, reach: number }

local Illumination = {}
Illumination.__index = Illumination

-- Part de la portée d'une PointLight qui compte comme « éclairé » (réglage de départ, à ajuster en test)
Illumination.REACH_FACTOR = 0.8
-- Débord horizontal des volumes de pièce lus sur la maison : un mur posé par chaque pièce fait 0,5 stud
-- (HouseLayout.WALL), donc deux pièces voisines se rejoignent au milieu du mur et un seuil de porte appartient à
-- la pièce de son côté (la lumière d'une pièce éclairée tombe sur sa moitié de seuil)
Illumination.THRESHOLD = 0.5

-- Cette méthode permet de créer le modèle d'éclairage d'une maison lorsque le serveur ou un test connaît ses pièces et
-- ses lampes ; toutes les ailes ont du courant et aucune lampe n'est grillée.
function Illumination.new(rooms: { Room }, lamps: { Lamp })
	local self = setmetatable({
		rooms = {} :: { [string]: Room },
		roomOrder = {} :: { string },
		lamps = {} :: { [string]: Lamp },
		lampOrder = {} :: { string },
		roomLamps = {} :: { [string]: { Lamp } },
		wingSet = {} :: { [string]: boolean },
		unpowered = {} :: { [string]: boolean },
		burnt = {} :: { [string]: boolean },
	}, Illumination)
	for _, room in rooms do
		if self.rooms[room.id] then
			error("Illumination : pièce en double " .. room.id)
		end
		self.rooms[room.id] = room
		table.insert(self.roomOrder, room.id)
		self.roomLamps[room.id] = {}
		self.wingSet[room.wingId] = true
	end
	for _, lamp in lamps do
		if not self.rooms[lamp.roomId] then
			error(string.format("Illumination : lampe %s dans une pièce inconnue %s", lamp.id, tostring(lamp.roomId)))
		end
		if self.lamps[lamp.id] then
			error("Illumination : lampe en double " .. lamp.id)
		end
		self.lamps[lamp.id] = lamp
		table.insert(self.lampOrder, lamp.id)
		table.insert(self.roomLamps[lamp.roomId], lamp)
		self.wingSet[lamp.wingId] = true
	end
	return self
end

-- Cette méthode permet de lire pièces et lampes sur la maison construite (tags MapTags.Room et MapTags.Lamp) lorsque
-- le serveur démarre ; `reachFactor` remplace REACH_FACTOR (tests).
function Illumination.fromHouse(house: Instance, reachFactor: number?)
	local factor = reachFactor or Illumination.REACH_FACTOR
	local margin = Vector3.new(Illumination.THRESHOLD, 0, Illumination.THRESHOLD)
	local rooms, lamps = {}, {}
	for _, part in house:GetDescendants() do
		if part:IsA("BasePart") then
			local center = part.CFrame.Position
			if part:HasTag(MapTags.Room) then
				table.insert(rooms, {
					id = part:GetAttribute(Attr.RoomId),
					wingId = part:GetAttribute(Attr.WingId),
					min = center - part.Size / 2 - margin,
					max = center + part.Size / 2 + margin,
				})
			elseif part:HasTag(MapTags.Lamp) then
				local light = part:FindFirstChild("Light")
				local range = if light and light:IsA("PointLight") then light.Range else 0
				table.insert(lamps, {
					id = part:GetAttribute(Attr.LampId),
					roomId = part:GetAttribute(Attr.RoomId),
					wingId = part:GetAttribute(Attr.WingId),
					position = center,
					reach = range * factor,
				})
			end
		end
	end
	-- Ordre stable (GetDescendants ne le garantit pas) : listes et messages reproductibles
	table.sort(rooms, function(a, b)
		return a.id < b.id
	end)
	table.sort(lamps, function(a, b)
		return a.id < b.id
	end)
	return Illumination.new(rooms, lamps)
end

-- Lecture --------------------------------------------------------------------------------------------------------

-- Cette méthode permet de trouver la pièce qui contient un point lorsque l'on teste l'éclairage ou la position de la
-- Mort (nil dehors ; au milieu d'un seuil, la première des deux pièces).
function Illumination:roomAt(position: Vector3): string?
	for _, id in self.roomOrder do
		if self:_contains(id, position) then
			return id
		end
	end
	return nil
end

-- Cette méthode permet de savoir si un point est dans le volume d'une pièce lorsque l'on cherche les pièces qui
-- l'éclairent (un point au milieu d'un mur touche les deux pièces).
function Illumination:_contains(roomId: string, position: Vector3): boolean
	local room = self.rooms[roomId]
	local lo, hi = room.min, room.max
	return position.X >= lo.X
		and position.X <= hi.X
		and position.Y >= lo.Y
		and position.Y <= hi.Y
		and position.Z >= lo.Z
		and position.Z <= hi.Z
end

-- Cette méthode permet de savoir si une lampe éclaire lorsque l'on applique le disjoncteur et les ampoules grillées.
function Illumination:isLampOn(lampId: string): boolean
	local lamp = self.lamps[lampId]
	return lamp ~= nil and not self.unpowered[lamp.wingId] and not self.burnt[lampId]
end

-- Cette méthode permet de savoir si un point est éclairé lorsque la Mort s'y trouve (silhouette, vitesse), qu'un piège
-- veut y être préparé ou qu'un système teste la lumière ; renvoie aussi la lampe qui l'éclaire.
function Illumination:isLit(position: Vector3): (boolean, string?)
	for _, roomId in self.roomOrder do
		if self:_contains(roomId, position) then
			for _, lamp in self.roomLamps[roomId] do
				if self:isLampOn(lamp.id) and (position - lamp.position).Magnitude <= lamp.reach then
					return true, lamp.id
				end
			end
		end
	end
	return false, nil
end

-- Cette méthode permet de savoir si une pièce a au moins une lampe allumée lorsque l'on raisonne par pièce (ampoule à
-- griller, fauchage dans une pièce éclairée).
function Illumination:isRoomLit(roomId: string): boolean
	for _, lamp in self.roomLamps[roomId] or {} do
		if self:isLampOn(lamp.id) then
			return true
		end
	end
	return false
end

-- Cette méthode permet de savoir si une aile existe lorsque le disjoncteur reçoit une demande.
function Illumination:hasWing(wingId: string): boolean
	return self.wingSet[wingId] == true
end

-- Cette méthode permet de savoir si une aile a du courant lorsque l'on affiche ou applique le disjoncteur.
function Illumination:isWingPowered(wingId: string): boolean
	return not self.unpowered[wingId]
end

-- Cette méthode permet de lister les lampes d'une pièce lorsque l'on grille ses ampoules ou affiche ses actions.
function Illumination:lampsOfRoom(roomId: string): { Lamp }
	return table.clone(self.roomLamps[roomId] or {})
end

-- Cette méthode permet de lister les lampes dans un ordre stable lorsque le serveur applique leur état aux instances.
function Illumination:allLamps(): { Lamp }
	local list = {}
	for _, id in self.lampOrder do
		table.insert(list, self.lamps[id])
	end
	return list
end

-- Cette méthode permet de lire une pièce par identifiant lorsque l'on a besoin de son aile ou de son volume.
function Illumination:getRoom(roomId: string): Room?
	return self.rooms[roomId]
end

-- Changements d'état ---------------------------------------------------------------------------------------------

-- Cette méthode permet de couper ou rétablir le courant d'une aile lorsque le disjoncteur est actionné ; renvoie true
-- si l'état a changé.
function Illumination:setWingPowered(wingId: string, powered: boolean): boolean
	if not self.wingSet[wingId] then
		error("Illumination : aile inconnue " .. tostring(wingId))
	end
	local wasPowered = not self.unpowered[wingId]
	self.unpowered[wingId] = if powered then nil else true
	return wasPowered ~= powered
end

-- Cette méthode permet de griller toutes les ampoules d'une pièce lorsque la Mort la plonge dans le noir ; renvoie les
-- lampes qui viennent de griller (définitif jusqu'à la remise à zéro de la manche).
function Illumination:burnRoom(roomId: string): { string }
	local burnt = {}
	for _, lamp in self.roomLamps[roomId] or {} do
		if not self.burnt[lamp.id] then
			self.burnt[lamp.id] = true
			table.insert(burnt, lamp.id)
		end
	end
	return burnt
end

-- Cette méthode permet de rallumer toute la maison lorsqu'une manche commence ou se termine.
function Illumination:reset()
	table.clear(self.unpowered)
	table.clear(self.burnt)
end

return Illumination
