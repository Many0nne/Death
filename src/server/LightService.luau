-- Service de lumière (serveur) : tient l'état des lampes (Shared.Illumination) et les règles de sabotage
-- (Shared.Sabotage), les applique aux lampes de la maison, crée les invites d'action du disjoncteur et des ampoules,
-- joue les sons et remet tout à zéro à chaque manche.
--
-- API pour les étapes suivantes (pièges #5, lampe torche #8, HUD #9), via `LightService.get()` :
--   :isLit(position)          point éclairé par une lampe allumée (règle Shared.Illumination)
--   :canPrepareAt(position)   la Mort peut préparer un piège ici (jamais dans la lumière)
--   :isRoomLit(roomId), :roomAt(position)
--   :cutPower(wingId), :restorePower(), :burnRoom(roomId)   (true) ou (false, raison)
-- Événement : Changed() après chaque changement de lumière. Attributs répliqués : Shared.LightAttributes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared.DeathRules)
local HouseLayout = require(Shared.HouseLayout)
local Illumination = require(Shared.Illumination)
local LightAttributes = require(Shared.LightAttributes)
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local NightLighting = require(Shared.NightLighting)
local Sabotage = require(Shared.Sabotage)
local Signal = require(Shared.Signal)

local LA = LightAttributes
local Role = DeathRules.Role

local LightService = {}
LightService.__index = LightService

-- Lampe éteinte : bloc gris foncé à la place du néon
local LAMP_OFF_COLOR = Color3.fromRGB(58, 58, 62)

-- Sons provisoires (fichiers fournis avec le client Roblox). Disjoncteur : non positionnel, entendu par tous ;
-- ampoule : positionnel et faible, entendu seulement de près.
local SOUNDS = {
	cut = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.9, speed = 0.45 },
	restore = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.5, speed = 0.8 },
	burn = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, speed = 2.2, rollOff = 18 },
}

-- Grésillement d'une ampoule qui grille : durées successives éteinte / allumée, puis état réel
local FLICKER = { 0.08, 0.06, 0.1, 0.05, 0.12 }

