-- Contrat de la carte : tags CollectionService et attributs posés par le générateur de maison (Server.HouseBuilder).
-- La lumière et la Mort (#4), les pièges (#5) et la fuite (#7) ne lisent la carte que par ces noms.
local MapTags = {
	-- Volume invisible de chaque pièce (CanQuery/CanCollide faux) : attributs RoomId, RoomName, WingId, Level, Dark
	Room = "Room",
	-- Toute lampe (Part néon + PointLight « Light ») : attributs LampId, RoomId, WingId ; voir aussi wingLamps/roomLamps
	Lamp = "Lamp",
	-- Apparitions (Part invisible posée au sol)
	MortalSpawn = "MortalSpawn",
	DeathSpawn = "DeathSpawn",
	-- Emplacement candidat d'un piège : attribut TrapKind (voir TrapKinds) ; voir aussi trapKind
	TrapCandidate = "TrapCandidate",
	-- Emplacement candidat des clés (#7) : Part invisible posée sur un meuble
	KeySpot = "KeySpot",
	-- Sortie des mortels (devant la porte du garage)
	Exit = "Exit",
	-- Disjoncteur en bloc (cave)
	Breaker = "Breaker",
	-- Voiture de fuite : Model en blocs (PrimaryPart « Body »)
	EscapeCar = "EscapeCar",
	-- Battants fermés des portes extérieures
	GarageDoor = "GarageDoor",
	FrontDoor = "FrontDoor",
}

MapTags.Attributes = {
	RoomId = "RoomId",
	RoomName = "RoomName",
	WingId = "WingId",
	Level = "Level",
	Dark = "Dark",
	LampId = "LampId",
	TrapKind = "TrapKind",
	AnchorId = "AnchorId",
	DoorId = "DoorId",
}

MapTags.TrapKinds = {
	WetFloor = "WetFloor", -- petit : carrelage mouillé (zone au sol)
	Shelf = "Shelf", -- moyen : étagère (le meuble lui-même)
	Chandelier = "Chandelier", -- grand : lustre du salon (aussi une lampe)
}

-- Cette méthode permet de nommer le tag des lampes d'une aile lorsque #4 coupe le disjoncteur de cette aile.
function MapTags.wingLamps(wingId: string): string
	return "Lamp_Wing_" .. wingId
end

-- Cette méthode permet de nommer le tag des lampes d'une pièce lorsque #4 éteint ou grille une seule pièce.
function MapTags.roomLamps(roomId: string): string
	return "Lamp_Room_" .. roomId
end

-- Cette méthode permet de nommer le tag des candidats d'un type de piège lorsque #5 cherche tous les lustres, etc.
function MapTags.trapKind(kind: string): string
	return "Trap_" .. kind
end

return MapTags
