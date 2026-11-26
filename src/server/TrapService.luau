-- Service des pièges (serveur) : tient l'état des points fragiles (Shared.Traps), crée les invites de la Mort
-- (préparer ou désarmer, souffler) et des mortels (examiner, désamorcer), joue les bruits de préparation, l'indice
-- visuel intermittent des pièges armés et les accidents (carrelage, étagère, lustre), met les mortels touchés en
-- agonie (MatchService:down) et signale la buée aux mortels proches d'un piège armé. Remise à zéro à chaque manche.
--
-- API pour les étapes suivantes (dissipation #8, âmes, HUD #9), via `TrapService.get()` :
--   :removeBreathCharge()   la Mort perd une charge (dissipée par la lampe torche) ; (true) ou (false, raison)
--   :refillBreath()         souffle plein (âme récoltée)
--   :breath()               charges, fin de recharge (horloge du serveur) ; aussi en attributs (Shared.TrapAttributes)
-- Événement : Triggered({ id, kind, victims }) après chaque accident.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared.DeathRules)
local HouseGeometry = require(Shared.HouseGeometry)
local HouseLayout = require(Shared.HouseLayout)
local HouseStyle = require(Shared.HouseStyle)
local LightAttributes = require(Shared.LightAttributes)
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local Signal = require(Shared.Signal)
local TrapAttributes = require(Shared.TrapAttributes)
local Traps = require(Shared.Traps)

local LA = LightAttributes
local TA = TrapAttributes
local Role = DeathRules.Role
local State = Traps.State

local TrapService = {}
TrapService.__index = TrapService

-- Touches des invites : préparer/désarmer et désamorcer sur F, souffler sur Q, examiner sur E (celle des invites par
-- défaut, comme rétablir le courant) ; décalage vertical des bulles d'un même objet
local KEYS = {
	work = { key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY },
	blow = { key = Enum.KeyCode.Q, pad = Enum.KeyCode.ButtonR1 },
	examine = { key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX },
	defuse = { key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY },
}
local PROMPT_SPACING = 80

-- Bruit de préparation selon la taille (docs/design.md) : presque rien, grincement à environ 15 m, bruit fort entendu
-- dans les pièces voisines. Sons provisoires fournis avec le client Roblox, en boucle pendant le maintien.
local NOISE = {
	Small = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.15, speed = 1.6, rollOff = 10 },
	Medium = {
		id = "rbxasset://sounds/action_footsteps_plastic.mp3",
		volume = 0.8,
		speed = 0.3,
		rollOff = math.floor(15 * Traps.STUDS_PER_METER),
	},
	Large = { id = "rbxasset://sounds/action_swim.mp3", volume = 1.2, speed = 0.35, rollOff = 110 },
}
-- Bruit de l'accident (entendu de loin : tout le monde sait qu'un piège vient de tomber)
local CRASH = {
	WetFloor = { id = "rbxasset://sounds/action_falling.ogg", volume = 0.8, speed = 1, rollOff = 40 },
	Shelf = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.8, speed = 0.7, rollOff = 90 },
	Chandelier = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 1, speed = 1.1, rollOff = 120 },
}
-- Indice visuel intermittent d'un piège armé : eau qui suinte, vis qui tombent, étincelles
local CUE = {
	WetFloor = { color = Color3.fromRGB(150, 190, 220), size = 0.25, speed = 1, rate = 30, spread = 180 },
	Shelf = { color = Color3.fromRGB(150, 150, 150), size = 0.12, speed = 2, rate = 25, spread = 30 },
	Chandelier = { color = Color3.fromRGB(255, 210, 120), size = 0.18, speed = 6, rate = 60, spread = 180 },
}
-- Durée d'un signe de l'indice visuel (émetteur allumé) et d'une chute d'objet (secondes)
local CUE_PULSE = 0.3
local FALL_TIME = 0.6
-- Fréquence des contrôles périodiques : buée, indices, recharge publiée (secondes)
local STEP_PERIOD = 0.2

