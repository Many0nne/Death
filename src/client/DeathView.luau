-- Rendu de la Mort (client), d'après les attributs du serveur (LightRole, DeathExposed, DeathInBeam) et les règles
-- pures de Shared.DeathLook (#80) :
-- - pour un mortel : invisible dans l'ombre ; exposée, une ombre pleine (remplissage sombre, contour léger) qui épouse
--   la silhouette et dont le bas se défait en volutes ondulantes (#90 : une traînée par chaîne d'os de la robe, plus de
--   nuage rond), avec quelques fumerolles et braises claires, sans faux ; dans un faisceau de lampe, l'ombre se
--   déchire (bouffée de fumée) et laisse voir le vrai corps et la faux ;
-- - pour la Mort elle-même : son corps et sa faux restent visibles, voilés dans l'ombre, pleins à la lumière
--   (l'indicateur « ombre / lumière » est dans le HUD, Client.Hud) ;
-- - pour tous : la Mort ne fait aucun bruit de pas.
-- Indépendant du modèle : la faux (`Scythe`) et les lanières du bas (`Tatters`, #81, estompées dans l'ombre au lieu
-- d'être remplies) sont retrouvées par leur nom, le reste du corps est pris tel quel. Les
-- valeurs d'origine (CastShadow, fumées du modèle) sont mémorisées et rétablies (#78).
-- Studio : un faux joueur Mort de debug (mannequin tagué MatchAttributes.BotTag, attributs sur le mannequin) est rendu
-- comme un joueur (#63).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathLook = require(Shared:WaitForChild("DeathLook"))
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))

local LA = LightAttributes
local View = DeathLook.View

-- Nom de la faux dans le modèle de la Mort (docs/assets.md)
local SCYTHE_NAME = "Scythe"
-- Nom du groupe des lanières du bas (#81), que l'ombre vue d'un mortel estompe au lieu de la remplir
local TATTERS_NAME = "Tatters"
-- Remplissage du voile de la Mort sur elle-même (inchangé depuis #4)
local SELF_COLOR = Color3.fromRGB(0, 0, 0)
-- Ombre vue des mortels : noir bleuté plutôt que noir pur, contour gris violacé à peine visible
local SHADOW_COLOR = Color3.fromRGB(9, 8, 13)
local OUTLINE_COLOR = Color3.fromRGB(110, 98, 128)
-- Textures de particules fournies avec Roblox
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local EMBER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
-- Débit (particules par seconde) de chaque effet de l'ombre, pleine ombre (#90 : plus de colonne de fumée au bas)
local RATES = { wisps = 8, embers = 4 }
-- Volutes (#90) : une par chaîne d'os de la robe (Bone « Cxx_2 », « Cxx_3 », Shared.CloakMotion) ; sans os (avatar
-- d'un bot), une couronne autour du bas du corps
local TENDRIL_CHAINS = 16
local TENDRIL_SEGMENTS = 14
-- Au-delà de cette distance de la caméra (studs), les volutes ne se recalculent plus (figées)
local TENDRIL_RANGE = 120
-- Bouffées jouées quand l'ombre se déchire dans le faisceau
local TEAR_SMOKE = 30
local TEAR_EMBERS = 8
-- Au-delà, sans faux à mettre à part, un seul remplissage couvre tout le personnage
local MAX_GROUPS = 8

local DeathView = {}

-- Cette méthode permet de savoir si une instance fait partie d'un morceau mis à part (faux, lanières) lorsque le rendu
-- le traite autrement que le corps.
local function within(instance: Instance, piece: Instance?): boolean
	return piece ~= nil and (instance == piece or instance:IsDescendantOf(piece))
end

-- Cette méthode permet de savoir si un morceau du personnage a quelque chose à dessiner lorsque les remplissages sont
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

-- Cette méthode permet de lister les morceaux du corps à couvrir d'une ombre lorsque le modèle apparaît ou change : un
-- Highlight ne prend qu'un Model ou une BasePart, donc un par Model visible hors des morceaux mis à part (`skip` : la
-- faux, les lanières vues d'un mortel), un par pièce visible ; on descend dans tout le reste (dossier, accessoire,
-- outil, pièce invisible du rig, Model qui contient un morceau mis à part).
local function collectGroups(container: Instance, skip: { Instance }, out: { Instance })
	for _, child in container:GetChildren() do
		if table.find(skip, child) then
			continue
		end
		local holdsSkipped = false
		for _, s in skip do
			holdsSkipped = holdsSkipped or s:IsDescendantOf(child)
		end
		if child:IsA("Model") and not holdsSkipped then
			if hasVisible(child) then
				table.insert(out, child)
			end
			continue
		end
		if child:IsA("BasePart") and child.Transparency < 1 then
			table.insert(out, child)
		end
		collectGroups(child, skip, out)
	end
end

-- Cette méthode permet de créer un remplissage (Highlight) sur un morceau du corps lorsque le modèle est relevé.
local function newHighlight(adornee: Instance, color: Color3, outline: Color3): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "DeathShadow"
	highlight.FillColor = color
	highlight.OutlineColor = outline
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = adornee
	highlight.Parent = adornee
	return highlight
end

-- Cette méthode permet de créer un émetteur de fumée ou de braises de l'ombre lorsque les effets d'un corps sont créés
-- (débit nul : il est réglé à chaque frame).
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

-- Cette méthode permet de créer un volume invisible qui porte des émetteurs lorsque les effets d'un corps sont créés.
local function newVolume(name: string, folder: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = folder
	return part
end

-- Cette méthode permet de créer les volutes du bas de l'ombre (#90) lorsque les effets d'un corps sont créés : une
-- traînée (Beam) sombre par chaîne de la robe, entre deux attaches posées en coordonnées monde à chaque frame.
local function newTendrils(folder: Instance): { holder: BasePart, beams: { Beam } }
	local holder = newVolume("ShadowTendrils", folder)
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.identity
	local beams = {}
	for k = 1, TENDRIL_CHAINS do
		local a0 = Instance.new("Attachment")
		a0.Name = "TendrilStart" .. k
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Name = "TendrilEnd" .. k
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Name = "Tendril" .. k
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(SHADOW_COLOR)
		beam.LightInfluence = 0
		beam.LightEmission = 0
		beam.FaceCamera = true
		beam.Segments = TENDRIL_SEGMENTS
		beam.Width0 = DeathLook.TENDRIL.WIDTH_START
		beam.Width1 = DeathLook.TENDRIL.WIDTH_END
		-- pleine (sans texture : la fumée de Roblox est trop transparente pour une ombre), défaite au bout
		beam.Enabled = false
		beam.Parent = holder
		table.insert(beams, beam)
	end
	return { holder = holder, beams = beams }
end

-- Cette méthode permet de donner la transparence d'une volute selon la part d'ombre lorsqu'elle apparaît ou disparaît :
-- pleine au départ, défaite au bout.
local function tendrilTransparency(smoke: number): NumberSequence
	local fade = 1 - smoke
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, fade),
		NumberSequenceKeypoint.new(0.6, 0.25 + 0.75 * fade),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Cette méthode permet de créer les effets de l'ombre (volutes du bas, fumerolles, braises, déchirure) lorsqu'un
-- mortel voit une Mort pour la première fois ; locaux à ce client, hors du personnage.
local function newShadowFx(folder: Instance)
	local hem = newVolume("ShadowHem", folder)
	local body = newVolume("ShadowBody", folder)
	local dark = ColorSequence.new(SHADOW_COLOR)
	return {
		hem = hem,
		body = body,
		tendrils = newTendrils(folder),
		-- Fumerolles qui s'échappent de la silhouette : les bords ne sont jamais nets (petites, pour ne pas en
		-- brouiller la forme)
		wisps = newEmitter(body, {
			Name = "Wisps",
			Texture = SMOKE_TEXTURE,
			Color = dark,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(0.3, 0.8),
			Acceleration = Vector3.new(0, 1.2, 0),
		}),
		-- Quelques braises claires qui montent de la fumée : un repère dans le noir
		embers = newEmitter(hem, {
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
-- du modèle tant que l'ombre les remplace (#90). Les valeurs d'origine (CastShadow, ParticleEmitter.Enabled) sont
-- relevées à la première écriture et rétablies ensuite (#78).
local function applyTransparency(
	character: Model,
	state,
	body: number,
	scythe: number,
	tatters: number,
	modelSmoke: boolean
)
	for _, d in character:GetDescendants() do
		local value = if within(d, state.scythe) then scythe elseif within(d, state.tatters) then tatters else body
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
				-- corps disparu : ses fumées en vol aussi ; quand l'ombre les remplace, elles s'éteignent sans couper net
				d:Clear()
			end
		end
	end
end

-- Cette méthode permet d'allumer ou d'éteindre toutes les volutes d'un corps lorsque l'ombre apparaît ou disparaît.
local function setTendrils(tendrils, enabled: boolean)
	for _, beam in tendrils.beams do
		beam.Enabled = enabled
	end
end

-- Cette méthode permet de donner les départs des volutes (monde) et leur côté extérieur lorsque la frame les place :
-- bas de chaque chaîne de la robe, prolongé d'un os ; sans os (avatar d'un bot), une couronne au bas du corps.
local function tendrilStarts(state): { { start: Vector3, outward: Vector3 } }
	local root = state.root
	local center = root.Position
	local out = {}
	if #state.chains > 0 then
		for _, chain in state.chains do
			local a = chain.upper.TransformedWorldCFrame.Position
			local b = chain.lower.TransformedWorldCFrame.Position
			-- un peu au-dessus de l'ourlet : la volute sort de sous la robe, sans coupure
			local start = b + (b - a) * 0.6
			table.insert(out, { start = start, outward = start - center })
		end
		return out
	end
	local y = state.bounds.bottom + 0.4
	for k = 0, TENDRIL_CHAINS - 1 do
		local th = 2 * math.pi * k / TENDRIL_CHAINS
		local offset = Vector3.new(math.sin(th), 0, -math.cos(th)) * state.bounds.radius * 0.6
		local start = root.CFrame:PointToWorldSpace(offset + Vector3.new(0, y, 0))
		table.insert(out, { start = start, outward = start - center })
	end
	return out
end

-- Cette méthode permet de placer et d'animer les volutes du bas de l'ombre à chaque frame lorsqu'un mortel voit la
-- Mort (Shared.DeathLook.tendril) ; leur transparence suit la part d'ombre, par paliers.
local function renderTendrils(state, tendrils, smoke: number)
	local camera = workspace.CurrentCamera
	local inRange = not camera or (camera.CFrame.Position - state.root.Position).Magnitude <= TENDRIL_RANGE
	-- trop loin : éteintes plutôt que figées à l'ancienne place (elles trahiraient où elle était)
	local on = smoke > 0.01 and inRange
	setTendrils(tendrils, on)
	if not on then
		return
	end
	local level = math.floor(smoke * 20 + 0.5) / 20
	if state.tendrilLevel ~= level then
		state.tendrilLevel = level
		local transparency = tendrilTransparency(level)
		for _, beam in tendrils.beams do
			beam.Transparency = transparency
		end
	end
	local root = state.root
	local velocity = root.AssemblyLinearVelocity
	-- vrai sol sous la Mort (rayon qui ignore son corps et les effets) ; à défaut, le bas du corps
	local floorY = root.CFrame:PointToWorldSpace(Vector3.new(0, state.bounds.bottom, 0)).Y
	if not state.floorParams then
		-- seules les pièces qui portent comptent (pas les ancres invisibles de la maison ni une batterie posée)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.character, tendrils.holder.Parent }
		params.RespectCanCollide = true
		state.floorParams = params
	end
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), state.floorParams)
	if hit then
		floorY = hit.Position.Y
	end
	local look = root.CFrame.LookVector
	local t = os.clock()
	for k, origin in tendrilStarts(state) do
		local beam = tendrils.beams[k]
		if not beam then
			break
		end
		local flat = Vector3.new(origin.outward.X, 0, origin.outward.Z)
		local back = if flat.Magnitude > 1e-6 then (1 - flat.Unit:Dot(look)) / 2 else 0.5
		local tendril = DeathLook.tendril(
			origin.start,
			origin.outward,
			velocity,
			t,
			k * 2.39,
			DeathLook.tendrilLength(back),
			floorY
		)
		local a0, a1 = beam.Attachment0 :: Attachment, beam.Attachment1 :: Attachment
		-- l'axe X d'une attache porte le point de contrôle de la courbe du Beam
		a0.WorldCFrame = CFrame.fromMatrix(tendril.start, tendril.startAxis, tendril.endAxis)
		a1.WorldCFrame = CFrame.fromMatrix(tendril.finish, tendril.endAxis, tendril.startAxis)
		beam.CurveSize0 = tendril.startCurve
		beam.CurveSize1 = tendril.endCurve
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

	-- Cette méthode permet de relever la faux, les morceaux du corps et leurs mesures lorsque le personnage apparaît ou
	-- qu'une pièce lui est ajoutée : un remplissage par morceau, la faux à part.
	local function scan(character: Model, state)
		for _, highlight in state.highlights do
			highlight:Destroy()
		end
		if state.scytheHighlight then
			state.scytheHighlight:Destroy()
		end
		local scythe = character:FindFirstChild(SCYTHE_NAME, true)
		state.scythe = scythe
		-- lanières vues d'un mortel : sans remplissage, effacées à demi (DeathLook.TATTER_FADE)
		local tatters = if state.view == View.Mortal then character:FindFirstChild(TATTERS_NAME, true) else nil
		state.tatters = tatters
		local color = if state.view == View.Self then SELF_COLOR else SHADOW_COLOR
		local outline = if state.view == View.Self then SELF_COLOR else OUTLINE_COLOR
		local groups = {}
		local skip = {}
		for _, s in { scythe, tatters } do
			if s then
				table.insert(skip, s)
			end
		end
		collectGroups(character, skip, groups)
		if #groups > MAX_GROUPS and not scythe then
			-- Avatar en pièces détachées (mannequin R15 d'un bot) : un seul remplissage, Roblox n'en dessine que 31
			groups = { character }
		end
		state.highlights = {}
		for _, group in groups do
			table.insert(state.highlights, newHighlight(group, color, outline))
		end
		state.scytheHighlight = if scythe then newHighlight(scythe, color, outline) else nil
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		state.root = if root and root:IsA("BasePart") then root else nil
		-- bas des chaînes de la robe, d'où partent les volutes (#90)
		state.chains = {}
		for c = 0, TENDRIL_CHAINS - 1 do
			local upper = character:FindFirstChild(string.format("C%02d_2", c), true)
			local lower = character:FindFirstChild(string.format("C%02d_3", c), true)
			if upper and upper:IsA("Bone") and lower and lower:IsA("Bone") then
				table.insert(state.chains, { upper = upper, lower = lower })
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
	-- d'origine rétablies, remplissages et effets détruits.
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
			state.fx.hem:Destroy()
			state.fx.body:Destroy()
			state.fx.tendrils.holder:Destroy()
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

	-- Cette méthode permet de régler et placer les effets de l'ombre à chaque frame lorsqu'un mortel voit une Mort :
	-- débit selon la part d'ombre, bouffée de déchirure quand le faisceau la révèle.
	local function renderFx(state, smoke: number, tearing: boolean)
		if not state.root or not state.bounds then
			-- Corps plus mesurable (racine ou pièces disparues) : rien ne doit continuer à fumer à l'ancienne place
			if state.fx then
				state.fx.wisps.Enabled = false
				state.fx.embers.Enabled = false
				setTendrils(state.fx.tendrils, false)
			end
			return
		end
		if not state.fx then
			state.fx = newShadowFx(fxFolder)
		end
		local fx = state.fx
		local rootCFrame = state.root.CFrame
		local hemOffset, hemSize = DeathLook.hemBox(state.bounds)
		local bodyOffset, bodySize = DeathLook.bodyBox(state.bounds)
		fx.hem.Size = hemSize
		fx.hem.CFrame = rootCFrame * CFrame.new(hemOffset)
		fx.body.Size = bodySize
		fx.body.CFrame = rootCFrame * CFrame.new(bodyOffset)
		local on = smoke > 0.01
		fx.wisps.Rate = RATES.wisps * smoke
		fx.embers.Rate = RATES.embers * smoke
		fx.wisps.Enabled = on
		fx.embers.Enabled = on
		renderTendrils(state, fx.tendrils, smoke)
		if tearing then
			fx.tear:Emit(TEAR_SMOKE)
			fx.embers:Emit(TEAR_EMBERS)
		end
		if state.visibility <= 0 and state.fxVisible then
			-- Disparue (ombre) : les fumées en vol disparaissent avec elle
			fx.wisps:Clear()
			fx.embers:Clear()
			fx.tear:Clear()
		end
		state.fxVisible = state.visibility > 0
	end

	-- Cette méthode permet de mettre à jour l'apparence de la Mort à chaque frame lorsqu'un joueur (ou un faux joueur)
	-- a ce rôle : fondus de visibilité et de révélation (Shared.DeathLook), puis corps, remplissages et effets.
	local function render(subject: Instance, character: Model, dt: number)
		local state = tracked[character]
		if not state then
			state = {
				view = if subject == localPlayer then View.Self else View.Mortal,
				character = character,
				highlights = {},
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
				-- Seul ce qui se dessine change le modèle (pas un son, un os, une soudure ni les remplissages de ce rendu)
				if
					d:IsA("BasePart")
					or d:IsA("Decal")
					or d:IsA("ParticleEmitter")
					or d:IsA("Model")
					or d:IsA("Accessory")
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
			if state.fx then
				for _, emitter in { state.fx.wisps, state.fx.embers, state.fx.tear } do
					emitter:Clear()
				end
			end
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
			or applied.tatters ~= layers.tatters
			or applied.modelSmoke ~= layers.modelSmoke
		then
			state.applied =
				{ body = layers.body, scythe = layers.scythe, tatters = layers.tatters, modelSmoke = layers.modelSmoke }
			applyTransparency(character, state, layers.body, layers.scythe, layers.tatters, layers.modelSmoke)
		end
		local shadowOn = layers.fill < 1
		for _, highlight in state.highlights do
			highlight.Enabled = shadowOn
			highlight.FillTransparency = layers.fill
			highlight.OutlineTransparency = layers.outline
		end
		if state.scytheHighlight then
			state.scytheHighlight.Enabled = false
		end
		renderFx(state, layers.smoke, tearing)
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
