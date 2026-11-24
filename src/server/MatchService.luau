-- Service de manche (serveur) : tire les rôles, fait tourner le sablier, applique les règles de `Match` et réplique
-- l'état aux clients par attributs (`MatchAttributes`). Cycle : Waiting -> Running -> Ended -> Waiting.
--
-- API pour les étapes suivantes (pièges #5, agonie #6, fuite #7), via `MatchService.get()` :
--   :down(player)                   mortel vivant -> agonie
--   :revive(player)                 agonie -> vivant
--   :kill(player, reaped?, cause?)  -> mort ; reaped = fauché par la Mort (depuis l'agonie seulement)
--   :save(player)                   vivant -> sauvé
-- Chaque appel renvoie (true) ou (false, raison). Événements : PhaseChanged(phase), MatchStarted(info),
-- MortalStateChanged(change), MatchEnded(result). Lecture : getPhase, getRole, getMortalState, getTimeLeft.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Match = require(Shared.Match)
local MatchAttributes = require(Shared.MatchAttributes)
local Signal = require(Shared.Signal)

local Phase = Match.Phase
local A = MatchAttributes

local MatchService = {}
MatchService.__index = MatchService

-- Dépendances injectables (faux objets dans les tests Lune)
export type Deps = {
	players: any, -- service Players : GetPlayers, PlayerAdded, PlayerRemoving
	replicated: any, -- Instance qui porte les attributs de la manche (ReplicatedStorage)
	heartbeat: any, -- signal appelé à chaque frame avec dt (RunService.Heartbeat)
	isStudio: boolean, -- active le mode test et les attributs de debug
	pick: (number) -> number, -- tirage d'un index de 1 à n
	encode: (any) -> string, -- encodage JSON du résultat
	log: (string) -> (),
	warn: (string) -> (),
}

-- États de debug acceptés par DebugSetState
local DEBUG_STATES = {
	Agony = function(self, player)
		return self:down(player)
	end,
	Alive = function(self, player)
		return self:revive(player)
	end,
	Dead = function(self, player)
		return self:kill(player, false)
	end,
	Reaped = function(self, player)
		return self:kill(player, true)
	end,
	Saved = function(self, player)
		return self:save(player)
	end,
}

-- Cette méthode permet de construire les dépendances réelles (services Roblox) lorsque le service est créé en jeu.
local function defaultDeps(): Deps
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local HttpService = game:GetService("HttpService")
	local rng = Random.new()
	return {
		players = Players,
		replicated = ReplicatedStorage,
		heartbeat = RunService.Heartbeat,
		isStudio = RunService:IsStudio(),
		pick = function(n)
			return rng:NextInteger(1, n)
		end,
		encode = function(value)
			return HttpService:JSONEncode(value)
		end,
		log = function(message)
			print("[Manche] " .. message)
		end,
		warn = function(message)
			warn("[Manche] " .. message)
		end,
	}
end

-- Cette méthode permet de créer un service de manche à l'arrêt lorsqu'on veut l'instance du jeu (`get`) ou un
-- service isolé en test (`deps` simulées).
function MatchService.new(deps: Deps?)
	return setmetatable({
		deps = deps or defaultDeps(),
		started = false,
		phase = Phase.Waiting,
		phaseClock = 0, -- secondes passées dans la phase (attente avant démarrage auto, affichage du résultat)
		match = nil,
		participants = {}, -- UserId -> Player de la manche en cours
		names = {}, -- UserId -> nom, gardé pour le résultat si le joueur part
		timeScale = 1,
		shownTime = nil :: number?,
		PhaseChanged = Signal.new(),
		MatchStarted = Signal.new(),
		MortalStateChanged = Signal.new(),
		MatchEnded = Signal.new(),
	}, MatchService)
end

local instance = nil

-- Cette méthode permet de récupérer le service de manche du serveur lorsqu'un autre module (pièges, agonie, fuite)
-- doit agir sur la manche ; il est créé au premier appel avec les services Roblox.
function MatchService.get()
	if not instance then
		instance = MatchService.new()
	end
	return instance
end

-- Cette méthode permet de brancher le service sur les joueurs et sur la boucle de frames lorsque le serveur démarre
-- (une seule fois).
function MatchService:start()
	if self.started then
		return
	end
	self.started = true
	self:_setPhase(Phase.Waiting)
	local players = self.deps.players
	for _, player in players:GetPlayers() do
		self:_watchPlayer(player)
	end
	players.PlayerAdded:Connect(function(player)
		self:_watchPlayer(player)
	end)
	players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
	self.deps.heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

-- Lecture ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de lire la phase courante (Match.Phase) lorsqu'un système dépend du cycle de manche.
function MatchService:getPhase(): string
	return self.phase
end

-- Cette méthode permet de lire le rôle d'un joueur dans la manche en cours ou terminée lorsqu'un système doit
-- distinguer la Mort des mortels (nil hors manche).
function MatchService:getRole(player): string?
	return self.match and self.match:roleOf(player.UserId)
end

-- Cette méthode permet de lire l'état d'un mortel (Match.MortalState) lorsqu'un système en dépend (nil sinon).
function MatchService:getMortalState(player): string?
	return self.match and self.match:stateOf(player.UserId)
end

-- Cette méthode permet de lire le temps restant au sablier en secondes lorsqu'une manche est en cours (nil sinon).
function MatchService:getTimeLeft(): number?
	return if self.phase == Phase.Running then self.match.timeLeft else nil
end

-- API d'état des mortels ---------------------------------------------------------------------------------------

-- Cette méthode permet d'appliquer une règle de `Match` à un joueur lorsqu'une API publique est appelée, puis de
-- répliquer le changement ; renvoie (true) ou (false, raison).
function MatchService:_mutate(player, method: string, ...): (boolean, string?)
	if self.phase ~= Phase.Running then
		return false, "aucune manche en cours"
	end
	local change, err = self.match[method](self.match, player.UserId, ...)
	if not change then
		return false, err
	end
	self:_applyChanges({ change })
	return true
end

-- Cette méthode permet de faire tomber un mortel vivant en agonie lorsqu'un piège le touche.
function MatchService:down(player): (boolean, string?)
	return self:_mutate(player, "down")
end

-- Cette méthode permet de ranimer un mortel en agonie lorsque le massage ou le défibrillateur réussit.
function MatchService:revive(player): (boolean, string?)
	return self:_mutate(player, "revive")
end

-- Cette méthode permet de déclarer un mortel mort lorsque la Mort le fauche (`reaped`, depuis l'agonie) ou qu'il
-- meurt sans être fauché (âme échappée) ; `cause` : Match.DeathCause, pour le bilan.
function MatchService:kill(player, reaped: boolean?, cause: string?): (boolean, string?)
	return self:_mutate(player, "kill", reaped, cause)
end

-- Cette méthode permet de déclarer un mortel vivant sauvé lorsqu'il atteint la sortie, objectif rempli.
function MatchService:save(player): (boolean, string?)
	return self:_mutate(player, "save")
end

-- Cycle de manche ----------------------------------------------------------------------------------------------

-- Cette méthode permet de démarrer une manche avec les joueurs présents lorsque le serveur est complet ou que le
-- mode test le demande (`options.test`, Studio : 1 Mort et 1 à 4 mortels) ; renvoie (true) ou (false, raison).
function MatchService:startMatch(options: { test: boolean? }?): (boolean, string?)
	if self.phase == Phase.Running then
		return false, "une manche est déjà en cours"
	end
	local test = options ~= nil and options.test == true
	if test and not self.deps.isStudio then
		return false, "le mode test est réservé à Studio"
	end
	local players = self.deps.players:GetPlayers()
	local mortalCount = #players - 1
	local canStart = if test then GameConfig.canStartTestMatch else GameConfig.canStartMatch
	if not canStart(mortalCount, #players > 0) then
		return false,
			string.format(
				"%d joueur(s) : il faut 1 Mort et %s mortels",
				#players,
				if test
					then string.format("%d à %d", GameConfig.TEST_MIN_MORTALS, GameConfig.MORTALS_PER_MATCH)
					else tostring(GameConfig.MORTALS_PER_MATCH)
			)
	end

	local ids, byId, forced = {}, {}, {}
	for _, player in players do
		table.insert(ids, player.UserId)
		byId[player.UserId] = player
		if self.deps.isStudio then
			forced[player.UserId] = player:GetAttribute(A.DebugRole)
		end
	end
	local deathId, mortalIds = Match.assignRoles(ids, forced, self.deps.pick)
	if not deathId then
		return false, "aucun joueur ne peut être la Mort (tous forcés Mortal)"
	end

	self:_clearParticipants()
	self.match = Match.new(deathId, mortalIds, GameConfig.MATCH_DURATION)
	self.participants = byId
	self.names = {}
	for id, player in byId do
		self.names[id] = player.Name
		local role = self.match:roleOf(id)
		player:SetAttribute(A.Role, role)
		player:SetAttribute(A.MortalState, self.match:stateOf(id))
	end
	local replicated = self.deps.replicated
	replicated:SetAttribute(A.Result, nil)
	replicated:SetAttribute(A.EndReason, nil)
	replicated:SetAttribute(A.Duration, GameConfig.MATCH_DURATION)
	self.shownTime = nil
	self:_publishTime()
	self:_setPhase(Phase.Running)
	self.deps.log(
		string.format(
			"manche lancée%s : Mort = %s, %d mortel(s), sablier %d s",
			if test then " (test)" else "",
			self.names[deathId],
			#mortalIds,
			GameConfig.MATCH_DURATION
		)
	)
	self.MatchStarted:Fire({ deathId = deathId, mortalIds = table.clone(mortalIds), test = test })
	return true
end

-- Cette méthode permet d'annuler la manche en cours ou d'écourter le résultat lorsque le mode test le demande ou
-- que la Mort quitte le serveur : retour à l'attente sans résultat. Renvoie false si rien n'est en cours.
function MatchService:stopMatch(): boolean
	if self.phase == Phase.Waiting then
		return false
	end
	if self.phase == Phase.Running then
		self.deps.log("manche annulée")
	end
	self:_returnToWaiting()
	return true
end

-- Cette méthode permet d'avancer le cycle d'une frame lorsque le Heartbeat tombe : sablier (accéléré par le mode
-- test) en manche, minuterie du résultat, puis démarrage automatique quand le serveur est complet.
function MatchService:_step(dt: number)
	if self.phase == Phase.Running then
		local changes = self.match:advance(dt * self.timeScale)
		self:_publishTime()
		self:_applyChanges(changes)
	elseif self.phase == Phase.Ended then
		self.phaseClock += dt
		if self.phaseClock >= GameConfig.RESULT_DURATION then
			self:_returnToWaiting()
		end
	else
		local count = #self.deps.players:GetPlayers()
		if GameConfig.canStartMatch(count - 1, count > 0) then
			self.phaseClock += dt
			if self.phaseClock >= GameConfig.INTERMISSION_DURATION then
				local ok, err = self:startMatch()
				if not ok then
					self.phaseClock = 0
					self.deps.warn("démarrage automatique impossible : " .. tostring(err))
				end
			end
		else
			self.phaseClock = 0
		end
	end
end

-- Cette méthode permet de répliquer des changements d'état de mortels et de prévenir les abonnés lorsque les règles
-- en produisent ; elle clôt la manche si la dernière transition l'a terminée.
function MatchService:_applyChanges(changes: { Match.Change })
	for _, change in changes do
		local player = self.participants[change.userId]
		if player then
			player:SetAttribute(A.MortalState, change.to)
			player:SetAttribute(A.SoulFate, change.soul)
		end
		self.MortalStateChanged:Fire({
			player = player,
			userId = change.userId,
			from = change.from,
			to = change.to,
			soul = change.soul,
			cause = change.cause,
		})
	end
	if self.phase == Phase.Running and self.match.phase == Phase.Ended then
		self:_endMatch()
	end
end

-- Cette méthode permet de publier le résultat puis de passer en phase Ended lorsque la manche vient de se terminer ;
-- le résultat est écrit avant la phase pour qu'un client qui voit Ended le lise aussitôt.
function MatchService:_endMatch()
	local raw = self.match:result()
	local result = {
		reason = raw.reason,
		death = { userId = raw.deathId, name = self.names[raw.deathId] },
		mortals = {},
		saved = raw.saved,
		reaped = raw.reaped,
		escaped = raw.escaped,
	}
	for _, mortal in raw.mortals do
		table.insert(result.mortals, {
			userId = mortal.userId,
			name = self.names[mortal.userId],
			state = mortal.state,
			soul = mortal.soul,
			cause = mortal.cause,
		})
	end
	local replicated = self.deps.replicated
	self:_publishTime()
	replicated:SetAttribute(A.EndReason, result.reason)
	replicated:SetAttribute(A.Result, self.deps.encode(result))
	self:_setPhase(Phase.Ended)
	self.deps.log(
		string.format(
			"manche terminée (%s) : %d sauvé(s), %d âme(s) fauchée(s), %d âme(s) échappée(s)",
			result.reason,
			result.saved,
			result.reaped,
			result.escaped
		)
	)
	self.MatchEnded:Fire(result)
end

-- Cette méthode permet de revenir à l'attente lorsque l'affichage du résultat est écoulé ou que la manche est
-- annulée : attributs de joueurs et de sablier effacés, dernier résultat gardé jusqu'à la manche suivante.
function MatchService:_returnToWaiting()
	self:_clearParticipants()
	self.match = nil
	local replicated = self.deps.replicated
	replicated:SetAttribute(A.TimeLeft, nil)
	replicated:SetAttribute(A.Duration, nil)
	replicated:SetAttribute(A.EndReason, nil)
	self.shownTime = nil
	self:_setPhase(Phase.Waiting)
end

-- Cette méthode permet d'effacer les attributs de manche des joueurs lorsque la manche se termine ou recommence.
function MatchService:_clearParticipants()
	for _, player in self.participants do
		player:SetAttribute(A.Role, nil)
		player:SetAttribute(A.MortalState, nil)
		player:SetAttribute(A.SoulFate, nil)
	end
	self.participants = {}
end

-- Cette méthode permet de changer de phase, de la répliquer et de prévenir les abonnés lorsque le cycle avance.
function MatchService:_setPhase(phase: string)
	self.phase = phase
	self.phaseClock = 0
	self.deps.replicated:SetAttribute(A.Phase, phase)
	self.PhaseChanged:Fire(phase)
end

-- Cette méthode permet de répliquer le temps restant en secondes entières lorsque l'affichage change (une écriture
-- par seconde au plus, pas une par frame).
function MatchService:_publishTime()
	local shown = math.ceil(self.match.timeLeft)
	if shown ~= self.shownTime then
		self.shownTime = shown
		self.deps.replicated:SetAttribute(A.TimeLeft, shown)
	end
end

-- Joueurs et debug ---------------------------------------------------------------------------------------------

-- Cette méthode permet de traiter le départ d'un joueur lorsqu'une manche est en cours : la Mort partie annule la
-- manche, un mortel parti meurt sans être fauché (âme échappée, cause Left).
function MatchService:_onPlayerRemoving(player)
	if self.phase ~= Phase.Running then
		return
	end
	local id = player.UserId
	if id == self.match.deathId then
		self.deps.warn("la Mort a quitté la partie")
		self:stopMatch()
	elseif self.match:stateOf(id) and not Match.isResolved(self.match:stateOf(id)) then
		self.participants[id] = nil
		local change = self.match:kill(id, false, Match.DeathCause.Left)
		if change then
			self:_applyChanges({ change })
		end
	end
end

-- Cette méthode permet d'écouter les attributs de debug d'un joueur lorsqu'il rejoint le serveur, en Studio seulement.
function MatchService:_watchPlayer(player)
	if not self.deps.isStudio then
		return
	end
	player.AttributeChanged:Connect(function(name)
		self:_onDebugAttribute(player, name)
	end)
end

-- Cette méthode permet d'exécuter une commande de debug lorsqu'un attribut Debug* change sur un joueur ; les
-- commandes ponctuelles sont remises à nil une fois lues, DebugRole et DebugTimeScale restent en place.
function MatchService:_onDebugAttribute(player, name: string)
	local value = player:GetAttribute(name)
	if value == nil then
		return
	end
	if name == A.DebugStart then
		player:SetAttribute(name, nil)
		local ok, err = self:startMatch({ test = true })
		if not ok then
			self.deps.warn("DebugStartMatch refusé : " .. tostring(err))
		end
	elseif name == A.DebugStop then
		player:SetAttribute(name, nil)
		self:stopMatch()
	elseif name == A.DebugState then
		player:SetAttribute(name, nil)
		local apply = DEBUG_STATES[value]
		if not apply then
			self.deps.warn("DebugSetState inconnu : " .. tostring(value))
			return
		end
		local ok, err = apply(self, player)
		if not ok then
			self.deps.warn(string.format("DebugSetState %s refusé pour %s : %s", value, player.Name, tostring(err)))
		end
	elseif name == A.DebugTimeScale then
		if type(value) == "number" and value > 0 then
			self.timeScale = value
			self.deps.log(string.format("sablier x%g", value))
		else
			self.deps.warn("DebugTimeScale attend un nombre positif")
		end
	elseif name == A.DebugTimeLeft then
		player:SetAttribute(name, nil)
		if self.phase == Phase.Running and type(value) == "number" then
			self.match:setTimeLeft(value)
			self:_step(0)
		end
	end
end

return MatchService
