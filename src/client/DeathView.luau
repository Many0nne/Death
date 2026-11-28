-- Rendu de la Mort (client), d'après les attributs du serveur (LightRole, DeathExposed, DeathInBeam) et les règles
-- pures de Shared.DeathLook (#80) :
-- - pour un mortel : invisible dans l'ombre ; exposée, une colonne d'ombre pleine qui avale tout le corps (#98 : le
--   vrai corps est caché, une masse presque informe, pointe de capuche en haut, cœur noir sans contour, bord qui
--   bouillonne de fumée sombre, bas qui lèche le sol et traîne derrière elle), avec quelques braises claires, sans
--   faux ; dans un faisceau de lampe, la colonne se déchire (bouffée de fumée) et laisse voir le vrai corps et la faux ;
-- - pour la Mort elle-même : son corps et sa faux restent visibles, voilés dans l'ombre, pleins à la lumière
--   (l'indicateur « ombre / lumière » est dans le HUD, Client.Hud) ;
-- - pour tous : la Mort ne fait aucun bruit de pas.
-- Indépendant du modèle : la faux (`Scythe`) et le suaire (`Shroud`, tête penchée) sont retrouvés par leur nom, les
-- anneaux d'os de la robe (`Cxx_1`, `Cxx_3`) par Shared.CloakMotion ; sans eux, la colonne se pose d'après la boîte du
-- corps. Les valeurs d'origine (CastShadow, fumées du modèle) sont mémorisées et rétablies (#78).
-- Studio : un faux joueur Mort de debug (mannequin tagué MatchAttributes.BotTag, attributs sur le mannequin) est rendu
-- comme un joueur (#63).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CloakMotion = require(Shared:WaitForChild("CloakMotion"))
local DeathLook = require(Shared:WaitForChild("DeathLook"))
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))

local LA = LightAttributes
local View = DeathLook.View

-- Nom de la faux dans le modèle de la Mort (docs/assets.md)
local SCYTHE_NAME = "Scythe"
-- Nom du suaire, dont la position donne la tête penchée de la colonne
local SHROUD_NAME = "Shroud"
-- Remplissage du voile de la Mort sur elle-même (inchangé depuis #4)
local SELF_COLOR = Color3.fromRGB(0, 0, 0)
-- Ombre vue des mortels : noir bleuté plutôt que noir pur, sans contour (#96, Shared.DeathLook.layers)
local SHADOW_COLOR = Color3.fromRGB(9, 8, 13)
-- Textures de particules fournies avec Roblox
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
-- Fumée de l'ombre (#98) : bouffée dense au cœur, bords effilochés (assets/textures/death/shadow_smoke.png, script
-- tools/blender/shadow_smoke.py, asset Image envoyé par Open Cloud) ; celles de Roblox sont trop pâles (smoke_main) ou
-- rondes (explosion01)
local SHADOW_SMOKE_TEXTURE = "rbxassetid://80745440503887"
local EMBER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
-- Débit (particules par seconde) de chaque effet de la colonne, pleine ombre : chaque flanc bas, chaque flanc haut
-- (capuche), fumée qui lèche le sol, braises ; en vol : 2 x 12 x 1,15 + 2 x 6 x 1,15 + 14 x 1,5 + 4 x 2,1 = 71
local RATES = { flankLow = 12, flankHigh = 6, lick = 14, embers = 4 }
-- Bouffées jouées quand l'ombre se déchire dans le faisceau
local TEAR_SMOKE = 30
local TEAR_EMBERS = 8
-- Au-delà, sans faux à mettre à part, un seul voile couvre tout le personnage (vue de la Mort sur elle-même)
local MAX_GROUPS = 8
-- Rang des os de la robe qui donnent le centre de la colonne : milieu et bas de chaque chaîne (Shared.CloakMotion)
local MID_BONE, HEM_BONE = 1, 3
-- Pas de transparence de la colonne : elle n'est réécrite que quand elle change d'un pas
local FILL_STEP = 0.05

local DeathView = {}

-- Cette méthode permet de savoir si une instance fait partie d'un morceau mis à part (la faux) lorsque le rendu le
-- traite autrement que le corps.
local function within(instance: Instance, piece: Instance?): boolean
	return piece ~= nil and (instance == piece or instance:IsDescendantOf(piece))
end

-- Cette méthode permet de savoir si un morceau du personnage a quelque chose à dessiner lorsque les voiles sont
-- posés : les pièces du rig, invisibles (Transparency = 1), n'en reçoivent pas.
local function hasVisible(instance: Instance): boolean
	if instance:IsA("BasePart") and instance.Transparency < 1 then
		return true
	end
	for _, d in instance:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			return true
		end
	end
	return false
end

-- Cette méthode permet de lister les morceaux du corps à voiler lorsque le modèle apparaît ou change : un Highlight ne
-- prend qu'un Model ou une BasePart, donc un par Model visible hors de la faux, un par pièce visible ; on descend dans
-- tout le reste (dossier, accessoire, outil, pièce invisible du rig, Model qui contient la faux).
local function collectGroups(container: Instance, scythe: Instance?, out: { Instance })
	for _, child in container:GetChildren() do
		if child == scythe then
			continue
		end
		local holdsScythe = scythe ~= nil and scythe:IsDescendantOf(child)
		if child:IsA("Model") and not holdsScythe then
			if hasVisible(child) then
				table.insert(out, child)
			end
			continue
		end
		if child:IsA("BasePart") and child.Transparency < 1 then
			table.insert(out, child)
		end
		collectGroups(child, scythe, out)
	end
end

-- Cette méthode permet de créer un remplissage (Highlight) sur un morceau lorsque le modèle est relevé ou que la
-- colonne d'ombre est créée.
local function newHighlight(adornee: Instance, color: Color3): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "DeathShadow"
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = adornee
	highlight.Parent = adornee
	return highlight
end

-- Cette méthode permet de créer un émetteur de fumée ou de braises de la colonne lorsque les effets d'un corps sont
-- créés (débit nul : il est réglé à chaque frame).
local function newEmitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.LightInfluence = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

-- Cette méthode permet de créer une pièce locale, ancrée et inerte (ni collision, ni rayon, ni ombre portée) lorsque
-- les effets d'un corps sont créés.
local function newPart(name: string, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

-- Cette méthode permet de créer la colonne d'ombre (#98) lorsque les effets d'un corps sont créés : un ellipsoïde par
-- morceau (Shared.DeathLook.column : couches serrées, pointe de capuche, jupe), tous sous un seul remplissage plat et
-- sans contour, d'où une masse continue au flanc lisse.
local function newColumn(folder: Instance)
	local model = Instance.new("Model")
	model.Name = "ShadowColumn"
	local parts = {}
	for k = 1, DeathLook.columnPieces() do
		local part = newPart("Column" .. k, model)
		part.Material = Enum.Material.SmoothPlastic
		part.Color = SHADOW_COLOR
		-- la sphère remplit la pièce : la pièce prend la vraie taille du morceau (une pièce de 1 stud agrandie par son
		-- seul maillage n'est plus dessinée au loin, mesuré à 20 studs)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		table.insert(parts, part)
	end
	model.Parent = folder
	return { model = model, parts = parts, highlight = newHighlight(model, SHADOW_COLOR) }
end

-- Cette méthode permet de créer une fumée de flanc lorsque les effets d'un corps sont créés : langues sombres qui
-- naissent sur le bord de la silhouette (axe X de leur volume), s'en détachent de 0,3 à 0,8 stud et se défont.
local function newFlank(folder: Instance, name: string): (BasePart, ParticleEmitter)
	local part = newPart(name, folder)
	local emitter = newEmitter(part, {
		Name = "Smoke",
		Texture = SHADOW_SMOKE_TEXTURE,
		Color = ColorSequence.new(SHADOW_COLOR),
		EmissionDirection = Enum.NormalId.Right,
		-- étirées dans le sens de leur vitesse : des langues, pas des boules
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.2) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.1) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.9, 1.4),
		Speed = NumberRange.new(0.5, 1.1),
		Drag = 2,
		SpreadAngle = Vector2.new(30, 45),
		Acceleration = Vector3.new(0, 0.5, 0),
		Rotation = NumberRange.new(0, 0),
		RotSpeed = NumberRange.new(-40, 40),
	})
	return part, emitter
end

-- Cette méthode permet de créer la colonne et ses fumées (flancs qui bouillonnent, bas qui lèche le sol, braises,
-- déchirure) lorsqu'un mortel voit une Mort pour la première fois ; locales à ce client, hors du personnage.
local function newShadowFx(folder: Instance)
	local body = newPart("ShadowBody", folder)
	local floor = newPart("ShadowFloor", folder)
	local dark = ColorSequence.new(SHADOW_COLOR)
	local flankParts, flankEmitters = {}, {}
	for k = 1, 4 do
		local part, emitter = newFlank(folder, "ShadowFlank" .. k)
		flankParts[k], flankEmitters[k] = part, emitter
	end
	return {
		body = body,
		floor = floor,
		column = newColumn(folder),
		flankParts = flankParts,
		-- bas gauche, bas droit, haut gauche, haut droit (Shared.DeathLook.column)
		flanks = flankEmitters,
		-- Bas qui lèche le sol : fumée épaisse et aplatie qui roule au ras du plancher depuis le bord de la jupe ; laissée
		-- en place (monde), elle fait une langue derrière la Mort qui glisse
		lick = newEmitter(floor, {
			Name = "Lick",
			Shape = Enum.ParticleEmitterShape.Cylinder,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Texture = SHADOW_SMOKE_TEXTURE,
			Color = dark,
			Squash = NumberSequence.new(-0.3),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3) }),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(0.6, 1.4),
			Drag = 1.5,
			Acceleration = Vector3.new(0, 0.15, 0),
		}),
		-- Quelques braises claires qui montent de la fumée : un repère dans le noir
		embers = newEmitter(floor, {
			Name = "Embers",
			Texture = EMBER_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(215, 200, 180), Color3.fromRGB(120, 105, 95)),
			LightEmission = 0.6,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1.6, 2.6),
			Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0, 0.8, 0),
		}),
		-- Déchirure : bouffée rapide qui s'écarte du corps, jouée une fois quand le faisceau la révèle
		tear = newEmitter(body, {
			Name = "Tear",
			Enabled = false, -- bouffées seulement (Emit)
			Texture = SMOKE_TEXTURE,
			Color = dark,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
		}),
	}
