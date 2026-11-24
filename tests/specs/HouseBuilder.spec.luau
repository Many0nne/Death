-- Générateur de la maison : instancie le plan sous un parent, avec tags CollectionService et lumières, et l'ambiance de
-- nuit (instances Roblox simulées par Lune).
return function(T, Loader)
	local loader = Loader.new()
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local NightAmbience = loader:require("src/server/NightAmbience")
	local MapTags = loader:require("src/shared/MapTags")

	-- Cette méthode permet de compter les descendants portant un tag lorsque l'on vérifie la maison construite.
	local function countTagged(root, tag)
		local n = 0
		for _, d in root:GetDescendants() do
			if d:HasTag(tag) then
				n += 1
			end
		end
		return n
	end

	T.describe("HouseBuilder.build", function()
		local world = Instance.new("Folder")
		local baseplate = Instance.new("Part")
		baseplate.Name = "Baseplate"
		baseplate.Parent = world
		local templateSpawn = Instance.new("SpawnLocation")
		templateSpawn.Parent = world
		local house = HouseBuilder.build(world)

		T.it("construit un modèle House avec un dossier par pièce", function()
			T.expectEqual(house.Parent, world)
			T.expect(house:FindFirstChild("Kitchen"), "dossier Kitchen")
			T.expect(house:FindFirstChild("Cave"), "dossier Cave")
		end)

		T.it("retire le Baseplate et le SpawnLocation du modèle de place", function()
			T.expectEqual(world:FindFirstChild("Baseplate"), nil)
			T.expectEqual(world:FindFirstChild("SpawnLocation"), nil)
			local spawns = 0
			for _, d in house:GetDescendants() do
				if d:IsA("SpawnLocation") then
					spawns += 1
				end
			end
			T.expectEqual(spawns, 0, "aucun SpawnLocation dans la maison (zone d'attente)")
		end)

		T.it("donne une PointLight à chaque lampe taguée", function()
			local lamps = 0
			for _, d in house:GetDescendants() do
				if d:HasTag(MapTags.Lamp) then
					lamps += 1
					T.expect(d:FindFirstChild("Light") and d.Light:IsA("PointLight"), d.Name .. " sans PointLight")
					T.expect(d:GetAttribute("WingId") ~= nil, d.Name .. " sans WingId")
				end
			end
			T.expect(lamps > 0, "aucune lampe")
		end)

		T.it("tague la voiture (Model avec PrimaryPart) et les ancrages invisibles", function()
			local car = house.Garage.EscapeCar
			T.expect(car:HasTag(MapTags.EscapeCar), "voiture non taguée")
			T.expect(car.PrimaryPart ~= nil, "voiture sans PrimaryPart")
			T.expect(countTagged(house, MapTags.MortalSpawn) >= 4, "apparitions")
			for _, d in house:GetDescendants() do
				if d:HasTag(MapTags.KeySpot) or d:HasTag(MapTags.MortalSpawn) or d:HasTag(MapTags.Exit) then
					T.expectEqual(d.CanCollide, false, d.Name)
					T.expectEqual(d.Transparency, 1, d.Name)
					-- détectables par contact et requête spatiale (#5, #7)
					T.expectEqual(d.CanTouch, true, d.Name)
					T.expectEqual(d.CanQuery, true, d.Name)
				end
				if d:HasTag(MapTags.Room) then
					-- un volume de pièce ne doit pas arrêter le faisceau d'une lampe torche
					T.expectEqual(d.CanQuery, false, d.Name)
				end
			end
		end)

		T.it("construit le terrain : clôtures, portail tagué et décor hors carte dans son dossier", function()
			T.expectEqual(countTagged(house, MapTags.Gate), 1, "portail")
			T.expect(house:FindFirstChild("Garden"), "dossier Garden")
			local scenery = house:FindFirstChild(HouseBuilder.SCENERY_FOLDER)
			T.expect(scenery and #scenery:GetChildren() > 0, "décor hors carte")
			local fences = 0
			for _, d in house:GetDescendants() do
				if d:IsA("BasePart") and string.find(d.Name, "Fence", 1, true) then
					fences += 1
					T.expectEqual(d.CanCollide, true, d.Name)
				end
			end
			T.expect(fences > 0, "clôtures")
			local boundaries = 0
			for _, d in house[HouseBuilder.BOUNDS_FOLDER]:GetChildren() do
				if string.find(d.Name, "Boundary", 1, true) == 1 then
					boundaries += 1
					-- Limite invisible : arrête les joueurs, jamais un rayon
					T.expectEqual(d.Transparency, 1, d.Name)
					T.expectEqual(d.CanCollide, true, d.Name)
					T.expectEqual(d.CanQuery, false, d.Name)
				end
			end
			T.expectEqual(boundaries, 4, "limite du terrain")
		end)

		T.it("remplace une maison déjà construite", function()
			HouseBuilder.build(world)
			local houses = 0
			for _, child in world:GetChildren() do
				if child.Name == HouseBuilder.MODEL_NAME then
					houses += 1
				end
			end
			T.expectEqual(houses, 1)
		end)
	end)

	T.describe("NightAmbience.apply", function()
		T.it("règle Lighting, le brouillard et la palette sans doublon", function()
			local lighting = Instance.new("Lighting")
			NightAmbience.apply(lighting)
			NightAmbience.apply(lighting)
			T.expectEqual(lighting.ClockTime, 0)
			local atmospheres, corrections = 0, 0
			for _, child in lighting:GetChildren() do
				if child:IsA("Atmosphere") then
					atmospheres += 1
					T.expect(child.Density > 0, "brouillard")
				elseif child:IsA("ColorCorrectionEffect") then
					corrections += 1
					T.expect(child.Saturation < 0, "palette désaturée")
				end
			end
			T.expectEqual(atmospheres, 1)
			T.expectEqual(corrections, 1)
			local ambient = lighting.Ambient
			local level = (ambient.R + ambient.G + ambient.B) / 3
			-- Bornes larges autour de la valeur réglée en jeu (≈ 0,26) : ni noir complet, ni éclairage de jour
			T.expect(level > 0.15 and level < 0.35, "ambiance ni noire ni claire")
		end)
	end)
end
