-- remount.luau (#79) : remontage automatique d'un modèle importé (GLB) sur son modèle Studio, d'après le manifeste.
-- Ne s'exécute pas tel quel : `lune run tools/rbxm/build-remount.luau -- <modèle> <import> <sortie.luau>` y injecte
-- le manifeste (tools/models/<modèle>.manifest.json) et les mesures (<modèle>.measured.json), puis on exécute la
-- sortie dans Studio (MCP `execute_luau`, mode Edit). Procédure : docs/assets.md.
--
-- Idempotent : relancé, il donne le même résultat. Il réapplique ce que l'import GLB perd ou ne crée pas :
-- - pièces : si le modèle importé (IMPORT_NAME, dans workspace ou ReplicatedStorage) contient une MeshPart du nom
--   d'une pièce, elle remplace l'ancienne, placée d'après son centre mesuré dans le repère de la racine (l'import
--   tourne le modèle de 180° autour de Y) ; os de la robe déplacés sous la racine, à leur place de liaison ;
-- - pièces d'un ancien modèle (studio.remove) retirées ;
-- - rig R15 (#81) : articulations des bras (épaule, coude, poignet) calées sur les os du corps mesurés
--   (bones.body.joints), puis os du corps rangés sous la pièce du rig qui les porte (bones.body.attach) : animer le
--   rig anime les bras skinnés ;
-- - couleurs, matériaux, SurfaceAppearance (table « surface » du manifeste : retirée si la table est vide) ;
-- - pièces sans masse, sans collision, contact ni requête, soudées à la racine ou à la pièce du rig de leur groupe
--   (studio.groupWeld : la faux suit la main droite) ;
-- - pièces ajoutées dans Studio (HemSmokeArea), fumées (HemSmoke), réglages du Humanoid.
-- Imprime un rapport JSON (préfixe « REMOUNT ») ; l'import est détruit à la fin, sauf échec (il reste pour relancer).
-- Les centres sont contrôlés avant toute modification : un import incohérent ne touche pas au modèle.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MANIFEST = HttpService:JSONDecode([==[@MANIFEST@]==])
local MEASURED = HttpService:JSONDecode([==[@MEASURED@]==])
local IMPORT_NAME = "@IMPORT@"

local report =
	{ replaced = {}, kept = {}, missing = {}, surfaces = {}, moved = {}, warnings = {}, removed = {}, joints = {} }

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
	assert(not g or g:IsA("Model"), model:GetFullName() .. "." .. name .. " n'est pas un Model")
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

-- Cette méthode permet de garder exactement une WeldConstraint entre la pièce porteuse (racine par défaut) et la pièce.
local function weld(part: BasePart, target: BasePart?)
	local anchor = target or root
	local found = nil
	for _, c in part:GetChildren() do
		if c:IsA("WeldConstraint") and c.Part0 == anchor and c.Part1 == part and not found then
			found = c
		elseif c:IsA("WeldConstraint") or c:IsA("Weld") then
			c:Destroy()
		end
	end
	if not found then
		found = Instance.new("WeldConstraint")
		found.Part0 = anchor
		found.Part1 = part
		found.Parent = part
	end
	found.Name = "WeldConstraint"
end

-- Cette méthode permet de trouver la pièce porteuse d'un groupe (studio.groupWeld), ou nil pour la racine.
local function weldTarget(groupName: string): BasePart?
	local name = MANIFEST.studio.groupWeld and MANIFEST.studio.groupWeld[groupName]
	if not name then
		return nil
	end
	local target = model:FindFirstChild(name)
	assert(target and target:IsA("BasePart"), "pièce porteuse « " .. name .. " » introuvable")
	return target :: BasePart
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

-- Cette méthode permet de trouver la racine d'un jeu d'os (Bone de ce nom) dans l'import.
local function importBone(name: string): Bone?
	for _, d in import:GetDescendants() do
		if d:IsA("Bone") and d.Name == name then
			return d
		end
	end
	return nil
end

-- Cette méthode permet de retirer tous les os d'une pièce posée (ils sont rangés ailleurs : jamais deux jeux d'os du
-- même nom, la peau se lierait au hasard).
local function stripBones(placed: BasePart)
	for _, d in placed:GetDescendants() do
		if d:IsA("Bone") then
			d:Destroy()
		end
	end
