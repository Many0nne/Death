-- Géométrie pure de la maison : transforme la description (HouseLayout) en blocs placés (centre, taille, tags,
-- attributs) que Server.HouseBuilder n'a plus qu'à instancier, et vérifie la cohérence de la description.
local MapTags = require(script.Parent.MapTags)

local Attr = MapTags.Attributes
local EPS = 1e-6

export type Piece = {
	kind: string,
	name: string,
	room: string?,
	group: string?,
	center: Vector3,
	size: Vector3,
	tags: { string },
	attributes: { [string]: any },
	light: { range: number, brightness: number }?,
}

export type Rect = { u0: number, u1: number, y0: number, y1: number }

local HouseGeometry = {}

-- Réglages des lampes : portée et intensité des PointLight par type de lampe. height = hauteur du centre au-dessus du
-- sol (sinon sous le plafond) ; pole = largeur du poteau posé sous la lampe (lampadaire). Dehors, seules les lampes à
-- hauteur fixe sont permises (pas de plafond).
HouseGeometry.LAMP_STYLES = {
	Ceiling = { size = Vector3.new(2, 0.4, 2), range = 18, brightness = 1.2 },
	Chandelier = { size = Vector3.new(3, 1.5, 3), height = 8.5, range = 22, brightness = 1.5 },
	-- Applique (porche, façade) : au-dessus d'une porte, à un demi-mur de la façade (bord du volume de la zone)
	Wall = { size = Vector3.new(1.2, 1.2, 1.2), height = 8.5, range = 16, brightness = 1.3 },
	-- Lampadaire (rue, jardin) : tête sur un poteau
	Post = { size = Vector3.new(1.6, 1.2, 1.6), height = 9.5, range = 24, brightness = 1.5, pole = 0.6 },
}

-- Hauteur qu'un personnage atteint en sautant depuis un meuble (saut Roblox ≈ 7,2 studs, plus une marge) : dehors, un
-- meuble ne doit pas servir de marchepied par-dessus la clôture ou sur un toit.
HouseGeometry.JUMP_REACH = 7.5

-- Cette méthode permet de donner la hauteur du sol d'un niveau lorsque l'on place une pièce, une porte ou un meuble.
function HouseGeometry.floorY(layout, level: number): number
	return level * layout.LEVEL_HEIGHT
end

-- Cette méthode permet de donner la hauteur du plafond (dessous de la dalle) d'une pièce lorsqu'elle couvre un ou
-- plusieurs niveaux.
function HouseGeometry.topY(layout, room): number
	return HouseGeometry.floorY(layout, room.level) + (room.levels or 1) * layout.LEVEL_HEIGHT - layout.SLAB
end

-- Cette méthode permet de savoir si une pièce occupe un niveau lorsqu'elle peut traverser plusieurs étages.
function HouseGeometry.spansLevel(room, level: number): boolean
	return level >= room.level and level < room.level + (room.levels or 1)
end

-- Cette méthode permet de retrouver les pièces par identifiant lorsque portes, lampes et meubles les référencent.
function HouseGeometry.roomsById(layout): { [string]: any }
	local byId = {}
	for _, room in layout.rooms do
		byId[room.id] = room
	end
	return byId
end

-- Cette méthode permet de savoir si une zone extérieure est close par une clôture d'un côté lorsque l'on construit
-- ses limites ou que l'on cherche ses passages vers les zones voisines.
local function fenced(room, side: string): boolean
	return room.outdoor == true and room.fence ~= nil and table.find(room.fence, side) ~= nil
end

-- Cette méthode permet de savoir si un côté d'une pièce longe une pièce de la maison lorsque l'on retire l'épaisseur
-- de son mur du volume d'une zone extérieure (la lumière du dehors s'arrête au milieu du seuil).
local function touchesIndoor(layout, room, side: string): boolean
	for _, other in layout.rooms do
		if other.outdoor or not (other.level <= room.level and room.level < other.level + (other.levels or 1)) then
			continue
		end
		local alongX = side == "South" or side == "North"
		local line = if side == "South"
			then room.z0
			elseif side == "North" then room.z1
			elseif side == "West" then room.x0
			else room.x1
		local facing = if side == "South"
			then other.z1
			elseif side == "North" then other.z0
			elseif side == "West" then other.x1
			else other.x0
		local a0, a1 = if alongX then room.x0 else room.z0, if alongX then room.x1 else room.z1
		local b0, b1 = if alongX then other.x0 else other.z0, if alongX then other.x1 else other.z1
		if math.abs(line - facing) < EPS and a0 < b1 - EPS and b0 < a1 - EPS then
			return true
		end
	end
	return false
end

-- Cette méthode permet de donner le rectangle intérieur (entre les murs) d'une pièce lorsque l'on y pose un objet ;
-- une zone extérieure ne perd une épaisseur de mur que du côté de ses clôtures et de la maison.
function HouseGeometry.interior(layout, room)
	-- Cette méthode permet de donner le retrait d'un côté lorsqu'il porte un mur ou une clôture.
	local function inset(side: string): number
		local walled = not room.outdoor or fenced(room, side) or touchesIndoor(layout, room, side)
		return if walled then layout.WALL else 0
	end
	return {
		x0 = room.x0 + inset("West"),
		x1 = room.x1 - inset("East"),
		z0 = room.z0 + inset("South"),
		z1 = room.z1 - inset("North"),
	}
end

-- Cette méthode permet de créer un bloc à partir de ses coins lorsque la géométrie raisonne en intervalles.
local function piece(kind: string, name: string, room, minV: Vector3, maxV: Vector3): Piece
	return {
		kind = kind,
		name = name,
		room = room and room.id,
		center = (minV + maxV) / 2,
		size = maxV - minV,
		tags = {},
		attributes = room and { [Attr.RoomId] = room.id } or {},
	}
end

-- Cette méthode permet de lister les quatre murs d'une pièce lorsque l'on y perce les portes ; les murs sud et nord
-- courent sur toute la longueur, ceux d'ouest et d'est s'arrêtent aux angles pour ne pas se chevaucher.
function HouseGeometry.walls(layout, room)
	local w = layout.WALL
	return {
		{ side = "South", along = "X", line = room.z0, inner = room.z0 + w, u0 = room.x0, u1 = room.x1 },
		{ side = "North", along = "X", line = room.z1, inner = room.z1 - w, u0 = room.x0, u1 = room.x1 },
		{ side = "West", along = "Z", line = room.x0, inner = room.x0 + w, u0 = room.z0 + w, u1 = room.z1 - w },
		{ side = "East", along = "Z", line = room.x1, inner = room.x1 - w, u0 = room.z0 + w, u1 = room.z1 - w },
	}
