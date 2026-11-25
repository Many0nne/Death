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
				Dining = 0,
				Laundry = 0,
				Library = 0,
				Veranda = 0,
				Attic = 1,
				TeenBedroom = 1,
				Garden = 0,
				Driveway = 0,
				Shed = 0,
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
			for _, id in { "HallDown", "HallUp", "HallEast", "Stairs", "GarageStairs", "CaveStairs", "Cave", "Cellar" } do
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

	T.describe("HouseLayout : plan en boucles (#25)", function()
		local graph = HouseGeometry.neighbors(HouseLayout)

		-- Cette méthode permet de compter pièces, passages et boucles indépendantes d'un niveau lorsque l'on vérifie que
		-- le plan n'est pas linéaire (boucles = passages - pièces + composantes connexes).
		local function levelGraph(level)
			local rooms, count, edges = {}, 0, 0
			for _, room in HouseLayout.rooms do
				if HouseGeometry.spansLevel(room, level) then
					rooms[room.id] = true
					count += 1
				end
			end
			for id in rooms do
				for _, other in graph[id] do
					if rooms[other] then
						edges += 1
					end
				end
			end
			edges //= 2
			local seen, components = {}, 0
			for id in rooms do
				if not seen[id] then
					components += 1
					local stack = { id }
					seen[id] = true
					while #stack > 0 do
						for _, other in graph[table.remove(stack)] do
							if rooms[other] and not seen[other] then
								seen[other] = true
								table.insert(stack, other)
							end
						end
					end
				end
			end
			return { rooms = count, loops = edges - count + components }
		end

		T.it("offre au moins deux boucles par niveau", function()
			for level = -1, 1 do
				local g = levelGraph(level)
				T.expect(g.loops >= 2, string.format("niveau %d : %d boucle(s)", level, g.loops))
			end
		end)

		T.it("n'a aucun cul-de-sac : chaque pièce mène à au moins deux voisines", function()
			for _, room in HouseLayout.rooms do
				local distinct, count = {}, 0
				for _, other in graph[room.id] do
					if not distinct[other] then
						distinct[other] = true
						count += 1
					end
				end
				T.expect(count >= 2, room.id .. " : une seule voisine")
			end
		end)

		T.it("relie chaque niveau au suivant par au moins deux escaliers", function()
			local accesses = {}
			for _, room in HouseLayout.rooms do
				if room.stairs then
					accesses[room.level] = (accesses[room.level] or 0) + 1
				end
			end
			T.expect((accesses[-1] or 0) >= 2, "cave ↔ rez")
			T.expect((accesses[0] or 0) >= 2, "rez ↔ étage")
		end)

		T.it("offre au moins deux fois la surface du prototype #3 (7 896 studs²)", function()
			local total = 0
			for _, room in HouseLayout.rooms do
				total += (room.x1 - room.x0) * (room.z1 - room.z0) * (room.levels or 1)
			end
			T.expect(total >= 2 * 7896, total .. " studs²")
		end)

		T.it("varie la taille des pièces (petites pièces, grand séjour)", function()
			local smallest, largest = math.huge, 0
			for _, room in HouseLayout.rooms do
				if not room.outdoor and not room.stairs then
					local area = (room.x1 - room.x0) * (room.z1 - room.z0)
					smallest = math.min(smallest, area)
					largest = math.max(largest, area)
				end
			end
			T.expect(largest >= 4 * smallest, string.format("%d / %d studs²", largest, smallest))
		end)
	end)

	T.describe("HouseLayout : extérieur (#25)", function()
		local rooms = HouseGeometry.roomsById(HouseLayout)

		T.it("a un jardin éclairé par endroits, un abri, une allée et la rue derrière le portail", function()
			T.expect(rooms.Garden and rooms.Garden.outdoor, "jardin")
			T.expect(rooms.Driveway and rooms.Driveway.outdoor, "allée")
			T.expect(rooms.Shed and not rooms.Shed.outdoor and rooms.Shed.roof, "abri couvert")
			local outdoorLamps = 0
			for _, lamp in HouseLayout.lamps do
				if rooms[lamp.room].outdoor then
					outdoorLamps += 1
				end
			end
			T.expect(outdoorLamps >= 2 and outdoorLamps <= 4, outdoorLamps .. " lumières dehors (quelques-unes)")
			local street = false
			for _, s in HouseLayout.scenery do
				street = street or s.kind == "Street"
			end
			T.expect(street, "rue")
		end)

		T.it("relie les zones extérieures voisines sans porte, mais pas par un bord trop court", function()
			local linked = {}
			for _, l in HouseGeometry.outdoorLinks(HouseLayout) do
				linked[l.a .. "/" .. l.b] = true
				linked[l.b .. "/" .. l.a] = true
			end
			T.expect(linked["FrontYard/Driveway"], "devant ↔ allée")
			T.expect(linked["WestSide/Garden"], "côté ouest ↔ jardin")
			T.expect(not linked["NorthPassage/VegetableGarden"], "bord de 4 studs : pas un passage")
		end)

		T.it("pose clôtures, terrain et décor hors carte", function()
			local fences, grounds, scenery = 0, 0, 0
			for _, p in plan.pieces do
				if p.kind == "Fence" then
					fences += 1
					T.expectNear(p.size.Y, HouseLayout.FENCE_HEIGHT - (p.center.Y - p.size.Y / 2), 1e-6, p.name)
				elseif p.kind == "Ground" then
					grounds += 1
				elseif p.kind == "Street" or p.kind == "Lawn" then
					scenery += 1
					T.expectEqual(p.room, nil, p.name)
				end
			end
			T.expect(fences > 0 and grounds > 0, "clôtures et terrain")
			T.expectEqual(scenery, #HouseLayout.scenery)
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

		T.it("répartit environ 30 points fragiles dans la maison et dehors (docs/design.md)", function()
			local rooms = {}
			local total = 0
			for _, p in tagged(MapTags.TrapCandidate) do
				total += 1
				rooms[p.room] = true
			end
			local roomCount = 0
			for _ in rooms do
				roomCount += 1
			end
			T.expect(total >= 25, total .. " candidats seulement")
			T.expect(roomCount >= 20, roomCount .. " pièces avec un candidat seulement")
			local byRoom = HouseGeometry.roomsById(HouseLayout)
			local outdoor = false
			for id in rooms do
				outdoor = outdoor or byRoom[id].outdoor == true
			end
			T.expect(outdoor, "aucun candidat dehors")
		end)

		T.it(
			"place plusieurs emplacements de clés, une sortie au bout de l'allée, la voiture et le disjoncteur",
			function()
				T.expect(#tagged(MapTags.KeySpot) >= 4, "emplacements de clés")
				local exits = tagged(MapTags.Exit)
				T.expectEqual(#exits, 1, "une sortie")
				T.expectEqual(exits[1].room, "Driveway")
				-- La sortie attend devant le portail de la rue
				local gates = tagged(MapTags.Gate)
				T.expectEqual(#gates, 1, "un portail")
				local d = exits[1].center - gates[1].center
				T.expect(math.sqrt(d.X * d.X + d.Z * d.Z) <= 10, "sortie loin du portail")
				local breakers = tagged(MapTags.Breaker)
				T.expectEqual(#breakers, 1, "un disjoncteur")
				T.expectEqual(breakers[1].room, "Cave")
				T.expect(table.find(plan.groups.EscapeCar.tags, MapTags.EscapeCar), "voiture taguée")
				T.expectEqual(plan.groups.EscapeCar.room, "Garage")
				T.expectEqual(#tagged(MapTags.GarageDoor), 1, "porte du garage")
			end
		)

		T.it("pose un volume tagué par pièce avec son aile et son ombre", function()
			local zones = tagged(MapTags.Room)
			T.expectEqual(#zones, #HouseLayout.rooms)
			for _, z in zones do
				T.expect(z.attributes.WingId and z.attributes.Level ~= nil and z.attributes.Dark ~= nil, z.name)
			end
		end)
	end)

	T.describe("HouseLayout : petits objets (#38)", function()
		-- Cette méthode permet de compter les petits objets (garnitures et objets des meubles) d'une pièce lorsque l'on
		-- vérifie qu'elle est habitée.
		local function smallCount(roomId)
			local n = 0
			for _, p in plan.pieces do
				if p.room == roomId and (p.kind == "Clutter" or p.small) then
					n += 1
				end
			end
			return n
		end

		T.it("garnit chaque pièce de vie de petits objets, la bibliothèque plus que toutes", function()
			local rooms = {
				"Living",
				"Entry",
				"Dining",
				"Kitchen",
				"Library",
				"Laundry",
				"Veranda",
				"Garage",
				"Study",
				"MasterBedroom",
				"Bathroom",
				"KidsBedroom",
				"GuestBedroom",
				"TeenBedroom",
				"ShowerRoom",
				"Attic",
				"Cave",
				"Cellar",
				"WineCellar",
				"Workshop",
				"Shed",
			}
			local library = smallCount("Library")
			for _, id in rooms do
				local n = smallCount(id)
				T.expect(n >= 8, id .. " : " .. n .. " petits objets seulement")
				if id ~= "Library" then
					T.expect(library > n, "la bibliothèque doit être la plus dense (" .. id .. " : " .. n .. ")")
				end
			end
		end)

		T.it("remplit les étagères de livres un par un et la cave à vin de bouteilles", function()
			local books, bottles = {}, 0
			for _, p in plan.pieces do
				if p.kind == "Detail" and p.small and string.find(p.name, "^Book") then
					books[p.group] = (books[p.group] or 0) + 1
				elseif p.room == "WineCellar" and p.small and string.find(p.name, "^Bottle%d*$") then
					bottles += 1
				end
			end
			for _, prop in HouseLayout.props do
				if prop.style == "Bookcase" then
					local shelf = math.max(prop.size[1], prop.size[3])
					T.expect((books[prop.id] or 0) >= shelf * 8, prop.id .. " : " .. (books[prop.id] or 0) .. " livres")
				end
			end
			T.expect(bottles >= 100, bottles .. " bouteilles")
		end)

		T.it("pose chaque garniture sur une surface : sol, dessus de son meuble ou contre un mur", function()
			local byRoom = HouseGeometry.roomsById(HouseLayout)
			local propsById = {}
			for _, prop in HouseLayout.props do
				propsById[prop.id] = prop
			end
			for _, c in HouseLayout.clutter do
				local g = plan.groups[c.id]
				T.expect(g ~= nil, c.id .. " sans groupe")
				local room = byRoom[g.room]
				local floor = HouseGeometry.floorY(HouseLayout, room.level)
				local bottom = math.huge
				for _, p in plan.pieces do
					if p.group == c.id then
						local minV = HouseGeometry.extent(p)
						bottom = math.min(bottom, minV.Y)
					end
				end
				if c.on then
					local prop = propsById[c.on]
					local top = floor + (prop.y or 0) + prop.size[2]
					T.expect(math.abs(bottom - top) < 0.01, c.id .. " ne repose pas sur " .. c.on)
				elseif c.wall then
					local inner = HouseGeometry.interior(HouseLayout, room)
					local face = ({ North = inner.z1, South = inner.z0, East = inner.x1, West = inner.x0 })[c.wall]
					local box = g.box
					local touching = if c.wall == "North"
						then box.max.Z
						elseif c.wall == "South" then box.min.Z
						elseif c.wall == "East" then box.max.X
						else box.min.X
					T.expect(math.abs(touching - face) < 0.01, c.id .. " décollée du mur " .. c.wall)
					if (c.y or 0) == 0 then
						T.expect(math.abs(bottom - floor) < 0.01, c.id .. " appuyée au mur mais pas au sol")
					end
				else
					T.expect(math.abs(bottom - floor) < 0.01, c.id .. " ne repose pas au sol")
				end
			end
		end)

		T.it("construit la même maison à chaque fois (variation déterministe)", function()
			local again = HouseGeometry.build(HouseLayout)
			T.expectEqual(#again.pieces, #plan.pieces)
			for i, p in again.pieces do
				local q = plan.pieces[i]
				T.expect(
					p.name == q.name and p.center == q.center and p.size == q.size,
					"bloc " .. i .. " : " .. p.name
				)
			end
		end)

		T.it("refuse une garniture qui bouche une porte ou traverse un meuble", function()
			local broken = deepCopy(HouseLayout)
			table.insert(broken.clutter, {
				id = "DoorToys",
				room = "Kitchen",
				x = 51,
				z = 21.5,
				size = { 3, 1, 1.5 },
				set = "Toys",
			})
			table.insert(broken.clutter, {
				id = "SofaToys",
				room = "Living",
				x = 12,
				z = 6,
				size = { 3, 1, 1.5 },
				set = "Toys",
			})
			local errors = HouseGeometry.validate(broken)
			T.expect(mentions(errors, "DoorToys : bouche la porte DiningKitchen"), "porte")
			T.expect(mentions(errors, "SofaToys chevauche LivingSofa"), "meuble")
		end)

		T.it("refuse une garniture sur un emplacement de clés, sur un piège ou trop haute au sol", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.clutter, "EntryConsoleTray").at = { 0, 0 }
			table.insert(broken.clutter, {
				id = "TallToys",
				room = "Living",
				x = 4,
				z = 20,
				size = { 2, 2, 2 },
				set = "Toys",
			})
			local errors = HouseGeometry.validate(broken)
			T.expect(mentions(errors, "EntryConsoleTray couvre EntryConsoleKeySpot"), "clés")
			T.expect(mentions(errors, "TallToys : garniture au sol plus haute qu'une marche"), "hauteur")
			-- Refus de description (avant tout calcul de blocs) : vérifié à part
			local trap = deepCopy(HouseLayout)
			table.insert(trap.clutter, { id = "OnShelf", on = "LivingBookcase", set = "Lamp" })
			local trapErrors = HouseGeometry.validate(trap)
			T.expect(mentions(trapErrors, "OnShelf : posée sur un candidat de piège (LivingBookcase)"), "piège")
		end)

		T.it("refuse une garniture inconnue ou devant une fenêtre", function()
			local unknown = deepCopy(HouseLayout)
			byId(unknown.clutter, "LivingClock").set = "Clockk"
			T.expect(mentions(HouseGeometry.validate(unknown), "LivingClock : garniture inconnue Clockk"), "inconnue")
			local window = deepCopy(HouseLayout)
			table.insert(window.clutter, {
				id = "WindowPainting",
				room = "Living",
				wall = "South",
				at = 6.75,
				y = 4,
				size = { 3, 2, 0.15 },
				set = "Landscape",
			})
			local errors = HouseGeometry.validate(window)
			T.expect(mentions(errors, "WindowPainting chevauche LivingWallSouth1Window"), "fenêtre")
		end)
	end)

	T.describe("HouseGeometry.validate : rejets", function()
		T.it("refuse une porte qui n'est pas sur un mur des deux pièces", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.doors, "DiningKitchen").z = 15
			T.expect(mentions(HouseGeometry.validate(broken), "DiningKitchen : pas sur un mur"))
		end)

		T.it("refuse un meuble qui bouche une porte", function()
			local broken = deepCopy(HouseLayout)
			local island = byId(broken.props, "KitchenIsland")
			island.z = 22.5
			T.expect(mentions(HouseGeometry.validate(broken), "KitchenIsland : bouche la porte DiningKitchen"))
		end)

		T.it("refuse deux pièces qui se chevauchent", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Kitchen").x0 = 30
			T.expect(mentions(HouseGeometry.validate(broken), "se chevauchent"))
		end)

		T.it("refuse une pièce sans plafond ni étage au-dessus", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Veranda").roof = nil
			T.expect(mentions(HouseGeometry.validate(broken), "Veranda : sans plafond"))
		end)

		T.it("refuse une pièce coupée du reste de la maison", function()
			local broken = deepCopy(HouseLayout)
			for i = #broken.doors, 1, -1 do
				if table.find(broken.doors[i].rooms, "Shed") then
					table.remove(broken.doors, i)
				end
			end
			T.expect(mentions(HouseGeometry.validate(broken), "Shed : inaccessible"))
		end)

		T.it("refuse une lampe dans une zone sombre", function()
			local broken = deepCopy(HouseLayout)
			table.insert(broken.lamps, { id = "HallLamp", room = "HallDown", x = 31, z = 28 })
			T.expect(mentions(HouseGeometry.validate(broken), "HallLamp : lampe dans une zone sombre"))
		end)
	end)

	T.describe("HouseGeometry.validate : types inconnus", function()
		T.it("refuse un type d'ancrage, de lampe, de piège ou de tag inconnu", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.anchors, "Exit").kind = "Exitt"
			byId(broken.lamps, "KitchenLamp").kind = "Spot"
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
			spawn.x, spawn.z = 12, 6
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

	T.describe("HouseGeometry.validate : extérieur", function()
		T.it("refuse un meuble dehors devant une porte extérieure", function()
			local broken = deepCopy(HouseLayout)
			table.insert(broken.props, { id = "Bin", room = "Driveway", x = 94, z = 14, size = { 2, 2, 2 } })
			T.expect(mentions(HouseGeometry.validate(broken), "Bin : bouche la porte GarageDoor"))
		end)

		T.it("arrête le volume d'une zone extérieure au milieu du mur de la maison", function()
			local garden = HouseGeometry.interior(HouseLayout, byId(HouseLayout.rooms, "Garden"))
			T.expectEqual(garden.z0, 70.5, "contre la véranda")
			local courtyard = HouseGeometry.interior(HouseLayout, byId(HouseLayout.rooms, "Courtyard"))
			T.expectEqual(courtyard.x1, 88, "côté potager : bord libre")
		end)

		T.it("refuse un terrain ouvert sur le vide (côté sans clôture ni voisin)", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "WestSide").fence = {}
			T.expect(mentions(HouseGeometry.validate(broken), "WestSide : bord West ouvert sur le vide"))
		end)

		T.it("refuse un meuble qui bouche un passage entre deux zones extérieures", function()
			local broken = deepCopy(HouseLayout)
			table.insert(broken.props, { id = "Woodpile", room = "NorthPassage", x = 90, z = 52, size = { 2, 2, 7 } })
			T.expect(mentions(HouseGeometry.validate(broken), "passage Driveway ↔ NorthPassage bouché"))
		end)

		T.it("refuse un meuble de jardin qui sert de marchepied vers un lampadaire", function()
			local broken = deepCopy(HouseLayout)
			local table_ = byId(broken.props, "GardenTable")
			table_.x, table_.z = 24, 82
			T.expect(mentions(HouseGeometry.validate(broken), "GardenTable : marchepied vers le lampadaire GardenLamp"))
		end)

		T.it("refuse une pièce hors de la limite du terrain", function()
			local broken = deepCopy(HouseLayout)
			broken.bounds.x1 = 100
			T.expect(mentions(HouseGeometry.validate(broken), "Driveway : hors de la limite du terrain"))
		end)

		T.it("refuse une zone extérieure couverte", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Garden").roof = true
			T.expect(mentions(HouseGeometry.validate(broken), "Garden : une zone extérieure est à ciel ouvert"))
		end)

		T.it("refuse une clôture entre deux zones extérieures", function()
			local broken = deepCopy(HouseLayout)
			table.insert(byId(broken.rooms, "Garden").fence, "South")
			T.expect(mentions(HouseGeometry.validate(broken), "Garden : clôture South contre la zone"))
		end)

		T.it("refuse un meuble de jardin qui sert de marchepied par-dessus la clôture", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.props, "GardenTable").size[2] = 4
			T.expect(mentions(HouseGeometry.validate(broken), "GardenTable : meuble extérieur assez haut"))
		end)

		T.it("refuse une lampe de plafond dehors", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.lamps, "GardenLamp").kind = nil
			T.expect(mentions(HouseGeometry.validate(broken), "GardenLamp : lampe de plafond dehors"))
		end)

		T.it("refuse un décor posé sur la carte", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.scenery, "Street").z1 = -10
			T.expect(mentions(HouseGeometry.validate(broken), "Street : décor posé sur la carte (FrontYard)"))
		end)

		T.it("refuse un portail sans clôture autour", function()
			local broken = deepCopy(HouseLayout)
			byId(broken.rooms, "Driveway").fence = { "East" }
			T.expect(mentions(HouseGeometry.validate(broken), "Gate : battant sans clôture autour dans Driveway"))
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