end

-- Cette méthode permet de remplacer les os de la robe par ceux de l'import, sous la racine, à la même place relative
-- aux pièces que dans l'import (sinon la peau se déforme) ; `toTarget` passe du repère de l'import à celui du modèle.
local function moveCloakBones(toTarget: CFrame)
	local rootName = MANIFEST.bones.root
	local importRoot = importBone(rootName)
	if not importRoot then
		table.insert(
			report.warnings,
			"import sans os « " .. rootName .. " » : anciens os gardés, peau peut-être faussée"
		)
		return
	end
	local world = toTarget * importRoot.WorldCFrame
	local bones = importRoot:Clone()
	for _, old in root:GetChildren() do
		if old:IsA("Bone") and old.Name == rootName then
			old:Destroy()
		end
	end
	bones.CFrame = root.CFrame:ToObjectSpace(world)
	bones.Parent = root
end

-- Cette méthode permet de vérifier, avant toute modification, qu'une articulation du rig et son os mesuré existent ;
-- renvoie le Motor6D (Part0 et Part1 posés) et l'os, ou une erreur.
local function jointOf(motorName: string, boneName: string): (Motor6D, any)
	local motor = model:FindFirstChild(motorName, true)
	local bone = MEASURED.bodyBones and MEASURED.bodyBones[boneName]
	assert(motor and motor:IsA("Motor6D"), "articulation " .. motorName .. " introuvable : rien n'est modifié")
	assert(bone, "os mesuré " .. boneName .. " absent : rien n'est modifié")
	assert(motor.Part0 and motor.Part1, "articulation " .. motorName .. " sans Part0 ou Part1 : rien n'est modifié")
	return motor :: Motor6D, bone
end

-- Cette méthode permet de caler une articulation du rig sur son os : Part1 centrée sur l'os, C0, C1 et RigAttachment
-- suivent ; l'articulation est détachée le temps du déplacement (sinon toute la chaîne suivrait).
local function fitJoint(motorName: string, boneName: string)
	local motor, bone = jointOf(motorName, boneName)
	local part0, part1 = motor.Part0 :: BasePart, motor.Part1 :: BasePart
	local rot = root.CFrame.Rotation
	local head = root.CFrame:PointToWorldSpace(Vector3.new(bone.head[1], bone.head[2], bone.head[3]))
	local tail = root.CFrame:PointToWorldSpace(Vector3.new(bone.tail[1], bone.tail[2], bone.tail[3]))
	local joint = CFrame.new(head) * rot
	motor.Part1 = nil
	part1.CFrame = CFrame.new((head + tail) / 2) * rot
	motor.C0 = part0.CFrame:ToObjectSpace(joint)
	motor.C1 = part1.CFrame:ToObjectSpace(joint)
	motor.Part1 = part1
	for _, pair in { { part0, motor.C0 }, { part1, motor.C1 } } do
		local att = pair[1]:FindFirstChild(motorName .. "RigAttachment")
		if att and att:IsA("Attachment") then
			att.CFrame = pair[2]
		end
	end
	local rel = root.CFrame:PointToObjectSpace(head)
	report.joints[motorName] =
		{ math.round(rel.X * 100) / 100, math.round(rel.Y * 100) / 100, math.round(rel.Z * 100) / 100 }
end

