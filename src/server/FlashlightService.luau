-- Lampe torche des mortels (#8, docs/design.md « Lumière ») : le serveur tient l'interrupteur et la batterie de chaque
-- mortel, oriente son faisceau (SpotLight sur la tête, vu de tous) d'après le regard envoyé par le client, éclaire au
-- sens de la règle de #4 (source mobile de Server.LightService : la Mort dans le faisceau est exposée et ralentie, ne
-- prépare pas de piège), et dissipe la Mort tenue DISPEL_TIME secondes dans un faisceau : elle se reforme dans une
-- ombre lointaine et perd une charge de souffle (Server.TrapService). Des piles rares, posées à chaque manche sur les
-- emplacements KeySpot laissés libres par les clés, remplissent la batterie. Règles pures : Shared.Flashlight.
-- Le client (Client.Flashlight) n'envoie que l'interrupteur et la direction du regard : cône, portée, ligne de vue et
-- batterie sont contrôlés ici.
--
-- API, via `FlashlightService.get()` : :isInBeam(position), :batteryOf(player), :toggle(player), :dispel(player).
-- Événement : Dispelled({ player, from, to }). Attributs répliqués : Shared.LightAttributes (FlashlightBattery,
-- FlashlightOn) ; DispelProgress va dans le conteneur privé de la Mort (Server.PrivateState, #49).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared.DeathRules)
local Flashlight = require(Shared.Flashlight)
local GameConfig = require(Shared.GameConfig)
local LightAttributes = require(Shared.LightAttributes)
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local Signal = require(Shared.Signal)

local PrivateState = require(script.Parent.PrivateState)

local LA = LightAttributes
local Role = DeathRules.Role

local FlashlightService = {}
FlashlightService.__index = FlashlightService

-- Faisceau : couleur chaude d'une ampoule à incandescence, tenu devant le visage (Shared.Flashlight.HOLD_OFFSET,
-- BRIGHTNESS)
local BEAM_COLOR = Color3.fromRGB(255, 240, 205)
local BEAM_OFFSET = Flashlight.HOLD_OFFSET
local ATTACHMENT_NAME = "FlashlightBeam"
-- Hauteur des yeux au-dessus de la racine quand la tête manque
local EYE_HEIGHT = 1.5
-- Hauteur où poser la Mort au-dessus d'un ancrage au sol (elle tombe sur ses pieds), comme Server.MatchSpawner
local DROP_HEIGHT = 3
-- Intervalle minimal entre deux interrupteurs d'un même client (secondes)
local TOGGLE_INTERVAL = 0.15
-- Faisceau vu des autres : réécrit seulement s'il bouge de plus de ORIENT_MOVE studs ou d'environ 1,5 degré
local ORIENT_MOVE = 0.05
local ORIENT_MIN_DOT = 0.9997
-- Pile : petit cylindre debout, orangé pour se voir sous le faisceau
local BATTERY_COLOR = Color3.fromRGB(190, 110, 40)
local BATTERY_SIZE = Vector3.new(0.8, 0.4, 0.4)
local BATTERY_DISTANCE = 8
-- Refus d'une pile lampe pleine (cas normal, pas d'avertissement)
local BATTERY_FULL = "batterie pleine"
-- Faisceau factice de debug (DebugFlashlight "beam") : durée et distance devant la Mort
local DEBUG_BEAM_TIME = 4
local DEBUG_BEAM_DISTANCE = 12

export type Deps = {
	house: Instance, -- maison construite (ancrages KeySpot, DeathSpawn, MortalSpawn, carrelage mouillé)
	players: any, -- participants (Server.Roster, API de Players) : GetPlayers, PlayerAdded, PlayerRemoving
	match: any?, -- MatchService : MatchStarted, PhaseChanged
	lights: any?, -- LightService : addLightSource(test), isLit(position)
	traps: any?, -- TrapService : removeBreathCharge()
	isStudio: boolean,
	roleOf: (any) -> string?, -- rôle effectif (attribut LightRole)
	clock: () -> number,
	lineOfSight: (Vector3, Vector3) -> boolean, -- rien du décor entre deux points (personnages traversés)
	teleport: (any, CFrame) -> (), -- déplace le personnage d'un joueur
	effect: (Vector3) -> (), -- fumée et son de la dissipation, à l'ancienne place de la Mort
	pick: (number) -> number, -- index tiré de 1 à n
	notify: (any, string) -> (), -- message bref pour un joueur
	privateOf: (any) -> Instance?, -- conteneur privé d'un joueur (Server.PrivateState.get)
	connectPrompt: (any, (any) -> ()) -> (), -- branche ProximityPrompt.Triggered (joueur en argument)
	remotes: { toggle: any, aim: any }?, -- événements client -> serveur (OnServerEvent)
	heartbeat: any?,
	log: (string) -> (),
	warn: (string) -> (),
}

