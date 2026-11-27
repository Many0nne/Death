-- remount.luau (#79) : remontage automatique d'un modèle importé (GLB) sur son modèle Studio, d'après le manifeste.
-- Ne s'exécute pas tel quel : `lune run tools/rbxm/build-remount.luau -- <modèle> <import> <sortie.luau>` y injecte
-- le manifeste (tools/models/<modèle>.manifest.json) et les mesures (<modèle>.measured.json), puis on exécute la
-- sortie dans Studio (MCP `execute_luau`, mode Edit). Procédure : docs/assets.md.
--
-- Idempotent : relancé, il donne le même résultat. Il réapplique ce que l'import GLB perd ou ne crée pas :
-- - pièces : si le modèle importé (IMPORT_NAME, dans workspace ou ReplicatedStorage) contient une MeshPart du nom
--   d'une pièce, elle remplace l'ancienne, placée d'après son centre mesuré dans le repère de la racine (l'import
--   tourne le modèle de 180° autour de Y) ; os de la pièce skinnée déplacés sous la racine, à leur place de liaison ;
-- - couleurs, matériaux, SurfaceAppearance (table « surface » du manifeste : retirée si la table est vide) ;
-- - pièces sans masse, sans collision, contact ni requête, soudées à la racine (une WeldConstraint chacune) ;
-- - pièces ajoutées dans Studio (HemSmokeArea), fumées (HemSmoke, HoodShadow), réglages du Humanoid.
-- Imprime un rapport JSON (préfixe « REMOUNT ») ; l'import est détruit à la fin.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MANIFEST = HttpService:JSONDecode([==[@MANIFEST@]==])
local MEASURED = HttpService:JSONDecode([==[@MEASURED@]==])
local IMPORT_NAME = "@IMPORT@"

local report = { replaced = {}, kept = {}, missing = {}, surfaces = {}, warnings = {} }

local characters = ReplicatedStorage:FindFirstChild("Characters")
local model = characters and characters:FindFirstChild(MANIFEST.model)
assert(model and model:IsA("Model"), "ReplicatedStorage.Characters." .. MANIFEST.model .. " introuvable")
local root = model:FindFirstChild(MANIFEST.studio.weldTo)
assert(root and root:IsA("BasePart"), MANIFEST.studio.weldTo .. " introuvable")
local humanoid = model:FindFirstChildOfClass("Humanoid")
assert(humanoid, "Humanoid introuvable")

local import = nil
if IMPORT_NAME ~= "" then
	import = workspace:FindFirstChild(IMPORT_NAME) or ReplicatedStorage:FindFirstChild(IMPORT_NAME)
	assert(import, "modèle importé « " .. IMPORT_NAME .. " » introuvable dans workspace ni ReplicatedStorage")
end

-- l'import tourne le modèle de 180° autour de Y : chaque pièce a cette orientation dans le repère de la racine
local TURN = CFrame.Angles(0, math.pi, 0)

-- Cette méthode permet de trouver la première pièce (BasePart) d'un nom donné parmi les descendants.
local function findPart(container: Instance, name: string): BasePart?
	for _, d in container:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

-- Cette méthode permet de trouver (ou créer) le groupe (Model) d'une pièce sous le modèle.
local function group(name: string): Model
	local g = model:FindFirstChild(name)
	if not g then
		g = Instance.new("Model")
		g.Name = name
		g.Parent = model
	end
	return g :: Model
end

-- Cette méthode permet de donner la place d'une pièce d'après son centre mesuré (repère Roblox de la racine).
local function placeOf(center: { number }): CFrame
	return root.CFrame * CFrame.new(center[1], center[2], center[3]) * TURN
end

-- Cette méthode permet de retirer les soudures d'une pièce lorsqu'on va la déplacer (une WeldConstraint entraînerait
-- la racine avec elle).
local function unweld(part: BasePart)
	for _, c in part:GetChildren() do
		if c:IsA("WeldConstraint") or c:IsA("Weld") then
			c:Destroy()
		end
	end
end

-- Cette méthode permet de garder exactement une WeldConstraint entre la racine et la pièce.
local function weld(part: BasePart)
	local found = nil
	for _, c in part:GetChildren() do
		if c:IsA("WeldConstraint") and c.Part0 == root and c.Part1 == part and not found then
			found = c
		elseif c:IsA("WeldConstraint") or c:IsA("Weld") then
			c:Destroy()
		end
	end
	if not found then
		found = Instance.new("WeldConstraint")
		found.Part0 = root
		found.Part1 = part
		found.Parent = part
	end
	found.Name = "WeldConstraint"
end

-- Cette méthode permet de poser les réglages physiques communes aux pièces portées (glissent avec la racine).
local function carried(part: BasePart, castShadow: boolean)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = castShadow
end

-- Cette méthode permet de convertir une valeur du manifeste (JSON) en valeur Roblox typée.
local function decode(value: any): any
	if type(value) ~= "table" then
		return value
	end
	if value.NumberRange then
		return NumberRange.new(value.NumberRange[1], value.NumberRange[2])
	elseif value.NumberSequence then
		local keys = {}
		for _, k in value.NumberSequence do
			table.insert(keys, NumberSequenceKeypoint.new(k[1], k[2], k[3] or 0))
		end
		return NumberSequence.new(keys)
	elseif value.ColorSequence then
		local keys = {}
		for _, k in value.ColorSequence do
			table.insert(keys, ColorSequenceKeypoint.new(k[1], Color3.fromRGB(k[2][1], k[2][2], k[2][3])))
		end
		return ColorSequence.new(keys)
	elseif value.Vector3 then
		return Vector3.new(value.Vector3[1], value.Vector3[2], value.Vector3[3])
	elseif value.Vector2 then
		return Vector2.new(value.Vector2[1], value.Vector2[2])
	elseif value.Enum then
		return (Enum :: any)[value.Enum[1]][value.Enum[2]]
	end
	error("valeur du manifeste non reconnue : " .. HttpService:JSONEncode(value))
