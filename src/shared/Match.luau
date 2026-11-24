-- Règles pures d'une manche (docs/design.md, « Manche » et « Âmes ») : tirage des rôles, états d'un mortel et leurs
-- transitions, sablier, conditions de fin et résultat. Sans Instance Roblox (testable sous Lune) : identifiants =
-- UserId. Le serveur (MatchService) applique ces règles et les réplique par attributs.
local Match = {}
Match.__index = Match

Match.Phase = table.freeze({ Waiting = "Waiting", Running = "Running", Ended = "Ended" })
Match.Role = table.freeze({ Death = "Death", Mortal = "Mortal" })
Match.MortalState = table.freeze({ Alive = "Alive", Agony = "Agony", Dead = "Dead", Saved = "Saved" })
Match.SoulFate = table.freeze({ Reaped = "Reaped", Escaped = "Escaped" })
Match.EndReason = table.freeze({ AllResolved = "AllResolved", TimeUp = "TimeUp" })
-- Cause d'une mort, pour le bilan : fauché, accident sans agonie, agonie écoulée, fin du sablier, joueur parti.
Match.DeathCause = table.freeze({
	Reaped = "Reaped",
	Accident = "Accident",
	Agony = "Agony",
	TimeUp = "TimeUp",
	Left = "Left",
})

local State = Match.MortalState