-- Cette méthode permet de ranger les os du corps de l'import sous les pièces du rig R15 (bones.body.attach), à leur
-- place de liaison : un os rangé garde ses enfants, sauf ceux qui sont rangés ailleurs à leur tour.
local function attachBodyBones(toTarget: CFrame)
	local body = MANIFEST.bones.body
	local importRoot = importBone(body.root)
	if not importRoot then
		table.insert(report.warnings, "import sans os « " .. body.root .. " » : os du corps non rangés")
		return
	end
	-- place monde de chaque os de l'import, avant tout déplacement (os du corps : noms uniques, appariés par nom)
	local worldByName = {}
	for _, d in importRoot:GetDescendants() do
		if d:IsA("Bone") then
			worldByName[d.Name] = toTarget * d.WorldCFrame
		end
	end
	worldByName[importRoot.Name] = toTarget * importRoot.WorldCFrame
	local clone = importRoot:Clone()
	local copies = { clone }
	for _, d in clone:GetDescendants() do
		table.insert(copies, d)
	end
	-- anciens os du corps (exécution précédente) retirés
	local names = {}
	for _, n in MEASURED.bodyBoneNames or {} do
		names[n] = true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") and names[d.Name] and not d:IsDescendantOf(import) then
			d:Destroy()
		end
	end
	-- parents d'abord (la racine puis les os rangés, dans l'ordre de l'arbre)
	for _, b in copies do
		local partName = b:IsA("Bone") and body.attach[b.Name]
		if partName then
			local part = model:FindFirstChild(partName)
			if not part or not part:IsA("BasePart") then
				table.insert(report.warnings, "os " .. b.Name .. " : pièce " .. partName .. " absente")
				continue
			end
			b.Parent = part
			b.CFrame = part.CFrame:ToObjectSpace(worldByName[b.Name])
		end
	end
	if clone.Parent == nil then
		clone:Destroy()
	end
end

-- avant toute modification : l'origine déduite de chaque pièce importée doit être la même (repère des centres)
local origin = nil
local originDrift = 0
if import then
	for name in MANIFEST.parts do
		local fresh = findPart(import, name)
		local measured = MEASURED.parts[name]
		if fresh and measured then
			local c = measured.center
			local o = fresh.CFrame * (CFrame.new(c[1], c[2], c[3]) * TURN):Inverse()
			if origin then
				originDrift = math.max(originDrift, (o.Position - origin.Position).Magnitude)
			else
				origin = o
			end
		end
	end
	report.originDrift = math.round(originDrift * 1000) / 1000
	if originDrift > 0.01 then
		error("centres incohérents avec l'import (écart " .. report.originDrift .. " stud) : rien n'est modifié")
	end
end

-- Cette méthode permet de lister les pièces skinnées de chaque jeu d'os (robe, corps) lorsqu'on décide de remplacer
-- leurs os.
local function skinnedSets(): { [string]: { string } }
	local body = MANIFEST.bones.body
	local sets = { [MANIFEST.bones.root] = {} }
	if body then
		sets[body.root] = body.skinned
	end
	for name, spec in MANIFEST.parts do
		if spec.skinned and not (body and table.find(body.skinned, name)) then
			table.insert(sets[MANIFEST.bones.root], name)
		end
	end
	return sets
end

-- avant toute modification : un jeu d'os se remplace avec toutes ses pièces (une pièce gardée resterait liée aux
-- anciens os), les articulations et pièces porteuses existent
if import then
	for rootName, names in skinnedSets() do
		local present = 0
		for _, n in names do
			if findPart(import, n) and MEASURED.parts[n] then
				present += 1
			end
		end
		if present > 0 and present < #names then
			error("import partiel des pièces skinnées sur « " .. rootName .. " » : rien n'est modifié")
		end
	end
end
if MANIFEST.bones.body then
	for _, j in MANIFEST.bones.body.joints do
		jointOf(j[1], j[2])
	end
end
for groupName in MANIFEST.studio.groupWeld or {} do
	weldTarget(groupName)
end

-- pièces d'un ancien modèle (et leurs fumées) : retirées
local stale = {}
for _, n in MANIFEST.studio.remove or {} do
	stale[n] = true
end
for _, d in model:GetDescendants() do
	if stale[d.Name] and (d:IsA("BasePart") or d:IsA("ParticleEmitter")) and d.Parent then
		table.insert(report.removed, d.Name)
		d:Destroy()
	end
end

-- articulations des bras d'abord : la faux est ensuite soudée à la main à sa place définitive
if MANIFEST.bones.body then
	for _, j in MANIFEST.bones.body.joints do
		fitJoint(j[1], j[2])
	end
end

