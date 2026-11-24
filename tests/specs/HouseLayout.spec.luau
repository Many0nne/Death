-- Maison du prototype v0 : description (pièces, étages, ailes), praticabilité (portes, escaliers) et ancrages taggés.
return function(T, Loader)
	local loader = Loader.new()
	local HouseLayout = loader:require("src/shared/HouseLayout")
	local HouseGeometry = loader:require("src/shared/HouseGeometry")
	local MapTags = loader:require("src/shared/MapTags")
	local GameConfig = loader:require("src/shared/GameConfig")

	-- Cette méthode permet de copier la description en profondeur lorsqu'un test la casse exprès.
	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for k, v in value do
			copy[k] = deepCopy(v)
		end
		return copy
	end

	-- Cette méthode permet de trouver un élément par identifiant lorsqu'un test modifie une copie de la description.
	local function byId(list, id)
		for _, item in list do
			if item.id == id then
				return item
			end
		end
		error("introuvable : " .. id)
	end

	-- Cette méthode permet de savoir si une liste d'erreurs contient un fragment lorsque l'on vérifie un rejet.
	local function mentions(errors, fragment)
		for _, e in errors do
			if string.find(e, fragment, 1, true) then
				return true
			end
		end
		return false
	end

	local plan = HouseGeometry.build(HouseLayout)

	-- Cette méthode permet de lister les blocs du plan portant un tag lorsque l'on vérifie le contrat des ancrages.
	local function tagged(tag)
		local found = {}
		for _, p in plan.pieces do
			if table.find(p.tags, tag) then
				table.insert(found, p)
			end
		end
		return found
	end

	T.describe("HouseLayout : description", function()
		T.it("est valide (aucune incohérence relevée)", function()
			local errors = HouseGeometry.validate(HouseLayout)
			T.expect(#errors == 0, table.concat(errors, "\n"))
		end)

		T.it("a une cave, un rez-de-chaussée et un étage", function()
			local levels = {}
			for _, room in HouseLayout.rooms do
				levels[room.level] = true
			end
			T.expect(levels[-1] and levels[0] and levels[1], "niveaux -1, 0 et 1 attendus")
		end)

		T.it("contient les pièces de docs/design.md à leur niveau", function()
			local expected = {
				Kitchen = 0,
				Living = 0,
				Bathroom = 1,
				Stairs = 0,
				MasterBedroom = 1,
				KidsBedroom = 1,
				GuestBedroom = 1,
				Garage = 0,
				Cave = -1,
			}
			local rooms = HouseGeometry.roomsById(HouseLayout)
			for id, level in expected do
				T.expect(rooms[id], "pièce manquante : " .. id)
				T.expectEqual(rooms[id].level, level, id)
			end
		end)

		T.it("rattache chaque pièce à une aile électrique connue", function()
			for _, room in HouseLayout.rooms do
				T.expect(HouseLayout.wings[room.wing], room.id .. " sans aile")
			end
		end)

		T.it("garde les couloirs, l'escalier et la cave sombres", function()
			local rooms = HouseGeometry.roomsById(HouseLayout)
			for _, id in { "HallDown", "HallUp", "Stairs", "CaveStairs", "Cave", "Cellar" } do
				T.expectEqual(rooms[id].lit, false, id)
			end
		end)

		T.it("relie toutes les pièces par des portes intérieures", function()
			local reachable = HouseGeometry.reachableRooms(HouseLayout, "Living")
			for _, room in HouseLayout.rooms do
				T.expect(reachable[room.id], room.id .. " inaccessible depuis le salon")
			end
		end)
	end)

	T.describe("HouseLayout : échelle d'un personnage Roblox", function()
		T.it("perce des portes d'au moins 4 × 7 studs", function()
			for _, door in HouseLayout.doors do
				T.expect((door.width or HouseLayout.DOOR_WIDTH) >= 4, door.id .. " trop étroite")
				T.expect((door.height or HouseLayout.DOOR_HEIGHT) >= 7, door.id .. " trop basse")
			end
		end)

		T.it("laisse au moins 10 studs sous plafond et 8 studs de côté (couloirs)", function()
			for _, room in HouseLayout.rooms do
				local height = HouseGeometry.topY(HouseLayout, room) - HouseGeometry.floorY(HouseLayout, room.level)
				T.expect(height >= 10, room.id .. " trop basse")
				T.expect(math.min(room.x1 - room.x0, room.z1 - room.z0) >= 8, room.id .. " trop petite")
			end
		end)

		T.it("monte chaque escalier marche par marche (1 stud au plus) jusqu'au niveau suivant", function()
			for _, room in HouseLayout.rooms do
				if not room.stairs then
					continue
				end
				local base = HouseGeometry.floorY(HouseLayout, room.level)
				-- Parcours : marches basses, palier intermédiaire, marches hautes, palier haut
				local heights = {}
				for _, name in { "StepLow", "HalfLanding", "StepHigh", "TopLanding" } do
					local group = {}
					for _, p in plan.pieces do
						if p.room == room.id and string.find(p.name, room.id .. name, 1, true) == 1 then
							table.insert(group, p.center.Y + p.size.Y / 2 - base)
						end
					end
					table.sort(group)
					table.move(group, 1, #group, #heights + 1, heights)
				end
				local previous = 0
				for _, h in heights do
					T.expect(h - previous <= HouseLayout.STEP_RISE + 1e-6, room.id .. " : marche trop haute")
					previous = h
				end
				T.expectNear(previous, HouseLayout.LEVEL_HEIGHT, 1e-6, room.id .. " : palier haut")
			end
		end)
	end)

	T.describe("HouseLayout : lampes", function()
		T.it("éclaire chaque pièce éclairée et seulement elles", function()
			local lamps = {}
			for _, p in tagged(MapTags.Lamp) do
				lamps[p.room] = (lamps[p.room] or 0) + 1
			end
			for _, room in HouseLayout.rooms do
				T.expectEqual(lamps[room.id] ~= nil, room.lit, room.id)
			end
		end)

		T.it("identifie chaque lampe par pièce et par aile (tags et attributs)", function()
			local rooms = HouseGeometry.roomsById(HouseLayout)
			local ids = {}
			for _, p in tagged(MapTags.Lamp) do
				local room = rooms[p.room]
				T.expect(table.find(p.tags, MapTags.wingLamps(room.wing)), p.name .. " sans tag d'aile")
				T.expect(table.find(p.tags, MapTags.roomLamps(room.id)), p.name .. " sans tag de pièce")
				T.expectEqual(p.attributes.WingId, room.wing, p.name)
				T.expectEqual(p.attributes.RoomId, room.id, p.name)
				T.expect(p.light and p.light.range > 0, p.name .. " sans lumière")
				T.expect(not ids[p.attributes.LampId], "LampId en double : " .. p.attributes.LampId)
				ids[p.attributes.LampId] = true
			end
		end)

		T.it("donne des lampes à chaque aile", function()
			for wing in HouseLayout.wings do
				T.expect(#tagged(MapTags.wingLamps(wing)) > 0, "aile sans lampe : " .. wing)
			end
		end)
	end)

	T.describe("HouseLayout : ancrages", function()
		T.it("prévoit une apparition par mortel et au moins une pour la Mort, dans l'ombre", function()
			T.expect(#tagged(MapTags.MortalSpawn) >= GameConfig.MORTALS_PER_MATCH, "apparitions de mortels")
			local deathSpawns = tagged(MapTags.DeathSpawn)
			T.expect(#deathSpawns >= 1, "apparition de la Mort")
			local rooms = HouseGeometry.roomsById(HouseLayout)
			for _, p in deathSpawns do
				T.expectEqual(rooms[p.room].lit, false, p.name .. " : la Mort apparaît dans l'ombre")
			end
		end)

		T.it("place des candidats pour les trois pièges du prototype", function()
			local kinds = {}
			for _, p in tagged(MapTags.TrapCandidate) do
				T.expect(table.find(p.tags, MapTags.trapKind(p.attributes.TrapKind)), p.name .. " sans tag de type")
				kinds[p.attributes.TrapKind] = (kinds[p.attributes.TrapKind] or 0) + 1
			end
			T.expect((kinds.WetFloor or 0) >= 2, "carrelage mouillé")
			T.expect((kinds.Shelf or 0) >= 2, "étagère")
			T.expectEqual(kinds.Chandelier, 1, "un lustre")
			T.expectEqual(tagged(MapTags.trapKind("Chandelier"))[1].room, "Living", "le lustre est au salon")
		end)

		T.it("place plusieurs emplacements de clés, une sortie au garage, la voiture et le disjoncteur", function()
			T.expect(#tagged(MapTags.KeySpot) >= 4, "emplacements de clés")
			local exits = tagged(MapTags.Exit)
			T.expectEqual(#exits, 1, "une sortie")
			T.expectEqual(exits[1].room, "Garage")
			local breakers = tagged(MapTags.Breaker)
			T.expectEqual(#breakers, 1, "un disjoncteur")
			T.expectEqual(breakers[1].room, "Cave")
			T.expect(table.find(plan.groups.EscapeCar.tags, MapTags.EscapeCar), "voiture taguée")
			T.expectEqual(plan.groups.EscapeCar.room, "Garage")
			T.expectEqual(#tagged(MapTags.GarageDoor), 1, "porte du garage")
		end)

		T.it("pose un volume tagué par pièce avec son aile et son ombre", function()
			local zones = tagged(MapTags.Room)
			T.expectEqual(#zones, #HouseLayout.rooms)
			for _, z in zones do
				T.expect(z.attributes.WingId and z.attributes.Level ~= nil and z.attributes.Dark ~= nil, z.name)
			end
		end)
	end)

	T.describe("HouseGeometry.validate : rejets", function()
		T.it("refuse une porte qui n'est pas sur un mur des deux pièces", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.doors, "KitchenHall").z = 15
			T.expect(mentions(HouseGeometry.validate(broken), "KitchenHall : pas sur un mur"))
		end)

		T.it("refuse un meuble qui bouche une porte", function()
			local broken = deepCopy(HouseLayout)
			local table_ = byId(broken.props, "KitchenTable")
			table_.x, table_.z = 12, 17
			T.expect(mentions(HouseGeometry.validate(broken), "KitchenTable : bouche la porte KitchenHall"))
		end)

		T.it("refuse deux pièces qui se chevauchent", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Kitchen").x1 = 30
			T.expect(mentions(HouseGeometry.validate(broken), "se chevauchent"))
		end)

		T.it("refuse une pièce sans plafond ni étage au-dessus", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Garage").roof = nil
			T.expect(mentions(HouseGeometry.validate(broken), "Garage : sans plafond"))
		end)

		T.it("refuse une pièce coupée du reste de la maison", function()
			local broken = deepCopy(HouseLayout)
			for i, door in broken.doors do
				if door.id == "GarageHall" then
					table.remove(broken.doors, i)
					break
				end
			end
			T.expect(mentions(HouseGeometry.validate(broken), "Garage : inaccessible"))
		end)

		T.it("refuse une lampe dans une zone sombre", function()
			local broken = deepCopy(HouseLayout)
			table.insert(broken.lamps, { id = "HallLamp", room = "HallDown", x = 10, z = 24 })
			T.expect(mentions(HouseGeometry.validate(broken), "HallLamp : lampe dans une zone sombre"))
		end)
	end)

	T.describe("HouseGeometry.validate : types inconnus", function()
		T.it("refuse un type d'ancrage, de lampe, de piège ou de tag inconnu", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.anchors, "Exit").kind = "Exitt"
			byId(broken.lamps, "KitchenLamp").kind = "Wall"
			byId(broken.props, "KitchenShelf").trap = "Shelff"
			byId(broken.props, "Breaker").tag = "Brekaer"
			local errors = HouseGeometry.validate(broken)
			T.expect(mentions(errors, "Exit : type d'ancrage inconnu"), "ancrage")
			T.expect(mentions(errors, "KitchenLamp : type de lampe inconnu"), "lampe")
			T.expect(mentions(errors, "KitchenShelf : type de piège inconnu"), "piège")
			T.expect(mentions(errors, "Breaker : tag inconnu"), "tag")
		end)

		T.it("refuse une apparition dans un meuble", function()
			local broken = deepCopy(HouseLayout)
			local spawn = byId(broken.anchors, "MortalSpawn2")
			spawn.x, spawn.z = 34, 4
			T.expect(mentions(HouseGeometry.validate(broken), "MortalSpawn2 est dans LivingSofa"))
		end)

		T.it("refuse une porte extérieure percée dans un mur intérieur", function()
			local broken = deepCopy(HouseLayout)
			local front = byId(broken.doors, "EntryHall")
			front.rooms, front.leaf = { "Entry" }, "FrontDoor"
			local errors = HouseGeometry.validate(broken)
			T.expect(mentions(errors, "EntryHall : porte extérieure sur un mur partagé avec HallDown"))
		end)

		T.it("signale une description incomplète au lieu de planter", function()
			local broken = deepCopy(HouseLayout)
			broken.car = nil
			local errors, partial = HouseGeometry.validate(broken)
			T.expect(mentions(errors, "description sans car"), "voiture manquante")
			T.expectEqual(partial, nil)
		end)

		T.it("renvoie le plan calculé avec une description valide", function()
			local errors, validPlan = HouseGeometry.validate(HouseLayout)
			T.expectEqual(#errors, 0)
			T.expectEqual(#validPlan.pieces, #plan.pieces)
		end)
	end)

	T.describe("HouseGeometry.splitWall", function()
		T.it("laisse l'ouverture vide et garde un linteau au-dessus", function()
			local rects = HouseGeometry.splitWall(0, 20, 0, 11, { { u0 = 8, u1 = 13, y0 = 0, y1 = 8 } })
			T.expectEqual(#rects, 3)
			for _, r in rects do
				local inOpening = r.u0 < 13 and r.u1 > 8 and r.y0 < 8
				T.expect(not inOpening, "bloc dans l'ouverture")
			end
		end)

		T.it("signale deux ouvertures qui se chevauchent", function()
			local _, problem = HouseGeometry.splitWall(0, 20, 0, 11, {
				{ u0 = 2, u1 = 7, y0 = 0, y1 = 8 },
				{ u0 = 5, u1 = 10, y0 = 0, y1 = 8 },
			})
			T.expect(problem ~= nil, "chevauchement non signalé")
		end)
	end)
end