-- Touches des invites de coupure, une par aile (dans l'ordre alphabétique des ailes), et décalage vertical des
-- bulles pour qu'elles ne se superposent pas sur le disjoncteur
local CUT_KEYS = {
	{ key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX },
	{ key = Enum.KeyCode.R, pad = Enum.KeyCode.ButtonY },
	{ key = Enum.KeyCode.T, pad = Enum.KeyCode.ButtonB },
}
local PROMPT_SPACING = 80

export type Deps = {
	house: Instance, -- maison construite (Server.HouseBuilder)
	match: any?, -- MatchService : remise à zéro au début de manche et au retour à l'attente
	players: any?, -- service Players : attribut DebugLight (Studio)
	isStudio: boolean,
	roleOf: (any) -> string?, -- rôle effectif d'un joueur pour la lumière (attribut LightRole)
	clock: () -> number,
	soundParent: Instance?, -- parent des sons entendus par tous (SoundService)
	connectPrompt: (any, (any) -> ()) -> (), -- branche ProximityPrompt.Triggered
	delay: (number, () -> ()) -> (),
	lineOfSight: (any, Vector3, Vector3, Instance) -> boolean, -- (joueur, depuis, vers, cible) : vue dégagée
	log: (string) -> (),
	warn: (string) -> (),
}

-- Cette méthode permet de construire les dépendances réelles (services Roblox) lorsque le service est créé en jeu.
local function defaultDeps(): Deps
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local HouseBuilder = require(script.Parent.HouseBuilder)
	local MatchService = require(script.Parent.MatchService)
	local house = workspace:FindFirstChild(HouseBuilder.MODEL_NAME)
	if not house then
		error("LightService : maison introuvable, HouseBuilder.build doit passer avant")
	end

	-- Chargé ici : il lit le service Players, absent des tests Lune
	local LineOfSight = require(Shared.LineOfSight)

	-- Cette méthode permet de vérifier qu'aucun décor ne cache la cible depuis le personnage lorsqu'une invite est
	-- déclenchée (même règle que l'affichage des invites d'ampoule, Client.LightPrompts).
	local function lineOfSight(_player, from: Vector3, to: Vector3, target: Instance): boolean
		return LineOfSight.clear(from, to, target)
	end
	-- Cette méthode permet de lire le rôle répliqué d'un joueur lorsqu'une invite est déclenchée.
	local function roleOf(player): string?
		return player:GetAttribute(LA.LightRole)
	end
	-- Cette méthode permet de brancher une invite lorsqu'elle est créée.
	local function connectPrompt(prompt, fn)
		prompt.Triggered:Connect(fn)
	end
	-- Cette méthode permet de différer une action (grésillement, fin de recharge) lorsque le service la programme.
	local function delay(seconds: number, fn: () -> ())
		task.delay(seconds, fn)
	end

	return {
		house = house,
		match = MatchService.get(),
		players = Players,
		isStudio = RunService:IsStudio(),
		roleOf = roleOf,
		clock = os.clock,
		soundParent = game:GetService("SoundService"),
		connectPrompt = connectPrompt,
		delay = delay,
		lineOfSight = lineOfSight,
		log = function(message)
			print("[Lumière] " .. message)
		end,
		warn = function(message)
			warn("[Lumière] " .. message)
		end,
	}
end

-- Cette méthode permet de créer le service sur une maison construite lorsqu'on veut l'instance du jeu (`get`) ou un
-- service isolé en test ; les lampes, le disjoncteur et les pièces sont lus par leurs tags.
function LightService.new(deps: Deps?)
	local d = deps or defaultDeps()
	local illumination = Illumination.fromHouse(d.house)
	local self = setmetatable({
		deps = d,
		started = false,
		illumination = illumination,
		sabotage = Sabotage.new(illumination),
		lampParts = {} :: { [string]: BasePart },
		roomNames = {} :: { [string]: string },
		breaker = nil :: BasePart?,
		prompts = {} :: { any }, -- { prompt, kind = "cut" | "restore" | "burn", wing?, room? }
		flickering = {} :: { [string]: boolean }, -- lampes en train de grésiller (affichage piloté par _flicker)
		sounds = {},
		Changed = Signal.new(),
	}, LightService)
	for _, part in d.house:GetDescendants() do
		if part:HasTag(MapTags.Lamp) then
			self.lampParts[part:GetAttribute(MapTags.Attributes.LampId)] = part
		elseif part:HasTag(MapTags.Room) then
			self.roomNames[part:GetAttribute(MapTags.Attributes.RoomId)] =
				part:GetAttribute(MapTags.Attributes.RoomName)
		elseif part:HasTag(MapTags.Breaker) and part:IsA("BasePart") then
			self.breaker = part
		end
	end
	return self
end

local instance = nil

-- Cette méthode permet de récupérer le service de lumière du serveur lorsqu'un autre module (Mort, pièges, lampe
-- torche) doit lire ou changer la lumière ; il est créé au premier appel, sur la maison du Workspace.
function LightService.get()
	if not instance then
		instance = LightService.new()
	end
	return instance
end

-- Cette méthode permet de créer invites et sons, d'allumer les lampes et d'écouter la manche lorsque le serveur
-- démarre (une seule fois).
function LightService:start()
	if self.started then
		return
	end
	self.started = true
	self:_createSounds()
	self:_createPrompts()
	self:_applyAll()
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
end

-- Lecture ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de savoir si un point est éclairé lorsque la Mort s'y trouve ou qu'un système teste la lumière.
function LightService:isLit(position: Vector3): boolean
	return (self.illumination:isLit(position))
end

-- Cette méthode permet de savoir si la Mort peut préparer un piège à un endroit lorsque #5 lance une préparation.
function LightService:canPrepareAt(position: Vector3): boolean
	return DeathRules.canPrepare(self.illumination, position)
end

-- Cette méthode permet de savoir si une pièce a une lampe allumée lorsque l'on raisonne par pièce (fauchage, HUD).
function LightService:isRoomLit(roomId: string): boolean
	return self.illumination:isRoomLit(roomId)
end

-- Cette méthode permet de trouver la pièce d'un point lorsqu'un système a besoin de la localiser (nil hors pièce).
function LightService:roomAt(position: Vector3): string?
	return self.illumination:roomAt(position)
end

