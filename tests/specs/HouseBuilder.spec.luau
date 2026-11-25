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

		T.it("habille la maison sans changer ce que touchent les joueurs et les rayons (#26)", function()
			-- Meuble habillé : un modèle, volume invisible tagué en PrimaryPart, blocs visibles qui arrêtent tout
			local shelf = house.Living.LivingBookcase
			T.expect(shelf:IsA("Model"), "meuble habillé en Model")
			local box = shelf.PrimaryPart
			T.expect(box ~= nil and box.Name == "LivingBookcase", "volume du meuble en PrimaryPart")
			T.expect(box:HasTag(MapTags.TrapCandidate), "tags de piège sur le volume")
			T.expectEqual(box.Transparency, 1)
			T.expectEqual(box.CanCollide, false)
			T.expectEqual(box.CanQuery, false)
			T.expectEqual(box.CanTouch, true)
			local structure = { Back = true, SideLeft = true, SideRight = true, Top = true }
			local visible, books = 0, 0
			for _, part in shelf:GetChildren() do
				if part == box then
					continue
				elseif structure[part.Name] or string.find(part.Name, "^Shelf%d$") then
					visible += 1
					T.expect(part.Transparency < 1 and part.CanCollide and part.CanQuery, part.Name)
				else
					-- Livres et bibelots (#38) : visibles, mais ni collision, ni rayon, ni ombre
					books += if string.find(part.Name, "^Book") then 1 else 0
					T.expect(part.Transparency < 1, part.Name)
					T.expect(not part.CanCollide and not part.CanQuery and not part.CastShadow, part.Name)
				end
			end
			T.expect(visible >= 6, "bibliothèque en plusieurs blocs")
			T.expect(books >= 40, books .. " livres seulement dans la bibliothèque du salon")
			-- Le disjoncteur reste un bloc unique, visible et visé par les rayons (LightService)
			local breaker = house.Cave.Breaker
			T.expect(breaker:IsA("BasePart") and breaker:HasTag(MapTags.Breaker), "disjoncteur")
			T.expect(breaker.CanQuery and breaker.Transparency == 0, "disjoncteur visible")
			T.expectEqual(breaker.Material.Name, "Metal")
			-- Habillage décoratif : abat-jour, fenêtres, tapis n'arrêtent ni joueur, ni rayon, ni lumière
			local windows, fixtures = 0, 0
			for _, d in house:GetDescendants() do
				if d:IsA("BasePart") and (string.find(d.Name, "Window", 1, true) or d.Name == "LivingRug") then
					if string.find(d.Name, "Window", 1, true) then
						windows += 1
					end
					T.expect(not d.CanCollide and not d.CanQuery and not d.CastShadow, d.Name)
				elseif d:IsA("BasePart") and string.find(d.Name, "^KitchenLampShade") then
					fixtures += 1
					T.expect(not d.CanCollide and not d.CanQuery and not d.CastShadow, d.Name)
				end
			end
			T.expect(windows >= 20, "fenêtres de façade")
			T.expectEqual(fixtures, 4, "abat-jour du plafonnier de la cuisine")
			-- Matériaux : parquet au salon, carrelage en cuisine, façade crépie, haie
			T.expectEqual(house.Living.LivingFloor.Material.Name, "WoodPlanks")
			T.expectEqual(house.Kitchen.KitchenFloor.Material.Name, "CeramicTiles")
			T.expectEqual(house.Living.LivingWallSouth1Facade.Material.Name, "Plaster")
			T.expectEqual(house.Garden.GardenFenceNorth1.Material.Name, "LeafyGrass")
		end)

		-- Cette méthode permet de savoir si un axe de bloc suit un axe du monde lorsque l'on compte les objets tournés
		-- (un quart de tour, celui d'un cylindre debout, ne compte pas).
		local function aligned(v): boolean
			for _, c in { v.X, v.Y, v.Z } do
				if math.abs(c) > 1e-4 and math.abs(math.abs(c) - 1) > 1e-4 then
					return false
				end
			end
			return true
		end

		T.it("pose les petits objets sans gêner joueurs, rayons ni lumière, tournés et arrondis (#38)", function()
			local table_ = house.Dining.DiningTableSetting
			T.expect(table_:IsA("Model"), "garniture en Model")
			local clutter, round, turned = 0, 0, 0
			for _, room in house:GetChildren() do
				for _, model in room:GetChildren() do
					if not model:IsA("Model") or model:FindFirstChild(model.Name) then
						continue -- meuble habillé ou voiture : son volume porte son nom
					end
					for _, part in model:GetChildren() do
						if part:IsA("BasePart") and model.Name ~= "EscapeCar" then
							clutter += 1
							T.expect(not part.CanCollide and not part.CanQuery and not part.CanTouch, part.Name)
							T.expect(not part.CastShadow and part.Transparency < 1, part.Name)
							round += if part.Shape.Name ~= "Block" then 1 else 0
							turned += if aligned(part.CFrame.RightVector) and aligned(part.CFrame.UpVector)
								then 0
								else 1
						end
					end
				end
			end
			T.expect(clutter >= 500, clutter .. " petits objets seulement")
			T.expect(round >= 50, "objets ronds (assiettes, bouteilles, pots)")
			T.expect(turned >= 50, "objets tournés (livres penchés, papiers de travers)")
			-- Bouteilles de la cave à vin : cylindres couchés, goulot vers la pièce
			local bottles = 0
			for _, part in house.WineCellar.WineRackMiddle:GetChildren() do
				if string.find(part.Name, "^Bottle%d*$") then
					bottles += 1
					T.expectEqual(part.Shape.Name, "Cylinder", part.Name)
				end
			end
			T.expect(bottles >= 40, bottles .. " bouteilles seulement")
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
