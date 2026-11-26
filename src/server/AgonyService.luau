-- Service de l'agonie (serveur, #6), abonné aux événements de Server.MatchService. Il applique les règles pures de
-- Shared.Agony à la manche :
-- - agonie : le mortel rampe (GameConfig.CRAWL_SPEED, pas de saut), son cœur bat de plus en plus lentement et s'entend
--   à distance ; au bout de GameConfig.AGONY_DURATION il meurt seul (âme échappée) ;
-- - « Faucher » (Mort, maintien GameConfig.REAP_DURATION) : âme récoltée (MatchService:kill reaped ; le souffle se
--   recharge dans Server.TrapService) ; pendant un massage, lutte pour l'âme, Mort immobile jusqu'à l'issue ;
-- - « Masser » (mortel vivant) : le masseur reste sur place et envoie ses compressions par l'événement
--   AgonyAttributes.Event (Client.AgonyClient), notées à leur réception ; réanimation -> MatchService:revive ;
-- - mortel ranimé : attribut RevealedUntil pendant GameConfig.REVEAL_DURATION (Client.AgonyClient le montre à la Mort).
-- Les invites sont posées sur la racine du personnage agonisant et filtrées par Client.LightPrompts ; le serveur
-- revérifie rôle, maintien, distance et vue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Agony = require(Shared.Agony)
local AgonyAttributes = require(Shared.AgonyAttributes)
local DeathRules = require(Shared.DeathRules)
local GameConfig = require(Shared.GameConfig)
local LightAttributes = require(Shared.LightAttributes)
local Match = require(Shared.Match)

local AA = AgonyAttributes
local LA = LightAttributes
local Role = DeathRules.Role
local Outcome = Agony.Outcome

-- Portée des invites (studs) : il faut être penché sur l'agonisant
local REAP_DISTANCE = 8
local MASSAGE_DISTANCE = 7
-- Masseur simulé par la commande de debug (aucun joueur n'a cet identifiant)
local BOT_ID = -1000
-- Battement de cœur : son fourni avec le client Roblox (bruit sourd, provisoire), entendu jusqu'à HEART_RANGE studs
local HEART = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1.4, speed = 0.45 }
local HEART_RANGE = 70

local AgonyService = {}
AgonyService.__index = AgonyService

export type Deps = {
	match: any, -- MatchService : MortalStateChanged, PhaseChanged, MatchStarted, getPhase, revive, kill
	death: any?, -- DeathController : setRooted(player, rooted)
	players: any, -- service Players : GetPlayers, GetPlayerByUserId, PlayerAdded
	isStudio: boolean,
	roleOf: (any) -> string?, -- rôle effectif (attribut LightRole)
	clock: () -> number,
	serverTime: () -> number, -- horloge partagée avec les clients (workspace:GetServerTimeNow)
	-- branche Triggered et PromptButtonHoldBegan d'une invite (joueur en argument)
	connectPrompt: (any, (any) -> (), (any) -> ()) -> (),
	lineOfSight: (Vector3, Vector3, Instance) -> boolean,
	send: (any, ...any) -> (), -- message de massage à un joueur (RemoteEvent:FireClient)
	onPress: ((any) -> ()) -> (), -- branche la réception des compressions
	notify: (any, string) -> (),
	play: (any) -> (), -- Sound:Play
	heartbeat: any?,
	log: (string) -> (),
	warn: (string) -> (),
}

