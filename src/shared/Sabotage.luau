-- Règles pures du sabotage de la lumière (docs/design.md « Sabotage de la lumière ») sur un modèle Illumination :
-- disjoncteur (une aile à la fois, rétablie par un mortel, recharge ensuite) et ampoules grillées (une pièce allumée,
-- recharge entre deux pièces). Le temps est passé par l'appelant (`now`, en secondes) : testable sans horloge.
local DeathRules = require(script.Parent.DeathRules)

local Sabotage = {}
Sabotage.__index = Sabotage

export type Timing = { breakerCooldown: number, burnCooldown: number }

-- Cette méthode permet de créer les règles de sabotage d'une maison lorsque le serveur démarre ou qu'un test les
-- isole ; `timing` remplace les recharges de DeathRules.
function Sabotage.new(illumination, timing: Timing?)
	return setmetatable({
		illumination = illumination,
		timing = timing or { breakerCooldown = DeathRules.BREAKER_COOLDOWN, burnCooldown = DeathRules.BURN_COOLDOWN },
		cut = nil :: string?,
		cutReadyAt = -math.huge,
		burnReadyAt = -math.huge,
	}, Sabotage)
end

-- Cette méthode permet de lire l'aile coupée au disjoncteur lorsque l'on affiche les actions possibles (nil sinon).
function Sabotage:cutWing(): string?
	return self.cut
end

-- Cette méthode permet de savoir si la Mort peut couper une aile lorsqu'elle est au disjoncteur ; renvoie aussi la
-- raison d'un refus.
function Sabotage:canCut(wingId: string, now: number): (boolean, string?)
	if not self.illumination:hasWing(wingId) then
		return false, "aile inconnue " .. tostring(wingId)
	elseif self.cut then
		return false, "une aile est déjà coupée"
	elseif now < self.cutReadyAt then
		return false, string.format("disjoncteur en recharge (%.0f s)", self.cutReadyAt - now)
	end
	return true
end

-- Cette méthode permet de couper le courant d'une aile lorsque la Mort actionne le disjoncteur ; renvoie (true) ou
-- (false, raison).
function Sabotage:cutPower(wingId: string, now: number): (boolean, string?)
	local ok, err = self:canCut(wingId, now)
	if not ok then
		return false, err
	end
	self.cut = wingId
	self.illumination:setWingPowered(wingId, false)
	return true
end

-- Cette méthode permet de rétablir l'aile coupée lorsqu'un mortel relève le disjoncteur ; la Mort doit ensuite
-- attendre la recharge pour couper à nouveau. Renvoie (true, nil, aile) ou (false, raison).
function Sabotage:restorePower(now: number): (boolean, string?, string?)
	local wingId = self.cut
	if not wingId then
		return false, "aucune aile n'est coupée"
	end
	self.cut = nil
	self.illumination:setWingPowered(wingId, true)
	self.cutReadyAt = now + self.timing.breakerCooldown
	return true, nil, wingId
end

-- Cette méthode permet de savoir si la Mort peut griller les ampoules d'une pièce lorsqu'elle vise une lampe : la pièce
-- doit être allumée (une ampoule sans courant ne grille pas) et la recharge écoulée.
function Sabotage:canBurn(roomId: string, now: number): (boolean, string?)
	if not self.illumination:getRoom(roomId) then
		return false, "pièce inconnue " .. tostring(roomId)
	elseif not self.illumination:isRoomLit(roomId) then
		return false, "aucune lampe allumée dans " .. roomId
	elseif now < self.burnReadyAt then
		return false, string.format("ampoules en recharge (%.0f s)", self.burnReadyAt - now)
	end
	return true
end

-- Cette méthode permet de griller les ampoules d'une pièce lorsque la Mort le décide ; renvoie (true, nil, lampes) ou
-- (false, raison).
function Sabotage:burn(roomId: string, now: number): (boolean, string?, { string }?)
	local ok, err = self:canBurn(roomId, now)
	if not ok then
		return false, err
	end
	self.burnReadyAt = now + self.timing.burnCooldown
	return true, nil, self.illumination:burnRoom(roomId)
end

-- Cette méthode permet de tout rallumer et d'effacer les recharges lorsqu'une manche commence ou se termine.
function Sabotage:reset()
	self.illumination:reset()
	self.cut = nil
	self.cutReadyAt = -math.huge
	self.burnReadyAt = -math.huge
end

return Sabotage
