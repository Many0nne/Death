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
-- small = petit objet (#38 : livre, bouteille, bibelot) : visible, mais n'arrête ni le joueur, ni un rayon, sans ombre.
-- shape = forme Roblox : « Ball », ou cylindre d'axe « X », « Y » (vertical) ou « Z » ; min/max restent la boîte de
-- l'objet droit. rot = rotation autour du centre de cette boîte, en degrés (CFrame.Angles x, y, z, repère du meuble).
export type Part = {
	name: string,
	surface: string,
	min: { number },
	max: { number },
	small: boolean?,
	shape: string?,
	rot: { number }?,
}

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
	-- Petits objets (#38)
	BookBrown = s("SmoothPlastic", 110, 78, 52),
	BookBlack = s("SmoothPlastic", 42, 40, 44),
	BookOchre = s("SmoothPlastic", 176, 132, 56),
	BookTeal = s("SmoothPlastic", 52, 108, 110),
	BookGrey = s("SmoothPlastic", 120, 118, 112),
	BookPurple = s("SmoothPlastic", 92, 64, 104),
	Paper = s("SmoothPlastic", 232, 228, 214),
	GlassClear = s("Glass", 196, 210, 212, 0.45, 0.15),
	BottleGreen = s("Glass", 34, 70, 44, 0.15, 0.2),
	BottleBrown = s("Glass", 92, 56, 30, 0.15, 0.2),
	Terracotta = s("Concrete", 168, 96, 66),
	Screen = s("Glass", 18, 20, 24, 0, 0.3),
	Plastic = s("SmoothPlastic", 42, 42, 46),
	ToyRed = s("SmoothPlastic", 196, 56, 48),
	ToyYellow = s("SmoothPlastic", 220, 180, 48),
	ToyBlue = s("SmoothPlastic", 52, 104, 196),
	ToyGreen = s("SmoothPlastic", 64, 150, 72),
	Plush = s("Fabric", 150, 108, 70),
	Wax = s("SmoothPlastic", 232, 222, 196),
	Copper = s("Metal", 160, 96, 64),
	Brass = s("Metal", 182, 150, 72),
	Mirror = s("Glass", 186, 196, 200, 0, 0.5),
	PaintingSky = s("SmoothPlastic", 108, 128, 150),
	PaintingField = s("SmoothPlastic", 110, 120, 70),
	PaintingDark = s("SmoothPlastic", 46, 40, 38),
	PaintingSkin = s("SmoothPlastic", 196, 168, 140),
	PaintingOchre = s("SmoothPlastic", 170, 124, 64),
	Denim = s("Fabric", 62, 80, 112),
	ClothesGrey = s("Fabric", 110, 110, 114),
	TowelWhite = s("Fabric", 230, 230, 226),
	TowelBlue = s("Fabric", 90, 130, 170),
	FruitRed = s("SmoothPlastic", 170, 40, 36),
	FruitOrange = s("SmoothPlastic", 214, 120, 40),
	FruitGreen = s("SmoothPlastic", 120, 160, 60),
	DetergentBlue = s("SmoothPlastic", 60, 110, 190),
	DetergentOrange = s("SmoothPlastic", 220, 120, 50),
	Cork = s("Cardboard", 176, 136, 92),
	Cobweb = s("SmoothPlastic", 226, 226, 222, 0.6),
	DustSheet = s("Fabric", 206, 204, 194),
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

----------------------------------------------------------------------------------------------------------------------
-- Petits objets (#38) : tirage déterministe, catalogue d'objets et rangées
----------------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de tirer des nombres pseudo-aléatoires reproductibles (0..1) lorsque l'on varie livres et objets :
-- même graine, même suite, sur Roblox comme sous Lune (générateur de Park-Miller, exact en nombres flottants).
function HouseStyle.random(seed: number): () -> number
	local state = seed % 2147483646 + 1
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- Cette méthode permet de tirer une graine d'un identifiant lorsque chaque meuble ou garniture doit varier à sa façon.
function HouseStyle.seed(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- Cette méthode permet de choisir un élément d'une liste lorsque l'on tire une couleur ou un objet au hasard.
local function pick<T>(rnd: () -> number, list: { T }): T
	return list[math.floor(rnd() * #list) + 1]
end

-- Cette méthode permet d'ajouter un petit objet centré en (x, z) et posé en y lorsque l'on garnit un meuble ou une
-- surface ; shape et rot sont facultatifs (voir Part).
local function bit(
	parts: { Part },
	name: string,
	surface: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	shape: string?,
	rot: { number }?
)
	table.insert(parts, {
		name = name,
		surface = surface,
		min = { x - sx / 2, y, z - sz / 2 },
		max = { x + sx / 2, y + sy, z + sz / 2 },
		small = true,
		shape = shape,
		rot = rot,
	})
end

local BOOK_COLORS = {
	"BookRed",
	"BookGreen",
	"BookBlue",
	"BookCream",
	"BookBrown",
	"BookBlack",
	"BookOchre",
	"BookTeal",
	"BookGrey",
	"BookPurple",
}
local MUG_COLORS = { "Dishes", "PaintedRed", "PaintedGreen", "BookOchre", "FabricBlue" }
local BOTTLE_COLORS = { "BottleGreen", "BottleBrown", "Bottles", "BottleGreen" }
local TOY_COLORS = { "ToyRed", "ToyYellow", "ToyBlue", "ToyGreen" }
local CLOTHES_COLORS = { "Denim", "ClothesGrey", "FabricRed", "Linen", "Blanket", "FabricBlue", "BookBlack" }
local CAN_COLORS = { "PaintedRed", "PaintedGreen", "PaintedWhite", "MetalDark", "DetergentBlue" }

-- Objet posé : empreinte w (x) × d (z), hauteur h ; build l'ajoute centré en (x, z), posé en y, sans dépasser
-- l'empreinte (rotations comprises).
type Item = {
	w: number,
	d: number,
	h: number,
	build: (parts: { Part }, rnd: () -> number, x: number, y: number, z: number) -> (),
}

-- Catalogue des petits objets, réutilisés par les rangées (tablettes, plans, sol)
local ITEMS: { [string]: Item } = {
	-- Cuisine et table
	PlateStack = {
		w = 1,
		d = 1,
		h = 0.45,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Plates", "Dishes", x, y, z, 0.9, 0.1 + math.floor(rnd() * 4) * 0.08, 0.9, "Y")
		end,
	},
	StandingPlate = {
		w = 1,
		d = 0.3,
		h = 0.95,
		build = function(parts, _, x, y, z)
			bit(parts, "Plate", "Dishes", x, y, z, 0.9, 0.9, 0.08, "Z")
		end,
	},
	Bowl = {
		w = 0.85,
		d = 0.85,
		h = 0.35,
		build = function(parts, _, x, y, z)
			bit(parts, "Bowl", "Dishes", x, y, z, 0.75, 0.3, 0.75, "Y")
		end,
	},
	Mug = {
		w = 0.5,
		d = 0.5,
		h = 0.4,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Mug", pick(rnd, MUG_COLORS), x - 0.04, y, z, 0.36, 0.38, 0.36, "Y")
			bit(parts, "MugHandle", "Dishes", x + 0.18, y + 0.1, z, 0.08, 0.2, 0.06)
		end,
	},
	Glass = {
		w = 0.35,
		d = 0.35,
		h = 0.5,
		build = function(parts, _, x, y, z)
			bit(parts, "Glass", "GlassClear", x, y, z, 0.28, 0.45, 0.28, "Y")
		end,
	},
	Bottle = {
		w = 0.4,
		d = 0.4,
		h = 1.2,
		build = function(parts, rnd, x, y, z)
			local color = pick(rnd, BOTTLE_COLORS)
			bit(parts, "Bottle", color, x, y, z, 0.32, 0.8, 0.32, "Y")
			bit(parts, "BottleNeck", color, x, y + 0.8, z, 0.13, 0.35, 0.13, "Y")
		end,
	},
	Jar = {
		w = 0.5,
		d = 0.5,
		h = 0.7,
		build = function(parts, rnd, x, y, z)
			bit(
				parts,
				"Jar",
				pick(rnd, { "FruitRed", "BookOchre", "FruitGreen", "BookCream" }),
				x,
				y,
				z,
				0.44,
				0.55,
				0.44,
				"Y"
			)
			bit(parts, "JarLid", "Metal", x, y + 0.55, z, 0.46, 0.1, 0.46, "Y")
		end,
	},
	Pot = {
		w = 1.5,
		d = 1.1,
		h = 0.75,
		build = function(parts, _, x, y, z)
			bit(parts, "Pot", "MetalDark", x - 0.2, y, z, 1, 0.6, 1, "Y")
			bit(parts, "PotLid", "Metal", x - 0.2, y + 0.6, z, 1.02, 0.07, 1.02, "Y")
			bit(parts, "PotHandle", "MetalDark", x + 0.47, y + 0.45, z, 0.45, 0.08, 0.15)
		end,
	},
	Pan = {
		w = 2,
		d = 1.1,
		h = 0.2,
		build = function(parts, _, x, y, z)
			bit(parts, "Pan", "Copper", x - 0.45, y, z, 1, 0.15, 1, "Y")
			bit(parts, "PanHandle", "WoodDark", x + 0.5, y + 0.06, z, 0.9, 0.07, 0.15)
		end,
	},
	CuttingBoard = {
		w = 1.8,
		d = 1.2,
		h = 0.2,
		build = function(parts, _, x, y, z)
			bit(parts, "CuttingBoard", "WoodLight", x, y, z, 1.6, 0.1, 1)
			bit(parts, "Knife", "Metal", x, y + 0.1, z + 0.1, 1, 0.04, 0.14, nil, { 0, 15, 0 })
		end,
	},
	Kettle = {
		w = 0.9,
		d = 0.8,
		h = 1,
		build = function(parts, _, x, y, z)
			bit(parts, "Kettle", "Metal", x, y, z, 0.7, 0.7, 0.7, "Y")
			bit(parts, "KettleHandle", "Plastic", x, y + 0.82, z, 0.5, 0.1, 0.1)
		end,
	},
	Toaster = {
		w = 1.1,
		d = 0.8,
		h = 0.7,
		build = function(parts, _, x, y, z)
			bit(parts, "Toaster", "Metal", x, y, z, 1, 0.6, 0.6)
			bit(parts, "ToasterSlot", "Plastic", x, y + 0.6, z, 0.7, 0.02, 0.12)
		end,
	},
	FruitBowl = {
		w = 1.1,
		d = 1.1,
		h = 0.65,
		build = function(parts, rnd, x, y, z)
			bit(parts, "FruitBowl", "Dishes", x, y, z, 1, 0.3, 1, "Y")
			for i, o in { { -0.2, -0.1 }, { 0.2, -0.1 }, { 0, 0.2 } } do
				local fruit = pick(rnd, { "FruitRed", "FruitOrange", "FruitGreen" })
				bit(parts, "Fruit" .. i, fruit, x + o[1], y + 0.22, z + o[2], 0.34, 0.34, 0.34, "Ball")
			end
		end,
	},
	Candle = {
		w = 0.4,
		d = 0.4,
		h = 0.85,
		build = function(parts, rnd, x, y, z)
			bit(parts, "CandleHolder", "Brass", x, y, z, 0.35, 0.1, 0.35, "Y")
			bit(parts, "Candle", "Wax", x, y + 0.1, z, 0.18, 0.4 + rnd() * 0.3, 0.18, "Y")
		end,
	},
	Vase = {
		w = 0.6,
		d = 0.6,
		h = 1.3,
		build = function(parts, rnd, x, y, z)
			bit(
				parts,
				"Vase",
				pick(rnd, { "Ceramic", "PaintedGreen", "BookTeal", "Terracotta" }),
				x,
				y,
				z,
				0.45,
				0.8,
				0.45,
				"Y"
			)
			bit(parts, "Flowers", "Foliage", x, y + 0.75, z, 0.55, 0.55, 0.55, "Ball")
		end,
	},
	PlantPot = {
		w = 0.9,
		d = 0.9,
		h = 1.15,
		build = function(parts, _, x, y, z)
			bit(parts, "PlantPot", "Terracotta", x, y, z, 0.6, 0.5, 0.6, "Y")
			bit(parts, "Plant", "Foliage", x, y + 0.35, z, 0.8, 0.8, 0.8, "Ball")
		end,
	},
	SmallPot = {
		w = 0.8,
		d = 0.8,
		h = 0.95,
		build = function(parts, _, x, y, z)
			bit(parts, "PlantPot", "Terracotta", x, y, z, 0.6, 0.45, 0.6, "Y")
			bit(parts, "Plant", "Foliage", x, y + 0.4, z, 0.55, 0.55, 0.55, "Ball")
		end,
	},
	-- Lecture, bureau, chevet
	BookPile = {
		w = 1.2,
		d = 1,
		h = 0.75,
		build = function(parts, rnd, x, y, z)
			local top = y
			for _ = 1, 2 + math.floor(rnd() * 3) do
				local t = 0.14 + rnd() * 0.04
				local a = (rnd() * 2 - 1) * 8
				bit(parts, "Book", pick(rnd, BOOK_COLORS), x, top, z, 0.95, t, 0.7, nil, { 0, a, 0 })
				top += t
			end
		end,
	},
	OpenBook = {
		w = 1.4,
		d = 1,
		h = 0.15,
		build = function(parts, rnd, x, y, z)
			bit(parts, "BookCover", pick(rnd, BOOK_COLORS), x, y, z, 1.3, 0.04, 0.9)
			bit(parts, "PageLeft", "Paper", x - 0.31, y + 0.04, z, 0.6, 0.06, 0.84, nil, { 0, 0, -5 })
			bit(parts, "PageRight", "Paper", x + 0.31, y + 0.04, z, 0.6, 0.06, 0.84, nil, { 0, 0, 5 })
		end,
	},
	Papers = {
		w = 1.5,
		d = 1.3,
		h = 0.1,
		build = function(parts, rnd, x, y, z)
			for i = 1, 2 + math.floor(rnd() * 2) do
				local a = (rnd() * 2 - 1) * 20
				bit(
					parts,
					"Paper",
					"Paper",
					x + (rnd() * 2 - 1) * 0.1,
					y + (i - 1) * 0.02,
					z,
					0.8,
					0.02,
					1.05,
					nil,
					{ 0, a, 0 }
				)
			end
		end,
	},
	Lamp = {
		w = 1,
		d = 1,
		h = 1.7,
		build = function(parts, _, x, y, z)
			bit(parts, "LampBase", "MetalDark", x, y, z, 0.5, 0.12, 0.5, "Y")
			bit(parts, "LampStem", "Brass", x, y + 0.12, z, 0.1, 0.9, 0.1, "Y")
			bit(parts, "LampShade", "Lampshade", x, y + 0.95, z, 0.9, 0.7, 0.9, "Y")
		end,
	},
	AlarmClock = {
		w = 0.7,
		d = 0.5,
		h = 0.5,
		build = function(parts, _, x, y, z)
			bit(parts, "AlarmClock", "PaintedRed", x, y, z - 0.02, 0.6, 0.45, 0.3)
			bit(parts, "ClockFace", "Paper", x, y + 0.08, z + 0.14, 0.4, 0.3, 0.02)
		end,
	},
	Phone = {
		w = 0.6,
		d = 0.75,
		h = 0.05,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Phone", "Plastic", x, y, z, 0.3, 0.03, 0.6, nil, { 0, (rnd() * 2 - 1) * 25, 0 })
		end,
	},
	Laptop = {
		w = 1.6,
		d = 1.3,
		h = 1.05,
		build = function(parts, _, x, y, z)
			bit(parts, "LaptopBase", "MetalDark", x, y, z + 0.13, 1.4, 0.06, 1)
			bit(parts, "LaptopScreen", "Screen", x, y + 0.06, z - 0.49, 1.4, 0.95, 0.05, nil, { -15, 0, 0 })
		end,
	},
	PencilCup = {
		w = 0.45,
		d = 0.45,
		h = 0.75,
		build = function(parts, rnd, x, y, z)
			bit(parts, "PencilCup", "Metal", x, y, z, 0.3, 0.4, 0.3, "Y")
			bit(parts, "Pencil", pick(rnd, TOY_COLORS), x - 0.05, y + 0.2, z, 0.05, 0.5, 0.05, nil, { 0, 0, 8 })
			bit(parts, "Pencil", pick(rnd, TOY_COLORS), x + 0.06, y + 0.2, z, 0.05, 0.45, 0.05, nil, { 6, 0, -10 })
		end,
	},
	PhotoFrame = {
		w = 0.7,
		d = 0.5,
		h = 0.9,
		build = function(parts, rnd, x, y, z)
			bit(parts, "PhotoFrame", "WoodDark", x, y, z, 0.6, 0.8, 0.06, nil, { -10, 0, 0 })
			local photo = pick(rnd, { "PaintingSky", "PaintingSkin", "PaintingField" })
			bit(parts, "Photo", photo, x, y + 0.13, z + 0.04, 0.42, 0.55, 0.02, nil, { -10, 0, 0 })
		end,
	},
	Trophy = {
		w = 0.5,
		d = 0.5,
		h = 1,
		build = function(parts, _, x, y, z)
			bit(parts, "TrophyBase", "WoodDark", x, y, z, 0.4, 0.2, 0.4)
			bit(parts, "Trophy", "Brass", x, y + 0.2, z, 0.3, 0.7, 0.3, "Y")
		end,
	},
	Globe = {
		w = 0.8,
		d = 0.8,
		h = 1.1,
		build = function(parts, _, x, y, z)
			bit(parts, "GlobeFoot", "WoodDark", x, y, z, 0.5, 0.1, 0.5, "Y")
			bit(parts, "GlobeStand", "Brass", x, y + 0.1, z, 0.06, 0.3, 0.06, "Y")
			bit(parts, "Globe", "BookTeal", x, y + 0.36, z, 0.7, 0.7, 0.7, "Ball")
		end,
	},
	-- Salle de bain et buanderie
	SoapBottle = {
		w = 0.4,
		d = 0.4,
		h = 0.7,
		build = function(parts, rnd, x, y, z)
			bit(
				parts,
				"Soap",
				pick(rnd, { "DetergentBlue", "TowelWhite", "FruitGreen", "DetergentOrange" }),
				x,
				y,
				z,
				0.28,
				0.5,
				0.28,
				"Y"
			)
			bit(parts, "SoapPump", "Plastic", x, y + 0.5, z, 0.08, 0.15, 0.08, "Y")
		end,
	},
	ToothCup = {
		w = 0.4,
		d = 0.4,
		h = 0.75,
		build = function(parts, rnd, x, y, z)
			bit(parts, "ToothCup", "GlassClear", x, y, z, 0.3, 0.4, 0.3, "Y")
			bit(parts, "Toothbrush", pick(rnd, TOY_COLORS), x, y + 0.2, z, 0.05, 0.5, 0.05, nil, { 0, 0, 10 })
		end,
	},
	FoldedTowel = {
		w = 1.3,
		d = 0.9,
		h = 0.55,
		build = function(parts, rnd, x, y, z)
			local top = y
			for _ = 1, 1 + math.floor(rnd() * 2) do
				bit(parts, "Towel", pick(rnd, { "TowelWhite", "TowelBlue", "FabricRed" }), x, top, z, 1.2, 0.25, 0.8)
				top += 0.25
			end
		end,
	},
	Detergent = {
		w = 0.7,
		d = 0.5,
		h = 1,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Detergent", pick(rnd, { "DetergentBlue", "DetergentOrange" }), x, y, z, 0.6, 0.85, 0.4)
			bit(parts, "DetergentCap", "PaintedWhite", x + 0.15, y + 0.85, z, 0.2, 0.1, 0.2, "Y")
		end,
	},
	Clothes = {
		w = 1.5,
		d = 1.3,
		h = 0.35,
		build = function(parts, rnd, x, y, z)
			local top = y
			for _ = 1, 1 + math.floor(rnd() * 2) do
				bit(
					parts,
					"Clothes",
					pick(rnd, CLOTHES_COLORS),
					x,
					top,
					z,
					1.1,
					0.14,
					0.85,
					nil,
					{ 0, (rnd() * 2 - 1) * 30, 0 }
				)
				top += 0.14
			end
		end,
	},
	Shoes = {
		w = 1,
		d = 1.05,
		h = 0.35,
		build = function(parts, rnd, x, y, z)
			local color = pick(rnd, { "Leather", "Rubber", "PaintedWhite", "ToyRed", "Denim" })
			bit(parts, "Shoe", color, x - 0.22, y, z, 0.35, 0.3, 0.85, nil, { 0, (rnd() * 2 - 1) * 10, 0 })
			bit(parts, "Shoe", color, x + 0.22, y, z, 0.35, 0.3, 0.85, nil, { 0, (rnd() * 2 - 1) * 10, 0 })
		end,
	},
	-- Atelier, garage, cave
	PaintCan = {
		w = 0.8,
		d = 0.8,
		h = 0.85,
		build = function(parts, rnd, x, y, z)
			bit(parts, "PaintCan", pick(rnd, CAN_COLORS), x, y, z, 0.7, 0.78, 0.7, "Y")
			bit(parts, "PaintCanLid", "Metal", x, y + 0.78, z, 0.72, 0.05, 0.72, "Y")
		end,
	},
	Carton = {
		w = 1.6,
		d = 1.3,
		h = 1.2,
		build = function(parts, rnd, x, y, z)
			local sx, sy, sz = 1 + rnd() * 0.5, 0.7 + rnd() * 0.45, 0.8 + rnd() * 0.45
			bit(parts, "Carton", "Cardboard", x, y, z, sx, sy, sz)
			bit(parts, "CartonTape", "BookCream", x, y + sy, z, 0.2, 0.02, sz)
		end,
	},
	SmallCarton = {
		w = 1.35,
		d = 1.25,
		h = 0.9,
		build = function(parts, rnd, x, y, z)
			local sx, sy, sz = 0.8 + rnd() * 0.3, 0.5 + rnd() * 0.35, 0.7 + rnd() * 0.3
			bit(parts, "Carton", "Cardboard", x, y, z, sx, sy, sz, nil, { 0, (rnd() * 2 - 1) * 12, 0 })
		end,
	},
	Toolbox = {
		w = 1.5,
		d = 0.8,
		h = 0.8,
		build = function(parts, _, x, y, z)
			bit(parts, "Toolbox", "PaintedRed", x, y, z, 1.4, 0.55, 0.7)
			bit(parts, "ToolboxHandle", "MetalDark", x, y + 0.55, z, 0.8, 0.12, 0.1)
		end,
	},
	Hammer = {
		w = 1.2,
		d = 0.6,
		h = 0.2,
		build = function(parts, _, x, y, z)
			bit(parts, "HammerHandle", "WoodLight", x + 0.08, y, z, 1, 0.12, 0.15)
			bit(parts, "HammerHead", "MetalDark", x - 0.45, y, z, 0.18, 0.16, 0.5)
		end,
	},
	Wrench = {
		w = 1,
		d = 0.4,
		h = 0.06,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Wrench", "Metal", x, y, z, 0.9, 0.05, 0.15, nil, { 0, (rnd() * 2 - 1) * 12, 0 })
		end,
	},
	Screwdriver = {
		w = 0.85,
		d = 0.3,
		h = 0.12,
		build = function(parts, rnd, x, y, z)
			bit(parts, "ScrewdriverGrip", pick(rnd, TOY_COLORS), x - 0.22, y, z, 0.32, 0.12, 0.12)
			bit(parts, "ScrewdriverShaft", "Metal", x + 0.17, y + 0.035, z, 0.46, 0.05, 0.05)
		end,
	},
	Saw = {
		w = 1.8,
		d = 0.7,
		h = 0.06,
		build = function(parts, _, x, y, z)
			bit(parts, "SawBlade", "Metal", x + 0.15, y, z, 1.4, 0.03, 0.5)
			bit(parts, "SawHandle", "WoodLight", x - 0.7, y, z, 0.35, 0.06, 0.45)
		end,
	},
	Radio = {
		w = 1.3,
		d = 0.6,
		h = 1.2,
		build = function(parts, _, x, y, z)
			bit(parts, "Radio", "PaintedRed", x, y, z, 1.2, 0.7, 0.5)
			bit(parts, "RadioSpeaker", "MetalDark", x - 0.25, y + 0.15, z + 0.25, 0.4, 0.4, 0.02)
			bit(parts, "RadioAntenna", "Metal", x + 0.35, y + 0.7, z, 0.04, 0.45, 0.04, nil, { 0, 0, -30 })
		end,
	},
	-- Jouets
	Block = {
		w = 0.6,
		d = 0.6,
		h = 0.42,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Block", pick(rnd, TOY_COLORS), x, y, z, 0.4, 0.4, 0.4, nil, { 0, rnd() * 45, 0 })
		end,
	},
	ToyBall = {
		w = 0.85,
		d = 0.85,
		h = 0.8,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Ball", pick(rnd, TOY_COLORS), x, y, z, 0.8, 0.8, 0.8, "Ball")
		end,
	},
	ToyCar = {
		w = 1,
		d = 0.65,
		h = 0.45,
		build = function(parts, rnd, x, y, z)
			bit(parts, "ToyCar", pick(rnd, TOY_COLORS), x, y + 0.08, z, 0.8, 0.22, 0.45)
			bit(parts, "ToyCarCabin", "GlassClear", x - 0.05, y + 0.3, z, 0.4, 0.14, 0.4)
			for i, o in { { -0.25, -0.26 }, { 0.25, -0.26 }, { -0.25, 0.26 }, { 0.25, 0.26 } } do
				bit(parts, "ToyWheel" .. i, "Rubber", x + o[1], y, z + o[2], 0.2, 0.2, 0.08, "Z")
			end
		end,
	},
	Teddy = {
		w = 0.9,
		d = 0.8,
		h = 1,
		build = function(parts, _, x, y, z)
			bit(parts, "TeddyBody", "Plush", x, y, z, 0.6, 0.6, 0.6, "Ball")
			bit(parts, "TeddyHead", "Plush", x, y + 0.55, z, 0.42, 0.42, 0.42, "Ball")
			bit(parts, "TeddyEarLeft", "Plush", x - 0.17, y + 0.84, z, 0.15, 0.15, 0.15, "Ball")
			bit(parts, "TeddyEarRight", "Plush", x + 0.17, y + 0.84, z, 0.15, 0.15, 0.15, "Ball")
		end,
	},
	-- Jardin
	WateringCan = {
		w = 1.1,
		d = 0.6,
		h = 0.85,
		build = function(parts, _, x, y, z)
			bit(parts, "WateringCan", "PaintedGreen", x - 0.2, y, z, 0.5, 0.6, 0.5, "Y")
			bit(parts, "WateringSpout", "PaintedGreen", x + 0.25, y + 0.3, z, 0.5, 0.08, 0.08, nil, { 0, 0, 35 })
		end,
	},
	Bucket = {
		w = 0.8,
		d = 0.8,
		h = 0.75,
		build = function(parts, rnd, x, y, z)
			bit(parts, "Bucket", pick(rnd, { "MetalDark", "ToyBlue", "Metal" }), x, y, z, 0.65, 0.65, 0.65, "Y")
		end,
	},
}

-- Cette méthode permet d'aligner des petits objets tirés d'une liste sur une rangée (x0..x1, posée en y, profondeur
-- z0..z1, hauteur maxH au plus) lorsque l'on garnit une tablette, un plan ou un coin de sol ; un objet trop grand pour la
-- place est écarté, l'espacement moyen vaut gap.
local function fillRow(
	parts: { Part },
	rnd: () -> number,
	kinds: { string },
	x0: number,
	x1: number,
	y: number,
	z0: number,
	z1: number,
	maxH: number,
	gap: number?
)
	local fitting = {}
	for _, kind in kinds do
		local item = ITEMS[kind]
		if item.h <= maxH + 1e-6 and item.d <= z1 - z0 + 1e-6 then
			table.insert(fitting, item)
		end
	end
	if #fitting == 0 then
		return
	end
	local x = x0 + rnd() * 0.2
	while true do
		-- Objets qui tiennent dans la place restante ; aucun : la rangée est pleine
		local room = {}
		for _, item in fitting do
			if x + item.w <= x1 + 1e-6 then
				table.insert(room, item)
			end
		end
		if #room == 0 then
			break
		end
		local item = pick(rnd, room)
		item.build(parts, rnd, x + item.w / 2, y, z0 + item.d / 2 + rnd() * (z1 - z0 - item.d))
		x += item.w + 0.05 + rnd() * (gap or 0.3)
	end
end

-- Cette méthode permet de garnir toute une boîte (w × h × d) de rangées d'objets lorsque l'on décrit une garniture de
-- plan ou de sol ; rows = nombre de rangées dans la profondeur.
local function rowsOf(kinds: { string }, count: number?, gap: number?)
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
		local parts = {}
		local n = count or 1
		for i = 1, n do
			local z0 = -d / 2 + (i - 1) * d / n
			fillRow(parts, rnd, kinds, -w / 2, w / 2, 0, z0, z0 + d / n, h, gap)
		end
		return parts
	end
end

-- Cette méthode permet de poser un seul objet au centre de la boîte lorsque la garniture est un objet isolé.
local function single(kind: string)
	return function(_w: number, _h: number, _d: number, rnd: () -> number): { Part }
		local parts = {}
		ITEMS[kind].build(parts, rnd, 0, 0, 0)
		return parts
	end
end

-- Cette méthode permet d'aligner une rangée de livres sur une tablette (x0..x1, posée en y, dos à l'avant z1, profondeur
-- disponible z1 - z0, hauteur maxH au plus) lorsque l'on garnit une bibliothèque : épaisseurs, hauteurs et couleurs
-- variées, des trous où un livre penche, des piles couchées et un bibelot de temps en temps.
local function bookRow(
	parts: { Part },
	rnd: () -> number,
	x0: number,
	x1: number,
	y: number,
	z0: number,
	z1: number,
	maxH: number
)
	local depth = z1 - z0
	local x = x0 + rnd() * 0.2
	local lean = false
	while x < x1 - 0.2 do
		local r, room = rnd(), x1 - x
		if r < 0.07 then
			-- Trou : le livre suivant penche dedans
			x += 0.4 + rnd() * 0.5
			lean = true
		elseif r < 0.13 and room >= 1.2 then
			-- Pile de livres couchés
			local bw, top = 0.85 + rnd() * 0.25, y
			for _ = 1, 2 + math.floor(rnd() * 3) do
				local t = 0.14 + rnd() * 0.1
				if top + t > y + maxH then
					break
				end
				local bd = depth * (0.7 + rnd() * 0.25)
				add(parts, "Book", pick(rnd, BOOK_COLORS), x, top, z1 - bd, x + bw, top + t, z1)
				parts[#parts].small = true
				top += t
			end
			x += bw + 0.08
		elseif r < 0.17 and room >= 1.2 then
			local item = ITEMS[pick(rnd, { "Vase", "Candle", "PhotoFrame", "Trophy", "Globe" })]
			if item.h <= maxH and item.d <= depth and item.w <= room then
				item.build(parts, rnd, x + item.w / 2, y, z1 - item.d / 2)
				x += item.w + 0.05
			else
				x += 0.3
			end
		else
			local t = 0.16 + rnd() * 0.22
			local bh = maxH * (0.62 + rnd() * 0.33)
			local bd = depth * (0.72 + rnd() * 0.26)
			local color = pick(rnd, BOOK_COLORS)
			local a = 12 + rnd() * 10
			local rad = math.rad(a)
			local leanW = math.min(bh, maxH * 0.85) * math.sin(rad) + t * math.cos(rad)
			if lean and leanW <= room then
				-- Livre penché vers la gauche, posé sur son coin : boîte englobante x..x + leanW, y..y + leanH
				bh = math.min(bh, maxH * 0.85)
				local leanH = bh * math.cos(rad) + t * math.sin(rad)
				local cx, cy = x + leanW / 2, y + leanH / 2
				table.insert(parts, {
					name = "Book",
					surface = color,
					min = { cx - t / 2, cy - bh / 2, z1 - bd },
					max = { cx + t / 2, cy + bh / 2, z1 },
					rot = { 0, 0, a },
					small = true,
				})
				x += leanW + 0.02
			elseif t <= room then
				add(parts, "Book", color, x, y, z1 - bd, x + t, y + bh, z1)
				parts[#parts].small = true
				x += t + (if rnd() < 0.15 then 0.04 else 0)
			else
				break
			end
			lean = false
		end
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
-- sert à s'asseoir ; cosy ajoute des coussins de décoration penchés et un plaid plié (#38).
local function seat(fabric: string, cushion: string, cosy: boolean?)
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
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
		if cosy then
			-- Coussins calés contre le dossier, un plaid plié en travers d'une place
			for i, side in { -1, 1 } do
				local px = side * (w / 2 - arm - 0.8)
				local surface = if i == 1 then "FabricRed" else "Linen"
				bit(parts, "ThrowPillow", surface, px, seatH + 0.42, -d / 2 + back + 0.25, 1.1, 1.1, 0.35, nil, {
					-15,
					0,
					side * (8 + rnd() * 6),
				})
			end
			bit(parts, "Plaid", "Blanket", w * 0.15, seatH + 0.4, 0.2, 1.4, 0.15, 1.1, nil, { 0, 10 + rnd() * 15, 0 })
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

-- Cette méthode permet de construire une bibliothèque ouverte (fond, côtés, tablettes garnies) lorsque le meuble est
-- haut et ouvert ; items = nil pour des rangées de livres (#38), sinon les objets du catalogue posés sur les tablettes.
local function bookcase(body: string, items: { string }?, glass: boolean?)
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
		local parts = {}
		local t = 0.2
		add(parts, "Back", body, -w / 2, 0, -d / 2, w / 2, h, -d / 2 + t)
		add(parts, "SideLeft", body, -w / 2, 0, -d / 2, -w / 2 + t, h, d / 2)
		add(parts, "SideRight", body, w / 2 - t, 0, -d / 2, w / 2, h, d / 2)
		add(parts, "Top", body, -w / 2 + t, h - t, -d / 2, w / 2 - t, h, d / 2)
		local shelves = math.max(2, math.floor(h / 1.6))
		local gap = (h - t) / shelves
		local front = d / 2 - (if glass then 0.12 else 0.05)
		for i = 1, shelves do
			local y = (i - 1) * gap
			add(parts, "Shelf" .. i, body, -w / 2 + t, y, -d / 2 + t, w / 2 - t, y + t, d / 2)
			local x0, x1, z0 = -w / 2 + t + 0.05, w / 2 - t - 0.05, -d / 2 + t + 0.05
			if items then
				fillRow(parts, rnd, items, x0, x1, y + t, z0, front, gap - t - 0.1, 0.25)
			else
				bookRow(parts, rnd, x0, x1, y + t, z0, front, gap - t - 0.1)
			end
		end
		if glass then
			add(parts, "Glass", "ShowerGlass", -w / 2 + t, t, d / 2 - 0.08, w / 2 - t, h - t, d / 2 - 0.02)
		end
		return parts
	end
end

-- Cette méthode permet de construire une étagère métallique (montants, plateaux, objets rangés) lorsque le meuble est un
-- rangement de cave, de garage ou d'atelier ; items = objets du catalogue tirés pour chaque plateau.
local function rack(post: string, board: string, items: { string })
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
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
			if i < boards then
				local nextY = math.min(i * gap + 0.3, h - 0.15)
				local x0, x1 = -w / 2 + p + 0.05, w / 2 - p - 0.05
				fillRow(parts, rnd, items, x0, x1, y + 0.15, -d / 2 + 0.05, d / 2 - 0.05, nextY - y - 0.25, 0.6)
			end
		end
		return parts
	end
end

-- Cette méthode permet de construire un casier à bouteilles (cadre, tablettes, bouteilles couchées goulot vers l'avant,
-- quelques cases vides) lorsque le meuble est dans la cave à vin.
local function wineRack(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local t = 0.25
	add(parts, "SideLeft", "WoodDark", -w / 2, 0, -d / 2, -w / 2 + t, h, d / 2)
	add(parts, "SideRight", "WoodDark", w / 2 - t, 0, -d / 2, w / 2, h, d / 2)
	add(parts, "Top", "WoodDark", -w / 2 + t, h - t, -d / 2, w / 2 - t, h, d / 2)
	local count = 5
	local gap = (h - t) / count
	local slots = math.floor((w - 2 * t - 0.1) / 0.5)
	for i = 1, count do
		local y = (i - 1) * gap
		add(parts, "Board" .. i, "WoodDark", -w / 2 + t, y, -d / 2, w / 2 - t, y + 0.2, d / 2)
		for k = 1, slots do
			if rnd() < 0.86 then
				local cx = -slots * 0.25 + (k - 0.5) * 0.5
				local color = pick(rnd, BOTTLE_COLORS)
				bit(parts, "Bottle", color, cx, y + 0.2, -d / 2 + 0.6, 0.42, 0.42, 1, "Z")
				bit(parts, "BottleNeck", color, cx, y + 0.33, -d / 2 + 1.24, 0.16, 0.16, 0.28, "Z")
			end
		end
	end
	return parts
end

-- Cette méthode permet de construire un lit (cadre, matelas, couette, oreillers, tête de lit au fond) lorsque la pièce
-- est une chambre ; l'avant du lit est le pied. extra (#38) : « Throw » plaid au pied, « Teddy » ours assis contre
-- l'oreiller, « Clothes » vêtements jetés sur la couette.
local function bed(blanket: string, extra: string?)
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
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
		if extra == "Throw" then
			bit(parts, "Plaid", "FabricRed", 0, 2, d / 2 - 1, w - 0.2, 0.15, 1.2)
		elseif extra == "Teddy" then
			ITEMS.Teddy.build(parts, rnd, w / 2 - 0.9, 1.8, -d / 2 + head + 1.85)
		elseif extra == "Clothes" then
			ITEMS.Clothes.build(parts, rnd, -w / 4, 2, d / 4)
			ITEMS.Clothes.build(parts, rnd, w / 5, 2, d / 2 - 1)
		end
		return parts
	end
end

-- Cette méthode permet de construire une grande plante en pot (pot, tige, feuillage en boules) lorsque le meuble est
-- une plante d'intérieur.
local function plant(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local size = math.min(w, d)
	add(parts, "Pot", "Terracotta", -size * 0.3, 0, -size * 0.3, size * 0.3, h * 0.22, size * 0.3)
	parts[#parts].shape = "Y"
	add(parts, "Stem", "WoodDark", -0.08, h * 0.22, -0.08, 0.08, h * 0.6, 0.08)
	for i = 1, 3 do
		local r = size * (0.32 + rnd() * 0.12)
		local y = h - 2 * r - (i - 1) * h * 0.14
		local ox = (rnd() * 2 - 1) * (size / 2 - r)
		local oz = (rnd() * 2 - 1) * (size / 2 - r)
		add(parts, "Leaves" .. i, "Foliage", ox - r, y, oz - r, ox + r, y + 2 * r, oz + r)
		parts[#parts].shape = "Ball"
	end
	return parts
end

-- Cette méthode permet de construire un meuble oublié sous un drap (masse drapée, dossier, pan qui traîne) lorsque le
-- meuble est un encombrement de grenier.
local function covered(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	add(parts, "Sheet", "DustSheet", -w / 2 + 0.1, 0, -d / 2 + 0.1, w / 2 - 0.1, h * 0.6, d / 2 - 0.1)
	add(parts, "SheetBack", "DustSheet", -w / 2 + 0.2, h * 0.6, -d / 2 + 0.1, w / 2 - 0.2, h - 0.05, -d / 2 + 0.9)
	add(parts, "SheetHem", "DustSheet", -w / 2, 0, -d / 2, w / 2, 0.5, d / 2)
	local a = (rnd() * 2 - 1) * 6
	bit(parts, "SheetFold", "DustSheet", 0, h * 0.6 - 0.05, 0.2, w * 0.6, 0.15, d * 0.4, nil, { 0, a, 0 })
	return parts
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

-- Meubles par style : chaque fonction reçoit largeur (latérale), hauteur, profondeur et un tirage propre au meuble
-- (HouseStyle.random), et rend ses blocs locaux. Un meuble sans style reste un bloc plein (disjoncteur).
HouseStyle.furniture = {
	Sofa = seat("FabricBlue", "FabricLight", true),
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
	Bookcase = bookcase("WoodDark"),
	Dresser = bookcase("PaintedWhite", { "PlateStack", "Bowl", "Mug", "Jar", "StandingPlate", "Glass" }),
	DisplayCabinet = bookcase("Wood", { "StandingPlate", "StandingPlate", "Glass", "Bowl", "Vase", "Candle" }, true),
	Rack = rack("MetalDark", "Metal", { "Carton", "PaintCan", "Toolbox", "Jar", "Carton" }),
	LaundryRack = rack("MetalDark", "Metal", { "Detergent", "FoldedTowel", "Carton", "Detergent" }),
	WoodRack = rack("WoodDark", "WoodRaw", { "Carton", "SmallCarton", "Bucket", "Carton" }),
	PantryRack = rack("WoodDark", "WoodRaw", { "Jar", "Jar", "Bottle", "Carton" }),
	GardenRack = rack("WoodDark", "WoodRaw", { "PlantPot", "PaintCan", "Bucket", "WateringCan" }),
	WineRack = wineRack,
	Bed = bed("Blanket", "Throw"),
	KidsBed = bed("FabricRed", "Teddy"),
	TeenBed = bed("Denim", "Clothes"),
	Plant = plant,
	Covered = covered,
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

----------------------------------------------------------------------------------------------------------------------
-- Garnitures (#38) : petits objets posés sur un meuble, accrochés au mur ou jetés au sol (HouseLayout.clutter). Repère
-- local comme un meuble : x latéral, y vers le haut depuis la surface, z de l'arrière (mur, dos du meuble) vers l'avant.
----------------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser une barre entre deux points d'un plan vertical (x, y) lorsque l'on dessine un cadre de
-- vélo, un fil ou un manche ; z = centre en profondeur.
local function tube(
	parts: { Part },
	name: string,
	surface: string,
	xa: number,
	ya: number,
	xb: number,
	yb: number,
	z: number,
	thick: number
)
	local dx, dy = xb - xa, yb - ya
	local length = math.sqrt(dx * dx + dy * dy)
	local a = math.deg(math.atan2(dy, dx))
	local cx, cy = (xa + xb) / 2, (ya + yb) / 2
	bit(parts, name, surface, cx, cy - thick / 2, z, length, thick, thick, nil, { 0, 0, a })
end

-- Cette méthode permet de poser une barre couchée entre deux points du sol (x, z) lorsque l'on dessine un vélo tombé.
local function flatTube(
	parts: { Part },
	name: string,
	surface: string,
	xa: number,
	za: number,
	xb: number,
	zb: number,
	y: number,
	thick: number
)
	local dx, dz = xb - xa, zb - za
	local length = math.sqrt(dx * dx + dz * dz)
	local a = math.deg(math.atan2(-dz, dx))
	bit(parts, name, surface, (xa + xb) / 2, y, (za + zb) / 2, length, thick, thick, nil, { 0, a, 0 })
end

-- Cette méthode permet de construire un tableau encadré (cadre, toile peinte) lorsque l'on habille un mur ; style =
-- « Landscape » (ciel et terre), « Portrait » (silhouette sans visage sur fond sombre) ou « Abstract ».
local function painting(style: string)
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
		local parts = {}
		local back = -d / 2
		add(parts, "Frame", pick(rnd, { "WoodDark", "Brass", "Wood" }), -w / 2, 0, back, w / 2, h, back + 0.1)
		local m = math.min(0.25, w * 0.1, h * 0.1)
		local x0, x1, y0, y1, z0, z1 = -w / 2 + m, w / 2 - m, m, h - m, back + 0.1, back + 0.13
		if style == "Landscape" then
			local horizon = y0 + (y1 - y0) * (0.3 + rnd() * 0.25)
			add(parts, "CanvasSky", pick(rnd, { "PaintingSky", "PaintingOchre" }), x0, horizon, z0, x1, y1, z1)
			add(parts, "CanvasLand", pick(rnd, { "PaintingField", "PaintingDark" }), x0, y0, z0, x1, horizon, z1)
		elseif style == "Portrait" then
			add(parts, "Canvas", "PaintingDark", x0, y0, z0, x1, y1, z1)
			local fw = (x1 - x0) * 0.36
			local fy = y0 + (y1 - y0) * 0.45
			add(parts, "Face", "PaintingSkin", -fw / 2, fy, z1, fw / 2, math.min(fy + fw * 1.3, y1 - 0.1), z1 + 0.02)
			local sw = (x1 - x0) * 0.7
			add(
				parts,
				"Shoulders",
				pick(rnd, { "BookBlack", "WallpaperRed", "Denim" }),
				-sw / 2,
				y0,
				z1,
				sw / 2,
				fy,
				z1 + 0.02
			)
		else
			add(parts, "Canvas", pick(rnd, { "PaintingOchre", "Linen", "PaintingSky" }), x0, y0, z0, x1, y1, z1)
			for i = 1, 2 do
				local bw, bh = (x1 - x0) * (0.25 + rnd() * 0.3), (y1 - y0) * (0.2 + rnd() * 0.3)
				local bx = x0 + rnd() * (x1 - x0 - bw)
				local by = y0 + rnd() * (y1 - y0 - bh)
				local color = pick(rnd, { "PaintedRed", "BookBlack", "BookTeal", "FruitOrange" })
				add(parts, "Shape" .. i, color, bx, by, z1, bx + bw, by + bh, z1 + 0.02)
			end
		end
		return parts
	end
end

-- Cette méthode permet de construire un groupe de photos encadrées de tailles variées lorsque l'on habille un mur de
-- souvenirs de famille.
local function photos(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	local columns = math.max(1, math.floor(w / 1.1))
	for row = 1, 2 do
		for col = 1, columns do
			if rnd() < 0.8 then
				local fw, fh = 0.6 + rnd() * 0.35, 0.6 + rnd() * 0.4
				local cx = -w / 2 + (col - 0.5) * w / columns
				local cy = (row - 0.5) * h / 2
				fh = math.min(fh, h / 2 - 0.1)
				add(
					parts,
					"PhotoFrame",
					pick(rnd, { "WoodDark", "BookBlack", "PaintedWhite" }),
					cx - fw / 2,
					cy - fh / 2,
					back,
					cx + fw / 2,
					cy + fh / 2,
					back + 0.08
				)
				local photo = pick(rnd, { "PaintingSky", "PaintingSkin", "PaintingField", "BookGrey" })
				add(
					parts,
					"Photo",
					photo,
					cx - fw / 2 + 0.1,
					cy - fh / 2 + 0.1,
					back + 0.08,
					cx + fw / 2 - 0.1,
					cy + fh / 2 - 0.1,
					back + 0.1
				)
			end
		end
	end
	return parts
end

-- Cette méthode permet de construire un miroir encadré lorsque l'on habille une entrée, une salle de bain ou une chambre.
local function mirror(w: number, h: number, d: number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "MirrorFrame", "WoodDark", -w / 2, 0, back, w / 2, h, back + 0.08)
	add(parts, "Mirror", "Mirror", -w / 2 + 0.15, 0.15, back + 0.08, w / 2 - 0.15, h - 0.15, back + 0.11)
	return parts
end

-- Cette méthode permet de construire une horloge murale arrêtée à 3 h 40 (cadran rond, aiguilles) lorsque l'on habille
-- un mur.
local function clock(w: number, h: number, d: number): { Part }
	local parts = {}
	local back = -d / 2
	local size = math.min(w, h)
	bit(parts, "Clock", "WoodDark", 0, h / 2 - size / 2, back + 0.06, size, size, 0.12, "Z")
	bit(parts, "ClockFace", "Paper", 0, h / 2 - size / 2 + 0.1, back + 0.13, size - 0.2, size - 0.2, 0.02, "Z")
	for _, hand in { { "HourHand", 110, size * 0.25 }, { "MinuteHand", 240, size * 0.38 } } do
		local a, length = math.rad(hand[2]), hand[3]
		local cx, cy = math.sin(a) * length / 2, h / 2 + math.cos(a) * length / 2
		bit(parts, hand[1], "BookBlack", cx, cy - length / 2, back + 0.15, 0.06, length, 0.02, nil, { 0, 0, -hand[2] })
	end
	return parts
end

-- Cette méthode permet de construire une étagère murale (planche, équerres, objets alignés) lorsque l'on habille un mur ;
-- items = objets du catalogue.
local function wallShelf(items: { string })
	return function(w: number, h: number, d: number, rnd: () -> number): { Part }
		local parts = {}
		local back = -d / 2
		add(parts, "Board", "WoodDark", -w / 2, 0.3, back, w / 2, 0.42, d / 2)
		add(parts, "BracketLeft", "MetalDark", -w / 2 + 0.25, 0, back, -w / 2 + 0.31, 0.3, back + d * 0.7)
		add(parts, "BracketRight", "MetalDark", w / 2 - 0.31, 0, back, w / 2 - 0.25, 0.3, back + d * 0.7)
		fillRow(parts, rnd, items, -w / 2 + 0.05, w / 2 - 0.05, 0.42, back + 0.02, d / 2, h - 0.42, 0.2)
		return parts
	end
end

-- Cette méthode permet de construire une barre à ustensiles (barre, louches, spatules, poêle suspendue) lorsque l'on
-- habille le mur d'une cuisine.
local function utensils(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "Rail", "Metal", -w / 2, h - 0.12, back, w / 2, h - 0.04, back + 0.12)
	local x = -w / 2 + 0.4
	while x < w / 2 - 0.5 do
		if rnd() < 0.25 then
			bit(parts, "HangingPan", "Copper", x + 0.05, h - 1.05, back + 0.12, 0.8, 0.8, 0.06, "Z")
			x += 1
		else
			local length = 0.8 + rnd() * 0.4
			bit(
				parts,
				"Utensil",
				pick(rnd, { "Metal", "WoodLight", "MetalDark" }),
				x,
				h - 0.1 - length,
				back + 0.16,
				0.12,
				length,
				0.05
			)
			x += 0.45
		end
	end
	return parts
end

-- Cette méthode permet de construire des patères (planche, crochets, manteaux pendus) lorsque l'on habille une entrée.
local function coatHooks(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "Rail", "WoodDark", -w / 2, h - 0.45, back, w / 2, h - 0.15, back + 0.12)
	local n = math.max(2, math.floor(w / 0.9))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n
		bit(parts, "Hook", "Brass", x, h - 0.5, back + 0.17, 0.08, 0.2, 0.1)
		if rnd() < 0.75 then
			local length = math.min(2.2 + rnd() * 0.9, h - 0.5)
			local color = pick(rnd, { "Denim", "ClothesGrey", "FabricRed", "Leather", "BookBlack", "PaintedGreen" })
			bit(parts, "Coat", color, x, h - 0.4 - length, back + 0.37, 0.85, length, 0.45)
		end
	end
	return parts
end

-- Cette méthode permet de construire un panneau à outils (planche, outils suspendus) lorsque l'on habille le mur d'un
-- garage ou d'un atelier.
local function pegboard(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "Pegboard", "WoodRaw", -w / 2, 0, back, w / 2, h, back + 0.08)
	local z = back + 0.12
	local x = -w / 2 + 0.45
	while x < w / 2 - 0.4 do
		local length = 0.7 + rnd() * 0.6
		local y = 0.25 + rnd() * (h - 0.5 - length)
		local kind = math.floor(rnd() * 3)
		if kind == 0 then
			bit(parts, "HammerHandle", "WoodLight", x, y, z, 0.12, length, 0.06)
			bit(parts, "HammerHead", "MetalDark", x, y + length - 0.16, z + 0.02, 0.5, 0.16, 0.08)
		elseif kind == 1 then
			bit(parts, "Tool", "Metal", x, y + 0.35, z, 0.1, length - 0.35, 0.05)
			bit(parts, "ToolGrip", pick(rnd, TOY_COLORS), x, y, z, 0.16, 0.35, 0.08)
		else
			bit(parts, "SawBlade", "Metal", x, y + 0.35, z, 0.45, length - 0.35, 0.03)
			bit(parts, "SawHandle", "WoodLight", x, y, z, 0.4, 0.35, 0.06)
		end
		x += 0.6 + rnd() * 0.3
	end
	return parts
end

-- Cette méthode permet de construire des dessins d'enfant punaisés de travers (feuilles et gribouillis) lorsque l'on
-- habille une chambre d'enfant.
local function drawings(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	local n = math.max(1, math.floor(w / 1))
	for i = 1, n do
		if rnd() < 0.85 then
			local cx = -w / 2 + (i - 0.5) * w / n
			local y = rnd() * (h - 0.9)
			local a = (rnd() * 2 - 1) * 10
			bit(parts, "Drawing", "Paper", cx, y + 0.15, back + 0.01, 0.8, 0.6, 0.02, nil, { 0, 0, a })
			bit(parts, "Scribble", pick(rnd, TOY_COLORS), cx, y + 0.41, back + 0.03, 0.5, 0.08, 0.02, nil, { 0, 0, a })
		end
	end
	return parts
end

-- Cette méthode permet de construire des affiches (feuilles larges, bandeau de couleur) lorsque l'on habille une chambre
-- d'ado.
local function posters(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	local n = math.max(1, math.floor(w / 1.7))
	for i = 1, n do
		local cx = -w / 2 + (i - 0.5) * w / n
		local pw, ph = 1.3 + rnd() * 0.2, math.min(1.8 + rnd() * 0.4, h)
		local y = rnd() * (h - ph)
		local color = pick(rnd, { "PaintedRed", "BookBlack", "BookTeal", "PaintingOchre", "ToyBlue" })
		add(parts, "Poster", color, cx - pw / 2, y, back, cx + pw / 2, y + ph, back + 0.02)
		add(
			parts,
			"PosterBand",
			pick(rnd, { "Paper", "ToyYellow", "BookBlack" }),
			cx - pw / 2 + 0.1,
			y + ph * 0.7,
			back + 0.02,
			cx + pw / 2 - 0.1,
			y + ph * 0.85,
			back + 0.03
		)
	end
	return parts
end

-- Cette méthode permet de construire un calendrier punaisé (feuilles, bandeau du mois) lorsque l'on habille une cuisine.
local function calendar(w: number, h: number, d: number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "Calendar", "Paper", -w / 2, 0, back, w / 2, h, back + 0.03)
	add(parts, "CalendarMonth", "PaintedRed", -w / 2, h * 0.75, back + 0.03, w / 2, h, back + 0.05)
	return parts
end

-- Cette méthode permet de construire un porte-serviettes (barre, supports, serviette pendue) lorsque l'on habille une
-- salle de bain.
local function towelRail(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "BracketLeft", "Metal", -w / 2, h - 0.25, back, -w / 2 + 0.08, h - 0.15, back + 0.25)
	add(parts, "BracketRight", "Metal", w / 2 - 0.08, h - 0.25, back, w / 2, h - 0.15, back + 0.25)
	add(parts, "Rail", "Metal", -w / 2, h - 0.25, back + 0.17, w / 2, h - 0.15, back + 0.25)
	local towel = pick(rnd, { "TowelWhite", "TowelBlue", "FabricRed" })
	add(
		parts,
		"Towel",
		towel,
		-w / 2 + 0.2,
		h - 0.1 - math.min(1.4, h - 0.1),
		back + 0.25,
		w / 2 - 0.2,
		h - 0.1,
		back + 0.33
	)
	return parts
end

-- Cette méthode permet de construire un vélo, debout contre un mur ou couché au sol (roues, cadre, selle, guidon)
-- lorsque l'on habille un garage ou un jardin.
local function bike(lying: boolean)
	return function(_w: number, _h: number, d: number, rnd: () -> number): { Part }
		local parts = {}
		local frame = pick(rnd, { "ToyRed", "PaintedGreen", "ToyBlue" })
		local r = 1.05
		-- Points du vélo vu de profil (u le long du vélo, v vers le haut)
		local points = {
			rear = { -1.25, r },
			crank = { 0, r },
			seat = { -0.3, 2 },
			head = { 0.9, 2 },
			front = { 1.25, r },
		}
		local bars = {
			{ "TopTube", "seat", "head" },
			{ "DownTube", "head", "crank" },
			{ "SeatTube", "crank", "seat" },
			{ "ChainStay", "rear", "crank" },
			{ "SeatStay", "rear", "seat" },
			{ "Fork", "head", "front" },
		}
		if lying then
			-- Couché sur le flanc : le profil se lit dans le plan du sol (v devient la profondeur)
			local function zOf(v: number): number
				return v - 1.2
			end
			for i, u in { points.rear[1], points.front[1] } do
				bit(parts, "Wheel" .. i, "Rubber", u, 0, zOf(r), 2.1, 0.1, 2.1, "Y")
				bit(parts, "Rim" .. i, "Metal", u, 0.02, zOf(r), 1.7, 0.12, 1.7, "Y")
			end
			for _, b in bars do
				local a, c = points[b[2]], points[b[3]]
				flatTube(parts, b[1], frame, a[1], zOf(a[2]), c[1], zOf(c[2]), 0.14, 0.1)
			end
			bit(parts, "Saddle", "Leather", -0.35, 0.14, zOf(2.15), 0.6, 0.12, 0.25)
			bit(parts, "Handlebar", "MetalDark", 1, 0.14, zOf(2.35), 0.1, 0.1, 0.8)
		else
			local z = -d / 2 + 0.45
			for i, u in { points.rear[1], points.front[1] } do
				bit(parts, "Wheel" .. i, "Rubber", u, 0, z, 2.1, 2.1, 0.1, "Z")
				bit(parts, "Rim" .. i, "Metal", u, 0.2, z, 1.7, 1.7, 0.12, "Z")
			end
			for _, b in bars do
				local a, c = points[b[2]], points[b[3]]
				tube(parts, b[1], frame, a[1], a[2], c[1], c[2], z, 0.1)
			end
			bit(parts, "Saddle", "Leather", -0.35, 2.05, z, 0.6, 0.12, 0.25)
			bit(parts, "Handlebar", "MetalDark", 1, 2.3, z, 0.1, 0.1, 0.8)
		end
		return parts
	end
end

-- Cette méthode permet de construire des outils de jardin appuyés contre un mur (manches inclinés, têtes au sol) lorsque
-- l'on habille un abri, un garage ou une buanderie.
local function leaningTools(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local n = math.max(1, math.floor(w / 0.6))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n
		local kind = math.floor(rnd() * 3)
		local base = if kind == 0 then 0.35 else 0.12
		local length = math.min(3.8 + rnd() * 0.8, h - base - 0.2)
		local front = d / 2 - 0.25
		local a = math.asin(math.min(0.5, (d - 0.5) / length))
		local cy = base + length / 2 * math.cos(a)
		local cz = front - length / 2 * math.sin(a)
		bit(parts, "Handle", "WoodLight", x, cy - length / 2, cz, 0.12, length, 0.12, nil, { -math.deg(a), 0, 0 })
		if kind == 0 then
			bit(parts, "Bristles", "WoodRaw", x, 0, front, 0.5, 0.35, 0.3)
		elseif kind == 1 then
			bit(parts, "RakeHead", "MetalDark", x, 0, front, 0.5, 0.12, 0.25)
		else
			bit(parts, "ShovelBlade", "Metal", x, 0, front - 0.05, 0.45, 0.12, 0.3)
		end
	end
	return parts
end

-- Cette méthode permet de construire une toile d'araignée tendue dans un angle (voile pâle en diagonale) lorsque l'on
-- habille une cave, un grenier ou un abri ; angle = 45 pour l'angle de gauche, -45 pour celui de droite.
local function cobweb(angle: number)
	return function(w: number, h: number, d: number): { Part }
		local parts = {}
		local span = math.min(w, d) * 1.38
		bit(parts, "Cobweb", "Cobweb", 0, 0, 0, span, h, 0.02, nil, { 0, angle, 0 })
		return parts
	end
end

-- Cette méthode permet de construire un tableau de liège couvert de notes, de photos et de fils rouges lorsque l'on
-- habille un bureau (quelqu'un enquêtait ici).
local function corkboard(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "Corkboard", "Cork", -w / 2, 0, back, w / 2, h, back + 0.08)
	add(parts, "CorkFrame", "WoodDark", -w / 2, h - 0.1, back, w / 2, h, back + 0.12)
	local notes = {}
	local columns = math.max(2, math.floor(w / 0.9))
	for i = 1, columns do
		local cx = -w / 2 + (i - 0.5) * w / columns
		local cy = 0.5 + rnd() * (h - 1.1)
		local surface = pick(rnd, { "Paper", "Paper", "PaintingSkin", "ToyYellow" })
		bit(parts, "Note", surface, cx, cy - 0.3, back + 0.09, 0.55, 0.6, 0.02, nil, { 0, 0, (rnd() * 2 - 1) * 8 })
		table.insert(notes, { cx, cy })
	end
	for i = 1, #notes - 1 do
		local a, b = notes[i], notes[i + 1]
		tube(parts, "String", "PaintedRed", a[1], a[2], b[1], b[2], back + 0.12, 0.03)
	end
	return parts
end

-- Cette méthode permet de construire un écran plat fixé au mur (cadre noir, dalle éteinte) lorsque l'on habille une
-- chambre d'ado.
local function wallTv(w: number, h: number, d: number): { Part }
	local parts = {}
	local back = -d / 2
	add(parts, "TvBezel", "Plastic", -w / 2, 0, back, w / 2, h, back + 0.12)
	add(parts, "TvScreen", "Screen", -w / 2 + 0.08, 0.08, back + 0.12, w / 2 - 0.08, h - 0.08, back + 0.14)
	return parts
end

-- Cette méthode permet de construire des cadres posés au sol et appuyés contre le mur (cadre, toile) lorsque l'on
-- habille un grenier.
local function leaningFrames(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local n = math.max(1, math.floor(w / 1.4))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n
		local fw = math.min(1.2, w / n - 0.1)
		local fh = math.min(1.2 + rnd() * 1.2, h - 0.1)
		local cz = -d / 2 + 0.1 + fh * math.sin(math.rad(8)) / 2 + i * 0.12
		-- Centre à la demi-hauteur de la boîte englobante du cadre penché : son coin bas touche le sol
		local cy = (fh * math.cos(math.rad(8)) + 0.08 * math.sin(math.rad(8))) / 2
		local frame = pick(rnd, { "WoodDark", "Brass", "Wood" })
		bit(parts, "OldFrame", frame, x, cy - fh / 2, cz, fw, fh, 0.08, nil, { -8, 0, 0 })
		bit(
			parts,
			"OldCanvas",
			pick(rnd, { "PaintingDark", "PaintingSky", "PaintingField", "PaintingSkin" }),
			x,
			cy - (fh - 0.3) / 2,
			cz + 0.05,
			fw - 0.25,
			fh - 0.3,
			0.02,
			nil,
			{ -8, 0, 0 }
		)
	end
	return parts
end

-- Cette méthode permet de construire un téléviseur posé (pied, écran) lorsque l'on garnit un meuble télé.
local function tv(w: number, h: number, d: number): { Part }
	local parts = {}
	local sw, sh = math.min(w - 0.2, 3.6), math.min(h - 0.35, 2.1)
	bit(parts, "TvFoot", "Plastic", 0, 0, 0, 1.2, 0.08, math.min(0.6, d))
	bit(parts, "TvNeck", "Plastic", 0, 0.08, -0.05, 0.2, 0.3, 0.1)
	bit(parts, "TvBezel", "Plastic", 0, 0.35, -0.05, sw, sh, 0.12)
	bit(parts, "TvScreen", "Screen", 0, 0.42, 0.02, sw - 0.14, sh - 0.14, 0.02)
	return parts
end

-- Cette méthode permet de dresser une table (assiettes et verres face aux chaises, couverts, bougies, coupe de fruits,
-- un verre renversé) lorsque l'on garnit la table de la salle à manger.
local function tableSetting(w: number, _h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local px = math.min(3, w * 0.3)
	local pz = d / 2 - 0.6
	for i, place in { { -px, -1 }, { px, -1 }, { -px, 1 }, { px, 1 } } do
		local x, side = place[1], place[2]
		local z = side * pz
		local skew = if i == 3 then 25 else (rnd() * 2 - 1) * 5
		bit(parts, "Plate", "Dishes", x, 0, z, 0.9, 0.08, 0.9, "Y")
		bit(parts, "Fork", "Metal", x - 0.6, 0, z, 0.08, 0.03, 0.7, nil, { 0, skew, 0 })
		bit(parts, "Knife", "Metal", x + 0.6, 0, z, 0.08, 0.03, 0.75, nil, { 0, skew, 0 })
		if i == 2 then
			-- Verre renversé, couché sur le flanc
			bit(
				parts,
				"Glass",
				"GlassClear",
				x + 0.95,
				0.14 - 0.225,
				z - side * 0.45,
				0.28,
				0.45,
				0.28,
				"Y",
				{ 0, 0, 90 }
			)
		else
			bit(parts, "Glass", "GlassClear", x + 0.75, 0, z - side * 0.55, 0.28, 0.45, 0.28, "Y")
		end
	end
	ITEMS.FruitBowl.build(parts, rnd, 0, 0, 0)
	ITEMS.Candle.build(parts, rnd, -1, 0, 0)
	ITEMS.Candle.build(parts, rnd, 1, 0, 0)
	return parts
end

-- Cette méthode permet de construire un panier à linge (fond, bords en osier, linge qui déborde) lorsque l'on garnit
-- le sol d'une buanderie.
local function laundryBasket(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local t, top = 0.08, math.min(0.85, h - 0.15)
	add(parts, "BasketBottom", "Rattan", -w / 2, 0, -d / 2, w / 2, t, d / 2)
	add(parts, "BasketBack", "Rattan", -w / 2, t, -d / 2, w / 2, top, -d / 2 + t)
	add(parts, "BasketFront", "Rattan", -w / 2, t, d / 2 - t, w / 2, top, d / 2)
	add(parts, "BasketLeft", "Rattan", -w / 2, t, -d / 2 + t, -w / 2 + t, top, d / 2 - t)
	add(parts, "BasketRight", "Rattan", w / 2 - t, t, -d / 2 + t, w / 2, top, d / 2 - t)
	for _ = 1, 2 do
		bit(
			parts,
			"Laundry",
			pick(rnd, CLOTHES_COLORS),
			0,
			top - 0.2,
			0,
			w * 0.55,
			0.3,
			d * 0.5,
			nil,
			{ 0, (rnd() * 2 - 1) * 20, 0 }
		)
	end
	return parts
end

-- Cette méthode permet de construire une valise couchée (coque, poignée, sangles) lorsque l'on garnit une chambre
-- d'amis.
local function suitcase(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local sw, sh, sd = w - 0.4, math.min(0.8, h), d - 0.2
	add(parts, "Suitcase", pick(rnd, { "Leather", "Denim", "PaintedRed" }), -sw / 2, 0, -sd / 2, sw / 2, sh, sd / 2)
	add(parts, "SuitcaseHandle", "BookBlack", -0.4, sh * 0.35, sd / 2, 0.4, sh * 0.55, sd / 2 + 0.1)
	for i, x in { -sw / 4, sw / 4 } do
		add(parts, "Strap" .. i, "BookBlack", x - 0.08, sh, -sd / 2, x + 0.08, sh + 0.02, sd / 2)
	end
	return parts
end

-- Cette méthode permet de construire une caisse de vin entamée (caisse ouverte, goulots qui dépassent) lorsque l'on
-- garnit le sol de la cave à vin.
local function wineCrate(w: number, h: number, d: number, rnd: () -> number): { Part }
	local parts = {}
	local top = math.min(0.6, h - 0.35)
	add(parts, "Crate", "WoodRaw", -w / 2, 0, -d / 2, w / 2, top, d / 2)
	local columns, lines = math.max(1, math.floor(w / 0.5)), math.max(1, math.floor(d / 0.5))
	for i = 1, columns do
		for j = 1, lines do
			if rnd() < 0.7 then
				local x = -w / 2 + (i - 0.5) * w / columns
				local z = -d / 2 + (j - 0.5) * d / lines
				bit(parts, "BottleNeck", pick(rnd, BOTTLE_COLORS), x, top, z, 0.14, 0.3, 0.14, "Y")
			end
		end
	end
	return parts
end

-- Garnitures par nom : chaque fonction reçoit largeur, hauteur et profondeur de son emplacement et un tirage propre
-- (HouseStyle.random), et rend des blocs qui restent dans cet emplacement.
HouseStyle.clutter = {
	-- Sur un meuble
	CoffeeTable = rowsOf({ "Papers", "Mug", "BookPile", "Candle", "Phone", "OpenBook" }, 2),
	Tv = tv,
	Lamp = single("Lamp"),
	EntryTray = rowsOf({ "Bowl", "Papers", "Phone" }),
	TableSetting = tableSetting,
	SideboardDecor = rowsOf({ "Candle", "Vase", "PhotoFrame", "Bottle", "Glass" }),
	KitchenPrep = rowsOf({ "CuttingBoard", "Kettle", "Jar", "Jar", "Bottle", "Mug" }),
	KitchenSnack = rowsOf({ "Toaster", "FruitBowl", "Jar", "Glass", "Bottle" }),
	IslandMess = rowsOf({ "Pot", "Pan", "FruitBowl", "Bowl", "Glass", "Papers", "Bottle", "Mug" }, 2),
	Laptop = rowsOf({ "Laptop", "Mug", "PencilCup" }),
	DeskMess = rowsOf({ "Papers", "BookPile", "Mug", "OpenBook", "PencilCup" }, 2),
	ReadingLamp = rowsOf({ "Lamp", "Candle", "PencilCup" }),
	ReadingPile = rowsOf({ "BookPile", "OpenBook", "Papers", "Glass" }),
	Bedside = rowsOf({ "Lamp", "AlarmClock", "BookPile", "Glass", "Phone" }),
	Vanity = rowsOf({ "PhotoFrame", "SoapBottle", "Candle", "Vase", "Bowl" }),
	Laundry = rowsOf({ "FoldedTowel", "Detergent", "FoldedTowel" }),
	Toiletries = rowsOf({ "SoapBottle", "ToothCup", "SoapBottle" }),
	KidsDesk = rowsOf({ "Papers", "PencilCup", "BookPile", "Block", "ToyCar" }),
	TeenDesk = rowsOf({ "Mug", "Bottle", "Phone", "Glass", "BookPile" }),
	Tools = rowsOf({ "Hammer", "Wrench", "Screwdriver", "Saw", "PaintCan", "Radio", "Toolbox", "Jar" }, 2),
	Project = rowsOf({ "Saw", "Hammer", "Papers", "PaintCan", "Mug", "Wrench" }, 2),
	Wine = rowsOf({ "Bottle", "Glass", "Candle", "Bottle" }),
	Tea = rowsOf({ "Kettle", "Mug", "Mug", "Papers", "OpenBook" }),
	Potting = rowsOf({ "PlantPot", "SmallPot", "WateringCan" }),
	Hardware = rowsOf({ "PaintCan", "Jar", "Hammer", "Wrench" }),
	Jars = rowsOf({ "Jar", "Jar", "Bottle", "Bowl" }),
	-- Au mur
	Landscape = painting("Landscape"),
	Portrait = painting("Portrait"),
	Abstract = painting("Abstract"),
	Photos = photos,
	Mirror = mirror,
	Clock = clock,
	SpiceShelf = wallShelf({ "Jar", "Jar", "Mug", "Bottle" }),
	ToyShelf = wallShelf({ "Teddy", "ToyBall", "Block", "ToyCar", "BookPile" }),
	BathShelf = wallShelf({ "SoapBottle", "ToothCup", "FoldedTowel" }),
	DetergentShelf = wallShelf({ "Detergent", "Bottle", "Detergent" }),
	Utensils = utensils,
	CoatHooks = coatHooks,
	Pegboard = pegboard,
	Drawings = drawings,
	Posters = posters,
	Calendar = calendar,
	TowelRail = towelRail,
	Bike = bike(false),
	LeaningTools = leaningTools,
	CobwebLeft = cobweb(45),
	CobwebRight = cobweb(-45),
	Corkboard = corkboard,
	WallTv = wallTv,
	LeaningFrames = leaningFrames,
	-- Au sol (une marche de haut au plus)
	Toys = rowsOf({ "Block", "Block", "ToyBall", "ToyCar", "Teddy", "BookPile" }, 2),
	Shoes = rowsOf({ "Shoes" }, 1, 0.1),
	Clothes = rowsOf({ "Clothes", "Clothes", "Shoes" }),
	LaundryBasket = laundryBasket,
	FloorBooks = rowsOf({ "BookPile", "Mug", "OpenBook", "Papers" }),
	FloorPapers = rowsOf({ "Papers", "Papers", "OpenBook" }),
	TeenFloor = rowsOf({ "Shoes", "ToyBall", "Mug", "BookPile", "Phone" }),
	PaintCans = rowsOf({ "PaintCan", "PaintCan", "Bucket" }),
	Pots = rowsOf({ "SmallPot" }, 1, 0.2),
	GardenTools = rowsOf({ "WateringCan", "SmallPot", "Bucket" }),
	LyingBike = bike(true),
	Suitcase = suitcase,
	WineCrate = wineCrate,
	Junk = rowsOf({ "SmallCarton", "BookPile", "Bucket", "Shoes", "Teddy" }, 2),
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