end

-- Cette méthode permet de lister les murs réellement posés (quatre murs d'une pièce, clôtures d'une zone extérieure)
-- lorsque l'on construit la maison ou cherche ce qui fait face à une porte ; une clôture va d'un coin à l'autre.
function HouseGeometry.builtWalls(layout, room)
	local walls = HouseGeometry.walls(layout, room)
	if not room.outdoor then
		return walls
	end
	local w = layout.WALL
	local built = {}
	for _, wall in walls do
		if fenced(room, wall.side) then
			if wall.along == "Z" then
				wall.u0 = room.z0 + (if fenced(room, "South") then w else 0)
				wall.u1 = room.z1 - (if fenced(room, "North") then w else 0)
			end
			table.insert(built, wall)
		end
	end
	return built
end

-- Cette méthode permet de donner la hauteur des murs posés par une pièce lorsque l'on les découpe autour des portes :
-- jusqu'au plafond dans la maison, hauteur de clôture dehors.
local function wallTop(layout, room): number
	if room.outdoor then
		return HouseGeometry.floorY(layout, room.level) + layout.FENCE_HEIGHT
	end
	return HouseGeometry.topY(layout, room)
end

export type Link = { a: string, b: string, length: number, along: string, line: number, u0: number, u1: number }

-- Cette méthode permet de lister les passages libres entre zones extérieures voisines lorsque l'on parcourt la carte :
-- deux zones qui partagent un bord d'au moins une largeur de porte, sans clôture de part ni d'autre, sont reliées.
function HouseGeometry.outdoorLinks(layout): { Link }
	local links = {}
	local outdoor = {}
	for _, room in layout.rooms do
		if room.outdoor then
			table.insert(outdoor, room)
		end
	end
	for i, a in outdoor do
		for j = i + 1, #outdoor do
			local b = outdoor[j]
			if a.level ~= b.level then
				continue
			end
			-- Bord commun : côté de a, côté de b, ligne du bord et segment partagé (u le long du bord)
			local sideA, sideB, along, line, u0, u1 = nil, nil, "X", 0, 0, 0
			if math.abs(a.x1 - b.x0) < EPS or math.abs(b.x1 - a.x0) < EPS then
				sideA = if math.abs(a.x1 - b.x0) < EPS then "East" else "West"
				sideB = if sideA == "East" then "West" else "East"
				along, line = "Z", if sideA == "East" then a.x1 else a.x0
				u0, u1 = math.max(a.z0, b.z0), math.min(a.z1, b.z1)
			elseif math.abs(a.z1 - b.z0) < EPS or math.abs(b.z1 - a.z0) < EPS then
				sideA = if math.abs(a.z1 - b.z0) < EPS then "North" else "South"
				sideB = if sideA == "North" then "South" else "North"
				along, line = "X", if sideA == "North" then a.z1 else a.z0
				u0, u1 = math.max(a.x0, b.x0), math.min(a.x1, b.x1)
			end
			local length = u1 - u0
			if
				sideA
				and length >= layout.DOOR_WIDTH - EPS
				and not fenced(a, sideA)
				and not fenced(b, sideB :: string)
			then
				table.insert(
					links,
					{ a = a.id, b = b.id, length = length, along = along, line = line, u0 = u0, u1 = u1 }
				)
			end
		end
	end
	return links
end

-- Cette méthode permet de donner l'ouverture d'une porte dans le repère d'un mur (u le long du mur, y vertical)
-- lorsque la porte est percée dans ce mur.
function HouseGeometry.doorOpening(layout, door): Rect
	local half = (door.width or layout.DOOR_WIDTH) / 2
	local u = if door.along == "X" then door.x else door.z
	local y0 = HouseGeometry.floorY(layout, door.level)
	return { u0 = u - half, u1 = u + half, y0 = y0, y1 = y0 + (door.height or layout.DOOR_HEIGHT) }
end

-- Cette méthode permet de savoir si une porte est percée dans un mur donné lorsque l'on découpe les murs d'une pièce.
local function doorOnWall(door, wall): boolean
	local line = if door.along == "X" then door.z else door.x
	return door.along == wall.along and math.abs(line - wall.line) < EPS
end

-- Cette méthode permet de découper un mur en colonnes pleines autour de ses portes lorsqu'elles le percent ; deux
-- ouvertures qui se chevauchent le long du mur (même superposées sur deux niveaux) sont signalées comme erreur.
function HouseGeometry.splitWall(
	u0: number,
	u1: number,
	y0: number,
	y1: number,
	openings: { Rect }
): ({ Rect }, string?)
	local sorted = table.clone(openings)
	table.sort(sorted, function(a, b)
		return a.u0 < b.u0
	end)
	local rects: { Rect } = {}
	local cursor = u0
	local problem = nil
	for _, o in sorted do
		if o.u0 < cursor - EPS then
			problem = string.format("ouvertures qui se chevauchent vers u = %.2f", o.u0)
		end
		if o.u0 > cursor + EPS then
			table.insert(rects, { u0 = cursor, u1 = o.u0, y0 = y0, y1 = y1 })
		end
		if o.y0 > y0 + EPS then
			table.insert(rects, { u0 = o.u0, u1 = o.u1, y0 = y0, y1 = o.y0 })
		end
		if o.y1 < y1 - EPS then
			table.insert(rects, { u0 = o.u0, u1 = o.u1, y0 = o.y1, y1 = y1 })
		end
		cursor = math.max(cursor, o.u1)
	end
	if cursor < u1 - EPS then
		table.insert(rects, { u0 = cursor, u1 = u1, y0 = y0, y1 = y1 })
	end
	return rects, problem
end