-- Cette méthode permet de construire les dépendances réelles (services Roblox) lorsque le service est créé en jeu.
local function defaultDeps(): Deps
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LineOfSight = require(Shared.LineOfSight)
	local TrapAttributes = require(Shared.TrapAttributes)
	local event = Instance.new("RemoteEvent")
	event.Name = AA.Event
	event.Parent = ReplicatedStorage
	return {
		match = require(script.Parent.MatchService).get(),
		death = require(script.Parent.DeathController).get(),
		players = Players,
		isStudio = RunService:IsStudio(),
		-- Cette méthode permet de lire le rôle répliqué d'un joueur lorsqu'il agit sur un agonisant.
		roleOf = function(player)
			return player:GetAttribute(LA.LightRole)
		end,
		clock = os.clock,
		-- Cette méthode permet de lire l'horloge partagée avec les clients lorsqu'une échéance est publiée.
		serverTime = function()
			return workspace:GetServerTimeNow()
		end,
		-- Cette méthode permet de brancher une invite lorsqu'elle est créée : début du maintien et déclenchement.
		connectPrompt = function(prompt, onTriggered, onHoldBegan)
			prompt.PromptButtonHoldBegan:Connect(onHoldBegan)
			prompt.Triggered:Connect(onTriggered)
		end,
		lineOfSight = LineOfSight.clear,
		-- Cette méthode permet d'envoyer au masseur le début, la fin ou le résultat d'une compression.
		send = function(player, ...)
			event:FireClient(player, ...)
		end,
		-- Cette méthode permet de recevoir les compressions des clients (tout autre message est ignoré).
		onPress = function(handler)
			event.OnServerEvent:Connect(function(player, kind)
				if kind == "Press" then
					handler(player)
				end
			end)
		end,
		-- Cette méthode permet d'afficher un message bref à un joueur lorsque son action est refusée (bandeau des pièges).
		notify = function(player, text)
			local notice = ReplicatedStorage:FindFirstChild(TrapAttributes.NoticeEvent)
			if notice and notice:IsA("RemoteEvent") then
				notice:FireClient(player, text)
			end
		end,
		-- Cette méthode permet de jouer un battement de cœur lorsque son heure est venue.
		play = function(sound)
			sound:Play()
		end,
		heartbeat = RunService.Heartbeat,
		-- Cette méthode permet d'écrire un message de l'agonie dans la sortie lorsque son état change.
		log = function(message)
			print("[Agonie] " .. message)
		end,
		-- Cette méthode permet de signaler un refus ou une anomalie de l'agonie dans la sortie.
		warn = function(message)
			warn("[Agonie] " .. message)
		end,
	}
end

-- Cette méthode permet de créer le service à l'arrêt lorsqu'on veut l'instance du jeu (`get`) ou un service isolé en
-- test (`deps` simulées).
function AgonyService.new(deps: Deps?)
	return setmetatable({
		deps = deps or defaultDeps(),
		started = false,
		rules = Agony.new(),
		-- UserId agonisant -> { player, root, prompts = { reap, massage }, heart, nextBeat, reaper, pull }
		entries = {} :: { [number]: any },
		massagers = {} :: { [number]: any }, -- UserId du masseur -> Player
		reveals = {} :: { [any]: number }, -- Player ranimé -> fin de sa visibilité (horloge)
		holds = setmetatable({}, { __mode = "k" }) :: any, -- invite -> joueur -> début du maintien
		-- Joueur ralenti ou immobilisé -> vitesse, hauteur et puissance de saut d'origine
		saved = setmetatable({}, { __mode = "k" }) :: any,
		bot = nil :: { target: number, period: number, nextPress: number }?,
		watched = setmetatable({}, { __mode = "k" }) :: any, -- participants dont DebugAgony est écouté
	}, AgonyService)
end

local instance = nil

-- Cette méthode permet de récupérer le service de l'agonie du serveur lorsqu'un autre module en a besoin ; il est créé
-- au premier appel avec les services Roblox.
function AgonyService.get()
	if not instance then
		instance = AgonyService.new()
	end
	return instance
end