-- Actions ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de couper une aile au disjoncteur lorsque la Mort le décide : lampes éteintes, bruit entendu
-- par tous ; renvoie (true) ou (false, raison).
function LightService:cutPower(wingId: string): (boolean, string?)
	local ok, err = self.sabotage:cutPower(wingId, self.deps.clock())
	if not ok then
		return false, err
	end
	self:_play("cut")
	self.deps.log("disjoncteur : aile " .. wingId .. " coupée")
	self:_changed()
	return true
end

-- Cette méthode permet de rétablir l'aile coupée lorsqu'un mortel relève le disjoncteur ; la coupure suivante attend
-- la recharge. Renvoie (true) ou (false, raison).
function LightService:restorePower(): (boolean, string?)
	local ok, err, wingId = self.sabotage:restorePower(self.deps.clock())
	if not ok then
		return false, err
	end
	self:_play("restore")
	self.deps.log("disjoncteur : aile " .. tostring(wingId) .. " rétablie")
	self:_changed()
	-- Fin de recharge : les invites de coupure redeviennent disponibles
	self.deps.delay(self.sabotage.timing.breakerCooldown + 0.05, function()
		self:_refreshPrompts()
	end)
	return true
end

-- Cette méthode permet de griller les ampoules d'une pièce lorsque la Mort le décide : grésillement bref, bruit
-- faible ; renvoie (true) ou (false, raison).
function LightService:burnRoom(roomId: string): (boolean, string?)
	local ok, err, lampIds = self.sabotage:burn(roomId, self.deps.clock())
	if not ok then
		return false, err
	end
	for _, id in lampIds :: { string } do
		self:_burnSound(id)
	end
	self.deps.log("ampoules grillées : " .. roomId)
	self:_changed(lampIds)
	self.deps.delay(self.sabotage.timing.burnCooldown + 0.05, function()
		self:_refreshPrompts()
	end)
	return true
end

-- Cette méthode permet de rallumer toute la maison et d'effacer les recharges lorsqu'une manche commence ou se termine.
function LightService:reset()
	self.sabotage:reset()
	self:_changed()
end

-- Application à la maison -----------------------------------------------------------------------------------------

-- Cette méthode permet de répercuter un changement de lumière lorsque l'état change : lampes (avec grésillement pour
-- celles qui viennent de griller), disjoncteur, invites, puis événement Changed.
function LightService:_changed(flicker: { string }?)
	self:_applyAll(flicker)
	self:_refreshPrompts()
	self.Changed:Fire()
end

