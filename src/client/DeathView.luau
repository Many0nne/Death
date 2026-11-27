-- Rendu de la Mort (client), d'après les attributs du serveur (LightRole, DeathExposed, DeathInBeam) et les règles
-- pures de Shared.DeathLook (#80) :
-- - pour un mortel : invisible dans l'ombre ; exposée, une ombre pleine (remplissage sombre, contour léger) dont le bas
--   se défait en colonne de fumée, avec volutes et quelques braises claires, sans faux ; dans un faisceau de lampe,
--   l'ombre se déchire (bouffée de fumée) et laisse voir le vrai corps et la faux ;
-- - pour la Mort elle-même : son corps et sa faux restent visibles, voilés dans l'ombre, pleins à la lumière
--   (l'indicateur « ombre / lumière » est dans le HUD, Client.Hud) ;
-- - pour tous : la Mort ne fait aucun bruit de pas.
-- Indépendant du modèle : la faux est retrouvée par son nom (`Scythe`), le reste du corps est pris tel quel. Les
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
-- Remplissage du voile de la Mort sur elle-même (inchangé depuis #4)
local SELF_COLOR = Color3.fromRGB(0, 0, 0)
-- Ombre vue des mortels : noir bleuté plutôt que noir pur, contour gris violacé à peine visible
local SHADOW_COLOR = Color3.fromRGB(9, 8, 13)
local OUTLINE_COLOR = Color3.fromRGB(110, 98, 128)
-- Textures de particules fournies avec Roblox
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local EMBER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
-- Débit (particules par seconde) de chaque effet de l'ombre, pleine ombre
local RATES = { hem = 40, wisps = 14, embers = 6 }
-- Bouffées jouées quand l'ombre se déchire dans le faisceau
local TEAR_SMOKE = 30
local TEAR_EMBERS = 8

local DeathView = {}

-- Cette méthode permet de savoir si une instance fait partie de la faux lorsque le rendu sépare corps et faux.
local function inScythe(instance: Instance, scythe: Instance?): boolean
	return scythe ~= nil and (instance == scythe or instance:IsDescendantOf(scythe))
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
-- Highlight ne prend qu'un Model ou une BasePart, donc un par Model visible sans la faux, un par pièce visible ; on
-- descend dans le reste (dossier, accessoire, pièce invisible du rig, Model qui contient la faux).
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
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Accessory") or child:IsA("Folder") then
			collectGroups(child, scythe, out)
		end
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

-- Cette méthode permet de créer les effets de l'ombre (colonne de fumée du bas, volutes, braises, déchirure) lorsqu'un
-- mortel voit une Mort pour la première fois ; locaux à ce client, hors du personnage.
local function newShadowFx(folder: Instance)
	local hem = newVolume("ShadowHem", folder)
	local body = newVolume("ShadowBody", folder)
	local dark = ColorSequence.new(SHADOW_COLOR)
	return {
		hem = hem,
		body = body,
		-- Nuage épais au bas du corps, qui s'étale autour et traîne derrière la Mort qui glisse. Le remplissage
		-- (Highlight) se dessine par-dessus les particules : la fumée noie le bas de la silhouette par les côtés et
		-- derrière, elle ne peut pas le recouvrir (mesuré en jeu, ZOffset sans effet)
		hemSmoke = newEmitter(hem, {
			Name = "HemColumn",
			Texture = SMOKE_TEXTURE,
			Color = dark,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2),
				NumberSequenceKeypoint.new(0.5, 3.2),
				NumberSequenceKeypoint.new(1, 4.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0.6, 1.6),
			SpreadAngle = Vector2.new(80, 80),
			Acceleration = Vector3.new(0, 0.3, 0),
			Drag = 1.2,
		}),
		-- Volutes qui s'échappent de toute la silhouette : les bords ne sont jamais nets
		wisps = newEmitter(body, {
			Name = "Wisps",
			Texture = SMOKE_TEXTURE,
			Color = dark,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1.8) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
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
-- caché, un morceau ne projette plus d'ombre (qui le trahirait sous une lampe) et ses fumées s'arrêtent. Les valeurs
-- d'origine (CastShadow, ParticleEmitter.Enabled) sont relevées à la première écriture et rétablies ensuite (#78).
local function applyTransparency(character: Model, state, body: number, scythe: number)
	for _, d in character:GetDescendants() do
		local value = if inScythe(d, state.scythe) then scythe else body
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
			d.Enabled = state.emitters[d] and value < 1
			if value >= 1 then
				d:Clear()
			end
		end
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
		local color = if state.view == View.Self then SELF_COLOR else SHADOW_COLOR
		local outline = if state.view == View.Self then SELF_COLOR else OUTLINE_COLOR
		local groups = {}
		collectGroups(character, scythe, groups)
		state.highlights = {}
		for _, group in groups do
			table.insert(state.highlights, newHighlight(group, color, outline))
		end
		state.scytheHighlight = if scythe then newHighlight(scythe, color, outline) else nil
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		state.root = if root and root:IsA("BasePart") then root else nil
		state.bounds = nil
		if state.root then
			local boxes = {}
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 and not inScythe(d, scythe) then
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
		fx.hemSmoke.Rate = RATES.hem * smoke
		fx.wisps.Rate = RATES.wisps * smoke
		fx.embers.Rate = RATES.embers * smoke
		fx.hemSmoke.Enabled = on
		fx.wisps.Enabled = on
		fx.embers.Enabled = on
		if tearing then
			fx.tear:Emit(TEAR_SMOKE)
			fx.embers:Emit(TEAR_EMBERS)
		end
		if state.visibility <= 0 and state.fxVisible then
			-- Disparue (ombre) : les fumées en vol disparaissent avec elle
			fx.hemSmoke:Clear()
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
				highlights = {},
				visibility = 0,
				reveal = 0,
				revealTarget = 0,
				muted = {},
				castShadow = {},
				emitters = {},
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
		local position = if state.root then state.root.Position else nil
		if DeathLook.jumped(state.position, position) then
			-- Dissipée et reformée ailleurs : rien ne doit trahir l'endroit où elle reparaît, les fondus repartent de zéro
			state.visibility, state.reveal, state.revealTarget = 0, 0, 0
			if state.fx then
				for _, emitter in { state.fx.hemSmoke, state.fx.wisps, state.fx.embers, state.fx.tear } do
					emitter:Clear()
				end
			end
		end
		state.position = position
		local exposed = subject:GetAttribute(LA.Exposed) == true
		local mode = DeathLook.mode(state.view, exposed, subject:GetAttribute(LA.InBeam) == true)
		local visibilityTarget, revealTarget = DeathLook.targets(mode, exposed)
		state.visibility =
			DeathLook.approach(state.visibility, visibilityTarget, DeathLook.FADE_TIME, DeathLook.FADE_TIME, dt)
		state.reveal = DeathLook.approach(state.reveal, revealTarget, DeathLook.REVEAL_TIME, DeathLook.CLOSE_TIME, dt)
		local tearing = revealTarget > state.revealTarget and state.visibility > 0
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
		if not applied or applied.body ~= layers.body or applied.scythe ~= layers.scythe then
			state.applied = { body = layers.body, scythe = layers.scythe }
			applyTransparency(character, state, layers.body, layers.scythe)
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