-- Cette méthode permet de construire un bloc dans l'épaisseur d'un mur lorsque l'on connaît son rectangle (u, y).
local function wallPiece(kind: string, name: string, room, wall, r: Rect): Piece
	local a, b = math.min(wall.line, wall.inner), math.max(wall.line, wall.inner)
	if wall.along == "X" then
		return piece(kind, name, room, Vector3.new(r.u0, r.y0, a), Vector3.new(r.u1, r.y1, b))
	end
	return piece(kind, name, room, Vector3.new(a, r.y0, r.u0), Vector3.new(b, r.y1, r.u1))
end

-- Cette méthode permet de calculer les couloirs des deux volées d'une cage d'escalier lorsque la cage s'ouvre au sud :
-- volée basse à l'ouest (porte du bas), volée haute à l'est (porte du haut), en x monde.
function HouseGeometry.stairLanes(layout, room)
	local inner = HouseGeometry.interior(layout, room)
	local laneWidth = (inner.x1 - inner.x0 - layout.LANE_GAP) / 2
	local flightRise = layout.LEVEL_HEIGHT / 2
	local steps = math.floor(flightRise / layout.STEP_RISE + 0.5) - 1
	local flight = steps * layout.STEP_DEPTH
	local depth = inner.z1 - inner.z0
	return {
		low = { inner.x0, inner.x0 + laneWidth },
		high = { inner.x1 - laneWidth, inner.x1 },
		steps = steps,
		flightRise = flightRise,
		flight = flight,
		depth = depth,
		-- profondeur libre devant la volée basse, égale à celle du palier haut
		entry = depth - flight - layout.HALF_LANDING,
	}
end

-- Cette méthode permet de produire les marches, paliers et la cloison d'un escalier tournant lorsque la pièce est une
-- cage d'escalier ; tous les blocs partent du sol de la cage (aucun recoin où se coincer sous les marches).
local function stairPieces(layout, room, out: { Piece })
	local lanes = HouseGeometry.stairLanes(layout, room)
	local inner = HouseGeometry.interior(layout, room)
	local base = HouseGeometry.floorY(layout, room.level)
	local d, rise = layout.STEP_DEPTH, layout.STEP_RISE
	local z0 = inner.z0 + lanes.entry
	-- Cette méthode permet d'ajouter un bloc plein posé sur le sol de la cage lorsque l'on empile marches et paliers.
	local function add(kind, name, x0, x1, za, zb, height)
		table.insert(
			out,
			piece(kind, room.id .. name, room, Vector3.new(x0, base, za), Vector3.new(x1, base + height, zb))
		)
	end
	for k = 1, lanes.steps do
		add("Step", "StepLow" .. k, lanes.low[1], lanes.low[2], z0 + (k - 1) * d, z0 + k * d, k * rise)
	end
	add("Landing", "HalfLanding", inner.x0, inner.x1, z0 + lanes.flight, inner.z1, lanes.flightRise)
	for j = 1, lanes.steps do
		local zb = z0 + (lanes.steps - j + 1) * d
		add("Step", "StepHigh" .. j, lanes.high[1], lanes.high[2], zb - d, zb, lanes.flightRise + j * rise)
	end
	add("Landing", "TopLanding", lanes.high[1], lanes.high[2], inner.z0, z0, layout.LEVEL_HEIGHT)
	add(
		"Partition",
		"Partition",
		lanes.low[2],
		lanes.high[1],
		inner.z0,
		z0 + lanes.flight,
		layout.LEVEL_HEIGHT + layout.RAILING
	)
end

-- Cette méthode permet de produire sol, plafond, murs percés, volume de pièce et escalier d'une pièce lorsque l'on
-- construit la maison ; une zone extérieure n'a ni plafond ni murs, seulement son terrain et ses clôtures.
local function roomPieces(layout, room, out: { Piece }, problems: { string })
	local base = HouseGeometry.floorY(layout, room.level)
	local top = HouseGeometry.topY(layout, room)
	table.insert(
		out,
		piece(
			if room.outdoor then "Ground" else "Floor",
			room.id .. "Floor",
			room,
			Vector3.new(room.x0, base - layout.SLAB, room.z0),
			Vector3.new(room.x1, base, room.z1)
		)
	)
	if room.roof then
		table.insert(
			out,
			piece(
				"Ceiling",
				room.id .. "Ceiling",
				room,
				Vector3.new(room.x0, top, room.z0),
				Vector3.new(room.x1, top + layout.SLAB, room.z1)
			)
		)
	end
	local wallKind = if room.outdoor then "Fence" else "Wall"
	for _, wall in HouseGeometry.builtWalls(layout, room) do
		local openings = {}
		for _, door in layout.doors do
			if table.find(door.rooms, room.id) and doorOnWall(door, wall) then
				local opening = HouseGeometry.doorOpening(layout, door)
				table.insert(openings, opening)
				if door.leaf then
					local leaf = wallPiece("DoorLeaf", door.id, room, wall, opening)
					table.insert(leaf.tags, door.leaf)
					leaf.attributes[Attr.DoorId] = door.id
					table.insert(out, leaf)
				end
			end
		end
		local rects, problem = HouseGeometry.splitWall(wall.u0, wall.u1, base, wallTop(layout, room), openings)
		if problem then
			table.insert(problems, string.format("%s, mur %s : %s", room.id, wall.side, problem))
		end
		for i, r in rects do
			local name = string.format("%s%s%s%d", room.id, wallKind, wall.side, i)
			table.insert(out, wallPiece(wallKind, name, room, wall, r))
		end
	end
	local inner = HouseGeometry.interior(layout, room)
	local zone =
		piece("Zone", room.id, room, Vector3.new(inner.x0, base, inner.z0), Vector3.new(inner.x1, top, inner.z1))
	table.insert(zone.tags, MapTags.Room)
	zone.attributes[Attr.RoomName] = room.name
	zone.attributes[Attr.WingId] = room.wing
	zone.attributes[Attr.Level] = room.level
	zone.attributes[Attr.Dark] = not room.lit
	zone.attributes[Attr.Outdoor] = room.outdoor == true
	table.insert(out, zone)
	if room.stairs then
		stairPieces(layout, room, out)
	end
end

