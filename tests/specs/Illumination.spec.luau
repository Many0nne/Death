-- Illumination : règle « est-ce éclairé ici ? » sur la vraie maison (construite par HouseBuilder sous Lune) et sur un
-- modèle minimal : pièces, portée des lampes, murs et dalles, disjoncteur, ampoules grillées.
return function(T, Loader)
	local loader = Loader.new()
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local HouseGeometry = loader:require("src/shared/HouseGeometry")
	local HouseLayout = loader:require("src/shared/HouseLayout")
	local Illumination = loader:require("src/shared/Illumination")

	local world = Instance.new("Folder")
	local house = HouseBuilder.build(world)
	local byId = HouseGeometry.roomsById(HouseLayout)

	-- Hauteur du HumanoidRootPart d'un personnage R15 debout au-dessus du sol (point testé pour la Mort)
	local ROOT_HEIGHT = 3

	-- Cette méthode permet de donner un point à hauteur de personnage dans une pièce lorsque le test vise un endroit
	-- du plan (x, z).
	local function at(roomId, x, z)
		return Vector3.new(x, HouseGeometry.floorY(HouseLayout, byId[roomId].level) + ROOT_HEIGHT, z)
	end

	-- Cette méthode permet de mesurer la part du sol d'une pièce éclairée à hauteur de personnage lorsque l'on vérifie
	-- la portée des lampes (grille de 1 stud dans l'intérieur de la pièce, premier niveau seulement).
	local function coverage(model, room)
		local inner = HouseGeometry.interior(HouseLayout, room)
		local lit, total = 0, 0
		for x = inner.x0 + 0.5, inner.x1 - 0.5 do
			for z = inner.z0 + 0.5, inner.z1 - 0.5 do
				total += 1
				if model:isLit(at(room.id, x, z)) then
					lit += 1
				end
			end
		end
		return lit / total
	end

	T.describe("Illumination.fromHouse", function()
		local model = Illumination.fromHouse(house)

		T.it("lit toutes les pièces et toutes les lampes de la maison", function()
			T.expectEqual(#model.roomOrder, #HouseLayout.rooms)
			T.expectEqual(#model:allLamps(), #HouseLayout.lamps)
			for _, lamp in model:allLamps() do
				T.expect(lamp.reach > 0, lamp.id .. " : portée nulle")
				T.expectEqual(lamp.wingId, byId[lamp.roomId].wing, lamp.id)
			end
		end)

		T.it("situe un point dans sa pièce, et nulle part hors de la maison", function()
			T.expectEqual(model:roomAt(at("Kitchen", 51, 28)), "Kitchen")
			T.expectEqual(model:roomAt(at("Cave", 50, 26)), "Cave")
			T.expectEqual(model:roomAt(at("Garden", 40, 80)), "Garden")
			T.expectEqual(model:roomAt(at("MasterBedroom", 12, 10)), "MasterBedroom")
			T.expectEqual(model:roomAt(Vector3.new(-20, 3, 10)), nil)
		end)

		T.it("éclaire le centre de chaque pièce éclairée et jamais une zone sombre", function()
			for _, room in HouseLayout.rooms do
				local inner = HouseGeometry.interior(HouseLayout, room)
				if room.lit then
					local lit = false
					for _, lamp in HouseLayout.lamps do
						if lamp.room == room.id and model:isLit(at(room.id, lamp.x, lamp.z)) then
							lit = true
						end
					end
					T.expect(lit, room.id .. " : pas éclairé sous ses lampes")
				else
					T.expectEqual(coverage(model, room), 0, room.id .. " : zone sombre éclairée")
				end
				T.expect(inner.x1 > inner.x0, room.id)
			end
		end)

		T.it("couvre au moins la moitié du sol de chaque pièce éclairée, des flaques de lumière dehors", function()
			local report = {}
			for _, room in HouseLayout.rooms do
				if room.lit then
					local c = coverage(model, room)
					table.insert(report, string.format("%s %d%%", room.id, math.floor(c * 100 + 0.5)))
					if room.outdoor then
						-- Dehors, la nuit : quelques lumières, la majeure partie du terrain reste sombre
						T.expect(c > 0.05 and c < 0.5, string.format("%s : %.0f %% éclairé dehors", room.id, c * 100))
					else
						T.expect(c >= 0.5, string.format("%s : %.0f %% éclairé seulement", room.id, c * 100))
					end
				end
			end
			-- Mesure de portée, reprise dans le compte rendu de la tâche
			print("  Couverture des pièces éclairées : " .. table.concat(report, ", "))
		end)

		T.it("éclaire la moitié du seuil côté pièce éclairée, pas celle côté dégagement", function()
			-- Porte entrée / dégagement : mur mitoyen de z = 19,5 à 20,5, lampe au milieu de l'entrée
			T.expectEqual((model:isLit(at("Entry", 31, 19.8))), true, "seuil côté entrée")
			T.expectEqual((model:isLit(at("HallDown", 31, 20.3))), false, "seuil côté dégagement")
			T.expectEqual(model:roomAt(at("Entry", 31, 19.8)), "Entry")
		end)

		T.it("dehors, laisse la lumière passer d'une zone à l'autre (aucun mur)", function()
			-- Devant de la maison, à 14 studs du lampadaire de l'allée et à plus de 50 de l'applique du porche
			local lit, lampId = model:isLit(at("FrontYard", 89, -10))
			T.expectEqual(lit, true)
			T.expectEqual(lampId, "StreetLamp")
			T.expectEqual(model:roomAt(at("FrontYard", 89, -10)), "FrontYard")
			-- Une lampe extérieure n'entre pas dans la maison : le salon derrière la façade reste sur ses lampes
			local m = Illumination.fromHouse(house)
			m:burnRoom("Living")
			T.expectEqual((m:isLit(at("Living", 20, 2))), false)
			-- Seuil de la véranda (sombre) sur le jardin : la lanterne s'arrête au milieu du mur
			m:burnRoom("Veranda")
			T.expectEqual((m:isLit(at("Veranda", 10, 69.6))), false, "seuil côté véranda")
			T.expectEqual((m:isLit(at("Garden", 10, 70.3))), true, "seuil côté jardin")
		end)

		T.it("arrête la lumière aux murs : le dégagement contre l'entrée reste sombre", function()
			-- À 1,5 stud du mur, la lampe de l'entrée est à portée mais dans une autre pièce
			T.expectEqual((model:isLit(at("HallDown", 31, 21.5))), false)
		end)

		T.it("arrête la lumière aux dalles : la chambre au-dessus du salon ne profite pas de son lustre", function()
			local m = Illumination.fromHouse(house)
			m:burnRoom("MasterBedroom")
			T.expectEqual((m:isLit(at("MasterBedroom", 12, 10))), false)
			T.expectEqual((m:isLit(at("Living", 12, 10))), true)
		end)

		T.it("éteint une aile entière au disjoncteur et la rallume", function()
			local m = Illumination.fromHouse(house)
			T.expectEqual(m:setWingPowered("Day", false), true)
			T.expectEqual(m:setWingPowered("Day", false), false, "déjà coupée")
			for _, id in { "Kitchen", "Living", "Entry" } do
				T.expectEqual(m:isRoomLit(id), false, id)
			end
			T.expectEqual(m:isRoomLit("Garage"), true, "aile service intacte")
			T.expectEqual(m:isRoomLit("Bathroom"), true, "aile nuit intacte")
			m:setWingPowered("Day", true)
			T.expectEqual(m:isRoomLit("Living"), true)
		end)

		T.it("grille toutes les ampoules d'une pièce, et seulement elles", function()
			local m = Illumination.fromHouse(house)
			local burnt = m:burnRoom("Living")
			table.sort(burnt)
			T.expectEqual(table.concat(burnt, ","), "LivingChandelier,LivingLamp")
			T.expectEqual(m:isRoomLit("Living"), false)
			T.expectEqual(m:isRoomLit("Kitchen"), true)
			T.expectEqual(#m:burnRoom("Living"), 0, "déjà grillées")
			-- Une ampoule grillée ne revient pas avec le courant
			m:setWingPowered("Day", false)
			m:setWingPowered("Day", true)
			T.expectEqual(m:isRoomLit("Living"), false)
		end)

		T.it("rallume tout à la remise à zéro", function()
			local m = Illumination.fromHouse(house)
			m:burnRoom("Kitchen")
			m:setWingPowered("Night", false)
			m:reset()
			T.expectEqual(m:isRoomLit("Kitchen"), true)
			T.expectEqual(m:isRoomLit("Study"), true)
		end)

		T.it("refuse une aile inconnue", function()
			local m = Illumination.fromHouse(house)
			T.expect(not pcall(m.setWingPowered, m, "Attic", false))
		end)
	end)

	T.describe("Illumination (modèle minimal)", function()
		local rooms = {
			{ id = "A", wingId = "W", min = Vector3.new(0, 0, 0), max = Vector3.new(20, 10, 20) },
			{ id = "B", wingId = "W", min = Vector3.new(20, 0, 0), max = Vector3.new(40, 10, 20) },
		}
		local lamps = {
			{ id = "LA", roomId = "A", wingId = "W", position = Vector3.new(10, 9, 10), reach = 8 },
		}

		T.it("éclaire jusqu'à la portée de la lampe, pas au-delà", function()
			local m = Illumination.new(rooms, lamps)
			local lit, lampId = m:isLit(Vector3.new(10, 1, 10))
			T.expectEqual(lit, true)
			T.expectEqual(lampId, "LA")
			T.expectEqual((m:isLit(Vector3.new(10, 9, 17.9))), true, "juste dans la portée")
			T.expectEqual((m:isLit(Vector3.new(10, 9, 18.1))), false, "juste hors de portée")
		end)

		T.it("lit la portée d'une PointLight multipliée par REACH_FACTOR", function()
			local model = Illumination.fromHouse(house)
			local kitchen = model.lamps.KitchenLamp
			T.expectNear(kitchen.reach, HouseGeometry.LAMP_STYLES.Ceiling.range * Illumination.REACH_FACTOR)
		end)

		T.it("refuse une lampe dans une pièce inconnue et les doublons", function()
			T.expect(not pcall(Illumination.new, rooms, {
				{ id = "X", roomId = "Z", wingId = "W", position = Vector3.new(), reach = 1 },
			}))
			T.expect(not pcall(Illumination.new, { rooms[1], rooms[1] }, {}))
			T.expect(not pcall(Illumination.new, rooms, { lamps[1], lamps[1] }))
		end)
	end)
end
