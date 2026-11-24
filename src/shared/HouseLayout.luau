-- Description pure de la maison familiale de nuit et de son terrain (docs/design.md « Première carte ») : pièces,
-- zones extérieures, portes, escaliers, lampes, meubles et ancrages. HouseGeometry en tire des blocs,
-- Server.HouseBuilder les construit en gris ; rien n'est gardé dans Studio.
-- Repère, en studs : x vers l'est, z vers le nord, y vers le haut. Un niveau fait 12 studs, dalle comprise ; le sol du
-- niveau N est à y = 12 * N. Les rectangles x0..x1 / z0..z1 sont les bords extérieurs de la pièce : chaque pièce pose
-- son propre mur de 0,5 stud à l'intérieur de ce rectangle (un mur mitoyen fait donc 1 stud). Une zone extérieure
-- (outdoor) ne pose ni murs ni plafond : seulement son terrain et une clôture sur les côtés listés dans `fence` ; deux
-- zones extérieures voisines communiquent librement par leur bord commun.
--
-- Plan (z vers le haut du schéma ; la rue est au sud, le jardin au nord) :
--   Étage (1)  z 36..56 : [Ch. enfant 0..24][Escalier 24..38][Ch. ado 38..52][Salle d'eau 52..64]
--              z 32..36 :                                    (ch. ado et salle d'eau descendent jusqu'à z 32)
--              z 28..48 :                                                                   [Esc. du garage 64..78]
--              z 20..36 : [Dressing 0..12][SdB 12..24][Palier 24..38][Couloir est 38..64, z 20..32]
--              z  0..20 : [Ch. parents 0..24, z 0..22][Bureau 24..38][Ch. d'amis 38..64][Grenier 64..92, z 0..28]
--   Rez (0)    z 56..70 : [Véranda 0..50]                             [Cour 50..88][Potager 88..104, z 56..78]
--              z 34..56 : [Bibliothèque 0..24][Escalier 24..38][Buanderie 38..50][Esc. cave 50..64]
--              z 48..56 :                                                           [Passage nord 64..92]
--              z 28..48 :                                        [Esc. du garage 64..78][Esc. de l'atelier 78..92]
--              z 20..36 : [Salon 0..24, z 0..34][Dégagement 24..38][Cuisine 38..64]   [Garage 64..92, z 0..28]
--              z  0..20 :                       [Entrée 24..38]    [Salle à manger 38..64]
--   Cave (-1)  z  0..36 : [Cave à vin 18..38][Cellier 38..64, z 0..14 / Cave z 14..36][Atelier 64..92, z 0..28]
--   Dehors (0) : devant (z -16..0), allée à l'est (x 92..104, portail et sortie au sud), côté ouest, passage nord,
--                cour, potager, jardin (z 70..90), abri de jardin (x 88..104, z 78..90). Clôture haute tout autour.
local HouseLayout = {}

HouseLayout.LEVEL_HEIGHT = 12 -- d'un sol au suivant, dalle comprise
HouseLayout.SLAB = 1 -- épaisseur des dalles (sol, plafond)
HouseLayout.WALL = 0.5 -- épaisseur de mur posée par chaque pièce
HouseLayout.DOOR_WIDTH = 5
HouseLayout.DOOR_HEIGHT = 8
-- Haie ou clôture en limite de terrain : plus haute qu'un saut, même depuis un meuble de jardin
HouseLayout.FENCE_HEIGHT = 10
-- Limite du terrain : un mur invisible de cette hauteur l'entoure (deux joueurs empilés, un toit ou un lampadaire
-- ne permettent pas de passer la haie)
HouseLayout.bounds = { x0 = -12, x1 = 104, z0 = -16, z1 = 90, height = 60 }
-- Escalier tournant (cage sur deux niveaux) : deux volées côte à côte séparées par une cloison, palier de demi-niveau
-- au fond ; la volée basse part de la porte du bas, la volée haute arrive au palier de la porte du haut.
HouseLayout.STEP_RISE = 1
HouseLayout.STEP_DEPTH = 1.5
HouseLayout.HALF_LANDING = 5
HouseLayout.LANE_GAP = 1 -- cloison pleine entre les deux volées
HouseLayout.RAILING = 3 -- la cloison dépasse le palier haut de cette hauteur (garde-corps)

HouseLayout.levels = { [-1] = "Cave", [0] = "Rez-de-chaussée", [1] = "Étage" }

-- Ailes électriques : le disjoncteur (#4) coupe une aile entière. Les lumières du dehors (porche, jardin, lampadaire
-- de l'allée) sont sur le circuit de service, avec le garage, la buanderie et la cave.
HouseLayout.wings = {
	Day = "Aile jour",
	Night = "Aile nuit",
	Service = "Aile service",
}

-- lit = éclairée par des lampes ; une pièce non éclairée est une zone sombre où la Mort circule.
-- levels = nombre de niveaux traversés (cages d'escalier) ; roof = la pièce pose son plafond (sinon le sol du niveau
-- au-dessus le couvre) ; stairs = côté de la cage où s'ouvrent ses deux portes (seul « South » est géré) ;
-- outdoor = zone extérieure à ciel ouvert, fence = ses côtés clôturés.
HouseLayout.rooms = {
	-- Cave (-1) : sombre, la Mort y apparaît
	{ id = "Cave", name = "Cave", level = -1, x0 = 38, x1 = 64, z0 = 14, z1 = 36, wing = "Service", lit = false },
	{ id = "Cellar", name = "Cellier", level = -1, x0 = 38, x1 = 64, z0 = 0, z1 = 14, wing = "Service", lit = false },
	{
		id = "WineCellar",
		name = "Cave à vin",
		level = -1,
		x0 = 18,
		x1 = 38,
		z0 = 0,
		z1 = 36,
		wing = "Service",
		lit = false,
	},
	{ id = "Workshop", name = "Atelier", level = -1, x0 = 64, x1 = 92, z0 = 0, z1 = 28, wing = "Service", lit = false },
	{
		id = "CaveStairs",
		name = "Escalier de la cave",
		level = -1,
		levels = 2,
		x0 = 50,
		x1 = 64,
		z0 = 36,
		z1 = 56,
		wing = "Service",
		lit = false,
		stairs = "South",
	},
	{
		id = "WorkshopStairs",
		name = "Escalier de l'atelier",
		level = -1,
		levels = 2,
		x0 = 78,
		x1 = 92,
		z0 = 28,
		z1 = 48,
		wing = "Service",
		lit = false,
		roof = true,
		stairs = "South",
	},
	-- Rez-de-chaussée (0)
	{ id = "Living", name = "Salon", level = 0, x0 = 0, x1 = 24, z0 = 0, z1 = 34, wing = "Day", lit = true },
	{ id = "Entry", name = "Entrée", level = 0, x0 = 24, x1 = 38, z0 = 0, z1 = 20, wing = "Day", lit = true },
	{
		id = "HallDown",
		name = "Dégagement",
		level = 0,
		x0 = 24,
		x1 = 38,
		z0 = 20,
		z1 = 36,
		wing = "Day",
		lit = false,
	},
	{ id = "Dining", name = "Salle à manger", level = 0, x0 = 38, x1 = 64, z0 = 0, z1 = 20, wing = "Day", lit = true },
	{ id = "Kitchen", name = "Cuisine", level = 0, x0 = 38, x1 = 64, z0 = 20, z1 = 36, wing = "Day", lit = true },
	{
		id = "Library",
		name = "Bibliothèque",
		level = 0,
		x0 = 0,
		x1 = 24,
		z0 = 34,
		z1 = 56,
		wing = "Day",
		lit = false,
	},
	{ id = "Laundry", name = "Buanderie", level = 0, x0 = 38, x1 = 50, z0 = 36, z1 = 56, wing = "Service", lit = true },
	{
		id = "Veranda",
		name = "Véranda",
		level = 0,
		x0 = 0,
		x1 = 50,
		z0 = 56,
		z1 = 70,
		wing = "Day",
		lit = true,
		roof = true,
	},
	{ id = "Garage", name = "Garage", level = 0, x0 = 64, x1 = 92, z0 = 0, z1 = 28, wing = "Service", lit = true },
	{
		id = "Stairs",
		name = "Escalier",
		level = 0,
		levels = 2,
		x0 = 24,
		x1 = 38,
		z0 = 36,
		z1 = 56,
		wing = "Night",
		lit = false,
		roof = true,
		stairs = "South",
	},
	{
		id = "GarageStairs",
		name = "Escalier du garage",
		level = 0,
		levels = 2,
		x0 = 64,
		x1 = 78,
		z0 = 28,
		z1 = 48,
		wing = "Service",
		lit = false,
		roof = true,
		stairs = "South",
	},
	-- Étage (1)
	{
		id = "Study",
		name = "Bureau",
		level = 1,
		x0 = 24,
		x1 = 38,
		z0 = 0,
		z1 = 20,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "HallUp",
		name = "Palier",
		level = 1,
		x0 = 24,
		x1 = 38,
		z0 = 20,
		z1 = 36,
		wing = "Night",
		lit = false,
		roof = true,
	},
	{
		id = "MasterBedroom",
		name = "Chambre des parents",
		level = 1,
		x0 = 0,
		x1 = 24,
		z0 = 0,
		z1 = 22,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "Dressing",
		name = "Dressing",
		level = 1,
		x0 = 0,
		x1 = 12,
		z0 = 22,
		z1 = 36,
		wing = "Night",
		lit = false,
		roof = true,
	},
	{
		id = "Bathroom",
		name = "Salle de bain",
		level = 1,
		x0 = 12,
		x1 = 24,
		z0 = 22,
		z1 = 36,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "KidsBedroom",
		name = "Chambre d'enfant",
		level = 1,
		x0 = 0,
		x1 = 24,
		z0 = 36,
		z1 = 56,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "HallEast",
		name = "Couloir de l'étage",
		level = 1,
		x0 = 38,
		x1 = 64,
		z0 = 20,
		z1 = 32,
		wing = "Night",
		lit = false,
		roof = true,
	},
	{
		id = "GuestBedroom",
		name = "Chambre d'amis",
		level = 1,
		x0 = 38,
		x1 = 64,
		z0 = 0,
		z1 = 20,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "TeenBedroom",
		name = "Chambre d'ado",
		level = 1,
		x0 = 38,
		x1 = 52,
		z0 = 32,
		z1 = 56,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "ShowerRoom",
		name = "Salle d'eau",
		level = 1,
		x0 = 52,
		x1 = 64,
		z0 = 32,
		z1 = 56,
		wing = "Night",
		lit = true,
		roof = true,
	},
	{
		id = "Attic",
		name = "Grenier",
		level = 1,
		x0 = 64,
		x1 = 92,
		z0 = 0,
		z1 = 28,
		wing = "Service",
		lit = false,
		roof = true,
	},
	-- Dehors (0) : terrain clos, sombre, quelques lumières
	{
		id = "FrontYard",
		name = "Devant de la maison",
		level = 0,
		x0 = -12,
		x1 = 92,
		z0 = -16,
		z1 = 0,
		wing = "Service",
		lit = true,
		outdoor = true,
		fence = { "South", "West" },
	},
	{
		id = "Driveway",
		name = "Allée",
		level = 0,
		x0 = 92,
		x1 = 104,
		z0 = -16,
		z1 = 56,
		wing = "Service",
		lit = true,
		outdoor = true,
		fence = { "South", "East" },
	},
	{
		id = "WestSide",
		name = "Côté ouest",
		level = 0,
		x0 = -12,
		x1 = 0,
		z0 = 0,
		z1 = 70,
		wing = "Service",
		lit = false,
		outdoor = true,
		fence = { "West" },
	},
	{
		id = "NorthPassage",
		name = "Passage nord",
		level = 0,
		x0 = 64,
		x1 = 92,
		z0 = 48,
		z1 = 56,
		wing = "Service",
		lit = false,
		outdoor = true,
	},
	{
		id = "Courtyard",
		name = "Cour",
		level = 0,
		x0 = 50,
		x1 = 88,
		z0 = 56,
		z1 = 70,
		wing = "Service",
		lit = false,
		outdoor = true,
	},
	{
		id = "VegetableGarden",
		name = "Potager",
		level = 0,
		x0 = 88,
		x1 = 104,
		z0 = 56,
		z1 = 78,
		wing = "Service",
		lit = false,
		outdoor = true,
		fence = { "East" },
	},
	{
		id = "Garden",
		name = "Jardin",
		level = 0,
		x0 = -12,
		x1 = 88,
		z0 = 70,
		z1 = 90,
		wing = "Service",
		lit = true,
		outdoor = true,
		fence = { "West", "North" },
	},
	{
		id = "Shed",
		name = "Abri de jardin",
		level = 0,
		x0 = 88,
		x1 = 104,
		z0 = 78,
		z1 = 90,
		wing = "Service",
		lit = false,
		roof = true,
	},
}

-- Portes sans battant (praticables). along = direction du mur percé ("X" : mur à z constant, "Z" : mur à x constant) ;
-- x, z = centre de l'ouverture sur la ligne du mur. Une porte extérieure (une seule pièce) a un battant fermé « leaf »,
-- tagué du même nom (MapTags).
HouseLayout.doors = {
	-- Rez-de-chaussée
	{ id = "EntryLiving", rooms = { "Entry", "Living" }, level = 0, along = "Z", x = 24, z = 10 },
	{ id = "EntryDining", rooms = { "Entry", "Dining" }, level = 0, along = "Z", x = 38, z = 10 },
	{ id = "EntryHall", rooms = { "Entry", "HallDown" }, level = 0, along = "X", x = 31, z = 20 },
	{ id = "LivingHall", rooms = { "Living", "HallDown" }, level = 0, along = "Z", x = 24, z = 27 },
	{ id = "HallKitchen", rooms = { "HallDown", "Kitchen" }, level = 0, along = "Z", x = 38, z = 28 },
	{ id = "DiningKitchen", rooms = { "Dining", "Kitchen" }, level = 0, along = "X", x = 51, z = 20 },
	{ id = "LivingLibrary", rooms = { "Living", "Library" }, level = 0, along = "X", x = 12, z = 34 },
	{ id = "LibraryVeranda", rooms = { "Library", "Veranda" }, level = 0, along = "X", x = 12, z = 56 },
	{ id = "KitchenLaundry", rooms = { "Kitchen", "Laundry" }, level = 0, along = "X", x = 44, z = 36 },
	{ id = "LaundryVeranda", rooms = { "Laundry", "Veranda" }, level = 0, along = "X", x = 44, z = 56 },
	{ id = "KitchenGarage", rooms = { "Kitchen", "Garage" }, level = 0, along = "Z", x = 64, z = 24 },
	{ id = "StairsBottom", rooms = { "HallDown", "Stairs" }, level = 0, along = "X", x = 27.5, z = 36 },
	{ id = "CaveStairsTop", rooms = { "Kitchen", "CaveStairs" }, level = 0, along = "X", x = 60.5, z = 36 },
	{ id = "GarageStairsBottom", rooms = { "Garage", "GarageStairs" }, level = 0, along = "X", x = 67.5, z = 28 },
	{ id = "WorkshopStairsTop", rooms = { "Garage", "WorkshopStairs" }, level = 0, along = "X", x = 88.5, z = 28 },
	-- Vers le dehors
	{ id = "LivingWestSide", rooms = { "Living", "WestSide" }, level = 0, along = "Z", x = 0, z = 17 },
	{ id = "VerandaGardenWest", rooms = { "Veranda", "Garden" }, level = 0, along = "X", x = 10, z = 70 },
	{ id = "VerandaGardenEast", rooms = { "Veranda", "Garden" }, level = 0, along = "X", x = 38, z = 70 },
	{ id = "ShedGarden", rooms = { "Shed", "Garden" }, level = 0, along = "Z", x = 88, z = 84 },
	{ id = "ShedVegetableGarden", rooms = { "Shed", "VegetableGarden" }, level = 0, along = "X", x = 96, z = 78 },
	-- Battants fermés : porte d'entrée (à clé), porte du garage (ouverte par la fuite), portail de la rue
	{ id = "FrontDoor", rooms = { "Entry" }, level = 0, along = "X", x = 31, z = 0, leaf = "FrontDoor" },
	{
		id = "GarageDoor",
		rooms = { "Garage" },
		level = 0,
		along = "Z",
		x = 92,
		z = 14,
		width = 12,
		height = 10,
		leaf = "GarageDoor",
	},
	{ id = "Gate", rooms = { "Driveway" }, level = 0, along = "X", x = 98, z = -16, width = 8, leaf = "Gate" },
	-- Étage
	{ id = "StairsTop", rooms = { "Stairs", "HallUp" }, level = 1, along = "X", x = 34.5, z = 36 },
	{ id = "HallUpStudy", rooms = { "HallUp", "Study" }, level = 1, along = "X", x = 31, z = 20 },
	{ id = "HallUpBathroom", rooms = { "HallUp", "Bathroom" }, level = 1, along = "Z", x = 24, z = 29 },
	{ id = "HallUpEast", rooms = { "HallUp", "HallEast" }, level = 1, along = "Z", x = 38, z = 26 },
	{ id = "StudyMaster", rooms = { "Study", "MasterBedroom" }, level = 1, along = "Z", x = 24, z = 10 },
	{ id = "StudyGuest", rooms = { "Study", "GuestBedroom" }, level = 1, along = "Z", x = 38, z = 10 },
	{ id = "MasterDressing", rooms = { "MasterBedroom", "Dressing" }, level = 1, along = "X", x = 6, z = 22 },
	{ id = "DressingBathroom", rooms = { "Dressing", "Bathroom" }, level = 1, along = "Z", x = 12, z = 29 },
	{ id = "DressingKids", rooms = { "Dressing", "KidsBedroom" }, level = 1, along = "X", x = 6, z = 36 },
	{ id = "BathroomKids", rooms = { "Bathroom", "KidsBedroom" }, level = 1, along = "X", x = 18, z = 36 },
	{ id = "HallEastGuest", rooms = { "HallEast", "GuestBedroom" }, level = 1, along = "X", x = 56, z = 20 },
	{ id = "HallEastAttic", rooms = { "HallEast", "Attic" }, level = 1, along = "Z", x = 64, z = 24 },
	{ id = "GuestAttic", rooms = { "GuestBedroom", "Attic" }, level = 1, along = "Z", x = 64, z = 10 },
	{ id = "HallEastTeen", rooms = { "HallEast", "TeenBedroom" }, level = 1, along = "X", x = 45, z = 32 },
	{ id = "HallEastShower", rooms = { "HallEast", "ShowerRoom" }, level = 1, along = "X", x = 58, z = 32 },
	{ id = "TeenShower", rooms = { "TeenBedroom", "ShowerRoom" }, level = 1, along = "Z", x = 52, z = 44 },
	{ id = "GarageStairsTop", rooms = { "GarageStairs", "Attic" }, level = 1, along = "X", x = 74.5, z = 28 },
	-- Cave
	{ id = "CaveStairsBottom", rooms = { "CaveStairs", "Cave" }, level = -1, along = "X", x = 53.5, z = 36 },
	{
		id = "WorkshopStairsBottom",
		rooms = { "WorkshopStairs", "Workshop" },
		level = -1,
		along = "X",
		x = 81.5,
		z = 28,
	},
	{ id = "CellarCave", rooms = { "Cellar", "Cave" }, level = -1, along = "X", x = 45, z = 14 },
	{ id = "CaveWorkshop", rooms = { "Cave", "Workshop" }, level = -1, along = "Z", x = 64, z = 24 },
	{ id = "CellarWorkshop", rooms = { "Cellar", "Workshop" }, level = -1, along = "Z", x = 64, z = 7 },
	{ id = "WineCellarCave", rooms = { "WineCellar", "Cave" }, level = -1, along = "Z", x = 38, z = 25 },
	{ id = "WineCellarCellar", rooms = { "WineCellar", "Cellar" }, level = -1, along = "Z", x = 38, z = 7 },
}

-- Lampes d'ambiance. Plafonnier par défaut (sous le plafond) ; le lustre pend au milieu du salon et sert aussi de
-- piège (grand). Dehors : applique (Wall) et lampadaire (Post), voir HouseGeometry.LAMP_STYLES.
HouseLayout.lamps = {
	{ id = "LivingChandelier", room = "Living", x = 12, z = 15, kind = "Chandelier" },
	{ id = "LivingLamp", room = "Living", x = 12, z = 28 },
	{ id = "EntryLamp", room = "Entry", x = 31, z = 10 },
	{ id = "DiningLamp", room = "Dining", x = 51, z = 10 },
	{ id = "KitchenLamp", room = "Kitchen", x = 51, z = 28 },
	{ id = "LaundryLamp", room = "Laundry", x = 44, z = 46 },
	{ id = "VerandaLampWest", room = "Veranda", x = 12, z = 63 },
	{ id = "VerandaLampEast", room = "Veranda", x = 38, z = 63 },
	{ id = "GarageLampWest", room = "Garage", x = 70, z = 8 },
	{ id = "GarageLampEast", room = "Garage", x = 86, z = 20 },
	{ id = "StudyLamp", room = "Study", x = 31, z = 10 },
	{ id = "MasterBedroomLamp", room = "MasterBedroom", x = 12, z = 11 },
	{ id = "BathroomLamp", room = "Bathroom", x = 18, z = 29 },
	{ id = "KidsBedroomLamp", room = "KidsBedroom", x = 12, z = 46 },
	{ id = "GuestBedroomLamp", room = "GuestBedroom", x = 51, z = 10 },
	{ id = "TeenBedroomLamp", room = "TeenBedroom", x = 45, z = 44 },
	{ id = "ShowerRoomLamp", room = "ShowerRoom", x = 58, z = 44 },
	{ id = "PorchLamp", room = "FrontYard", x = 31, z = -1.1, kind = "Wall" },
	{ id = "StreetLamp", room = "Driveway", x = 102.5, z = -10, kind = "Post" },
	{ id = "GardenLamp", room = "Garden", x = 24, z = 78, kind = "Post" },
}

-- Meubles en blocs : x, z = centre au sol, size = { largeur x, hauteur, profondeur z }, y = hauteur du bas (0 par
-- défaut). trap = le meuble est un candidat de piège ; keySpot = un emplacement de clés est posé dessus ; tag = tag
-- MapTags posé sur le meuble. Dehors, un meuble reste bas (pas de marchepied par-dessus la clôture). Pas de clés
-- au garage ni devant la maison : trop près de la voiture et de la sortie.
HouseLayout.props = {
	-- Salon
	{ id = "LivingSofa", room = "Living", x = 12, z = 6, size = { 10, 3, 3 } },
	{ id = "LivingCoffeeTable", room = "Living", x = 12, z = 11, size = { 5, 1.5, 3 } },
	{ id = "LivingArmchair", room = "Living", x = 20, z = 22, size = { 3, 3, 3 } },
	{ id = "LivingBookcase", room = "Living", x = 1.25, z = 28, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Entrée
	{ id = "EntryConsole", room = "Entry", x = 25.5, z = 16.5, size = { 2, 3, 5 }, keySpot = true },
	{ id = "EntryWardrobe", room = "Entry", x = 36.75, z = 3, size = { 1.5, 7, 4 }, trap = "Shelf" },
	-- Salle à manger
	{ id = "DiningTable", room = "Dining", x = 51, z = 10, size = { 10, 3, 5 } },
	{ id = "DiningSideboard", room = "Dining", x = 51, z = 1.5, size = { 8, 3.5, 2 }, keySpot = true },
	{ id = "DiningCabinet", room = "Dining", x = 62.75, z = 10, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Cuisine
	{ id = "KitchenCounter", room = "Kitchen", x = 43, z = 21.5, size = { 8, 3.5, 2 }, keySpot = true },
	{ id = "KitchenIsland", room = "Kitchen", x = 51, z = 29, size = { 8, 3.5, 4 } },
	{ id = "KitchenShelf", room = "Kitchen", x = 52, z = 34.75, size = { 6, 7, 1.5 }, trap = "Shelf" },
	-- Bibliothèque
	{ id = "LibraryDesk", room = "Library", x = 12, z = 45, size = { 6, 3, 3 }, keySpot = true },
	{ id = "LibraryBookcaseWest", room = "Library", x = 1.25, z = 45, size = { 1.5, 7, 8 }, trap = "Shelf" },
	{ id = "LibraryBookcaseEast", room = "Library", x = 22.75, z = 45, size = { 1.5, 7, 8 }, trap = "Shelf" },
	-- Buanderie
	{ id = "LaundryWasher", room = "Laundry", x = 40, z = 46, size = { 3, 3, 3 }, keySpot = true },
	{ id = "LaundryShelf", room = "Laundry", x = 48.75, z = 46, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Véranda
	{ id = "VerandaTable", room = "Veranda", x = 25, z = 63, size = { 6, 3, 4 }, keySpot = true },
	-- Garage
	{ id = "GarageWorkbench", room = "Garage", x = 78, z = 26.25, size = { 8, 3.5, 2.5 } },
	{ id = "GarageShelf", room = "Garage", x = 70, z = 1.25, size = { 6, 7, 1.5 }, trap = "Shelf" },
	-- Bureau
	{ id = "StudyDesk", room = "Study", x = 31, z = 3, size = { 7, 3, 3 }, keySpot = true },
	{ id = "StudyBookcase", room = "Study", x = 25.25, z = 17, size = { 1.5, 7, 4 }, trap = "Shelf" },
	-- Chambre des parents
	{ id = "MasterBed", room = "MasterBedroom", x = 8, z = 6, size = { 6, 2.5, 9 } },
	{ id = "MasterNightstand", room = "MasterBedroom", x = 13, z = 2, size = { 2.5, 2.5, 2.5 }, keySpot = true },
	{ id = "MasterWardrobe", room = "MasterBedroom", x = 1.25, z = 16, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Dressing
	{ id = "DressingWardrobe", room = "Dressing", x = 1.25, z = 29, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Salle de bain
	{ id = "Bathtub", room = "Bathroom", x = 18, z = 24.5, size = { 7, 2.5, 3 } },
	{ id = "BathroomSink", room = "Bathroom", x = 13.5, z = 34, size = { 2, 3, 3 }, keySpot = true },
	-- Chambre d'enfant
	{ id = "KidsBed", room = "KidsBedroom", x = 4, z = 50, size = { 5, 2.5, 8 } },
	{ id = "KidsToyBox", room = "KidsBedroom", x = 20, z = 53, size = { 4, 2, 3 }, keySpot = true },
	{ id = "KidsWardrobe", room = "KidsBedroom", x = 22.75, z = 44, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Couloir de l'étage
	{ id = "HallEastCupboard", room = "HallEast", x = 51.5, z = 30.75, size = { 5, 7, 1.5 }, trap = "Shelf" },
	-- Chambre d'amis
	{ id = "GuestBed", room = "GuestBedroom", x = 47, z = 5, size = { 6, 2.5, 9 } },
	{ id = "GuestNightstand", room = "GuestBedroom", x = 52, z = 1.75, size = { 2.5, 2.5, 2.5 }, keySpot = true },
	{ id = "GuestWardrobe", room = "GuestBedroom", x = 62.75, z = 17, size = { 1.5, 7, 4 }, trap = "Shelf" },
	-- Chambre d'ado
	{ id = "TeenBed", room = "TeenBedroom", x = 41.5, z = 50, size = { 5, 2.5, 8 } },
	{ id = "TeenDesk", room = "TeenBedroom", x = 48, z = 54.5, size = { 5, 3, 2 }, keySpot = true },
	{ id = "TeenWardrobe", room = "TeenBedroom", x = 39.25, z = 38, size = { 1.5, 7, 6 }, trap = "Shelf" },
	-- Salle d'eau
	{ id = "ShowerCabin", room = "ShowerRoom", x = 60, z = 52, size = { 6, 7, 6 } },
	{ id = "ShowerSink", room = "ShowerRoom", x = 62.5, z = 40, size = { 2, 3, 3 }, keySpot = true },
	-- Grenier
	{ id = "AtticTrunk", room = "Attic", x = 86, z = 4, size = { 4, 2.5, 3 }, keySpot = true },
	{ id = "AtticShelf", room = "Attic", x = 90.75, z = 14, size = { 1.5, 7, 8 }, trap = "Shelf" },
	{ id = "AtticBoxes", room = "Attic", x = 78, z = 12, size = { 4, 4, 4 } },
	{ id = "AtticBoxesSmall", room = "Attic", x = 72, z = 20, size = { 3, 3, 3 } },
	-- Cave
	{ id = "Breaker", room = "Cave", x = 63, z = 31, y = 3.5, size = { 1, 3, 2 }, tag = "Breaker" },
	{ id = "CaveShelf", room = "Cave", x = 56, z = 15.25, size = { 8, 7, 1.5 }, trap = "Shelf" },
	{ id = "CaveBoiler", room = "Cave", x = 42, z = 33, size = { 4, 7, 4 } },
	-- Cellier
	{ id = "CellarCrate", room = "Cellar", x = 52, z = 6, size = { 4, 3, 4 }, keySpot = true },
	{ id = "CellarCrateSmall", room = "Cellar", x = 58, z = 12, size = { 3, 3, 3 } },
	{ id = "CellarRack", room = "Cellar", x = 50, z = 1.25, size = { 8, 7, 1.5 }, trap = "Shelf" },
	-- Cave à vin
	{ id = "WineRackWest", room = "WineCellar", x = 19.25, z = 18, size = { 1.5, 7, 12 }, trap = "Shelf" },
	{ id = "WineRackMiddle", room = "WineCellar", x = 28, z = 14, size = { 8, 7, 1.5 }, trap = "Shelf" },
	{ id = "WineBarrel", room = "WineCellar", x = 28, z = 30, size = { 4, 4, 4 } },
	-- Atelier
	{ id = "WorkshopBench", room = "Workshop", x = 78, z = 2, size = { 8, 3.5, 2.5 }, keySpot = true },
	{ id = "WorkshopTable", room = "Workshop", x = 76, z = 15, size = { 6, 3, 4 } },
	{ id = "WorkshopShelf", room = "Workshop", x = 90.75, z = 14, size = { 1.5, 7, 8 }, trap = "Shelf" },
	-- Devant de la maison
	{ id = "FrontShrubWest", room = "FrontYard", x = 8, z = -8, size = { 8, 2, 3 } },
	{ id = "FrontShrubEast", room = "FrontYard", x = 56, z = -8, size = { 8, 2, 3 } },
	{ id = "FrontMailbox", room = "FrontYard", x = 84, z = -14, size = { 1.5, 2, 1.5 } },
	-- Côté ouest
	{ id = "WestBins", room = "WestSide", x = -3, z = 40, size = { 2.5, 2, 5 } },
	{ id = "WestWoodpile", room = "WestSide", x = -10, z = 55, size = { 2, 2, 8 } },
	-- Cour
	{ id = "CourtyardWoodpile", room = "Courtyard", x = 60, z = 57.75, size = { 6, 2, 2 } },
	{ id = "CourtyardBarbecue", room = "Courtyard", x = 75, z = 63, size = { 3, 2, 3 } },
	-- Potager
	{ id = "VegetableBedWest", room = "VegetableGarden", x = 94.5, z = 66, size = { 4, 1, 12 } },
	{ id = "VegetableBedEast", room = "VegetableGarden", x = 100.5, z = 66, size = { 4, 1, 12 } },
	-- Jardin
	{ id = "GardenTable", room = "Garden", x = 36, z = 84, size = { 5, 2, 3 }, keySpot = true },
	{ id = "GardenBench", room = "Garden", x = 60, z = 88, size = { 6, 2, 2 } },
	-- Abri de jardin
	{ id = "ShedShelf", room = "Shed", x = 102.75, z = 85, size = { 1.5, 7, 8 }, trap = "Shelf" },
	{ id = "ShedBench", room = "Shed", x = 95, z = 88.5, size = { 6, 3, 2 }, keySpot = true },
}

-- Ancrages posés au sol : apparitions, carrelage mouillé (piège petit ; dehors, une flaque), sortie.
HouseLayout.anchors = {
	{ id = "MortalSpawn1", kind = "MortalSpawn", room = "Living", x = 6, z = 18 },
	{ id = "MortalSpawn2", kind = "MortalSpawn", room = "Living", x = 10, z = 20 },
	{ id = "MortalSpawn3", kind = "MortalSpawn", room = "Living", x = 14, z = 20 },
	{ id = "MortalSpawn4", kind = "MortalSpawn", room = "Living", x = 18, z = 18 },
	{ id = "DeathSpawnCave", kind = "DeathSpawn", room = "Cave", x = 50, z = 26 },
	{ id = "DeathSpawnCellar", kind = "DeathSpawn", room = "Cellar", x = 44, z = 5 },
	{ id = "WetFloorKitchen", kind = "WetFloor", room = "Kitchen", x = 44, z = 26 },
	{ id = "WetFloorLaundry", kind = "WetFloor", room = "Laundry", x = 44, z = 46 },
	{ id = "WetFloorVeranda", kind = "WetFloor", room = "Veranda", x = 46, z = 63 },
	{ id = "WetFloorGarage", kind = "WetFloor", room = "Garage", x = 68, z = 14 },
	{ id = "WetFloorBathroom", kind = "WetFloor", room = "Bathroom", x = 18, z = 30 },
	{ id = "WetFloorShower", kind = "WetFloor", room = "ShowerRoom", x = 57, z = 44 },
	{ id = "WetFloorCave", kind = "WetFloor", room = "Cave", x = 58, z = 22 },
	{ id = "WetFloorCourtyard", kind = "WetFloor", room = "Courtyard", x = 66, z = 64 },
	{ id = "WetFloorGarden", kind = "WetFloor", room = "Garden", x = 70, z = 78 },
	{ id = "Exit", kind = "Exit", room = "Driveway", x = 98, z = -10 },
}

-- Voiture de fuite (blocs), capot vers la porte du garage (est).
HouseLayout.car = { id = "EscapeCar", room = "Garage", x = 78, z = 14 }

-- Décor hors de la carte, au-delà de la clôture : la rue au sud, des terrains voisins tout autour (non praticables).
HouseLayout.scenery = {
	{ id = "Street", kind = "Street", x0 = -60, x1 = 152, z0 = -40, z1 = -16 },
	{ id = "LawnSouth", kind = "Lawn", x0 = -60, x1 = 152, z0 = -64, z1 = -40 },
	{ id = "LawnWest", kind = "Lawn", x0 = -60, x1 = -12, z0 = -16, z1 = 130 },
	{ id = "LawnEast", kind = "Lawn", x0 = 104, x1 = 152, z0 = -16, z1 = 130 },
	{ id = "LawnNorth", kind = "Lawn", x0 = -12, x1 = 104, z0 = 90, z1 = 130 },
}

return HouseLayout