-- Cette méthode permet de produire une lampe (bloc néon et sa lumière) lorsque la pièce est éclairée ; le lustre est en
-- plus un candidat de piège.
local function lampPiece(layout, room, lamp): Piece
	local style = HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"]
	local base = HouseGeometry.floorY(layout, room.level)
	local centerY = if style.height then base + style.height else HouseGeometry.topY(layout, room) - style.size.Y / 2
	local center = Vector3.new(lamp.x, centerY, lamp.z)
	local p = piece("Lamp", lamp.id, room, center - style.size / 2, center + style.size / 2)
	p.light = { range = style.range, brightness = style.brightness }
	p.tags = { MapTags.Lamp, MapTags.wingLamps(room.wing), MapTags.roomLamps(room.id) }
	p.attributes[Attr.LampId] = lamp.id
	p.attributes[Attr.WingId] = room.wing
	if lamp.kind == "Chandelier" then
		table.insert(p.tags, MapTags.TrapCandidate)
		table.insert(p.tags, MapTags.trapKind(MapTags.TrapKinds.Chandelier))
		p.attributes[Attr.TrapKind] = MapTags.TrapKinds.Chandelier
	end
	return p
end

-- Cette méthode permet de produire un ancrage invisible posé au sol (ou sur un meuble) lorsque la suite du jeu doit
-- retrouver un emplacement par son tag.
local function anchorPiece(id: string, room, x: number, y: number, z: number, size: Vector3, tags: { string }): Piece
	local minV = Vector3.new(x - size.X / 2, y, z - size.Z / 2)
	local p = piece("Anchor", id, room, minV, minV + size)
	p.tags = tags
	p.attributes[Attr.AnchorId] = id
	return p
end

local ANCHOR_SIZE = Vector3.new(2, 0.2, 2)
local WET_FLOOR_SIZE = Vector3.new(4, 0.2, 4)

-- Cette méthode permet de produire un meuble et, s'il porte des clés, l'emplacement posé dessus lorsque l'on meuble
-- une pièce.
local function propPieces(layout, room, prop, out: { Piece })
	local base = HouseGeometry.floorY(layout, room.level) + (prop.y or 0)
	local sx, sy, sz = prop.size[1], prop.size[2], prop.size[3]
	local p = piece(
		"Prop",
		prop.id,
		room,
		Vector3.new(prop.x - sx / 2, base, prop.z - sz / 2),
		Vector3.new(prop.x + sx / 2, base + sy, prop.z + sz / 2)
	)
	if prop.trap then
		p.tags = { MapTags.TrapCandidate, MapTags.trapKind(prop.trap) }
		p.attributes[Attr.TrapKind] = prop.trap
	end
	if prop.tag then
		table.insert(p.tags, MapTags[prop.tag])
	end
	table.insert(out, p)
	if prop.keySpot then
		table.insert(
			out,
			anchorPiece(prop.id .. "KeySpot", room, prop.x, base + sy, prop.z, ANCHOR_SIZE, { MapTags.KeySpot })
		)
	end
end

local ANCHOR_TAGS = {
	MortalSpawn = { MapTags.MortalSpawn },
	DeathSpawn = { MapTags.DeathSpawn },
	WetFloor = { MapTags.TrapCandidate, MapTags.trapKind(MapTags.TrapKinds.WetFloor) },
	Exit = { MapTags.Exit },
}

-- Cette méthode permet de produire la voiture de fuite en blocs (caisse, habitacle, roues) lorsque le garage est
-- construit ; capot vers l'est.
local function carPieces(layout, room, car, out: { Piece })
	local base = HouseGeometry.floorY(layout, room.level)
	-- Cette méthode permet d'ajouter un bloc de la voiture lorsque l'on donne sa position relative au centre au sol.
	local function add(name, cx, cy, cz, sx, sy, sz)
		local c = Vector3.new(car.x + cx, base + cy, car.z + cz)
		local s = Vector3.new(sx, sy, sz)
		local p = piece("Car", name, room, c - s / 2, c + s / 2)
		p.group = car.id
		table.insert(out, p)
	end
	add("Body", 0, 2.25, 0, 12, 2.5, 6)
	add("Cabin", -1, 4.75, 0, 6, 2.5, 5.5)
	for i, offset in { { 4, -3.25 }, { 4, 3.25 }, { -4, -3.25 }, { -4, 3.25 } } do
		add("Wheel" .. i, offset[1], 1.25, offset[2], 2.5, 2.5, 1)
	end
end

-- Cette méthode permet de calculer tous les blocs de la maison lorsque le serveur la construit ou qu'un test la vérifie ;
-- groups décrit les modèles (voiture) et problems liste les incohérences relevées en chemin.
function HouseGeometry.build(layout)
	local byId = HouseGeometry.roomsById(layout)
	local pieces: { Piece } = {}
	local problems: { string } = {}
	for _, room in layout.rooms do
		roomPieces(layout, room, pieces, problems)
	end
	for _, lamp in layout.lamps do
		local room = byId[lamp.room]
		local p = lampPiece(layout, room, lamp)
		table.insert(pieces, p)
		local style = HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"]
		if style.pole then
			-- Poteau plein du sol jusque sous la tête du lampadaire : un meuble comme un autre (collisions, portes)
			local base = HouseGeometry.floorY(layout, room.level)
			local half = style.pole / 2
			local headBottom = p.center.Y - p.size.Y / 2
			table.insert(
				pieces,
				piece(
					"Prop",
					lamp.id .. "Pole",
					room,
					Vector3.new(lamp.x - half, base, lamp.z - half),
					Vector3.new(lamp.x + half, headBottom, lamp.z + half)
				)
			)
		end
	end
	for _, prop in layout.props do
		propPieces(layout, byId[prop.room], prop, pieces)
	end
	for _, anchor in layout.anchors do
		local room = byId[anchor.room]
		local size = if anchor.kind == "WetFloor" then WET_FLOOR_SIZE else ANCHOR_SIZE
		local p = anchorPiece(
			anchor.id,
			room,
			anchor.x,
			HouseGeometry.floorY(layout, room.level),
			anchor.z,
			size,
			table.clone(ANCHOR_TAGS[anchor.kind])
		)
		if anchor.kind == "WetFloor" then
			p.attributes[Attr.TrapKind] = MapTags.TrapKinds.WetFloor
		end
		table.insert(pieces, p)
	end
	local carRoom = byId[layout.car.room]
	carPieces(layout, carRoom, layout.car, pieces)
	for _, s in layout.scenery or {} do
		-- Décor hors de la carte (rue, terrains voisins) : un sol sans pièce, au niveau du terrain
		local y = HouseGeometry.floorY(layout, s.level or 0)
		table.insert(
			pieces,
			piece(s.kind, s.id, nil, Vector3.new(s.x0, y - layout.SLAB, s.z0), Vector3.new(s.x1, y, s.z1))
		)
	end
	if layout.bounds then
		-- Limite invisible autour du terrain, bien plus haute que tout ce qu'on peut escalader (joueurs empilés, toits)
		local b = layout.bounds
		local y0, y1 = HouseGeometry.floorY(layout, 0), HouseGeometry.floorY(layout, 0) + b.height
		local t = layout.WALL * 2
		for name, r in
			{
				West = { b.x0 - t, b.x0, b.z0 - t, b.z1 + t },
				East = { b.x1, b.x1 + t, b.z0 - t, b.z1 + t },
				South = { b.x0, b.x1, b.z0 - t, b.z0 },
				North = { b.x0, b.x1, b.z1, b.z1 + t },
			}
		do
			table.insert(
				pieces,
				piece("Boundary", "Boundary" .. name, nil, Vector3.new(r[1], y0, r[3]), Vector3.new(r[2], y1, r[4]))
			)
		end
	end
	local groups = {
		[layout.car.id] = {
			room = carRoom.id,
			primary = "Body",
			tags = { MapTags.EscapeCar },
			attributes = { [Attr.RoomId] = carRoom.id },
		},
	}
	return { pieces = pieces, groups = groups, problems = problems }