-- Cette méthode permet de brancher le service sur la manche, les compressions et les frames lorsque le serveur démarre
-- (une seule fois).
function AgonyService:start()
	if self.started then
		return
	end
	self.started = true
	local match = self.deps.match
	match.MortalStateChanged:Connect(function(change)
		self:_onStateChanged(change)
	end)
	match.PhaseChanged:Connect(function(phase)
		if phase ~= Match.Phase.Running then
			self:reset()
		end
	end)
	match.MatchStarted:Connect(function()
		self:reset()
	end)
	self.deps.onPress(function(player)
		self:press(player)
	end)
	local players = self.deps.players
	if self.deps.isStudio then
		for _, player in players:GetPlayers() do
			self:_watchPlayer(player)
		end
		players.PlayerAdded:Connect(function(player)
			self:_watchPlayer(player)
		end)
	end
	if self.deps.heartbeat then
		self.deps.heartbeat:Connect(function(dt)
			self:step(dt)
		end)
	end
end

-- Corps des personnages --------------------------------------------------------------------------------------------

-- Cette méthode permet de lire la racine et l'Humanoid d'un joueur lorsqu'on agit sur son personnage (nil sinon).
local function bodyOf(player): (BasePart?, Humanoid?)
	local character = player and player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

-- Cette méthode permet de ralentir (reptation) ou d'immobiliser (massage) un personnage lorsque l'agonie l'exige ;
-- réécrite à chaque frame (personnage réapparu), valeurs d'origine gardées une fois par joueur.
function AgonyService:_slow(player, speed: number)
	local _, humanoid = bodyOf(player)
	if not humanoid then
		return
	end
	if not self.saved[player] then
		self.saved[player] =
			{ walk = humanoid.WalkSpeed, jumpHeight = humanoid.JumpHeight, jumpPower = humanoid.JumpPower }
	end
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
	if humanoid.JumpHeight ~= 0 or humanoid.JumpPower ~= 0 then
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
end

-- Cette méthode permet de rendre à un personnage sa vitesse et son saut lorsque l'agonie ou le massage se termine.
function AgonyService:_free(player)
	local _, humanoid = bodyOf(player)
	local saved = self.saved[player]
	self.saved[player] = nil
	if not saved or not humanoid then
		return
	end
	humanoid.WalkSpeed = saved.walk
	humanoid.JumpHeight = saved.jumpHeight
	humanoid.JumpPower = saved.jumpPower
end

-- État de la manche --------------------------------------------------------------------------------------------------

-- Cette méthode permet de réagir à un changement d'état d'un mortel lorsque la manche le publie : un masseur qui n'est
-- plus vivant arrête, un mortel qui tombe commence son agonie, un agonisant qui en sort est nettoyé (ranimé : révélé).
function AgonyService:_onStateChanged(change)
	local id = change.userId
	if change.to ~= Match.MortalState.Alive and self.massagers[id] then
		self:_releaseMassager(id)
		self.rules:endMassage(id)
	end
	-- Un ranimé qui retombe ou meurt n'est plus montré à la Mort
	if change.from == Match.MortalState.Alive and change.player and self.reveals[change.player] then
		self.reveals[change.player] = nil
		change.player:SetAttribute(AA.RevealedUntil, nil)
	end
	if change.from == Match.MortalState.Agony then
		self:_endAgony(id)
		if change.to == Match.MortalState.Alive and change.player then
			self:_reveal(change.player)
		end
	end
	if change.to == Match.MortalState.Agony and change.player then
		self:_startAgony(change.player, id)
	end
end

