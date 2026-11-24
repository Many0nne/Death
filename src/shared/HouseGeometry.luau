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

-- Réglages des lampes : portée et intensité des PointLight par type de lampe.
HouseGeometry.LAMP_STYLES = {
	Ceiling = { size = Vector3.new(2, 0.4, 2), range = 18, brightness = 1.2 },
	Chandelier = { size = Vector3.new(3, 1.5, 3), height = 8.5, range = 22, brightness = 1.5 },
}

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

-- Cette méthode permet de donner le rectangle intérieur (entre les murs) d'une pièce lorsque l'on y pose un objet.
function HouseGeometry.interior(layout, room)
	local w = layout.WALL
	return { x0 = room.x0 + w, x1 = room.x1 - w, z0 = room.z0 + w, z1 = room.z1 - w }
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

-- Cette méthode permet de découper un mur en rectangles pleins autour de ses ouvertures lorsque des portes le
-- percent ; renvoie aussi une erreur si deux ouvertures se chevauchent le long du mur. Limite assumée : deux portes
-- superposées (même u, niveaux différents d'une cage) sont refusées, le découpage se fait par colonnes.
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
-- construit la maison.
local function roomPieces(layout, room, out: { Piece }, problems: { string })
	local base = HouseGeometry.floorY(layout, room.level)
	local top = HouseGeometry.topY(layout, room)
	table.insert(
		out,
		piece(
			"Floor",
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
	for _, wall in HouseGeometry.walls(layout, room) do
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
		local rects, problem = HouseGeometry.splitWall(wall.u0, wall.u1, base, top, openings)
		if problem then
			table.insert(problems, string.format("%s, mur %s : %s", room.id, wall.side, problem))
		end
		for i, r in rects do
			table.insert(out, wallPiece("Wall", string.format("%sWall%s%d", room.id, wall.side, i), room, wall, r))
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
		table.insert(pieces, lampPiece(layout, byId[lamp.room], lamp))
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
	local spawnRoom = byId[layout.spawn.room]
	table.insert(
		pieces,
		anchorPiece(
			"SpawnLocation",
			spawnRoom,
			layout.spawn.x,
			HouseGeometry.floorY(layout, spawnRoom.level),
			layout.spawn.z,
			Vector3.new(6, 0.2, 6),
			{}
		)
	)
	pieces[#pieces].kind = "Spawn"
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

-- Cette méthode permet de lister les pièces reliées par une porte intérieure lorsque l'on vérifie qu'on peut aller
-- partout depuis une pièce.
function HouseGeometry.reachableRooms(layout, fromId: string): { [string]: boolean }
	local seen = { [fromId] = true }
	local queue = { fromId }
	while #queue > 0 do
		local current = table.remove(queue, 1)
		for _, door in layout.doors do
			if #door.rooms == 2 and table.find(door.rooms, current) then
				local other = if door.rooms[1] == current then door.rooms[2] else door.rooms[1]
				if not seen[other] then
					seen[other] = true
					table.insert(queue, other)
				end
			end
		end
	end
	return seen
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
		if not layout.levels[room.level] then
			table.insert(errors, room.id .. " : niveau inconnu " .. tostring(room.level))
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
		if room.roof and #covers > 0 then
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
			elseif opening.u0 < onWall.u0 + layout.WALL - EPS or opening.u1 > onWall.u1 - layout.WALL + EPS then
				table.insert(errors, door.id .. " : déborde du mur de " .. roomId)
			end
			if not HouseGeometry.spansLevel(room, door.level) then
				table.insert(errors, door.id .. " : niveau absent de " .. roomId)
			elseif opening.y1 > HouseGeometry.topY(layout, room) + EPS then
				table.insert(errors, door.id .. " : plus haute que le plafond de " .. roomId)
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

-- Cette méthode permet de vérifier les blocs posés dans les pièces (dedans, sans boucher une porte ni se chevaucher)
-- lorsque l'on valide la description.
local function checkFurniture(layout, byId, plan, errors: { string })
	local solids = {}
	for _, p in plan.pieces do
		if p.kind ~= "Prop" and p.kind ~= "Car" and p.kind ~= "Lamp" and p.kind ~= "Anchor" and p.kind ~= "Spawn" then
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
			if table.find(door.rooms, room.id) and HouseGeometry.spansLevel(room, door.level) then
				-- Dégagement : toute la largeur de la porte plus 0,5 stud, sur 3 studs de chaque côté du mur
				local o = HouseGeometry.doorOpening(layout, door)
				local line = if door.along == "X" then door.z else door.x
				local u0, u1 = o.u0 - 0.5, o.u1 + 0.5
				local blocks = if door.along == "X"
					then overlaps(minV.X, maxV.X, u0, u1) and overlaps(minV.Z, maxV.Z, line - 3, line + 3)
					else overlaps(minV.Z, maxV.Z, u0, u1) and overlaps(minV.X, maxV.X, line - 3, line + 3)
				if blocks and minV.Y < o.y1 then
					table.insert(errors, p.name .. " : bouche la porte " .. door.id)
				end
			end
		end
		for _, other in solids do
			if other.group ~= nil and other.group == p.group then
				continue
			end
			local oMin, oMax = other.center - other.size / 2, other.center + other.size / 2
			if
				overlaps(minV.X, maxV.X, oMin.X, oMax.X)
				and overlaps(minV.Y, maxV.Y, oMin.Y, oMax.Y)
				and overlaps(minV.Z, maxV.Z, oMin.Z, oMax.Z)
			then
				table.insert(errors, p.name .. " chevauche " .. other.name)
			end
		end
		table.insert(solids, p)
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
	for _, lamp in layout.lamps do
		if not HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"] then
			table.insert(errors, lamp.id .. " : type de lampe inconnu " .. tostring(lamp.kind))
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

-- Cette méthode permet de relever toutes les incohérences de la description lorsque les tests ou le générateur la
-- vérifient ; une liste vide signifie que la maison est constructible et praticable. Renvoie aussi le plan calculé
-- (nil si la description ne permet pas de le calculer) pour éviter un second calcul.
function HouseGeometry.validate(layout): ({ string }, any)
	local errors: { string } = {}
	local byId = HouseGeometry.roomsById(layout)
	checkRooms(layout, errors)
	checkDoors(layout, byId, errors)
	checkKinds(layout, errors)
	for _, list in { layout.lamps, layout.props, layout.anchors, { layout.car, layout.spawn } } do
		for _, item in list do
			if not byId[item.room] then
				table.insert(errors, tostring(item.id or "spawn") .. " : pièce inconnue " .. tostring(item.room))
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
	local reachable = HouseGeometry.reachableRooms(layout, layout.rooms[1].id)
	for _, room in layout.rooms do
		if not reachable[room.id] then
			table.insert(errors, room.id .. " : inaccessible depuis " .. layout.rooms[1].id)
		end
	end
	return errors, plan
end

return HouseGeometry
