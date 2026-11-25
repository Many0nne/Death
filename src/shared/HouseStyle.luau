-- Habillage de la maison (#26, docs/design.md « Réalisme sobre ») : matériaux Roblox et couleurs par surface, finitions
-- par pièce, et meubles en primitives assemblées. Pur (aucune instance) : HouseGeometry place les blocs, Server.HouseBuilder
-- les instancie, tools/house-map les montre dans la vue 3D.
-- Couleurs franches mais pas criardes : la correction colorimétrique de nuit (NightLighting) désature déjà de 45 %.
local HouseStyle = {}

export type Surface = {
	material: string, -- nom d'un Enum.Material
	color: { number }, -- RGB 0..255
	transparency: number?,
	reflectance: number?,
}

-- Bloc d'un meuble dans son repère local : x latéral (-w/2..w/2), y vers le haut (0..h), z de l'arrière (-d/2) vers
-- l'avant (+d/2). HouseGeometry le tourne selon l'orientation du meuble.
export type Part = { name: string, surface: string, min: { number }, max: { number } }

-- Cette méthode permet de décrire une surface lorsque l'on remplit la palette.
local function s(
	material: string,
	r: number,
	g: number,
	b: number,
	transparency: number?,
	reflectance: number?
): Surface
	return { material = material, color = { r, g, b }, transparency = transparency, reflectance = reflectance }
end

HouseStyle.surfaces = {
	-- Maison : façade, toiture des pièces du haut, menuiseries
	Facade = s("Plaster", 196, 186, 168),
	ShedBoards = s("WoodPlanks", 104, 84, 62),
	WindowGlass = s("Glass", 34, 44, 62, 0.2, 0.25),
	WindowFrame = s("SmoothPlastic", 206, 204, 198),
	DoorWood = s("Wood", 104, 74, 50),
	GarageDoor = s("CorrodedMetal", 140, 140, 136),
	GateWood = s("WoodPlanks", 86, 66, 48),
	-- Sols
	Oak = s("WoodPlanks", 140, 104, 70),
	OakDark = s("WoodPlanks", 92, 64, 44),
	WoodRaw = s("WoodPlanks", 150, 126, 94),
	Tiles = s("CeramicTiles", 192, 188, 178),
	TilesBlue = s("CeramicTiles", 128, 150, 162),
	TilesDark = s("CeramicTiles", 78, 80, 86),
	Slate = s("Slate", 92, 94, 98),
	CarpetRed = s("Carpet", 112, 48, 46),
	CarpetBeige = s("Carpet", 176, 160, 136),
	CarpetBlue = s("Carpet", 82, 104, 140),
	CarpetGrey = s("Carpet", 96, 96, 104),
	Concrete = s("Concrete", 128, 126, 122),
	ConcreteDark = s("Concrete", 96, 94, 92),
	Brick = s("Brick", 124, 84, 70),
	-- Murs et plafonds
	CeilingWhite = s("Plaster", 214, 210, 200),
	PaintBeige = s("Plaster", 200, 186, 160),
	PaintSage = s("Plaster", 150, 164, 140),
	PaintCream = s("Plaster", 212, 202, 172),
	PaintBlue = s("Plaster", 146, 166, 186),
	PaintYellow = s("Plaster", 206, 190, 132),
	PaintPurple = s("Plaster", 108, 94, 120),
	WallpaperRed = s("Fabric", 124, 62, 58),
	WallpaperGreen = s("Fabric", 84, 104, 84),
	WallpaperNavy = s("Fabric", 62, 72, 98),
	WallpaperRose = s("Fabric", 178, 150, 140),
	-- Dehors
	Grass = s("Grass", 70, 92, 58),
	Hedge = s("LeafyGrass", 48, 70, 42),
	Soil = s("Ground", 76, 62, 48),
	Gravel = s("Pebble", 122, 118, 108),
	Paving = s("Cobblestone", 112, 108, 104),
	Asphalt = s("Asphalt", 50, 50, 54),
	Foliage = s("LeafyGrass", 62, 90, 52),
	-- Meubles
	Wood = s("Wood", 120, 86, 58),
	WoodDark = s("Wood", 76, 54, 38),
	WoodLight = s("Wood", 172, 142, 102),
	PaintedWhite = s("SmoothPlastic", 212, 208, 198),
	PaintedGreen = s("SmoothPlastic", 92, 120, 96),
	PaintedRed = s("SmoothPlastic", 150, 66, 58),
	FabricBlue = s("Fabric", 88, 98, 122),
	FabricLight = s("Fabric", 150, 156, 170),
	FabricRed = s("Fabric", 130, 64, 60),
	Rattan = s("Wood", 166, 132, 86),
	Leather = s("Leather", 92, 60, 44),
	Linen = s("Fabric", 222, 216, 202),
	Pillow = s("Fabric", 236, 232, 222),
	Blanket = s("Fabric", 116, 88, 110),
	Ceramic = s("Marble", 232, 232, 228),
	ShowerGlass = s("Glass", 168, 196, 204, 0.6, 0.1),
	Metal = s("Metal", 142, 144, 148),
	MetalDark = s("Metal", 70, 72, 76),
	Granite = s("Granite", 70, 70, 74),
	Cardboard = s("Cardboard", 160, 128, 90),
	Rubber = s("Rubber", 30, 30, 32),
	Bottles = s("Glass", 30, 48, 34, 0.1, 0.2),
	BookRed = s("SmoothPlastic", 128, 52, 48),
	BookGreen = s("SmoothPlastic", 56, 92, 66),
	BookBlue = s("SmoothPlastic", 52, 70, 112),
	BookCream = s("SmoothPlastic", 206, 194, 160),
	Dishes = s("SmoothPlastic", 226, 226, 220),
	Lampshade = s("Fabric", 222, 204, 166),
	CarPaint = s("Metal", 92, 42, 42),
	Headlight = s("Glass", 220, 220, 200, 0.1, 0.3),
	Breaker = s("Metal", 150, 152, 150),
}

-- Finitions par pièce : sol, murs (face intérieure), plafond, marches. Une pièce absente prend DEFAULT_FINISH.
-- Dehors : seul le sol compte (terrain). La cave n'a pas de façade : ses murs sont dans la terre.
local DEFAULT_FINISH = { floor = "Oak", wall = "PaintBeige", ceiling = "CeilingWhite", step = "Oak" }
local CAVE_FINISH = { floor = "ConcreteDark", wall = "Concrete", ceiling = "Concrete", step = "Concrete" }
HouseStyle.finishes = {
	-- Cave
	Cave = CAVE_FINISH,
	Cellar = CAVE_FINISH,
	WineCellar = { floor = "ConcreteDark", wall = "Brick", ceiling = "Brick", step = "Concrete" },
	Workshop = CAVE_FINISH,
	CaveStairs = { floor = "ConcreteDark", wall = "Concrete", ceiling = "Concrete", step = "Concrete" },
	WorkshopStairs = CAVE_FINISH,
	-- Rez-de-chaussée
	Living = { floor = "Oak", wall = "PaintBeige", ceiling = "CeilingWhite" },
	Entry = { floor = "TilesDark", wall = "PaintCream", ceiling = "CeilingWhite" },
	HallDown = { floor = "Oak", wall = "PaintCream", ceiling = "CeilingWhite" },
	Dining = { floor = "Oak", wall = "PaintSage", ceiling = "CeilingWhite" },
	Kitchen = { floor = "Tiles", wall = "PaintCream", ceiling = "CeilingWhite" },
	Library = { floor = "OakDark", wall = "WallpaperRed", ceiling = "CeilingWhite" },
	Laundry = { floor = "Tiles", wall = "PaintBlue", ceiling = "CeilingWhite" },
	Veranda = { floor = "Slate", wall = "PaintCream", ceiling = "WoodLight" },
	Garage = { floor = "Concrete", wall = "Concrete", ceiling = "Concrete" },
	Stairs = { floor = "Oak", wall = "PaintCream", ceiling = "CeilingWhite", step = "OakDark" },
	GarageStairs = { floor = "Concrete", wall = "Concrete", ceiling = "Concrete", step = "Concrete" },
	-- Étage
	Study = { floor = "OakDark", wall = "WallpaperNavy", ceiling = "CeilingWhite" },
	HallUp = { floor = "CarpetRed", wall = "PaintCream", ceiling = "CeilingWhite" },
	HallEast = { floor = "CarpetRed", wall = "PaintCream", ceiling = "CeilingWhite" },
	MasterBedroom = { floor = "CarpetBeige", wall = "WallpaperRose", ceiling = "CeilingWhite" },
	Dressing = { floor = "Oak", wall = "PaintBeige", ceiling = "CeilingWhite" },
	Bathroom = { floor = "TilesBlue", wall = "Tiles", ceiling = "CeilingWhite" },
	KidsBedroom = { floor = "CarpetBlue", wall = "PaintYellow", ceiling = "CeilingWhite" },
	GuestBedroom = { floor = "Oak", wall = "WallpaperGreen", ceiling = "CeilingWhite" },
	TeenBedroom = { floor = "CarpetGrey", wall = "PaintPurple", ceiling = "CeilingWhite" },
	ShowerRoom = { floor = "TilesBlue", wall = "Tiles", ceiling = "CeilingWhite" },
	Attic = { floor = "WoodRaw", wall = "WoodRaw", ceiling = "WoodRaw" },
	-- Dehors
	FrontYard = { floor = "Grass" },
	Driveway = { floor = "Gravel" },
	WestSide = { floor = "Grass" },
	NorthPassage = { floor = "Paving" },
	Courtyard = { floor = "Paving" },
	VegetableGarden = { floor = "Soil" },
	Garden = { floor = "Grass" },
	Shed = { floor = "WoodRaw", wall = "ShedBoards", ceiling = "ShedBoards", facade = "ShedBoards" },
}

-- Cette méthode permet de donner les finitions d'une pièce lorsque l'on habille ses sols, murs, plafond et marches.
function HouseStyle.finish(roomId: string)
	local f = HouseStyle.finishes[roomId] or DEFAULT_FINISH
	return {
		floor = f.floor or DEFAULT_FINISH.floor,
		wall = f.wall or DEFAULT_FINISH.wall,
		ceiling = f.ceiling or DEFAULT_FINISH.ceiling,
		step = f.step or f.floor or DEFAULT_FINISH.step,
		facade = f.facade or "Facade",
	}
end

-- Surfaces des autres blocs de la maison, par type de bloc (HouseGeometry) ou par nom
HouseStyle.blocks = {
	Fence = "Hedge",
	Street = "Asphalt",
	Lawn = "Grass",
	Pole = "MetalDark",
	Breaker = "Breaker",
}
HouseStyle.doorLeaves = { FrontDoor = "DoorWood", GarageDoor = "GarageDoor", Gate = "GateWood" }
HouseStyle.car = {
	Body = "CarPaint",
	Cabin = "WindowGlass",
	Bumper = "MetalDark",
	HeadlightLeft = "Headlight",
	HeadlightRight = "Headlight",
}

-- Fenêtres factices posées dans l'épaisseur des murs de façade (aucune ouverture : la lumière et la vue ne passent
-- pas) : largeur, hauteur, allège, écart minimal entre deux fenêtres et marge autour des portes.
HouseStyle.WINDOW = { width = 3.5, height = 4.5, sill = 3, spacing = 9, doorMargin = 1.5, frame = 0.3 }
-- Écart entre fenêtres par pièce : la véranda est presque toute vitrée, le grenier et l'abri n'ont qu'un jour
HouseStyle.windowSpacing = { Veranda = 5, Attic = 14, Shed = 14, Garage = 14 }