-- Cette méthode permet de commencer l'agonie d'un mortel lorsqu'il tombe : minuterie, invites, cœur, reptation.
function AgonyService:_startAgony(player, id: number)
	self.rules:start(id)
	self.entries[id] = { player = player, prompts = nil, root = nil, nextBeat = self.deps.clock() }
	player:SetAttribute(AA.AgonyEnd, self.deps.serverTime() + GameConfig.AGONY_DURATION)
	self:_attach(self.entries[id])
	self:_slow(player, GameConfig.CRAWL_SPEED)
	-- Faux joueur de debug (#12) : absent de PlayerAdded, sa commande DebugAgony s'écoute sur son mannequin
	if self.deps.isStudio and player.IsBot then
		self:_watchPlayer(player)
	end
	self.deps.log(string.format("%s en agonie (%d s)", player.Name, GameConfig.AGONY_DURATION))
end

-- Cette méthode permet de nettoyer un agonisant lorsque son agonie se termine (ranimé, mort, fin de manche) : invites
-- et cœur retirés, masseur et Mort libérés, reptation levée.
function AgonyService:_endAgony(id: number)
	local dying = self.rules:stop(id)
	if dying and dying.massager then
		self:_releaseMassager(dying.massager)
	end
	if self.bot and self.bot.target == id then
		self.bot = nil
	end
	local entry = self.entries[id]
	if not entry then
		return
	end
	self.entries[id] = nil
	self:_detach(entry)
	if entry.reaper and not self:_reaperOf(entry.reaper) then
		self:_root(entry.reaper, false)
	end
	entry.player:SetAttribute(AA.AgonyEnd, nil)
	entry.player:SetAttribute(AA.SoulPull, nil)
	self:_free(entry.player)
end

-- Cette méthode permet de montrer un mortel ranimé à la Mort lorsqu'il revient à la vie (GameConfig.REVEAL_DURATION).
function AgonyService:_reveal(player)
	self.reveals[player] = self.deps.clock() + GameConfig.REVEAL_DURATION
	player:SetAttribute(AA.RevealedUntil, self.deps.serverTime() + GameConfig.REVEAL_DURATION)
	self.deps.log(player.Name .. " ranimé : visible par la Mort")
end

-- Cette méthode permet de tout arrêter lorsqu'une manche commence ou se termine.
function AgonyService:reset()
	local ids = {}
	for id in self.entries do
		table.insert(ids, id)
	end
	for _, id in ids do
		self:_endAgony(id)
	end
	for id in table.clone(self.massagers) do
		self:_releaseMassager(id)
	end
	for player in self.reveals do
		player:SetAttribute(AA.RevealedUntil, nil)
	end
	table.clear(self.reveals)
	self.rules:clear()
	self.bot = nil
end

-- Invites ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de créer une invite sur la racine d'un agonisant lorsqu'il tombe ou que son personnage
-- réapparaît ; filtrée par chaque client (rôle, disponibilité, vue, regard).
function AgonyService:_makePrompt(root: BasePart, role: string, props: { [string]: any }, onTriggered)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = AA.PromptName
	prompt.Enabled = false
	prompt.RequiresLineOfSight = false
	for property, value in props do
		(prompt :: any)[property] = value
	end
	prompt:SetAttribute(LA.PromptRole, role)
	prompt:SetAttribute(LA.PromptAvailable, true)
	prompt:SetAttribute(LA.PromptSight, true)
	prompt:AddTag(LA.PromptTag)
	prompt.Parent = root
	local holds = setmetatable({}, { __mode = "k" })
	self.holds[prompt] = holds
	self.deps.connectPrompt(prompt, function(player)
		local began = holds[player]
		holds[player] = nil
		onTriggered(player, if began then self.deps.clock() - began else nil)
	end, function(player)
		holds[player] = self.deps.clock()
	end)
	return prompt
end

-- Cette méthode permet de poser invites et cœur sur le personnage actuel d'un agonisant lorsqu'il tombe ou réapparaît
-- (rien tant qu'il n'a pas de personnage).
function AgonyService:_attach(entry)
	local root = bodyOf(entry.player)
	if root == entry.root then
		return
	end
	self:_detach(entry)
	if not root then
		return
	end
	local id = entry.player.UserId
	-- Un faux joueur de debug (#12) n'a pas de DisplayName
	local name = entry.player.DisplayName or entry.player.Name
	entry.root = root
	entry.prompts = {
		reap = self:_makePrompt(root, Role.Death, {
			ActionText = "Faucher",
			ObjectText = name,
			KeyboardKeyCode = Enum.KeyCode.F,
			GamepadKeyCode = Enum.KeyCode.ButtonY,
			HoldDuration = GameConfig.REAP_DURATION,
			MaxActivationDistance = REAP_DISTANCE,
		}, function(player, elapsed)
			self:_onReap(player, id, elapsed)
		end),
		massage = self:_makePrompt(root, Role.Mortal, {
			ActionText = "Masser",
			ObjectText = name,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			HoldDuration = 0,
			MaxActivationDistance = MASSAGE_DISTANCE,
		}, function(player)
			self:_onMassage(player, id)
		end),
	}
	local heart = Instance.new("Sound")
	heart.Name = "AgonyHeart"
	heart.SoundId = HEART.id
	heart.Volume = HEART.volume
	heart.PlaybackSpeed = HEART.speed
	heart.RollOffMode = Enum.RollOffMode.InverseTapered
	heart.RollOffMinDistance = 8
	heart.RollOffMaxDistance = HEART_RANGE
	heart.Parent = root
	entry.heart = heart
end

-- Cette méthode permet de retirer invites et cœur d'un agonisant lorsque son agonie se termine ou que son personnage
-- change.
function AgonyService:_detach(entry)
	if entry.prompts then
		for _, prompt in entry.prompts do
			self.holds[prompt] = nil
			prompt:Destroy()
		end
	end
	if entry.heart then
		entry.heart:Destroy()
	end
	entry.prompts = nil
	entry.heart = nil
	entry.root = nil
end

-- Cette méthode permet de savoir si un joueur est assez près d'un agonisant, sans mur entre eux, lorsqu'il déclenche
-- une invite (le client n'est jamais cru sur parole).
function AgonyService:_canReach(player, entry, distance: number): boolean
	local from = bodyOf(player)
	local to = entry.root
	if not from or not to or not to.Parent then
		return false
	end
	if (to.CFrame.Position - from.CFrame.Position).Magnitude > distance + DeathRules.DISTANCE_TOLERANCE then
		self.deps.warn(player.Name .. " : action refusée, trop loin")
		return false
	end
	if not self.deps.lineOfSight(from.CFrame.Position, to.CFrame.Position, to) then
		self.deps.warn(player.Name .. " : action refusée, cible hors de vue")
		return false
	end
	return true
end

-- Cette méthode permet à la Mort de finir son fauchage lorsqu'elle a tenu l'invite : âme récoltée, ou lutte si un
-- massage est en cours.
function AgonyService:_onReap(player, id: number, elapsed: number?)
	local entry = self.entries[id]
	if not entry or self.deps.roleOf(player) ~= Role.Death then
		return
	end
	if not DeathRules.isHoldValid(elapsed, GameConfig.REAP_DURATION) then
		self.deps.warn(player.Name .. " : fauchage refusé, maintien invalide")
		return
	end
	if not self:_canReach(player, entry, REAP_DISTANCE) then
		return
	end
	self:reap(id, player)
end

-- Cette méthode permet d'appliquer un fauchage fini lorsque la Mort (ou la commande de debug, sans joueur) l'a mené
-- à terme ; renvoie l'issue de Shared.Agony (Reaped, "Struggle") ou nil et la raison.
function AgonyService:reap(id: number, reaper): (string?, string?)
	local entry = self.entries[id]
	if reaper and self:_reaperOf(reaper) then
		self.deps.notify(reaper, "ta faux tire déjà une âme")
		return nil, "lutte déjà en cours"
	end
	local outcome, err = self.rules:reap(id, reaper and reaper.UserId)
	if outcome == Outcome.Reaped then
		self.deps.log(entry.player.Name .. " : âme fauchée")
		self:_resolve(id, outcome)
	elseif outcome then
		entry.reaper = reaper
		if reaper then
			self:_root(reaper, true)
		end
		self.deps.log(entry.player.Name .. " : lutte pour l'âme")
	elseif reaper then
		self.deps.notify(reaper, tostring(err))
	end
	return outcome, err
end

-- Cette méthode permet de trouver l'agonisant dont la Mort tire l'âme lorsqu'une lutte commence ou finit (nil sinon).
function AgonyService:_reaperOf(reaper): number?
	for id, entry in self.entries do
		if entry.reaper == reaper then
			return id
		end
	end
	return nil
end

-- Cette méthode permet à un mortel de commencer un massage lorsqu'il déclenche « Masser » près d'un agonisant : il
-- reste sur place et son client passe en mode compressions.
function AgonyService:_onMassage(player, id: number)
	local entry = self.entries[id]
	if not entry or self.deps.roleOf(player) ~= Role.Mortal then
		return
	end
	if not self:_canReach(player, entry, MASSAGE_DISTANCE) then
		return
	end
	local ok, err = self.rules:beginMassage(id, player.UserId, self.deps.clock())
	if not ok then
		self.deps.notify(player, tostring(err))
		return
	end
	self.massagers[player.UserId] = player
	self:_slow(player, 0)
	self.deps.send(player, "Massage", id)
	self.deps.log(string.format("%s masse %s", player.Name, entry.player.Name))
end

-- Cette méthode permet d'appliquer une compression lorsqu'un masseur appuie : notée à sa réception, résultat renvoyé
-- au masseur (qualité, avancée, lutte). Ignorée hors massage.
function AgonyService:press(player)
	local quality = self.rules:press(player.UserId, self.deps.clock())
	if quality == nil then
		return
	end
	local target = self.rules:targetOf(player.UserId)
	local dying = target and self.rules:get(target)
	if dying then
		self.deps.send(player, "Beat", quality, dying.progress, dying.pull)
	end
end

-- Cette méthode permet de libérer un masseur lorsque son massage s'arrête (abandon, issue, accident) : il peut de
-- nouveau marcher et son client quitte le mode compressions.
function AgonyService:_releaseMassager(massagerId: number)
	local player = self.massagers[massagerId]
	self.massagers[massagerId] = nil
	if player then
		self:_free(player)
		self.deps.send(player, "Massage", nil)
	end
end

-- Cette méthode permet d'immobiliser la Mort ou de la libérer lorsque sa faux tire une âme pendant la lutte.
function AgonyService:_root(player, rooted: boolean)
	if self.deps.death then
		self.deps.death:setRooted(player, rooted)
	end
end

-- Cette méthode permet d'appliquer une issue de l'agonie à la manche lorsqu'elle tombe : ranimé, âme fauchée, ou mort
-- seul (âme échappée). Le nettoyage suit l'événement MortalStateChanged ; il est forcé si la manche refuse.
function AgonyService:_resolve(id: number, outcome: string)
	local entry = self.entries[id]
	if not entry then
		return
	end
	local match = self.deps.match
	local ok, err
	if outcome == Outcome.Revived then
		ok, err = match:revive(entry.player)
	elseif outcome == Outcome.Reaped then
		ok, err = match:kill(entry.player, true)
	else
		ok, err = match:kill(entry.player, false, Match.DeathCause.Agony)
	end
	if not ok then
		self.deps.warn(string.format("%s : issue %s refusée (%s)", entry.player.Name, outcome, tostring(err)))
	end
	if self.entries[id] then
		self:_endAgony(id)
	end
end

-- Boucle -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'avancer l'agonie d'une frame lorsque le Heartbeat tombe : masseur simulé, issues des règles,
-- massages abandonnés, puis pour chaque agonisant invites, reptation, cœur et lutte publiés ; fin des révélations.
function AgonyService:step(dt: number)
	local now = self.deps.clock()
	local bot = self.bot
	if bot and now >= bot.nextPress then
		bot.nextPress = math.max(bot.nextPress + bot.period, now)
		local quality = self.rules:press(BOT_ID, now)
		if quality == nil then
			self.bot = nil
		else
			self.deps.log(string.format("compression simulée : qualité %.2f", quality))
		end
	end
	local resolved, idle = self.rules:advance(dt, now)
	for _, massagerId in idle do
		self:_releaseMassager(massagerId)
	end
	for _, resolution in resolved do
		if resolution.massager then
			self:_releaseMassager(resolution.massager)
		end
		self:_resolve(resolution.userId, resolution.outcome)
	end
	for id, entry in self.entries do
		local dying = self.rules:get(id)
		if dying then
			self:_stepEntry(entry, dying, now)
		end
	end
	for massagerId, player in self.massagers do
		if self.rules:targetOf(massagerId) then
			self:_slow(player, 0)
		end
	end
	for player, untilTime in self.reveals do
		if now >= untilTime then
			self.reveals[player] = nil
			player:SetAttribute(AA.RevealedUntil, nil)
		end
	end
end

-- Cette méthode permet de tenir à jour un agonisant lorsque une frame passe : invites sur son personnage actuel et
-- leur disponibilité, reptation, battement du cœur, part de l'âme sortie pendant une lutte.
function AgonyService:_stepEntry(entry, dying: Agony.Dying, now: number)
	self:_attach(entry)
	-- Massé ou pendant la lutte : il ne rampe plus (le massage ne se fait pas à distance)
	local held = dying.massager ~= nil or dying.pull ~= nil
	self:_slow(entry.player, if held then 0 else GameConfig.CRAWL_SPEED)
	if entry.prompts then
		entry.prompts.reap:SetAttribute(LA.PromptAvailable, dying.pull == nil)
		entry.prompts.massage:SetAttribute(LA.PromptAvailable, dying.massager == nil)
	end
	if entry.heart and now >= entry.nextBeat then
		self.deps.play(entry.heart)
		entry.nextBeat = now + 60 / Agony.heartRate(dying.timeLeft)
	end
	local pull = if dying.pull then math.floor(dying.pull * 20 + 0.5) / 20 else nil
	if pull ~= entry.pull then
		entry.pull = pull
		entry.player:SetAttribute(AA.SoulPull, pull)
	end
end

-- Debug --------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'écouter la commande DebugAgony d'un joueur lorsqu'il rejoint le serveur, ou d'un faux joueur
-- lorsqu'il tombe en agonie (Studio seulement, une fois par participant).
function AgonyService:_watchPlayer(player)
	if self.watched[player] then
		return
	end
	self.watched[player] = true
	player.AttributeChanged:Connect(function(name)
		if name == AA.DebugAgony then
			self:_onDebug(player)
		end
	end)
end

-- Cette méthode permet d'exécuter une commande DebugAgony lorsqu'elle est écrite sur un agonisant (voir
-- Shared.AgonyAttributes) ; l'attribut est remis à nil une fois lu.
function AgonyService:_onDebug(player)
	local value = player:GetAttribute(AA.DebugAgony)
	if value == nil then
		return
	end
	player:SetAttribute(AA.DebugAgony, nil)
	local id = player.UserId
	local command, arg = string.match(tostring(value), "^(%a+):?(.*)$")
	local ok, err = true, nil
	if command == "reap" then
		local outcome
		outcome, err = self:reap(id, nil)
		ok = outcome ~= nil
	elseif command == "massage" then
		local bpm = tonumber(arg)
		if not bpm or bpm <= 0 then
			ok, err = false, "massage:<bpm> attend une cadence positive"
		else
			self.rules:endMassage(BOT_ID)
			ok, err = self.rules:beginMassage(id, BOT_ID, self.deps.clock())
			if ok then
				self.bot = { target = id, period = 60 / bpm, nextPress = self.deps.clock() }
			end
		end
	elseif command == "stop" then
		self.bot = nil
		self.rules:endMassage(BOT_ID)
	else
		ok, err = false, "commande inconnue"
	end
	if not ok then
		self.deps.warn(string.format("DebugAgony %s refusé : %s", tostring(value), tostring(err)))
	end
end

return AgonyService