-- Transitions permises : l'agonie se termine par une réanimation ou la mort ; mort et sauvé sont définitifs.
-- Un mortel en agonie ne peut pas être sauvé (il doit d'abord être ranimé).
local TRANSITIONS = {
	[State.Alive] = { [State.Agony] = true, [State.Dead] = true, [State.Saved] = true },
	[State.Agony] = { [State.Alive] = true, [State.Dead] = true },
	[State.Dead] = {},
	[State.Saved] = {},
}

export type Change = {
	userId: number,
	from: string,
	to: string,
	soul: string?,
	cause: string?,
}

export type MortalResult = {
	userId: number,
	state: string,
	soul: string?,
	cause: string?,
}

export type Result = {
	reason: string,
	deathId: number,
	mortals: { MortalResult },
	saved: number,
	reaped: number,
	escaped: number,
}

-- Cette méthode permet de savoir si un mortel peut passer de l'état `from` à l'état `to` lorsqu'un événement
-- (piège, réanimation, fauchage, fuite) veut changer son état.
function Match.canTransition(from: string, to: string): boolean
	local allowed = TRANSITIONS[from]
	return allowed ~= nil and allowed[to] == true
end

-- Cette méthode permet de savoir si un état de mortel est définitif lorsqu'on teste la fin de manche.
function Match.isResolved(state: string): boolean
	return state == State.Dead or state == State.Saved
end

-- Cette méthode permet de tirer la Mort parmi les joueurs lorsque la manche démarre ; `forced` impose des rôles
-- (mode test) et `pick(n)` renvoie un index de 1 à n (Random en jeu, déterministe en test). Renvoie nil sans candidat.
function Match.assignRoles(
	userIds: { number },
	forced: { [number]: string }?,
	pick: (number) -> number
): (number?, { number })
	local ids = table.clone(userIds)
	table.sort(ids)
	local roles = forced or {}
	local forcedDeath, candidates = {}, {}
	for _, id in ids do
		if roles[id] == Match.Role.Death then
			table.insert(forcedDeath, id)
		elseif roles[id] ~= Match.Role.Mortal then
			table.insert(candidates, id)
		end
	end
	local pool = if #forcedDeath > 0 then forcedDeath else candidates
	if #pool == 0 then
		return nil, {}
	end
	local deathId = pool[math.clamp(pick(#pool), 1, #pool)]
	local mortals = {}
	for _, id in ids do
		if id ~= deathId then
			table.insert(mortals, id)
		end
	end
	return deathId, mortals
end

-- Cette méthode permet de créer une manche en cours lorsque les rôles sont tirés : tous les mortels sont vivants et
-- le sablier part de `duration` secondes.
function Match.new(deathId: number, mortalIds: { number }, duration: number)
	assert(#mortalIds >= 1, "une manche demande au moins un mortel")
	assert(duration > 0, "la durée du sablier doit être positive")
	local mortals = {}
	for _, id in mortalIds do
		assert(id ~= deathId, "la Mort ne peut pas être aussi un mortel")
		mortals[id] = { state = State.Alive }
	end
	return setmetatable({
		phase = Match.Phase.Running,
		deathId = deathId,
		order = table.clone(mortalIds),
		mortals = mortals,
		duration = duration,
		timeLeft = duration,
		endReason = nil :: string?,
	}, Match)
end

-- Cette méthode permet de renvoyer le rôle d'un joueur lorsqu'on ne connaît que son UserId (nil hors manche).
function Match:roleOf(userId: number): string?
	if userId == self.deathId then
		return Match.Role.Death
	end
	return if self.mortals[userId] then Match.Role.Mortal else nil
end

-- Cette méthode permet de lire l'état d'un mortel lorsqu'un système (piège, HUD serveur) en dépend (nil sinon).
function Match:stateOf(userId: number): string?
	local mortal = self.mortals[userId]
	return mortal and mortal.state
end

-- Cette méthode permet d'appliquer un changement d'état déjà validé lorsqu'une transition ou la fin du sablier le
-- demande ; elle fixe le sort de l'âme pour une mort et renvoie le changement.
function Match:_apply(userId: number, to: string, reaped: boolean, cause: string?): Change
	local mortal = self.mortals[userId]
	local from = mortal.state
	mortal.state = to
	if to == State.Dead then
		mortal.soul = if reaped then Match.SoulFate.Reaped else Match.SoulFate.Escaped
		-- Un fauchage a toujours la cause Reaped, et seule une âme fauchée l'a ; sinon cause donnée, ou par défaut
		-- mort au bout de l'agonie ou accident direct depuis l'état vivant
		if reaped then
			mortal.cause = Match.DeathCause.Reaped
		elseif cause and cause ~= Match.DeathCause.Reaped then
			mortal.cause = cause
		else
			mortal.cause = if from == State.Agony then Match.DeathCause.Agony else Match.DeathCause.Accident
		end
	end
	return { userId = userId, from = from, to = to, soul = mortal.soul, cause = mortal.cause }
end

-- Cette méthode permet de valider puis d'appliquer un changement d'état lorsqu'une API publique est appelée ;
-- elle termine la manche quand le dernier mortel est mort ou sauvé. Renvoie le changement, ou nil et la raison.
function Match:_transition(userId: number, to: string, reaped: boolean, cause: string?): (Change?, string?)
	if self.phase ~= Match.Phase.Running then
		return nil, "la manche est terminée"
	end
	local mortal = self.mortals[userId]
	if not mortal then
		return nil, "ce joueur n'est pas un mortel de la manche"
	end
	if not Match.canTransition(mortal.state, to) then
		return nil, string.format("transition %s -> %s refusée", mortal.state, to)
	end
	if reaped and mortal.state ~= State.Agony then
		return nil, "seul un mortel en agonie peut être fauché"
	end
	local change = self:_apply(userId, to, reaped, cause)
	if self:allResolved() then
		self:_finish(Match.EndReason.AllResolved)
	end
	return change
end

-- Cette méthode permet de faire tomber un mortel vivant en agonie lorsqu'un accident le touche.
function Match:down(userId: number): (Change?, string?)
	return self:_transition(userId, State.Agony, false)
end

-- Cette méthode permet de ranimer un mortel en agonie lorsque le massage ou le défibrillateur réussit.
function Match:revive(userId: number): (Change?, string?)
	return self:_transition(userId, State.Alive, false)
end

-- Cette méthode permet de déclarer un mortel mort lorsque la Mort le fauche (`reaped`, depuis l'agonie seulement)
-- ou qu'il meurt sans être fauché (âme échappée) ; `cause` précise la mort pour le bilan (Match.DeathCause).
function Match:kill(userId: number, reaped: boolean?, cause: string?): (Change?, string?)
	return self:_transition(userId, State.Dead, reaped == true, cause)
end

-- Cette méthode permet de déclarer un mortel vivant sauvé lorsqu'il atteint la sortie, objectif rempli.
function Match:save(userId: number): (Change?, string?)
	return self:_transition(userId, State.Saved, false)
end

-- Cette méthode permet de savoir si tous les mortels sont morts ou sauvés lorsqu'on teste la fin de manche.
function Match:allResolved(): boolean
	for _, id in self.order do
		if not Match.isResolved(self.mortals[id].state) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de clore la manche lorsqu'une condition de fin est atteinte.
function Match:_finish(reason: string)
	self.phase = Match.Phase.Ended
	self.endReason = reason
end

-- Cette méthode permet de régler le temps restant du sablier lorsque le mode test l'impose (borné à [0, durée]).
function Match:setTimeLeft(seconds: number)
	if self.phase == Match.Phase.Running then
		self.timeLeft = math.clamp(seconds, 0, self.duration)
	end
end

-- Cette méthode permet de faire avancer le sablier de `dt` secondes lorsque le serveur avance d'une frame ; à zéro,
-- les mortels encore présents meurent (âme échappée) et la manche se termine. Renvoie les changements d'état.
function Match:advance(dt: number): { Change }
	if self.phase ~= Match.Phase.Running then
		return {}
	end
	self.timeLeft = math.max(0, self.timeLeft - math.max(0, dt))
	if self.timeLeft > 0 then
		return {}
	end
	local changes = {}
	for _, id in self.order do
		if not Match.isResolved(self.mortals[id].state) then
			table.insert(changes, self:_apply(id, State.Dead, false, Match.DeathCause.TimeUp))
		end
	end
	self:_finish(Match.EndReason.TimeUp)
	return changes
end

-- Cette méthode permet de construire le résultat de la manche lorsqu'elle est terminée : état final de chaque
-- mortel (sauvé ou mort, sort de l'âme) et décompte des sauvés, âmes fauchées et âmes échappées.
function Match:result(): Result
	local result = {
		reason = self.endReason,
		deathId = self.deathId,
		mortals = {},
		saved = 0,
		reaped = 0,
		escaped = 0,
	}
	for _, id in self.order do
		local mortal = self.mortals[id]
		table.insert(result.mortals, { userId = id, state = mortal.state, soul = mortal.soul, cause = mortal.cause })
		if mortal.state == State.Saved then
			result.saved += 1
		elseif mortal.soul == Match.SoulFate.Reaped then
			result.reaped += 1
		elseif mortal.soul == Match.SoulFate.Escaped then
			result.escaped += 1
		end
	end
	return result
end

return Match