-- Cette méthode permet d'afficher une lampe allumée ou éteinte lorsque son état change ou qu'elle grésille (lumière
-- et néon seulement : l'attribut LampOn suit la règle, voir _applyAll).
function LightService:_showLamp(lampId: string, on: boolean)
	local part = self.lampParts[lampId]
	if not part then
		return
	end
	local light = part:FindFirstChild("Light")
	if light and light:IsA("Light") then
		light.Enabled = on
	end
	part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Color = if on then NightLighting.lampColor else LAMP_OFF_COLOR
end

-- Cette méthode permet d'appliquer l'état de toutes les lampes et du disjoncteur lorsque la lumière change ; les
-- lampes de `flicker` grésillent avant de s'éteindre, et celles qui grésillent déjà finissent leur grésillement.
function LightService:_applyAll(flicker: { string }?)
	for _, lamp in self.illumination:allLamps() do
		local on = self.illumination:isLampOn(lamp.id)
		local part = self.lampParts[lamp.id]
		if part then
			part:SetAttribute(LA.LampOn, on)
		end
		if not self.flickering[lamp.id] then
			self:_showLamp(lamp.id, on)
		end
	end
	if flicker and #flicker > 0 then
		for _, id in flicker do
			self.flickering[id] = true
		end
		self:_flicker(flicker, 1)
	end
	if self.breaker then
		self.breaker:SetAttribute(LA.CutWing, self.sabotage:cutWing())
	end
end

-- Cette méthode permet de faire grésiller des lampes lorsqu'elles grillent : alternance éteinte / allumée selon
-- FLICKER, puis leur état réel (qui tient compte d'une coupure ou d'une remise à zéro survenue entre-temps).
function LightService:_flicker(lampIds: { string }, step: number)
	if step > #FLICKER then
		for _, id in lampIds do
			self.flickering[id] = nil
			self:_showLamp(id, self.illumination:isLampOn(id))
		end
		return
	end
	for _, id in lampIds do
		self:_showLamp(id, step % 2 == 0)
	end
	self.deps.delay(FLICKER[step], function()
		self:_flicker(lampIds, step + 1)
	end)
end

-- Sons ---------------------------------------------------------------------------------------------------------

-- Cette méthode permet de créer les sons du disjoncteur, entendus par tous, lorsque le service démarre.
function LightService:_createSounds()
	local parent = self.deps.soundParent
	if not parent then
		return
	end
	for _, name in { "cut", "restore" } do
		local spec = SOUNDS[name]
		local sound = Instance.new("Sound")
		sound.Name = "Breaker_" .. name
		sound.SoundId = spec.id
		sound.Volume = spec.volume
		sound.PlaybackSpeed = spec.speed
		sound.Parent = parent
		self.sounds[name] = sound
	end
end

-- Cette méthode permet de jouer un son du disjoncteur lorsque la Mort coupe ou qu'un mortel rétablit le courant.
function LightService:_play(name: string)
	local sound = self.sounds[name]
	if sound then
		sound:Play()
	end
end

-- Cette méthode permet de jouer le petit claquement d'une ampoule qui grille, audible seulement de près, lorsque la
-- Mort grille une pièce.
function LightService:_burnSound(lampId: string)
	local part = self.lampParts[lampId]
	if not part or not self.deps.soundParent then
		return
	end
	local spec = SOUNDS.burn
	local sound = Instance.new("Sound")
	sound.Name = "Burn"
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = spec.rollOff
	sound.Parent = part
	sound:Play()
	self.deps.delay(3, function()
		sound:Destroy()
	end)
end

-- Invites d'action -----------------------------------------------------------------------------------------------

-- Cette méthode permet de créer une invite d'action réservée à un rôle lorsque le service démarre ; chaque client
-- l'active pour son joueur selon PromptRole et PromptAvailable (LightAttributes).
function LightService:_makePrompt(parent: Instance, role: string, props: { [string]: any }, entry)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LightPrompt"
	prompt.RequiresLineOfSight = true
	for property, value in props do
		(prompt :: any)[property] = value
	end
	prompt:SetAttribute(LA.PromptRole, role)
	prompt:SetAttribute(LA.PromptAvailable, false)
	prompt:AddTag(LA.PromptTag)
	prompt.Parent = parent
	entry.prompt = prompt
	entry.role = role
	table.insert(self.prompts, entry)
	self.deps.connectPrompt(prompt, function(player)
		self:_onPrompt(player, entry)
	end)
	return prompt
end

-- Cette méthode permet de créer les invites du disjoncteur (une coupure par aile pour la Mort, le rétablissement pour
-- les mortels) et une invite « griller » par lampe lorsque le service démarre.
function LightService:_createPrompts()
	local breaker = self.breaker
	if breaker then
		local wings = {}
		for wingId in self.illumination.wingSet do
			table.insert(wings, wingId)
		end
		table.sort(wings)
		for i, wingId in wings do
			local keys = CUT_KEYS[i]
			if not keys then
				self.deps.warn("disjoncteur : pas de touche pour l'aile " .. wingId)
				continue
			end
			self:_makePrompt(breaker, Role.Death, {
				ActionText = "Couper : " .. (HouseLayout.wings[wingId] or wingId),
				ObjectText = "Disjoncteur",
				KeyboardKeyCode = keys.key,
				GamepadKeyCode = keys.pad,
				HoldDuration = DeathRules.CUT_HOLD,
				MaxActivationDistance = DeathRules.BREAKER_DISTANCE,
				UIOffset = Vector2.new(0, (i - (#wings + 1) / 2) * PROMPT_SPACING),
			}, { kind = "cut", wing = wingId })
		end
		self:_makePrompt(breaker, Role.Mortal, {
			ActionText = "Rétablir le courant",
			ObjectText = "Disjoncteur",
			HoldDuration = DeathRules.RESTORE_HOLD,
			MaxActivationDistance = DeathRules.BREAKER_DISTANCE,
		}, { kind = "restore" })
	else
		self.deps.warn("disjoncteur introuvable (tag " .. MapTags.Breaker .. ")")
	end
	for _, lamp in self.illumination:allLamps() do
		local part = self.lampParts[lamp.id]
		if part then
			local prompt = self:_makePrompt(part, Role.Death, {
				ActionText = "Griller l'ampoule",
				ObjectText = self.roomNames[lamp.roomId] or lamp.roomId,
				HoldDuration = DeathRules.BURN_HOLD,
				MaxActivationDistance = DeathRules.LAMP_DISTANCE,
				-- Vue testée depuis le personnage par le client (PromptSight) et le serveur, pas depuis la caméra
				RequiresLineOfSight = false,
			}, { kind = "burn", room = lamp.roomId })
			prompt:SetAttribute(LA.PromptSight, true)
		end
	end
	self:_refreshPrompts()
end

-- Cette méthode permet de publier ce que chaque invite permet maintenant lorsque la lumière change ou qu'une recharge
-- se termine.
function LightService:_refreshPrompts()
	local now = self.deps.clock()
	local cut = self.sabotage:cutWing()
	for _, entry in self.prompts do
		local available
		if entry.kind == "cut" then
			available = self.sabotage:canCut(entry.wing, now)
		elseif entry.kind == "restore" then
			available = cut ~= nil
			entry.prompt.ActionText = if cut
				then "Rétablir : " .. (HouseLayout.wings[cut] or cut)
				else "Rétablir le courant"
		else
			available = self.sabotage:canBurn(entry.room, now)
		end
		entry.prompt:SetAttribute(LA.PromptAvailable, available)
	end
end

-- Cette méthode permet d'exécuter l'action d'une invite lorsqu'un joueur la déclenche, après contrôle du rôle, de la
-- distance et de la vue sur la cible depuis le personnage : le client n'est jamais cru sur parole.
function LightService:_onPrompt(player, entry)
	if self.deps.roleOf(player) ~= entry.role then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local from = root.CFrame.Position
	local part = entry.prompt.Parent :: BasePart
	local target = part.CFrame.Position
	local reach = entry.prompt.MaxActivationDistance + DeathRules.DISTANCE_TOLERANCE
	if (target - from).Magnitude > reach then
		self.deps.warn(string.format("%s : %s refusé, trop loin", player.Name, entry.kind))
		return
	end
	if not self.deps.lineOfSight(player, from, target, part) then
		self.deps.warn(string.format("%s : %s refusé, cible hors de vue", player.Name, entry.kind))
		return
	end
	local ok, err
	if entry.kind == "cut" then
		ok, err = self:cutPower(entry.wing)
	elseif entry.kind == "restore" then
		ok, err = self:restorePower()
	else
		ok, err = self:burnRoom(entry.room)
	end
	if not ok then
		self.deps.warn(string.format("%s : %s refusé : %s", player.Name, entry.kind, tostring(err)))
	end
end

-- Debug ----------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'écouter la commande DebugLight d'un joueur lorsqu'il rejoint le serveur (Studio seulement).
function LightService:_watchPlayer(player)
	player.AttributeChanged:Connect(function(name)
		if name == LA.DebugLight then
			self:_onDebug(player)
		end
	end)
end

-- Cette méthode permet d'exécuter une commande DebugLight ("cut:<aile>", "restore", "burn:<pièce>", "reset")
-- lorsqu'elle est écrite sur un joueur ; l'attribut est remis à nil une fois lu.
function LightService:_onDebug(player)
	local value = player:GetAttribute(LA.DebugLight)
	if value == nil then
		return
	end
	player:SetAttribute(LA.DebugLight, nil)
	local command, arg = string.match(tostring(value), "^(%a+):?(.*)$")
	local ok, err = true, nil
	if command == "cut" then
		ok, err = self:cutPower(arg)
	elseif command == "restore" then
		ok, err = self:restorePower()
	elseif command == "burn" then
		ok, err = self:burnRoom(arg)
	elseif command == "reset" then
		self:reset()
	else
		ok, err = false, "commande inconnue"
	end
	if not ok then
		self.deps.warn(string.format("DebugLight %s refusé : %s", tostring(value), tostring(err)))
	end
end

return LightService
