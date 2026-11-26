-- Service des pièges (serveur) : tient l'état des points fragiles (Shared.Traps), crée les invites des mortels
-- (examiner, désamorcer) et reçoit celles de la Mort (préparer ou désarmer, souffler : créées par son seul client,
-- Client.DeathTrapPrompts, relayées par TrapAttributes.ActionEvent), joue les bruits de préparation, l'indice
-- visuel intermittent des pièges armés et les accidents (carrelage, étagère, lustre), applique l'accident aux mortels
-- touchés (MatchService:accident : agonie, ou mort sans agonie s'ils ont déjà été ranimés) et signale la buée aux
-- mortels proches d'un piège armé. Une âme fauchée recharge le souffle. Remise à zéro à chaque manche.
--
-- API pour les étapes suivantes (dissipation #8, âmes, HUD #9), via `TrapService.get()` :
--   :removeBreathCharge()   la Mort perd une charge (dissipée par la lampe torche) ; (true) ou (false, raison)
--   :refillBreath()         souffle plein (âme récoltée)
--   :breath()               charges, fin de recharge (horloge du serveur)
-- État privé (#49) : souffle, pièges armés et état de chaque piège publiés dans le conteneur privé de la Mort, buée dans
-- celui de chaque mortel (Server.PrivateState, noms et lecture : Shared.TrapAttributes) ; jamais sur un objet répliqué
-- à tous.
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
local TrapPrompts = require(Shared.TrapPrompts)
local Traps = require(Shared.Traps)

local PrivateState = require(script.Parent.PrivateState)

local LA = LightAttributes
local TA = TrapAttributes
local Role = DeathRules.Role
local State = Traps.State
local Action = TrapPrompts.Action
local Phase = TA.ActionPhase

local TrapService = {}
TrapService.__index = TrapService

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
	match: any?, -- MatchService : accident(player), MatchStarted, PhaseChanged, MortalStateChanged
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
	-- branche l'événement des invites de la Mort (TrapAttributes.ActionEvent) : handler(joueur, phase, id, action)
	listenActions: ((any, any, any, any) -> ()) -> (),
	-- conteneur privé d'un joueur (Server.PrivateState.get), nil tant qu'il n'existe pas
	privateOf: (any) -> Instance?,
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
	local actionEvent = Instance.new("RemoteEvent")
	actionEvent.Name = TA.ActionEvent
	actionEvent.Parent = ReplicatedStorage
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
		-- Cette méthode permet de recevoir les invites de la Mort lorsque son client en tient ou déclenche une.
		listenActions = function(handler)
			actionEvent.OnServerEvent:Connect(handler)
		end,
		privateOf = PrivateState.get,
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
		local id = TrapPrompts.idOf(part)
		local kind = part:GetAttribute(MapTags.Attributes.TrapKind)
		if kinds[id] then
			d.warn("point fragile en double : " .. id)
		elseif not TrapPrompts.isValidId(id) then
			d.warn("point fragile ignoré, identifiant inutilisable comme attribut : " .. id)
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
		-- { prompt, action, entry, role } ; pour la Mort, `prompt` est une vue serveur (ActionText, HoldDuration,
		-- MaxActivationDistance, available) de l'invite que seul son client crée
		prompts = {} :: { any },
		deathItems = {} :: { [string]: { [string]: any } }, -- id -> action -> élément d'une invite de la Mort
		holds = {} :: { [any]: { [any]: number } }, -- invite -> joueur -> début du maintien
		-- invite -> joueur à qui le refus a déjà été annoncé au début du maintien
		refused = {} :: { [any]: { [any]: boolean } },
		nextCue = {} :: { [string]: number }, -- piège armé -> prochain indice visuel (horloge)
		-- Clés faibles : un joueur parti ne reste pas en mémoire
		chilled = setmetatable({}, { __mode = "k" }) :: any,
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
	self.deps.listenActions(function(player, phase, id, action)
		self:_onAction(player, phase, id, action)
	end)
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
		-- Âme fauchée : elle recharge entièrement le souffle de la Mort (docs/design.md « Âmes »)
		match.MortalStateChanged:Connect(function(change)
			if change.soul == Match.SoulFate.Reaped then
				self:refillBreath()
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
			down, reason = match:accident(player)
		end
		if not down then
			self.deps.warn(string.format("%s : accident refusé pour %s (%s)", id, player.Name, tostring(reason)))
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

	self:_makeDeathView(entry, Action.Work)
	self:_makeDeathView(entry, Action.Blow)
	self:_makePrompt(entry, Action.Examine, Role.Mortal, TrapPrompts.props(entry.kind, Action.Examine))
	self:_makePrompt(entry, Action.Defuse, Role.Mortal, TrapPrompts.props(entry.kind, Action.Defuse))
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

-- Cette méthode permet de créer une invite réservée aux mortels sur un point fragile lorsque le service démarre ;
-- chaque client la filtre comme celles de la lumière (Client.LightPrompts : rôle, disponibilité, vue, regard).
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
	local triggered, began, ended = self:_handlers(item)
	self.deps.connectPrompt(prompt, triggered, began, ended)
	return prompt
end

-- Cette méthode permet de créer la vue serveur d'une invite de la Mort lorsque le service démarre : l'invite elle-même
-- n'existe que sur le client de la Mort (Client.DeathTrapPrompts), le serveur garde son maintien et sa portée pour
-- contrôler les actions reçues par TrapAttributes.ActionEvent.
function TrapService:_makeDeathView(entry, action: string)
	local props = TrapPrompts.props(entry.kind, action)
	local view = {
		ActionText = props.ActionText,
		HoldDuration = props.HoldDuration,
		MaxActivationDistance = props.MaxActivationDistance,
		available = false,
	}
	local item = { prompt = view, action = action, entry = entry, role = Role.Death }
	table.insert(self.prompts, item)
	local triggered, began, ended = self:_handlers(item)
	item.handlers = { [Phase.Triggered] = triggered, [Phase.Began] = began, [Phase.Ended] = ended }
	self.deathItems[entry.id] = self.deathItems[entry.id] or {}
	self.deathItems[entry.id][action] = item
	return view
end

-- Cette méthode permet de construire les réactions d'une invite (déclenchée, maintien commencé, maintien lâché) lorsque
-- elle est créée ; le début du maintien est daté par l'horloge du serveur.
function TrapService:_handlers(item): ((any) -> (), (any) -> (), (any) -> ())
	local key = item.prompt
	local holds = setmetatable({}, { __mode = "k" })
	self.holds[key] = holds
	self.refused[key] = setmetatable({}, { __mode = "k" })
	return function(player)
		self:_onPrompt(player, item)
	end, function(player)
		holds[player] = self.deps.clock()
		self:_onHoldBegan(player, item)
	end, function(player)
		self:_onHoldEnded(player, item)
	end
end

-- Cette méthode permet de recevoir une invite de la Mort lorsque son client la tient, la lâche ou la déclenche : les
-- arguments viennent du client, ils sont vérifiés avant d'atteindre les contrôles habituels (rôle, maintien, distance,
-- vue, lumière).
function TrapService:_onAction(player, phase: any, id: any, action: any)
	if type(phase) ~= "string" or type(id) ~= "string" or type(action) ~= "string" then
		return
	end
	local items = self.deathItems[id]
	local item = items and items[action]
	local handler = item and item.handlers[phase]
	if handler then
		handler(player)
	end
end

-- Cette méthode permet de mettre à jour ce que chaque invite permet maintenant lorsque l'état des pièges ou le souffle
-- change : vues serveur des invites de la Mort (même calcul que son client, Shared.TrapPrompts.deathView), et
-- disponibilité des invites des mortels, qui ne révèle rien (tout objet encore en place).
function TrapService:_refreshPrompts()
	local charges = self.rules:breath(self.deps.clock())
	for _, item in self.prompts do
		local trap = self.rules:get(item.entry.id)
		if item.role == Role.Death then
			local view = TrapPrompts.deathView(trap.kind, item.action, trap.state, trap.step, charges)
			item.prompt.ActionText = view.text
			item.prompt.HoldDuration = view.hold
			item.prompt.available = view.available
		else
			item.prompt:SetAttribute(LA.PromptAvailable, trap.state ~= State.Spent)
		end
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
	if item.action ~= Action.Work or self.deps.roleOf(player) ~= Role.Death then
		return
	end
	-- L'invite de la Mort vit sur son client : portée et vue contrôlées ici aussi, sinon un client modifié lancerait le
	-- bruit de préparation de n'importe quel piège de la maison
	local reach = self:_reach(player, item)
	if reach ~= nil then
		self.deps.warn(string.format("%s : %s refusé au début, %s", player.Name, item.action, reach))
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
	if item.action == Action.Work and player == item.entry.noiseHolder then
		item.entry.noiseHolder = nil
		self.deps.stop(item.entry.noise)
	end
end

-- Cette méthode permet de vérifier qu'un joueur peut atteindre la cible d'une invite lorsqu'il la tient ou la
-- déclenche : personnage présent, portée de l'invite (plus la tolérance) et vue ; renvoie nil, ou la raison du refus.
function TrapService:_reach(player, item): string?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return "sans personnage"
	end
	local from = root.CFrame.Position
	local part = item.entry.part
	local target = part.CFrame.Position
	if (target - from).Magnitude > item.prompt.MaxActivationDistance + DeathRules.DISTANCE_TOLERANCE then
		return "trop loin"
	end
	if not self.deps.lineOfSight(player, from, target, part) then
		return "cible hors de vue"
	end
	return nil
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
	if item.action == Action.Work then
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
	local reach = self:_reach(player, item)
	if reach == "sans personnage" then
		return
	elseif reach ~= nil then
		self.deps.warn(string.format("%s : %s refusé, %s", player.Name, item.action, reach))
		return
	end
	local id = item.entry.id
	local label = Traps.KINDS[item.entry.kind].label
	if item.action == Action.Work then
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
	elseif item.action == Action.Blow then
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
	elseif item.action == Action.Examine then
		self.deps.notify(
			player,
			if self.rules:isTampered(id) then label .. " : quelque chose cloche…" else label .. " : rien d'anormal"
		)
	elseif item.action == Action.Defuse then
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

-- Cette méthode permet de publier souffle, pièges armés et état de chaque piège dans le conteneur privé de la Mort
-- lorsque l'une des valeurs change (écriture seulement au changement, pas par frame) ; ceux des autres joueurs sont
-- vidés. Rien n'est posé sur le Player, répliqué à tous (#49).
function TrapService:_publish()
	local charges, rechargeEnd = self:breath()
	local armed = self.rules:armedCount()
	-- Arrondi au dixième : l'horloge du serveur avance, la fin de recharge publiée ne doit pas bouger à chaque appel
	local roundedEnd = if rechargeEnd then math.floor(rechargeEnd * 10 + 0.5) / 10 else nil
	for _, player in self.deps.players:GetPlayers() do
		local private = self.deps.privateOf(player)
		if private then
			local isDeath = self.deps.roleOf(player) == Role.Death
			PrivateState.write(private, TA.BreathCharges, if isDeath then charges else nil)
			PrivateState.write(private, TA.BreathRechargeEnd, if isDeath then roundedEnd else nil)
			PrivateState.write(private, TA.ArmedTraps, if isDeath then armed else nil)
			local states = PrivateState.folder(private, TA.TrapStates, isDeath)
			if states and not isDeath then
				states:Destroy()
			elseif states then
				for id, trap in self.rules.traps do
					PrivateState.write(states, id, if trap.state == State.Idle then nil else trap.state)
					PrivateState.write(
						states,
						id .. TA.StepSuffix,
						if trap.state == State.Preparing then trap.step else nil
					)
				end
			end
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
	-- ou n'a jamais envoyé la fin du maintien (client modifié, invite détruite en plein maintien)
	for id, entry in self.entries do
		local holder = entry.noiseHolder
		if holder then
			local item = self.deathItems[id] and self.deathItems[id][Action.Work]
			local began = item and self.holds[item.prompt][holder]
			local stale = began == nil or now - began > item.prompt.HoldDuration + DeathRules.HOLD_STALE
			if not present[holder] or stale then
				entry.noiseHolder = nil
				self.deps.stop(entry.noise)
			end
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
		-- Buée publiée dans le conteneur privé du mortel : un autre client ne la lit pas (#49)
		local private = if (self.chilled[player] == true) ~= chilled then self.deps.privateOf(player) else nil
		if private then
			self.chilled[player] = chilled or nil
			PrivateState.write(private, TA.Chill, if chilled then true else nil)
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