local toTarget = nil
local replacedSet = {}
for name, spec in MANIFEST.parts do
	local measured = MEASURED.parts[name]
	local old = findPart(model, name)
	local fresh = import and findPart(import, name)
	local part = old
	if fresh and measured then
		local placed = fresh:Clone()
		for _, c in placed:GetChildren() do
			c:Destroy()
		end
		placed.CFrame = placeOf(measured.center)
		placed.Name = name
		placed.Parent = group(spec.group)
		-- repère de l'import -> repère du modèle (le même pour toutes les pièces : contrôlé plus haut)
		toTarget = toTarget or placed.CFrame * fresh.CFrame:Inverse()
		stripBones(placed)
		if old then
			-- ce qu'on avait ajouté à l'ancienne pièce (fumée, lumière...) suit la nouvelle ; soudure et apparence
			-- sont reposées d'après le manifeste
			for _, c in old:GetChildren() do
				if
					not (
						c:IsA("Bone")
						or c:IsA("JointInstance")
						or c:IsA("WeldConstraint")
						or c:IsA("SurfaceAppearance")
					)
				then
					c.Parent = placed
					table.insert(report.moved, name .. "." .. c.Name)
				end
			end
			old:Destroy()
		end
		part = placed
		replacedSet[name] = true
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
	weld(part, weldTarget(spec.group))
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

-- os : la robe sous la racine, le corps sous les pièces du rig R15 (import partiel refusé plus haut)
if import and toTarget then
	local sets = skinnedSets()
	if replacedSet[sets[MANIFEST.bones.root][1]] then
		moveCloakBones(toTarget)
	end
	local body = MANIFEST.bones.body
	if body and replacedSet[body.skinned[1]] then
		attachBodyBones(toTarget)
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

-- l'échelle automatique d'abord : active, elle recalculerait la hauteur des hanches
if MANIFEST.studio.humanoid.AutomaticScalingEnabled ~= nil then
	humanoid.AutomaticScalingEnabled = MANIFEST.studio.humanoid.AutomaticScalingEnabled
end
for prop, value in MANIFEST.studio.humanoid do
	if prop ~= "AutomaticScalingEnabled" then
		(humanoid :: any)[prop] = value
	end
end

-- contrôle : une pièce par nom, os de la cape sous la racine et nulle part ailleurs
local bones = 0
for _, d in root:GetDescendants() do
	if d:IsA("Bone") then
		bones += 1
	end
end
local roots = 0
for _, d in model:GetDescendants() do
	if d:IsA("Bone") and d.Name == MANIFEST.bones.root then
		roots += 1
	end
end
report.bones = bones
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
local expectedBones = 1 + MANIFEST.bones.chains * MANIFEST.bones.perChain
local failures = {}
if roots ~= 1 then
	table.insert(failures, string.format("%d os « %s » dans le modèle, 1 attendu", roots, MANIFEST.bones.root))
end
if next(duplicates) then
	table.insert(failures, "pièces absentes ou en double : " .. HttpService:JSONEncode(duplicates))
end
if bones ~= expectedBones then
	table.insert(failures, string.format("%d os sous la racine, %d attendus", bones, expectedBones))
end
-- os du corps : chacun une fois, les os rangés sous leur pièce du rig R15
if MANIFEST.bones.body then
	local count = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			count[d.Name] = (count[d.Name] or 0) + 1
		end
	end
	local wrong = {}
	for _, n in MEASURED.bodyBoneNames or {} do
		if count[n] ~= 1 then
			wrong[n] = count[n] or 0
		end
	end
	for n, partName in MANIFEST.bones.body.attach do
		local part = model:FindFirstChild(partName)
		local b = part and part:FindFirstChild(n)
		if not (b and b:IsA("Bone")) then
			wrong[n .. "@" .. partName] = 0
		end
	end
	report.bodyBones = #(MEASURED.bodyBoneNames or {})
	if next(wrong) then
		table.insert(failures, "os du corps absents, en double ou mal rangés : " .. HttpService:JSONEncode(wrong))
	end
end
print("REMOUNT " .. HttpService:JSONEncode(report))
if #failures > 0 then
	-- l'import reste en place pour corriger puis relancer
	error("remontage incomplet : " .. table.concat(failures, " ; "))
end
if import then
	import:Destroy()
end