-- Cette méthode permet de construire les dépendances réelles (services Roblox) lorsque le service est créé en jeu.
local function defaultDeps(): Deps
	local Debris = game:GetService("Debris")
	local RunService = game:GetService("RunService")
	local HouseBuilder = require(script.Parent.HouseBuilder)
	local house = workspace:FindFirstChild(HouseBuilder.MODEL_NAME)
	if not house then
		error("FlashlightService : maison introuvable, HouseBuilder.build doit passer avant")
	end
	-- Chargé ici : il lit le service Players, absent des tests Lune
	local LineOfSight = require(Shared.LineOfSight)
	local TrapAttributes = require(Shared.TrapAttributes)
	local toggle = Instance.new("RemoteEvent")
	toggle.Name = LA.FlashlightEvent
	toggle.Parent = ReplicatedStorage
	local aim = Instance.new("UnreliableRemoteEvent")
	aim.Name = LA.FlashlightAimEvent
	aim.Parent = ReplicatedStorage
	local rng = Random.new()

	-- Cette méthode permet de jouer la dissipation de la Mort lorsqu'un faisceau l'a tenue assez longtemps : bouffée
	-- de fumée noire et souffle sourd à l'endroit qu'elle quitte, visibles et audibles de tous.
	local function effect(position: Vector3)
		local part = Instance.new("Part")
		part.Name = "DeathDispel"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(2, 5, 2)
		part.CFrame = CFrame.new(position)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Enabled = false
		smoke.Color = ColorSequence.new(Color3.fromRGB(12, 12, 16))
		smoke.LightInfluence = 0
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 3.5),
		})
		smoke.Lifetime = NumberRange.new(0.8, 1.4)
		smoke.Speed = NumberRange.new(2, 5)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Drag = 3
		smoke.Parent = part
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/action_swim.mp3"
		sound.Volume = 0.9
		sound.PlaybackSpeed = 0.5
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = 60
		sound.Parent = part
		part.Parent = workspace
		smoke:Emit(45)
		sound:Play()
		Debris:AddItem(part, 3)
	end

	local match = require(script.Parent.MatchService).get()
	return {
		house = house,
		-- Joueurs et faux joueurs de debug (Server.Roster) : un bot mortel porte une lampe, un bot Mort peut être dissipé
		players = match:roster(),
		match = match,
		lights = require(script.Parent.LightService).get(),
		traps = require(script.Parent.TrapService).get(),
		isStudio = RunService:IsStudio(),
		-- Cette méthode permet de lire le rôle répliqué d'un joueur lorsqu'il allume sa lampe ou qu'un faisceau le vise.
		roleOf = function(player)
			return player:GetAttribute(LA.LightRole)
		end,
		clock = os.clock,
		-- Cette méthode permet de vérifier qu'aucun décor n'arrête le faisceau entre la lampe et un point.
		lineOfSight = function(from, to)
			return LineOfSight.clear(from, to, nil)
		end,
		-- Cette méthode permet de déplacer la Mort lorsqu'elle se reforme ailleurs.
		teleport = function(player, cframe)
			local character = player.Character
			if character then
				character:PivotTo(cframe)
			end
		end,
		effect = effect,
		-- Cette méthode permet de tirer un index de 1 à n lorsque le service choisit une ombre ou un emplacement de pile.
		pick = function(n)
			return rng:NextInteger(1, n)
		end,
		-- Cette méthode permet d'afficher un message bref au joueur (bandeau de Client.TrapCues) lorsqu'il ramasse une pile.
		notify = function(player, text)
			local event = ReplicatedStorage:FindFirstChild(TrapAttributes.NoticeEvent)
			if event and event:IsA("RemoteEvent") then
				event:FireClient(player, text)
			end
		end,
		privateOf = PrivateState.get,
		-- Cette méthode permet de brancher l'action d'une pile lorsqu'elle est posée.
		connectPrompt = function(prompt, onTriggered)
			prompt.Triggered:Connect(onTriggered)
		end,
		remotes = { toggle = toggle, aim = aim },
		heartbeat = RunService.Heartbeat,
		-- Cette méthode permet d'écrire un message de la lampe dans la sortie lorsque son état change.
		log = function(message)
			print("[Lampe] " .. message)
		end,
		-- Cette méthode permet de signaler un refus ou une anomalie de la lampe dans la sortie.
		warn = function(message)
			warn("[Lampe] " .. message)
		end,
	}