export type Deps = {
	house: Instance,
	match: any?, -- MatchService : down(player), MatchStarted, PhaseChanged
	-- LightService : canPrepareAt(position) (point du piège dans l'ombre), breakLamp(lampId) quand le lustre tombe
	lights: any?,
	layout: any?, -- description de la maison (Shared.HouseLayout) : orientation des meubles
	players: any, -- service Players : GetPlayers, PlayerAdded
	isStudio: boolean,
	roleOf: (any) -> string?, -- rôle effectif (attribut LightRole)
	isExposed: (any) -> boolean, -- la Mort est éclairée (attribut DeathExposed)
	clock: () -> number,
	serverTime: () -> number, -- horloge partagée avec les clients (workspace:GetServerTimeNow)
	-- branche Triggered, PromptButtonHoldBegan et PromptButtonHoldEnded d'une invite (joueur en argument)
	connectPrompt: (any, (any) -> (), (any) -> (), (any) -> ()) -> (),
	delay: (number, () -> ()) -> (),
	-- joue une animation de `duration` secondes : appelle step(alpha) de 0 à 1
	animate: (number, (number) -> ()) -> (),
	lineOfSight: (any, Vector3, Vector3, Instance) -> boolean,
	notify: (any, string) -> (),
	play: (any) -> (), -- Sound:Play
	stop: (any) -> (), -- Sound:Stop
	random: () -> number, -- tirage dans [0, 1[
	heartbeat: any?,
	log: (string) -> (),
	warn: (string) -> (),
}

-- Cette méthode permet de construire les dépendances réelles (services Roblox) lorsque le service est créé en jeu.
local function defaultDeps(): Deps
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local HouseBuilder = require(script.Parent.HouseBuilder)
	local house = workspace:FindFirstChild(HouseBuilder.MODEL_NAME)
	if not house then
		error("TrapService : maison introuvable, HouseBuilder.build doit passer avant")
	end
	-- Chargé ici : il lit le service Players, absent des tests Lune
	local LineOfSight = require(Shared.LineOfSight)
	local notice = Instance.new("RemoteEvent")
	notice.Name = TA.NoticeEvent
	notice.Parent = ReplicatedStorage
	local rng = Random.new()

	-- Cette méthode permet de jouer une animation image par image lorsque un objet tombe (étagère, lustre).
	local function animate(duration: number, step: (number) -> ())
		task.spawn(function()
			local t = 0
			while t < duration do
				t += RunService.Heartbeat:Wait()
				step(math.min(t / duration, 1))
			end
		end)
	end

	return {
		house = house,
		match = require(script.Parent.MatchService).get(),
		lights = require(script.Parent.LightService).get(),
		layout = HouseLayout,
		players = Players,
		isStudio = RunService:IsStudio(),
		-- Cette méthode permet de lire le rôle répliqué d'un joueur lorsqu'il agit sur un piège.
		roleOf = function(player)
			return player:GetAttribute(LA.LightRole)
		end,
		-- Cette méthode permet de savoir si la Mort est éclairée lorsqu'elle veut agir sur un piège.
		isExposed = function(player)
			return player:GetAttribute(LA.Exposed) == true
		end,
		clock = os.clock,
		-- Cette méthode permet de lire l'horloge partagée avec les clients lorsque la fin de recharge est publiée.
		serverTime = function()
			return workspace:GetServerTimeNow()
		end,
		-- Cette méthode permet de brancher une invite lorsqu'elle est créée : début et fin du maintien, déclenchement.
		connectPrompt = function(prompt, onTriggered, onHoldBegan, onHoldEnded)
			prompt.PromptButtonHoldBegan:Connect(onHoldBegan)
			prompt.PromptButtonHoldEnded:Connect(onHoldEnded)
			prompt.Triggered:Connect(onTriggered)
		end,
		-- Cette méthode permet de différer une action (fin d'un signe d'indice) lorsque le service la programme.
		delay = function(seconds, fn)
			task.delay(seconds, fn)
		end,
		animate = animate,
		-- Cette méthode permet de vérifier que rien ne cache la cible lorsqu'une invite est déclenchée.
		lineOfSight = function(_player, from, to, target)
			return LineOfSight.clear(from, to, target)
		end,
		-- Cette méthode permet d'envoyer un message bref à un seul joueur lorsqu'une action réussit ou est refusée.
		notify = function(player, text)
			notice:FireClient(player, text)
		end,
		-- Cette méthode permet de jouer un son lorsqu'une préparation commence ou qu'un piège tombe.
		play = function(sound)
			sound:Play()
		end,
		-- Cette méthode permet d'arrêter un son lorsque la préparation s'interrompt.
		stop = function(sound)
			sound:Stop()
		end,
		-- Cette méthode permet de tirer un nombre dans [0, 1[ lorsque le prochain indice visuel est programmé.
		random = function()
			return rng:NextNumber()
		end,
		heartbeat = RunService.Heartbeat,
		-- Cette méthode permet d'écrire un message des pièges dans la sortie lorsque leur état change.
		log = function(message)
			print("[Pièges] " .. message)
		end,
		-- Cette méthode permet de signaler un refus ou une anomalie des pièges dans la sortie.
		warn = function(message)
			warn("[Pièges] " .. message)
		end,
	}
end

-- Cette méthode permet de trouver l'identifiant d'un point fragile lorsque le service lit la maison : AnchorId du
-- carrelage, LampId du lustre, sinon le nom du meuble.
local function trapId(part: BasePart): string
	local id = part:GetAttribute(MapTags.Attributes.AnchorId) or part:GetAttribute(MapTags.Attributes.LampId)
	if type(id) == "string" then
		return id
	end
	return if part.Parent and part.Parent:IsA("Model") then part.Parent.Name else part.Name
end

-- Avant d'un meuble selon son orientation (HouseGeometry.propFacing) : nord = +Z, est = +X
local FACING_VECTORS = {
	North = Vector3.new(0, 0, 1),
	South = Vector3.new(0, 0, -1),
	East = Vector3.new(1, 0, 0),
	West = Vector3.new(-1, 0, 0),
}

-- Cette méthode permet de donner l'orientation de chaque étagère piège lorsque le service lit la maison : la même que
-- celle de ses blocs (HouseGeometry.propFacing, orientation imposée par la description sinon dos au mur le plus proche).
function TrapService.shelfFacings(layout): { [string]: string }
	local rooms = HouseGeometry.roomsById(layout)
	local facings = {}
	for _, prop in layout.props do
		local room = rooms[prop.room]
		if prop.trap == MapTags.TrapKinds.Shelf and room then
			facings[prop.id] =
				HouseGeometry.propFacing(layout, room, prop.x, prop.z, prop.size[1], prop.size[3], prop.facing)
		end
	end
	return facings
end

-- Cette méthode permet de créer le service sur une maison construite lorsqu'on veut l'instance du jeu (`get`) ou un
-- service isolé en test ; les points fragiles sont lus par leur tag (MapTags.TrapCandidate).
function TrapService.new(deps: Deps?)
	local d = deps or defaultDeps()
	local rooms = {}
	local candidates = {}
	for _, part in d.house:GetDescendants() do
		if part:HasTag(MapTags.Room) and part:IsA("BasePart") then
			rooms[part:GetAttribute(MapTags.Attributes.RoomId)] = part
		elseif part:HasTag(MapTags.TrapCandidate) and part:IsA("BasePart") then
			table.insert(candidates, part)
		end
	end
	local facings = TrapService.shelfFacings(d.layout or HouseLayout)
	local kinds = {}
	local entries = {}
	for _, part in candidates do
		local id = trapId(part)
		local kind = part:GetAttribute(MapTags.Attributes.TrapKind)
		if kinds[id] then
			d.warn("point fragile en double : " .. id)
		elseif not Traps.KINDS[kind] then
			d.warn(string.format("point fragile %s : type inconnu %s", id, tostring(kind)))
		else
			kinds[id] = kind
			local room = rooms[part:GetAttribute(MapTags.Attributes.RoomId)]
			entries[id] = TrapService._describe(id, kind, part, room, facings[id])
		end
	end
	return setmetatable({
		deps = d,
		started = false,
		rules = Traps.new(kinds),
		entries = entries, -- id -> { id, kind, part, floor, front?, prompts, ... }
		prompts = {} :: { any }, -- { prompt, action, entry, role }
		holds = {} :: { [any]: { [any]: number } }, -- invite -> joueur -> début du maintien
		-- invite -> joueur à qui le refus a déjà été annoncé au début du maintien
		refused = {} :: { [any]: { [any]: boolean } },
		nextCue = {} :: { [string]: number }, -- piège armé -> prochain indice visuel (horloge)
		-- Clés faibles : un joueur parti ne reste pas en mémoire
		chilled = setmetatable({}, { __mode = "k" }) :: any,
		published = setmetatable({}, { __mode = "k" }) :: any, -- joueur Mort -> souffle publié
		elapsed = 0,
		Triggered = Signal.new(),
	}, TrapService)
end

-- Cette méthode permet de décrire un point fragile lorsque le service le découvre : point au sol (zone touchée, buée),
-- direction de chute de l'étagère (son avant, `facing`) et blocs qui tombent (positions lues par CFrame, cf. tests).
function TrapService._describe(id: string, kind: string, part: BasePart, room: BasePart?, facing: string?)
	local pos = part.CFrame.Position
	local roomPos = room and room.CFrame.Position
	local floorY = if room and roomPos then roomPos.Y - room.Size.Y / 2 else pos.Y - part.Size.Y / 2
	local entry = {
		id = id,
		kind = kind,
		part = part,
		floor = Vector3.new(pos.X, floorY, pos.Z),
		front = nil :: Vector3?,
		-- Volume de la pièce (centre, taille) : victimes et buée seulement dedans
		zone = if room and roomPos then { center = roomPos, size = room.Size } else nil,
		moving = {} :: { BasePart }, -- blocs qui tombent (étagère : tout le meuble ; lustre : lampe et habillage)
		origins = {} :: { [BasePart]: CFrame },
	}
	if kind == MapTags.TrapKinds.Shelf then
		entry.front = FACING_VECTORS[facing or "North"]
		local model = part.Parent
		if model and model:IsA("Model") then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(entry.moving, d)
				end
			end
		end
	elseif kind == MapTags.TrapKinds.Chandelier and part.Parent then
		-- Le lustre et son habillage (tige, bras, coupelles) : noms exacts de HouseStyle.fixture, préfixés par la lampe
		local names = { [id] = true }
		for _, fixture in HouseStyle.fixture("Chandelier", { 1, 1, 1 }, 1, 0) do
			names[id .. fixture.name] = true
		end
		for _, sibling in part.Parent:GetChildren() do
			if sibling:IsA("BasePart") and names[sibling.Name] then
				table.insert(entry.moving, sibling)
			end
		end
	end
	return entry
end

local instance = nil

-- Cette méthode permet de récupérer le service des pièges du serveur lorsqu'un autre module (lampe torche, âmes, HUD)
-- doit agir sur le souffle ; il est créé au premier appel, sur la maison du Workspace.
function TrapService.get()
	if not instance then
		instance = TrapService.new()
	end
	return instance
end

-- Cette méthode permet de créer invites, sons et indices puis d'écouter manche, joueurs et frames lorsque le serveur
-- démarre (une seule fois).
function TrapService:start()
	if self.started then
		return
	end
	self.started = true
	local ids = {}
	for id in self.entries do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		self:_setup(self.entries[id])
	end
	self:_refreshPrompts()
	local match = self.deps.match
	if match then
		match.MatchStarted:Connect(function()
			self:reset()
		end)
		match.PhaseChanged:Connect(function(phase)
			if phase == Match.Phase.Waiting then
				self:reset()
			end
		end)
	end
	local players = self.deps.players
	if players and self.deps.isStudio then
		for _, player in players:GetPlayers() do
			self:_watchPlayer(player)
		end
		players.PlayerAdded:Connect(function(player)
			self:_watchPlayer(player)
		end)
	end
	if self.deps.heartbeat then
		self.deps.heartbeat:Connect(function(dt)
			self.elapsed += dt
			if self.elapsed >= STEP_PERIOD then
				self.elapsed = 0
				self:step()
			end
		end)
	end
	self.deps.log(string.format("%d points fragiles", #ids))
end

-- Lecture et API ---------------------------------------------------------------------------------------------------

-- Cette méthode permet de lire le souffle lorsque le HUD ou un test en a besoin : charges, puis fin de la recharge en
-- cours sur l'horloge du serveur (nil quand le souffle est plein).
function TrapService:breath(): (number, number?)
	local now = self.deps.clock()
	local charges, at = self.rules:breath(now)
	return charges, if at then self.deps.serverTime() + (at - now) else nil
end

-- Cette méthode permet de retirer une charge de souffle lorsque la Mort est dissipée par une lampe torche (#8) ;
-- renvoie (true) ou (false, raison).
function TrapService:removeBreathCharge(): (boolean, string?)
	local ok, err = self.rules:spendCharge(self.deps.clock())
	if ok then
		self:_changed()
	end
	return ok, err
end

-- Cette méthode permet de remplir le souffle lorsque la Mort récolte une âme.
function TrapService:refillBreath()
	self.rules:refillBreath()
	self:_changed()
end

-- Cette méthode permet de tout remettre en place (objets relevés, pièges inoffensifs, souffle plein) lorsqu'une manche
-- commence ou se termine.
function TrapService:reset()
	self.rules:reset()
	table.clear(self.nextCue)
	for _, entry in self.entries do
		self:_restore(entry)
	end
	self:_changed()
end

-- Actions --------------------------------------------------------------------------------------------------------

-- Cette méthode permet de faire une étape de préparation lorsque la Mort a tenu l'invite (ou par debug) ; le piège armé
-- commence ses indices visuels. Renvoie (true, nil, état) ou (false, raison).
function TrapService:prepare(id: string): (boolean, string?, string?)
	local ok, err, state = self.rules:prepare(id)
	if not ok then
		return false, err
	end
	if state == State.Armed then
		self:_scheduleCue(id)
	end
	self.deps.log(string.format("%s : %s", id, tostring(state)))
	self:_changed()
	return true, nil, state
end

-- Cette méthode permet à la Mort de désarmer un de ses pièges lorsqu'elle veut le replacer ; (true) ou (false, raison).
function TrapService:disarm(id: string): (boolean, string?)
	local ok, err = self.rules:disarm(id)
	if ok then
		self.nextCue[id] = nil
		self.deps.log(id .. " : désarmé par la Mort")
		self:_changed()
	end
	return ok, err
end

-- Cette méthode permet à un mortel de désamorcer un objet lorsqu'il a tenu l'invite ; (true) si un piège a été
-- désamorcé, (false, raison) sinon.
function TrapService:defuse(id: string): (boolean, string?)
	local ok, err = self.rules:defuse(id)
	if ok then
		self.nextCue[id] = nil
		self.deps.log(id .. " : désamorcé")
		self:_changed()
	end
	return ok, err
end

-- Cette méthode permet de déclencher un piège armé par le souffle lorsque la Mort le décide : charge dépensée, objet qui
-- tombe, mortels touchés en agonie. Renvoie (true, nil, victimes) ou (false, raison).
function TrapService:blow(id: string): (boolean, string?, { any }?)
	local ok, err = self.rules:blow(id, self.deps.clock())
	if not ok then
		return false, err
	end
	self.nextCue[id] = nil
	local entry = self.entries[id]
	local victims = self:_victims(entry)
	self:_accident(entry)
	local match = self.deps.match
	for _, player in victims do
		local down, reason = false, "aucune manche"
		if match then
			down, reason = match:down(player)
		end
		if not down then
			self.deps.warn(string.format("%s : %s pas mis en agonie (%s)", id, player.Name, tostring(reason)))
		end
	end
	local names = {}
	for _, player in victims do
		table.insert(names, player.Name)
	end
	self.deps.log(
		string.format(
			"%s déclenché : %s",
			id,
			if #names > 0 then table.concat(names, ", ") .. " touché(s)" else "personne"
		)
	)
	self:_changed()
	self.Triggered:Fire({ id = id, kind = entry.kind, victims = victims })
	return true, nil, victims
end

-- Cette méthode permet de lister les mortels touchés par un accident lorsque le piège se déclenche (rôle mortel,
-- personnage dans la pièce du piège et dans la zone de Traps.hits).
function TrapService:_victims(entry): { any }
	local victims = {}
	for _, player in self.deps.players:GetPlayers() do
		if self.deps.roleOf(player) == Role.Mortal then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local pos = root and root.CFrame.Position
			if
				pos
				and (entry.zone == nil or Traps.inZone(entry.zone.center, entry.zone.size, pos))
				and Traps.hits(entry.kind, entry.floor, pos, entry.front, entry.part.Size)
			then
				table.insert(victims, player)
			end
		end
	end
	return victims
end

-- Effets dans la maison ------------------------------------------------------------------------------------------

-- Cette méthode permet de créer un son attaché à un objet lorsque le service démarre (bruit de préparation, accident).
local function makeSound(parent: Instance, name: string, spec, looped: boolean)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = spec.rollOff
	sound.Parent = parent
	return sound
end

-- Cette méthode permet de préparer un point fragile lorsque le service démarre : sons, émetteur de l'indice visuel,
-- position d'origine des objets qui tombent, puis ses quatre invites.
function TrapService:_setup(entry)
	local part = entry.part
	local spec = Traps.KINDS[entry.kind]
	entry.noise = makeSound(part, "TrapNoise", NOISE[spec.size], true)
	entry.crash = makeSound(part, "TrapCrash", CRASH[entry.kind], false)
	local cue = CUE[entry.kind]
	local attachment = Instance.new("Attachment")
	attachment.Name = "TrapCue"
	if entry.kind == MapTags.TrapKinds.Shelf then
		-- Vis qui tombent du haut du meuble, devant lui
		attachment.Position = Vector3.new(0, part.Size.Y / 2 - 0.3, 0) + (entry.front or Vector3.zero) * 0.5
	elseif entry.kind == MapTags.TrapKinds.Chandelier then
		attachment.Position = Vector3.new(0, -part.Size.Y / 2, 0)
	end
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "TrapCue"
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(cue.color)
	emitter.Size = NumberSequence.new(cue.size)
	emitter.Speed = NumberRange.new(cue.speed * 0.5, cue.speed)
	emitter.SpreadAngle = Vector2.new(cue.spread, cue.spread)
	emitter.Rate = cue.rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.LightEmission = if entry.kind == MapTags.TrapKinds.Chandelier then 1 else 0
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Parent = attachment
	entry.cue = emitter
	entry.look = {
		material = part.Material,
		color = part.Color,
		transparency = part.Transparency,
		reflectance = part.Reflectance,
		canQuery = part.CanQuery,
	}
	for _, moving in entry.moving do
		entry.origins[moving] = moving.CFrame
	end

	local label = spec.label
	-- Le lustre porte déjà l'invite « Griller l'ampoule » au centre : bulles des pièges écartées d'une bulle entière
	local gap = if entry.kind == MapTags.TrapKinds.Chandelier then PROMPT_SPACING else PROMPT_SPACING / 2
	self:_makePrompt(entry, "work", Role.Death, {
		ObjectText = label,
		KeyboardKeyCode = KEYS.work.key,
		GamepadKeyCode = KEYS.work.pad,
		MaxActivationDistance = Traps.INTERACT_DISTANCE,
		UIOffset = Vector2.new(0, -gap),
	})
	self:_makePrompt(entry, "blow", Role.Death, {
		ActionText = "Souffler",
		ObjectText = label,
		KeyboardKeyCode = KEYS.blow.key,
		GamepadKeyCode = KEYS.blow.pad,
		HoldDuration = 0,
		MaxActivationDistance = Traps.BREATH_DISTANCE,
		UIOffset = Vector2.new(0, gap),
	})
	self:_makePrompt(entry, "examine", Role.Mortal, {
		ActionText = "Examiner",
		ObjectText = label,
		KeyboardKeyCode = KEYS.examine.key,
		GamepadKeyCode = KEYS.examine.pad,
		HoldDuration = Traps.EXAMINE_HOLD,
		MaxActivationDistance = Traps.INTERACT_DISTANCE,
		UIOffset = Vector2.new(0, -gap),
	})
	self:_makePrompt(entry, "defuse", Role.Mortal, {
		ActionText = "Désamorcer",
		ObjectText = label,
		KeyboardKeyCode = KEYS.defuse.key,
		GamepadKeyCode = KEYS.defuse.pad,
		HoldDuration = spec.defuse,
		MaxActivationDistance = Traps.INTERACT_DISTANCE,
		UIOffset = Vector2.new(0, gap),
	})
end

-- Cette méthode permet de programmer le prochain indice visuel d'un piège armé lorsque il vient d'être armé ou qu'un
-- signe vient d'être joué (toutes les 8 à 10 s).
function TrapService:_scheduleCue(id: string)
	self.nextCue[id] = self.deps.clock() + Traps.CUE_MIN + self.deps.random() * (Traps.CUE_MAX - Traps.CUE_MIN)
end

-- Cette méthode permet de jouer un signe de l'indice visuel lorsque son heure est venue : l'émetteur s'allume un court
-- instant (Enabled se réplique, contrairement à Emit appelé par le serveur).
function TrapService:_pulseCue(entry)
	local emitter = entry.cue
	if not emitter then
		return
	end
	emitter.Enabled = true
	self.deps.delay(CUE_PULSE, function()
		emitter.Enabled = false
	end)
end

-- Cette méthode permet de jouer la chute d'un piège déclenché lorsque le souffle le déclenche : flaque visible qui
-- glisse, étagère qui bascule en avant, lustre qui s'écrase et s'éteint.
function TrapService:_accident(entry)
	self.deps.stop(entry.noise)
	self.deps.play(entry.crash)
	if entry.kind == MapTags.TrapKinds.WetFloor then
		local part = entry.part
		part.Transparency = 0.35
		part.Material = Enum.Material.Glass
		part.Color = Color3.fromRGB(120, 150, 170)
		part.Reflectance = 0.3
		-- Une flaque visible ne doit pas cacher une cible basse (LineOfSight ne traverse que l'invisible)
		part.CanQuery = false
	elseif entry.kind == MapTags.TrapKinds.Shelf then
		-- Le volume invisible du meuble (non tourné) donne ses dimensions ; pivot sur l'arête basse avant : le meuble
		-- bascule de 90° vers la pièce
		local origin = entry.origins[entry.part] or entry.part.CFrame
		local size = entry.part.Size
		local front = entry.front or Vector3.new(0, 0, 1)
		local depth = if math.abs(front.X) > 0 then size.X else size.Z
		local hinge = Vector3.new(origin.Position.X, origin.Position.Y - size.Y / 2, origin.Position.Z)
			+ front * (depth / 2)
		local axis = Vector3.new(0, 1, 0):Cross(front)
		local token = {}
		entry.fall = token
		self.deps.animate(FALL_TIME, function(alpha)
			-- Remise à zéro pendant la chute : l'animation s'arrête, l'objet reste relevé
			if entry.fall ~= token then
				return
			end
			local angle = (math.pi / 2) * alpha * alpha
			local turn = CFrame.new(hinge) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-hinge)
			for _, moving in entry.moving do
				moving.CFrame = turn * entry.origins[moving]
			end
		end)
	elseif entry.kind == MapTags.TrapKinds.Chandelier then
		local drop = entry.part.CFrame.Position.Y - entry.floor.Y - entry.part.Size.Y / 2
		local token = {}
		entry.fall = token
		self.deps.animate(FALL_TIME, function(alpha)
			if entry.fall ~= token then
				return
			end
			local offset = Vector3.new(0, -drop * alpha * alpha, 0)
			for _, moving in entry.moving do
				moving.CFrame = entry.origins[moving] + offset
			end
		end)
		if self.deps.lights then
			self.deps.lights:breakLamp(entry.id)
		end
	end
end

-- Cette méthode permet de remettre un objet à sa place d'origine lorsque la manche est remise à zéro.
function TrapService:_restore(entry)
	entry.fall = nil
	entry.noiseHolder = nil
	entry.preparer = nil
	self.deps.stop(entry.noise)
	if entry.cue then
		entry.cue.Enabled = false
	end
	for part, cframe in entry.origins do
		part.CFrame = cframe
	end
	if entry.kind == MapTags.TrapKinds.WetFloor then
		local part = entry.part
		local look = entry.look
		if look then
			part.Transparency = look.transparency
			part.Reflectance = look.reflectance
			part.CanQuery = look.canQuery
			part.Material = look.material
			part.Color = look.color
		end
	end
end

-- Invites --------------------------------------------------------------------------------------------------------

-- Cette méthode permet de créer une invite réservée à un rôle sur un point fragile lorsque le service démarre ; chaque
-- client la filtre comme celles de la lumière (Client.LightPrompts : rôle, disponibilité, vue, regard).
function TrapService:_makePrompt(entry, action: string, role: string, props: { [string]: any })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TA.PromptName
	-- Masquée jusqu'à la décision du client (#19). Pas de PromptState : un LightRole « Mortal » est déjà un mortel vivant
	-- en manche, et le bac à sable de Studio (hors manche) garde ses invites
	prompt.Enabled = false
	prompt.RequiresLineOfSight = false
	for property, value in props do
		(prompt :: any)[property] = value
	end
	prompt:SetAttribute(LA.PromptRole, role)
	prompt:SetAttribute(LA.PromptAvailable, false)
	prompt:SetAttribute(LA.PromptSight, true)
	prompt:AddTag(LA.PromptTag)
	prompt.Parent = entry.part
	local item = { prompt = prompt, action = action, entry = entry, role = role }
	table.insert(self.prompts, item)
	local holds = setmetatable({}, { __mode = "k" })
	self.holds[prompt] = holds
	self.refused[prompt] = setmetatable({}, { __mode = "k" })
	self.deps.connectPrompt(prompt, function(player)
		self:_onPrompt(player, item)
	end, function(player)
		holds[player] = self.deps.clock()
		self:_onHoldBegan(player, item)
	end, function(player)
		self:_onHoldEnded(player, item)
	end)
	return prompt
end

-- Cette méthode permet de publier ce que chaque invite permet maintenant lorsque l'état des pièges ou le souffle
-- change ; l'invite de travail de la Mort devient « Préparer (étape) » ou « Désarmer ».
function TrapService:_refreshPrompts()
	local now = self.deps.clock()
	for _, item in self.prompts do
		local trap = self.rules:get(item.entry.id)
		local prompt = item.prompt
		local available = false
		if item.action == "work" then
			local step = self.rules:nextStepDuration(item.entry.id)
			if step then
				local steps = #Traps.KINDS[trap.kind].steps
				prompt.ActionText = if steps > 1
					then string.format("Préparer (%d/%d)", trap.step + 1, steps)
					else "Préparer"
				prompt.HoldDuration = step
				available = true
			elseif trap.state == State.Armed then
				prompt.ActionText = "Désarmer"
				prompt.HoldDuration = Traps.DISARM_HOLD
				available = true
			end
		elseif item.action == "blow" then
			-- Grand piège commencé : la touche du souffle sert à l'abandonner (sa place dans la limite est rendue)
			if trap.state == State.Preparing then
				prompt.ActionText = "Abandonner"
				prompt.HoldDuration = Traps.DISARM_HOLD
				available = true
			else
				prompt.ActionText = "Souffler"
				prompt.HoldDuration = 0
				available = (self.rules:canBlow(item.entry.id, now))
			end
		else
			-- Examiner et désamorcer ne révèlent rien : possibles sur tout objet encore en place
			available = trap.state ~= State.Spent
		end
		prompt:SetAttribute(LA.PromptAvailable, available)
	end
end

-- Cette méthode permet de savoir si la Mort peut préparer ou désarmer ce point lorsqu'elle maintient l'invite : ni
-- éclairée, ni sur un piège éclairé, et selon la limite de pièges ; renvoie aussi la raison d'un refus.
function TrapService:_canWork(player, id: string): (boolean, string?)
	if self.deps.isExposed(player) then
		return false, "dans la lumière, impossible d'agir sur un piège"
	end
	local trap = self.rules:get(id)
	if trap and trap.state == State.Armed then
		return true
	end
	local ok, err = self.rules:canPrepare(id)
	if not ok then
		return false, err
	end
	-- Le piège lui-même doit être dans l'ombre (lustre allumé, cuisine éclairée) : éteindre d'abord
	local lights = self.deps.lights
	local entry = self.entries[id]
	if lights and entry and not lights:canPrepareAt(entry.floor + Vector3.new(0, 1, 0)) then
		return false, "ce piège est dans la lumière : éteindre d'abord"
	end
	return true
end

-- Cette méthode permet de réagir au début d'un maintien lorsqu'un joueur commence une action : refus annoncé tout de
-- suite (lumière, limite), bruit de préparation lancé sinon.
function TrapService:_onHoldBegan(player, item)
	local refusedSet = self.refused[item.prompt]
	if refusedSet then
		refusedSet[player] = nil
	end
	if item.entry.preparer == player then
		item.entry.preparer = nil
	end
	if item.action ~= "work" or self.deps.roleOf(player) ~= Role.Death then
		return
	end
	local ok, err = self:_canWork(player, item.entry.id)
	if not ok then
		self.deps.notify(player, tostring(err))
		local refused = self.refused[item.prompt]
		if refused then
			refused[player] = true
		end
		return
	end
	if self.rules:nextStepDuration(item.entry.id) then
		item.entry.noiseHolder = player
		item.entry.preparer = player
		self.deps.play(item.entry.noise)
	end
end

-- Cette méthode permet d'arrêter le bruit de préparation lorsque la Mort lâche l'invite (ou la termine).
function TrapService:_onHoldEnded(player, item)
	if item.action == "work" and player == item.entry.noiseHolder then
		item.entry.noiseHolder = nil
		self.deps.stop(item.entry.noise)
	end
end

-- Cette méthode permet d'exécuter l'action d'une invite lorsqu'un joueur la déclenche, après contrôle du rôle, du
-- maintien, de la distance et de la vue depuis le personnage : le client n'est jamais cru sur parole.
function TrapService:_onPrompt(player, item)
	if self.deps.roleOf(player) ~= item.role then
		return
	end
	local entry = item.entry
	-- Une préparation n'aboutit que si son maintien a commencé avec le bruit (jamais de piège armé en silence)
	local prepared = entry.preparer == player
	if item.action == "work" then
		if entry.noiseHolder == player then
			entry.noiseHolder = nil
			self.deps.stop(entry.noise)
		end
		if prepared then
			entry.preparer = nil
		end
	end
	local refusedSet = self.refused[item.prompt]
	local announced = refusedSet and refusedSet[player] == true
	if refusedSet then
		refusedSet[player] = nil
	end
	local holds = self.holds[item.prompt]
	local began = holds[player]
	holds[player] = nil
	local elapsed = if began then self.deps.clock() - began else nil
	if not DeathRules.isHoldValid(elapsed, item.prompt.HoldDuration) then
		self.deps.warn(string.format("%s : %s refusé, maintien invalide", player.Name, item.action))
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local from = root.CFrame.Position
	local part = item.entry.part
	local target = part.CFrame.Position
	if (target - from).Magnitude > item.prompt.MaxActivationDistance + DeathRules.DISTANCE_TOLERANCE then
		self.deps.warn(string.format("%s : %s refusé, trop loin", player.Name, item.action))
		return
	end
	if not self.deps.lineOfSight(player, from, target, part) then
		self.deps.warn(string.format("%s : %s refusé, cible hors de vue", player.Name, item.action))
		return
	end
	local id = item.entry.id
	local label = Traps.KINDS[item.entry.kind].label
	if item.action == "work" then
		local ok, err = self:_canWork(player, id)
		if not ok then
			-- Déjà annoncé au début du maintien : pas une seconde fois à la fin
			if not announced then
				self.deps.notify(player, tostring(err))
			end
			return
		end
		local trap = self.rules:get(id)
		if trap and trap.state == State.Armed then
			self:disarm(id)
			self.deps.notify(player, label .. " désarmé")
			return
		end
		if not prepared then
			if not announced then
				self.deps.notify(player, "préparation refusée : recommencer")
			end
			return
		end
		local _, _, state = self:prepare(id)
		self.deps.notify(
			player,
			if state == State.Armed
				then string.format("%s armé (%d/%d)", label, self.rules:activeCount(), self.rules.timing.maxActive)
				else label .. " : première étape faite"
		)
	elseif item.action == "blow" then
		if self.deps.isExposed(player) then
			self.deps.notify(player, "dans la lumière, impossible d'agir sur un piège")
			return
		end
		local trap = self.rules:get(id)
		if trap and trap.state == State.Preparing then
			self:disarm(id)
			self.deps.notify(player, label .. " abandonné")
			return
		end
		local ok, err = self:blow(id)
		if not ok then
			self.deps.notify(player, tostring(err))
		end
	elseif item.action == "examine" then
		self.deps.notify(
			player,
			if self.rules:isTampered(id) then label .. " : quelque chose cloche…" else label .. " : rien d'anormal"
		)
	elseif item.action == "defuse" then
		local ok = self:defuse(id)
		self.deps.notify(player, if ok then label .. " : piège désamorcé" else label .. " : rien à désamorcer")
	end
end

-- Boucle ---------------------------------------------------------------------------------------------------------

-- Cette méthode permet de répercuter un changement des pièges ou du souffle lorsque l'état change : invites, puis
-- attributs publiés.
function TrapService:_changed()
	self:_refreshPrompts()
	self:_publish()
end

-- Cette méthode permet de publier souffle et pièges armés sur le joueur Mort lorsque l'une des valeurs change (une
-- écriture par changement, pas par frame) ; les autres joueurs n'ont pas ces attributs.
function TrapService:_publish()
	local charges, rechargeEnd = self:breath()
	local armed = self.rules:armedCount()
	-- Arrondi au dixième : l'horloge du serveur avance, la fin de recharge publiée ne doit pas bouger à chaque appel
	local roundedEnd = if rechargeEnd then math.floor(rechargeEnd * 10 + 0.5) / 10 else nil
	local key = string.format("%d|%s|%d", charges, tostring(self.rules.rechargeAt), armed)
	for _, player in self.deps.players:GetPlayers() do
		if self.deps.roleOf(player) == Role.Death then
			if self.published[player] ~= key then
				self.published[player] = key
				player:SetAttribute(TA.BreathCharges, charges)
				player:SetAttribute(TA.BreathRechargeEnd, roundedEnd)
				player:SetAttribute(TA.ArmedTraps, armed)
			end
		elseif self.published[player] then
			self.published[player] = nil
			player:SetAttribute(TA.BreathCharges, nil)
			player:SetAttribute(TA.BreathRechargeEnd, nil)
			player:SetAttribute(TA.ArmedTraps, nil)
		end
	end
end

-- Cette méthode permet de faire les contrôles périodiques lorsque le Heartbeat en donne l'occasion (toutes les
-- STEP_PERIOD secondes) : recharge du souffle, indices visuels des pièges armés, buée des mortels proches.
function TrapService:step()
	local now = self.deps.clock()
	local before = self.rules.charges
	self.rules:breath(now)
	if self.rules.charges ~= before then
		self:_refreshPrompts()
	end
	self:_publish()
	-- Bruit de préparation orphelin : la Mort est partie (ou a changé de rôle) sans lâcher l'invite
	local present = {}
	for _, player in self.deps.players:GetPlayers() do
		present[player] = self.deps.roleOf(player) == Role.Death
	end
	for _, entry in self.entries do
		if entry.noiseHolder and not present[entry.noiseHolder] then
			entry.noiseHolder = nil
			self.deps.stop(entry.noise)
		end
	end
	local armed = self.rules:armed()
	for _, id in armed do
		local at = self.nextCue[id]
		if at == nil then
			self:_scheduleCue(id)
		elseif now >= at then
			self:_pulseCue(self.entries[id])
			self:_scheduleCue(id)
		end
	end
	for _, player in self.deps.players:GetPlayers() do
		local chilled = false
		if self.deps.roleOf(player) == Role.Mortal then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local pos = root.CFrame.Position
				for _, id in armed do
					local entry = self.entries[id]
					local zone = entry.zone
					if
						(zone == nil or Traps.inZone(zone.center, zone.size, pos)) and Traps.chills(entry.floor, pos)
					then
						chilled = true
						break
					end
				end
			end
		end
		if (self.chilled[player] == true) ~= chilled then
			self.chilled[player] = chilled or nil
			player:SetAttribute(TA.Chill, if chilled then true else nil)
		end
	end
end

-- Debug ----------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'écouter la commande DebugTrap d'un joueur lorsqu'il rejoint le serveur (Studio seulement).
function TrapService:_watchPlayer(player)
	player.AttributeChanged:Connect(function(name)
		if name == TA.DebugTrap then
			self:_onDebug(player)
		end
	end)
end

-- Cette méthode permet d'exécuter une commande DebugTrap lorsqu'elle est écrite sur un joueur (voir
-- Shared.TrapAttributes) ; l'attribut est remis à nil une fois lu.
function TrapService:_onDebug(player)
	local value = player:GetAttribute(TA.DebugTrap)
	if value == nil then
		return
	end
	player:SetAttribute(TA.DebugTrap, nil)
	local command, id = string.match(tostring(value), "^(%a+):?(.*)$")
	local ok, err = true, nil
	if command == "prepare" then
		ok, err = self:prepare(id)
	elseif command == "arm" then
		repeat
			ok, err = self:prepare(id)
		until not ok or self.rules:get(id).state == State.Armed
	elseif command == "disarm" then
		ok, err = self:disarm(id)
	elseif command == "blow" then
		ok, err = self:blow(id)
	elseif command == "examine" then
		self.deps.log(string.format("examen de %s : %s", id, tostring(self.rules:isTampered(id))))
	elseif command == "defuse" then
		ok, err = self:defuse(id)
	elseif command == "drain" then
		ok, err = self:removeBreathCharge()
	elseif command == "reset" then
		self:reset()
	else
		ok, err = false, "commande inconnue"
	end
	if not ok then
		self.deps.warn(string.format("DebugTrap %s refusé : %s", tostring(value), tostring(err)))
	end
end

return TrapService