end

-- Cette méthode permet de savoir si deux intervalles ouverts se recouvrent lorsque l'on cherche des chevauchements.
local function overlaps(a0: number, a1: number, b0: number, b1: number): boolean
	return a0 < b1 - EPS and b0 < a1 - EPS
end

-- Cette méthode permet de vérifier qu'un rectangle est entièrement couvert par d'autres lorsque l'on contrôle qu'un
-- plafond absent est bien remplacé par le sol du niveau au-dessus.
function HouseGeometry.covered(rect, covers): boolean
	local xs, zs = { rect.x0, rect.x1 }, { rect.z0, rect.z1 }
	for _, c in covers do
		table.insert(xs, math.clamp(c.x0, rect.x0, rect.x1))
		table.insert(xs, math.clamp(c.x1, rect.x0, rect.x1))
		table.insert(zs, math.clamp(c.z0, rect.z0, rect.z1))
		table.insert(zs, math.clamp(c.z1, rect.z0, rect.z1))
	end
	table.sort(xs)
	table.sort(zs)
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			if xs[i + 1] - xs[i] > EPS and zs[j + 1] - zs[j] > EPS then
				local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
				local hit = false
				for _, c in covers do
					if cx > c.x0 and cx < c.x1 and cz > c.z0 and cz < c.z1 then
						hit = true
						break
					end
				end
				if not hit then
					return false
				end
			end
		end
	end
	return true
end

-- Cette méthode permet de lister les voisins praticables de chaque pièce (portes sans battant, passages entre zones
-- extérieures) lorsque l'on parcourt la carte ; une voisine reliée deux fois y figure deux fois.
function HouseGeometry.neighbors(layout): { [string]: { string } }
	local graph = {}
	for _, room in layout.rooms do
		graph[room.id] = {}
	end
	-- Cette méthode permet d'ajouter un passage dans les deux sens lorsqu'une porte ou un bord libre relie deux pièces.
	local function link(a: string, b: string)
		if graph[a] and graph[b] then
			table.insert(graph[a], b)
			table.insert(graph[b], a)
		end
	end
	for _, door in layout.doors do
		if #door.rooms == 2 then
			link(door.rooms[1], door.rooms[2])
		end
	end
	for _, l in HouseGeometry.outdoorLinks(layout) do
		link(l.a, l.b)
	end
	return graph
end

-- Cette méthode permet de lister les pièces reliées par une porte intérieure ou un passage extérieur lorsque l'on
-- vérifie qu'on peut aller partout depuis une pièce.
function HouseGeometry.reachableRooms(layout, fromId: string): { [string]: boolean }
	local graph = HouseGeometry.neighbors(layout)
	local seen = { [fromId] = true }
	local queue = { fromId }
	while #queue > 0 do
		local current = table.remove(queue, 1)
		for _, other in graph[current] or {} do
			if not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	return seen
end

