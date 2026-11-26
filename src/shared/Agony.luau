-- Règles pures de l'agonie (#6, docs/design.md « Agonie, fauchage, réanimation ») : minuterie de l'agonie, massage
-- cardiaque en rythme (qualité d'une compression -> avancée), fauchage et lutte pour l'âme. Sans Instance Roblox
-- (testable sous Lune) : identifiants = UserId, horloge passée en argument. Le serveur (Server.AgonyService) applique
-- les issues à la manche (MatchService : kill, revive).
--
-- Massage : chaque compression après la première est notée selon l'écart avec la précédente (1 dans la cadence
-- MASSAGE_BPM_MIN..MAX, latence près, puis décroissance jusqu'à 0) ; une compression parfaite avance la réanimation de
-- PRESS_VALUE, soit MASSAGE_DURATION secondes à TARGET_BPM. Un mauvais rythme avance moins, donc plus lentement.
-- Lutte : la Mort finit son fauchage pendant un massage -> l'âme est à moitié sortie (`pull` = STRUGGLE_START) ; la
-- faux la tire de STRUGGLE_PULL par seconde, chaque compression la repousse de STRUGGLE_PUSH × qualité. À 1 l'âme est
-- fauchée, à 0 le mortel est ranimé : au rythme parfait le massage gagne, sous BREAK_EVEN_QUALITY il perd.
local GameConfig = require(script.Parent.GameConfig)

local Agony = {}
Agony.__index = Agony

Agony.Outcome = table.freeze({ Died = "Died", Reaped = "Reaped", Revived = "Revived" })

-- Fenêtre de la cadence (secondes entre deux compressions) élargie de cette marge : gigue du réseau, le serveur
-- note les compressions à leur réception
Agony.RHYTHM_TOLERANCE = 0.04
-- Au-delà de la fenêtre, la qualité baisse linéairement et s'annule à cet écart (secondes)
Agony.RHYTHM_FALLOFF = 0.2
Agony.TARGET_BPM = (GameConfig.MASSAGE_BPM_MIN + GameConfig.MASSAGE_BPM_MAX) / 2
Agony.PRESS_VALUE = 60 / (GameConfig.MASSAGE_DURATION * Agony.TARGET_BPM)
-- Sans compression pendant ce délai (secondes), le massage est abandonné et son avancée perdue
Agony.MASSAGE_IDLE = 1.5
Agony.STRUGGLE_START = 0.5
-- Sans massage, l'âme à moitié sortie finit de sortir dans le temps d'un fauchage
Agony.STRUGGLE_PULL = (1 - Agony.STRUGGLE_START) / GameConfig.REAP_DURATION
Agony.STRUGGLE_PUSH = 0.125
-- Qualité moyenne du rythme (à TARGET_BPM) en dessous de laquelle la faux gagne la lutte
Agony.BREAK_EVEN_QUALITY = Agony.STRUGGLE_PULL / (Agony.STRUGGLE_PUSH * Agony.TARGET_BPM / 60)
-- Cœur de l'agonisant (battements par minute) : de HEART_BPM_START à la chute à HEART_BPM_END à la fin de l'agonie
Agony.HEART_BPM_START = 90
Agony.HEART_BPM_END = 40

export type Dying = {
	timeLeft: number,
	progress: number, -- avancée de la réanimation, 0 à 1
	massager: number?, -- UserId du mortel qui masse
	since: number?, -- début du massage (horloge)
	lastPress: number?, -- dernière compression (horloge)
	pull: number?, -- lutte en cours : part de l'âme sortie, 0 à 1
	reaper: number?, -- UserId de la Mort qui fauche pendant la lutte
}

export type Resolution = { userId: number, outcome: string, massager: number? }

-- Cette méthode permet de noter une compression lorsque le massage en reçoit une : 1 si l'écart avec la précédente
-- (secondes) est dans la cadence attendue, latence près, puis de moins en moins jusqu'à 0.
function Agony.quality(interval: number): number
	local lo = 60 / GameConfig.MASSAGE_BPM_MAX - Agony.RHYTHM_TOLERANCE
	local hi = 60 / GameConfig.MASSAGE_BPM_MIN + Agony.RHYTHM_TOLERANCE
	if interval >= lo and interval <= hi then
		return 1
	end
	local gap = if interval < lo then lo - interval else interval - hi
	return math.max(0, 1 - gap / Agony.RHYTHM_FALLOFF)
end

-- Cette méthode permet de donner le rythme du cœur d'un agonisant lorsque son battement est joué : il ralentit à
-- mesure que l'agonie s'écoule.
function Agony.heartRate(timeLeft: number): number
	local t = 1 - math.clamp(timeLeft / GameConfig.AGONY_DURATION, 0, 1)
	return Agony.HEART_BPM_START + (Agony.HEART_BPM_END - Agony.HEART_BPM_START) * t
end

-- Cette méthode permet de créer le suivi des agonisants lorsque le serveur démarre (vide).
function Agony.new()
	return setmetatable({ dying = {} :: { [number]: Dying } }, Agony)
end

-- Cette méthode permet de commencer l'agonie d'un mortel lorsqu'un accident le met à terre (minuterie pleine).
function Agony:start(userId: number)
	self.dying[userId] = { timeLeft = GameConfig.AGONY_DURATION, progress = 0 }
end

-- Cette méthode permet d'oublier un agonisant lorsque son état change hors de ces règles (debug, départ, fin de
-- manche) ; renvoie son suivi (pour libérer son masseur), nil s'il n'agonisait pas.
function Agony:stop(userId: number): Dying?
	local dying = self.dying[userId]
	self.dying[userId] = nil
	return dying
