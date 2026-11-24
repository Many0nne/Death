-- Construit la maison en blocs gris à partir de la description partagée (Shared.HouseLayout → Shared.HouseGeometry).
-- Tout est généré au démarrage : rien de la maison n'est gardé dans Studio. Tags et attributs : Shared.MapTags.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HouseGeometry = require(ReplicatedStorage.Shared.HouseGeometry)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local NightLighting = require(ReplicatedStorage.Shared.NightLighting)

local HouseBuilder = {}

HouseBuilder.MODEL_NAME = "House"

-- Gris du prototype par type de bloc : sols plus sombres que les murs, marches claires pour lire l'escalier dans
-- la pénombre.
local COLORS = {
	Floor = Color3.fromRGB(92, 92, 96),
	Ceiling = Color3.fromRGB(96, 96, 100),
	Wall = Color3.fromRGB(150, 150, 154),
	Step = Color3.fromRGB(140, 140, 144),
	Landing = Color3.fromRGB(140, 140, 144),
	Partition = Color3.fromRGB(135, 135, 139),
	Prop = Color3.fromRGB(104, 104, 108),
	DoorLeaf = Color3.fromRGB(62, 62, 66),
	Car = Color3.fromRGB(88, 88, 94),
}

-- Blocs invisibles, avec leurs collisions : un volume de pièce ne gêne ni le joueur, ni le contact, ni les rayons
-- (faisceau de lampe torche) ; un ancrage reste détectable (Touched, GetPartsInPart) sans bloquer le passage ; le
-- SpawnLocation (dalle de 0,2 stud) porte le personnage.
local INVISIBLE = {
	Zone = { CanCollide = false, CanTouch = false, CanQuery = false },
	Anchor = { CanCollide = false, CanTouch = true, CanQuery = true },
	Spawn = { CanCollide = true, CanTouch = true, CanQuery = false },
}

-- Cette méthode permet de poser tags et attributs d'un bloc calculé sur son instance lorsque la suite du jeu doit le
-- retrouver par CollectionService.
local function mark(instance: Instance, tags: { string }, attributes: { [string]: any })
	for _, tag in tags do
		instance:AddTag(tag)
	end
	for name, value in attributes do
		instance:SetAttribute(name, value)
	end
end

-- Cette méthode permet d'instancier un bloc calculé (Part, lampe, ancrage ou SpawnLocation) lorsque la maison est
-- construite.
local function makePart(p): BasePart
	local part: BasePart
	if p.kind == "Spawn" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Enabled = true
		part = spawn
	else
		part = Instance.new("Part")
	end
	part.Name = p.name
	part.Anchored = true
	part.Size = p.size
	part.CFrame = CFrame.new(p.center)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = COLORS[p.kind] or COLORS.Prop
	local invisible = INVISIBLE[p.kind]
	if invisible then
		part.Transparency = 1
		part.CastShadow = false
		part.CanCollide = invisible.CanCollide
		part.CanTouch = invisible.CanTouch
		part.CanQuery = invisible.CanQuery
	end
	if p.kind == "Lamp" then
		part.Material = Enum.Material.Neon
		part.Color = NightLighting.lampColor
		part.CanCollide = false
		part.CastShadow = false
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Range = p.light.range
		light.Brightness = p.light.brightness
		light.Color = NightLighting.lampColor
		light.Shadows = true
		light.Parent = part
	end
	mark(part, p.tags, p.attributes)
	return part
end

-- Pièces du modèle de place Studio qui gênent la maison : le Baseplate remplirait la cave (sol à y = 0, 16 studs
-- d'épaisseur) et le SpawnLocation d'origine ferait apparaître dans le mur de la cuisine.
local TEMPLATE_PARTS = { Baseplate = "BasePart", SpawnLocation = "SpawnLocation" }

-- Cette méthode permet de retirer les pièces du modèle de place lorsque la maison est construite à leur place.
local function removeTemplateParts(parent: Instance)
	for name, className in TEMPLATE_PARTS do
		local part = parent:FindFirstChild(name)
		if part and part:IsA(className) then
			part:Destroy()
		end
	end
end

-- Cette méthode permet de construire la maison sous parent (Workspace en jeu) lorsque le serveur démarre ; une maison
-- déjà présente est remplacée. Renvoie le modèle « House » : un dossier par pièce, la voiture en Model.
function HouseBuilder.build(parent: Instance, layout: any?): Model
	local description = layout or HouseLayout
	local errors, plan = HouseGeometry.validate(description)
	if #errors > 0 then
		error("Description de la maison invalide :\n" .. table.concat(errors, "\n"))
	end
	local old = parent:FindFirstChild(HouseBuilder.MODEL_NAME)
	if old then
		old:Destroy()
	end
	removeTemplateParts(parent)

	local house = Instance.new("Model")
	house.Name = HouseBuilder.MODEL_NAME
	local folders = {}
	for _, room in description.rooms do
		local folder = Instance.new("Folder")
		folder.Name = room.id
		folder.Parent = house
		folders[room.id] = folder
	end
	local models = {}
	for id, group in plan.groups do
		local model = Instance.new("Model")
		model.Name = id
		mark(model, group.tags, group.attributes)
		model.Parent = folders[group.room]
		models[id] = model
	end
	for _, p in plan.pieces do
		local part = makePart(p)
		if p.group then
			part.Parent = models[p.group]
			if p.name == plan.groups[p.group].primary then
				models[p.group].PrimaryPart = part
			end
		else
			part.Parent = folders[p.room]
		end
	end
	house.Parent = parent
	return house
end

return HouseBuilder