end

-- Cette méthode permet de créer le service sur une maison construite lorsqu'on veut l'instance du jeu (`get`) ou un
-- service isolé en test ; emplacements de piles et ombres de reformation sont lus par leurs tags.
function FlashlightService.new(deps: Deps?)
	local d = deps or defaultDeps()
	local spots: { [string]: BasePart } = {}
	local spotList: { Flashlight.Spot } = {}
	local respawns: { Vector3 } = {}
	for _, part in d.house:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		if part:HasTag(MapTags.KeySpot) then
			local id = part:GetAttribute(MapTags.Attributes.AnchorId)
			spots[id] = part
			table.insert(spotList, { id = id, room = part:GetAttribute(MapTags.Attributes.RoomId) })
		elseif
			part:HasTag(MapTags.DeathSpawn)
			or part:HasTag(MapTags.MortalSpawn)
			or part:GetAttribute(MapTags.Attributes.TrapKind) == MapTags.TrapKinds.WetFloor
		then
			-- Ancrages posés au sol, sur une place libre : la Mort peut s'y reformer
			table.insert(respawns, part.CFrame.Position + Vector3.new(0, DROP_HEIGHT, 0))
		end
	end
	-- Ordre stable (GetDescendants ne le garantit pas) : un même tirage donne le même point
	table.sort(respawns, function(a, b)
		return if a.X ~= b.X then a.X < b.X else (if a.Z ~= b.Z then a.Z < b.Z else a.Y < b.Y)
	end)
	return setmetatable({
		deps = d,
		started = false,
		spots = spots,
		spotList = spotList,
		respawns = respawns,
		-- Tables ordinaires vidées au départ du joueur (PlayerRemoving) : avec des clés faibles, Roblox peut ramasser le
		-- Player d'un joueur encore là (aucune référence Lua entre deux frames) et perdre sa batterie
		holders = {} :: { [any]: any }, -- mortel -> { on, battery, aim, published, ... }
		dispels = {} :: { [any]: Flashlight.Dispel }, -- joueur Mort -> cumul de dissipation
		beams = {} :: { { origin: Vector3, direction: Vector3 } }, -- faisceaux allumés à la dernière frame
		debugBeams = {} :: { { origin: Vector3, direction: Vector3, untilClock: number } },
		batteries = {} :: { [string]: BasePart }, -- emplacement -> pile posée
		Dispelled = Signal.new(),
	}, FlashlightService)
end

local instance = nil

-- Cette méthode permet de récupérer le service de lampe torche du serveur lorsqu'un autre module (HUD, tests en jeu)
-- en a besoin ; il est créé au premier appel, sur la maison du Workspace.
function FlashlightService.get()
	if not instance then
		instance = FlashlightService.new()
	end
	return instance
end

-- Cette méthode permet de brancher la lumière, la manche, les joueurs et les frames lorsque le serveur démarre (une
-- seule fois).
function FlashlightService:start()
	if self.started then
		return
	end
	self.started = true
	local d = self.deps
	if d.lights then
		d.lights:addLightSource(function(position)
			return self:isInBeam(position)
		end)
	end
	local match = d.match
	if match then
		-- Abonné après Server.EscapeService : les clés sont déjà posées quand les piles choisissent leurs emplacements
		match.MatchStarted:Connect(function()
			self:reset()
			if match:getPhase() == Match.Phase.Running then
				self:placeBatteries()
			end
		end)
		match.PhaseChanged:Connect(function(phase)
			if phase == Match.Phase.Waiting then
				self:reset()
			elseif phase == Match.Phase.Ended then
				self:_freezeBatteries()
			end
		end)
	end
	if d.remotes then
		d.remotes.toggle.OnServerEvent:Connect(function(player, action)
			if action == "toggle" then
				self:_onToggleRequest(player)
			end
		end)
		d.remotes.aim.OnServerEvent:Connect(function(player, direction)
			self:_onAim(player, direction)
		end)
	end
	if d.players.PlayerRemoving then
		d.players.PlayerRemoving:Connect(function(player)
			self.holders[player] = nil
			self.dispels[player] = nil
		end)
	end
	if d.isStudio then
		for _, player in d.players:GetPlayers() do
			self:_watchPlayer(player)
		end
		d.players.PlayerAdded:Connect(function(player)
			self:_watchPlayer(player)
		end)
	end
	if d.heartbeat then
		d.heartbeat:Connect(function(dt)
			self:step(dt)
		end)
	end