end

-- Cette méthode permet d'appliquer la transparence locale au corps et à la faux lorsque leur part visible change ;
-- caché, un morceau ne projette plus d'ombre (qui le trahirait sous une lampe) et ses fumées s'arrêtent, comme celles
-- du modèle tant que la colonne les remplace. Les valeurs d'origine (CastShadow, ParticleEmitter.Enabled) sont
-- relevées à la première écriture et rétablies ensuite (#78).
local function applyTransparency(character: Model, state, body: number, scythe: number, modelSmoke: boolean)
	for _, d in character:GetDescendants() do
		local value = if within(d, state.scythe) then scythe else body
		if d:IsA("BasePart") then
			if state.castShadow[d] == nil then
				state.castShadow[d] = d.CastShadow
			end
			d.LocalTransparencyModifier = value
			d.CastShadow = state.castShadow[d] and value < 1
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = value
		elseif d:IsA("ParticleEmitter") then
			if state.emitters[d] == nil then
				state.emitters[d] = d.Enabled
			end
			d.Enabled = state.emitters[d] and value < 1 and modelSmoke
			if value >= 1 then
				-- corps disparu : ses fumées en vol aussi ; quand la colonne les remplace, elles s'éteignent sans couper net
				d:Clear()
			end
		end
	end
end

-- Cette méthode permet de donner le centre d'un anneau d'os de la robe (monde) lorsque la colonne est posée ; nil sans
-- os (avatar d'un bot).
local function ringCenter(bones: { Bone }): Vector3?
	if #bones == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, bone in bones do
		sum += bone.TransformedWorldCFrame.Position
	end
	return sum / #bones
end

-- Cette méthode permet de cacher ou montrer la colonne d'ombre lorsque sa transparence change d'un pas (FILL_STEP) :
-- pièces et remplissage fondus ensemble.
local function setColumnFill(state, column, fill: number)
	local level = if fill >= 1 then 1 else math.floor(fill / FILL_STEP + 0.5) * FILL_STEP
	if state.columnFill == level then
		return
	end
	state.columnFill = level
	-- jamais tout à fait opaques : une pièce opaque prend le voile de l'atmosphère au loin (bleu-gris à 20 studs, mesuré),
	-- une pièce à peine transparente reste noire sous le remplissage
	for _, part in column.parts do
		part.Transparency = math.max(level, FILL_STEP)
	end
	column.highlight.Enabled = level < 1
	column.highlight.FillTransparency = level
end

-- Cette méthode permet de poser la colonne d'ombre à chaque frame lorsqu'un mortel voit la Mort (Shared.DeathLook.column)
-- : sol réel sous elle, centre des anneaux d'os de la robe, tête penchée, vitesse ; place aussi les volumes des fumées.
local function placeColumn(state, fx)
	local root = state.root
	local rootCFrame = root.CFrame
	-- vrai sol sous la Mort (rayon qui ignore son corps et les effets) ; à défaut, le bas du corps
	local floorY = rootCFrame:PointToWorldSpace(Vector3.new(0, state.bounds.bottom, 0)).Y
	if not state.floorParams then
		-- seules les pièces qui portent comptent (pas les ancres invisibles de la maison ni une batterie posée)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.character, fx.body.Parent }
		params.RespectCanCollide = true
		state.floorParams = params
	end
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), state.floorParams)
	if hit then
		floorY = hit.Position.Y
	end
	local shroud = state.shroud
	local column = DeathLook.column({
		root = rootCFrame,
		floorY = floorY,
		top = rootCFrame:PointToWorldSpace(Vector3.new(0, state.bounds.top, 0)).Y,
		hem = ringCenter(state.rings.hem),
		mid = ringCenter(state.rings.mid),
		head = if shroud and shroud.Parent then shroud.Position else nil,
		camera = if workspace.CurrentCamera then workspace.CurrentCamera.CFrame.Position else nil,
		velocity = root.AssemblyLinearVelocity,
		t = os.clock(),
	})
	local frames = table.create(#column.pieces)
	for k, piece in column.pieces do
		frames[k] = piece.cframe
		fx.column.parts[k].Size = piece.size
	end
	workspace:BulkMoveTo(fx.column.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	fx.body.Size = column.body.size
	fx.body.CFrame = column.body.cframe
	fx.floor.Size = column.floor.size
	fx.floor.CFrame = column.floor.cframe
	for k, flank in column.flanks do
		fx.flankParts[k].Size = flank.size
		fx.flankParts[k].CFrame = flank.cframe
	end
end

-- Cette méthode permet de lister les Morts à rendre lorsque la frame commence : les joueurs de rôle Mort (attributs sur
-- le Player) et, en Studio, les mannequins des faux joueurs Mort (attributs sur le mannequin).
local function subjects(): { [Model]: Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and player:GetAttribute(LA.LightRole) == DeathRules.Role.Death then
			list[character] = player
		end
	end
	for _, mannequin in CollectionService:GetTagged(MatchAttributes.BotTag) do
		if mannequin:IsA("Model") and mannequin:GetAttribute(LA.LightRole) == DeathRules.Role.Death then
			list[mannequin] = mannequin
		end
	end
	return list
end

-- Cette méthode permet de démarrer le rendu de la Mort lorsque le client se lance.
function DeathView.start()
	local localPlayer = Players.LocalPlayer
	-- Effets locaux de l'ombre (hors des personnages : ni ombre portée, ni transparence à poser)
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "DeathShadowFx"
	fxFolder.Parent = workspace
	-- Personnage suivi comme Mort -> état de rendu (voir render)
	local tracked: { [Model]: any } = {}

	-- Cette méthode permet de relever la faux, le suaire, les anneaux d'os de la robe, les voiles de la Mort sur
	-- elle-même et les mesures du corps lorsque le personnage apparaît ou qu'une pièce lui est ajoutée.
	local function scan(character: Model, state)
		for _, highlight in state.highlights do
			highlight:Destroy()
		end
		if state.scytheHighlight then
			state.scytheHighlight:Destroy()
		end
		state.highlights = {}
		state.scytheHighlight = nil
		local scythe = character:FindFirstChild(SCYTHE_NAME, true)
		state.scythe = scythe
		local shroud = character:FindFirstChild(SHROUD_NAME, true)
		state.shroud = if shroud and shroud:IsA("BasePart") then shroud else nil
		if state.view == View.Self then
			-- Voile de la Mort sur son propre corps : un remplissage par morceau, la faux à part
			local groups = {}
			collectGroups(character, scythe, groups)
			if #groups > MAX_GROUPS and not scythe then
				-- Avatar en pièces détachées (mannequin R15 d'un bot) : un seul remplissage, Roblox n'en dessine que 31
				groups = { character }
			end
			for _, group in groups do
				table.insert(state.highlights, newHighlight(group, SELF_COLOR))
			end
			state.scytheHighlight = if scythe then newHighlight(scythe, SELF_COLOR) else nil
		end
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		state.root = if root and root:IsA("BasePart") then root else nil
		-- anneaux d'os du milieu et du bas de la robe, que la colonne suit (ondulation, traîne de la cape)
		state.rings = { mid = {}, hem = {} }
		for _, d in character:GetDescendants() do
			if d:IsA("Bone") then
				local _, index = CloakMotion.parseBone(d.Name)
				if index == MID_BONE then
					table.insert(state.rings.mid, d)
				elseif index == HEM_BONE then
					table.insert(state.rings.hem, d)
				end
			end
		end
		state.bounds = nil
		if state.root then
			local boxes = {}
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 and not within(d, scythe) then
					table.insert(boxes, { cframe = d.CFrame, size = d.Size })
				end
			end
			state.bounds = DeathLook.bounds(state.root.CFrame, boxes)
		end
		state.dirty = false
		state.applied = nil
	end

	-- Cette méthode permet de rendre au personnage son apparence et ses sons lorsqu'il n'est plus la Mort : valeurs
	-- d'origine rétablies, voiles, colonne et fumées détruits.
	local function release(character: Model)
		local state = tracked[character]
		tracked[character] = nil
		state.added:Disconnect()
		for _, highlight in state.highlights do
			highlight:Destroy()
		end
		if state.scytheHighlight then
			state.scytheHighlight:Destroy()
		end
		if state.fx then
			state.fx.body:Destroy()
			state.fx.floor:Destroy()
			state.fx.column.model:Destroy()
			for _, part in state.fx.flankParts do
				part:Destroy()
			end
		end
		for sound, volume in state.muted do
			if sound.Parent then
				sound.Volume = volume
			end
		end
		for part, castShadow in state.castShadow do
			if part.Parent then
				part.LocalTransparencyModifier = 0
				part.CastShadow = castShadow
			end
		end
		for emitter, enabled in state.emitters do
			if emitter.Parent then
				emitter.Enabled = enabled
			end
		end
		if state.applied and character.Parent then
			for _, d in character:GetDescendants() do
				if d:IsA("Decal") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end

	-- Cette méthode permet de couper à chaque frame les sons du personnage (pas, chute, atterrissage) lorsque c'est la
	-- Mort : le script de sons de Roblox réécrit leur volume à chaque mouvement.
	local function mute(character: Model, state)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		for _, sound in root:GetChildren() do
			if sound:IsA("Sound") then
				if state.muted[sound] == nil then
					state.muted[sound] = sound.Volume
				end
				sound.Volume = 0
			end
		end
	end

	-- Cette méthode permet d'éteindre la colonne et ses fumées lorsque la Mort disparaît ou n'est plus mesurable :
	-- `clear` retire aussi les fumées en vol.
	local function hideFx(state, clear: boolean)
		local fx = state.fx
		if not fx then
			return
		end
		setColumnFill(state, fx.column, 1)
		for _, emitter in { fx.lick, fx.embers, table.unpack(fx.flanks) } do
			emitter.Enabled = false
		end
		if clear then
			for _, emitter in { fx.lick, fx.embers, fx.tear, table.unpack(fx.flanks) } do
				emitter:Clear()
			end
		end
	end

	-- Cette méthode permet de régler et placer la colonne et ses fumées à chaque frame lorsqu'un mortel voit une Mort :
	-- transparence et débits selon la part d'ombre, bouffée de déchirure quand le faisceau la révèle.
	local function renderFx(state, fill: number, smoke: number, tearing: boolean)
		if not state.root or not state.bounds then
			-- Corps plus mesurable (racine ou pièces disparues) : rien ne doit rester ni fumer à l'ancienne place
			hideFx(state, false)
			return
		end
		if not state.fx then
			state.fx = newShadowFx(fxFolder)
		end
		local fx = state.fx
		local on = smoke > 0.01
		setColumnFill(state, fx.column, fill)
		if on or tearing then
			placeColumn(state, fx)
		end
		for k, flank in fx.flanks do
			flank.Rate = (if k <= 2 then RATES.flankLow else RATES.flankHigh) * smoke
			flank.Enabled = on
		end
		fx.lick.Rate = RATES.lick * smoke
		fx.embers.Rate = RATES.embers * smoke
		fx.lick.Enabled = on
		fx.embers.Enabled = on
		if tearing then
			fx.tear:Emit(TEAR_SMOKE)
			fx.embers:Emit(TEAR_EMBERS)
		end
		if state.visibility <= 0 and state.fxVisible then
			-- Disparue (ombre) : les fumées en vol disparaissent avec elle
			hideFx(state, true)
		end
		state.fxVisible = state.visibility > 0
	end

	-- Cette méthode permet de mettre à jour l'apparence de la Mort à chaque frame lorsqu'un joueur (ou un faux joueur)
	-- a ce rôle : fondus de visibilité et de révélation (Shared.DeathLook), puis corps, voiles, colonne et fumées.
	local function render(subject: Instance, character: Model, dt: number)
		local state = tracked[character]
		if not state then
			state = {
				view = if subject == localPlayer then View.Self else View.Mortal,
				character = character,
				highlights = {},
				rings = { mid = {}, hem = {} },
				visibility = 0,
				reveal = 0,
				revealTarget = 0,
				-- Clés faibles : une pièce détruite pendant que la Mort est suivie ne reste pas en mémoire
				muted = setmetatable({}, { __mode = "k" }),
				castShadow = setmetatable({}, { __mode = "k" }),
				emitters = setmetatable({}, { __mode = "k" }),
				dirty = true,
			}
			state.added = character.DescendantAdded:Connect(function(d)
				-- Seul ce qui se dessine ou porte la robe change le modèle (pas un son, une soudure ni les voiles)
				if
					d:IsA("BasePart")
					or d:IsA("Decal")
					or d:IsA("ParticleEmitter")
					or d:IsA("Model")
					or d:IsA("Accessory")
					or d:IsA("Bone")
				then
					state.dirty = true
				end
			end)
			tracked[character] = state
		end
		if state.dirty then
			scan(character, state)
		end
		mute(character, state)
		local exposed = subject:GetAttribute(LA.Exposed) == true
		local position = if state.root then state.root.Position else nil
		-- Une dissipation suit toujours un faisceau : un saut sans faisceau (saccade réseau, placement) ne cache rien
		if state.view == View.Mortal and state.revealTarget > 0 and DeathLook.jumped(state.position, position, dt) then
			-- Dissipée et reformée ailleurs : rien ne doit trahir l'endroit où elle reparaît. Cachée tout de suite, et
			-- jusqu'à ce que son exposition (encore vraie pendant le délai d'ombre du serveur) retombe
			state.visibility, state.reveal, state.revealTarget = 0, 0, 0
			state.hold = DeathLook.JUMP_HOLD
			hideFx(state, true)
		end
		state.position = position
		state.hold = DeathLook.holdAfterJump(state.hold or 0, exposed, dt)
		local shown = exposed and state.hold <= 0
		local mode = DeathLook.mode(state.view, shown, subject:GetAttribute(LA.InBeam) == true)
		local visibilityTarget, revealTarget = DeathLook.targets(mode, shown)
		state.visibility =
			DeathLook.approach(state.visibility, visibilityTarget, DeathLook.FADE_TIME, DeathLook.FADE_TIME, dt)
		local tearing = DeathLook.tears(state.revealTarget, revealTarget, state.reveal, state.visibility)
		state.reveal = DeathLook.approach(state.reveal, revealTarget, DeathLook.REVEAL_TIME, DeathLook.CLOSE_TIME, dt)
		state.revealTarget = revealTarget
		local layers = DeathLook.layers(state.view, state.visibility, state.reveal)

		if state.view == View.Self then
			-- Première personne verrouillée (#24) : pas de voile sur ses propres bras, le HUD l'indique ; la
			-- transparence de son corps reste à la caméra
			local veiled = localPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson
			for _, highlight in state.highlights do
				highlight.Enabled = veiled
				highlight.FillTransparency = layers.fill
			end
			if state.scytheHighlight then
				state.scytheHighlight.Enabled = veiled
				state.scytheHighlight.FillTransparency = layers.scytheFill
			end
			return
		end

		local applied = state.applied
		if
			not applied
			or applied.body ~= layers.body
			or applied.scythe ~= layers.scythe
			or applied.modelSmoke ~= layers.modelSmoke
		then
			state.applied = { body = layers.body, scythe = layers.scythe, modelSmoke = layers.modelSmoke }
			applyTransparency(character, state, layers.body, layers.scythe, layers.modelSmoke)
		end
		renderFx(state, layers.fill, layers.smoke, tearing)
	end

	RunService.RenderStepped:Connect(function(dt)
		local seen = subjects()
		for character, subject in seen do
			render(subject, character, dt)
		end
		for character in tracked do
			if not seen[character] then
				release(character)
			end
		end
	end)
end

return DeathView
