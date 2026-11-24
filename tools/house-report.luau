-- Rapport de la carte (lune run tools/house-report) : erreurs de la description, surfaces par niveau, passages et
-- boucles par niveau, couverture d'éclairage par pièce. Sert aux mesures des comptes rendus (docs/design.md
-- « Première carte ») ; ne remplace pas la vérification en jeu (traversées, PathfindingService).
local roblox = require("@lune/roblox")
local Loader = require("../tests/lib/Loader")

local Vector3 = roblox.Vector3
local Instance = roblox.Instance

local loader = Loader.new()
local HouseLayout = loader:require("src/shared/HouseLayout")
local HouseGeometry = loader:require("src/shared/HouseGeometry")
local HouseBuilder = loader:require("src/server/HouseBuilder")
local Illumination = loader:require("src/shared/Illumination")

local errors = HouseGeometry.validate(HouseLayout)
if #errors > 0 then
	print("ERREURS (" .. #errors .. ")")
	for _, e in errors do
		print("  " .. e)
	end
	return
end
print("Description valide")

-- Surfaces (bords extérieurs des pièces ; une cage d'escalier compte à chaque niveau qu'elle traverse)
local byLevel, outdoor, indoorCount, outdoorCount = {}, 0, 0, 0
for _, room in HouseLayout.rooms do
	local area = (room.x1 - room.x0) * (room.z1 - room.z0)
	if room.outdoor then
		outdoor += area
		outdoorCount += 1
	else
		indoorCount += 1
		for level = room.level, room.level + (room.levels or 1) - 1 do
			byLevel[level] = (byLevel[level] or 0) + area
		end
	end
end
local indoor = 0
for level = -1, 1 do
	indoor += byLevel[level] or 0
	print(string.format("Niveau %d : %d studs²", level, byLevel[level] or 0))
end
print(string.format("Intérieur : %d studs² (%d pièces)", indoor, indoorCount))
print(string.format("Extérieur : %d studs² (%d zones)", outdoor, outdoorCount))
print(string.format("Total jouable : %d studs²", indoor + outdoor))

-- Graphe par niveau : nombre de cycles indépendants (passages - pièces + composantes) et culs-de-sac
local graph = HouseGeometry.neighbors(HouseLayout)
local byId = HouseGeometry.roomsById(HouseLayout)
for level = -1, 1 do
	local rooms, edges = {}, 0
	for _, room in HouseLayout.rooms do
		if HouseGeometry.spansLevel(room, level) then
			rooms[room.id] = true
		end
	end
	local count, deadEnds = 0, {}
	for id in rooms do
		count += 1
		local degree = 0
		for _, other in graph[id] do
			if rooms[other] then
				edges += 1
			end
		end
		-- Cul-de-sac : une seule voisine sur toute la carte (une cage d'escalier mène à l'autre niveau)
		local distinct = {}
		for _, other in graph[id] do
			if not distinct[other] then
				distinct[other] = true
				degree += 1
			end
		end
		if degree <= 1 then
			table.insert(deadEnds, id)
		end
	end
	edges //= 2
	-- Composantes connexes du niveau
	local seen, components = {}, 0
	for id in rooms do
		if not seen[id] then
			components += 1
			local stack = { id }
			seen[id] = true
			while #stack > 0 do
				local current = table.remove(stack)
				for _, other in graph[current] do
					if rooms[other] and not seen[other] then
						seen[other] = true
						table.insert(stack, other)
					end
				end
			end
		end
	end
	table.sort(deadEnds)
	print(
		string.format(
			"Niveau %d : %d pièces, %d passages, %d boucles indépendantes, culs-de-sac : %s",
			level,
			count,
			edges,
			edges - count + components,
			if #deadEnds > 0 then table.concat(deadEnds, ", ") else "aucun"
		)
	)
end
local stairs = {}
for _, room in HouseLayout.rooms do
	if room.stairs then
		table.insert(stairs, string.format("%s (%d↔%d)", room.id, room.level, room.level + 1))
	end
end
print("Accès entre niveaux : " .. table.concat(stairs, ", "))

-- Couverture d'éclairage à hauteur de personnage (grille de 1 stud, règle Shared.Illumination)
local house = HouseBuilder.build(Instance.new("Folder"), HouseLayout)
local model = Illumination.fromHouse(house)
local report = {}
for _, room in HouseLayout.rooms do
	if not room.lit then
		continue
	end
	local inner = HouseGeometry.interior(HouseLayout, room)
	local lit, total = 0, 0
	local y = HouseGeometry.floorY(HouseLayout, room.level) + 3
	for x = inner.x0 + 0.5, inner.x1 - 0.5 do
		for z = inner.z0 + 0.5, inner.z1 - 0.5 do
			total += 1
			if model:isLit(Vector3.new(x, y, z)) then
				lit += 1
			end
		end
	end
	table.insert(report, string.format("%s %d%%", byId[room.id].id, math.floor(lit / total * 100 + 0.5)))
end
print("Couverture des pièces éclairées : " .. table.concat(report, ", "))