end

-- Cette méthode permet de remplacer les os de la pièce skinnée par ceux de l'import, sous la racine, à la même place
-- relative à la nouvelle pièce que dans l'import (sinon la peau se déforme).
local function moveBones(fresh: BasePart, placed: BasePart)
	local rootName = MANIFEST.bones.root
	local importRoot = nil
	for _, d in import:GetDescendants() do
		if d:IsA("Bone") and d.Name == rootName then
			importRoot = d
			break
		end
	end
	if not importRoot then
		table.insert(report.warnings, "import sans os « " .. rootName .. " » : os gardés")
		return
	end
	local toTarget = placed.CFrame * fresh.CFrame:Inverse()
	local world = toTarget * importRoot.WorldCFrame
	local bones = importRoot:Clone()
	for _, old in root:GetChildren() do
		if old:IsA("Bone") and old.Name == rootName then
			old:Destroy()
		end
	end
	bones.CFrame = root.CFrame:ToObjectSpace(world)
	bones.Parent = root
	for _, d in placed:GetDescendants() do
		if d:IsA("Bone") then
			d:Destroy()
		end
	end
end

-- import : écart entre l'origine déduite de chaque pièce et celle de la première (vérifie le repère des centres)
local origin = nil
local originDrift = 0

for name, spec in MANIFEST.parts do
	local measured = MEASURED.parts[name]
	local old = findPart(model, name)
	local fresh = import and findPart(import, name)
	local part = old
	if fresh and measured then
		local o = fresh.CFrame
			* (CFrame.new(measured.center[1], measured.center[2], measured.center[3]) * TURN):Inverse()
		if origin then
			originDrift = math.max(originDrift, (o.Position - origin.Position).Magnitude)
		else
			origin = o
		end
		local placed = fresh:Clone()
		for _, c in placed:GetChildren() do
			if not c:IsA("Bone") then
				c:Destroy()
			end
		end
		placed.CFrame = placeOf(measured.center)
		placed.Name = name
		placed.Parent = group(spec.group)
		if spec.skinned then
			moveBones(fresh, placed)
		end
		if old then
			old:Destroy()
		end
		part = placed
		table.insert(report.replaced, name)
	else
		if fresh then
			table.insert(
				report.warnings,
				name .. " : dans l'import mais pas dans les mesures (pipeline.py en échec ?)"
			)
		end
		if part then
			table.insert(report.kept, name)
		end
	end
	if not part then
		table.insert(report.missing, name)
		continue
	end
	if part.Parent ~= group(spec.group) then
		part.Parent = group(spec.group)
	end
	carried(part, spec.castShadow)
	part.Material = (Enum.Material :: any)[spec.material]
	part.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	weld(part)
	local sa = part:FindFirstChildOfClass("SurfaceAppearance")
	if spec.surface and next(spec.surface) then
		if not sa then
			sa = Instance.new("SurfaceAppearance")
			sa.Parent = part
		end
		sa.Name = "SurfaceAppearance"
		for prop, id in spec.surface do
			(sa :: any)[prop] = id
		end
		report.surfaces[name] = spec.surface
	elseif sa then
		sa:Destroy()
	end
end

for name, spec in MANIFEST.studio.extraParts do
	local part = findPart(model, name)
	if not part then
		part = Instance.new("Part")
		part.Name = name
	end
	assert(part)
	unweld(part)
	part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	part.Transparency = spec.transparency
	part.CFrame = root.CFrame * CFrame.new(spec.offset[1], spec.offset[2], spec.offset[3])
	part.Parent = group(spec.group)
	carried(part, spec.castShadow)
	weld(part)
end

for name, spec in MANIFEST.studio.emitters do
	local parent = findPart(model, spec.parent)
	if not parent then
		table.insert(report.warnings, "fumée " .. name .. " : pièce " .. spec.parent .. " absente")
		continue
	end
	-- une seule fumée de ce nom dans le modèle : celle qui serait restée ailleurs est déplacée, les doublons retirés
	local emitter = nil
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == name then
			if emitter then
				d:Destroy()
			else
				emitter = d
			end
		end
	end
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
	end
	emitter.Parent = parent
	for prop, value in spec.props do
		(emitter :: any)[prop] = decode(value)
	end
end

for prop, value in MANIFEST.studio.humanoid do
	(humanoid :: any)[prop] = value
end

-- contrôle : une pièce par nom, os de la cape sous la racine
local bones = 0
for _, d in root:GetDescendants() do
	if d:IsA("Bone") then
		bones += 1
	end
end
report.bones = bones
report.originDrift = math.round(originDrift * 1000) / 1000
local duplicates = {}
for name in MANIFEST.parts do
	local n = 0
	for _, d in model:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			n += 1
		end
	end
	if n ~= 1 then
		duplicates[name] = n
	end
end
report.duplicates = duplicates
if import then
	import:Destroy()
end
print("REMOUNT " .. HttpService:JSONEncode(report))