end

-- Lecture ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de savoir si un point est dans un faisceau allumé, sans mur, lorsque la lumière est testée
-- (source de LightService) ou que la Mort est visée ; le bord d'un corps (BODY_RADIUS) suffit.
function FlashlightService:isInBeam(position: Vector3): boolean
	for _, beam in self.beams do
		if
			Flashlight.inBeam(beam.origin, beam.direction, position, Flashlight.BODY_RADIUS)
			and self.deps.lineOfSight(beam.origin, position)
		then
			return true
		end
	end
	return false
end

-- Cette méthode permet de lire la batterie d'un mortel (0 à 1) lorsque le HUD ou un test en a besoin.
function FlashlightService:batteryOf(player): number
	local holder = self.holders[player]
	return if holder then holder.battery else 1
end

-- Cette méthode permet de lire si la lampe d'un mortel est allumée lorsqu'un test ou le HUD en a besoin.
function FlashlightService:isOn(player): boolean
	local holder = self.holders[player]
	return holder ~= nil and holder.on
end

-- Actions --------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'allumer ou d'éteindre la lampe d'un mortel lorsqu'il le demande ; renvoie (true) ou
-- (false, raison) : seul un mortel en jeu a une lampe, et elle ne s'allume pas batterie vide.
function FlashlightService:toggle(player): (boolean, string?)
	if self.deps.roleOf(player) ~= Role.Mortal then
		return false, "seul un mortel a une lampe"
	end
	local holder = self:_holder(player)
	if not holder.on and holder.battery <= 0 then
		return false, "batterie vide"
	end
	self:_setOn(player, holder, not holder.on)
	return true
end

-- Cette méthode permet de dissiper la Mort lorsqu'un faisceau l'a tenue DISPEL_TIME secondes (ou par debug) : fumée à
-- sa place, reformation dans une ombre lointaine, une charge de souffle perdue ; renvoie (true) ou (false, raison).
function FlashlightService:dispel(player): (boolean, string?)
	local root = self:_root(player)
	if not root then
		return false, "personnage absent"
	end
	local d = self.deps
	local from = root.CFrame.Position
	-- Tous les autres joueurs comptent, mortels en agonie compris (sans rôle de lumière) : la Mort ne se reforme pas à
	-- côté d'un mortel à faucher ; ceux qui ont quitté la maison sont loin de toute façon
	local threats = {}
	for _, other in d.players:GetPlayers() do
		local otherRoot = if d.roleOf(other) ~= Role.Death then self:_root(other) else nil
		if otherRoot then
			table.insert(threats, otherRoot.CFrame.Position)
		end
	end
	-- Cette méthode permet de savoir si un point de reformation est éclairé (lampes et faisceaux) lorsqu'on le choisit.
	local function isLit(point: Vector3): boolean
		return d.lights ~= nil and d.lights:isLit(point)
	end
	local to = Flashlight.chooseRespawn(self.respawns, from, threats, isLit, d.pick)
	d.effect(from)
	if to then
		-- Orientation gardée : la caméra de la Mort ne pivote pas d'un coup
		d.teleport(player, CFrame.new(to) * root.CFrame.Rotation)
	else
		d.warn("aucune ombre où reformer la Mort : elle reste sur place")
	end
	local charged, err = true, nil
	if d.traps then
		charged, err = d.traps:removeBreathCharge()
	end
	d.log(
		string.format(
			"%s dissipée, reformée à %s ; souffle : %s",
			player.Name,
			if to then string.format("%.0f, %.0f, %.0f", to.X, to.Y, to.Z) else "sa place",
			if charged then "une charge perdue" else tostring(err)
		)
	)
	local dispel = self.dispels[player]
	if dispel then
		dispel.held, dispel.gap = 0, 0
		dispel.immunity = Flashlight.DISPEL_IMMUNITY
	end
	self.Dispelled:Fire({ player = player, from = from, to = to })
	return true
