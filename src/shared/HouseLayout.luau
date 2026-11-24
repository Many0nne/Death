-- Description pure de la maison familiale de nuit (prototype v0, docs/design.md « Première carte ») : pièces, portes,
-- escaliers, lampes, meubles et ancrages. HouseGeometry en tire des blocs, Server.HouseBuilder les construit en gris ;
-- rien n'est gardé dans Studio.
-- Repère, en studs : x vers l'est, z vers le nord, y vers le haut. Un niveau fait 12 studs, dalle comprise ; le sol du
-- niveau N est à y = 12 * N. Les rectangles x0..x1 / z0..z1 sont les bords extérieurs de la pièce : chaque pièce pose
-- son propre mur de 0,5 stud à l'intérieur de ce rectangle (un mur mitoyen fait donc 1 stud).
--
-- Plan (z vers le haut du schéma) :
--   Étage (1)     z 28..48 : [Escalier 0..14][Chambre d'amis 14..35][Bureau 35..56]
--                 z 20..28 : [Couloir de l'étage 0..56]
--                 z  0..20 : [Chambre des parents 0..24][Chambre d'enfant 24..40][Salle de bain 40..56]
--   Rez (0)       z 28..48 : [Escalier 0..14][Buanderie 14..28][Escalier de la cave 28..42][Entrée 42..56]
--                 z 20..28 : [Couloir du rez-de-chaussée 0..56]                                  [Garage 56..80,
--                 z  0..20 : [Cuisine 0..24][Salon 24..56]                                        z 0..28]
--   Cave (-1)     z 28..48 :                 [Escalier de la cave 28..42]
--                 z  0..28 : [Cellier 0..28][Cave 28..56]
local HouseLayout = {}

HouseLayout.LEVEL_HEIGHT = 12 -- d'un sol au suivant, dalle comprise
HouseLayout.SLAB = 1 -- épaisseur des dalles (sol, plafond)
HouseLayout.WALL = 0.5 -- épaisseur de mur posée par chaque pièce
HouseLayout.DOOR_WIDTH = 5
HouseLayout.DOOR_HEIGHT = 8
-- Escalier tournant (cage sur deux niveaux) : deux volées côte à côte séparées par une cloison, palier de demi-niveau
-- au fond ; la volée basse part de la porte du bas, la volée haute arrive au palier de la porte du haut.
HouseLayout.STEP_RISE = 1
HouseLayout.STEP_DEPTH = 1.5
HouseLayout.HALF_LANDING = 5
HouseLayout.LANE_GAP = 1 -- cloison pleine entre les deux volées
HouseLayout.RAILING = 3 -- la cloison dépasse le palier haut de cette hauteur (garde-corps)

HouseLayout.levels = { [-1] = "Cave", [0] = "Rez-de-chaussée", [1] = "Étage" }

-- Ailes électriques : le disjoncteur (#4) coupe une aile entière.
HouseLayout.wings = {
	Day = "Aile jour",
	Night = "Aile nuit",
	Service = "Aile service",
}

-- lit = éclairée par des lampes ; une pièce non éclairée est une zone sombre où la Mort circule.
-- levels = nombre de niveaux traversés (cages d'escalier) ; roof = la pièce pose son plafond (sinon le sol du niveau
-- au-dessus le couvre) ; stairs = côté de la cage où s'ouvrent ses deux portes (seul « South » est géré).
HouseLayout.rooms = {
	-- Cave (-1) : sombre, la Mort y apparaît
	{ id = "Cellar", name = "Cellier", level = -1, x0 = 0, x1 = 28, z0 = 0, z1 = 28, wing = "Service", lit = false },
	{ id = "Cave", name = "Cave", level = -1, x0 = 28, x1 = 56, z0 = 0, z1 = 28, wing = "Service", lit = false },
	{
		id = "CaveStairs",
		name = "Escalier de la cave",
		level = -1,
		levels = 2,
		x0 = 28,
		x1 = 42,
		z0 = 28,
		z1 = 48,
		wing = "Service",
		lit = false,
		stairs = "South",
	},
	-- Rez-de-chaussée (0)
	{ id = "Kitchen", name = "Cuisine", level = 0, x0 = 0, x1 = 24, z0 = 0, z1 = 20, wing = "Day", lit = true },
	{ id = "Living", name = "Salon", level = 0, x0 = 24, x1 = 56, z0 = 0, z1 = 20, wing = "Day", lit = true },
	{
		id = "HallDown",
		name = "Couloir du rez-de-chaussée",
		level = 0,
		x0 = 0,
		x1 = 56,
		z0 = 20,
		z1 = 28,
		wing = "Day",
		lit = false,
	},
	{
		id = "Stairs",
		name = "Escalier",
		level = 0,
		levels = 2,
		x0 = 0,
		x1 = 14,
		z0 = 28,
		z1 = 48,
		wing = "Night",
		lit = false,
		roof = true,
		stairs = "South",
	},
	{ id = "Laundry", name = "Buanderie", level = 0, x0 = 14, x1 = 28, z0 = 28, z1 = 48, wing = "Service", lit = true },
	{ id = "Entry", name = "Entrée", level = 0, x0 = 42, x1 = 56, z0 = 28, z1 = 48, wing = "Day", lit = true },
	{
		id = "Garage",
		name = "Garage",
		level = 0,
		x0 = 56,
		x1 = 80,
		z0 = 0,
		z1 = 28,
		wing = "Service",
		lit = true,
		roof = true,
	},
	-- Étage (1)
	{
		id = "MasterBedroom",
		name = "Chambre des parents",
		level = 1,
		x0 = 0,
		x1 = 24,
		z0 = 0,
		z1 = 20,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "KidsBedroom",
		name = "Chambre d'enfant",
		level = 1,
		x0 = 24,
		x1 = 40,
		z0 = 0,
		z1 = 20,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "Bathroom",
		name = "Salle de bain",
		level = 1,
		x0 = 40,
		x1 = 56,
		z0 = 0,
		z1 = 20,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "HallUp",
		name = "Couloir de l'étage",
		level = 1,
		x0 = 0,
		x1 = 56,
		z0 = 20,
		z1 = 28,
		wing = "Night",
		lit = false,
		roof = true,
	},
	{
		id = "GuestBedroom",
		name = "Chambre d'amis",
		level = 1,
		x0 = 14,
		x1 = 35,
		z0 = 28,
		z1 = 48,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "Study",
		name = "Bureau",
		level = 1,
		x0 = 35,
		x1 = 56,
		z0 = 28,
		z1 = 48,
		wing = "Night",
		lit = true,
		roof = true,
	},
}

-- Portes sans battant (praticables). along = direction du mur percé ("X" : mur à z constant, "Z" : mur à x constant) ;
-- x, z = centre de l'ouverture sur la ligne du mur. Une porte extérieure (une seule pièce) a un battant fermé « leaf »,
-- tagué du même nom (MapTags).
HouseLayout.doors = {
	-- Rez-de-chaussée
	{ id = "KitchenHall", rooms = { "Kitchen", "HallDown" }, level = 0, along = "X", x = 12, z = 20 },
	{ id = "KitchenLiving", rooms = { "Kitchen", "Living" }, level = 0, along = "Z", x = 24, z = 10 },
	{ id = "LivingHall", rooms = { "Living", "HallDown" }, level = 0, along = "X", x = 40, z = 20 },
	{ id = "StairsBottom", rooms = { "HallDown", "Stairs" }, level = 0, along = "X", x = 3.5, z = 28 },
	{ id = "LaundryHall", rooms = { "Laundry", "HallDown" }, level = 0, along = "X", x = 21, z = 28 },
	{ id = "CaveStairsTop", rooms = { "HallDown", "CaveStairs" }, level = 0, along = "X", x = 38.5, z = 28 },
	{ id = "EntryHall", rooms = { "Entry", "HallDown" }, level = 0, along = "X", x = 49, z = 28 },
	{ id = "GarageHall", rooms = { "Garage", "HallDown" }, level = 0, along = "Z", x = 56, z = 24 },
	{ id = "FrontDoor", rooms = { "Entry" }, level = 0, along = "X", x = 49, z = 48, leaf = "FrontDoor" },
	{
		id = "GarageDoor",
		rooms = { "Garage" },
		level = 0,
		along = "Z",
		x = 80,
		z = 14,
		width = 12,
		height = 10,
		leaf = "GarageDoor",
	},
	-- Étage
	{ id = "StairsTop", rooms = { "Stairs", "HallUp" }, level = 1, along = "X", x = 10.5, z = 28 },
	{ id = "MasterBedroomHall", rooms = { "MasterBedroom", "HallUp" }, level = 1, along = "X", x = 12, z = 20 },
	{ id = "KidsBedroomHall", rooms = { "KidsBedroom", "HallUp" }, level = 1, along = "X", x = 32, z = 20 },
	{ id = "BathroomHall", rooms = { "Bathroom", "HallUp" }, level = 1, along = "X", x = 48, z = 20 },
	{ id = "GuestBedroomHall", rooms = { "GuestBedroom", "HallUp" }, level = 1, along = "X", x = 24, z = 28 },
	{ id = "StudyHall", rooms = { "Study", "HallUp" }, level = 1, along = "X", x = 46, z = 28 },
	-- Cave
	{ id = "CaveStairsBottom", rooms = { "CaveStairs", "Cave" }, level = -1, along = "X", x = 31.5, z = 28 },
	{ id = "CellarCave", rooms = { "Cellar", "Cave" }, level = -1, along = "Z", x = 28, z = 14 },
}

-- Lampes d'ambiance. Plafonnier par défaut (sous le plafond) ; le lustre pend au milieu du salon et sert aussi de
-- piège (grand).
HouseLayout.lamps = {
	{ id = "KitchenCeiling", room = "Kitchen", x = 12, z = 10 },
	{ id = "LivingChandelier", room = "Living", x = 40, z = 10, kind = "Chandelier" },
	{ id = "LivingCeiling", room = "Living", x = 28, z = 10 },
	{ id = "LaundryCeiling", room = "Laundry", x = 21, z = 38 },
	{ id = "EntryCeiling", room = "Entry", x = 49, z = 38 },
	{ id = "GarageCeilingWest", room = "Garage", x = 62, z = 8 },
	{ id = "GarageCeilingEast", room = "Garage", x = 74, z = 20 },
	{ id = "MasterBedroomCeiling", room = "MasterBedroom", x = 12, z = 10 },
	{ id = "KidsBedroomCeiling", room = "KidsBedroom", x = 32, z = 10 },
	{ id = "BathroomCeiling", room = "Bathroom", x = 48, z = 10 },
	{ id = "GuestBedroomCeiling", room = "GuestBedroom", x = 24.5, z = 38 },
	{ id = "StudyCeiling", room = "Study", x = 45.5, z = 38 },
}

-- Meubles en blocs : x, z = centre au sol, size = { largeur x, hauteur, profondeur z }, y = hauteur du bas (0 par
-- défaut). trap = le meuble est un candidat de piège ; keySpot = un emplacement de clés est posé dessus ; tag = tag
-- MapTags posé sur le meuble.
HouseLayout.props = {
	-- Cuisine
	{ id = "KitchenCounter", room = "Kitchen", x = 2, z = 10, size = { 3, 3.5, 12 }, keySpot = true },
	{ id = "KitchenTable", room = "Kitchen", x = 14, z = 9, size = { 6, 3, 4 } },
	{ id = "KitchenShelf", room = "Kitchen", x = 18, z = 1.25, size = { 6, 7, 1.5 }, trap = "Shelf" },
	-- Salon
	{ id = "LivingSofa", room = "Living", x = 34, z = 4, size = { 10, 3, 3 } },
	{ id = "LivingCoffeeTable", room = "Living", x = 34, z = 9, size = { 5, 1.5, 3 } },
	{ id = "LivingBookcase", room = "Living", x = 54.75, z = 10, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Buanderie
	{ id = "LaundryWasher", room = "Laundry", x = 17, z = 45.5, size = { 3, 3, 3 } },
	{ id = "LaundryShelf", room = "Laundry", x = 26.75, z = 40, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Entrée
	{ id = "EntryConsole", room = "Entry", x = 54.5, z = 38, size = { 2, 3, 6 }, keySpot = true },
	-- Garage
	{ id = "GarageWorkbench", room = "Garage", x = 64, z = 26, size = { 8, 3.5, 2.5 }, keySpot = true },
	{ id = "GarageShelf", room = "Garage", x = 62, z = 1.25, size = { 6, 7, 1.5 }, trap = "Shelf" },
	-- Chambre des parents
	{ id = "MasterBed", room = "MasterBedroom", x = 6, z = 6, size = { 6, 2.5, 9 } },
	{ id = "MasterNightstand", room = "MasterBedroom", x = 11, z = 2, size = { 2.5, 2.5, 2.5 }, keySpot = true },
	{ id = "MasterWardrobe", room = "MasterBedroom", x = 22.75, z = 8, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Chambre d'enfant
	{ id = "KidsBed", room = "KidsBedroom", x = 34, z = 6, size = { 5, 2.5, 8 } },
	-- Salle de bain
	{ id = "Bathtub", room = "Bathroom", x = 51, z = 4, size = { 8, 2.5, 4.5 } },
	{ id = "BathroomSink", room = "Bathroom", x = 42, z = 10, size = { 2, 3, 3 }, keySpot = true },
	-- Chambre d'amis
	{ id = "GuestBed", room = "GuestBedroom", x = 24, z = 42, size = { 6, 2.5, 9 } },
	{ id = "GuestNightstand", room = "GuestBedroom", x = 30, z = 46.25, size = { 2.5, 2.5, 2.5 }, keySpot = true },
	-- Bureau
	{ id = "StudyDesk", room = "Study", x = 46, z = 46, size = { 7, 3, 3 }, keySpot = true },
	{ id = "StudyBookcase", room = "Study", x = 54.75, z = 38, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Cave
	{ id = "Breaker", room = "Cave", x = 55, z = 14, y = 3.5, size = { 1, 3, 2 }, tag = "Breaker" },
	{ id = "CaveShelf", room = "Cave", x = 42, z = 1.25, size = { 8, 7, 1.5 }, trap = "Shelf" },
	{ id = "CaveBoiler", room = "Cave", x = 36, z = 4, size = { 4, 7, 4 } },
	-- Cellier
	{ id = "CellarWineRack", room = "Cellar", x = 1.25, z = 14, size = { 1.5, 7, 8 }, trap = "Shelf" },
	{ id = "CellarCrate", room = "Cellar", x = 14, z = 6, size = { 4, 3, 4 }, keySpot = true },
	{ id = "CellarCrateSmall", room = "Cellar", x = 20, z = 22, size = { 3, 3, 3 } },
}

-- Ancrages posés au sol : apparitions, carrelage mouillé (piège petit), sortie.
HouseLayout.anchors = {
	{ id = "MortalSpawn1", kind = "MortalSpawn", room = "Living", x = 28, z = 15 },
	{ id = "MortalSpawn2", kind = "MortalSpawn", room = "Living", x = 32, z = 15 },
	{ id = "MortalSpawn3", kind = "MortalSpawn", room = "Living", x = 48, z = 15 },
	{ id = "MortalSpawn4", kind = "MortalSpawn", room = "Living", x = 52, z = 15 },
	{ id = "DeathSpawnCave", kind = "DeathSpawn", room = "Cave", x = 50, z = 22 },
	{ id = "DeathSpawnCellar", kind = "DeathSpawn", room = "Cellar", x = 8, z = 22 },
	{ id = "WetFloorKitchen", kind = "WetFloor", room = "Kitchen", x = 6, z = 10 },
	{ id = "WetFloorBathroom", kind = "WetFloor", room = "Bathroom", x = 48, z = 12 },
	{ id = "WetFloorLaundry", kind = "WetFloor", room = "Laundry", x = 21, z = 40 },
	{ id = "WetFloorCave", kind = "WetFloor", room = "Cave", x = 46, z = 20 },
	{ id = "Exit", kind = "Exit", room = "Garage", x = 77, z = 14 },
}

-- Voiture de fuite (blocs), capot vers la porte du garage (est).
HouseLayout.car = { id = "EscapeCar", room = "Garage", x = 66, z = 14 }

-- Point d'apparition par défaut (SpawnLocation) tant que la boucle de manche (#2) ne téléporte pas les joueurs.
HouseLayout.spawn = { room = "Living", x = 40, z = 15 }

return HouseLayout
