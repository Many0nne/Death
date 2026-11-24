-- Escape et SpawnPlan : règles pures de l'objectif de fuite (#7) et de l'apparition en début de manche (#11).
return function(T, Loader)
	local loader = Loader.new()
	local Escape = loader:require("src/shared/Escape")
	local SpawnPlan = loader:require("src/shared/SpawnPlan")
	local HouseLayout = loader:require("src/shared/HouseLayout")
	local HouseGeometry = loader:require("src/shared/HouseGeometry")
	local GameConfig = loader:require("src/shared/GameConfig")
	local MapTags = loader:require("src/shared/MapTags")

	-- Cette méthode permet de renvoyer toujours le même index lorsqu'un test veut un tirage déterministe.
	local function pickFixed(index)
		return function(n)
			return math.min(index, n)
		end
	end

	-- Cette méthode permet de tirer des index pseudo-aléatoires reproductibles lorsqu'un test répète le tirage.
	local function pickSeeded(seed)
		local state = seed
		return function(n)
			state = (state * 1103515245 + 12345) % 2147483648
			return state % n + 1
		end
	end

	-- Emplacements de clés de la vraie maison, comme Server.EscapeService les lit sur les ancrages KeySpot
	local houseSpots, exitRoom = {}, nil
	for _, p in HouseGeometry.build(HouseLayout).pieces do
		if table.find(p.tags, MapTags.KeySpot) then
			table.insert(houseSpots, { id = p.attributes.AnchorId, room = p.room })
		elseif table.find(p.tags, MapTags.Exit) then
			exitRoom = p.room
		end
	end

	T.describe("Escape.drawKeySpots", function()
		local spots = {
			{ id = "A", room = "R1" },
			{ id = "B", room = "R1" },
			{ id = "C", room = "R2" },
			{ id = "D", room = "R3" },
			{ id = "E", room = "Garage" },
		}

		T.it("tire des emplacements distincts, un par pièce, hors pièce exclue", function()
			for seed = 1, 50 do
				local chosen = Escape.drawKeySpots(spots, 3, pickSeeded(seed), "Garage")
				T.expectEqual(#chosen, 3)
				local rooms = {}
				for _, id in chosen do
					T.expect(id ~= "E", "emplacement de la pièce exclue")
					local room = if id == "A" or id == "B" then "R1" elseif id == "C" then "R2" else "R3"
					T.expect(not rooms[room], "deux clés dans " .. room)
					rooms[room] = true
				end
			end
		end)

		T.it("ne dépend que du tirage, pas de l'ordre des emplacements", function()
			local reversed = {}
			for i = #spots, 1, -1 do
				table.insert(reversed, spots[i])
			end
			local a = Escape.drawKeySpots(spots, 3, pickSeeded(7), "Garage")
			local b = Escape.drawKeySpots(reversed, 3, pickSeeded(7), "Garage")
			T.expectEqual(table.concat(a, ","), table.concat(b, ","))
		end)

		T.it("varie d'une manche à l'autre", function()
			local seen = {}
			for seed = 1, 30 do
				seen[table.concat(Escape.drawKeySpots(spots, 2, pickSeeded(seed), "Garage"), ",")] = true
			end
			local variants = 0
			for _ in seen do
				variants += 1
			end
			T.expect(variants > 1, "toujours le même tirage")
		end)

		T.it("renvoie moins de clés s'il manque des pièces", function()
			T.expectEqual(#Escape.drawKeySpots(spots, 5, pickFixed(1), "Garage"), 3)
		end)

		T.it("trouve assez d'emplacements dans la maison, hors de la pièce de la sortie", function()
			T.expectEqual(exitRoom, "Driveway")
			local roomOf = {}
			for _, spot in houseSpots do
				roomOf[spot.id] = spot.room
			end
			for seed = 1, 20 do
				local chosen = Escape.drawKeySpots(houseSpots, GameConfig.ESCAPE_KEY_COUNT, pickSeeded(seed), exitRoom)
				T.expectEqual(#chosen, GameConfig.ESCAPE_KEY_COUNT)
				for _, id in chosen do
					T.expect(roomOf[id] ~= exitRoom, "clé près de la sortie : " .. id)
				end
			end
		end)
	end)

	T.describe("Escape : clés et voiture", function()
		T.it("ramasse chaque clé une seule fois", function()
			local o = Escape.new({ "A", "B" })
			T.expectEqual(o.keysNeeded, 2)
			T.expect((o:collectKey("A")), "première clé")
			local ok, err = o:collectKey("A")
			T.expectEqual(ok, false)
			T.expect(err ~= nil, "raison du refus")
			T.expectEqual((o:collectKey("Z")), false)
			T.expectEqual(o.keysFound, 1)
		end)

		T.it("ne démarre la voiture qu'avec toutes les clés, une seule fois", function()
			local o = Escape.new({ "A", "B" })
			T.expectEqual(o:canStartCar(), false)
			T.expectEqual((o:startCar()), false)
			o:collectKey("A")
			o:collectKey("B")
			T.expectEqual(o:canStartCar(), true)
			T.expectEqual(o:isComplete(), false)
			T.expect((o:startCar()), "démarrage")
			T.expectEqual(o:isComplete(), true)
			T.expectEqual(o:canStartCar(), false)
			T.expectEqual((o:startCar()), false)
		end)

		T.it("réserve les actions aux mortels vivants", function()
			T.expectEqual(Escape.canAct("Mortal", "Alive"), true)
			T.expectEqual(Escape.canAct("Death", nil), false)
			T.expectEqual(Escape.canAct("Mortal", "Agony"), false)
			T.expectEqual(Escape.canAct("Mortal", "Saved"), false)
			T.expectEqual(Escape.canAct(nil, nil), false)
		end)
	end)

	T.describe("Escape : condition de fuite", function()
		T.it("sauve un mortel vivant seulement une fois l'objectif rempli", function()
			local o = Escape.new({ "A" })
			T.expectEqual(o:canEscape("Mortal", "Alive"), false)
			o:collectKey("A")
			T.expectEqual(o:canEscape("Mortal", "Alive"), false)
			o:startCar()
			T.expectEqual(o:canEscape("Mortal", "Alive"), true)
			T.expectEqual(o:canEscape("Mortal", "Agony"), false)
			T.expectEqual(o:canEscape("Mortal", "Dead"), false)
			T.expectEqual(o:canEscape("Death", nil), false)
		end)

		T.it("détecte une position sur la sortie (rayon horizontal, hauteur bornée)", function()
			local exit = Vector3.new(77, 0, 14)
			T.expectEqual(Escape.isAtExit(Vector3.new(77, 3, 14), exit, 4, 6), true)
			T.expectEqual(Escape.isAtExit(Vector3.new(80, 3, 16), exit, 4, 6), true)
			T.expectEqual(Escape.isAtExit(Vector3.new(72, 3, 14), exit, 4, 6), false)
			T.expectEqual(Escape.isAtExit(Vector3.new(77, 15, 14), exit, 4, 6), false, "à l'étage")
			T.expectEqual(Escape.isAtExit(Vector3.new(77, -9, 14), exit, 4, 6), false, "à la cave")
		end)
	end)

	T.describe("SpawnPlan.assign", function()
		T.it("place un mortel par point et la Mort sur l'un des siens", function()
			for seed = 1, 30 do
				local plan = SpawnPlan.assign(9, { 1, 2, 3, 4 }, 4, 2, pickSeeded(seed))
				T.expect(plan ~= nil, "plan")
				local used = {}
				for _, id in { 1, 2, 3, 4 } do
					local p = plan[id]
					T.expectEqual(p.kind, "Mortal")
					T.expect(p.index >= 1 and p.index <= 4, "index de point")
					T.expect(not used[p.index], "deux mortels sur le même point")
					used[p.index] = true
				end
				T.expectEqual(plan[9].kind, "Death")
				T.expect(plan[9].index >= 1 and plan[9].index <= 2, "point de la Mort")
			end
		end)

		T.it("accepte moins de mortels que de points (mode test)", function()
			local plan = SpawnPlan.assign(9, { 1 }, 4, 2, pickFixed(1))
			T.expect(plan and plan[1] and plan[9], "plan partiel")
		end)

		T.it("refuse s'il manque des points", function()
			local plan, err = SpawnPlan.assign(9, { 1, 2, 3 }, 2, 1, pickFixed(1))
			T.expectEqual(plan, nil)
			T.expect(err ~= nil, "raison")
			T.expectEqual((SpawnPlan.assign(9, { 1 }, 4, 0, pickFixed(1))), nil)
		end)

		T.it("couvre les apparitions de la maison", function()
			local mortals, deaths = 0, 0
			for _, a in HouseLayout.anchors do
				if a.kind == "MortalSpawn" then
					mortals += 1
				elseif a.kind == "DeathSpawn" then
					deaths += 1
				end
			end
			T.expect(mortals >= GameConfig.MORTALS_PER_MATCH, "un point par mortel")
			T.expect(deaths >= 1, "un point pour la Mort")
		end)
	end)
end