----------------------------------------------------------------------------------------------------------------------
-- Meubles
----------------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'ajouter un bloc à un meuble lorsque l'on le décrit par ses coins locaux.
local function add(
	parts: { Part },
	name: string,
	surface: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
)
	table.insert(parts, { name = name, surface = surface, min = { x0, y0, z0 }, max = { x1, y1, z1 } })
end

-- Cette méthode permet de poser quatre pieds sous un plateau lorsque l'on construit une table, un banc ou un meuble
-- sur pieds.
local function legs(parts: { Part }, surface: string, w: number, d: number, height: number, size: number)
	local x, z = w / 2, d / 2
	for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local cx, cz = c[1] * (x - size / 2), c[2] * (z - size / 2)
		add(parts, "Leg" .. i, surface, cx - size / 2, 0, cz - size / 2, cx + size / 2, height, cz + size / 2)
	end
end

-- Cette méthode permet de construire une table (plateau et quatre pieds) lorsque le meuble est une table.
local function table_(surface: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		add(parts, "Top", surface, -w / 2, h - 0.3, -d / 2, w / 2, h, d / 2)
		legs(parts, surface, w, d, h - 0.3, 0.4)
		return parts
	end
end

-- Cette méthode permet de construire un canapé ou un fauteuil (assise, dossier, accoudoirs, coussins) lorsque le meuble
-- sert à s'asseoir.
local function seat(fabric: string, cushion: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local arm, back, seatH = math.min(0.7, w * 0.15), math.min(0.9, d * 0.3), h * 0.45
		add(parts, "Base", fabric, -w / 2 + arm, 0, -d / 2 + back, w / 2 - arm, seatH, d / 2)
		add(parts, "Back", fabric, -w / 2, 0, -d / 2, w / 2, h, -d / 2 + back)
		add(parts, "ArmLeft", fabric, -w / 2, 0, -d / 2 + back, -w / 2 + arm, h * 0.7, d / 2)
		add(parts, "ArmRight", fabric, w / 2 - arm, 0, -d / 2 + back, w / 2, h * 0.7, d / 2)
		local inner0, inner1 = -w / 2 + arm + 0.1, w / 2 - arm - 0.1
		local count = if inner1 - inner0 > 4 then 2 else 1
		local step = (inner1 - inner0) / count
		for i = 1, count do
			local a = inner0 + (i - 1) * step
			add(
				parts,
				"Cushion" .. i,
				cushion,
				a + 0.05,
				seatH,
				-d / 2 + back,
				a + step - 0.05,
				seatH + 0.4,
				d / 2 - 0.1
			)
		end
		return parts
	end
end

-- Cette méthode permet de construire une chaise ou un tabouret (assise, pieds, dossier optionnel) lorsque la pièce a
-- besoin de sièges autour d'une table.
local function chair(surface: string, withBack: boolean)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local seatH = if withBack then math.min(1.8, h * 0.55) else h
		add(parts, "Seat", surface, -w / 2, seatH - 0.25, -d / 2, w / 2, seatH, d / 2)
		legs(parts, surface, w, d, seatH - 0.25, 0.25)
		if withBack then
			add(parts, "Back", surface, -w / 2, seatH, -d / 2, w / 2, h, -d / 2 + 0.25)
		end
		return parts
	end
end

-- Cette méthode permet de construire un bureau (plateau, caisson à tiroirs à droite, pieds à gauche) lorsque le meuble
-- sert à travailler.
local function desk(surface: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		add(parts, "Top", surface, -w / 2, h - 0.3, -d / 2, w / 2, h, d / 2)
		local cx = w / 2 - math.min(2, w * 0.35)
		add(parts, "Drawers", surface, cx, 0, -d / 2, w / 2, h - 0.3, d / 2 - 0.08)
		for i = 1, 2 do
			local y0 = (h - 0.3) * (i - 1) / 2 + 0.15
			local y1 = (h - 0.3) * i / 2 - 0.15
			add(parts, "Drawer" .. i, "WoodLight", cx + 0.15, y0, d / 2 - 0.08, w / 2 - 0.15, y1, d / 2)
		end
		add(parts, "LegBack", surface, -w / 2, 0, -d / 2, -w / 2 + 0.3, h - 0.3, -d / 2 + 0.3)
		add(parts, "LegFront", surface, -w / 2, 0, d / 2 - 0.38, -w / 2 + 0.3, h - 0.3, d / 2 - 0.08)
		return parts
	end
end

-- Cette méthode permet de construire un meuble bas fermé (caisson, plan, poignées) lorsque le meuble est un buffet,
-- une console ou un élément de cuisine.
local function cabinetLow(body: string, top: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		add(parts, "Body", body, -w / 2 + 0.05, 0, -d / 2, w / 2 - 0.05, h - 0.25, d / 2 - 0.1)
		add(parts, "Worktop", top, -w / 2, h - 0.25, -d / 2, w / 2, h, d / 2)
		local doors = math.max(1, math.floor(w / 2))
		local step = w / doors
		for i = 1, doors do
			local cx = -w / 2 + (i - 0.5) * step
			add(parts, "Handle" .. i, "Metal", cx - 0.4, h - 0.8, d / 2 - 0.1, cx + 0.4, h - 0.6, d / 2)
		end
		return parts
	end
end

-- Cette méthode permet de construire une armoire (caisse et deux portes avec poignées) lorsque le meuble est haut et
-- fermé ; c'est un candidat de piège (étagère qui bascule).
local function wardrobe(body: string, doors: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		add(parts, "Carcass", body, -w / 2, 0, -d / 2, w / 2, h, d / 2 - 0.12)
		local count = if w >= 3 then 2 else 1
		local step = (w - 0.2) / count
		for i = 1, count do
			local a = -w / 2 + 0.1 + (i - 1) * step
			add(parts, "Door" .. i, doors, a + 0.03, 0.15, d / 2 - 0.12, a + step - 0.03, h - 0.15, d / 2 - 0.05)
			local hx = if i == 1 then a + step - 0.35 else a + 0.2
			if count == 1 then
				hx = a + step - 0.35
			end
			add(parts, "Handle" .. i, "Metal", hx, h * 0.45, d / 2 - 0.05, hx + 0.15, h * 0.45 + 0.8, d / 2)
		end
		return parts
	end
end

-- Cette méthode permet de construire une bibliothèque ouverte (fond, côtés, tablettes, rangées d'objets) lorsque le
-- meuble est haut et ouvert ; items donne les surfaces des objets posés (livres, vaisselle, cartons).
local function bookcase(body: string, items: { string }, glass: boolean?)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local t = 0.2
		add(parts, "Back", body, -w / 2, 0, -d / 2, w / 2, h, -d / 2 + t)
		add(parts, "SideLeft", body, -w / 2, 0, -d / 2, -w / 2 + t, h, d / 2)
		add(parts, "SideRight", body, w / 2 - t, 0, -d / 2, w / 2, h, d / 2)
		add(parts, "Top", body, -w / 2 + t, h - t, -d / 2, w / 2 - t, h, d / 2)
		local shelves = math.max(2, math.floor(h / 1.6))
		local gap = (h - t) / shelves
		local inner = w - 2 * t
		for i = 1, shelves do
			local y = (i - 1) * gap
			add(parts, "Shelf" .. i, body, -w / 2 + t, y, -d / 2 + t, w / 2 - t, y + t, d / 2)
			-- Une rangée d'objets par tablette : longueur et couleur variées, assez remplie pour se lire de loin
			local surface = items[(i - 1) % #items + 1]
			local fill = 0.55 + 0.3 * ((i * 37) % 10) / 10
			local a = if i % 2 == 0 then -w / 2 + t + 0.1 else w / 2 - t - 0.1 - inner * fill
			add(
				parts,
				"Items" .. i,
				surface,
				a,
				y + t,
				-d / 2 + t + 0.05,
				a + inner * fill - 0.1,
				y + t + gap * 0.65,
				d / 2 - 0.15
			)
		end
		if glass then
			add(parts, "Glass", "ShowerGlass", -w / 2 + t, t, d / 2 - 0.08, w / 2 - t, h - t, d / 2 - 0.02)
		end
		return parts
	end
end

-- Cette méthode permet de construire une étagère métallique (montants, plateaux, cartons) lorsque le meuble est un
-- rangement de cave, de garage ou d'atelier.
local function rack(post: string, board: string, items: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local p = 0.25
		for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local cx, cz = c[1] * (w / 2 - p / 2), c[2] * (d / 2 - p / 2)
			add(parts, "Post" .. i, post, cx - p / 2, 0, cz - p / 2, cx + p / 2, h, cz + p / 2)
		end
		local boards = math.max(3, math.floor(h / 1.8))
		local gap = (h - 0.15) / (boards - 1)
		for i = 1, boards do
			local y = math.min((i - 1) * gap + 0.3, h - 0.15)
			add(parts, "Board" .. i, board, -w / 2 + p, y, -d / 2, w / 2 - p, y + 0.15, d / 2)
			if i < boards and i % 2 == 1 then
				local bw = (w - 2 * p) * 0.4
				local a = if i % 4 == 1 then -w / 2 + p + 0.2 else w / 2 - p - 0.2 - bw
				add(parts, "Box" .. i, items, a, y + 0.15, -d / 2 + 0.1, a + bw, y + 0.15 + gap * 0.6, d / 2 - 0.1)
			end
		end
		return parts
	end
end

-- Cette méthode permet de construire un casier à bouteilles (cadre, tablettes, rangées de bouteilles) lorsque le meuble
-- est dans la cave à vin.
local function wineRack(w: number, h: number, d: number): { Part }
	local parts = {}
	local t = 0.25
	add(parts, "SideLeft", "WoodDark", -w / 2, 0, -d / 2, -w / 2 + t, h, d / 2)
	add(parts, "SideRight", "WoodDark", w / 2 - t, 0, -d / 2, w / 2, h, d / 2)
	add(parts, "Top", "WoodDark", -w / 2 + t, h - t, -d / 2, w / 2 - t, h, d / 2)
	local rows = 5
	local gap = (h - t) / rows
	for i = 1, rows do
		local y = (i - 1) * gap
		add(parts, "Board" .. i, "WoodDark", -w / 2 + t, y, -d / 2, w / 2 - t, y + 0.2, d / 2)
		add(parts, "Bottles" .. i, "Bottles", -w / 2 + t, y + 0.2, -d / 2 + 0.1, w / 2 - t, y + gap * 0.75, d / 2 - 0.1)
	end
	return parts
end

-- Cette méthode permet de construire un lit (cadre, matelas, couette, oreillers, tête de lit au fond) lorsque la pièce
-- est une chambre ; l'avant du lit est le pied.
local function bed(blanket: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local head = 0.4
		add(parts, "Headboard", "WoodDark", -w / 2, 0, -d / 2, w / 2, h, -d / 2 + head)
		add(parts, "Frame", "Wood", -w / 2, 0, -d / 2 + head, w / 2, 1, d / 2)
		add(parts, "Mattress", "Linen", -w / 2 + 0.15, 1, -d / 2 + head, w / 2 - 0.15, 1.8, d / 2 - 0.1)
		add(parts, "Blanket", blanket, -w / 2 + 0.05, 1.2, -d / 2 + head + d * 0.3, w / 2 - 0.05, 2, d / 2)
		local pillows = if w >= 5.5 then 2 else 1
		local step = (w - 0.6) / pillows
		for i = 1, pillows do
			local a = -w / 2 + 0.3 + (i - 1) * step
			add(
				parts,
				"Pillow" .. i,
				"Pillow",
				a + 0.1,
				1.8,
				-d / 2 + head + 0.1,
				a + step - 0.1,
				2.25,
				-d / 2 + head + 1.4
			)
		end
		return parts
	end
end

-- Cette méthode permet de construire un petit meuble à tiroir (chevet, commode basse) lorsque le meuble est bas et
-- fermé.
local function nightstand(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Body", "Wood", -w / 2, 0, -d / 2, w / 2, h, d / 2 - 0.08)
	add(parts, "Drawer", "WoodLight", -w / 2 + 0.15, h * 0.55, d / 2 - 0.08, w / 2 - 0.15, h - 0.15, d / 2)
	return parts
end

-- Cette méthode permet de construire une baignoire (coque à quatre bords et fond) lorsque la pièce est une salle de
-- bain.
local function bathtub(w: number, h: number, d: number): { Part }
	local parts = {}
	local t = 0.3
	add(parts, "Bottom", "Ceramic", -w / 2, 0, -d / 2, w / 2, 0.6, d / 2)
	add(parts, "RimBack", "Ceramic", -w / 2, 0.6, -d / 2, w / 2, h, -d / 2 + t)
	add(parts, "RimFront", "Ceramic", -w / 2, 0.6, d / 2 - t, w / 2, h, d / 2)
	add(parts, "RimLeft", "Ceramic", -w / 2, 0.6, -d / 2 + t, -w / 2 + t, h, d / 2 - t)
	add(parts, "RimRight", "Ceramic", w / 2 - t, 0.6, -d / 2 + t, w / 2, h, d / 2 - t)
	return parts
end

-- Cette méthode permet de construire un lavabo sur meuble lorsque la pièce est une salle de bain ou une salle d'eau.
local function sink(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Body", "PaintedWhite", -w / 2 + 0.1, 0, -d / 2, w / 2 - 0.1, h - 0.4, d / 2 - 0.1)
	add(parts, "Basin", "Ceramic", -w / 2, h - 0.4, -d / 2, w / 2, h, d / 2)
	return parts
end

-- Cette méthode permet de construire des toilettes (socle, cuvette, réservoir) lorsque la pièce est une salle de bain.
local function toilet(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Tank", "Ceramic", -w / 2, 0, -d / 2, w / 2, h, -d / 2 + 0.6)
	add(parts, "Pedestal", "Ceramic", -w * 0.3, 0, -d / 2 + 0.6, w * 0.3, 1, d / 2 - 0.2)
	add(parts, "Bowl", "Ceramic", -w / 2 + 0.1, 1, -d / 2 + 0.6, w / 2 - 0.1, 1.5, d / 2)
	return parts
end

-- Cette méthode permet de construire une cabine de douche (receveur, fond carrelé, parois vitrées, entrée ouverte sur la
-- moitié avant) lorsque la pièce est une salle d'eau.
local function shower(w: number, h: number, d: number): { Part }
	local parts = {}
	local t = 0.15
	add(parts, "Tray", "Ceramic", -w / 2, 0, -d / 2, w / 2, 0.4, d / 2)
	add(parts, "Back", "TilesBlue", -w / 2, 0.4, -d / 2, w / 2, h, -d / 2 + t)
	add(parts, "SideLeft", "ShowerGlass", -w / 2, 0.4, -d / 2 + t, -w / 2 + t, h - 0.5, d / 2)
	add(parts, "SideRight", "ShowerGlass", w / 2 - t, 0.4, -d / 2 + t, w / 2, h - 0.5, d / 2)
	add(parts, "Front", "ShowerGlass", 0, 0.4, d / 2 - t, w / 2 - t, h - 0.5, d / 2)
	add(parts, "ShowerHead", "Metal", -0.4, h - 1, -d / 2 + t, 0.4, h - 0.7, -d / 2 + t + 0.8)
	return parts
end

-- Cette méthode permet de construire un appareil ménager blanc (machine à laver, sèche-linge) lorsque la pièce est une
-- buanderie.
local function appliance(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Body", "PaintedWhite", -w / 2, 0, -d / 2, w / 2, h, d / 2 - 0.08)
	add(parts, "Door", "MetalDark", -w * 0.3, h * 0.2, d / 2 - 0.08, w * 0.3, h * 0.2 + w * 0.6, d / 2)
	add(parts, "Panel", "Metal", -w / 2 + 0.1, h - 0.5, d / 2 - 0.08, w / 2 - 0.1, h - 0.15, d / 2)
	return parts
end

-- Cette méthode permet de construire une chaudière (corps, tuyaux montant au plafond) lorsque la pièce est la cave.
local function boiler(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Body", "PaintedWhite", -w / 2, 0, -d / 2 + 0.6, w / 2, h * 0.75, d / 2)
	add(parts, "PipeLeft", "Metal", -w * 0.3, 0, -d / 2, -w * 0.3 + 0.4, h, -d / 2 + 0.4)
	add(parts, "PipeRight", "Metal", w * 0.3 - 0.4, 0, -d / 2, w * 0.3, h, -d / 2 + 0.4)
	add(parts, "Gauge", "MetalDark", -0.4, h * 0.5, d / 2 - 0.01, 0.4, h * 0.5 + 0.8, d / 2)
	return parts
end

-- Cette méthode permet de construire une caisse en bois cerclée lorsque le meuble est une caisse ou une malle.
local function crate(body: string, band: string)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		add(parts, "Body", body, -w / 2 + 0.05, 0, -d / 2 + 0.05, w / 2 - 0.05, h - 0.05, d / 2 - 0.05)
		add(parts, "BandLow", band, -w / 2, h * 0.2, -d / 2, w / 2, h * 0.2 + 0.25, d / 2)
		add(parts, "BandHigh", band, -w / 2, h - 0.35, -d / 2, w / 2, h, d / 2)
		return parts
	end
end

-- Cette méthode permet de construire une pile de cartons (gros carton et petit carton décalé) lorsque le meuble est un
-- encombrement de grenier ou de cave.
local function boxes(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "BoxLow", "Cardboard", -w / 2, 0, -d / 2, w / 2, h * 0.55, d / 2)
	add(parts, "BoxHigh", "Cardboard", -w / 2 + 0.2, h * 0.55, -d / 2 + 0.3, w * 0.2, h, d / 2 - 0.2)
	return parts
end

-- Cette méthode permet de construire un tonneau (corps et deux cercles) lorsque la pièce est la cave à vin.
local function barrel(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Body", "WoodDark", -w / 2 + 0.15, 0, -d / 2 + 0.15, w / 2 - 0.15, h, d / 2 - 0.15)
	add(parts, "HoopLow", "MetalDark", -w / 2, h * 0.2, -d / 2, w / 2, h * 0.2 + 0.25, d / 2)
	add(parts, "HoopHigh", "MetalDark", -w / 2, h * 0.75, -d / 2, w / 2, h * 0.75 + 0.25, d / 2)
	return parts
end

-- Cette méthode permet de construire un établi (plateau épais, pieds, tablette basse, étau) lorsque la pièce est un
-- garage, un atelier ou un abri.
local function workbench(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Top", "WoodDark", -w / 2, h - 0.4, -d / 2, w / 2, h, d / 2)
	legs(parts, "WoodDark", w, d, h - 0.4, 0.4)
	add(parts, "Shelf", "Wood", -w / 2 + 0.4, 0.5, -d / 2 + 0.1, w / 2 - 0.4, 0.7, d / 2 - 0.1)
	add(parts, "Toolbox", "PaintedRed", -w / 2 + 0.6, 0.7, -d / 2 + 0.2, -w / 2 + 2.2, 1.5, d / 2 - 0.3)
	add(parts, "Vise", "MetalDark", w / 2 - 1.2, h - 1.2, d / 2 - 0.6, w / 2 - 0.4, h - 0.4, d / 2)
	return parts
end

-- Cette méthode permet de construire un banc de jardin (assise, pieds, dossier) lorsque le meuble est dehors.
local function bench(w: number, h: number, d: number): { Part }
	local parts = {}
	local seatH = math.min(1.6, h * 0.6)
	add(parts, "Seat", "GateWood", -w / 2, seatH - 0.25, -d / 2 + 0.3, w / 2, seatH, d / 2)
	legs(parts, "MetalDark", w, d, seatH - 0.25, 0.25)
	add(parts, "Back", "GateWood", -w / 2, seatH, -d / 2, w / 2, h, -d / 2 + 0.3)
	return parts
end

-- Cette méthode permet de construire un massif (trois touffes de feuillage de hauteurs différentes) lorsque le meuble
-- est un arbuste.
local function shrub(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Clump1", "Foliage", -w / 2, 0, -d / 2 + 0.2, -w / 6, h * 0.8, d / 2 - 0.2)
	add(parts, "Clump2", "Hedge", -w / 4, 0, -d / 2, w / 4, h, d / 2)
	add(parts, "Clump3", "Foliage", w / 6, 0, -d / 2 + 0.3, w / 2, h * 0.7, d / 2 - 0.1)
	return parts
end

-- Cette méthode permet de construire deux poubelles côte à côte (cuve et couvercle) lorsque le meuble est le coin des
-- poubelles.
local function bins(w: number, h: number, d: number): { Part }
	local parts = {}
	for i, color in { "PaintedGreen", "MetalDark" } do
		local a = -w / 2 + (i - 1) * w / 2
		add(parts, "Bin" .. i, color, a + 0.15, 0, -d / 2 + 0.1, a + w / 2 - 0.15, h - 0.25, d / 2 - 0.1)
		add(parts, "Lid" .. i, color, a + 0.05, h - 0.25, -d / 2, a + w / 2 - 0.05, h, d / 2)
	end
	return parts
end

-- Cette méthode permet de construire un tas de bois (rangées de bûches empilées) lorsque le meuble est une réserve de
-- bois.
local function woodpile(w: number, h: number, d: number): { Part }
	local parts = {}
	local rows = 3
	for i = 1, rows do
		local y0, y1 = (i - 1) * h / rows, i * h / rows
		local inset = (i - 1) * 0.15
		add(
			parts,
			"Logs" .. i,
			if i % 2 == 0 then "Wood" else "WoodDark",
			-w / 2 + inset,
			y0,
			-d / 2,
			w / 2 - inset,
			y1,
			d / 2
		)
	end
	return parts
end

-- Cette méthode permet de construire une boîte aux lettres (poteau et boîte) lorsque le meuble est en bord de rue.
local function mailbox(w: number, h: number, d: number): { Part }
	local parts = {}
	add(parts, "Post", "WoodDark", -0.2, 0, -0.2, 0.2, h - 0.8, 0.2)
	add(parts, "Box", "PaintedGreen", -w / 2, h - 0.8, -d / 2, w / 2, h, d / 2)
	return parts
end

-- Cette méthode permet de construire un barbecue (pieds, cuve, grille) lorsque le meuble est dans la cour.
local function barbecue(w: number, h: number, d: number): { Part }
	local parts = {}
	legs(parts, "MetalDark", w, d, h * 0.55, 0.2)
	add(parts, "Bowl", "MetalDark", -w / 2, h * 0.55, -d / 2, w / 2, h - 0.1, d / 2)
	add(parts, "Grill", "Metal", -w / 2 + 0.15, h - 0.1, -d / 2 + 0.15, w / 2 - 0.15, h, d / 2 - 0.15)
	return parts
end

-- Cette méthode permet de construire un carré de potager (bordure en planches, terre, rangées de légumes) lorsque le
-- meuble est dans le potager.
local function vegetableBed(w: number, h: number, d: number): { Part }
	local parts = {}
	local t = 0.25
	add(parts, "BorderBack", "WoodRaw", -w / 2, 0, -d / 2, w / 2, h * 0.6, -d / 2 + t)
	add(parts, "BorderFront", "WoodRaw", -w / 2, 0, d / 2 - t, w / 2, h * 0.6, d / 2)
	add(parts, "BorderLeft", "WoodRaw", -w / 2, 0, -d / 2 + t, -w / 2 + t, h * 0.6, d / 2 - t)
	add(parts, "BorderRight", "WoodRaw", w / 2 - t, 0, -d / 2 + t, w / 2, h * 0.6, d / 2 - t)
	add(parts, "Soil", "Soil", -w / 2 + t, 0, -d / 2 + t, w / 2 - t, h * 0.5, d / 2 - t)
	local rows = 3
	local step = (d - 2 * t) / rows
	for i = 1, rows do
		local z = -d / 2 + t + (i - 0.5) * step
		add(parts, "Plants" .. i, "Foliage", -w / 2 + 0.6, h * 0.5, z - step * 0.25, w / 2 - 0.6, h, z + step * 0.25)
	end
	return parts
end

-- Meubles par style : chaque fonction reçoit largeur (latérale), hauteur et profondeur, et rend ses blocs locaux. Un
-- meuble sans style reste un bloc plein (disjoncteur).
HouseStyle.furniture = {
	Sofa = seat("FabricBlue", "FabricLight"),
	Armchair = seat("Leather", "Leather"),
	RattanChair = seat("Rattan", "Linen"),
	CoffeeTable = table_("WoodDark"),
	Table = table_("Wood"),
	GardenTable = table_("GateWood"),
	Chair = chair("Wood", true),
	Stool = chair("WoodDark", false),
	Desk = desk("Wood"),
	Sideboard = cabinetLow("Wood", "WoodDark"),
	KitchenCounter = cabinetLow("PaintedWhite", "Granite"),
	Wardrobe = wardrobe("Wood", "WoodLight"),
	WhiteWardrobe = wardrobe("PaintedWhite", "PaintedWhite"),
	Bookcase = bookcase("WoodDark", { "BookRed", "BookGreen", "BookBlue", "BookCream" }),
	Dresser = bookcase("PaintedWhite", { "Dishes" }),
	DisplayCabinet = bookcase("Wood", { "Dishes", "BookCream" }, true),
	Rack = rack("MetalDark", "Metal", "Cardboard"),
	WoodRack = rack("WoodDark", "WoodRaw", "Cardboard"),
	WineRack = wineRack,
	Bed = bed("Blanket"),
	KidsBed = bed("FabricRed"),
	Nightstand = nightstand,
	Bathtub = bathtub,
	Sink = sink,
	Toilet = toilet,
	Shower = shower,
	Appliance = appliance,
	Boiler = boiler,
	Crate = crate("WoodRaw", "WoodDark"),
	Trunk = crate("WoodDark", "MetalDark"),
	ToyBox = crate("PaintedRed", "PaintedWhite"),
	Boxes = boxes,
	Barrel = barrel,
	Workbench = workbench,
	Bench = bench,
	Shrub = shrub,
	Bins = bins,
	Woodpile = woodpile,
	Mailbox = mailbox,
	Barbecue = barbecue,
	VegetableBed = vegetableBed,
}

-- Habillage des lampes (blocs sans collision ni ombre, autour du bloc lumineux) : abat-jour du plafonnier, tige et bras
-- du lustre, platine de l'applique, socle et chapeau du lampadaire. Repère : centre de la lampe, y vers le haut ;
-- ceiling = distance du centre au plafond (plafonnier, lustre), ground = distance du centre au sol (lampadaire).
-- Cette méthode permet de donner les blocs d'habillage d'une lampe lorsque l'on la construit.
function HouseStyle.fixture(kind: string, size: { number }, ceiling: number?, ground: number?): { Part }
	local parts = {}
	local sx, sy, sz = size[1], size[2], size[3]
	if kind == "Ceiling" then
		-- Abat-jour : quatre bandes autour du bloc lumineux, un peu plus bas que lui
		local r, t = sx / 2 + 0.15, 0.1
		add(parts, "ShadeSouth", "Lampshade", -r, -sy / 2 - 0.3, -r, r, sy / 2, -r + t)
		add(parts, "ShadeNorth", "Lampshade", -r, -sy / 2 - 0.3, r - t, r, sy / 2, r)
		add(parts, "ShadeWest", "Lampshade", -r, -sy / 2 - 0.3, -r + t, -r + t, sy / 2, r - t)
		add(parts, "ShadeEast", "Lampshade", r - t, -sy / 2 - 0.3, -r + t, r, sy / 2, r - t)
	elseif kind == "Chandelier" then
		local top = ceiling or 1
		add(parts, "Rod", "Metal", -0.1, sy / 2, -0.1, 0.1, top, 0.1)
		local arm = sx / 2 + 1.2
		add(parts, "ArmX", "Metal", -arm, -sy / 2, -0.1, arm, -sy / 2 + 0.2, 0.1)
		add(parts, "ArmZ", "Metal", -0.1, -sy / 2, -arm, 0.1, -sy / 2 + 0.2, arm)
		for i, c in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
			local cx, cz = c[1] * (arm - 0.2), c[2] * (arm - 0.2)
			add(
				parts,
				"Cup" .. i,
				"Lampshade",
				cx - 0.25,
				-sy / 2 + 0.2,
				cz - 0.25,
				cx + 0.25,
				-sy / 2 + 0.7,
				cz + 0.25
			)
		end
	elseif kind == "Wall" then
		-- Platine contre le mur, à l'arrière (z local négatif : HouseGeometry tourne l'applique dos au mur)
		add(
			parts,
			"Plate",
			"MetalDark",
			-sx / 2 - 0.1,
			-sy / 2 - 0.3,
			-sz / 2,
			sx / 2 + 0.1,
			sy / 2 + 0.3,
			-sz / 2 + 0.1
		)
		add(parts, "Cap", "MetalDark", -sx / 2 - 0.1, sy / 2, -sz / 2, sx / 2 + 0.1, sy / 2 + 0.15, sz / 2 + 0.1)
	elseif kind == "Post" then
		add(
			parts,
			"Cap",
			"MetalDark",
			-sx / 2 - 0.15,
			sy / 2,
			-sz / 2 - 0.15,
			sx / 2 + 0.15,
			sy / 2 + 0.25,
			sz / 2 + 0.15
		)
		local g = ground or 0
		add(parts, "Base", "MetalDark", -0.6, -g, -0.6, 0.6, -g + 0.8, 0.6)
	end
	return parts
end

return HouseStyle