-- Cette méthode permet de vérifier une zone extérieure (à ciel ouvert, sur un seul niveau, clôtures sur des côtés
-- connus qui ne la séparent pas d'une autre zone extérieure) lorsque l'on valide la description.
local function checkOutdoorRoom(layout, room, errors: { string })
	if room.roof or (room.levels or 1) ~= 1 or room.stairs then
		table.insert(errors, room.id .. " : une zone extérieure est à ciel ouvert, sur un seul niveau")
	end
	for _, side in room.fence or {} do
		if not table.find({ "South", "North", "West", "East" }, side) then
			table.insert(errors, room.id .. " : côté de clôture inconnu " .. tostring(side))
		end
	end
	for _, other in layout.rooms do
		if other == room or not other.outdoor or other.level ~= room.level then
			continue
		end
		-- Côté de `room` qui touche `other` sur une longueur non nulle
		local touching = nil
		if overlaps(room.z0, room.z1, other.z0, other.z1) then
			if math.abs(room.x1 - other.x0) < EPS then
				touching = "East"
			elseif math.abs(room.x0 - other.x1) < EPS then
				touching = "West"
			end
		elseif overlaps(room.x0, room.x1, other.x0, other.x1) then
			if math.abs(room.z1 - other.z0) < EPS then
				touching = "North"
			elseif math.abs(room.z0 - other.z1) < EPS then
				touching = "South"
			end
		end
		if touching and fenced(room, touching) then
			table.insert(errors, string.format("%s : clôture %s contre la zone %s", room.id, touching, other.id))
		end
	end
	-- Terrain clos : derrière chaque côté sans clôture, tous les 0,5 stud, une autre pièce ou zone (pas le vide)
	for _, wall in HouseGeometry.walls(layout, room) do
		if fenced(room, wall.side) then
			continue
		end
		local outward = if wall.side == "South" or wall.side == "West" then -0.25 else 0.25
		local first, last =
			if wall.along == "X" then room.x0 else room.z0, if wall.along == "X" then room.x1 else room.z1
		for u = first + 0.25, last - 0.25, 0.5 do
			local x = if wall.along == "X" then u else wall.line + outward
			local z = if wall.along == "X" then wall.line + outward else u
			local closed = false
			for _, other in layout.rooms do
				if
					other ~= room
					and HouseGeometry.spansLevel(other, room.level)
					and x > other.x0
					and x < other.x1
					and z > other.z0
					and z < other.z1
				then
					closed = true
					break
				end
			end
			if not closed then
				table.insert(
					errors,
					string.format("%s : bord %s ouvert sur le vide vers (%.2f, %.2f)", room.id, wall.side, x, z)
				)
				break
			end
		end
	end
end

-- Cette méthode permet de vérifier les pièces (taille, chevauchement, plafond, aile) lorsque l'on valide la
-- description.
local function checkRooms(layout, errors: { string })
	local seen = {}
	for _, room in layout.rooms do
		if seen[room.id] then
			table.insert(errors, "pièce en double : " .. room.id)
		end
		seen[room.id] = true
		if not layout.wings[room.wing or ""] then
			table.insert(errors, room.id .. " : aile électrique inconnue " .. tostring(room.wing))
		end
		for level = room.level, room.level + (room.levels or 1) - 1 do
			if not layout.levels[level] then
				table.insert(errors, room.id .. " : niveau inconnu " .. tostring(level))
			end
		end
		if room.x1 - room.x0 < 8 or room.z1 - room.z0 < 8 then
			table.insert(errors, room.id .. " : pièce de moins de 8 studs de côté")
		end
		local above = room.level + (room.levels or 1)
		local covers = {}
		for _, other in layout.rooms do
			if
				other ~= room
				and overlaps(room.x0, room.x1, other.x0, other.x1)
				and overlaps(room.z0, room.z1, other.z0, other.z1)
			then
				for level = room.level, above - 1 do
					if HouseGeometry.spansLevel(other, level) then
						table.insert(
							errors,
							string.format("%s et %s se chevauchent au niveau %d", room.id, other.id, level)
						)
						break
					end
				end
				if other.level == above then
					table.insert(covers, other)
				end
			end
		end
		if room.outdoor then
			checkOutdoorRoom(layout, room, errors)
		elseif room.roof and #covers > 0 then
			table.insert(errors, room.id .. " : plafond posé sous une pièce du niveau au-dessus (dalle en double)")
		elseif not room.roof and not HouseGeometry.covered(room, covers) then
			table.insert(errors, room.id .. " : sans plafond et pas entièrement couverte par le niveau au-dessus")
		end
	end
end

-- Cette méthode permet de vérifier que chaque porte est percée dans un mur des pièces qu'elle relie, à leur niveau et
-- sous leur plafond, lorsque l'on valide la description.
local function checkDoors(layout, byId, errors: { string })
	for _, door in layout.doors do
		if #door.rooms ~= 2 and not (#door.rooms == 1 and door.leaf) then
			table.insert(
				errors,
				door.id .. " : une porte relie deux pièces (ou une pièce et l'extérieur, avec battant)"
			)
		end
		local opening = HouseGeometry.doorOpening(layout, door)
		for _, roomId in door.rooms do
			local room = byId[roomId]
			if not room then
				table.insert(errors, door.id .. " : pièce inconnue " .. tostring(roomId))
				continue
			end
			local onWall = nil
			for _, wall in HouseGeometry.walls(layout, room) do
				if doorOnWall(door, wall) then
					onWall = wall
				end
			end
			if not onWall then
				table.insert(errors, door.id .. " : pas sur un mur de " .. roomId)
			elseif #door.rooms == 1 and room.outdoor and not fenced(room, onWall.side) then
				table.insert(errors, door.id .. " : battant sans clôture autour dans " .. roomId)
			elseif opening.u0 < onWall.u0 + layout.WALL - EPS or opening.u1 > onWall.u1 - layout.WALL + EPS then
				table.insert(errors, door.id .. " : déborde du mur de " .. roomId)
			end
			if not HouseGeometry.spansLevel(room, door.level) then
				table.insert(errors, door.id .. " : niveau absent de " .. roomId)
			elseif opening.y1 > wallTop(layout, room) + EPS then
				table.insert(errors, door.id .. " : plus haute que le mur (ou la clôture) de " .. roomId)
			end
		end
		if #door.rooms == 1 then
			-- Porte extérieure : aucune autre pièce ne doit avoir de mur (ou de clôture) sur la même ligne, en face de
			-- l'ouverture ; une zone extérieure sans clôture de ce côté laisse le passage
			for _, other in layout.rooms do
				if other.id ~= door.rooms[1] and HouseGeometry.spansLevel(other, door.level) then
					for _, wall in HouseGeometry.builtWalls(layout, other) do
						if doorOnWall(door, wall) and overlaps(opening.u0, opening.u1, wall.u0, wall.u1) then
							table.insert(
								errors,
								door.id .. " : porte extérieure sur un mur partagé avec " .. other.id
							)
						end
					end
				end
			end
		end
	end
end

-- Cette méthode permet de vérifier qu'une cage d'escalier a une porte en bas de la volée basse et une en haut de la
-- volée haute lorsque l'on valide la description.
local function checkStairs(layout, errors: { string })
	for _, room in layout.rooms do
		if not room.stairs then
			continue
		end
		if room.stairs ~= "South" or room.levels ~= 2 then
			table.insert(errors, room.id .. " : seule une cage sur deux niveaux ouverte au sud est gérée")
			continue
		end
		local lanes = HouseGeometry.stairLanes(layout, room)
		if lanes.entry < 4 then
			table.insert(errors, room.id .. " : cage trop courte pour ses volées")
		end
		local found = { low = false, high = false }
		for _, door in layout.doors do
			if table.find(door.rooms, room.id) and door.along == "X" and math.abs(door.z - room.z0) < EPS then
				local o = HouseGeometry.doorOpening(layout, door)
				for key, level in { low = room.level, high = room.level + 1 } do
					local lane = lanes[key]
					if door.level == level and o.u0 >= lane[1] - EPS and o.u1 <= lane[2] + EPS then
						found[key] = true
					end
				end
			end
		end
		if not (found.low and found.high) then
			table.insert(
				errors,
				room.id .. " : il faut une porte au sud en bas de la volée basse et en haut de la volée haute"
			)
		end
	end
end

-- Cette méthode permet de savoir si deux blocs du plan se recouvrent lorsque l'on cherche un meuble ou un ancrage mal
-- placé.
local function piecesOverlap(a: Piece, b: Piece): boolean
	local aMin, aMax = a.center - a.size / 2, a.center + a.size / 2
	local bMin, bMax = b.center - b.size / 2, b.center + b.size / 2
	return overlaps(aMin.X, aMax.X, bMin.X, bMax.X)
		and overlaps(aMin.Y, aMax.Y, bMin.Y, bMax.Y)
		and overlaps(aMin.Z, aMax.Z, bMin.Z, bMax.Z)
end

-- Cette méthode permet de vérifier les blocs posés dans les pièces (dedans, sans boucher une porte ni se chevaucher,
-- ancrages au sol hors des meubles) lorsque l'on valide la description.
local function checkFurniture(layout, byId, plan, errors: { string })
	local solids = {}
	local floorAnchors = {}
	for _, p in plan.pieces do
		if p.kind == "Anchor" and not table.find(p.tags, MapTags.KeySpot) then
			table.insert(floorAnchors, p)
		end
		if p.kind ~= "Prop" and p.kind ~= "Car" and p.kind ~= "Lamp" and p.kind ~= "Anchor" then
			continue
		end
		local room = byId[p.room]
		local inner = HouseGeometry.interior(layout, room)
		local minV, maxV = p.center - p.size / 2, p.center + p.size / 2
		local inside = minV.X >= inner.x0 - EPS
			and maxV.X <= inner.x1 + EPS
			and minV.Z >= inner.z0 - EPS
			and maxV.Z <= inner.z1 + EPS
			and minV.Y >= HouseGeometry.floorY(layout, room.level) - EPS
			and maxV.Y <= HouseGeometry.topY(layout, room) + EPS
		if not inside then
			table.insert(errors, p.name .. " : sort de " .. room.id)
		end
		if p.kind ~= "Prop" and p.kind ~= "Car" then
			continue
		end
		for _, door in layout.doors do
			-- Une porte extérieure (un seul côté décrit) se dégage aussi du côté dehors, quelle que soit la zone
			local concerned = table.find(door.rooms, room.id) ~= nil or #door.rooms == 1
			if concerned and HouseGeometry.spansLevel(room, door.level) then
				-- Dégagement : toute la largeur de la porte plus 0,5 stud, sur 3 studs de chaque côté du mur
				local o = HouseGeometry.doorOpening(layout, door)
				local line = if door.along == "X" then door.z else door.x
				local u0, u1 = o.u0 - 0.5, o.u1 + 0.5
				local blocks = if door.along == "X"
					then overlaps(minV.X, maxV.X, u0, u1) and overlaps(minV.Z, maxV.Z, line - 3, line + 3)
					else overlaps(minV.Z, maxV.Z, u0, u1) and overlaps(minV.X, maxV.X, line - 3, line + 3)
				if blocks and overlaps(minV.Y, maxV.Y, o.y0, o.y1) then
					table.insert(errors, p.name .. " : bouche la porte " .. door.id)
				end
			end
		end
		for _, other in solids do
			if not (other.group ~= nil and other.group == p.group) and piecesOverlap(p, other) then
				table.insert(errors, p.name .. " chevauche " .. other.name)
			end
		end
		table.insert(solids, p)
	end
	-- Apparitions, carrelage mouillé et sortie : au sol, hors des meubles (on doit pouvoir s'y tenir)
	for _, anchor in floorAnchors do
		for _, solid in solids do
			if piecesOverlap(anchor, solid) then
				table.insert(errors, anchor.name .. " est dans " .. solid.name)
			end
		end
	end
end

-- Cette méthode permet de vérifier les passages dehors lorsque l'on valide la description : un bord libre entre deux
-- zones garde une largeur de porte sans meuble, et aucun meuble de jardin ne sert de marchepied vers un lampadaire.
local function checkOutdoorPassages(layout, byId, plan, errors: { string })
	local solids = {}
	for _, p in plan.pieces do
		if (p.kind == "Prop" or p.kind == "Car") and byId[p.room].outdoor then
			table.insert(solids, p)
		end
	end
	for _, link in HouseGeometry.outdoorLinks(layout) do
		-- Intervalles bouchés le long du bord, sur 3 studs de part et d'autre
		local blocked = {}
		for _, p in solids do
			if p.room ~= link.a and p.room ~= link.b then
				continue
			end
			local minV, maxV = p.center - p.size / 2, p.center + p.size / 2
			local across0, across1 =
				if link.along == "X" then minV.Z else minV.X, if link.along == "X" then maxV.Z else maxV.X
			if overlaps(across0, across1, link.line - 3, link.line + 3) then
				local a0 = if link.along == "X" then minV.X else minV.Z
				local a1 = if link.along == "X" then maxV.X else maxV.Z
				if overlaps(a0, a1, link.u0, link.u1) then
					table.insert(blocked, { u0 = math.max(a0, link.u0), u1 = math.min(a1, link.u1), y0 = 0, y1 = 1 })
				end
			end
		end
		local free = HouseGeometry.splitWall(link.u0, link.u1, 0, 1, blocked)
		local widest = 0
		for _, r in free do
			if r.y0 == 0 and r.y1 == 1 then
				widest = math.max(widest, r.u1 - r.u0)
			end
		end
		if widest < layout.DOOR_WIDTH - EPS then
			table.insert(errors, string.format("passage %s ↔ %s bouché par un meuble", link.a, link.b))
		end
	end
	for _, lamp in layout.lamps do
		local style = HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"]
		if not (style and style.pole) then
			continue
		end
		local poleTop = HouseGeometry.floorY(layout, byId[lamp.room].level) + style.height - style.size.Y / 2
		for _, p in solids do
			local minV, maxV = p.center - p.size / 2, p.center + p.size / 2
			local dx = math.max(minV.X - lamp.x, lamp.x - maxV.X, 0)
			local dz = math.max(minV.Z - lamp.z, lamp.z - maxV.Z, 0)
			if
				p.name ~= lamp.id .. "Pole"
				and dx * dx + dz * dz < 36
				and maxV.Y + HouseGeometry.JUMP_REACH > poleTop
			then
				table.insert(errors, p.name .. " : marchepied vers le lampadaire " .. lamp.id)
			end
		end
	end
end

-- Cette méthode permet de vérifier les lampes (pièces éclairées seulement, au moins une par pièce éclairée) lorsque
-- l'on valide la description.
local function checkLamps(layout, byId, errors: { string })
	local count = {}
	for _, lamp in layout.lamps do
		local room = byId[lamp.room]
		if not room then
			table.insert(errors, lamp.id .. " : pièce inconnue " .. tostring(lamp.room))
		elseif not room.lit then
			table.insert(errors, lamp.id .. " : lampe dans une zone sombre (" .. room.id .. ")")
		else
			count[room.id] = (count[room.id] or 0) + 1
		end
	end
	for _, room in layout.rooms do
		if room.lit and not count[room.id] then
			table.insert(errors, room.id .. " : pièce éclairée sans lampe")
		end
	end
end

-- Cette méthode permet de vérifier les types (lampe, ancrage, piège, tag de meuble) lorsque l'on valide la
-- description : un type inconnu ferait échouer la construction ou perdrait un tag sans bruit.
local function checkKinds(layout, errors: { string })
	local byId = HouseGeometry.roomsById(layout)
	for _, lamp in layout.lamps do
		local style = HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"]
		if not style then
			table.insert(errors, lamp.id .. " : type de lampe inconnu " .. tostring(lamp.kind))
		elseif byId[lamp.room] and byId[lamp.room].outdoor and not style.height then
			table.insert(errors, lamp.id .. " : lampe de plafond dehors")
		end
	end
	for _, s in layout.scenery or {} do
		if s.kind ~= "Street" and s.kind ~= "Lawn" then
			table.insert(errors, tostring(s.id) .. " : type de décor inconnu " .. tostring(s.kind))
		end
		for _, room in layout.rooms do
			if
				HouseGeometry.spansLevel(room, s.level or 0)
				and overlaps(s.x0, s.x1, room.x0, room.x1)
				and overlaps(s.z0, s.z1, room.z0, room.z1)
			then
				table.insert(errors, tostring(s.id) .. " : décor posé sur la carte (" .. room.id .. ")")
			end
		end
	end
	for _, anchor in layout.anchors do
		if not ANCHOR_TAGS[anchor.kind] then
			table.insert(errors, anchor.id .. " : type d'ancrage inconnu " .. tostring(anchor.kind))
		end
	end
	for _, prop in layout.props do
		if prop.trap and not MapTags.TrapKinds[prop.trap] then
			table.insert(errors, prop.id .. " : type de piège inconnu " .. tostring(prop.trap))
		end
		if prop.tag and type(MapTags[prop.tag]) ~= "string" then
			table.insert(errors, prop.id .. " : tag inconnu " .. tostring(prop.tag))
		end
		local room = byId[prop.room]
		if
			room
			and room.outdoor
			and (prop.y or 0) + prop.size[2] + HouseGeometry.JUMP_REACH > layout.FENCE_HEIGHT - EPS
		then
			table.insert(errors, prop.id .. " : meuble extérieur assez haut pour franchir la clôture")
		end
	end
end

-- Cette méthode permet de vérifier que toute la carte tient dans la limite du terrain et que le décor reste dehors
-- lorsque l'on valide la description.
local function checkBounds(layout, errors: { string })
	local b = layout.bounds
	if not b then
		return
	end
	for _, room in layout.rooms do
		if room.x0 < b.x0 - EPS or room.x1 > b.x1 + EPS or room.z0 < b.z0 - EPS or room.z1 > b.z1 + EPS then
			table.insert(errors, room.id .. " : hors de la limite du terrain")
		end
	end
	for _, s in layout.scenery or {} do
		if overlaps(s.x0, s.x1, b.x0, b.x1) and overlaps(s.z0, s.z1, b.z0, b.z1) then
			table.insert(errors, tostring(s.id) .. " : décor dans la limite du terrain")
		end
	end
end

-- Cette méthode permet de vérifier que deux blocs d'une même pièce ne portent pas le même nom lorsque l'on valide la
-- description (un FindFirstChild par nom doit trouver le bon bloc).
local function checkNames(plan, errors: { string })
	local seen = {}
	for _, p in plan.pieces do
		local key = (p.group or p.room or "") .. "/" .. p.name
		if seen[key] then
			table.insert(errors, "nom de bloc en double : " .. key)
		end
		seen[key] = true
	end
end

-- Cette méthode permet de relever les incohérences de la description lorsque les tests ou le générateur la vérifient ;
-- renvoie les erreurs (vide = constructible et praticable) et le plan calculé, ou nil s'il est incalculable.
function HouseGeometry.validate(layout): ({ string }, any)
	local errors: { string } = {}
	for _, key in { "rooms", "doors", "lamps", "props", "anchors", "car" } do
		if type(layout[key]) ~= "table" then
			table.insert(errors, "description sans " .. key)
		end
	end
	if #errors > 0 then
		return errors, nil
	end
	local byId = HouseGeometry.roomsById(layout)
	checkRooms(layout, errors)
	checkDoors(layout, byId, errors)
	checkKinds(layout, errors)
	for _, list in { layout.lamps, layout.props, layout.anchors, { layout.car } } do
		for _, item in list do
			if not byId[item.room] then
				table.insert(errors, tostring(item.id) .. " : pièce inconnue " .. tostring(item.room))
			end
		end
	end
	if #errors > 0 then
		return errors, nil
	end
	checkStairs(layout, errors)
	checkLamps(layout, byId, errors)
	local plan = HouseGeometry.build(layout)
	for _, problem in plan.problems do
		table.insert(errors, problem)
	end
	checkNames(plan, errors)
	checkFurniture(layout, byId, plan, errors)
	checkOutdoorPassages(layout, byId, plan, errors)
	checkBounds(layout, errors)
	local reachable = HouseGeometry.reachableRooms(layout, layout.rooms[1].id)
	for _, room in layout.rooms do
		if not reachable[room.id] then
			table.insert(errors, room.id .. " : inaccessible depuis " .. layout.rooms[1].id)
		end
	end
	return errors, plan
end

return HouseGeometry