end

-- Cette méthode permet de tout oublier lorsque la manche se termine.
function Agony:clear()
	table.clear(self.dying)
end

-- Cette méthode permet de lire le suivi d'un agonisant lorsque le serveur publie son état (nil sinon).
function Agony:get(userId: number): Dying?
	return self.dying[userId]
end

-- Cette méthode permet de trouver l'agonisant qu'un mortel masse lorsqu'il envoie une compression (nil sinon).
function Agony:targetOf(massagerId: number): number?
	for id, dying in self.dying do
		if dying.massager == massagerId then
			return id
		end
	end
	return nil
end

-- Cette méthode permet de commencer un massage lorsqu'un mortel vivant le lance sur un agonisant : un seul masseur
-- par agonisant, un seul massage par masseur. Renvoie (true) ou (false, raison).
function Agony:beginMassage(userId: number, massagerId: number, now: number): (boolean, string?)
	local dying = self.dying[userId]
	if not dying then
		return false, "ce mortel n'agonise pas"
	end
	if userId == massagerId or self.dying[massagerId] then
		return false, "un agonisant ne peut pas masser"
	end
	if dying.massager ~= nil then
		return false, if dying.massager == massagerId then "massage déjà en cours" else "quelqu'un le masse déjà"
	end
	if self:targetOf(massagerId) then
		return false, "massage déjà en cours"
	end
	dying.massager = massagerId
	dying.since = now
	dying.lastPress = nil
	return true
end

-- Cette méthode permet d'arrêter le massage d'un mortel lorsqu'il l'abandonne (ou ne peut plus masser) : l'avancée
-- est perdue, la lutte éventuelle continue sans lui. Renvoie l'agonisant qu'il massait, nil sinon.
function Agony:endMassage(massagerId: number): number?
	local id = self:targetOf(massagerId)
	if id then
		local dying = self.dying[id]
		dying.massager = nil
		dying.since = nil
		dying.lastPress = nil
		dying.progress = 0
	end
	return id
end

-- Cette méthode permet d'appliquer une compression lorsque le masseur appuie en rythme : avance la réanimation, ou
-- repousse l'âme pendant une lutte. Renvoie la qualité (0 à 1 ; 0 pour la première, sans écart), nil hors massage.
function Agony:press(massagerId: number, now: number): number?
	local id = self:targetOf(massagerId)
	if not id then
		return nil
	end
	local dying = self.dying[id]
	local quality = if dying.lastPress then Agony.quality(now - dying.lastPress) else 0
	dying.lastPress = now
	if dying.pull then
		dying.pull = math.max(0, dying.pull - quality * Agony.STRUGGLE_PUSH)
	else
		dying.progress = math.min(1, dying.progress + quality * Agony.PRESS_VALUE)
	end
	return quality
end

-- Cette méthode permet de finir un fauchage lorsque la Mort a tenu son maintien : âme récoltée tout de suite, ou
-- lutte si un massage est en cours. Renvoie Outcome.Reaped, "Struggle", ou nil et la raison.
function Agony:reap(userId: number, reaperId: number?): (string?, string?)
	local dying = self.dying[userId]
	if not dying then
		return nil, "ce mortel n'agonise pas"
	end
	if dying.pull then
		return nil, "lutte déjà en cours"
	end
	if dying.massager then
		dying.pull = Agony.STRUGGLE_START
		dying.reaper = reaperId
		return "Struggle"
	end
	self.dying[userId] = nil
	return Agony.Outcome.Reaped
end

-- Cette méthode permet d'avancer l'agonie de `dt` secondes lorsque le serveur avance : réanimation acquise, âme
-- tirée par la faux, massage abandonné, mort au bout de la minuterie. Renvoie les issues (agonisants retirés du suivi)
-- et les masseurs dont le massage s'est arrêté faute de compression.
function Agony:advance(dt: number, now: number): ({ Resolution }, { number })
	local ids = {}
	for id in self.dying do
		table.insert(ids, id)
	end
	table.sort(ids)
	local resolved, idle = {}, {}
	for _, id in ids do
		local dying = self.dying[id]
		local outcome = nil
		if dying.progress >= 1 or (dying.pull ~= nil and dying.pull <= 0) then
			outcome = Agony.Outcome.Revived
		else
			dying.timeLeft -= dt
			if dying.pull then
				dying.pull = math.min(1, dying.pull + Agony.STRUGGLE_PULL * dt)
			end
			if dying.pull and dying.pull >= 1 then
				outcome = Agony.Outcome.Reaped
			elseif dying.timeLeft <= 0 then
				outcome = Agony.Outcome.Died
			elseif dying.massager and now - (dying.lastPress or dying.since or now) > Agony.MASSAGE_IDLE then
				table.insert(idle, dying.massager)
				self:endMassage(dying.massager)
			end
		end
		if outcome then
			self.dying[id] = nil
			table.insert(resolved, { userId = id, outcome = outcome, massager = dying.massager })
		end
	end
	return resolved, idle
end

return Agony