end

-- Cette méthode permet de poser les piles de la manche lorsqu'elle démarre : GameConfig.FLASHLIGHT_BATTERY_COUNT
-- emplacements KeySpot libres (pas sous une clé), une pile par pièce au plus.
function FlashlightService:placeBatteries()
	local occupied = {}
	for id, spot in self.spots do
		for _, sibling in (spot.Parent and spot.Parent:GetChildren() or {}) :: { Instance } do
			if sibling ~= spot and sibling:GetAttribute(MapTags.Attributes.AnchorId) == id then
				occupied[id] = true
			end
		end
	end
	local chosen =
		Flashlight.drawBatterySpots(self.spotList, GameConfig.FLASHLIGHT_BATTERY_COUNT, self.deps.pick, occupied)
	if #chosen < GameConfig.FLASHLIGHT_BATTERY_COUNT then
		self.deps.warn(
			string.format("%d emplacement(s) libre(s) pour %d piles", #chosen, GameConfig.FLASHLIGHT_BATTERY_COUNT)
		)
	end
	for _, id in chosen do
		self:_placeBattery(id)
	end
	self.deps.log("piles posées : " .. table.concat(chosen, ", "))
	return chosen
end

-- Cette méthode permet de ramasser une pile lorsqu'un mortel termine l'action : batterie pleine, pile retirée ;
-- renvoie (true) ou (false, raison). Une lampe déjà pleine laisse la pile en place.
function FlashlightService:pickBattery(player, spotId: string): (boolean, string?)
	local part = self.batteries[spotId]
	if not part then
		return false, "aucune pile ici"
	end
	if self.deps.roleOf(player) ~= Role.Mortal then
		return false, "seul un mortel ramasse une pile"
	end
	local root = self:_root(player)
	if
		not root
		or (root.CFrame.Position - part.CFrame.Position).Magnitude
			> BATTERY_DISTANCE + DeathRules.DISTANCE_TOLERANCE
	then
		return false, "trop loin"
	end
	local holder = self:_holder(player)
	if holder.battery >= 1 then
		self.deps.notify(player, "Lampe déjà chargée")
		return false, BATTERY_FULL
	end
	holder.battery = 1
	self.batteries[spotId] = nil
	part:Destroy()
	self:_publish(player, holder)
	self.deps.notify(player, "Pile : lampe rechargée")
	self.deps.log(player.Name .. " a ramassé une pile (" .. spotId .. ")")
	return true
end

-- Cette méthode permet de tout remettre à l'état de départ lorsqu'une manche commence ou revient à l'attente : piles
-- retirées, lampes éteintes et pleines, dissipations et faisceaux de debug effacés.
function FlashlightService:reset()
	for _, part in self.batteries do
		part:Destroy()
	end
	table.clear(self.batteries)
	for player, holder in self.holders do
		holder.battery = 1
		holder.on = false
		if holder.light then
			holder.light.Enabled = false
		end
		-- Attributs réécrits seulement pour un mortel : la Mort et les joueurs sans rôle n'en ont pas (LightAttributes)
		if self.deps.roleOf(player) == Role.Mortal then
			self:_publish(player, holder)
		end
	end
	for _, dispel in self.dispels do
		dispel.held, dispel.gap, dispel.immunity = 0, 0, 0
	end
	table.clear(self.debugBeams)
	table.clear(self.beams)
end

-- Boucle -------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'avancer d'une frame lorsque le Heartbeat tombe : batteries qui se vident, faisceaux
-- recalculés, puis dissipation cumulée sur chaque joueur Mort.
function FlashlightService:step(dt: number)
	local d = self.deps
	local now = d.clock()
	local beams = {}
	local deaths = {}
	for _, player in d.players:GetPlayers() do
		local role = d.roleOf(player)
		if role == Role.Mortal then
			local holder = self:_holder(player)
			self:_ensureLight(player, holder)
			if holder.on then
				holder.battery = Flashlight.drain(holder.battery, dt)
				if holder.battery <= 0 then
					self:_setOn(player, holder, false)
					d.log(player.Name .. " : batterie vide")
				end
			end
			local beam = if holder.on then self:_beamOf(player, holder) else nil
			if beam then
				table.insert(beams, beam)
			end
			self:_publish(player, holder)
		else
			self:_release(player)
			if role == Role.Death then
				table.insert(deaths, player)
			end
		end
	end
	for i = #self.debugBeams, 1, -1 do
		local beam = self.debugBeams[i]
		if now >= beam.untilClock then
			table.remove(self.debugBeams, i)
		else
			table.insert(beams, beam)
		end
	end
	self.beams = beams
	for player in self.dispels do
		if not table.find(deaths, player) then
			self.dispels[player] = nil
			local private = self.deps.privateOf(player)
			if private then
				PrivateState.write(private, LA.DispelProgress, nil)
			end
		end
	end
	for _, player in deaths do
		self:_stepDeath(player, dt)
	end
end

-- Cette méthode permet de cumuler le faisceau tenu sur un joueur Mort lorsqu'une frame passe ; la dissipation part
-- au bout de DISPEL_TIME secondes (Shared.Flashlight.updateDispel).
function FlashlightService:_stepDeath(player, dt: number)
	local dispel = self.dispels[player]
	if not dispel then
		dispel = Flashlight.newDispel()
		self.dispels[player] = dispel
	end
	local root = self:_root(player)
	local hit = root ~= nil and #self.beams > 0 and self:isInBeam(root.CFrame.Position)
	local dispelled, progress = Flashlight.updateDispel(dispel, hit, dt)
	-- Au vingtième près, nil à 0 (une progression qui démarre ne publie pas 0)
	local rounded = math.floor(progress * 20 + 0.5) / 20
	local published = if rounded > 0 then rounded else nil
	-- Privée (#49) : un client mortel ne doit pas savoir que son faisceau tient la Mort, invisible dans l'ombre
	local private = self.deps.privateOf(player)
	if private then
		PrivateState.write(private, LA.DispelProgress, published)
	end
	if dispelled then
		self:dispel(player)
	end
end

-- Mortels --------------------------------------------------------------------------------------------------------

-- Cette méthode permet de lire la racine du personnage d'un joueur lorsqu'on le vise ou le déplace (nil sinon).
function FlashlightService:_root(player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Cette méthode permet de lire (ou créer, batterie pleine) l'état de lampe d'un mortel lorsqu'il en a besoin.
function FlashlightService:_holder(player)
	local holder = self.holders[player]
	if not holder then
		holder = {
			on = false,
			battery = 1,
			aim = nil :: Vector3?,
			published = nil :: number?,
			publishedOn = nil :: boolean?,
			attachment = nil :: Attachment?,
			light = nil :: SpotLight?,
			lastToggle = -math.huge,
		}
		self.holders[player] = holder
	end
	return holder
end

-- Cette méthode permet d'éteindre la lampe et de retirer les attributs d'un joueur lorsqu'il n'est plus mortel en jeu
-- (agonie, Mort, fin de manche) ; la batterie est gardée (un mortel ranimé la retrouve).
function FlashlightService:_release(player)
	local holder = self.holders[player]
	if not holder then
		return
	end
	if holder.on then
		self:_setOn(player, holder, false)
	end
	if holder.published ~= nil then
		holder.published = nil
		holder.publishedOn = nil
		player:SetAttribute(LA.FlashlightBattery, nil)
		player:SetAttribute(LA.FlashlightOn, nil)
	end
end

-- Cette méthode permet d'allumer ou d'éteindre une lampe lorsque le mortel la bascule ou que la batterie se vide.
function FlashlightService:_setOn(player, holder, on: boolean)
	-- Rallumée : l'ancien regard est périmé, le faisceau part devant la tête jusqu'au prochain regard reçu
	if on and not holder.on then
		holder.aim = nil
	end
	holder.on = on
	if holder.light then
		holder.light.Enabled = on
	end
	self:_publish(player, holder)
end

-- Cette méthode permet de publier batterie (au centième) et interrupteur d'un mortel lorsqu'ils changent.
function FlashlightService:_publish(player, holder)
	local level = Flashlight.quantize(holder.battery)
	if level ~= holder.published then
		holder.published = level
		player:SetAttribute(LA.FlashlightBattery, level)
	end
	if holder.on ~= holder.publishedOn then
		holder.publishedOn = holder.on
		player:SetAttribute(LA.FlashlightOn, holder.on)
	end
end

-- Cette méthode permet de poser le faisceau (Attachment et SpotLight) sur la tête d'un mortel lorsqu'il n'y est pas
-- encore (nouveau personnage) ; vu de tous, allumé selon l'interrupteur.
function FlashlightService:_ensureLight(player, holder)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	if holder.attachment and holder.attachment.Parent == head then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.CFrame = BEAM_OFFSET
	local light = Instance.new("SpotLight")
	light.Name = "Beam"
	light.Face = Enum.NormalId.Front
	light.Color = BEAM_COLOR
	light.Brightness = Flashlight.BRIGHTNESS
	light.Range = Flashlight.RANGE
	light.Angle = Flashlight.VISUAL_ANGLE
	light.Shadows = true
	light.Enabled = holder.on
	light.Parent = attachment
	attachment.Parent = head
	holder.attachment = attachment
	holder.light = light
	if holder.aim then
		self:_orient(head, holder)
	end
end

-- Cette méthode permet de trouver d'où part le faisceau lorsque la règle ou le rendu en a besoin : la lampe tenue
-- devant le visage, ou le centre de la tête si un mur les sépare (le faisceau ne traverse pas la cloison).
function FlashlightService:_holdPoint(head: BasePart): Vector3
	local center = head.CFrame.Position
	local held = (head.CFrame * BEAM_OFFSET).Position
	return if self.deps.lineOfSight(center, held) then held else center
end

-- Cette méthode permet d'orienter le faisceau vu des autres sur le regard d'un mortel lorsque regard ou tête bougent ;
-- l'Attachment n'est réécrit (et répliqué) que s'il a vraiment changé.
function FlashlightService:_orient(head: BasePart, holder, origin: Vector3?)
	local attachment = holder.attachment
	if not attachment or not holder.aim then
		return
	end
	local from = origin or self:_holdPoint(head)
	local wanted = head.CFrame:ToObjectSpace(CFrame.lookAt(from, from + holder.aim))
	local current = attachment.CFrame
	if
		(current.Position - wanted.Position).Magnitude > ORIENT_MOVE
		or current.LookVector:Dot(wanted.LookVector) < ORIENT_MIN_DOT
	then
		attachment.CFrame = wanted
	end
end

-- Cette méthode permet de donner le faisceau d'un mortel lampe allumée lorsqu'une frame passe : depuis la lampe, vers
-- le dernier regard reçu (devant la tête sinon) ; le rendu vu des autres est réaligné dessus.
function FlashlightService:_beamOf(player, holder): { origin: Vector3, direction: Vector3 }?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local origin = self:_holdPoint(head)
		self:_orient(head, holder, origin)
		return { origin = origin, direction = holder.aim or head.CFrame.LookVector }
	end
	local root = self:_root(player)
	if not root then
		return nil
	end
	return {
		origin = root.CFrame.Position + Vector3.new(0, EYE_HEIGHT, 0),
		direction = holder.aim or root.CFrame.LookVector,
	}
end

-- Cette méthode permet de traiter une demande d'interrupteur d'un client lorsqu'elle arrive (rythme limité).
function FlashlightService:_onToggleRequest(player)
	local holder = self:_holder(player)
	local now = self.deps.clock()
	if now - holder.lastToggle < TOGGLE_INTERVAL then
		return
	end
	holder.lastToggle = now
	self:toggle(player)
end

-- Cette méthode permet d'enregistrer le regard envoyé par un client lorsqu'il arrive : vecteur valide seulement
-- (type, longueur proche de 1) ; toujours le plus récent, rien de coûteux n'est fait ici.
function FlashlightService:_onAim(player, direction)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local length = direction.Magnitude
	-- NaN échoue aux deux comparaisons
	if not (length > 0.5 and length < 1.5) then
		return
	end
	local holder = self.holders[player]
	if not holder then
		return
	end
	-- Le faisceau vu des autres suit à la frame suivante (_beamOf)
	holder.aim = direction.Unit
end

-- Piles ----------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser une pile sur un emplacement lorsque la manche démarre : petit cylindre debout sur
-- l'ancrage, action « Ramasser » maintenue, proposée seulement à un mortel vivant qui la voit.
function FlashlightService:_placeBattery(spotId: string)
	local spot = self.spots[spotId]
	local part = Instance.new("Part")
	part.Name = LA.BatteryName
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Metal
	part.Color = BATTERY_COLOR
	part.Size = BATTERY_SIZE
	-- Posée sur l'ancrage (et non dedans) ; cylindre couché sur X, redressé à la verticale
	local top = spot.CFrame.Position.Y + spot.Size.Y / 2
	part.CFrame = CFrame.new(spot.CFrame.Position.X, top + BATTERY_SIZE.X / 2, spot.CFrame.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	part:SetAttribute(MapTags.Attributes.AnchorId, spotId)
	local prompt = Instance.new("ProximityPrompt")
	-- Enabled reste à false : le client décide (Shared.PromptVisibility), le serveur n'y touche plus (#18, #19)
	prompt.Enabled = false
	prompt.RequiresLineOfSight = false
	prompt.ObjectText = "Pile"
	prompt.ActionText = "Ramasser"
	prompt.HoldDuration = GameConfig.BATTERY_PICKUP_DURATION
	prompt.MaxActivationDistance = BATTERY_DISTANCE
	prompt:SetAttribute(LA.PromptRole, Match.Role.Mortal)
	prompt:SetAttribute(LA.PromptState, Match.MortalState.Alive)
	prompt:SetAttribute(LA.PromptAvailable, true)
	prompt:SetAttribute(LA.PromptSight, true)
	prompt:AddTag(LA.PromptTag)
	prompt.Parent = part
	self.deps.connectPrompt(prompt, function(player)
		local ok, err = self:pickBattery(player, spotId)
		-- Lampe pleine : cas normal, le joueur est déjà prévenu
		if not ok and err ~= BATTERY_FULL then
			self.deps.warn(string.format("pile refusée pour %s : %s", player.Name, tostring(err)))
		end
	end)
	part.Parent = spot.Parent
	self.batteries[spotId] = part
end

-- Cette méthode permet de couper l'action des piles restantes lorsque la manche se termine (état figé pendant le
-- résultat).
function FlashlightService:_freezeBatteries()
	for _, part in self.batteries do
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:SetAttribute(LA.PromptAvailable, false)
		end
	end
end

-- Debug ----------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'écouter la commande DebugFlashlight d'un joueur lorsqu'il rejoint le serveur (Studio).
function FlashlightService:_watchPlayer(player)
	player.AttributeChanged:Connect(function(name)
		if name == LA.DebugFlashlight then
			self:_onDebug(player)
		end
	end)
end

-- Cette méthode permet d'exécuter une commande DebugFlashlight ("on", "off", "battery:<0..1>", "beam", "dispel")
-- lorsqu'elle est écrite sur un joueur ; l'attribut est remis à nil une fois lu.
function FlashlightService:_onDebug(player)
	local value = player:GetAttribute(LA.DebugFlashlight)
	if value == nil then
		return
	end
	player:SetAttribute(LA.DebugFlashlight, nil)
	local command, arg = string.match(tostring(value), "^(%a+):?(.*)$")
	local ok, err = true, nil
	if command == "on" or command == "off" then
		local holder = self:_holder(player)
		if command == "on" and holder.battery <= 0 then
			ok, err = false, "batterie vide"
		else
			self:_setOn(player, holder, command == "on")
		end
	elseif command == "battery" then
		local level = tonumber(arg)
		if level then
			local holder = self:_holder(player)
			holder.battery = math.clamp(level, 0, 1)
			self:_publish(player, holder)
		else
			ok, err = false, "niveau attendu (0 à 1)"
		end
	elseif command == "beam" then
		local root = self:_root(player)
		if root then
			local origin = root.CFrame.Position
				+ root.CFrame.LookVector * DEBUG_BEAM_DISTANCE
				+ Vector3.new(0, EYE_HEIGHT, 0)
			table.insert(self.debugBeams, {
				origin = origin,
				direction = (root.CFrame.Position - origin).Unit,
				untilClock = self.deps.clock() + DEBUG_BEAM_TIME,
			})
		else
			ok, err = false, "personnage absent"
		end
	elseif command == "dispel" then
		ok, err = self:dispel(player)
	else
		ok, err = false, "commande inconnue"
	end
	if not ok then
		self.deps.warn(string.format("DebugFlashlight %s refusé : %s", tostring(value), tostring(err)))
	else
		self.deps.log("DebugFlashlight " .. tostring(value))
	end
end

return FlashlightService
